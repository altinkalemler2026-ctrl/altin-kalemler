import type {
  AiProviderContext,
  AiQuestionProvider,
  AiWorkerOutput,
} from "./types.ts";

export class InvalidTestQuestionProvider
  implements AiQuestionProvider
{
  readonly providerName =
    "invalid-test-provider";

  readonly modelName =
    "deterministic-invalid-model";

  readonly workerVersion =
    "worker-v1";

  readonly promptVersion =
    "invalid-test-v1";

  async generateQuestions(
    _context: AiProviderContext,
  ): Promise<AiWorkerOutput> {
    return {
      schema_version:
        "1.0",

      questions: [
        {
          client_question_id:
            "INVALID-TEST-001",

          question_text:
            "Bu soru worker retry davranışını test etmek için bilerek job gereksinimine aykırı üretilmiştir.",

          options: {
            A: "10",
            B: "20",
            C: "30",
            D: "40",
          },

          correct_answer:
            "C",

          // Job easy isteyecek.
          // Burada bilerek hard döndürüyoruz.
          difficulty:
            "hard",

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
              "Bilerek geçersiz test çıktısıdır.",

            final_answer:
              "C",
          },

          analysis: {
            intentional_validation_failure:
              true,
          },

          metadata: {
            smoke_test:
              true,

            production_ready:
              false,
          },
        },
      ],
    };
  }
}