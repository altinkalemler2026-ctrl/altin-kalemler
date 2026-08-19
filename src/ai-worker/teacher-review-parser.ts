import type {
  JsonObject,
} from "./types.ts";

import type {
  TeacherReviewIssue,
  TeacherReviewIssueCategory,
  TeacherReviewIssueSeverity,
  TeacherReviewOutput,
  TeacherReviewRiskLevel,
  TeacherReviewRole,
  TeacherReviewVerdict,
} from "./teacher-review-types.ts";

const REVIEWER_ROLES: TeacherReviewRole[] = [
  "subject_teacher",
  "error_hunter",
  "correction",
  "final_checker",
];

const VERDICTS: TeacherReviewVerdict[] = [
  "pass",
  "pass_with_warning",
  "needs_correction",
  "human_review_required",
  "reject",
];

const RISK_LEVELS: TeacherReviewRiskLevel[] = [
  "unknown",
  "low",
  "medium",
  "high",
  "critical",
];

const ISSUE_SEVERITIES: TeacherReviewIssueSeverity[] = [
  "info",
  "low",
  "medium",
  "high",
  "critical",
];

const ISSUE_CATEGORIES: TeacherReviewIssueCategory[] = [
  "answer",
  "solution",
  "calculation",
  "factual",
  "curriculum",
  "grade_level",
  "language",
  "terminology",
  "ambiguity",
  "question_structure",
  "options",
  "distractors",
  "solve_time",
  "visual",
  "unit",
  "originality",
  "copyright",
  "other",
];

function stripCodeFence(
  rawText: string,
): string {
  const trimmed =
    rawText.trim();

  if (!trimmed.startsWith("```")) {
    return trimmed;
  }

  return trimmed
    .replace(
      /^```(?:json)?\s*/i,
      "",
    )
    .replace(
      /\s*```$/,
      "",
    )
    .trim();
}

function isObject(
  value: unknown,
): value is Record<string, unknown> {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  );
}

function readOptionalBoolean(
  object: Record<string, unknown>,
  key: string,
): boolean | undefined {
  const value =
    object[key];

  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "boolean") {
    throw new Error(
      `${key} must be boolean.`,
    );
  }

  return value;
}

function parseIssue(
  value: unknown,
  path: string,
): TeacherReviewIssue {
  if (!isObject(value)) {
    throw new Error(
      `${path} must be an object.`,
    );
  }

  if (
    typeof value.issue_code !== "string" ||
    value.issue_code.trim().length === 0
  ) {
    throw new Error(
      `${path}.issue_code is required.`,
    );
  }

  if (
    typeof value.issue_category !== "string" ||
    !ISSUE_CATEGORIES.includes(
      value.issue_category as TeacherReviewIssueCategory,
    )
  ) {
    throw new Error(
      `${path}.issue_category is invalid.`,
    );
  }

  if (
    typeof value.severity !== "string" ||
    !ISSUE_SEVERITIES.includes(
      value.severity as TeacherReviewIssueSeverity,
    )
  ) {
    throw new Error(
      `${path}.severity is invalid.`,
    );
  }

  if (
    typeof value.description !== "string" ||
    value.description.trim().length === 0
  ) {
    throw new Error(
      `${path}.description is required.`,
    );
  }

  if (
    typeof value.correction_recommended !== "boolean"
  ) {
    throw new Error(
      `${path}.correction_recommended must be boolean.`,
    );
  }

  if (
    typeof value.blocks_publication !== "boolean"
  ) {
    throw new Error(
      `${path}.blocks_publication must be boolean.`,
    );
  }

  if (
    value.field_name !== undefined &&
    typeof value.field_name !== "string"
  ) {
    throw new Error(
      `${path}.field_name must be string.`,
    );
  }

  if (
    value.evidence !== undefined &&
    !isObject(value.evidence)
  ) {
    throw new Error(
      `${path}.evidence must be an object.`,
    );
  }

  return {
    issue_code:
      value.issue_code,

    issue_category:
      value.issue_category as TeacherReviewIssueCategory,

    severity:
      value.severity as TeacherReviewIssueSeverity,

    ...(value.field_name !== undefined
      ? {
          field_name:
            value.field_name as string,
        }
      : {}),

    description:
      value.description,

    ...(value.evidence !== undefined
      ? {
          evidence:
            value.evidence as JsonObject,
        }
      : {}),

    correction_recommended:
      value.correction_recommended,

    blocks_publication:
      value.blocks_publication,
  };
}

