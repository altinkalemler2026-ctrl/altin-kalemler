"use client"

/**
 * Yarisma oturum bileşeni.
 *
 * Faz 5b: Aktif yarisma akisi.
 *
 * Fazlari: idle -> ready -> waiting -> question -> answered -> completed -> error
 *
 * GUVENLIK:
 *  - Rakip verisi DTO'da bulunmaz; gorunmez.
 *  - Cevap dogrulugu/puani aktif asamada gosterilmez.
 *  - setPlayerReady yalnizca bir kez, acik buton tiklamasiyla cagirilir.
 *  - Waiting asamasinda yalnizca syncCompetitionState poll edilir.
 *  - Timer deadlineAt uzerinden calisir.
 *  - Unmount temizligi tum ref/interval uzerinden yapilir.
 */

import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"

import type {
  ChoiceLetter,
  CompetitionQuestion,
  CompetitionSession as CompetitionSessionType,
} from "@/lib/competition/types"
import { CHOICE_LETTERS } from "@/lib/competition/types"

import {
  getCurrentQuestionAction,
  setPlayerReadyAction,
  submitAnswerAction,
  syncCompetitionStateAction,
} from "@/app/(student)/competition/actions"

import QuestionRenderer from "./QuestionRenderer"

const POLL_INTERVAL_MS = 3_000

interface CompetitionSessionProps {
  competitionId: string
}

type Phase =
  | { kind: "idle" }
  | { kind: "readying" }
  | { kind: "waiting" }
  | { kind: "question"; question: CompetitionQuestion; session: CompetitionSessionType }
  | { kind: "answered"; session: CompetitionSessionType }
  | { kind: "completed" }
  | { kind: "error"; message: string }
  | { kind: "no_competition" }

function formatSeconds(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60
  return `${minutes}:${String(seconds).padStart(2, "0")}`
}

