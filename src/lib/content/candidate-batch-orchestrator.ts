/**
 * C-1 Toplu Denetim Orkestratörü.
 *
 * Aday soru toplu paketlerini alır, deterministik doğrulama yapar,
 * DB'ye intake eder (ai_question_staging) ve bağımsız denetim
 * kapılarından (033-039) geçirir. Otomatik publication YAPMAZ.
 *
 * Test edilebilirlik için istemci DI ve gate provider DI verilir.
 * Production'da gate provider gerçek 033-039 RPC zincirini çağırır.
 */

import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/supabase/types"

import type {
  CandidateQuestionBatchV1,
  BatchValidationResult,
  BatchAuditResult,
  CandidateAuditResult,
  CandidateAuditOutcome,
  GateEvaluationResult,
  GateName,
} from "./candidate-batch-types"

import { validateCandidateQuestionBatch } from "./candidate-batch-validator"

export type ContentClient = SupabaseClient<Database>

export class CandidateBatchError extends Error {}

/** Yeni migration RPC'leri generated Database tipinde henüz yok — dar tip. */
interface CandidateBatchRpcClient {
  rpc(
    fn: "register_candidate_question_batch",
    args: { p_payload: Record<string, unknown> }
  ): Promise<{ data: unknown; error: { message: string } | null }>
}

function toNarrowClient(client: ContentClient): CandidateBatchRpcClient {
  return client as unknown as CandidateBatchRpcClient
}

// ============================================================
// GATE PROVIDER ARAYÜZÜ
//
// Her aday soru için bağımsız denetim kapılarını değerlendirir.
// Production'da gerçek 033-039 RPC zincirini çağırır.
// Testlerde mock ile beslenir.
// ============================================================

export interface GateProvider {
  /**
   * Tek bir staging soru için tüm bağımsız denetim kapılarını çalıştırır.
   * Geçen kapılar pass, başarısız olanlar fail döner.
   * Gate çalıştırılamıyorsa (AI sonucu yoksa) skipped/pending döner.
   */
  evaluateCandidate(stagingQuestionId: string): Promise<GateEvaluationResult[]>
}

// ============================================================
// VARSAYILAN GATE DEĞERLENDİRİCİ
//
// DB'deki mevcut ai_validation_results ve gate run
// tablolarından deterministik durum okuması yapar.
// AI çağrısı YAPMAZ.
// ============================================================

const MANDATORY_GATES: GateName[] = [
  "answer_verification",
  "curriculum_fit",
  "solve_time",
  "originality",
  "question_quality",
]

function aggregateOutcome(
  gates: GateEvaluationResult[]
): CandidateAuditOutcome {
  const blockingReasons: string[] = []
  const warnings: string[] = []

  for (const gate of gates) {
    if (gate.status === "fail") {
      blockingReasons.push(`${gate.gate}: basarisiz`)
    }
    if (gate.status === "warning") {
      warnings.push(`${gate.gate}: uyarili`)
    }
    if (gate.status === "pending" || gate.status === "skipped") {
      blockingReasons.push(`${gate.gate}: denetim_tamamlanmadi`)
    }
  }

  if (blockingReasons.length > 0) {
    const hasFail = gates.some((g) => g.status === "fail")
    return hasFail ? "rejected" : "needs_review"
  }

  return "ready_for_human_review"
}

// ============================================================
// ORKESTRATÖR
// ============================================================

export class CandidateBatchOrchestrator {
  private readonly client: ContentClient
  private readonly gateProvider: GateProvider

  constructor(client: ContentClient, gateProvider: GateProvider) {
    this.client = client
    this.gateProvider = gateProvider
  }

