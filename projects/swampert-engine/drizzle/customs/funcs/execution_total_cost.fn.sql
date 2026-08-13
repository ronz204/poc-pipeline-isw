-- Function: trace.fn_execution_total_cost
-- Kind: scalar (numeric)
-- Used by: trace.sp_record_execution_step
--
-- What it does: adds up every estimated_cost recorded for an execution so far, and
-- returns 0 (not NULL) for an execution with no cost rows yet, so callers can add to
-- the result without a COALESCE of their own.
--
-- Why it exists: it's the running total the budget check compares against
-- core.fn_tenant_budget_threshold before a new step is written. Soft-deleted cost
-- rows are excluded — a cost that was retracted shouldn't keep consuming budget.
--
-- Example: SELECT trace.fn_execution_total_cost('018f0000-0000-7000-8000-000000000003');

CREATE OR REPLACE FUNCTION trace.fn_execution_total_cost(p_execution_id uuid)
RETURNS numeric AS $$
DECLARE
  v_total numeric;
BEGIN
  SELECT coalesce(sum(tc.estimated_cost), 0) INTO v_total
  FROM trace.token_costs tc
  WHERE tc.execution_id = p_execution_id
    AND tc.deleted_at IS NULL;

  RETURN v_total;
END;
$$ LANGUAGE plpgsql STABLE;
