import {
  validateOutputAgainstJob,
} from "./job-output-validator.ts";

import type {
  AiWorkerOutput,
  ClaimedAiJob,
} from "./types.ts";

const baseJob: ClaimedAiJob = {
  status: "claimed",
  job_available: true,

  ai_job_id:
    "00000000-0000-0000-0000-000000000101",

  job_type:
    "question_generation",

  generation_spec_id:
    "00000000-0000-0000-0000-000000000102",

  competition_generation_request_id:
    "00000000-0000-0000-0000-000000000103",

  competition_factory_dispatch_id:
    "00000000-0000-0000-0000-000000000104",

  claim_token:
    "00000000-0000-0000-0000-000000000105",

  claimed_by:
    "validator-local-test",

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
    },

    solve_time_requirements: {
      minimum_seconds: 15,
      maximum_seconds: 45,
    },
  },
};

const validQuestion = {
  client_question_id:
    "VALIDATOR-LOCAL-001",

  question_text:
    "Bir kutuda 12 kırmızı ve 8 mavi kalem vardır. Kutuda toplam kaç kalem vardır?",

  options: {
    A: "16",
    B: "18",
    C: "20",
    D: "22",
  },

  correct_answer:
    "C" as const,

  difficulty:
    "easy" as const,

  cognitive_type:
    "application" as const,

  primary_question_type:
    "multiple_choice",

  is_new_generation:
    true,

  has_visual:
    false,

  estimated_solve_time_seconds:
    20,

  solution: {
    explanation:
      "12 + 8 = 20",

    final_answer:
      "C",
  },
};

function runTest(
  title: string,
  output: AiWorkerOutput,
  expectedSuccess: boolean,
): void {
  console.log("");
  console.log(
    "========================================",
  );
  console.log(title);
  console.log(
    "========================================",
  );

  const result =
    validateOutputAgainstJob(
      baseJob,
      output,
    );

  console.log(
    JSON.stringify(
      result,
      null,
      2,
    ),
  );

  if (
    result.success !==
    expectedSuccess
  ) {
    throw new Error(
      `${title} beklenen sonucu vermedi.`,
    );
  }
}


// =========================================================
// TEST 1
// Tam uyumlu çıktı
// Beklenen: success = true
// =========================================================

runTest(
  "TEST 1 - TAM UYUMLU",
  {
    schema_version: "1.0",

    questions: [
      validQuestion,
    ],
  },
  true,
);


// =========================================================
// TEST 2
// Job 1 soru istiyor,
// provider 2 soru döndürüyor.
// Beklenen: success = false
// =========================================================

runTest(
  "TEST 2 - YANLIS SORU SAYISI",
  {
    schema_version: "1.0",

    questions: [
      validQuestion,

      {
        ...validQuestion,

        client_question_id:
          "VALIDATOR-LOCAL-002",
      },
    ],
  },
  false,
);


// =========================================================
// TEST 3
// Job easy istiyor,
// provider hard döndürüyor.
// Beklenen: success = false
// =========================================================

runTest(
  "TEST 3 - YANLIS ZORLUK",
  {
    schema_version: "1.0",

    questions: [
      {
        ...validQuestion,

        difficulty:
          "hard" as const,
      },
    ],
  },
  false,
);


// =========================================================
// TEST 4
// Job application istiyor,
// provider comprehension döndürüyor.
// Beklenen: success = false
// =========================================================

runTest(
  "TEST 4 - YANLIS BILISSEL SEVIYE",
  {
    schema_version: "1.0",

    questions: [
      {
        ...validQuestion,

        cognitive_type:
          "comprehension" as const,
      },
    ],
  },
  false,
);


// =========================================================
// TEST 5
// Job multiple_choice istiyor,
// provider başka tip döndürüyor.
// Beklenen: success = false
// =========================================================

runTest(
  "TEST 5 - YANLIS SORU TIPI",
  {
    schema_version: "1.0",

    questions: [
      {
        ...validQuestion,

        primary_question_type:
          "open_ended",
      },
    ],
  },
  false,
);


// =========================================================
// TEST 6
// Minimum süre 15 saniye,
// provider 10 saniye döndürüyor.
// Beklenen: success = false
// =========================================================

runTest(
  "TEST 6 - SURE MINIMUM ALTINDA",
  {
    schema_version: "1.0",

    questions: [
      {
        ...validQuestion,

        estimated_solve_time_seconds:
          10,
      },
    ],
  },
  false,
);


