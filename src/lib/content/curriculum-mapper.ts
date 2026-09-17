/**
 * Müfredat eşleme servisi.
 *
 * Sınıf → ders → konu → alt konu → kazanım ilişkisini mevcut
 * question_curriculum_mappings / question_outcome_mappings tablolarına bağlar.
 *
 * KURALLAR:
 * - Dosya adı veya AI tahmini TEK BAŞINA kesin eşleme sayılmaz; yalnız
 *   yüksek güvenli ve benzersiz aday onaylanır.
 * - Belirsiz eşleme (birden çok aday / düşük güven) insan incelemesine
 *   gider: ambiguityDetected=true döner ve DB'de review_status='pending'
 *   olarak kaydedilir.
 * - Eksik müfredat/takvim bilgisi sessizce uydurulmaz; aday yoksa
 *   no_candidates döner.
 *
 * Bu servis DB verisi sokmaz/çıkarmaz; aday değerlendirmesi için client
 * DI olarak verilir ve okuma yalnız topics / curriculum_outcomes üzerinden
 * yapılır.
 */

import type { SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "@/lib/supabase/types"

import {
  isMappingReviewStatus,
  isSourceType,
  type CurriculumMappingTarget,
  type MappingResult,
  type MappingSource,
  type MappingReviewStatus,
} from "./types"

export type MappingClient = SupabaseClient<Database>

export class MappingValidationError extends Error {}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function assertUuid(value: string, label: string): string {
  if (!UUID_PATTERN.test(value)) {
    throw new MappingValidationError(`${label} geçerli bir UUID değil.`)
  }
  return value
}

/** Tek güvenilir aday eşiği. Bu altında hiçbir aday tek başına onaylanmaz. */
export const MIN_MAPPING_CONFIDENCE = 0.7

/**
 * Eşleme adaylarını değerlendirir:
 * - Aday yok → no_candidates (fail-closed; uydurma yok).
 * - Tek güvenilir aday (unique + yüksek güven) → approved.
 * - Birden çok aday ya da hiçbir aday güven eşiğini aşmıyor → ambiguous
 *   (insan incelemesi).
 *
 * `mappingSource` ve `reviewStatus` çağıran tarafından belirlenir; bu
 * fonksiyon aday listesini DERLEMEZ, derecelendirir.
 */
export function evaluateMappingCandidates(
  questionId: string,
  candidates: Array<{
    topicId: string | null
    outcomeId: string | null
    confidenceScore: number
    mappingSource: MappingSource
    reviewStatus: MappingReviewStatus
    notes: string | null
  }>
): MappingResult {
  assertUuid(questionId, "Soru id")

  const normalized = candidates.filter((candidate) => {
    const hasTarget = candidate.topicId !== null || candidate.outcomeId !== null
    return hasTarget && candidate.confidenceScore >= 0 && candidate.confidenceScore <= 1
  })

  if (normalized.length === 0) {
    return { status: "no_candidates", mapping: null, ambiguity: null }
  }

  const confident = normalized.filter(
    (candidate) => candidate.confidenceScore >= MIN_MAPPING_CONFIDENCE
  )

  if (confident.length === 1) {
    const only = confident[0]
    return {
      status: "approved",
      mapping: {
        topicId: only.topicId,
        outcomeId: only.outcomeId,
        confidenceScore: only.confidenceScore,
        mappingSource: only.mappingSource,
        reviewStatus: only.reviewStatus,
        notes: only.notes,
      },
      ambiguity: null,
    }
  }

  if (confident.length === 0) {
    return {
      status: "ambiguous",
      mapping: null,
      ambiguity: {
        questionId,
        candidates: normalized.map((candidate) => ({
          topicId: candidate.topicId,
          outcomeId: candidate.outcomeId,
          confidenceScore: candidate.confidenceScore,
          mappingSource: candidate.mappingSource,
          reviewStatus: candidate.reviewStatus,
          notes: candidate.notes,
        })),
        ambiguityDetected: true,
        reason: "hicbir_aday_guven_esigini_gecmiyor",
      },
    }
  }

  return {
    status: "ambiguous",
    mapping: null,
    ambiguity: {
      questionId,
      candidates: confident.map((candidate) => ({
        topicId: candidate.topicId,
        outcomeId: candidate.outcomeId,
        confidenceScore: candidate.confidenceScore,
        mappingSource: candidate.mappingSource,
        reviewStatus: candidate.reviewStatus,
        notes: candidate.notes,
      })),
      ambiguityDetected: true,
      reason: "birden_fazla_aday_method",
    },
  }
}

/** Ham eşleme satırı → tek aday. Geçersiz target (iki tarafı da boş) atlanır. */
export function mapMappingCandidate(raw: unknown): {
  topicId: string | null
  outcomeId: string | null
  confidenceScore: number
  mappingSource: MappingSource
  reviewStatus: MappingReviewStatus
  notes: string | null
} | null {
  if (typeof raw !== "object" || raw === null) return null
  const record = raw as Record<string, unknown>

  const topicId = typeof record.topic_id === "string" ? record.topic_id : null
  const outcomeId = typeof record.outcome_id === "string" ? record.outcome_id : null
  if (topicId === null && outcomeId === null) return null

  const confidence = Number(record.confidence_score)
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
    return null
  }

  const mappingSource = record.mapping_source
  if (!isSourceType(mappingSource) && mappingSource !== "auto_matched") {
    // mapping_source allowlist'i tiplerde; geçerli üç değer:
    if (mappingSource !== "manual" && mappingSource !== "ai_suggested") return null
  }

  const reviewStatusRaw = record.review_status
  const reviewStatus = isMappingReviewStatus(reviewStatusRaw)
    ? (reviewStatusRaw as MappingReviewStatus)
    : "pending"

  return {
    topicId,
    outcomeId,
    confidenceScore: confidence,
    mappingSource: (["manual", "ai_suggested", "auto_matched"] as MappingSource[]).includes(
      mappingSource as MappingSource
    )
      ? (mappingSource as MappingSource)
      : "auto_matched",
    reviewStatus,
    notes: typeof record.notes === "string" ? record.notes : null,
  }
}

/**
 * Soru için mevcut kayıtlı eşleme adaylarını okur ve değerlendirir.
 * Verilen questionId üzerinden yalnız okuma yapar; yazma RPC/admin katmanında
 * kalır (bu servis salt-okunurdur).
 */
export async function evaluateQuestionMappings(
  client: MappingClient,
  questionId: string
): Promise<MappingResult> {
  assertUuid(questionId, "Soru id")

  const [topicResult, outcomeResult] = await Promise.all([
    client
      .from("question_curriculum_mappings")
      .select(
        "topic_id, outcome_id, confidence_score, mapping_source, review_status, notes"
      )
      .eq("question_id", questionId),
    client
      .from("question_outcome_mappings")
      .select(
        "topic_id, outcome_id, confidence_score, mapping_source, review_status, notes"
      )
      .eq("question_id", questionId),
  ])

  const rawRows = [...(topicResult.data ?? []), ...(outcomeResult.data ?? [])]
  const candidates: Parameters<typeof evaluateMappingCandidates>[1] = []
  for (const raw of rawRows) {
    const mapped = mapMappingCandidate(raw)
    if (mapped) candidates.push(mapped)
  }

  return evaluateMappingCandidates(questionId, candidates)
}