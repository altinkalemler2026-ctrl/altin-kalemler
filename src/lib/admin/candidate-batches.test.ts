// @vitest-environment node
/**
 * Faz 19 — Aday Yükleme Paketleri okuyucu testleri (120 RPC'leri).
 *
 * - hasCandidateBatchReadPermission: ai.manage VEYA questions.approve
 *   true ise izin; her ikisinde de hata/false → fail-closed reddet.
 * - DTO allowlist: ham RPC çıktısı keyfi alan taşımaz; her alan tip
 *   kontrolünden geçer; gate özetleri yalnız bilinen anahtarları okur.
 * - Liste hata durumu ayrıdır; ham RPC hata metni asla taşınmaz.
 * - Detay: not-found ok+null'a, diğer hatalar error'a düşer.
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

import {
  hasCandidateBatchReadPermission,
  listCandidateQuestionBatches,
  getCandidateBatchDetail,
  getCandidateBatchOperationStatus,
  mapCandidateBatchListItem,
  mapCandidate,
  mapCandidatePreview,
  mapCandidateGateRun,
  mapOperationGateCounts,
  CANDIDATE_BATCH_PAGE_SIZE,
} from "./candidate-batches"

const BATCH_UUID = "7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3"

const FULL_BATCH_ROW = {
  batch_id: BATCH_UUID,
  batch_key: "AK-2026-0001",
  schema_version: "https://altyapı.bilgi/candidate-batch.schema.json",
  origin: "internal-ai",
  producer_id: "producer-x",
  producer_model: "gpt-large",
  status: "received",
  counts: {
    total_items: 10,
    valid_items: 8,
    invalid_items: 2,
    inserted_items: 0,
    duplicate_items: 1,
  },
  validation_summary: "2 soru geçersiz",
  created_at: "2026-09-01T10:00:00.000Z",
  updated_at: "2026-09-01T10:30:00.000Z",
  bazuka: "SIZMAYAN-ALAN",
}

describe("hasCandidateBatchReadPermission", () => {
  it("ai.manage true ise izin var", async () => {
    const rpcMock = vi
      .fn()
      .mockResolvedValueOnce({ data: true, error: null })
      .mockResolvedValueOnce({ data: false, error: null })
    createClientMock.mockImplementation(async () => ({ rpc: rpcMock }))
    expect(await hasCandidateBatchReadPermission()).toBe(true)
    const calls = rpcMock.mock.calls
    expect(calls[0]?.[0]).toBe("teacher_review_admin_has_permission")
    expect(calls[0]?.[1]).toEqual({ p_permission_code: "ai.manage" })
    expect(calls[1]?.[1]).toEqual({ p_permission_code: "questions.approve" })
  })

  it("questions.approve true ise izin var", async () => {
    const rpcMock = vi
      .fn()
      .mockResolvedValueOnce({ data: false, error: null })
      .mockResolvedValueOnce({ data: true, error: null })
    createClientMock.mockImplementation(async () => ({ rpc: rpcMock }))
    expect(await hasCandidateBatchReadPermission()).toBe(true)
  })

  it("her iki kod false ise fail-closed", async () => {
    const rpcMock = vi
      .fn()
      .mockResolvedValue({ data: false, error: null })
    createClientMock.mockImplementation(async () => ({ rpc: rpcMock }))
    expect(await hasCandidateBatchReadPermission()).toBe(false)
  })

  it("RPC hatasında fail-closed", async () => {
    const rpcMock = vi
      .fn()
      .mockResolvedValue({ data: null, error: { message: "db down" } })
    createClientMock.mockImplementation(async () => ({ rpc: rpcMock }))
    expect(await hasCandidateBatchReadPermission()).toBe(false)
  })
})

describe("mapCandidateBatchListItem — DTO allowlist", () => {
  it("bilinen alanları doğru tiplerle eşler, keyfi alan taşımaz", () => {
    const item = mapCandidateBatchListItem(FULL_BATCH_ROW)
    expect(item.batchId).toBe(BATCH_UUID)
    expect(item.batchKey).toBe("AK-2026-0001")
    expect(item.origin).toBe("internal-ai")
    expect(item.producerModel).toBe("gpt-large")
    expect(item.status).toBe("received")
    expect(item.counts.totalItems).toBe(10)
    expect(item.counts.duplicateItems).toBe(1)
    expect(JSON.stringify(item)).not.toContain("SIZMAYAN-ALAN")
  })

  it("eksik alanlar güvenli varsayılan alır", () => {
    const item = mapCandidateBatchListItem({})
    expect(item.batchId).toBe("")
    expect(item.batchKey).toBe("")
    expect(item.schemaVersion).toBeNull()
    expect(item.counts.totalItems).toBeNull()
    expect(item.createdAt).toBeNull()
    expect(item.validationSummary).toBeNull()
  })
})

describe("mapCandidatePreview — DTO allowlist", () => {
  it("yalnız A–E seçenekleri okunur; keyfi alan taşınmaz", () => {
    const preview = mapCandidatePreview({
      staging_status: "staged",
      question_text: "2+2 kaçtır?",
      options: {
        A: "3",
        B: "4",
        C: "5",
        D: null,
        E: "6",
        F: "YEDİNCİ-SEÇENEK",
      },
      proposed_correct_answer: "B",
      proposed_solve_time_seconds: 30,
      solution: "4'tür.",
      gizli: "SIZMAZ",
    })
    expect(preview.questionText).toBe("2+2 kaçtır?")
    expect(preview.options.A).toBe("3")
    expect(preview.options.E).toBe("6")
    expect(preview.options.B).toBe("4")
    expect(preview.proposedSolveTimeSeconds).toBe(30)
    expect(preview.solution).toBe("4'tür.")
    expect(JSON.stringify(preview)).not.toContain("YEDİNCİ-SEÇENEK")
    expect(JSON.stringify(preview)).not.toContain("SIZMAZ")
    expect(Object.keys(preview.options)).toEqual(["A", "B", "C", "D", "E"])
  })

  it("sözel sayı alanı null'a düşer (tip güvenli)", () => {
    const preview = mapCandidatePreview({ proposed_solve_time_seconds: "30" })
    expect(preview.proposedSolveTimeSeconds).toBeNull()
  })
})

describe("mapCandidateGateRun — özet allowlist", () => {
  it("yalnız izinli anahtarları taşır; bilinmeyen anahtar atlanır", () => {
    const gate = mapCandidateGateRun("answerVerification", {
      consensus_status: "consensus",
      consensus_answer: "B",
      minimum_confidence: 0.9,
      solver_1_confidence: 0.95,
      human_decision: null,
      created_inside_db: "atla",
      raw: { secret: "x" },
    })
    expect(gate).not.toBeNull()
    const keys = gate!.fields.map((f) => f.key)
    expect(keys).toEqual([
      "consensus_status",
      "consensus_answer",
      "minimum_confidence",
      "solver_1_confidence",
      "human_decision",
    ])
    expect(JSON.stringify(gate)).not.toContain("atla")
    expect(JSON.stringify(gate)).not.toContain("secret")
    expect(gate!.fields.find((f) => f.key === "minimum_confidence")?.value).toBe(
      0.9
    )
    expect(gate!.fields.find((f) => f.key === "human_decision")?.value).toBeNull()
  })

  it("readiness'te diziler string dizisi olarak taşınır", () => {
    const gate = mapCandidateGateRun("readiness", {
      readiness_status: "not_ready",
      blocking_reasons: ["eksik çözüm"],
      readiness_score: 12,
    })
    expect(gate!.fields.find((f) => f.key === "blocking_reasons")?.value).toEqual(
      ["eksik çözüm"]
    )
    expect(gate!.fields.find((f) => f.key === "readiness_score")?.value).toBe(12)
  })

  it("null/geçersiz girdi null döndürür", () => {
    expect(mapCandidateGateRun("finalReview", null)).toBeNull()
    expect(mapCandidateGateRun("finalReview", "x")).toBeNull()
    expect(mapCandidateGateRun("finalReview", [])).toBeNull()
  })
})

describe("mapCandidate — DTO allowlist", () => {
  it("preview/gates alanlarını izinli DTO'ya eşler", () => {
    const candidate = mapCandidate({
      candidate_index: 0,
      client_question_id: "c-1",
      validation_status: "passed",
      validation_errors: [],
      validation_warnings: ["yavaş"],
      staging_question_id: "staging-1",
      preview: {
        question_text: "Soru?",
        options: { A: "1", B: "2" },
        solution: "cevap",
      },
      validation_results: [
        {
          validator_type: "schema",
          validation_type: "structure",
          result: "valid",
          score: 1,
        },
      ],
      review_queue: [
        { reason_code: "manual", priority: "high", status: "pending" },
      ],
      gates: {
        answer_verification: { consensus_status: "consensus" },
        unknown_gate: { whatever: 1 },
      },
    })
    expect(candidate.candidateIndex).toBe(0)
    expect(candidate.validationWarnings).toEqual(["yavaş"])
    expect(candidate.preview?.questionText).toBe("Soru?")
    expect(candidate.validationResults[0]?.validatorType).toBe("schema")
    expect(candidate.reviewQueue[0]?.reasonCode).toBe("manual")
    expect(candidate.gates.answerVerification?.fields[0]?.key).toBe(
      "consensus_status"
    )
    expect(JSON.stringify(candidate)).not.toContain("unknown_gate")
  })

  it("staging yokken preview null olur", () => {
    const candidate = mapCandidate({
      candidate_index: 1,
      staging_question_id: null,
      preview: null,
    })
    expect(candidate.preview).toBeNull()
    expect(candidate.candidateIndex).toBe(1)
  })
})

describe("listCandidateQuestionBatches", () => {
  beforeEach(() => {
    createClientMock.mockReset()
  })

  it("RPC items+total'ı DTO'ya eşler ve sayfametreği hesap eder", async () => {
    const rpcMock = vi.fn().mockResolvedValue({
      data: {
        items: [FULL_BATCH_ROW, { batch_id: "x", batch_key: "AK-0002" }],
        total: 26,
        limit: CANDIDATE_BATCH_PAGE_SIZE,
        offset: 0,
      },
      error: null,
    })
    createClientMock.mockImplementation(async () => ({ rpc: rpcMock }))
    const result = await listCandidateQuestionBatches(1)
    expect(result.status).toBe("ok")
    expect(result.items).toHaveLength(2)
    expect(result.total).toBe(26)
    expect(result.totalPages).toBe(2)
    expect(result.page).toBe(1)
    expect(rpcMock.mock.calls[0]?.[0]).toBe(
      "list_candidate_question_batches"
    )
    expect(rpcMock.mock.calls[0]?.[1]).toEqual({
      p_limit: CANDIDATE_BATCH_PAGE_SIZE,
      p_offset: 0,
    })
  })

  it("sayfa 2 offset'i PAGE_SIZE kadar kaydırır", async () => {
    const rpcMock = vi.fn().mockResolvedValue({
      data: { items: [], total: 50, limit: CANDIDATE_BATCH_PAGE_SIZE, offset: 25 },
      error: null,
    })
    createClientMock.mockImplementation(async () => ({ rpc: rpcMock }))
    await listCandidateQuestionBatches(2)
    expect(rpcMock.mock.calls[0]?.[1]).toEqual({
      p_limit: CANDIDATE_BATCH_PAGE_SIZE,
      p_offset: CANDIDATE_BATCH_PAGE_SIZE,
    })
  })

  it("sayfadan küçük 1'e çekilir", async () => {
    const rpcMock = vi.fn().mockResolvedValue({
      data: { items: [], total: 0, limit: CANDIDATE_BATCH_PAGE_SIZE, offset: 0 },
      error: null,
    })
    createClientMock.mockImplementation(async () => ({ rpc: rpcMock }))
    await listCandidateQuestionBatches(0)
    expect(rpcMock.mock.calls[0]?.[1]).toEqual({
      p_limit: CANDIDATE_BATCH_PAGE_SIZE,
      p_offset: 0,
    })
  })

  it("RPC hatası status:'error' döner; ham hata taşınmaz", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({
        data: null,
        error: { message: "Aday paket listesi icin ai.manage veya questions.approve yetkisi gerekli." },
      }),
    }))
    const result = await listCandidateQuestionBatches(1)
    expect(result.status).toBe("error")
    expect(result.items).toEqual([])
    expect(JSON.stringify(result)).not.toContain("yetkisi")
  })

  it("data null ise boş ok sonuç döner", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({ data: null, error: null }),
    }))
    const result = await listCandidateQuestionBatches(1)
    expect(result.status).toBe("ok")
    expect(result.items).toEqual([])
  })
})

describe("getCandidateBatchDetail", () => {
  beforeEach(() => {
    createClientMock.mockReset()
  })

  it("batch + candidates RPC çıktısını DTO'ya eşler", async () => {
    const rpcMock = vi.fn().mockResolvedValue({
      data: {
        batch: FULL_BATCH_ROW,
        candidates: [
          {
            candidate_index: 0,
            client_question_id: "c-1",
            validation_status: "passed",
            validation_errors: [],
            validation_warnings: [],
            staging_question_id: "staging-1",
            preview: { question_text: "Soru?", solution: "çözüm" },
            validation_results: [],
            review_queue: [],
            gates: { readiness: { readiness_status: "ready" } },
          },
        ],
      },
      error: null,
    })
    createClientMock.mockImplementation(async () => ({ rpc: rpcMock }))
    const result = await getCandidateBatchDetail(BATCH_UUID)
    expect(result.status).toBe("ok")
    expect(result.item?.batch.batchKey).toBe("AK-2026-0001")
    expect(result.item?.candidates).toHaveLength(1)
    expect(result.item?.candidates[0]?.preview?.questionText).toBe("Soru?")
    expect(rpcMock.mock.calls[0]?.[0]).toBe(
      "get_candidate_question_batch_detail"
    )
    expect(rpcMock.mock.calls[0]?.[1]).toEqual({ p_batch_id: BATCH_UUID })
  })

  it("bulunamadı hatası ok+null'a düşer (ayrı durum)", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({
        data: null,
        error: { message: "Aday paketi bulunamadi." },
      }),
    }))
    const result = await getCandidateBatchDetail(BATCH_UUID)
    expect(result.status).toBe("ok")
    expect(result.item).toBeNull()
  })

  it("diğer RPC hataları error'a düşer; ham hata taşınmaz", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({
        data: null,
        error: { message: "connection reset" },
      }),
    }))
    const result = await getCandidateBatchDetail(BATCH_UUID)
    expect(result.status).toBe("error")
    expect(result.item).toBeNull()
    expect(JSON.stringify(result)).not.toContain("connection reset")
  })

  it("anomali dönüşler error'a düşer", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({ data: null, error: null }),
    }))
    expect((await getCandidateBatchDetail(BATCH_UUID)).status).toBe("error")

    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({ data: "junk", error: null }),
    }))
    expect((await getCandidateBatchDetail(BATCH_UUID)).status).toBe("error")

    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({
        data: { batch: null, candidates: [] },
        error: null,
      }),
    }))
    expect((await getCandidateBatchDetail(BATCH_UUID)).status).toBe("error")
  })
})

describe("getCandidateBatchOperationStatus (Faz 20)", () => {
  beforeEach(() => {
    createClientMock.mockReset()
  })

  const STATUS_ROW = {
    batch: {
      batch_id: BATCH_UUID,
      batch_key: "AK-2026-0001",
      status: "validating",
      counts: {
        total_items: 3,
        valid_items: 2,
        invalid_items: 1,
        inserted_items: 2,
        duplicate_items: 0,
      },
      created_at: "2026-09-01T10:00:00.000Z",
      updated_at: "2026-09-01T10:30:00.000Z",
      error_data: { some: "HAM-HATA" },
      raw_payload: { some: "HAM-PAYLOAD" },
    },
    phase: {
      candidate_counts: {
        pending: 0,
        valid: 2,
        invalid: 1,
        duplicate: 0,
        inserted: 2,
        failed: 0,
      },
    },
    gates: {
      answer_verification: {
        total: 2,
        waiting_solver_1: 2,
        waiting_solver_2: 0,
        needs_human_review: 0,
        verified: 0,
        rejected: 0,
        other: 0,
      },
      curriculum_fit: {
        total: 1,
        waiting_reviewer_1: 1,
        waiting_reviewer_2: 0,
        verified: 0,
        rejected: 0,
        other: 0,
      },
      solve_time_verification: {
        total: 1,
        waiting_reviewer_1: 1,
        waiting_reviewer_2: 0,
        verified: 0,
        rejected: 0,
        other: 0,
      },
      originality_verification: {
        total: 0,
        waiting_reviewer_1: 0,
        waiting_reviewer_2: 0,
        verified: 0,
        blocked: 0,
        rejected: 0,
        other: 0,
      },
      question_quality: {
        total: 0,
        waiting_reviewer_1: 0,
        waiting_reviewer_2: 0,
        verified: 0,
        rejected: 0,
        other: 0,
      },
      readiness: {
        total: 0,
        not_ready: 0,
        ready_for_human_review: 0,
        human_review_required: 0,
        blocked: 0,
        rejected: 0,
        already_promoted: 0,
      },
      final_review: {
        total: 0,
        approve: 0,
        request_changes: 0,
        reject: 0,
      },
    },
    provider: {
      has_batch_error_data: true,
      candidate_validation_error_count: 1,
    },
    retry: {
      supported: false,
      reason_key: "gate_retry_not_supported",
    },
  }

  it("işlem durumu RPC çıktısını allowlist DTO'ya eşler", async () => {
    const rpcMock = vi.fn().mockResolvedValue({ data: STATUS_ROW, error: null })
    createClientMock.mockImplementation(async () => ({ rpc: rpcMock }))

    const result = await getCandidateBatchOperationStatus(BATCH_UUID)

    expect(result.status).toBe("ok")
    expect(result.item?.batch.batchKey).toBe("AK-2026-0001")
    expect(result.item?.batch.status).toBe("validating")
    expect(result.item?.gates.answerVerification.waitingSolver1).toBe(2)
    expect(result.item?.gates.curriculumFit.waitingReviewer1).toBe(1)
    expect(result.item?.provider.hasBatchErrorData).toBe(true)
    expect(result.item?.provider.candidateValidationErrorCount).toBe(1)
    expect(result.item?.retry.supported).toBe(false)
    expect(result.item?.retry.reasonKey).toBe("gate_retry_not_supported")
    expect(rpcMock.mock.calls[0]?.[0]).toBe(
      "get_candidate_question_batch_operation_status"
    )
    expect(rpcMock.mock.calls[0]?.[1]).toEqual({ p_batch_id: BATCH_UUID })
  })

  it("DTO dışı keyfi/raw alan taşınmaz", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({ data: STATUS_ROW, error: null }),
    }))
    const result = await getCandidateBatchOperationStatus(BATCH_UUID)
    const json = JSON.stringify(result)
    expect(json).not.toContain("HAM-HATA")
    expect(json).not.toContain("HAM-PAYLOAD")
    expect(json).not.toContain("error_data")
    expect(json).not.toContain("raw_payload")
  })

  it("bulunamadı hatası ok+null'a düşer", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({
        data: null,
        error: { message: "Aday paketi bulunamadi." },
      }),
    }))
    const result = await getCandidateBatchOperationStatus(BATCH_UUID)
    expect(result.status).toBe("ok")
    expect(result.item).toBeNull()
  })

  it("diğer RPC hataları error'a düşer; ham hata taşınmaz", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({
        data: null,
        error: { message: "connection reset" },
      }),
    }))
    const result = await getCandidateBatchOperationStatus(BATCH_UUID)
    expect(result.status).toBe("error")
    expect(JSON.stringify(result)).not.toContain("connection reset")
  })

  it("oluşturulamayan anomali dönüşler error'a düşer", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({ data: null, error: null }),
    }))
    expect((await getCandidateBatchOperationStatus(BATCH_UUID)).status).toBe(
      "error"
    )

    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({ data: "junk", error: null }),
    }))
    expect((await getCandidateBatchOperationStatus(BATCH_UUID)).status).toBe(
      "error"
    )
  })
})

describe("mapOperationGateCounts (Faz 20)", () => {
  it("yalnız bilinen anahtarları okur; keyfi alan sızmaz", () => {
    const counts = mapOperationGateCounts({
      total: 5,
      waiting_reviewer_1: 2,
      waiting_reviewer_2: 1,
      verified: 2,
      rejected: 0,
      bazuka: 99,
      api_key: "GIZLI",
    })
    expect(counts.total).toBe(5)
    expect(counts.waitingReviewer1).toBe(2)
    expect(counts.waitingReviewer2).toBe(1)
    expect(counts.verified).toBe(2)
    expect(counts.rejected).toBe(0)
    expect(JSON.stringify(counts)).not.toContain("bazuka")
    expect(JSON.stringify(counts)).not.toContain("GIZLI")
  })

  it("geçersiz tip null olur", () => {
    const counts = mapOperationGateCounts({ total: "abc", verified: 3 })
    expect(counts.total).toBeNull()
    expect(counts.verified).toBe(3)
  })
})