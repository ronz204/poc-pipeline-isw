import { t } from "elysia";

export const LoginBody = t.Object({
  tenantSlug: t.String({ minLength: 1 }),
  email: t.String({ format: "email" }),
  password: t.String({ minLength: 1 }),
});

export const LoginResponse = t.Object({
  token: t.String(),
  tenantId: t.String(),
  userId: t.String(),
  role: t.Union([t.Literal("admin"), t.Literal("member"), t.Literal("viewer")]),
});

export const UnauthorizedResponse = t.Object({
  error: t.String(),
});
