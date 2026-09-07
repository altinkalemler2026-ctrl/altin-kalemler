/**
 * Faz 8 Lig mapper'lari — allowlist + runtime validation.
 *
 * Guvenlik kurallari:
 *  - Supabase ham satiri/jsonb dogrudan UI'a gecmez; yalniz allowlist
 *    alanlari kopyalanir (bilinmeyen anahtarlar sessizce dusurulur).
 *  - PII sentinel degerleri (user_id, e-posta, gercek ad, okul, dogum
 *    tarihi, correct_answer vb.) bu mapper'dan ASLA gecmez.
 *  - Grade uyuşmazligi (expectedGrade verilirse) reddedilir: baska
 *    sinifin verisi DTO'ya giremez.
 *  - Puan turleri ayridir: yalnizca "rating" (lig rating) tasinir;
 *    yarisma puani, XP/level ve harcanabilir yildiz alani YOKTUR.
 */

import type {
  LeaguePageStatus,
  LeagueRankingDto,
  LeagueSeasonInfo,
  NextLeagueInfo,
  OwnLeagueCard,
  RankedStudent,
} from "./types"

export class LeagueValidationError extends Error {}

const VALID_STATUSES: readonly LeaguePageStatus[] = [
  "active",
  "no_active_season",
  "no_membership",
]

const LEAGUE_TIER_LABELS: Record<string, string> = {
  bronze: "Bronz",
  silver: "Gümüş",
  gold: "Altın",
  diamond: "Elmas",
}

/** Lig kodunu Turkce kademe etiketine cevirir (renk tek basina anlam tasimaz). */
export function leagueTierLabel(leagueCode: string | null | undefined): string {
  if (!leagueCode) return "Lig"
  return LEAGUE_TIER_LABELS[leagueCode] ?? "Lig"
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null
    ? (value as Record<string, unknown>)
    : null
}

/**
 * RPC'nin sayisal alanlari jsonb'de string gelebilir; guvenli
 * donusum. Gecersizse fallback doner.
 */
function coerceInt(value: unknown, fallback: number): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value)
  }
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value)
    if (Number.isInteger(parsed)) return parsed
  }
  return fallback
}

function coerceOptionalString(
  value: unknown
): string | null {
  return typeof value === "string" && value.length > 0 ? value : null
}

/**
 * 1-12 disi veya tamsayi olmayan grade gecersizdir (fail-closed).
 */
function assertValidGrade(value: unknown): number {
  const grade = coerceInt(value, 0)
  if (grade < 1 || grade > 12) {
    throw new LeagueValidationError("Gecersiz sinif duzeyi.")
  }
  return grade
}

/** Siralama satirini allowlist ile mapler; gecersiz satir atilir. */
export function mapRankedStudent(raw: unknown): RankedStudent | null {
  const record = asRecord(raw)
  if (!record) return null

  const rank = coerceInt(record.rank, 0)
  const rating = coerceInt(record.rating, -1)
  const nickname = coerceOptionalString(record.nickname)

  if (rank < 1 || rating < 0 || !nickname) return null

  return {
    rank,
    isCurrentStudent: record.is_current_student === true,
    nickname,
    avatarKey: coerceOptionalString(record.avatar_key),
    leagueCode: coerceOptionalString(record.league_code) ?? "",
    leagueName: coerceOptionalString(record.league_name) ?? "",
    rating,
  }
}

/** Kendi sira kartini allowlist ile mapler. */
export function mapOwnLeagueCard(raw: unknown): OwnLeagueCard | null {
  const record = asRecord(raw)
  if (!record) return null

  const hasRow = record.rank !== null && record.rank !== undefined
  if (!hasRow) return null

  const rating = coerceInt(record.rating, -1)

  return {
    rank: coerceInt(record.rank, 0) >= 1 ? coerceInt(record.rank, 0) : null,
    rating: rating >= 0 ? rating : null,
    leagueCode: coerceOptionalString(record.league_code),
    leagueName: coerceOptionalString(record.league_name),
    nickname: coerceOptionalString(record.nickname),
    avatarKey: coerceOptionalString(record.avatar_key),
  }
}

/** Sezon bilgisini allowlist ile mapler. */
export function mapLeagueSeason(raw: unknown): LeagueSeasonInfo | null {
  const record = asRecord(raw)
  if (!record) return null

  const code = coerceOptionalString(record.code)
  const name = coerceOptionalString(record.name)
  if (!code || !name) return null

  return {
    code,
    name,
    status: coerceOptionalString(record.status) ?? "",
    startsAt: coerceOptionalString(record.starts_at),
    endsAt: coerceOptionalString(record.ends_at),
  }
}

/** Sonraki lig esigini allowlist ile mapler. */
export function mapNextLeague(raw: unknown): NextLeagueInfo | null {
  const record = asRecord(raw)
  if (!record) return null

  const leagueCode = coerceOptionalString(record.league_code)
  const leagueName = coerceOptionalString(record.league_name)
  const threshold = coerceInt(record.threshold, -1)

  if (!leagueCode || !leagueName || threshold < 0) return null

  return { leagueCode, leagueName, threshold }
}

/**
 * get_my_league_ranking RPC yanitini guvenli DTO'ya cevirir.
 *
 * @param raw RPC jsonb yaniti (unknown).
 * @param expectedGrade verilirse grade uyuşmazliginda reddeder
 *        (baska sinif verisi mapper'dan gecemez).
 */
export function mapLeagueRanking(
  raw: unknown,
  expectedGrade?: number
): LeagueRankingDto {
  const record = asRecord(raw)
  if (!record) {
    throw new LeagueValidationError("Lig yaniti gecersiz.")
  }

  const statusValue = coerceOptionalString(record.season_status) ?? ""
  if (!(VALID_STATUSES as readonly string[]).includes(statusValue)) {
    throw new LeagueValidationError("Bilinmeyen lig durumu.")
  }
  const status = statusValue as LeaguePageStatus

  const gradeLevel = assertValidGrade(record.grade_level)

  if (expectedGrade !== undefined && gradeLevel !== expectedGrade) {
    throw new LeagueValidationError(
      "Grade uyuşmazlığı: baska sinif verisi reddedildi."
    )
  }

  const seasonRaw = record.season
  const season =
    status === "active" || status === "no_membership"
      ? mapLeagueSeason(seasonRaw)
      : null

  const entries = Array.isArray(record.entries)
    ? record.entries
        .map((entry) => mapRankedStudent(entry))
        .filter((entry): entry is RankedStudent => entry !== null)
    : []

  const my =
    status === "active" ? mapOwnLeagueCard(record.my) : null

  const total = coerceInt(record.total, 0)
  const nextLeague =
    status === "active" ? mapNextLeague(record.next_league) : null

  return {
    status,
    gradeLevel,
    season,
    my,
    entries,
    total: total >= 0 ? total : 0,
    nextLeague,
  }
}
