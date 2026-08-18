import {
  buildAiGenerationPrompt,
} from "./prompt-builder.ts";

import {
  parseAiWorkerOutput,
} from "./output-parser.ts";

import {
  validateOutputAgainstJob,
} from "./job-output-validator.ts";

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
      "Test provider çıktısı ham JSON olarak simüle edilecek.",
    );
    console.log(
      "========================================",
    );
    console.log("");

    const fallbackOutput =
      await this.fallbackProvider.generateQuestions(
        context,
      );

    const rawProviderText =
      JSON.stringify(
        fallbackOutput,
      );

    console.log(
      "Ham provider çıktısı alındı.",
    );

    const parsed =
      parseAiWorkerOutput(
        rawProviderText,
      );

    if (!parsed.success) {
      throw new Error(
        [
          "AI provider output validation failed.",
          ...parsed.errors,
        ].join(" "),
      );
    }

    console.log(
      "Ham provider çıktısı başarıyla parse ve validate edildi.",
    );

    const jobValidation =
      validateOutputAgainstJob(
        context.job,
        parsed.output,
      );

    if (!jobValidation.success) {
      throw new Error(
        [
          "AI provider output does not match the requested job.",
          ...jobValidation.errors,
        ].join(" "),
      );
    }

    console.log(
      "Provider çıktısı job gereksinimleriyle uyumlu.",
    );

    return parsed.output;
  }
}