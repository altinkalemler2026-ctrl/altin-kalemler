import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"

export default async function DashboardPage() {
  const supabase = await createClient()

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser()

  if (userError || !user) {
    redirect("/login")
  }

  const { data: profile, error: profileError } = await supabase
    .from("student_profiles")
    .select("nickname, grade_level")
    .eq("id", user.id)
    .single()

  if (profileError || !profile) {
    return (
      <main className="mx-auto w-full max-w-3xl p-6">
        <div className="rounded-2xl border border-red-200 bg-red-50 p-5 text-red-700">
          Öğrenci profili bulunamadı.
        </div>
      </main>
    )
  }

  async function logout() {
    "use server"

    const supabase = await createClient()
    await supabase.auth.signOut()

    redirect("/login")
  }

  return (
    <main className="mx-auto w-full max-w-5xl p-6">
      <section className="rounded-3xl border border-gray-200 bg-white p-6 shadow-sm sm:p-8">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p className="text-sm font-medium text-gray-500">
              Altın Kalemler
            </p>

            <h1 className="mt-2 text-3xl font-bold text-gray-900">
              Hoş geldin, {profile.nickname}
            </h1>

            <p className="mt-2 text-gray-600">
              {profile.grade_level}. sınıf öğrenci panelindesin.
            </p>
          </div>

          <form action={logout}>
            <button
              type="submit"
              className="rounded-xl border border-gray-300 px-4 py-2 text-sm font-semibold text-gray-700 transition hover:bg-gray-50"
            >
              Çıkış Yap
            </button>
          </form>
        </div>

        <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div className="rounded-2xl border border-gray-200 p-5">
            <h2 className="font-semibold text-gray-900">Konu Çalış</h2>
            <p className="mt-2 text-sm text-gray-600">
              Ders ve konu seçerek soru çöz.
            </p>
          </div>

          <div className="rounded-2xl border border-gray-200 p-5">
            <h2 className="font-semibold text-gray-900">Yarışmalar</h2>
            <p className="mt-2 text-sm text-gray-600">
              Rakiplerle bilgi yarışmalarına katıl.
            </p>
          </div>

          <div className="rounded-2xl border border-gray-200 p-5">
            <h2 className="font-semibold text-gray-900">Başarılarım</h2>
            <p className="mt-2 text-sm text-gray-600">
              Puanlarını ve ilerlemeni takip et.
            </p>
          </div>
        </div>
      </section>
    </main>
  )
}