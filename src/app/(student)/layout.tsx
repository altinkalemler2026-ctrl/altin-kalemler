import { redirect } from "next/navigation"

import StudentNav from "@/components/student/StudentNav"
import { ThemeProvider } from "@/lib/ui/theme-context"
import { createClient } from "@/lib/supabase/server"

/**
 * Öğrenci alanı merkezî oturum koruması.
 *
 * Bu grup altındaki her sayfa (dashboard, training, ...) oturum
 * doğrulamasından geçer; oturum yoksa /login'e yönlendirilir.
 * Mevcut sayfa içi kontroller zararsız biçimde yerinde kalır.
 */
export default async function StudentLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect("/login")
  }

  const { data: profile } = await supabase
    .from("student_profiles")
    .select("nickname")
    .eq("id", user.id)
    .single()

  async function logout() {
    "use server"

    const supabase = await createClient()

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (user) {
      await supabase.auth.signOut()
    }

    redirect("/login")
  }

  return (
    <ThemeProvider>
      <div className="flex min-h-full flex-col">
        <StudentNav
          nickname={profile?.nickname ?? "öğrenci"}
          logout={logout}
        />

        <div className="flex-1 pb-20 sm:pb-0">{children}</div>
      </div>
    </ThemeProvider>
  )
}
