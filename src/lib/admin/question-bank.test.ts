// @vitest-environment node
/**
 * Faz 4 soru bankası okuyucu testleri.
 *
 * - parseGrade: geçersiz girdi reddedilir (enjeksiyon koruması).
 * - mapQuestionListItem / mapQuestionDetail: izinli alanlar taşınır;
 *   PII/alan dışı alanlar asla DTO'ya karışmaz.
 */

import { describe, expect, it, vi } from "vitest"
import {
  GRADES,
  QUESTION_LIST_LIMIT,
  listQuestions,
  listSubjects,
  mapQuestionDetail,
  mapQuestionListItem,
  parseGrade,
  parseUuid,
  sanitizeSearchQuery,
} from "./question-bank"

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

const PII_SENTINEL = "ANA-NICK-GIZLI"
const EMAIL_SENTINEL = "soru-bankasi-pii@test.local"
const SOLUTION_SENTINEL = "ANA-COZUM-GIZLI"

function rawRow(overrides: Record<string, unknown> = {}) {
  return {
    id: "aaaaaaaa-1111-4000-8000-000000000001",
    question_code: "TYT-MAT-001",
    question_text: "1 + 1 kaç eder?",
    exam_track: "TYT",
    grade_level: 7,
    difficulty: "easy",
    correct_answer: "B",
    created_at: "2026-08-01T10:00:00.000Z",
    option_a: "1",
    option_b: "2",
    option_c: "3",
    option_d: "4",
    option_e: "5",
    quality_level: "high",
    ownership_status: "owned",
    license_status: "approved",
    estimated_solve_time_seconds: 60,
    subject_id: "bbbbbbbb-1111-4000-8000-000000000002",
    subjects: { name: "Matematik" },
    ...overrides,
  }
}

