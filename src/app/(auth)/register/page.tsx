"use client"

import { FormEvent, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
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
    <main className="w-full max-w-md">
      <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm sm:p-8">
        <div className="mb-6 text-center">
          <h1 className="text-2xl font-bold text-gray-900">
            Altın Kalemler
          </h1>

          <p className="mt-2 text-sm text-gray-600">
            Yeni öğrenci hesabı oluştur
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <label
              htmlFor="nickname"
              className="mb-1.5 block text-sm font-medium text-gray-700"
            >
              Kullanıcı adı
            </label>

            <input
              id="nickname"
              type="text"
              autoComplete="nickname"
              value={nickname}
              onChange={(event) => setNickname(event.target.value)}
              className="w-full rounded-xl border border-gray-300 px-4 py-3 text-gray-900 outline-none transition focus:border-gray-500"
              placeholder="Örneğin: altinkalem42"
            />
          </div>

          <div>
            <label
              htmlFor="gradeLevel"
              className="mb-1.5 block text-sm font-medium text-gray-700"
            >
              Sınıf
            </label>

            <select
              id="gradeLevel"
              value={gradeLevel}
              onChange={(event) => setGradeLevel(event.target.value)}
              className="w-full rounded-xl border border-gray-300 bg-white px-4 py-3 text-gray-900 outline-none transition focus:border-gray-500"
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

          <div>
            <label
              htmlFor="email"
              className="mb-1.5 block text-sm font-medium text-gray-700"
            >
              E-posta
            </label>

            <input
              id="email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              className="w-full rounded-xl border border-gray-300 px-4 py-3 text-gray-900 outline-none transition focus:border-gray-500"
              placeholder="ornek@email.com"
            />
          </div>

          <div>
            <label
              htmlFor="password"
              className="mb-1.5 block text-sm font-medium text-gray-700"
            >
              Şifre
            </label>

            <input
              id="password"
              type="password"
              autoComplete="new-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              className="w-full rounded-xl border border-gray-300 px-4 py-3 text-gray-900 outline-none transition focus:border-gray-500"
              placeholder="En az 8 karakter"
            />
          </div>

          <div>
            <label
              htmlFor="passwordAgain"
              className="mb-1.5 block text-sm font-medium text-gray-700"
            >
              Şifre tekrar
            </label>

            <input
              id="passwordAgain"
              type="password"
              autoComplete="new-password"
              value={passwordAgain}
              onChange={(event) => setPasswordAgain(event.target.value)}
              className="w-full rounded-xl border border-gray-300 px-4 py-3 text-gray-900 outline-none transition focus:border-gray-500"
              placeholder="Şifreni tekrar yaz"
            />
          </div>

          {error && (
            <div
              role="alert"
              className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700"
            >
              {error}
            </div>
          )}

          {success && (
            <div
              role="status"
              className="rounded-xl bg-green-50 px-4 py-3 text-sm text-green-700"
            >
              {success}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-xl bg-gray-900 px-4 py-3 font-semibold text-white transition hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {loading ? "Kayıt oluşturuluyor..." : "Kayıt Ol"}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-gray-600">
          Zaten hesabın var mı?{" "}
          <Link
            href="/login"
            className="font-semibold text-gray-900 underline-offset-4 hover:underline"
          >
            Giriş Yap
          </Link>
        </p>
      </div>
    </main>
  )
}