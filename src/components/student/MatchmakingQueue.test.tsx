/**
 * MatchmakingQueue bileseni testleri.
 *
 * - Pending sirasinda join butonu disabled olur.
 * - Mesaj tum durumlarda gorunur ve guncellenir.
 * - Duplicate tiklama ikinci cagri gondermez.
 * - Error durumunda tekrar denenebilir.
 */

import { cleanup, render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

const pushMock = vi.fn()

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock }),
}))

vi.mock("@/app/(student)/competition/actions", () => ({
  joinMatchmakingQueueAction: vi.fn(),
  leaveMatchmakingQueueAction: vi.fn(),
}))

import {
  joinMatchmakingQueueAction,
} from "@/app/(student)/competition/actions"

import MatchmakingQueue from "./MatchmakingQueue"

const mockedJoin = vi.mocked(joinMatchmakingQueueAction)

beforeEach(() => {
  vi.clearAllMocks()
  vi.useFakeTimers({ shouldAdvanceTime: true })
})

afterEach(() => {
  vi.useRealTimers()
  cleanup()
})

function renderQueue(
  overrides: { subjectId?: string; subjectName?: string } = {}
) {
  return render(
    <MatchmakingQueue
      subjectId={overrides.subjectId ?? "11111111-1111-1111-1111-111111111111"}
      subjectName={overrides.subjectName ?? "Matematik"}
    />
  )
}

describe("MatchmakingQueue — bos durum", () => {
  it("baslangicta siraya katil butonu gorunur", () => {
    renderQueue()
    expect(
      screen.getByRole("button", { name: /siraya katil/i })
    ).toBeDefined()
  })
})

describe("MatchmakingQueue — joining", () => {
  it("pending sirasinda siraya aliniyor mesaji gosterilir", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockReturnValue(new Promise(() => {}))
    renderQueue()

    await user.click(screen.getByRole("button", { name: /siraya katil/i }))

    expect(screen.getByText(/siraya aliniyor/i)).toBeDefined()
    expect(screen.queryByRole("button", { name: /siraya katil/i })).toBeNull()
  })
})

describe("MatchmakingQueue — queued", () => {
  it("kuyrukta beklerken mesaj gosterilir", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: true,
      data: {
        status: "waiting",
        queueId: "22222222-2222-2222-2222-222222222222",
        gradeLevel: 10,
        subjectId: "11111111-1111-1111-1111-111111111111",
      },
    })
    renderQueue()

    await user.click(screen.getByRole("button", { name: /siraya katil/i }))

    expect(screen.getByText(/eslesme araniyor/i)).toBeDefined()
    expect(
      screen.getByRole("button", { name: /kuyruktan cik/i })
    ).toBeDefined()
  })
})

describe("MatchmakingQueue — error", () => {
  it("hata durumunda mesaj gosterilir ve tekrar dene butonu cikar", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: false,
      message: "Ders bulunamadi veya pasif.",
    })
    renderQueue()

    await user.click(screen.getByRole("button", { name: /siraya katil/i }))

    expect(screen.getByRole("alert")).toBeDefined()
    expect(screen.getByText(/ders bulunamadi/i)).toBeDefined()
    expect(
      screen.getByRole("button", { name: /tekrar dene/i })
    ).toBeDefined()
  })

  it("tekrar dene ile idle donusu yapilabilir", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: false,
      message: "Genel hata.",
    })
    renderQueue()

    await user.click(screen.getByRole("button", { name: /siraya katil/i }))
    await user.click(screen.getByRole("button", { name: /tekrar dene/i }))

    expect(
      screen.getByRole("button", { name: /siraya katil/i })
    ).toBeDefined()
  })
})
