/**
 * Training Analytics servis katmanı — YALNIZ server tarafı.
 *
 * Güvenlik kuralları:
 *  - Kullanıcı kimliği ASLA parametre olarak alınmaz; RPC yalnızca
 *    oturumdaki auth.uid() üzerinden kendi verisini döndürür.
 *  - RPC cevabı sıkı allowlist mapper'dan (mapDimensionSummaryRow)
 *    geçer; ham DB satırı DTO olarak doğrudan dışarı verilmez.
 *  - PII ve soru gizli alanları bu modülden çıkmaz.
 *  - DB hata metni fail-closed mesajlara çevrilir; ham mesaj sızmaz.
 *
 * Test edilebilirlik için fonksiyonlar istemciyi bağımlılık olarak alır
 * (DI); server component/action gerçek istemciyi, testler sahte istemci
 * verir.
 */

import type { SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "@/lib/supabase/types"
import {
  EVIDENCE_CONFIDENCE,
  LOW_SUCCESS_THRESHOLD,
  MIN_BAND_ATTEMPTS,
  RECENCY_BANDS,
  RECENCY_WEIGHT,
  REPEAT_CONFIDENCE_BANDS,
  REPEAT_WEIGHT,
  STALE_TOPIC_DAYS,
  STRONG_SUCCESS_THRESHOLD,
  TIME_WEIGHT,
  WEAKNESS_WEIGHT,
  isDimensionScope,
  isEvidenceLevel,
  isPerformanceBand,
  isReasonCode,
  isTrendDays,
  type AttemptTrendDay,
  type DimensionSummaryRow,
  type EvidenceLevel,
  type PerformanceBand,
  type PriorityTopicDto,
  type ReasonCode,
  type TopicPriorityInput,
  type TrendDays,
} from "./types"

export type AnalyticsClient = SupabaseClient<Database>

/** Kullanıcıya güvenle gösterilebilen hata. Ham DB mesajı taşımaz. */
export class AnalyticsError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "AnalyticsError"
  }
}

const AUTH_PATTERN = /kimlik dogrulamasi|permission denied|row-level security/i

/** Bilinen RPC hatalarını güvenli kullanıcı mesajına çevirir (fail-closed). */
function mapAnalyticsErrorText(error: unknown): string {
  const text = errorText(error)
  if (AUTH_PATTERN.test(text)) {
    return "Oturumunuz doğrulanamadı. Lütfen giriş yapıp tekrar deneyin."
  }
  return "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin."
}

function errorText(error: unknown): string {
  if (error instanceof Error) return error.message
  if (typeof error === "string") return error
  if (typeof error === "object" && error !== null && "message" in error) {
    const message = (error as { message?: unknown }).message
    if (typeof message === "string") return message
  }
  return ""
}

function toFiniteNumber(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string") {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return parsed
  }
  return 0
}

function toInt(value: unknown): number {
  return Math.trunc(toFiniteNumber(value))
}

function toNullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null
}

/** timestamptz çıktısını deterministik ISO (Z) biçimine normalleştirir. */
function toNullableTimestamp(value: unknown): string | null {
  const raw = toNullableString(value)
  if (raw === null) return null
  const parsed = new Date(raw)
  if (Number.isNaN(parsed.getTime())) return null
  return parsed.toISOString()
}

/**
 * Ham RPC satırını güvenli DTO'ya çevirir.
 * Sıkı allowlist: yalnızca aşağıdaki alanlar geçer; bilinmeyen/ekstra
 * alanlar (PII, soru gizli alanları, sonraki DB sütunları) sessizce
 * düşer. Anlamsız kapsam/kimlik içeren satır null döner (atlanır).
 */
export function mapDimensionSummaryRow(
  raw: unknown
): DimensionSummaryRow | null {
  if (typeof raw !== "object" || raw === null) return null
  const record = raw as Record<string, unknown>

  const scopeType = record.scope_type
  if (!isDimensionScope(scopeType)) return null
  const scopeKey = record.scope_key
  if (typeof scopeKey !== "string" || scopeKey.length === 0) return null

  return {
    scopeType,
    scopeKey,
    displayName: toNullableString(record.display_name) ?? scopeKey,
    subjectId: toNullableString(record.subject_id),
    subjectName: toNullableString(record.subject_name),
    total: toInt(record.total),
    correct: toInt(record.correct),
    wrong: toInt(record.wrong),
    blank: toInt(record.blank),
    passTimeout: toInt(record.pass_timeout),
    repeatTotal: toInt(record.repeat_total),
    repeatCorrect: toInt(record.repeat_correct),
    totalTimeMs: toInt(record.total_time_ms),
    successRate: toFiniteNumber(record.success_rate),
    repeatSuccessRate: toFiniteNumber(record.repeat_success_rate),
    avgTimeMs: toFiniteNumber(record.avg_time_ms),
    lastAttemptedAt: toNullableTimestamp(record.last_attempted_at),
  }
}

