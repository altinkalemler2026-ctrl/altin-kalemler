import type {
  TeacherReviewOutput,
  TeacherReviewRole,
} from "./teacher-review-types.ts";

export type TestTeacherReviewProviderContext = {
  reviewerRole: TeacherReviewRole;
};

export class TestTeacherReviewProvider {
  readonly providerName =
    "test-teacher-review-provider";

  readonly modelName =
    "deterministic-teacher-review-model";

  readonly promptVersion =
    "teacher-review-test-v1";

  async reviewQuestion(
    context: TestTeacherReviewProviderContext,
  ): Promise<TeacherReviewOutput> {
    if (
      context.reviewerRole ===
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
      context.reviewerRole ===
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
      context.reviewerRole ===
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
}