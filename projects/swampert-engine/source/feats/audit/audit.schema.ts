import { t } from "elysia";

export const HistoryParams = t.Object({
  table: t.String({ minLength: 1 }),
});

export const AuditHistoryResponse = t.Array(t.Object({
  id: t.String(),
  userId: t.String(),
  action: t.String(),
  entityId: t.String(),
  details: t.Record(t.String(), t.Unknown()),
  occurredAt: t.Date(),
}));