/**
 * 085/086 RPC'leri (training analytics) generated Supabase tiplerine
 * eklendi (supabase gen types); RPC çağrıları artık doğrudan
 * AnalyticsClient üzerinden tip-güvenli yapılır.
 */

/**
 * Oturumdaki öğrencinin kendi boyut metrik özetini döndürür
 * (subject/topic/subtopic/outcome). Kullanıcı parametresi almaz;
 * kimlik RPC'de auth.uid()'den gelir.
 */
export async function fetchStudentDimensionSummary(
  client: AnalyticsClient
): Promise<DimensionSummaryRow[]> {
  const { data, error } = await client.rpc("get_student_dimension_summary")
  if (error) throw new AnalyticsError(mapAnalyticsErrorText(error))

  const rows = Array.isArray(data) ? data : []
  const result: DimensionSummaryRow[] = []
  for (const raw of rows) {
    const mapped = mapDimensionSummaryRow(raw)
    if (mapped) result.push(mapped)
  }
  return result
}

/** Pencere genişliğini allowlist'e bağlar; geçersizse fail-closed fırlatır. */
export function validateTrendDays(days: number): TrendDays {
  if (!isTrendDays(days)) {
    throw new AnalyticsError(
      "Geçersiz pencere; yalnızca 7 veya 30 günlük trend desteklenir."
    )
  }
  return days
}

/**
 * Ham günlük-trend satırını güvenli DTO'ya çevirir.
 * Sıkı allowlist: yalnızca ilk sekiz alan taşınır; bilinmeyen/ekstra
 * alanlar (PII, soru gizli alanları, sonraki DB sütunları) sessizce
 * düşer. Anlamsız gün içeren satır null döner (atlanır).
 */
export function mapAttemptTrendRow(raw: unknown): AttemptTrendDay | null {
  if (typeof raw !== "object" || raw === null) return null
  const record = raw as Record<string, unknown>

  const day = record.day
  if (typeof day !== "string" || day.length === 0) return null

  return {
    day,
    total: toInt(record.total),
    correct: toInt(record.correct),
    wrong: toInt(record.wrong),
    blank: toInt(record.blank),
    passTimeout: toInt(record.pass_timeout),
    successRate: toFiniteNumber(record.success_rate),
    avgTimeMs: toFiniteNumber(record.avg_time_ms),
  }
}

/**
 * Oturumdaki öğrencinin kendi günlük deneme trendini döndürür
 * (bugün dahil son 7 ve 30 UTC takvim günü). Kullanıcı parametresi
 * almaz; kimlik RPC'de auth.uid()'den gelir.
 */
export async function fetchStudentAttemptTrend(
  client: AnalyticsClient,
  days: number
): Promise<AttemptTrendDay[]> {
  const windowDays = validateTrendDays(days)

  const { data, error } = await client.rpc("get_student_attempt_trend", {
    p_days: windowDays,
  })
  if (error) throw new AnalyticsError(mapAnalyticsErrorText(error))

  const rows = Array.isArray(data) ? data : []
  const result: AttemptTrendDay[] = []
  for (const raw of rows) {
    const mapped = mapAttemptTrendRow(raw)
    if (mapped) result.push(mapped)
  }
  return result
}

// ====================================================================
// TRAINING ANALYTICS PHASE 3 — TOPIC PRIORITY (canonical, TypeScript)
//
// AI YOK, random YOK, siyah kutu YOK. Tamamen deterministik ve
// açıklanabilir. Bu fonksiyon Phase 3'ün tek canonical scoring
// kaynağıdır; aynı girdi + aynı referenceNow => aynı çıktı.
//
// Sinyaller (ağırlıklar SABİT ürün kararı):
//   weakness = 50%  (100 - success_rate, evidence confidence ile)
//   repeat   = 30%  (100 - repeat_success_rate, repeat confidence ile)
//   recency  = 20%  (son denetimden bugüne gün bandı)
//   time     = 0%   (güvenilir topic solve-time benchmark YOK)
// ====================================================================

