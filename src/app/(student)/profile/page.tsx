import { redirect } from "next/navigation"

import { createClient } from "@/lib/supabase/server"

export const metadata = {
  title: "Profil | Altın Kalemler",
}

export default async function ProfilePage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
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
        <div
          role="alert"
          aria-live="assertive"
          className="rounded-2xl border border-red-200 bg-red-50 p-5 text-red-700"
        >
          Profil bilgilerin şu anda görüntülenemiyor.
        </div>
      </main>
    )
  }

  return (
    <main className="mx-auto w-full max-w-3xl p-6">
      <section className="rounded-3xl border border-gray-200 bg-white p-6 shadow-sm sm:p-8">
        <h1 className="text-2xl font-bold text-gray-900">Profilim</h1>

        <dl className="mt-6 space-y-4">
          <div className="rounded-2xl border border-gray-200 p-4">
            <dt className="text-sm font-medium text-gray-500">Takma ad</dt>
            <dd className="mt-1 text-lg font-semibold text-gray-900">
              {profile.nickname}
            </dd>
          </div>

          <div className="rounded-2xl border border-gray-200 p-4">
            <dt className="text-sm font-medium text-gray-500">Sınıf</dt>
            <dd className="mt-1 text-lg font-semibold text-gray-900">
              {profile.grade_level}. Sınıf
            </dd>
          </div>
        </dl>

        <p className="mt-6 text-sm text-gray-600">
          Sınıfın, kendi eğitim içeriğini belirler. Profil ekranından sınıf
          değiştirilemez.
        </p>
      </section>
    </main>
  )
}
