"use client"

import { FormEvent, useState } from "react"
import Link from "next/link"

import { Alert } from "@/components/ui/Alert"
import { Button } from "@/components/ui/Button"
import { Input } from "@/components/ui/Input"
import { Card } from "@/components/ui/Card"
import { createClient } from "@/lib/supabase/client"

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("")
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")
  const [loading, setLoading] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()

    setError("")
    setSuccess("")

    const cleanEmail = email.trim()

    if (!cleanEmail) {
      setError("Lütfen e-posta adresinizi girin.")
      return
    }

    setLoading(true)

    const supabase = createClient()

    const { error: resetError } =
      await supabase.auth.resetPasswordForEmail(cleanEmail, {
        redirectTo: `${window.location.origin}/auth/callback?next=/reset-password`,
      })

    if (resetError) {
      setError(
        "Şifre sıfırlama bağlantısı gönderilemedi. Lütfen tekrar deneyin."
      )
      setLoading(false)
      return
    }

    setSuccess(
      "Eğer bu e-posta adresiyle kayıtlı bir hesap varsa şifre sıfırlama bağlantısı gönderildi."
    )

    setLoading(false)
  }

  return (
    <Card className="w-full max-w-md" padding="lg">
      <div className="mb-6 text-center">
        <h1 className="text-2xl font-bold text-ink">Şifremi Unuttum</h1>

        <p className="mt-2 text-sm text-ink-muted">
          E-posta adresine şifre sıfırlama bağlantısı gönderelim.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-5">
        <Input
          label="E-posta"
          type="email"
          autoComplete="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          placeholder="ornek@email.com"
        />

        {error && <Alert variant="danger">{error}</Alert>}

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
          {loading ? "Gönderiliyor..." : "Sıfırlama Bağlantısı Gönder"}
        </Button>
      </form>

      <p className="mt-6 text-center text-sm text-ink-muted">
        Şifreni hatırladın mı?{" "}
        <Link
          href="/login"
          className="font-semibold text-ink underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
        >
          Giriş Yap
        </Link>
      </p>
    </Card>
  )
}
