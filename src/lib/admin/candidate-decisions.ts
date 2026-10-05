/**
 * Faz 35 — AI aday soru insan kararı (UI-P2A) saf alan mantığı.
 *
 * Bu modül bilinçli olarak yan etkisiz (pure) tutulur: sunucu bileşeni de
 * server action da aynı türetmeyi kullanır. Böylece karar uygunluğu tek bir
 * yerden hesaplanır ve UI katmanındaki bir güncelleme sunucu yetkisini
 * genişletemez.
 *
 * Tüm veriler `src/lib/admin/candidate-batches.ts` içindeki allowlist'li DTO'dan
 * gelir; ham DB satırı veya gizli alan bu modüle girmez.
 *
 * Sözleşme kaynağı: `supabase/migrations/130_faz35b_review_actions_m1_m4.sql`
 * (`private.review_and_promote_ai_question`).
 *
 * KAPILI ALTIN KURAL (P2A ürün kararı):
 * Doğrulama/readiness tamamlanmadan insan kararı verilemez. Migration 130
 * `request_changes`/`reject` dallarına staging durumu kapısı koymaz; bu modül
 * bilinçli olarak migration'dan DAHA KATIDIR ve `validating` (ve öncesi)
 * adaylarda üç kararı da kapatır. Böylece gerçek veri durumunda panel
 * hiçbir yazma yolu açmaz. Sapma bilinçlidir ve faz raporunda kayıtlıdır.
 */

import type { CandidateRecord } from "./candidate-batches"

// ---------------------------------------------------------------------------
// Karar sözleşmesi
// ---------------------------------------------------------------------------

/** Migration 130'ün kabul ettiği kararlar — başka hiçbir değer kabul edilmez. */
export const CANDIDATE_DECISIONS = ["approve", "request_changes", "reject"] as const

export type CandidateDecision = (typeof CANDIDATE_DECISIONS)[number]

const DECISION_SET: ReadonlySet<string> = new Set(CANDIDATE_DECISIONS)

export function isCandidateDecision(value: unknown): value is CandidateDecision {
  return typeof value === "string" && DECISION_SET.has(value)
}

/**
 * Gerekçe (p_review_notes) zorunluluğu karara bağlıdır.
 *
 * Gerekçesiz ret/reddetme denetim izini zayıflatır; onayda ise gerekçe
 * isteğe bağlıdır çünkü onayın kendisi denetim kaydıdır.
 */
export function isRationaleRequired(decision: CandidateDecision): boolean {
  return decision === "request_changes" || decision === "reject"
}

/** `ai_question_staging.staging_status` CHECK değerleri (migration 006). */
const STAGING_STATUSES = [
  "draft",
  "extracted",
  "validating",
  "needs_review",
  "approved",
  "rejected",
  "promoted",
] as const

export type CandidateStagingStatus = (typeof STAGING_STATUSES)[number]

const STAGING_STATUS_SET: ReadonlySet<string> = new Set(STAGING_STATUSES)

export function isCandidateStagingStatus(
  value: unknown
): value is CandidateStagingStatus {
  return typeof value === "string" && STAGING_STATUS_SET.has(value)
}

/**
 * Karar öncesinde doğrulama/readiness'in tamamlanmamış olduğu durumlar.
 * Migration 006 CHECK listesinde `validating`'ten önce gelen tüm durumlar.
 */
const PRE_VALIDATION_STATUSES: ReadonlySet<string> = new Set([
  "draft",
  "extracted",
  "validating",
])

/** Kararın kapanmış olduğu durumlar — migration 130 bunları reddeder. */
const TERMINAL_STATUSES: ReadonlySet<string> = new Set(["rejected", "promoted"])

/** Readiness kapısı: migration 130 `approve` dalının tam olarak istediği değer. */
const REQUIRED_READINESS_STATUS = "ready_for_human_review"
const REQUIRED_READINESS_SCORE = 1

// ---------------------------------------------------------------------------
// Devre dışı nedenleri
// ---------------------------------------------------------------------------

/**
 * Bir karar düğmesinin devre dışı olma nedeni. `null` = karar uygun.
 * Her değet doğrudan kullanıcıya gösterilebilir güvenli bir sınıftır.
 */
export type DecisionBlockedReason =
  | "noStagingQuestion"
  | "alreadyDecided"
  | "validationIncomplete"
  | "readinessMissing"
  | "readinessNotComplete"
  | "readinessScoreLow"
  | "readinessBlocked"
  | "alreadyApproved"

// ---------------------------------------------------------------------------
// Readiness okuma yardımcıları
// ---------------------------------------------------------------------------

type GateFields = NonNullable<CandidateRecord["gates"]["readiness"]>["fields"]

function gateField(
  fields: GateFields | undefined,
  key: string
): string | number | boolean | string[] | null {
  if (!fields) return null
  return fields.find((field) => field.key === key)?.value ?? null
}

function gateString(fields: GateFields | undefined, key: string): string | null {
  const value = gateField(fields, key)
  return typeof value === "string" && value.length > 0 ? value : null
}

