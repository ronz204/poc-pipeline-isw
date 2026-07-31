import { drizzler } from "@database/drizzler.client";
import { TenantScope } from "@helpers/tenant.helper";
import { AuthSeeder } from "@customs/seeders/auth.seeder";
import { CoreSeeder } from "@customs/seeders/core.seeder";
import { TraceSeeder } from "@customs/seeders/trace.seeder";

const SEED_NUMBER = Number(process.env.SEED_NUMBER ?? 2026);
const SEED_TENANT_COUNT = Number(process.env.SEED_TENANT_COUNT ?? 6);

const authSeeder = new AuthSeeder(drizzler);
const coreSeeder = new CoreSeeder();
const traceSeeder = new TraceSeeder();
const tenantScope = new TenantScope(drizzler);

console.log(`Sembrando ${SEED_TENANT_COUNT} tenants (seed=${SEED_NUMBER})...`);

const tenants = await authSeeder.seedTenants({ count: SEED_TENANT_COUNT, seed: SEED_NUMBER });

for (const tenant of tenants) {
  await tenantScope.run(tenant.id, async (tx) => {
    await authSeeder.seedUsers(tx, tenant, { seed: SEED_NUMBER });
    await coreSeeder.seedAll(tx, tenant, { seed: SEED_NUMBER });
    await traceSeeder.seedAll(tx, tenant, { seed: SEED_NUMBER });
  });
}

console.log(`Listo: ${tenants.length} tenants sembrados.`);

await drizzler.$client.end();
