import { createClient } from "@/lib/supabase/server"

/**
 * Faz 4 admin paneli özet metrik okuyucuları (salt okunur).
 *
 * - Sorgular doğrudan RLS kapsamında çalışır; yalnızca mevcut politikaların
 *   okunmasına izin verdiği veriler döndürülür. Yeni tablo/politika YOK.
 * - Her metrik tek başına hataya dayanır; bir metrik bozulursa diğerleri
 *   etkilenmez. Hata ham mesaj olarak UI'a sızmaz.
 */

export interface DashboardMetric {
  /** null = okunamadı (RLS/veri yokluğu değil, sorgu hatası). */
  value: number | null
  /** İsteğe bağlı alt kırılım: anahtar -> sayı. */
  breakdown?: Record<string, number>
}

export interface DashboardMetrics {
  published: DashboardMetric
  publishedByExamTrack: DashboardMetric
  reviewQueue: DashboardMetric
  staging: DashboardMetric
}

async function safeCount(
  query: PromiseLike<{
    count: number | null
    error: { message: string } | null
  } | null>
): Promise<number | null> {
  const result = await query
  const count = result?.count ?? 0
  return result?.error ? null : count
}

/**
 * Sınav kırılımı metriklerini derlerir; yalnızca okunabilen (null olmayan)
 * değerler kırılıma katılır. Boş sonuç `null` kırılım üretir.
 */
export function buildExamTrackBreakdown(
  pairs: readonly (readonly [string, number | null])[]
): DashboardMetric["breakdown"] | undefined {
  const breakdown: Record<string, number> = {}
  for (const [track, value] of pairs) {
    if (value !== null) breakdown[track] = value
  }
  return Object.keys(breakdown).length > 0 ? breakdown : undefined
}

/**
 * Yayındaki soru sayıları (onaylı + aktif; RLS'in öğrenci kümesi).
 */
async function publishedCounts(): Promise<{
  total: number | null
  byExamTrack: DashboardMetric
}> {
  const supabase = await createClient()

  const total = await safeCount(
    supabase
      .from("questions")
      .select("id", { count: "exact", head: true })
      .eq("approval_status", "approved")
      .eq("is_active", true)
  )

  const trackItems = await Promise.all(
    ["TYT", "AYT"].map(async (track) => {
      const value = await safeCount(
        supabase
          .from("questions")
          .select("id", { count: "exact", head: true })
          .eq("approval_status", "approved")
          .eq("is_active", true)
          .eq("exam_track", track)
      )
      return [track, value] as const
    })
  )

  const breakdown = buildExamTrackBreakdown(trackItems)

  return {
    total,
    byExamTrack:
      breakdown !== undefined
        ? { value: total, breakdown }
        : { value: total },
  }
}

/**
 * Admin-okunur inceleme tabloları sayıları (questions.view / ai.* kuralları).
 */
async function pipelineCounts(): Promise<{
  reviewQueue: DashboardMetric
  staging: DashboardMetric
}> {
  const supabase = await createClient()

  const reviewQueue = await safeCount(
    supabase.from("review_queue").select("id", { count: "exact", head: true })
  )

  const staging = await safeCount(
    supabase
      .from("ai_question_staging")
      .select("id", { count: "exact", head: true })
  )

  return {
    reviewQueue: { value: reviewQueue },
    staging: { value: staging },
  }
}

export async function loadDashboardMetrics(): Promise<DashboardMetrics> {
  const [published, pipeline] = await Promise.all([
    publishedCounts(),
    pipelineCounts(),
  ])

  return {
    published: { value: published.total },
    publishedByExamTrack: published.byExamTrack,
    reviewQueue: pipeline.reviewQueue,
    staging: pipeline.staging,
  }
}
