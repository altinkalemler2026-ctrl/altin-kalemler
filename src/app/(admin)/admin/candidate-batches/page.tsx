import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  hasCandidateBatchReadPermission,
  listCandidateQuestionBatches,
  type CandidateBatchListItem,
} from "@/lib/admin/candidate-batches"
import { ADMIN_CANDIDATE_BATCHES_MESSAGES as M } from "@/lib/admin/admin-panel-messages"
import { parsePage } from "@/lib/admin/question-bank"

type SearchParams = Promise<{ page?: string }>

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
    : "—"
}

/**
 * Gerçek DB status kelime dağarcığı → Türkçe etiket. Bilinmeyen değer
 * ham hâliyle gösterilir (sahte durum üretilmez). Görünür metin etikettir;
 * ham status sayfa üzerinde title özniteliğiyle korunur.
 */
function statusLabel(status: string | null): string {
  if (!status) return M.unknown
  const label: Record<string, string | undefined> = M.statusLabels
  return label[status] ?? status
}

function statusTone(status: string | null): string {
  switch (status) {
    case "validated":
    case "ingested":
      return "border-emerald-200 bg-emerald-50 text-emerald-800"
    case "validating":
      return "border-amber-200 bg-amber-50 text-amber-800"
    case "rejected":
    case "failed":
      return "border-rose-200 bg-rose-50 text-rose-800"
    case "partially_valid":
      return "border-amber-200 bg-amber-50 text-amber-800"
    default:
      return "border-slate-200 bg-slate-50 text-slate-700"
  }
}

function StatusBadge({ status }: { status: string | null }) {
  return (
    <span
      title={status ? `${M.statusLabel}: ${status}` : M.unknown}
      className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-semibold ${statusTone(status)}`}
    >
      <span className="h-1.5 w-1.5 rounded-full bg-current" aria-hidden="true" />
      {statusLabel(status)}
    </span>
  )
}

function CountPill({
  label,
  value,
}: {
  label: string
  value: number | null
}) {
  return (
    <span
      className="inline-flex items-center gap-1 rounded-lg bg-indigo-50 px-2.5 py-1 text-xs text-indigo-900"
    >
      <span className="font-medium opacity-70">{label}</span>
      <span className="font-bold tabular-nums">{formatCount(value)}</span>
    </span>
  )
}

/** Preflight.review_required gerçek olduğunda "İnceleme Gerekli" rozeti. */
function ReviewRequiredBadge({ reviewRequired }: { reviewRequired: boolean | null }) {
  if (reviewRequired !== true) return null
  return (
    <span className="inline-flex items-center gap-1.5 rounded-lg border border-amber-200 bg-amber-50 px-2.5 py-1 text-xs font-semibold text-amber-800">
      <span aria-hidden="true" className="h-1.5 w-1.5 rounded-full bg-amber-500" />
      {M.reviewRequired}
    </span>
  )
}

/** Doğrulama rozeti: yalnız gerçek valid/total oranı. */
function VerificationBadge({ batch }: { batch: CandidateBatchListItem }) {
  const valid = batch.counts.validItems
  const total = batch.counts.totalItems
  if (valid === null || total === null || total <= 0) return null
  const full = valid === total
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-semibold ${
        full
          ? "border-emerald-200 bg-emerald-50 text-emerald-800"
          : "border-amber-200 bg-amber-50 text-amber-800"
      }`}
    >
      <span
        aria-hidden="true"
        className={full ? "h-1.5 w-1.5 rounded-full bg-emerald-500" : "h-1.5 w-1.5 rounded-full bg-amber-500"}
      />
      {formatCount(valid)}/{formatCount(total)} {M.verificationBadge}
    </span>
  )
}

function MetricCard({
  label,
  value,
  unit,
}: {
  label: string
  value: string
  unit: string
}) {
  return (
    <div className="flex flex-col justify-between rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
      <span className="text-xs font-semibold text-slate-500">{label}</span>
      <div className="mt-1 flex items-baseline gap-1.5">
        <span className="text-2xl font-bold tabular-nums text-slate-900">
          {value}
        </span>
        <span className="text-xs font-medium text-slate-500">{unit}</span>
      </div>
    </div>
  )
}

function BatchRow({ batch }: { batch: CandidateBatchListItem }) {
  const preflight = batch.preflightSummary
  return (
    <li className="rounded-xl border border-slate-200 bg-white p-4 shadow-sm transition-shadow hover:shadow-md">
      <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
        <div className="min-w-0 md:max-w-[26rem]">
          <div className="flex flex-wrap items-center gap-2">
            <p className="break-all text-sm font-semibold tracking-tight text-indigo-700">
              {batch.batchKey || "—"}
            </p>
            <span className="rounded-md bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-500">
              {M.schemaVersionLabel}: {batch.schemaVersion ?? "—"}
            </span>
          </div>
          <p className="mt-1 text-sm text-slate-600">
            {batch.origin ?? M.unknown}
            {batch.producerModel ? ` • ${batch.producerModel}` : ""}
          </p>
          <p className="mt-0.5 text-xs text-slate-500">
            {M.createdLabel}: {formatDateTime(batch.createdAt)}
          </p>
        </div>
        <div className="flex flex-col gap-2 md:items-end">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge status={batch.status} />
            <ReviewRequiredBadge reviewRequired={preflight?.reviewRequired ?? null} />
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <CountPill label={M.totalItemsLabel} value={batch.counts.totalItems} />
            <CountPill label={M.validItemsLabel} value={batch.counts.validItems} />
            <CountPill
              label={M.insertedItemsLabel}
              value={batch.counts.insertedItems}
            />
            <VerificationBadge batch={batch} />
          </div>
          <Link
            href={`/admin/candidate-batches/${batch.batchId}`}
            className="inline-flex min-h-[44px] items-center justify-center gap-1.5 rounded-xl bg-indigo-600 px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-indigo-700"
          >
            {M.reviewAction}
            <span aria-hidden="true">→</span>
          </Link>
        </div>
      </div>
    </li>
  )
}

