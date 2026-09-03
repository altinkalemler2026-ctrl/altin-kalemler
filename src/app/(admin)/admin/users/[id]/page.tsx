import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import { getUserDetail } from "@/lib/admin/admin-users"
import { ADMIN_USERS_MESSAGES as M } from "@/lib/admin/admin-panel-messages"

type PermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

type Params = Promise<{ id: string }>

export default async function AdminUserDetailPage({
  params,
}: {
  params: Params
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

  const { id } = await params
  const user = await getUserDetail(id)

  if (!user) {
    return (
      <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
        <div className="mx-auto max-w-3xl">
          <Link
            href="/admin/users"
            className="mb-4 inline-block rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
          >
            {M.backToList}
          </Link>
          <p className="rounded-2xl border border-gray-200 bg-white px-6 py-10 text-gray-600">
            {M.notFound}
          </p>
        </div>
      </main>
    )
  }

  return (
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-3xl">
        <Link
          href="/admin/users"
          className="mb-4 inline-block rounded-xl border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 hover:bg-gray-100"
        >
          {M.backToList}
        </Link>

        <div className="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
          <div className="border-b border-gray-200 bg-gray-50 px-6 py-4">
            <h1 className="text-2xl font-bold text-gray-900">{M.detailTitle}</h1>
            <p className="mt-1 font-semibold text-gray-700">{user.nickname}</p>
          </div>

          <div className="border-t border-gray-200 bg-gray-50 px-6 py-5">
            <h2 className="mb-3 text-sm font-semibold text-gray-500 uppercase">
              {M.profileFields}
            </h2>
            <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
              <MetadataItem label={M.nickname} value={user.nickname || "-"} />
              <MetadataItem
                label={M.gradeLevel}
                value={`${user.grade_level}. ${M.classYears}`}
              />
              <MetadataItem
                label={M.created}
                value={formatDate(user.created_at)}
              />
              <MetadataItem
                label={M.lastUpdated}
                value={formatDate(user.updated_at)}
              />
              <MetadataItem
                label={M.points}
                value={
                  user.total_points !== null
                    ? user.total_points.toLocaleString("tr-TR")
                    : M.notSet
                }
              />
              <MetadataItem
                label={M.monthlyPoints}
                value={
                  user.monthly_points !== null
                    ? user.monthly_points.toLocaleString("tr-TR")
                    : M.notSet
                }
              />
            </dl>
          </div>

          <div className="border-t border-gray-200 bg-gray-50 px-6 py-5">
            <h2 className="mb-3 text-sm font-semibold text-gray-500 uppercase">
              {M.leagueInfo}
            </h2>
            <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
              <MetadataItem
                label={M.league}
                value={user.league_code ?? M.noLeague}
              />
              <MetadataItem
                label={M.character}
                value={user.character_key ?? M.noCharacter}
              />
              <MetadataItem
                label={M.avatar}
                value={user.avatar_key ?? M.noAvatar}
              />
            </dl>
          </div>
        </div>
      </div>
    </main>
  )
}

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

function MetadataItem({
  label,
  value,
}: {
  label: string
  value: string
}) {
  return (
    <div>
      <dt className="text-gray-500">{label}</dt>
      <dd className="font-medium text-gray-900">{value}</dd>
    </div>
  )
}
