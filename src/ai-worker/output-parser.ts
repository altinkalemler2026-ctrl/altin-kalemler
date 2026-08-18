import type {
  AiWorkerCognitiveType,
  AiWorkerDifficulty,
  AiWorkerOptionKey,
  AiWorkerOutput,
  AiWorkerQuestion,
  JsonObject,
} from "./types.ts";

export type ParseAiWorkerOutputResult =
  | {
      success: true;
      output: AiWorkerOutput;
    }
  | {
      success: false;
      errors: string[];
    };

function isJsonObject(
  value: unknown,
): value is JsonObject {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  );
}

function isNonEmptyString(
  value: unknown,
): value is string {
  return (
    typeof value === "string" &&
    value.trim().length > 0
  );
}

function isOptionKey(
  value: unknown,
): value is AiWorkerOptionKey {
  return (
    value === "A" ||
    value === "B" ||
    value === "C" ||
    value === "D" ||
    value === "E"
  );
}

function isDifficulty(
  value: unknown,
): value is AiWorkerDifficulty {
  return (
    value === "easy" ||
    value === "medium" ||
    value === "hard"
  );
}

function isCognitiveType(
  value: unknown,
): value is AiWorkerCognitiveType {
  return (
    value === "learning" ||
    value === "comprehension" ||
    value === "application"
  );
}

function validateQuestion(
  value: unknown,
  index: number,
  errors: string[],
): AiWorkerQuestion | null {
  if (!isJsonObject(value)) {
    errors.push(
      `questions[${index}] must be an object.`,
    );

    return null;
  }

  const questionText =
    value["question_text"];

  if (
    !isNonEmptyString(questionText) ||
    questionText.trim().length < 10
  ) {
    errors.push(
      `questions[${index}].question_text must contain at least 10 characters.`,
    );
  }

  const optionsValue =
    value["options"];

  if (!isJsonObject(optionsValue)) {
    errors.push(
      `questions[${index}].options must be an object.`,
    );

    return null;
  }

  const optionA =
    optionsValue["A"];

  const optionB =
    optionsValue["B"];

  const optionC =
    optionsValue["C"];

  const optionD =
    optionsValue["D"];

  const optionE =
    optionsValue["E"];

  if (!isNonEmptyString(optionA)) {
    errors.push(
      `questions[${index}].options.A is required.`,
    );
  }

  if (!isNonEmptyString(optionB)) {
    errors.push(
      `questions[${index}].options.B is required.`,
    );
  }

  if (!isNonEmptyString(optionC)) {
    errors.push(
      `questions[${index}].options.C is required.`,
    );
  }

  if (!isNonEmptyString(optionD)) {
    errors.push(
      `questions[${index}].options.D is required.`,
    );
  }

  if (
    optionE !== undefined &&
    !isNonEmptyString(optionE)
  ) {
    errors.push(
      `questions[${index}].options.E must be a non-empty string when provided.`,
    );
  }

  const correctAnswer =
    value["correct_answer"];

  if (!isOptionKey(correctAnswer)) {
    errors.push(
      `questions[${index}].correct_answer must be A, B, C, D or E.`,
    );
  }

  if (
    correctAnswer === "E" &&
    !isNonEmptyString(optionE)
  ) {
    errors.push(
      `questions[${index}] selects E as the correct answer but option E does not exist.`,
    );
  }

  const difficulty =
    value["difficulty"];

  if (
    difficulty !== undefined &&
    !isDifficulty(difficulty)
  ) {
    errors.push(
      `questions[${index}].difficulty must be easy, medium or hard.`,
    );
  }

  const cognitiveType =
    value["cognitive_type"];

  if (
    cognitiveType !== undefined &&
    !isCognitiveType(cognitiveType)
  ) {
    errors.push(
      `questions[${index}].cognitive_type must be learning, comprehension or application.`,
    );
  }

  const estimatedSolveTime =
    value[
      "estimated_solve_time_seconds"
    ];

  if (
    estimatedSolveTime !== undefined &&
    (
      typeof estimatedSolveTime !==
        "number" ||
      !Number.isInteger(
        estimatedSolveTime,
      ) ||
      estimatedSolveTime <= 0
    )
  ) {
    errors.push(
      `questions[${index}].estimated_solve_time_seconds must be a positive integer.`,
    );
  }

  const optionalObjectFields = [
    "solution",
    "analysis",
    "metadata",
  ] as const;

  for (
    const field of
    optionalObjectFields
  ) {
    const fieldValue =
      value[field];

    if (
      fieldValue !== undefined &&
      !isJsonObject(fieldValue)
    ) {
      errors.push(
        `questions[${index}].${field} must be an object when provided.`,
      );
    }
  }

  if (
    errors.some(
      (error) =>
        error.startsWith(
          `questions[${index}]`,
        ),
    )
  ) {
    return null;
  }

  return {
    client_question_id:
      isNonEmptyString(
        value["client_question_id"],
      )
        ? value["client_question_id"]
        : undefined,

    question_text:
      questionText as string,

    options: {
      A: optionA as string,
      B: optionB as string,
      C: optionC as string,
      D: optionD as string,

      ...(isNonEmptyString(optionE)
        ? {
            E: optionE,
          }
        : {}),
    },

    correct_answer:
      correctAnswer as AiWorkerOptionKey,

    difficulty:
      isDifficulty(difficulty)
        ? difficulty
        : undefined,

    cognitive_type:
      isCognitiveType(cognitiveType)
        ? cognitiveType
        : undefined,

    primary_question_type:
      isNonEmptyString(
        value["primary_question_type"],
      )
        ? value[
            "primary_question_type"
          ]
        : undefined,

    is_new_generation:
      typeof value[
        "is_new_generation"
      ] === "boolean"
        ? value[
            "is_new_generation"
          ]
        : undefined,

    has_visual:
      typeof value["has_visual"] ===
      "boolean"
        ? value["has_visual"]
        : undefined,

    estimated_solve_time_seconds:
      typeof estimatedSolveTime ===
        "number" &&
      Number.isInteger(
        estimatedSolveTime,
      ) &&
      estimatedSolveTime > 0
        ? estimatedSolveTime
        : undefined,

    solution:
      isJsonObject(
        value["solution"],
      )
        ? value["solution"]
        : undefined,

    analysis:
      isJsonObject(
        value["analysis"],
      )
        ? value["analysis"]
        : undefined,

    metadata:
      isJsonObject(
        value["metadata"],
      )
        ? value["metadata"]
        : undefined,
  };
}

