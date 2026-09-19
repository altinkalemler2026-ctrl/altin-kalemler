/**
 * Faz 19 — Aday Yükleme Paketleri okuma RPC hataları için mesaj eşlemesi.
 *
 * 120 RPC'leri ASCII Türkçe hata üretir; burada hata metni üzerinden
 * güvenli bir sınıf (kind) çıkarılır ve UI metnine çevrilir. Eşleşmeyen
 * her hata genel mesaja düşer (fail-closed) — ham DB mesajı asla sızmaz.
 */

export const CANDIDATE_BATCH_ERROR_MESSAGES = {
  /** auth.uid() yok — kimlik doğrulaması gerekli. */
  authRequired:
    "Bu sayfayı görüntülemek için giriş yapmalısınız.",
  /** ai.manage veya questions.approve yetkisi yok. */
  forbidden:
    "Bu paket verilerini görüntülemek için yetkiniz yok. Lütfen sistem yöneticinizle iletişime geçin.",
  /** p_batch_id zorunlu. */
  required:
    "Paket kimliği eksik veya geçersiz.",
  /** Paket bulunamadı. */
  notFound:
    "Aradığınız aday yükleme paketi bulunamadı.",
  /** Bilinmeyen hata. */
  generic:
    "Aday yükleme paketi verisi şu anda okunamadı. Lütfen daha sonra tekrar deneyin.",
} as const

export type CandidateBatchErrorKind =
  | "authRequired"
  | "forbidden"
  | "required"
  | "notFound"
  | "generic"

const AUTH_REQUIRED_PATTERN = /Kimlik dogrulamasi gerekli/i
const FORBIDDEN_PATTERN = /ai\.manage veya questions\.approve yetkisi gerekli/i
const REQUIRED_PATTERN = /zorunludur|p_batch_id/i
const NOT_FOUND_PATTERN = /Aday paketi bulunamadi/i

function errorText(error: unknown): string {
  if (error instanceof Error) return `${error.message}`
  if (typeof error === "string") return error
  if (typeof error === "object" && error !== null && "message" in error) {
    const message = (error as { message?: unknown }).message
    if (typeof message === "string") return message
  }
  return ""
}

/**
 * Ham RPC hatasından güvenli sınıf çıkarır. Hiçbir koşulda ham mesaj
 * dışarı taşınmaz; eşleşmeyen her şey "generic" döner.
 */
export function candidateBatchErrorKind(error: unknown): CandidateBatchErrorKind {
  const text = errorText(error)
  if (AUTH_REQUIRED_PATTERN.test(text)) return "authRequired"
  if (FORBIDDEN_PATTERN.test(text)) return "forbidden"
  if (REQUIRED_PATTERN.test(text)) return "required"
  if (NOT_FOUND_PATTERN.test(text)) return "notFound"
  return "generic"
}

/** Bilinen RPC hatalarını Türkçe kullanıcı mesajına çevirir. */
export function mapCandidateBatchError(error: unknown): string {
  return CANDIDATE_BATCH_ERROR_MESSAGES[candidateBatchErrorKind(error)]
}

/**
 * Sorgu parametresinden güvenli paket UUID'si (geçersizse undefined).
 * Geçersiz uuid RPC'de gereksiz hata üretmesin diye erken reddedilir.
 */
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function parseBatchUuid(
  value: string | undefined
): string | undefined {
  const trimmed = value?.trim()
  return trimmed && UUID_PATTERN.test(trimmed) ? trimmed : undefined
}