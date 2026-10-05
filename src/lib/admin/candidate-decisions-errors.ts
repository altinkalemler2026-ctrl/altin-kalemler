/**
 * Faz 35 — AI aday soru insan kararı (UI-P2A) hata/mesaj sözleşmesi.
 *
 * `private.review_and_promote_ai_question` ASCII Türkçe/İngilizce hata
 * üretir (migration 130). Burada ham metin üzerinden yalnız bir güvenli
 * sınıf (kind) çıkarılır ve UI metnine çevrilir.
 *
 * Fail-closed kural: eşleşmeyen her hata `generic` döner; ham DB mesajı
 * asla istemciye taşınmaz. Aynı desen `candidate-batches-errors.ts` ile
 * aynıdır.
 *
 * Kaynak satırlar (migration 130):
 *   1489 'Human authentication required.'
 *   1504 'Question approval permission required.'
 *   1515 'Invalid final review decision.'
 *   1532 'Staging question not found.'
 *   1554 'Rejected staging question cannot be promoted.'
 *   1579 'Final readiness evaluation not found.'
 *   1903 'Question is not ready for final human approval. Current readiness status: %'
 *   1910 'All mandatory AI quality gates must pass before promotion.'
 *   1938 'Question cannot be promoted: blocking promotion gates failed: %'
 */

import type { CandidateDecision, DecisionBlockedReason } from "./candidate-decisions"

// ---------------------------------------------------------------------------
// Girdi doğrulama mesajları
// ---------------------------------------------------------------------------

export const CANDIDATE_DECISION_INPUT_MESSAGES = {
  invalidStagingId:
    "Aday soru kimliği eksik veya geçersiz. Lütfen sayfayı yenileyip tekrar deneyin.",
  invalidDecision: "Geçersiz bir karar seçildi. Lütfen üç seçenekten birini seçin.",
  rationaleRequired:
    "Düzeltme istemek veya reddetmek için gerekçe yazmalısınız. Gerekçe olmadan karar kaydedilmez.",
} as const

export type CandidateDecisionInputError = keyof typeof CANDIDATE_DECISION_INPUT_MESSAGES

/** Girdi doğrulama hatasını Türkçe mesaja çevirir (fail-closed). */
export function mapDecisionInputError(error: unknown): string {
  if (
    error === "invalidStagingId" ||
    error === "invalidDecision" ||
    error === "rationaleRequired"
  ) {
    return CANDIDATE_DECISION_INPUT_MESSAGES[error]
  }
  return CANDIDATE_DECISION_INPUT_MESSAGES.invalidStagingId
}

// ---------------------------------------------------------------------------
// Devre dışı nedeni mesajları
// ---------------------------------------------------------------------------

/**
 * Devre dışı nedenlerinin kullanıcı metni. `null` neden asla gösterilmez.
 * Metinler doğrudan düğmelerin yanında görünür olacak şekilde yazılmıştır.
 */
export const DECISION_BLOCKED_MESSAGES: Record<DecisionBlockedReason, string> = {
  noStagingQuestion:
    "Bu aday için hazırlık kaydı yok. Karar verilemez.",
  alreadyDecided:
    "Bu aday için karar zaten verilmiş. Yeni karar verilemez.",
  validationIncomplete:
    "Doğrulama ve hazırlık değerlendirmesi tamamlanmadan insan kararı verilemez.",
  readinessMissing:
    "Hazırlık değerlendirmesi henüz oluşmadı. Önce doğrulama kapıları tamamlanmalı.",
  readinessNotComplete:
    "Hazırlık değerlendirmesi insan onayına hazır değil. Eksik doğrulama kapıları önce tamamlanmalı.",
  readinessScoreLow:
    "Hazırlık puanı tam puan değil. Eksik doğrulama kapıları önce tamamlanmalı.",
  readinessBlocked:
    "Tespit edilen hazırlık engelleri giderilmeden onay verilemez.",
  alreadyApproved:
    "Bu aday zaten onaylanmış durumda. Yeni bir onay kararı verilemez.",
}

