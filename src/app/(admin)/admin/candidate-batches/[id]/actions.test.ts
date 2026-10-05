// @vitest-environment node
/**
 * Faz 35 / UI-P2A — aday kararı sunucu aksiyonu testleri.
 *
 * Kanıtlanan güvenlik sözleşmeleri:
 * - Oturum yoksa /login'e yönlendirilir, RPC HİÇ çağrılmaz.
 * - Sunucu yetkisi yoksa mutasyon RPC'si HİÇ çağrılmaz (fail-closed).
 * - Girdi doğrulaması RPC'ye gitmeden reddeder (geçersiz uuid, geçersiz karar,
 *   gerekçesiz request_changes/reject).
 * - Karar uygunluğu SUNUCUDA yeniden türetilir: `validating` aday için
 *   istemci "onaya geçmiş" olsa bile RPC çağrılmaz.
 * - RPC argümanları migration 130 imzasına birebir uyar.
 * - RPC hatası Türkçe mesaja çevrilir; ham DB mesajı flash URL'ine taşınmaz.
 * - Beklenmeyen `status` değeri başarı olarak sunulmaz (fail-closed).
 * - Hiçbir yayın/activate fonksiyonu çağrılmaz.
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())
const revalidateMock = vi.hoisted(() => vi.fn())
const redirectMock = vi.hoisted(() =>
  vi.fn((url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`)
  })
)
const hasPermissionMock = vi.hoisted(() => vi.fn())
const getDetailMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({ createClient: createClientMock }))
vi.mock("next/navigation", () => ({ redirect: redirectMock }))
vi.mock("next/cache", () => ({ revalidatePath: revalidateMock }))
vi.mock("@/lib/admin/candidate-batches", async (importOriginal) => {
  const actual = await importOriginal<
    typeof import("@/lib/admin/candidate-batches")
  >()
  return {
    ...actual,
    hasCandidateBatchReadPermission: hasPermissionMock,
    getCandidateBatchDetail: getDetailMock,
  }
})

import { submitCandidateDecisionAction } from "./actions"

const BATCH_ID = "7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3"
const STAGING_ID = "11111111-2222-4333-8444-555555555555"

function formData(fields: Record<string, string>): FormData {
  const data = new FormData()
  for (const [key, value] of Object.entries(fields)) data.set(key, value)
  return data
}

function validForm(
  overrides: Record<string, string> = {}
): FormData {
  return formData({
    batchId: BATCH_ID,
    stagingQuestionId: STAGING_ID,
    decision: "reject",
    rationale: "çözüm hatalı",
    candidatePosition: "1",
    ...overrides,
  })
}

function flashUrl(): string {
  const call = redirectMock.mock.calls.at(-1)
  expect(call).toBeDefined()
  return String(call![0])
}

function flashMessage(kind: "ok" | "error"): string {
  const url = new URL(flashUrl(), "http://localhost")
  return url.searchParams.get(kind) ?? ""
}

/** Aday kaydı üretir (staging durumu + readiness alanları kontrollü). */
function candidate(
  stagingStatus: string | null,
  readinessFields?: Array<{ key: string; value: string | number | string[] | null }>
) {
  return {
    candidateIndex: 0,
    clientQuestionId: "c-1",
    validationStatus: "passed",
    validationErrors: [],
    validationWarnings: [],
    stagingQuestionId: STAGING_ID,
    preview: stagingStatus
      ? ({
          stagingStatus,
        } as unknown as Record<string, unknown>)
      : null,
    validationResults: [],
    reviewQueue: [],
    gates: {
      answerVerification: null,
      curriculumFit: null,
      solveTimeVerification: null,
      originalityVerification: null,
      questionQuality: null,
      readiness: readinessFields ? { fields: readinessFields } : null,
      finalReview: null,
    },
  }
}

function detailWith(
  stagingStatus: string | null,
  readinessFields?: Array<{ key: string; value: string | number | string[] | null }>
) {
  return {
    status: "ok",
    item: {
      batch: { batchId: BATCH_ID } as unknown as Record<string, unknown>,
      candidates: [candidate(stagingStatus, readinessFields)],
    },
  }
}

