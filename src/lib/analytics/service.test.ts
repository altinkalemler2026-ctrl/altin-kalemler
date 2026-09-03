// @vitest-environment node
import { describe, expect, it, vi } from "vitest"

import {
  AnalyticsError,
  analyticsReferenceNow,
  computeTopicPriorities,
  fetchStudentAttemptTrend,
  fetchStudentDimensionSummary,
  mapAttemptTrendRow,
  mapDimensionSummaryRow,
  validateTrendDays,
  type AnalyticsClient,
} from "./service"

const SECRET_SENTINEL = "ANA-GIZLI"

/** Gizli/PII alanlar bilinçli olarak eklenmiş ham RPC satırı. */
function rawRow(overrides: Record<string, unknown> = {}) {
  return {
    scope_type: "subject",
    scope_key: "aaaaaaaa-1111-4000-8000-000000000001",
    display_name: "Matematik",
    subject_id: "aaaaaaaa-1111-4000-8000-000000000001",
    subject_name: "Matematik",
    total: 10,
    correct: 7,
    wrong: 2,
    blank: 1,
    pass_timeout: 0,
    repeat_total: 4,
    repeat_correct: 3,
    total_time_ms: 60000,
    success_rate: 70,
    repeat_success_rate: 75,
    avg_time_ms: 6000,
    last_attempted_at: "2026-08-01T10:00:00.000Z",
    correct_answer: SECRET_SENTINEL,
    solution: SECRET_SENTINEL + "-cozum",
    explanation: SECRET_SENTINEL + "-aciklama",
    email: "ogrenci@test.local",
    nickname: "ANA-NICK",
    ...overrides,
  }
}

describe("mapDimensionSummaryRow — allowlist", () => {
  it("izinli alanları camelCase DTO'ya taşır", () => {
    const mapped = mapDimensionSummaryRow(rawRow())
    expect(mapped).toMatchObject({
      scopeType: "subject",
      scopeKey: "aaaaaaaa-1111-4000-8000-000000000001",
      displayName: "Matematik",
      subjectId: "aaaaaaaa-1111-4000-8000-000000000001",
      subjectName: "Matematik",
      total: 10,
      correct: 7,
      wrong: 2,
      blank: 1,
      passTimeout: 0,
      repeatTotal: 4,
      repeatCorrect: 3,
      totalTimeMs: 60000,
      successRate: 70,
      repeatSuccessRate: 75,
      avgTimeMs: 6000,
    })
    expect(mapped?.lastAttemptedAt).toBe("2026-08-01T10:00:00.000Z")
  })

  it("gizli/PII alanların hiçbirini içermez", () => {
    const mapped = mapDimensionSummaryRow(rawRow()) as unknown as Record<
      string,
      unknown
    >
    expect(JSON.stringify(mapped)).not.toContain(SECRET_SENTINEL)
    expect(JSON.stringify(mapped)).not.toContain("ogrenci@test.local")
    for (const forbidden of [
      "correct_answer",
      "solution",
      "explanation",
      "email",
      "nickname",
    ]) {
      expect(Object.keys(mapped)).not.toContain(forbidden)
    }
  })

  it("yalnızca dört boyut kapsamını kabul eder", () => {
    expect(
      mapDimensionSummaryRow(rawRow({ scope_type: "topic" }))?.scopeType
    ).toBe("topic")
    expect(
      mapDimensionSummaryRow(rawRow({ scope_type: "subtopic" }))?.scopeType
    ).toBe("subtopic")
    expect(
      mapDimensionSummaryRow(rawRow({ scope_type: "outcome" }))?.scopeType
    ).toBe("outcome")
    expect(mapDimensionSummaryRow(rawRow({ scope_type: "difficulty" }))).toBe(
      null
    )
    expect(mapDimensionSummaryRow(rawRow({ scope_type: "yabancı" }))).toBe(null)
  })

  it("scope_key yoksa satırı atlar", () => {
    expect(
      mapDimensionSummaryRow(rawRow({ scope_key: "" }))
    ).toBeNull()
    expect(
      mapDimensionSummaryRow(rawRow({ scope_key: undefined }))
    ).toBeNull()
  })

  it("skaler olmayan girdiyi atlar", () => {
    expect(mapDimensionSummaryRow(null)).toBeNull()
    expect(mapDimensionSummaryRow("x")).toBeNull()
    expect(mapDimensionSummaryRow(0)).toBeNull()
  })
})

