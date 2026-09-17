/**
 * Aday soru toplu paket sözleşmesi v1.0 — dış üreticilerden/farklı AI
 * modellerinden gelen soruların doğrudan yayınlanmadan
 * ai_question_staging alanına aday olarak alınmasını sağlayan yapı.
 *
 * Bu dosya yalnız sunucu katmanında kullanılır; istemciye doğrudan
 * verilmez. PDF metni/görseli/kaynak-türetme alanı bu sözleşmede
 * YOKTUR.
 *
 * Sözleşme kaynagi:
 *   - 032_ai_worker_staging_ingestion.sql deseni (deterministik intake)
 *   - 038_ai_question_final_readiness_gate.sql (gate zinciri)
 *   - 010_curriculum_outcomes.sql (outcome_code eşleme)
 *   - solution-types.ts (yazılı çözüm yapısı)
 */

import type { AiWorkerOptionKey, AiWorkerDifficulty, AiWorkerCognitiveType } from "@/ai-worker/types"
import type { WrittenSolution } from "./solution-types"

// ============================================================
// SÖZLEŞME SÜRÜMÜ
// ============================================================

export const CANDIDATE_BATCH_SCHEMA_VERSION = "1.0" as const

// ============================================================
// FORBIDDEN FIELDS
//
// PDF kaynak-derived alanları veya kaynak soru yeniden yazımı
// bu sözleşmede yasaktır.
// ============================================================

export const FORBIDDEN_QUESTION_FIELDS = [
  "source_question_text",
  "pdf_reference",
  "crop_reference",
  "image_data",
  "image_url",
  "source_page_number",
  "source_test_code",
  "source_question_code",
  "derived_from_question_id",
  "derived_from_source_id",
] as const

// ============================================================
// İzinli origin değerleri
// ============================================================

export const ALLOWED_ORIGINS = ["curriculum_original"] as const

export type AllowedOrigin = (typeof ALLOWED_ORIGINS)[number]

// ============================================================
// Öğretici üretici bilgisi
// ============================================================

export interface CandidateProducer {
  /** Üretici benzersiz kimliği (API anahtarı veya model adı). */
  id: string
  /** Üretici model adı (ör. "gpt-4o", "human-expert-1"). */
  model?: string
}

// ============================================================
// Tek tek aday soru
// ============================================================

export interface CandidateQuestionV1 {
  /** Üretici tarafından atanan benzersiz soru kimliği. */
  client_question_id?: string

  /** Sınıf seviyesi (1-12). */
  grade_level: number

  /** Ders UUID'si (subjects tablosu). */
  subject_id: string

  /** Kazanım kodu (curriculum_outcomes.outcome_code). */
  outcome_code: string

  /** Konu kısa adı/bilgisi (serbest metin). */
  topic?: string

  /** Soru metni (minimum 10 karakter, trimming sonrası). */
  question_text: string

  /** Seçenekler (A-D zorunlu, E isteğe bağlı). */
  options: {
    A: string
    B: string
    C: string
    D: string
    E?: string
  }

  /** Doğru cevap (A-E arası, seçenek anahtarı). */
  correct_answer: AiWorkerOptionKey

  /** Zorluk düzeyi (opsiyonel). */
  difficulty?: AiWorkerDifficulty

  /** Bilişsel tür (opsiyonel). */
  cognitive_type?: AiWorkerCognitiveType

  /** Tahmini çözüm süresi (saniye, pozitif tamsayı). */
  estimated_solve_time_seconds?: number

  /** Yapılandırılmış yazılı çözüm (zorunlu; adım adım). */
  solution?: WrittenSolution

  /** Üretici metadata'sı (serbest JSON). */
  metadata?: Record<string, unknown>
}

// ============================================================
// Toplu paket
// ============================================================

export interface CandidateQuestionBatchV1 {
  schema_version: typeof CANDIDATE_BATCH_SCHEMA_VERSION

  /** Üretici bilgisi. */
  producer: CandidateProducer

  /** Köken: yalnız curriculum_original izinli. */
  origin: AllowedOrigin

  /** Soru listesi (boş olamaz). */
  questions: CandidateQuestionV1[]
}

// ============================================================
// Doğrulama sonuç tipleri
// ============================================================

export type CandidateValidationStatus = "valid" | "invalid" | "duplicate"

export interface CandidateValidationResult {
  index: number
  client_question_id: string | null
  status: CandidateValidationStatus
  errors: string[]
  warnings: string[]
}

export type BatchValidationStatus = "accepted" | "rejected" | "partially_accepted"

export interface BatchValidationResult {
  status: BatchValidationStatus
  schema_version_valid: boolean
  origin_valid: boolean
  producer_valid: boolean
  question_count: number
  valid_count: number
  invalid_count: number
  duplicate_count: number
  candidates: CandidateValidationResult[]
  root_errors: string[]
}

// ============================================================
// Gate değerlendirme sonuçları (C-1 orchestrator için)
// ============================================================

export type GateName =
  | "answer_verification"
  | "curriculum_fit"
  | "solve_time"
  | "originality"
  | "question_quality"

export type GateResultStatus = "pending" | "pass" | "warning" | "fail" | "skipped"

export interface GateEvaluationResult {
  gate: GateName
  status: GateResultStatus
  score?: number
  details?: Record<string, unknown>
  message?: string
}

export type CandidateAuditOutcome = "ready_for_human_review" | "needs_review" | "rejected" | "pending_gates"

export interface CandidateAuditResult {
  staging_question_id: string
  outcome: CandidateAuditOutcome
  gates: GateEvaluationResult[]
  blocking_reasons: string[]
  warnings: string[]
}

export type BatchAuditStatus = "completed" | "partially_completed" | "blocked"

export interface BatchAuditResult {
  batch_id: string
  status: BatchAuditStatus
  total_candidates: number
  ready_count: number
  review_count: number
  rejected_count: number
  pending_count: number
  candidates: CandidateAuditResult[]
  /** Otomatik publication YAPILMAZ — her zaman false. */
  automatic_publication_allowed: false
}