function gateScore(fields: GateFields | undefined): number | null {
  const value = gateField(fields, "readiness_score")
  return typeof value === "number" && Number.isFinite(value) ? value : null
}

function gateBlockers(fields: GateFields | undefined): string[] {
  const value = gateField(fields, "blocking_reasons")
  if (Array.isArray(value)) {
    return value.filter((entry): entry is string => typeof entry === "string")
  }
  // Bazı sürümlerde tek satırlık metin olarak gelir; yine de diziye çevrilir.
  return typeof value === "string" && value.length > 0 ? [value] : []
}

// ---------------------------------------------------------------------------
// Türetme
// ---------------------------------------------------------------------------

/** Tek bir karar için uygunluk + varsa devre dışı nedeni. */
export interface CandidateDecisionAvailability {
  decision: CandidateDecision
  enabled: boolean
  reason: DecisionBlockedReason | null
}

export interface CandidateDecisionContext {
  stagingStatus: string | null
  readinessStatus: string | null
  readinessScore: number | null
  blockingReasons: string[]
}

/** Aday kaydından karar değerlendirme bağlamını çıkarır. */
export function buildDecisionContext(
  candidate: CandidateRecord
): CandidateDecisionContext {
  const fields = candidate.gates.readiness?.fields
  return {
    stagingStatus: candidate.preview?.stagingStatus ?? null,
    readinessStatus: gateString(fields, "readiness_status"),
    readinessScore: gateScore(fields),
    blockingReasons: gateBlockers(fields),
  }
}

/**
 * Tüm kararlar için uygunluk haritası üretir.
 *
 * Kural sırası (ilk eşleşen kazanır):
 * 1. staging kaydı yok → hiçbir karar verilemez.
 * 2. `rejected`/`promoted` → karar kapanmış, migration da reddeder.
 * 3. `draft`/`extracted`/`validating` → doğrulama tamamlanmamış (P2A kuralı).
 * 4. `approved` → `approve` gereksiz (zaten onaylı), diğerleri açık.
 * 5. `approve` için readiness kapısı: durum + skor + blocking_reasons.
 * 6. Bilinmeyen/eksik durum → fail-closed, hiçbir karar açılmaz.
 */
export function deriveCandidateDecisionAvailability(
  candidate: CandidateRecord
): Record<CandidateDecision, CandidateDecisionAvailability> {
  const { stagingStatus, readinessStatus, readinessScore, blockingReasons } =
    buildDecisionContext(candidate)

  const availability = (
    decision: CandidateDecision,
    enabled: boolean,
    reason: DecisionBlockedReason | null
  ): CandidateDecisionAvailability => ({ decision, enabled, reason })

  if (!candidate.stagingQuestionId) {
    return {
      approve: availability("approve", false, "noStagingQuestion"),
      request_changes: availability("request_changes", false, "noStagingQuestion"),
      reject: availability("reject", false, "noStagingQuestion"),
    }
  }

  if (!isCandidateStagingStatus(stagingStatus)) {
    // Bilinmeyen veya eksik durum: fail-closed, hiçbir şey açılmaz.
    return {
      approve: availability("approve", false, "validationIncomplete"),
      request_changes: availability("request_changes", false, "validationIncomplete"),
      reject: availability("reject", false, "validationIncomplete"),
    }
  }

  if (TERMINAL_STATUSES.has(stagingStatus)) {
    return {
      approve: availability("approve", false, "alreadyDecided"),
      request_changes: availability("request_changes", false, "alreadyDecided"),
      reject: availability("reject", false, "alreadyDecided"),
    }
  }

  if (PRE_VALIDATION_STATUSES.has(stagingStatus)) {
    return {
      approve: availability("approve", false, "validationIncomplete"),
      request_changes: availability("request_changes", false, "validationIncomplete"),
      reject: availability("reject", false, "validationIncomplete"),
    }
  }

  // Buraya yalnız `needs_review` ve `approved` ulaşır (diğerleri yukarıda
  // elendi). `request_changes`/`reject` her ikisinde de açıktır.
  if (stagingStatus === "approved") {
    return {
      approve: availability("approve", false, "alreadyApproved"),
      request_changes: availability("request_changes", true, null),
      reject: availability("reject", true, null),
    }
  }

  // approve dalı: migration 130 kapılarını birebir yansıt.
  let approveReason: DecisionBlockedReason | null = null
  if (readinessStatus === null) {
    approveReason = "readinessMissing"
  } else if (readinessStatus !== REQUIRED_READINESS_STATUS) {
    approveReason = "readinessNotComplete"
  } else if (
    readinessScore === null ||
    readinessScore !== REQUIRED_READINESS_SCORE
  ) {
    // Migration 130 tam eşitlik ister (`IS DISTINCT FROM 1.0000`): hem
    // eksik/0.9 gibi düşük, hem de beklenmeyen 1.1 gibi yüksek skor kapalıdır.
    approveReason = "readinessScoreLow"
  } else if (blockingReasons.length > 0) {
    approveReason = "readinessBlocked"
  }

  return {
    approve: availability("approve", approveReason === null, approveReason),
    request_changes: availability("request_changes", true, null),
    reject: availability("reject", true, null),
  }
}