describe("mapDimensionSummaryRow — sağlamlık", () => {
  it("DB sayıları string gelirse sayıya çevirir", () => {
    const mapped = mapDimensionSummaryRow(
      rawRow({
        total: "10",
        correct: "7",
        success_rate: "87.5",
        repeat_success_rate: "75.0",
        avg_time_ms: "6000.0",
        total_time_ms: "60000",
      })
    )
    expect(mapped?.total).toBe(10)
    expect(mapped?.successRate).toBe(87.5)
    expect(mapped?.repeatSuccessRate).toBe(75)
    expect(mapped?.avgTimeMs).toBe(6000)
    expect(mapped?.totalTimeMs).toBe(60000)
  })

  it("bozuk sayılar deterministik 0'a düşer", () => {
    const mapped = mapDimensionSummaryRow(
      rawRow({ total: "abc", success_rate: "no", repeat_correct: null })
    )
    expect(mapped?.total).toBe(0)
    expect(mapped?.successRate).toBe(0)
    expect(mapped?.repeatCorrect).toBe(0)
  })

  it("timestamptz'i deterministik ISO (Z) biçimine normalleştirir", () => {
    const mapped = mapDimensionSummaryRow(
      rawRow({ last_attempted_at: "2026-08-01T10:00:00+00:00" })
    )
    expect(mapped?.lastAttemptedAt).toBe("2026-08-01T10:00:00.000Z")

    const nullish = mapDimensionSummaryRow(
      rawRow({ last_attempted_at: "tarih-degil" })
    )
    expect(nullish?.lastAttemptedAt).toBeNull()
  })

  it("eksik dimension'da display_name scope_key'e, subject alanları null düşer", () => {
    const mapped = mapDimensionSummaryRow(
      rawRow({ display_name: null, subject_id: null, subject_name: null })
    )
    expect(mapped?.displayName).toBe(
      "aaaaaaaa-1111-4000-8000-000000000001"
    )
    expect(mapped?.subjectId).toBeNull()
    expect(mapped?.subjectName).toBeNull()
  })
})

describe("fetchStudentDimensionSummary", () => {
  function clientWith(data: unknown, error?: unknown): AnalyticsClient {
    const rpc = vi.fn().mockResolvedValue({ data, error })
    return { rpc } as unknown as AnalyticsClient
  }

  it("RPC cevabını allowlist DTO listesine çevirir", async () => {
    const client = clientWith([rawRow(), rawRow({ scope_type: "topic" })])
    const rows = await fetchStudentDimensionSummary(client)
    expect(rows).toHaveLength(2)
    expect(rows[0]?.scopeType).toBe("subject")
    expect(rows[1]?.scopeType).toBe("topic")
  })

  it("geçersiz satırları (subtopic olmayan/difficulty vb.) atlar", async () => {
    const client = clientWith([
      rawRow(),
      rawRow({ scope_type: "difficulty" }),
      rawRow({ scope_key: "" }),
      "bozuk",
    ])
    const rows = await fetchStudentDimensionSummary(client)
    expect(rows).toHaveLength(1)
  })

  it("null/boş cevapta boş liste döner", async () => {
    expect(await fetchStudentDimensionSummary(clientWith(null))).toEqual([])
  })

  it("RPC hatasını güvenli AnalyticsError'a çevirir (ham mesaj sızmaz)", async () => {
    const client = clientWith(null, {
      message: "Kimlik dogrulamasi gerekli. Ham-DB-DETAY-0123",
      code: "P0001",
    })
    await expect(fetchStudentDimensionSummary(client)).rejects.toThrow(
      AnalyticsError
    )
    try {
      await fetchStudentDimensionSummary(client)
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : String(caught)
      expect(message).not.toContain("Ham-DB-DETAY-0123")
    }
  })

  it("oturum hatası kullanıcıya tanımlı mesajla düşer", async () => {
    const client = clientWith(null, { message: "Kimlik dogrulamasi gerekli." })
    await expect(
      fetchStudentDimensionSummary(client)
    ).rejects.toThrow("Oturumunuz doğrulanamadı")
  })

  it("permission denied/RLS hataları oturum mesajına düşer (fail-closed)", async () => {
    const client = clientWith(null, {
      message: "permission denied for function get_student_dimension_summary",
    })
    await expect(fetchStudentDimensionSummary(client)).rejects.toThrow(
      "Oturumunuz doğrulanamadı"
    )
  })

  it("bilinmeyen DB hatası genel güvenli mesaja düşer", async () => {
    const client = clientWith(null, {
      message: "internal error: şifreli-kok-db-panik",
    })
    await expect(fetchStudentDimensionSummary(client)).rejects.toThrow(
      "Beklenmeyen bir hata oluştu"
    )
  })
})

