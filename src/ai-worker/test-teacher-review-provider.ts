import type {
  TeacherReviewOutput,
  TeacherReviewRole,
} from "./teacher-review-types.ts";

export type TestTeacherReviewProviderContext = {
  reviewerRole: TeacherReviewRole;

  scenario?:
    | "valid_question"
    | "wrong_answer_key";
};

export class TestTeacherReviewProvider {
  readonly providerName =
    "test-teacher-review-provider";

  readonly modelName =
    "deterministic-teacher-review-model";

  readonly promptVersion =
    "teacher-review-test-v2";

  async reviewQuestion(
    context: TestTeacherReviewProviderContext,
  ): Promise<TeacherReviewOutput> {
    const scenario =
      context.scenario ??
      "valid_question";

    if (
      scenario === "wrong_answer_key"
    ) {
      return this.reviewWrongAnswerScenario(
        context.reviewerRole,
      );
    }

    return this.reviewValidScenario(
      context.reviewerRole,
    );
  }

  private reviewValidScenario(
    reviewerRole: TeacherReviewRole,
  ): TeacherReviewOutput {
    if (
      reviewerRole ===
      "subject_teacher"
    ) {
      return {
        schema_version: "1.0",

        reviewer_role:
          "subject_teacher",

        verdict:
          "pass",

        risk_level:
          "low",

        confidence_score:
          0.98,

        checks: {
          answer_is_correct:
            true,

          solution_is_correct:
            true,

          single_correct_answer:
            true,

          question_is_complete:
            true,

          question_is_unambiguous:
            true,

          curriculum_fit:
            true,

          grade_fit:
            true,

          language_fit:
            true,

          terminology_fit:
            true,

          options_are_valid:
            true,

          distractors_are_valid:
            true,

          solve_time_is_reasonable:
            true,

          factual_accuracy:
            true,

          calculation_accuracy:
            true,

          unit_consistency:
            true,
        },

        correction_required:
          false,

        detected_errors:
          [],

        warnings:
          [],

        review_summary:
          "Deterministic Matematik Öğretmen AI testi: soru kontrollerden geçti.",

        verification_details: {
          independent_solution_completed:
            true,

          answer_key_not_trusted:
            true,
        },

        metadata: {
          smoke_test:
            true,

          production_ready:
            false,
        },
      };
    }

    if (
      reviewerRole ===
      "error_hunter"
    ) {
      return {
        schema_version: "1.0",

        reviewer_role:
          "error_hunter",

        verdict:
          "pass",

        risk_level:
          "low",

        confidence_score:
          0.97,

        checks: {
          answer_is_correct:
            true,

          single_correct_answer:
            true,

          question_is_complete:
            true,

          question_is_unambiguous:
            true,

          options_are_valid:
            true,

          distractors_are_valid:
            true,

          factual_accuracy:
            true,

          calculation_accuracy:
            true,

          unit_consistency:
            true,
        },

        correction_required:
          false,

        detected_errors:
          [],

        warnings:
          [],

        review_summary:
          "Deterministic Hata Avcısı AI testi: yayın engelleyici hata bulunmadı.",

        metadata: {
          smoke_test:
            true,

          production_ready:
            false,
        },
      };
    }

    if (
      reviewerRole ===
      "final_checker"
    ) {
      return {
        schema_version: "1.0",

        reviewer_role:
          "final_checker",

        verdict:
          "pass",

        risk_level:
          "low",

        confidence_score:
          0.99,

        checks: {
          answer_is_correct:
            true,

          solution_is_correct:
            true,

          single_correct_answer:
            true,

          question_is_complete:
            true,

          question_is_unambiguous:
            true,

          curriculum_fit:
            true,

          grade_fit:
            true,

          options_are_valid:
            true,

          calculation_accuracy:
            true,
        },

        correction_required:
          false,

        detected_errors:
          [],

        warnings:
          [],

        review_summary:
          "Deterministic Son Denetçi AI testi: önceki denetimler bağımsız kontrolde doğrulandı.",

        verification_details: {
          reviewer_disagreement_detected:
            false,

          independent_recheck_completed:
            true,
        },

        metadata: {
          smoke_test:
            true,

          production_ready:
            false,
        },
      };
    }

    return {
      schema_version: "1.0",

      reviewer_role:
        "correction",

      verdict:
        "pass",

      risk_level:
        "low",

      confidence_score:
        0.97,

      checks: {},

      correction_required:
        false,

      detected_errors:
        [],

      warnings:
        [],

      review_summary:
        "Deterministic Düzeltici AI testi: düzeltme gerektiren hata bulunmadı.",

      metadata: {
        smoke_test:
          true,

        production_ready:
          false,
      },
    };
  }

