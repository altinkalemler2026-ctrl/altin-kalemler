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

function detailPageProps(candidate?: string) {
  return {
    params: Promise.resolve({ id: BATCH_UUID }),
    searchParams: Promise.resolve(candidate === undefined ? {} : { candidate }),
  }
}

/** Flash (ok/error) sorgu parametreleriyle sayfa props'u. */
function detailPagePropsWith(
  extra: { ok?: string; error?: string; candidate?: string },
) {
  return {
    params: Promise.resolve({ id: BATCH_UUID }),
    searchParams: Promise.resolve(extra),
  }
}

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
          subjectName: "Matematik",
          outcomeCode: "MAT.5.3.1",
          lowConfidence: true,
          ownershipStatus: "ai_generated",
          licenseStatus: "pending",
          commercialUseAllowed: null,
          copyrightRiskLevel: "low",
          solution: {
            method: "Toplama",
            steps: [{ title: "Adım 1", content: "2+2 toplamı 4 eder." }],
            result: "4",
            correctAnswerJustification: "İki artı iki dört eder.",
            commonMistakes: ["Cevaba 3 demek"],
          },
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

/**
 * Gerçek veri durumunu taklit eder: staging `validating`, readiness
 * `human_review_required`, skor 0 — yani üç karar da kapalı olmalı.
 */
function validatingDetail() {
  const detail = okDetail()
  const base = detail.candidates[0]!
  return {
    ...detail,
    candidates: [
      {
        ...base,
        stagingQuestionId: "11111111-2222-4333-8444-555555555555",
        preview: { ...base.preview!, stagingStatus: "validating" },
        gates: {
          ...base.gates,
          readiness: {
            fields: [
              { key: "readiness_status", value: "human_review_required" },
              { key: "readiness_score", value: 0 },
            ],
          },
        },
      },
    ],
  }
}

function twoCandidateDetail() {
  const detail = okDetail()
  const firstCandidate = detail.candidates[0]!
  return {
    ...detail,
    batch: {
      ...detail.batch,
      counts: {
        ...detail.batch.counts,
        totalItems: 2,
        validItems: 2,
      },
    },
    candidates: [
      firstCandidate,
      {
        ...firstCandidate,
        candidateIndex: 3,
        clientQuestionId: "c-2",
        stagingQuestionId: "staging-2",
        preview: {
          ...firstCandidate.preview!,
          questionText: "3+3 kaçtır?",
          options: { A: "5", B: "6", C: "7", D: null, E: null },
        },
      },
    ],
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
      AdminCandidateBatchDetailPage(detailPageProps()),
    ).rejects.toThrow("REDIRECT:/login")
    expect(getDetailMock).not.toHaveBeenCalled()
  })

  it("yetki yok → /dashboard redirect (RPC çağrılmaz)", async () => {
    mockAuthenticated()
    hasPermissionMock.mockResolvedValue(false)
    await expect(
      AdminCandidateBatchDetailPage(detailPageProps()),
    ).rejects.toThrow("REDIRECT:/dashboard")
    expect(getDetailMock).not.toHaveBeenCalled()
  })
})

