import type {
  AiProviderContext,
  AiQuestionProvider,
  AiWorkerOutput,
} from "./types.ts";

export class TestQuestionProvider
  implements AiQuestionProvider
{
  readonly providerName = "test-provider";

  readonly modelName = "deterministic-test-model";

  readonly workerVersion = "worker-v1";

  readonly promptVersion = "test-prompt-v1";

  async generateQuestions(
    context: AiProviderContext,
  ): Promise<AiWorkerOutput> {
    const requestedCountValue =
      context.job.input_data[
        "requested_question_count"
      ];

    const requestedCount =
      typeof requestedCountValue === "number" &&
      Number.isInteger(requestedCountValue) &&
      requestedCountValue > 0
        ? requestedCountValue
        : 1;

    const questions =
      Array.from(
        {
          length: requestedCount,
        },
        (_, index) => {
          const firstNumber =
            12 + index;

          const secondNumber =
            8 + index;

          const correctTotal =
            firstNumber + secondNumber;

          return {
            client_question_id:
              `TEST-${context.job.ai_job_id}-${index + 1}`,

            question_text:
              `Bir kutuda ${firstNumber} kırmızı ve ${secondNumber} mavi kalem vardır. Kutuda toplam kaç kalem vardır?`,

            options: {
              A: String(
                correctTotal - 4,
              ),

              B: String(
                correctTotal - 2,
              ),

              C: String(
                correctTotal,
              ),

              D: String(
                correctTotal + 2,
              ),
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
                `${firstNumber} + ${secondNumber} = ${correctTotal}`,

              final_answer:
                "C",
            },

            analysis: {
              deterministic_test:
                true,

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
              generated_by:
                "TestQuestionProvider",

              smoke_test:
                true,

              production_ready:
                false,
            },
          };
        },
      );

    return {
      schema_version:
        "1.0",

      questions,
    };
  }
}