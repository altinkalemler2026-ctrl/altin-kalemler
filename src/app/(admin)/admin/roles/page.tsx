import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import { hasAuditViewPermission, parseAuditEntityId } from "@/lib/admin/audit-log"
import { listUsers } from "@/lib/admin/admin-users"
import { ADMIN_ROLES_MESSAGES as M } from "@/lib/admin/admin-panel-messages"
import {
  assignableRolesFromCatalog,
  buildRoleManagementView,
  hasUsersManagePermission,
  isCurrentUserSuperAdmin,
  listActiveRoles,
  listRoleAssignments,
  resolveUserNicknames,
} from "@/lib/admin/role-management"
import RoleManagementPanel, {
  type PanelTarget,
} from "./RoleManagementPanel"
import type { RosterAdmin } from "@/lib/admin/role-management"

type SearchParams = Promise<{
  q?: string
  ok?: string
  error?: string
  target?: string
  audit?: string
}>

function firstParam(value: string | string[] | undefined): string {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "")
}

function RoleChip({ admin }: { admin: RosterAdmin }) {
  return (
    <div className="flex flex-wrap gap-2">
      {admin.roles.map((role) => (
        <span
          key={role.roleCode}
          className="rounded-full bg-indigo-50 px-3 py-1 text-xs font-medium text-indigo-700"
        >
          {role.roleName}
          {role.roleCode === "super_admin" && (
            <span
              title={M.superAdminChipHint}
              className="ml-1 rounded-full bg-gray-100 px-1.5 text-gray-500"
            >
              *
            </span>
          )}
        </span>
      ))}
      {admin.roles.length === 0 && (
        <span className="text-xs text-gray-500">{M.noRoles}</span>
      )}
    </div>
  )
}

type PermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

function RolesHeader() {
  return (
    <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 className="text-3xl font-bold text-gray-900">{M.title}</h1>
        <p className="mt-2 text-gray-600">{M.subtitle}</p>
      </div>
      <Link
        href="/admin"
        className="inline-flex min-h-[44px] items-center rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
      >
        {M.backToDashboard}
      </Link>
    </div>
  )
}

/**
 * Güvenli kapalı durum (RC-2 düzeltmesi).
 *
 * `users.manage` ve/veya süper yönetici olmayan bir yönetici bu kartı görür:
 * rol listesi, hedef kullanıcı verisi, arama formu ve mutasyon kontrolü
 * HİÇ render edilmez ve HİÇ okunmaz (veri minimizasyonu). Sahte buton,
 * sahte denetim bağlantısı veya ham hata metni üretilmez.
 */
function RolesClosedState() {
  return (
    <section
      aria-labelledby="roles-closed-heading"
      className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6"
    >
      <h2
        id="roles-closed-heading"
        className="text-lg font-semibold text-gray-900"
      >
        {M.mutationClosedHeading}
      </h2>
      <p
        role="status"
        className="mt-2 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
      >
        {M.mutationClosedBody}
      </p>
    </section>
  )
}

/**
 * /admin/roles — Süper admin rol yönetimi.
 *
 * Katmanlı koruma:
 *  - Rota erişim kapısı admin layout ile aynı `questions.view` düzeyindedir;
 *    oturumsuz istek `/login`'e, admin olmayan istek `/dashboard`'a gider
 *    (layout koruması aynen sürer, buradaki kontrol derinlik savunmasıdır).
 *  - Veri ve mutasyon yüzeyi yalnız `users.manage` + `is_current_user_super_admin`
 *    birlikte açıkken render edilir; ikisinden biri yoksa yalnız kapalı durum
 *    kartı sunulur (rol listesi/hedef veri okunmaz).
 *  - Mutasyon alanı yalnız `is_current_user_super_admin` ile açılır; server
 *    action ve migration 131 RPC katmanları AYNI kalır, hiçbir denetim
 *    gevşetilmez (super_admin kategorik ret, self-target ret, son-admin ret).
 *  - Roster satırı "Siz" ile işaretlenir ve hedef listesinden çıkarılır.
 *  - Denetim bağlantısı yalnız gerçek yazma sonrası (`?audit=1`) ve
 *    `audit.view` izni varken gösterilir.
 */
