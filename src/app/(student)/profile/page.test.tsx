/**
 * ProfilePage testleri (Server Component, Faz 10).
 *
 * - Auth gate: oturum yoksa /login'e redirect.
 * - Profil ozeti: takma ad, sinif, avatar; grade duzenleme KONTROLU YOK.
 * - Oyunlastirma: XP/seviye/seri/kota/rozetler; hata durumunda guvenli mesaj.
 * - Katalog bos: "Avatarlar hazirlaniyor" durumu.
 * - PII: e-posta/UUID/ham DB hatasi DOM'a sizmaz.
 */

import { render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

const redirectMock = vi.hoisted(() =>
  vi.fn((_url: string) => {
    throw new Error(`REDIRECT:${_url}`)
  })
)
const createClientMock = vi.hoisted(() => vi.fn())
const getUserMock = vi.hoisted(() => vi.fn())
const fetchOwnProfileSummaryMock = vi.hoisted(() => vi.fn())
const fetchAvatarCatalogMock = vi.hoisted(() => vi.fn())
const fetchGamificationProfileMock = vi.hoisted(() => vi.fn())
const updateNicknameActionMock = vi.hoisted(() => vi.fn())
const selectAvatarActionMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/profile/service", () => ({
  fetchOwnProfileSummary: (...args: unknown[]) =>
    fetchOwnProfileSummaryMock(...args),
  fetchAvatarCatalog: (...args: unknown[]) => fetchAvatarCatalogMock(...args),
}))

vi.mock("@/lib/gamification/service", () => ({
  fetchGamificationProfile: (...args: unknown[]) =>
    fetchGamificationProfileMock(...args),
}))

vi.mock("./actions", () => ({
  updateNicknameAction: (...args: unknown[]) => updateNicknameActionMock(...args),
  selectAvatarAction: (...args: unknown[]) => selectAvatarActionMock(...args),
}))

import ProfilePage from "./page"
import type { GamificationProfile } from "@/lib/gamification/types"
import type { AvatarCatalog, OwnProfileSummary } from "@/lib/profile/types"

function mockUser(user: { id: string } | null) {
  createClientMock.mockResolvedValue({
    auth: { getUser: getUserMock },
  })
  getUserMock.mockResolvedValue({ data: { user }, error: null })
}

const SUMMARY: OwnProfileSummary = {
  nickname: "MatematikUstasi",
  gradeLevel: 7,
  avatar: { code: "character_1", name: "Karakter 1" },
}

const CATALOG: AvatarCatalog = {
  status: "available",
  options: [
    {
      code: "character_1",
      name: "Karakter 1",
      description: "Başlangıç karakteri.",
    },
  ],
}

function gamificationProfile(overrides: Partial<GamificationProfile> = {}): GamificationProfile {
  return {
    xp: {
      totalXp: 1200,
      level: 2,
      maxLevel: 50,
      nextLevelRequiredTotalXp: 2000,
      xpToNextLevel: 800,
    },
    streak: { current: 3, longest: 9, lastActivityDay: "2026-09-07" },
    dailyQuota: {
      day: "2026-09-08",
      questionsUsed: 120,
      limit: 500,
      remaining: 380,
    },
    badges: [
      { badgeCode: "first_step", name: "İlk Adım", grantedAt: "2026-09-01" },
    ],
    ...overrides,
  }
}

