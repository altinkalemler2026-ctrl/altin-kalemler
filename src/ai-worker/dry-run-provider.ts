import {
  buildAiGenerationPrompt,
} from "./prompt-builder.ts";

import {
  TestQuestionProvider,
} from "./test-provider.ts";

import type {
  AiProviderContext,
  AiQuestionProvider,
  AiWorkerOutput,
} from "./types.ts";

export class DryRunQuestionProvider
  implements AiQuestionProvider
{
  readonly providerName =
    "dry-run-provider";

  readonly modelName =
    "no-external-api";

  readonly workerVersion =
    "worker-v1";

  readonly promptVersion =
    "prompt-builder-v1";

  private readonly fallbackProvider =
    new TestQuestionProvider();

  async generateQuestions(
    context: AiProviderContext,
  ): Promise<AiWorkerOutput> {
    const prompt =
      buildAiGenerationPrompt(
        context.job,
      );

    console.log("");
    console.log(
      "========================================",
    );
    console.log(
      "DRY-RUN AI PROMPT",
    );
    console.log(
      "========================================",
    );

    console.log("");
    console.log(
      "--- SYSTEM PROMPT ---",
    );
    console.log(
      prompt.systemPrompt,
    );

    console.log("");
    console.log(
      "--- USER PROMPT ---",
    );
    console.log(
      prompt.userPrompt,
    );

    console.log("");
    console.log(
      "========================================",
    );
    console.log(
      "Harici AI API çağrısı yapılmadı.",
    );
    console.log(
      "Ücret oluşmadı.",
    );
    console.log(
      "Test çıktısı kullanılacak.",
    );
    console.log(
      "========================================",
    );
    console.log("");

    return this.fallbackProvider.generateQuestions(
      context,
    );
  }
}