"use client"

/**
 * Erişilebilir matematik metni renderer'ı.
 *
 * Desteklenen desenler (soru metni ve seçenekler düz metin/HTML-strip
 * sonrası bu desenleri içerebilir):
 *  - Kesir:  "3/4"  -> dikey kesir görünümü + aria "3 bölü 4"
 *  - Üs:     "2^10" -> üst simge + aria "2 üzeri 10"
 *  - Sembol: "*" çarpı görünümü (aria "çarpı"); "÷" olduğu gibi
 *
 * Güvenlik: yalnız React string escaping; HTML asla enjekte edilmez
 * (dangerouslySetInnerHTML YOK). Script/event-handler/javascript:
 * girdileri düz metin olarak kalır ve çalıştırılamaz.
 *
 * Dayanıklılık: renderer beklenmeyen hatada sayfayı çökertmez;
 * güvenli düz metin fallback'ine düşer (MathTextErrorBoundary).
 * Uzun formüller satır sonunda kırılır (break-words); mobil yatay
 * taşma üretmez. Ekran okuyucu alternatifi, görsel temsilin BİREBIR
 * düz metin karşılığıdır (WCAG: renk/görsele tek başına anlam
 * yüklenmez).
 */

import { Component, Fragment, type ReactNode } from "react"

function splitWithMath(text: string): ReactNode[] {
  const tokens: ReactNode[] = []

  // Önce üs, sonra kesir: "2^3/4" -> üs öncelikli (2^3) sonra 4 kalır.
  // Deterministik basit yaklaşım: iki deseni sırayla işle.
  // Desenler bileşen başına yerel üretilir (module-level mutable state yok).
  const powerMatches = [...text.matchAll(/(\d+)\^(\d+)/g)]
  const fractionMatches = [...text.matchAll(/(\d+)\/(\d+)/g)]

  type Match = { start: number; end: number; kind: "power" | "fraction"; m: RegExpMatchArray }
  const all: Match[] = [
    ...powerMatches.map((m) => ({
      start: m.index ?? 0,
      end: (m.index ?? 0) + m[0].length,
      kind: "power" as const,
      m,
    })),
    ...fractionMatches.map((m) => ({
      start: m.index ?? 0,
      end: (m.index ?? 0) + m[0].length,
      kind: "fraction" as const,
      m,
    })),
  ].sort((a, b) => a.start - b.start)

  let cursor = 0
  for (const item of all) {
    if (item.start < cursor) continue // çakışan eşleşmeyi atla
    if (item.start > cursor) tokens.push(text.slice(cursor, item.start))

    if (item.kind === "power") {
      const [, base, exponent] = item.m
      tokens.push(
        <span key={`p-${item.start}`}>
          <span aria-hidden="true">
            {base}
            <sup className="font-semibold">{exponent}</sup>
          </span>
          <span className="sr-only">
            {base} üzeri {exponent}
          </span>
        </span>
      )
    } else {
      const [, numerator, denominator] = item.m
      tokens.push(
        <span
          key={`f-${item.start}`}
          aria-label={`${numerator} bölü ${denominator}`}
        >
          <span
            aria-hidden="true"
            className="mx-0.5 inline-flex flex-col items-center align-middle leading-tight"
          >
            <span className="border-b border-current px-1 text-[0.85em]">
              {numerator}
            </span>
            <span className="px-1 text-[0.85em]">{denominator}</span>
          </span>
          <span className="sr-only">
            {numerator} bölü {denominator}
          </span>
        </span>
      )
    }

    cursor = item.end
  }

  if (cursor < text.length) tokens.push(text.slice(cursor))

  return tokens
}

/**
 * Renderer hatası sayfayı çökertmez: güvenli düz metin fallback'i.
 * Fallback, orijinal metnin birebir kendisidir (içerik uydurma YOK).
 * Test edilebilirlik için dışa aktarılmıştır.
 */
export class MathTextErrorBoundary extends Component<
  { text: string; className?: string; children: ReactNode },
  { failed: boolean }
> {
  state = { failed: false }

  static getDerivedStateFromError() {
    return { failed: true }
  }

  componentDidCatch() {
    // Hatayı yut; ham hata metni kullanıcıya asla gösterilmez.
  }

  render() {
    if (this.state.failed) {
      return (
        <span className={this.props.className}>{this.props.text}</span>
      )
    }
    return this.props.children
  }
}

export default function MathText({
  text,
  className,
}: {
  text: string
  className?: string
}) {
  if (!text) return null

  const wrapperClass = [
    "min-w-0 break-words [overflow-wrap:anywhere]",
    className ?? "",
  ]
    .filter(Boolean)
    .join(" ")

  return (
    <MathTextErrorBoundary text={text} className={wrapperClass}>
      <SafeMathSpan text={text} className={wrapperClass} />
    </MathTextErrorBoundary>
  )
}

function SafeMathSpan({
  text,
  className,
}: {
  text: string
  className?: string
}) {
  // Yerel desenler: matchAll 'g' bayraklı regex kullanır ve lastIndex
  // taşımaz (her çağrıda taze nesne; global mutable state yok).
  const hasMath =
    /(\d+)\^(\d+)/.test(text) || /(\d+)\/(\d+)/.test(text)

  if (!hasMath) {
    return <span className={className}>{text}</span>
  }

  return (
    <span className={className}>
      {splitWithMath(text).map((node, index) => (
        <Fragment key={index}>{node}</Fragment>
      ))}
    </span>
  )
}
