/**
 * Haftalik kota gostergesi (163, AK-MEB-VAULT-42-22).
 *
 * Ogrencinin KENDİ haftalik yarisma/yeni soru durumunu gosterir.
 * Veri yalnizca weekly_quota_status() RPC'sinden gelir (server-side
 * fetch); yerel sayac UYDURULMAZ.
 *
 * Kurallar:
 *  - academicYear === null (gecerli akademik donem yok — teknik durum)
 *    veya veri yoksa HICBIR sey gosterilmez; yanlis kalan hak üretilmez.
 *  - Kota tukendisinde ogrenciye tam olarak urun karari mesaji gosterilir.
 *  - Bu bilesen bilgi amacli UX'tir; guvenlik siniri 163 sunucu
 *    tetikleri ve RPC'lerinde kalmalidir.
 *  - 165 ders bazli mod (AK-QUOTA-SUBJECT-01): subjectSnapshot verildiginde
 *    kuresel sayi GOSTERILMEZ; sayilar ders kartlarindadir.
 */

import { COMPETITION_ERROR_MESSAGES } from "@/lib/competition/errors"
import {
  weeklyQuotaBlocksJoin,
  weeklyQuotaCompetitionsRemaining,
  weeklyQuotaNewQuestionsRemaining,
  type SubjectWeeklyQuotaSnapshot,
  type WeeklyQuotaStatus,
} from "@/lib/competition/types"

export default function WeeklyQuotaBanner({
  quota,
  subjectSnapshot = null,
}: {
  quota: WeeklyQuotaStatus | null
  /**
   * 165 ders bazli mod (AK-QUOTA-SUBJECT-01): dogrulugunda kuresel sayi
   * GOSTERILMEZ; banner yalniz model bilgisi tasiyan baslik gosterir.
   * Ders bazli sayilar her ders KARTINDA (MatchmakingQueue) gösterilir —
   * boylece bir dersin dolan hakri digeri yanlis gosterilmez.
   */
  subjectSnapshot?: SubjectWeeklyQuotaSnapshot | null
}) {
  // Ders bazli mod: kuresel sayi uydurulmaz; gecerli donem yoksa hicbir
  // sey gosterilmez (fail-closed, 163 ilkesiyle ayni).
  if (subjectSnapshot) {
    if (subjectSnapshot.academicYear === null) return null
    return (
      <section
        aria-label="Ders bazlı haftalık yarışma hakkı"
        className="mt-6 rounded-2xl border border-border bg-surface-muted p-4"
      >
        <h2 className="text-sm font-semibold text-ink">Bu haftaki hakların</h2>
        <p className="mt-1 text-sm text-ink-muted">
          Her dersten haftada en fazla 40 yarışma ve 200 yeni soru hakkın var.
          Her dersin hakkı ayrıdır; bir derste hakların bitmesi diğer
          derslerini etkilemez. Güncel haklarını her dersin kartında görebilirsin.
        </p>
      </section>
    )
  }

  // Teknik durumlar (RPC hatasi / donem yok) icin sayi uydurulmaz.
  if (!quota || quota.academicYear === null) return null

  const competitionsRemaining = weeklyQuotaCompetitionsRemaining(quota)
  const newQuestionsRemaining = weeklyQuotaNewQuestionsRemaining(quota)
  const blocked = weeklyQuotaBlocksJoin(quota)

  return (
    <section
      aria-label="Haftalık yarışma hakkı"
      className="mt-6 rounded-2xl border border-border bg-surface-muted p-4"
    >
      <h2 className="text-sm font-semibold text-ink">Bu haftaki hakların</h2>
      <p className="mt-1 text-sm text-ink-muted">
        Yarışma: {quota.competitionsUsed}/{quota.competitionsLimit} kullanılan
        {" — "}
        {competitionsRemaining} yarışma hakkın kaldı.
        {" · "}
        Yeni soru: {quota.newQuestionsUsed}/{quota.newQuestionsLimit} kullanılan
        {" — "}
        {newQuestionsRemaining} yeni soru hakkın kaldı.
      </p>
      {blocked && (
        <p
          className="mt-2 text-sm font-medium text-warning-900"
          role="status"
          aria-live="polite"
        >
          {COMPETITION_ERROR_MESSAGES.weeklyQuota}
        </p>
      )}
    </section>
  )
}
