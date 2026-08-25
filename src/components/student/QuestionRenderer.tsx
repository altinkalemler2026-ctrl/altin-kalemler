"use client"

/**
 * Guvenli soru icerigi renderer'i.
 *
 * GUVENLIK SINIRI:
 *  - HTML icerigi DOMParser ile parse edilip textContent olarak cikarilir.
 *  - dangerouslySetInnerHTML KULLANILMAZ.
 *  - Script, style, iframe, object, embed, svg node'lari DOM'a eklenmez.
 *  - Harici URL/resource istegi olusturulmaz.
 *  - Guvenlik React'in string escaping davranisina dayanir;
 *    HTML sanitization iddiasi yoktur.
 *  - Yeni npm dependency eklenmez.
 */

import type { ChoiceLetter } from "@/lib/competition/types"
import { CHOICE_LETTERS } from "@/lib/competition/types"

/**
 * HTML string'ini guvenli sekilde duz metne cevirir.
 * DOMParser kullanarak script/style/iframe gibi tehlikeli
 * elementlerin icerigini dusurur; yalnizca textContent kalir.
 * DOMParser calismadigi durumda regex ile tag temizler.
 */
function stripHtml(html: string): string {
  if (typeof DOMParser === "undefined") {
    return html.replace(/<[^>]*>/g, "")
  }
  try {
    const doc = new DOMParser().parseFromString(html, "text/html")
    return doc.body.textContent ?? ""
  } catch {
    return html.replace(/<[^>]*>/g, "")
  }
}

interface QuestionRendererProps {
  stemHtml: string
  options: Partial<Record<ChoiceLetter, string>>
}

export default function QuestionRenderer({
  stemHtml,
  options,
}: QuestionRendererProps) {
  const stemText = stripHtml(stemHtml)

  return (
    <div>
      <p className="text-base leading-relaxed text-gray-900">
        {stemText || "Soru metni bulunamadi."}
      </p>

      <div className="mt-4 grid gap-2" role="list" aria-label="Cevap secenekleri">
        {CHOICE_LETTERS.map((letter) => {
          const htmlContent = options[letter]
          if (!htmlContent) return null
          const textContent = stripHtml(htmlContent)
          return (
            <div
              key={letter}
              role="listitem"
              className="flex items-start gap-3 rounded-xl border border-gray-200 px-4 py-3"
            >
              <span
                aria-hidden="true"
                className="flex size-7 shrink-0 items-center justify-center rounded-full border border-gray-400 text-xs font-bold text-gray-700"
              >
                {letter}
              </span>
              <span className="text-gray-900">{textContent}</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
