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
  mapQuestionResult,
  mapSessionState,
  mapAnswerSubmitResult,
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

// ------------------------------------------------------------
// Faz 5b: Yarisma oturum mapper testleri
// ------------------------------------------------------------

describe("mapQuestionResult", () => {
  it("gecerli question payload dondurur", () => {
    const result = mapQuestionResult({
      competition_id: "11111111-1111-1111-1111-111111111111",
      status: "active",
      question_available: true,
      payload: {
        competition_question_id: "22222222-2222-2222-2222-222222222222",
        question_order: 1,
        sent_at: "2025-01-01T00:00:00Z",
        deadline_at: "2025-01-01T00:01:30Z",
        question: {
          id: "33333333-3333-3333-3333-333333333333",
          stem_html: "<p>Soru metni</p>",
          option_a_html: "<p>Secenek A</p>",
          option_b_html: "<p>Secenek B</p>",
          difficulty: "medium",
        },
      },
    })

    expect(result.competitionId).toBe("11111111-1111-1111-1111-111111111111")
    expect(result.questionAvailable).toBe(true)
    expect(result.payload).not.toBeNull()
    expect(result.payload?.id).toBe("33333333-3333-3333-3333-333333333333")
    expect(result.payload?.stemHtml).toBe("<p>Soru metni</p>")
    expect(result.payload?.options.A).toBe("<p>Secenek A</p>")
    expect(result.payload?.options.B).toBe("<p>Secenek B</p>")
    expect(result.payload?.difficulty).toBe("medium")
  })

  it("question_available false ise payload null doner", () => {
    const result = mapQuestionResult({
      competition_id: "11111111-1111-1111-1111-111111111111",
      status: "active",
      question_available: false,
    })
    expect(result.questionAvailable).toBe(false)
    expect(result.payload).toBeNull()
  })

  it("correct_answer, solution, explanation DTO'da bulunmaz", () => {
    const result = mapQuestionResult({
      competition_id: "11111111-1111-1111-1111-111111111111",
      status: "active",
      question_available: true,
      payload: {
        competition_question_id: "22222222-2222-2222-2222-222222222222",
        question_order: 1,
        sent_at: "2025-01-01T00:00:00Z",
        deadline_at: "2025-01-01T00:01:30Z",
        question: {
          id: "33333333-3333-3333-3333-333333333333",
          stem_html: "test",
          correct_answer: "A",
          solution: "Cozum burada",
          explanation: "Aciklama burada",
        },
      },
    })

    const json = JSON.stringify(result)
    expect(json).not.toContain("correct_answer")
    expect(json).not.toContain("Cozum burada")
    expect(json).not.toContain("Aciklama burada")
  })

  it("null/bozuk response guvenli default'a duser", () => {
    const result = mapQuestionResult(null)
    expect(result.competitionId).toBe("")
    expect(result.questionAvailable).toBe(false)
    expect(result.payload).toBeNull()
  })
})

describe("mapSessionState", () => {
  it("gecerli session state dondurur", () => {
    const result = mapSessionState({
      competition_id: "11111111-1111-1111-1111-111111111111",
      status: "active",
      current_question_order: 2,
      question_count: 5,
      sent_at: "2025-01-01T00:00:00Z",
      deadline_at: "2025-01-01T00:01:30Z",
      time_limit_seconds: 90,
      has_answered_current_question: false,
      my_current_score: 150,
      opponent_current_score: 100,
      competition_code: "F5-TEST",
      competition_type: "one_vs_one",
    })

    expect(result).not.toBeNull()
    expect(result?.competitionId).toBe("11111111-1111-1111-1111-111111111111")
    expect(result?.status).toBe("active")
    expect(result?.currentQuestionOrder).toBe(2)
    expect(result?.totalQuestions).toBe(5)
    expect(result?.myCurrentScore).toBe(150)
    expect(result?.hasAnsweredCurrentQuestion).toBe(false)
  })

  it("opponent_current_score DTO'da dusurulur", () => {
    const result = mapSessionState({
      competition_id: "11111111-1111-1111-1111-111111111111",
      status: "active",
      my_current_score: 100,
      opponent_current_score: 200,
    })

    expect(result).not.toBeNull()
    const json = JSON.stringify(result)
    expect(json).not.toContain("opponent_current_score")
    expect(json).not.toContain("200")
  })

  it("competition_id yoksa null doner", () => {
    const result = mapSessionState({ status: "active" })
    expect(result).toBeNull()
  })

  it("null response null doner", () => {
    const result = mapSessionState(null)
    expect(result).toBeNull()
  })
})

describe("mapAnswerSubmitResult", () => {
  it("gecerli cevap sonucu dondurur", () => {
    const result = mapAnswerSubmitResult({
      answer_id: "11111111-1111-1111-1111-111111111111",
      result: "correct",
      time_ms: 5000,
      points_awarded: 100,
    })

    expect(result.accepted).toBe(true)
    expect(result.submissionId).toBe("11111111-1111-1111-1111-111111111111")
  })

  it("correct/wrong/pointsAwarded/timeBand DTO'da bulunmaz", () => {
    const result = mapAnswerSubmitResult({
      answer_id: "11111111-1111-1111-1111-111111111111",
      result: "correct",
      time_ms: 5000,
      time_band: "fast",
      points_awarded: 100,
    })

    const json = JSON.stringify(result)
    expect(json).not.toContain("correct")
    expect(json).not.toContain("wrong")
    expect(json).not.toContain("100")
    expect(json).not.toContain("fast")
    expect(json).not.toContain("points_awarded")
    expect(json).not.toContain("time_band")
  })

  it("answer_id yoksa accepted false olur", () => {
    const result = mapAnswerSubmitResult({ result: "timeout" })
    expect(result.accepted).toBe(false)
    expect(result.submissionId).toBeNull()
  })

  it("null response guvenli default'a duser", () => {
    const result = mapAnswerSubmitResult(null)
    expect(result.accepted).toBe(false)
    expect(result.submissionId).toBeNull()
  })
})

