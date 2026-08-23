import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import { CALENDAR_ERROR_MESSAGES } from "@/lib/admin/academic-calendar-errors"
import {
  deleteWeekAction,
  upsertWeekAction,
} from "./actions"

type PermissionRpc = (
  functionName: "academic_calendar_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

type YearsRpc = (
  functionName: "academic_calendar_list_years",
  args: Record<string, never>,
) => Promise<{
  data: { academic_year: string; week_count: number }[] | null
  error: { message: string } | null
}>

type WeeksRpc = (
  functionName: "academic_calendar_list_weeks",
  args: { p_year: string },
) => Promise<{
  data:
    | {
        academic_year: string
        week: number
        starts_at: string
        ends_at: string
        is_started: boolean
      }[]
    | null
  error: { message: string } | null
}>

type SearchParams = Promise<{
  year?: string
  ok?: string
  error?: string
}>

export default async function AcademicCalendarPage({
  searchParams,
}: {
  searchParams: SearchParams
}) {
  const supabase = await createClient()

  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    redirect("/login")
  }

  const permissionRpc = supabase.rpc.bind(
    supabase
  ) as unknown as PermissionRpc

  const { data: canManage, error: permissionError } =
    await permissionRpc("academic_calendar_has_permission", {
      p_permission_code: "calendar.manage",
    })

  if (permissionError || canManage !== true) {
    redirect("/dashboard")
  }

  const params = await searchParams

  const yearsRpc = supabase.rpc.bind(
    supabase
  ) as unknown as YearsRpc

  const { data: yearsData, error: yearsError } =
    await yearsRpc("academic_calendar_list_years", {})

  if (yearsError) {
    throw new Error(CALENDAR_ERROR_MESSAGES.generic)
  }

  const years = yearsData ?? []
  const selectedYear =
    params.year?.trim() || years[0]?.academic_year || ""

  let weeks: {
    academic_year: string
    week: number
    starts_at: string
    ends_at: string
    is_started: boolean
  }[] = []

  if (selectedYear) {
    const weeksRpc = supabase.rpc.bind(
      supabase
    ) as unknown as WeeksRpc

    const { data: weeksData, error: weeksError } =
      await weeksRpc("academic_calendar_list_weeks", {
        p_year: selectedYear,
      })

    if (weeksError) {
      throw new Error(CALENDAR_ERROR_MESSAGES.generic)
    }

    weeks = weeksData ?? []
  }

  return (
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-5xl">
        <div className="mb-6">
          <h1 className="text-3xl font-bold text-gray-900">
            Akademik Takvim
          </h1>
          <p className="mt-2 text-gray-600">
            Akademik yıl ve hafta kayıtlarını yönetin. Başlamış veya geçmiş
            haftalar değiştirilemez; öğrenci denemesi içeren haftalar
            silinemez.
          </p>
        </div>

        {params.error && (
          <div
            role="alert"
            className="mb-6 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-red-800"
          >
            {params.error}
          </div>
        )}

        {!params.error && params.ok && (
          <div
            role="status"
            className="mb-6 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-emerald-800"
          >
            {params.ok}
          </div>
        )}

        <form
          method="get"
          className="mb-6 flex flex-wrap items-center gap-3 rounded-2xl border border-gray-200 bg-white p-4 shadow-sm"
        >
          <label
            htmlFor="year-select"
            className="text-sm font-medium text-gray-700"
          >
            Akademik yıl
          </label>

          <select
            id="year-select"
            name="year"
            defaultValue={selectedYear}
            className="rounded-xl border border-gray-300 px-4 py-2.5 text-gray-900 outline-none focus:border-gray-500"
          >
            {years.map((year) => (
              <option key={year.academic_year} value={year.academic_year}>
                {year.academic_year} ({year.week_count} hafta)
              </option>
            ))}
          </select>

          <button
            type="submit"
            className="rounded-xl bg-gray-900 px-5 py-2.5 font-semibold text-white hover:bg-gray-700"
          >
            Göster
          </button>
        </form>

        <section className="mb-8 rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
          <h2 className="text-lg font-semibold text-gray-900">
            Hafta ekle veya güncelle
          </h2>

          <p className="mt-1 text-sm text-gray-500">
            Aynı yıl ve hafta numarası mevcutsa kayıt güncellenir.
          </p>

          <form
            action={upsertWeekAction}
            className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-5"
          >
            <input type="hidden" name="year" value={selectedYear} />

            <div>
              <label
                htmlFor="week-number"
                className="block text-sm font-medium text-gray-700"
              >
                Hafta (0-52)
              </label>
              <input
                id="week-number"
                name="week"
                type="number"
                min={0}
                max={52}
                required
                className="mt-1 w-full rounded-xl border border-gray-300 px-4 py-2.5 text-gray-900 outline-none focus:border-gray-500"
              />
            </div>

            <div>
              <label
                htmlFor="starts-at"
                className="block text-sm font-medium text-gray-700"
              >
                Başlangıç
              </label>
              <input
                id="starts-at"
                name="startsAt"
                type="date"
                required
                className="mt-1 w-full rounded-xl border border-gray-300 px-4 py-2.5 text-gray-900 outline-none focus:border-gray-500"
              />
            </div>

            <div>
              <label
                htmlFor="ends-at"
                className="block text-sm font-medium text-gray-700"
              >
                Bitiş (hariç)
              </label>
              <input
                id="ends-at"
                name="endsAt"
                type="date"
                required
                className="mt-1 w-full rounded-xl border border-gray-300 px-4 py-2.5 text-gray-900 outline-none focus:border-gray-500"
              />
            </div>

            <div className="flex items-end lg:col-span-2">
              <button
                type="submit"
                className="w-full rounded-xl bg-emerald-700 px-5 py-2.5 font-semibold text-white hover:bg-emerald-800 sm:w-auto"
              >
                Kaydet
              </button>
            </div>
          </form>
        </section>

        <section className="rounded-2xl border border-gray-200 bg-white shadow-sm">
          <div className="border-b border-gray-200 bg-gray-50 px-6 py-4">
            <h2 className="font-semibold text-gray-900">
              Haftalar{" "}
              {selectedYear ? `· ${selectedYear}` : ""}
            </h2>
          </div>

          {weeks.length === 0 ? (
            <p className="px-6 py-8 text-gray-600">
              Bu akademik yıla ait hafta kaydı yok. Takvim boşken öğrenci
              soru akışı güvenlik nedeniyle durur.
            </p>
          ) : (
            <ul className="divide-y divide-gray-200">
              {weeks.map((row) => {
                // Sunucu-otoritatif bayrak: starts_at <= current_date (RPC).
                const started = row.is_started

                return (
                  <li
                    key={`${row.academic_year}-${row.week}`}
                    className="flex flex-wrap items-center gap-x-6 gap-y-3 px-6 py-4"
                  >
                    <span className="w-20 font-semibold text-gray-900">
                      {row.week}. hafta
                    </span>

                    <span className="text-gray-700">
                      {row.starts_at} → {row.ends_at}
                    </span>

                    {started && (
                      <span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-medium text-amber-800">
                        Başladı
                      </span>
                    )}

                    <div className="ml-auto flex flex-wrap items-end gap-2">
                      <form
                        action={upsertWeekAction}
                        className="flex flex-wrap items-end gap-2"
                      >
                        <input
                          type="hidden"
                          name="year"
                          value={row.academic_year}
                        />
                        <input
                          type="hidden"
                          name="week"
                          value={row.week}
                        />
                        <label className="sr-only" htmlFor={`starts-${row.week}`}>
                          Başlangıç
                        </label>
                        <input
                          id={`starts-${row.week}`}
                          type="date"
                          name="startsAt"
                          defaultValue={row.starts_at}
                          disabled={started}
                          className="rounded-lg border border-gray-300 px-2 py-1.5 text-sm text-gray-900 disabled:bg-gray-100 disabled:text-gray-400"
                        />
                        <label className="sr-only" htmlFor={`ends-${row.week}`}>
                          Bitiş
                        </label>
                        <input
                          id={`ends-${row.week}`}
                          type="date"
                          name="endsAt"
                          defaultValue={row.ends_at}
                          disabled={started}
                          className="rounded-lg border border-gray-300 px-2 py-1.5 text-sm text-gray-900 disabled:bg-gray-100 disabled:text-gray-400"
                        />
                        <button
                          type="submit"
                          disabled={started}
                          title={
                            started
                              ? "Başlamış haftalar değiştirilemez."
                              : undefined
                          }
                          className={`rounded-lg px-3 py-1.5 text-sm font-medium ${
                            started
                              ? "cursor-not-allowed bg-gray-100 text-gray-400"
                              : "bg-gray-900 text-white hover:bg-gray-700"
                          }`}
                        >
                          Güncelle
                        </button>
                      </form>

                      <form action={deleteWeekAction}>
                        <input
                          type="hidden"
                          name="year"
                          value={row.academic_year}
                        />
                        <input
                          type="hidden"
                          name="week"
                          value={row.week}
                        />
                        <button
                          type="submit"
                          disabled={started}
                          title={
                            started
                              ? "Başlamış haftalar silinemez."
                              : undefined
                          }
                          className={`rounded-lg px-3 py-1.5 text-sm font-medium ${
                            started
                              ? "cursor-not-allowed bg-gray-100 text-gray-400"
                              : "bg-red-700 text-white hover:bg-red-800"
                          }`}
                        >
                          Sil
                        </button>
                      </form>
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </section>
      </div>
    </main>
  )
}
