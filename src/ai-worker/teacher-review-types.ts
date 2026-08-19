import type {
  JsonObject,
} from "./types.ts";

export type TeacherReviewRole =
  | "subject_teacher"
  | "error_hunter"
  | "correction"
  | "final_checker";

export type TeacherReviewVerdict =
  | "pass"
  | "pass_with_warning"
  | "needs_correction"
  | "human_review_required"
  | "reject";

export type TeacherReviewRiskLevel =
  | "unknown"
  | "low"
  | "medium"
  | "high"
  | "critical";

export type TeacherReviewIssueSeverity =
  | "info"
  | "low"
  | "medium"
  | "high"
  | "critical";

export type TeacherReviewIssueCategory =
  | "answer"
  | "solution"
  | "calculation"
  | "factual"
  | "curriculum"
  | "grade_level"
  | "language"
  | "terminology"
  | "ambiguity"
  | "question_structure"
  | "options"
  | "distractors"
  | "solve_time"
  | "visual"
  | "unit"
  | "originality"
  | "copyright"
  | "other";

export type TeacherReviewIssue = {
  issue_code: string;
  issue_category: TeacherReviewIssueCategory;
  severity: TeacherReviewIssueSeverity;
  field_name?: string;
  description: string;
  evidence?: JsonObject;
  correction_recommended: boolean;
  blocks_publication: boolean;
};

export type TeacherReviewCorrectionProposal = {
  question_text?: string;

  options?: {
    A?: string;
    B?: string;
    C?: string;
    D?: string;
    E?: string;
  };

  correct_answer?: "A" | "B" | "C" | "D" | "E";

  solution?: JsonObject;

  change_summary?: string;

  change_reasons?: string[];

  confidence_score: number;

  requires_recheck: boolean;
};

export type TeacherReviewOutput = {
  schema_version: "1.0";

  reviewer_role: TeacherReviewRole;

  verdict: TeacherReviewVerdict;

  risk_level: TeacherReviewRiskLevel;

  confidence_score: number;

  checks: {
    answer_is_correct?: boolean;
    solution_is_correct?: boolean;
    single_correct_answer?: boolean;
    question_is_complete?: boolean;
    question_is_unambiguous?: boolean;
    curriculum_fit?: boolean;
    grade_fit?: boolean;
    language_fit?: boolean;
    terminology_fit?: boolean;
    options_are_valid?: boolean;
    distractors_are_valid?: boolean;
    solve_time_is_reasonable?: boolean;
    factual_accuracy?: boolean;
    calculation_accuracy?: boolean;
    unit_consistency?: boolean;
  };

  correction_required: boolean;

  detected_errors: TeacherReviewIssue[];

  warnings: TeacherReviewIssue[];

  review_summary: string;

  verification_details?: JsonObject;

  proposed_correction?: TeacherReviewCorrectionProposal;

  metadata?: JsonObject;
};