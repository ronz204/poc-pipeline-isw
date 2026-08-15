import type { ExecutionsPort, ExecutionRow, CompleteExecutionInput } from "@core/executions/executions.port";

export class CompleteExecutionUseCase {
  constructor(private readonly port: ExecutionsPort) {};

  public execute(tenantId: string, input: CompleteExecutionInput): Promise<ExecutionRow> {
    return this.port.complete(tenantId, input);
  };
};
