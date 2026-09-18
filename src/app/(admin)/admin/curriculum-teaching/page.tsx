import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  hasCurriculumTeachingPermission,
  listCurriculumTeachingApprovals,
  listCurriculumTeachingMeta,
  type CurriculumTeachingItem,
} from "@/lib/admin/curriculum-teaching"
import { setTeachingApprovalAction } from "./actions"
import {
  CURRICULUM_TEACHING_ERROR_MESSAGES as TE,
} from "@/lib/admin/curriculum-teaching-errors"

type SearchParams = Promise<{
  subject?: string
  year?: string
  ok?: string
  error?: string
}>

const STATUS_LABELS: Record<string, string> = {
  approved: "Onaylandı",
  rejected: "Reddedildi",
}

function StatusBadge({ status }: { status: string | null }) {
  if (status === "approved") {
    return (
      <span className="inline-flex items-center rounded-full bg-green-100 px-3 py-1 text-sm font-medium text-green-800">
        {STATUS_LABELS.approved}
      </span>
    )
  }
  if (status === "rejected") {
    return (
      <span className="inline-flex items-center rounded-full bg-red-100 px-3 py-1 text-sm font-medium text-red-800">
        {STATUS_LABELS.rejected}
      </span>
    )
  }
  return (
    <span className="inline-flex items-center rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-600">
      İşlenmedi
    </span>
  )
}

function ApprovalForm({
  item,
  subjectId,
  year,
}: {
  item: CurriculumTeachingItem
  subjectId: string
  year: string
}) {
  return (
    <form
      action={setTeachingApprovalAction}
      className="flex flex-wrap items-center gap-2"
      aria-label={`${item.topicName ?? "Konu"} onay durumu`}
    >
      <input type="hidden" name="schedule_item_id" value={item.scheduleItemId} />
      <input type="hidden" name="academic_year" value={year} />
      <input type="hidden" name="subject_id" value={subjectId} />

      <label className="sr-only" htmlFor={`notes-${item.scheduleItemId}`}>
        Not
      </label>
      <input
        id={`notes-${item.scheduleItemId}`}
        name="notes"
        type="text"
        maxLength={500}
        placeholder="Not (isteğe bağlı)"
        className="w-full rounded-xl border border-gray-300 px-3 py-2 text-sm text-gray-900 outline-none focus:border-gray-500 sm:w-44"
      />

      <button
        type="submit"
        name="status"
        value="approved"
        className="rounded-xl bg-green-700 px-4 py-2 text-sm font-semibold text-white hover:bg-green-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-green-600 focus-visible:ring-offset-2"
      >
        Onayla
      </button>

      <button
        type="submit"
        name="status"
        value="rejected"
        className="rounded-xl border border-red-300 bg-red-50 px-4 py-2 text-sm font-semibold text-red-700 hover:bg-red-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-red-500 focus-visible:ring-offset-2"
      >
        Reddet
      </button>
    </form>
  )
}

