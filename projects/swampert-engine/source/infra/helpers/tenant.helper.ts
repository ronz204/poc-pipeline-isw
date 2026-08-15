import { sql } from "drizzle-orm";
import type { Drizzler } from "@database/drizzler.client";

export type TenantTx = Parameters<Parameters<Drizzler["transaction"]>[0]>[0];

// drizzle-orm's postgres-js driver needs the full client instance it was built from
// (it reads client.options internally) — a reserved connection off the pool doesn't
// carry that, so runDetached() hands work() the raw postgres-js connection instead
// of a fresh Drizzler wrapping it (verified: drizzle({ client: reserved }) throws
// "client.options.parsers" is undefined at runtime, not just a type mismatch).
export type ReservedConnection = Awaited<ReturnType<Drizzler["$client"]["reserve"]>>;

export class TenantScope {
  constructor(private readonly db: Drizzler) {};

  public async run<T>(tenantId: string, work: (tx: TenantTx) => Promise<T>) {
    return this.db.transaction(async (tx) => {
      await tx.execute(sql`SELECT set_config('app.current_tenant_id', ${tenantId}, true)`);
      return work(tx);
    });
  };

  public async setActor(tx: TenantTx, userId: string) {
    await tx.execute(sql`SELECT set_config('app.current_user_id', ${userId}, true)`);
  };

  // For the routines that TenantScope.run() cannot host: a procedure that commits
  // internally (core.sp_archive_stale_swarms) needs the tenant setting to survive
  // those commits, which set_config(..., true) (transaction-local) does not — see
  // deltas/restful.spec.md § Technical context. This reserves a connection off the
  // pool, sets app.current_tenant_id at session level, runs work against it, then
  // explicitly clears the setting before releasing the connection back to the pool.
  // Skipping that reset would leak this tenant's context into whichever unrelated
  // request the pool hands the connection to next.
  public async runDetached<T>(tenantId: string, work: (sql: ReservedConnection) => Promise<T>) {
    const reserved = await this.db.$client.reserve();

    try {
      await reserved`SELECT set_config('app.current_tenant_id', ${tenantId}, false)`;
      return await work(reserved);
    } finally {
      await reserved`SELECT set_config('app.current_tenant_id', '', false)`;
      reserved.release();
    }
  };
};
