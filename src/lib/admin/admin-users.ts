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
  /** Allowlist'li sıralama; undefined -> newest. */
  sort?: SortOption
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

/** Kullanıcı listesi sayfa boyutu (sabit ürün kararı). */
export const USER_PAGE_SIZE = 25

/** parsePage üst sınırı; from/to hesabı güvenli aralıkta kalır. */
const MAX_PAGE = 1_000_000

/**
 * Sunucu taraflı liste sonucu. `status: "error"` veri kaynağının
 * OKUNAMADIĞINI belirtir ve UI'da gerçekten boş sonuçtan AYRI gösterilir;
 * ham Supabase hata metni asla taşınmaz.
 */
export interface ListPageResult<T> {
  status: "ok" | "error"
  items: T[]
  /** Filtrelere uyan toplam kayıt sayısı (hata durumunda 0). */
  total: number
  page: number
  totalPages: number
}

/**
 * Sorgu parametresinden güvenli sayfa numarası. Negatif, sıfır, NaN,
 * ondalıklı ve boş girdiler 1'e düşer; aşırı büyük değerler MAX_PAGE'e
 * kırpılır. Sonuç her zaman >= 1 tam sayıdır.
 */
export function parsePage(value: string | undefined): number {
  const n = Number(value)
  if (!Number.isInteger(n) || n < 1) return 1
  return n > MAX_PAGE ? MAX_PAGE : n
}

/** Allowlist'li sıralama seçenekleri (yalnızca güvenli sütun). */
export const SORT_OPTIONS = ["newest", "oldest"] as const

export type SortOption = (typeof SORT_OPTIONS)[number]

/** Sıralama parametresi; geçersiz/boş girdi güvenli varsayılana düşer. */
export function parseSort(value: string | undefined): SortOption {
  return (SORT_OPTIONS as readonly string[]).includes(value ?? "")
    ? (value as SortOption)
    : "newest"
}

/**
 * Tekil kayıt sonucu. `status: "error"` veri kaynağının OKUNAMADIĞINI
 * belirtir ve "bulunamadı" (ok + item null) durumundan AYRI gösterilir;
 * ham Supabase hata metni asla taşınmaz.
 */
export interface DetailResult<T> {
  status: "ok" | "error"
  item: T | null
}

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
 * Sunucu taraflı sayfalama: önce aynı filtrelerle exact count, sonra
 * yalnızca istenen sayfa `.range(from, to)` ile çekilir. Hata durumunda
 * `status: "error"` döner; boş listeyle karışmaz.
 */
export async function listUsers(
  filter: UserFilter,
  page: number
): Promise<ListPageResult<UserListItem>> {
  const supabase = await createClient()
  const safePage = parsePage(String(page))

  let countQuery = supabase
    .from("student_profiles")
    .select("id", { count: "exact", head: true })
  if (filter.grade !== undefined && filter.grade !== null) {
    countQuery = countQuery.eq("grade_level", filter.grade)
  }
  if (filter.query) {
    countQuery = countQuery.ilike("nickname", `%${filter.query}%`)
  }

  const { count, error: countError } = await countQuery
  if (countError || count === null) {
    return { status: "error", items: [], total: 0, page: safePage, totalPages: 1 }
  }

  const total = count
  const totalPages = Math.max(1, Math.ceil(total / USER_PAGE_SIZE))
  if (total === 0 || safePage > totalPages) {
    return { status: "ok", items: [], total, page: safePage, totalPages }
  }

  const from = (safePage - 1) * USER_PAGE_SIZE
  const ascending = (filter.sort ?? "newest") === "oldest"
  let dataQuery = supabase
    .from("student_profiles")
    .select(
      "id, nickname, grade_level, created_at, student_public_profiles(is_visible, total_points, monthly_points, avatar_key)",
    )
    .order("created_at", { ascending })
    .range(from, from + USER_PAGE_SIZE - 1)

  if (filter.grade !== undefined && filter.grade !== null) {
    dataQuery = dataQuery.eq("grade_level", filter.grade)
  }
  if (filter.query) {
    dataQuery = dataQuery.ilike("nickname", `%${filter.query}%`)
  }

  const { data, error } = await dataQuery
  if (error) {
    return { status: "error", items: [], total, page: safePage, totalPages }
  }

  return {
    status: "ok",
    items: (data ?? []).map((row) => {
      const r = row as Record<string, unknown>
      const pub = Array.isArray(r.student_public_profiles)
        ? (r.student_public_profiles[0] as Record<string, unknown> | undefined)
        : null
      return mapUserListItem(r, pub ?? null)
    }),
    total,
    page: safePage,
    totalPages,
  }
}

/**
 * Tekil kullanıcı detayı — student_profiles + student_public_profiles.
 * Hata durumu `status: "error"` ile ayrıştırılır; okunamayan kayıt
 * asla "bulunamadı" gibi gösterilmez.
 */
export async function getUserDetail(
  id: string,
): Promise<DetailResult<UserDetail>> {
  const supabase = await createClient()

  const { data, error } = await supabase
    .from("student_profiles")
    .select(
      "id, nickname, grade_level, created_at, updated_at, student_public_profiles(is_visible, total_points, monthly_points, avatar_key, character_key, league_code)",
    )
    .eq("id", id)
    .maybeSingle()

  if (error) return { status: "error", item: null }
  if (!data) return { status: "ok", item: null }

  const r = data as Record<string, unknown>
  const pub = Array.isArray(r.student_public_profiles)
    ? (r.student_public_profiles[0] as Record<string, unknown> | undefined)
    : null

  return { status: "ok", item: mapUserDetail(r, pub ?? null) }
}
