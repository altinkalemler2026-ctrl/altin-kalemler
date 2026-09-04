import { Alert } from "@/components/ui/Alert"
import { EmptyState } from "@/components/ui/EmptyState"

export const metadata = {
  title: "Lig | Altın Kalemler",
}

export default function LeaguePage() {
  return (
    <main className="mx-auto w-full max-w-5xl p-6">
      <h1 className="text-2xl font-bold text-ink">Lig</h1>

      <p className="mt-2 text-ink-muted">
        Aynı sınıf düzeyindeki öğrencilerle yapılacak lig maçları ve
        sıralamalar bu sayfada yer alacak.
      </p>

      <div className="mt-6">
        <EmptyState
          title="Ligler yakında"
          description="Lig bölümü şu anda pasif. Hazır olduğunda burada göreceksin."
        />
      </div>

      <div className="mt-4">
        <Alert variant="info" role="status">
          Lig özelliği hazırlanıyor; bu bölüm şu anda kullanılamaz.
        </Alert>
      </div>
    </main>
  )
}