  private reviewWrongAnswerScenario(
    reviewerRole: TeacherReviewRole,
  ): TeacherReviewOutput {
    if (
      reviewerRole ===
      "subject_teacher"
    ) {
      return {
        schema_version: "1.0",

        reviewer_role:
          "subject_teacher",

        verdict:
          "needs_correction",

        risk_level:
          "high",

        confidence_score:
          0.99,

        checks: {
          answer_is_correct:
            false,

          solution_is_correct:
            false,

          single_correct_answer:
            true,

          question_is_complete:
            true,

          question_is_unambiguous:
            true,

          curriculum_fit:
            true,

          grade_fit:
            true,

          language_fit:
            true,

          terminology_fit:
            true,

          options_are_valid:
            true,

          distractors_are_valid:
            true,

          solve_time_is_reasonable:
            true,

          factual_accuracy:
            true,

          calculation_accuracy:
            false,

          unit_consistency:
            true,
        },

        correction_required:
          true,

        detected_errors: [
          {
            issue_code:
              "WRONG_ANSWER_KEY",

            issue_category:
              "answer",

            severity:
              "high",

            field_name:
              "proposed_correct_answer",

            description:
              "12 + 8 işleminin sonucu 20'dir. Doğru seçenek B olmalıdır; mevcut cevap anahtarı C olarak işaretlenmiştir.",

            evidence: {
              calculation:
                "12 + 8 = 20",

              expected_answer:
                "B",

              received_answer:
                "C",
            },

            correction_recommended:
              true,

            blocks_publication:
              true,
          },
        ],

        warnings:
          [],

        review_summary:
          "Soru kökü ve seçenekler uygundur ancak cevap anahtarı yanlıştır. Doğru cevap B olmalıdır.",

        proposed_correction: {
          correct_answer:
            "B",

          solution: {
            calculation:
              "12 + 8 = 20",

            final_answer:
              "B",
          },

          change_summary:
            "Cevap anahtarı C yerine B olarak düzeltilmelidir.",

          change_reasons: [
            "12 + 8 = 20 olduğundan doğru seçenek B'dir.",
          ],

          confidence_score:
            0.99,

          requires_recheck:
            true,
        },

        metadata: {
          smoke_test:
            true,

          scenario:
            "wrong_answer_key",

          production_ready:
            false,
        },
      };
    }

    if (
      reviewerRole ===
      "error_hunter"
    ) {
      return {
        schema_version: "1.0",

        reviewer_role:
          "error_hunter",

        verdict:
          "needs_correction",

        risk_level:
          "high",

        confidence_score:
          0.99,

        checks: {
          answer_is_correct:
            false,

          single_correct_answer:
            true,

          question_is_complete:
            true,

          question_is_unambiguous:
            true,

          options_are_valid:
            true,

          distractors_are_valid:
            true,

          factual_accuracy:
            true,

          calculation_accuracy:
            false,

          unit_consistency:
            true,
        },

        correction_required:
          true,

        detected_errors: [
          {
            issue_code:
              "WRONG_ANSWER_KEY_CONFIRMED",

            issue_category:
              "answer",

            severity:
              "high",

            field_name:
              "proposed_correct_answer",

            description:
              "Hata Avcısı bağımsız hesaplamada cevap anahtarının yanlış olduğunu doğruladı.",

            evidence: {
              calculation:
                "12 + 8 = 20",

              correct_option:
                "B",

              current_option:
                "C",
            },

            correction_recommended:
              true,

            blocks_publication:
              true,
          },
        ],

        warnings:
          [],

        review_summary:
          "Cevap anahtarı hatası bağımsız olarak doğrulandı.",

        proposed_correction: {
          correct_answer:
            "B",

          solution: {
            calculation:
              "12 + 8 = 20",

            final_answer:
              "B",
          },

          change_summary:
            "Cevap anahtarı B olarak değiştirilmelidir.",

          change_reasons: [
            "Bağımsız işlem sonucu 20'dir.",
          ],

          confidence_score:
            0.99,

          requires_recheck:
            true,
        },

        metadata: {
          smoke_test:
            true,

          scenario:
            "wrong_answer_key",

          production_ready:
            false,
        },
      };
    }

    if (
      reviewerRole ===
      "correction"
    ) {
      return {
        schema_version: "1.0",

        reviewer_role:
          "correction",

        verdict:
          "needs_correction",

        risk_level:
          "medium",

        confidence_score:
          0.99,

        checks: {
          answer_is_correct:
            false,

          single_correct_answer:
            true,

          question_is_complete:
            true,

          question_is_unambiguous:
            true,

          options_are_valid:
            true,

          calculation_accuracy:
            true,
        },

        correction_required:
          true,

        detected_errors: [
          {
            issue_code:
              "ANSWER_KEY_CORRECTION_REQUIRED",

            issue_category:
              "answer",

            severity:
              "high",

            field_name:
              "proposed_correct_answer",

            description:
              "Mevcut cevap anahtarı C yerine B olmalıdır.",

            evidence: {
              old_answer:
                "C",

              new_answer:
                "B",
            },

            correction_recommended:
              true,

            blocks_publication:
              true,
          },
        ],

        warnings:
          [],

        review_summary:
          "Soru metni ve seçenekler korunarak yalnızca cevap anahtarının düzeltilmesi önerildi.",

        proposed_correction: {
          question_text:
            "Bir kutuda 12 kırmızı ve 8 mavi kalem vardır. Kutuda toplam kaç kalem vardır?",

          options: {
            A:
              "18",

            B:
              "20",

            C:
              "22",

            D:
              "24",
          },

          correct_answer:
            "B",

          solution: {
            explanation:
              "12 kırmızı kalem ile 8 mavi kalem toplanır.",

            calculation:
              "12 + 8 = 20",

            final_answer:
              "B",
          },

          change_summary:
            "Yanlış cevap anahtarı C'den B'ye düzeltildi.",

          change_reasons: [
            "Toplam kalem sayısı 20'dir.",
            "20 değeri B seçeneğindedir.",
          ],

          confidence_score:
            0.99,

          requires_recheck:
            true,
        },

        metadata: {
          smoke_test:
            true,

          scenario:
            "wrong_answer_key",

          production_ready:
            false,
        },
      };
    }

    return {
      schema_version: "1.0",

      reviewer_role:
        "final_checker",

      verdict:
        "pass",

      risk_level:
        "low",

      confidence_score:
        0.99,

      checks: {
        answer_is_correct:
          true,

        solution_is_correct:
          true,

        single_correct_answer:
          true,

        question_is_complete:
          true,

        question_is_unambiguous:
          true,

        curriculum_fit:
          true,

        grade_fit:
          true,

        language_fit:
          true,

        terminology_fit:
          true,

        options_are_valid:
          true,

        distractors_are_valid:
          true,

        solve_time_is_reasonable:
          true,

        factual_accuracy:
          true,

        calculation_accuracy:
          true,

        unit_consistency:
          true,
      },

      correction_required:
        false,

      detected_errors:
        [],

      warnings:
        [],

      review_summary:
        "Düzeltilmiş cevap anahtarı B bağımsız kontrolde doğrulandı.",

      verification_details: {
        corrected_answer:
          "B",

        independent_calculation:
          "12 + 8 = 20",

        recheck_completed:
          true,
      },

      metadata: {
        smoke_test:
          true,

        scenario:
          "wrong_answer_key",

        production_ready:
          false,
      },
    };
  }
}