/**
 * Faz 3.5 akademik takvim RPC hataları için Türkçe kullanıcı mesajları.
 *
 * Veritabanı hata mesajları (073) ASCII Türkçe yazılmıştır; burada
 * desen eşleşmesiyle anlaşılır UI metnine çevrilir. Eşleşmeyen her
 * hata genel bir mesaja düşer (fail-closed) — ham DB mesajı asla
 * ekrana sızmaz.
 */

export const CALENDAR_ERROR_MESSAGES = {
  /** calendar.manage yetkisi yok (okuma ve mutasyon). */
  forbidden:
    "Bu işlem için akademik takvim yönetim yetkiniz yok. Lütfen sistem yöneticinizle iletişime geçin.",
  /** Aynı yıl içinde çakışma. */
  sameYearOverlap:
    "Girilen tarih aralığı aynı akademik yıl içindeki başka bir haftayla çakışıyor.",
  /** Farklı yıl takvimiyle çakışma (Faz 3.5 kuralı). */
  crossYearOverlap:
    "Girilen tarih aralığı farklı bir akademik yılın takvimiyle çakışıyor. Yılların takvimleri üst üste binemez.",
  /** DB backstop (074): eşzamanlı yazışma penceresinde yakalanan çakışma. */
  concurrentOverlap:
    "Bu tarih aralığı az önce başka bir kayıtla çakıştı; sayfayı yenileyip güncel takvimle tekrar deneyin.",
  /** Başlamış/geçmiş hafta güncellenemez. */
  startedUpdate:
    "Başlamış veya geçmiş bir akademik hafta değiştirilemez.",
  /** Başlamış/geçmiş hafta silinemez. */
  startedDelete:
    "Başlamış veya geçmiş bir akademik hafta silinemez.",
  /** Attempt referansı olan hafta silinemez. */
  referencedDelete:
    "Bu haftaya ait öğrenci deneme kayıtları bulunduğu için silinemedi.",
  /** Silinecek kayıt yok. */
  notFound:
    "Silinecek hafta bulunamadı; sayfayı yenileyip tekrar deneyin.",
  /** Girdi hatası (yıl/hafta/tarih). */
  invalidInput:
    "Girdiler geçersiz. Yıl, hafta numarası (0-52) ve tarih aralığını kontrol edin.",
  /** Bilinmeyen her hata için genel mesaj. */
  generic:
    "Takvim işlemi tamamlanamadı. Girdileri kontrol edip tekrar deneyin; sorun sürerse destek ekibine bildirin.",
} as const

/** Başarılı işlemler için sayfa üstü bilgi mesajları. */
export const CALENDAR_SUCCESS_MESSAGES = {
  upsert: "Akademik hafta kaydedildi.",
  delete: "Akademik hafta silindi.",
} as const

/** Sunucu aksiyonu girdi doğrulaması mesajları (RPC'ye gitmeden). */
export const CALENDAR_INPUT_MESSAGES = {
  yearRequired: "Akademik yıl bilgisi gereklidir.",
  weekRange: "Hafta numarası 0 ile 52 arasında bir sayı olmalıdır.",
  dateRequired: "Başlangıç ve bitiş tarihleri gereklidir.",
  dateInvalid: "Tarihler YYYY-AA-GG biçiminde olmalıdır.",
  dateOrder: "Bitiş tarihi başlangıç tarihinden sonra olmalıdır.",
} as const

const FORBIDDEN_PATTERN = /calendar\.manage yetkisi/i
const SAME_YEAR_PATTERN = /ayni akademik yilda.*cakisiyor/i
const CROSS_YEAR_PATTERN = /farkli.*akademik yil.*takvimiyle cakisiyor/i
// 074: RPC içi yakalama (ASCII Türkçe) + ham 23P01 İngilizce fallback.
const CONCURRENT_PATTERN =
  /eszamanli guncelleme algilandi|exclusion constraint/i
const STARTED_UPDATE_PATTERN = /baslamis veya gecmis.*degistirilemez/i
const STARTED_DELETE_PATTERN = /baslamis veya gecmis.*silinemez/i
const REFERENCED_PATTERN = /deneme kayitlari tarafindan referans aliniyor/i
const NOT_FOUND_PATTERN = /silinecek akademik hafta bulunamadi/i
const INVALID_INPUT_PATTERN =
  /gecersiz|bos olamaz|olmali|arasinda olmali|sonra olmali/i

function errorText(error: unknown): string {
  if (error instanceof Error) return `${error.message}`
  if (typeof error === "string") return error
  // supabase-js hataları Error örneği değil, düz PostgrestError
  // nesnesidir ({ message, details, hint, code }).
  if (typeof error === "object" && error !== null && "message" in error) {
    const message = (error as { message?: unknown }).message
    if (typeof message === "string") return message
  }
  return ""
}

/**
 * Bilinen takvim RPC hatalarını Türkçe kullanıcı mesajına çevirir.
 * Bilinmeyen hatalarda ham mesaj sızmaz.
 */
export function mapCalendarError(error: unknown): string {
  const text = errorText(error)

  if (FORBIDDEN_PATTERN.test(text)) return CALENDAR_ERROR_MESSAGES.forbidden
  if (CROSS_YEAR_PATTERN.test(text)) return CALENDAR_ERROR_MESSAGES.crossYearOverlap
  if (SAME_YEAR_PATTERN.test(text)) return CALENDAR_ERROR_MESSAGES.sameYearOverlap
  if (CONCURRENT_PATTERN.test(text)) return CALENDAR_ERROR_MESSAGES.concurrentOverlap
  if (STARTED_UPDATE_PATTERN.test(text)) return CALENDAR_ERROR_MESSAGES.startedUpdate
  if (STARTED_DELETE_PATTERN.test(text)) return CALENDAR_ERROR_MESSAGES.startedDelete
  if (REFERENCED_PATTERN.test(text)) return CALENDAR_ERROR_MESSAGES.referencedDelete
  if (NOT_FOUND_PATTERN.test(text)) return CALENDAR_ERROR_MESSAGES.notFound
  if (INVALID_INPUT_PATTERN.test(text)) return CALENDAR_ERROR_MESSAGES.invalidInput

  return CALENDAR_ERROR_MESSAGES.generic
}
