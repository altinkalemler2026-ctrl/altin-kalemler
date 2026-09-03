/**
 * Admin soru düzenleme ve yayın kontrolü: girdi doğrulama + RPC hata
 * çevirisi (migration 089/040 sözleşmeleri).
 *
 * Veritabanı hata mesajları (089/040, İngilizce) desen eşleşmesiyle
 * anlaşılır Türkçe UI metnine çevrilir. Eşleşmeyen her hata genel bir
 * mesaja düşer (fail-closed) — ham DB mesajı asla ekrana sızmaz.
 */

export const QUESTION_EDIT_INPUT_MESSAGES = {
  questionIdInvalid: "Geçersiz soru kimliği.",
  questionTextRequired: "Soru metni boş olamaz.",
  questionTextTooLong: "Soru metni en fazla 10000 karakter olabilir.",
  optionRequired: "A, B, C ve D seçenekleri dolu olmalıdır.",
  optionTooLong: "Seçenek metinleri en fazla 2000 karakter olabilir.",
  correctAnswerInvalid: "Doğru cevap A, B, C, D veya E seçeneklerinden biri olmalıdır.",
  deactivateReasonRequired: "Geri çekme sebebi gereklidir.",
  reasonTooLong: "Sebep metni en fazla 500 karakter olabilir.",
} as const

export const QUESTION_EDIT_ERROR_MESSAGES = {
  forbidden:
    "Bu işlem için soru düzenleme yetkiniz yok. Lütfen sistem yöneticinizle iletişime geçin.",
  publishForbidden:
    "Bu işlem için soru yayınlama yetkiniz yok. Lütfen sistem yöneticinizle iletişime geçin.",
  notFound: "Soru bulunamadı; sayfayı yenileyip tekrar deneyin.",
  sessionRequired: "Bu işlem için giriş yapmalısınız.",
  invalidInput:
    "Girdiler geçersiz. Soru metni, seçenekler ve doğru cevabı kontrol edin.",
  generic:
    "Soru işlemi tamamlanamadı. Girdileri kontrol edip tekrar deneyin; sorun sürerse destek ekibine bildirin.",
} as const

export const QUESTION_EDIT_SUCCESS_MESSAGES = {
  edit: "Soru güncellendi.",
  activate: "Soru öğrencilere yayınlandı.",
  deactivate: "Soru öğrencilerden geri çekildi.",
} as const

/** Yayın (activate/deactivate) RPC'lerinin özel durumları. */
export const QUESTION_PUBLICATION_STATUS_MESSAGES = {
  alreadyActive: "Soru zaten yayında.",
  alreadyInactive: "Soru zaten yayında değil.",
} as const

export const QUESTION_PUBLICATION_MESSAGES = {
  readinessUnavailable:
    "Yayın uygunluk durumu şu anda okunamadı. Lütfen daha sonra tekrar deneyin.",
  blockedTitle: "Soru şu anda yayına uygun değil:",
  readyTitle: "Soru yayına uygun görünüyor.",
  blockersTitle: "Yayın engelleri",
  warningsTitle: "Uyarılar",
  unknownBlocker: "Bu yayın koşulu açıklanamadı; gerekleri kontrol edin.",
} as const

/** Migration 040 readiness blocker/uyarı kodları → Türkçe açıklama. */
const BLOCKER_MESSAGES: Record<string, string> = {
  question_not_approved:
    "Soru onaylı değil; onay akışı tamamlandıktan sonra yayınlanabilir.",
  missing_question_text: "Soru metni boş; yayın için soru metni girilmelidir.",
  missing_required_options: "A, B, C ve D seçenekleri dolu olmalıdır.",
  invalid_correct_answer: "Geçerli bir doğru cevap (A-E) seçilmelidir.",
  invalid_grade: "Geçerli bir sınıf seviyesi gereklidir.",
  missing_subject: "Ders bilgisi eksik; yayın için ders atanmalıdır.",
  restricted_license: "Kısıtlı lisanslı soru yayınlanamaz.",
  third_party_license_not_approved:
    "Üçüncü taraf içerik için onaylı lisans gereklidir.",
  staging_not_promoted: "AI taslağı üretime taşınmadan (promote) yayınlanamaz.",
  missing_final_human_approval: "Son insan onayı kaydı gereklidir.",
  approved_curriculum_mapping_missing: "Onaylı müfredat eşlemesi gereklidir.",
  full_ai_readiness_missing: "Tam AI uygunluk puanı gereklidir.",
  valid_visual_asset_missing:
    "Görselli soru için geçerli ve aktif görsel varlığı gereklidir.",
  commercial_clearance_missing:
    "Ticari kullanımı açık soru için onaylı ticari izin gereklidir.",
  ownership_unknown: "Sahiplik durumu belirsiz; dikkatli ilerleyin.",
  curriculum_mapping_not_provided: "Bu soru için müfredat eşlemesi sağlanmamış.",
}

/** Bloker kodunu Türkçe açıklamaya çevirir; bilinmeyen kod sızmaz. */
export function mapBlockerMessage(code: string): string {
  return BLOCKER_MESSAGES[code] ?? QUESTION_PUBLICATION_MESSAGES.unknownBlocker
}

const FORBIDDEN_PATTERN = /Question edit permission required/i
const PUBLISH_FORBIDDEN_PATTERN =
  /Question approval permission required|Admin permission required/i
