import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  AnalyticsError,
  analyticsReferenceNow,
  computeTopicPriorities,
  fetchStudentAttemptTrend,
  fetchStudentDimensionSummary,
} from "@/lib/analytics/service"
import StudentAnalytics from "@/components/student/StudentAnalytics"
import StudentHome from "@/components/student/StudentHome"

/** Trend isteği başarısızsa boş listeyle düşer; hatayı yutar. */
async function safeTrend(
  client: Parameters<typeof fetchStudentAttemptTrend>[0],
  days: number
) {
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
        <div
          role="alert"
          aria-live="assertive"
          className="rounded-2xl border border-danger-700 bg-danger-100 p-5 text-danger-700"
        >
          Öğrenci profilin şu anda görüntülenemiyor. Lütfen tekrar deneyin.
        </div>
      </main>
    )
  }

  let priorities: Awaited<ReturnType<typeof computeTopicPriorities>> = []
  let outcomeRows: Awaited<
    ReturnType<typeof fetchStudentDimensionSummary>
  > = []
  let analyticsError: string | null = null

  try {
    const dimensionRows = await fetchStudentDimensionSummary(supabase)
    outcomeRows = dimensionRows
    priorities = computeTopicPriorities(dimensionRows, analyticsReferenceNow())
  } catch (error) {
    analyticsError =
      error instanceof AnalyticsError
        ? error.message
        : "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin."
  }

  const trend7 = await safeTrend(supabase, 7)
  const trend30 = await safeTrend(supabase, 30)

  return (
    <main className="mx-auto w-full max-w-5xl p-6">
      <StudentHome
        nickname={profile.nickname}
        gradeLevel={profile.grade_level}
        priorities={priorities}
        trend7={trend7}
        outcomeRows={outcomeRows}
        referenceNow={analyticsReferenceNow()}
        analyticsError={analyticsError}
      />

      <StudentAnalytics
        priorities={priorities}
        trend7={trend7}
        trend30={trend30}
      />
    </main>
  )
}
