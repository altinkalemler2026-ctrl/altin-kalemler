import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  APPROVAL_STATUSES,
  DIFFICULTIES,
  EXAM_TRACKS,
  GRADES,
  QUESTION_LIST_LIMIT,
  listQuestions,
  listSubjects,
  parseGrade,
  parseUuid,
} from "@/lib/admin/question-bank"
import {
  ADMIN_QUESTIONS_MESSAGES as M,
} from "@/lib/admin/admin-panel-messages"

type PermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

type SearchParams = Promise<{
  examTrack?: string
  grade?: string
  subject?: string
  difficulty?: string
  approvalStatus?: string
  isActive?: string
  query?: string
}>

function difficultyLabel(value: string): string {
  switch (value) {
    case "easy":
      return M.difficultyEasy
    case "medium":
      return M.difficultyMedium
    case "hard":
      return M.difficultyHard
    default:
      return value
  }
}

function approvalStatusLabel(value: string): string {
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
      return value
  }
}

export default async function AdminQuestionsPage({
  searchParams,
}: {
  searchParams: SearchParams
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

  const params = await searchParams

  const examTrack = params.examTrack?.trim() || undefined
  const grade = parseGrade(params.grade)
  const subjectId = parseUuid(params.subject)
  const difficulty = params.difficulty?.trim() || undefined
  const approvalStatus = params.approvalStatus?.trim() || undefined
  const isActiveParam = params.isActive?.trim()
  const isActive =
    isActiveParam === "true" ? true : isActiveParam === "false" ? false : undefined
  const query = params.query?.trim() || undefined

  const [questions, subjects] = await Promise.all([
    listQuestions({
      examTrack:
        examTrack && (EXAM_TRACKS as readonly string[]).includes(examTrack)
          ? examTrack
          : undefined,
      grade: grade ?? undefined,
      subjectId,
      difficulty:
        difficulty && (DIFFICULTIES as readonly string[]).includes(difficulty)
          ? difficulty
          : undefined,
      approvalStatus:
        approvalStatus &&
        (APPROVAL_STATUSES as readonly string[]).includes(approvalStatus)
          ? approvalStatus
          : undefined,
      isActive,
      query,
    }),
    listSubjects(),
  ])

  return (
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-6xl">
        <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-3xl font-bold text-gray-900">{M.title}</h1>
            <p className="mt-2 text-gray-600">{M.subtitle}</p>
          </div>
          <Link
            href="/admin"
            className="rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
          >
            {M.backToDashboard}
          </Link>
        </div>

        <form
          method="get"
          className="mb-6 grid gap-3 rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:grid-cols-2 lg:grid-cols-5"
        >
          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.examTrackLabel}
            </span>
            <select
              name="examTrack"
              defaultValue={examTrack ?? ""}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            >
              <option value="">{M.allExamTracks}</option>
              {EXAM_TRACKS.map((track) => (
                <option key={track} value={track}>
                  {track}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.gradeLabel}
            </span>
            <select
              name="grade"
              defaultValue={grade ?? ""}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            >
              <option value="">{M.allGrades}</option>
              {GRADES.map((g) => (
                <option key={g} value={g}>
                  {g}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.subjectLabel}
            </span>
            <select
              name="subject"
              defaultValue={subjectId ?? ""}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            >
              <option value="">{M.allSubjects}</option>
              {subjects.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.difficultyLabel}
            </span>
            <select
              name="difficulty"
              defaultValue={difficulty ?? ""}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            >
              <option value="">{M.allDifficulties}</option>
              {DIFFICULTIES.map((d) => (
                <option key={d} value={d}>
                  {difficultyLabel(d)}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.approvalStatusLabel}
            </span>
            <select
              name="approvalStatus"
              defaultValue={approvalStatus ?? ""}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            >
              <option value="">{M.allApprovalStatuses}</option>
              {APPROVAL_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {approvalStatusLabel(s)}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.isActiveLabel}
            </span>
            <select
              name="isActive"
              defaultValue={isActiveParam ?? ""}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            >
              <option value="">{M.allActivity}</option>
              <option value="true">{M.activeYes}</option>
              <option value="false">{M.activeNo}</option>
            </select>
          </label>

          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.searchLabel}
            </span>
            <input
              name="query"
              defaultValue={query ?? ""}
              placeholder={M.questionCode}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            />
          </label>

          <div className="sm:col-span-2 lg:col-span-5">
            <button
              type="submit"
              className="rounded-xl bg-gray-900 px-5 py-2.5 font-semibold text-white hover:bg-gray-700"
            >
              {M.filterLabel}
            </button>
          </div>
        </form>

        <section className="rounded-2xl border border-gray-200 bg-white shadow-sm">
          {questions.length === 0 ? (
            <p className="px-6 py-10 text-gray-600">{M.empty}</p>
          ) : (
            <>
              {questions.length >= QUESTION_LIST_LIMIT && (
                <p className="border-b border-gray-200 bg-amber-50 px-6 py-3 text-sm text-amber-800">
                  {M.truncatedNotice}
                </p>
              )}
              <ul className="divide-y divide-gray-200">
              {questions.map((q) => (
                <li key={q.id}>
                  <Link
                    href={`/admin/questions/${q.id}`}
                    className="flex items-start justify-between gap-4 px-6 py-4 hover:bg-gray-50"
                  >
                    <div className="min-w-0">
                      <p className="font-mono text-sm font-semibold text-gray-900">
                        {q.question_code}
                      </p>
                      <p className="mt-0.5 line-clamp-2 text-gray-700">
                        {q.question_text ?? M.noQuestionText}
                      </p>
                    </div>
                    <div className="flex shrink-0 flex-wrap items-center gap-2 text-sm text-gray-600">
                      <span>{q.subject_name ?? "-"}</span>
                      <span>{q.grade_level}. sınıf</span>
                      {q.exam_track && <span>{q.exam_track}</span>}
                      {q.difficulty && (
                        <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs">
                          {difficultyLabel(q.difficulty)}
                        </span>
                      )}
                      {q.approval_status && (
                        <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium">
                          {approvalStatusLabel(q.approval_status)}
                        </span>
                      )}
                      <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs">
                        {q.is_active ? M.activeYes : M.activeNo}
                      </span>
                    </div>
                  </Link>
                </li>
              ))}
              </ul>
            </>
          )}
        </section>
      </div>
    </main>
  )
}
