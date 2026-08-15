import { env } from "@secrets";
import { jwt } from "@elysia/jwt";

export const JwtPlugin = jwt({
  name: "jwt",
  secret: env.JWT_SECRET,
  exp: env.JWT_EXPIRES_IN,
});