/** Devre dışı nedenini Türkçe metne çevirir. */
export function blockedReasonMessage(reason: DecisionBlockedReason): string {
  return DECISION_BLOCKED_MESSAGES[reason] ?? DECISION_BLOCKED_MESSAGES.validationIncomplete
}

// ---------------------------------------------------------------------------
// RPC hata sınıfları
// ---------------------------------------------------------------------------

export const CANDIDATE_DECISION_ERROR_MESSAGES = {
  /** auth.uid() yok. */
  authRequired: "Bu işlemi tamamlamak için giriş yapmalısınız.",
  /** questions.approve veya ai.manage yetkisi yok. */
  forbidden:
    "Bu aday için karar vermeye yetkiniz yok. Lütfen sistem yöneticinizle iletişime geçin.",
  /** p_decision sözleşme dışı. */
  invalidDecision: "Geçersiz karar değeri gönderildi. İşlem tamamlanmadı.",
  /** Staging kaydı yok. */
  notFound: "Aday soru kaydı bulunamadı. Sayfayı yenileyip tekrar deneyin.",
  /** staging_status = 'rejected' — migration bu durumu reddeder. */
  alreadyRejected:
    "Bu aday daha önce reddedilmiş. Reddedilmiş bir adaya yeni karar verilemez.",
  /** Readiness run üretilemedi. */
  readinessMissing:
    "Hazırlık değerlendirmesi hesaplanamadı. İşlem tamamlanmadı.",
  /** approve: readiness_status hazır değil. */
  notReady:
    "Bu aday insan onayına hazır değil. Eksik doğrulama kapıları tamamlanmadan onay verilemez.",
  /** approve: readiness_score 1.0000 değil. */
  gatesFailed:
    "Zorunlu doğrulama kapılarının tümü geçilmeden onay verilemez.",
  /** approve: promotion blocker var. */
  promotionBlocked:
    "Tespit edilen engeller nedeniyle bu aday ilerletilemedi. Engelleri inceleyip tekrar deneyin.",
  /** approve: eksik deterministik alanlar. */
  incompleteQuestion:
    "Sorunun zorunlu alanları eksik olduğu için karar kaydedilemedi.",
  /** Sunucu tarafı yetki yeniden denetiminde karar uygun değildi. */
  notEligible:
    "Bu karar için aday uygun değil. Sayfayı yenileyip güncel durumu kontrol edin.",
  /** Bilinmeyen hata. */
  generic:
    "Aday kararı kaydedilemedi. Lütfen daha sonra tekrar deneyin.",
} as const

export type CandidateDecisionErrorKind = keyof typeof CANDIDATE_DECISION_ERROR_MESSAGES

// Eşleme sırası önemlidir: daha spesifik kalıplar önce denenir.
const ERROR_PATTERNS: ReadonlyArray<
  readonly [CandidateDecisionErrorKind, RegExp]
> = [
  ["authRequired", /Human authentication required/i],
  ["forbidden", /Question approval permission required/i],
  ["invalidDecision", /Invalid final review decision/i],
  ["notFound", /Staging question not found/i],
  ["alreadyRejected", /Rejected staging question cannot be promoted/i],
  ["readinessMissing", /Final readiness evaluation not found/i],
  ["notReady", /Question is not ready for final human approval/i],
  ["gatesFailed", /All mandatory AI quality gates must pass before promotion/i],
  ["promotionBlocked", /Question cannot be promoted: blocking promotion gates failed/i],
  [
    "incompleteQuestion",
    /Grade level is required|Subject is required|Question text is required|A valid correct answer is required|At least options A, B, C and D are required/i,
  ],
]

function errorText(error: unknown): string {
  if (error instanceof Error) return `${error.message}`
  if (typeof error === "string") return error
  if (typeof error === "object" && error !== null && "message" in error) {
    const message = (error as { message?: unknown }).message
    if (typeof message === "string") return message
  }
  return ""
}

