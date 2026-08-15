import { drizzler } from "@database/drizzler.client";
import { TenantScope } from "@helpers/tenant.helper";
import { PasswordHelper } from "@helpers/password.helper";

import { AuthRepo } from "@repos/auth.repo";
import { ExecutionsRepo } from "@repos/executions.repo";
import { SwarmsRepo } from "@repos/swarms.repo";
import { ReportsRepo } from "@repos/reports.repo";
import { AuditRepo } from "@repos/audit.repo";

import { LoginUseCase } from "@core/auth/login.usecase";
import { LaunchExecutionUseCase } from "@core/executions/launch-execution.usecase";
import { CompleteExecutionUseCase } from "@core/executions/complete-execution.usecase";
import { RecordExecutionStepUseCase } from "@core/executions/record-execution-step.usecase";
import { ProvisionRosterUseCase } from "@core/swarms/provision-roster.usecase";
import { ArchiveStaleSwarmsUseCase } from "@core/swarms/archive-stale-swarms.usecase";
import { RefreshReportsUseCase } from "@core/reports/refresh-reports.usecase";
import { ReadReportsUseCase } from "@core/reports/read-reports.usecase";
import { TableHistoryUseCase } from "@core/audit/table-history.usecase";

// Composition root: the only place that wires infra adapters (repos) into core
// use-cases and hands the result to feats — deltas/restful.spec.md's hexagonal
// split means nowhere else in source/ should import from both @repos and @core.
const tenantScope = new TenantScope(drizzler);

const authRepo = new AuthRepo(drizzler, tenantScope);
const executionsRepo = new ExecutionsRepo(drizzler, tenantScope);
const swarmsRepo = new SwarmsRepo(drizzler, tenantScope);
const reportsRepo = new ReportsRepo(drizzler, tenantScope);
const auditRepo = new AuditRepo(drizzler, tenantScope);

export const container = {
  login: new LoginUseCase(authRepo, PasswordHelper.verify),
  launchExecution: new LaunchExecutionUseCase(executionsRepo),
  completeExecution: new CompleteExecutionUseCase(executionsRepo),
  recordExecutionStep: new RecordExecutionStepUseCase(executionsRepo),
  provisionRoster: new ProvisionRosterUseCase(swarmsRepo),
  archiveStaleSwarms: new ArchiveStaleSwarmsUseCase(swarmsRepo),
  refreshReports: new RefreshReportsUseCase(reportsRepo),
  readReports: new ReadReportsUseCase(reportsRepo),
  tableHistory: new TableHistoryUseCase(auditRepo),
};
