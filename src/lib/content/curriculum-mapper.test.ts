/**
 * curriculum-mapper testleri.
 *
 * - Tek güvenilir aday → approved.
 * - Birden çok aday / düşük güven → ambiguous (insan incelemesine gider).
 * - Aday yok → no_candidates (fail-closed; uydurma yok).
 * - Sabit eşik MIN_MAPPING_CONFIDENCE değiştirilmeden değerlendirme
 *   deterministik kalır.
 */

import { describe, expect, it, vi } from "vitest"

import {
  evaluateMappingCandidates,
  evaluateQuestionMappings,
  mapMappingCandidate,
  MIN_MAPPING_CONFIDENCE,
  MappingValidationError,
  type MappingClient,
} from "./curriculum-mapper"

const QID = "11111111-1111-4111-8111-111111111111"
const TOPIC_A = "22222222-2222-4222-8222-111111111111"
const TOPIC_B = "22222222-2222-4222-8222-222222222222"
const OUTCOME_X = "33333333-3333-4333-8333-333333333333"

function candidate(overrides: Partial<Parameters<typeof evaluateMappingCandidates>[1][number]> = {}) {
  return {
    topicId: TOPIC_A,
    outcomeId: null,
    confidenceScore: 0.9,
    mappingSource: "ai_suggested" as const,
    reviewStatus: "pending" as const,
    notes: null,
    ...overrides,
  }
}

describe("evaluateMappingCandidates", () => {
  it("tek güvenilir aday onaylanır", () => {
    const result = evaluateMappingCandidates(QID, [candidate()])
    expect(result.status).toBe("approved")
    expect(result.mapping?.topicId).toBe(TOPIC_A)
    expect(result.mapping?.confidenceScore).toBe(0.9)
  })

  it("güven eşiğinin altında tek aday → ambiguous (insan incelemesi)", () => {
    const result = evaluateMappingCandidates(QID, [
      candidate({ confidenceScore: MIN_MAPPING_CONFIDENCE - 0.1 }),
    ])
    expect(result.status).toBe("ambiguous")
    expect(result.ambiguity?.ambiguityDetected).toBe(true)
    expect(result.ambiguity?.reason).toBe("hicbir_aday_guven_esigini_gecmiyor")
    expect(MIN_MAPPING_CONFIDENCE).toBeGreaterThan(0)
    expect(MIN_MAPPING_CONFIDENCE).toBeLessThan(1)
  })

  it("birden çok güvenilir aday → ambiguous", () => {
    const result = evaluateMappingCandidates(QID, [
      candidate({ topicId: TOPIC_A }),
      candidate({ topicId: TOPIC_B }),
    ])
    expect(result.status).toBe("ambiguous")
    expect(result.ambiguity?.reason).toBe("birden_fazla_aday_method")
    expect(result.mapping).toBeNull()
  })

  it("aday listesi boşsa no_candidates döner (uydurma yok)", () => {
    const result = evaluateMappingCandidates(QID, [])
    expect(result.status).toBe("no_candidates")
    expect(result.mapping).toBeNull()
    expect(result.ambiguity).toBeNull()
  })

  it("geçersiz hedef (iki taraf boş) aday sayılmaz", () => {
    const result = evaluateMappingCandidates(QID, [
      candidate({ topicId: null, outcomeId: null }),
    ])
    expect(result.status).toBe("no_candidates")
  })

  it("güven 0-1 dışında aday elenir", () => {
    const result = evaluateMappingCandidates(QID, [
      candidate({ confidenceScore: 1.4 }),
    ])
    expect(result.status).toBe("no_candidates")
  })

  it("geçersiz UUID reddedilir", () => {
    expect(() => evaluateMappingCandidates("bozuk", [candidate()])).toThrow(
      MappingValidationError
    )
  })
})

describe("mapMappingCandidate — ham satır allowlist", () => {
  it("geçerli satır içeriği DTO'ya çevirir", () => {
    const mapped = mapMappingCandidate({
      topic_id: TOPIC_A,
      outcome_id: null,
      confidence_score: 0.85,
      mapping_source: "manual",
      review_status: "approved",
      notes: "MEB kazanım listesinden",
    })
    expect(mapped?.topicId).toBe(TOPIC_A)
    expect(mapped?.confidenceScore).toBe(0.85)
    expect(mapped?.reviewStatus).toBe("approved")
  })

  it("iki taraf da boş satır null döner", () => {
    expect(
      mapMappingCandidate({ topic_id: null, outcome_id: null, confidence_score: 0.8 })
    ).toBeNull()
  })

  it("geçersiz güven null döner", () => {
    expect(
      mapMappingCandidate({
        topic_id: TOPIC_A,
        outcome_id: null,
        confidence_score: "yüksek",
      })
    ).toBeNull()
  })

  it("bilinmeyen mapping_source güvenli şekilde reddedilir (fail-closed)", () => {
    expect(
      mapMappingCandidate({
        topic_id: TOPIC_A,
        outcome_id: null,
        confidence_score: 0.8,
        mapping_source: "hack",
        review_status: "pending",
      })
    ).toBeNull()
  })

  it("auto_matched değerini korur", () => {
    const mapped = mapMappingCandidate({
      topic_id: TOPIC_A,
      outcome_id: null,
      confidence_score: 0.8,
      mapping_source: "auto_matched",
      review_status: "pending",
    })
    expect(mapped?.mappingSource).toBe("auto_matched")
  })

  it("bozuk/garbage girdi null döner", () => {
    expect(mapMappingCandidate(null)).toBeNull()
    expect(mapMappingCandidate("garbage")).toBeNull()
  })
})

describe("evaluateQuestionMappings — client okuma", () => {
  function buildClient(rows: Array<Record<string, unknown>>) {
    const from = vi.fn().mockImplementation((table: string) => {
      const selected = rows.filter((row) =>
        table === "question_curriculum_mappings"
          ? row.table === "topic"
          : row.table === "outcome"
      )
      return {
        select: () => ({
          eq: () =>
            Promise.resolve({
              data: selected,
              error: null,
            }),
        }),
      }
    })
    return { client: { from } as unknown as MappingClient, from }
  }

  it("iki tablodan gelen adayları birleştirip değerlendirir", async () => {
    const { client, from } = buildClient([
      { table: "topic", topic_id: TOPIC_A, outcome_id: null, confidence_score: 0.91, mapping_source: "auto_matched", review_status: "pending", notes: null },
      { table: "outcome", topic_id: null, outcome_id: OUTCOME_X, confidence_score: 0.9, mapping_source: "ai_suggested", review_status: "pending", notes: null },
    ])
    const result = await evaluateQuestionMappings(client, QID)

    expect(from).toHaveBeenCalledTimes(2)
    expect(result.status).toBe("ambiguous")
    expect(result.ambiguity?.candidates).toHaveLength(2)
  })

  it("tek kesin aday varsa approved döner", async () => {
    const { client } = buildClient([
      { table: "topic", topic_id: TOPIC_A, outcome_id: null, confidence_score: 0.92, mapping_source: "manual", review_status: "approved", notes: null },
    ])
    const result = await evaluateQuestionMappings(client, QID)
    expect(result.status).toBe("approved")
  })
})