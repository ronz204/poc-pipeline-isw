import { ApiClient, API_BASE_URL } from "@shared/http/api.client";

export type UserRole = "admin" | "member" | "viewer";

export interface LoginResult {
  token: string;
  tenantId: string;
  userId: string;
  role: UserRole;
}

export class AuthApiClient extends ApiClient {
  public async login(tenantSlug: string, email: string, password: string): Promise<LoginResult> {
    return this.request<LoginResult>("/auth/login", {
      method: "POST",
      body: JSON.stringify({ tenantSlug, email, password }),
    });
  }
}

export const authApiClient = new AuthApiClient(API_BASE_URL);