const SESSION_PATTERN = /(Human )?[Aa]uthentication required/i
const NOT_FOUND_PATTERN = /Question not found/i
const INVALID_INPUT_PATTERN =
  /Invalid (difficulty|cognitive type|quality level|correct answer)|Solve time must be positive|Deactivation reason is required/i

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

/** 089/040 RPC hatalarını Türkçe kullanıcı mesajına çevirir (ham sızmaz). */
export function mapQuestionEditError(error: unknown): string {
  const text = errorText(error)

  if (FORBIDDEN_PATTERN.test(text)) return QUESTION_EDIT_ERROR_MESSAGES.forbidden
  if (PUBLISH_FORBIDDEN_PATTERN.test(text))
    return QUESTION_EDIT_ERROR_MESSAGES.publishForbidden
  if (SESSION_PATTERN.test(text))
    return QUESTION_EDIT_ERROR_MESSAGES.sessionRequired
  if (NOT_FOUND_PATTERN.test(text)) return QUESTION_EDIT_ERROR_MESSAGES.notFound
  if (INVALID_INPUT_PATTERN.test(text))
    return QUESTION_EDIT_ERROR_MESSAGES.invalidInput

  return QUESTION_EDIT_ERROR_MESSAGES.generic
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** Aksiyonlarda erken reddetmek için UUID kimlik kontrolü. */
export function isValidQuestionId(value: string): boolean {
  return UUID_PATTERN.test(value)
}

const MAX_QUESTION_TEXT_LENGTH = 10_000
const MAX_OPTION_LENGTH = 2_000
const MAX_REASON_LENGTH = 500

export interface QuestionEditRawInput {
  questionId: string
  questionText: string
  optionA: string
  optionB: string
  optionC: string
  optionD: string
  optionE: string
  correctAnswer: string
}

export interface QuestionEditParsedInput {
  questionId: string
  questionText: string
  optionA: string
  optionB: string
  optionC: string
  optionD: string
  /** Boş string bilinçli olarak gönderilir: DB'de NULL'a temizlenir. */
  optionE: string
  correctAnswer: "A" | "B" | "C" | "D" | "E"
}

export type QuestionEditValidationResult =
  | { ok: true; value: QuestionEditParsedInput }
  | { ok: false; message: string }

/**
 * Düzenleme formu girdisini RPC'ye gitmeden doğrular:
 * - soru kimliği UUID,
 * - soru metni zorunlu ve uzunluk sınırlı,
 * - A-D seçenekleri zorunlu, tüm seçenekler uzunluk sınırlı,
 *   E seçeneği boş bırakılabilir (NULL'a temizlenir),
 * - doğru cevap A-E kümesinde.
 */
export function validateQuestionEditInput(
  raw: QuestionEditRawInput
): QuestionEditValidationResult {
  const questionId = raw.questionId.trim()
  if (!UUID_PATTERN.test(questionId)) {
    return { ok: false, message: QUESTION_EDIT_INPUT_MESSAGES.questionIdInvalid }
  }

  const questionText = raw.questionText.trim()
  if (questionText.length === 0) {
    return {
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.questionTextRequired,
    }
  }
  if (questionText.length > MAX_QUESTION_TEXT_LENGTH) {
    return {
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.questionTextTooLong,
    }
  }

  const optionA = raw.optionA.trim()
  const optionB = raw.optionB.trim()
  const optionC = raw.optionC.trim()
  const optionD = raw.optionD.trim()
  const optionE = raw.optionE.trim()

  if (optionA.length === 0 || optionB.length === 0 || optionC.length === 0 || optionD.length === 0) {
    return { ok: false, message: QUESTION_EDIT_INPUT_MESSAGES.optionRequired }
  }

  for (const option of [optionA, optionB, optionC, optionD, optionE]) {
    if (option.length > MAX_OPTION_LENGTH) {
      return { ok: false, message: QUESTION_EDIT_INPUT_MESSAGES.optionTooLong }
    }
  }

  const correctAnswer = raw.correctAnswer.trim().toUpperCase()
  if (
    correctAnswer !== "A" &&
    correctAnswer !== "B" &&
    correctAnswer !== "C" &&
    correctAnswer !== "D" &&
    correctAnswer !== "E"
  ) {
    return {
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.correctAnswerInvalid,
    }
  }

  return {
    ok: true,
    value: {
      questionId,
      questionText,
      optionA,
      optionB,
      optionC,
      optionD,
      optionE,
      correctAnswer: correctAnswer as QuestionEditParsedInput["correctAnswer"],
    },
  }
}

/** Geri çekme sebebi: zorunlu, kırpılmış, uzunluk sınırlı. */
export function validateDeactivateReason(
  raw: string
): { ok: true; value: string } | { ok: false; message: string } {
  const reason = raw.trim()
  if (reason.length === 0) {
    return {
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.deactivateReasonRequired,
    }
  }
  if (reason.length > MAX_REASON_LENGTH) {
    return { ok: false, message: QUESTION_EDIT_INPUT_MESSAGES.reasonTooLong }
  }
  return { ok: true, value: reason }
}

/** Yayın sebebi: opsiyonel; doluysa uzunluk sınırlı ve kırpılmış. */
export function validateActivateReason(
  raw: string
): { ok: true; value: string | null } | { ok: false; message: string } {
  const reason = raw.trim()
  if (reason.length === 0) return { ok: true, value: null }
  if (reason.length > MAX_REASON_LENGTH) {
    return { ok: false, message: QUESTION_EDIT_INPUT_MESSAGES.reasonTooLong }
  }
  return { ok: true, value: reason }
}
