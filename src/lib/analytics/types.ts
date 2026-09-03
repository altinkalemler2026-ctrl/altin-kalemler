/**
 * Training Analytics katmanı için GÜVENLİ veri transfer tipleri.
 *
 * Bu dosyadaki tipler yalnızca istemciye gidebilir alanları içerir.
 * service.ts mapper'ı RPC cevabından bu şemaya sıkı allowlist ile
 * çeviri yapar; PII ve soru gizli alanları (correct_answer, solution,
 * explanation, review vb.) bu katmandan ASLA geçmez.
 */

/** get_student_dimension_summary() tarafından okunan boyut kapsamları. */
export type DimensionScope = "subject" | "topic" | "subtopic" | "outcome"

export const DIMENSION_SCOPES: readonly DimensionScope[] = [
  "subject",
  "topic",
  "subtopic",
  "outcome",
]

export function isDimensionScope(value: unknown): value is DimensionScope {
  return (
    typeof value === "string" &&
    (DIMENSION_SCOPES as readonly string[]).includes(value)
  )
}

/** Bir boyut kapsamının öğrenciye özel metrik özet satırı. */
export interface DimensionSummaryRow {
  /** subject | topic | subtopic | outcome */
  scopeType: DimensionScope
  /** Müfredat nesnesinin uuid::text karşılığı; fallback kimliği olabilir. */
  scopeKey: string
  /** Sorgulanabilir görünen ad; eksik/bozuk dimension'da scope_key'e düşer. */
  displayName: string
  /** Ders id'si; dimension çözülemezse null. */
  subjectId: string | null
  /** Ders adı; dimension çözülemezse null. */
  subjectName: string | null
  total: number
  correct: number
  wrong: number
  blank: number
  passTimeout: number
  repeatTotal: number
  repeatCorrect: number
  totalTimeMs: number
  /** 0..100 (proje konvansiyonu, 1 hane); deneme yoksa 0. */
  successRate: number
  /** 0..100 (proje konvansiyonu, 1 hane); tekrar yoksa 0. */
  repeatSuccessRate: number
  /** Ortalama çözüm süresi (ms); deneme yoksa 0. */
  avgTimeMs: number
  /** En son deneme zamanı (ISO); yoksa null. */
  lastAttemptedAt: string | null
}

/** get_student_attempt_trend için izinli pencere genişlikleri (gün). */
export const TREND_DAYS = [7, 30] as const

export type TrendDays = (typeof TREND_DAYS)[number]

export function isTrendDays(value: unknown): value is TrendDays {
  return value === 7 || value === 30
}

/** get_student_attempt_trend tarafından okunan bir takvim gününün toplamı. */
export interface AttemptTrendDay {
  /** UTC takvim günü (YYYY-MM-DD); bugün dahil, azalara doğru sıralı. */
  day: string
  /** O günkü toplam deneme sayısı (tüm sonuçlar dahil). */
  total: number
  correct: number
  wrong: number
  blank: number
  /** pass + timeout birleşik sayısı (Phase 1 pass_timeout konvansiyonu). */
  passTimeout: number
  /** 0..100 (proje konvansiyonu, 1 hane); deneme yoksa 0. */
  successRate: number
  /** Ortalama çözüm süresi (ms); NULL time_ms 0 sayılır; deneme yoksa 0. */
  avgTimeMs: number
}

// ====================================================================
// TRAINING ANALYTICS PHASE 3 — TOPIC PRIORITY (strong/weak + öncelik)
//
// Yalnız istemciye gidebilir alanlar. Priority canonically TypeScript'te
// hesaplanır (computeTopicPriorities); SQL/RPC'e dokunulmaz. Gizli/PII
// alan bu DTO'dan geçmez.
// ====================================================================

/** Topic başına toplam deneme sayısına göre kanıt güveni. */
export type EvidenceLevel = "none" | "minimal" | "low" | "medium" | "high"

/** Deterministik performans bandı (success_rate + kanıt eşiği bazlı). */
export type PerformanceBand =
  | "INSUFFICIENT_DATA"
  | "WEAK"
  | "DEVELOPING"
  | "STRONG"

/** Yalnız gerçekten kullanılan sinyallere göre üretilen açıklanabilir neden kodu. */
export type ReasonCode =
  | "LOW_SUCCESS"
  | "LOW_REPEAT_SUCCESS"
  | "STALE_TOPIC"
  | "INSUFFICIENT_DATA"

