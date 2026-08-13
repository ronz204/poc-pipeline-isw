-- Function: core.fn_is_swarm_active
-- Kind: scalar (boolean)
-- Used by: core.sp_launch_execution, core.sp_provision_swarm_roster
--
-- What it does: answers whether a swarm is operational right now — status 'active'
-- and not soft-deleted.
--
-- Why it exists: "is this swarm usable?" is the same two-column check in every
-- procedure that touches a swarm. Keeping it in one function means a future change
-- to what "active" means (e.g. treating 'paused' differently) is a one-file change
-- instead of an edit in every caller.
--
-- Example: SELECT core.fn_is_swarm_active('018f0000-0000-7000-8000-000000000001');

CREATE OR REPLACE FUNCTION core.fn_is_swarm_active(p_swarm_id uuid)
RETURNS boolean AS $$
DECLARE
  v_active boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM core.swarms s
    WHERE s.id = p_swarm_id
      AND s.status = 'active'
      AND s.deleted_at IS NULL
  ) INTO v_active;

  RETURN v_active;
END;
$$ LANGUAGE plpgsql STABLE;
