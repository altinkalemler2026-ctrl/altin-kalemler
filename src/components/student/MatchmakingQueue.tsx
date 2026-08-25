"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"

import type { QueueJoinResult } from "@/lib/competition/types"

import {
  joinMatchmakingQueueAction,
  leaveMatchmakingQueueAction,
} from "@/app/(student)/competition/actions"

const POLL_INTERVAL_MS = 3_000

interface MatchmakingQueueProps {
  subjectId: string
  subjectName: string
}

type ComponentState =
  | { phase: "idle" }
  | { phase: "joining" }
  | { phase: "queued"; queueId: string; gradeLevel: number }
  | { phase: "leaving" }
  | { phase: "matched"; competitionId: string; competitionCode: string }
  | { phase: "error"; message: string }

export default function MatchmakingQueue({
  subjectId,
  subjectName,
}: MatchmakingQueueProps) {
  const router = useRouter()
  const [state, setState] = useState<ComponentState>({ phase: "idle" })
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const mountedRef = useRef(true)

  const handleQueueResultRef = useRef<(data: QueueJoinResult) => void>(
    () => undefined
  )

  const clearPoll = useCallback(() => {
    if (pollRef.current) {
      clearInterval(pollRef.current)
      pollRef.current = null
    }
  }, [])

  const handleQueueResult = useCallback(
    (data: QueueJoinResult) => {
      if (!mountedRef.current) return

      if (data.status === "matched") {
        clearPoll()
        if (!data.competitionId || !data.competitionCode) {
          setState({
            phase: "error",
            message: "Eslesme bulundu ancak yarisma bilgileri eksik.",
          })
          return
        }
        setState({
          phase: "matched",
          competitionId: data.competitionId,
          competitionCode: data.competitionCode,
        })
        return
      }

      if (data.status === "waiting") {
        setState({
          phase: "queued",
          queueId: data.queueId,
          gradeLevel: data.gradeLevel,
        })

        if (!pollRef.current) {
          pollRef.current = setInterval(async () => {
            if (!mountedRef.current) return
            const pollResult = await joinMatchmakingQueueAction(subjectId)
            if (!mountedRef.current) return
            if (pollResult.ok) {
              handleQueueResultRef.current(pollResult.data)
            }
          }, POLL_INTERVAL_MS)
        }
        return
      }

      clearPoll()
      setState({ phase: "idle" })
    },
    [subjectId, clearPoll]
  )

  useEffect(() => {
    handleQueueResultRef.current = handleQueueResult
  })

  useEffect(() => {
    return () => {
      mountedRef.current = false
      if (pollRef.current) clearInterval(pollRef.current)
    }
  }, [])

  const handleJoin = useCallback(async () => {
    if (state.phase === "joining" || state.phase === "queued") return

    setState({ phase: "joining" })

    const result = await joinMatchmakingQueueAction(subjectId)

    if (!mountedRef.current) return

    if (!result.ok) {
      setState({ phase: "error", message: result.message })
      return
    }

    handleQueueResultRef.current(result.data)
  }, [state.phase, subjectId])

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

      {state.phase === "idle" && (
        <button
          type="button"
          onClick={handleJoin}
          disabled={isPending}
          className="mt-3 inline-flex min-h-11 items-center justify-center rounded-xl bg-gray-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-gray-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900 disabled:cursor-not-allowed disabled:opacity-50"
        >
          Siraya Katil
        </button>
      )}

      {state.phase === "joining" && (
        <p className="mt-3 text-sm text-gray-600" aria-live="polite">
          Siraya aliniyor...
        </p>
      )}

      {state.phase === "queued" && (
        <div className="mt-3">
          <p className="text-sm text-gray-600" aria-live="polite">
            Eslesme araniyor... Rakibiniz bekleniyor.
          </p>
          <button
            type="button"
            onClick={handleLeave}
            disabled={isPending}
            className="mt-2 inline-flex min-h-11 items-center justify-center rounded-xl border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Kuyruktan Cik
          </button>
        </div>
      )}

      {state.phase === "leaving" && (
        <p className="mt-3 text-sm text-gray-600" aria-live="polite">
          Kuyruktan cikiliyor...
        </p>
      )}

      {state.phase === "matched" && (
        <div className="mt-3">
          <p
            className="text-sm font-medium text-green-700"
            aria-live="polite"
          >
            Eslesme bulundu! Yarisma kodu: {state.competitionCode}
          </p>
          <button
            type="button"
            onClick={handleMatchedContinue}
            className="mt-2 inline-flex min-h-11 items-center justify-center rounded-xl bg-green-700 px-4 py-2 text-sm font-medium text-white transition hover:bg-green-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-green-700"
          >
            Yarismaya Basla
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
            onClick={() => setState({ phase: "idle" })}
            className="mt-2 inline-flex min-h-11 items-center justify-center rounded-xl border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            Tekrar Dene
          </button>
        </div>
      )}
    </div>
  )
}
