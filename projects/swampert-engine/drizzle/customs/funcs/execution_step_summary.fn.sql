-- Function: trace.fn_execution_step_summary
-- Kind: table-returning — TABLE(step_number integer, agent_id uuid, tools_used text[], occurred_at timestamptz)
-- Used by: core.sp_complete_execution
--
-- What it does: returns the recorded steps of an execution in the order they
-- happened, without the reasoning payload — the readable trace of a run, not a dump
-- of every column.
--
-- Why it exists: two different needs read the same rows. sp_complete_execution uses
-- an empty result as its "this execution did no work" signal (an execution with zero
-- steps can't be marked completed), and the same query is what a run detail view
-- would show. Soft-deleted steps are excluded, so a retracted step neither shows up
-- in the trace nor keeps an empty execution completable.
--
-- Example: SELECT * FROM trace.fn_execution_step_summary('018f0000-0000-7000-8000-000000000003');

CREATE OR REPLACE FUNCTION trace.fn_execution_step_summary(p_execution_id uuid)
RETURNS TABLE (
  step_number integer,
  agent_id uuid,
  tools_used text[],
  occurred_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT s.step_number, s.agent_id, s.tools_used, s.occurred_at
  FROM trace.execution_steps s
  WHERE s.execution_id = p_execution_id
    AND s.deleted_at IS NULL
  ORDER BY s.step_number;
END;
$$ LANGUAGE plpgsql STABLE;
