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

function BatchStatusBadge({ status }: { status: string | null }) {
  const text = status ?? M.unknown
  return (
    <span className="inline-flex items-center rounded-full bg-gray-100 px-3 py-1 text-xs font-semibold text-gray-700">
      {text}
    </span>
  )
}

function CountBadge({ label, value }: { label: string; value: number | null }) {
  return (
    <span
      className="inline-flex items-center gap-1 rounded-lg bg-gray-50 px-2 py-0.5 text-xs font-medium text-gray-600"
      title={label}
    >
      <span className="text-gray-400">{label}</span>
      <span className="font-semibold text-gray-900">
        {value !== null && value !== undefined
          ? value.toLocaleString("tr-TR")
          : "—"}
      </span>
    </span>
  )
}

function BatchRow({ batch }: { batch: CandidateBatchListItem }) {
  return (
    <li>
      <Link
        href={`/admin/candidate-batches/${batch.batchId}`}
        className="flex flex-col gap-3 px-6 py-4 hover:bg-gray-50 sm:flex-row sm:items-center sm:justify-between"
      >
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <p className="font-semibold text-gray-900">{batch.batchKey || "—"}</p>
            <BatchStatusBadge status={batch.status} />
          </div>
          <p className="mt-1 text-sm text-gray-600">
            {M.originLabel}: {batch.origin ?? M.unknown}
            {batch.producerModel ? ` • ${batch.producerModel}` : ""}
          </p>
          <p className="mt-0.5 text-xs text-gray-500">
            {M.createdLabel}: {formatDateTime(batch.createdAt)}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <CountBadge label={M.totalItemsLabel} value={batch.counts.totalItems} />
          <CountBadge label={M.validItemsLabel} value={batch.counts.validItems} />
          <CountBadge
            label={M.invalidItemsLabel}
            value={batch.counts.invalidItems}
          />
          <CountBadge
            label={M.insertedItemsLabel}
            value={batch.counts.insertedItems}
          />
        </div>
      </Link>
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
      className="flex items-center justify-between gap-3 border-t border-gray-200 px-6 py-4"
    >
      {hasPrev ? (
        <Link
          href={`/admin/candidate-batches?page=${page - 1}`}
          className="rounded-xl border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-100"
        >
          {M.prevPage}
        </Link>
      ) : (
        <span
          aria-disabled="true"
          className="rounded-xl border border-gray-200 bg-gray-50 px-4 py-2 text-sm font-medium text-gray-400"
        >
          {M.prevPage}
        </span>
      )}
      <p className="text-sm text-gray-600">
        {`Sayfa ${page} / ${totalPages}`}
      </p>
      {hasNext ? (
        <Link
          href={`/admin/candidate-batches?page=${page + 1}`}
          className="rounded-xl border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-100"
        >
          {M.nextPage}
        </Link>
      ) : (
        <span
          aria-disabled="true"
          className="rounded-xl border border-gray-200 bg-gray-50 px-4 py-2 text-sm font-medium text-gray-400"
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
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-6xl">
        <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="text-3xl font-bold text-gray-900">{M.title}</h1>
            <p className="mt-2 text-gray-600">{M.subtitle}</p>
          </div>
          <Link
            href="/admin"
            className="rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
          >
            {M.backToDashboard}
          </Link>
        </div>

        <section
          aria-label={M.title}
          className="rounded-2xl border border-gray-200 bg-white shadow-sm"
        >
          {result.status === "error" ? (
            <p role="alert" className="px-6 py-10 text-gray-600">
              {M.listError}
            </p>
          ) : result.items.length === 0 ? (
            <p className="px-6 py-10 text-gray-600">{M.empty}</p>
          ) : (
            <>
              <ul className="divide-y divide-gray-200">
                {result.items.map((batch) => (
                  <BatchRow key={batch.batchId} batch={batch} />
                ))}
              </ul>
              <PaginationNav page={result.page} totalPages={result.totalPages} />
            </>
          )}
        </section>
      </div>
    </main>
  )
}