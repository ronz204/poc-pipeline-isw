import { and, eq, isNull } from "drizzle-orm";
import { tenants, users } from "@elements/auth.element";

import type { Drizzler } from "@database/drizzler.client";
import type { LoginPort, TenantLookup, UserCredentials } from "@core/auth/auth.port";

import { TenantScope } from "@helpers/tenant.helper";

export class AuthRepo implements LoginPort {
  constructor(
    private readonly db: Drizzler,
    private readonly tenantScope: TenantScope,
  ) {};

  // auth.tenants carries no RLS (it isn't tenant-scoped, it IS the tenant list) —
  // a plain read as `runner` needs no app.current_tenant_id.
  public async findTenantBySlug(slug: string): Promise<TenantLookup | null> {
    const [tenant] = await this.db.select({ id: tenants.id })
      .from(tenants)
      .where(and(eq(tenants.slug, slug), isNull(tenants.deletedAt)))
      .limit(1);

    return tenant ?? null;
  };

  // auth.users IS tenant-scoped RLS — reading it before a JWT exists means the only
  // tenant context available is the one just resolved from the slug, set for the
  // scope of this one lookup.
  public async findUserByEmail(tenantId: string, email: string): Promise<UserCredentials | null> {
    return this.tenantScope.run(tenantId, async (tx) => {
      const [user] = await tx.select({
        id: users.id,
        passwordHash: users.password,
        role: users.role,
        active: users.active,
      })
        .from(users)
        .where(and(
          eq(users.tenantId, tenantId),
          eq(users.email, email),
          isNull(users.deletedAt),
        ))
        .limit(1);

      return user ?? null;
    });
  };
};