describe("AdminCandidateBatchDetailPage — geçersiz id / bulunamadı", () => {
  it("geçersiz uuid RPC çağrılmadan bulunamadı sayfası gösterir", async () => {
    mockAuthenticated()
    const result = await AdminCandidateBatchDetailPage({
      params: Promise.resolve({ id: "not-a-uuid" }),
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("İletilen paket kimliğiyle eşleşen kayıt bulunamadı.")
    expect(getDetailMock).not.toHaveBeenCalled()
  })

  it("ok+null (bulunamadı) paket bulunamadı sayfası gösterir", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "ok", item: null })
    const result = await AdminCandidateBatchDetailPage(detailPageProps())
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("Paket Bulunamadı")
    expect(html).not.toContain("okunamadı")
  })

  it("veri kaynağı hatasında ayrı hata mesajı gösterilir", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "error", item: null })
    const result = await AdminCandidateBatchDetailPage(detailPageProps())
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

    const result = await AdminCandidateBatchDetailPage(detailPageProps())
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("AK-2026-0001")
    expect(html).toContain("Alındı")
    expect(html).toContain("internal-ai")
    expect(html).toContain("2+2 kaçtır?")
    expect(html).toContain("Matematik")
    expect(html).toContain("MAT.5.3.1")
    expect(html).toContain("Öncelikli İnsan İncelemesi")
    expect(html).toContain("Yöntem")
    expect(html).toContain("Toplama")
    expect(html).toContain("2+2 toplamı 4 eder.")
    expect(html).toContain("İki artı iki dört eder.")
    expect(html).toContain("Cevaba 3 demek")
    expect(html).toContain("Seçenekler")
    expect(html).toContain(">3<")
    expect(html).toContain(">4<")
    expect(html).toContain(">5<")
    expect(html).toContain("Önerilen doğru cevap")
    expect(html).toContain("Cevap Doğrulama")
    expect(html).toContain("consensus")
    expect(html).toContain("Nihai İnceleme")
    expect(html).toContain("İnceleme Kararı")
    // Faz 35 / UI-P2A: üç gerçek karar etiketi migration 130 sözleşmesinden gelir.
    expect(html).toContain("İncelemeyi Onayla")
    expect(html).toContain("Düzeltme İste")
    expect(html).toContain("Reddet")
    expect(html).toContain("İki Aşamalı Yayın İlkesi")
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

    const result = await AdminCandidateBatchDetailPage(detailPageProps())
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
    const result = await AdminCandidateBatchDetailPage(detailPageProps())
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).not.toContain("Invalid Date")
  })

  it("önizleme yok durumunda önizleme bloğu render edilmez", async () => {
    mockAuthenticated()
    const detail = okDetail() as unknown as CandidateBatchDetail
    detail.candidates[0]!.preview = null
    getDetailMock.mockResolvedValue({ status: "ok", item: detail })

    const result = await AdminCandidateBatchDetailPage(detailPageProps())
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("Staging durumu")
    expect(html).not.toContain("2+2 kaçtır?")
  })

  it("varsayılan olarak ilk adayı gösterir ve önceki kontrolü pasif tutar", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "ok", item: twoCandidateDetail() })

    const result = await AdminCandidateBatchDetailPage(detailPageProps())
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Aday 1 / 2")
    expect(html).toContain("2+2 kaçtır?")
    expect(html).not.toContain("3+3 kaçtır?")
    expect(html).toContain('aria-label="Adaylar arasında gezin"')
    expect(html).toContain('aria-label="Önceki aday"')
    expect(html).toContain('aria-disabled="true"')
    expect(html).toContain(`/admin/candidate-batches/${BATCH_UUID}?candidate=2`)
  })

  it("candidate sorgusuyla seçili adayı gösterir ve sonraki kontrolü pasif tutar", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "ok", item: twoCandidateDetail() })

    const result = await AdminCandidateBatchDetailPage(detailPageProps("2"))
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Aday 2 / 2")
    expect(html).toContain("3+3 kaçtır?")
    expect(html).not.toContain("2+2 kaçtır?")
    expect(html).toContain(`/admin/candidate-batches/${BATCH_UUID}?candidate=1`)
    expect(html).not.toContain("?candidate=3")
    expect(html).toContain('aria-label="Sonraki aday"')
    expect(html).toContain('aria-disabled="true"')
  })

  it("geçersiz candidate sorgusunda ilk adaya fail-closed döner", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "ok", item: twoCandidateDetail() })

    const result = await AdminCandidateBatchDetailPage(detailPageProps("999"))
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Aday 1 / 2")
    expect(html).toContain("2+2 kaçtır?")
    expect(html).not.toContain("3+3 kaçtır?")
  })
})

/**
 * FAZ 34G / G4 regresyonu: mobilde `grid-cols-1` olan `dl` içinde çıplak
 * `col-span-2`, CSS Grid'i örtük ikinci sütun yaratıyor ve genişliği
 * etiketlerden çalıyordu (375px'te 3 etiket taşması). Masaüstündeki
 * sütun kaplaması korunmalı, mobilde uygulanmamalı.
 */
