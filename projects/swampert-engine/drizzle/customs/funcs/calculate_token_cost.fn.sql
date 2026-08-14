-- Function: trace.fn_calculate_token_cost
-- Kind: scalar (numeric)
-- Used by: trace.sp_record_execution_step
--
-- What it does: pure arithmetic, no table access — turns a token count and a
-- per-1000-token price into the cost of one step:
--   (input_tokens / 1000) * cost_per_1k_input + (output_tokens / 1000) * cost_per_1k_output
-- rounded to 4 decimals, which is the scale trace.token_costs.estimated_cost stores
-- (numeric(10, 4)) — rounding here instead of letting the INSERT truncate keeps the
-- value the procedure checked against the budget identical to the value it writes.
--
-- Why it exists: it's the one place the pricing formula lives. Inlining it in the
-- procedure would mean any future change (a different unit than 1000 tokens, a
-- minimum charge) has to be found and edited wherever a cost is computed.
--
-- Negative inputs are rejected rather than silently producing a negative cost — a
-- negative cost would quietly lower the execution total and defeat the budget check
-- in sp_record_execution_step.
--
-- Example: SELECT trace.fn_calculate_token_cost(480, 210, 0.0010, 0.0030);  -- 0.1110

CREATE OR REPLACE FUNCTION trace.fn_calculate_token_cost(
  p_input_tokens integer,
  p_output_tokens integer,
  p_cost_per_1k_input numeric,
  p_cost_per_1k_output numeric
)
RETURNS numeric AS $$
BEGIN
  IF p_input_tokens IS NULL OR p_output_tokens IS NULL
     OR p_cost_per_1k_input IS NULL OR p_cost_per_1k_output IS NULL THEN
    RAISE EXCEPTION 'fn_calculate_token_cost does not accept NULL arguments'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  IF p_input_tokens < 0 OR p_output_tokens < 0
     OR p_cost_per_1k_input < 0 OR p_cost_per_1k_output < 0 THEN
    RAISE EXCEPTION 'Token counts and prices must be non-negative (got %, %, %, %)',
      p_input_tokens, p_output_tokens, p_cost_per_1k_input, p_cost_per_1k_output
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN round(
    (p_input_tokens / 1000.0) * p_cost_per_1k_input
    + (p_output_tokens / 1000.0) * p_cost_per_1k_output,
    4
  );
END;
$$ LANGUAGE plpgsql IMMUTABLE;
