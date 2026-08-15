export interface ProvisionRosterInput {
  swarmId: string;
  agentIds: string[];
}

export interface ProvisionRosterResult {
  swarmId: string;
  rosterSize: number;
}

export interface ArchiveStaleSwarmsInput {
  inactiveSince: Date;
}

export interface ArchiveStaleSwarmsResult {
  archivedCount: number;
}

export interface SwarmsPort {
  provisionRoster(tenantId: string, input: ProvisionRosterInput): Promise<ProvisionRosterResult>;
  archiveStale(tenantId: string, input: ArchiveStaleSwarmsInput): Promise<ArchiveStaleSwarmsResult>;
}