export default async function AdminCurriculumTeachingPage({
  searchParams,
}: {
  searchParams: SearchParams
}) {
  const supabase = await createClient()

  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    redirect("/login")
  }

  // curriculum.manage izni yoksa sayfa hiç render edilmez (fail-closed);
  // atomik yetki doğrulaması zaten RPC içinde tekrarlanır.
  if (!(await hasCurriculumTeachingPermission())) {
    redirect("/dashboard")
  }

  const meta = await listCurriculumTeachingMeta()
  if (meta.status === "error") {
    throw new Error(TE.generic)
  }

  const params = await searchParams
  const subjectId = params.subject?.trim() || ""
  const year = params.year?.trim() || ""

  const subjects = meta.subjects
  const years = meta.years.slice(0, 5)
  const selectedYear = year || years[0]?.academicYear || ""

  let items: CurriculumTeachingItem[] = []
  let listError = false

  if (subjectId && selectedYear) {
    const result = await listCurriculumTeachingApprovals(
      subjectId,
      selectedYear
    )
    if (result.status === "error") {
      listError = true
    } else {
      items = result.items
    }
  }

  return (
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-6xl">
        <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-3xl font-bold text-gray-900">
              Öğretmen Konu Onayı
            </h1>
            <p className="mt-2 text-gray-600">
              Seçilen ders ve akademik yıl için takvimdeki konuların öğretmen
              onayı durumunu görüntüleyin ve yönetin.
            </p>
          </div>
          <Link
            href="/admin"
            className="rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
          >
            Panele dön
          </Link>
        </div>

        {params.ok ? (
          <p
            role="status"
            aria-live="polite"
            className="mb-4 rounded-xl border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800"
          >
            {params.ok}
          </p>
        ) : null}
        {params.error ? (
          <p
            role="alert"
            aria-live="assertive"
            className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"
          >
            {params.error}
          </p>
        ) : null}

        <form
          method="get"
          className="mb-6 flex flex-wrap items-end gap-3 rounded-2xl border border-gray-200 bg-white p-4 shadow-sm"
        >
          <label className="block">
            <span className="text-sm font-medium text-gray-700">Ders</span>
            <select
              name="subject"
              defaultValue={subjectId}
              required
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            >
              <option value="">Ders seçin</option>
              {subjects.map((subject) => (
                <option key={subject.id} value={subject.id}>
                  {subject.name}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              Akademik yıl
            </span>
            <select
              name="year"
              defaultValue={selectedYear}
              required
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            >
              <option value="">Yıl seçin</option>
              {years.map((y) => (
                <option key={y.academicYear} value={y.academicYear}>
                  {y.academicYear}
                </option>
              ))}
            </select>
          </label>

          <button
            type="submit"
            className="rounded-xl bg-gray-900 px-5 py-2.5 font-semibold text-white hover:bg-gray-700"
          >
            Listele
          </button>
        </form>

        {subjectId && selectedYear ? (
          <section className="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
            {listError ? (
              <p role="alert" className="px-6 py-10 text-gray-600">
                {TE.generic}
              </p>
            ) : items.length === 0 ? (
              <p className="px-6 py-10 text-gray-600">
                Bu filtrelerle eşleşen takvim öğesi bulunamadı.
              </p>
            ) : (
              <ul className="divide-y divide-gray-200">
                {items.map((item) => (
                  <li
                    key={item.scheduleItemId}
                    className="grid gap-3 px-6 py-4 lg:grid-cols-[8rem_1fr_10rem_auto] lg:items-center"
                  >
                    <div className="text-sm">
                      <p className="text-gray-500">
                        {item.gradeLevel}. sınıf
                      </p>
                      <p className="mt-1 font-mono text-xs text-gray-400">
                        {item.profileName
                          ? item.profileName
                          : "Bilinmeyen profil"}
                      </p>
                    </div>

                    <div className="min-w-0">
                      <p className="text-sm font-semibold text-gray-900">
                        {item.topicName ?? "Konu adı yok"}
                      </p>
                      {item.outcomeText ? (
                        <p className="mt-0.5 text-sm text-gray-600">
                          {item.outcomeText}
                        </p>
                      ) : null}
                    </div>

                    <div className="text-sm text-gray-500">
                      {item.startWeek !== null ? (
                        <span>K{item.startWeek}</span>
                      ) : (
                        <span>Haftasız</span>
                      )}
                    </div>

                    <div className="flex flex-col items-start gap-2 lg:items-end">
                      <StatusBadge status={item.status} />
                        <ApprovalForm
                          item={item}
                          subjectId={subjectId}
                          year={selectedYear}
                        />
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>
        ) : (
          <p className="rounded-2xl border border-dashed border-gray-300 bg-white px-6 py-10 text-gray-600">
            Ders ve akademik yıl seçin; konu onay durumlarını burada
            görüntüleyebilirsiniz.
          </p>
        )}
      </div>
    </main>
  )
}