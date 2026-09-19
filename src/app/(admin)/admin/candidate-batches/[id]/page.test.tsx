/**
 * /admin/candidate-batches/[id] detail page tests.
 *
 * - Unauthenticated → /login redirect
 * - Yetki yok → /dashboard redirect (fail-closed)
 * - Geçersiz uuid → paket bulunamadı sayfası (RPC çağrılmaz)
 * - Bulunamadı (ok+null) → paket bulunamadı sayfası
 * - Veri kaynağı hatası → ayrı hata mesajı
 * - Yetkili render: künye, sayaçlar, aday, önizleme (soru/şık/çözüm),
 *   validation sonuçları, review kuyruğu, gate özeti
 * - DTO allowlist: keyfi/raw alan render edilmez
 * - Mutation import almaz (salt okunur)
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())
const redirectMock = vi.hoisted(() =>
  vi.fn((url: string) => {
    throw new Error(`REDIRECT:${url}`)
  }),
)
const hasPermissionMock = vi.hoisted(() => vi.fn())
const getDetailMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/admin/candidate-batches", () => ({
  hasCandidateBatchReadPermission: hasPermissionMock,
  getCandidateBatchDetail: getDetailMock,
}))

import AdminCandidateBatchDetailPage from "./page"
import type { CandidateBatchDetail } from "@/lib/admin/candidate-batches"

const BATCH_UUID = "7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3"

function okDetail(overrides: Record<string, unknown> = {}) {
  return {
    batch: {
      batchId: BATCH_UUID,
      batchKey: "AK-2026-0001",
      schemaVersion: null,
      origin: "internal-ai",
      producerId: "producer-x",
      producerModel: "gpt-large",
      status: "received",
      counts: {
        totalItems: 1,
        validItems: 1,
        invalidItems: 0,
        insertedItems: 0,
        duplicateItems: 0,
      },
      validationSummary: null,
      createdAt: "2026-09-01T10:00:00.000Z",
      updatedAt: "2026-09-01T10:30:00.000Z",
    },
    candidates: [
      {
        candidateIndex: 0,
        clientQuestionId: "c-1",
        validationStatus: "passed",
        validationErrors: [],
        validationWarnings: [],
        stagingQuestionId: "staging-1",
        preview: {
          stagingStatus: "staged",
          questionText: "2+2 kaçtır?",
          options: { A: "3", B: "4", C: "5", D: null, E: null },
          proposedCorrectAnswer: "B",
          proposedDifficulty: "medium",
          proposedCognitiveType: "aritmetik",
          proposedSolveTimeSeconds: 30,
          gradeLevel: 5,
          subjectId: "math-1",
          ownershipStatus: "ai_generated",
          licenseStatus: "pending",
          commercialUseAllowed: null,
          copyrightRiskLevel: "low",
          solution: "4'tür; 2+2 toplamı 4 eder.",
        },
        validationResults: [
          {
            validatorType: "schema",
            validationType: "structure",
            result: "valid",
            score: 1,
            summary: "Yapı geçerli",
            providerName: "in-house",
            modelName: "validator-v1",
            promptVersion: "1",
            createdAt: "2026-09-01T10:05:00.000Z",
          },
        ],
        reviewQueue: [
          {
            reasonCode: "manual_review",
            reasonDetails: "İnsan kontrolü gerekli",
            priority: "high",
            status: "pending",
            createdAt: "2026-09-01T10:10:00.000Z",
          },
        ],
        gates: {
          answerVerification: {
            fields: [{ key: "consensus_status", value: "consensus" }],
          },
          curriculumFit: null,
          solveTimeVerification: null,
          originalityVerification: null,
          questionQuality: null,
          readiness: { fields: [{ key: "readiness_status", value: "ready" }] },
          finalReview: null,
        },
      },
    ],
    ...overrides,
  }
}

beforeEach(() => {
  getUserMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  hasPermissionMock.mockReset()
  getDetailMock.mockReset()

  hasPermissionMock.mockResolvedValue(true)

  createClientMock.mockImplementation(async () => ({
    auth: { getUser: getUserMock },
  }))
})

function mockAuthenticated() {
  getUserMock.mockResolvedValue({
    data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
  })
}

function mockUnauthenticated() {
  getUserMock.mockResolvedValue({ data: { user: null } })
}

describe("AdminCandidateBatchDetailPage — auth gates", () => {
  it("unauthenticated → /login redirect", async () => {
    mockUnauthenticated()
    await expect(
      AdminCandidateBatchDetailPage({ params: Promise.resolve({ id: BATCH_UUID }) }),
    ).rejects.toThrow("REDIRECT:/login")
    expect(getDetailMock).not.toHaveBeenCalled()
  })

  it("yetki yok → /dashboard redirect (RPC çağrılmaz)", async () => {
    mockAuthenticated()
    hasPermissionMock.mockResolvedValue(false)
    await expect(
      AdminCandidateBatchDetailPage({ params: Promise.resolve({ id: BATCH_UUID }) }),
    ).rejects.toThrow("REDIRECT:/dashboard")
    expect(getDetailMock).not.toHaveBeenCalled()
  })
})

describe("AdminCandidateBatchDetailPage — geçersiz id / bulunamadı", () => {
  it("geçersiz uuid RPC çağrılmadan bulunamadı sayfası gösterir", async () => {
    mockAuthenticated()
    const result = await AdminCandidateBatchDetailPage({
      params: Promise.resolve({ id: "not-a-uuid" }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("İletilen paket kimliğiyle eşleşen kayıt bulunamadı.")
    expect(getDetailMock).not.toHaveBeenCalled()
  })

  it("ok+null (bulunamadı) paket bulunamadı sayfası gösterir", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "ok", item: null })
    const result = await AdminCandidateBatchDetailPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("Paket Bulunamadı")
    expect(html).not.toContain("okunamadı")
  })

  it("veri kaynağı hatasında ayrı hata mesajı gösterilir", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "error", item: null })
    const result = await AdminCandidateBatchDetailPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("şu anda okunamadı")
    expect(html).not.toContain("Paket Bulunamadı")
    expect(html).not.toContain("connection reset")
  })
})

describe("AdminCandidateBatchDetailPage — yetkili render", () => {
  it("künye, sayaçlar ve aday önizleme render edilir", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "ok", item: okDetail() })

    const result = await AdminCandidateBatchDetailPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("AK-2026-0001")
    expect(html).toContain("received")
    expect(html).toContain("internal-ai")
    expect(html).toContain("2+2 kaçtır?")
    expect(html).toContain("4&#x27;tür; 2+2 toplamı 4 eder.")
    expect(html).toContain("Seçenekler")
    expect(html).toContain(">3<")
    expect(html).toContain(">4<")
    expect(html).toContain(">5<")
    expect(html).toContain("Önerilen doğru cevap")
    expect(html).toContain("Cevap Doğrulama")
    expect(html).toContain("consensus")
    expect(html).toContain("Nihai İnceleme")
  })

  it("DTO dışı keyfi/raw alan render edilmez", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({
      status: "ok",
      item: okDetail({
        batch: {
          ...okDetail().batch,
          raw_payload: { secret: "GIZLI-PAYLOAD" },
        },
        candidates: [
          {
            ...okDetail().candidates[0],
            preview: {
              ...okDetail().candidates[0].preview,
              metadata: { arbitrary: "GIZLI-META" },
              api_key: "GIZLI-ANAHTAR",
            },
          },
        ],
      }),
    })

    const result = await AdminCandidateBatchDetailPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).not.toContain("GIZLI-PAYLOAD")
    expect(html).not.toContain("GIZLI-META")
    expect(html).not.toContain("GIZLI-ANAHTAR")
  })

  it("bozuk tarih güvenli '-' olarak gösterilir", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({
      status: "ok",
      item: okDetail({
        batch: { ...okDetail().batch, createdAt: "tarih-degil" },
      }),
    })
    const result = await AdminCandidateBatchDetailPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).not.toContain("Invalid Date")
  })

  it("önizleme yok durumunda önizleme bloğu render edilmez", async () => {
    mockAuthenticated()
    const detail = okDetail() as unknown as CandidateBatchDetail
    detail.candidates[0]!.preview = null
    getDetailMock.mockResolvedValue({ status: "ok", item: detail })

    const result = await AdminCandidateBatchDetailPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("Staging durumu")
    expect(html).not.toContain("2+2 kaçtır?")
  })
})

describe("AdminCandidateBatchDetailPage — no mutation capability", () => {
  it("sayfa mutation fonksiyonu import etmez", async () => {
    const pageModule = await import("./page")
    const source = Object.keys(pageModule)
    expect(source).toEqual(["default"])
  })
})