export function parseTeacherReviewOutput(
  rawText: string,
): TeacherReviewOutput {
  const cleaned =
    stripCodeFence(rawText);

  let parsed: unknown;

  try {
    parsed =
      JSON.parse(cleaned);
  } catch {
    throw new Error(
      "Teacher review output is not valid JSON.",
    );
  }

  if (!isObject(parsed)) {
    throw new Error(
      "Teacher review output root must be an object.",
    );
  }

  if (
    parsed.schema_version !== "1.0"
  ) {
    throw new Error(
      'schema_version must be "1.0".',
    );
  }

  if (
    typeof parsed.reviewer_role !== "string" ||
    !REVIEWER_ROLES.includes(
      parsed.reviewer_role as TeacherReviewRole,
    )
  ) {
    throw new Error(
      "reviewer_role is invalid.",
    );
  }

  if (
    typeof parsed.verdict !== "string" ||
    !VERDICTS.includes(
      parsed.verdict as TeacherReviewVerdict,
    )
  ) {
    throw new Error(
      "verdict is invalid.",
    );
  }

  if (
    typeof parsed.risk_level !== "string" ||
    !RISK_LEVELS.includes(
      parsed.risk_level as TeacherReviewRiskLevel,
    )
  ) {
    throw new Error(
      "risk_level is invalid.",
    );
  }

  if (
    typeof parsed.confidence_score !== "number" ||
    parsed.confidence_score < 0 ||
    parsed.confidence_score > 1
  ) {
    throw new Error(
      "confidence_score must be between 0 and 1.",
    );
  }

  if (!isObject(parsed.checks)) {
    throw new Error(
      "checks must be an object.",
    );
  }

  if (
    typeof parsed.correction_required !== "boolean"
  ) {
    throw new Error(
      "correction_required must be boolean.",
    );
  }

  if (
    !Array.isArray(parsed.detected_errors)
  ) {
    throw new Error(
      "detected_errors must be an array.",
    );
  }

  if (
    !Array.isArray(parsed.warnings)
  ) {
    throw new Error(
      "warnings must be an array.",
    );
  }

  if (
    typeof parsed.review_summary !== "string" ||
    parsed.review_summary.trim().length === 0
  ) {
    throw new Error(
      "review_summary is required.",
    );
  }

  const checks = {
    answer_is_correct:
      readOptionalBoolean(
        parsed.checks,
        "answer_is_correct",
      ),

    solution_is_correct:
      readOptionalBoolean(
        parsed.checks,
        "solution_is_correct",
      ),

    single_correct_answer:
      readOptionalBoolean(
        parsed.checks,
        "single_correct_answer",
      ),

    question_is_complete:
      readOptionalBoolean(
        parsed.checks,
        "question_is_complete",
      ),

    question_is_unambiguous:
      readOptionalBoolean(
        parsed.checks,
        "question_is_unambiguous",
      ),

    curriculum_fit:
      readOptionalBoolean(
        parsed.checks,
        "curriculum_fit",
      ),

    grade_fit:
      readOptionalBoolean(
        parsed.checks,
        "grade_fit",
      ),

    language_fit:
      readOptionalBoolean(
        parsed.checks,
        "language_fit",
      ),

    terminology_fit:
      readOptionalBoolean(
        parsed.checks,
        "terminology_fit",
      ),

    options_are_valid:
      readOptionalBoolean(
        parsed.checks,
        "options_are_valid",
      ),

    distractors_are_valid:
      readOptionalBoolean(
        parsed.checks,
        "distractors_are_valid",
      ),

    solve_time_is_reasonable:
      readOptionalBoolean(
        parsed.checks,
        "solve_time_is_reasonable",
      ),

    factual_accuracy:
      readOptionalBoolean(
        parsed.checks,
        "factual_accuracy",
      ),

    calculation_accuracy:
      readOptionalBoolean(
        parsed.checks,
        "calculation_accuracy",
      ),

    unit_consistency:
      readOptionalBoolean(
        parsed.checks,
        "unit_consistency",
      ),
  };

  const detectedErrors =
    parsed.detected_errors.map(
      (value, index) =>
        parseIssue(
          value,
          `detected_errors[${index}]`,
        ),
    );

  const warnings =
    parsed.warnings.map(
      (value, index) =>
        parseIssue(
          value,
          `warnings[${index}]`,
        ),
    );

  let proposedCorrection:
    TeacherReviewOutput["proposed_correction"];

  if (
    parsed.proposed_correction !== undefined
  ) {
    if (
      !isObject(
        parsed.proposed_correction,
      )
    ) {
      throw new Error(
        "proposed_correction must be an object.",
      );
    }

    const proposal =
      parsed.proposed_correction;

    if (
      typeof proposal.confidence_score !== "number" ||
      proposal.confidence_score < 0 ||
      proposal.confidence_score > 1
    ) {
      throw new Error(
        "proposed_correction.confidence_score must be between 0 and 1.",
      );
    }

    if (
      typeof proposal.requires_recheck !== "boolean"
    ) {
      throw new Error(
        "proposed_correction.requires_recheck must be boolean.",
      );
    }

    if (
      proposal.correct_answer !== undefined &&
      ![
        "A",
        "B",
        "C",
        "D",
        "E",
      ].includes(
        String(
          proposal.correct_answer,
        ),
      )
    ) {
      throw new Error(
        "proposed_correction.correct_answer is invalid.",
      );
    }

    if (
      proposal.options !== undefined &&
      !isObject(proposal.options)
    ) {
      throw new Error(
        "proposed_correction.options must be an object.",
      );
    }

    if (
      proposal.solution !== undefined &&
      !isObject(proposal.solution)
    ) {
      throw new Error(
        "proposed_correction.solution must be an object.",
      );
    }

    if (
      proposal.change_reasons !== undefined &&
      (
        !Array.isArray(
          proposal.change_reasons,
        ) ||
        !proposal.change_reasons.every(
          (item) =>
            typeof item === "string",
        )
      )
    ) {
      throw new Error(
        "proposed_correction.change_reasons must be a string array.",
      );
    }

    proposedCorrection = {
      ...(typeof proposal.question_text === "string"
        ? {
            question_text:
              proposal.question_text,
          }
        : {}),

      ...(isObject(proposal.options)
        ? {
            options: {
              ...(typeof proposal.options.A === "string"
                ? {
                    A:
                      proposal.options.A,
                  }
                : {}),

              ...(typeof proposal.options.B === "string"
                ? {
                    B:
                      proposal.options.B,
                  }
                : {}),

              ...(typeof proposal.options.C === "string"
                ? {
                    C:
                      proposal.options.C,
                  }
                : {}),

              ...(typeof proposal.options.D === "string"
                ? {
                    D:
                      proposal.options.D,
                  }
                : {}),

              ...(typeof proposal.options.E === "string"
                ? {
                    E:
                      proposal.options.E,
                  }
                : {}),
            },
          }
        : {}),

      ...(proposal.correct_answer !== undefined
        ? {
            correct_answer:
              proposal.correct_answer as
                | "A"
                | "B"
                | "C"
                | "D"
                | "E",
          }
        : {}),

      ...(isObject(proposal.solution)
        ? {
            solution:
              proposal.solution as JsonObject,
          }
        : {}),

      ...(typeof proposal.change_summary === "string"
        ? {
            change_summary:
              proposal.change_summary,
          }
        : {}),

      ...(Array.isArray(
        proposal.change_reasons,
      )
        ? {
            change_reasons:
              proposal.change_reasons as string[],
          }
        : {}),

      confidence_score:
        proposal.confidence_score,

      requires_recheck:
        proposal.requires_recheck,
    };
  }

  if (
    parsed.correction_required &&
    !proposedCorrection
  ) {
    throw new Error(
      "correction_required is true but proposed_correction is missing.",
    );
  }

  if (
    parsed.verification_details !== undefined &&
    !isObject(
      parsed.verification_details,
    )
  ) {
    throw new Error(
      "verification_details must be an object.",
    );
  }

  if (
    parsed.metadata !== undefined &&
    !isObject(parsed.metadata)
  ) {
    throw new Error(
      "metadata must be an object.",
    );
  }

  return {
    schema_version:
      "1.0",

    reviewer_role:
      parsed.reviewer_role as TeacherReviewRole,

    verdict:
      parsed.verdict as TeacherReviewVerdict,

    risk_level:
      parsed.risk_level as TeacherReviewRiskLevel,

    confidence_score:
      parsed.confidence_score,

    checks,

    correction_required:
      parsed.correction_required,

    detected_errors:
      detectedErrors,

    warnings,

    review_summary:
      parsed.review_summary,

    ...(parsed.verification_details !== undefined
      ? {
          verification_details:
            parsed.verification_details as JsonObject,
        }
      : {}),

    ...(proposedCorrection
      ? {
          proposed_correction:
            proposedCorrection,
        }
      : {}),

    ...(parsed.metadata !== undefined
      ? {
          metadata:
            parsed.metadata as JsonObject,
        }
      : {}),
  };
}