export default async function AdminRolesPage({
  searchParams,
}: {
  searchParams: SearchParams
}) {
  const supabase = await createClient()

  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    redirect("/login")
  }
  const actorUserId = userData.user.id

  // 1) Rota erişim kapısı — (admin) layout ile aynı `questions.view` düzeyi.
  const rpc = supabase.rpc.bind(supabase) as unknown as PermissionRpc
  const { data: canView, error: viewError } = await rpc(
    "teacher_review_admin_has_permission",
    { p_permission_code: "questions.view" },
  )
  if (viewError || canView !== true) {
    redirect("/dashboard")
  }

  // 2) Veri + mutasyon yüzeyi (fail-closed): `users.manage` ve süper
  //    yönetici BİRLİKTE açık olmalı. Değilse yalnız kapalı durum kartı.
  const canManageUsers = await hasUsersManagePermission()
  const superAdmin = await isCurrentUserSuperAdmin()
  const showManagementSurface =
    canManageUsers && superAdmin.status === "ok" && superAdmin.isSuperAdmin

  if (!showManagementSurface) {
    // Roster, katalog, kullanıcı araması ve etiketler HİÇ okunmaz;
    // rol listesi / hedef kullanıcı verisi / mutasyon kontrolü render edilmez.
    return (
      <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
        <div className="mx-auto max-w-5xl">
          <RolesHeader />
          <RolesClosedState />
        </div>
      </main>
    )
  }

  const params = await searchParams
  const flashOk = firstParam(params.ok)
  const flashError = firstParam(params.error)
  const auditTarget = parseAuditEntityId(firstParam(params.target) || undefined)
  const auditRequested = firstParam(params.audit) === "1"

  // 3) Salt-okunur veriler (yalnız yönetim yüzeyi açıkken).
  const [rosterResult, catalogResult] = await Promise.all([
    listRoleAssignments(),
    listActiveRoles(),
  ])

  const searchQuery = firstParam(params.q).trim() || undefined
  const searchResult = await listUsers({ query: searchQuery, sort: "newest" }, 1)

  // 4) Etiketler (öğrenci takma adları) — yalnız ilgili kimlikler.
  const rosterIds = rosterResult.items.map((entry) => entry.userId)
  const searchIds = searchResult.items.map((user) => user.id)
  const labelIds = Array.from(new Set([...rosterIds, ...searchIds]))
  const labels = await resolveUserNicknames(labelIds)
  const labelsOk = labels.status === "ok"

  // 5) Sunum türetmeleri (actor her zaman hedef listesinden çıkarılır).
  const view = buildRoleManagementView({
    roster: rosterResult.items,
    searchResults: searchResult.items.map((user) => ({
      id: user.id,
      nickname: user.nickname,
    })),
    labels: labelsOk ? labels.labels : {},
    actorUserId,
  })

  const assignableRoles = assignableRolesFromCatalog(catalogResult.items)
  const panelRoles = assignableRoles.map((entry) => ({
    roleCode: entry.roleCode,
    name: entry.name || entry.roleCode,
  }))
  const panelTargets: PanelTarget[] = view.targetOptions.map((option) => ({
    userId: option.userId,
    label: option.label,
    isRosterAdmin: option.isRosterAdmin,
    assignedRoleCodes: option.assignedRoleCodes,
  }))

  // 6) Denetim bağlantısı görünürlüğü — yalnız gerçek yazma + izin.
  let showAuditLink = false
  if (flashOk.length > 0 && auditTarget && auditRequested) {
    showAuditLink = await hasAuditViewPermission()
  }

  const showSearchSummary = searchResult.status === "ok"

  return (
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-5xl">
        <RolesHeader />

        {flashOk && (
          <div
            role="status"
            className="mb-6 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900"
          >
            <p className="font-semibold">{flashOk}</p>
            {showAuditLink && (
              <p className="mt-1">
                {M.auditLinkHint}{" "}
                <Link
                  href={`/admin/audit?entity=${auditTarget}`}
                  className="font-medium underline underline-offset-2"
                >
                  {M.auditLinkLabel}
                </Link>
              </p>
            )}
          </div>
        )}
        {flashError && (
          <div
            role="alert"
            className="mb-6 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-medium text-amber-900"
          >
            {flashError}
          </div>
        )}

        <section
          aria-labelledby="roster-heading"
          className="mb-6 rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6"
        >
          <h2 id="roster-heading" className="text-lg font-semibold text-gray-900">
            {M.rosterTitle}
          </h2>
          <p className="mt-1 text-sm text-gray-600">{M.readOnlyNotice}</p>

          {rosterResult.status === "error" ? (
            <p role="alert" className="mt-4 text-gray-600">
              {M.rosterListError}
            </p>
          ) : view.admins.length === 0 ? (
            <p className="mt-4 text-gray-600">{M.rosterEmpty}</p>
          ) : (
            <ul className="mt-4 divide-y divide-gray-200">
              {view.admins.map((admin) => (
                <li key={admin.userId} className="py-3">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="font-semibold text-gray-900">
                        {admin.label}
                        {admin.isSelf && (
                          <span className="ml-2 rounded-full bg-gray-900 px-2 py-0.5 text-xs font-medium text-white">
                            {M.selfLabel}
                          </span>
                        )}
                      </p>
                      <p className="mt-0.5 break-all text-xs text-gray-500">
                        {admin.userId}
                        {!labelsOk && ` · ${M.nicknameLoadError}`}
                      </p>
                    </div>
                    <RoleChip admin={admin} />
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>

        {catalogResult.status === "error" ? (
          <section className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6">
            <h2 className="text-lg font-semibold text-gray-900">
              {M.mutationOpenHeading}
            </h2>
            <p role="alert" className="mt-2 text-gray-600">
              {M.catalogError}
            </p>
          </section>
        ) : (
          <>
            <form
              method="get"
              className="mb-4 flex flex-wrap items-end gap-3 rounded-2xl border border-gray-200 bg-white p-4 shadow-sm"
            >
              <label className="block flex-1 min-w-52">
                <span className="text-sm font-medium text-gray-700">
                  {M.searchLabel}
                </span>
                <input
                  name="q"
                  defaultValue={searchQuery ?? ""}
                  className="mt-1 w-full rounded-xl border border-gray-300 px-3 py-2 text-gray-900 outline-none focus:border-gray-500"
                />
              </label>
              <button
                type="submit"
                className="rounded-xl bg-gray-900 px-5 py-2.5 font-semibold text-white hover:bg-gray-700"
              >
                {M.searchAction}
              </button>
            </form>

            {searchResult.status === "error" ? (
              <p
                role="alert"
                className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
              >
                {M.searchError}
              </p>
            ) : showSearchSummary && searchQuery ? (
              <p
                role="status"
                className="mb-4 rounded-xl bg-white px-4 py-2 text-sm text-gray-600 shadow-sm"
              >
                {searchResult.items.length === 0
                  ? M.searchEmpty
                  : M.searchSummary.replace(
                      "{count}",
                      String(searchResult.total),
                    )}
              </p>
            ) : null}

            <RoleManagementPanel targets={panelTargets} roles={panelRoles} />
          </>
        )}
      </div>
    </main>
  )
}