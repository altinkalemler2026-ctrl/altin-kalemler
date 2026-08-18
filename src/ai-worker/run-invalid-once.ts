import { executeProvider } from "./provider.ts";
import { SupabaseAiWorker } from "./supabase-worker.ts";
import { InvalidTestQuestionProvider } from "./invalid-test-provider.ts";
import { validateOutputAgainstJob } from "./job-output-validator.ts";

const WORKER_NAME =
  "altin-kalemler-invalid-retry-test-worker";

const LEASE_SECONDS =
  300;

async function main(): Promise<void> {
  const worker =
    new SupabaseAiWorker();

  const provider =
    new InvalidTestQuestionProvider();

  console.log(
    "Hatalı provider retry testi için kuyruk kontrol ediliyor...",
  );

  const claim =
    await worker.claimNextJob(
      WORKER_NAME,
      LEASE_SECONDS,
    );

  if (!claim.job_available) {
    console.log(
      "Kuyrukta uygun AI generation job yok.",
    );

    return;
  }

  console.log(
    "Job claim edildi:",
    claim.ai_job_id,
  );

  try {
    const execution =
      await executeProvider(
        provider,
        claim,
      );

    const jobValidation =
      validateOutputAgainstJob(
        claim,
        execution.output,
      );

    if (!jobValidation.success) {
      throw new Error(
        [
          "Intentional provider validation failure.",
          ...jobValidation.errors,
        ].join(" "),
      );
    }

    throw new Error(
      "TEST HATASI: Bilerek geçersiz provider çıktısı validator tarafından reddedilmedi.",
    );
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : String(error);

    console.log("");
    console.log(
      "Beklenen worker hatası yakalandı:",
    );

    console.log(message);

    const failureResult =
      await worker.failClaim(
        claim,
        "intentional_validation_failure",
        message,
        true,
      );

    console.log("");
    console.log(
      "Retry sonucu:",
    );

    console.log(
      JSON.stringify(
        failureResult,
        null,
        2,
      ),
    );

    console.log("");
    console.log(
      "INVALID PROVIDER RETRY TEST TAMAMLANDI",
    );
  }
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "Retry test runner başarısız:",
    message,
  );

  process.exitCode = 1;
});