import type { ExecutionsPort, ExecutionStepRow, RecordExecutionStepInput } from "@core/executions/executions.port";

export class RecordExecutionStepUseCase {
  constructor(private readonly port: ExecutionsPort) {};

  public execute(tenantId: string, input: RecordExecutionStepInput): Promise<ExecutionStepRow> {
    return this.port.recordStep(tenantId, input);
  };
};
