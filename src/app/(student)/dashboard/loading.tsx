import { Card } from "@/components/ui/Card"
import { Skeleton } from "@/components/ui/Skeleton"

/** Ana sayfa yükleniyor durumu: gerçek veri gelirken iskelet gösterir. */
export default function DashboardLoading() {
  return (
    <main className="mx-auto w-full max-w-5xl space-y-6 p-6">
      <Card padding="lg">
        <Skeleton lines={1} className="w-40" />
        <Skeleton lines={1} className="mt-3 w-64" />

        <div className="mt-6 grid gap-4 sm:grid-cols-2">
          <Skeleton lines={2} />
          <Skeleton lines={2} />
        </div>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <Skeleton lines={3} />
        </Card>

        <Card>
          <Skeleton lines={3} />
        </Card>
      </div>

      <Card>
        <Skeleton lines={4} />
      </Card>
    </main>
  )
}
