import type { SwarmsPort, ArchiveStaleSwarmsInput, ArchiveStaleSwarmsResult } from "@core/swarms/swarms.port";

export class ArchiveStaleSwarmsUseCase {
  constructor(private readonly port: SwarmsPort) {};

  public execute(tenantId: string, input: ArchiveStaleSwarmsInput): Promise<ArchiveStaleSwarmsResult> {
    return this.port.archiveStale(tenantId, input);
  };
};
