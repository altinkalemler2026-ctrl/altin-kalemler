import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  listUsers,
  parseGrade,
  parsePage,
  parseSort,
  SORT_OPTIONS,
  GRADES,
  type ListPageResult,
  type SortOption,
  type UserListItem,
} from "@/lib/admin/admin-users"
import { ADMIN_USERS_MESSAGES as M } from "@/lib/admin/admin-panel-messages"

type PermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

type SearchParams = Promise<{
  grade?: string
  query?: string
  page?: string
  sort?: string
}>

/** Deterministik tarih gösterimi (GG.AA.YYYY); bozuk girdide "-". */
function formatDate(value: string): string {
  if (!value) return "-"
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return "-"
  return d.toLocaleDateString("tr-TR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  })
}

/** Filtreleri koruyarak güvenli kodlanmış sayfa bağlantısı üretir. */
function pageHref(
  current: { grade?: string; query?: string; sort?: string },
  page: number
): string {
  const sp = new URLSearchParams()
  if (current.grade) sp.set("grade", current.grade)
  if (current.query) sp.set("query", current.query)
  if (current.sort) sp.set("sort", current.sort)
  sp.set("page", String(page))
  return `/admin/users?${sp.toString()}`
}

function PaginationNav({
  result,
  current,
}: {
  result: ListPageResult<UserListItem>
  current: { grade?: string; query?: string; sort?: string }
}) {
  const hasPrev = result.page > 1
  const hasNext = result.page < result.totalPages
  if (!hasPrev && !hasNext) return null
  return (
    <nav
      aria-label={M.paginationLabel}
      className="flex items-center justify-between gap-3 border-t border-gray-200 px-6 py-4"
    >
      {hasPrev ? (
        <Link
          href={pageHref(current, result.page - 1)}
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
        {`Sayfa ${result.page} / ${result.totalPages}`}
      </p>
      {hasNext ? (
        <Link
          href={pageHref(current, result.page + 1)}
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

export default async function AdminUsersPage({
  searchParams,
}: {
  searchParams: SearchParams
}) {
  const supabase = await createClient()

  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    redirect("/login")
  }

  const rpc = supabase.rpc.bind(supabase) as unknown as PermissionRpc
  const { data: canView, error: permissionError } = await rpc(
    "teacher_review_admin_has_permission",
    { p_permission_code: "users.manage" },
  )

  if (permissionError || canView !== true) {
    redirect("/dashboard")
  }

  const params = await searchParams
  const grade = parseGrade(params.grade)
  const query = params.query?.trim() || undefined
  const page = parsePage(params.page)
  const sort = parseSort(params.sort)

  const result = await listUsers(
    {
      grade: grade ?? undefined,
      query,
      sort,
    },
    page
  )
  const currentFilters = {
    grade: grade !== null ? String(grade) : undefined,
    query,
    sort,
  }

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

        <form
          method="get"
          className="mb-6 grid gap-3 rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:grid-cols-2 lg:grid-cols-3"
        >
          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.searchLabel}
            </span>
            <input
              name="query"
              defaultValue={query ?? ""}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            />
          </label>

          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.gradeLabel}
            </span>
            <select
              name="grade"
              defaultValue={grade ?? ""}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            >
              <option value="">{M.allGrades}</option>
              {GRADES.map((g) => (
                <option key={g} value={g}>
                  {g}. {M.classYears}
                </option>
              ))}
            </select>
          </label>

          <label className="block">
            <span className="text-sm font-medium text-gray-700">
              {M.sortLabel}
            </span>
            <select
              name="sort"
              defaultValue={sort}
              className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
            >
              {SORT_OPTIONS.map((s: SortOption) => (
                <option key={s} value={s}>
                  {s === "oldest" ? M.sortOldest : M.sortNewest}
                </option>
              ))}
            </select>
          </label>

          <div className="flex items-end">
            <button
              type="submit"
              className="w-full rounded-xl bg-gray-900 px-5 py-2.5 font-semibold text-white hover:bg-gray-700 sm:w-auto"
            >
              {M.filterLabel}
            </button>
          </div>
        </form>

        <section
          aria-label="Kullanıcı listesi"
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
              {result.items.map((u) => (
                <li key={u.id}>
                  <Link
                    href={`/admin/users/${u.id}`}
                    className="flex flex-wrap items-center justify-between gap-3 px-6 py-4 hover:bg-gray-50"
                  >
                    <div className="min-w-0">
                      <p className="font-semibold text-gray-900">{u.nickname}</p>
                      <p className="mt-0.5 text-sm text-gray-600">
                        {formatDate(u.created_at)}
                      </p>
                    </div>
                    <div className="flex flex-wrap items-center gap-2 text-sm text-gray-600">
                      <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium">
                        {u.grade_level}. {M.classYears}
                      </span>
                      {u.total_points !== null && (
                        <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs">
                          {M.points}: {u.total_points.toLocaleString("tr-TR")}
                        </span>
                      )}
                      {u.is_visible !== null && (
                        <span
                          className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                            u.is_visible
                              ? "bg-emerald-100 text-emerald-700"
                              : "bg-gray-100 text-gray-600"
                          }`}
                        >
                          {u.is_visible ? M.visible : M.hidden}
                        </span>
                      )}
                    </div>
                  </Link>
                </li>
              ))}
              </ul>
              <PaginationNav result={result} current={currentFilters} />
            </>
          )}
        </section>
      </div>
    </main>
  )
}
