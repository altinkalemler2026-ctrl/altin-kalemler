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
  /** Cevap zaten gonderilmis (duplicate). */
  answerAlreadySubmitted:
    "Bu soruya cevabiniz zaten gonderildi.",
  /** Soru henuz baslamadi. */
  questionNotStarted:
    "Soru henuz baslamadi; lutfen bekleyin.",
  /** Yarisma sona erdi. */
  competitionCompleted:
    "Yarisma sona erdi.",
  /** Skor tablosu henuz mevcut degil. */
  scoreboardNotAvailable:
    "Skor tablosu yarisma sona erdikten sonra goruntulenebilir.",
  /** Haftalik kota tukendi (KOTA_163 — 163 kuresel kota sozlesmesi). */
  weeklyQuota:
    "Haftalık yarışma hakkınız tükendi. Yeni haftanın başlamasıyla birlikte tekrar yarışmalara katılabilirsiniz.",
  /**
   * Ders bazli haftalik kota tukendi (KOTA_165 — 165 ders bazli kota,
   * AK-QUOTA-SUBJECT-01 urun karari). Yalniz ILGILI ders icin gecerlidir.
   */
  weeklyQuotaSubject:
    "Bu ders için haftalık yarışma hakkınız tükendi. Yeni haftanın başlamasıyla birlikte bu derste tekrar yarışabilirsiniz.",
  /** Ders bazli haftalik YENI SORU hakki tukendi (KOTA_165, 200 kapisi). */
  weeklyQuestionQuotaSubject:
    "Bu ders için haftalık yeni soru hakkınız tükendi. Yeni haftanın başlamasıyla birlikte bu derste tekrar yarışabilirsiniz.",
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
const ANSWER_ALREADY_SUBMITTED_PATTERN = /cevap zaten gonderildi|already submitted/i
const QUESTION_NOT_STARTED_PATTERN = /soru henuz baslamadi/i
const COMPETITION_COMPLETED_PATTERN = /yarisma sona erdi/i
const SCOREBOARD_NOT_AVAILABLE_PATTERN = /skor tablosu.*mevcut degil|after the competition ends/i
// 163 haftalik kota: yalniz IKI kota-tukenmis varyanti eslesir
// (40 yarisma / 200 yeni soru). "KOTA_163: gecerli akademik donem yok"
// teknik hatasi ve YETKI_163 bilerek DISARIDA — kota mesaji yanlis
// senaryoda gosterilmez (urun karari, AK-FLOW-01 §kota).
const WEEKLY_QUOTA_PATTERN =
  /KOTA_163: haftalik (yarisma kotasi doldu|yeni soru kotasi asilirdi)/i
// 165 ders bazli kota (AK-QUOTA-SUBJECT-01): yalniz kota-tukenmis
// varyantlari eslesir. KOTA_165 teknik hata ve YETKI_165/KOTA_165_DEPRECATED
// BILEREK disaridadir — stok yetersizligi/teknik hata/rakip
// bulunamamasi bu mesajlarla KARISTIRILMAZ (urun karari).
const SUBJECT_QUOTA_COMPETITION_PATTERN =
  /KOTA_165: bu ders icin haftalik yarisma kotasi doldu/i
const SUBJECT_QUOTA_QUESTION_PATTERN =
  /KOTA_165: bu ders icin haftalik yeni soru kotasi asilirdi/i

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

  if (WEEKLY_QUOTA_PATTERN.test(text)) return COMPETITION_ERROR_MESSAGES.weeklyQuota
  if (SUBJECT_QUOTA_COMPETITION_PATTERN.test(text)) {
    return COMPETITION_ERROR_MESSAGES.weeklyQuotaSubject
  }
  if (SUBJECT_QUOTA_QUESTION_PATTERN.test(text)) {
    return COMPETITION_ERROR_MESSAGES.weeklyQuestionQuotaSubject
  }
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
  if (ANSWER_ALREADY_SUBMITTED_PATTERN.test(text)) {
    return COMPETITION_ERROR_MESSAGES.answerAlreadySubmitted
  }
  if (QUESTION_NOT_STARTED_PATTERN.test(text)) {
    return COMPETITION_ERROR_MESSAGES.questionNotStarted
  }
  if (COMPETITION_COMPLETED_PATTERN.test(text)) {
    return COMPETITION_ERROR_MESSAGES.competitionCompleted
  }
  if (SCOREBOARD_NOT_AVAILABLE_PATTERN.test(text)) {
    return COMPETITION_ERROR_MESSAGES.scoreboardNotAvailable
  }
  // PostgREST yetki hatalari da oturum mesajina dusur (42501 vb.).
  if (/permission denied|row-level security/i.test(text)) {
    return COMPETITION_ERROR_MESSAGES.authRequired
  }

  return COMPETITION_ERROR_MESSAGES.generic
}
