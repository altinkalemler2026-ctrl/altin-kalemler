"use client"

/**
 * Yarisma oturum bileseni.
 *
 * Faz 7: Aktif yarisma akisi.
 *
 * Asamalar: idle -> readying -> waiting -> question -> answered -> completed
 * Ek durumlar: no_competition, cancelled (rakip ayrildi / iptal), error
 *
 * GUVENLIK:
 *  - Rakip verisi DTO'da bulunmaz; gorunmez. Rakibin gizli cevabi
 *    hicbir asamada istemciye gecmez.
 *  - Cevap dogrulugu aktif asamada gosterilmez; gosterilen puan
 *    sunucunun hesapladigi my_current_score degeridir (V1 sunucu
 *    sonucu), istemciden alinmaz.
 *  - setPlayerReady yalnizca bir kez, acik buton tiklamasiyla cagirilir.
 *  - Cevap gonderimi ref-korumalidir; cift tiklama ikinci istegi
 *    gondermez. Sunucu tarafinda da ayni soruya ikinci cevap
 *    reddedilir (idempotent guvence).
 *  - Timer deadlineAt uzerinden calisir; sure bittiginde sunucu
 *    durumu sync ile ilerletilir (eksik cevaplar timeout olur).
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
import { COMPETITION_ERROR_MESSAGES } from "@/lib/competition/errors"

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
  | { kind: "cancelled" }
  | { kind: "error"; message: string }
  | { kind: "no_competition" }

function formatSeconds(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60
  return `${minutes}:${String(seconds).padStart(2, "0")}`
}

/** Yarisma durumu iptal/terk anlamina mi geliyor? */
function isAbandonedStatus(status: string): boolean {
  return status === "cancelled" || status === "abandoned"
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
  const submitInFlightRef = useRef(false)
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
    mountedRef.current = true
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

      // get_current_competition_question yalnizca ready/active
      // yarismalari dondurur; henüz kimse hazir degilse bu RPC
      // no_active_competition döner. URL'deki yarismayi dogrudan
      // senkronize ederek pre-start akisini kurtariyoruz.
      if (status === "no_active_competition" || !cid) {
        const syncResult = await syncCompetitionStateAction(competitionId)
        if (cancelled || !mountedRef.current) return

        if (!syncResult.ok) {
          setPhase({ kind: "no_competition" })
          return
        }

        const s = syncResult.data.status
        if (s === "completed") {
          setPhase({ kind: "completed" })
          return
        }
        if (isAbandonedStatus(s)) {
          setPhase({ kind: "cancelled" })
          return
        }
        if (s === "active") {
          const qRetry = await getCurrentQuestionAction()
          if (cancelled || !mountedRef.current) return
          if (
            qRetry.ok &&
            qRetry.data.questionAvailable &&
            qRetry.data.payload
          ) {
            setPhase({
              kind: "question",
              question: qRetry.data.payload,
              session: syncResult.data,
            })
            return
          }
          setPhase({ kind: "waiting" })
          return
        }
        // waiting / ready -> hazir ekranı (setPlayerReady idempotent).
        setPhase({ kind: "idle" })
        return
      }

      if (isAbandonedStatus(status)) {
        setPhase({ kind: "cancelled" })
        return
      }

      if (status === "completed") {
        setPhase({ kind: "completed" })
        return
      }

      // Yarisma daha baslamadi (oluşturuldu / rakip hazir): hazir ekranı.
      // setPlayerReady idempotenttir; kullanici zaten hazirsa tekrar
      // tiklama zararsizdir ve beklemeye döner.
      if (status === "waiting" || status === "ready") {
        setPhase({ kind: "idle" })
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
  }, [phase.kind, competitionId])

  // Waiting asamasinda sync poll
  useEffect(() => {
    if (phase.kind !== "waiting") {
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

      if (isAbandonedStatus(status)) {
        clearPoll()
        setPhase({ kind: "cancelled" })
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

      if (isAbandonedStatus(result.data.status)) {
        clearPoll()
        setPhase({ kind: "cancelled" })
        return
      }

      // Sunucu puanini guncel tut (my_current_score).
      setPhase((current) =>
        current.kind === "answered"
          ? { kind: "answered", session: result.data }
          : current
      )

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

  // Sure bitti: sunucu eksik cevaplari timeout olarak isaretler ve
  // akisi ilerletir. Bu poll yalnizca sure dolduktan sonra calisir.
  const deadlinePassed = phase.kind === "question" && timerLeft <= 0

  useEffect(() => {
    if (!deadlinePassed || phase.kind !== "question") {
      return
    }

    let cancelled = false

    const poll = async () => {
      if (cancelled || !mountedRef.current) return
      // Cevap istegi yoldaysa bu turu atla (cift istek engellenir).
      if (submitInFlightRef.current) return

      const result = await syncCompetitionStateAction(competitionId)
      if (cancelled || !mountedRef.current) return
      if (!result.ok) return

      if (result.data.status === "completed") {
        clearPoll()
        setPhase({ kind: "completed" })
        return
      }

      if (isAbandonedStatus(result.data.status)) {
        clearPoll()
        setPhase({ kind: "cancelled" })
        return
      }

      if (result.data.hasAnsweredCurrentQuestion) {
        clearPoll()
        setPhase({ kind: "answered", session: result.data })
        return
      }

      // Soru ilerlediyse yeni soruyu yukle.
      const qResult = await getCurrentQuestionAction()
      if (cancelled || !mountedRef.current) return
      if (
        qResult.ok &&
        qResult.data.questionAvailable &&
        qResult.data.payload &&
        qResult.data.payload.questionOrder !== phase.question.questionOrder
      ) {
        clearPoll()
        setPhase({
          kind: "question",
          question: qResult.data.payload,
          session: result.data,
        })
      }
      // Ayni soru ve henuz cevap yoksa beklemeye devam.
    }

    void poll()
    pollRef.current = setInterval(() => void poll(), POLL_INTERVAL_MS)
    return () => {
      cancelled = true
      clearPoll()
    }
  }, [deadlinePassed, phase, competitionId, clearPoll])

  // Ready butonu tiklamasi
  const handleReady = useCallback(async () => {
    if (readyRef.current) return
    readyRef.current = true
    setPhase({ kind: "readying" })

    const result = await setPlayerReadyAction(competitionId)
    if (!mountedRef.current) return

    if (!result.ok) {
      readyRef.current = false
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
          return
        }
      }
      setPhase({ kind: "waiting" })
    } else {
      setPhase({ kind: "waiting" })
    }
  }, [competitionId])

  // Cevap gonderme
  const handleSubmitAnswer = useCallback(
    async (answer?: ChoiceLetter) => {
      if (phase.kind !== "question") return
      if (submitInFlightRef.current) return
      submitInFlightRef.current = true
      setSubmitting(true)

      try {
        const result = await submitAnswerAction(
          phase.question.id,
          answer
        )
        if (!mountedRef.current) return

        if (!result.ok) {
          // Sunucu ayni soruya ikinci cevabi zaten reddetti; bu
          // durumda cevap kaydi mevcuttur -> answered asamasina gec.
          if (result.message === COMPETITION_ERROR_MESSAGES.answerAlreadySubmitted) {
            setPhase({ kind: "answered", session: phase.session })
            return
          }
          setPhase({ kind: "error", message: result.message })
          return
        }

        setSelectedAnswer(null)
        setPhase({ kind: "answered", session: phase.session })
      } catch {
        if (!mountedRef.current) return
        setPhase({ kind: "error", message: "Bağlantı hatası, tekrar deneyin." })
      } finally {
        submitInFlightRef.current = false
        setSubmitting(false)
      }
    },
    [phase]
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
            Şu anda aktif bir yarışma yok
          </h1>
          <p className="mt-2 text-gray-600">
            Şu anda sürmekte olan bir yarışma bulunmuyor. Yarışmalar
            sayfasından yeni bir eşleşme arayabilirsin.
          </p>
          <button
            type="button"
            onClick={() => router.push("/competition")}
            className="mt-4 inline-flex min-h-11 items-center rounded-xl bg-gray-900 px-6 py-3 font-semibold text-white transition hover:bg-gray-800"
          >
            Yarışmalara dön
          </button>
        </div>
      </main>
    )
  }

  if (phase.kind === "cancelled") {
    return (
      <main className="mx-auto w-full max-w-2xl flex-1 p-6">
        <div className="rounded-2xl border border-gray-200 bg-white p-6">
          <h1 className="text-xl font-semibold text-gray-900">
            Yarışma iptal edildi
          </h1>
          <p className="mt-2 text-gray-600" role="alert">
            Rakibin yarışmadan ayrılması nedeniyle yarışma sona erdi.
            Puanında bir değişiklik yapılmadı. İstersen yeni bir eşleşme
            arayabilirsin.
          </p>
          <button
            type="button"
            onClick={() => router.push("/competition")}
            className="mt-4 inline-flex min-h-11 items-center rounded-xl bg-gray-900 px-6 py-3 font-semibold text-white transition hover:bg-gray-800"
          >
            Yarışmalara dön
          </button>
        </div>
      </main>
    )
  }

  if (phase.kind === "error") {
    return (
      <main className="mx-auto w-full max-w-2xl flex-1 p-6">
        <div className="rounded-2xl border border-gray-200 bg-white p-6">
          <h1 className="text-xl font-semibold text-gray-900">Bir sorun oluştu</h1>
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
            Tekrar dene
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
            Yarışma sona erdi. Sonuç ekranına geçiliyor…
          </p>
        </div>
      </main>
    )
  }

  return (
    <main className="mx-auto w-full max-w-2xl flex-1 p-4 sm:p-6">
      <p role="status" aria-live="polite" className="sr-only">
        {phase.kind === "readying" && "Hazır olduğun işaretleniyor…"}
        {phase.kind === "waiting" && "Rakibin bekleniyor…"}
        {phase.kind === "answered" && "Cevabın alındı. Sonraki soru bekleniyor…"}
      </p>

      {phase.kind === "idle" && (
        <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
          <h1 className="text-xl font-semibold text-gray-900">Yarışma</h1>
          <p className="mt-2 text-gray-600">
            Beş soruluk yarışma, rakibin de hazır olmasıyla başlar.
            Başlamak için hazır olduğunda işaretle.
          </p>
          <button
            type="button"
            onClick={handleReady}
            className="mt-4 inline-flex min-h-11 items-center rounded-xl bg-gray-900 px-6 py-3 font-semibold text-white transition hover:bg-gray-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            Hazırım
          </button>
        </div>
      )}

      {phase.kind === "readying" && (
        <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm text-gray-600" aria-live="polite">
            Hazır olduğun işaretleniyor…
          </p>
        </div>
      )}

      {phase.kind === "waiting" && (
        <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm text-gray-600" aria-live="polite">
            Rakibin hazırlanıyor. Yarışma başlamak üzere…
          </p>
        </div>
      )}

      {phase.kind === "question" && (
        <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm sm:p-6">
          <header className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-sm font-medium text-gray-500">
              {phase.session.totalQuestions > 0
                ? `Soru ${phase.question.questionOrder} / ${phase.session.totalQuestions}`
                : `Soru ${phase.question.questionOrder}`}
            </p>
            <p
              className={`rounded-lg px-3 py-1 text-sm font-semibold tabular-nums ${
                timerLeft <= 10
                  ? "bg-red-100 text-red-700"
                  : "bg-gray-100 text-gray-700"
              }`}
            >
              <span className="sr-only">Kalan süre {timerLeft} saniye</span>
              <span aria-hidden="true">{formatSeconds(timerLeft)}</span>
            </p>
          </header>

          <p className="mt-2 text-sm font-medium text-gray-700">
            Puanın: {phase.session.myCurrentScore}
            <span className="sr-only">
              {" "}
              (sunucunun hesapladığı güncel puan)
            </span>
          </p>

          <div className="mt-4">
            <QuestionRenderer
              stemHtml={phase.question.stemHtml}
              options={phase.question.options}
            />
          </div>

          <fieldset className="mt-5" disabled={submitting}>
            <legend className="sr-only">Cevap seçenekleri</legend>
            <div
              role="radiogroup"
              aria-label="Cevap seçenekleri"
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
                    <span className="sr-only">Seçenek {letter}</span>
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
              {submitting ? "Gönderiliyor…" : "Cevapla"}
            </button>
            <button
              type="button"
              onClick={() => void handleSubmitAnswer()}
              disabled={submitting}
              className="min-h-11 rounded-xl border border-gray-300 px-6 py-3 font-semibold text-gray-900 transition hover:border-gray-500 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Pas geç
            </button>
          </div>
        </section>
      )}

      {phase.kind === "answered" && (
        <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
          <p className="text-sm text-gray-600" aria-live="polite">
            Cevabın alındı. Şu anki puanın: {phase.session.myCurrentScore}.
            Sonraki soru için rakip bekleniyor…
          </p>
        </div>
      )}
    </main>
  )
}
