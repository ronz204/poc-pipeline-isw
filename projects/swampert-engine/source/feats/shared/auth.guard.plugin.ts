import { Elysia } from "elysia";
import { JwtPlugin } from "@security/jwt.plugin";
import type { AuthContext } from "@core/auth/auth.port";

// Every route except POST /api/auth/login uses this. Decodes the bearer JWT into
// `auth` before the handler runs; a missing/invalid token short-circuits with 401
// so no protected handler ever executes without a resolved tenant/user identity —
// deltas/restful.spec.md § Objective.
export const AuthGuardPlugin = new Elysia({ name: "auth.guard.plugin" })
  .use(JwtPlugin)
  .resolve({ as: "scoped" }, async ({ jwt, headers }) => {
    const token = headers.authorization?.replace(/^Bearer\s+/i, "");
    const payload = token ? await jwt.verify(token) : false;

    return { auth: (payload || null) as AuthContext | null };
  })
  .onBeforeHandle({ as: "scoped" }, ({ auth, set }) => {
    if (!auth) {
      set.status = 401;
      return { error: "Unauthorized" };
    }
  });
