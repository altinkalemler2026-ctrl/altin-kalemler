"use client"

import { FormEvent, useState } from "react"
import Link from "next/link"
import { createClient } from "@/lib/supabase/client"

export default function ResetPasswordPage() {
  const [password, setPassword] = useState("")
  const [passwordAgain, setPasswordAgain] = useState("")
  const [error, setError] = useState("")
  const [success, setSuccess] = useState("")
  const [loading, setLoading] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()

    setError("")
    setSuccess("")

    if (!password || !passwordAgain) {
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

    setLoading(true)

    const supabase = createClient()

    const { error: updateError } = await supabase.auth.updateUser({
      password,
    })

    if (updateError) {
      setError(
        "Şifre güncellenemedi. Sıfırlama bağlantısını yeniden kullanmayı deneyin."
      )
      setLoading(false)
      return
    }

    setSuccess("Şifreniz başarıyla güncellendi.")
    setPassword("")
    setPasswordAgain("")
    setLoading(false)
  }

  return (
    <main className="w-full max-w-md">
      <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm sm:p-8">
        <div className="mb-6 text-center">
          <h1 className="text-2xl font-bold text-gray-900">
            Yeni Şifre Belirle
          </h1>

          <p className="mt-2 text-sm text-gray-600">
            Hesabınız için yeni bir şifre oluşturun.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <label
              htmlFor="password"
              className="mb-1.5 block text-sm font-medium text-gray-700"
            >
              Yeni şifre
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
              Yeni şifre tekrar
            </label>

            <input
              id="passwordAgain"
              type="password"
              autoComplete="new-password"
              value={passwordAgain}
              onChange={(event) => setPasswordAgain(event.target.value)}
              className="w-full rounded-xl border border-gray-300 px-4 py-3 text-gray-900 outline-none transition focus:border-gray-500"
              placeholder="Şifrenizi tekrar yazın"
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
            {loading ? "Güncelleniyor..." : "Şifreyi Güncelle"}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-gray-600">
          Giriş sayfasına dönmek için{" "}
          <Link
            href="/login"
            className="font-semibold text-gray-900 underline-offset-4 hover:underline"
          >
            buraya tıklayın
          </Link>
        </p>
      </div>
    </main>
  )
}