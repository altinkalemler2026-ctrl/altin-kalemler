// @vitest-environment node
/**
 * Server action katmanı testleri (B2 regresyonu).
 *
 * - TrainingValidationError `instanceof` ile ayrışır; doğrulama hatası
 *   kullanıcılara ÖZEL Türkçe mesajla döner (generic mesaja düşmez).
 * - Oturum yoksa SESSION_EXPIRED_MESSAGE döner.
 * - Kimlik sunucudan okunur; RPC'ye user_id taşınmaz.
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

import { fetchAttemptFeedbackAction, submitTrainingAttemptAction } from "./actions"
import { SESSION_EXPIRED_MESSAGE } from "@/lib/training/errors"

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

describe("submitTrainingAttemptAction", () => {
  it("doğrulama hatası ÖZEL Türkçe mesajla döner (B2: instanceof)", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })

    const response = await submitTrainingAttemptAction({
      questionId: "33333333-3333-3333-3333-000000000001",
      clientKey: "cccccccc-cccc-cccc-cccc-cccccccccccc",
      timeMs: 1000,
      choice: "F" as never,
    })

    expect(response.ok).toBe(false)
    if (!response.ok) {
      expect(response.message).toBe(
        "Geçersiz seçenek. A, B, C, D veya E seçin."
      )
    }
    // Doğrulama RPC'ye hiç gitmemeli.
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("eksik seçenek/işlem gönderimi özel mesajla reddedilir", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })

    const response = await submitTrainingAttemptAction({
      questionId: "33333333-3333-3333-3333-000000000001",
      clientKey: "cccccccc-cccc-cccc-cccc-cccccccccccc",
      timeMs: 1000,
    })

    expect(response.ok).toBe(false)
    if (!response.ok) {
      expect(response.message).toBe(
        "Cevap gönderimi için seçenek veya işlem gereklidir."
      )
    }
  })

  it("oturum yoksa oturum-süresi mesajı döner", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })

    const response = await submitTrainingAttemptAction({
      questionId: "33333333-3333-3333-3333-000000000001",
      clientKey: "cccccccc-cccc-cccc-cccc-cccccccccccc",
      timeMs: 1000,
      choice: "A",
    })

    expect(response).toEqual({ ok: false, message: SESSION_EXPIRED_MESSAGE })
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("geçerli gönderim RPC'ye user_id olmadan gider ve sonuç maplenir", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: {
        attempt_id: "a1",
        attempt_number: 1,
        result: "correct",
        duplicate: false,
      },
      error: null,
    })

    const response = await submitTrainingAttemptAction({
      questionId: "33333333-3333-3333-3333-000000000001",
      clientKey: "cccccccc-cccc-cccc-cccc-cccccccccccc",
      timeMs: 2500,
      choice: "B",
    })

    expect(response).toEqual({
      ok: true,
      data: {
        attemptId: "a1",
        attemptNumber: 1,
        result: "correct",
        duplicate: false,
      },
    })

    expect(rpcMock).toHaveBeenCalledTimes(1)
    const [fn, args] = rpcMock.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ]
    expect(fn).toBe("submit_training_attempt")
    expect(Object.keys(args).sort()).toEqual(
      ["p_action", "p_choice", "p_client_key", "p_question_id", "p_time_ms"].sort()
    )
    expect(JSON.stringify(args)).not.toContain("user_id")
  })

  it("DB hatası Türkçe genel/oturum mesajına çevrilir, ham metin sızmaz", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: null,
      error: { message: "Kimlik dogrulamasi gerekli." },
    })

    const response = await submitTrainingAttemptAction({
      questionId: "33333333-3333-3333-3333-000000000001",
      clientKey: "cccccccc-cccc-cccc-cccc-cccccccccccc",
      timeMs: 1000,
      choice: "A",
    })

    expect(response.ok).toBe(false)
    if (!response.ok) {
      expect(response.message).toBe(
        "Oturumunuz doğrulanamadı. Lütfen sayfayı yenileyip tekrar giriş yapın."
      )
      expect(response.message).not.toContain("dogrulamasi")
    }
  })
})

describe("fetchAttemptFeedbackAction — Faz 11", () => {
  it("oturum yoksa oturum-süresi mesajı döner ve RPC çağrılmaz", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })

    const response = await fetchAttemptFeedbackAction(
      "33333333-3333-3333-3333-000000000001"
    )

    expect(response).toEqual({ ok: false, message: SESSION_EXPIRED_MESSAGE })
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("geçersiz soru kimliğini özel mesajla reddeder (RPC'ye gitmez)", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })

    const response = await fetchAttemptFeedbackAction("not-a-uuid")

    expect(response.ok).toBe(false)
    if (!response.ok) {
      expect(response.message).toBe("questionId geçerli bir UUID değil.")
    }
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("kabul edilmiş cevapta onaylı geri bildirim DTO'su döner", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
    })
    rpcMock.mockResolvedValue({
      data: { found: true, correct_answer: "B", solution_text: "Ankara." },
      error: null,
    })

    const response = await fetchAttemptFeedbackAction(
      "33333333-3333-3333-3333-000000000001"
    )

    expect(response.ok).toBe(true)
    if (response.ok) {
      expect(response.data).toEqual({
        found: true,
        correctAnswer: "B",
        solutionText: "Ankara.",
      })
    }
    expect(rpcMock).toHaveBeenCalledWith("get_attempt_feedback", {
      p_question_id: "33333333-3333-3333-3333-000000000001",
    })
  })
})