// =========================================================
// TEST 7
// Maksimum süre 45 saniye,
// provider 60 saniye döndürüyor.
// Beklenen: success = false
// =========================================================

runTest(
  "TEST 7 - SURE MAKSIMUM USTUNDE",
  {
    schema_version: "1.0",

    questions: [
      {
        ...validQuestion,

        estimated_solve_time_seconds:
          60,
      },
    ],
  },
  false,
);


// =========================================================
// TEST 8
// Süre job tarafından istendiği halde
// provider süre vermiyor.
// Beklenen: success = false
// =========================================================

const {
  estimated_solve_time_seconds:
    _removedSolveTime,
  ...questionWithoutSolveTime
} = validQuestion;

runTest(
  "TEST 8 - SURE EKSIK",
  {
    schema_version: "1.0",

    questions: [
      questionWithoutSolveTime,
    ],
  },
  false,
);


// =========================================================
// TEST 9
// Job yeni üretim istiyor,
// provider false döndürüyor.
// Beklenen: success = false
// =========================================================

const jobWithNewGenerationRequirement: ClaimedAiJob = {
  ...baseJob,

  input_data: {
    ...baseJob.input_data,

    generation_requirements: {
      difficulty: "easy",
      cognitive_level: "application",
      question_type: "multiple_choice",
      is_new_generation: true,
    },
  },
};

console.log("");
console.log(
  "========================================",
);
console.log(
  "TEST 9 - YANLIS NEW GENERATION",
);
console.log(
  "========================================",
);

const newGenerationResult =
  validateOutputAgainstJob(
    jobWithNewGenerationRequirement,
    {
      schema_version: "1.0",

      questions: [
        {
          ...validQuestion,

          is_new_generation:
            false,
        },
      ],
    },
  );

console.log(
  JSON.stringify(
    newGenerationResult,
    null,
    2,
  ),
);

if (
  newGenerationResult.success !==
  false
) {
  throw new Error(
    "TEST 9 beklenen sonucu vermedi.",
  );
}


// =========================================================
// TEST 10
// Job görsel istemiyor,
// provider has_visual = true döndürüyor.
// Beklenen: success = false
// =========================================================

const jobWithoutVisual: ClaimedAiJob = {
  ...baseJob,

  input_data: {
    ...baseJob.input_data,

    generation_requirements: {
      difficulty: "easy",
      cognitive_level: "application",
      question_type: "multiple_choice",

      visual_requirements: {
        requires_visual:
          false,
      },
    },
  },
};

console.log("");
console.log(
  "========================================",
);
console.log(
  "TEST 10 - YANLIS VISUAL DURUMU",
);
console.log(
  "========================================",
);

const visualResult =
  validateOutputAgainstJob(
    jobWithoutVisual,
    {
      schema_version: "1.0",

      questions: [
        {
          ...validQuestion,

          has_visual:
            true,
        },
      ],
    },
  );

console.log(
  JSON.stringify(
    visualResult,
    null,
    2,
  ),
);

if (
  visualResult.success !==
  false
) {
  throw new Error(
    "TEST 10 beklenen sonucu vermedi.",
  );
}


// =========================================================
// TEST 11
// correct_answer = C
// solution.final_answer = B
// Beklenen: success = false
// =========================================================

console.log("");
console.log(
  "========================================",
);
console.log(
  "TEST 11 - COZUM CEVABI UYUSMUYOR",
);
console.log(
  "========================================",
);

const finalAnswerResult =
  validateOutputAgainstJob(
    baseJob,
    {
      schema_version: "1.0",

      questions: [
        {
          ...validQuestion,

          solution: {
            explanation:
              "12 + 8 = 20",

            final_answer:
              "B",
          },
        },
      ],
    },
  );

console.log(
  JSON.stringify(
    finalAnswerResult,
    null,
    2,
  ),
);

if (
  finalAnswerResult.success !==
  false
) {
  throw new Error(
    "TEST 11 beklenen sonucu vermedi.",
  );
}


// =========================================================
// TÜM TESTLER TAMAMLANDI
// =========================================================

console.log("");
console.log(
  "========================================",
);
console.log(
  "JOB OUTPUT VALIDATOR TESTLERI BASARILI",
);
console.log(
  "========================================",
);