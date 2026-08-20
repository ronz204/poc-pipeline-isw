const DEFAULT_BASE_URL = "http://localhost:3000/api";

export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || DEFAULT_BASE_URL;

export class ApiError extends Error {
  public readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

// Shared fetch wrapper for every *.client.ts — attaches the base URL and an
// optional bearer token, parses JSON, and turns a non-2xx response into a
// typed ApiError instead of leaving each client to repeat that plumbing.
export class ApiClient {
  private readonly baseUrl: string;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
  }

  protected async request<T>(path: string, init: RequestInit = {}, token?: string | null): Promise<T> {
    const headers = new Headers(init.headers);
    headers.set("Content-Type", "application/json");
    if (token) {
      headers.set("Authorization", `Bearer ${token}`);
    }

    const response = await fetch(`${this.baseUrl}${path}`, { ...init, headers });
    const payload = await response.json().catch(() => null);

    if (!response.ok) {
      const message = payload && typeof payload === "object" && "error" in payload
        ? String((payload as { error: unknown }).error)
        : response.statusText;

      throw new ApiError(response.status, message);
    }

    return payload as T;
  }
}
