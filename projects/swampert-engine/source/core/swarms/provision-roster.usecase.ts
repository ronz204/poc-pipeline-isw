import type { SwarmsPort, ProvisionRosterInput, ProvisionRosterResult } from "@core/swarms/swarms.port";

export class ProvisionRosterUseCase {
  constructor(private readonly port: SwarmsPort) {};

  public execute(tenantId: string, input: ProvisionRosterInput): Promise<ProvisionRosterResult> {
    return this.port.provisionRoster(tenantId, input);
  };
};
