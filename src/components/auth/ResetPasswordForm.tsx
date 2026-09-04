"use client"

import { FormEvent, useState } from "react"
import { useRouter } from "next/navigation"

import { Alert } from "@/components/ui/Alert"
import { Button } from "@/components/ui/Button"
import { Card } from "@/components/ui/Card"
import { Input } from "@/components/ui/Input"
import { createClient } from "@/lib/supabase/client"

export default function ResetPasswordForm() {
  const router = useRouter()
  const [password, setPassword] = useState("")
  const [passwordAgain, setPasswordAgain] = useState("")
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")
  const [loading, setLoading] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()

    setError("")
    setSuccess("")

    if (password.length < 8) {
      setError("Şifre en az 8 karakter olmalıdır.")
      return
    }

    if (password !== passwordAgain) {
      setError("Şifreler birbiriyle aynı değil.")
      return
    }

    setLoading(true)

    const supabase = createClient()

    const { error: updateError } = await supabase.auth.updateUser({
      password,
    })

    if (updateError) {
      setError(
        "Şifre güncellenemedi. Sıfırlama bağlantısı süresi dolmuş olabilir. Yeni bir bağlantı isteyin."
      )
      setLoading(false)
      return
    }

    setSuccess("Şifren güncellendi. Yeni şifrenle giriş yapabilirsin.")

    await supabase.auth.signOut()

    setTimeout(() => {
      router.push("/login")
      router.refresh()
    }, 1200)
  }

  return (
    <Card className="w-full max-w-md" padding="lg">
      <div className="mb-6 text-center">
        <h1 className="text-2xl font-bold text-ink">Şifre Yenile</h1>

        <p className="mt-2 text-sm text-ink-muted">
          Hesabın için yeni bir şifre belirle.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-5">
        <Input
          label="Yeni şifre"
          type="password"
          autoComplete="new-password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          placeholder="En az 8 karakter"
          required
          minLength={8}
        />

        <Input
          label="Yeni şifre tekrar"
          type="password"
          autoComplete="new-password"
          value={passwordAgain}
          onChange={(event) => setPasswordAgain(event.target.value)}
          placeholder="Şifreni tekrar yaz"
          required
          minLength={8}
        />

        {error && (
          <Alert variant="danger">{error}</Alert>
        )}

        {success && (
          <Alert variant="success" role="status">
            {success}
          </Alert>
        )}

        <Button
          type="submit"
          size="lg"
          loading={loading}
          className="w-full"
        >
          {loading ? "Güncelleniyor..." : "Şifreyi Güncelle"}
        </Button>
      </form>
    </Card>
  )
}
