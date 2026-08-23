import { redirect } from "next/navigation"

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

  return <div className="flex min-h-full flex-col">{children}</div>
}
