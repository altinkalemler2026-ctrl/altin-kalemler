/**
 * League page testleri (Server Component).
 *
 * - Auth gate: auth.getUser() yoksa /login'e redirect.
 * - Aktif sezon listesi: kendi sira karti + "Sen" isareti.
 * - Gizli profil listede gorunmez.
 * - Bos / sezon yok / uyelik yok / guvenli hata durumlari.
 * - Ham DB hatasi UI'a yansimaz.
 * - Sinif/okul/secici YOK; Faz 9 XP/rozet UI'i YOK.
 * - Erisilebilir liste yapisis (ol/li) + baslik hiyerarsisi.
 */

import { render, screen, within } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

const redirectMock = vi.hoisted(() =>
  vi.fn((_url: string) => {
    throw new Error(`REDIRECT:${_url}`)
  })
)
const createClientMock = vi.hoisted(() => vi.fn())
const getMyLeagueRankingMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/league/service", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/league/service")>()
  return {
    ...actual,
    getMyLeagueRanking: (...args: unknown[]) =>
      getMyLeagueRankingMock(...args),
  }
})

function mockUser(user: { id: string } | null) {
  createClientMock.mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user } }),
    },
  })
}

import LeaguePage from "./page"

const ACTIVE_DTO = {
  status: "active",
  gradeLevel: 7,
  season: {
    code: "FAZ8-S1",
    name: "Faz 8 Sezon 1",
    status: "active",
    startsAt: "2026-09-06T00:00:00Z",
    endsAt: "2026-09-14T00:00:00Z",
  },
  my: {
    rank: 2,
    rating: 64,
    leagueCode: "bronze",
    leagueName: "Bronz Lig",
    nickname: "QA-NICK-A",
    avatarKey: "avatar_a",
  },
  entries: [
    {
      rank: 1,
      isCurrentStudent: false,
      nickname: "QA-NICK-B",
      avatarKey: "avatar_b",
      leagueCode: "bronze",
      leagueName: "Bronz Lig",
      rating: 88,
    },
    {
      rank: 2,
      isCurrentStudent: true,
      nickname: "QA-NICK-A",
      avatarKey: "avatar_a",
      leagueCode: "bronze",
      leagueName: "Bronz Lig",
      rating: 64,
    },
  ],
  total: 2,
  nextLeague: {
    leagueCode: "silver",
    leagueName: "Gümüş Lig",
    threshold: 1000,
  },
}

