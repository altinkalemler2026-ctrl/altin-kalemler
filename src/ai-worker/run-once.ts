import { executeProvider } from "./provider.ts";
import { SupabaseAiWorker } from "./supabase-worker.ts";
import { TestQuestionProvider } from "./test-provider.ts";

const WORKER_NAME =
  "altin-kalemler-local-test-worker";

const LEASE_SECONDS =
  300;

async function main(): Promise<void> {
  const worker =
    new SupabaseAiWorker();

  const provider =
    new TestQuestionProvider();

  console.log(
    "AI worker kuyruğu kontrol ediliyor...",
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

  let workerOutputId: string;

  try {
    const execution =
      await executeProvider(
        provider,
        claim,
      );

    console.log(
      "Test provider çıktısı üretildi.",
    );

    workerOutputId =
      await worker.registerWorkerOutput({
        aiJobId:
          claim.ai_job_id,

        output:
          execution.output,

        providerName:
          execution.providerName,

        modelName:
          execution.modelName,

        promptVersion:
          execution.promptVersion,

        workerVersion:
          execution.workerVersion,
      });

    console.log(
      "Worker output kaydedildi:",
      workerOutputId,
    );

    const ingestionResult =
      await worker.ingestWorkerOutput(
        workerOutputId,
      );

    console.log(
      "Ingestion tamamlandı:",
    );

    console.log(
      JSON.stringify(
        ingestionResult,
        null,
        2,
      ),
    );
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : String(error);

    console.error(
      "Worker execution hatası:",
      message,
    );

    try {
      const failureResult =
        await worker.failClaim(
          claim,
          "local_worker_execution_failed",
          message,
          true,
        );

      console.error(
        "Job failure sonucu:",
      );

      console.error(
        JSON.stringify(
          failureResult,
          null,
          2,
        ),
      );
    } catch (failureError) {
      const failureMessage =
        failureError instanceof Error
          ? failureError.message
          : String(failureError);

      console.error(
        "Job failure kaydı da başarısız oldu:",
        failureMessage,
      );
    }

    process.exitCode = 1;

    return;
  }

  // -------------------------------------------------------
  // Reporting:
  //
  // Job başarıyla ingest edildikten sonra rapor alınamaması,
  // generation job'ın başarısız olduğu anlamına gelmez.
  // Bu nedenle report hatası fail_ai_job_claim çağırmaz.
  // -------------------------------------------------------

  try {
    const report =
      await worker.getWorkerOutputReport(
        workerOutputId,
      );

    console.log(
      "Worker output raporu:",
    );

    console.log(
      JSON.stringify(
        report,
        null,
        2,
      ),
    );
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : String(error);

    console.warn(
      "Worker output raporu alınamadı:",
      message,
    );

    console.warn(
      "Job ingestion daha önce başarıyla tamamlandı; job başarısız sayılmadı.",
    );
  }
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "AI worker başlatılamadı:",
    message,
  );

  process.exitCode = 1;
});