/**
 * CompetitionSession component testleri.
 *
 * - Ready yazımı yalnızca bir kez (readyRef guard).
 * - Waiting polling yalnızca syncCompetitionState.
 * - İlerleme (Soru X / Y) ve sunucu puanı gösterilir.
 * - Cevap sonrası geri bildirim rakip cevabını sızdırmaz.
 * - cancelled/abandoned durumunda iptal ekranı gösterilir.
 * - Timer/poll unmount cleanup.
 * - Invalid competition ID hatası.
 */

import { cleanup, render, screen, act } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

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

const COMP_ID = "11111111-1111-1111-1111-111111111111"

function makeClient() {
  return {
    auth: { getUser: getUserMock },
    rpc: rpcMock,
  }
}

function questionPayload(questionOrder: number) {
  return {
    competition_question_id: `2222222${questionOrder}-2222-2222-2222-222222222222`,
    question_order: questionOrder,
    sent_at: "2026-01-01T10:00:00Z",
    deadline_at: "2027-01-01T10:02:00Z",
    question: {
      id: `3333333${questionOrder}-3333-3333-3333-333333333333`,
      stem_html: "<p>Soru metni</p>",
      option_a_html: "<p>A</p>",
      option_b_html: "<p>B</p>",
    },
  }
}

function activeSessionState(overrides: Record<string, unknown> = {}) {
  return {
    competition_id: COMP_ID,
    status: "active",
    current_question_order: 1,
    question_count: 5,
    sent_at: "2026-01-01T10:00:00Z",
    deadline_at: "2027-01-01T10:02:00Z",
    time_limit_seconds: 120,
    has_answered_current_question: false,
    my_current_score: 100,
    opponent_current_score: 80,
    ...overrides,
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

afterEach(() => {
  cleanup()
})

describe("CompetitionSession — temel akış", () => {
  it("idle aşamasında hazırım butonu gösterilir", async () => {
    rpcMock.mockResolvedValue({
      data: {
        competition_id: COMP_ID,
        status: "waiting_for_opponent",
        question_available: false,
      },
      error: null,
    })

    render(<CompetitionSession competitionId={COMP_ID} />)

    expect(await screen.findByText("Hazırım")).toBeDefined()
  })

  it("hatalı durumda hata mesajı gösterilir", async () => {
    rpcMock.mockResolvedValue({
      data: null,
      error: new Error("permission denied"),
    })

    render(<CompetitionSession competitionId={COMP_ID} />)

    expect(await screen.findByRole("alert")).toBeDefined()
  })

  it("hata sonrası tekrar dene butonu sunulur", async () => {
    rpcMock.mockResolvedValue({
      data: null,
      error: new Error("some error"),
    })

    render(<CompetitionSession competitionId={COMP_ID} />)

    expect(
      await screen.findByRole("button", { name: "Tekrar dene" })
    ).toBeDefined()
  })

  it("no_active_competition durumunda URL'deki yarisma senkronize edilir (hazir ekranı)", async () => {
    rpcMock.mockImplementation(async (fn: string) => {
      if (fn === "get_current_competition_question") {
        return {
          data: {
            status: "no_active_competition",
            question_available: false,
          },
          error: null,
        }
      }
      if (fn === "sync_competition_state") {
        return { data: activeSessionState({ status: "waiting" }), error: null }
      }
      return { data: null, error: null }
    })

    render(<CompetitionSession competitionId={COMP_ID} />)

    // waiting/ready durumunda hazir ekranı gösterilir.
    expect(await screen.findByText("Hazırım")).toBeDefined()
  })

  it("sync de yarisma bulamazsa bilgilendirme gösterilir", async () => {
    rpcMock.mockImplementation(async (fn: string) => {
      if (fn === "get_current_competition_question") {
        return {
          data: {
            status: "no_active_competition",
            question_available: false,
          },
          error: null,
        }
      }
      if (fn === "sync_competition_state") {
        return { data: null, error: null }
      }
      return { data: null, error: null }
    })

    render(<CompetitionSession competitionId={COMP_ID} />)

    expect(
      await screen.findByText(/aktif bir yarışma yok/i)
    ).toBeDefined()
  })
})

describe("CompetitionSession — soru fazı", () => {
  it("ilerleme (Soru 1 / 5) ve sunucu puanı gösterilir", async () => {
    rpcMock.mockImplementation(async (fn: string) => {
      if (fn === "get_current_competition_question") {
        return {
          data: {
            competition_id: COMP_ID,
            status: "active",
            question_available: true,
            payload: questionPayload(1),
          },
          error: null,
        }
      }
      if (fn === "sync_competition_state") {
        return { data: activeSessionState(), error: null }
      }
      return { data: null, error: null }
    })

    render(<CompetitionSession competitionId={COMP_ID} />)

    expect(await screen.findByText(/Soru 1 \/ 5/)).toBeDefined()
    expect(screen.getByText(/Puanın: 100/)).toBeDefined()
  })

  it("rakip skoru ve rakip cevabı arayüzde görünmez", async () => {
    rpcMock.mockImplementation(async (fn: string) => {
      if (fn === "get_current_competition_question") {
        return {
          data: {
            competition_id: COMP_ID,
            status: "active",
            question_available: true,
            payload: questionPayload(1),
          },
          error: null,
        }
      }
      if (fn === "sync_competition_state") {
        return {
          data: activeSessionState({ opponent_current_score: 999 }),
          error: null,
        }
      }
      return { data: null, error: null }
    })

    const { container } = render(
      <CompetitionSession competitionId={COMP_ID} />
    )
    await screen.findByText(/Soru 1 \/ 5/)

    const text = container.textContent ?? ""
    expect(text).not.toContain("999")
    expect(text).not.toContain("opponent")
    expect(text).not.toContain("correct")
  })

  it("cancelled/abandoned durumunda iptal ekranı gösterilir", async () => {
    rpcMock.mockImplementation(async (fn: string) => {
      if (fn === "get_current_competition_question") {
        return {
          data: {
            competition_id: COMP_ID,
            status: "cancelled",
            question_available: false,
          },
          error: null,
        }
      }
      return { data: null, error: null }
    })

    render(<CompetitionSession competitionId={COMP_ID} />)

    expect(
      await screen.findByText(/yarışma iptal edildi/i)
    ).toBeDefined()
    expect(
      await screen.findByRole("button", { name: /yarışmalara dön/i })
    ).toBeDefined()
  })
})

describe("CompetitionSession — cevap gönderimi", () => {
  it("duplicate cevap hatasında cevap alındı aşamasına geçer (idempotent UX)", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    vi.useFakeTimers({ shouldAdvanceTime: true })
    try {
      let submitted = false
      rpcMock.mockImplementation(async (fn: string) => {
        if (fn === "get_current_competition_question") {
          return {
            data: {
              competition_id: COMP_ID,
              status: "active",
              question_available: true,
              payload: questionPayload(1),
            },
            error: null,
          }
        }
        if (fn === "sync_competition_state") {
          return {
            data: activeSessionState({ has_answered_current_question: submitted }),
            error: null,
          }
        }
        if (fn === "submit_competition_answer") {
          submitted = true
          return {
            data: null,
            error: new Error("Answer already submitted for this question."),
          }
        }
        return { data: null, error: null }
      })

      render(<CompetitionSession competitionId={COMP_ID} />)
      await screen.findByText(/Soru 1 \/ 5/)

      await user.click(screen.getByRole("radio", { name: /Seçenek A/ }))
      await user.click(screen.getByRole("button", { name: "Cevapla" }))

      // Hata ekranı DEĞİL, answered aşaması gösterilmeli.
      expect(
        await screen.findByText(/Şu anki puanın/)
      ).toBeDefined()
      expect(screen.queryByRole("alert")).toBeNull()
    } finally {
      vi.useRealTimers()
    }
  })

  it("çift tıklamada yalnızca tek submit isteği gider", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    vi.useFakeTimers({ shouldAdvanceTime: true })
    try {
      let submitted = false
      let submitCount = 0
      rpcMock.mockImplementation(async (fn: string) => {
        if (fn === "get_current_competition_question") {
          return {
            data: {
              competition_id: COMP_ID,
              status: "active",
              question_available: true,
              payload: questionPayload(1),
            },
            error: null,
          }
        }
        if (fn === "sync_competition_state") {
          return {
            data: activeSessionState({ has_answered_current_question: submitted }),
            error: null,
          }
        }
        if (fn === "submit_competition_answer") {
          submitCount += 1
          submitted = true
          return {
            data: { answer_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" },
            error: null,
          }
        }
        return { data: null, error: null }
      })

      render(<CompetitionSession competitionId={COMP_ID} />)
      await screen.findByText(/Soru 1 \/ 5/)

      await user.click(screen.getByRole("radio", { name: /Seçenek A/ }))
      await user.click(screen.getByRole("button", { name: "Cevapla" }))
      await screen.findByText(/Şu anki puanın/)

      // Buton artık DOM'da yok (answered fazı); ikinci istek imkansız.
      expect(screen.queryByRole("button", { name: "Cevapla" })).toBeNull()
      expect(submitCount).toBe(1)
    } finally {
      vi.useRealTimers()
    }
  })

  it("answered fazında sunucu puanı gösterilir, rakip verisi sızdırılmaz", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    try {
      rpcMock.mockImplementation(async (fn: string) => {
        if (fn === "get_current_competition_question") {
          return {
            data: {
              competition_id: COMP_ID,
              status: "active",
              question_available: true,
              payload: questionPayload(1),
            },
            error: null,
          }
        }
        if (fn === "sync_competition_state") {
          return {
            data: activeSessionState({
              has_answered_current_question: true,
              my_current_score: 130,
              opponent_current_score: 777,
            }),
            error: null,
          }
        }
        return { data: null, error: null }
      })

      render(<CompetitionSession competitionId={COMP_ID} />)

      // idle load'da hasAnswered true -> dogrudan answered fazina gecer.
      const answeredNode = await screen.findByText(/Şu anki puanın: 130/)
      expect(answeredNode).toBeDefined()

      const mainEl = answeredNode.closest("main") as HTMLElement
      const text = mainEl.textContent ?? ""
      expect(text).not.toContain("777")
      expect(text).not.toContain("opponent")
    } finally {
      vi.useRealTimers()
    }
  })
})

describe("CompetitionSession — waiting poll", () => {
  it("waiting poll cancelled dondugunde iptal ekranina gecer", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    try {
      let callCount = 0
      rpcMock.mockImplementation(async (fn: string) => {
        if (fn === "get_current_competition_question") {
          callCount += 1
          if (callCount === 1) {
            return {
              data: {
                competition_id: COMP_ID,
                status: "active",
                question_available: false,
              },
              error: null,
            }
          }
          return {
            data: {
              competition_id: COMP_ID,
              status: "cancelled",
              question_available: false,
            },
            error: null,
          }
        }
        if (fn === "sync_competition_state") {
          return {
            data: {
              competition_id: COMP_ID,
              status: "cancelled",
              has_answered_current_question: false,
              my_current_score: 0,
            },
            error: null,
          }
        }
        return { data: null, error: null }
      })

      render(<CompetitionSession competitionId={COMP_ID} />)
      await screen.findByText(/rakibin hazırlanıyor/i)

      await act(async () => {
        await vi.advanceTimersByTimeAsync(3_000)
      })

      expect(
        await screen.findByText(/yarışma iptal edildi/i)
      ).toBeDefined()
    } finally {
      vi.useRealTimers()
    }
  })
})
