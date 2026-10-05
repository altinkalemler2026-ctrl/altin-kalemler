"use client"

/**
 * Faz 35 / UI-P2A — Aday soru insan kararı paneli.
 *
 * İki adımlı yazma modeli (BU FAZIN ANA GÜVENLİK ÖZELLİĞİ):
 *   1. "Kararı Seç ve Onaya Git" — YAZMAZ. Yalnızca yerel istemci durumunu
 *      değiştirip onay adımını açar. Bu düğme `type="button"`dır ve hiçbir
 *      `<form action=...>` içinde değildir; basıldığında sunucuda hiçbir
 *      aksiyon çalışmaz.
 *   2. "Kararı Onayla" — TEK yazma noktası (`submitCandidateDecisionAction`
 *      sunucu aksiyonu). Adım 1'de karar seçilmeden bu form hiç render
 *      edilmez.
 *
 * Dolayısıyla karar kaydı, açık bir admin tıklaması + ikinci bir onay
 * tıklaması olmadan MÜMKÜN DEĞİLDİR.
 *
 * Erişilebilirlik:
 * - Durum duyuruları `role="status"`, uyarılar `role="alert"` ile verilir.
 * - Devre dışı düğmelerin nedeni yalnızca `disabled` ile gizlenmez; metin
 *   olarak da görünür (renk tek başına bilgi taşımaz).
 * - Etkileşimli hedefler en az 44px yüksekliğindedir (`min-h-11`).
 * - Adım değişiminde odak onay adımı başlığına taşınır; klavye kullanıcısı
 *   adım değişimini kaçırmaz.
 */

import { useEffect, useRef, useState } from "react"
import { ADMIN_CANDIDATE_BATCH_DETAIL_MESSAGES as M } from "@/lib/admin/admin-panel-messages"
import {
  CANDIDATE_DECISIONS,
  RATIONALE_MAX_LENGTH,
  deriveCandidateDecisionAvailability,
  isRationaleRequired,
  readFinalReviewHistory,
  readReadinessSummary,
  summarizeCandidateDecision,
  type CandidateDecision,
} from "@/lib/admin/candidate-decisions"
import {
  CANDIDATE_DECISION_DESCRIPTIONS,
  CANDIDATE_DECISION_LABELS,
  CANDIDATE_DECISION_PUBLICATION_NOTICE,
  blockedReasonMessage,
} from "@/lib/admin/candidate-decisions-errors"
import { submitCandidateDecisionAction } from "./actions"
import type { CandidateRecord } from "@/lib/admin/candidate-batches"

const inputClassName =
  "w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"

function formatScore(score: number | null): string {
  return score === null ? "-" : score.toFixed(4)
}

/** Hazırlık özeti: durum, puan, engeller, ticari kullanım izni. */
function ReadinessSummary({ candidate }: { candidate: CandidateRecord }) {
  const summary = readReadinessSummary(candidate)

  return (
    <section aria-labelledby="decision-readiness-heading" className="mt-6">
      <h3 id="decision-readiness-heading" className="text-sm font-semibold text-gray-800">
        {M.decisionReadinessHeading}
      </h3>
      {summary.readinessStatus === null && summary.readinessScore === null ? (
        <p className="mt-2 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
          {M.decisionReadinessNone}
        </p>
      ) : (
        <dl className="mt-2 grid gap-3 sm:grid-cols-2">
          <div className="rounded-xl bg-gray-50 px-4 py-3">
            <dt className="text-xs text-gray-500">{M.decisionReadinessStatusLabel}</dt>
            <dd className="mt-1 break-words text-sm font-medium text-gray-900">
              {summary.readinessStatus ?? "-"}
            </dd>
          </div>
          <div className="rounded-xl bg-gray-50 px-4 py-3">
            <dt className="text-xs text-gray-500">{M.decisionReadinessScoreLabel}</dt>
            <dd className="mt-1 text-sm font-medium text-gray-900">
              {formatScore(summary.readinessScore)}
            </dd>
          </div>
          <div className="rounded-xl bg-gray-50 px-4 py-3">
            <dt className="text-xs text-gray-500">{M.decisionReadinessClearanceLabel}</dt>
            <dd className="mt-1 break-words text-sm font-medium text-gray-900">
              {summary.commercialClearanceStatus ?? "-"}
            </dd>
          </div>
          <div className="rounded-xl bg-gray-50 px-4 py-3">
            <dt className="text-xs text-gray-500">{M.decisionReadinessBlockersLabel}</dt>
            <dd className="mt-1 text-sm font-medium text-gray-900">
              {summary.blockingReasons.length === 0 ? (
                <span className="text-gray-500">{M.decisionReadinessNoBlockers}</span>
              ) : (
                <ul className="list-inside list-disc space-y-1">
                  {summary.blockingReasons.map((reason) => (
                    <li key={reason} className="break-words">
                      {reason}
                    </li>
                  ))}
                </ul>
              )}
            </dd>
          </div>
        </dl>
      )}
    </section>
  )
}

