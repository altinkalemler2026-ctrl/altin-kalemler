export const metadata = {
  title: "Lig | Altın Kalemler",
}

export default function LeaguePage() {
  return (
    <main className="mx-auto w-full max-w-5xl p-6">
      <section className="rounded-3xl border border-gray-200 bg-white p-6 shadow-sm sm:p-8">
        <h1 className="text-2xl font-bold text-gray-900">Lig</h1>

        <p className="mt-2 text-gray-600">
          Aynı sınıf düzeyindeki öğrencilerle yapılacak lig maçları ve
          sıralamalar bu sayfada yer alacak.
        </p>

        <p
          role="status"
          aria-live="polite"
          className="mt-6 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm font-medium text-amber-900"
        >
          Ligler yakında — şu anda bu bölüm pasif.
        </p>
      </section>
    </main>
  )
}
