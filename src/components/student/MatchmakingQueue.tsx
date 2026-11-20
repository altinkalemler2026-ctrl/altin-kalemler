"use client"

/**
 * Eslesme kuyrugu bileseni (Faz 7).
 *
 * Durumlar: restoring -> idle/joining/queued/leaving/matched/expired/error
 *
 * FAZ 7 kurallari:
 *  - Beklerken polling YALNIZCA get_own_matchmaking_status (084) ile
 *    yapilir; bu RPC rate-limit tuketmez. join_matchmaking_queue
 *    yalnizca kullanici acikca katil dediginde VE zaman asimi
 *    sonrasinda tekrar katil dediginde bir kez cagrilir.
 *  - Sayfa yenilendiginde kuyruk/yarisma durumu 084 ile geri yuklenir
 *    (bekliyor / eslesti durumu kaybolmaz).
 *  - Kuyruk suresi doldugunda (not_queued) "zaman asimi" durumu
 *    gosterilir; kullanici tekrar katilabilir.
 *  - Rakip ozel verisi bu bilesende hic bulunmaz.
 */

import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"

import {
  getOwnMatchmakingStatusAction,
  joinMatchmakingQueueAction,
  leaveMatchmakingQueueAction,
} from "@/app/(student)/competition/actions"
import { COMPETITION_ERROR_MESSAGES } from "@/lib/competition/errors"
import {
  subjectQuotaCompetitionsRemaining,
  subjectQuotaNewQuestionsRemaining,
  type SubjectWeeklyQuotaStatus,
} from "@/lib/competition/types"

const POLL_INTERVAL_MS = 3_000

interface MatchmakingQueueProps {
  subjectId: string
  subjectName: string
  /**
   * 163 haftalik kota sunucu tarafindan bloklanmis (40/40 veya 5 yeni
   * soruya yetmeyen yeni soru hakki). YALNIZ UX kilididir; guvenlik
   * siniri 163 sunucu tetikleri/RPC'lerinde kalmalidir.
   */
  quotaBlocked?: boolean
  /**
   * 165 ders bazli kota (AK-QUOTA-SUBJECT-01): bu DERSIN guncel haftalik
   * durumu. Bayragi kapali/veri yoksa null → kart sayi GOSTERMEZ ve
   * kilitlemez (uydurma sayi yok). Yalniz bu karti etkiler; diger ders
   * kartlari bagimsizdir (urun karari 10).
   */
  quota?: SubjectWeeklyQuotaStatus | null
}

type ComponentState =
  | { phase: "restoring" }
  | { phase: "idle" }
  | { phase: "joining" }
  | { phase: "queued" }
  | { phase: "leaving" }
  | { phase: "matched"; competitionId: string; competitionCode: string }
  | { phase: "expired" }
  | { phase: "error"; message: string }

