-- Function: core.fn_agent_belongs_to_swarm
-- Kind: scalar (boolean)
-- Used by: trace.sp_record_execution_step
--
-- What it does: answers whether a given agent is on a given swarm's roster, i.e.
-- whether the (swarm_id, agent_id) pair exists in core.swarm_agents.
--
-- Why it exists: an execution step is work done by an agent inside a swarm's run —
-- recording a step for an agent that was never assigned to that swarm would produce
-- trace data that contradicts the roster. core.swarm_agents carries no tenant_id and
-- no RLS of its own (trg_swarm_agents_validate_tenant guards it instead), so this
-- lookup is also what keeps a step from silently crossing tenants.
--
-- Example: SELECT core.fn_agent_belongs_to_swarm(
--   '018f0000-0000-7000-8000-00000000000a', '018f0000-0000-7000-8000-000000000001');

CREATE OR REPLACE FUNCTION core.fn_agent_belongs_to_swarm(p_agent_id uuid, p_swarm_id uuid)
RETURNS boolean AS $$
DECLARE
  v_belongs boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM core.swarm_agents sa
    WHERE sa.agent_id = p_agent_id
      AND sa.swarm_id = p_swarm_id
  ) INTO v_belongs;

  RETURN v_belongs;
END;
$$ LANGUAGE plpgsql STABLE;
