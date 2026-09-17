/**
 * Candidate Batch Orchestrator testleri — 7 senaryo.
 *
 * 1. Geçerli paket → accepted, staging ids döner
 * 2. Eksik alan → rejected (missing outcome_code / question_text)
 * 3. Yanlış outcome kodu → rejected (outcome_code format check fails)
 * 4. Yanlış cevap/çözüm → rejected (correct_answer points to missing option E, solution steps empty)
 * 5. Tekrar paket → duplicate question text → partially_accepted
 * 6. Denetim başarısız → needs_review / rejected → review_queue
 * 7. Hazır ama promotion edilmemiş → ready_for_human_review, auto_promote YOK
 *
 * Bu testler DB erişimi YAPMAZ; doğrulama ve orkestrasyon mantığı
 * test edilir. DB intake部分 mocked.
 */

import { describe, expect, it, vi } from "vitest"

import {
  validateCandidateQuestionBatch,
} from "./candidate-batch-validator"

import {
  CandidateBatchOrchestrator,
  createMockGateProvider,
  type ContentClient,
  type GateProvider,
} from "./candidate-batch-orchestrator"

import type {
  CandidateQuestionBatchV1,
  CandidateQuestionV1,
  GateEvaluationResult,
} from "./candidate-batch-types"

const SUBJECT_ID = "22222222-2222-4222-8222-222222222222"
const BATCH_ID = "33333333-3333-4333-8333-333333333333"
const STAGING_ID_1 = "44444444-4444-4444-8444-444444444444"
const STAGING_ID_2 = "55555555-5555-4555-8555-555555555555"

function validQuestion(overrides: Partial<CandidateQuestionV1> = {}): CandidateQuestionV1 {
  return {
    grade_level: 9,
    subject_id: SUBJECT_ID,
    outcome_code: "MAT.9.1.1",
    topic: "Kesirler",
    question_text: "1/2 ile 3/4'ün toplamı nedir?",
    options: {
      A: "5/6",
      B: "4/6",
      C: "5/8",
      D: "4/8",
    },
    correct_answer: "A",
    difficulty: "easy",
    cognitive_type: "application",
    estimated_solve_time_seconds: 75,
    solution: {
      method: "Kesirlerde payda eşitleme",
      steps: [
        { title: "Paydaları eşitle", content: "1/2 = 2/4 olur" },
        { title: "Topla", content: "2/4 + 3/4 = 5/4 = 1 1/4" },
      ],
      result: "5/4",
      correctAnswerJustification: "Seçenek A 5/4 veriyor",
    },
    ...overrides,
  }
}

function validBatch(questions: CandidateQuestionV1[] = [validQuestion()]): CandidateQuestionBatchV1 {
  return {
    schema_version: "1.0",
    producer: { id: "test-producer-1", model: "test-model" },
    origin: "curriculum_original",
    questions,
  }
}

// ============================================================
// MOCK DB CLIENT
// ============================================================

function mockClient(intakeResult: Record<string, unknown> | null = null, stagingRows: Array<{ id: string }> = []) {
  return {
    rpc: vi.fn().mockResolvedValue({
      data: intakeResult,
      error: intakeResult === null ? { message: "rpc hatası" } : null,
    }),
    from: vi.fn().mockReturnValue({
      select: vi.fn().mockReturnThis(),
      contains: vi.fn().mockReturnThis(),
      neq: vi.fn().mockResolvedValue({
        data: stagingRows,
        error: null,
      }),
    }),
  } as unknown as ContentClient
}

// ============================================================
// SENARYO 1: Geçerli paket → accepted
// ============================================================

describe("Candidate Batch — Senaryo 1: Geçerli paket", () => {
  it("geçerli paket doğrulanır ve accepted döner", () => {
    const batch = validBatch()
    const result = validateCandidateQuestionBatch(batch)

    expect(result.status).toBe("accepted")
    expect(result.schema_version_valid).toBe(true)
    expect(result.origin_valid).toBe(true)
    expect(result.producer_valid).toBe(true)
    expect(result.question_count).toBe(1)
    expect(result.valid_count).toBe(1)
    expect(result.invalid_count).toBe(0)
    expect(result.duplicate_count).toBe(0)
    expect(result.root_errors).toHaveLength(0)
    expect(result.candidates[0].status).toBe("valid")
  })
})

// ============================================================
// SENARYO 2: Eksik alan → rejected
// ============================================================

