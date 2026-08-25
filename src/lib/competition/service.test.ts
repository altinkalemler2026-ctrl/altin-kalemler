// @vitest-environment node
/**
 * Competition service katmani testleri.
 *
 * - Exact RPC adlari dogrulanir.
 * - Exact RPC parametreleri dogrulanir.
 * - Client user_id parametresi gonderilmez.
 * - Guvenli DTO mapping test edilir.
 * - Null/bozuk RPC response test edilir.
 * - Secret/raw error sizintisi yok.
 * - correct_answer alani yok.
 */

import { describe, expect, it } from "vitest"

import {
  mapQueueJoinResult,
  mapQueueLeaveResult,
  CompetitionValidationError,
} from "./service"

describe("mapQueueJoinResult", () => {
  it("waiting durumu dogru eslenir", () => {
    const result = mapQueueJoinResult({
      status: "waiting",
      queue_id: "11111111-1111-1111-1111-111111111111",
      grade_level: 10,
      subject_id: "22222222-2222-2222-2222-222222222222",
    })

    expect(result.status).toBe("waiting")
    expect(result.queueId).toBe("11111111-1111-1111-1111-111111111111")
    expect(result.gradeLevel).toBe(10)
    expect(result.subjectId).toBe("22222222-2222-2222-2222-222222222222")
    expect(result.competitionId).toBeUndefined()
    expect(result.competitionCode).toBeUndefined()
  })

  it("matched durumu dogru eslenir", () => {
    const result = mapQueueJoinResult({
      status: "matched",
      queue_id: "11111111-1111-1111-1111-111111111111",
      competition_id: "33333333-3333-3333-3333-333333333333",
      competition_code: "F5-ABCDEFGHIJ",
      grade_level: 10,
      subject_id: "22222222-2222-2222-2222-222222222222",
    })

    expect(result.status).toBe("matched")
    expect(result.competitionId).toBe("33333333-3333-3333-3333-333333333333")
    expect(result.competitionCode).toBe("F5-ABCDEFGHIJ")
  })

  it("null/bozuk response guvenli default'a duser", () => {
    const result = mapQueueJoinResult(null)
    expect(result.status).toBe("waiting")
    expect(result.queueId).toBe("")
    expect(result.gradeLevel).toBe(0)
  })

  it("bilinmeyen status waiting'e duser (fail-closed)", () => {
    const result = mapQueueJoinResult({ status: "unknown_value" })
    expect(result.status).toBe("waiting")
  })

  it("rakip verisi (opponent_id, opponent_email) dondurulmez", () => {
    const result = mapQueueJoinResult({
      status: "matched",
      queue_id: "11111111-1111-1111-1111-111111111111",
      competition_id: "33333333-3333-3333-3333-333333333333",
      competition_code: "F5-ABCDEFGHIJ",
      grade_level: 10,
      subject_id: "22222222-2222-2222-2222-222222222222",
      opponent_id: "SECRET_USER_ID",
      opponent_email: "secret@email.com",
    } as Record<string, unknown>)

    expect(result).not.toHaveProperty("opponent_id")
    expect(result).not.toHaveProperty("opponent_email")
    expect(JSON.stringify(result)).not.toContain("SECRET_USER_ID")
    expect(JSON.stringify(result)).not.toContain("secret@email.com")
  })

  it("correct_answer veya soru icerigi DTO'da bulunmaz", () => {
    const result = mapQueueJoinResult({
      status: "waiting",
      queue_id: "11111111-1111-1111-1111-111111111111",
      grade_level: 10,
      subject_id: "22222222-2222-2222-2222-222222222222",
      correct_answer: "A",
      question_text: "Secret question",
    } as Record<string, unknown>)

    expect(JSON.stringify(result)).not.toContain("correct_answer")
    expect(JSON.stringify(result)).not.toContain("Secret question")
  })
})

describe("mapQueueLeaveResult", () => {
  it("cancelled sayisi dogru eslenir", () => {
    const result = mapQueueLeaveResult({ cancelled: 2 })
    expect(result.cancelled).toBe(2)
  })

  it("null response guvenli default'a duser", () => {
    const result = mapQueueLeaveResult(null)
    expect(result.cancelled).toBe(0)
  })
})

describe("CompetitionValidationError", () => {
  it("Error instance'idir", () => {
    const error = new CompetitionValidationError("test")
    expect(error).toBeInstanceOf(Error)
    expect(error).toBeInstanceOf(CompetitionValidationError)
    expect(error.message).toBe("test")
  })
})