function removeMarkdownFence(
  rawText: string,
): string {
  const trimmed =
    rawText.trim();

  if (
    !trimmed.startsWith("```")
  ) {
    return trimmed;
  }

  const lines =
    trimmed.split(/\r?\n/);

  if (
    lines.length >= 2 &&
    lines[0].startsWith("```")
  ) {
    lines.shift();
  }

  if (
    lines.length > 0 &&
    lines[
      lines.length - 1
    ].trim() === "```"
  ) {
    lines.pop();
  }

  return lines
    .join("\n")
    .trim();
}

export function parseAiWorkerOutput(
  rawText: string,
): ParseAiWorkerOutputResult {
  const errors: string[] = [];

  if (
    typeof rawText !== "string" ||
    rawText.trim().length === 0
  ) {
    return {
      success: false,
      errors: [
        "AI provider returned an empty response.",
      ],
    };
  }

  const normalizedText =
    removeMarkdownFence(
      rawText,
    );

  let parsed: unknown;

  try {
    parsed =
      JSON.parse(
        normalizedText,
      );
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : String(error);

    return {
      success: false,
      errors: [
        `AI provider returned invalid JSON: ${message}`,
      ],
    };
  }

  if (!isJsonObject(parsed)) {
    return {
      success: false,
      errors: [
        "AI provider root response must be a JSON object.",
      ],
    };
  }

  if (
    parsed["schema_version"] !==
    "1.0"
  ) {
    errors.push(
      'schema_version must be exactly "1.0".',
    );
  }

  const questionsValue =
    parsed["questions"];

  if (
    !Array.isArray(
      questionsValue,
    )
  ) {
    errors.push(
      "questions must be an array.",
    );

    return {
      success: false,
      errors,
    };
  }

  if (
    questionsValue.length === 0
  ) {
    errors.push(
      "questions must contain at least one question.",
    );
  }

  const questions:
    AiWorkerQuestion[] = [];

  questionsValue.forEach(
    (
      question,
      index,
    ) => {
      const validatedQuestion =
        validateQuestion(
          question,
          index,
          errors,
        );

      if (
        validatedQuestion
      ) {
        questions.push(
          validatedQuestion,
        );
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

    output: {
      schema_version: "1.0",
      questions,
    },
  };
}