describe("Candidate Batch — Senaryo 2: Eksik alanlar", () => {
  it("outcome_code eksikse rejected döner", () => {
    const batch = validBatch([
      validQuestion({ outcome_code: "" }),
    ])
    const result = validateCandidateQuestionBatch(batch)

    expect(result.status).toBe("rejected")
    expect(result.candidates[0].status).toBe("invalid")
    expect(result.candidates[0].errors).toContain("outcome_code_bos_olamaz")
  })

  it("question_text çok kısaysa rejected döner", () => {
    const batch = validBatch([
      validQuestion({ question_text: "Kısa" }),
    ])
    const result = validateCandidateQuestionBatch(batch)

    expect(result.status).toBe("rejected")
    expect(result.candidates[0].status).toBe("invalid")
    expect(result.candidates[0].errors).toContain("question_text_en_az_10_karakter_olmali")
  })

  it("subject_id geçersiz UUID ise rejected döner", () => {
    const batch = validBatch([
      validQuestion({ subject_id: "gecersiz-uuid" }),
    ])
    const result = validateCandidateQuestionBatch(batch)

    expect(result.status).toBe("rejected")
    expect(result.candidates[0].status).toBe("invalid")
    expect(result.candidates[0].errors).toContain("subject_id_gecerli_bir_uuid_olmali")
  })
})

// ============================================================
// SENARYO 3: Yanlış outcome kodu
// ============================================================

describe("Candidate Batch — Senaryo 3: Yanlış outcome kodu", () => {
  it("outcome_code format dışıysa rejected döner", () => {
    const batch = validBatch([
      validQuestion({ outcome_code: "MAT 9 1 1 (boşluklu!)" }),
    ])
    const result = validateCandidateQuestionBatch(batch)

    expect(result.status).toBe("rejected")
    expect(result.candidates[0].status).toBe("invalid")
    expect(result.candidates[0].errors).toContain(
      "outcome_code_sadece_harf_rakam_nokta_ayrac_icerebilir"
    )
  })

  it("origin geçersizse root-level rejected döner", () => {
    const batch = {
      ...validBatch(),
      origin: "pdf_derived" as const,
    }
    const result = validateCandidateQuestionBatch(batch)

    expect(result.status).toBe("rejected")
    expect(result.origin_valid).toBe(false)
    expect(result.root_errors).toContain("origin_yalnizca_curriculum_original_olmali")
  })
})

// ============================================================
// SENARYO 4: Yanlış cevap/çözüm
// ============================================================

describe("Candidate Batch — Senaryo 4: Yanlış cevap/çözüm", () => {
  it("correct_answer E seçeneğini gösteriyor ama E yoksa rejected döner", () => {
    const batch = validBatch([
      validQuestion({
        correct_answer: "E",
        options: { A: "1", B: "2", C: "3", D: "4" },
      }),
    ])
    const result = validateCandidateQuestionBatch(batch)

    expect(result.status).toBe("rejected")
    expect(result.candidates[0].status).toBe("invalid")
    expect(result.candidates[0].errors).toContain("correct_answer_E_ama_secenek_E_bos")
  })

  it("solution.steps boşsa rejected döner", () => {
    const batch = validBatch([
      validQuestion({
        solution: {
          method: "Test",
          steps: [],
          result: "Sonuç",
          correctAnswerJustification: "Gerekçe",
        },
      }),
    ])
    const result = validateCandidateQuestionBatch(batch)

    expect(result.status).toBe("rejected")
    expect(result.candidates[0].status).toBe("invalid")
    expect(result.candidates[0].errors).toContain("solution_steps_en_az_bir_adim_icerirmeli")
  })

  it("yasaklı alan varsa rejected döner", () => {
    const batch = validBatch([
      validQuestion({ source_question_text: "Eski soru" } as unknown as CandidateQuestionV1),
    ])
    const result = validateCandidateQuestionBatch(batch)

    expect(result.status).toBe("rejected")
    expect(result.candidates[0].errors.some((e) => e.startsWith("yasakli_alanlar_tespit_edildi"))).toBe(true)
  })
})

// ============================================================
// SENARYO 5: Tekrar paket
// ============================================================

describe("Candidate Batch — Senaryo 5: Tekrar paket", () => {
  it("aynı normalized soru metni iki kez varsa duplicate döner", () => {
    const q1 = validQuestion({ client_question_id: "q1" })
    const q2 = validQuestion({ client_question_id: "q2" })
    const batch = validBatch([q1, q2])
    const result = validateCandidateQuestionBatch(batch)

    expect(result.status).toBe("partially_accepted")
    expect(result.valid_count).toBe(0)
    expect(result.duplicate_count).toBe(2)
    expect(result.candidates[0].status).toBe("duplicate")
    expect(result.candidates[1].status).toBe("duplicate")
  })
})

// ============================================================
// SENARYO 6: Denetim başarısız
// ============================================================

