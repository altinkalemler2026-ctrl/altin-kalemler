import { TeacherReviewService } from "./teacher-review-service.ts";
import { TestTeacherReviewProvider } from "./test-teacher-review-provider.ts";
import { parseTeacherReviewOutput } from "./teacher-review-parser.ts";

const STAGING_QUESTION_ID =
  "4147d871-002f-4a17-8d6f-089f7cfa2028";

const MATHEMATICS_SUBJECT_ID =
  "430903f3-527e-4e12-b7e8-ac0afdb784aa";

const PROFILE_CODE =
  "MATH-SUBJECT-TEACHER-V1";

async function main(): Promise<void> {
  const service =
    new TeacherReviewService();

  const provider =
    new TestTeacherReviewProvider();

  console.log(
    "Matematik Öğretmen AI profili yükleniyor...",
  );

  const profile =
    await service.getProfileByCode(
      PROFILE_CODE,
    );

  console.log(
    "Profil:",
    profile.profile_code,
  );

  if (
    profile.direct_publication_allowed
  ) {
    throw new Error(
      "GÜVENLİK HATASI: Teacher AI direct publication yetkisine sahip.",
    );
  }

  console.log(
    "Teacher review run oluşturuluyor...",
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

  console.log(
    "Deterministic Matematik Öğretmen AI çalıştırılıyor...",
  );

  const providerOutput =
    await provider.reviewQuestion({
      reviewerRole:
        "subject_teacher",
    });

  /*
   * Gerçek bir AI sağlayıcısında sonuç metin olarak geleceği için,
   * burada JSON stringify + parser ile aynı sınırı simüle ediyoruz.
   */
  const rawOutput =
    JSON.stringify(
      providerOutput,
    );

  const parsedOutput =
    parseTeacherReviewOutput(
      rawOutput,
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
        "Teacher AI confidence is below profile minimum.",
        `Minimum: ${profile.minimum_confidence}`,
        `Received: ${parsedOutput.confidence_score}`,
      ].join(" "),
    );
  }

  console.log(
    "Teacher AI çıktısı doğrulandı.",
  );

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
    "Subject teacher aşaması tamamlandı.",
  );

  console.log("");
  console.log(
    "Beklenen sonraki aşama: error_hunter",
  );

  console.log("");
  console.log(
    "TEACHER REVIEW DB TEST BASARILI",
  );
}

main().catch((error) => {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  console.error(
    "TEACHER REVIEW DB TEST BASARISIZ:",
    message,
  );

  process.exitCode = 1;
});