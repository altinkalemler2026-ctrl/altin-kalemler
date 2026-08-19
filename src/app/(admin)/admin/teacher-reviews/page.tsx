import { createClient } from "@/lib/supabase/server";
import { decideTeacherReviewAction } from "./actions";

type ReviewRunRow = {
  id: string;
  staging_question_id: string;
  subject_id: string;
  status: string;
  current_stage: string;
  overall_confidence: number | string | null;
  overall_risk_level: string;
  human_review_reason: string | null;
  created_at: string;
};

type StagingQuestionRow = {
  id: string;
  question_text: string;
  option_a: string | null;
  option_b: string | null;
  option_c: string | null;
  option_d: string | null;
  option_e: string | null;
  proposed_correct_answer: string | null;
  grade_level: number | null;
};

type SubjectRow = {
  id: string;
  name: string;
};

type CorrectionProposalRow = {
  id: string;
  review_run_id: string;
  status: string;
  proposed_question_text: string | null;
  proposed_option_a: string | null;
  proposed_option_b: string | null;
  proposed_option_c: string | null;
  proposed_option_d: string | null;
  proposed_option_e: string | null;
  proposed_correct_answer: string | null;
  change_summary: string | null;
  confidence_score: number | string;
  requires_recheck: boolean;
  applied_to_staging: boolean;
};

type ReviewIssueRow = {
  id: string;
  review_run_id: string;
  issue_code: string;
  severity: string;
  field_name: string | null;
  description: string;
  blocks_publication: boolean;
};

type SupabaseUntyped = {
  from: (
    table: string,
  ) => {
    select: (
      columns: string,
    ) => {
      eq: (
        column: string,
        value: unknown,
      ) => unknown;
      in: (
        column: string,
        values: unknown[],
      ) => unknown;
      order: (
        column: string,
        options?: {
          ascending?: boolean;
        },
      ) => unknown;
    };
  };
};

function confidenceText(
  value: number | string | null,
): string {
  if (
    value === null ||
    value === undefined
  ) {
    return "-";
  }

  const numberValue =
    Number(value);

  if (
    Number.isNaN(numberValue)
  ) {
    return String(value);
  }

  return `%${Math.round(
    numberValue * 100,
  )}`;
}