  /**
   * Paketi doğrula + DB'ye intake et + bağımsız denetim
   * kapılarını çalıştır + toplu rapor üret.
   *
   * Otomatik publication YAPMAZ.
   */
  async auditBatch(
    batch: CandidateQuestionBatchV1
  ): Promise<{
    validation: BatchValidationResult
    audit: BatchAuditResult
  }> {
    // 1. Deterministik doğrulama
    const validation = validateCandidateQuestionBatch(batch)

    if (validation.status === "rejected") {
      return {
        validation,
        audit: {
          batch_id: "",
          status: "blocked",
          total_candidates: validation.question_count,
          ready_count: 0,
          review_count: 0,
          rejected_count: 0,
          pending_count: 0,
          candidates: [],
          automatic_publication_allowed: false,
        },
      }
    }

    // 2. DB'ye intake (register_candidate_question_batch RPC)
    const { data: intakeResult, error: intakeError } = await toNarrowClient(this.client).rpc(
      "register_candidate_question_batch",
      { p_payload: batch as unknown as Record<string, unknown> }
    )

    if (intakeError) {
      throw new CandidateBatchError(
        `DB intake hatası: ${intakeError.message}`
      )
    }

    const batchId = (intakeResult as Record<string, unknown>)?.batch_id as string | undefined
    const stagingIds = (intakeResult as Record<string, unknown>)?.staging_ids as string[] | undefined

    if (!batchId || !stagingIds || stagingIds.length === 0) {
      return {
        validation,
        audit: {
          batch_id: "",
          status: "blocked",
          total_candidates: validation.question_count,
          ready_count: 0,
          review_count: 0,
          rejected_count: 0,
          pending_count: validation.question_count,
          candidates: [],
          automatic_publication_allowed: false,
        },
      }
    }

    // 3. Her aday için bağımsız denetim kapılarını çalıştır
    const candidateResults: CandidateAuditResult[] = []

    for (const stagingId of stagingIds) {
      const gates = await this.gateProvider.evaluateCandidate(stagingId)
      const outcome = aggregateOutcome(gates)

      const blockingReasons: string[] = []
      const warnings: string[] = []

      for (const gate of gates) {
        if (gate.status === "fail") {
          blockingReasons.push(`${gate.gate}: ${gate.message ?? "basarisiz"}`)
        }
        if (gate.status === "warning") {
          warnings.push(`${gate.gate}: ${gate.message ?? "uyarili"}`)
        }
        if (gate.status === "pending" || gate.status === "skipped") {
          blockingReasons.push(`${gate.gate}: denetim_tamamlanmadi`)
        }
      }

      candidateResults.push({
        staging_question_id: stagingId,
        outcome,
        gates,
        blocking_reasons: blockingReasons,
        warnings,
      })
    }

    // 4. Toplu rapor
    const readyCount = candidateResults.filter((c) => c.outcome === "ready_for_human_review").length
    const reviewCount = candidateResults.filter((c) => c.outcome === "needs_review").length
    const rejectedCount = candidateResults.filter((c) => c.outcome === "rejected").length
    const pendingCount = candidateResults.filter((c) => c.outcome === "pending_gates").length

    let auditStatus: "completed" | "partially_completed" | "blocked"
    if (rejectedCount > 0) {
      auditStatus = "partially_completed"
    } else if (pendingCount > 0) {
      auditStatus = "partially_completed"
    } else {
      auditStatus = "completed"
    }

    return {
      validation,
      audit: {
        batch_id: batchId,
        status: auditStatus,
        total_candidates: candidateResults.length,
        ready_count: readyCount,
        review_count: reviewCount,
        rejected_count: rejectedCount,
        pending_count: pendingCount,
        candidates: candidateResults,
        automatic_publication_allowed: false,
      },
    }
  }

