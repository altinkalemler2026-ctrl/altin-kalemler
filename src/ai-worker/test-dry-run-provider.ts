import {
  DryRunQuestionProvider,
} from "./dry-run-provider.ts";

import type {
  ClaimedAiJob,
} from "./types.ts";

const provider =
  new DryRunQuestionProvider();

const fakeJob: ClaimedAiJob = {
  status: "claimed",
  job_available: true,

  ai_job_id:
    "00000000-0000-0000-0000-000000000001",

  job_type:
    "question_generation",

  generation_spec_id:
    "00000000-0000-0000-0000-000000000002",

  competition_generation_request_id:
    "00000000-0000-0000-0000-000000000003",

  competition_factory_dispatch_id:
    "00000000-0000-0000-0000-000000000004",

  claim_token:
    "00000000-0000-0000-0000-000000000005",

  claimed_by:
    "local-provider-test",

  claimed_at:
    new Date().toISOString(),

  lease_expires_at:
    new Date(
      Date.now() + 300_000,
    ).toISOString(),

  attempt_count: 0,

  max_attempts: 3,

  input_data: {
    requested_question_count: 1,

    generation_requirements: {
      difficulty: "easy",
      cognitive_level: "application",
      question_type: "multiple_choice",

      visual_requirements: {
        requires_visual: false,
      },
    },

    curriculum_requirements: {
      grade_level: 5,

      subject_id:
        "430903f3-527e-4e12-b7e8-ac0afdb784aa",

      curriculum_version_id:
        "0675c13e-a27f-425a-8004-506a6ddbfe12",

      topic_id: null,
      subtopic_id: null,
      outcome_id: null,
    },

    solve_time_requirements: {
      minimum_seconds: 15,
      maximum_seconds: 45,
    },

    quality_requirements: {
      single_correct_answer_required:
        true,

      age_appropriate_language_required:
        true,

      independent_solution_required:
        true,
    },

    diversity_requirements: {
      avoid_repeated_stems:
        true,

      avoid_repeated_solution_patterns:
        true,
    },

    copyright_requirements: {
      original_generation_required:
        true,

      trivial_rewrite_forbidden:
        true,

      copyright_review_required:
        true,

      commercial_use_allowed:
        false,
    },

    review_requirements: {
      human_review_required:
        true,

      curriculum_review_required:
        true,

      originality_review_required:
        true,

      copyright_review_required:
        true,
    },
  },
};

async function main(): Promise<void> {
  const output =
    await provider.generateQuestions({
      job: fakeJob,
    });

  console.log("");
  console.log(
    "========================================",
  );

  console.log(
    "DRY-RUN PROVIDER LOCAL TEST BASARILI",
  );

  console.log(
    "========================================",
  );

  console.log(
    JSON.stringify(
      output,
      null,
      2,
    ),
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "DRY-RUN PROVIDER TEST HATASI:",
    message,
  );

  process.exitCode = 1;
});