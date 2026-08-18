import {
  parseAiWorkerOutput,
} from "./output-parser.ts";

function printResult(
  title: string,
  rawText: string,
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
    parseAiWorkerOutput(
      rawText,
    );

  console.log(
    JSON.stringify(
      result,
      null,
      2,
    ),
  );
}


// =========================================================
// TEST 1
// Geçerli JSON
// Beklenen: success = true
// =========================================================

const validJson =
  JSON.stringify(
    {
      schema_version:
        "1.0",

      questions: [
        {
          client_question_id:
            "LOCAL-PARSER-001",

          question_text:
            "Bir kutuda 12 kırmızı ve 8 mavi kalem vardır. Kutuda toplam kaç kalem vardır?",

          options: {
            A: "18",
            B: "19",
            C: "20",
            D: "21",
          },

          correct_answer:
            "C",

          difficulty:
            "easy",

          cognitive_type:
            "application",

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

          analysis: {
            grade_fit_requires_review:
              true,

            curriculum_fit_requires_review:
              true,

            originality_requires_review:
              true,

            copyright_review_required:
              true,
          },

          metadata: {
            local_parser_test:
              true,
          },
        },
      ],
    },
    null,
    2,
  );


// =========================================================
// TEST 2
// Bozuk JSON
// Beklenen: success = false
// =========================================================

const invalidJson =
  `{
    "schema_version": "1.0",
    "questions": [
      {
        "question_text": "Bu JSON kasıtlı olarak bozuktur."
        "options": {}
      }
    ]
  }`;


// =========================================================
// TEST 3
// Eksik zorunlu seçenek
// Beklenen: success = false
// options.D eksik.
// =========================================================

const missingOptionJson =
  JSON.stringify(
    {
      schema_version:
        "1.0",

      questions: [
        {
          question_text:
            "Bir sepette 10 elma vardır. Sepete 5 elma daha eklenirse toplam kaç elma olur?",

          options: {
            A: "12",
            B: "13",
            C: "15",
          },

          correct_answer:
            "C",

          difficulty:
            "easy",

          cognitive_type:
            "application",
        },
      ],
    },
    null,
    2,
  );


// =========================================================
// TEST 4
// Markdown kod bloğu içinde geçerli JSON
// Parser fence'i kaldırmalı.
// Beklenen: success = true
// =========================================================

const markdownWrappedJson =
  [
    "```json",
    validJson,
    "```",
  ].join("\n");


// =========================================================
// TEST 5
// Doğru cevap E ama E seçeneği yok.
// Beklenen: success = false
// =========================================================

const missingCorrectOptionJson =
  JSON.stringify(
    {
      schema_version:
        "1.0",

      questions: [
        {
          question_text:
            "20 sayısının yarısı aşağıdakilerden hangisidir?",

          options: {
            A: "5",
            B: "8",
            C: "10",
            D: "12",
          },

          correct_answer:
            "E",

          difficulty:
            "easy",

          cognitive_type:
            "learning",
        },
      ],
    },
    null,
    2,
  );


// =========================================================
// TESTLERİ ÇALIŞTIR
// =========================================================

printResult(
  "TEST 1 - GECERLI JSON",
  validJson,
);

printResult(
  "TEST 2 - BOZUK JSON",
  invalidJson,
);

printResult(
  "TEST 3 - EKSIK SECENEK",
  missingOptionJson,
);

printResult(
  "TEST 4 - MARKDOWN FENCE",
  markdownWrappedJson,
);

printResult(
  "TEST 5 - DOGRU CEVAP SECENEGI YOK",
  missingCorrectOptionJson,
);