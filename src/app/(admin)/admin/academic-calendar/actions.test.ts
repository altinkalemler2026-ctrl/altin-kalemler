// @vitest-environment node
/**
 * Akademik takvim server action testleri.
 *
 * - Kimlik sunucudan okunur; oturum yoksa RPC çağrılmaz.
 * - Girdi doğrulaması RPC'ye gitmeden Türkçe flash ile reddedilir.
 * - RPC hatası Türkçe mesaja çevrilip flash parametresiyle
 *   yönlendirme URL'ine taşınır; ham DB mesajı sızmaz.
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

import {
  deleteWeekAction,
  upsertWeekAction,
} from "./actions"
import {
  CALENDAR_ERROR_MESSAGES,
  CALENDAR_INPUT_MESSAGES,
  CALENDAR_SUCCESS_MESSAGES,
} from "@/lib/admin/academic-calendar-errors"

function makeFormData(fields: Record<string, string>): FormData {
  const data = new FormData()
  for (const [key, value] of Object.entries(fields)) {
    data.set(key, value)
  }
  return data
}

/** Son flash yönlendirmesinin query parametreleri (decode edilmiş). */
function lastFlashParams(): URLSearchParams {
  const call = redirectMock.mock.calls.at(-1)
  expect(call).toBeDefined()
  const url = String(call![0])
  return new URLSearchParams(url.split("?")[1] ?? "")
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

describe("upsertWeekAction", () => {
  it("geçersiz hafta numarası RPC'ye gitmeden reddedilir", async () => {
    await expect(
      upsertWeekAction(
        makeFormData({
          year: "QA-Y-2099",
          week: "99",
          startsAt: "2099-01-01",
          endsAt: "2099-01-08",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    const params = lastFlashParams()
    expect(params.get("error")).toBe(CALENDAR_INPUT_MESSAGES.weekRange)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("bitiş < başlangıç özel mesajla reddedilir", async () => {
    await expect(
      upsertWeekAction(
        makeFormData({
          year: "QA-Y-2099",
          week: "5",
          startsAt: "2099-01-08",
          endsAt: "2099-01-01",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(lastFlashParams().get("error")).toBe(
      CALENDAR_INPUT_MESSAGES.dateOrder
    )
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("başarılı upsert ok flash'i verir ve revalidate eder", async () => {
    await expect(
      upsertWeekAction(
        makeFormData({
          year: "QA-Y-2099",
          week: "5",
          startsAt: "2099-01-01",
          endsAt: "2099-01-08",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).toHaveBeenCalledWith("academic_calendar_upsert_week", {
      p_year: "QA-Y-2099",
      p_week: 5,
      p_starts_at: "2099-01-01",
      p_ends_at: "2099-01-08",
    })
    expect(revalidateMock).toHaveBeenCalledWith("/admin/academic-calendar")

    const params = lastFlashParams()
    expect(params.get("ok")).toBe(CALENDAR_SUCCESS_MESSAGES.upsert)
    expect(params.has("error")).toBe(false)
    expect(params.get("year")).toBe("QA-Y-2099")
  })

  it("RPC çakışma hatası Türkçe mesajla flash olur; ham mesaj sızmaz", async () => {
    rpcMock.mockResolvedValue({
      error: { message: "Farkli bir akademik yilin takvimiyle cakisiyor." },
    })

    await expect(
      upsertWeekAction(
        makeFormData({
          year: "QA-Y-2100",
          week: "5",
          startsAt: "2099-01-01",
          endsAt: "2099-01-08",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    const params = lastFlashParams()
    expect(params.get("error")).toBe(CALENDAR_ERROR_MESSAGES.crossYearOverlap)
    // Ham ASCII DB metni URL'e taşınmamalı.
    expect(lastFlashRawUrl()).not.toContain("cakisiyor.")
    expect(revalidateMock).not.toHaveBeenCalled()
  })

  it("bilinmeyen RPC hatası generic mesaja düşer; ham metin sızmaz", async () => {
    rpcMock.mockResolvedValue({
      error: { message: "internal error: password hash leaked xyz" },
    })

    await expect(
      upsertWeekAction(
        makeFormData({
          year: "QA-Y-2099",
          week: "5",
          startsAt: "2099-01-01",
          endsAt: "2099-01-08",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    const params = lastFlashParams()
    expect(params.get("error")).toBe(CALENDAR_ERROR_MESSAGES.generic)
    expect(lastFlashRawUrl()).not.toContain("password")
  })

  it("oturum yoksa RPC çağrılmaz", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })

    await expect(
      upsertWeekAction(
        makeFormData({
          year: "QA-Y-2099",
          week: "5",
          startsAt: "2099-01-01",
          endsAt: "2099-01-08",
        })
      )
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).not.toHaveBeenCalled()
  })
})

describe("deleteWeekAction", () => {
  it("başlamış hafta silme RPC'den gelen mesajla özel flash döner", async () => {
    rpcMock.mockResolvedValue({
      error: { message: "Baslamis veya gecmis akademik hafta silinemez." },
    })

    await expect(
      deleteWeekAction(makeFormData({ year: "QA-Y-2099", week: "1" }))
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(lastFlashParams().get("error")).toBe(
      CALENDAR_ERROR_MESSAGES.startedDelete
    )
  })

  it("başarılı silme ok flash'i verir", async () => {
    await expect(
      deleteWeekAction(makeFormData({ year: "QA-Y-2099", week: "20" }))
    ).rejects.toThrow("NEXT_REDIRECT")

    expect(rpcMock).toHaveBeenCalledWith("academic_calendar_delete_week", {
      p_year: "QA-Y-2099",
      p_week: 20,
    })

    const params = lastFlashParams()
    expect(params.get("ok")).toBe(CALENDAR_SUCCESS_MESSAGES.delete)
    expect(params.has("error")).toBe(false)
  })
})