describe("ProfilePage", () => {
  it("auth yoksa /login'e redirect eder", async () => {
    mockUser(null)
    await expect(ProfilePage()).rejects.toThrow("REDIRECT:/login")
  })

  it("takma ad, sinif ve karakter bilgisi gorunur; grade duzenleme kontrolu YOKTUR", async () => {
    mockUser({ id: "u1" })
    fetchOwnProfileSummaryMock.mockResolvedValue(SUMMARY)
    fetchAvatarCatalogMock.mockResolvedValue(CATALOG)
    fetchGamificationProfileMock.mockResolvedValue(gamificationProfile())

    render(await ProfilePage())

    expect(
      screen.getByRole("heading", { name: "Profilim", level: 1 })
    ).toBeInTheDocument()
    expect(screen.getByText("7. Sınıf")).toBeInTheDocument()
    expect(screen.getByDisplayValue("MatematikUstasi")).toBeInTheDocument()
    expect(screen.getAllByText("Karakter 1").length).toBeGreaterThan(0)

    // Grade degistirme kontrolu yoktur: hidden input dahil.
    expect(document.body.querySelector('input[name="grade_level"]')).toBeNull()
    expect(screen.queryByRole("combobox")).not.toBeInTheDocument()
    expect(screen.queryByText(/sınıf seç/i)).not.toBeInTheDocument()
  })

  it("XP, seviye ve sonraki seviye ilerlemesi dogru gosterilir", async () => {
    mockUser({ id: "u1" })
    fetchOwnProfileSummaryMock.mockResolvedValue(SUMMARY)
    fetchAvatarCatalogMock.mockResolvedValue(CATALOG)
    fetchGamificationProfileMock.mockResolvedValue(gamificationProfile())

    render(await ProfilePage())

    expect(screen.getByText("2. Seviye")).toBeInTheDocument()
    expect(screen.getByText("1200 XP")).toBeInTheDocument()
    expect(screen.getByText(/Sonraki seviyeye 800 XP kaldı/)).toBeInTheDocument()
  })

  it("yeni ogrenci 0 XP ve seviye 1 gorur", async () => {
    mockUser({ id: "u1" })
    fetchOwnProfileSummaryMock.mockResolvedValue(SUMMARY)
    fetchAvatarCatalogMock.mockResolvedValue(CATALOG)
    fetchGamificationProfileMock.mockResolvedValue(
      gamificationProfile({
        xp: {
          totalXp: 0,
          level: 1,
          maxLevel: 50,
          nextLevelRequiredTotalXp: 500,
          xpToNextLevel: 500,
        },
        streak: { current: 0, longest: 0, lastActivityDay: null },
        badges: [],
      })
    )

    render(await ProfilePage())

    expect(screen.getByText("1. Seviye")).toBeInTheDocument()
    expect(screen.getByText("0 XP")).toBeInTheDocument()
    expect(screen.getByText(/Henüz rozetin yok/)).toBeInTheDocument()
    expect(screen.getByText("0 gün")).toBeInTheDocument()
  })

  it("maksimum seviye 50 guvenli gosterilir", async () => {
    mockUser({ id: "u1" })
    fetchOwnProfileSummaryMock.mockResolvedValue(SUMMARY)
    fetchAvatarCatalogMock.mockResolvedValue(CATALOG)
    fetchGamificationProfileMock.mockResolvedValue(
      gamificationProfile({
        xp: {
          totalXp: 1225000,
          level: 50,
          maxLevel: 50,
          nextLevelRequiredTotalXp: null,
          xpToNextLevel: null,
        },
      })
    )

    render(await ProfilePage())

    expect(screen.getByText("50. Seviye")).toBeInTheDocument()
    expect(screen.getByText("Maksimum seviyedesin.")).toBeInTheDocument()
  })

  it("seri ve kota degerleri ayri kartlarda dogru gosterilir", async () => {
    mockUser({ id: "u1" })
    fetchOwnProfileSummaryMock.mockResolvedValue(SUMMARY)
    fetchAvatarCatalogMock.mockResolvedValue(CATALOG)
    fetchGamificationProfileMock.mockResolvedValue(
      gamificationProfile({
        dailyQuota: {
          day: "2026-09-08",
          questionsUsed: 500,
          limit: 500,
          remaining: 0,
        },
      })
    )

    render(await ProfilePage())

    expect(screen.getByText("3 gün")).toBeInTheDocument()
    expect(screen.getByText(/En uzun serin: 9 gün/)).toBeInTheDocument()
    expect(screen.getByText("0")).toBeInTheDocument()
    expect(screen.getByText(/Bugün 500 soru çözdün/)).toBeInTheDocument()
  })

  it("kazanilmis rozetler listelenir", async () => {
    mockUser({ id: "u1" })
    fetchOwnProfileSummaryMock.mockResolvedValue(SUMMARY)
    fetchAvatarCatalogMock.mockResolvedValue(CATALOG)
    fetchGamificationProfileMock.mockResolvedValue(gamificationProfile())

    render(await ProfilePage())

    expect(screen.getByText("İlk Adım")).toBeInTheDocument()
  })

  it("avatar katalogu bosken 'Avatarlar hazirlaniyor' durumu gosterilir", async () => {
    mockUser({ id: "u1" })
    fetchOwnProfileSummaryMock.mockResolvedValue(SUMMARY)
    fetchAvatarCatalogMock.mockResolvedValue({ status: "empty", options: [] })
    fetchGamificationProfileMock.mockResolvedValue(gamificationProfile())

    render(await ProfilePage())

    expect(screen.getByText("Avatarlar hazırlanıyor")).toBeInTheDocument()
    expect(screen.queryByRole("radio")).not.toBeInTheDocument()
  })

  it("oyunlastirma RPC hatasinda ham hata sizmaz; guvenli uyari gorunur", async () => {
    mockUser({ id: "u1" })
    fetchOwnProfileSummaryMock.mockResolvedValue(SUMMARY)
    fetchAvatarCatalogMock.mockResolvedValue(CATALOG)
    fetchGamificationProfileMock.mockRejectedValue(
      new Error("PG::SyntaxError relation gamification x F42501")
    )

    render(await ProfilePage())

    expect(
      screen.getByText("Gelişim bilgilerin yüklenemedi")
    ).toBeInTheDocument()

    const html = document.body.innerHTML
    expect(html).not.toContain("PG::")
    expect(html).not.toContain("relation")
    expect(html).not.toContain("F42501")
  })

  it("profil ozeti hatasinda guvenli durum doner", async () => {
    mockUser({ id: "u1" })
    fetchOwnProfileSummaryMock.mockRejectedValue(
      new Error("PG::InternalError sentinel-detay")
    )

    render(await ProfilePage())

    expect(
      screen.getByText("Profil bilgilerin yüklenemedi")
    ).toBeInTheDocument()
    expect(screen.queryByDisplayValue("MatematikUstasi")).not.toBeInTheDocument()
    expect(document.body.innerHTML).not.toContain("sentinel-detay")
  })

  it("PII sentinel: DTO'da dahi email/UUID/ledger render edilmez", async () => {
    mockUser({ id: "sentinel-user-uuid" })
    // Mapper allowlist disindaki alanlari dusurur; mock yine de
    // ham satiri dondurerek savunmayi test eder.
    fetchOwnProfileSummaryMock.mockResolvedValue({
      nickname: "MatematikUstasi",
      gradeLevel: 7,
      avatar: { code: "character_1", name: "Karakter 1" },
      email: "sentinel-mail@evil.test",
      id: "sentinel-user-uuid",
    } as unknown as OwnProfileSummary)
    fetchAvatarCatalogMock.mockResolvedValue(CATALOG)
    fetchGamificationProfileMock.mockResolvedValue(gamificationProfile())

    render(await ProfilePage())

    const html = document.body.innerHTML
    expect(html).not.toContain("sentinel-mail")
    expect(html).not.toContain("sentinel-user-uuid")
    expect(html).not.toContain("evil.test")
  })

  it("uzun nickname sayfayi bozmaz (render tamamlanir)", async () => {
    mockUser({ id: "u1" })
    fetchOwnProfileSummaryMock.mockResolvedValue({
      ...SUMMARY,
      nickname: "UzunTakmaAd1234567890123456789012345678901234567890",
    })
    fetchAvatarCatalogMock.mockResolvedValue(CATALOG)
    fetchGamificationProfileMock.mockResolvedValue(gamificationProfile())

    render(await ProfilePage())

    expect(
      screen.getByDisplayValue(
        "UzunTakmaAd1234567890123456789012345678901234567890"
      )
    ).toBeInTheDocument()
    expect(
      screen.getByRole("heading", { name: "Profilim", level: 1 })
    ).toBeInTheDocument()
  })

  it("Profil ve Lig baglantilari oyunlastirma kartinda yer alir", async () => {
    mockUser({ id: "u1" })
    fetchOwnProfileSummaryMock.mockResolvedValue(SUMMARY)
    fetchAvatarCatalogMock.mockResolvedValue(CATALOG)
    fetchGamificationProfileMock.mockResolvedValue(gamificationProfile())

    render(await ProfilePage())

    expect(screen.getByRole("link", { name: "Profilim" })).toHaveAttribute(
      "href",
      "/profile"
    )
    expect(
      screen.getByRole("link", { name: "Ligim" })
    ).toHaveAttribute("href", "/league")
  })
})
