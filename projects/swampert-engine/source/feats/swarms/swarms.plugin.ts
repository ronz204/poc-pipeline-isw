import { Elysia } from "elysia";
import { AuthGuardPlugin } from "@feats/shared/auth.guard.plugin";

import type { ProvisionRosterUseCase } from "@core/swarms/provision-roster.usecase";
import type { ArchiveStaleSwarmsUseCase } from "@core/swarms/archive-stale-swarms.usecase";

import {
  RosterParams, RosterBody, RosterResponse, ArchiveStaleBody, ArchiveStaleResponse,
} from "@feats/swarms/swarms.schema";

export interface SwarmsUseCases {
  provisionRoster: ProvisionRosterUseCase;
  archiveStaleSwarms: ArchiveStaleSwarmsUseCase;
}

export const SwarmsPlugin = (usecases: SwarmsUseCases) =>
  new Elysia({ name: "swarms.plugin", prefix: "/swarms" })
    .use(AuthGuardPlugin)
    .post("/:id/roster", ({ params, body, auth }) => usecases.provisionRoster.execute(
      auth!.tenantId, { swarmId: params.id, agentIds: body.agentIds }), {
      params: RosterParams,
      body: RosterBody,
      response: RosterResponse,
    })
    .post("/archive-stale", ({ body, auth }) => usecases.archiveStaleSwarms.execute(
      auth!.tenantId, body), {
      body: ArchiveStaleBody,
      response: ArchiveStaleResponse,
    });
