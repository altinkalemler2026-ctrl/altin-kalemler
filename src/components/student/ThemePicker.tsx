"use client"

import { useTheme } from "@/lib/ui/theme-context"
import { THEMES } from "@/lib/ui/theme"
import type { Theme } from "@/lib/ui/theme"

const THEME_META: Record<Theme, { label: string; description: string; dot: string }> = {
  arena: {
    label: "Altın Arena",
    description: "Lacivert zemin, ölçülü altın vurgu.",
    dot: "bg-[#0a122a]",
  },
  atolye: {
    label: "Renkli Atölye",
    description: "Krem zemin, beyaz kartlar, canlı renkler.",
    dot: "bg-[#faf9f5]",
  },
}

/**
 * Tema secici (Faz 12).
 *
 * - Radyo dugmeleriyle klavye erisilebilirdir; secili durum yalniz
 *   renkle degil metinle de anlatilir ("(Seçili)").
 * - Tema degisimi localStorage'a yazilir; server'a gonderilmez.
 * - Yalniz onayli iki tema sunulur; yeni tema eklenmedikce liste
 *   sabittir.
 */
export default function ThemePicker() {
  const { theme, setTheme } = useTheme()

  return (
    <fieldset className="mt-2">
      <legend className="text-sm font-medium text-ink">Tema seç</legend>

      <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
        {THEMES.map((t) => {
          const meta = THEME_META[t]
          const isSelected = theme === t
          const optionId = `theme-option-${t}`

          return (
            <label
              key={t}
              htmlFor={optionId}
              className={`flex min-h-11 cursor-pointer items-start gap-3 rounded-xl border p-3 transition focus-within:outline focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-teal-700 ${
                isSelected
                  ? "border-teal-700 bg-teal-100"
                  : "border-border bg-surface hover:bg-surface-muted"
              }`}
            >
              <input
                id={optionId}
                type="radio"
                name="theme"
                value={t}
                checked={isSelected}
                onChange={() => setTheme(t)}
                className="mt-1 h-4 w-4 accent-teal-700"
              />

              <span className="min-w-0">
                <span className="flex items-center gap-2">
                  <span
                    aria-hidden="true"
                    className={`h-4 w-4 shrink-0 rounded-full border border-border ${meta.dot}`}
                  />
                  <span className="block text-sm font-semibold text-ink">
                    {meta.label}
                    {isSelected && (
                      <span className="ml-2 text-xs font-medium text-teal-700">
                        (Seçili)
                      </span>
                    )}
                  </span>
                </span>

                <span className="mt-0.5 block text-xs text-ink-muted">
                  {meta.description}
                </span>
              </span>
            </label>
          )
        })}
      </div>
    </fieldset>
  )
}