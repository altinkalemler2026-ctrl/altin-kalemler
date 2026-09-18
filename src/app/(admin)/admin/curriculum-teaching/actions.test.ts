// @vitest-environment node
/**
 * Öğretmen Konu-Açma sunucu action testleri.
 *
 * - Girdi doğrulaması (eksik schedule item / yıl / geçersiz status)
 *   RPC'ye gitmeden Türkçe flash ile reddedilir.
 * - Oturum yoksa RPC çağrılmaz.
 * - RPC hatası Türkçe mesaja çevrilip flash'a taşınır; ham DB mesajı
 *   URL'e sızmaz.
 * - Başarılı yazma: yalnız izinli argümanlar RPC'ye gider, ok flash'i
 *   verir, route revalidate edilir, audit payload URL'de görünmez.
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

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("next/navigation", () => ({
  redirect: redirectMock,
}))

vi.mock("next/cache", () => ({
  revalidatePath: revalidateMock,
}))

import { setTeachingApprovalAction } from "./actions"
import {
  CURRICULUM_TEACHING_ERROR_MESSAGES as TE,
  CURRICULUM_TEACHING_INPUT_MESSAGES as TI,
  CURRICULUM_TEACHING_SUCCESS_MESSAGES as TS,
} from "@/lib/admin/curriculum-teaching-errors"

const SUBJECT_ID = "430903f3-527e-4e12-b7e8-ac0afdb784aa"
const ITEM_ID = "a4090000-0000-4000-8000-000000000001"
const YEAR = "2026-2027"

function makeFormData(fields: Record<string, string>): FormData {
  const data = new FormData()
  for (const [key, value] of Object.entries(fields)) {
    data.set(key, value)
  }
  return data
}

function lastFlashParams(): URLSearchParams {
  const call = redirectMock.mock.calls.at(-1)
  expect(call).toBeDefined()
  return new URLSearchParams(String(call![0]).split("?")[1] ?? "")
}

function lastFlashRawUrl(): string {
  const call = redirectMock.mock.calls.at(-1)
  expect(call).toBeDefined()
  return String(call![0])
}

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  revalidateMock.mockReset()
  redirectMock.mockClear()
  getUserMock.mockResolvedValue({
    data: { user: { id: "99999999-9999-9999-9999-999999999901" } },
  })
  rpcMock.mockResolvedValue({ error: null })
  createClientMock.mockImplementation(async () => ({
    auth: { getUser: getUserMock },
    rpc: rpcMock,
  }))
})

describe("setTeachingApprovalAction — girdi doğrulaması", () => {
  it("eksik schedule item RPC'ye gitmeden reddedilir", async () => {
    await expect(
      setTeachingApprovalAction(
        makeFormData({ academic_year: YEAR, status: "approved" })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(lastFlashParams().get("error")).toBe(TI.scheduleItemRequired)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("eksik akademik yıl özel mesajla reddedilir", async () => {
    await expect(
      setTeachingApprovalAction(
        makeFormData({ schedule_item_id: ITEM_ID, status: "approved" })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(lastFlashParams().get("error")).toBe(TI.academicYearRequired)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("geçersiz status RPC'ye gitmeden reddedilir", async () => {
    await expect(
      setTeachingApprovalAction(
        makeFormData({
          schedule_item_id: ITEM_ID,
          academic_year: YEAR,
          status: "needs_revision",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(lastFlashParams().get("error")).toBe(TI.invalidStatus)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("oturum yoksa RPC çağrılmaz", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })

    await expect(
      setTeachingApprovalAction(
        makeFormData({
          schedule_item_id: ITEM_ID,
          academic_year: YEAR,
          status: "approved",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).not.toHaveBeenCalled()
  })
})

describe("setTeachingApprovalAction — RPC yazma", () => {
  it("onay/red yalnız izinli argümanlarla RPC'ye gider; ok flash + revalidate", async () => {
    await expect(
      setTeachingApprovalAction(
        makeFormData({
          schedule_item_id: ITEM_ID,
          academic_year: YEAR,
          status: "approved",
          notes: "Kazanımlar işlendi.",
          subject_id: SUBJECT_ID,
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).toHaveBeenCalledWith("set_curriculum_teaching_approval", {
      p_schedule_item_id: ITEM_ID,
      p_academic_year: YEAR,
      p_status: "approved",
      p_notes: "Kazanımlar işlendi.",
    })
    expect(revalidateMock).toHaveBeenCalledWith("/admin/curriculum-teaching")

    const params = lastFlashParams()
    expect(params.get("ok")).toBe(TS.saved)
    expect(params.has("error")).toBe(false)
    expect(params.get("subject")).toBe(SUBJECT_ID)
    expect(params.get("year")).toBe(YEAR)
  })

  it("boş not null olarak gider; audit payload URL'de görünmez", async () => {
    await expect(
      setTeachingApprovalAction(
        makeFormData({
          schedule_item_id: ITEM_ID,
          academic_year: YEAR,
          status: "rejected",
          notes: "",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).toHaveBeenCalledWith("set_curriculum_teaching_approval", {
      p_schedule_item_id: ITEM_ID,
      p_academic_year: YEAR,
      p_status: "rejected",
      p_notes: null,
    })

    const url = lastFlashRawUrl()
    expect(url).not.toContain("before_data")
    expect(url).not.toContain("after_data")
    expect(url).not.toContain("approved_by")
  })

  it("RPC yetki hatası Türkçe mesajla flash olur; ham ASCII metin sızmaz", async () => {
    rpcMock.mockResolvedValue({
      error: { message: "curriculum.manage yetkisi gerekli." },
    })

    await expect(
      setTeachingApprovalAction(
        makeFormData({
          schedule_item_id: ITEM_ID,
          academic_year: YEAR,
          status: "approved",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    const params = lastFlashParams()
    expect(params.get("error")).toBe(TE.forbidden)
    expect(lastFlashRawUrl()).not.toContain("curriculum.manage")
    expect(lastFlashRawUrl()).not.toContain("yetkisi")
    expect(revalidateMock).not.toHaveBeenCalled()
  })

  it("bilinmeyen RPC hatası generic mesaja düşer; ham metin sızmaz", async () => {
    rpcMock.mockResolvedValue({
      error: { message: "internal error: divider by zero stack" },
    })

    await expect(
      setTeachingApprovalAction(
        makeFormData({
          schedule_item_id: ITEM_ID,
          academic_year: YEAR,
          status: "approved",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    const params = lastFlashParams()
    expect(params.get("error")).toBe(TE.generic)
    expect(lastFlashRawUrl()).not.toContain("divider")
  })

  it("silme/yok etme için hiçbir action tanımlı değildir (yalnız onay yazma)", async () => {
    const actions = await import("./actions")
    expect(Object.keys(actions).sort()).toEqual(["setTeachingApprovalAction"])
    expect("deleteTeachingApprovalAction" in actions).toBe(false)
  })
})