/** /ilerleme sunucu verisi yüklenirken gösterilen iskelet durum. */
export default function ProgressLoading() {
  return (
    <main className="mx-auto w-full max-w-3xl p-4 sm:p-6">
      <section aria-labelledby="ilerleme-title" aria-busy="true">
        <h1 id="ilerleme-title" className="text-3xl font-bold text-ink">
          İlerlemen
        </h1>
        <p className="mt-2 text-ink-muted">İlerlemen yükleniyor…</p>
        <div className="mt-6 space-y-3" aria-hidden="true">
          <div className="h-24 animate-pulse rounded-2xl bg-surface-muted" />
          <div className="h-40 animate-pulse rounded-2xl bg-surface-muted" />
          <div className="h-40 animate-pulse rounded-2xl bg-surface-muted" />
        </div>
        <p role="status" aria-live="polite" className="sr-only">
          İlerlemen yükleniyor.
        </p>
      </section>
    </main>
  )
}