export default function CompetitionSession({
  competitionId,
}: CompetitionSessionProps) {
  const router = useRouter()
  const [phase, setPhase] = useState<Phase>({ kind: "idle" })
  const [selectedAnswer, setSelectedAnswer] = useState<ChoiceLetter | null>(
    null
  )
  const [submitting, setSubmitting] = useState(false)

  const mountedRef = useRef(true)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const readyRef = useRef(false)
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const [timerLeft, setTimerLeft] = useState(0)

  const clearPoll = useCallback(() => {
    if (pollRef.current) {
      clearInterval(pollRef.current)
      pollRef.current = null
    }
  }, [])

  const clearTimer = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current)
      timerRef.current = null
    }
  }, [])

  useEffect(() => {
    return () => {
      mountedRef.current = false
      clearPoll()
      clearTimer()
    }
  }, [clearPoll, clearTimer])

  // Timer: deadlineAt uzerinden calisir
  useEffect(() => {
    clearTimer()
    if (phase.kind !== "question") {
      return
    }

    const deadline = new Date(phase.question.deadlineAt).getTime()
    if (!Number.isFinite(deadline)) return

    const tick = () => {
      const remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000))
      setTimerLeft(remaining)
      if (remaining <= 0) {
        clearTimer()
      }
    }

    tick()
    timerRef.current = setInterval(tick, 250)
    return () => clearTimer()
  }, [phase, clearTimer])

  // Idle asamasinda soruyu yukle
  useEffect(() => {
    if (phase.kind !== "idle") return
    if (!mountedRef.current) return

    let cancelled = false

    async function load() {
      const result = await getCurrentQuestionAction()
      if (cancelled || !mountedRef.current) return

      if (!result.ok) {
        setPhase({ kind: "error", message: result.message })
        return
      }

      const { status, questionAvailable, payload, competitionId: cid } = result.data

      if (status === "no_active_competition" || !cid) {
        setPhase({ kind: "no_competition" })
        return
      }

      if (status === "completed") {
        setPhase({ kind: "completed" })
        return
      }

      if (questionAvailable && payload) {
        // Sync state'i de al
        const syncResult = await syncCompetitionStateAction(cid)
        if (cancelled || !mountedRef.current) return

        const session =
          syncResult.ok ? syncResult.data : null
        if (!session) {
          setPhase({
            kind: "question",
            question: payload,
            session: {
              competitionId: cid,
              status,
              currentQuestionOrder: payload.questionOrder,
              totalQuestions: 0,
              sentAt: payload.sentAt,
              deadlineAt: payload.deadlineAt,
              timeLimitSeconds: null,
              hasAnsweredCurrentQuestion: false,
              myCurrentScore: 0,
              competitionCode: null,
              competitionType: null,
            },
          })
          return
        }

        if (session.hasAnsweredCurrentQuestion) {
          setPhase({ kind: "answered", session })
        } else {
          setPhase({ kind: "question", question: payload, session })
        }
        return
      }

      // Soru yoksa waiting
      setPhase({ kind: "waiting" })
    }

    void load()
    return () => {
      cancelled = true
    }
  }, [phase.kind])

  // Waiting asamasinda sync poll
  useEffect(() => {
    if (phase.kind !== "waiting") {
      clearPoll()
      return
    }

    let cancelled = false

    const poll = async () => {
      if (cancelled || !mountedRef.current) return
      const result = await syncCompetitionStateAction(competitionId)
      if (cancelled || !mountedRef.current) return
      if (!result.ok) return

      const { status, hasAnsweredCurrentQuestion } = result.data

      if (status === "completed") {
        clearPoll()
        setPhase({ kind: "completed" })
        return
      }

      if (status === "active") {
        clearPoll()
        // Soruyu yukle
        const qResult = await getCurrentQuestionAction()
        if (cancelled || !mountedRef.current) return
        if (qResult.ok && qResult.data.questionAvailable && qResult.data.payload) {
          if (hasAnsweredCurrentQuestion) {
            setPhase({ kind: "answered", session: result.data })
          } else {
            setPhase({
              kind: "question",
              question: qResult.data.payload,
              session: result.data,
            })
          }
        }
        return
      }
    }

    void poll()
    pollRef.current = setInterval(() => void poll(), POLL_INTERVAL_MS)
    return () => {
      cancelled = true
      clearPoll()
    }
  }, [phase.kind, competitionId, clearPoll])

  // Answered asamasinda sync poll
  useEffect(() => {
    if (phase.kind !== "answered") {
      if (phase.kind !== "waiting") clearPoll()
      return
    }

    let cancelled = false

    const poll = async () => {
      if (cancelled || !mountedRef.current) return
      const result = await syncCompetitionStateAction(competitionId)
      if (cancelled || !mountedRef.current) return
      if (!result.ok) return

      if (result.data.status === "completed") {
        clearPoll()
        setPhase({ kind: "completed" })
        return
      }

      if (!result.data.hasAnsweredCurrentQuestion) {
        clearPoll()
        // Yeni soru geldi
        const qResult = await getCurrentQuestionAction()
        if (cancelled || !mountedRef.current) return
        if (qResult.ok && qResult.data.questionAvailable && qResult.data.payload) {
          setPhase({
            kind: "question",
            question: qResult.data.payload,
            session: result.data,
          })
        }
      }
    }

    void poll()
    pollRef.current = setInterval(() => void poll(), POLL_INTERVAL_MS)
    return () => {
      cancelled = true
      clearPoll()
    }
  }, [phase.kind, competitionId, clearPoll])

  // Ready butonu tiklamasi
  const handleReady = useCallback(async () => {
    if (readyRef.current) return
    readyRef.current = true
    setPhase({ kind: "readying" })

    const result = await setPlayerReadyAction(competitionId)
    if (!mountedRef.current) return

    if (!result.ok) {
      setPhase({ kind: "error", message: result.message })
      return
    }

    if (result.data.status === "started") {
      // Basladi, soruyu yukle
      const qResult = await getCurrentQuestionAction()
      if (!mountedRef.current) return
      if (qResult.ok && qResult.data.questionAvailable && qResult.data.payload) {
        const syncResult = await syncCompetitionStateAction(competitionId)
        if (!mountedRef.current) return
        const session = syncResult.ok ? syncResult.data : null
        if (session) {
          setPhase({
            kind: "question",
            question: qResult.data.payload,
            session,
          })
        }
      } else {
        setPhase({ kind: "waiting" })
      }
    } else {
      setPhase({ kind: "waiting" })
    }
  }, [competitionId])

  // Cevap gonderme
  const handleSubmitAnswer = useCallback(
    async (answer?: ChoiceLetter) => {
      if (phase.kind !== "question" || submitting) return
      setSubmitting(true)

      try {
        const result = await submitAnswerAction(
          phase.question.id,
          answer
        )
        if (!mountedRef.current) return

        if (!result.ok) {
          setPhase({ kind: "error", message: result.message })
          return
        }

        setSelectedAnswer(null)
        setPhase({ kind: "answered", session: phase.session })
      } catch {
        if (!mountedRef.current) return
        setPhase({ kind: "error", message: "Baglanti hatasi, tekrar deneyin." })
      } finally {
        setSubmitting(false)
      }
    },
    [phase, submitting]
  )

  // Completed asamasinda sonuc sayfasina yonlendir
  useEffect(() => {
    if (phase.kind === "completed") {
      router.push(`/competition/${competitionId}/result`)
    }
  }, [phase.kind, competitionId, router])

  if (phase.kind === "no_competition") {
    return (
      <main className="mx-auto w-full max-w-2xl flex-1 p-6">
        <div className="rounded-2xl border border-gray-200 bg-white p-6">
          <h1 className="text-xl font-semibold text-gray-900">
            Aktif Yarisma Yok
          </h1>
          <p className="mt-2 text-gray-600">
            Su anda bir yarisma bulunmuyor. Yarismalar sayfasina donun.
          </p>
          <button
            type="button"
            onClick={() => router.push("/competition")}
            className="mt-4 inline-flex min-h-11 items-center rounded-xl bg-gray-900 px-6 py-3 font-semibold text-white transition hover:bg-gray-800"
          >
            Yarismalar
          </button>
        </div>
      </main>
    )
  }

  if (phase.kind === "error") {
    return (
      <main className="mx-auto w-full max-w-2xl flex-1 p-6">
        <div className="rounded-2xl border border-gray-200 bg-white p-6">
          <h1 className="text-xl font-semibold text-gray-900">Hata</h1>
          <p className="mt-2 text-sm text-red-600" role="alert">
            {phase.message}
          </p>
          <button
            type="button"
            onClick={() => {
              readyRef.current = false
              setPhase({ kind: "idle" })
            }}
            className="mt-4 inline-flex min-h-11 items-center rounded-xl border border-gray-300 bg-white px-6 py-3 font-semibold text-gray-700 transition hover:bg-gray-50"
          >
            Tekrar Dene
          </button>
        </div>
      </main>
    )
  }

  if (phase.kind === "completed") {
    return (
      <main className="mx-auto w-full max-w-2xl flex-1 p-6">
        <div className="rounded-2xl border border-gray-200 bg-white p-6">
          <p className="text-sm text-gray-600" aria-live="polite">
            Yarisma sona erdi. Skor tablosuna geciliyor...
          </p>
        </div>
      </main>
    )
  }

  return (
    <main className="mx-auto w-full max-w-2xl flex-1 p-4 sm:p-6">
      <p role="status" aria-live="polite" className="sr-only">
        {phase.kind === "readying" && "Hazir ol isaretleniyor..."}
        {phase.kind === "waiting" && "Rakibiniz bekleniyor..."}
        {phase.kind === "answered" && "Cevabiniz alindi. Sonraki soru bekleniyor..."}
      </p>

      {phase.kind === "idle" && (
        <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
          <h1 className="text-xl font-semibold text-gray-900">Yarisma</h1>
          <p className="mt-2 text-gray-600">
            Yarismaya katilmak icin hazir olun.
          </p>
          <button
            type="button"
            onClick={handleReady}
            className="mt-4 inline-flex min-h-11 items-center rounded-xl bg-gray-900 px-6 py-3 font-semibold text-white transition hover:bg-gray-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            Hazirim
          </button>
        </div>
      )}

      {phase.kind === "readying" && (
        <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm text-gray-600" aria-live="polite">
            Hazir ol isaretleniyor...
          </p>
        </div>
      )}

      {phase.kind === "waiting" && (
        <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm text-gray-600" aria-live="polite">
            Rakibiniz bekleniyor...
          </p>
        </div>
      )}

      {phase.kind === "question" && (
        <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm sm:p-6">
          <header className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-sm font-medium text-gray-500">
              Soru {phase.question.questionOrder}
            </p>
            <p
              className={`rounded-lg px-3 py-1 text-sm font-semibold tabular-nums ${
                timerLeft <= 10
                  ? "bg-red-100 text-red-700"
                  : "bg-gray-100 text-gray-700"
              }`}
            >
              <span className="sr-only">Kalan sure {timerLeft} saniye</span>
              <span aria-hidden="true">{formatSeconds(timerLeft)}</span>
            </p>
          </header>

          <div className="mt-4">
            <QuestionRenderer
              stemHtml={phase.question.stemHtml}
              options={phase.question.options}
            />
          </div>

          <fieldset className="mt-5" disabled={submitting}>
            <legend className="sr-only">Cevap secenekleri</legend>
            <div
              role="radiogroup"
              aria-label="Cevap secenekleri"
              className="grid gap-2"
            >
              {CHOICE_LETTERS.map((letter) => {
                if (!phase.question.options[letter]) return null
                return (
                  <label
                    key={letter}
                    htmlFor={`comp-option-${letter}`}
                    className="flex min-h-11 cursor-pointer items-center gap-3 rounded-xl border border-gray-300 bg-white px-4 py-3 transition has-[:checked]:border-gray-900 has-[:checked]:bg-gray-50 hover:border-gray-500"
                  >
                    <input
                      id={`comp-option-${letter}`}
                      type="radio"
                      name="competition-choice"
                      value={letter}
                      checked={selectedAnswer === letter}
                      onChange={() => setSelectedAnswer(letter)}
                      disabled={submitting}
                      className="sr-only"
                    />
                    <span
                      aria-hidden="true"
                      className="flex size-7 shrink-0 items-center justify-center rounded-full border border-gray-400 text-xs font-bold text-gray-700"
                    >
                      {letter}
                    </span>
                    <span className="text-gray-900">{letter}</span>
                  </label>
                )
              })}
            </div>
          </fieldset>

          <div className="mt-6 grid gap-2 sm:grid-cols-2">
            <button
              type="button"
              onClick={() => {
                if (selectedAnswer) void handleSubmitAnswer(selectedAnswer)
              }}
              disabled={!selectedAnswer || submitting}
              className="min-h-11 rounded-xl bg-gray-900 px-6 py-3 font-semibold text-white transition hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
            >
              {submitting ? "Gonderiliyor..." : "Cevapla"}
            </button>
            <button
              type="button"
              onClick={() => void handleSubmitAnswer()}
              disabled={submitting}
              className="min-h-11 rounded-xl border border-gray-300 px-6 py-3 font-semibold text-gray-900 transition hover:border-gray-500 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Pas Gec
            </button>
          </div>
        </section>
      )}

      {phase.kind === "answered" && (
        <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm text-gray-600" aria-live="polite">
            Cevabiniz alindi. Rakibin beklenmesi...
          </p>
        </div>
      )}
    </main>
  )
}