/** Gizli/PII alanlar bilinçli olarak eklenmiş ham trend satırı. */
function rawTrendRow(overrides: Record<string, unknown> = {}) {
  return {
    day: "2026-08-29",
    total: 4,
    correct: 2,
    wrong: 1,
    blank: 0,
    pass_timeout: 1,
    success_rate: 50,
    avg_time_ms: 2125,
    correct_answer: SECRET_SENTINEL,
    solution: SECRET_SENTINEL + "-cozum",
    question_text: SECRET_SENTINEL + "-soru",
    email: "ogrenci@test.local",
    ...overrides,
  }
}

describe("validateTrendDays — allowlist", () => {
  it("yalnızca 7 ve 30 kabul eder", () => {
    expect(validateTrendDays(7)).toBe(7)
    expect(validateTrendDays(30)).toBe(30)
  })

  it("diğer pencere genişlikleri fail-closed fırlatır", () => {
    for (const bad of [1, 5, 14, 31, 90, 0, -7, 8.5]) {
      expect(() => validateTrendDays(bad)).toThrow(
        "Geçersiz pencere; yalnızca 7 veya 30 günlük trend desteklenir."
      )
    }
  })
})

describe("mapAttemptTrendRow — allowlist", () => {
  it("izinli alanları camelCase DTO'ya taşır", () => {
    expect(mapAttemptTrendRow(rawTrendRow())).toEqual({
      day: "2026-08-29",
      total: 4,
      correct: 2,
      wrong: 1,
      blank: 0,
      passTimeout: 1,
      successRate: 50,
      avgTimeMs: 2125,
    })
  })

  it("gizli/PII alanların hiçbirini içermez", () => {
    const mapped = mapAttemptTrendRow(
      rawTrendRow()
    ) as unknown as Record<string, unknown>
    expect(JSON.stringify(mapped)).not.toContain(SECRET_SENTINEL)
    expect(JSON.stringify(mapped)).not.toContain("ogrenci@test.local")
    for (const forbidden of [
      "correct_answer",
      "solution",
      "question_text",
      "email",
    ]) {
      expect(Object.keys(mapped)).not.toContain(forbidden)
    }
  })

  it("gün yoksa satırı atlar", () => {
    expect(mapAttemptTrendRow(rawTrendRow({ day: "" }))).toBeNull()
    expect(mapAttemptTrendRow(rawTrendRow({ day: undefined }))).toBeNull()
    expect(mapAttemptTrendRow(rawTrendRow({ day: null }))).toBeNull()
  })

  it("skaler olmayan girdiyi atlar", () => {
    expect(mapAttemptTrendRow(null)).toBeNull()
    expect(mapAttemptTrendRow("x")).toBeNull()
    expect(mapAttemptTrendRow(0)).toBeNull()
  })
})

