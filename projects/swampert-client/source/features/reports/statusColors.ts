export type TaskStatus = "pending" | "progress" | "completed" | "failed";
export type ErrorSeverity = "low" | "medium" | "high" | "critical";

export const TASK_STATUSES: readonly TaskStatus[] = ["pending", "progress", "completed", "failed"];
export const ERROR_SEVERITIES: readonly ErrorSeverity[] = ["low", "medium", "high", "critical"];

// Skill §3 only names 3 of these 4 states explicitly (completed→ok, progress→warn,
// failed→critical) — "pending" gets the neutral muted token, nothing in the token
// table implies a task that hasn't started yet should read as good/bad/urgent.
const TASK_STATUS_COLOR: Record<TaskStatus, string> = {
  pending: "var(--text-muted)",
  progress: "var(--warn)",
  completed: "var(--ok)",
  failed: "var(--critical)",
};

const TASK_STATUS_LABEL: Record<TaskStatus, string> = {
  pending: "Pendiente",
  progress: "En curso",
  completed: "Completada",
  failed: "Fallida",
};

// Same gap for severity: the skill's table only names medium→warn and
// critical→critical. "low" gets --ok (same "not concerning" direction). "high"
// has no token of its own — rather than reuse the exact --critical hue (which
// would make high and critical visually indistinguishable in a bar chart) or add
// an 11th color the skill's closed palette doesn't authorize, it's blended from
// the two adjacent tokens so it reads as a real step between medium and critical.
const SEVERITY_COLOR: Record<ErrorSeverity, string> = {
  low: "var(--ok)",
  medium: "var(--warn)",
  high: "color-mix(in srgb, var(--critical) 65%, var(--warn) 35%)",
  critical: "var(--critical)",
};

const SEVERITY_LABEL: Record<ErrorSeverity, string> = {
  low: "Baja",
  medium: "Media",
  high: "Alta",
  critical: "Crítica",
};

export function taskStatusColor(status: string): string {
  return TASK_STATUS_COLOR[status as TaskStatus] ?? "var(--text-muted)";
}

export function taskStatusLabel(status: string): string {
  return TASK_STATUS_LABEL[status as TaskStatus] ?? status;
}

export function severityColor(severity: string): string {
  return SEVERITY_COLOR[severity as ErrorSeverity] ?? "var(--text-muted)";
}

export function severityLabel(severity: string): string {
  return SEVERITY_LABEL[severity as ErrorSeverity] ?? severity;
}
