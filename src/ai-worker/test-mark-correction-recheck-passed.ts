import { TeacherReviewService } from "./teacher-review-service.ts";

const REVIEW_RUN_ID =
  "5ebec132-7845-4d26-94d9-30c8047d350e";

async function main(): Promise<void> {
  const service =
    new TeacherReviewService();

  await service.markCorrectionRecheckPassed(
    REVIEW_RUN_ID,
  );

  console.log(
    "Correction proposal recheck_passed olarak güncellendi.",
  );

  console.log(
    "MARK CORRECTION RECHECK PASSED TEST BASARILI",
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "MARK CORRECTION RECHECK PASSED TEST BASARISIZ:",
    message,
  );

  process.exitCode = 1;
});