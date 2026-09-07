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

const POLL_INTERVAL_MS = 3_000

interface MatchmakingQueueProps {
  subjectId: string
  subjectName: string
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
}: MatchmakingQueueProps) {
  const router = useRouter()
  const [state, setState] = useState<ComponentState>({ phase: "restoring" })
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const mountedRef = useRef(true)

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

    setState({ phase: "joining" })

    const result = await joinMatchmakingQueueAction(subjectId)

    if (!mountedRef.current) return

    if (!result.ok) {
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
  }, [state.phase, subjectId, startStatusPolling])

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
    <div className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
      <h3 className="font-semibold text-gray-900">{subjectName}</h3>

      {state.phase === "restoring" && (
        <p className="mt-3 text-sm text-gray-600" aria-live="polite">
          Durum kontrol ediliyor…
        </p>
      )}

      {(state.phase === "idle" || state.phase === "expired") && (
        <>
          {state.phase === "expired" && (
            <p
              className="mt-3 text-sm text-orange-700"
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
            disabled={isPending}
            className="mt-3 inline-flex min-h-11 items-center justify-center rounded-xl bg-gray-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-gray-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Sıraya katıl
          </button>
        </>
      )}

      {state.phase === "joining" && (
        <p className="mt-3 text-sm text-gray-600" aria-live="polite">
          Sıraya ekleniyorsun…
        </p>
      )}

      {state.phase === "queued" && (
        <div className="mt-3">
          <p className="text-sm text-gray-600" aria-live="polite">
            Eşleşme aranıyor. Aynı sınıf düzeyinden bir rakip beklüyor…
          </p>
          <button
            type="button"
            onClick={() => void handleLeave()}
            className="mt-2 inline-flex min-h-11 items-center justify-center rounded-xl border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            Kuyruktan çık
          </button>
        </div>
      )}

      {state.phase === "leaving" && (
        <p className="mt-3 text-sm text-gray-600" aria-live="polite">
          Kuyruktan çıkılıyor…
        </p>
      )}

      {state.phase === "matched" && (
        <div className="mt-3">
          <p
            className="text-sm font-medium text-green-700"
            aria-live="polite"
          >
            Eşleşme bulundu! Yarışma kodu: {state.competitionCode}
          </p>
          <button
            type="button"
            onClick={handleMatchedContinue}
            className="mt-2 inline-flex min-h-11 items-center justify-center rounded-xl bg-green-700 px-4 py-2 text-sm font-medium text-white transition hover:bg-green-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-green-700"
          >
            Yarışmaya başla
          </button>
        </div>
      )}

      {state.phase === "error" && (
        <div className="mt-3">
          <p className="text-sm text-red-600" role="alert">
            {state.message}
          </p>
          <button
            type="button"
            onClick={() => void handleJoin()}
            className="mt-2 inline-flex min-h-11 items-center justify-center rounded-xl border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            Tekrar dene
          </button>
        </div>
      )}
    </div>
  )
}
