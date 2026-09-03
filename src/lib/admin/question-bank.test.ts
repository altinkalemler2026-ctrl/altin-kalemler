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
  QUESTION_PAGE_SIZE,
  SORT_OPTIONS,
  getQuestionDetail,
  listQuestions,
  listSubjects,
  mapQuestionDetail,
  mapQuestionListItem,
  parseGrade,
  parsePage,
  parseSort,
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
    "range",
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

  it("license_status alanını taşır (telif riski göstergesi için)", () => {
    expect(mapQuestionListItem(rawRow()).license_status).toBe("approved")
    expect(
      mapQuestionListItem(rawRow({ license_status: "under_review" }))
        .license_status
    ).toBe("under_review")
    expect(mapQuestionListItem(rawRow({ license_status: null })).license_status).toBeNull()
    expect(
      mapQuestionListItem(rawRow({ license_status: 42 })).license_status
    ).toBeNull()
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

describe("parsePage", () => {
  it("boş/geçersiz/ondalıklı/negatif girdiler 1 döner", () => {
    for (const bad of [undefined, "", "abc", "0", "-3", "2.5", "1e3x"]) {
      expect(parsePage(bad)).toBe(1)
    }
  })

  it("geçerli sayfa numarasını korur", () => {
    expect(parsePage("3")).toBe(3)
    expect(parsePage("12")).toBe(12)
  })

  it("aşırı büyük değerleri güvenli üst sınıra kırpılır", () => {
    expect(parsePage("99999999999")).toBe(1_000_000)
  })
})

describe("parseSort", () => {
  it("boş/geçersiz girdiler varsayılan 'newest'e düşer", () => {
    for (const bad of [undefined, "", "abc", "OLDEST", "ascending"]) {
      expect(parseSort(bad)).toBe("newest")
    }
  })

  it("yalnızca allowlist değerlerini kabul eder", () => {
    expect(parseSort("oldest")).toBe("oldest")
    expect(parseSort("newest")).toBe("newest")
    expect(SORT_OPTIONS).toEqual(["newest", "oldest"])
  })
})

describe("listQuestions — sıralama", () => {
  it("varsayılan sıralama created_at DESC'tir", async () => {
    const builder = makeQueryMock({ data: [], error: null, count: 60 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await listQuestions({ sort: "newest" }, 1)
    expect(builder.order).toHaveBeenCalledWith("created_at", {
      ascending: false,
    })
  })

  it("oldest sıralama created_at ASC'e çevrilir", async () => {
    const builder = makeQueryMock({ data: [], error: null, count: 60 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await listQuestions({ sort: "oldest" }, 1)
    expect(builder.order).toHaveBeenCalledWith("created_at", {
      ascending: true,
    })
  })
})

describe("getQuestionDetail — hata/bulunamadı ayrımı", () => {
  it("veri kaynağı hatasında status:'error' döner", async () => {
    const builder = makeQueryMock({
      data: null,
      error: { message: "db down" },
    })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const result = await getQuestionDetail("q1")
    expect(result.status).toBe("error")
    expect(result.item).toBeNull()
  })

  it("bulunamayan soruda ok + null döner (hata ile karışmaz)", async () => {
    const builder = makeQueryMock({ data: null, error: null })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const result = await getQuestionDetail("q1")
    expect(result.status).toBe("ok")
    expect(result.item).toBeNull()
  })

  it("başarılı cevabı detay DTO'suna çevirir", async () => {
    const builder = makeQueryMock({ data: rawRow(), error: null })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const result = await getQuestionDetail("q1")
    expect(result.status).toBe("ok")
    expect(result.item?.question_code).toBe("TYT-MAT-001")
    expect(result.item?.license_status).toBe("approved")
    expect(result.item?.subject_name).toBe("Matematik")
  })
})

describe("listQuestions — sayfalama ve fail-closed", () => {
  it("count hatasında status:'error' döner (boş liste ≠ hata)", async () => {
    const builder = makeQueryMock({
      data: null,
      error: { message: "db down" },
      count: null,
    })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const result = await listQuestions({}, 1)
    expect(result.status).toBe("error")
    expect(result.items).toEqual([])
    expect(result.total).toBe(0)
  })

  it("toplam 0 kayıt: ok + boş liste + totalPages 1 + veri sorgusu yok", async () => {
    const builder = makeQueryMock({ data: null, error: null, count: 0 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const result = await listQuestions({}, 1)
    expect(result.status).toBe("ok")
    expect(result.items).toEqual([])
    expect(result.total).toBe(0)
    expect(result.totalPages).toBe(1)
    expect(builder.range).not.toHaveBeenCalled()
  })

  it("varsayılan sayfa için doğru range uygulanır", async () => {
    const builder = makeQueryMock({ data: [], error: null, count: 60 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const result = await listQuestions({}, 1)
    expect(builder.range).toHaveBeenCalledWith(0, QUESTION_PAGE_SIZE - 1)
    expect(result.status).toBe("ok")
    expect(result.page).toBe(1)
    expect(result.totalPages).toBe(3)
  })

  it("ikinci sayfa için doğru range uygulanır", async () => {
    const builder = makeQueryMock({ data: [], error: null, count: 60 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const result = await listQuestions({}, 2)
    expect(builder.range).toHaveBeenCalledWith(
      QUESTION_PAGE_SIZE,
      QUESTION_PAGE_SIZE * 2 - 1
    )
    expect(result.page).toBe(2)
  })

  it("son sayfada eksik kayıt aralığı (total 27, page 2)", async () => {
    const builder = makeQueryMock({ data: [], error: null, count: 27 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const result = await listQuestions({}, 2)
    expect(builder.range).toHaveBeenCalledWith(25, 49)
    expect(result.totalPages).toBe(2)
  })

  it("istenen sayfa son sayfayı aşıyorsa veri çekilmez", async () => {
    const builder = makeQueryMock({ data: [rawRow()], error: null, count: 10 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const result = await listQuestions({}, 99)
    expect(result.status).toBe("ok")
    expect(result.items).toEqual([])
    expect(result.page).toBe(99)
    expect(builder.range).not.toHaveBeenCalled()
  })

  it("veri sorgusu hatasında status:'error' döner ve total korunur", async () => {
    const countBuilder = makeQueryMock({ data: null, error: null, count: 40 })
    const dataBuilder = makeQueryMock({
      data: null,
      error: { message: "db down" },
    })
    const from = vi
      .fn()
      .mockReturnValueOnce(countBuilder)
      .mockReturnValueOnce(dataBuilder)
    createClientMock.mockResolvedValue({ from })
    const result = await listQuestions({}, 1)
    expect(result.status).toBe("error")
    expect(result.total).toBe(40)
    expect(result.totalPages).toBe(2)
  })

  it("arama girdisi sanitizasyonla or filtresine bağlanır", async () => {
    const builder = makeQueryMock({ data: [], error: null, count: 60 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await listQuestions({ query: "mat, (TYT)" }, 1)
    expect(builder.or).toHaveBeenCalledWith(
      "question_code.ilike.%mat TYT%,question_text.ilike.%mat TYT%"
    )
  })

  it("boş arama girdisi or filtresi üretmez", async () => {
    const builder = makeQueryMock({ data: [], error: null, count: 60 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    await listQuestions({ query: ",,()" }, 1)
    expect(builder.or).not.toHaveBeenCalled()
  })

  it("başarılı cevabı DTO listesine çevirir", async () => {
    const builder = makeQueryMock({ data: [rawRow()], error: null, count: 1 })
    createClientMock.mockResolvedValue({ from: vi.fn(() => builder) })
    const result = await listQuestions({}, 1)
    expect(result.status).toBe("ok")
    expect(result.items).toHaveLength(1)
    expect(result.items[0]?.question_code).toBe("TYT-MAT-001")
    expect(result.items[0]?.subject_name).toBe("Matematik")
    expect(result.total).toBe(1)
    expect(result.totalPages).toBe(1)
  })
})

describe("listSubjects — sorgu hattı (hata/başarı ayrımı)", () => {
  it("veri kaynağı hatasında status:'error' + boş liste döner", async () => {
    createClientMock.mockResolvedValue({
      from: vi.fn(() => makeQueryMock({ data: null, error: { message: "db down" } })),
    })
    const result = await listSubjects()
    expect(result.status).toBe("error")
    expect(result.subjects).toEqual([])
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
    const result = await listSubjects()
    expect(result.status).toBe("ok")
    expect(result.subjects).toEqual([
      { id: "bbbbbbb1-0000-4000-8000-000000000001", name: "Matematik" },
    ])
  })
})
