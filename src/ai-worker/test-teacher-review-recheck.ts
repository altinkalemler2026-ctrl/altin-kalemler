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
      `Expected pass during recheck, received ${parsedOutput.verdict}.`,
    );
  }

  if (
    parsedOutput.correction_required !==
    false
  ) {
    throw new Error(
      "Recheck should confirm that no further correction is required.",
    );
  }

  if (
    parsedOutput.checks.answer_is_correct !==
    true
  ) {
    throw new Error(
      "Recheck did not confirm the corrected answer.",
    );
  }

  await service.completeRecheckStage(
    REVIEW_RUN_ID,
    parsedOutput,
  );

  console.log(
    "Correction proposal yeniden kontrol edildi.",
  );

  console.log(
    "Düzeltilmiş cevap B doğrulandı.",
  );

  console.log(
    "Beklenen status: waiting_final_checker",
  );

  console.log(
    "Beklenen current_stage: final_checker",
  );

  console.log(
    "RECHECK TEST BASARILI",
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "RECHECK TEST BASARISIZ:",
    message,
  );

  process.exitCode = 1;
});