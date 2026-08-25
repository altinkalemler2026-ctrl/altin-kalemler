/**
 * Faz 5 Yarisma RPC hatalari icin Turkce kullanici mesajlari.
 *
 * Veritabani hata mesajlari (079) ASCII Turkce olarak yazilmistir;
 * burada desen eslesmesiyle anlasilir UI metnine cevrilir. Eslesmeyen
 * her hata genel bir mesaja dusur (fail-closed) — ham DB mesaji
 * kullaniciya gosterilmez.
 */

export const COMPETITION_ERROR_MESSAGES = {
  /** Oturum yok / suresi doldu. */
  authRequired:
    "Oturumunuz dogrulanamadi. Lutfen sayfayi yenileyip tekrar giris yapin.",
  /** Faz 4 rate limit penceresi doldu (075). */
  rateLimit:
    "Cok hizli islem yaptiniz; lutfen biraz bekleyip tekrar deneyin.",
  /** Ders bulunamadi veya pasif. */
  subjectNotFound:
    "Secili ders bulunamadi veya su anda pasif durumda.",
  /** Ogrenci profili eksik. */
  profileMissing:
    "Hesap bilgileriniz cozulenemedi. Profil kaydiniz eksik gorunuyor; lutfen destek ile iletisime gecin.",
  /** Yarisma bulunamadi. */
  competitionNotFound:
    "Yarisma bulunamadi. Lutfen sayfayi yenileyip tekrar deneyin.",
  /** Yarisma durumu izin vermiyor. */
  competitionNotReady:
    "Yarisma su anda bu islem icin hazir degil.",
  /** Katilimci degil. */
  notParticipant:
    "Bu yarismaya katilimci degilsiniz.",
  /** Genel bilinmeyen hata. */
  generic:
    "Beklenmeyen bir hata olustu. Lutfen tekrar deneyin; sorun surerse destek ekibine bildirin.",
} as const

/** Oturum kaybinda kullanilan kisa mesaj. */
export const SESSION_EXPIRED_MESSAGE =
  "Oturumunuz sona erdi. Lutfen tekrar giris yapin."

const AUTH_PATTERN = /kimlik dogrulamasi/i
const RATE_LIMIT_PATTERN = /cok fazla istek/i
const SUBJECT_PATTERN = /ders bulunamadi|pasif/i
const PROFILE_PATTERN = /profil bulunamadi|ogrenci profili/i
const COMPETITION_NOT_FOUND_PATTERN = /yarisma bulunamadi/i
const COMPETITION_STATUS_PATTERN = /durumu paket|izin vermiyor/i
const NOT_PARTICIPANT_PATTERN = /katilimci degilsiniz/i

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
 * Bilinen RPC hatalarini Turkce kullanici mesajina cevirir.
 * Bilinmeyen hatalarda ham mesaj sizmaz.
 */
export function mapCompetitionError(error: unknown): string {
  const text = errorText(error)

  if (AUTH_PATTERN.test(text)) return COMPETITION_ERROR_MESSAGES.authRequired
  if (RATE_LIMIT_PATTERN.test(text)) return COMPETITION_ERROR_MESSAGES.rateLimit
  if (SUBJECT_PATTERN.test(text)) return COMPETITION_ERROR_MESSAGES.subjectNotFound
  if (PROFILE_PATTERN.test(text)) return COMPETITION_ERROR_MESSAGES.profileMissing
  if (COMPETITION_NOT_FOUND_PATTERN.test(text)) {
    return COMPETITION_ERROR_MESSAGES.competitionNotFound
  }
  if (COMPETITION_STATUS_PATTERN.test(text)) {
    return COMPETITION_ERROR_MESSAGES.competitionNotReady
  }
  if (NOT_PARTICIPANT_PATTERN.test(text)) {
    return COMPETITION_ERROR_MESSAGES.notParticipant
  }
  // PostgREST yetki hatalari da oturum mesajina dusur (42501 vb.).
  if (/permission denied|row-level security/i.test(text)) {
    return COMPETITION_ERROR_MESSAGES.authRequired
  }

  return COMPETITION_ERROR_MESSAGES.generic
}
