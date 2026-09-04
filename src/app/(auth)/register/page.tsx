"use client"

import { FormEvent, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"

import { Alert } from "@/components/ui/Alert"
import { Button } from "@/components/ui/Button"
import { Input } from "@/components/ui/Input"
import { Card } from "@/components/ui/Card"
import { createClient } from "@/lib/supabase/client"

export default function RegisterPage() {
  const router = useRouter()
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [passwordAgain, setPasswordAgain] = useState("")
  const [nickname, setNickname] = useState("")
  const [gradeLevel, setGradeLevel] = useState("")
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")
  const [loading, setLoading] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()

    setError("")
    setSuccess("")

    const cleanEmail = email.trim()
    const cleanNickname = nickname.trim()
    const grade = Number(gradeLevel)

    if (
      !cleanEmail ||
      !password ||
      !passwordAgain ||
      !cleanNickname ||
      !gradeLevel
    ) {
      setError("Lütfen tüm alanları doldurun.")
      return
    }

    if (password.length < 8) {
      setError("Şifre en az 8 karakter olmalıdır.")
      return
    }

    if (password !== passwordAgain) {
      setError("Şifreler birbiriyle aynı değil.")
      return
    }

    if (!Number.isInteger(grade) || grade < 1 || grade > 12) {
      setError("Lütfen 1 ile 12 arasında geçerli bir sınıf seçin.")
      return
    }

    setLoading(true)

    const supabase = createClient()

    const { data, error: signUpError } = await supabase.auth.signUp({
      email: cleanEmail,
      password,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
        data: {
          nickname: cleanNickname,
          grade_level: grade,
        },
      },
    })

    if (signUpError) {
      setError("Kayıt oluşturulamadı. Bilgilerinizi kontrol edip tekrar deneyin.")
      setLoading(false)
      return
    }

    if (!data.user) {
      setError("Kullanıcı hesabı oluşturulamadı.")
      setLoading(false)
      return
    }

    if (data.session) {
      router.replace("/dashboard")
      return
    }

    setSuccess(
      "Kayıt alındı. E-posta adresinize gelen doğrulama bağlantısını kontrol edin."
    )

    setLoading(false)
  }

  return (
    <Card className="w-full max-w-md" padding="lg">
      <div className="mb-6 text-center">
        <h1 className="text-2xl font-bold text-ink">Altın Kalemler</h1>

        <p className="mt-2 text-sm text-ink-muted">
          Yeni öğrenci hesabı oluştur
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-5">
        <Input
          label="Kullanıcı adı"
          type="text"
          autoComplete="nickname"
          value={nickname}
          onChange={(event) => setNickname(event.target.value)}
          placeholder="Örneğin: altinkalem42"
        />

        <div className="w-full">
          <label
            htmlFor="gradeLevel"
            className="mb-1.5 block text-sm font-medium text-ink"
          >
            Sınıf
          </label>

          <select
            id="gradeLevel"
            value={gradeLevel}
            onChange={(event) => setGradeLevel(event.target.value)}
            className="min-h-11 w-full rounded-xl border border-border bg-surface px-4 py-2.5 text-ink outline-none transition focus:ring-2 focus:ring-teal-600 focus:ring-offset-1"
          >
            <option value="">Sınıfını seç</option>

            {Array.from({ length: 12 }, (_, index) => index + 1).map(
              (grade) => (
                <option key={grade} value={grade}>
                  {grade}. Sınıf
                </option>
              )
            )}
          </select>
        </div>

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
          autoComplete="new-password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          placeholder="En az 8 karakter"
          hint="En az 8 karakter olmalıdır."
        />

        <Input
          label="Şifre tekrar"
          type="password"
          autoComplete="new-password"
          value={passwordAgain}
          onChange={(event) => setPasswordAgain(event.target.value)}
          placeholder="Şifreni tekrar yaz"
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
          {loading ? "Kayıt oluşturuluyor..." : "Kayıt Ol"}
        </Button>
      </form>

      <p className="mt-6 text-center text-sm text-ink-muted">
        Zaten hesabın var mı?{" "}
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
