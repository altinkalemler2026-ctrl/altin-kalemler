import { redirect } from "next/navigation"

import { createClient } from "@/lib/supabase/server"
import MatchmakingQueue from "@/components/student/MatchmakingQueue"

export const metadata = {
  title: "Yarışmalar — Altın Kalemler",
}

export default async function CompetitionPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect("/login")
  }

  const { data: subjects, error } = await supabase
    .from("subjects")
    .select("id, name")
    .eq("is_active", true)
    .order("sort_order", { ascending: true })
    .order("name", { ascending: true })

  if (error || !subjects || subjects.length === 0) {
    return (
      <main className="mx-auto w-full max-w-3xl p-6">
        <div className="rounded-2xl border border-red-200 bg-red-50 p-5 text-red-700">
          Dersler yüklenirken bir sorun oluştu. Lütfen sayfayı yenileyip tekrar
          dene.
        </div>
      </main>
    )
  }

  return (
    <main className="mx-auto w-full max-w-3xl p-6">
      <section className="rounded-3xl border border-gray-200 bg-white p-6 shadow-sm sm:p-8">
        <p className="text-sm font-medium text-gray-500">Altın Kalemler</p>
        <h1 className="mt-2 text-3xl font-bold text-gray-900">Yarışmalar</h1>
        <p className="mt-2 text-gray-600">
          Bir ders seç ve aynı sınıf düzeyinden bir rakiple eşleşmek için
          sıraya katıl. Yarışma beş sorudan oluşur ve puanını sunucu hesaplar.
        </p>

        <div className="mt-6 grid gap-4 sm:grid-cols-2">
          {subjects.map((subject) => (
            <MatchmakingQueue
              key={subject.id}
              subjectId={subject.id}
              subjectName={subject.name}
            />
          ))}
        </div>
      </section>
    </main>
  )
}
