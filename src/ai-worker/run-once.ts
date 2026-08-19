import { DryRunQuestionProvider } from "./dry-run-provider.ts";
import { LeaseHeartbeat } from "./lease-heartbeat.ts";
import { executeProvider } from "./provider.ts";
import { SupabaseAiWorker } from "./supabase-worker.ts";

const WORKER_NAME =
  "altin-kalemler-local-dry-run-worker";

const LEASE_SECONDS = 300;

const HEARTBEAT_INTERVAL_MILLISECONDS =
  120_000;

async function main(): Promise<void> {
  const worker =
    new SupabaseAiWorker();

  const provider =
    new DryRunQuestionProvider();

  console.log(
    "AI worker kuyruk kontrolü yapılıyor...",
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
    "AI job claim edildi:",
    claim.ai_job_id,
  );

  const heartbeat =
    new LeaseHeartbeat(
      worker,
      claim,
      {
        leaseSeconds:
          LEASE_SECONDS,

        heartbeatIntervalMilliseconds:
          HEARTBEAT_INTERVAL_MILLISECONDS,
      },
    );

  heartbeat.start();

  try {
    const execution =
      await executeProvider(
        provider,
        claim,
      );

    heartbeat.assertHealthy();

    const workerOutputId =
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

    heartbeat.assertHealthy();

    console.log(
      "Worker output kaydedildi:",
      workerOutputId,
    );

    const ingestion =
      await worker.ingestWorkerOutput(
        workerOutputId,
      );

    heartbeat.assertHealthy();

    console.log(
      "Worker output staging'e işlendi:",
      ingestion,
    );

    await heartbeat.stop();

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
    } catch (reportError) {
      const message =
        reportError instanceof Error
          ? reportError.message
          : String(reportError);

      console.error(
        "Worker output raporu alınamadı:",
        message,
      );
    }
  } catch (error) {
    await heartbeat.stop();

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

      console.log(
        "AI job failure sonucu:",
      );

      console.log(
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
        "AI job failure kaydı başarısız:",
        failureMessage,
      );
    }

    process.exitCode = 1;
  }
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "Worker başlatılamadı:",
    message,
  );

  process.exitCode = 1;
});