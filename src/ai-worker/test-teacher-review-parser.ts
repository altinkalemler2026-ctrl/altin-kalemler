import { parseTeacherReviewOutput } from "./teacher-review-parser.ts";

function expectSuccess(
  name: string,
  raw: string,
): void {
  try {
    parseTeacherReviewOutput(raw);

    console.log(
      `${name}: true`,
    );
  } catch (error) {
    console.error(
      `${name}: false`,
    );

    throw error;
  }
}

function expectFailure(
  name: string,
  raw: string,
): void {
  let failed = false;

  try {
    parseTeacherReviewOutput(raw);
  } catch {
    failed = true;
  }

  console.log(
    `${name}: ${failed}`,
  );

  if (!failed) {
    throw new Error(
      `${name} should have failed.`,
    );
  }
}

const validPassOutput = JSON.stringify({
  schema_version: "1.0",
  reviewer_role: "subject_teacher",
  verdict: "pass",
  risk_level: "low",
  confidence_score: 0.98,

  checks: {
    answer_is_correct: true,
    single_correct_answer: true,
    question_is_complete: true,
    question_is_unambiguous: true,
    curriculum_fit: true,
    grade_fit: true,
    language_fit: true,
    terminology_fit: true,
    options_are_valid: true,
    distractors_are_valid: true,
    solve_time_is_reasonable: true,
    factual_accuracy: true,
    calculation_accuracy: true,
    unit_consistency: true,
  },

  correction_required: false,

  detected_errors: [],

  warnings: [],

  review_summary:
    "Soru matematiksel olarak tutarlı ve tek doğru cevaplıdır.",

  verification_details: {
    independent_solution_completed: true,
  },

  metadata: {
    smoke_test: true,
  },
});

expectSuccess(
  "1 valid pass output",
  validPassOutput,
);

expectFailure(
  "2 malformed JSON",
  "{not-json",
);

expectFailure(
  "3 invalid reviewer role",
  JSON.stringify({
    ...JSON.parse(validPassOutput),
    reviewer_role: "unknown_teacher",
  }),
);

expectFailure(
  "4 confidence above one",
  JSON.stringify({
    ...JSON.parse(validPassOutput),
    confidence_score: 1.5,
  }),
);

expectFailure(
  "5 correction required without proposal",
  JSON.stringify({
    ...JSON.parse(validPassOutput),
    verdict: "needs_correction",
    correction_required: true,
  }),
);

expectSuccess(
  "6 valid correction proposal",
  JSON.stringify({
    schema_version: "1.0",
    reviewer_role: "correction",
    verdict: "needs_correction",
    risk_level: "medium",
    confidence_score: 0.96,

    checks: {
      answer_is_correct: false,
      single_correct_answer: true,
      question_is_complete: true,
    },

    correction_required: true,

    detected_errors: [
      {
        issue_code: "WRONG_ANSWER_KEY",
        issue_category: "answer",
        severity: "high",
        field_name: "proposed_correct_answer",
        description:
          "Mevcut cevap anahtarı bağımsız çözümle uyuşmuyor.",
        evidence: {
          expected_answer: "C",
          received_answer: "B",
        },
        correction_recommended: true,
        blocks_publication: true,
      },
    ],

    warnings: [],

    review_summary:
      "Cevap anahtarında hata tespit edildi.",

    proposed_correction: {
      correct_answer: "C",
      solution: {
        final_answer: "C",
      },
      change_summary:
        "Cevap anahtarı B yerine C olarak düzeltilmelidir.",
      change_reasons: [
        "Bağımsız çözüm sonucu C seçeneğidir.",
      ],
      confidence_score: 0.99,
      requires_recheck: true,
    },

    metadata: {
      smoke_test: true,
    },
  }),
);

expectFailure(
  "7 invalid issue category",
  JSON.stringify({
    ...JSON.parse(validPassOutput),
    detected_errors: [
      {
        issue_code: "BAD_CATEGORY",
        issue_category: "not_a_real_category",
        severity: "high",
        description: "Invalid category test.",
        correction_recommended: false,
        blocks_publication: false,
      },
    ],
  }),
);

expectFailure(
  "8 invalid correction answer",
  JSON.stringify({
    schema_version: "1.0",
    reviewer_role: "correction",
    verdict: "needs_correction",
    risk_level: "medium",
    confidence_score: 0.95,
    checks: {},
    correction_required: true,
    detected_errors: [],
    warnings: [],
    review_summary: "Test",
    proposed_correction: {
      correct_answer: "F",
      confidence_score: 0.95,
      requires_recheck: true,
    },
  }),
);

expectSuccess(
  "9 markdown code fence",
  [
    "```json",
    validPassOutput,
    "```",
  ].join("\n"),
);

console.log(
  "TEACHER REVIEW PARSER TESTLERI BASARILI",
);