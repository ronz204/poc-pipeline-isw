import { seed } from "drizzle-seed";
import { hashSeed } from "@helpers/random.helper";
import { tenants, users } from "@elements/auth.element";
import { PasswordHelper } from "@helpers/password.helper";

import type { TenantTx } from "@helpers/tenant.helper";
import type { Drizzler } from "@database/drizzler.client";

const SLUG_POOL = [
  "nimbus-swarm", "vertex-agents", "quanta-labs", "helix-orchestrator",
  "driftwood-ai", "cascade-agents", "iron-hive", "solace-systems",
  "brightloop-ai", "fathom-agents", "gridline-ai", "lucent-swarm",
  "moonforge-ai", "outpost-agents", "pinewave-ai", "redshift-agents",
  "silverline-ai", "tidalwave-agents", "ultraviolet-ai", "wayfinder-agents",
];

export class AuthSeeder {
  constructor(private readonly db: Drizzler) {}

  async seedTenants({ count, seed: seedNumber }: { count: number; seed: number }) {
    await seed(this.db, { tenants }, { count, seed: seedNumber }).refine((f) => ({
      tenants: {
        columns: {
          id: f.uuid(),
          name: f.companyName({ isUnique: true }),
          slug: f.valuesFromArray({ values: SLUG_POOL, isUnique: true }),
          plan: f.valuesFromArray({
            values: [
              { weight: 0.5, values: ["basic"] },
              { weight: 0.35, values: ["pro"] },
              { weight: 0.15, values: ["enterprise"] },
            ],
          }),
          deletedAt: f.default({ defaultValue: null }),
        },
      },
    }));

    return this.db.select().from(tenants);
  }

  async seedUsers(tx: TenantTx, tenant: { id: string }, { seed: seedNumber }: { seed: number }) {
    const tenantSeed = hashSeed(seedNumber, tenant.id);
    const userCount = 2 + (tenantSeed % 5);
    const password = await PasswordHelper.hash("swampert-dev-password");

    await seed(tx, { users }, { count: userCount, seed: tenantSeed }).refine((f) => ({
      users: {
        columns: {
          id: f.uuid(),
          tenantId: f.valuesFromArray({ values: [tenant.id] }),
          name: f.fullName(),
          email: f.email(),
          password: f.default({ defaultValue: password }),
          role: f.valuesFromArray({
            values: [
              { weight: 0.2, values: ["admin"] },
              { weight: 0.5, values: ["member"] },
              { weight: 0.3, values: ["viewer"] },
            ],
          }),
          deletedAt: f.default({ defaultValue: null }),
        },
      },
    }));
  }
}
