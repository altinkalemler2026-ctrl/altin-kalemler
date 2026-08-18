import { LeaseHeartbeat } from "./lease-heartbeat.ts";
import { SupabaseAiWorker } from "./supabase-worker.ts";

const FIRST_WORKER =
  "altin-kalemler-heartbeat-test-worker-a";

const SECOND_WORKER =
  "altin-kalemler-heartbeat-test-worker-b";

const LEASE_SECONDS = 30;

const HEARTBEAT_INTERVAL_MILLISECONDS =
  10_000;

const TOTAL_WAIT_MILLISECONDS =
  42_000;

function sleep(
  milliseconds: number,
): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

async function main(): Promise<void> {
  const worker =
    new SupabaseAiWorker();

  console.log(
    "1. worker job claim ediyor...",
  );

  const firstClaim =
    await worker.claimNextJob(
      FIRST_WORKER,
      LEASE_SECONDS,
    );

  if (!firstClaim.job_available) {
    throw new Error(
      "Heartbeat test job bulunamadı.",
    );
  }

  console.log(
    "İlk claim başarılı:",
    firstClaim.ai_job_id,
  );

  console.log(
    "İlk attempt_count:",
    firstClaim.attempt_count,
  );

  const heartbeat =
    new LeaseHeartbeat(
      worker,
      firstClaim,
      {
        leaseSeconds:
          LEASE_SECONDS,

        heartbeatIntervalMilliseconds:
          HEARTBEAT_INTERVAL_MILLISECONDS,
      },
    );

  console.log("");
  console.log(
    "Heartbeat başlatılıyor...",
  );

  heartbeat.start();

  console.log(
    `${TOTAL_WAIT_MILLISECONDS / 1000} saniye bekleniyor...`,
  );

  await sleep(
    TOTAL_WAIT_MILLISECONDS,
  );

  heartbeat.assertHealthy();

  console.log("");
  console.log(
    "2. worker aynı job'ı claim etmeye çalışıyor...",
  );

  const secondClaim =
    await worker.claimNextJob(
      SECOND_WORKER,
      LEASE_SECONDS,
    );

  if (secondClaim.job_available) {
    await heartbeat.stop();

    throw new Error(
      [
        "GÜVENLİK HATASI:",
        "Heartbeat çalışırken ikinci worker job claim edebildi.",
        `Claim edilen job: ${secondClaim.ai_job_id}`,
      ].join(" "),
    );
  }

  console.log(
    "İkinci worker job alamadı. Beklenen davranış.",
  );

  heartbeat.assertHealthy();

  console.log("");
  console.log(
    "Heartbeat durduruluyor...",
  );

  await heartbeat.stop();

  heartbeat.assertHealthy();

  console.log("");
  console.log(
    "HEARTBEAT TEST BASARILI",
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "HEARTBEAT TEST BASARISIZ:",
    message,
  );

  process.exitCode = 1;
});