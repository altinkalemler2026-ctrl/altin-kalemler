/**
 * Faz 6 review servis testleri.
 *
 * - Sıkı allowlist mapper: PII/gizli alan düşürme, bozuk satır atlama.
 * - Eşik davranışı: success_rate NULL (yetersiz veri) ve redeem_rate
 *   NULL (payda < 5) korunur — yanıltıcı yüzde UI'a taşınmaz.
 * - RPC sözleşmesi: user_id ASLA gönderilmez; p_limit 1..10 clamp.
 * - reason fail-closed değerleri: gecersiz_kapsam / tekrar_gerekmiyor.
 * - Determinizm: aynı girdi → aynı DTO.
 */

import { describe, expect, it } from "vitest"

import {
  fetchOutcomeReviewPlan,
  mapOutcomeReviewRow,
  startTargetedReview,
  ReviewValidationError,
  type ReviewClient,
} from "./service"
import { clampReviewLimit, MIN_REDEEM_EVIDENCE } from "./types"

const SECRET_SENTINEL = "TUI-GIZLI-VERI"

const SUBJECT_ID = "430903f3-527e-4e12-b7e8-ac0afdb784aa"
const OUTCOME_ID = "22222222-2222-4222-8222-000000000001"

function rawOutcomeRow(overrides: Record<string, unknown> = {}) {
  return {
    outcome_id: OUTCOME_ID,
    outcome_text: "Kesirlerle toplama yapar",
    band: "weak",
    total_attempts: 12,
    success_rate: 33.3,
    repeat_total: 4,
    repeat_success_rate: 50,
    pending_errors: 3,
    redeemed: 2,
    redeem_rate: 40,
    last_reviewed_at: "2099-01-02T03:04:05+00:00",
    // Bilinçli ekstra/PII alanlar — mapper düşürmeli:
    internal_note: SECRET_SENTINEL,
    correct_answer: SECRET_SENTINEL,
    ...overrides,
  }
}

describe("mapOutcomeReviewRow — allowlist", () => {
  it("izinli alanları taşır; gizli alanları düşürür", () => {
    const mapped = mapOutcomeReviewRow(rawOutcomeRow())

    expect(mapped?.outcomeId).toBe(OUTCOME_ID)
    expect(mapped?.outcomeText).toBe("Kesirlerle toplama yapar")
    expect(mapped?.band).toBe("weak")
    expect(mapped?.totalAttempts).toBe(12)
    expect(mapped?.successRate).toBe(33.3)
    expect(mapped?.pendingErrors).toBe(3)
    expect(mapped?.redeemed).toBe(2)
    expect(mapped?.redeemRate).toBe(40)
    expect(mapped?.lastReviewedAt).toBe("2099-01-02T03:04:05.000Z")
    expect(JSON.stringify(mapped)).not.toContain(SECRET_SENTINEL)
  })

  it("yetersiz veride success_rate NULL kalır (yanıltıcı yüzde engellenir)", () => {
    const mapped = mapOutcomeReviewRow(
      rawOutcomeRow({
        band: "insufficient_data",
        total_attempts: 2,
        success_rate: null,
      })
    )

    expect(mapped?.band).toBe("insufficient_data")
    expect(mapped?.successRate).toBeNull()
  })

  it("payda MIN_REDEEM_EVIDENCE altındaysa redeem_rate NULL kalır", () => {
    const mapped = mapOutcomeReviewRow(
      rawOutcomeRow({ pending_errors: 1, redeemed: 1, redeem_rate: null })
    )

    expect(1 + 1).toBeLessThan(MIN_REDEEM_EVIDENCE)
    expect(mapped?.redeemRate).toBeNull()
  })

  it("bozuk band veya bozuk id içeren satır null döner (satır atlanır)", () => {
    expect(mapOutcomeReviewRow(rawOutcomeRow({ band: "hack" }))).toBeNull()
    expect(mapOutcomeReviewRow(rawOutcomeRow({ outcome_id: "bozuk" }))).toBeNull()
    expect(mapOutcomeReviewRow(rawOutcomeRow({ outcome_text: "  " }))).toBeNull()
    expect(mapOutcomeReviewRow(null)).toBeNull()
    expect(mapOutcomeReviewRow("garbage")).toBeNull()
  })

  it("deterministiktir: aynı girdi → aynı çıktı", () => {
    const a = mapOutcomeReviewRow(rawOutcomeRow())
    const b = mapOutcomeReviewRow(rawOutcomeRow())
    expect(a).toEqual(b)
  })
})

function createRpcCaptureClient(result: {
  data?: unknown
  error?: { message: string } | null
}) {
  const calls: Array<{ fn: string; args?: Record<string, unknown> }> = []

  const client = {
    rpc(fnName: string, args?: Record<string, unknown>) {
      calls.push({ fn: fnName, args })
      return Promise.resolve({
        data: result.data ?? null,
        error: result.error ?? null,
      })
    },
  }

  return { client: client as unknown as ReviewClient, calls }
}

