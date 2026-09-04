/**
 * Token kontrast testleri — WCAG AA.
 *
 * AA_TEXT_PAIRS: normal metin, oran ≥ 4.5.
 * LARGE_TEXT_PAIRS: büyük metin/aksan, oran ≥ 3.0.
 */

import { describe, expect, it } from "vitest"

import { AA_TEXT_PAIRS, BRAND, LARGE_TEXT_PAIRS } from "./tokens"

function srgbChannel(value: number): number {
  const v = value / 255

  return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
}

function relativeLuminance(hex: string): number {
  const clean = hex.replace("#", "")

  const r = parseInt(clean.slice(0, 2), 16)
  const g = parseInt(clean.slice(2, 4), 16)
  const b = parseInt(clean.slice(4, 6), 16)

  return (
    0.2126 * srgbChannel(r) +
    0.7152 * srgbChannel(g) +
    0.0722 * srgbChannel(b)
  )
}

function contrastRatio(foreground: string, background: string): number {
  const l1 = relativeLuminance(foreground)
  const l2 = relativeLuminance(background)

  return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05)
}

describe("WCAG AA token kontrastı", () => {
  it("tüm marka hex değerleri geçerli 6 haneli formatta", () => {
    for (const value of Object.values(BRAND)) {
      expect(value).toMatch(/^#[0-9A-F]{6}$/i)
    }
  })

  it.each(AA_TEXT_PAIRS)(
    "%s normal metin için ≥ 4.5",
    (_name, foreground, background) => {
      expect(contrastRatio(foreground, background)).toBeGreaterThanOrEqual(4.5)
    }
  )

  it.each(LARGE_TEXT_PAIRS)(
    "%s için ≥ 3.0",
    (_name, foreground, background) => {
      expect(contrastRatio(foreground, background)).toBeGreaterThanOrEqual(3)
    }
  )
})