describe("Candidate Batch — Senaryo 6: Denetim başarısız", () => {
  it("tüm kapılar fail ise rejected döner", async () => {
    const mockRpcResult = {
      batch_id: BATCH_ID,
      staging_ids: [STAGING_ID_1],
      inserted_count: 1,
      invalid_count: 0,
      duplicate_count: 0,
    }

    const client = mockClient(mockRpcResult)
    const gateProvider = createMockGateProvider({
      answer_verification: "fail",
      curriculum_fit: "fail",
      solve_time: "fail",
      originality: "fail",
      question_quality: "fail",
    })

    const orchestrator = new CandidateBatchOrchestrator(client, gateProvider)
    const { audit } = await orchestrator.auditBatch(validBatch())

    expect(audit.status).toBe("partially_completed")
    expect(audit.rejected_count).toBe(1)
    expect(audit.candidates[0].outcome).toBe("rejected")
    expect(audit.candidates[0].blocking_reasons.length).toBeGreaterThan(0)
  })

  it("bazı kapılar pending ise needs_review döner (fail-closed)", async () => {
    const mockRpcResult = {
      batch_id: BATCH_ID,
      staging_ids: [STAGING_ID_1],
      inserted_count: 1,
      invalid_count: 0,
      duplicate_count: 0,
    }

    const client = mockClient(mockRpcResult)
    const gateProvider = createMockGateProvider({
      answer_verification: "pass",
      curriculum_fit: "pending",
      solve_time: "pass",
      originality: "pending",
      question_quality: "pending",
    })

    const orchestrator = new CandidateBatchOrchestrator(client, gateProvider)
    const { audit } = await orchestrator.auditBatch(validBatch())

    expect(audit.candidates[0].outcome).toBe("needs_review")
    expect(audit.review_count).toBe(1)
  })
})

// ============================================================
// SENARYO 7: Hazır ama promotion edilmemiş
// ============================================================

describe("Candidate Batch — Senaryo 7: Hazır ama promotion yok", () => {
  it("tüm kapılar pass ise ready_for_human_review döner, auto_promote YAPILMAZ", async () => {
    const mockRpcResult = {
      batch_id: BATCH_ID,
      staging_ids: [STAGING_ID_1, STAGING_ID_2],
      inserted_count: 2,
      invalid_count: 0,
      duplicate_count: 0,
    }

    const client = mockClient(mockRpcResult)
    const gateProvider = createMockGateProvider({
      answer_verification: "pass",
      curriculum_fit: "pass",
      solve_time: "pass",
      originality: "pass",
      question_quality: "pass",
    })

    const orchestrator = new CandidateBatchOrchestrator(client, gateProvider)
    const { validation, audit } = await orchestrator.auditBatch(validBatch())

    expect(validation.status).toBe("accepted")
    expect(audit.status).toBe("completed")
    expect(audit.ready_count).toBe(2)
    expect(audit.review_count).toBe(0)
    expect(audit.rejected_count).toBe(0)
    expect(audit.automatic_publication_allowed).toBe(false)

    // review_and_promote_ai_question çağrılmamış olmalı
    // (rpc mock'una bakarak doğrula)
    expect(client.rpc).toHaveBeenCalledWith(
      "register_candidate_question_batch",
      expect.any(Object)
    )
    // Tek rpc çağrısı intake içindir; promotion yok
    expect(client.rpc).toHaveBeenCalledTimes(1)
  })

  it("birds aday karışık durumda ise kısmi sonuç döner", async () => {
    const mockRpcResult = {
      batch_id: BATCH_ID,
      staging_ids: [STAGING_ID_1, STAGING_ID_2],
      inserted_count: 2,
      invalid_count: 0,
      duplicate_count: 0,
    }

    const callCount = { n: 0 }
    const client = mockClient(mockRpcResult)
    const gateProvider: GateProvider = {
      async evaluateCandidate(id: string): Promise<GateEvaluationResult[]> {
        callCount.n++
        if (id === STAGING_ID_1) {
          return [
            { gate: "answer_verification", status: "pass" },
            { gate: "curriculum_fit", status: "pass" },
            { gate: "solve_time", status: "pass" },
            { gate: "originality", status: "pass" },
            { gate: "question_quality", status: "pass" },
          ]
        }
        return [
          { gate: "answer_verification", status: "fail", message: "cevap tutarsız" },
          { gate: "curriculum_fit", status: "pass" },
          { gate: "solve_time", status: "pass" },
          { gate: "originality", status: "pass" },
          { gate: "question_quality", status: "pass" },
        ]
      },
    }

    const orchestrator = new CandidateBatchOrchestrator(client, gateProvider)
    const { audit } = await orchestrator.auditBatch(validBatch())

    expect(audit.ready_count).toBe(1)
    expect(audit.rejected_count).toBe(1)
    expect(audit.status).toBe("partially_completed")
    expect(callCount.n).toBe(2)
  })
})