describe("mapAttemptTrendRow — sağlamlık", () => {
  it("DB sayıları string gelirse sayıya çevirir", () => {
    const mapped = mapAttemptTrendRow(
      rawTrendRow({
        total: "4",
        correct: "2",
        wrong: "1",
        blank: "0",
        pass_timeout: "1",
        success_rate: "50.0",
        avg_time_ms: "2125.0",
      })
    )
    expect(mapped?.total).toBe(4)
    expect(mapped?.successRate).toBe(50)
    expect(mapped?.avgTimeMs).toBe(2125)
  })

  it("bozuk sayılar deterministik 0'a düşer", () => {
    const mapped = mapAttemptTrendRow(
      rawTrendRow({ total: "abc", success_rate: "no", wrong: null })
    )
    expect(mapped?.total).toBe(0)
    expect(mapped?.successRate).toBe(0)
    expect(mapped?.wrong).toBe(0)
  })
})

describe("fetchStudentAttemptTrend", () => {
  function clientWith(data: unknown, error?: unknown): AnalyticsClient {
    const rpc = vi.fn().mockResolvedValue({ data, error })
    return { rpc } as unknown as AnalyticsClient
  }

  it("geçersiz pencere DB'ye gitmeden fail-closed fırlatır", async () => {
    const client = clientWith([])
    await expect(fetchStudentAttemptTrend(client, 14)).rejects.toThrow(
      "Geçersiz pencere"
    )
    expect(client.rpc).not.toHaveBeenCalled()
  })

  it("RPC'ye allowlist p_days iletir ve DTO listesine çevirir", async () => {
    const client = clientWith([rawTrendRow(), rawTrendRow({ day: "2026-08-28" })])
    const rows = await fetchStudentAttemptTrend(client, 7)
    expect(client.rpc).toHaveBeenCalledWith("get_student_attempt_trend", {
      p_days: 7,
    })
    expect(rows).toHaveLength(2)
    expect(rows[0]?.day).toBe("2026-08-29")
  })

  it("günü bozuk satırları atlar", async () => {
    const client = clientWith([
      rawTrendRow(),
      rawTrendRow({ day: "" }),
      "bozuk",
      null,
    ])
    const rows = await fetchStudentAttemptTrend(client, 30)
    expect(rows).toHaveLength(1)
  })

  it("null/boş cevapta boş liste döner", async () => {
    expect(await fetchStudentAttemptTrend(clientWith(null), 30)).toEqual([])
  })

  it("RPC hatasını güvenli AnalyticsError'a çevirir (ham mesaj sızmaz)", async () => {
    const client = clientWith(null, {
      message: "Gecersiz pencere; yalniz 7 veya 30 gun. Ham-DB-DETAY-0999",
      code: "22023",
    })
    await expect(fetchStudentAttemptTrend(client, 7)).rejects.toThrow(
      AnalyticsError
    )
    try {
      await fetchStudentAttemptTrend(client, 7)
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : String(caught)
      expect(message).not.toContain("Ham-DB-DETAY-0999")
    }
  })

  it("oturum hatası kullanıcıya tanımlı mesajla düşer", async () => {
    const client = clientWith(null, { message: "Kimlik dogrulamasi gerekli." })
    await expect(fetchStudentAttemptTrend(client, 7)).rejects.toThrow(
      "Oturumunuz doğrulanamadı"
    )
  })
})

// ====================================================================
// TRAINING ANALYTICS PHASE 3 — TOPIC PRIORITY (deterministic)
// ====================================================================

const REFERENCE_NOW = Date.UTC(2026, 7, 29, 12, 0, 0) // 2026-08-29T12:00:00Z

/** referenceNow'a göre n gün önceyi ISO (Z) biçiminde üretir. */
function daysAgoIso(days: number): string {
  return new Date(REFERENCE_NOW - days * 86_400_000).toISOString()
}

