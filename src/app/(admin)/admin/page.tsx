import Link from "next/link"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  loadDashboardMetrics,
} from "@/lib/admin/admin-dashboard"
import {
  ADMIN_DASHBOARD_MESSAGES,
  ADMIN_NAV_ITEMS,
} from "@/lib/admin/admin-panel-messages"
import { countUsers } from "@/lib/admin/admin-users"

type PermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

export default async function AdminDashboardPage() {
  const supabase = await createClient()

  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    redirect("/login")
  }

  const rpc = supabase.rpc.bind(supabase) as unknown as PermissionRpc
  const { data: canView, error: permissionError } = await rpc(
    "teacher_review_admin_has_permission",
    { p_permission_code: "questions.view" },
  )

  if (permissionError || canView !== true) {
    redirect("/dashboard")
  }

  const [metrics, userCount] = await Promise.all([
    loadDashboardMetrics(),
    countUsers(),
  ])

  return (
    <main className="min-h-screen bg-gray-50 p-4 sm:p-8">
      <div className="mx-auto max-w-5xl">
        <div className="mb-6">
          <h1 className="text-3xl font-bold text-gray-900">
            {ADMIN_DASHBOARD_MESSAGES.title}
          </h1>
          <p className="mt-2 text-gray-600">
            {ADMIN_DASHBOARD_MESSAGES.subtitle}
          </p>
        </div>

        <section
          aria-label="Özet metrikler"
          className="mb-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4"
        >
          <MetricCard
            label={ADMIN_DASHBOARD_MESSAGES.publishedQuestions}
            value={metrics.published.value}
            hint={ADMIN_DASHBOARD_MESSAGES.publishedQuestionsHint}
            breakdown={metrics.publishedByExamTrack.breakdown}
          />
          <MetricCard
            label={ADMIN_DASHBOARD_MESSAGES.stagingQuestions}
            value={metrics.staging.value}
          />
          <MetricCard
            label={ADMIN_DASHBOARD_MESSAGES.reviewQueue}
            value={metrics.reviewQueue.value}
          />

          <Link
            href="/admin/users"
            className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm hover:bg-gray-50"
          >
            <h2 className="text-sm font-semibold text-gray-500 uppercase">
              {ADMIN_DASHBOARD_MESSAGES.usersCount}
            </h2>
            {userCount === null ? (
              <p className="mt-2 text-sm text-amber-800">
                {ADMIN_DASHBOARD_MESSAGES.metricUnavailable}
              </p>
            ) : (
              <p className="mt-1 text-3xl font-bold text-gray-900">
                {userCount.toLocaleString("tr-TR")}
              </p>
            )}
          </Link>
        </section>

        <section aria-label="Bölümler" className="rounded-2xl border border-gray-200 bg-white shadow-sm">
          <div className="border-b border-gray-200 bg-gray-50 px-6 py-4">
            <h2 className="font-semibold text-gray-900">
              {ADMIN_DASHBOARD_MESSAGES.navTitle}
            </h2>
          </div>
          <ul className="divide-y divide-gray-200">
            {ADMIN_NAV_ITEMS.map((item) => (
              <li key={item.href}>
                <Link
                  href={item.href}
                  className="flex items-center justify-between gap-4 px-6 py-4 hover:bg-gray-50"
                >
                  <span>
                    <span className="block font-semibold text-gray-900">
                      {item.title}
                    </span>
                    <span className="mt-0.5 block text-sm text-gray-600">
                      {item.description}
                    </span>
                  </span>
                  <span aria-hidden="true" className="text-gray-400">
                    →
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </main>
  )
}

function MetricCard({
  label,
  value,
  hint,
  breakdown,
}: {
  label: string
  value: number | null
  hint?: string
  breakdown?: Record<string, number>
}) {
  if (value === null) {
    return (
      <div className="rounded-2xl border border-amber-200 bg-amber-50 p-5 shadow-sm">
        <h2 className="text-sm font-semibold text-gray-500 uppercase">
          {label}
        </h2>
        <p className="mt-2 text-sm text-amber-800">
          {ADMIN_DASHBOARD_MESSAGES.metricUnavailable}
        </p>
      </div>
    )
  }

  return (
    <div className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
      <h2 className="text-sm font-semibold text-gray-500 uppercase">
        {label}
      </h2>
      <p className="mt-1 text-3xl font-bold text-gray-900">
        {value.toLocaleString("tr-TR")}
      </p>
      {breakdown && Object.keys(breakdown).length > 0 && (
        <dl className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm text-gray-600">
          {Object.entries(breakdown).map(([key, count]) => (
            <div key={key} className="flex items-center gap-1">
              <dt className="text-gray-500">{key}</dt>
              <dd className="font-semibold text-gray-900">
                {count.toLocaleString("tr-TR")}
              </dd>
            </div>
          ))}
        </dl>
      )}
      {hint && <p className="mt-2 text-xs text-gray-400">{hint}</p>}
    </div>
  )
}