export default async function TeacherReviewsPage() {
  const supabase =
    await createClient();

  const db =
    supabase as unknown as SupabaseUntyped;

  const runsQuery =
    db
      .from(
        "ai_teacher_review_runs",
      )
      .select(
        [
          "id",
          "staging_question_id",
          "subject_id",
          "status",
          "current_stage",
          "overall_confidence",
          "overall_risk_level",
          "human_review_reason",
          "created_at",
        ].join(","),
      );

  const {
    data: runData,
    error: runError,
  } =
    await (
      runsQuery
        .eq(
          "status",
          "human_review_required",
        ) as Promise<{
          data: ReviewRunRow[] | null;
          error: {
            message: string;
          } | null;
        }>
    );

  if (runError) {
    throw new Error(
      `Teacher Review listesi alınamadı: ${runError.message}`,
    );
  }

  const runs =
    runData ?? [];

  if (runs.length === 0) {
    return (
      <main className="min-h-screen bg-gray-50 p-6 sm:p-10">
        <div className="mx-auto max-w-7xl">
          <div className="rounded-2xl border border-gray-200 bg-white p-8 shadow-sm">
            <h1 className="text-2xl font-bold text-gray-900">
              Teacher Review
            </h1>

            <p className="mt-2 text-gray-600">
              İnsan incelemesi bekleyen soru bulunmuyor.
            </p>
          </div>
        </div>
      </main>
    );
  }

  const stagingIds =
    runs.map(
      (run) =>
        run.staging_question_id,
    );

  const subjectIds =
    runs.map(
      (run) =>
        run.subject_id,
    );

  const runIds =
    runs.map(
      (run) =>
        run.id,
    );

  const {
    data: stagingData,
    error: stagingError,
  } =
    await (
      db
        .from(
          "ai_question_staging",
        )
        .select(
          [
            "id",
            "question_text",
            "option_a",
            "option_b",
            "option_c",
            "option_d",
            "option_e",
            "proposed_correct_answer",
            "grade_level",
          ].join(","),
        )
        .in(
          "id",
          stagingIds,
        ) as Promise<{
          data: StagingQuestionRow[] | null;
          error: {
            message: string;
          } | null;
        }>
    );

  if (stagingError) {
    throw new Error(
      `Staging soruları alınamadı: ${stagingError.message}`,
    );
  }

  const {
    data: subjectData,
    error: subjectError,
  } =
    await (
      db
        .from(
          "subjects",
        )
        .select(
          "id,name",
        )
        .in(
          "id",
          subjectIds,
        ) as Promise<{
          data: SubjectRow[] | null;
          error: {
            message: string;
          } | null;
        }>
    );

  if (subjectError) {
    throw new Error(
      `Ders bilgileri alınamadı: ${subjectError.message}`,
    );
  }

  const {
    data: proposalData,
    error: proposalError,
  } =
    await (
      db
        .from(
          "ai_teacher_correction_proposals",
        )
        .select(
          [
            "id",
            "review_run_id",
            "status",
            "proposed_question_text",
            "proposed_option_a",
            "proposed_option_b",
            "proposed_option_c",
            "proposed_option_d",
            "proposed_option_e",
            "proposed_correct_answer",
            "change_summary",
            "confidence_score",
            "requires_recheck",
            "applied_to_staging",
          ].join(","),
        )
        .in(
          "review_run_id",
          runIds,
        ) as Promise<{
          data: CorrectionProposalRow[] | null;
          error: {
            message: string;
          } | null;
        }>
    );

  if (proposalError) {
    throw new Error(
      `Düzeltme önerileri alınamadı: ${proposalError.message}`,
    );
  }

  const {
    data: issueData,
    error: issueError,
  } =
    await (
      db
        .from(
          "ai_teacher_review_issues",
        )
        .select(
          [
            "id",
            "review_run_id",
            "issue_code",
            "severity",
            "field_name",
            "description",
            "blocks_publication",
          ].join(","),
        )
        .in(
          "review_run_id",
          runIds,
        ) as Promise<{
          data: ReviewIssueRow[] | null;
          error: {
            message: string;
          } | null;
        }>
    );

  if (issueError) {
    throw new Error(
      `Teacher Review hataları alınamadı: ${issueError.message}`,
    );
  }

  const stagingMap =
    new Map(
      (stagingData ?? []).map(
        (question) => [
          question.id,
          question,
        ],
      ),
    );

  const subjectMap =
    new Map(
      (subjectData ?? []).map(
        (subject) => [
          subject.id,
          subject,
        ],
      ),
    );

  return (
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-7xl">
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-gray-900">
            Teacher Review
          </h1>

          <p className="mt-2 text-gray-600">
            AI denetiminden sonra insan kararı bekleyen sorular.
          </p>

          <p className="mt-1 text-sm text-gray-500">
            Bekleyen kayıt:
            {" "}
            {runs.length}
          </p>
        </div>

        <div className="space-y-6">
          {runs.map((run) => {
            const question =
              stagingMap.get(
                run.staging_question_id,
              );

            const subject =
              subjectMap.get(
                run.subject_id,
              );

            const proposals =
              (proposalData ?? []).filter(
                (proposal) =>
                  proposal.review_run_id ===
                  run.id,
              );

            const proposal =
              proposals.find(
                (item) =>
                  item.status ===
                    "recheck_passed" &&
                  item.applied_to_staging ===
                    false,
              ) ??
              proposals[0];

            const issues =
              (issueData ?? []).filter(
                (issue) =>
                  issue.review_run_id ===
                  run.id,
              );

            return (
              <section
                key={run.id}
                className="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm"
              >
                <div className="border-b border-gray-200 bg-gray-50 px-6 py-4">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <h2 className="font-semibold text-gray-900">
                        {subject?.name ??
                          "Bilinmeyen ders"}
                        {" · "}
                        {question?.grade_level
                          ? `${question.grade_level}. sınıf`
                          : "Sınıf bilgisi yok"}
                      </h2>

                      <p className="mt-1 text-xs text-gray-500">
                        Run:
                        {" "}
                        {run.id}
                      </p>
                    </div>

                    <div className="flex gap-2">
                      <span className="rounded-full bg-amber-100 px-3 py-1 text-sm font-medium text-amber-800">
                        {run.overall_risk_level}
                      </span>

                      <span className="rounded-full bg-blue-100 px-3 py-1 text-sm font-medium text-blue-800">
                        Güven:
                        {" "}
                        {confidenceText(
                          run.overall_confidence,
                        )}
                      </span>
                    </div>
                  </div>
                </div>

                <div className="space-y-6 p-6">
                  <div>
                    <h3 className="text-sm font-semibold uppercase tracking-wide text-gray-500">
                      Soru
                    </h3>

                    <p className="mt-2 text-lg text-gray-900">
                      {question?.question_text ??
                        "Soru bulunamadı."}
                    </p>

                    {question && (
                      <div className="mt-4 grid gap-2 sm:grid-cols-2">
                        <div>A) {question.option_a}</div>
                        <div>B) {question.option_b}</div>
                        <div>C) {question.option_c}</div>
                        <div>D) {question.option_d}</div>

                        {question.option_e && (
                          <div>
                            E) {question.option_e}
                          </div>
                        )}
                      </div>
                    )}

                    <p className="mt-4 font-medium">
                      Mevcut cevap:
                      {" "}
                      <span className="text-red-700">
                        {question?.proposed_correct_answer ??
                          "-"}
                      </span>
                    </p>
                  </div>

                  {issues.length > 0 && (
                    <div>
                      <h3 className="text-sm font-semibold uppercase tracking-wide text-gray-500">
                        AI tarafından bulunan sorunlar
                      </h3>

                      <div className="mt-3 space-y-3">
                        {issues.map(
                          (issue) => (
                            <div
                              key={issue.id}
                              className="rounded-xl border border-red-200 bg-red-50 p-4"
                            >
                              <div className="font-semibold text-red-900">
                                {issue.issue_code}
                                {" · "}
                                {issue.severity}
                              </div>

                              <p className="mt-1 text-sm text-red-800">
                                {issue.description}
                              </p>

                              {issue.blocks_publication && (
                                <p className="mt-2 text-xs font-semibold text-red-700">
                                  Yayını engelliyor
                                </p>
                              )}
                            </div>
                          ),
                        )}
                      </div>
                    </div>
                  )}

                  {proposal && (
                    <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-5">
                      <h3 className="font-semibold text-emerald-950">
                        AI düzeltme önerisi
                      </h3>

                      <p className="mt-2 text-sm text-emerald-900">
                        {proposal.change_summary ??
                          "Düzeltme açıklaması bulunmuyor."}
                      </p>

                      <div className="mt-4 flex flex-wrap gap-6">
                        <div>
                          <span className="text-sm text-gray-600">
                            Önerilen cevap
                          </span>

                          <div className="text-xl font-bold text-emerald-800">
                            {proposal.proposed_correct_answer ??
                              "-"}
                          </div>
                        </div>

                        <div>
                          <span className="text-sm text-gray-600">
                            Güven
                          </span>

                          <div className="text-xl font-bold text-emerald-800">
                            {confidenceText(
                              proposal.confidence_score,
                            )}
                          </div>
                        </div>

                        <div>
                          <span className="text-sm text-gray-600">
                            Durum
                          </span>

                          <div className="font-semibold text-emerald-800">
                            {proposal.status}
                          </div>
                        </div>
                      </div>
                    </div>
                  )}

                  <div className="rounded-xl border border-gray-200 p-4">
                    <h3 className="font-semibold text-gray-900">
                      İnsan incelemesi
                    </h3>

                    <p className="mt-2 text-sm text-gray-600">
                      {run.human_review_reason ??
                        "İnsan incelemesi gerekli."}
                    </p>

                    <form
                      action={
                        decideTeacherReviewAction
                      }
                      className="mt-4 space-y-4"
                    >
                      <input
                        type="hidden"
                        name="review_run_id"
                        value={run.id}
                      />

                      <input
                        type="hidden"
                        name="correction_proposal_id"
                        value={
                          proposal?.id ?? ""
                        }
                      />

                      <textarea
                        name="notes"
                        rows={3}
                        placeholder="İnceleme notu..."
                        className="w-full rounded-xl border border-gray-300 px-4 py-3 text-gray-900 outline-none focus:border-gray-500"
                      />

                      <div className="flex flex-wrap gap-3">
                        <button
                          type="submit"
                          name="decision"
                          value="approved"
                          className="rounded-xl bg-emerald-700 px-5 py-3 font-semibold text-white hover:bg-emerald-800"
                        >
                          Onayla
                        </button>

                        <button
                          type="submit"
                          name="decision"
                          value="needs_revision"
                          className="rounded-xl bg-amber-600 px-5 py-3 font-semibold text-white hover:bg-amber-700"
                        >
                          Revizyon İste
                        </button>

                        <button
                          type="submit"
                          name="decision"
                          value="rejected"
                          className="rounded-xl bg-red-700 px-5 py-3 font-semibold text-white hover:bg-red-800"
                        >
                          Reddet
                        </button>
                      </div>
                    </form>
                  </div>
                </div>
              </section>
            );
          })}
        </div>
      </div>
    </main>
  );
}