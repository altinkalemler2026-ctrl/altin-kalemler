/**
 * Faz 8 Lig DTO tipleri.
 *
 * Puan turleri KESIN ayridir:
 *   - rating: lig siralamasi icin sunucu-otoriter lig rating degeri.
 *     Harcanamaz, yildiz/XP ile iliskisi yoktur.
 *   - Yarisma puani, XP/level ve harcanabilir yildiz bu DTO'da YOKTUR
 *     (Faz 9/10 kapsamlari ayridir).
 */

export type LeaguePageStatus =
  | "active"
  | "no_active_season"
  | "no_membership"

export interface LeagueSeasonInfo {
  code: string
  name: string
  status: string
  startsAt: string | null
  endsAt: string | null
}

/** Siralama satiri — yalniz izinli public alanlar. */
export interface RankedStudent {
  rank: number
  isCurrentStudent: boolean
  nickname: string
  avatarKey: string | null
  leagueCode: string
  leagueName: string
  /** Lig rating puani (harcanabilir yildiz DEGIL). */
  rating: number
}

/** Ogrencinin kendi sira karti. */
export interface OwnLeagueCard {
  rank: number | null
  rating: number | null
  leagueCode: string | null
  leagueName: string | null
  nickname: string | null
  avatarKey: string | null
}

/** Sonraki lig esigi (016 bant sozlesmesinden). */
export interface NextLeagueInfo {
  leagueCode: string
  leagueName: string
  threshold: number
}

export interface LeagueRankingDto {
  status: LeaguePageStatus
  gradeLevel: number
  season: LeagueSeasonInfo | null
  my: OwnLeagueCard | null
  entries: RankedStudent[]
  total: number
  nextLeague: NextLeagueInfo | null
}
