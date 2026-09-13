"use client"

import { useId, useState, useTransition } from "react"

import { Button } from "@/components/ui/Button"
import { Input } from "@/components/ui/Input"

/**
 * Takma ad düzenleme formu (Faz 10).
 *
 * - Yalnız nickname gönderilir; grade/user_id alanı YOKTUR
 *   (hidden input dahi gönderilmez).
 * - Uzunluk sınırı veritabanı kuralı yoksa uydurulmaz; kural
 *   sunucu veritabanıdır (boş olamaz + benzersiz olmalı).
 * - Kaydetme sırasında buton kilitlenir; çift gönderim engellenir.
 * - Başarısız işlem mevcut takma adı bozmaz (değer formda kalır).
 * - Başarı/hata mesajları aria-live ile duyurulur.
 * - Sınıf notu bu formda YOKTUR; "sınıf değiştirilemez" bilgisi
 *   yalnız profil özetinde bir kez gösterilir.
 */
export default function NicknameForm({
  currentNickname,
  action,
}: {
  currentNickname: string
  action: (
    rawNickname: string
  ) => Promise<{ ok: boolean; message?: string; data?: unknown }>
}) {
  const inputId = useId()
  const [pending, startTransition] = useTransition()
  const [message, setMessage] = useState<{
    tone: "success" | "error"
    text: string
  } | null>(null)
  const [value, setValue] = useState(currentNickname)

  function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (pending) return

    setMessage(null)

    startTransition(async () => {
      const result = await action(value)

      if (result.ok) {
        const data = result.data as { nickname?: string } | undefined
        if (typeof data?.nickname === "string") {
          setValue(data.nickname)
        }
        setMessage({
          tone: "success",
          text: "Takma adın güncellendi.",
        })
      } else {
        setMessage({
          tone: "error",
          text: result.message ?? "Takma ad güncellenemedi.",
        })
      }
    })
  }

  return (
    <form onSubmit={handleSubmit} noValidate>
      <Input
        id={inputId}
        name="nickname"
        label="Takma ad"
        autoComplete="nickname"
        value={value}
        onChange={(event) => setValue(event.target.value)}
        disabled={pending}
      />

      <div className="mt-3">
        <Button type="submit" loading={pending}>
          Kaydet
        </Button>
      </div>

      <div aria-live="polite">
        {message && (
          <p
            role="status"
            className={
              message.tone === "success"
                ? "mt-3 text-sm font-medium text-success-700"
                : "mt-3 text-sm font-medium text-danger-700"
            }
          >
            {message.text}
          </p>
        )}
      </div>
    </form>
  )
}
