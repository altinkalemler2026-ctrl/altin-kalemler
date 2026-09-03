import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  AnalyticsError,
  analyticsReferenceNow,
  computeTopicPriorities,
  fetchStudentAttemptTrend,
  fetchStudentDimensionSummary,
  type AnalyticsClient,
} from "@/lib/analytics/service"
import type {
  AttemptTrendDay,
  PriorityTopicDto,
} from "@/lib/analytics/types"
import StudentAnalytics from "@/components/student/StudentAnalytics"

/** Trend isteği başarısızsa boş listeyle düşer; hatayı yutar. */
async function safeTrend(
  client: AnalyticsClient,
  days: number
): Promise<AttemptTrendDay[]> {
  try {
    return await fetchStudentAttemptTrend(client, days)
  } catch {
    return []
  }
}

export default async function DashboardPage() {
  const supabase = await createClient()

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser()

  if (userError || !user) {
    redirect("/login")
  }

  const { data: profile, error: profileError } = await supabase
    .from("student_profiles")
    .select("nickname, grade_level")
    .eq("id", user.id)
    .single()

  if (profileError || !profile) {
    return (
      <main className="mx-auto w-full max-w-3xl p-6">
        <div className="rounded-2xl border border-red-200 bg-red-50 p-5 text-red-700">
          Öğrenci profili bulunamadı.
        </div>
      </main>
    )
  }

  let priorities: PriorityTopicDto[] = []
  let analyticsError: string | null = null

  try {
    const dimensionRows = await fetchStudentDimensionSummary(supabase)
    priorities = computeTopicPriorities(dimensionRows, analyticsReferenceNow())
  } catch (error) {
    analyticsError =
      error instanceof AnalyticsError
        ? error.message
        : "Analiz verisi şu anda yüklenemedi."
  }

  const [trend7, trend30] = await Promise.all([
    safeTrend(supabase, 7),
    safeTrend(supabase, 30),
  ])

  return (
    <main className="mx-auto w-full max-w-5xl p-6">
      <section className="rounded-3xl border border-gray-200 bg-white p-6 shadow-sm sm:p-8">
        <p className="text-sm font-medium text-gray-500">
          Altın Kalemler
        </p>

        <h1 className="mt-2 text-3xl font-bold text-gray-900">
          Hoş geldin, {profile.nickname}
        </h1>

        <p className="mt-2 text-gray-600">
          {profile.grade_level}. sınıf öğrenci panelindesin.
        </p>

        <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Link
            href="/training"
            className="flex min-h-11 flex-col rounded-2xl border border-gray-200 p-5 transition hover:border-gray-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            <h2 className="font-semibold text-gray-900">Konu Çalış</h2>
            <p className="mt-2 text-sm text-gray-600">
              Ders ve konu seçerek soru çöz.
            </p>
            <span className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-gray-900">
              Çalışmaya başla
              <span aria-hidden="true">→</span>
            </span>
          </Link>

          <Link
            href="/competition"
            className="flex min-h-11 flex-col rounded-2xl border border-gray-200 p-5 transition hover:border-gray-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            <h2 className="font-semibold text-gray-900">Yarismalar</h2>
            <p className="mt-2 text-sm text-gray-600">
              Rakiplerle bilgi yarismalarina katil.
            </p>
            <span className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-gray-900">
              Yarismaya basla
              <span aria-hidden="true">&rarr;</span>
            </span>
          </Link>

          <div className="rounded-2xl border border-gray-200 p-5">
            <h2 className="font-semibold text-gray-900">Başarılarım</h2>
            <p className="mt-2 text-sm text-gray-600">
              Puanlarını ve ilerlemeni takip et.
            </p>
          </div>
        </div>
      </section>

      {analyticsError ? (
        <section
          aria-labelledby="analytics-error-title"
          className="mt-8 rounded-2xl border border-amber-300 bg-amber-50 p-5 text-amber-900"
          role="alert"
        >
          <h2 id="analytics-error-title" className="font-semibold">
            Çalışma önerileri şu anda yüklenemedi
          </h2>
          <p className="mt-1 text-sm">{analyticsError}</p>
        </section>
      ) : (
        <StudentAnalytics
          priorities={priorities}
          trend7={trend7}
          trend30={trend30}
        />
      )}
    </main>
  )
}