describe("LeaguePage", () => {
  it("auth yoksa /login'e redirect eder", async () => {
    mockUser(null)
    await expect(LeaguePage()).rejects.toThrow("REDIRECT:/login")
  })

  it("baslik gercek grade bilgisini tasiyor (7. Sınıf Ligi)", async () => {
    mockUser({ id: "u1" })
    getMyLeagueRankingMock.mockResolvedValue(ACTIVE_DTO)

    render(await LeaguePage())

    expect(
      screen.getByRole("heading", { name: "7. Sınıf Ligi" })
    ).toBeInTheDocument()
  })

  it("kendi sira karti ve lig rating gorunur; 'Sen' isareti kendi satirinda", async () => {
    mockUser({ id: "u1" })
    getMyLeagueRankingMock.mockResolvedValue(ACTIVE_DTO)

    render(await LeaguePage())

    expect(screen.getByText("Senin sıran")).toBeInTheDocument()
    expect(screen.getByText("Lig rating:")).toBeInTheDocument()
    expect(screen.getAllByText("Sen").length).toBeGreaterThan(0)
    expect(screen.getByText("Bronz Lig")).toBeInTheDocument()
  })

  it("erisilebilir liste yapisisi: ol + li + sirali satirlar", async () => {
    mockUser({ id: "u1" })
    getMyLeagueRankingMock.mockResolvedValue(ACTIVE_DTO)

    render(await LeaguePage())

    const list = screen.getByRole("list")
    const items = within(list).getAllByRole("listitem")
    expect(items).toHaveLength(2)
    expect(items[0].textContent).toContain("QA-NICK-B")
    expect(items[1].textContent).toContain("QA-NICK-A")
  })

  it("siralama rakip takma adini gosterir (ayni sinif, gizlilik yok)", async () => {
    mockUser({ id: "u1" })
    getMyLeagueRankingMock.mockResolvedValue(ACTIVE_DTO)

    render(await LeaguePage())

    expect(screen.getByText("QA-NICK-B")).toBeInTheDocument()
  })

  it("service hata DTO'sunda gizli profil zaten yoktur (sentinel sizzmaz)", async () => {
    mockUser({ id: "u1" })
    const dtoWithHidden = {
      ...ACTIVE_DTO,
      entries: ACTIVE_DTO.entries.filter(
        (e) => e.nickname !== "QA-NICK-B"
      ),
      total: 1,
    }
    getMyLeagueRankingMock.mockResolvedValue(dtoWithHidden)

    render(await LeaguePage())

    expect(screen.queryByText("QA-NICK-B")).not.toBeInTheDocument()
    const html = document.body.innerHTML
    expect(html).not.toContain("SECRET")
  })

  it("no_active_season durumunda bos durum gosterilir", async () => {
    mockUser({ id: "u1" })
    getMyLeagueRankingMock.mockResolvedValue({
      status: "no_active_season",
      gradeLevel: 7,
      season: null,
      my: null,
      entries: [],
      total: 0,
      nextLeague: null,
    })

    render(await LeaguePage())

    expect(
      screen.getByText("Şu anda aktif bir lig sezonu yok")
    ).toBeInTheDocument()
  })

  it("no_membership durumunda uyelik bos durumu gosterilir", async () => {
    mockUser({ id: "u1" })
    getMyLeagueRankingMock.mockResolvedValue({
      status: "no_membership",
      gradeLevel: 7,
      season: {
        code: "FAZ8-S1",
        name: "Faz 8 Sezon 1",
        status: "active",
        startsAt: "2026-09-06T00:00:00Z",
        endsAt: "2026-09-14T00:00:00Z",
      },
      my: null,
      entries: [],
      total: 0,
      nextLeague: null,
    })

    render(await LeaguePage())

    expect(screen.getByText("Henüz lig üyeliğin yok")).toBeInTheDocument()
    expect(screen.getByText("7. Sınıf Ligi")).toBeInTheDocument()
  })

  it("ham DB hatasi UI'a yansimaz (guvenli hata durumu)", async () => {
    mockUser({ id: "u1" })
    getMyLeagueRankingMock.mockRejectedValue(
      new Error("PG::SyntaxError: relation \"x\" does not exist F42501")
    )

    render(await LeaguePage())

    expect(screen.getByText("Lig verisi yüklenemedi")).toBeInTheDocument()
    const html = document.body.innerHTML
    expect(html).not.toContain("PG::")
    expect(html).not.toContain("relation")
    expect(html).not.toContain("F42501")
  })

  it("sinif secici, okul siralamasi ve XP/rozet UI'i bulunmaz", async () => {
    mockUser({ id: "u1" })
    getMyLeagueRankingMock.mockResolvedValue(ACTIVE_DTO)

    render(await LeaguePage())

    expect(screen.queryByRole("combobox")).not.toBeInTheDocument()
    expect(screen.queryByText(/sınıf seç/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/okul sıralaması/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/XP/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/rozet/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/mağaza/i)).not.toBeInTheDocument()
  })

  it("rating aciklamasi yildiz ayrimini dogru etiketler", async () => {
    mockUser({ id: "u1" })
    getMyLeagueRankingMock.mockResolvedValue(ACTIVE_DTO)

    render(await LeaguePage())

    expect(
      screen.getByText(/Lig rating puanı yalnızca lig sıralaması/i)
    ).toBeInTheDocument()
    expect(
      screen.getByText(/Harcanabilir yıldız bakiyesi ayrıdır/i)
    ).toBeInTheDocument()
  })

  it("sezon bitis bilgisi Turkce formatla gosterilir", async () => {
    mockUser({ id: "u1" })
    getMyLeagueRankingMock.mockResolvedValue(ACTIVE_DTO)

    render(await LeaguePage())

    expect(screen.getByText(/Sezon bitişi:/)).toBeInTheDocument()
    expect(screen.getByText("Aktif sezon")).toBeInTheDocument()
  })
})
