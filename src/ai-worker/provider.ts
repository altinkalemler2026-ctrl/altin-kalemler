import type {
  AiQuestionProvider,
  AiWorkerOutput,
  ClaimedAiJob,
} from "./types.ts";

export type ProviderExecutionResult = {
  output: AiWorkerOutput;

  providerName: string;

  modelName: string;

  promptVersion: string;

  workerVersion: string;
};

function validateWorkerOutput(
  output: AiWorkerOutput,
): void {
  if (output.schema_version !== "1.0") {
    throw new Error(
      "AI provider returned an unsupported schema_version.",
    );
  }

  if (!Array.isArray(output.questions)) {
    throw new Error(
      "AI provider output must contain a questions array.",
    );
  }

  for (const question of output.questions) {
    if (
      typeof question.question_text !== "string" ||
      question.question_text.trim().length < 10
    ) {
      throw new Error(
        "AI provider returned an invalid question_text.",
      );
    }

    if (
      !question.options ||
      typeof question.options.A !== "string" ||
      typeof question.options.B !== "string" ||
      typeof question.options.C !== "string" ||
      typeof question.options.D !== "string"
    ) {
      throw new Error(
        "AI provider returned invalid answer options.",
      );
    }

    const allowedAnswers = [
      "A",
      "B",
      "C",
      "D",
      "E",
    ];

    if (
      !allowedAnswers.includes(
        question.correct_answer,
      )
    ) {
      throw new Error(
        "AI provider returned an invalid correct_answer.",
      );
    }

    const selectedOption =
      question.options[
        question.correct_answer
      ];

    if (
      typeof selectedOption !== "string" ||
      selectedOption.trim().length === 0
    ) {
      throw new Error(
        "AI provider correct_answer does not point to an existing option.",
      );
    }

    if (
      question.estimated_solve_time_seconds !==
        undefined &&
      (
        !Number.isInteger(
          question.estimated_solve_time_seconds,
        ) ||
        question.estimated_solve_time_seconds <= 0
      )
    ) {
      throw new Error(
        "estimated_solve_time_seconds must be a positive integer.",
      );
    }
  }
}

export async function executeProvider(
  provider: AiQuestionProvider,
  job: ClaimedAiJob,
): Promise<ProviderExecutionResult> {
  const output =
    await provider.generateQuestions({
      job,
    });

  validateWorkerOutput(output);

  return {
    output,

    providerName:
      provider.providerName,

    modelName:
      provider.modelName,

    promptVersion:
      provider.promptVersion,

    workerVersion:
      provider.workerVersion,
  };
}