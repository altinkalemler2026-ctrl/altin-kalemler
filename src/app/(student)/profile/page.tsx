import { redirect } from "next/navigation"

import { Card } from "@/components/ui/Card"
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
        <Card>
          <p role="alert" className="font-medium text-danger-700">
            Profil bilgilerin şu anda görüntülenemiyor.
          </p>
        </Card>
      </main>
    )
  }

  return (
    <main className="mx-auto w-full max-w-3xl p-6">
      <h1 className="text-2xl font-bold text-ink">Profilim</h1>

      <Card className="mt-6">
        <dl className="space-y-4">
          <div className="rounded-xl border border-border p-4">
            <dt className="text-sm font-medium text-ink-muted">Takma ad</dt>
            <dd className="mt-1 text-lg font-semibold text-ink">
              {profile.nickname}
            </dd>
          </div>

          <div className="rounded-xl border border-border p-4">
            <dt className="text-sm font-medium text-ink-muted">Sınıf</dt>
            <dd className="mt-1 text-lg font-semibold text-ink">
              {profile.grade_level}. Sınıf
            </dd>
          </div>
        </dl>

        <p className="mt-6 text-sm text-ink-muted">
          Sınıfın, kendi eğitim içeriğini belirler. Profil ekranından sınıf
          değiştirilemez.
        </p>
      </Card>
    </main>
  )
}