describe("AdminCandidateBatchDetailPage — mobil ızgara sözleşmesi (G4)", () => {
  it("çıplak col-span-2 yok; masaüstü kaplaması sm:col-span-2 ile korunuyor", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "ok", item: okDetail() })

    const result = await AdminCandidateBatchDetailPage(detailPageProps())
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    const classTokens = [...html.matchAll(/class="([^"]*)"/g)].flatMap((match) =>
      (match[1] ?? "").split(/\s+/).filter(Boolean)
    )

    // Mobilde uygulanan çıplak span, örtük sütun ve taşma demektir.
    expect(classTokens.filter((token) => token === "col-span-2")).toEqual([])
    // Masaüstü kaplaması yanlışlıkla silinmemeli.
    expect(classTokens.filter((token) => token === "sm:col-span-2")).not.toEqual([])
  })
})

describe("AdminCandidateBatchDetailPage — karar yazma yeteneği sözleşmesi (UI-P2A)", () => {
  it("sayfa modülü yalnızca default export sunar", async () => {
    const pageModule = await import("./page")
    const source = Object.keys(pageModule)
    expect(source).toEqual(["default"])
  })

  it("seçim adımında sunucu aksiyonlu form YOKTUR (ilk tıklama yazmaz)", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "ok", item: okDetail() })

    const result = await AdminCandidateBatchDetailPage(detailPageProps())
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    // Onay adımı seçilmediği sürece hiçbir <form> render edilmemeli.
    // Bu, "karar kaydı için iki ayrı tıklama" kuralının temelidir.
    expect(html).not.toContain("<form")
    expect(html).not.toContain("action=")
    // Seçim düğmesi bir sunucu formu değil, düz bir type=button olmalı.
    expect(html).toContain('type="button"')
    expect(html).toContain("Kararı Seç ve Onaya Git")
  })

  it("kapı kapalı adayda üç karar da devre dışı ve nedeni görünür", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({
      status: "ok",
      item: validatingDetail(),
    })

    const result = await AdminCandidateBatchDetailPage(detailPageProps())
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    // Üç karar seçeneği de disabled olmalı ve neden metin olarak verilmeli.
    const radioCount = (html.match(/type="radio"/g) ?? []).length
    expect(radioCount).toBe(3)
    expect(html.match(/type="radio" disabled/g)?.length ?? 0).toBe(3)
    expect(html).toContain("Karar Kapıları Kapalı")
    expect(html).toContain(
      "Doğrulama ve hazırlık değerlendirmesi tamamlanmadan insan kararı verilemez."
    )
  })

  it("panelde yayınlama/activate çağrısı YOK; yayın uyarısı görünür", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "ok", item: okDetail() })

    const result = await AdminCandidateBatchDetailPage(detailPageProps())
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).not.toContain("activate_question_for_students")
    expect(html).toContain("İki Aşamalı Yayın İlkesi")
    expect(html).toContain(
      "Bu ekranda verilen hiçbir karar öğrenciye doğrudan yayınlama veya canlıya alma sağlamaz."
    )
  })

  it("karar sonucu flash'ı role=status / role=alert olarak erişilebilir", async () => {
    mockAuthenticated()
    getDetailMock.mockResolvedValue({ status: "ok", item: okDetail() })

    const okResult = await AdminCandidateBatchDetailPage(
      detailPagePropsWith({ ok: "Karar kaydedildi: aday reddedildi." }),
    )
    const { renderToString } = await import("react-dom/server")
    const okHtml = renderToString(okResult)

    expect(okHtml).toContain('role="status"')
    expect(okHtml).toContain("Karar kaydedildi: aday reddedildi.")

    const errResult = await AdminCandidateBatchDetailPage(
      detailPagePropsWith({ error: "Bu karar için aday uygun değil." }),
    )
    const errHtml = renderToString(errResult)

    expect(errHtml).toContain('role="alert"')
    expect(errHtml).toContain("Bu karar için aday uygun değil.")
  })
})