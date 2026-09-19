import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  hasCandidateBatchReadPermission,
  getCandidateBatchOperationStatus,
  type CandidateBatchOperationStatus,
  type OperationGateCounts,
} from "@/lib/admin/candidate-batches"
import { parseBatchUuid } from "@/lib/admin/candidate-batches-errors"
import { ADMIN_CANDIDATE_BATCH_OPERATION_STATUS_MESSAGES as M } from "@/lib/admin/admin-panel-messages"

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
    : M.none
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

function GateStatusBlock({
  title,
  counts,
  waitingLabels,
}: {
  title: string
  counts: OperationGateCounts
  waitingLabels: { label: string; value: number | null }[]
}) {
  return (
    <div className="mb-4 last:mb-0">
      <h3 className="text-sm font-semibold text-gray-700">{title}</h3>
      <dl className="mt-1 grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
        <div>
          <dt className="text-gray-500">{M.gateTotal}</dt>
          <dd className="font-medium text-gray-900">{formatCount(counts.total)}</dd>
        </div>
        {waitingLabels.map(({ label, value }) => (
          <div key={label}>
            <dt className="text-gray-500">{label}</dt>
            <dd className="font-medium text-gray-900">{formatCount(value)}</dd>
          </div>
        ))}
        <div>
          <dt className="text-gray-500">{M.verified}</dt>
          <dd className="font-medium text-gray-900">{formatCount(counts.verified)}</dd>
        </div>
        <div>
          <dt className="text-gray-500">{M.rejected}</dt>
          <dd className="font-medium text-gray-900">{formatCount(counts.rejected)}</dd>
        </div>
      </dl>
    </div>
  )
}

function WaitingGates({ status }: { status: CandidateBatchOperationStatus }) {
  const gates = status.gates
  return (
    <div>
      <GateStatusBlock
        title={M.gateAnswerVerification}
        counts={gates.answerVerification}
        waitingLabels={[
          { label: M.waitingSolver1, value: gates.answerVerification.waitingSolver1 },
          { label: M.waitingSolver2, value: gates.answerVerification.waitingSolver2 },
          { label: M.needsHumanReview, value: gates.answerVerification.needsHumanReview },
        ]}
      />
      <GateStatusBlock
        title={M.gateCurriculumFit}
        counts={gates.curriculumFit}
        waitingLabels={[
          { label: M.waitingReviewer1, value: gates.curriculumFit.waitingReviewer1 },
          { label: M.waitingReviewer2, value: gates.curriculumFit.waitingReviewer2 },
        ]}
      />
      <GateStatusBlock
        title={M.gateSolveTimeVerification}
        counts={gates.solveTimeVerification}
        waitingLabels={[
          { label: M.waitingReviewer1, value: gates.solveTimeVerification.waitingReviewer1 },
          { label: M.waitingReviewer2, value: gates.solveTimeVerification.waitingReviewer2 },
        ]}
      />
      <GateStatusBlock
        title={M.gateOriginalityVerification}
        counts={gates.originalityVerification}
        waitingLabels={[
          { label: M.waitingReviewer1, value: gates.originalityVerification.waitingReviewer1 },
          { label: M.waitingReviewer2, value: gates.originalityVerification.waitingReviewer2 },
          { label: M.blocked, value: gates.originalityVerification.blocked },
        ]}
      />
      <GateStatusBlock
        title={M.gateQuestionQuality}
        counts={gates.questionQuality}
        waitingLabels={[
          { label: M.waitingReviewer1, value: gates.questionQuality.waitingReviewer1 },
          { label: M.waitingReviewer2, value: gates.questionQuality.waitingReviewer2 },
        ]}
      />
      <GateStatusBlock
        title={M.gateReadiness}
        counts={gates.readiness}
        waitingLabels={[
          { label: M.notReady, value: gates.readiness.notReady },
          { label: M.readyForHumanReview, value: gates.readiness.readyForHumanReview },
          { label: M.humanReviewRequired, value: gates.readiness.humanReviewRequired },
          { label: M.blocked, value: gates.readiness.blocked },
          { label: M.alreadyPromoted, value: gates.readiness.alreadyPromoted },
        ]}
      />
      <GateStatusBlock
        title={M.gateFinalReview}
        counts={gates.finalReview}
        waitingLabels={[
          { label: M.approve, value: gates.finalReview.approve },
          { label: M.requestChanges, value: gates.finalReview.requestChanges },
        ]}
      />
    </div>
  )
}

