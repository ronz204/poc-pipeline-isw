import { Elysia } from "elysia";
import { JwtPlugin } from "@security/jwt.plugin";
import { InvalidCredentialsError, LoginUseCase } from "@core/auth/login.usecase";
import { LoginBody, LoginResponse, UnauthorizedResponse } from "@feats/auth/auth.schema";

export const AuthPlugin = (login: LoginUseCase) =>
  new Elysia({ name: "auth.plugin", prefix: "/auth" })
    .use(JwtPlugin)
    .post("/login", async ({ body, jwt, set }) => {
      try {
        const auth = await login.execute(body);
        const token = await jwt.sign({ ...auth });
        return { token, ...auth };
      } catch (error) {
        if (error instanceof InvalidCredentialsError) {
          set.status = 401;
          return { error: error.message };
        }
        throw error;
      }
    }, {
      body: LoginBody,
      response: { 200: LoginResponse, 401: UnauthorizedResponse },
    });
