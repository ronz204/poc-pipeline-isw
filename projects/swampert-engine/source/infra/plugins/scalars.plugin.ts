import { env } from "@secrets";
import { openapi } from "@elysia/openapi";

export const ScalarsPlugin = openapi({
  path: "/docs",
  documentation: {
    info: {
      title: env.APP_NAME,
      version: env.APP_VERSION,
    },
  },
});
