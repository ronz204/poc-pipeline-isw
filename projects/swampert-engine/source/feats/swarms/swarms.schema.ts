import { t } from "elysia";

export const RosterParams = t.Object({
  id: t.String({ format: "uuid" }),
});

export const RosterBody = t.Object({
  agentIds: t.Array(t.String({ format: "uuid" }), { minItems: 1 }),
});

export const RosterResponse = t.Object({
  swarmId: t.String(),
  rosterSize: t.Integer(),
});

export const ArchiveStaleBody = t.Object({
  inactiveSince: t.Date(),
});

export const ArchiveStaleResponse = t.Object({
  archivedCount: t.Integer(),
});
