/**
 * Faz 8 Lig mapper testleri.
 *
 * - DTO allowlist: bilinmeyen anahtarlar DTO'ya gecmez.
 * - SECRET_SENTINEL: PII/duyurlu alanlar (user_id, e-posta, okul,
 *   correct_answer, yildiz ledger detaylari) mapper'dan gecemez.
 * - Grade izolasyonu: expectedGrade ile baska sinif verisi reddedilir.
 * - Puan ayrimi: DTO'da yalnizca "rating" bulunur; yarisma puani,
 *   XP/level ve harcanabilir yildiz alani tasinmaz.
 */

import { describe, expect, it } from "vitest"

import {
  leagueTierLabel,
  mapLeagueRanking,
  mapNextLeague,
  mapOwnLeagueCard,
  mapRankedStudent,
} from "./mappers"

const SECRET_SENTINELS = [
  "USER-UUID-SENTINEL",
  "secret@sentinel.mail",
  "GERCEK-AD-SENTINEL",
  "0555-SENTINEL-TELEFON",
  "OKUL-SENTINEL",
  "DOGUM-SENTINEL",
  "CORRECT-ANSWER-SENTINEL",
  "STAR-LEDGER-SENTINEL",
]

function poisonedRankingPayload(): Record<string, unknown> {
  return {
    season_status: "active",
    grade_level: 7,
    my: {
      rank: 1,
      rating: 64,
      nickname: "QA-NICK-A",
      avatar_key: "avatar_a",
      league_code: "bronze",
      league_name: "Bronz Lig",
      user_id: "USER-UUID-SENTINEL",
      email: "secret@sentinel.mail",
      real_name: "GERCEK-AD-SENTINEL",
      phone: "0555-SENTINEL-TELEFON",
      school: "OKUL-SENTINEL",
      birth_date: "DOGUM-SENTINEL",
      star_balance: "STAR-LEDGER-SENTINEL",
    },
    entries: [
      {
        rank: 1,
        is_current_student: true,
        nickname: "QA-NICK-A",
        avatar_key: "avatar_a",
        league_code: "bronze",
        league_name: "Bronz Lig",
        rating: 64,
        user_id: "USER-UUID-SENTINEL",
        email: "secret@sentinel.mail",
        correct_answer: "CORRECT-ANSWER-SENTINEL",
        school_name: "OKUL-SENTINEL",
        competition_total_points: 250,
        xp: 500,
      },
    ],
    total: 1,
    next_league: {
      league_code: "silver",
      league_name: "Gümüş Lig",
      threshold: 1000,
    },
  }
}

