// @vitest-environment node
/**
 * Competition sunucu aksiyonlari testleri.
 *
 * - auth.getUser() basarisizsa SESSION_EXPIRED_MESSAGE doner.
 * - Basarili durumda RPC'ler dogru cagrilir.
 * - Service error'lari Turkce mesaja cevrilir, ham bilgi sizmaz.
 * - RLS hatalarinda kullaniciya ham bilgi sızdırılmaz.
 * - Yeni action'lar: getCurrentQuestion, syncState, submitAnswer, setReady, getOwnResult.
 * - Rakip verisi, full scoreboard, winnerUserId action response'da bulunmaz.
 * - auth user ID yalnizca sunucu session'dan gelir; client user ID kabul edilmez.
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

import {
  joinMatchmakingQueueAction,
  leaveMatchmakingQueueAction,
  getCurrentQuestionAction,
  syncCompetitionStateAction,
  submitAnswerAction,
  setPlayerReadyAction,
  getOwnCompetitionResultAction,
} from "./actions"

import { SESSION_EXPIRED_MESSAGE } from "@/lib/competition/errors"

function makeClient() {
  return {
    auth: { getUser: getUserMock },
    rpc: rpcMock,
  }
}

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  createClientMock.mockImplementation(async () => makeClient())
})

describe("joinMatchmakingQueueAction", () => {
  it("oturum yoksa SESSION_EXPIRED_MESSAGE doner", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })

    const result = await joinMatchmakingQueueAction(
      "33333333-3333-3333-3333-333333333333"
    )
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).toBe(SESSION_EXPIRED_MESSAGE)
    }
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("hatali UUID dogrulama basarisizsa CompetitionValidationError mesaji doner", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })

    const result = await joinMatchmakingQueueAction("INVALID_UUID")
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).toContain("UUID degil")
    }
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("basarili join sonucu doner", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: {
        status: "waiting",
        queue_id: "11111111-1111-1111-1111-111111111111",
        grade_level: 10,
        subject_id: "22222222-2222-2222-2222-222222222222",
      },
      error: null,
    })

    const result = await joinMatchmakingQueueAction(
      "33333333-3333-3333-3333-333333333333"
    )
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.data.status).toBe("waiting")
      expect(result.data.queueId).toBe(
        "11111111-1111-1111-1111-111111111111"
      )
    }

    expect(rpcMock).toHaveBeenCalledTimes(1)
    const [fn, args] = rpcMock.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ]
    expect(fn).toBe("join_matchmaking_queue")
    expect(args).toEqual({
      p_subject_id: "33333333-3333-3333-3333-333333333333",
    })
  })

  it("auth hatasi oturum kaybina duser, ham hata gunlugue gitmez", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: null,
      error: new Error(
        "permission denied for function join_matchmaking_queue"
      ),
    })

    const result = await joinMatchmakingQueueAction(
      "33333333-3333-3333-3333-333333333333"
    )
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).toContain("Oturumunuz")
      expect(result.message).not.toContain("permission denied")
      expect(result.message).not.toContain("join_matchmaking_queue")
    }
  })
})

describe("leaveMatchmakingQueueAction", () => {
  it("oturum yoksa SESSION_EXPIRED_MESSAGE doner", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })

    const result = await leaveMatchmakingQueueAction()
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).toBe(SESSION_EXPIRED_MESSAGE)
    }
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("basarili leave sonucu doner", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({ data: { cancelled: 1 }, error: null })

    const result = await leaveMatchmakingQueueAction()
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.data.cancelled).toBe(1)
    }

    expect(rpcMock).toHaveBeenCalledTimes(1)
    const [fn] = rpcMock.mock.calls[0] as [string]
    expect(fn).toBe("leave_matchmaking_queue")
  })
})

// ------------------------------------------------------------
// Faz 5b: Yarisma oturum aksiyon testleri
// ------------------------------------------------------------

describe("getCurrentQuestionAction", () => {
  it("oturum yoksa SESSION_EXPIRED_MESSAGE doner", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })
    const result = await getCurrentQuestionAction()
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).toBe(SESSION_EXPIRED_MESSAGE)
    }
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("basarili soru dondurur", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: {
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
            stem_html: "<p>Soru</p>",
            option_a_html: "<p>A</p>",
          },
        },
      },
      error: null,
    })

    const result = await getCurrentQuestionAction()
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.data.questionAvailable).toBe(true)
      expect(result.data.competitionId).toBe(
        "11111111-1111-1111-1111-111111111111"
      )
    }
    const [fn] = rpcMock.mock.calls[0] as [string]
    expect(fn).toBe("get_current_competition_question")
  })

  it("RPC hatasi Turkce mesaja cevrilir", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: null,
      error: new Error("permission denied"),
    })

    const result = await getCurrentQuestionAction()
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).toContain("Oturumunuz")
      expect(result.message).not.toContain("permission denied")
    }
  })
})

describe("syncCompetitionStateAction", () => {
  it("oturum yoksa SESSION_EXPIRED_MESSAGE doner", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })
    const result = await syncCompetitionStateAction(
      "11111111-1111-1111-1111-111111111111"
    )
    expect(result.ok).toBe(false)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("hatali UUID CompetitionValidationError doner", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    const result = await syncCompetitionStateAction("INVALID")
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).toContain("UUID degil")
    }
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("basarili sync sonucu doner", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: {
        competition_id: "11111111-1111-1111-1111-111111111111",
        status: "active",
        current_question_order: 1,
        question_count: 5,
        has_answered_current_question: false,
        my_current_score: 100,
        opponent_current_score: 50,
      },
      error: null,
    })

    const result = await syncCompetitionStateAction(
      "11111111-1111-1111-1111-111111111111"
    )
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.data.myCurrentScore).toBe(100)
      const json = JSON.stringify(result.data)
      expect(json).not.toContain("opponent_current_score")
      expect(json).not.toContain('"50"')
    }
  })

  it("ham DB hatasi sizmaz", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: null,
      error: new Error("internal server error code=XYZ"),
    })

    const result = await syncCompetitionStateAction(
      "11111111-1111-1111-1111-111111111111"
    )
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).not.toContain("XYZ")
      expect(result.message).not.toContain("internal server error")
    }
  })
})

describe("submitAnswerAction", () => {
  it("oturum yoksa SESSION_EXPIRED_MESSAGE doner", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })
    const result = await submitAnswerAction(
      "11111111-1111-1111-1111-111111111111",
      "A"
    )
    expect(result.ok).toBe(false)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("hatali UUID CompetitionValidationError doner", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    const result = await submitAnswerAction("INVALID", "A")
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).toContain("UUID degil")
    }
  })

  it("basarili cevap gonderir, dogruluk/puan donmez", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: {
        answer_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        result: "correct",
        time_ms: 5000,
        points_awarded: 100,
        time_band: "fast",
      },
      error: null,
    })

    const result = await submitAnswerAction(
      "11111111-1111-1111-1111-111111111111",
      "A"
    )
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.data.accepted).toBe(true)
      expect(result.data.submissionId).toBe(
        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      )
      const json = JSON.stringify(result.data)
      expect(json).not.toContain("correct")
      expect(json).not.toContain("100")
      expect(json).not.toContain("fast")
    }
    const [fn, args] = rpcMock.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ]
    expect(fn).toBe("submit_competition_answer")
    expect(args.p_competition_question_id).toBe(
      "11111111-1111-1111-1111-111111111111"
    )
    expect(args.p_submitted_answer).toBe("A")
  })

  it("duplicate cevap hatasi Turkce mesaja cevrilir", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: null,
      error: new Error("Answer already submitted for this question."),
    })

    const result = await submitAnswerAction(
      "11111111-1111-1111-1111-111111111111",
      "A"
    )
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).toContain("cevabiniz zaten gonderildi")
      expect(result.message).not.toContain("already submitted")
    }
  })

  it("cevap allowlist disinda hata donmez (pass = undefined)", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: {
        answer_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        result: "pass",
      },
      error: null,
    })

    const result = await submitAnswerAction(
      "11111111-1111-1111-1111-111111111111"
    )
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.data.accepted).toBe(true)
    }
    const [, args] = rpcMock.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ]
    expect(args.p_submitted_answer).toBeUndefined()
  })
})

describe("setPlayerReadyAction", () => {
  it("oturum yoksa SESSION_EXPIRED_MESSAGE doner", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })
    const result = await setPlayerReadyAction(
      "11111111-1111-1111-1111-111111111111"
    )
    expect(result.ok).toBe(false)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("hatali UUID CompetitionValidationError doner", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    const result = await setPlayerReadyAction("INVALID")
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).toContain("UUID degil")
    }
  })

  it("basarili ready isareti doner", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: { status: "started", ready_count: 2 },
      error: null,
    })

    const result = await setPlayerReadyAction(
      "11111111-1111-1111-1111-111111111111"
    )
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.data.status).toBe("started")
    }
    const [fn] = rpcMock.mock.calls[0] as [string]
    expect(fn).toBe("set_competition_player_ready")
  })

  it("ham hata sizmaz", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: null,
      error: new Error("DRY_RUN_INTERNAL_ERROR"),
    })

    const result = await setPlayerReadyAction(
      "11111111-1111-1111-1111-111111111111"
    )
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).not.toContain("DRY_RUN")
    }
  })
})

describe("getOwnCompetitionResultAction", () => {
  it("oturum yoksa SESSION_EXPIRED_MESSAGE doner", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })
    const result = await getOwnCompetitionResultAction(
      "11111111-1111-1111-1111-111111111111"
    )
    expect(result.ok).toBe(false)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("auth user ID yalnizca sunucu session'dan gelir", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: {
        competition_id: "11111111-1111-1111-1111-111111111111",
        competition_code: "F5-TEST",
        competition_type: "one_vs_one",
        grade_level: 10,
        subject_id: "22222222-2222-2222-2222-222222222222",
        question_count: 5,
        result_type: "win_loss",
        my_player_slot: 1,
        my_total_points: 300,
        my_correct_count: 3,
        my_wrong_count: 1,
        my_pass_count: 0,
        my_timeout_count: 1,
        my_finished_at: "2025-01-01T00:05:00Z",
        question_results: [
          { question_order: 1, difficulty: "easy", points_awarded: 100, time_ms: 5000 },
          { question_order: 2, difficulty: "medium", points_awarded: 0, time_ms: 15000 },
        ],
        started_at: "2025-01-01T00:00:00Z",
        completed_at: "2025-01-01T00:05:00Z",
      },
      error: null,
    })

    const result = await getOwnCompetitionResultAction(
      "11111111-1111-1111-1111-111111111111"
    )
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.data.myPlayerSlot).toBe(1)
      expect(result.data.myTotalPoints).toBe(300)
      expect(result.data.myCorrectCount).toBe(3)

      const json = JSON.stringify(result.data)
      expect(json).not.toContain("winner_user_id")
      expect(json).not.toContain("winnerUserId")
      expect(json).not.toContain('"players"')
    }
  })

  it("full scoreboard action export edilmemis", async () => {
    const actions = await import("./actions")
    expect(actions).not.toHaveProperty("getScoreboardAction")
    expect(actions).not.toHaveProperty("getFullScoreboardAction")
  })

  it("raw DB error sizmaz", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: null,
      error: new Error("pg_restore: ERROR internal_detail_12345"),
    })

    const result = await getOwnCompetitionResultAction(
      "11111111-1111-1111-1111-111111111111"
    )
    expect(result.ok).toBe(false)
    if (!result.ok) {
      expect(result.message).not.toContain("pg_restore")
      expect(result.message).not.toContain("12345")
    }
  })
})
