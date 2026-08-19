import { TeacherReviewService } from "./teacher-review-service.ts";
import { TestTeacherReviewProvider } from "./test-teacher-review-provider.ts";
import { parseTeacherReviewOutput } from "./teacher-review-parser.ts";

const REVIEW_RUN_ID =
  "9fa6f03d-41f5-4c9a-acda-18d52f7dface";

async function main(): Promise<void> {
  const service =
    new TeacherReviewService();

  const provider =
    new TestTeacherReviewProvider();

  const providerOutput =
    await provider.reviewQuestion({
      reviewerRole:
        "error_hunter",
    });

  const parsedOutput =
    parseTeacherReviewOutput(
      JSON.stringify(providerOutput),
    );

  await service.completeErrorHunterStage(
    REVIEW_RUN_ID,
    parsedOutput,
  );

  console.log(
    "Error Hunter aşaması tamamlandı.",
  );

  console.log(
    "Beklenen sonraki aşama: final_checker",
  );

  console.log(
    "ERROR HUNTER STAGE TEST BASARILI",
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "ERROR HUNTER STAGE TEST BASARISIZ:",
    message,
  );

  process.exitCode = 1;
});