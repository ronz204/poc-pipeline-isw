import { Elysia } from "elysia";
import { AuthGuardPlugin } from "@feats/shared/auth.guard.plugin";

import type { LaunchExecutionUseCase } from "@core/executions/launch-execution.usecase";
import type { CompleteExecutionUseCase } from "@core/executions/complete-execution.usecase";
import type { RecordExecutionStepUseCase } from "@core/executions/record-execution-step.usecase";

import {
  LaunchExecutionBody, CompleteExecutionParams, CompleteExecutionBody,
  RecordStepParams, RecordStepBody, ExecutionResponse, ExecutionStepResponse,
} from "@feats/executions/executions.schema";

export interface ExecutionsUseCases {
  launchExecution: LaunchExecutionUseCase;
  completeExecution: CompleteExecutionUseCase;
  recordExecutionStep: RecordExecutionStepUseCase;
}

export const ExecutionsPlugin = (usecases: ExecutionsUseCases) =>
  new Elysia({ name: "executions.plugin", prefix: "/executions" })
    .use(AuthGuardPlugin)
    // auth is guaranteed non-null here: AuthGuardPlugin's onBeforeHandle already
    // rejected the request with 401 before this handler runs.
    .post("/launch", ({ body, auth }) => usecases.launchExecution.execute(auth!.tenantId, body), {
      body: LaunchExecutionBody,
      response: ExecutionResponse,
    })
    .post("/:id/complete", ({ params, body, auth }) => usecases.completeExecution.execute(
      auth!.tenantId, { executionId: params.id, ...body }), {
      params: CompleteExecutionParams,
      body: CompleteExecutionBody,
      response: ExecutionResponse,
    })
    .post("/:id/steps", ({ params, body, auth }) => usecases.recordExecutionStep.execute(
      auth!.tenantId, { executionId: params.id, ...body }), {
      params: RecordStepParams,
      body: RecordStepBody,
      response: ExecutionStepResponse,
    });
