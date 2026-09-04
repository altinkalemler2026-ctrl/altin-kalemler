"use client"

import { FormEvent, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"

import { Alert } from "@/components/ui/Alert"
import { Button } from "@/components/ui/Button"
import { Input } from "@/components/ui/Input"
import { Card } from "@/components/ui/Card"
import { createClient } from "@/lib/supabase/client"

export default function LoginPage() {
  const router = useRouter()
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [error, setError] = useState("")
  const [loading, setLoading] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError("")

    if (!email || !password) {
      setError("E-posta ve şifre alanlarını doldurun.")
      return
    }

    setLoading(true)

    const supabase = createClient()

    const { error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (signInError) {
      setError("E-posta veya şifre hatalı.")
      setLoading(false)
      return
    }

    router.push("/dashboard")
    router.refresh()
  }

  return (
    <Card className="w-full max-w-md" padding="lg">
      <div className="mb-6 text-center">
        <h1 className="text-2xl font-bold text-ink">Altın Kalemler</h1>

        <p className="mt-2 text-sm text-ink-muted">Hesabına giriş yap</p>
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

        <Input
          label="Şifre"
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          placeholder="Şifren"
        />

        <div className="text-right">
          <Link
            href="/forgot-password"
            className="text-sm font-medium text-ink underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
          >
            Şifremi unuttum
          </Link>
        </div>

        {error && <Alert variant="danger">{error}</Alert>}

        <Button
          type="submit"
          size="lg"
          loading={loading}
          className="w-full"
        >
          {loading ? "Giriş yapılıyor..." : "Giriş Yap"}
        </Button>
      </form>

      <p className="mt-6 text-center text-sm text-ink-muted">
        Henüz hesabın yok mu?{" "}
        <Link
          href="/register"
          className="font-semibold text-ink underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
        >
          Kayıt Ol
        </Link>
      </p>
    </Card>
  )
}