/** Son karar kaydı — yalnız mevcut allowlist'li okuma yolundan gelir. */
function DecisionHistory({ candidate }: { candidate: CandidateRecord }) {
  const history = readFinalReviewHistory(candidate)

  if (!history.decision) {
    return (
      <section aria-labelledby="decision-history-heading" className="mt-6">
        <h3 id="decision-history-heading" className="text-sm font-semibold text-gray-800">
          {M.decisionHistoryHeading}
        </h3>
        <p className="mt-2 rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-600">
          {M.decisionHistoryNone}
        </p>
      </section>
    )
  }

  const rows: Array<{ label: string; value: string }> = [
    { label: M.decisionHistoryDecisionLabel, value: history.decision },
    { label: M.decisionHistoryNotesLabel, value: history.reviewNotes ?? "-" },
    { label: M.decisionHistoryReviewerLabel, value: history.reviewedBy ?? "-" },
    { label: M.decisionHistoryAtLabel, value: history.reviewedAt ?? "-" },
  ]

  return (
    <section aria-labelledby="decision-history-heading" className="mt-6">
      <h3 id="decision-history-heading" className="text-sm font-semibold text-gray-800">
        {M.decisionHistoryHeading}
      </h3>
      <dl className="mt-2 grid gap-3 sm:grid-cols-2">
        {rows.map((row) => (
          <div key={row.label} className="rounded-xl bg-gray-50 px-4 py-3">
            <dt className="text-xs text-gray-500">{row.label}</dt>
            <dd className="mt-1 break-words text-sm font-medium text-gray-900">{row.value}</dd>
          </div>
        ))}
      </dl>
    </section>
  )
}

/** Onay adımı: seçilen kararı salt okunur gösterir, tek yazma düğmesini sunar. */
function ConfirmStep({
  candidate,
  batchId,
  candidatePosition,
  decision,
  rationale,
  onCancel,
}: {
  candidate: CandidateRecord
  batchId: string
  candidatePosition: number
  decision: CandidateDecision
  rationale: string
  onCancel: () => void
}) {
  const headingRef = useRef<HTMLHeadingElement>(null)
  const missingRationale = isRationaleRequired(decision) && rationale.trim().length === 0

  useEffect(() => {
    headingRef.current?.focus()
  }, [])

  return (
    <section aria-labelledby="decision-confirm-heading" className="mt-6">
      <h3
        id="decision-confirm-heading"
        ref={headingRef}
        tabIndex={-1}
        className="text-sm font-semibold text-gray-800 outline-none"
      >
        {M.decisionConfirmStepHeading}
      </h3>
      <p className="mt-1 text-sm text-gray-600">{M.decisionConfirmStepHint}</p>

      <dl className="mt-3 grid gap-3 sm:grid-cols-2">
        <div className="rounded-xl bg-gray-50 px-4 py-3">
          <dt className="text-xs text-gray-500">{M.decisionConfirmSummaryLabel}</dt>
          <dd className="mt-1 text-sm font-semibold text-gray-900">
            {CANDIDATE_DECISION_LABELS[decision]}
          </dd>
        </div>
        <div className="rounded-xl bg-gray-50 px-4 py-3">
          <dt className="text-xs text-gray-500">{M.decisionRationaleLabel}</dt>
          <dd className="mt-1 whitespace-pre-wrap break-words text-sm font-medium text-gray-900">
            {rationale.trim() || "-"}
          </dd>
        </div>
      </dl>

      <p className="mt-3 rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-700">
        {CANDIDATE_DECISION_DESCRIPTIONS[decision]}
      </p>

      {missingRationale && (
        <p
          role="alert"
          className="mt-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-medium text-amber-900"
        >
          {M.decisionRationaleHintRequired}
        </p>
      )}

      {/* TEK YAZMA NOKTASI. Yayin / activate fonksiyonu YOK. */}
      <form action={submitCandidateDecisionAction} className="mt-4 grid gap-3">
        <input type="hidden" name="batchId" value={batchId} />
        <input type="hidden" name="stagingQuestionId" value={candidate.stagingQuestionId ?? ""} />
        <input type="hidden" name="candidatePosition" value={String(candidatePosition)} />
        <input type="hidden" name="decision" value={decision} />
        <input type="hidden" name="rationale" value={rationale} />

        <div className="flex flex-wrap gap-3">
          <button
            type="submit"
            disabled={missingRationale}
            className={`min-h-11 rounded-xl px-5 py-2.5 font-semibold ${
              missingRationale
                ? "cursor-not-allowed bg-gray-100 text-gray-400"
                : "bg-emerald-700 text-white hover:bg-emerald-800"
            }`}
          >
            {M.decisionProceedLabel}
          </button>
          <button
            type="button"
            onClick={onCancel}
            className="inline-flex min-h-11 items-center rounded-xl border border-gray-300 bg-white px-5 py-2.5 font-semibold text-gray-700 hover:bg-gray-100"
          >
            {M.decisionCancelLabel}
          </button>
        </div>
      </form>
    </section>
  )
}

