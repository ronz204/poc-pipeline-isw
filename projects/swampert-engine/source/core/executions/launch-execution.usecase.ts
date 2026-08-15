import type { ExecutionsPort, ExecutionRow, LaunchExecutionInput } from "@core/executions/executions.port";

export class LaunchExecutionUseCase {
  constructor(private readonly port: ExecutionsPort) {};

  public execute(tenantId: string, input: LaunchExecutionInput): Promise<ExecutionRow> {
    return this.port.launch(tenantId, input);
  };
};
