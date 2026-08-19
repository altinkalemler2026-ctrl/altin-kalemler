import { TeacherReviewService } from "./teacher-review-service.ts";
import { TestTeacherReviewProvider } from "./test-teacher-review-provider.ts";
import { parseTeacherReviewOutput } from "./teacher-review-parser.ts";

const STAGING_QUESTION_ID =
  "1fc0ec26-29b6-4033-aaba-42331a5c683f";

const MATHEMATICS_SUBJECT_ID =
  "430903f3-527e-4e12-b7e8-ac0afdb784aa";

const PROFILE_CODE =
  "MATH-SUBJECT-TEACHER-V1";

async function main(): Promise<void> {
  const service =
    new TeacherReviewService();

  const provider =
    new TestTeacherReviewProvider();

  const profile =
    await service.getProfileByCode(
      PROFILE_CODE,
    );

  console.log(
    "Yanlış cevaplı soru için review run oluşturuluyor...",
  );

  const run =
    await service.createReviewRun(
      STAGING_QUESTION_ID,
      MATHEMATICS_SUBJECT_ID,
    );

  console.log(
    "Review run id:",
    run.id,
  );

  const providerOutput =
    await provider.reviewQuestion({
      reviewerRole:
        "subject_teacher",

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
    parsedOutput.verdict !==
    "needs_correction"
  ) {
    throw new Error(
      `Expected needs_correction, received ${parsedOutput.verdict}.`,
    );
  }

  if (
    parsedOutput.correction_required !==
    true
  ) {
    throw new Error(
      "Teacher AI should require correction.",
    );
  }

  if (
    parsedOutput.checks.answer_is_correct !==
    false
  ) {
    throw new Error(
      "Teacher AI did not detect the wrong answer key.",
    );
  }

  if (
    parsedOutput.proposed_correction
      ?.correct_answer !== "B"
  ) {
    throw new Error(
      "Teacher AI did not propose B as the corrected answer.",
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
    "Teacher review kaydedildi:",
    reviewId,
  );

  await service.completeSubjectTeacherStage(
    run.id,
    parsedOutput,
  );

  console.log(
    "Yanlış cevap anahtarı tespit edildi.",
  );

  console.log(
    "Önerilen doğru cevap: B",
  );

  console.log(
    "WRONG ANSWER TEACHER TEST BASARILI",
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "WRONG ANSWER TEACHER TEST BASARISIZ:",
    message,
  );

  process.exitCode = 1;
});