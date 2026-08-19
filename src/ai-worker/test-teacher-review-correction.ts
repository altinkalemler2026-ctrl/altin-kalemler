import { TeacherReviewService } from "./teacher-review-service.ts";
import { TestTeacherReviewProvider } from "./test-teacher-review-provider.ts";
import { parseTeacherReviewOutput } from "./teacher-review-parser.ts";

const REVIEW_RUN_ID =
  "5ebec132-7845-4d26-94d9-30c8047d350e";

const STAGING_QUESTION_ID =
  "1fc0ec26-29b6-4033-aaba-42331a5c683f";

const MATHEMATICS_SUBJECT_ID =
  "430903f3-527e-4e12-b7e8-ac0afdb784aa";

const PROFILE_CODE =
  "MATH-CORRECTION-V1";

async function main(): Promise<void> {
  const service =
    new TeacherReviewService();

  const provider =
    new TestTeacherReviewProvider();

  const profile =
    await service.getProfileByCode(
      PROFILE_CODE,
    );

  const run = {
    id:
      REVIEW_RUN_ID,

    staging_question_id:
      STAGING_QUESTION_ID,

    subject_id:
      MATHEMATICS_SUBJECT_ID,

    status:
      "waiting_correction",

    current_stage:
      "correction",
  };

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

  if (
    parsedOutput.reviewer_role !==
    "correction"
  ) {
    throw new Error(
      "Expected correction reviewer role.",
    );
  }

  if (
    parsedOutput.correction_required !==
    true
  ) {
    throw new Error(
      "Correction AI should require a correction.",
    );
  }

  if (
    parsedOutput.proposed_correction
      ?.correct_answer !== "B"
  ) {
    throw new Error(
      "Correction AI did not propose B as the correct answer.",
    );
  }

  if (
    parsedOutput.proposed_correction
      ?.requires_recheck !== true
  ) {
    throw new Error(
      "Correction proposal should require recheck.",
    );
  }

  const reviewId =
    await service.saveReview(
      run,
      profile,
      parsedOutput,
      {
        providerName:
          provider.providerName,

        modelName:
          provider.modelName,

        promptVersion:
          provider.promptVersion,
      },
    );

  console.log(
    "Correction review kaydedildi:",
    reviewId,
  );

  console.log(
    "Önerilen değişiklik: C -> B",
  );

  console.log(
    "Staging otomatik değiştirilmedi.",
  );

  console.log(
    "CORRECTION AI TEST BASARILI",
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "CORRECTION AI TEST BASARISIZ:",
    message,
  );

  process.exitCode = 1;
});