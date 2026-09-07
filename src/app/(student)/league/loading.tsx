import { Skeleton } from "@/components/ui/Skeleton"

export default function LeagueLoading() {
  return (
    <main className="mx-auto w-full max-w-3xl p-6" aria-busy="true">
      <Skeleton lines={1} className="h-9 w-56" />
      <div className="mt-6">
        <Skeleton lines={3} className="rounded-2xl p-6" />
      </div>
      <div className="mt-6 space-y-2">
        <Skeleton lines={6} className="rounded-2xl p-6" />
      </div>
    </main>
  )
}