export const EVIDENCE_LEVELS: readonly EvidenceLevel[] = [
  "none",
  "minimal",
  "low",
  "medium",
  "high",
]

export const PERFORMANCE_BANDS: readonly PerformanceBand[] = [
  "INSUFFICIENT_DATA",
  "WEAK",
  "DEVELOPING",
  "STRONG",
]

export const REASON_CODES: readonly ReasonCode[] = [
  "LOW_SUCCESS",
  "LOW_REPEAT_SUCCESS",
  "STALE_TOPIC",
  "INSUFFICIENT_DATA",
]

export function isEvidenceLevel(value: unknown): value is EvidenceLevel {
  return (
    typeof value === "string" &&
    (EVIDENCE_LEVELS as readonly string[]).includes(value)
  )
}

export function isPerformanceBand(value: unknown): value is PerformanceBand {
  return (
    typeof value === "string" &&
    (PERFORMANCE_BANDS as readonly string[]).includes(value)
  )
}

export function isReasonCode(value: unknown): value is ReasonCode {
  return (
    typeof value === "string" &&
    (REASON_CODES as readonly string[]).includes(value)
  )
}

/** Doğruluk bandı eşiği (0..100; calculate_accuracy konvansiyonu, 1 hane). */
export const LOW_SUCCESS_THRESHOLD = 40
export const STRONG_SUCCESS_THRESHOLD = 70

/** Minimum band sınıflandırması için gereken toplam deneme sayısı. */
export const MIN_BAND_ATTEMPTS = 5

/** Priority ağırlıkları (SABİT ürün kararı; uygulamada değiştirilmez). */
export const WEAKNESS_WEIGHT = 0.5
export const REPEAT_WEIGHT = 0.3
export const RECENCY_WEIGHT = 0.2
export const TIME_WEIGHT = 0

/** Kanıt güveni çarpanları, evidence_level başına. */
export const EVIDENCE_CONFIDENCE: Record<EvidenceLevel, number> = {
  none: 0,
  minimal: 0.25,
  low: 0.5,
  medium: 0.75,
  high: 1,
}

/** Tekrar kanıt güveni: repeat_total bant aralığı üst sınırı -> çarpan. */
export const REPEAT_CONFIDENCE_BANDS: ReadonlyArray<{
  maxRepeatTotal: number
  confidence: number
}> = [
  { maxRepeatTotal: 1, confidence: 0.25 },
  { maxRepeatTotal: 4, confidence: 0.5 },
  { maxRepeatTotal: 9, confidence: 0.75 },
  { maxRepeatTotal: Number.POSITIVE_INFINITY, confidence: 1 },
]

/** Recency: son denemeden bugüne gün aralığı (kapsayıcı üst sınır) -> puan. */
export const RECENCY_BANDS: ReadonlyArray<{
  maxDays: number
  score: number
}> = [
  { maxDays: 7, score: 0 },
  { maxDays: 14, score: 25 },
  { maxDays: 29, score: 50 },
  { maxDays: 59, score: 75 },
  { maxDays: Number.POSITIVE_INFINITY, score: 100 },
]

/** STALE_TOPIC tetikleyen son-denetme eşiği (gün; recency bandlarıyla tutarlı). */
export const STALE_TOPIC_DAYS = 30

/** Girdi bir topic özeti; canonical prioritization bunun üstünde çalışır. */
export interface TopicPriorityInput {
  topicId: string
  topicName: string
  subjectId: string | null
  subjectName: string | null
  totalAttempts: number
  successRate: number
  repeatTotal: number
  repeatSuccessRate: number
  avgTimeMs: number
  lastAttemptedAt: string | null
}

/** Phase 3 çıktı DTO'su — istemciye güvenle gönderilebilir. */
export interface PriorityTopicDto {
  topicId: string
  topicName: string
  subjectId: string | null
  subjectName: string | null
  totalAttempts: number
  successRate: number
  repeatTotal: number
  repeatSuccessRate: number
  avgTimeMs: number
  lastAttemptedAt: string | null
  evidenceLevel: EvidenceLevel
  performanceBand: PerformanceBand
  weaknessScore: number
  repeatScore: number
  recencyScore: number
  timeScore: number
  priorityScore: number
  priorityRank: number
  reasonCodes: ReasonCode[]
}