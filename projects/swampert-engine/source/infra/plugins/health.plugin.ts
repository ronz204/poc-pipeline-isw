import { env } from "@secrets";
import { Elysia } from "elysia";

export const HealthPlugin = new Elysia({ name: "health.plugin" })
  .get("/health", () => ({ service: env.APP_NAME, status: "healthy" }));
