import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";

import type {
  AiWorkerOutput,
  ClaimAiJobResult,
  ClaimedAiJob,
  JsonObject,
} from "./types.ts";

type RpcResponse<T> = {
  data: T | null;
  error: {
    message: string;
    code?: string;
    details?: string;
    hint?: string;
  } | null;
};

export type RegisterWorkerOutputInput = {
  aiJobId: string;

  output: AiWorkerOutput;

  providerName: string;

  modelName: string;

  promptVersion: string;

  workerVersion: string;
};

export type WorkerIngestionResult = {
  worker_output_id: string;
  ai_job_id: string;
  dispatch_id: string;

  received_question_count: number;
  valid_question_count: number;
  invalid_question_count: number;
  inserted_question_count: number;
  duplicate_question_count: number;

  total_staging_count: number;
  requested_question_count: number;
  remaining_question_count: number;

  retry_required: boolean;
  job_status: string;

  production_publication: false;
};

export type LeaseRenewalResult = {
  status: "renewed";

  ai_job_id: string;

  claim_token: string;

  heartbeat_at: string;

  lease_expires_at: string;
};

export type FailureResult = {
  status: "queued" | "failed";

  ai_job_id: string;

  attempt_count: number;

  max_attempts: number;

  retry_scheduled: boolean;
};

function requireEnvironmentVariable(
  name: string,
): string {
  const value =
    process.env[name]?.trim();

  if (!value) {
    throw new Error(
      `Required environment variable is missing: ${name}`,
    );
  }

  return value;
}

function createWorkerSupabaseClient(): SupabaseClient {
  const supabaseUrl =
    requireEnvironmentVariable(
      "NEXT_PUBLIC_SUPABASE_URL",
    );

  const serviceRoleKey =
    requireEnvironmentVariable(
      "SUPABASE_SERVICE_ROLE_KEY",
    );

  return createClient(
    supabaseUrl,
    serviceRoleKey,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    },
  );
}

function throwRpcError(
  operation: string,
  error: RpcResponse<unknown>["error"],
): never {
  const details = [
    error?.message,
    error?.details,
    error?.hint,
  ]
    .filter(Boolean)
    .join(" | ");

  throw new Error(
    `${operation} failed${
      details
        ? `: ${details}`
        : "."
    }`,
  );
}

export class SupabaseAiWorker {
  private readonly client: SupabaseClient;

  constructor() {
    this.client =
      createWorkerSupabaseClient();
  }

  async claimNextJob(
    workerName: string,
    leaseSeconds = 300,
  ): Promise<ClaimAiJobResult> {
    const response =
      (await this.client.rpc(
        "claim_next_ai_generation_job",
        {
          p_worker_name:
            workerName,

          p_lease_seconds:
            leaseSeconds,
        },
      )) as RpcResponse<ClaimAiJobResult>;

    if (response.error) {
      throwRpcError(
        "claim_next_ai_generation_job",
        response.error,
      );
    }

    if (!response.data) {
      throw new Error(
        "claim_next_ai_generation_job returned no result.",
      );
    }

    return response.data;
  }

  async renewLease(
    job: ClaimedAiJob,
    leaseSeconds = 300,
  ): Promise<LeaseRenewalResult> {
    const response =
      (await this.client.rpc(
        "renew_ai_job_lease",
        {
          p_ai_job_id:
            job.ai_job_id,

          p_claim_token:
            job.claim_token,

          p_lease_seconds:
            leaseSeconds,
        },
      )) as RpcResponse<LeaseRenewalResult>;

    if (response.error) {
      throwRpcError(
        "renew_ai_job_lease",
        response.error,
      );
    }

    if (!response.data) {
      throw new Error(
        "renew_ai_job_lease returned no result.",
      );
    }

    return response.data;
  }

  async failClaim(
    job: ClaimedAiJob,
    errorCode: string,
    errorMessage: string,
    retryable = true,
  ): Promise<FailureResult> {
    const response =
      (await this.client.rpc(
        "fail_ai_job_claim",
        {
          p_ai_job_id:
            job.ai_job_id,

          p_claim_token:
            job.claim_token,

          p_error_code:
            errorCode,

          p_error_message:
            errorMessage,

          p_retryable:
            retryable,
        },
      )) as RpcResponse<FailureResult>;

    if (response.error) {
      throwRpcError(
        "fail_ai_job_claim",
        response.error,
      );
    }

    if (!response.data) {
      throw new Error(
        "fail_ai_job_claim returned no result.",
      );
    }

    return response.data;
  }

  async registerWorkerOutput(
    input: RegisterWorkerOutputInput,
  ): Promise<string> {
    const response =
      (await this.client.rpc(
        "register_ai_worker_output",
        {
          p_ai_job_id:
            input.aiJobId,

          p_raw_output:
            input.output,

          p_provider_name:
            input.providerName,

          p_model_name:
            input.modelName,

          p_prompt_version:
            input.promptVersion,

          p_worker_version:
            input.workerVersion,
        },
      )) as RpcResponse<string>;

    if (response.error) {
      throwRpcError(
        "register_ai_worker_output",
        response.error,
      );
    }

    if (
      typeof response.data !==
        "string" ||
      response.data.length === 0
    ) {
      throw new Error(
        "register_ai_worker_output did not return a worker output id.",
      );
    }

    return response.data;
  }

  async ingestWorkerOutput(
    workerOutputId: string,
  ): Promise<WorkerIngestionResult> {
    const response =
      (await this.client.rpc(
        "ingest_ai_worker_output",
        {
          p_worker_output_id:
            workerOutputId,
        },
      )) as RpcResponse<WorkerIngestionResult>;

    if (response.error) {
      throwRpcError(
        "ingest_ai_worker_output",
        response.error,
      );
    }

    if (!response.data) {
      throw new Error(
        "ingest_ai_worker_output returned no result.",
      );
    }

    return response.data;
  }

  async getWorkerOutputReport(
    workerOutputId: string,
  ): Promise<JsonObject> {
    const response =
      (await this.client.rpc(
        "get_ai_worker_output_report",
        {
          p_worker_output_id:
            workerOutputId,
        },
      )) as RpcResponse<JsonObject>;

    if (response.error) {
      throwRpcError(
        "get_ai_worker_output_report",
        response.error,
      );
    }

    if (!response.data) {
      throw new Error(
        "get_ai_worker_output_report returned no result.",
      );
    }

    return response.data;
  }
}