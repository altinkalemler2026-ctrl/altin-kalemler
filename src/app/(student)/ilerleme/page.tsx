import { redirect } from "next/navigation"

import StudentProgress from "@/components/student/StudentProgress"
import { AnalyticsError, fetchStudentDimensionSummary } from "@/lib/analytics/service"
import { createClient } from "@/lib/supabase/server"

export const metadata = {
  title: "İlerlemem | Altın Kalemler",
}

/**
 * Faz 11: Öğrencinin kendi kazanım ilerlemesi.
 *
 * - Kimlik ASLA query parametresinden alınmaz; oturum auth.uid()
 *   üzerinden doğrulanır ve veri yalnız kendi RPC'sinden (085) gelir.
 * - Hata ham DB metni olarak döndürülmez; güvenli Türkçe mesaj.
 */
export default async function ProgressPage() {
  const supabase = await createClient()

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser()

  if (userError || !user) {
    redirect("/login")
  }

  let rows: Awaited<ReturnType<typeof fetchStudentDimensionSummary>> = []
  let progressError: string | null = null

  try {
    rows = await fetchStudentDimensionSummary(supabase)
  } catch (error) {
    progressError =
      error instanceof AnalyticsError
        ? error.message
        : "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin."
  }

  return (
    <main className="mx-auto w-full max-w-3xl p-4 sm:p-6">
      <StudentProgress rows={rows} error={progressError} />
    </main>
  )
}