const READY_FIELDS = [
  { key: "readiness_status", value: "ready_for_human_review" },
  { key: "readiness_score", value: 1 },
  { key: "blocking_reasons", value: [] },
]

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  revalidateMock.mockReset()
  hasPermissionMock.mockReset()
  getDetailMock.mockReset()

  getUserMock.mockResolvedValue({
    data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
  })
  hasPermissionMock.mockResolvedValue(true)
  getDetailMock.mockResolvedValue(detailWith("needs_review", READY_FIELDS))
  createClientMock.mockImplementation(async () => ({
    auth: { getUser: getUserMock },
    rpc: rpcMock,
  }))
  rpcMock.mockResolvedValue({ data: { status: "rejected" }, error: null })
})

/** Beklenen hata mesajıyla flash + redirect beklentisi. */
async function expectRedirectRejection(): Promise<string> {
  await submitCandidateDecisionAction(validForm()).catch((error: unknown) => {
    if (!(error instanceof Error)) throw error
    expect(error.message).toContain("NEXT_REDIRECT")
  })
  return flashMessage("error")
}

describe("submitCandidateDecisionAction — oturum ve yetki kapıları", () => {
  it("oturum yoksa /login'e yönlendirir, RPC çağrılmaz", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })

    await submitCandidateDecisionAction(validForm()).catch((error: unknown) => {
      expect((error as Error).message).toContain("NEXT_REDIRECT")
    })

    expect(flashUrl()).toBe("/login")
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("sunucu yetkisi yoksa RPC çağrılmaz ve yetki mesajı döner", async () => {
    hasPermissionMock.mockResolvedValue(false)

    const message = await expectRedirectRejection()

    expect(rpcMock).not.toHaveBeenCalled()
    expect(message).toMatch(/yetkiniz yok/i)
  })

  it("yetki RPC'si hata verirse de fail-closed: RPC çağrılmaz", async () => {
    hasPermissionMock.mockRejectedValue(new Error("yetki kontrolü başarısız"))

    await expect(submitCandidateDecisionAction(validForm())).rejects.toThrow(
      /yetki kontrolü başarısız/
    )
    expect(rpcMock).not.toHaveBeenCalled()
  })
})

