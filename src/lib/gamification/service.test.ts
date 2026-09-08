import { describe, expect, it } from "vitest"

import {
  DAILY_QUOTA_FULL_MESSAGE,
  DAILY_QUOTA_FULL_REASON,
  fetchGamificationProfile,
  mapDailyQuota,
  mapGamificationBadges,
  mapGamificationProfile,
  mapGamificationStreak,
  mapGamificationXp,
} from "./service"

/** Bilinmeyen/gizli alanlar bilinçli olarak eklenmiş ham RPC cevabı. */
function rawProfile(overrides: Record<string, unknown> = {}) {
  return {
    xp: {
      total: 12345,
      level: 6,
      max_level: 50,
      next_level_required_total_xp: 12500,
      xp_to_next_level: 155,
      client_suggested_level: 99,
    },
    streak: {
      current: 4,
      longest: 9,
      last_activity_day: "2026-09-08",
    },
    daily_quota: {
      day: "2026-09-08",
      questions_used: 120,
      limit: 500,
      remaining: 380,
    },
    badges: [
      {
        badge_code: "first_correct",
        name: "İlk Doğru",
        granted_at: "2026-09-01T10:00:00+00:00",
      },
      {
        badge_code: "first_step",
        name: "İlk Adım",
        granted_at: "2026-09-01T09:00:00+00:00",
        internal_source: "GIZLI",
      },
    ],
    wallet: { stars: 999 },
    competition_points: 100,
    league_rating: 2500,
    ...overrides,
  }
}

describe("mapGamificationXp", () => {
  it("gerçek değerleri eşler; seviye istemciden KABUL EDİLMEZ", () => {
    const xp = mapGamificationXp(rawProfile().xp)
    expect(xp).toEqual({
      totalXp: 12345,
      level: 6,
      maxLevel: 50,
      nextLevelRequiredTotalXp: 12500,
      xpToNextLevel: 155,
    })
  })

  it("istemcinin önerdiği seviye alanını düşürür (sunucu otoriter)", () => {
    const record = rawProfile().xp as Record<string, unknown>
    expect(record.client_suggested_level).toBeDefined()
    const xp = mapGamificationXp(record)
    expect(Object.values(xp)).not.toContain(99)
  })

  it("maksimum seviyede null eşikleri destekler", () => {
    const xp = mapGamificationXp({
      total: 1200500,
      level: 50,
      max_level: 50,
      next_level_required_total_xp: null,
      xp_to_next_level: null,
    })
    expect(xp.level).toBe(50)
    expect(xp.nextLevelRequiredTotalXp).toBeNull()
    expect(xp.xpToNextLevel).toBeNull()
  })

  it("eksik/bozuk girdide güvenli varsayılanlara düşer", () => {
    const xp = mapGamificationXp(null)
    expect(xp.totalXp).toBe(0)
    expect(xp.level).toBe(1)
    expect(xp.maxLevel).toBe(50)
  })
})

describe("mapGamificationStreak ve mapDailyQuota", () => {
  it("seri değerlerini eşler; gecikmiş tarih alanları null olabilir", () => {
    expect(mapGamificationStreak(rawProfile().streak)).toEqual({
      current: 4,
      longest: 9,
      lastActivityDay: "2026-09-08",
    })
    expect(mapGamificationStreak(null)).toEqual({
      current: 0,
      longest: 0,
      lastActivityDay: null,
    })
  })

  it("günlük kota alanlarını eşler", () => {
    expect(mapDailyQuota(rawProfile().daily_quota)).toEqual({
      day: "2026-09-08",
      questionsUsed: 120,
      limit: 500,
      remaining: 380,
    })
    expect(mapDailyQuota(undefined)).toEqual({
      day: null,
      questionsUsed: 0,
      limit: 500,
      remaining: 500,
    })
  })
})

describe("mapGamificationBadges", () => {
  it("yalnız güvenli alanları eşler; gizli kaynak alanı düşer", () => {
    const badges = mapGamificationBadges(rawProfile().badges)
    expect(badges).toHaveLength(2)
    expect(badges[1]).toEqual({
      badgeCode: "first_step",
      name: "İlk Adım",
      grantedAt: "2026-09-01T09:00:00+00:00",
    })
    const serialized = JSON.stringify(badges)
    expect(serialized).not.toContain("GIZLI")
  })

  it("dizi olmayan girdide boş liste döner", () => {
    expect(mapGamificationBadges(null)).toEqual([])
    expect(mapGamificationBadges("x")).toEqual([])
  })
})

describe("mapGamificationProfile", () => {
  it("bütün alt bölümleri ayrı DTO alanları olarak eşler", () => {
    const profile = mapGamificationProfile(rawProfile())
    expect(profile.xp.totalXp).toBe(12345)
    expect(profile.streak.current).toBe(4)
    expect(profile.dailyQuota.remaining).toBe(380)
    expect(profile.badges).toHaveLength(2)
  })

  it("yarışma puanı, lig rating ve yıldız alanlarını DTO'ya SOKMAZ", () => {
    const profile = mapGamificationProfile(rawProfile())
    const serialized = JSON.stringify(profile)
    expect(serialized).not.toContain("stars")
    expect(serialized).not.toContain("999")
    expect(serialized).not.toContain("competition_points")
    expect(serialized).not.toContain("league_rating")
  })
})

describe("fetchGamificationProfile", () => {
  it("RPC hatasında hata fırlatır; sahte değer üretmez", async () => {
    const client = {
      rpc: async () => ({ data: null, error: { message: "hata" } }),
    } as unknown as Parameters<typeof fetchGamificationProfile>[0]

    await expect(fetchGamificationProfile(client)).rejects.toBeTruthy()
  })

  it("RPC cevabını allowlist eşleyicisinden geçirir", async () => {
    const client = {
      rpc: async () => ({ data: rawProfile(), error: null }),
    } as unknown as Parameters<typeof fetchGamificationProfile>[0]

    const profile = await fetchGamificationProfile(client)
    expect(profile.xp.level).toBe(6)
    expect(profile.badges).toHaveLength(2)
  })
})

describe("kota-doldu sabitleri", () => {
  it("DB reason değeri ve doğal Türkçe mesaj sözleşmeye uygundur", () => {
    expect(DAILY_QUOTA_FULL_REASON).toBe("gunluk_kota_doldu")
    expect(DAILY_QUOTA_FULL_MESSAGE).toContain("500")
    expect(DAILY_QUOTA_FULL_MESSAGE).toContain("Yarın")
  })
})