/** topic satırı: scope_type='topic'; defaults ile özelleştirilebilir. */
function topicRow(overrides: Record<string, unknown> = {}) {
  return {
    scope_type: "topic",
    scope_key: "bbbbbbb2-0000-4000-8000-000000000002",
    display_name: "Kümeler",
    subject_id: "bbbbbbb1-0000-4000-8000-000000000001",
    subject_name: "Matematik",
    total: 10,
    correct: 8,
    wrong: 2,
    blank: 0,
    pass_timeout: 0,
    repeat_total: 4,
    repeat_correct: 3,
    total_time_ms: 600000,
    success_rate: 80,
    repeat_success_rate: 75,
    avg_time_ms: 6000,
    last_attempted_at: daysAgoIso(3),
    correct_answer: SECRET_SENTINEL,
    solution: SECRET_SENTINEL + "-cozum",
    ...overrides,
  }
}

function row(input: Record<string, unknown>): DimensionSummaryRow {
  const r = mapDimensionSummaryRow(topicRow(input))
  if (r) return r
  throw new Error("topic row map edilemedi")
}

import type { DimensionSummaryRow } from "./types"

describe("computeTopicPriorities — band & evidence", () => {
  it("0 attempt -> INSUFFICIENT_DATA + tüm skorlar 0 (test 1)", () => {
    const [dto] = computeTopicPriorities(
      [row({ total: 0, correct: 0, success_rate: 0, last_attempted_at: null })],
      REFERENCE_NOW
    )
    expect(dto.evidenceLevel).toBe("none")
    expect(dto.performanceBand).toBe("INSUFFICIENT_DATA")
    expect(dto.weaknessScore).toBe(0)
    expect(dto.repeatScore).toBe(0)
    expect(dto.recencyScore).toBe(0)
    expect(dto.priorityScore).toBe(0)
    expect(dto.reasonCodes).toContain("INSUFFICIENT_DATA")
  })

  it("1 wrong -> WEAK DEĞİL, INSUFFICIENT_DATA (test 2)", () => {
    const [dto] = computeTopicPriorities(
      [row({ total: 1, correct: 0, wrong: 1, success_rate: 0, last_attempted_at: daysAgoIso(0) })],
      REFERENCE_NOW
    )
    expect(dto.performanceBand).toBe("INSUFFICIENT_DATA")
    expect(dto.performanceBand).not.toBe("WEAK")
  })

  it("2-4 attempts -> INSUFFICIENT_DATA, ama evidence-adjusted score korunur (test 3)", () => {
    for (const total of [2, 3, 4]) {
      const [dto] = computeTopicPriorities(
        [row({ total, correct: 0, wrong: total, success_rate: 0, last_attempted_at: daysAgoIso(0) })],
        REFERENCE_NOW
      )
      expect(dto.performanceBand).toBe("INSUFFICIENT_DATA")
      expect(dto.evidenceLevel).toBe("low")
      expect(dto.reasonCodes).toContain("INSUFFICIENT_DATA")
      expect(dto.weaknessScore).toBeGreaterThan(0)
    }
  })

  it(">=5 düşük başarı -> WEAK (test 4)", () => {
    const [dto] = computeTopicPriorities(
      [row({ total: 10, correct: 3, wrong: 7, success_rate: 30, last_attempted_at: daysAgoIso(0) })],
      REFERENCE_NOW
    )
    expect(dto.performanceBand).toBe("WEAK")
    expect(dto.reasonCodes).toContain("LOW_SUCCESS")
  })

  it(">=5 orta başarı -> DEVELOPING (test 5)", () => {
    const [dto] = computeTopicPriorities(
      [row({ total: 10, correct: 5, wrong: 5, success_rate: 50, last_attempted_at: daysAgoIso(0) })],
      REFERENCE_NOW
    )
    expect(dto.performanceBand).toBe("DEVELOPING")
  })

  it(">=5 yüksek başarı -> STRONG (test 6)", () => {
    const [dto] = computeTopicPriorities(
      [row({ total: 10, correct: 8, wrong: 2, success_rate: 80, last_attempted_at: daysAgoIso(0) })],
      REFERENCE_NOW
    )
    expect(dto.performanceBand).toBe("STRONG")
  })

  it("high evidence weak -> high priority (test 7)", () => {
    const weak = row({ total: 20, correct: 2, wrong: 18, success_rate: 10, repeat_total: 0, last_attempted_at: daysAgoIso(0) })
    const strong = row({ total: 20, correct: 18, wrong: 2, success_rate: 90, repeat_total: 0, last_attempted_at: daysAgoIso(0) })
    const [w, s] = computeTopicPriorities([strong, weak], REFERENCE_NOW)
    expect(w.priorityRank).toBe(1)
    expect(w.performanceBand).toBe("WEAK")
    expect(w.priorityScore).toBeGreaterThan(s.priorityScore)
  })
})

