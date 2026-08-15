import { sql, eq, count } from "drizzle-orm";
import { swarms, swarmAgents } from "@elements/core.element";

import type { Drizzler } from "@database/drizzler.client";
import type {
  SwarmsPort, ProvisionRosterInput, ProvisionRosterResult,
  ArchiveStaleSwarmsInput, ArchiveStaleSwarmsResult,
} from "@core/swarms/swarms.port";

import { TenantScope, type ReservedConnection } from "@helpers/tenant.helper";
import { sqlArray } from "@helpers/sql-array.helper";

export class SwarmsRepo implements SwarmsPort {
  constructor(
    private readonly db: Drizzler,
    private readonly tenantScope: TenantScope,
  ) {};

  // core.sp_provision_swarm_roster's only feedback on the added/skipped split is a
  // RAISE NOTICE, which postgres-js has no per-call hook to retrieve reliably (see
  // deltas/restful.spec.md § Risks #2) — the honest signal this repo can give back
  // is the roster's actual size after the call, not a fabricated added/skipped count.
  public async provisionRoster(tenantId: string, input: ProvisionRosterInput): Promise<ProvisionRosterResult> {
    return this.tenantScope.run(tenantId, async (tx) => {
      await tx.execute(sql`CALL core.sp_provision_swarm_roster(
        ${input.swarmId}::uuid, ${sqlArray(input.agentIds)}::uuid[])`);

      const [row] = await tx.select({ rosterSize: count() })
        .from(swarmAgents)
        .where(eq(swarmAgents.swarmId, input.swarmId));

      return { swarmId: input.swarmId, rosterSize: row?.rosterSize ?? 0 };
    });
  };

  // core.sp_archive_stale_swarms commits per swarm internally — it cannot run inside
  // TenantScope.run()'s transaction (deltas/restful.spec.md § Technical context, §
  // Risks #1), hence runDetached: a reserved, session-scoped connection instead of
  // the pooled transactional one. Before/after counts on the same reserved connection
  // are what let this repo report how many swarms the call actually archived, since
  // the procedure's own count lives only in a RAISE NOTICE this driver can't retrieve.
  public async archiveStale(tenantId: string, input: ArchiveStaleSwarmsInput): Promise<ArchiveStaleSwarmsResult> {
    return this.tenantScope.runDetached(tenantId, async (reserved) => {
      const before = await this.countArchived(reserved);

      await reserved`CALL core.sp_archive_stale_swarms(${input.inactiveSince.toISOString()}::timestamptz)`;

      const after = await this.countArchived(reserved);
      return { archivedCount: after - before };
    });
  };

  // A reserved connection is raw postgres-js, not a Drizzler — see
  // @helpers/tenant.helper's ReservedConnection note — so this one query goes
  // through postgres-js's own tagged template instead of the query builder.
  private async countArchived(reserved: ReservedConnection): Promise<number> {
    const [row] = await reserved<{ total: number }[]>
      `SELECT count(*)::int AS total FROM core.swarms WHERE status = 'archived'`;

    return row?.total ?? 0;
  };
};
