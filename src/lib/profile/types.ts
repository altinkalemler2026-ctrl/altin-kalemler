/**
 * Faz 10 profil DTO tipleri — YALNIZ allowlist alanları.
 *
 * Sözleşme:
 *  - DTO'da e-posta, telefon, UUID, auth metadata, özel metadata,
 *    puan defteri (ledger) ve grade dışı kişisel alan YOKTUR.
 *  - Grade yalnız OKUNUR; hiçbir yazma yolu bu modülden geçmez.
 *  - Avatar yalnız sunucudaki aktif katalogdan doğrulanır.
 */

/** Öğrencinin seçili avatarının güvenli görünümü. */
export interface OwnAvatarInfo {
  code: string
  name: string
}

/** Profil özeti: yalnız takma ad + sınıf + seçili avatar. */
export interface OwnProfileSummary {
  nickname: string
  gradeLevel: number
  avatar: OwnAvatarInfo | null
}

/** Onaylı katalogdaki bir avatar seçeneği (yalnız aktif + default). */
export interface AvatarOption {
  code: string
  name: string
  description: string | null
}

export interface AvatarCatalog {
  /** Katalogda seçilebilir avatar yoksa "empty". */
  status: "available" | "empty"
  options: AvatarOption[]
}

/** select_own_avatar RPC cevabının güvenli eşleniği. */
export interface AvatarSelectionResult {
  code: string
  name: string
}
