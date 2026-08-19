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
        "final_checker",

      scenario:
        "wrong_answer_key",
    });

  const parsedOutput =
    parseTeacherReviewOutput(
      JSON.stringify(
        providerOutput,
      ),
    );

  if (
    parsedOutput.verdict !== "pass"
  ) {
    throw new Error(
      `Expected final checker pass, received ${parsedOutput.verdict}.`,
    );
  }

  if (
    parsedOutput.correction_required !==
    false
  ) {
    throw new Error(
      "Final checker should confirm that no further correction is required.",
    );
  }

  if (
    parsedOutput.checks.answer_is_correct !==
    true
  ) {
    throw new Error(
      "Final checker did not confirm the corrected answer.",
    );
  }

  await service.completeFinalCheckerStage(
    REVIEW_RUN_ID,
    parsedOutput,
  );

  console.log(
    "Düzeltilmiş soru Final Checker kontrolünden geçti.",
  );

  console.log(
    "Beklenen status: ai_review_passed",
  );

  console.log(
    "Beklenen current_stage: complete",
  );

  console.log(
    "CORRECTED QUESTION FINAL CHECKER TEST BASARILI",
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "CORRECTED QUESTION FINAL CHECKER TEST BASARISIZ:",
    message,
  );

  process.exitCode = 1;
});