import { describe, expect, it, vi } from "vitest"
import {
  GRADES,
  USER_LIST_LIMIT,
  countUsers,
  getUserDetail,
  listUsers,
  mapUserDetail,
  mapUserListItem,
  parseGrade,
} from "./admin-users"

const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

/** Supabase sorgu zinciri için thenable sahte kurucu. */
function makeQueryMock(result: {
  data: unknown
  error: unknown
  count?: number | null
}) {
  const builder: Record<string, unknown> = {}
  const promise = Promise.resolve(result)
  for (const method of [
    "select",
    "order",
    "limit",
    "eq",
    "or",
    "ilike",
    "maybeSingle",
  ]) {
    builder[method] = vi.fn(() => builder)
  }
  builder.then = promise.then.bind(promise)
  builder.catch = promise.catch.bind(promise)
  builder.finally = promise.finally.bind(promise)
  return builder
}

describe("parseGrade", () => {
  it("boş/geçersiz değer null döner", () => {
    expect(parseGrade(undefined)).toBeNull()
    expect(parseGrade("")).toBeNull()
    expect(parseGrade("abc")).toBeNull()
    expect(parseGrade("13")).toBeNull()
  })

  it("geçerli sınıf değerini sayıya çevirir", () => {
    expect(parseGrade("7")).toBe(7)
  })

  it("tüm izinli sınıf aralığını kabul eder", () => {
    for (const g of GRADES) {
      expect(parseGrade(String(g))).toBe(g)
    }
  })
})

describe("mapUserListItem — allowlist", () => {
  const profiles = {
    id: "u1",
    nickname: "ali",
    grade_level: 7,
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-02T00:00:00Z",
    // sensitives that must NEVER leak
    schedule_profile_id: "secret-schedule",
  }
  const publicRow = {
    user_id: "u1",
    is_visible: true,
    total_points: 120,
    monthly_points: 30,
    avatar_key: "av.png",
    character_key: "ch",
    league_code: "gold",
    // PII / internals that must never leak
    metadata: { email: "ali@example.com" },
    badges: ["x"],
    cosmetics: {},
  }

  it("yalnızca izinli listeleme alanlarını taşır", () => {
    const item = mapUserListItem(profiles, publicRow)
    expect(item.id).toBe("u1")
    expect(item.nickname).toBe("ali")
    expect(item.grade_level).toBe(7)
    expect(item.created_at).toBe("2026-01-01T00:00:00Z")
    expect(item.is_visible).toBe(true)
    expect(item.total_points).toBe(120)
    expect(item.monthly_points).toBe(30)
    expect(item.avatar_key).toBe("av.png")
  })

  it("izinsiz/PII alanlarını DTO'ya taşımaz", () => {
    const item = mapUserListItem(profiles, publicRow)
    expect("metadata" in item).toBe(false)
    expect("badges" in item).toBe(false)
    expect("cosmetics" in item).toBe(false)
    expect("character_key" in item).toBe(false)
    expect("league_code" in item).toBe(false)
    expect("schedule_profile_id" in item).toBe(false)
    expect("updated_at" in item).toBe(false)
    expect("user_id" in item).toBe(false)
    expect("email" in item).toBe(false)
  })

  it("public satır yoksa puan/görünürlük null olur", () => {
    const item = mapUserListItem(profiles, null)
    expect(item.total_points).toBeNull()
    expect(item.monthly_points).toBeNull()
    expect(item.is_visible).toBeNull()
    expect(item.avatar_key).toBeNull()
  })

  it("eksik public alanlarını null olarak korur", () => {
    const item = mapUserListItem(profiles, { is_visible: false })
    expect(item.is_visible).toBe(false)
    expect(item.total_points).toBeNull()
    expect(item.monthly_points).toBeNull()
  })
})

