/**
 * StudentGamification testleri (Faz 9/10).
 *
 * - XP/seviye/seri/kota/rozetler yalnız gerçek DTO değerleriyle.
 * - Yarışma puanı, lig rating ve yıldız kartta GÖSTERİLMEZ.
 * - Kota kartında kullanılan soru sayısı ayrıca görünür (Faz 10).
 * - Profil ve Lig bağlantıları (Faz 10) mevcuttur.
 */

import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import StudentGamification from "./StudentGamification"
import type { GamificationProfile } from "@/lib/gamification/types"

function makeProfile(overrides: Partial<GamificationProfile> = {}): GamificationProfile {
  return {
    xp: {
      totalXp: 750,
      level: 2,
      maxLevel: 50,
      nextLevelRequiredTotalXp: 2000,
      xpToNextLevel: 1250,
    },
    streak: { current: 4, longest: 11, lastActivityDay: "2026-09-07" },
    dailyQuota: {
      day: "2026-09-08",
      questionsUsed: 64,
      limit: 500,
      remaining: 436,
    },
    badges: [{ badgeCode: "first_step", name: "İlk Adım", grantedAt: "2026-09-01" }],
    ...overrides,
  }
}

describe("StudentGamification", () => {
  it("XP/seviye/seri/kota/rozet degerleri ayri kartlarda gorunur", () => {
    render(<StudentGamification profile={makeProfile()} />)

    expect(screen.getByText("2. Seviye")).toBeInTheDocument()
    expect(screen.getByText("750 XP")).toBeInTheDocument()
    expect(screen.getByText("4 gün")).toBeInTheDocument()
    expect(screen.getByText("En uzun serin: 11 gün")).toBeInTheDocument()
    expect(screen.getByText("436")).toBeInTheDocument()
    expect(screen.getByText("/ 500 soru kaldı")).toBeInTheDocument()
    expect(screen.getByText("İlk Adım")).toBeInTheDocument()
  })

  it("kota kartinda kullanilan soru sayisi ayrıca görünür (Faz 10)", () => {
    render(<StudentGamification profile={makeProfile()} />)

    expect(screen.getByText("Bugün 64 soru çözdün.")).toBeInTheDocument()
  })

  it("maksimum seviyede guvenli metin", () => {
    render(
      <StudentGamification
        profile={makeProfile({
          xp: {
            totalXp: 1225000,
            level: 50,
            maxLevel: 50,
            nextLevelRequiredTotalXp: null,
            xpToNextLevel: null,
          },
        })}
      />
    )

    expect(screen.getByText("50. Seviye")).toBeInTheDocument()
    expect(screen.getByText("Maksimum seviyedesin.")).toBeInTheDocument()
  })

  it("rozet yokken aciklayici bos durum", () => {
    render(<StudentGamification profile={makeProfile({ badges: [] })} />)

    expect(screen.getByText(/Henüz rozetin yok/)).toBeInTheDocument()
  })

  it("Profilim ve Ligim baglantilari yerinde", () => {
    render(<StudentGamification profile={makeProfile()} />)

    expect(screen.getByRole("link", { name: "Profilim" })).toHaveAttribute(
      "href",
      "/profile"
    )
    expect(screen.getByRole("link", { name: "Ligim" })).toHaveAttribute(
      "href",
      "/league"
    )
  })

  it("lig rating / yarisma puani / yildiz karisimina yer yok", () => {
    render(
      <StudentGamification
        profile={makeProfile({
          // Faz 8/9 ayrilik kontrasi: rating/stars DTO'da ZATEN yok;
          // ham karisim senaryosunda da kart gostermez.
          ...({ lig_rating: 1022, yildiz: 99 } as object),
        })}
      />
    )

    expect(screen.queryByText(/rating/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/yıldız/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/mağaza/i)).not.toBeInTheDocument()
  })
})
