import type { AuthContext, LoginCredentials, LoginPort } from "@core/auth/auth.port";

export class InvalidCredentialsError extends Error {
  constructor() {
    super("Invalid tenant, email or password");
  }
}

export class LoginUseCase {
  constructor(
    private readonly port: LoginPort,
    private readonly verifyPassword: (plain: string, hash: string) => Promise<boolean>,
  ) {};

  // Never distinguishes which of {unknown tenant, unknown email, wrong password}
  // failed — deltas/restful.spec.md § Implementation § 5, deliberate
  // enumeration-resistance, not an oversight.
  public async execute(credentials: LoginCredentials): Promise<AuthContext> {
    const tenant = await this.port.findTenantBySlug(credentials.tenantSlug);
    if (!tenant) throw new InvalidCredentialsError();

    const user = await this.port.findUserByEmail(tenant.id, credentials.email);
    if (!user || !user.active) throw new InvalidCredentialsError();

    const valid = await this.verifyPassword(credentials.password, user.passwordHash);
    if (!valid) throw new InvalidCredentialsError();

    return { tenantId: tenant.id, userId: user.id, role: user.role };
  };
};