describe("submitCandidateDecisionAction — girdi doğrulama (RPC öncesi)", () => {
  it("geçersiz batchId liste sayfasına gider", async () => {
    await submitCandidateDecisionAction(
      formData({
        batchId: "bozuk",
        stagingQuestionId: STAGING_ID,
        decision: "reject",
        rationale: "gerekçe",
      })
    ).catch((error: unknown) => {
      expect((error as Error).message).toContain("NEXT_REDIRECT")
    })

    expect(flashUrl()).toContain("/admin/candidate-batches?")
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("geçersiz staging uuid reddedilir, RPC çağrılmaz", async () => {
    const message = await (async () => {
      await submitCandidateDecisionAction(
        validForm({ stagingQuestionId: "bozuk-uuid" })
      ).catch((error: unknown) => {
        expect((error as Error).message).toContain("NEXT_REDIRECT")
      })
      return flashMessage("error")
    })()

    expect(message).toMatch(/kimliği eksik veya geçersiz/i)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("sözleşme dışı karar reddedilir, RPC çağrılmaz", async () => {
    await submitCandidateDecisionAction(
      validForm({ decision: "publish", rationale: "x" })
    ).catch((error: unknown) => {
      expect((error as Error).message).toContain("NEXT_REDIRECT")
    })

    expect(flashMessage("error")).toMatch(/Geçersiz bir karar/i)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it.each(["request_changes", "reject"])(
    "%s için gerekçesiz giriş reddedilir, RPC çağrılmaz",
    async (decision) => {
      await submitCandidateDecisionAction(
        validForm({ decision, rationale: "   " })
      ).catch((error: unknown) => {
        expect((error as Error).message).toContain("NEXT_REDIRECT")
      })

      expect(flashMessage("error")).toMatch(/gerekçe yazmalısınız/i)
      expect(rpcMock).not.toHaveBeenCalled()
    }
  )

  it("approve gerekçesiz kabul edilir", async () => {
    rpcMock.mockResolvedValue({ data: { status: "promoted" }, error: null })

    await submitCandidateDecisionAction(
      validForm({ decision: "approve", rationale: "" })
    ).catch((error: unknown) => {
      expect((error as Error).message).toContain("NEXT_REDIRECT")
    })

    expect(rpcMock).toHaveBeenCalledTimes(1)
    expect(flashMessage("ok")).toMatch(/soru bankasına taşındı/)
  })
})

describe("submitCandidateDecisionAction — sunucu tarafı yeniden türetme", () => {
  it("validating adayda karar sunucuda reddedilir, RPC çağrılmaz", async () => {
    getDetailMock.mockResolvedValue(
      detailWith("validating", [
        { key: "readiness_status", value: "human_review_required" },
        { key: "readiness_score", value: 0 },
      ])
    )

    const message = await expectRedirectRejection()

    expect(message).toMatch(/aday uygun değil/i)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("needs_review + hazır olmayan readiness: reject açık, approve kapalı", async () => {
    getDetailMock.mockResolvedValue(
      detailWith("needs_review", [
        { key: "readiness_status", value: "human_review_required" },
        { key: "readiness_score", value: 0 },
      ])
    )

    // reject -> RPC çağrılır
    await submitCandidateDecisionAction(validForm()).catch((e: unknown) => {
      expect((e as Error).message).toContain("NEXT_REDIRECT")
    })
    expect(rpcMock).toHaveBeenCalledTimes(1)

    rpcMock.mockClear()

    // approve -> sunucuda reddedilir
    await submitCandidateDecisionAction(
      validForm({ decision: "approve", rationale: "" })
    ).catch((e: unknown) => {
      expect((e as Error).message).toContain("NEXT_REDIRECT")
    })
    expect(flashMessage("error")).toMatch(/aday uygun değil/i)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("terminal durumda (promoted) yeni karar reddedilir", async () => {
    getDetailMock.mockResolvedValue(detailWith("promoted", READY_FIELDS))

    await expectRedirectRejection()

    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("detayde aday bulunamazsa reddedilir, RPC çağrılmaz", async () => {
    getDetailMock.mockResolvedValue({
      status: "ok",
      item: {
        batch: { batchId: BATCH_ID } as unknown as Record<string, unknown>,
        candidates: [],
      },
    })

    const message = await expectRedirectRejection()

    expect(message).toMatch(/bulunamadı/i)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("detay null iken (notFound) fail-closed: RPC çağrılmaz", async () => {
    getDetailMock.mockResolvedValue({ status: "ok", item: null })

    const message = await expectRedirectRejection()

    expect(message).toMatch(/bulunamadı/i)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("detay okuma hatasında RPC çağrılmaz", async () => {
    getDetailMock.mockResolvedValue({ status: "error", item: null })

    const message = await expectRedirectRejection()

    expect(message).toMatch(/kararı kaydedilemedi/i)
    expect(rpcMock).not.toHaveBeenCalled()
  })
})

describe("submitCandidateDecisionAction — RPC çağrı sözleşmesi", () => {
  it("argümanlar migration 130 imzasına birebir uyar", async () => {
    await submitCandidateDecisionAction(validForm()).catch((e: unknown) => {
      expect((e as Error).message).toContain("NEXT_REDIRECT")
    })

    expect(rpcMock).toHaveBeenCalledTimes(1)
    const [fn, args] = rpcMock.mock.calls[0]
    expect(fn).toBe("review_and_promote_ai_question")
    expect(args).toEqual({
      p_staging_question_id: STAGING_ID,
      p_decision: "reject",
      p_review_notes: "çözüm hatalı",
    })
  })

  it("boş gerekçe approve'da p_review_notes olarak gönderilmez", async () => {
    rpcMock.mockResolvedValue({ data: { status: "promoted" }, error: null })

    await submitCandidateDecisionAction(
      validForm({ decision: "approve", rationale: "" })
    ).catch((e: unknown) => {
      expect((e as Error).message).toContain("NEXT_REDIRECT")
    })

    const [, args] = rpcMock.mock.calls[0]
    expect(args.p_review_notes).toBeUndefined()
  })

  it("hiçbir yayın/activate fonksiyonu çağrılmaz", async () => {
    await submitCandidateDecisionAction(validForm()).catch((e: unknown) => {
      expect((e as Error).message).toContain("NEXT_REDIRECT")
    })

    const calledFunctions = rpcMock.mock.calls.map((call) => call[0])
    for (const fn of calledFunctions) {
      expect(String(fn)).not.toMatch(/activate|deactivate|publish/i)
    }
  })

  it("revalidatePath yalnız admin rotalarına uygulanır", async () => {
    await submitCandidateDecisionAction(validForm()).catch((e: unknown) => {
      expect((e as Error).message).toContain("NEXT_REDIRECT")
    })

    const paths = revalidateMock.mock.calls.map((call) => String(call[0]))
    expect(paths.length).toBeGreaterThan(0)
    for (const path of paths) {
      expect(path).toMatch(/^\/admin\//)
    }
  })
})

describe("submitCandidateDecisionAction — sonuç ve hata eşleme", () => {
  it.each([
    ["promoted", /soru bankasına taşındı/],
    ["already_promoted", /Yeni bir kayıt oluşturulmadı/],
    ["changes_requested", /düzeltme istendi/],
    ["rejected", /reddedildi/],
    ["idempotent_replay", /daha önce kaydedilmişti/],
  ])("status=%s için doğru Türkçe sonuç", async (status, pattern) => {
    rpcMock.mockResolvedValue({ data: { status }, error: null })

    await submitCandidateDecisionAction(validForm()).catch((e: unknown) => {
      expect((e as Error).message).toContain("NEXT_REDIRECT")
    })

    expect(flashMessage("ok")).toMatch(pattern)
  })

  it("beklenmeyen status değeri başarı olarak sunulmaz (fail-closed)", async () => {
    rpcMock.mockResolvedValue({ data: { status: "published" }, error: null })

    await submitCandidateDecisionAction(validForm()).catch((e: unknown) => {
      expect((e as Error).message).toContain("NEXT_REDIRECT")
    })

    expect(flashMessage("ok")).toBe("")
    expect(flashMessage("error")).toMatch(/kararı kaydedilemedi/i)
  })

  it("null data fail-closed", async () => {
    rpcMock.mockResolvedValue({ data: null, error: null })

    await submitCandidateDecisionAction(validForm()).catch((e: unknown) => {
      expect((e as Error).message).toContain("NEXT_REDIRECT")
    })

    expect(flashMessage("error")).toMatch(/kararı kaydedilemedi/i)
  })

  it.each([
    ["Human authentication required.", /giriş yapmalısınız/i],
    ["Question approval permission required.", /yetkiniz yok/i],
    ["Rejected staging question cannot be promoted.", /daha önce reddedilmiş/i],
    [
      "Question is not ready for final human approval. Current readiness status: human_review_required",
      /insan onayına hazır değil/i,
    ],
    [
      "All mandatory AI quality gates must pass before promotion.",
      /doğrulama kapılarının tümü geçilmeden/i,
    ],
  ])("RPC hatası Türkçe mesaja çevrilir: %s", async (raw, pattern) => {
    rpcMock.mockResolvedValue({ data: null, error: { message: raw } })

    await submitCandidateDecisionAction(validForm()).catch((e: unknown) => {
      expect((e as Error).message).toContain("NEXT_REDIRECT")
    })

    const message = flashMessage("error")
    expect(message).toMatch(pattern)
    // Ham DB mesajı flash URL'ine sızmaz.
    expect(flashUrl()).not.toContain(encodeURIComponent(raw))
    expect(message).not.toContain(raw)
  })
})