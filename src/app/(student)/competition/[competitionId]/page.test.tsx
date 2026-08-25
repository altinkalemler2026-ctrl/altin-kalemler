/**
 * Competition session page testleri (Server Component).
 *
 * - Auth gate: auth.getUser() yoksa redirect.
 * - Participant gate: is_competition_participant false ise redirect.
 * - Gecerli participant icin CompetitionSession render edilir.
 */

import { render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

const redirectMock = vi.hoisted(() =>
  vi.fn((_url: string) => {
    throw new Error(`REDIRECT:${_url}`)
  })
)
const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/components/student/CompetitionSession", () => ({
  default: ({ competitionId }: { competitionId: string }) =>
    `CompetitionSession:${competitionId}`,
}))

function mockClient(user: { id: string } | null, isParticipant: boolean) {
  createClientMock.mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user } }),
    },
    rpc: vi.fn().mockResolvedValue({ data: isParticipant }),
  })
}

import CompetitionSessionPage from "./page"

describe("CompetitionSessionPage", () => {
  it("auth yoksa /login'e redirect eder", async () => {
    mockClient(null, false)

    await expect(
      CompetitionSessionPage({
        params: Promise.resolve({
          competitionId: "11111111-1111-1111-1111-111111111111",
        }),
      })
    ).rejects.toThrow("REDIRECT:/login")
  })

  it("participant degilse /competition'a redirect eder", async () => {
    mockClient({ id: "99999999-8888-4000-8000-000000000901" }, false)

    await expect(
      CompetitionSessionPage({
        params: Promise.resolve({
          competitionId: "11111111-1111-1111-1111-111111111111",
        }),
      })
    ).rejects.toThrow("REDIRECT:/competition")
  })

  it("participant ise CompetitionSession render edilir", async () => {
    mockClient({ id: "99999999-8888-4000-8000-000000000901" }, true)

    const element = await CompetitionSessionPage({
      params: Promise.resolve({
        competitionId: "11111111-1111-1111-1111-111111111111",
      }),
    })

    render(element)
    expect(
      screen.getByText("CompetitionSession:11111111-1111-1111-1111-111111111111")
    ).toBeDefined()
  })
})
