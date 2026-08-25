/**
 * Competition result page testleri (Server Component).
 *
 * - Auth gate: auth.getUser() yoksa redirect.
 * - Participant gate: is_competition_participant false ise redirect.
 * - Incomplete competition redirect.
 * - Yalnizca OwnCompetitionResult render edilir.
 * - Rakip ismi/skoru/ID'si gosterilmez.
 * - winnerUserId, players dizisi render edilmez.
 */

import { render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

const redirectMock = vi.hoisted(() =>
  vi.fn((_url: string) => {
    throw new Error(`REDIRECT:${_url}`)
  })
)
const createClientMock = vi.hoisted(() => vi.fn())
const getOwnResultMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/competition/service", () => ({
  getOwnResult: (...args: unknown[]) => getOwnResultMock(...args),
}))

function mockClient(user: { id: string } | null, isParticipant: boolean) {
  createClientMock.mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user } }),
    },
    rpc: vi.fn().mockResolvedValue({ data: isParticipant }),
  })
}

import CompetitionResultPage from "./page"

describe("CompetitionResultPage", () => {
  it("auth yoksa /login'e redirect eder", async () => {
    mockClient(null, false)

    await expect(
      CompetitionResultPage({
        params: Promise.resolve({
          competitionId: "11111111-1111-1111-1111-111111111111",
        }),
      })
    ).rejects.toThrow("REDIRECT:/login")
  })

  it("participant degilse /competition'a redirect eder", async () => {
    mockClient({ id: "99999999-8888-4000-8000-000000000901" }, false)

    await expect(
      CompetitionResultPage({
        params: Promise.resolve({
          competitionId: "11111111-1111-1111-1111-111111111111",
        }),
      })
    ).rejects.toThrow("REDIRECT:/competition")
  })

  it("tamamlanmamis yarismada oturum sayfasina redirect", async () => {
    mockClient({ id: "99999999-8888-4000-8000-000000000901" }, true)
    getOwnResultMock.mockResolvedValue({
      competitionId: "11111111-1111-1111-1111-111111111111",
      completedAt: null,
    })

    await expect(
      CompetitionResultPage({
        params: Promise.resolve({
          competitionId: "11111111-1111-1111-1111-111111111111",
        }),
      })
    ).rejects.toThrow(
      "REDIRECT:/competition/11111111-1111-1111-1111-111111111111"
    )
  })

  it("tamamlanmis yarismada rakip verisi gosterilmez", async () => {
    mockClient({ id: "99999999-8888-4000-8000-000000000901" }, true)
    getOwnResultMock.mockResolvedValue({
      competitionId: "11111111-1111-1111-1111-111111111111",
      competitionCode: "F5-TEST",
      competitionType: "one_vs_one",
      gradeLevel: 10,
      subjectId: "22222222-2222-2222-2222-222222222222",
      questionCount: 5,
      resultType: "win_loss",
      myPlayerSlot: 1,
      myTotalPoints: 300,
      myCorrectCount: 3,
      myWrongCount: 1,
      myPassCount: 0,
      myTimeoutCount: 1,
      myFinishedAt: "2025-01-01T00:05:00Z",
      questionResults: [
        {
          questionOrder: 1,
          difficulty: "easy",
          pointsAwarded: 100,
          timeMs: 5000,
        },
      ],
      startedAt: "2025-01-01T00:00:00Z",
      completedAt: "2025-01-01T00:05:00Z",
    })

    const element = await CompetitionResultPage({
      params: Promise.resolve({
        competitionId: "11111111-1111-1111-1111-111111111111",
      }),
    })

    render(element)

    expect(screen.getByText("300")).toBeDefined()
    expect(screen.getByText("F5-TEST")).toBeDefined()

    const bodyText = document.body.textContent ?? ""
    expect(bodyText).not.toContain("AAAAAAAA")
    expect(bodyText).not.toContain("winnerUserId")
    expect(bodyText).not.toContain("winner_user_id")
    expect(bodyText).not.toContain("player_slot")
  })

  it("getOwnResult hatasinda oturum sayfasina redirect", async () => {
    mockClient({ id: "99999999-8888-4000-8000-000000000901" }, true)
    getOwnResultMock.mockRejectedValue(new Error("RPC failed"))

    await expect(
      CompetitionResultPage({
        params: Promise.resolve({
          competitionId: "11111111-1111-1111-1111-111111111111",
        }),
      })
    ).rejects.toThrow(
      "REDIRECT:/competition/11111111-1111-1111-1111-111111111111"
    )
  })
})