describe("computeTopicPriorities — repeat", () => {
  it("repeat_total=0 -> repeat_score 0 (test 11)", () => {
    const [dto] = computeTopicPriorities(
      [row({ total: 10, correct: 5, success_rate: 50, repeat_total: 0, repeat_success_rate: 0, last_attempted_at: daysAgoIso(0) })],
      REFERENCE_NOW
    )
    expect(dto.repeatScore).toBe(0)
  })

  it("poor repeat -> priority yükselir (test 9)", () => {
    const poorRepeat = row({ total: 10, correct: 6, success_rate: 60, repeat_total: 10, repeat_correct: 0, repeat_success_rate: 0, last_attempted_at: daysAgoIso(0) })
    const goodRepeat = row({ total: 10, correct: 6, success_rate: 60, repeat_total: 10, repeat_correct: 9, repeat_success_rate: 90, last_attempted_at: daysAgoIso(0) })
    const [poor, good] = computeTopicPriorities([goodRepeat, poorRepeat], REFERENCE_NOW)
    expect(poor.priorityScore).toBeGreaterThan(good.priorityScore)
  })

  it("improving repeat -> priority düşer (test 10)", () => {
    const poor = row({ total: 10, correct: 6, success_rate: 60, repeat_total: 5, repeat_correct: 1, repeat_success_rate: 20, last_attempted_at: daysAgoIso(0) })
    const improved = row({ total: 10, correct: 6, success_rate: 60, repeat_total: 5, repeat_correct: 4, repeat_success_rate: 80, last_attempted_at: daysAgoIso(0) })
    const [poorDto, improvedDto] = computeTopicPriorities([poor, improved], REFERENCE_NOW)
    // poor repeat daha yüksek öncelikte (rank 1); iyileşen daha düşük öncelikte.
    expect(poorDto.priorityScore).toBeGreaterThan(improvedDto.priorityScore)
    expect(poorDto.priorityRank).toBe(1)
    expect(improvedDto.priorityRank).toBe(2)
  })
})