describe("mapUserDetail — allowlist", () => {
  const profiles = {
    id: "u1",
    nickname: "ali",
    grade_level: 8,
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-02T00:00:00Z",
  }
  const publicRow = {
    is_visible: false,
    total_points: 10,
    monthly_points: 2,
    avatar_key: null,
    character_key: "knight",
    league_code: "silver",
  }

  it("detay için safe alanları taşır", () => {
    const d = mapUserDetail(profiles, publicRow)
    expect(d.id).toBe("u1")
    expect(d.nickname).toBe("ali")
    expect(d.grade_level).toBe(8)
    expect(d.updated_at).toBe("2026-01-02T00:00:00Z")
    expect(d.character_key).toBe("knight")
    expect(d.league_code).toBe("silver")
    expect(d.avatar_key).toBeNull()
  })

  it("detay PII alanı taşımaz", () => {
    const d = mapUserDetail(profiles, {
      ...publicRow,
      metadata: { email: "x@y.com" },
    })
    expect("metadata" in d).toBe(false)
    expect("email" in d).toBe(false)
  })

  it("eksik public alanları null olur", () => {
    const d = mapUserDetail(profiles, null)
    expect(d.character_key).toBeNull()
    expect(d.league_code).toBeNull()
    expect(d.total_points).toBeNull()
    expect(d.is_visible).toBeNull()
    expect(d.updated_at).toBe("2026-01-02T00:00:00Z")
  })
})

describe("countUsers", () => {
  it("başarılı sayımı döndürür", async () => {
    const builder = makeQueryMock({ data: null, error: null, count: 42 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await expect(countUsers()).resolves.toBe(42)
  })

  it("veri kaynağı hatasında null döner (0 değil)", async () => {
    const builder = makeQueryMock({
      data: null,
      error: { message: "permission denied" },
      count: null,
    })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await expect(countUsers()).resolves.toBeNull()
  })

  it("okunamayan sayı null döner", async () => {
    const builder = makeQueryMock({ data: null, error: null, count: null })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await expect(countUsers()).resolves.toBeNull()
  })
})

describe("listUsers — sorgu hattı (fail-closed)", () => {
  it("veri kaynağı hatasında boş liste döner", async () => {
    const builder = makeQueryMock({
      data: null,
      error: { message: "db down" },
    })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await expect(listUsers({})).resolves.toEqual([])
  })

  it("limit sabit ile uygulanır", async () => {
    const builder = makeQueryMock({ data: [], error: null })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await listUsers({})
    expect(builder.limit).toHaveBeenCalledWith(USER_LIST_LIMIT)
  })

  it("arama ve sınıf filtrelerini zincire ekler", async () => {
    const builder = makeQueryMock({ data: [], error: null })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await listUsers({ grade: 7, query: "ali" })
    expect(builder.eq).toHaveBeenCalledWith("grade_level", 7)
    expect(builder.ilike).toHaveBeenCalledWith("nickname", "%ali%")
  })

  it("public alt satırını DTO'ya çevirir", async () => {
    const row = {
      id: "u1",
      nickname: "ali",
      grade_level: 7,
      created_at: "2026-01-01T00:00:00Z",
      student_public_profiles: [
        { is_visible: true, total_points: 120, monthly_points: 30, avatar_key: "av.png" },
      ],
    }
    const builder = makeQueryMock({ data: [row], error: null })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const items = await listUsers({})
    expect(items).toHaveLength(1)
    expect(items[0]?.nickname).toBe("ali")
    expect(items[0]?.total_points).toBe(120)
  })
})

describe("getUserDetail — sorgu hattı (fail-closed)", () => {
  it("veri kaynağı hatasında null döner", async () => {
    const builder = makeQueryMock({
      data: null,
      error: { message: "db down" },
    })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await expect(getUserDetail("u1")).resolves.toBeNull()
  })

  it("bulunamayan kullanıcıda null döner", async () => {
    const builder = makeQueryMock({ data: null, error: null })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await expect(getUserDetail("u1")).resolves.toBeNull()
  })

  it("başarılı cevabı detay DTO'suna çevirir", async () => {
    const row = {
      id: "u1",
      nickname: "ali",
      grade_level: 8,
      created_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-01-02T00:00:00Z",
      student_public_profiles: [
        {
          is_visible: false,
          total_points: 10,
          monthly_points: 2,
          avatar_key: null,
          character_key: "knight",
          league_code: "silver",
        },
      ],
    }
    const builder = makeQueryMock({ data: row, error: null })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const detail = await getUserDetail("u1")
    expect(detail?.character_key).toBe("knight")
    expect(detail?.league_code).toBe("silver")
    expect(detail?.avatar_key).toBeNull()
  })
})