/**
 * Sunucu tarafı "şimdi" epoch ms referansı.
 *
 * computeTopicPriorities referenceNow'ı dışarıdan alır (test determinizmi).
 * Üretimde bu fonksiyon çağrılır. Date.now() burada (server-only, React
 * bileşeni olmayan modül) tek merkezde tutulur; böylece React purity
 * kuralına (react-hooks/purity) takılmadan server component'ten çağrılabilir.
 */
export function analyticsReferenceNow(): number {
  return Date.now()
}

/** Bir helal DimensionSummaryRow (topic) satırını input'a çevirir. */
function toTopicPriorityInput(
  row: DimensionSummaryRow
): TopicPriorityInput {
  return {
    topicId: row.scopeKey,
    topicName: row.displayName,
    subjectId: row.subjectId,
    subjectName: row.subjectName,
    totalAttempts: row.total,
    successRate: row.successRate,
    repeatTotal: row.repeatTotal,
    repeatSuccessRate: row.repeatSuccessRate,
    avgTimeMs: row.avgTimeMs,
    lastAttemptedAt: row.lastAttemptedAt,
  }
}

/** Negatif olmayan sonlu sayı; bozuk girdi deterministik 0'a düşer. */
function clampNonNegative(value: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0
  return value < 0 ? 0 : value
}

/** 0..100 clamp; nan/Infinity -> 0. */
function clampScore(value: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0
  if (value < 0) return 0
  if (value > 100) return 100
  return value
}

/** Toplam deneme sayısından evidence_level türetir (0..∞ bantlar). */
export function evidenceLevelFromAttempts(totalAttempts: number): EvidenceLevel {
  const t = clampNonNegative(totalAttempts)
  if (t === 0) return "none"
  if (t === 1) return "minimal"
  if (t <= 4) return "low"
  if (t <= 9) return "medium"
  return "high"
}

/** Evidence level'a göre güven çarpanı; yabancı değer fail-safe 0. */
function evidenceConfidence(level: EvidenceLevel): number {
  if (isEvidenceLevel(level)) return EVIDENCE_CONFIDENCE[level]
  return 0
}

/** Toplam deneme sayısına göre performance_band (success_rate bazlı). */
export function performanceBandFrom(
  totalAttempts: number,
  successRate: number
): PerformanceBand {
  const t = clampNonNegative(totalAttempts)
  const rate = clampScore(successRate)
  if (t < MIN_BAND_ATTEMPTS) return "INSUFFICIENT_DATA"
  if (rate < LOW_SUCCESS_THRESHOLD) return "WEAK"
  if (rate < STRONG_SUCCESS_THRESHOLD) return "DEVELOPING"
  return "STRONG"
}

/** repeat_total boyutundan tekrar kanıt güveni (fail-safe 0). */
function repeatEvidenceConfidence(repeatTotal: number): number {
  const rr = clampNonNegative(repeatTotal)
  for (const band of REPEAT_CONFIDENCE_BANDS) {
    if (rr <= band.maxRepeatTotal) return band.confidence
  }
  return 0
}

/** Son denemeden bugüne gün sayısını hesaplar; bozuk tarih -> null. */
function daysSince(referenceNow: number, iso: string | null): number | null {
  if (iso === null) return null
  const parsed = new Date(iso).getTime()
  if (!Number.isFinite(parsed) || !Number.isFinite(referenceNow)) return null
  const diffMs = referenceNow - parsed
  if (diffMs < 0) return 0
  return Math.floor(diffMs / 86_400_000)
}

/** Gün aralığından recency puanı (kapsayıcı üst sınır). */
function recencyScoreForDays(days: number): number {
  for (const band of RECENCY_BANDS) {
    if (days <= band.maxDays) return band.score
  }
  return 100
}

/** reason_codes'u yalnız gerçek sinyale göre üretir (bandlarla tutarlı). */
function buildReasonCodes(
  band: PerformanceBand,
  totalAttempts: number,
  successRate: number,
  repeatTotal: number,
  repeatSuccessRate: number,
  days: number | null
): ReasonCode[] {
  const codes: ReasonCode[] = []
  if (isPerformanceBand(band) && band === "INSUFFICIENT_DATA") {
    codes.push("INSUFFICIENT_DATA")
    return codes
  }
  const rate = clampScore(successRate)
  if (rate < LOW_SUCCESS_THRESHOLD) codes.push("LOW_SUCCESS")
  if (repeatTotal > 0 && clampScore(repeatSuccessRate) < LOW_SUCCESS_THRESHOLD) {
    codes.push("LOW_REPEAT_SUCCESS")
  }
  if (days !== null && days >= STALE_TOPIC_DAYS) codes.push("STALE_TOPIC")
  return codes.filter(isReasonCode)
}

