import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  hasCandidateBatchReadPermission,
  getCandidateBatchDetail,
  type CandidateBatchDetail,
  type CandidateRecord,
  type CandidatePreview,
  type GateField,
  type CandidateGates,
} from "@/lib/admin/candidate-batches"
import { parseBatchUuid } from "@/lib/admin/candidate-batches-errors"
import { ADMIN_CANDIDATE_BATCH_DETAIL_MESSAGES as M } from "@/lib/admin/admin-panel-messages"
import { ADMIN_CANDIDATE_BATCH_OPERATION_STATUS_MESSAGES as OM } from "@/lib/admin/admin-panel-messages"

type Params = Promise<{ id: string }>

/** Deterministik tarih gösterimi (GG.AA.YYYY SS:DD); bozuk girdide "-". */
function formatDateTime(value: string | null): string {
  if (!value) return "-"
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return "-"
  return d.toLocaleDateString("tr-TR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  })
}

function formatCount(value: number | null): string {
  return value !== null && value !== undefined
    ? value.toLocaleString("tr-TR")
    : M.notAvailable
}

function Field({
  label,
  value,
}: {
  label: string
  value: string
}) {
  return (
    <div>
      <dt className="text-gray-500">{label}</dt>
      <dd className="font-medium text-gray-900">{value || M.notSet}</dd>
    </div>
  )
}

function DetailSection({
  title,
  children,
}: {
  title: string
  children: React.ReactNode
}) {
  return (
    <div className="border-t border-gray-200 bg-gray-50 px-6 py-5">
      <h2 className="mb-3 text-sm font-semibold text-gray-500 uppercase">
        {title}
      </h2>
      {children}
    </div>
  )
}

function GateRunBlock({
  title,
  gate,
}: {
  title: string
  gate: { fields: GateField[] } | null
}) {
  if (!gate || gate.fields.length === 0) {
    return (
      <div className="mb-4 last:mb-0">
        <h3 className="text-sm font-semibold text-gray-700">{title}</h3>
        <p className="mt-1 text-sm text-gray-500">{M.notAvailable}</p>
      </div>
    )
  }
  return (
    <div className="mb-4 last:mb-0">
      <h3 className="text-sm font-semibold text-gray-700">{title}</h3>
      <dl className="mt-1 grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
        {gate.fields.map((field) => (
          <div key={field.key}>
            <dt className="text-gray-500">{field.key}</dt>
            <dd className="font-medium text-gray-900">
              {Array.isArray(field.value)
                ? field.value.length > 0
                  ? field.value.join(", ")
                  : "—"
                : field.value === null || field.value === undefined
                  ? "—"
                  : String(field.value)}
            </dd>
          </div>
        ))}
      </dl>
    </div>
  )
}

function GatesSummary({ gates }: { gates: CandidateGates }) {
  return (
    <div>
      <GateRunBlock
        title="Cevap Doğrulama (answer_verification)"
        gate={gates.answerVerification}
      />
      <GateRunBlock title="Müfredat Uyumu (curriculum_fit)" gate={gates.curriculumFit} />
      <GateRunBlock
        title="Çözüm Süresi (solve_time_verification)"
        gate={gates.solveTimeVerification}
      />
      <GateRunBlock
        title="Özgünlük (originality_verification)"
        gate={gates.originalityVerification}
      />
      <GateRunBlock title="Soru Kalitesi (question_quality)" gate={gates.questionQuality} />
      <GateRunBlock title="Hazırlık (readiness)" gate={gates.readiness} />
      <GateRunBlock title="Nihai İnceleme (final_review)" gate={gates.finalReview} />
    </div>
  )
}

function PreviewBlock({ preview }: { preview: CandidatePreview }) {
  return (
    <div>
      <p className="mb-2 text-sm text-gray-700">
        {M.stagingStatusLabel}: {preview.stagingStatus ?? M.notSet}
      </p>
      <div className="mb-3 rounded-xl border border-gray-200 bg-white p-4">
        <h4 className="text-sm font-semibold text-gray-700">
          {M.previewTitle}
        </h4>
        <p className="mt-1 whitespace-pre-wrap text-gray-900">
          {preview.questionText || M.questionTextMissing}
        </p>
      </div>

      {preview.options && (
        <div className="mb-3 rounded-xl border border-gray-200 bg-white p-4">
          <h4 className="text-sm font-semibold text-gray-700">
            {M.optionsTitle}
          </h4>
          <ul className="mt-2 space-y-1">
            {(["A", "B", "C", "D", "E"] as const).map((letter) => {
              const text = preview.options?.[letter] ?? null
              if (!text) return null
              return (
                <li key={letter} className="text-sm text-gray-900">
                  <span className="font-semibold">{letter}.</span> {text}
                </li>
              )
            })}
          </ul>
        </div>
      )}

      <dl className="mb-3 grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
        <Field
          label={M.proposedCorrectAnswerLabel}
          value={preview.proposedCorrectAnswer ?? ""}
        />
        <Field
          label={M.proposedDifficultyLabel}
          value={preview.proposedDifficulty ?? ""}
        />
        <Field
          label={M.proposedCognitiveTypeLabel}
          value={preview.proposedCognitiveType ?? ""}
        />
        <Field
          label={M.proposedSolveTimeLabel}
          value={
            preview.proposedSolveTimeSeconds !== null &&
            preview.proposedSolveTimeSeconds !== undefined
              ? `${preview.proposedSolveTimeSeconds} ${M.proposedSolveTimeUnit}`
              : ""
          }
        />
        <Field
          label={M.gradeLevelLabel}
          value={
            preview.gradeLevel !== null && preview.gradeLevel !== undefined
              ? String(preview.gradeLevel)
              : ""
          }
        />
        <Field label={M.subjectIdLabel} value={preview.subjectId ?? ""} />
        <Field
          label={M.ownershipStatusLabel}
          value={preview.ownershipStatus ?? ""}
        />
        <Field label={M.licenseStatusLabel} value={preview.licenseStatus ?? ""} />
        <Field
          label={M.commercialUseAllowedLabel}
          value={preview.commercialUseAllowed ?? ""}
        />
        <Field
          label={M.copyrightRiskLevelLabel}
          value={preview.copyrightRiskLevel ?? ""}
        />
      </dl>

      <div className="rounded-xl border border-gray-200 bg-white p-4">
        <h4 className="text-sm font-semibold text-gray-700">{M.solutionTitle}</h4>
        <p className="mt-1 whitespace-pre-wrap text-gray-900">
          {preview.solution || M.solutionMissing}
        </p>
      </div>
    </div>
  )
}

function ValidationResultsBlock({
  candidate,
}: {
  candidate: CandidateRecord
}) {
  if (candidate.validationResults.length === 0) {
    return <p className="text-sm text-gray-500">{M.noValidationResults}</p>
  }
  return (
    <ul className="space-y-3">
      {candidate.validationResults.map((item, index) => (
        <li
          key={`${item.validatorType}-${item.createdAt}-${index}`}
          className="rounded-xl border border-gray-200 bg-white p-4"
        >
          <dl className="grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
            <Field
              label={M.validatorTypeLabel}
              value={item.validatorType ?? ""}
            />
            <Field
              label={M.validationTypeLabel}
              value={item.validationType ?? ""}
            />
            <Field label={M.resultLabel} value={item.result ?? ""} />
            <Field
              label={M.scoreLabel}
              value={item.score !== null && item.score !== undefined ? String(item.score) : ""}
            />
            <Field label={M.providerModelLabel} value={item.modelName ?? ""} />
            <Field
              label={M.createdAtLabel}
              value={formatDateTime(item.createdAt)}
            />
            {item.summary && (
              <div className="col-span-2">
                <dt className="text-gray-500">{M.summaryLabel}</dt>
                <dd className="whitespace-pre-wrap font-medium text-gray-900">
                  {item.summary}
                </dd>
              </div>
            )}
          </dl>
        </li>
      ))}
    </ul>
  )
}

function ReviewQueueBlock({ candidate }: { candidate: CandidateRecord }) {
  if (candidate.reviewQueue.length === 0) {
    return <p className="text-sm text-gray-500">{M.noReviewQueue}</p>
  }
  return (
    <ul className="space-y-3">
      {candidate.reviewQueue.map((entry, index) => (
        <li
          key={`${entry.reasonCode}-${entry.createdAt}-${index}`}
          className="rounded-xl border border-gray-200 bg-white p-4"
        >
          <dl className="grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
            <Field label={M.reasonCodeLabel} value={entry.reasonCode ?? ""} />
            <Field label={M.priorityLabel} value={entry.priority ?? ""} />
            <Field label={M.statusLabel} value={entry.status ?? ""} />
            <Field
              label={M.createdAtLabel}
              value={formatDateTime(entry.createdAt)}
            />
            {entry.reasonDetails && (
              <div className="col-span-2">
                <dt className="text-gray-500">{M.reasonDetailsLabel}</dt>
                <dd className="whitespace-pre-wrap font-medium text-gray-900">
                  {entry.reasonDetails}
                </dd>
              </div>
            )}
          </dl>
        </li>
      ))}
    </ul>
  )
}

function CandidateBlock({ candidate }: { candidate: CandidateRecord }) {
  return (
    <div className="border-t border-gray-200 p-6">
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <h3 className="text-lg font-semibold text-gray-900">
          {M.candidateLabel} #{candidate.candidateIndex + 1}
        </h3>
        <span className="rounded-full bg-gray-100 px-3 py-1 text-xs font-semibold text-gray-700">
          {M.validationStatusLabel}: {candidate.validationStatus ?? M.notSet}
        </span>
      </div>

      <dl className="mb-4 grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
        <Field
          label={M.clientQuestionIdLabel}
          value={candidate.clientQuestionId ?? ""}
        />
        <Field
          label={M.stagingStatusLabel}
          value={candidate.preview?.stagingStatus ?? ""}
        />
      </dl>

      {candidate.validationErrors.length > 0 ? (
        <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 p-4">
          <h4 className="text-sm font-semibold text-amber-800">
            {M.validationErrorsLabel}
          </h4>
          <ul className="mt-1 list-inside list-disc text-sm text-amber-800">
            {candidate.validationErrors.map((error) => (
              <li key={error}>{error}</li>
            ))}
          </ul>
        </div>
      ) : (
        <p className="mb-4 text-sm text-gray-500">{M.noValidationErrors}</p>
      )}

      {candidate.validationWarnings.length > 0 && (
        <div className="mb-4 rounded-xl border border-yellow-200 bg-yellow-50 p-4">
          <h4 className="text-sm font-semibold text-yellow-800">
            {M.validationWarningsLabel}
          </h4>
          <ul className="mt-1 list-inside list-disc text-sm text-yellow-800">
            {candidate.validationWarnings.map((warning) => (
              <li key={warning}>{warning}</li>
            ))}
          </ul>
        </div>
      )}

      {candidate.preview && (
        <PreviewBlock preview={candidate.preview} />
      )}

      <DetailSection title={M.validationResultsTitle}>
        <ValidationResultsBlock candidate={candidate} />
      </DetailSection>

      <DetailSection title={M.reviewQueueTitle}>
        <ReviewQueueBlock candidate={candidate} />
      </DetailSection>

      <DetailSection title={M.gatesTitle}>
        <GatesSummary gates={candidate.gates} />
      </DetailSection>
    </div>
  )
}

function DetailBody({ detail }: { detail: CandidateBatchDetail }) {
  return (
    <div className="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
      <div className="border-b border-gray-200 bg-gray-50 px-6 py-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{M.title}</h1>
            <p className="mt-1 font-semibold text-gray-700">
              {detail.batch.batchKey}
            </p>
          </div>
          <Link
            href={`/admin/candidate-batches/${detail.batch.batchId}/islem-durumu`}
            className="rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
          >
            {OM.detailLinkLabel}
          </Link>
        </div>
      </div>

      <DetailSection title={M.batchInfoTitle}>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
          <Field label={M.statusLabel} value={detail.batch.status ?? ""} />
          <Field
            label={M.originLabel}
            value={detail.batch.origin ?? ""}
          />
          <Field
            label={M.producerIdLabel}
            value={detail.batch.producerId ?? ""}
          />
          <Field
            label={M.producerModelLabel}
            value={detail.batch.producerModel ?? ""}
          />
          <Field
            label={M.schemaVersionLabel}
            value={detail.batch.schemaVersion ?? ""}
          />
          <Field
            label={M.createdLabel}
            value={formatDateTime(detail.batch.createdAt)}
          />
          <Field
            label={M.updatedLabel}
            value={formatDateTime(detail.batch.updatedAt)}
          />
        </dl>
      </DetailSection>

      <DetailSection title={M.countsTitle}>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
          <Field
            label={M.totalItemsLabel}
            value={formatCount(detail.batch.counts.totalItems)}
          />
          <Field
            label={M.validItemsLabel}
            value={formatCount(detail.batch.counts.validItems)}
          />
          <Field
            label={M.invalidItemsLabel}
            value={formatCount(detail.batch.counts.invalidItems)}
          />
          <Field
            label={M.insertedItemsLabel}
            value={formatCount(detail.batch.counts.insertedItems)}
          />
          <Field
            label={M.duplicateItemsLabel}
            value={formatCount(detail.batch.counts.duplicateItems)}
          />
        </dl>
      </DetailSection>

      <DetailSection
        title={`${M.candidatesTitle} (${detail.candidates.length})`}
      >
        {detail.candidates.length === 0 ? (
          <p className="text-sm text-gray-500">{M.noCandidates}</p>
        ) : (
          detail.candidates.map((candidate) => (
            <CandidateBlock key={candidate.candidateIndex} candidate={candidate} />
          ))
        )}
      </DetailSection>
    </div>
  )
}

export default async function AdminCandidateBatchDetailPage({
  params,
}: {
  params: Params
}) {
  const supabase = await createClient()
  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    redirect("/login")
  }

  const allowed = await hasCandidateBatchReadPermission()
  if (!allowed) {
    redirect("/dashboard")
  }

  const { id } = await params
  const batchId = parseBatchUuid(id)

  if (!batchId) {
    return (
      <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
        <div className="mx-auto max-w-3xl">
          <BackLink />
          <p role="status" className="rounded-2xl border border-gray-200 bg-white px-6 py-10 text-gray-600">
            {M.notFoundHint}
          </p>
        </div>
      </main>
    )
  }

  const result = await getCandidateBatchDetail(batchId)

  if (result.status === "error") {
    return (
      <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
        <div className="mx-auto max-w-3xl">
          <BackLink />
          <p role="alert" className="rounded-2xl border border-amber-200 bg-amber-50 px-6 py-10 text-amber-800">
            {M.detailError}
          </p>
        </div>
      </main>
    )
  }

  const detail = result.item

  if (!detail) {
    return (
      <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
        <div className="mx-auto max-w-3xl">
          <BackLink />
          <p className="rounded-2xl border border-gray-200 bg-white px-6 py-10 text-gray-600">
            {M.notFoundTitle}
          </p>
        </div>
      </main>
    )
  }

  return (
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-5xl">
        <BackLink />
        <DetailBody detail={detail} />
      </div>
    </main>
  )
}

function BackLink() {
  return (
    <Link
      href="/admin/candidate-batches"
      className="mb-4 inline-block rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
    >
      {M.backToList}
    </Link>
  )
}