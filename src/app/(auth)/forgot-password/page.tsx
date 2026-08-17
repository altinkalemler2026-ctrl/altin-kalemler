"use client"

import { FormEvent, useState } from "react"
import Link from "next/link"
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
        redirectTo: `${window.location.origin}/reset-password`,
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
    <main className="w-full max-w-md">
      <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm sm:p-8">
        <div className="mb-6 text-center">
          <h1 className="text-2xl font-bold text-gray-900">
            Şifremi Unuttum
          </h1>

          <p className="mt-2 text-sm text-gray-600">
            E-posta adresine şifre sıfırlama bağlantısı gönderelim.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-5">
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
            {loading ? "Gönderiliyor..." : "Sıfırlama Bağlantısı Gönder"}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-gray-600">
          Şifreni hatırladın mı?{" "}
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