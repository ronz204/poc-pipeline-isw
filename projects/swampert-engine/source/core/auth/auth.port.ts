export type UserRole = "admin" | "member" | "viewer";

export interface AuthContext {
  tenantId: string;
  userId: string;
  role: UserRole;
}

export interface LoginCredentials {
  tenantSlug: string;
  email: string;
  password: string;
}

export interface TenantLookup {
  id: string;
}

export interface UserCredentials {
  id: string;
  passwordHash: string;
  role: UserRole;
  active: boolean;
}

export interface LoginPort {
  findTenantBySlug(slug: string): Promise<TenantLookup | null>;
  findUserByEmail(tenantId: string, email: string): Promise<UserCredentials | null>;
}