/** Panel genelinde tek bir "karar verilebilir mi" özeti (a11y duyuru metni). */
export interface CandidateDecisionSummary {
  canDecide: boolean
  enabledDecisions: CandidateDecision[]
}

export function summarizeCandidateDecision(
  availability: Record<CandidateDecision, CandidateDecisionAvailability>
): CandidateDecisionSummary {
  const enabledDecisions = CANDIDATE_DECISIONS.filter(
    (decision) => availability[decision].enabled
  )
  return { canDecide: enabledDecisions.length > 0, enabledDecisions }
}

/**
 * Sunucu tarafı tek karar doğrulaması.
 *
 * Server action bu fonksiyonu çağırarak URL'den gelen kararı yeniden
 * denetler; istemci katmanındaki hiçbir kontrole güvenilmez.
 */
export function isDecisionAvailable(
  candidate: CandidateRecord,
  decision: CandidateDecision
): boolean {
  return deriveCandidateDecisionAvailability(candidate)[decision].enabled
}

// ---------------------------------------------------------------------------
// Girdi doğrulama
// ---------------------------------------------------------------------------

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** Gerekçe uzunluk üst sınırı (migration'da TEXT; UI'da makul bir tavan). */
export const RATIONALE_MAX_LENGTH = 2000

/** Gerekçeyi güvenli biçimde normalize eder; fazla uzunluk kesilir. */
export function normalizeRationale(value: unknown): string {
  if (typeof value !== "string") return ""
  const trimmed = value.trim()
  return trimmed.length > RATIONALE_MAX_LENGTH
    ? trimmed.slice(0, RATIONALE_MAX_LENGTH)
    : trimmed
}

/** UUID biçimindeki staging soru kimliği (geçersizse undefined). */
export function parseStagingQuestionUuid(
  value: unknown
): string | undefined {
  if (typeof value !== "string") return undefined
  const trimmed = value.trim()
  return UUID_PATTERN.test(trimmed) ? trimmed : undefined
}

/**
 * Karar + gerekçe çiftinin girdi kurallarını doğrular.
 * Gerekçe zorunluluğu karara bağlıdır.
 */
export type DecisionInputError = "invalidStagingId" | "invalidDecision" | "rationaleRequired" | null

export function validateDecisionInput(input: {
  stagingQuestionId: unknown
  decision: unknown
  rationale: unknown
}): { ok: true; stagingQuestionId: string; decision: CandidateDecision; rationale: string } | { ok: false; error: DecisionInputError } {
  const stagingQuestionId = parseStagingQuestionUuid(input.stagingQuestionId)
  if (!stagingQuestionId) return { ok: false, error: "invalidStagingId" }

  if (!isCandidateDecision(input.decision)) {
    return { ok: false, error: "invalidDecision" }
  }
  const decision = input.decision

  const rationale = normalizeRationale(input.rationale)
  if (isRationaleRequired(decision) && rationale.length === 0) {
    return { ok: false, error: "rationaleRequired" }
  }

  return { ok: true, stagingQuestionId, decision, rationale }
}

// ---------------------------------------------------------------------------
// Karar geçmişi / readiness özeti (mevcut allowlist'li read DTO'dan)
// ---------------------------------------------------------------------------

export interface CandidateDecisionHistory {
  decision: string | null
  reviewNotes: string | null
  reviewedBy: string | null
  reviewedAt: string | null
}

type FinalReviewFields = NonNullable<CandidateRecord["gates"]["finalReview"]>["fields"]

/** `gates.final_review` alanlarından denetim kaydı özeti (yalnız allowlist). */
export function readFinalReviewHistory(
  candidate: CandidateRecord
): CandidateDecisionHistory {
  const fields: FinalReviewFields | undefined = candidate.gates.finalReview?.fields
  const read = (key: string): string | null => {
    const value = fields?.find((field) => field.key === key)?.value ?? null
    return typeof value === "string" && value.length > 0 ? value : null
  }
  return {
    decision: read("decision"),
    reviewNotes: read("review_notes"),
    reviewedBy: read("reviewed_by"),
    reviewedAt: read("reviewed_at"),
  }
}

/** Panelde gösterilecek readiness özeti. */
export interface CandidateReadinessSummary {
  readinessStatus: string | null
  readinessScore: number | null
  commercialClearanceStatus: string | null
  blockingReasons: string[]
}

export function readReadinessSummary(
  candidate: CandidateRecord
): CandidateReadinessSummary {
  const fields = candidate.gates.readiness?.fields
  return {
    readinessStatus: gateString(fields, "readiness_status"),
    readinessScore: gateScore(fields),
    commercialClearanceStatus: gateString(fields, "commercial_clearance_status"),
    blockingReasons: gateBlockers(fields),
  }
}