describe("computeTopicPriorities — recency", () => {
  it("fresh topic (0-7 gün) -> recency 0 (test 14)", () => {
    const [dto] = computeTopicPriorities(
      [row({ total: 10, correct: 5, success_rate: 50, repeat_total: 0, last_attempted_at: daysAgoIso(2) })],
      REFERENCE_NOW
    )
    expect(dto.recencyScore).toBe(0)
  })

  it("8/15/30/60 gün kesin band sınırları (test 15)", () => {
    const cases: Array<[number, number]> = [
      [8, 25],
      [15, 50],
      [30, 75],
      [60, 100],
      // alt sınırlar
      [7, 0],
      [14, 25],
      [29, 50],
      [59, 75],
    ]
    for (const [days, expected] of cases) {
      const [dto] = computeTopicPriorities(
        [row({ total: 10, correct: 5, success_rate: 50, repeat_total: 0, last_attempted_at: daysAgoIso(days) })],
        REFERENCE_NOW
      )
      expect(dto.recencyScore).toBe(expected)
    }
  })

  it("malformed/null last_attempted -> recency 0, stale ilan edilmez (test 16)", () => {
    const [dto] = computeTopicPriorities(
      [row({ total: 10, correct: 5, success_rate: 50, repeat_total: 0, last_attempted_at: null })],
      REFERENCE_NOW
    )
    expect(dto.recencyScore).toBe(0)
    expect(dto.reasonCodes).not.toContain("STALE_TOPIC")

    const [malformed] = computeTopicPriorities(
      [row({ total: 10, correct: 5, success_rate: 50, repeat_total: 0, last_attempted_at: "tarih-degil" })],
      REFERENCE_NOW
    )
    expect(malformed.recencyScore).toBe(0)
  })

  it("stale weak -> priority yükselir (test 12)", () => {
    const freshWeak = row({ total: 10, correct: 2, success_rate: 20, repeat_total: 0, last_attempted_at: daysAgoIso(1) })
    const staleWeak = row({ total: 10, correct: 2, success_rate: 20, repeat_total: 0, last_attempted_at: daysAgoIso(45) })
    const [stale, fresh] = computeTopicPriorities([freshWeak, staleWeak], REFERENCE_NOW)
    expect(stale.priorityScore).toBeGreaterThan(fresh.priorityScore)
    expect(stale.reasonCodes).toContain("STALE_TOPIC")
  })

  it("stale strong, zayıf/developing konuları anlamsız şekilde geçmez (test 13)", () => {
    const staleStrong = row({ scope_key: "bbbbbbb2-0000-4000-8000-000000000002", display_name: "StaleStrong", total: 30, correct: 27, success_rate: 90, repeat_total: 10, repeat_correct: 9, repeat_success_rate: 90, last_attempted_at: daysAgoIso(90) })
    const weak = row({ scope_key: "bbbbbbb2-0000-4000-8000-0000000000aa", display_name: "Weak", total: 12, correct: 2, success_rate: 17, repeat_total: 0, last_attempted_at: daysAgoIso(1) })
    const developing = row({ scope_key: "bbbbbbb2-0000-4000-8000-0000000000bb", display_name: "Developing", total: 12, correct: 6, success_rate: 50, repeat_total: 0, last_attempted_at: daysAgoIso(10) })
    const ranked = computeTopicPriorities([staleStrong, weak, developing], REFERENCE_NOW)
    const strong = ranked.find((r) => r.topicId === "bbbbbbb2-0000-4000-8000-000000000002")
    const weakDto = ranked.find((r) => r.topicId === "bbbbbbb2-0000-4000-8000-0000000000aa")
    const developingDto = ranked.find((r) => r.topicId === "bbbbbbb2-0000-4000-8000-0000000000bb")
    expect(weakDto?.priorityRank).toBe(1)
    expect(developingDto?.priorityRank).toBe(2)
    expect(strong?.priorityRank).not.toBe(1)
    expect(strong?.priorityScore ?? Infinity).toBeLessThan(
      weakDto?.priorityScore ?? Infinity
    )
  })
})

