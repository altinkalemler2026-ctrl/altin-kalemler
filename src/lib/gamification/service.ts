/**
 * Faz 9 oyunlaştırma servis katmanı — YALNIZ server tarafı.
 *
 * Güvenlik kuralları:
 *  - Kullanıcı kimliği ALINMAZ; RPC auth.uid()'den türetir.
 *  - Değerler yalnız sunucu RPC'sinden (get_own_gamification_profile)
 *    okunur; istemci XP/seviye/seri/rozet/kota YAZAMAZ.
 *  - RPC cevabı sıkı allowlist eşleyicisinden geçer; bilinmeyen
 *    anahtar sessizce düşürülür (defense in depth).
 */

import type { SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "@/lib/supabase/types"

import type {
  DailyQuota,
  GamificationBadge,
  GamificationProfile,
  GamificationStreak,
  GamificationXp,
} from "./types"

export type GamificationClient = SupabaseClient<Database>

function asRecord(raw: unknown): Record<string, unknown> {
  return typeof raw === "object" && raw !== null
    ? (raw as Record<string, unknown>)
    : {}
}

function asInt(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.round(value)
    : fallback
}

function asOptionalInt(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.round(value)
    : null
}

export function mapGamificationXp(raw: unknown): GamificationXp {
  const record = asRecord(raw)
  const level = asInt(record.level, 1)
  const maxLevel = asInt(record.max_level, 50)
  const nextLevelRequiredTotalXp = asOptionalInt(
    record.next_level_required_total_xp
  )

  return {
    totalXp: Math.max(0, asInt(record.total, 0)),
    level: Math.min(Math.max(1, level), maxLevel),
    maxLevel,
    nextLevelRequiredTotalXp,
    xpToNextLevel: asOptionalInt(record.xp_to_next_level),
  }
}

export function mapGamificationStreak(raw: unknown): GamificationStreak {
  const record = asRecord(raw)

  return {
    current: Math.max(0, asInt(record.current, 0)),
    longest: Math.max(0, asInt(record.longest, 0)),
    lastActivityDay:
      typeof record.last_activity_day === "string"
        ? record.last_activity_day
        : null,
  }
}

export function mapDailyQuota(raw: unknown): DailyQuota {
  const record = asRecord(raw)

  return {
    day: typeof record.day === "string" ? record.day : null,
    questionsUsed: Math.max(0, asInt(record.questions_used, 0)),
    limit: asInt(record.limit, 500),
    remaining: asInt(record.remaining, 500),
  }
}

export function mapGamificationBadges(raw: unknown): GamificationBadge[] {
  if (!Array.isArray(raw)) return []

  const badges: GamificationBadge[] = []
  for (const entry of raw) {
    const record = asRecord(entry)
    if (typeof record.badge_code !== "string") continue
    if (typeof record.name !== "string") continue

    badges.push({
      badgeCode: record.badge_code,
      name: record.name,
      grantedAt:
        typeof record.granted_at === "string" ? record.granted_at : null,
    })
  }
  return badges
}

/** RPC cevabının tamamı için allowlist eşleyici. */
export function mapGamificationProfile(raw: unknown): GamificationProfile {
  const record = asRecord(raw)

  return {
    xp: mapGamificationXp(record.xp),
    streak: mapGamificationStreak(record.streak),
    dailyQuota: mapDailyQuota(record.daily_quota),
    badges: mapGamificationBadges(record.badges),
  }
}

/**
 * Öğrencinin kendi oyunlaştırma profili (yalnız gerçek değerler).
 * RPC başarısızsa hata fırlatır; çağıran sayfa hata durumunu tasarlar.
 */
export async function fetchGamificationProfile(
  client: GamificationClient
): Promise<GamificationProfile> {
  const { data, error } = await client.rpc("get_own_gamification_profile")
  if (error) throw error
  return mapGamificationProfile(data)
}

/**
 * Günlük kota dolduğunda öğrenciye gösterilen doğal Türkçe mesaj.
 * Sözleşme: kota dolunca soru verilmez; güvenli ve anlaşılır durum.
 */
export const DAILY_QUOTA_FULL_MESSAGE =
  "Bugünkü 500 soruluk çalışma hakkını doldurdun. Yarın yeniden başlayabilirsin; yarışmalarını bu sınır etkilemez."

/** Seçim RPC'sindeki kota-doldu reason sabiti (103/104). */
export const DAILY_QUOTA_FULL_REASON = "gunluk_kota_doldu"
