import { sql } from "drizzle-orm";
import type { Drizzler } from "@database/drizzler.client";

const MONTHS_OF_HISTORY = 12;

// reports.sp_refresh_reports loops over every tenant inside its own body
// (deltas/reports.spec.md § Technical context) — it's called once per period here,
// never per-tenant, and never through TenantScope.run(): the procedure needs no
// caller-side app.current_tenant_id at all, same as source/infra/repos/reports.repo.ts.
export class ReportsSeeder {
  constructor(private readonly db: Drizzler) {};

  public async seedHistory({ months = MONTHS_OF_HISTORY }: { months?: number } = {}) {
    const now = new Date();

    for (let i = 0; i < months; i++) {
      const period = new Date(now.getFullYear(), now.getMonth() - i, 1)
        .toISOString().slice(0, 10);

      await this.db.execute(sql`CALL reports.sp_refresh_reports(${period}::date)`);
    };
  };
};
