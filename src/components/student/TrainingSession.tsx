"use client"

/**
 * Antrenman oturumu bileşeni.
 *
 * - Yalnız güvenli DTO alanlarını render eder (gizli DB alanları bu
 *   bileşene hiç ulaşmaz; ayrıca render/log edilmemesi testle denetlenir).
 * - Her soru için bir kez üretilen client_key ile gönderim yapar;
 *   ağ hatasında AYNI key ile yeniden dener, duplicate:true cevabı
 *   başarı sayılır ve ikinci attempt oluşturmaz. ActionResponse
 *   sözleşmesi dışı throw'lar da güvenli Türkçe mesaja düşer.
 * - Erişilebilirlik: yerel radio-group semantiği, klavye ile seçim,
 *   görünür focus, ≥44px dokunma hedefleri, aria-live geri bildirim.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import Link from "next/link"

import {
  CHOICE_LETTERS,
  type AttemptAction,
  type ChoiceLetter,
  type SubmitResult,
  type TrainingQuestion,
} from "@/lib/training/types"

export type SubmitActionResponse =
  | { ok: true; data: SubmitResult }
  | { ok: false; message: string }

export type SubmitActionFn = (input: {
  questionId: string
  clientKey: string
  timeMs: number
  choice?: ChoiceLetter
  action?: AttemptAction
}) => Promise<SubmitActionResponse>

interface TrainingSessionProps {
  subjectName: string
  questions: TrainingQuestion[]
  submitAction: SubmitActionFn
  backHref?: string
}

const DEFAULT_TIME_SECONDS = 60
const MIN_TIME_SECONDS = 10
const MAX_TIME_SECONDS = 3600

const RESULT_LABELS: Record<string, string> = {
  correct: "Doğru",
  wrong: "Yanlış",
  pass: "Pas",
  blank: "Boş",
  timeout: "Süre doldu",
}

function formatSeconds(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60
  return `${minutes}:${String(seconds).padStart(2, "0")}`
}

/**
 * Soru başına ayrı mount edilen geri sayım göstergesi.
 * key={question.id} ile yeniden başlar; süre bitince onExpire tetiklenir.
 */
function SessionTimer({
  totalSeconds,
  onExpire,
}: {
  totalSeconds: number
  onExpire: () => void
}) {
  const [left, setLeft] = useState(totalSeconds)
  const expireRef = useRef(onExpire)

  useEffect(() => {
    expireRef.current = onExpire
  })

  useEffect(() => {
    const startedAt = Date.now()
    const interval = setInterval(() => {
      const nextLeft = Math.max(
        0,
        Math.ceil(totalSeconds - (Date.now() - startedAt) / 1000)
      )
      setLeft(nextLeft)
      if (nextLeft <= 0) {
        clearInterval(interval)
        expireRef.current()
      }
    }, 250)
    return () => clearInterval(interval)
  }, [totalSeconds])

  return (
    <p className="rounded-lg bg-gray-100 px-3 py-1 text-sm font-semibold tabular-nums text-gray-700">
      {/* Ekran okuyucular için güvenilir tam metin; görsel sayaç korunur. */}
      <span className="sr-only">Kalan süre {left} saniye</span>
      <span aria-hidden="true">⏱ {formatSeconds(left)}</span>
    </p>
  )
}

function createClientKey(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID()
  }
  // Nadir ortamlar için yedek v4 üretimi.
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(
    /[xy]/g,
    (char) => {
      const random = Math.floor(Math.random() * 16)
      const value = char === "x" ? random : (random & 0x3) | 0x8
      return value.toString(16)
    }
  )
}

function questionTimeSeconds(question: TrainingQuestion): number {
  const raw = question.estimatedSolveTimeSeconds ?? DEFAULT_TIME_SECONDS
  if (!Number.isFinite(raw)) return DEFAULT_TIME_SECONDS
  return Math.min(MAX_TIME_SECONDS, Math.max(MIN_TIME_SECONDS, Math.round(raw)))
}

interface RecordedOutcome {
  questionId: string
  result: SubmitResult["result"]
  duplicate: boolean
}