describe("mapLeagueRanking — allowlist", () => {
  it("gecerli yaniti beklenen DTO'ya cevirir", () => {
    const dto = mapLeagueRanking(poisonedRankingPayload())

    expect(dto.status).toBe("active")
    expect(dto.gradeLevel).toBe(7)
    expect(dto.my?.rank).toBe(1)
    expect(dto.my?.rating).toBe(64)
    expect(dto.entries).toHaveLength(1)
    expect(dto.entries[0]).toMatchObject({
      rank: 1,
      isCurrentStudent: true,
      nickname: "QA-NICK-A",
      rating: 64,
    })
    expect(dto.nextLeague).toEqual({
      leagueCode: "silver",
      leagueName: "Gümüş Lig",
      threshold: 1000,
    })
  })

  it("SECRET_SENTINEL degerleri DTO'da hicbir yerde gecmez", () => {
    const dto = mapLeagueRanking(poisonedRankingPayload())
    const serialized = JSON.stringify(dto)

    for (const sentinel of SECRET_SENTINELS) {
      expect(serialized).not.toContain(sentinel)
    }
  })

  it("yarisma puani / XP / yildiz alani DTO'ya tasinmaz (puan ayrimi)", () => {
    const dto = mapLeagueRanking(poisonedRankingPayload())
    const serialized = JSON.stringify(dto)

    expect(serialized).not.toContain("competition_total_points")
    expect(serialized).not.toContain("xp")
    expect(serialized).not.toContain("star_balance")
    expect(serialized).not.toContain("level")
    expect(dto.entries[0].rating).toBe(64)
  })

  it("grade uyuşmazligi reddedilir (baska sinif verisi gecemez)", () => {
    expect(() =>
      mapLeagueRanking(poisonedRankingPayload(), 7)
    ).not.toThrow()

    expect(() => mapLeagueRanking(poisonedRankingPayload(), 6)).toThrow(
      /grade|sinif/i
    )
  })

  it("bilinmeyen season_status reddedilir (fail-closed)", () => {
    const raw = poisonedRankingPayload()
    raw.season_status = "birseyler_baskasi"

    expect(() => mapLeagueRanking(raw)).toThrow(/durum/)
  })

  it("grade 1-12 disi reddedilir", () => {
    const raw = poisonedRankingPayload()
    raw.grade_level = 13
    expect(() => mapLeagueRanking(raw)).toThrow(/sinif/)

    raw.grade_level = 0
    expect(() => mapLeagueRanking(raw)).toThrow(/sinif/)
  })

  it("no_active_season durumunda entries bos ve season null", () => {
    const dto = mapLeagueRanking({
      season_status: "no_active_season",
      grade_level: 7,
      entries: [],
      total: 0,
    })

    expect(dto.status).toBe("no_active_season")
    expect(dto.season).toBeNull()
    expect(dto.my).toBeNull()
    expect(dto.entries).toEqual([])
  })

  it("no_membership durumunda my null, sezon bilgisi tasınır", () => {
    const dto = mapLeagueRanking({
      season_status: "no_membership",
      grade_level: 7,
      season: {
        code: "FAZ8-S1",
        name: "Faz 8 Sezon 1",
        status: "active",
        starts_at: "2026-09-06T00:00:00Z",
        ends_at: "2026-09-14T00:00:00Z",
      },
      entries: [],
      total: 0,
    })

    expect(dto.status).toBe("no_membership")
    expect(dto.my).toBeNull()
    expect(dto.season?.code).toBe("FAZ8-S1")
  })
})

describe("mapRankedStudent — satir guvenligi", () => {
  it("eksik/lucre saysal alanlarda satiri atar (fail-closed)", () => {
    expect(mapRankedStudent(null)).toBeNull()
    expect(mapRankedStudent({ rank: 0, rating: 5, nickname: "x" })).toBeNull()
    expect(mapRankedStudent({ rank: 1, rating: -5, nickname: "x" })).toBeNull()
    expect(mapRankedStudent({ rank: 1, rating: 5 })).toBeNull()
  })

  it("string olarak gelen saysal alanlari cevirir", () => {
    const row = mapRankedStudent({
      rank: "3",
      rating: "25",
      is_current_student: false,
      nickname: "QA-NICK-F",
      league_code: "bronze",
      league_name: "Bronz Lig",
    })

    expect(row).not.toBeNull()
    expect(row?.rank).toBe(3)
    expect(row?.rating).toBe(25)
  })
})

describe("mapOwnLeagueCard", () => {
  it("rank yoksa null dondurur", () => {
    expect(mapOwnLeagueCard(null)).toBeNull()
    expect(mapOwnLeagueCard({})).toBeNull()
  })
})

describe("mapNextLeague", () => {
  it("esik gecersizse null dondurur", () => {
    expect(mapNextLeague({ league_code: "silver", threshold: -1 })).toBeNull()
    expect(
      mapNextLeague({
        league_code: "silver",
        league_name: "Gümüş Lig",
        threshold: 1000,
      })
    ).toEqual({ leagueCode: "silver", leagueName: "Gümüş Lig", threshold: 1000 })
  })
})

describe("leagueTierLabel", () => {
  it("lig kodlarini Turkce kademe etiketine cevirir (renk tek basina anlam tasimaz)", () => {
    expect(leagueTierLabel("bronze")).toBe("Bronz")
    expect(leagueTierLabel("silver")).toBe("Gümüş")
    expect(leagueTierLabel("gold")).toBe("Altın")
    expect(leagueTierLabel("diamond")).toBe("Elmas")
    expect(leagueTierLabel("bilinmeyen")).toBe("Lig")
    expect(leagueTierLabel(null)).toBe("Lig")
  })
})