function ProviderErrorBlock({ status }: { status: CandidateBatchOperationStatus }) {
  const provider = status.provider
  return (
    <div>
      {provider.hasBatchErrorData ? (
        <p className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
          {M.providerHasBatchError}
        </p>
      ) : (
        <p className="rounded-xl border border-gray-200 bg-white p-4 text-sm text-gray-700">
          {M.providerNoBatchError}
        </p>
      )}
      <dl className="mt-3 grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
        <Field
          label={M.candidateValidationErrorCountLabel}
          value={formatCount(provider.candidateValidationErrorCount)}
        />
      </dl>
    </div>
  )
}

function SafeRetryBlock({ status }: { status: CandidateBatchOperationStatus }) {
  const retry = status.retry
  return (
    <div>
      <dl className="mb-3 grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
        <Field label={M.retryStatusLabel} value={M.retryNotSupported} />
      </dl>
      {retry.supported ? (
        <p className="rounded-xl border border-gray-200 bg-white p-4 text-sm text-gray-700">
          {M.retrySupportedFalse}
        </p>
      ) : (
        <div className="rounded-xl border border-gray-200 bg-white p-4">
          <p className="text-sm text-gray-700">{M.retrySupportedFalse}</p>
          <p className="mt-1 text-sm text-gray-500">{M.retryUnsupportedReason}</p>
        </div>
      )}
    </div>
  )
}

function StatusBody({ status }: { status: CandidateBatchOperationStatus }) {
  const batch = status.batch
  const phase = status.phase.candidateCounts
  return (
    <div className="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
      <div className="border-b border-gray-200 bg-gray-50 px-6 py-4">
        <h1 className="text-2xl font-bold text-gray-900">{M.title}</h1>
        <p className="mt-1 font-semibold text-gray-700">{batch.batchKey}</p>
      </div>

      <DetailSection title={M.batchInfoTitle}>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
          <Field label={M.statusLabel} value={batch.status ?? ""} />
          <Field label={M.batchKeyLabel} value={batch.batchKey} />
          <Field label={M.createdLabel} value={formatDateTime(batch.createdAt)} />
          <Field label={M.updatedLabel} value={formatDateTime(batch.updatedAt)} />
        </dl>
      </DetailSection>

      <DetailSection title={M.countsTitle}>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
          <Field label={M.totalItemsLabel} value={formatCount(batch.counts.totalItems)} />
          <Field label={M.validItemsLabel} value={formatCount(batch.counts.validItems)} />
          <Field label={M.invalidItemsLabel} value={formatCount(batch.counts.invalidItems)} />
          <Field label={M.insertedItemsLabel} value={formatCount(batch.counts.insertedItems)} />
          <Field label={M.duplicateItemsLabel} value={formatCount(batch.counts.duplicateItems)} />
        </dl>
      </DetailSection>

      <DetailSection title={M.phaseTitle}>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
          <Field label={M.candidateCountsPending} value={formatCount(phase.pending)} />
          <Field label={M.candidateCountsValid} value={formatCount(phase.valid)} />
          <Field label={M.candidateCountsInvalid} value={formatCount(phase.invalid)} />
          <Field label={M.candidateCountsDuplicate} value={formatCount(phase.duplicate)} />
          <Field label={M.candidateCountsInserted} value={formatCount(phase.inserted)} />
          <Field label={M.candidateCountsFailed} value={formatCount(phase.failed)} />
        </dl>
      </DetailSection>

      <DetailSection title={M.gatesTitle}>
        <WaitingGates status={status} />
      </DetailSection>

      <DetailSection title={M.providerTitle}>
        <ProviderErrorBlock status={status} />
      </DetailSection>

      <DetailSection title={M.retryTitle}>
        <SafeRetryBlock status={status} />
      </DetailSection>
    </div>
  )
}

export default async function AdminCandidateBatchOperationStatusPage({
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

  const result = await getCandidateBatchOperationStatus(batchId)

  if (result.status === "error") {
    return (
      <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
        <div className="mx-auto max-w-3xl">
          <BackLink />
          <p role="alert" className="rounded-2xl border border-amber-200 bg-amber-50 px-6 py-10 text-amber-800">
            {M.statusError}
          </p>
        </div>
      </main>
    )
  }

  const status = result.item

  if (!status) {
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
        <StatusBody status={status} />
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
      {M.backToDetail}
    </Link>
  )
}