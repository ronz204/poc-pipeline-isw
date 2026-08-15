import { sql, eq, desc } from "drizzle-orm";
import { executions } from "@elements/core.element";
import { executionSteps } from "@elements/trace.element";

import type { Drizzler } from "@database/drizzler.client";
import type {
  ExecutionsPort, ExecutionRow, ExecutionStepRow,
  LaunchExecutionInput, CompleteExecutionInput, RecordExecutionStepInput,
} from "@core/executions/executions.port";

import { TenantScope } from "@helpers/tenant.helper";
import { sqlArray } from "@helpers/sql-array.helper";

// The 3 procedures backing this repo return nothing (they're PROCEDUREs, not
// FUNCTIONs — no OUT/INOUT params) and generate their own row ids internally
// (extensions.gen_random_uuid()), so every method here re-SELECTs the row the
// CALL just produced, inside the same transaction/tenant scope — deltas/restful.spec.md
// never promised a returning CALL, only that the endpoint surfaces the resulting row.
export class ExecutionsRepo implements ExecutionsPort {
  constructor(
    private readonly db: Drizzler,
    private readonly tenantScope: TenantScope,
  ) {};

  public async launch(tenantId: string, input: LaunchExecutionInput): Promise<ExecutionRow> {
    return this.tenantScope.run(tenantId, async (tx) => {
      await tx.execute(sql`CALL core.sp_launch_execution(
        ${input.taskId}::uuid, ${input.maxAttempts ?? 3}::integer)`);

      const [row] = await tx.select().from(executions)
        .where(eq(executions.taskId, input.taskId))
        .orderBy(desc(executions.attemptNumber))
        .limit(1);

      return row as ExecutionRow;
    });
  };

  public async complete(tenantId: string, input: CompleteExecutionInput): Promise<ExecutionRow> {
    return this.tenantScope.run(tenantId, async (tx) => {
      await tx.execute(sql`CALL core.sp_complete_execution(
        ${input.executionId}::uuid,
        ${input.status}::core.execution_status,
        ${input.maxAttempts ?? 3}::integer)`);

      const [row] = await tx.select().from(executions)
        .where(eq(executions.id, input.executionId))
        .limit(1);

      return row as ExecutionRow;
    });
  };

  public async recordStep(tenantId: string, input: RecordExecutionStepInput): Promise<ExecutionStepRow> {
    return this.tenantScope.run(tenantId, async (tx) => {
      await tx.execute(sql`CALL trace.sp_record_execution_step(
        ${input.executionId}::uuid,
        ${input.agentId}::uuid,
        ${JSON.stringify(input.reasoning ?? {})}::jsonb,
        ${sqlArray(input.toolsUsed ?? [])}::text[],
        ${input.inputTokens}::integer,
        ${input.outputTokens}::integer,
        ${input.costPer1kInput}::numeric,
        ${input.costPer1kOutput}::numeric)`);

      const [row] = await tx.select().from(executionSteps)
        .where(eq(executionSteps.executionId, input.executionId))
        .orderBy(desc(executionSteps.stepNumber))
        .limit(1);

      return row as ExecutionStepRow;
    });
  };
};
