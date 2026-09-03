import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  AUDIT_ACTION_CODES,
  hasAuditViewPermission,
  listAuditLog,
  parseAuditActionCode,
  parseAuditEntityId,
  type AuditLogEntry,
} from "@/lib/admin/audit-log"
import {
  ADMIN_AUDIT_MESSAGES as M,
} from "@/lib/admin/admin-panel-messages"

type SearchParams = Promise<{
  action?: string
  entity?: string
  page?: string
}>

type CurrentFilters = {
  action?: string
  entity?: string
}

/** Filtreleri koruyarak güvenli kodlanmış sayfa bağlantısı üretir. */
function pageHref(current: CurrentFilters, page: number): string {
  const sp = new URLSearchParams()
  for (const [key, value] of Object.entries(current)) {
    if (value) sp.set(key, value)
  }
  sp.set("page", String(page))
  return `/admin/audit?${sp.toString()}`
}

function PaginationNav({
  total,
  page,
  totalPages,
  current,
}: {
  total: number
  page: number
  totalPages: number
  current: CurrentFilters
}) {
  if (total === 0) return null
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
          href={pageHref(current, page - 1)}
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
          href={pageHref(current, page + 1)}
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

function AuditRow({ entry }: { entry: AuditLogEntry }) {
  return (
    <li className="grid gap-1 px-6 py-4 sm:grid-cols-[10rem_1fr] sm:gap-4">
      <span className="text-sm text-gray-500">
        {entry.performedAt ? entry.performedAt.replace("T", " ") : "-"}
      </span>
      <div className="min-w-0">
        <p className="font-mono text-sm font-semibold text-gray-900">
          {entry.actionCode}
        </p>
        <p className="mt-0.5 text-sm text-gray-600">
          {M.entityLabel}: {entry.entityType}
          {entry.entityId ? ` · ${entry.entityId}` : ""}
        </p>
        <p className="text-sm text-gray-500">
          {M.actorLabel}:{" "}
          <span className="font-mono">
            {entry.actorUserId ?? M.noActor}
          </span>
        </p>
      </div>
    </li>
  )
}

export default async function AdminAuditPage({
  searchParams,
}: {
  searchParams: SearchParams
}) {
  const supabase = await createClient()

  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    redirect("/login")
  }

  // audit.view izni yoksa sayfa hiç render edilmez (fail-closed);
  // satır görünürlüğünü zaten 089 RLS SELECT policy yönetir.
  if (!(await hasAuditViewPermission())) {
    redirect("/dashboard")
  }

  const params = await searchParams
  const actionCode = parseAuditActionCode(params.action)
  const entityId = parseAuditEntityId(params.entity)
  const page = Number(params.page ?? "1")

  const result = await listAuditLog(
    { actionCode, entityId },
    Number.isInteger(page) ? page : 1
  )

  const currentFilters: CurrentFilters = {
    action: actionCode,
    entity: entityId,
  }

  return (
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-4xl">
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

        <form
          method="get"
          className="mb-6 flex flex-wrap items-center gap-3 rounded-2xl border border-gray-200 bg-white p-4 shadow-sm"
        >
          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.actionLabel}
            </span>
            <select
              name="action"
              defaultValue={actionCode ?? ""}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            >
              <option value="">{M.allActions}</option>
              {AUDIT_ACTION_CODES.map((code) => (
                <option key={code} value={code}>
                  {code}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.entityIdLabel}
            </span>
            <input
              name="entity"
              defaultValue={entityId ?? ""}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            />
          </label>

          <div className="flex items-end">
            <button
              type="submit"
              className="rounded-xl bg-gray-900 px-5 py-2.5 font-semibold text-white hover:bg-gray-700"
            >
              {M.filterLabel}
            </button>
          </div>
        </form>

        <section className="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
          {result.status === "error" ? (
            <p role="alert" className="px-6 py-10 text-gray-600">
              {M.listError}
            </p>
          ) : result.items.length === 0 ? (
            <p className="px-6 py-10 text-gray-600">{M.empty}</p>
          ) : (
            <>
              <ul className="divide-y divide-gray-200">
                {result.items.map((entry) => (
                  <AuditRow key={entry.id} entry={entry} />
                ))}
              </ul>
              <PaginationNav
                total={result.total}
                page={result.page}
                totalPages={result.totalPages}
                current={currentFilters}
              />
            </>
          )}
        </section>
      </div>
    </main>
  )
}