export default function TrainingSession({
  subjectName,
  questions,
  submitAction,
  backHref = "/training",
}: TrainingSessionProps) {
  const [index, setIndex] = useState(0)
  const [selected, setSelected] = useState<ChoiceLetter | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [feedback, setFeedback] = useState<string | null>(null)
  const [duplicateNotice, setDuplicateNotice] = useState<string | null>(null)
  const [outcomes, setOutcomes] = useState<RecordedOutcome[]>([])

  /** Soru başına bir kez üretilen idempotency anahtarları. */
  const clientKeysRef = useRef(new Map<string, string>())
  const startedAtRef = useRef(0)
  const submittingRef = useRef(false)

  const question = questions[index]
  const finished = !question

  const ensureClientKey = useCallback((questionId: string): string => {
    const existing = clientKeysRef.current.get(questionId)
    if (existing) return existing
    const key = createClientKey()
    clientKeysRef.current.set(questionId, key)
    return key
  }, [])

  const advance = useCallback(() => {
    setSelected(null)
    setError(null)
    setDuplicateNotice(null)
    setIndex((current) => current + 1)
  }, [])

  const sendAnswer = useCallback(
    async (payload: { choice?: ChoiceLetter; action?: AttemptAction }) => {
      if (!question || submittingRef.current) return
      submittingRef.current = true
      setSubmitting(true)
      setError(null)

      const timeMs = Math.max(0, Date.now() - startedAtRef.current)
      // Anahtar ilk gönderimde üretilir ve yeniden denemelerde korunur.
      const clientKey = ensureClientKey(question.id)

      try {
        const response = await submitAction({
          questionId: question.id,
          clientKey,
          timeMs,
          ...payload,
        })

        if (!response.ok) {
          setError(response.message)
          setFeedback(response.message)
          return
        }

        const outcome: RecordedOutcome = {
          questionId: question.id,
          result: response.data.result,
          duplicate: response.data.duplicate,
        }
        setOutcomes((current) => [...current, outcome])
        setDuplicateNotice(
          outcome.duplicate ? "Bu cevap daha önce kaydedilmişti." : null
        )
        setFeedback(
          `${RESULT_LABELS[outcome.result] ?? outcome.result}${
            outcome.duplicate ? " (kayıtlıydı)" : ""
          } — sonraki soruya geçiliyor.`
        )
        advance()
      } catch {
        // ActionResponse sözleşmesi dışı throw / transport hatası:
        // güvenli Türkçe mesaj; client_key haritada korunduğu için
        // tekrar gönderim idempotent retry olarak çalışır.
        const message = "Bağlantı hatası, tekrar deneyin."
        setError(message)
        setFeedback(message)
      } finally {
        submittingRef.current = false
        setSubmitting(false)
      }
    },
    [advance, ensureClientKey, question, submitAction]
  )

  const submitRef = useRef(sendAnswer)
  useEffect(() => {
    submitRef.current = sendAnswer
  })

  // Soru değişince süre ölçümünü sıfırla (yalnızca ref — render saf kalır).
  useEffect(() => {
    if (!question) return
    startedAtRef.current = Date.now()
  }, [question])

  const summary = useMemo(() => {
    const counts: Record<string, number> = {}
    for (const item of outcomes) {
      counts[item.result] = (counts[item.result] ?? 0) + 1
    }
    return counts
  }, [outcomes])

  if (questions.length === 0) {
    return (
      <main className="mx-auto w-full max-w-2xl flex-1 p-6">
        <div className="rounded-2xl border border-gray-200 bg-white p-6">
          <h1 className="text-xl font-semibold text-gray-900">{subjectName}</h1>
          <p className="mt-2 text-gray-600">
            Bu ders için şu anda çözülebilir soru bulunamadı.
          </p>
          <Link
            href={backHref}
            className="mt-4 inline-flex min-h-11 items-center font-medium text-gray-900 underline-offset-4 hover:underline"
          >
            Ders seçimine dön
          </Link>
        </div>
      </main>
    )
  }

  if (finished) {
    const total = outcomes.length
    return (
      <main className="mx-auto w-full max-w-2xl flex-1 p-6">
        <section
          aria-labelledby="summary-title"
          className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm"
        >
          <h1 id="summary-title" className="text-2xl font-bold text-gray-900">
            Oturum Özeti — {subjectName}
          </h1>
          <p className="mt-1 text-sm text-gray-600">
            {total} soru yanıtlandı.
          </p>

          <ul className="mt-4 grid gap-2 sm:grid-cols-2">
            {(["correct", "wrong", "pass", "blank", "timeout"] as const).map(
              (key) => (
                <li
                  key={key}
                  className="flex items-center justify-between rounded-xl border border-gray-200 px-4 py-2 text-sm"
                >
                  <span className="text-gray-700">{RESULT_LABELS[key]}</span>
                  <span className="font-semibold text-gray-900">
                    {summary[key] ?? 0}
                  </span>
                </li>
              )
            )}
          </ul>

          <p role="status" aria-live="polite" className="mt-4 text-sm text-gray-600">
            Oturum tamamlandı. Tüm cevapların sunucu tarafında değerlendirildi.
          </p>

          <Link
            href={backHref}
            className="mt-5 inline-flex min-h-11 items-center rounded-xl bg-gray-900 px-6 py-3 font-semibold text-white transition hover:bg-gray-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            Başka ders çalış
          </Link>
        </section>
      </main>
    )
  }

  const canAnswer = selected !== null && !submitting

  return (
    <main className="mx-auto w-full max-w-2xl flex-1 p-4 sm:p-6">
      {/* Sesli/bölgesel geri bildirim */}
      <p role="status" aria-live="polite" className="sr-only">
        {feedback ?? ""}
      </p>

      {error && (
        <p role="alert" className="mb-4 rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700">
          {error}
        </p>
      )}

      <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm sm:p-6">
        <header className="flex flex-wrap items-center justify-between gap-2">
          <p className="text-sm font-medium text-gray-500">
            {subjectName} · Soru {index + 1}/{questions.length}
          </p>
          <SessionTimer
            key={question.id}
            totalSeconds={questionTimeSeconds(question)}
            onExpire={() => void submitRef.current({ action: "timeout" })}
          />
        </header>

        <h1 className="mt-4 text-lg font-semibold leading-relaxed text-gray-900">
          {question?.questionText ?? "Soru metni bulunamadı."}
        </h1>

        <fieldset className="mt-5" disabled={submitting}>
          <legend className="sr-only">Cevap seçenekleri</legend>

          <div
            role="radiogroup"
            aria-label="Cevap seçenekleri"
            className="grid gap-2"
          >
            {CHOICE_LETTERS.map((letter) => {
              const optionText = question?.options[letter]
              if (!optionText) return null
              return (
                <label
                  key={letter}
                  htmlFor={`option-${letter}`}
                  className="flex min-h-11 cursor-pointer items-center gap-3 rounded-xl border border-gray-300 bg-white px-4 py-3 transition has-[:checked]:border-gray-900 has-[:checked]:bg-gray-50 hover:border-gray-500 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-gray-900"
                >
                  <input
                    id={`option-${letter}`}
                    type="radio"
                    name="training-choice"
                    value={letter}
                    checked={selected === letter}
                    onChange={() => setSelected(letter)}
                    disabled={submitting}
                    className="sr-only"
                  />
                  <span
                    aria-hidden="true"
                    className="flex size-7 shrink-0 items-center justify-center rounded-full border border-gray-400 text-xs font-bold text-gray-700"
                  >
                    {letter}
                  </span>
                  <span className="text-gray-900">{optionText}</span>
                </label>
              )
            })}
          </div>
        </fieldset>

        {duplicateNotice && (
          <p className="mt-3 rounded-xl bg-blue-50 px-4 py-2 text-sm text-blue-700">
            {duplicateNotice}
          </p>
        )}

        <div className="mt-6 grid gap-2 sm:grid-cols-3">
          <button
            type="button"
            onClick={() => {
              if (selected) void sendAnswer({ choice: selected })
            }}
            disabled={!canAnswer}
            className="min-h-11 rounded-xl bg-gray-900 px-6 py-3 font-semibold text-white transition hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            {submitting ? "Gönderiliyor..." : "Cevapla"}
          </button>
          <button
            type="button"
            onClick={() => void sendAnswer({ action: "blank" })}
            disabled={submitting}
            className="min-h-11 rounded-xl border border-gray-300 px-6 py-3 font-semibold text-gray-900 transition hover:border-gray-500 disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            Boş Bırak
          </button>
          <button
            type="button"
            onClick={() => void sendAnswer({ action: "pass" })}
            disabled={submitting}
            className="min-h-11 rounded-xl border border-gray-300 px-6 py-3 font-semibold text-gray-900 transition hover:border-gray-500 disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            Pas Geç
          </button>
        </div>
      </section>
    </main>
  )
}
