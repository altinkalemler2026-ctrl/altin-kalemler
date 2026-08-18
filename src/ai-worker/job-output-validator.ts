import type {
  AiWorkerOutput,
  ClaimedAiJob,
  JsonObject,
  JsonValue,
} from "./types.ts";

export type ValidateJobOutputResult =
  | {
      success: true;
    }
  | {
      success: false;
      errors: string[];
    };

function asObject(
  value: JsonValue | undefined,
): JsonObject {
  if (
    value &&
    typeof value === "object" &&
    !Array.isArray(value)
  ) {
    return value as JsonObject;
  }

  return {};
}

function asString(
  value: JsonValue | undefined,
): string | null {
  return typeof value === "string"
    ? value
    : null;
}

function asNumber(
  value: JsonValue | undefined,
): number | null {
  return typeof value === "number"
    ? value
    : null;
}

export function validateOutputAgainstJob(
  job: ClaimedAiJob,
  output: AiWorkerOutput,
): ValidateJobOutputResult {
  const errors: string[] = [];

  const input =
    job.input_data;

  const generationRequirements =
    asObject(
      input["generation_requirements"],
    );

  const solveTimeRequirements =
    asObject(
      input["solve_time_requirements"],
    );

  const requestedQuestionCount =
    asNumber(
      input["requested_question_count"],
    );

  const requestedDifficulty =
    asString(
      generationRequirements[
        "difficulty"
      ],
    );

  const requestedCognitiveLevel =
    asString(
      generationRequirements[
        "cognitive_level"
      ],
    );

  const requestedQuestionType =
    asString(
      generationRequirements[
        "question_type"
      ],
    );

  const minimumSolveTime =
    asNumber(
      solveTimeRequirements[
        "minimum_seconds"
      ],
    );

  const maximumSolveTime =
    asNumber(
      solveTimeRequirements[
        "maximum_seconds"
      ],
    );

  if (
    requestedQuestionCount !== null &&
    output.questions.length !==
      requestedQuestionCount
  ) {
    errors.push(
      `Expected ${requestedQuestionCount} question(s), but provider returned ${output.questions.length}.`,
    );
  }

  output.questions.forEach(
    (
      question,
      index,
    ) => {
      if (
        requestedDifficulty !== null &&
        question.difficulty !==
          requestedDifficulty
      ) {
        errors.push(
          `questions[${index}].difficulty does not match the job. Expected "${requestedDifficulty}", received "${question.difficulty ?? "undefined"}".`,
        );
      }

      if (
        requestedCognitiveLevel !== null &&
        question.cognitive_type !==
          requestedCognitiveLevel
      ) {
        errors.push(
          `questions[${index}].cognitive_type does not match the job. Expected "${requestedCognitiveLevel}", received "${question.cognitive_type ?? "undefined"}".`,
        );
      }

      if (
        requestedQuestionType !== null &&
        question.primary_question_type !==
          requestedQuestionType
      ) {
        errors.push(
          `questions[${index}].primary_question_type does not match the job. Expected "${requestedQuestionType}", received "${question.primary_question_type ?? "undefined"}".`,
        );
      }

      const solveTime =
        question.estimated_solve_time_seconds;

      if (
        minimumSolveTime !== null
      ) {
        if (
          solveTime === undefined
        ) {
          errors.push(
            `questions[${index}].estimated_solve_time_seconds is required by the job.`,
          );
        } else if (
          solveTime <
          minimumSolveTime
        ) {
          errors.push(
            `questions[${index}].estimated_solve_time_seconds is below the minimum. Minimum ${minimumSolveTime}, received ${solveTime}.`,
          );
        }
      }

      if (
        maximumSolveTime !== null
      ) {
        if (
          solveTime === undefined
        ) {
          if (
            !errors.includes(
              `questions[${index}].estimated_solve_time_seconds is required by the job.`,
            )
          ) {
            errors.push(
              `questions[${index}].estimated_solve_time_seconds is required by the job.`,
            );
          }
        } else if (
          solveTime >
          maximumSolveTime
        ) {
          errors.push(
            `questions[${index}].estimated_solve_time_seconds exceeds the maximum. Maximum ${maximumSolveTime}, received ${solveTime}.`,
          );
        }
      }
    },
  );

  if (errors.length > 0) {
    return {
      success: false,
      errors,
    };
  }

  return {
    success: true,
  };
}