export default function MatchmakingQueue({
  subjectId,
  subjectName,
  quotaBlocked = false,
  quota = null,
}: MatchmakingQueueProps) {
  const router = useRouter()
  const [state, setState] = useState<ComponentState>({ phase: "restoring" })
  // Eszamanli tuketim: join KOTA_163/KOTA_165 donerse bilesen ici kilit
  // (sunucu yaniti tek gercek; bu yalniz gelen hatanin UI yansimasi).
  const [quotaLock, setQuotaLock] = useState(false)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const mountedRef = useRef(true)

  const blocked = quotaBlocked || quotaLock
  // Ders bazli modda (165) blok mesaji DERSE OZEL metindir; kuresel 163
  // davranisinda eski mesaj aynen kalir.
  const blockMessage = quota
    ? COMPETITION_ERROR_MESSAGES.weeklyQuotaSubject
    : COMPETITION_ERROR_MESSAGES.weeklyQuota

  const clearPoll = useCallback(() => {
    if (pollRef.current) {
      clearInterval(pollRef.current)
      pollRef.current = null
    }
  }, [])

  useEffect(() => {
    mountedRef.current = true
    return () => {
      mountedRef.current = false
      clearPoll()
    }
  }, [clearPoll])

  // Kuyruk beklerken periyodik durum sorgusu (084; rate-limit yok).
  const startStatusPolling = useCallback(() => {
    clearPoll()
    pollRef.current = setInterval(async () => {
      if (!mountedRef.current) return
      const result = await getOwnMatchmakingStatusAction(subjectId)
      if (!mountedRef.current || !result.ok) return

      if (result.data.status === "matched" && result.data.competitionId) {
        clearPoll()
        setState({
          phase: "matched",
          competitionId: result.data.competitionId,
          competitionCode: result.data.competitionCode ?? "",
        })
        return
      }

      if (result.data.status === "not_queued") {
        // Kuyruk suresi doldu veya kayit kapatildi -> zaman asimi.
        clearPoll()
        setState({ phase: "expired" })
      }
      // status === "waiting" -> beklemeye devam.
    }, POLL_INTERVAL_MS)
  }, [subjectId, clearPoll])

  // Sayfa yuklenirken mevcut kuyruk/yarisma durumunu geri yukle.
  useEffect(() => {
    let cancelled = false

    async function restore() {
      const result = await getOwnMatchmakingStatusAction(subjectId)
      if (cancelled || !mountedRef.current) return

      if (!result.ok) {
        setState({ phase: "error", message: result.message })
        return
      }

      if (
        result.data.status === "matched" &&
        result.data.competitionId
      ) {
        setState({
          phase: "matched",
          competitionId: result.data.competitionId,
          competitionCode: result.data.competitionCode ?? "",
        })
        return
      }

      if (result.data.status === "waiting") {
        setState({ phase: "queued" })
        startStatusPolling()
        return
      }

      setState({ phase: "idle" })
    }

    void restore()
    return () => {
      cancelled = true
      clearPoll()
    }
  }, [subjectId, startStatusPolling, clearPoll])

  const handleJoin = useCallback(async () => {
    if (state.phase === "joining" || state.phase === "queued") return
    if (blocked) return

    setState({ phase: "joining" })

    const result = await joinMatchmakingQueueAction(subjectId)

    if (!mountedRef.current) return

    if (!result.ok) {
      // Eszamanli tuketim veya kota dolu: sunucu KOTA_163/KOTA_165'i
      // errors.ts uzerinden tam urun mesajina cevirdi. Bilesen ici
      // kilitle ve tekrar-dene dongusu olusturma (sunucu haftayi kendisi
      // acacak).
      if (
        result.message === COMPETITION_ERROR_MESSAGES.weeklyQuota ||
        result.message === COMPETITION_ERROR_MESSAGES.weeklyQuotaSubject ||
        result.message === COMPETITION_ERROR_MESSAGES.weeklyQuestionQuotaSubject
      ) {
        setQuotaLock(true)
      }
      setState({ phase: "error", message: result.message })
      return
    }

    if (
      result.data.status === "matched" &&
      result.data.competitionId &&
      result.data.competitionCode
    ) {
      setState({
        phase: "matched",
        competitionId: result.data.competitionId,
        competitionCode: result.data.competitionCode,
      })
      return
    }

    if (result.data.status === "waiting") {
      setState({ phase: "queued" })
      startStatusPolling()
      return
    }

    setState({ phase: "idle" })
  }, [state.phase, subjectId, startStatusPolling, blocked])

  const handleLeave = useCallback(async () => {
    clearPoll()
    setState({ phase: "leaving" })

    const result = await leaveMatchmakingQueueAction()

    if (!mountedRef.current) return

    if (result.ok) {
      setState({ phase: "idle" })
    } else {
      setState({ phase: "error", message: result.message })
    }
  }, [clearPoll])

  const handleMatchedContinue = useCallback(() => {
    if (state.phase !== "matched") return
    router.push(`/competition/${state.competitionId}`)
  }, [state, router])

  const isPending =
    state.phase === "joining" ||
    state.phase === "queued" ||
    state.phase === "leaving"

  return (
    <div className="rounded-2xl border border-border bg-surface p-5 shadow-sm">
      <h3 className="font-semibold text-ink">{subjectName}</h3>

      {quota && (
        <p className="mt-2 text-sm text-ink-muted" aria-live="polite">
          Bu derste bu hafta: Yarışma {quota.competitionsUsed}/
          {quota.competitionsLimit} kullanılan —{" "}
          {subjectQuotaCompetitionsRemaining(quota)} yarışma hakkın kaldı.
          {" · "}
          Yeni soru: {quota.newQuestionsUsed}/{quota.newQuestionsLimit} kullanılan
          {" — "}
          {subjectQuotaNewQuestionsRemaining(quota)} yeni soru hakkın kaldı.
        </p>
      )}

      {state.phase === "restoring" && (
        <p className="mt-3 text-sm text-ink-muted" aria-live="polite">
          Durum kontrol ediliyor…
        </p>
      )}

      {(state.phase === "idle" || state.phase === "expired") && (
        <>
          {state.phase === "expired" && (
            <p
              className="mt-3 text-sm text-warning-900"
              role="status"
              aria-live="polite"
            >
              Eşleşme araman zaman aşımına uğradı. İstersen yeniden
              katılabilirsin.
            </p>
          )}
          <button
            type="button"
            onClick={() => void handleJoin()}
            disabled={isPending || blocked}
            aria-disabled={blocked || undefined}
            className="mt-3 inline-flex min-h-11 items-center justify-center rounded-xl bg-teal-700 px-4 py-2 text-sm font-medium text-accent-foreground transition hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Sıraya katıl
          </button>
          {blocked && (
            <p
              className="mt-2 text-sm font-medium text-warning-900"
              role="status"
              aria-live="polite"
            >
              {blockMessage}
            </p>
          )}
        </>
      )}

      {state.phase === "joining" && (
        <p className="mt-3 text-sm text-ink-muted" aria-live="polite">
          Sıraya ekleniyorsun…
        </p>
      )}

      {state.phase === "queued" && (
        <div className="mt-3">
          <p className="text-sm text-ink-muted" aria-live="polite">
            Eşleşme aranıyor. Aynı sınıf düzeyinden bir rakip beklüyor…
          </p>
          <button
            type="button"
            onClick={() => void handleLeave()}
            className="mt-2 inline-flex min-h-11 items-center justify-center rounded-xl border border-border-strong bg-surface px-4 py-2 text-sm font-medium text-ink transition hover:bg-surface-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
          >
            Kuyruktan çık
          </button>
        </div>
      )}

      {state.phase === "leaving" && (
        <p className="mt-3 text-sm text-ink-muted" aria-live="polite">
          Kuyruktan çıkılıyor…
        </p>
      )}

      {state.phase === "matched" && (
        <div className="mt-3">
          <p
            className="text-sm font-medium text-success-700"
            aria-live="polite"
          >
            Eşleşme bulundu! Yarışma kodu: {state.competitionCode}
          </p>
          <button
            type="button"
            onClick={handleMatchedContinue}
            className="mt-2 inline-flex min-h-11 items-center justify-center rounded-xl bg-success-700 px-4 py-2 text-sm font-medium text-accent-foreground transition hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-success-700"
          >
            Yarışmaya başla
          </button>
        </div>
      )}

      {state.phase === "error" && (
        <div className="mt-3">
          <p className="text-sm text-danger-700" role="alert">
            {state.message}
          </p>
          {blocked ? (
            // Kota tukendi: tekrar-dene dongusu anlamsiz; sunucu haftayi
            // kendisi acar. Buton pasif, mesaj kota mesajidir.
            <button
              type="button"
              disabled
              aria-disabled
              className="mt-2 inline-flex min-h-11 items-center justify-center rounded-xl border border-border-strong bg-surface px-4 py-2 text-sm font-medium text-ink opacity-50"
            >
              Sıraya katıl
            </button>
          ) : (
            <button
              type="button"
              onClick={() => void handleJoin()}
              className="mt-2 inline-flex min-h-11 items-center justify-center rounded-xl border border-border-strong bg-surface px-4 py-2 text-sm font-medium text-ink transition hover:bg-surface-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
            >
              Tekrar dene
            </button>
          )}
        </div>
      )}
    </div>
  )
}