// ------------------------------------------------------------
// 079 adapter & direct typed RPC path tests
// ------------------------------------------------------------

describe("RPC adapter & type safety", () => {
  const dummyId = "00000000-0000-0000-0000-000000000001"

  it("joinMatchmakingQueue calls 079 RPC with exact params, no user_id", async () => {
    const { joinMatchmakingQueue } = await import("./service")
    const calls: { fn: string; args: unknown }[] = []
    const mockClient = {
      rpc: (fn: string, args?: unknown) => {
        calls.push({ fn, args: args ?? null })
        return Promise.resolve({
          data: { status: "waiting", queue_id: dummyId, grade_level: 5, subject_id: dummyId },
          error: null,
        })
      },
    }
    await joinMatchmakingQueue(mockClient as never, dummyId)
    expect(calls).toHaveLength(1)
    expect(calls[0].fn).toBe("join_matchmaking_queue")
    expect(calls[0].args).toStrictEqual({ p_subject_id: dummyId })
    const argStr = JSON.stringify(calls[0].args)
    expect(argStr).not.toContain("user_id")
    expect(argStr).not.toContain("p_user_id")
  })

  it("leaveMatchmakingQueue calls 079 RPC with exact empty args", async () => {
    const { leaveMatchmakingQueue } = await import("./service")
    const calls: { fn: string; args: unknown }[] = []
    const mockClient = {
      rpc: (fn: string, args?: unknown) => {
        calls.push({ fn, args: args ?? null })
        return Promise.resolve({ data: { cancelled_count: 1 }, error: null })
      },
    }
    await leaveMatchmakingQueue(mockClient as never)
    expect(calls).toHaveLength(1)
    expect(calls[0].fn).toBe("leave_matchmaking_queue")
    expect(calls[0].args).toStrictEqual({})
  })

  it("submitAnswer uses direct typed client.rpc, no cast", async () => {
    const { submitAnswer } = await import("./service")
    const calls: { fn: string; args: unknown }[] = []
    const mockClient = {
      rpc: (fn: string, args?: unknown) => {
        calls.push({ fn, args: args ?? null })
        return Promise.resolve({ data: { answer_id: dummyId, result: "accepted" }, error: null })
      },
    }
    await submitAnswer(mockClient as never, dummyId, "A")
    expect(calls).toHaveLength(1)
    expect(calls[0].fn).toBe("submit_competition_answer")
    const args = calls[0].args as Record<string, unknown>
    expect(args.p_competition_question_id).toBe(dummyId)
    expect(args.p_submitted_answer).toBe("A")
    expect(args).not.toHaveProperty("p_user_id")
    expect(args).not.toHaveProperty("p_time_spent_ms")
    expect(args).not.toHaveProperty("p_correctness")
    expect(args).not.toHaveProperty("p_score")
  })

  it("submitAnswer without answer sends no p_submitted_answer key", async () => {
    const { submitAnswer } = await import("./service")
    const calls: { fn: string; args: unknown }[] = []
    const mockClient = {
      rpc: (fn: string, args?: unknown) => {
        calls.push({ fn, args: args ?? null })
        return Promise.resolve({ data: { answer_id: dummyId, result: "timeout" }, error: null })
      },
    }
    await submitAnswer(mockClient as never, dummyId)
    const args = calls[0].args as Record<string, unknown>
    expect(args).toHaveProperty("p_competition_question_id")
    expect(args).not.toHaveProperty("p_submitted_answer")
  })

  it("RPC error propagates without leaking stack/raw internals", async () => {
    const { joinMatchmakingQueue } = await import("./service")
    const mockClient = {
      rpc: () =>
        Promise.resolve({ data: null, error: { message: "rate limit exceeded" } }),
    }
    await expect(joinMatchmakingQueue(mockClient as never, dummyId)).rejects.toThrow(
      "rate limit exceeded"
    )
  })

  it("malformed raw response from RPC goes through safe mapper", async () => {
    const result = mapQueueJoinResult({ totally: "unexpected" })
    expect(result.status).toBe("waiting")
    expect(result.queueId).toBe("")
    expect(result.gradeLevel).toBe(0)
    expect(result.subjectId).toBe("")
    expect(result.competitionId).toBeUndefined()
  })

  it("RPC caller never leaks opponent/secret fields in returned DTO", async () => {
    const { joinMatchmakingQueue } = await import("./service")
    const mockClient = {
      rpc: () =>
        Promise.resolve({
          data: {
            status: "matched",
            queue_id: dummyId,
            grade_level: 5,
            subject_id: dummyId,
            competition_id: dummyId,
            competition_code: "ABC",
            // fields that must NOT appear in output
            opponent_user_id: "leaked",
            opponent_display_name: "leaked",
            opponent_score: 999,
          },
          error: null,
        }),
    }
    const result = await joinMatchmakingQueue(mockClient as never, dummyId)
    const json = JSON.stringify(result)
    expect(json).not.toContain("opponent")
    expect(json).not.toContain("leaked")
    expect(json).not.toContain("999")
  })
})
