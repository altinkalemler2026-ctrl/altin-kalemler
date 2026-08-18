import { SupabaseAiWorker } from "./supabase-worker.ts";

const FIRST_WORKER =
  "altin-kalemler-lease-test-worker-a";

const SECOND_WORKER =
  "altin-kalemler-lease-test-worker-b";

const LEASE_SECONDS = 30;

const WAIT_MILLISECONDS = 32_000;

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
      "Test job bulunamadı.",
    );
  }

  console.log(
    "İlk claim başarılı:",
    firstClaim.ai_job_id,
  );

  console.log(
    "İlk claim token:",
    firstClaim.claim_token,
  );

  console.log(
    "İlk attempt_count:",
    firstClaim.attempt_count,
  );

  console.log("");
  console.log(
    `${LEASE_SECONDS} saniyelik lease süresinin dolması bekleniyor...`,
  );

  await sleep(
    WAIT_MILLISECONDS,
  );

  console.log("");
  console.log(
    "2. worker aynı job'ı geri almaya çalışıyor...",
  );

  const secondClaim =
    await worker.claimNextJob(
      SECOND_WORKER,
      LEASE_SECONDS,
    );

  if (!secondClaim.job_available) {
    throw new Error(
      "Lease süresi dolmasına rağmen ikinci worker job'ı claim edemedi.",
    );
  }

  if (
    secondClaim.ai_job_id !==
    firstClaim.ai_job_id
  ) {
    throw new Error(
      [
        "İkinci worker farklı bir job claim etti.",
        `İlk job: ${firstClaim.ai_job_id}`,
        `İkinci job: ${secondClaim.ai_job_id}`,
      ].join(" "),
    );
  }

  if (
    secondClaim.claim_token ===
    firstClaim.claim_token
  ) {
    throw new Error(
      "Lease recovery sonrasında claim token değişmedi.",
    );
  }

  console.log(
    "İkinci claim başarılı:",
    secondClaim.ai_job_id,
  );

  console.log(
    "Yeni claim token:",
    secondClaim.claim_token,
  );

  console.log(
    "Yeni attempt_count:",
    secondClaim.attempt_count,
  );

  console.log("");
  console.log(
    "Eski claim token ile lease yenileme deneniyor...",
  );

  let oldClaimRejected = false;

  try {
    await worker.renewLease(
      firstClaim,
      LEASE_SECONDS,
    );
  } catch (error) {
    oldClaimRejected = true;

    const message =
      error instanceof Error
        ? error.message
        : String(error);

    console.log(
      "Eski claim beklendiği gibi reddedildi:",
      message,
    );
  }

  if (!oldClaimRejected) {
    throw new Error(
      "GÜVENLİK HATASI: Eski claim token hâlâ lease yenileyebiliyor.",
    );
  }

  console.log("");
  console.log(
    "Yeni claim ile lease yenileme deneniyor...",
  );

  const renewed =
    await worker.renewLease(
      secondClaim,
      LEASE_SECONDS,
    );

  console.log(
    "Yeni claim lease yenileme sonucu:",
  );

  console.log(
    JSON.stringify(
      renewed,
      null,
      2,
    ),
  );

  console.log("");
  console.log(
    "LEASE RECOVERY TEST BASARILI",
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "LEASE RECOVERY TEST BASARISIZ:",
    message,
  );

  process.exitCode = 1;
});