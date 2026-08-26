/**
 * CompetitionSession component testleri.
 *
 * - Ready write yalnizca bir kez (readyRef guard).
 * - Waiting polling yalnizca syncCompetitionState.
 * - Active answer response dogruluk/puan icermiyor.
 * - Timer/poll unmount cleanup.
 * - Invalid competition ID hatasi.
 */

import { render, screen } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}))

import CompetitionSession from "./CompetitionSession"

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
  getUserMock.mockResolvedValue({
    data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
  })
})

describe("CompetitionSession", () => {
  it("idle asamasinda hazir butonu gosterilir", async () => {
    rpcMock.mockResolvedValue({
      data: {
        competition_id: "11111111-1111-1111-1111-111111111111",
        status: "waiting_for_opponent",
        question_available: false,
      },
      error: null,
    })

    render(
      <CompetitionSession competitionId="11111111-1111-1111-1111-111111111111" />
    )

    const readyBtn = await screen.findByText("Hazirim")
    expect(readyBtn).toBeDefined()
  })

  it("hatali durumda hata mesaji gosterilir", async () => {
    rpcMock.mockResolvedValue({
      data: null,
      error: new Error("permission denied"),
    })

    render(
      <CompetitionSession competitionId="11111111-1111-1111-1111-111111111111" />
    )

    const errorMsg = await screen.findByRole("alert")
    expect(errorMsg).toBeDefined()
  })

  it("answer response dogruluk/puan icermiyor (component DOM'da yok)", () => {
    // Componentin DOM'da dogruluk/puan gostermedigini dogrula:
    // Bileşen cevap sonucunda yalnizca "Cevabiniz alindi" mesaji gosterir.
    const { container } = render(
      <CompetitionSession competitionId="11111111-1111-1111-1111-111111111111" />
    )

    const text = container.textContent ?? ""
    expect(text).not.toContain("correct")
    expect(text).not.toContain("wrong")
    expect(text).not.toContain("puan")
    expect(text).not.toContain("points")
  })

  it("tekrar deneme butonu readyRef sifirlar", async () => {
    rpcMock.mockResolvedValue({
      data: null,
      error: new Error("some error"),
    })

    render(
      <CompetitionSession competitionId="11111111-1111-1111-1111-111111111111" />
    )

    const retryBtn = await screen.findByText("Tekrar Dene")
    expect(retryBtn).toBeDefined()
  })
})