describe("computeTopicPriorities — determinism & bounds", () => {
  it("time_score her zaman 0; avg_time_ms priority'yi etkilemez (test 17,18)", () => {
    const fast = row({ total: 10, correct: 5, success_rate: 50, repeat_total: 0, avg_time_ms: 100, last_attempted_at: daysAgoIso(5) })
    const slow = row({ total: 10, correct: 5, success_rate: 50, repeat_total: 0, avg_time_ms: 900000, last_attempted_at: daysAgoIso(5) })
    const [f, s] = computeTopicPriorities([fast, slow], REFERENCE_NOW)
    expect(f.timeScore).toBe(0)
    expect(s.timeScore).toBe(0)
    expect(f.priorityScore).toBe(s.priorityScore)
    expect(s.avgTimeMs).toBe(900000)
  })

  it("score her zaman 0..100 (test 19)", () => {
    for (let success = 0; success <= 100; success += 5) {
      const [dto] = computeTopicPriorities(
        [row({ total: 100, correct: Math.round((success / 100) * 100), success_rate: success, repeat_total: 100, repeat_correct: Math.round((success / 100) * 100), repeat_success_rate: success, last_attempted_at: daysAgoIso(200) })],
        REFERENCE_NOW
      )
      expect(dto.priorityScore).toBeGreaterThanOrEqual(0)
      expect(dto.priorityScore).toBeLessThanOrEqual(100)
    }
  })

  it("aynı input + aynı referenceNow -> birebir aynı çıktı (test 20)", () => {
    const rows = [
      row({ total: 10, correct: 3, success_rate: 30, repeat_total: 3, repeat_correct: 0, repeat_success_rate: 0, last_attempted_at: daysAgoIso(20) }),
      row({ total: 0, success_rate: 0, last_attempted_at: null }),
      row({ total: 12, correct: 10, success_rate: 83, repeat_total: 5, repeat_correct: 4, repeat_success_rate: 80, last_attempted_at: daysAgoIso(70) }),
    ]
    const a = computeTopicPriorities(rows, REFERENCE_NOW)
    const b = computeTopicPriorities(rows, REFERENCE_NOW)
    expect(a).toEqual(b)
  })

  it("analyticsReferenceNow istek icindeki epoch ms'i dondurur (test 25)", () => {
    vi.useFakeTimers()
    try {
      vi.setSystemTime(new Date("2026-08-29T12:00:00.000Z"))
      expect(analyticsReferenceNow()).toBe(Date.UTC(2026, 7, 29, 12, 0, 0))
    } finally {
      vi.useRealTimers()
    }
  })

  it("kararlı tie sıralaması + rank 1'den başlar (test 21)", () => {
    const r1 = row({ scope_key: "bbbbbbb2-0000-4000-8000-00000000000a", display_name: "B", total: 10, correct: 5, success_rate: 50, repeat_total: 0, last_attempted_at: daysAgoIso(0) })
    const r2 = row({ scope_key: "bbbbbbb2-0000-4000-8000-00000000000b", display_name: "A", total: 10, correct: 5, success_rate: 50, repeat_total: 0, last_attempted_at: daysAgoIso(0) })
    const out = computeTopicPriorities([r1, r2], REFERENCE_NOW)
    expect(out[0]?.topicName).toBe("A")
    expect(out[0]?.priorityRank).toBe(1)
    expect(out[1]?.priorityRank).toBe(2)
  })
})

describe("computeTopicPriorities — allowlist & robustness", () => {
  it("yalnız topic satırları kabul edilir (test 22)", () => {
    const subject = mapDimensionSummaryRow(topicRow({ scope_type: "subject" }))
    const topic = mapDimensionSummaryRow(topicRow())
    const rows = [subject, topic].filter((r): r is NonNullable<typeof r> => r !== null)
    const out = computeTopicPriorities(rows, REFERENCE_NOW)
    expect(out).toHaveLength(1)
    expect(out[0]?.topicId).toBe(topic?.scopeKey)
  })

  it("DTO allowlist / PII & soru gizli alan sızmaz (test 23)", () => {
    const [dto] = computeTopicPriorities([row({})], REFERENCE_NOW)
    const json = JSON.stringify(dto)
    expect(json).not.toContain(SECRET_SENTINEL)
    for (const forbidden of ["correct_answer", "solution", "explanation", "email", "nickname"]) {
      expect(Object.keys(dto as unknown as Record<string, unknown>)).not.toContain(forbidden)
    }
  })

  it("bozuk sayısal girdi güvenli 0'a düşer, priority bozulmaz (test 24)", () => {
    const bad = [row({ total: "abc", success_rate: "no", repeat_total: null, repeat_success_rate: "x", last_attempted_at: "bozuk" })]
    const [dto] = computeTopicPriorities(bad, REFERENCE_NOW)
    expect(dto.priorityScore).toBeGreaterThanOrEqual(0)
    expect(dto.priorityScore).toBeLessThanOrEqual(100)
    expect(dto.evidenceLevel).toBe("none")
  })

  it("boş girdi -> boş liste (test: kararlı)", () => {
    expect(computeTopicPriorities([], REFERENCE_NOW)).toEqual([])
  })
})