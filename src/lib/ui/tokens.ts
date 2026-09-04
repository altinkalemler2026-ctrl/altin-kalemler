/**
 * Altın Kalemler marka ve semantik renk tokenları.
 *
 * Tek doğruluk kaynağı burasıdır; globals.css aynı değerleri
 * Tailwind @theme değişkenlerine yansıtır. Kontrast çiftleri
 * tokens.test.ts içinde WCAG AA (≥4.5) olarak doğrulanır.
 */

export const BRAND = {
  navy900: "#16233F",
  navy800: "#1B2A4A",
  navy700: "#24365E",
  navy100: "#E3E8F2",
  gold500: "#C9A227",
  gold300: "#E4C65B",
  gold100: "#F7ECD0",
  teal700: "#0E6E66",
  teal600: "#0F766E",
  teal100: "#D6EFEC",
  surface: "#FFFFFF",
  surfaceMuted: "#F5F7FA",
  ink: "#1F2937",
  inkMuted: "#4B5563",
  inkOnMuted: "#374151",
  border: "#D7DCE4",
  danger700: "#B91C1C",
  danger100: "#FEE2E2",
  success700: "#15803D",
  success100: "#DCFCE7",
  warning900: "#854D0E",
  warning100: "#FEF3C7",
} as const

/**
 * Metin çiftleri (normal metin için AA ≥ 4.5 zorunlu).
 * large/UI çiftleri büyük metin ve grafik öğeler için ≥ 3.0.
 */
export const AA_TEXT_PAIRS: Array<[string, string, string]> = [
  ["ink on surface", BRAND.ink, BRAND.surface],
  ["inkMuted on surface", BRAND.inkMuted, BRAND.surface],
  ["inkOnMuted on surfaceMuted", BRAND.inkOnMuted, BRAND.surfaceMuted],
  ["surface on navy800", BRAND.surface, BRAND.navy800],
  ["surface on teal700", BRAND.surface, BRAND.teal700],
  ["navy900 on gold100", BRAND.navy900, BRAND.gold100],
  ["teal700 on surface", BRAND.teal700, BRAND.surface],
  ["danger700 on danger100", BRAND.danger700, BRAND.danger100],
  ["success700 on success100", BRAND.success700, BRAND.success100],
  ["warning900 on warning100", BRAND.warning900, BRAND.warning100],
  ["danger700 on surface", BRAND.danger700, BRAND.surface],
]

export const LARGE_TEXT_PAIRS: Array<[string, string, string]> = [
  ["gold300 on navy900 (büyük metin)", BRAND.gold300, BRAND.navy900],
  ["gold500 on navy900 (büyük metin)", BRAND.gold500, BRAND.navy900],
]
