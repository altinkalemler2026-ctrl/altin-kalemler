/**
 * Faz 2/3 RPC hataları için Türkçe kullanıcı mesajları.
 *
 * Veritabanı hata mesajları (068/070) ASCII Türkçe olarak yazılmıştır;
 * burada desen eşleşmesiyle anlaşılır UI metnine çevrilir. Eşleşmeyen
 * her hata genel bir mesaja düşer (fail-closed) — ham DB mesajı
 * kullanıcıya gösterilmez.
 */

export const TRAINING_ERROR_MESSAGES = {
  /** Geçerli academic_week yok: fail-closed. */
  periodClosed:
    "Şu anda geçerli bir akademik dönem bulunamadığı için soru akışı güvenlik nedeniyle durduruldu. Lütfen daha sonra tekrar deneyin.",
  /** Profil/müfredat bağlamı çözülemedi. */
  contextMissing:
    "Hesap bilgileriniz çözümlenemedi. Sınıf veya müfredat kaydınız eksik görünüyor; lütfen destek ile iletişime geçin.",
  /** Oturum yok / süresi doldu. */
  authRequired:
    "Oturumunuz doğrulanamadı. Lütfen sayfayı yenileyip tekrar giriş yapın.",
  /** Haftalık yeni soru limiti doldu. */
  weeklyLimit:
    "Bu ders için bu haftaki yeni soru hakkınız doldu. Tekrar sorularla çalışmaya devam edebilirsiniz.",
  /** Bilinmeyen her hata için genel mesaj. */
  generic:
    "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin; sorun sürerse destek ekibine bildirin.",
} as const

/** Oturum kaybında aksiyon cevaplarında kullanılan kısa mesaj. */
export const SESSION_EXPIRED_MESSAGE =
  "Oturumunuz sona erdi. Lütfen tekrar giriş yapın."

const AUTH_PATTERN = /kimlik dogrulamasi/i
const PERIOD_PATTERN = /akademik donem bulunamadi|gecerli akademik donem/i
const CONTEXT_PATTERN = /baglami cozulemedi/i
const WEEKLY_LIMIT_PATTERN = /haftalik.*limit|kapasite.*dol/i

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

export function isPeriodClosedError(error: unknown): boolean {
  return PERIOD_PATTERN.test(errorText(error))
}

/**
 * Bilinen RPC hatalarını Türkçe kullanıcı mesajına çevirir.
 * Bilinmeyen hatalarda ham mesaj sızmaz.
 */
export function mapTrainingError(error: unknown): string {
  const text = errorText(error)

  if (PERIOD_PATTERN.test(text)) return TRAINING_ERROR_MESSAGES.periodClosed
  if (CONTEXT_PATTERN.test(text)) return TRAINING_ERROR_MESSAGES.contextMissing
  if (AUTH_PATTERN.test(text)) return TRAINING_ERROR_MESSAGES.authRequired
  if (WEEKLY_LIMIT_PATTERN.test(text)) {
    return TRAINING_ERROR_MESSAGES.weeklyLimit
  }
  // PostgREST yetki hataları da oturum mesajına düşer (42501 vb.).
  if (/permission denied|row-level security/i.test(text)) {
    return TRAINING_ERROR_MESSAGES.authRequired
  }

  return TRAINING_ERROR_MESSAGES.generic
}
