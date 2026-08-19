import type {
  JsonObject,
} from "./types.ts";

import type {
  TeacherReviewRole,
} from "./teacher-review-types.ts";

export type TeacherReviewPromptInput = {
  reviewerRole: TeacherReviewRole;

  profileCode: string;

  profileName: string;

  subjectName: string;

  gradeLevel?: number;

  curriculumVersionId?: string;

  topicId?: string;

  subtopicId?: string;

  outcomeId?: string;

  question: {
    questionText: string;

    options: {
      A: string;
      B: string;
      C: string;
      D: string;
      E?: string;
    };

    proposedCorrectAnswer?: string;

    proposedDifficulty?: string;

    proposedCognitiveType?: string;

    proposedSolveTimeSeconds?: number;

    metadata?: JsonObject;
  };

  previousReviews?: JsonObject[];

  profileRules?: JsonObject;
};

export type TeacherReviewPrompt = {
  systemPrompt: string;
  userPrompt: string;
};

export function buildTeacherReviewPrompt(
  input: TeacherReviewPromptInput,
): TeacherReviewPrompt {
  const systemPrompt = [
    "Sen Altın Kalemler için çalışan uzman bir Öğretmen AI denetçisisin.",
    "Görevin soru üretmek değil; sana verilen soruyu bağımsız biçimde denetlemektir.",
    "",
    "TEMEL KURALLAR:",
    "- Mevcut cevap anahtarına güvenme; soruyu kendin çöz.",
    "- Tek ve kesin doğru cevap olup olmadığını kontrol et.",
    "- Soru kökünde eksik bilgi, çelişki veya belirsizlik ara.",
    "- Tüm seçenekleri ayrı ayrı değerlendir.",
    "- Çözüm varsa bağımsız olarak doğrula.",
    "- Sınıf seviyesine ve müfredat bağlamına uygunluğu değerlendir.",
    "- Dil, terminoloji, matematiksel ifade ve birim hatalarını kontrol et.",
    "- Tahmini çözüm süresinin makul olup olmadığını kontrol et.",
    "- Emin olmadığın noktaları güven puanına yansıt.",
    "- Önceki AI değerlendirmelerini körü körüne kabul etme.",
    "- Hata görürsen açıkça belirt.",
    "- Kritik veya belirsiz durumda human_review_required verdict kullan.",
    "- AI hiçbir koşulda soruyu doğrudan production'a yayınlayamaz.",
    "",
    "ÇIKTI KURALI:",
    "- Yalnızca geçerli JSON döndür.",
    "- Markdown kullanma.",
    "- Açıklamayı JSON dışına yazma.",
    '- schema_version tam olarak "1.0" olmalı.',
  ].join("\n");

  const userPrompt = [
    `Reviewer role: ${input.reviewerRole}`,
    `Profile code: ${input.profileCode}`,
    `Profile name: ${input.profileName}`,
    `Subject: ${input.subjectName}`,
    `Grade level: ${input.gradeLevel ?? "unknown"}`,
    `Curriculum version id: ${input.curriculumVersionId ?? "unknown"}`,
    `Topic id: ${input.topicId ?? "unknown"}`,
    `Subtopic id: ${input.subtopicId ?? "unknown"}`,
    `Outcome id: ${input.outcomeId ?? "unknown"}`,
    "",
    "SORU:",
    input.question.questionText,
    "",
    "SEÇENEKLER:",
    `A: ${input.question.options.A}`,
    `B: ${input.question.options.B}`,
    `C: ${input.question.options.C}`,
    `D: ${input.question.options.D}`,
    input.question.options.E
      ? `E: ${input.question.options.E}`
      : "E: yok",
    "",
    `Mevcut önerilen cevap: ${input.question.proposedCorrectAnswer ?? "unknown"}`,
    `Önerilen zorluk: ${input.question.proposedDifficulty ?? "unknown"}`,
    `Önerilen bilişsel tür: ${input.question.proposedCognitiveType ?? "unknown"}`,
    `Önerilen çözüm süresi: ${input.question.proposedSolveTimeSeconds ?? "unknown"}`,
    "",
    "PROFILE RULES:",
    JSON.stringify(
      input.profileRules ?? {},
      null,
      2,
    ),
    "",
    "PREVIOUS REVIEWS:",
    JSON.stringify(
      input.previousReviews ?? [],
      null,
      2,
    ),
    "",
    "Aşağıdaki JSON yapısına uygun cevap ver:",
    JSON.stringify(
      {
        schema_version: "1.0",

        reviewer_role:
          input.reviewerRole,

        verdict:
          "pass | pass_with_warning | needs_correction | human_review_required | reject",

        risk_level:
          "unknown | low | medium | high | critical",

        confidence_score:
          "0 ile 1 arası sayı",

        checks: {
          answer_is_correct:
            "boolean veya omit",

          solution_is_correct:
            "boolean veya omit",

          single_correct_answer:
            "boolean veya omit",

          question_is_complete:
            "boolean veya omit",

          question_is_unambiguous:
            "boolean veya omit",

          curriculum_fit:
            "boolean veya omit",

          grade_fit:
            "boolean veya omit",

          language_fit:
            "boolean veya omit",

          terminology_fit:
            "boolean veya omit",

          options_are_valid:
            "boolean veya omit",

          distractors_are_valid:
            "boolean veya omit",

          solve_time_is_reasonable:
            "boolean veya omit",

          factual_accuracy:
            "boolean veya omit",

          calculation_accuracy:
            "boolean veya omit",

          unit_consistency:
            "boolean veya omit",
        },

        correction_required:
          "boolean",

        detected_errors: [
          {
            issue_code:
              "string",

            issue_category:
              "answer | solution | calculation | factual | curriculum | grade_level | language | terminology | ambiguity | question_structure | options | distractors | solve_time | visual | unit | originality | copyright | other",

            severity:
              "info | low | medium | high | critical",

            field_name:
              "string optional",

            description:
              "string",

            evidence:
              {},

            correction_recommended:
              "boolean",

            blocks_publication:
              "boolean",
          },
        ],

        warnings: [],

        review_summary:
          "string",

        verification_details:
          {},

        proposed_correction: {
          question_text:
            "string optional",

          options: {
            A: "string optional",
            B: "string optional",
            C: "string optional",
            D: "string optional",
            E: "string optional",
          },

          correct_answer:
            "A | B | C | D | E optional",

          solution:
            {},

          change_summary:
            "string optional",

          change_reasons: [
            "string",
          ],

          confidence_score:
            "0 ile 1 arası sayı",

          requires_recheck:
            "boolean",
        },

        metadata:
          {},
      },
      null,
      2,
    ),
  ].join("\n");

  return {
    systemPrompt,
    userPrompt,
  };
}