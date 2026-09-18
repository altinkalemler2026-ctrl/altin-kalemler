/**
 * Faz 16 P0.1 — Öğretmen Konu-Açma RPC hataları için Türkçe mesajlar.
 *
 * 110/119 RPC'leri ASCII Türkçe hata üretir; burada desen eşleşmesiyle
 * anlaşılır UI metnine çevrilir. Eşleşmeyen her hata genel mesaja düşer
 * (fail-closed) — ham DB mesajı asla ekrana sızmaz.
 */

export const CURRICULUM_TEACHING_ERROR_MESSAGES = {
  /** curriculum.manage yetkisi yok (okuma ve mutasyon). */
  forbidden:
    "Bu işlem için müfredat onayı yetkiniz yok. Lütfen sistem yöneticinizle iletişime geçin.",
  /** Schedule item veya akademik yıl eksik. */
  required:
    "Takvim öğesi ve akademik yıl bilgisi gereklidir.",
  /** p_status değeri geçersiz. */
  invalidStatus:
    "Onay durumu yalnız 'Onaylandı' veya 'Reddedildi' olabilir.",
  /** Schedule item bulunamadı. */
  notFound:
    "Takvim öğesi bulunamadı; sayfayı yenileyip tekrar deneyin.",
  /** Bilinmeyen her hata için genel mesaj. */
  generic:
    "Onay işlemi tamamlanamadı. Lütfen tekrar deneyin; sorun sürerse destek ekibine bildirin.",
} as const

/** Başarılı işlemler için sayfa üstü bilgi mesajları. */
export const CURRICULUM_TEACHING_SUCCESS_MESSAGES = {
  saved: "Onay durumu kaydedildi.",
} as const

/** Sunucu aksiyonu girdi doğrulaması mesajları (RPC'ye gitmeden). */
export const CURRICULUM_TEACHING_INPUT_MESSAGES = {
  scheduleItemRequired:
    "Takvim öğesi bilgisi gereklidir.",
  academicYearRequired:
    "Akademik yıl bilgisi gereklidir.",
  invalidStatus:
    "Geçersiz onay durumu seçimi.",
} as const

const FORBIDDEN_PATTERN = /curriculum\.manage yetkisi gerekli/i
const REQUIRED_PATTERN = /Schedule item ve akademik yil zorunludur|Akademik yil zorunludur/i
const INVALID_STATUS_PATTERN = /p_status approved veya rejected olmalidir/i
const NOT_FOUND_PATTERN = /Schedule item bulunamadi/i

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
 * Bilinen öğretmen konu-açma RPC hatalarını Türkçe kullanıcı mesajına
 * çevirir. Bilinmeyen hatalarda ham mesaj sızmaz.
 */
export function mapCurriculumTeachingError(
  error: unknown
): string {
  const text = errorText(error)

  if (FORBIDDEN_PATTERN.test(text)) {
    return CURRICULUM_TEACHING_ERROR_MESSAGES.forbidden
  }
  if (INVALID_STATUS_PATTERN.test(text)) {
    return CURRICULUM_TEACHING_ERROR_MESSAGES.invalidStatus
  }
  if (NOT_FOUND_PATTERN.test(text)) {
    return CURRICULUM_TEACHING_ERROR_MESSAGES.notFound
  }
  if (REQUIRED_PATTERN.test(text)) {
    return CURRICULUM_TEACHING_ERROR_MESSAGES.required
  }

  return CURRICULUM_TEACHING_ERROR_MESSAGES.generic
}