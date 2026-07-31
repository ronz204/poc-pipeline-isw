import { env } from "@secrets";
import { cors } from "@elysia/cors";

export const OriginsPlugin = cors({
  origin: env.CORS_ORIGIN,
  methods: env.CORS_METHODS,
  allowedHeaders: ["Content-Type", "Authorization"],
});
