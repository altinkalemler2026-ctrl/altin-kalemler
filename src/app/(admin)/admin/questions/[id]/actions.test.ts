// @vitest-environment node
/**
 * Soru düzenleme/yayın server action testleri.
 *
 * - Yetki sunucuda doğrulanır; izni olmayan kullanıcıda mutasyon RPC'si
 *   hiç çağrılmaz (fail-closed).
 * - Girdi doğrulaması RPC'ye gitmeden Türkçe flash ile reddedilir.
 * - RPC argümanları sözleşmeye uygun iletilir (089/040 imzaları).
 * - RPC hatası Türkçe mesaja çevrilir; ham DB mesajı sızmaz.
 * - Yayın: readiness PASS değilse activate çağrılmaz, bloker sebebi
 *   gösterilir.
 * - audit: admin_question_edit yanıtının audit_id taşıması sözleşme
 *   düzeyinde ayrıca doğrulanır (question-edit.test.ts, 089 kaynağı);
 *   burada mutasyon sonrası RPC yanıtının audit verisiyle geldiği
 *   doğrulanır.
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())
const revalidateMock = vi.hoisted(() => vi.fn())
const redirectMock = vi.hoisted(() =>
  vi.fn((url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`)
  })
)
const hasPermissionMock = vi.hoisted(() => vi.fn())
const readinessMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("next/navigation", () => ({
  redirect: redirectMock,
}))

vi.mock("next/cache", () => ({
  revalidatePath: revalidateMock,
}))

vi.mock("@/lib/admin/question-edit", () => ({
  hasAdminPermission: hasPermissionMock,
  getPublicationReadiness: readinessMock,
}))

import {
  activateQuestionAction,
  deactivateQuestionAction,
  editQuestionAction,
} from "./actions"
import {
  QUESTION_EDIT_ERROR_MESSAGES,
  QUESTION_EDIT_INPUT_MESSAGES,
  QUESTION_EDIT_SUCCESS_MESSAGES,
  QUESTION_PUBLICATION_MESSAGES,
  QUESTION_PUBLICATION_STATUS_MESSAGES,
} from "@/lib/admin/question-edit-errors"

const UUID = "aaaaaaaa-1111-4000-8000-000000000001"

function makeFormData(fields: Record<string, string>): FormData {
  const data = new FormData()
  for (const [key, value] of Object.entries(fields)) {
    data.set(key, value)
  }
  return data
}

function lastFlashUrl(): string {
  const call = redirectMock.mock.calls.at(-1)
  expect(call).toBeDefined()
  return String(call![0])
}

function lastFlashParams(): URLSearchParams {
  return new URLSearchParams(lastFlashUrl().split("?")[1] ?? "")
}

function mockSession() {
  getUserMock.mockResolvedValue({
    data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
  })
}

function readinessOk(overrides: Record<string, unknown> = {}) {
  readinessMock.mockResolvedValue({
    status: "ok",
    currentIsActive: false,
    canActivate: true,
    blockers: [],
    warnings: [],
    ...overrides,
  })
}

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  revalidateMock.mockReset()
  redirectMock.mockClear()
  hasPermissionMock.mockReset()
  readinessMock.mockReset()

  mockSession()
  rpcMock.mockResolvedValue({ data: null, error: null })
  hasPermissionMock.mockResolvedValue(true)
  readinessOk()
  createClientMock.mockImplementation(async () => ({
    auth: { getUser: getUserMock },
    rpc: rpcMock,
  }))
})

describe("editQuestionAction", () => {
  function editForm() {
    return makeFormData({
      questionId: UUID,
      questionText: "  Güncellenen soru metni  ",
      optionA: " 1 ",
      optionB: "2",
      optionC: "3",
      optionD: "4",
      optionE: "",
      correctAnswer: " c ",
    })
  }

  it("RPC argümanları 089 sözleşmesine göre iletilir; audit_id'li yanıt işlenir", async () => {
    rpcMock.mockResolvedValue({
      data: {
        status: "updated",
        question_id: UUID,
        audit_id: "cccccccc-0000-4000-8000-00000000000a",
        before_data: {},
        after_data: {},
      },
      error: null,
    })

    await expect(editQuestionAction(editForm())).rejects.toThrow(
      "NEXT_REDIRECT"
    )

    expect(rpcMock).toHaveBeenCalledWith("admin_question_edit", {
      p_question_id: UUID,
      p_question_text: "Güncellenen soru metni",
      p_option_a: "1",
      p_option_b: "2",
      p_option_c: "3",
      p_option_d: "4",
      p_option_e: "",
      p_correct_answer: "C",
    })
    expect(revalidateMock).toHaveBeenCalledWith(`/admin/questions/${UUID}`)

    const params = lastFlashParams()
    expect(params.get("ok")).toBe(QUESTION_EDIT_SUCCESS_MESSAGES.edit)
    expect(params.has("error")).toBe(false)
  })

  it("geçersiz girdi RPC'ye gitmeden reddedilir", async () => {
    await expect(
      editQuestionAction(
        makeFormData({
          questionId: UUID,
          questionText: "   ",
          optionA: "1",
          optionB: "2",
          optionC: "3",
          optionD: "4",
          optionE: "",
          correctAnswer: "A",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(lastFlashParams().get("error")).toBe(
      QUESTION_EDIT_INPUT_MESSAGES.questionTextRequired
    )
  })

  it("geçersiz soru kimliği listeye yönlendirilir; RPC çağrılmaz", async () => {
    await expect(
      editQuestionAction(
        makeFormData({
          questionId: "garbage",
          questionText: "metin",
          optionA: "1",
          optionB: "2",
          optionC: "3",
          optionD: "4",
          optionE: "",
          correctAnswer: "A",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(lastFlashUrl()).toContain("/admin/questions?")
    expect(lastFlashParams().get("error")).toBe(
      QUESTION_EDIT_INPUT_MESSAGES.questionIdInvalid
    )
  })

  it("oturum yoksa RPC çağrılmaz ve /login'e yönlendirilir", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })

    await expect(editQuestionAction(editForm())).rejects.toThrow(
      "NEXT_REDIRECT:/login"
    )
    expect(rpcMock).not.toHaveBeenCalled()
    expect(hasPermissionMock).not.toHaveBeenCalled()
  })

  it("questions.edit izni yoksa fail-closed: mutasyon RPC'si çağrılmaz", async () => {
    hasPermissionMock.mockImplementation(async (code: string) => {
      return code !== "questions.edit"
    })

    await expect(editQuestionAction(editForm())).rejects.toThrow(
      "NEXT_REDIRECT"
    )

    expect(rpcMock).not.toHaveBeenCalled()
    expect(lastFlashParams().get("error")).toBe(
      QUESTION_EDIT_ERROR_MESSAGES.forbidden
    )
  })

  it("RPC izin hatası Türkçe mesaja çevrilir; ham mesaj sızmaz", async () => {
    rpcMock.mockResolvedValue({
      data: null,
      error: { message: "Question edit permission required." },
    })

    await expect(editQuestionAction(editForm())).rejects.toThrow(
      "NEXT_REDIRECT"
    )

    const params = lastFlashParams()
    expect(params.get("error")).toBe(QUESTION_EDIT_ERROR_MESSAGES.forbidden)
    expect(lastFlashUrl()).not.toContain("Question edit permission")
    expect(revalidateMock).not.toHaveBeenCalled()
  })

  it("bilinmeyen RPC hatası generic mesaja düşer; ham metin sızmaz", async () => {
    rpcMock.mockResolvedValue({
      data: null,
      error: { message: "internal: constraint sys_catalog leaked" },
    })

    await expect(editQuestionAction(editForm())).rejects.toThrow(
      "NEXT_REDIRECT"
    )

    expect(lastFlashParams().get("error")).toBe(
      QUESTION_EDIT_ERROR_MESSAGES.generic
    )
    expect(lastFlashUrl()).not.toContain("sys_catalog")
  })
})

describe("activateQuestionAction", () => {
  it("readiness PASS ise activate RPC doğru argümanlarla çağrılır", async () => {
    readinessOk({ currentIsActive: false, canActivate: true })

    await expect(
      activateQuestionAction(makeFormData({ questionId: UUID, reason: "  " }))
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).toHaveBeenCalledWith("activate_question_for_students", {
      p_question_id: UUID,
    })
    expect(lastFlashParams().get("ok")).toBe(
      QUESTION_EDIT_SUCCESS_MESSAGES.activate
    )
  })

  it("yayın sebebi doluysa p_reason iletilir", async () => {
    await expect(
      activateQuestionAction(
        makeFormData({ questionId: UUID, reason: " dönem yayını " })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).toHaveBeenCalledWith("activate_question_for_students", {
      p_question_id: UUID,
      p_reason: "dönem yayını",
    })
  })

  it("readiness PASS değilse activate çağrılmaz; bloker sebebi gösterilir", async () => {
    readinessOk({
      canActivate: false,
      blockers: [{ code: "question_not_approved", message: "onaylı değil" }],
    })

    await expect(
      activateQuestionAction(makeFormData({ questionId: UUID }))
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).not.toHaveBeenCalled()
    const error = lastFlashParams().get("error") ?? ""
    expect(error).toContain("yayına uygun değil")
    expect(error).toContain("onaylı değil")
    expect(revalidateMock).not.toHaveBeenCalled()
  })

  it("soru zaten aktifse activate çağrılmaz", async () => {
    readinessOk({ currentIsActive: true })

    await expect(
      activateQuestionAction(makeFormData({ questionId: UUID }))
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(lastFlashParams().get("error")).toBe(
      QUESTION_PUBLICATION_STATUS_MESSAGES.alreadyActive
    )
  })

  it("readiness okunamazsa activate çağrılmaz", async () => {
    readinessMock.mockResolvedValue({
      status: "error",
      currentIsActive: null,
      canActivate: false,
      blockers: [],
      warnings: [],
    })

    await expect(
      activateQuestionAction(makeFormData({ questionId: UUID }))
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(lastFlashParams().get("error")).toBe(
      QUESTION_PUBLICATION_MESSAGES.readinessUnavailable
    )
  })

  it("questions.approve ve ai.manage izni yoksa fail-closed", async () => {
    hasPermissionMock.mockResolvedValue(false)

    await expect(
      activateQuestionAction(makeFormData({ questionId: UUID }))
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(readinessMock).not.toHaveBeenCalled()
    expect(lastFlashParams().get("error")).toBe(
      QUESTION_EDIT_ERROR_MESSAGES.publishForbidden
    )
  })

  it("RPC izin hatası Türkçeye çevrilir; ham mesaj sızmaz", async () => {
    rpcMock.mockResolvedValue({
      data: null,
      error: { message: "Question approval permission required." },
    })

    await expect(
      activateQuestionAction(makeFormData({ questionId: UUID }))
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(lastFlashParams().get("error")).toBe(
      QUESTION_EDIT_ERROR_MESSAGES.publishForbidden
    )
    expect(lastFlashUrl()).not.toContain("approval permission required.")
  })
})

describe("deactivateQuestionAction", () => {
  it("sebep zorunluluğu RPC'ye gitmeden uygulanır", async () => {
    await expect(
      deactivateQuestionAction(makeFormData({ questionId: UUID, reason: "  " }))
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(lastFlashParams().get("error")).toBe(
      QUESTION_EDIT_INPUT_MESSAGES.deactivateReasonRequired
    )
  })

  it("deactivate RPC doğru argümanlarla çağrılır", async () => {
    await expect(
      deactivateQuestionAction(
        makeFormData({ questionId: UUID, reason: " telif ihlali " })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).toHaveBeenCalledWith("deactivate_question_for_students", {
      p_question_id: UUID,
      p_reason: "telif ihlali",
    })
    expect(lastFlashParams().get("ok")).toBe(
      QUESTION_EDIT_SUCCESS_MESSAGES.deactivate
    )
  })

  it("RPC already_inactive dönerse özel mesaj gösterilir", async () => {
    rpcMock.mockResolvedValue({
      data: { status: "already_inactive", question_id: UUID },
      error: null,
    })

    await expect(
      deactivateQuestionAction(
        makeFormData({ questionId: UUID, reason: "gerekçe" })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(lastFlashParams().get("error")).toBe(
      QUESTION_PUBLICATION_STATUS_MESSAGES.alreadyInactive
    )
  })

  it("yayın izni yoksa fail-closed: RPC çağrılmaz", async () => {
    hasPermissionMock.mockResolvedValue(false)

    await expect(
      deactivateQuestionAction(
        makeFormData({ questionId: UUID, reason: "gerekçe" })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(lastFlashParams().get("error")).toBe(
      QUESTION_EDIT_ERROR_MESSAGES.publishForbidden
    )
  })
})