describe("parseGrade", () => {
  it("boş/geçersiz değer null döner", () => {
    expect(parseGrade(undefined)).toBeNull()
    expect(parseGrade("")).toBeNull()
    expect(parseGrade("abc")).toBeNull()
    expect(parseGrade("13")).toBeNull()
    expect(parseGrade("0")).toBeNull()
    expect(parseGrade("-1")).toBeNull()
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

describe("mapQuestionListItem — allowlist", () => {
  it("yalnızca izinli listeleme alanlarını taşır", () => {
    const mapped = mapQuestionListItem(rawRow())
    expect(mapped).toMatchObject({
      id: "aaaaaaaa-1111-4000-8000-000000000001",
      question_code: "TYT-MAT-001",
      question_text: "1 + 1 kaç eder?",
      exam_track: "TYT",
      grade_level: 7,
      difficulty: "easy",
      correct_answer: "B",
      subject_name: "Matematik",
    })
    expect(mapped.approval_status).toBeNull()
    expect(mapped.is_active).toBe(false)
  })

  it("yaşam döngüsü alanlarını (approval_status, is_active) taşır", () => {
    const mapped = mapQuestionListItem(
      rawRow({ approval_status: "pending", is_active: false })
    )
    expect(mapped.approval_status).toBe("pending")
    expect(mapped.is_active).toBe(false)

    const approved = mapQuestionListItem(
      rawRow({ approval_status: "approved", is_active: true })
    )
    expect(approved.approval_status).toBe("approved")
    expect(approved.is_active).toBe(true)
  })

  it("gizli/PII/alan dışı alanları listeleme DTO'suna katmaz", () => {
    const mapped = mapQuestionListItem(
      rawRow({
        nickname: PII_SENTINEL,
        email: EMAIL_SENTINEL,
        solution: SOLUTION_SENTINEL,
      })
    ) as unknown as Record<string, unknown>
    const json = JSON.stringify(mapped)
    expect(json).not.toContain(PII_SENTINEL)
    expect(json).not.toContain(EMAIL_SENTINEL)
    expect(json).not.toContain(SOLUTION_SENTINEL)
    for (const forbidden of ["nickname", "email", "solution", "explanation"]) {
      expect(Object.keys(mapped)).not.toContain(forbidden)
    }
  })

  it("eksik/geçersiz subjects alanı için subject_name null olur", () => {
    expect(mapQuestionListItem(rawRow({ subjects: null })).subject_name).toBeNull()
    expect(mapQuestionListItem(rawRow({ subjects: [] })).subject_name).toBeNull()
    expect(mapQuestionListItem(rawRow({ subjects: { name: 5 } })).subject_name).toBeNull()
  })
})

describe("mapQuestionDetail — allowlist", () => {
  it("soru içeriği künyesini taşır", () => {
    const mapped = mapQuestionDetail(rawRow())
    expect(mapped).toMatchObject({
      option_a: "1",
      option_b: "2",
      option_c: "3",
      option_d: "4",
      option_e: "5",
      quality_level: "high",
      ownership_status: "owned",
      license_status: "approved",
      estimated_solve_time_seconds: 60,
      subject_id: "bbbbbbbb-1111-4000-8000-000000000002",
      subject_name: "Matematik",
    })
  })

  it("PII/alan dışı alanları detay DTO'suna katmaz", () => {
    const mapped = mapQuestionDetail(
      rawRow({
        nickname: PII_SENTINEL,
        email: EMAIL_SENTINEL,
      })
    ) as unknown as Record<string, unknown>
    const json = JSON.stringify(mapped)
    expect(json).not.toContain(PII_SENTINEL)
    expect(json).not.toContain(EMAIL_SENTINEL)
    for (const forbidden of ["nickname", "email", "solution", "explanation"]) {
      expect(Object.keys(mapped)).not.toContain(forbidden)
    }
  })

  it("null seçenek alanlarını korur", () => {
    const mapped = mapQuestionDetail(rawRow({ option_c: null }))
    expect(mapped.option_c).toBeNull()
    expect(mapped.option_a).toBe("1")
  })
})

describe("sanitizeSearchQuery", () => {
  it("boş/whitespace girdiyi undefined yapar", () => {
    expect(sanitizeSearchQuery(undefined)).toBeUndefined()
    expect(sanitizeSearchQuery("")).toBeUndefined()
    expect(sanitizeSearchQuery("   ")).toBeUndefined()
    expect(sanitizeSearchQuery(",(),()")).toBeUndefined()
  })

  it("PostgREST or dilbilgisi ayraçlarını temizler", () => {
    expect(sanitizeSearchQuery("mat, fizik")).toBe("mat fizik")
    expect(sanitizeSearchQuery("(TYT)")).toBe("TYT")
    expect(sanitizeSearchQuery("a)(b,c")).toBe("a b c")
  })

  it("uzunluğu 100 karakterle sınırlar", () => {
    const long = "a".repeat(250)
    const cleaned = sanitizeSearchQuery(long)
    expect(cleaned?.length).toBe(100)
  })
})

describe("parseUuid", () => {
  it("geçerli uuid değerini döndürür", () => {
    expect(parseUuid("aaaaaaaa-1111-4000-8000-000000000001")).toBe(
      "aaaaaaaa-1111-4000-8000-000000000001"
    )
    expect(parseUuid("AAAAAAAA-1111-4000-8000-000000000001")).toBe(
      "AAAAAAAA-1111-4000-8000-000000000001"
    )
  })

  it("geçersiz uuid girdisini reddeder", () => {
    expect(parseUuid(undefined)).toBeUndefined()
    expect(parseUuid("")).toBeUndefined()
    expect(parseUuid("   ")).toBeUndefined()
    expect(parseUuid("not-a-uuid")).toBeUndefined()
    expect(parseUuid("zzzzzzzz-1111-4000-8000-000000000001")).toBeUndefined()
  })
})

describe("listQuestions — sorgu hattı (fail-closed)", () => {
  it("veri kaynağı hatasında boş liste döner", async () => {
    createClientMock.mockResolvedValue({
      from: vi.fn(() => makeQueryMock({ data: null, error: { message: "db down" } })),
    })
    await expect(listQuestions({})).resolves.toEqual([])
  })

  it("limit sabit ile uygulanır", async () => {
    const builder = makeQueryMock({ data: [], error: null })
    const from = vi.fn(() => builder)
    createClientMock.mockResolvedValue({ from })
    await listQuestions({})
    expect(builder.limit).toHaveBeenCalledWith(QUESTION_LIST_LIMIT)
  })

  it("arama girdisi sanitizasyonla or filtresine bağlanır", async () => {
    const builder = makeQueryMock({ data: [], error: null })
    const from = vi.fn(() => builder)
    createClientMock.mockResolvedValue({ from })
    await listQuestions({ query: "mat, (TYT)" })
    expect(builder.or).toHaveBeenCalledWith(
      "question_code.ilike.%mat TYT%,question_text.ilike.%mat TYT%"
    )
  })

  it("boş arama girdisi or filtresi üretmez", async () => {
    const builder = makeQueryMock({ data: [], error: null })
    const from = vi.fn(() => builder)
    createClientMock.mockResolvedValue({ from })
    await listQuestions({ query: ",,()" })
    expect(builder.or).not.toHaveBeenCalled()
  })

  it("başarılı cevabı DTO listesine çevirir", async () => {
    const builder = makeQueryMock({ data: [rawRow()], error: null })
    const from = vi.fn(() => builder)
    createClientMock.mockResolvedValue({ from })
    const rows = await listQuestions({})
    expect(rows).toHaveLength(1)
    expect(rows[0]?.question_code).toBe("TYT-MAT-001")
    expect(rows[0]?.subject_name).toBe("Matematik")
  })
})

describe("listSubjects — sorgu hattı (fail-closed)", () => {
  it("veri kaynağı hatasında boş liste döner", async () => {
    createClientMock.mockResolvedValue({
      from: vi.fn(() => makeQueryMock({ data: null, error: { message: "db down" } })),
    })
    await expect(listSubjects()).resolves.toEqual([])
  })

  it("başarılı cevabı ders listesine çevirir", async () => {
    const builder = makeQueryMock({
      data: [
        { id: "bbbbbbb1-0000-4000-8000-000000000001", name: "Matematik" },
      ],
      error: null,
    })
    const from = vi.fn(() => builder)
    createClientMock.mockResolvedValue({ from })
    await expect(listSubjects()).resolves.toEqual([
      { id: "bbbbbbb1-0000-4000-8000-000000000001", name: "Matematik" },
    ])
  })
})
