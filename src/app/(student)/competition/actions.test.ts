// @vitest-environment node
/**
 * Competition sunucu aksiyonlari testleri.
 *
 * - auth.getUser() basarisizsa SESSION_EXPIRED_MESSAGE doner.
 * - Basarili durumda RPC'ler dogru cagrilir.
 * - Service error'lari Turkce mesaja cevrilir, ham bilgi sizmaz.
 * - RLS hatalarinda kullaniciya ham bilgi sızdırılmaz.
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
