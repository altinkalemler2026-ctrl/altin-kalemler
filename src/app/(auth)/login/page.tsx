"use client"

import { FormEvent, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"

import { Alert } from "@/components/ui/Alert"
import { Button } from "@/components/ui/Button"
import { Input } from "@/components/ui/Input"
import { Card } from "@/components/ui/Card"
import { createClient } from "@/lib/supabase/client"

/**
 * Giriş sonrası hedef kararı (RC-1 düzeltmesi).
 *
 * Eski davranış: izin RPC'lerinden biri hata (ör. oturumun henüz
 * bağlanmamasından doğan geçici 401) döndüğünde sonuç "izin yok" sayılıp
 * kullanıcı `/dashboard`'a düşüyordu.
 *
 * Yeni sözleşme:
 * - Yalnız kesin `true` "izin var", yalnız kesin `false` "izin yoktur";
 *   hata veya boş veri ASLA yetkisizlik sayılmaz (fail-open yasak).
 * - Belirsiz sonuçta tek kontrollü yeniden deneme yapılır (oturumun
 *   istemciye bağlanması için kısa bekleme).
 * - Yeniden deneme sonrası hâlâ belirsizse NE admin ne öğrenci rotasına
 *   yönlendirme yapılır; kullanıcıya güvenli, ham hata içermeyen Türkçe
 *   bir durum gösterilir.
 */
type PermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

type PermissionResult = Awaited<ReturnType<PermissionRpc>>

type PermissionVerdict = "admin" | "student" | "unverified"

type PermissionClass = "granted" | "denied" | "unavailable"

/** Giriş sonrası yetki doğrulanamadığında gösterilen güvenli durum metni.
 *  Ham RPC hata metni, durum kodu, token/cookie asla UI'a taşınmaz. */
const POST_SIGN_IN_UNVERIFIED_MESSAGE =
  "Giriş sonrası yetki doğrulanamadı. Lütfen tekrar deneyin."

/** Belirsiz sonuç öncesi oturumun bağlanması için bekleme. */
const POST_SIGN_IN_RETRY_DELAY_MS = 200

function classifyPermission(result: PermissionResult): PermissionClass {
  if (result.error !== null) return "unavailable"
  if (result.data === true) return "granted"
  if (result.data === false) return "denied"
  return "unavailable"
}

function evaluatePermissionSet(
  viewResult: PermissionResult,
  aiResult: PermissionResult,
  approveResult: PermissionResult,
): PermissionVerdict {
  const view = classifyPermission(viewResult)
  // `questions.view` bilinmiyorsa admin kararı asla kurulamaz.
  if (view === "unavailable") return "unverified"
  // Doğrulanmış izin yokluğu => öğrenci paneli (kesin `false`).
  if (view === "denied") return "student"

  const ai = classifyPermission(aiResult)
  const approve = classifyPermission(approveResult)
  if (ai === "granted" || approve === "granted") return "admin"
  if (ai === "denied" && approve === "denied") return "student"
  // Kalan durum: gereken izinlerden biri hâlâ doğrulanamadı.
  return "unverified"
}

async function queryPermissionVerdict(
  supabase: ReturnType<typeof createClient>,
): Promise<PermissionVerdict> {
  const rpc = supabase.rpc.bind(supabase) as unknown as PermissionRpc
  const [viewResult, aiResult, approveResult] = await Promise.all([
    rpc("teacher_review_admin_has_permission", {
      p_permission_code: "questions.view",
    }),
    rpc("teacher_review_admin_has_permission", {
      p_permission_code: "ai.manage",
    }),
    rpc("teacher_review_admin_has_permission", {
      p_permission_code: "questions.approve",
    }),
  ])

  return evaluatePermissionSet(viewResult, aiResult, approveResult)
}

/** İlk deneme + en fazla TEK kontrollü yeniden deneme. */
async function resolvePostSignInPath(
  supabase: ReturnType<typeof createClient>,
): Promise<PermissionVerdict> {
  const firstVerdict = await queryPermissionVerdict(supabase)
  if (firstVerdict !== "unverified") return firstVerdict

  await new Promise<void>((resolve) => {
    setTimeout(resolve, POST_SIGN_IN_RETRY_DELAY_MS)
  })

  return queryPermissionVerdict(supabase)
}

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

    const postSignInPath = await resolvePostSignInPath(supabase)

    if (postSignInPath === "admin") {
      router.push("/admin/candidate-batches")
      router.refresh()
      return
    }

    if (postSignInPath === "student") {
      router.push("/dashboard")
      router.refresh()
      return
    }

    // Belirsiz kalıcı hata: fail-open yok (admin rotasına yönlendirme yok),
    // sessiz öğrenci ataması da yok. Kullanıcı güvenli biçimde bilgilendirilir.
    setLoading(false)
    setError(POST_SIGN_IN_UNVERIFIED_MESSAGE)
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
