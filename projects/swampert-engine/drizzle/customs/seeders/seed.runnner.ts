import { drizzler } from "@database/drizzler.client";
import { TenantScope } from "@helpers/tenant.helper";
import { AuthSeeder } from "@customs/seeders/auth.seeder";
import { CoreSeeder } from "@customs/seeders/core.seeder";
import { TraceSeeder } from "@customs/seeders/trace.seeder";
import { ReportsSeeder } from "@customs/seeders/reports.seeder";

const SEED_NUMBER = Number(process.env.SEED_NUMBER ?? 2026);
const SEED_TENANT_COUNT = Number(process.env.SEED_TENANT_COUNT ?? 6);

const authSeeder = new AuthSeeder(drizzler);
const coreSeeder = new CoreSeeder();
const traceSeeder = new TraceSeeder();
const reportsSeeder = new ReportsSeeder(drizzler);
const tenantScope = new TenantScope(drizzler);

console.log(`Sembrando ${SEED_TENANT_COUNT} tenants (seed=${SEED_NUMBER})...`);

const tenants = await authSeeder.seedTenants({ count: SEED_TENANT_COUNT, seed: SEED_NUMBER });

for (const tenant of tenants) {
  await tenantScope.run(tenant.id, async (tx) => {
    const tenantUsers = await authSeeder.seedUsers(tx, tenant, { seed: SEED_NUMBER });
    const actor = tenantUsers.find((user) => user.role === "admin") ?? tenantUsers[0]!;
    await tenantScope.setActor(tx, actor.id);

    await coreSeeder.seedAll(tx, tenant, { seed: SEED_NUMBER });
    await traceSeeder.seedAll(tx, tenant, { seed: SEED_NUMBER });
  });
}

console.log(`Listo: ${tenants.length} tenants sembrados.`);

console.log("Recalculando reportes de los últimos 12 meses...");
await reportsSeeder.seedHistory();
console.log("Listo: reports.* poblado para los últimos 12 meses.");

await drizzler.$client.end();
