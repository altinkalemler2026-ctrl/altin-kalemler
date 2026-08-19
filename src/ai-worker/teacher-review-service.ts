import { createClient } from "@supabase/supabase-js";

import type {
  TeacherReviewIssue,
  TeacherReviewOutput,
  TeacherReviewRole,
} from "./teacher-review-types.ts";

type TeacherReviewProfileRow = {
  id: string;
  profile_code: string;
  name: string;
  reviewer_role: TeacherReviewRole;
  minimum_confidence: number;
  automatic_low_risk_threshold: number;
  correction_allowed: boolean;
  direct_publication_allowed: boolean;
  rules: Record<string, unknown>;
};

type TeacherReviewRunRow = {
  id: string;
  staging_question_id: string;
  subject_id: string;
  status: string;
  current_stage: string;
};

export class TeacherReviewService {
  private readonly supabase;

  constructor() {
    const url =
      process.env.NEXT_PUBLIC_SUPABASE_URL;

    const serviceRoleKey =
      process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!url) {
      throw new Error(
        "NEXT_PUBLIC_SUPABASE_URL is missing.",
      );
    }

    if (!serviceRoleKey) {
      throw new Error(
        "SUPABASE_SERVICE_ROLE_KEY is missing.",
      );
    }

    this.supabase =
      createClient(
        url,
        serviceRoleKey,
        {
          auth: {
            persistSession: false,
            autoRefreshToken: false,
          },
        },
      );
  }

  async getProfileByCode(
    profileCode: string,
  ): Promise<TeacherReviewProfileRow> {
    const {
      data,
      error,
    } =
      await this.supabase
        .from(
          "ai_teacher_review_profiles",
        )
        .select(
          [
            "id",
            "profile_code",
            "name",
            "reviewer_role",
            "minimum_confidence",
            "automatic_low_risk_threshold",
            "correction_allowed",
            "direct_publication_allowed",
            "rules",
          ].join(","),
        )
        .eq(
          "profile_code",
          profileCode,
        )
        .eq(
          "is_active",
          true,
        )
        .single();

    if (error) {
      throw new Error(
        `Teacher review profile lookup failed: ${error.message}`,
      );
    }

    if (!data) {
      throw new Error(
        `Teacher review profile not found: ${profileCode}`,
      );
    }

    return data as unknown as TeacherReviewProfileRow;
  }

  async createReviewRun(
    stagingQuestionId: string,
    subjectId: string,
  ): Promise<TeacherReviewRunRow> {
    const {
      data,
      error,
    } =
      await this.supabase
        .from(
          "ai_teacher_review_runs",
        )
        .insert({
          staging_question_id:
            stagingQuestionId,

          subject_id:
            subjectId,

          status:
            "waiting_subject_teacher",

          current_stage:
            "subject_teacher",

          overall_risk_level:
            "unknown",

          human_review_required:
            true,

          metadata: {
            source:
              "teacher-review-service",
          },
        })
        .select(
          "id, staging_question_id, subject_id, status, current_stage",
        )
        .single();

    if (error) {
      throw new Error(
        `Teacher review run creation failed: ${error.message}`,
      );
    }

    if (!data) {
      throw new Error(
        "Teacher review run creation returned no data.",
      );
    }

    return data as unknown as TeacherReviewRunRow;
  }

  async saveReview(
    run: TeacherReviewRunRow,
    profile: TeacherReviewProfileRow,
    output: TeacherReviewOutput,
    providerMetadata: {
      providerName: string;
      modelName: string;
      promptVersion: string;
    },
  ): Promise<string> {
    const {
      data,
      error,
    } =
      await this.supabase
        .from(
          "ai_teacher_reviews",
        )
        .insert({
          review_run_id:
            run.id,

          staging_question_id:
            run.staging_question_id,

          profile_id:
            profile.id,

          reviewer_role:
            output.reviewer_role,

          reviewer_number:
            1,

          review_iteration:
            1,

          verdict:
            output.verdict,

          risk_level:
            output.risk_level,

          confidence_score:
            output.confidence_score,

          answer_is_correct:
            output.checks.answer_is_correct,

          solution_is_correct:
            output.checks.solution_is_correct,

          single_correct_answer:
            output.checks.single_correct_answer,

          question_is_complete:
            output.checks.question_is_complete,

          question_is_unambiguous:
            output.checks.question_is_unambiguous,

          curriculum_fit:
            output.checks.curriculum_fit,

          grade_fit:
            output.checks.grade_fit,

          language_fit:
            output.checks.language_fit,

          terminology_fit:
            output.checks.terminology_fit,

          options_are_valid:
            output.checks.options_are_valid,

          distractors_are_valid:
            output.checks.distractors_are_valid,

          solve_time_is_reasonable:
            output.checks.solve_time_is_reasonable,

          factual_accuracy:
            output.checks.factual_accuracy,

          calculation_accuracy:
            output.checks.calculation_accuracy,

          unit_consistency:
            output.checks.unit_consistency,

          correction_required:
            output.correction_required,

          detected_errors:
            output.detected_errors,

          warnings:
            output.warnings,

          verification_details:
            output.verification_details ?? {},

          provider_name:
            providerMetadata.providerName,

          model_name:
            providerMetadata.modelName,

          prompt_version:
            providerMetadata.promptVersion,

          review_summary:
            output.review_summary,

          metadata:
            output.metadata ?? {},
        })
        .select("id")
        .single();

    if (error) {
      throw new Error(
        `Teacher review save failed: ${error.message}`,
      );
    }

    if (!data) {
      throw new Error(
        "Teacher review save returned no data.",
      );
    }

    const reviewId =
      String(data.id);

    await this.saveIssues(
      reviewId,
      run,
      output.detected_errors,
    );

    return reviewId;
  }

  private async saveIssues(
    reviewId: string,
    run: TeacherReviewRunRow,
    issues: TeacherReviewIssue[],
  ): Promise<void> {
    if (issues.length === 0) {
      return;
    }

    const rows =
      issues.map((issue) => ({
        review_id:
          reviewId,

        review_run_id:
          run.id,

        staging_question_id:
          run.staging_question_id,

        issue_code:
          issue.issue_code,

        issue_category:
          issue.issue_category,

        severity:
          issue.severity,

        field_name:
          issue.field_name ?? null,

        description:
          issue.description,

        evidence:
          issue.evidence ?? {},

        correction_recommended:
          issue.correction_recommended,

        blocks_publication:
          issue.blocks_publication,
      }));

    const {
      error,
    } =
      await this.supabase
        .from(
          "ai_teacher_review_issues",
        )
        .insert(rows);

    if (error) {
      throw new Error(
        `Teacher review issue save failed: ${error.message}`,
      );
    }
  }

  async completeSubjectTeacherStage(
    runId: string,
    output: TeacherReviewOutput,
  ): Promise<void> {
    const passed =
      output.verdict === "pass" ||
      output.verdict === "pass_with_warning";

    const needsHumanReview =
      output.verdict ===
        "human_review_required" ||
      output.verdict === "reject" ||
      output.risk_level === "high" ||
      output.risk_level === "critical";

    const nextStatus =
      needsHumanReview
        ? "human_review_required"
        : output.correction_required
          ? "waiting_correction"
          : "waiting_error_hunter";

    const nextStage =
      needsHumanReview
        ? "human_review"
        : output.correction_required
          ? "correction"
          : "error_hunter";

    const {
      error,
    } =
      await this.supabase
        .from(
          "ai_teacher_review_runs",
        )
        .update({
          subject_teacher_passed:
            passed,

          correction_required:
            output.correction_required,

          overall_confidence:
            output.confidence_score,

          overall_risk_level:
            output.risk_level,

          human_review_required:
            needsHumanReview,

          human_review_reason:
            needsHumanReview
              ? output.review_summary
              : null,

          status:
            nextStatus,

          current_stage:
            nextStage,
        })
        .eq(
          "id",
          runId,
        );

    if (error) {
      throw new Error(
        `Teacher review run update failed: ${error.message}`,
      );
    }
  }

  async completeErrorHunterStage(
    runId: string,
    output: TeacherReviewOutput,
  ): Promise<void> {
    const passed =
      output.verdict === "pass" ||
      output.verdict === "pass_with_warning";

    const needsHumanReview =
      output.verdict ===
        "human_review_required" ||
      output.verdict === "reject" ||
      output.risk_level === "high" ||
      output.risk_level === "critical";

    const nextStatus =
      needsHumanReview
        ? "human_review_required"
        : output.correction_required
          ? "waiting_correction"
          : "waiting_final_checker";

    const nextStage =
      needsHumanReview
        ? "human_review"
        : output.correction_required
          ? "correction"
          : "final_checker";

    const {
      error,
    } =
      await this.supabase
        .from(
          "ai_teacher_review_runs",
        )
        .update({
          error_hunter_passed:
            passed,

          correction_required:
            output.correction_required,

          overall_confidence:
            output.confidence_score,

          overall_risk_level:
            output.risk_level,

          human_review_required:
            needsHumanReview,

          human_review_reason:
            needsHumanReview
              ? output.review_summary
              : null,

          status:
            nextStatus,

          current_stage:
            nextStage,
        })
        .eq(
          "id",
          runId,
        );

    if (error) {
      throw new Error(
        `Error Hunter stage update failed: ${error.message}`,
      );
    }
  }

  async completeFinalCheckerStage(
    runId: string,
    output: TeacherReviewOutput,
  ): Promise<void> {
    const passed =
      output.verdict === "pass" ||
      output.verdict === "pass_with_warning";

    const needsHumanReview =
      !passed ||
      output.correction_required ||
      output.verdict ===
        "human_review_required" ||
      output.risk_level === "high" ||
      output.risk_level === "critical";

    const nextStatus =
      needsHumanReview
        ? "human_review_required"
        : "ai_review_passed";

    const nextStage =
      needsHumanReview
        ? "human_review"
        : "complete";

    const {
      error,
    } =
      await this.supabase
        .from(
          "ai_teacher_review_runs",
        )
        .update({
          final_checker_passed:
            passed,

          correction_required:
            output.correction_required,

          overall_confidence:
            output.confidence_score,

          overall_risk_level:
            output.risk_level,

          human_review_required:
            needsHumanReview,

          human_review_reason:
            needsHumanReview
              ? output.review_summary
              : null,

          status:
            nextStatus,

          current_stage:
            nextStage,

          ai_review_completed_at:
            new Date().toISOString(),
        })
        .eq(
          "id",
          runId,
        );

    if (error) {
      throw new Error(
        `Final Checker stage update failed: ${error.message}`,
      );
    }
  }
}