-- Function: core.fn_tenant_budget_threshold
-- Kind: scalar (numeric)
-- Used by: trace.sp_record_execution_step
--
-- What it does: returns the maximum accumulated token cost a single execution is
-- allowed to reach, derived from the tenant's plan (auth.tenant_plan).
--
-- Why it exists: the data model is reused from Project I without structural changes,
-- so there is no budget_limit column to read — the ceiling has to come from
-- somewhere, and the plan is the only pricing-related attribute a tenant carries.
-- Keeping it in a function means changing the policy is a CREATE OR REPLACE, not a
-- migration.
--
-- The three amounts below are illustrative placeholders, not calibrated business
-- figures (deltas/process.spec.md § Risks says the same) — don't present them in the
-- oral review as if they came from a real pricing decision.
--
-- Example: SELECT core.fn_tenant_budget_threshold('018f0000-0000-7000-8000-0000000000ff');

CREATE OR REPLACE FUNCTION core.fn_tenant_budget_threshold(p_tenant_id uuid)
RETURNS numeric AS $$
DECLARE
  v_plan auth.tenant_plan;
  v_threshold numeric;
BEGIN
  SELECT t.plan INTO v_plan
  FROM auth.tenants t
  WHERE t.id = p_tenant_id
    AND t.deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tenant % does not exist or is deleted', p_tenant_id
      USING ERRCODE = 'no_data_found';
  END IF;

  v_threshold := CASE v_plan
    WHEN 'basic'      THEN 50.00
    WHEN 'pro'        THEN 250.00
    WHEN 'enterprise' THEN 1000.00
  END;

  IF v_threshold IS NULL THEN
    RAISE EXCEPTION 'No budget threshold defined for plan %', v_plan
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN v_threshold;
END;
$$ LANGUAGE plpgsql STABLE;
