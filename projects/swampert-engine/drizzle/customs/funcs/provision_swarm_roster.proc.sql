-- Procedure: core.sp_provision_swarm_roster
-- Tables written: core.swarm_agents | Control flow: FOR
-- Transaction: none of its own — a single table is written, so the surrounding
-- transaction is already the whole unit of work (approach.md §1 asks for explicit
-- transactions when a procedure modifies more than one table).
--
-- What it does: assigns a batch of agents to a swarm in one call. Every id that isn't
-- an active agent of the swarm's own tenant is skipped, as is every id already on the
-- roster, so the same call can be repeated to top up a roster without failing on what
-- is already there.
--
-- Why it exists: staffing a swarm is one decision but N inserts, each of which has to
-- be checked against the tenant's agent list first. Done by hand it's either N
-- verified statements or one unverified bulk insert.
--
-- Parameters:
--   p_swarm_id   — swarm to staff. Must exist, be active and not soft-deleted.
--   p_agent_ids  — agent ids to add. Must contain at least one element; individual
--                  ids that don't qualify are skipped, not rejected.
--
-- Note: skipping instead of raising is deliberate and it is the one place in this
-- slice where invalid input doesn't fail the call — a batch that is half-valid still
-- staffs what it can. The NOTICE reports the split; nothing else signals it (see
-- deltas/process.spec.md § Risks).
--
-- Calling contract: same as the other SECURITY DEFINER procedures in this slice —
-- runs as sampler under FORCE ROW LEVEL SECURITY, so app.current_tenant_id must be
-- set (SET LOCAL is fine) before the call (see core.sp_launch_execution's header).
--
-- Example:
--   SELECT set_config('app.current_tenant_id', '018f0000-0000-7000-8000-0000000000ff', false);
--   CALL core.sp_provision_swarm_roster(
--     '018f0000-0000-7000-8000-000000000001',
--     ARRAY['018f0000-0000-7000-8000-00000000000a',
--           '018f0000-0000-7000-8000-00000000000b']::uuid[]);

CREATE OR REPLACE PROCEDURE core.sp_provision_swarm_roster(
  p_swarm_id uuid,
  p_agent_ids uuid[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tenant_id uuid;
  v_swarm_deleted_at timestamptz;
  v_agent_id uuid;
  v_added integer := 0;
  v_skipped integer := 0;
BEGIN
  IF p_swarm_id IS NULL THEN
    RAISE EXCEPTION 'p_swarm_id is required'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  IF p_agent_ids IS NULL OR array_length(p_agent_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'p_agent_ids must contain at least one agent id'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT s.tenant_id, s.deleted_at
    INTO v_tenant_id, v_swarm_deleted_at
  FROM core.swarms s
  WHERE s.id = p_swarm_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Swarm % does not exist', p_swarm_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_swarm_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot staff swarm % (deleted)', p_swarm_id
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT core.fn_is_swarm_active(p_swarm_id) THEN
    RAISE EXCEPTION 'Cannot staff swarm %: it is not active', p_swarm_id
      USING ERRCODE = 'check_violation';
  END IF;

  FOR v_agent_id IN SELECT unnest(p_agent_ids)
  LOOP
    -- Not an active agent of this swarm's tenant. trg_swarm_agents_validate_tenant
    -- would reject a cross-tenant pair anyway; filtering here is what turns that
    -- rejection into a skip, so one foreign id doesn't abort the whole batch.
    IF NOT EXISTS (
      SELECT 1
      FROM core.fn_tenant_active_agents(v_tenant_id) a
      WHERE a.agent_id = v_agent_id
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM core.swarm_agents sa
      WHERE sa.swarm_id = p_swarm_id
        AND sa.agent_id = v_agent_id
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    INSERT INTO core.swarm_agents (swarm_id, agent_id, added_at)
    VALUES (p_swarm_id, v_agent_id, now());

    v_added := v_added + 1;
  END LOOP;

  RAISE NOTICE 'Swarm %: % agent(s) added, % skipped', p_swarm_id, v_added, v_skipped;
END;
$$;
