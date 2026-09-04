import { redirect } from "next/navigation"

import { createClient } from "@/lib/supabase/server"
import ResetPasswordForm from "@/components/auth/ResetPasswordForm"

export const metadata = {
  title: "Şifre Yenile | Altın Kalemler",
}

export default async function ResetPasswordPage() {
  const supabase = await createClient()

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser()

  if (userError || !user) {
    redirect("/forgot-password")
  }

  return <ResetPasswordForm />
}