function PaginationNav({
  page,
  totalPages,
}: {
  page: number
  totalPages: number
}) {
  const hasPrev = page > 1
  const hasNext = page < totalPages
  if (!hasPrev && !hasNext) return null
  return (
    <nav
      aria-label={M.paginationLabel}
      className="flex items-center justify-between gap-3 border-t border-slate-200 px-6 py-4"
    >
      {hasPrev ? (
        <Link
          href={`/admin/candidate-batches?page=${page - 1}`}
          className="rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-100"
        >
          {M.prevPage}
        </Link>
      ) : (
        <span
          aria-disabled="true"
          className="rounded-xl border border-slate-200 bg-slate-50 px-4 py-2 text-sm font-medium text-slate-400"
        >
          {M.prevPage}
        </span>
      )}
      <p className="text-sm text-slate-600">
        {`${M.paginationLabel}: Sayfa ${page} / ${totalPages}`}
      </p>
      {hasNext ? (
        <Link
          href={`/admin/candidate-batches?page=${page + 1}`}
          className="rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-100"
        >
          {M.nextPage}
        </Link>
      ) : (
        <span
          aria-disabled="true"
          className="rounded-xl border border-slate-200 bg-slate-50 px-4 py-2 text-sm font-medium text-slate-400"
        >
          {M.nextPage}
        </span>
      )}
    </nav>
  )
}

export default async function AdminCandidateBatchesPage({
  searchParams,
}: {
  searchParams: SearchParams
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

  const params = await searchParams
  const page = parsePage(params.page)
  const result = await listCandidateQuestionBatches(page)

  return (
    <main className="min-h-screen bg-slate-50 p-4 sm:p-8">
      <div className="mx-auto max-w-6xl">
        <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="mb-2 flex flex-wrap items-center gap-2">
              <span className="inline-flex items-center rounded-full bg-indigo-100 px-3 py-1 text-xs font-medium text-indigo-700">
                {M.sourceChip}
              </span>
              <span className="inline-flex items-center rounded-full border border-slate-200 bg-white px-3 py-1 text-xs font-medium text-slate-600">
                {M.modeChip}
              </span>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="text-3xl font-bold tracking-tight text-slate-900">
                {M.title}
              </h1>
              {result.status === "ok" && (
                <span className="inline-flex items-center rounded-full bg-indigo-600 px-3 py-1 text-sm font-bold tabular-nums text-white">
                  {formatCount(result.total)}
                </span>
              )}
            </div>
            <p className="mt-2 max-w-2xl text-sm text-slate-600">{M.subtitle}</p>
          </div>
          <Link
            href="/admin"
            className="rounded-xl border border-slate-300 bg-white px-4 py-2 font-medium text-slate-700 hover:bg-slate-100"
          >
            {M.backToDashboard}
          </Link>
        </div>

        {result.status === "ok" && (
          <section
            aria-label={M.title}
            className="mb-6 grid grid-cols-2 gap-3 sm:gap-4"
          >
            <MetricCard
              label={M.totalPackagesMetric}
              value={formatCount(result.total)}
              unit={M.packageUnitShort}
            />
            <MetricCard
              label={M.shownPackagesMetric}
              value={formatCount(result.items.length)}
              unit={M.packageUnitShort}
            />
          </section>
        )}

        <section
          aria-label={M.title}
          className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6"
        >
          {result.status === "error" ? (
            <p role="alert" className="px-2 py-10 text-slate-600">
              {M.listError}
            </p>
          ) : result.items.length === 0 ? (
            <p className="px-2 py-10 text-slate-600">{M.empty}</p>
          ) : (
            <>
              <div className="mb-3 flex flex-wrap items-center justify-between gap-2 px-1">
                <p className="text-sm text-slate-500">
                  {M.shownOfTotal
                    .replace("{shown}", String(result.items.length))
                    .replace("{total}", String(result.total))}
                </p>
                <Link
                  href="/admin/candidate-batches"
                  className="inline-flex min-h-[44px] items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-sm font-medium text-slate-600 hover:bg-slate-50"
                >
                  {M.refreshLabel}
                </Link>
              </div>
              <ul className="flex flex-col gap-3">
                {result.items.map((batch) => (
                  <BatchRow key={batch.batchId} batch={batch} />
                ))}
              </ul>
              <PaginationNav page={result.page} totalPages={result.totalPages} />
            </>
          )}
        </section>

        <div className="mt-6 flex items-start gap-3 rounded-xl border border-slate-200 bg-white p-4 shadow-sm">
          <div
            aria-hidden="true"
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-indigo-50 text-xl"
          >
            🔒
          </div>
          <div>
            <h2 className="text-sm font-semibold text-slate-900">
              {M.securityTitle}
            </h2>
            <p className="mt-1 text-sm leading-relaxed text-slate-600">
              {M.securityBody}
            </p>
          </div>
        </div>
      </div>
    </main>
  )
}