export interface CandidateDecisionPanelProps {
  batchId: string
  candidate: CandidateRecord
  /** 1 tabanlı aday sırası; detay sayfasındaki `?candidate=` ile aynı. */
  candidatePosition: number
}

/** Aday kararı panelinin tamamı (istemci bileşeni). */
export default function CandidateDecisionPanel({
  batchId,
  candidate,
  candidatePosition,
}: CandidateDecisionPanelProps) {
  const availability = deriveCandidateDecisionAvailability(candidate)
  const summary = summarizeCandidateDecision(availability)
  const disabledAll = !summary.canDecide

  // Adım 1 (yazmasız): `draftDecision` yalnızca radyo seçimini tutar.
  // Adım 2 (tek yazma noktası): `confirmedDecision` YALNIZCA "Kararı Seç ve
  // Onaya Git" düğmesine basılınca dolar. Radyo seçimi tek başına onay
  // adımını açmaz; böylece kayıt için iki ayrı bilinçli tıklama gerekir.
  const [draftDecision, setDraftDecision] = useState<CandidateDecision | null>(null)
  const [confirmedDecision, setConfirmedDecision] = useState<CandidateDecision | null>(null)
  const [rationale, setRationale] = useState("")

  // Karar aday verisi değiştiğinde onaylanmış karar geçersizleşebilir; her
  // render'da sunucu tarafı uygunluk yeniden denetlenir.
  const confirmDecision =
    confirmedDecision && availability[confirmedDecision].enabled
      ? confirmedDecision
      : null

  const rationaleRequiredForDraft =
    draftDecision !== null && isRationaleRequired(draftDecision)

  return (
    <section
      aria-labelledby="decision-panel-heading"
      className="rounded-2xl border border-gray-200 bg-white p-4 sm:p-6"
    >
      <h2 id="decision-panel-heading" className="text-lg font-semibold text-gray-900">
        {M.decisionPanelHeading}
      </h2>
      <p className="mt-1 text-sm text-gray-600">{M.decisionPanelIntro}</p>

      <ReadinessSummary candidate={candidate} />

      {confirmDecision ? (
        <ConfirmStep
          candidate={candidate}
          batchId={batchId}
          candidatePosition={candidatePosition}
          decision={confirmDecision}
          rationale={rationale}
          onCancel={() => {
            setConfirmedDecision(null)
            setDraftDecision(null)
            setRationale("")
          }}
        />
      ) : (
        <section aria-labelledby="decision-select-heading" className="mt-6">
          <h3 id="decision-select-heading" className="text-sm font-semibold text-gray-800">
            {M.decisionSelectStepHeading}
          </h3>
          <p className="mt-1 text-sm text-gray-600">{M.decisionSelectStepHint}</p>

          {disabledAll ? (
            <div
              role="status"
              className="mt-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
            >
              <p className="font-semibold">{M.decisionAllDisabledHeading}</p>
              <p className="mt-1">{M.decisionAllDisabledHint}</p>
              <ul className="mt-2 list-inside list-disc space-y-1">
                {CANDIDATE_DECISIONS.map((decision) => {
                  const reason = availability[decision].reason
                  if (!reason) return null
                  return (
                    <li key={decision}>
                      <span className="font-medium">{CANDIDATE_DECISION_LABELS[decision]}</span>
                      {" — "}
                      {blockedReasonMessage(reason)}
                    </li>
                  )
                })}
              </ul>
            </div>
          ) : (
            <p
              role="status"
              className="mt-3 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900"
            >
              {M.decisionEnabledSummary.replace(
                "{decisions}",
                summary.enabledDecisions
                  .map((decision) => CANDIDATE_DECISION_LABELS[decision])
                  .join(", ")
              )}
            </p>
          )}

          {/* YAZMADIĞI ADIM: sunucu aksiyonu YOK, yalnızca yerel durum. */}
          <div className="mt-4 grid gap-4">
            <fieldset className="grid gap-2">
              <legend className="text-sm font-medium text-gray-700">
                {M.decisionSelectLegendLabel}
              </legend>
              {CANDIDATE_DECISIONS.map((decision) => {
                const state = availability[decision]
                const rationaleRequired = isRationaleRequired(decision)
                return (
                  <label
                    key={decision}
                    className={`flex min-h-11 items-start gap-3 rounded-xl border px-4 py-3 ${
                      state.enabled
                        ? "border-gray-300 bg-white"
                        : "cursor-not-allowed border-gray-200 bg-gray-50"
                    }`}
                  >
                    <input
                      type="radio"
                      name="decision-selection"
                      value={decision}
                      disabled={!state.enabled}
                      checked={draftDecision === decision}
                      onChange={() => setDraftDecision(decision)}
                      aria-describedby={`decision-hint-${decision}`}
                      className="mt-1 h-4 w-4"
                    />
                    <span className="grid gap-1">
                      <span
                        className={`text-sm font-semibold ${
                          state.enabled ? "text-gray-900" : "text-gray-400"
                        }`}
                      >
                        {CANDIDATE_DECISION_LABELS[decision]}
                        {rationaleRequired && (
                          <span className="ml-2 text-xs font-normal text-gray-500">*</span>
                        )}
                      </span>
                      <span id={`decision-hint-${decision}`} className="text-xs text-gray-600">
                        {CANDIDATE_DECISION_DESCRIPTIONS[decision]}
                      </span>
                      {!state.enabled && state.reason && (
                        <span className="text-xs font-medium text-amber-800">
                          {blockedReasonMessage(state.reason)}
                        </span>
                      )}
                    </span>
                  </label>
                )
              })}
            </fieldset>

            <div className="grid gap-1">
              <label htmlFor="decision-rationale" className="text-sm font-medium text-gray-700">
                {M.decisionRationaleLabel}
              </label>
              <p id="decision-rationale-hint" className="text-xs text-gray-500">
                {rationaleRequiredForDraft
                  ? M.decisionRationaleHintRequired
                  : M.decisionRationaleHintOptional}
              </p>
              <textarea
                id="decision-rationale"
                rows={4}
                maxLength={RATIONALE_MAX_LENGTH}
                placeholder={M.decisionRationalePlaceholder}
                aria-describedby="decision-rationale-hint"
                value={rationale}
                onChange={(event) => setRationale(event.target.value)}
                className={`${inputClassName} min-h-11`}
              />
            </div>

            <button
              type="button"
              onClick={() => setConfirmedDecision(draftDecision)}
              disabled={disabledAll || draftDecision === null}
              className={`min-h-11 w-full rounded-xl px-5 py-2.5 font-semibold sm:w-auto ${
                disabledAll || draftDecision === null
                  ? "cursor-not-allowed bg-gray-100 text-gray-400"
                  : "bg-gray-900 text-white hover:bg-gray-700"
              }`}
            >
              {M.decisionSubmitLabel}
            </button>
          </div>
        </section>
      )}

      <DecisionHistory candidate={candidate} />

      <p className="mt-6 rounded-xl border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-900">
        {CANDIDATE_DECISION_PUBLICATION_NOTICE}
      </p>
    </section>
  )
}