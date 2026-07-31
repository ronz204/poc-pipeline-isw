-- Trigger (validación): rechaza asignar un swarm y un agente de tenants distintos.
-- swarm_agents no tiene tenant_id propio (junction table pura, sin RLS) — este trigger
-- es lo que cierra ese hueco de aislamiento multi-tenant a nivel de integridad.
CREATE OR REPLACE FUNCTION core.fn_swarm_agents_validate_tenant()
RETURNS trigger AS $$
DECLARE
  v_swarm_tenant uuid;
  v_agent_tenant uuid;
BEGIN
  SELECT tenant_id INTO v_swarm_tenant FROM core.swarms WHERE id = NEW.swarm_id;
  SELECT tenant_id INTO v_agent_tenant FROM core.agents WHERE id = NEW.agent_id;

  IF v_swarm_tenant IS DISTINCT FROM v_agent_tenant THEN
    RAISE EXCEPTION 'El swarm % (tenant %) y el agente % (tenant %) pertenecen a empresas distintas',
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