describe("fetchOutcomeReviewPlan — RPC sözleşmesi", () => {
  it("satırları güvenli DTO'ya çevirir; bozuk satır düşer", async () => {
    const { client, calls } = createRpcCaptureClient({
      data: [
        rawOutcomeRow(),
        rawOutcomeRow({ band: "hack" }),
        "garbage",
      ],
    })

    const plan = await fetchOutcomeReviewPlan(client, SUBJECT_ID)

    expect(calls).toHaveLength(1)
    expect(calls[0].fn).toBe("get_outcome_review_plan")
    expect(calls[0].args?.p_subject_id).toBe(SUBJECT_ID)
    expect(calls[0].args?.p_user_id).toBeUndefined()
    expect(plan).toHaveLength(1)
    expect(JSON.stringify(plan)).not.toContain(SECRET_SENTINEL)
  })

  it("boş plan boş dizi döner; RPC hatası olduğu gibi fırlatır", async () => {
    const empty = createRpcCaptureClient({ data: [] })
    await expect(
      fetchOutcomeReviewPlan(empty.client, SUBJECT_ID)
    ).resolves.toEqual([])

    const failing = createRpcCaptureClient({
      error: {
        message:
          "Gecerli akademik donem bulunamadi; soru akisi fail-closed olarak durduruldu.",
      },
    })
    await expect(
      fetchOutcomeReviewPlan(failing.client, SUBJECT_ID)
    ).rejects.toThrow(/akademik donem bulunamadi/i)
  })

  it("geçersiz UUID ReviewValidationError fırlatır; RPC çağrılmaz", async () => {
    const { client, calls } = createRpcCaptureClient({ data: null })

    await expect(
      fetchOutcomeReviewPlan(client, "not-a-uuid")
    ).rejects.toBeInstanceOf(ReviewValidationError)

    expect(calls).toHaveLength(0)
  })
})

describe("startTargetedReview — RPC sözleşmesi", () => {
  it("soruları allowlist ile eşler; gizli değer sızmaz; user_id gönderilmez", async () => {
    const { client, calls } = createRpcCaptureClient({
      data: {
        questions: [
          {
            id: "33333333-3333-3333-3333-000000000001",
            question_code: "TQ-01",
            question_text: "3/4 + 1/4 kaçtır?",
            option_a: "1",
            option_b: "1/2",
            option_c: "4/8",
            option_d: "3/8",
            option_e: null,
            correct_answer: SECRET_SENTINEL,
            solution: SECRET_SENTINEL,
          },
        ],
        session_kind: "targeted_review",
        outcome_id: OUTCOME_ID,
        wrong_review_count: 1,
        new_count: 0,
        reason: null,
        weekly: {
          academic_year: "QA-Y-2099",
          week: 5,
          subject_id: SUBJECT_ID,
          new_questions_used: 2,
          limit: 500,
        },
      },
    })

    const selection = await startTargetedReview(
      client,
      SUBJECT_ID,
      OUTCOME_ID
    )

    expect(calls).toHaveLength(1)
    expect(calls[0].fn).toBe("select_targeted_review_questions")
    expect(Object.keys(calls[0].args ?? {}).sort()).toEqual(
      ["p_limit", "p_outcome_id", "p_subject_id"].sort()
    )
    expect(calls[0].args?.p_user_id).toBeUndefined()
    expect(calls[0].args?.p_limit).toBe(5)

    expect(selection.sessionKind).toBe("targeted_review")
    expect(selection.outcomeId).toBe(OUTCOME_ID)
    expect(selection.wrongReviewCount).toBe(1)
    expect(selection.newCount).toBe(0)
    expect(selection.reason).toBeNull()
    expect(selection.weekly.week).toBe(5)
    expect(selection.questions).toHaveLength(1)
    expect(JSON.stringify(selection)).not.toContain(SECRET_SENTINEL)
  })

  it("fail-closed reason değerleri aynen taşınır; bilinmeyen reason null'a düşer", async () => {
    for (const reason of ["gecersiz_kapsam", "tekrar_gerekmiyor"] as const) {
      const { client } = createRpcCaptureClient({
        data: {
          questions: [],
          session_kind: "targeted_review",
          outcome_id: OUTCOME_ID,
          wrong_review_count: 0,
          new_count: 0,
          reason,
          weekly: {},
        },
      })

      const selection = await startTargetedReview(
        client,
        SUBJECT_ID,
        OUTCOME_ID
      )
      expect(selection.reason).toBe(reason)
      expect(selection.questions).toHaveLength(0)
    }

    const unknown = createRpcCaptureClient({
      data: {
        questions: [],
        session_kind: "targeted_review",
        outcome_id: OUTCOME_ID,
        wrong_review_count: 0,
        new_count: 0,
        reason: "saldiri_degeri",
        weekly: {},
      },
    })
    const selection = await startTargetedReview(
      unknown.client,
      SUBJECT_ID,
      OUTCOME_ID
    )
    expect(selection.reason).toBeNull()
  })

  it("p_limit 1..10 aralığına sıkıştırılır (clampReviewLimit)", async () => {
    expect(clampReviewLimit(0)).toBe(1)
    expect(clampReviewLimit(11)).toBe(10)
    expect(clampReviewLimit(7)).toBe(7)
    expect(clampReviewLimit(Number.NaN)).toBe(5)

    const { client, calls } = createRpcCaptureClient({
      data: {
        questions: [],
        session_kind: "targeted_review",
        outcome_id: OUTCOME_ID,
        wrong_review_count: 0,
        new_count: 0,
        reason: "tekrar_gerekmiyor",
        weekly: {},
      },
    })

    await startTargetedReview(client, SUBJECT_ID, OUTCOME_ID, 99)
    expect(calls[0].args?.p_limit).toBe(10)
  })

  it("geçersiz UUID ReviewValidationError fırlatır; RPC çağrılmaz", async () => {
    const { client, calls } = createRpcCaptureClient({ data: null })

    await expect(
      startTargetedReview(client, SUBJECT_ID, "not-a-uuid")
    ).rejects.toBeInstanceOf(ReviewValidationError)

    await expect(
      startTargetedReview(client, "not-a-uuid", OUTCOME_ID)
    ).rejects.toBeInstanceOf(ReviewValidationError)

    expect(calls).toHaveLength(0)
  })
})
