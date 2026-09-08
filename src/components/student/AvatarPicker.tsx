"use client"

import { useState, useTransition } from "react"

import { Button } from "@/components/ui/Button"

import type { AvatarOption } from "@/lib/profile/types"

/**
 * Avatar seçici (Faz 10).
 *
 * - Yalnız sunucudan gelen onaylı katalog seçenekleri listelenir.
 * - İstemci yalnız seçilen karakterin kodunu gönderir; dış URL,
 *   dosya yolu, SVG veya base64 gönderilemez.
 * - Seçenekler radyo düğmeleridir: klavye ile gezinilir, seçili
 *   durum yalnız renkle değil metinle de anlatılır.
 * - Kaydetme sırasında buton kilitlenir; çift gönderim engellenir.
 */
export default function AvatarPicker({
  options,
  currentCode,
  action,
}: {
  options: AvatarOption[]
  currentCode: string | null
  action: (
    rawCode: string
  ) => Promise<{ ok: boolean; message?: string; data?: unknown }>
}) {
  const [pending, startTransition] = useTransition()
  const [selected, setSelected] = useState(currentCode ?? "")
  const [message, setMessage] = useState<{
    tone: "success" | "error"
    text: string
  } | null>(null)

  function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (pending || selected === "") return

    setMessage(null)

    startTransition(async () => {
      const result = await action(selected)

      if (result.ok) {
        const data = result.data as { name?: string } | undefined
        setMessage({
          tone: "success",
          text: `${data?.name ?? "Avatar"} artık karakterin.`,
        })
      } else {
        setMessage({
          tone: "error",
          text: result.message ?? "Avatar seçilemedi. Lütfen tekrar dene.",
        })
      }
    })
  }

  return (
    <form onSubmit={handleSubmit}>
      <fieldset className="mt-2" disabled={pending}>
        <legend className="text-sm font-medium text-ink">
          Karakter seç
        </legend>

        <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
          {options.map((option) => {
            const isSelected = selected === option.code
            const optionId = `avatar-option-${option.code}`

            return (
              <label
                key={option.code}
                htmlFor={optionId}
                className={`flex min-h-11 cursor-pointer items-start gap-3 rounded-xl border p-3 transition focus-within:outline focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-teal-700 ${
                  isSelected
                    ? "border-teal-700 bg-teal-50"
                    : "border-border bg-surface hover:bg-surface-muted"
                }`}
              >
                <input
                  id={optionId}
                  type="radio"
                  name="avatar_code"
                  value={option.code}
                  checked={isSelected}
                  onChange={() => setSelected(option.code)}
                  className="mt-1 h-4 w-4 accent-teal-700"
                />

                <span className="min-w-0">
                  <span className="block text-sm font-semibold text-ink">
                    {option.name}
                    {isSelected && (
                      <span className="ml-2 text-xs font-medium text-teal-700">
                        (Seçili)
                      </span>
                    )}
                  </span>

                  {option.description && (
                    <span className="mt-0.5 block text-xs text-ink-muted">
                      {option.description}
                    </span>
                  )}
                </span>
              </label>
            )
          })}
        </div>
      </fieldset>

      <div className="mt-4">
        <Button type="submit" loading={pending} disabled={selected === ""}>
          Bu karakteri seç
        </Button>
      </div>

      <div aria-live="polite" className="mt-3 min-h-6">
        {message && (
          <p
            role="status"
            className={
              message.tone === "success"
                ? "text-sm font-medium text-success-700"
                : "text-sm font-medium text-danger-700"
            }
          >
            {message.text}
          </p>
        )}
      </div>
    </form>
  )
}
