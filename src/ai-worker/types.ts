export type JsonPrimitive =
  | string
  | number
  | boolean
  | null;

export type JsonValue =
  | JsonPrimitive
  | JsonObject
  | JsonValue[];

export type JsonObject = {
  [key: string]: JsonValue;
};

export type AiWorkerOptionKey =
  | "A"
  | "B"
  | "C"
  | "D"
  | "E";

export type AiWorkerDifficulty =
  | "easy"
  | "medium"
  | "hard";

export type AiWorkerCognitiveType =
  | "learning"
  | "comprehension"
  | "application";

export type AiWorkerQuestion = {
  client_question_id?: string;

  question_text: string;

  options: {
    A: string;
    B: string;
    C: string;
    D: string;
    E?: string;
  };

  correct_answer: AiWorkerOptionKey;

  difficulty?: AiWorkerDifficulty;

  cognitive_type?: AiWorkerCognitiveType;

  primary_question_type?: string;

  is_new_generation?: boolean;

  has_visual?: boolean;

  estimated_solve_time_seconds?: number;

  solution?: JsonObject;

  analysis?: JsonObject;

  metadata?: JsonObject;
};

export type AiWorkerOutput = {
  schema_version: "1.0";

  questions: AiWorkerQuestion[];
};

export type ClaimedAiJob = {
  status: "claimed";

  job_available: true;

  ai_job_id: string;

  job_type: "question_generation";

  generation_spec_id: string;

  competition_generation_request_id: string | null;

  competition_factory_dispatch_id: string;

  claim_token: string;

  claimed_by: string;

  claimed_at: string;

  lease_expires_at: string;

  attempt_count: number;

  max_attempts: number;

  input_data: JsonObject;
};

export type EmptyAiJobQueue = {
  status: "empty";

  job_available: false;
};

export type ClaimAiJobResult =
  | ClaimedAiJob
  | EmptyAiJobQueue;

export type AiProviderContext = {
  job: ClaimedAiJob;
};

export interface AiQuestionProvider {
  readonly providerName: string;
  readonly modelName: string;
  readonly workerVersion: string;
  readonly promptVersion: string;

  generateQuestions(
    context: AiProviderContext,
  ): Promise<AiWorkerOutput>;
}