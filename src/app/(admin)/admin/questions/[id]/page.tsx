import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import { getQuestionDetail } from "@/lib/admin/question-bank"
import {
  getPublicationReadiness,
  hasAdminPermission,
} from "@/lib/admin/question-edit"
import {
  QUESTION_PUBLICATION_MESSAGES,
} from "@/lib/admin/question-edit-errors"
import {
  ADMIN_QUESTION_DETAIL_MESSAGES as M,
} from "@/lib/admin/admin-panel-messages"
import {
  activateQuestionAction,
  deactivateQuestionAction,
  editQuestionAction,
} from "./actions"

type PermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

type Params = Promise<{ id: string }>

type SearchParams = Promise<{
  ok?: string
  error?: string
}>

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
  searchParams,
}: {
  params: Params
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

  // Yetkiler YALNIZCA sunucuda doğrulanır; düzenleme formu questions.edit
  // izni yoksa hiç render edilmez (fail-closed).
  const canEdit = await hasAdminPermission("questions.edit")
  let canPublish = await hasAdminPermission("questions.approve")
  if (!canPublish) {
    canPublish = await hasAdminPermission("ai.manage")
  }

  const { id } = await params
  const flashParams = await searchParams

  const readinessNeeded = canEdit || canPublish
  const [result, readiness] = await Promise.all([
    getQuestionDetail(id),
    readinessNeeded && canPublish
      ? getPublicationReadiness(id)
      : Promise.resolve(null),
  ])

  if (result.status === "error") {
    return (
      <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
        <div className="mx-auto max-w-3xl">
          <Link
            href="/admin/questions"
            className="mb-4 inline-block rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
          >
            {M.backToList}
          </Link>
          <p
            role="alert"
            className="rounded-2xl border border-amber-200 bg-amber-50 px-6 py-10 text-amber-800"
          >
            {M.detailError}
          </p>
        </div>
      </main>
    )
  }

  const question = result.item

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

  const inputClassName =
    "mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"

  return (
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-3xl">
        <Link
          href="/admin/questions"
          className="mb-4 inline-block rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
        >
          {M.backToList}
        </Link>

        {flashParams.error && (
          <div
            role="alert"
            className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-red-800"
          >
            {flashParams.error}
          </div>
        )}

        {!flashParams.error && flashParams.ok && (
          <div
            role="status"
            className="mb-4 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-emerald-800"
          >
            {flashParams.ok}
          </div>
        )}

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

        {canEdit && (
          <section
            aria-label="Soru düzenleme"
            className="mt-6 rounded-2xl border border-gray-200 bg-white p-6 shadow-sm"
          >
            <h2 className="text-lg font-semibold text-gray-900">
              Soruyu Düzenle
            </h2>
            <p className="mt-1 text-sm text-gray-500">
              Soru metni, seçenekler ve doğru cevap düzenlenebilir. Boş
              bırakılan E seçeneği kayıttan kaldırılır.
            </p>

            <form action={editQuestionAction} className="mt-4 grid gap-4">
              <input type="hidden" name="questionId" value={question.id} />

              <div>
                <label
                  htmlFor="edit-question-text"
                  className="block text-sm font-medium text-gray-700"
                >
                  Soru metni
                </label>
                <textarea
                  id="edit-question-text"
                  name="questionText"
                  rows={4}
                  required
                  defaultValue={question.question_text ?? ""}
                  className={inputClassName}
                />
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                {(
                  [
                    ["A", question.option_a],
                    ["B", question.option_b],
                    ["C", question.option_c],
                    ["D", question.option_d],
                    ["E", question.option_e],
                  ] as const
                ).map(([label, value]) => (
                  <div key={label}>
                    <label
                      htmlFor={`edit-option-${label}`}
                      className="block text-sm font-medium text-gray-700"
                    >
                      {label} seçeneği
                      {label === "E" ? " (isteğe bağlı)" : ""}
                    </label>
                    <input
                      id={`edit-option-${label}`}
                      name={`option${label}`}
                      type="text"
                      required={label !== "E"}
                      defaultValue={value ?? ""}
                      className={inputClassName}
                    />
                  </div>
                ))}
              </div>

              <div>
                <label
                  htmlFor="edit-correct-answer"
                  className="block text-sm font-medium text-gray-700"
                >
                  Doğru cevap
                </label>
                <select
                  id="edit-correct-answer"
                  name="correctAnswer"
                  required
                  defaultValue={question.correct_answer ?? ""}
                  className={inputClassName}
                >
                  {OPTION_LABELS.map((label) => (
                    <option key={label} value={label}>
                      {label}
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <button
                  type="submit"
                  className="w-full rounded-xl bg-gray-900 px-5 py-2.5 font-semibold text-white hover:bg-gray-700 sm:w-auto"
                >
                  Değişiklikleri Kaydet
                </button>
              </div>
            </form>
          </section>
        )}

        {canPublish && (
          <section
            aria-label="Yayın kontrolü"
            className="mt-6 rounded-2xl border border-gray-200 bg-white p-6 shadow-sm"
          >
            <h2 className="text-lg font-semibold text-gray-900">
              Yayın Kontrolü
            </h2>

            {!readiness ? (
              <p className="mt-2 text-sm text-gray-600">
                {QUESTION_PUBLICATION_MESSAGES.readinessUnavailable}
              </p>
            ) : readiness.status === "error" ? (
              <p
                role="alert"
                className="mt-2 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800"
              >
                {QUESTION_PUBLICATION_MESSAGES.readinessUnavailable}
              </p>
            ) : (
              <>
                {readiness.blockers.length > 0 && (
                  <div className="mt-3">
                    <p className="text-sm font-medium text-red-800">
                      {QUESTION_PUBLICATION_MESSAGES.blockedTitle}
                    </p>
                    <ul className="mt-1 list-inside list-disc text-sm text-red-700">
                      {readiness.blockers.map((blocker) => (
                        <li key={blocker.code}>{blocker.message}</li>
                      ))}
                    </ul>
                  </div>
                )}

                {readiness.warnings.length > 0 && (
                  <div className="mt-3">
                    <p className="text-sm font-medium text-amber-800">
                      {QUESTION_PUBLICATION_MESSAGES.warningsTitle}
                    </p>
                    <ul className="mt-1 list-inside list-disc text-sm text-amber-700">
                      {readiness.warnings.map((warning) => (
                        <li key={warning.code}>{warning.message}</li>
                      ))}
                    </ul>
                  </div>
                )}

                {readiness.canActivate && readiness.blockers.length === 0 && (
                  <p className="mt-3 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">
                    {QUESTION_PUBLICATION_MESSAGES.readyTitle}
                  </p>
                )}

                <div className="mt-4 grid gap-4">
                  <form action={activateQuestionAction} className="grid gap-2">
                    <input
                      type="hidden"
                      name="questionId"
                      value={question.id}
                    />
                    <label
                      htmlFor="activate-reason"
                      className="block text-sm font-medium text-gray-700"
                    >
                      Yayın sebebi (isteğe bağlı)
                    </label>
                    <input
                      id="activate-reason"
                      name="reason"
                      type="text"
                      maxLength={500}
                      className={inputClassName}
                    />
                    <button
                      type="submit"
                      disabled={readiness.currentIsActive !== false || !readiness.canActivate}
                      title={
                        readiness.currentIsActive === true
                          ? "Soru zaten yayında."
                          : !readiness.canActivate
                            ? "Yayın engelleri çözülmeden yayınlanamaz."
                            : undefined
                      }
                      className={`w-full rounded-xl px-5 py-2.5 font-semibold sm:w-auto ${
                        readiness.currentIsActive === false && readiness.canActivate
                          ? "bg-emerald-700 text-white hover:bg-emerald-800"
                          : "cursor-not-allowed bg-gray-100 text-gray-400"
                      }`}
                    >
                      Öğrencilere Yayınla
                    </button>
                  </form>

                  <form action={deactivateQuestionAction} className="grid gap-2">
                    <input
                      type="hidden"
                      name="questionId"
                      value={question.id}
                    />
                    <label
                      htmlFor="deactivate-reason"
                      className="block text-sm font-medium text-gray-700"
                    >
                      Geri çekme sebebi (zorunlu)
                    </label>
                    <input
                      id="deactivate-reason"
                      name="reason"
                      type="text"
                      maxLength={500}
                      required
                      className={inputClassName}
                    />
                    <button
                      type="submit"
                      disabled={readiness.currentIsActive !== true}
                      title={
                        readiness.currentIsActive === false
                          ? "Soru zaten yayında değil."
                          : undefined
                      }
                      className={`w-full rounded-xl px-5 py-2.5 font-semibold sm:w-auto ${
                        readiness.currentIsActive === true
                          ? "bg-red-700 text-white hover:bg-red-800"
                          : "cursor-not-allowed bg-gray-100 text-gray-400"
                      }`}
                    >
                      Yayından Geri Çek
                    </button>
                  </form>
                </div>
              </>
            )}
          </section>
        )}
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
