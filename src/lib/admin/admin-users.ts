import { createClient } from "@/lib/supabase/server"

/**
 * Phase 3 admin users salt-okunur okuyucuları.
 *
 * - Yalnızca admin panelinden çağrılır (layout, users.manage yetkisini
 *   doğrular). RLS, satır görünürlüğünü yönetir:
 *     - users.manage sahibi admin: tüm student_profiles / student_public_profiles
 *       satırlarını görür.
 *     - admin olmayan authenticated: yalnızca mevcut öğrenci politikalarının
 *       izin verdiği satırları görür.
 * - Filtreler isteğe bağlıdır; doğrulanmış parametre değerleri kullanılır.
 * - Gizli/PII alan hiçbir koşulda taşınmaz.
 */

export const GRADES = [5, 6, 7, 8, 9, 10, 11, 12] as const

export type UserFilter = {
  grade?: number
  query?: string
}

/** Kullanıcı listesi DTO — yalnızca izinli alanlar. */
export interface UserListItem {
  id: string
  nickname: string
  grade_level: number
  created_at: string
  is_visible: boolean | null
  total_points: number | null
  monthly_points: number | null
  avatar_key: string | null
}

/** Kullanıcı detay DTO — listeye ek safe alanlar. */
export interface UserDetail extends UserListItem {
  updated_at: string
  character_key: string | null
  league_code: string | null
}

/**
 * Ham student_profiles + student_public_profiles satırından
 * yalnızca izinli listeleme alanlarını okur.
 */
export function mapUserListItem(
  profilesRow: Record<string, unknown>,
  publicRow: Record<string, unknown> | null,
): UserListItem {
  return {
    id: typeof profilesRow.id === "string" ? profilesRow.id : "",
    nickname: typeof profilesRow.nickname === "string" ? profilesRow.nickname : "",
    grade_level:
      typeof profilesRow.grade_level === "number" ? profilesRow.grade_level : 0,
    created_at:
      typeof profilesRow.created_at === "string" ? profilesRow.created_at : "",
    is_visible:
      publicRow && typeof publicRow.is_visible === "boolean"
        ? publicRow.is_visible
        : null,
    total_points:
      publicRow && typeof publicRow.total_points === "number"
        ? publicRow.total_points
        : null,
    monthly_points:
      publicRow && typeof publicRow.monthly_points === "number"
        ? publicRow.monthly_points
        : null,
    avatar_key:
      publicRow && typeof publicRow.avatar_key === "string"
        ? publicRow.avatar_key
        : null,
  }
}

/**
 * Ham student_profiles + student_public_profiles satırından
 * yalnızca izinli detay alanlarını okur.
 */
export function mapUserDetail(
  profilesRow: Record<string, unknown>,
  publicRow: Record<string, unknown> | null,
): UserDetail {
  const base = mapUserListItem(profilesRow, publicRow)
  return {
    ...base,
    updated_at:
      typeof profilesRow.updated_at === "string" ? profilesRow.updated_at : "",
    character_key:
      publicRow && typeof publicRow.character_key === "string"
        ? publicRow.character_key
        : null,
    league_code:
      publicRow && typeof publicRow.league_code === "string"
        ? publicRow.league_code
        : null,
  }
}

/**
 * Sorgu parametresinden güvenli sınıf değeri (geçersizse null).
 */
export function parseGrade(value: string | undefined): number | null {
  if (!value) return null
  const n = Number(value)
  return Number.isInteger(n) && GRADES.includes(n as (typeof GRADES)[number])
    ? n
    : null
}

/** Liste sorgularının sabit güvenli üst sınırı. */
export const USER_LIST_LIMIT = 200

/**
 * Kullanıcı sayısı — admin SELECT politikası üzerinden student_profiles
 * satır sayısı. Hata veya okunamayan sayı `null` döner (0 değil); UI
 * "okunamadı" durumunu 0'dan ayrıştırır.
 */
export async function countUsers(): Promise<number | null> {
  const supabase = await createClient()
  const { count, error } = await supabase
    .from("student_profiles")
    .select("id", { count: "exact", head: true })
  if (error || count === null) return null
  return count
}

/**
 * Kullanıcı listesi — student_profiles + student_public_profiles JOIN.
 * Limit 200 ile geniş bir listeden arama yapılabilir.
 */
export async function listUsers(
  filter: UserFilter,
): Promise<UserListItem[]> {
  const supabase = await createClient()

  let query = supabase
    .from("student_profiles")
    .select(
      "id, nickname, grade_level, created_at, student_public_profiles(is_visible, total_points, monthly_points, avatar_key)",
    )
    .order("created_at", { ascending: false })
    .limit(USER_LIST_LIMIT)

  if (filter.grade !== undefined && filter.grade !== null) {
    query = query.eq("grade_level", filter.grade)
  }
  if (filter.query) {
    query = query.ilike("nickname", `%${filter.query}%`)
  }

  const { data, error } = await query
  if (error) return []

  return (data ?? []).map((row) => {
    const r = row as Record<string, unknown>
    const pub = Array.isArray(r.student_public_profiles)
      ? (r.student_public_profiles[0] as Record<string, unknown> | undefined)
      : null
    return mapUserListItem(r, pub ?? null)
  })
}

/**
 * Tekil kullanıcı detayı — student_profiles + student_public_profiles.
 */
export async function getUserDetail(
  id: string,
): Promise<UserDetail | null> {
  const supabase = await createClient()

  const { data, error } = await supabase
    .from("student_profiles")
    .select(
      "id, nickname, grade_level, created_at, updated_at, student_public_profiles(is_visible, total_points, monthly_points, avatar_key, character_key, league_code)",
    )
    .eq("id", id)
    .maybeSingle()

  if (error || !data) return null

  const r = data as Record<string, unknown>
  const pub = Array.isArray(r.student_public_profiles)
    ? (r.student_public_profiles[0] as Record<string, unknown> | undefined)
    : null

  return mapUserDetail(r, pub ?? null)
}
