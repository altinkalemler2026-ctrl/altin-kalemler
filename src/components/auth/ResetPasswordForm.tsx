"use client"

import { FormEvent, useState } from "react"
import { useRouter } from "next/navigation"
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
    <main className="w-full max-w-md">
      <div className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm sm:p-8">
        <div className="mb-6 text-center">
          <h1 className="text-2xl font-bold text-gray-900">Şifre Yenile</h1>

          <p className="mt-2 text-sm text-gray-600">
            Hesabın için yeni bir şifre belirle.
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
              required
              minLength={8}
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
              placeholder="Şifreni tekrar yaz"
              required
              minLength={8}
            />
          </div>

          {error && (
            <div
              role="alert"
              aria-live="assertive"
              className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700"
            >
              {error}
            </div>
          )}

          {success && (
            <div
              role="status"
              aria-live="polite"
              className="rounded-xl bg-green-50 px-4 py-3 text-sm text-green-700"
            >
              {success}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="min-h-11 w-full rounded-xl bg-gray-900 px-4 py-3 font-semibold text-white transition hover:bg-gray-800 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {loading ? "Güncelleniyor..." : "Şifreyi Güncelle"}
          </button>
        </form>
      </div>
    </main>
  )
}