/** Ham RPC hatasından güvenli sınıf çıkarır; eşleşme yoksa `generic`. */
export function candidateDecisionErrorKind(
  error: unknown
): CandidateDecisionErrorKind {
  const text = errorText(error)
  for (const [kind, pattern] of ERROR_PATTERNS) {
    if (pattern.test(text)) return kind
  }
  return "generic"
}

/** Bilinen RPC hatalarını Türkçe kullanıcı mesajına çevirir. */
export function mapCandidateDecisionError(error: unknown): string {
  return CANDIDATE_DECISION_ERROR_MESSAGES[candidateDecisionErrorKind(error)]
}

// ---------------------------------------------------------------------------
// Başarı / sonuç mesajları
// ---------------------------------------------------------------------------

/**
 * RPC'nin döndürdüğü `status` değerleri (migration 130):
 *   1540 'already_promoted'
 *   1608 'changes_requested' (idempotent_replay)
 *   1719 'changes_requested'
 *   1877 'rejected'
 *   2495 'promoted'
 * Bilinmeyen bir `status` fail-closed olarak `generic` işlenir.
 */
export type CandidateDecisionOutcomeStatus =
  | "promoted"
  | "already_promoted"
  | "changes_requested"
  | "rejected"
  | "idempotent_replay"

export function isCandidateDecisionOutcomeStatus(
  value: unknown
): value is CandidateDecisionOutcomeStatus {
  return (
    value === "promoted" ||
    value === "already_promoted" ||
    value === "changes_requested" ||
    value === "rejected" ||
    value === "idempotent_replay"
  )
}

/** Karar sonrası kullanıcı mesajı. Hepsi "yayınlanmadı" vurgusu taşır. */
export function decisionOutcomeMessage(status: CandidateDecisionOutcomeStatus): string {
  switch (status) {
    case "promoted":
      return "Karar kaydedildi: soru onaylandı ve soru bankasına taşındı. Öğrenciye yayınlanmadı."
    case "already_promoted":
      return "Bu aday daha önce onaylanmış ve soru bankasına taşınmış. Yeni bir kayıt oluşturulmadı."
    case "changes_requested":
      return "Karar kaydedildi: düzeltme istendi. Aday düzeltme için sıraya alındı ve öğrenciye yayınlanmadı."
    case "rejected":
      return "Karar kaydedildi: aday reddedildi. Aday ilerlemeyecek ve öğrenciye yayınlanmadı."
    case "idempotent_replay":
      return "Bu karar daha önce kaydedilmişti. Tekrar yazılmadı, mevcut sonuç gösteriliyor."
  }
}

/** Karar etiketleri (a11y ve onay adımı metinleri için). */
export const CANDIDATE_DECISION_LABELS: Record<CandidateDecision, string> = {
  approve: "İncelemeyi Onayla",
  request_changes: "Düzeltme İste",
  reject: "Reddet",
}

/** Onay adımında gösterilen karar açıklamaları. */
export const CANDIDATE_DECISION_DESCRIPTIONS: Record<CandidateDecision, string> = {
  approve:
    "Onaylanan soru soru bankasına taşınır ve bağımsız yayın güvenlik kapılarını bekler. Öğrenciye otomatik yayınlanmaz.",
  request_changes:
    "Düzeltme isteği kaydedilir ve aday düzeltme için sıraya alınır. Öğrenciye yayınlanmaz.",
  reject:
    "Aday kalıcı olarak reddedilir ve ilerleme zincirinden çıkar. Öğrenciye yayınlanmaz.",
}

/**
 * Yayın sınırı uyarısı. Panelin altında her zaman görünür; kullanıcıyı
 * "onayladım = öğrenciye yayınlandı" yanılgısından korur.
 */
export const CANDIDATE_DECISION_PUBLICATION_NOTICE =
  "Bu ekranda verilen hiçbir karar öğrenciye doğrudan yayın veya canlıya alma sağlamaz. Onaylanan sorular bağımsız Yayın İncelemesi güvenlik kapılarından geçmelidir."