  /**
   * DB'deki mevcut bir batch'in denetim durumunu yeniden hesaplar.
   * Intake yapmaz; yalnızca staging satırlarını okur.
   */
  async reevaluateBatch(
    batchId: string
  ): Promise<BatchAuditResult> {
    const { data: stagingRows, error } = await this.client
      .from("ai_question_staging")
      .select("id")
      .contains("metadata", { candidate_batch_id: batchId })
      .neq("staging_status", "rejected")

    if (error) {
      throw new CandidateBatchError(
        `Staging satırları okunamadı: ${error.message}`
      )
    }

    if (!stagingRows || stagingRows.length === 0) {
      return {
        batch_id: batchId,
        status: "completed",
        total_candidates: 0,
        ready_count: 0,
        review_count: 0,
        rejected_count: 0,
        pending_count: 0,
        candidates: [],
        automatic_publication_allowed: false,
      }
    }

    const candidateResults: CandidateAuditResult[] = []

    for (const row of stagingRows) {
      const stagingId = row.id as string
      const gates = await this.gateProvider.evaluateCandidate(stagingId)
      const outcome = aggregateOutcome(gates)

      const blockingReasons: string[] = []
      const warnings: string[] = []

      for (const gate of gates) {
        if (gate.status === "fail") {
          blockingReasons.push(`${gate.gate}: ${gate.message ?? "basarisiz"}`)
        }
        if (gate.status === "warning") {
          warnings.push(`${gate.gate}: ${gate.message ?? "uyarili"}`)
        }
        if (gate.status === "pending" || gate.status === "skipped") {
          blockingReasons.push(`${gate.gate}: denetim_tamamlanmadi`)
        }
      }

      candidateResults.push({
        staging_question_id: stagingId,
        outcome,
        gates,
        blocking_reasons: blockingReasons,
        warnings,
      })
    }

    const readyCount = candidateResults.filter((c) => c.outcome === "ready_for_human_review").length
    const reviewCount = candidateResults.filter((c) => c.outcome === "needs_review").length
    const rejectedCount = candidateResults.filter((c) => c.outcome === "rejected").length
    const pendingCount = candidateResults.filter((c) => c.outcome === "pending_gates").length

    let auditStatus: "completed" | "partially_completed" | "blocked"
    if (rejectedCount > 0) {
      auditStatus = "partially_completed"
    } else if (pendingCount > 0) {
      auditStatus = "partially_completed"
    } else {
      auditStatus = "completed"
    }

    return {
      batch_id: batchId,
      status: auditStatus,
      total_candidates: candidateResults.length,
      ready_count: readyCount,
      review_count: reviewCount,
      rejected_count: rejectedCount,
      pending_count: pendingCount,
      candidates: candidateResults,
      automatic_publication_allowed: false,
    }
  }
}

/**
 * Varsayılan gate provider: DB'den mevcut validation sonuçlarını okur,
 * AI çağrısı yapmaz. Tüm kapılar henüz çalıştırılmamışsa pending döner.
 */
export function createDefaultGateProvider(): GateProvider {
  return {
    async evaluateCandidate(
      stagedId: string
    ): Promise<GateEvaluationResult[]> {
      // Bu provider DB'den ai_validation_results + gate run
      // tablolarını okumalıdır. Faz 14A'da henüz gate
      // sonuçları olmadığı için tüm kapılar pending döner.
      void stagedId
      return MANDATORY_GATES.map((gate) => ({
        gate,
        status: "pending" as const,
        message: "denetim_kapisi_henuz_calistirilmadi",
      }))
    },
  }
}

/**
 * Mock gate provider — testler için.
 * Belirli kapı durumlarını döner.
 */
export function createMockGateProvider(
  gateOverrides: Partial<Record<GateName, "pass" | "fail" | "warning" | "pending" | "skipped">>
): GateProvider {
  return {
    async evaluateCandidate(
      stagedId: string
    ): Promise<GateEvaluationResult[]> {
      void stagedId
      return MANDATORY_GATES.map((gate) => ({
        gate,
        status: gateOverrides[gate] ?? "pending",
        message: `${gate}: ${gateOverrides[gate] ?? "pending"}`,
      }))
    },
  }
}
