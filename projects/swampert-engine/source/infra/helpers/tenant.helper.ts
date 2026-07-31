import { sql } from "drizzle-orm";
import type { Drizzler } from "@database/drizzler.client";

export type TenantTx = Parameters<Parameters<Drizzler["transaction"]>[0]>[0];

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
};
