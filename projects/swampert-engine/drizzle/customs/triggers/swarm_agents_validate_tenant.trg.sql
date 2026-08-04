-- Trigger: swarm_agents_validate_tenant
-- Table: core.swarm_agents | Event: BEFORE INSERT | Role: validation
--
-- What it does: looks up the tenant_id of the referenced swarm and the referenced
-- agent, and rejects the insert if they differ.
--
-- Why it exists: swarm_agents is a pure junction table — it carries no tenant_id of
-- its own and has no RLS policy. Without this trigger, nothing at the database level
-- would stop a swarm from one tenant being linked to an agent from another, which
-- would be a real cross-tenant data leak. This trigger closes that isolation gap at
-- the integrity level, since RLS can't cover a table that has no tenant_id column to
-- filter on.

CREATE OR REPLACE FUNCTION core.fn_swarm_agents_validate_tenant()
RETURNS trigger AS $$
DECLARE
  v_swarm_tenant uuid;
  v_agent_tenant uuid;
BEGIN
  SELECT tenant_id INTO v_swarm_tenant FROM core.swarms WHERE id = NEW.swarm_id;
  SELECT tenant_id INTO v_agent_tenant FROM core.agents WHERE id = NEW.agent_id;

  IF v_swarm_tenant IS DISTINCT FROM v_agent_tenant THEN
    RAISE EXCEPTION 'Swarm % (tenant %) and agent % (tenant %) belong to different tenants',
      NEW.swarm_id, v_swarm_tenant, NEW.agent_id, v_agent_tenant
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_swarm_agents_validate_tenant
  BEFORE INSERT ON core.swarm_agents
  FOR EACH ROW
  EXECUTE FUNCTION core.fn_swarm_agents_validate_tenant();
