import { TeacherReviewService } from "./teacher-review-service.ts";
import { TestTeacherReviewProvider } from "./test-teacher-review-provider.ts";
import { parseTeacherReviewOutput } from "./teacher-review-parser.ts";

const REVIEW_RUN_ID =
  "5ebec132-7845-4d26-94d9-30c8047d350e";

async function main(): Promise<void> {
  const service =
    new TeacherReviewService();

  const provider =
    new TestTeacherReviewProvider();

  const providerOutput =
    await provider.reviewQuestion({
      reviewerRole:
        "correction",

      scenario:
        "wrong_answer_key",
    });

  const parsedOutput =
    parseTeacherReviewOutput(
      JSON.stringify(
        providerOutput,
      ),
    );

  await service.completeCorrectionStage(
    REVIEW_RUN_ID,
    parsedOutput,
  );

  console.log(
    "Correction aşaması tamamlandı.",
  );

  console.log(
    "Beklenen status: waiting_recheck",
  );

  console.log(
    "Beklenen current_stage: recheck",
  );

  console.log(
    "CORRECTION STAGE TEST BASARILI",
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "CORRECTION STAGE TEST BASARISIZ:",
    message,
  );

  process.exitCode = 1;
});