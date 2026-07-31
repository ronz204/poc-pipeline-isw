import { env } from "@secrets";
import { Elysia } from "elysia";

import { HealthPlugin } from "@plugins/health.plugin";
import { ScalarsPlugin } from "@plugins/scalars.plugin";
import { OriginsPlugin } from "@plugins/origins.plugin";

const app = new Elysia({ prefix: "/api" })
  .use(OriginsPlugin)
  .use(HealthPlugin)
  .use(ScalarsPlugin)
  .listen(env.APP_PORT);

const url = `http://${app.server?.hostname}:${app.server?.port}`;
console.log(`🦊 Elysia is running at ${url}`);
