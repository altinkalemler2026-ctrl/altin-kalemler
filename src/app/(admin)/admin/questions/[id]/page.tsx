import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import { getQuestionDetail } from "@/lib/admin/question-bank"
import {
  ADMIN_QUESTION_DETAIL_MESSAGES as M,
} from "@/lib/admin/admin-panel-messages"

type PermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

type Params = Promise<{ id: string }>

const OPTION_LABELS = [
  "A",
  "B",
  "C",
  "D",
  "E",
] as const

function difficultyLabel(value: string | null): string {
  switch (value) {
    case "easy":
      return M.difficultyEasy
    case "medium":
      return M.difficultyMedium
    case "hard":
      return M.difficultyHard
    default:
      return value ?? "-"
  }
}

function approvalStatusLabel(value: string | null): string {
  switch (value) {
    case "approved":
      return M.statusApproved
    case "pending":
      return M.statusPending
    case "draft":
      return M.statusDraft
    case "rejected":
      return M.statusRejected
    default:
      return value ?? "-"
  }
}

export default async function AdminQuestionDetailPage({
  params,
}: {
  params: Params
}) {
  const supabase = await createClient()

  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    redirect("/login")
  }

  const rpc = supabase.rpc.bind(supabase) as unknown as PermissionRpc
  const { data: canView, error: permissionError } = await rpc(
    "teacher_review_admin_has_permission",
    { p_permission_code: "questions.view" },
  )

  if (permissionError || canView !== true) {
    redirect("/dashboard")
  }

  const { id } = await params
  const question = await getQuestionDetail(id)

  if (!question) {
    return (
      <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
        <div className="mx-auto max-w-3xl">
          <Link
            href="/admin/questions"
            className="mb-4 inline-block rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
          >
            {M.backToList}
          </Link>
          <p className="rounded-2xl border border-gray-200 bg-white px-6 py-10 text-gray-600">
            {M.notFound}
          </p>
        </div>
      </main>
    )
  }

  const options = OPTION_LABELS.map((label, index) => {
    const text =
      [question.option_a, question.option_b, question.option_c, question.option_d, question.option_e][
        index
      ] ?? null
    return { label, text, isCorrect: question.correct_answer === label }
  }).filter((o) => o.text !== null)

  return (
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-3xl">
        <Link
          href="/admin/questions"
          className="mb-4 inline-block rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
        >
          {M.backToList}
        </Link>

        <div className="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
          <div className="border-b border-gray-200 bg-gray-50 px-6 py-4">
            <p className="font-mono text-sm font-semibold text-gray-900">
              {question.question_code}
            </p>
          </div>

          <div className="px-6 py-5">
            <p className="whitespace-pre-wrap text-gray-900">
              {question.question_text ?? M.noQuestionText}
            </p>
          </div>

          {options.length > 0 && (
            <div className="border-t border-gray-200 px-6 py-5">
              <h2 className="mb-3 text-sm font-semibold text-gray-500 uppercase">
                {M.optionsTitle}
              </h2>
              <ul className="grid gap-2">
                {options.map((o) => (
                  <li
                    key={o.label}
                    className={`flex items-start gap-3 rounded-xl border px-4 py-3 ${
                      o.isCorrect
                        ? "border-emerald-300 bg-emerald-50"
                        : "border-gray-200"
                    }`}
                  >
                    <span
                      className={`font-semibold ${
                        o.isCorrect ? "text-emerald-700" : "text-gray-700"
                      }`}
                    >
                      {o.label}
                    </span>
                    <span className="text-gray-800">{o.text}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          <div className="border-t border-gray-200 bg-gray-50 px-6 py-5">
            <h2 className="mb-3 text-sm font-semibold text-gray-500 uppercase">
              {M.metadataTitle}
            </h2>
            <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
              <MetadataItem label={M.subject} value={question.subject_name ?? "-"} />
              <MetadataItem
                label={M.grade}
                value={`${question.grade_level}. sınıf`}
              />
              <MetadataItem label={M.examTrack} value={question.exam_track ?? "-"} />
              <MetadataItem
                label={M.difficulty}
                value={difficultyLabel(question.difficulty)}
              />
              <MetadataItem
                label={M.correctAnswer}
                value={
                  question.correct_answer
                    ? `${question.correct_answer}. seçenek`
                    : "-"
                }
              />
              <MetadataItem
                label={M.solveTime}
                value={
                  question.estimated_solve_time_seconds
                    ? `${question.estimated_solve_time_seconds} ${M.solveTimeUnit}`
                    : "-"
                }
              />
              <MetadataItem
                label={M.qualityLevel}
                value={question.quality_level ?? "-"}
              />
              <MetadataItem
                label={M.ownership}
                value={question.ownership_status ?? "-"}
              />
              <MetadataItem
                label={M.license}
                value={question.license_status ?? "-"}
              />
              <MetadataItem
                label={M.approvalStatus}
                value={approvalStatusLabel(question.approval_status)}
              />
              <MetadataItem
                label={M.activeStatus}
                value={question.is_active ? M.activeYes : M.activeNo}
              />
            </dl>
          </div>
        </div>
      </div>
    </main>
  )
}

function MetadataItem({
  label,
  value,
}: {
  label: string
  value: string
}) {
  return (
    <div>
      <dt className="text-gray-500">{label}</dt>
      <dd className="font-medium text-gray-900">{value}</dd>
    </div>
  )
}
