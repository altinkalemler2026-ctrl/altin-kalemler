import { TeacherReviewService } from "./teacher-review-service.ts";
import { TestTeacherReviewProvider } from "./test-teacher-review-provider.ts";
import { parseTeacherReviewOutput } from "./teacher-review-parser.ts";

const REVIEW_RUN_ID =
  "9fa6f03d-41f5-4c9a-acda-18d52f7dface";

const STAGING_QUESTION_ID =
  "4147d871-002f-4a17-8d6f-089f7cfa2028";

const PROFILE_CODE =
  "MATH-ERROR-HUNTER-V1";

async function main(): Promise<void> {
  const service =
    new TeacherReviewService();

  const provider =
    new TestTeacherReviewProvider();

  console.log(
    "Matematik Hata Avcısı profili yükleniyor...",
  );

  const profile =
    await service.getProfileByCode(
      PROFILE_CODE,
    );

  if (
    profile.direct_publication_allowed
  ) {
    throw new Error(
      "GÜVENLİK HATASI: Error Hunter AI direct publication yetkisine sahip.",
    );
  }

  const run = {
    id:
      REVIEW_RUN_ID,

    staging_question_id:
      STAGING_QUESTION_ID,

    subject_id:
      "430903f3-527e-4e12-b7e8-ac0afdb784aa",

    status:
      "waiting_error_hunter",

    current_stage:
      "error_hunter",
  };

  console.log(
    "Deterministic Hata Avcısı AI çalıştırılıyor...",
  );

  const providerOutput =
    await provider.reviewQuestion({
      reviewerRole:
        "error_hunter",
    });

  const parsedOutput =
    parseTeacherReviewOutput(
      JSON.stringify(
        providerOutput,
      ),
    );

  if (
    parsedOutput.reviewer_role !==
    profile.reviewer_role
  ) {
    throw new Error(
      [
        "Reviewer role mismatch.",
        `Profile: ${profile.reviewer_role}`,
        `Output: ${parsedOutput.reviewer_role}`,
      ].join(" "),
    );
  }

  if (
    parsedOutput.confidence_score <
    profile.minimum_confidence
  ) {
    throw new Error(
      [
        "Error Hunter confidence is below profile minimum.",
        `Minimum: ${profile.minimum_confidence}`,
        `Received: ${parsedOutput.confidence_score}`,
      ].join(" "),
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
    "Error Hunter review kaydedildi:",
    reviewId,
  );

  console.log("");
  console.log(
    "ERROR HUNTER DB TEST BASARILI",
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "ERROR HUNTER DB TEST BASARISIZ:",
    message,
  );

  process.exitCode = 1;
});