/**
 * Bileşen skorları. 0 denemedeki satır (evidence=none) kanıtlanamaz;
 * spec gereği tüm skorlar deterministik 0'dır (başka alan bozuk da olsa).
 * 1..4 denemede INSUFFICIENT_DATA bandı korunur ama evidence-adjusted
 * score DTO'da gösterilebilir.
 */
function computeScores(input: TopicPriorityInput, days: number | null) {
  const evidenceLevel = evidenceLevelFromAttempts(input.totalAttempts)
  if (evidenceLevel === "none") {
    return {
      evidenceLevel,
      weakness: 0,
      repeatScore: 0,
      recencyScore: 0,
      priority: 0,
    }
  }
  const confidence = evidenceConfidence(evidenceLevel)

  const rawWeakness = 100 - clampScore(input.successRate)
  const weakness = clampScore(rawWeakness * confidence)

  let repeatScore = 0
  if (input.repeatTotal > 0) {
    const rawRepeat = 100 - clampScore(input.repeatSuccessRate)
    repeatScore = clampScore(rawRepeat * repeatEvidenceConfidence(input.repeatTotal))
  }

  const recency = days === null ? 0 : recencyScoreForDays(days)

  const rawPriority =
    WEAKNESS_WEIGHT * weakness +
    REPEAT_WEIGHT * repeatScore +
    RECENCY_WEIGHT * recency +
    TIME_WEIGHT * 0
  const priority = clampScore(rawPriority)

  return { evidenceLevel, weakness, repeatScore, recencyScore: recency, priority }
}

/**
 * Canonical: DimensionSummaryRow (topic) satırlarından deterministik
 * topic öncelik listesi üretir.
 *
 * - Yalnız scope_type === 'topic' satırları kullanır.
 * - referenceNow ms epoch olarak inject edilir (test determinisimi;
 *   global Date.now() bağımlılığı YOK).
 * - Çıktı priority_score DESC, total_attempts DESC, topic_name lexical,
 *   topic_id tie-break ile sıralanır; rank 1'den başlar.
 */
export function computeTopicPriorities(
  rows: DimensionSummaryRow[],
  referenceNow: number
): PriorityTopicDto[] {
  const topics: TopicPriorityInput[] = []
  for (const row of rows) {
    if (row.scopeType === "topic") topics.push(toTopicPriorityInput(row))
  }

  const ranked: PriorityTopicDto[] = topics.map((input) => {
    const days = daysSince(referenceNow, input.lastAttemptedAt)
    const evidenceLevel = evidenceLevelFromAttempts(input.totalAttempts)
    const band = performanceBandFrom(input.totalAttempts, input.successRate)
    const { weakness, repeatScore, recencyScore, priority } = computeScores(
      input,
      days
    )
    const reasonCodes = buildReasonCodes(
      band,
      input.totalAttempts,
      input.successRate,
      input.repeatTotal,
      input.repeatSuccessRate,
      days
    )
    return {
      topicId: input.topicId,
      topicName: input.topicName,
      subjectId: input.subjectId,
      subjectName: input.subjectName,
      totalAttempts: input.totalAttempts,
      successRate: clampScore(input.successRate),
      repeatTotal: clampNonNegative(input.repeatTotal),
      repeatSuccessRate: clampScore(input.repeatSuccessRate),
      avgTimeMs: clampNonNegative(input.avgTimeMs),
      lastAttemptedAt: input.lastAttemptedAt,
      evidenceLevel,
      performanceBand: band,
      weaknessScore: weakness,
      repeatScore,
      recencyScore,
      timeScore: 0,
      priorityScore: priority,
      priorityRank: 0,
      reasonCodes,
    }
  })

  ranked.sort((a, b) => {
    if (b.priorityScore !== a.priorityScore) return b.priorityScore - a.priorityScore
    if (b.totalAttempts !== a.totalAttempts) return b.totalAttempts - a.totalAttempts
    if (a.topicName !== b.topicName)
      return (a.topicName < b.topicName ? -1 : 1) as -1 | 1
    return a.topicId < b.topicId ? -1 : a.topicId > b.topicId ? 1 : 0
  })

  for (let i = 0; i < ranked.length; i++) {
    ranked[i] = { ...ranked[i], priorityRank: i + 1 }
  }

  return ranked
}