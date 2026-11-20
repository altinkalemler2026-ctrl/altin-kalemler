import { redirect } from "next/navigation"

import { createClient } from "@/lib/supabase/server"
import { ThemeSurface } from "@/lib/ui/theme-context"
import { dersListesiniFiltrele } from "@/lib/gizli-dersler"
import MatchmakingQueue from "@/components/student/MatchmakingQueue"
import WeeklyQuotaBanner from "@/components/student/WeeklyQuotaBanner"
import {
  getWeeklyQuotaStatus,
  getWeeklyQuotaStatusPerSubject,
} from "@/lib/competition/service"
import { isSubjectQuotaEnabled } from "@/lib/competition/quota-mode"
import {
  subjectQuotaBlocksJoin,
  weeklyQuotaBlocksJoin,
  type SubjectWeeklyQuotaSnapshot,
  type SubjectWeeklyQuotaStatus,
  type WeeklyQuotaStatus,
} from "@/lib/competition/types"

export const metadata = {
  title: "Yarışmalar — Altın Kalemler",
}

export default async function CompetitionPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect("/login")
  }

  const { data: subjects, error } = await supabase
    .from("subjects")
    .select("id, name")
    .eq("is_active", true)
    .order("sort_order", { ascending: true })
    .order("name", { ascending: true })

  // 163 haftalik kota: veri yalnizca weekly_quota_status() RPC'sinden
  // gelir (her sayfa render'inda taze — yukarida kotasi tukenen ogrenci
  // sayfaya donunce guncel durumu gorur). RPC/teknik hatada kota null:
  // gosterge hicbir sayi uydurmaz, butonlar kapanmaz; koruma sunucudadir.
  //
  // 165 ders bazli mod (AK-QUOTA-SUBJECT-01): QUOTA_PER_SUBJECT_ENABLED
  // bayragi yalniz 165 canliya uygulandiktan SONRA acilir (quota-mode.ts).
  // Bayrak kapali iken davranis 163 ile birebir aynidir.
  const subjectQuotaMode = isSubjectQuotaEnabled()
  let quota: WeeklyQuotaStatus | null = null
  let subjectSnapshot: SubjectWeeklyQuotaSnapshot | null = null
  try {
    if (subjectQuotaMode) {
      subjectSnapshot = await getWeeklyQuotaStatusPerSubject(supabase)
    } else {
      quota = await getWeeklyQuotaStatus(supabase)
    }
  } catch {
    quota = null
    subjectSnapshot = null
  }
  const quotaBlocked = weeklyQuotaBlocksJoin(quota)

  // Ders bazli modda eslesmeyen/eksik ders kaydi: null → sayi gostermesiz,
  // kilitlemesiz (uydurma yok; gercek kapida sunucu KOTA_165 vurur).
  const quotaBySubject = new Map<string, SubjectWeeklyQuotaStatus>(
    subjectSnapshot && subjectSnapshot.academicYear !== null
      ? subjectSnapshot.subjects.map((s) => [s.subjectId, s])
      : []
  )

  // CURRICULUM-ALL-01: Geometri/Türkçe ders seçim listelerinde gizli.
  const gosterilecekDersler = dersListesiniFiltrele(subjects ?? [])

  if (error || !subjects || gosterilecekDersler.length === 0) {
    return (
      <ThemeSurface className="min-h-dvh bg-page">
        <main className="mx-auto w-full max-w-3xl p-6">
          <div className="rounded-2xl border border-danger-700 bg-danger-100 p-5 text-danger-700">
            Dersler yüklenirken bir sorun oluştu. Lütfen sayfayı yenileyip tekrar
            dene.
          </div>
        </main>
      </ThemeSurface>
    )
  }

  return (
    <ThemeSurface className="min-h-dvh bg-page">
      <main className="mx-auto w-full max-w-3xl p-6">
        <section className="rounded-3xl border border-border bg-surface p-6 shadow-sm sm:p-8">
          <p className="text-sm font-medium text-ink-muted">Altın Kalemler</p>
          <h1 className="mt-2 text-3xl font-bold text-ink">Yarışmalar</h1>

          <WeeklyQuotaBanner quota={quota} subjectSnapshot={subjectSnapshot} />

          <div className="mt-6 grid gap-4 sm:grid-cols-2">
            {gosterilecekDersler.map((subject) => {
              // Ders bazli modda kilit YALNIZ o dersin kartini kapatir
              // (ürün karari 10); kuresel modda 163 davranisi aynen durur.
              const subjectQuota = quotaBySubject.get(subject.id) ?? null
              return (
                <MatchmakingQueue
                  key={subject.id}
                  subjectId={subject.id}
                  subjectName={subject.name}
                  quotaBlocked={
                    subjectSnapshot
                      ? subjectQuotaBlocksJoin(subjectQuota)
                      : quotaBlocked
                  }
                  quota={subjectQuota}
                />
              )
            })}
          </div>

          <p className="mt-4 text-ink-muted">
            Bir ders seç ve aynı sınıf düzeyinden bir rakiple eşleşmek için
            sıraya katıl. Yarışma beş sorudan oluşur ve puanını sunucu hesaplar.
          </p>
        </section>
      </main>
    </ThemeSurface>
  )
}
