export type ExecutionStatus = "pending" | "running" | "completed" | "failed";

export interface ExecutionRow {
  id: string;
  tenantId: string;
  taskId: string;
  attemptNumber: number;
  status: ExecutionStatus;
  startedAt: Date;
  finishedAt: Date | null;
}

export interface ExecutionStepRow {
  id: string;
  executionId: string;
  agentId: string;
  stepNumber: number;
  toolsUsed: string[];
  occurredAt: Date;
}

export interface LaunchExecutionInput {
  taskId: string;
  maxAttempts?: number;
}

export interface CompleteExecutionInput {
  executionId: string;
  status: "completed" | "failed";
  maxAttempts?: number;
}

export interface RecordExecutionStepInput {
  executionId: string;
  agentId: string;
  reasoning?: Record<string, unknown>;
  toolsUsed?: string[];
  inputTokens: number;
  outputTokens: number;
  costPer1kInput: number;
  costPer1kOutput: number;
}

export interface ExecutionsPort {
  launch(tenantId: string, input: LaunchExecutionInput): Promise<ExecutionRow>;
  complete(tenantId: string, input: CompleteExecutionInput): Promise<ExecutionRow>;
  recordStep(tenantId: string, input: RecordExecutionStepInput): Promise<ExecutionStepRow>;
}
