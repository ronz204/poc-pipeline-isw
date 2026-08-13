-- Function: core.fn_tenant_active_agents
-- Kind: table-returning — TABLE(agent_id uuid, name text, role text)
-- Used by: core.sp_provision_swarm_roster
--
-- What it does: lists every agent a tenant can actually put to work — active and not
-- soft-deleted — ordered by name.
--
-- Why it exists: it's the eligibility list the roster procedure filters against, and
-- the same list a UI would show when picking agents for a swarm. Encapsulating the
-- three conditions (tenant, active, not deleted) keeps "usable agent" from being
-- re-spelled slightly differently at each call site.
--
-- Example: SELECT * FROM core.fn_tenant_active_agents('018f0000-0000-7000-8000-0000000000ff');

CREATE OR REPLACE FUNCTION core.fn_tenant_active_agents(p_tenant_id uuid)
RETURNS TABLE (
  agent_id uuid,
  name text,
  role text
) AS $$
BEGIN
  RETURN QUERY
  SELECT a.id, a.name, a.role
  FROM core.agents a
  WHERE a.tenant_id = p_tenant_id
    AND a.active
    AND a.deleted_at IS NULL
  ORDER BY a.name;
END;
$$ LANGUAGE plpgsql STABLE;
