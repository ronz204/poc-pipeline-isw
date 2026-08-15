import { env } from "@secrets";
import { Elysia } from "elysia";

import { HealthPlugin } from "@plugins/health.plugin";
import { ScalarsPlugin } from "@plugins/scalars.plugin";
import { OriginsPlugin } from "@plugins/origins.plugin";

import { ErrorsPlugin } from "@feats/shared/errors.plugin";
import { AuthPlugin } from "@feats/auth/auth.plugin";
import { ExecutionsPlugin } from "@feats/executions/executions.plugin";
import { SwarmsPlugin } from "@feats/swarms/swarms.plugin";
import { ReportsPlugin } from "@feats/reports/reports.plugin";
import { AuditPlugin } from "@feats/audit/audit.plugin";

import { container } from "@cmd/container";

const app = new Elysia({ prefix: "/api" })
  .use(OriginsPlugin)
  .use(HealthPlugin)
  .use(ScalarsPlugin)
  .use(ErrorsPlugin)
  .use(AuthPlugin(container.login))
  .use(ExecutionsPlugin(container))
  .use(SwarmsPlugin(container))
  .use(ReportsPlugin(container))
  .use(AuditPlugin(container.tableHistory))
  .listen(env.APP_PORT);

const url = `http://${app.server?.hostname}:${app.server?.port}`;
console.log(`🦊 Elysia is running at ${url}`);
