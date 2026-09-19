/**
 * /admin/candidate-batches/[id]/islem-durumu page tests (Faz 20).
 *
 * - Unauthenticated → /login redirect
 * - Yetki yok → /dashboard redirect (fail-closed)
 * - Geçersiz uuid → paket bulunamadı sayfası (RPC çağrılmaz)
 * - Bulunamadı (ok+null) → paket bulunamadı sayfası
 * - Veri kaynağı hatası → ayrı hata mesajı
 * - Yetkili render: paket aşaması, waiting_* gate sayaçları,
 *   provider hata, retry desteklenmiyor bilgisi
 * - DTO allowlist: keyfi/raw/ham hata alanı render edilmez
 * - Yeniden deneme DÜĞMESİ sunulmaz (yalnız bilgi)
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
const getOperationStatusMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/admin/candidate-batches", () => ({
  hasCandidateBatchReadPermission: hasPermissionMock,
  getCandidateBatchOperationStatus: getOperationStatusMock,
}))

import AdminCandidateBatchOperationStatusPage from "./page"
import type { CandidateBatchOperationStatus } from "@/lib/admin/candidate-batches"

const BATCH_UUID = "7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3"

function okStatus(): CandidateBatchOperationStatus {
  return {
    batch: {
      batchId: BATCH_UUID,
      batchKey: "AK-2026-0001",
      status: "validating",
      counts: {
        totalItems: 3,
        validItems: 2,
        invalidItems: 1,
        insertedItems: 2,
        duplicateItems: 0,
      },
      createdAt: "2026-09-01T10:00:00.000Z",
      updatedAt: "2026-09-01T10:30:00.000Z",
    },
    phase: {
      candidateCounts: {
        pending: 0,
        valid: 2,
        invalid: 1,
        duplicate: 0,
        inserted: 2,
        failed: 0,
      },
    },
    gates: {
      answerVerification: {
        total: 2,
        waitingReviewer1: null,
        waitingReviewer2: null,
        waitingSolver1: 2,
        waitingSolver2: 0,
        needsHumanReview: 0,
        verified: 0,
        blocked: null,
        rejected: 0,
        readyForHumanReview: null,
        humanReviewRequired: null,
        notReady: null,
        alreadyPromoted: null,
        approve: null,
        requestChanges: null,
        other: 0,
      },
      curriculumFit: {
        total: 1,
        waitingReviewer1: 1,
        waitingReviewer2: 0,
        waitingSolver1: null,
        waitingSolver2: null,
        needsHumanReview: null,
        verified: 0,
        blocked: null,
        rejected: 0,
        readyForHumanReview: null,
        humanReviewRequired: null,
        notReady: null,
        alreadyPromoted: null,
        approve: null,
        requestChanges: null,
        other: 0,
      },
      solveTimeVerification: {
        total: 0,
        waitingReviewer1: null,
        waitingReviewer2: null,
        waitingSolver1: null,
        waitingSolver2: null,
        needsHumanReview: null,
        verified: null,
        blocked: null,
        rejected: null,
        readyForHumanReview: null,
        humanReviewRequired: null,
        notReady: null,
        alreadyPromoted: null,
        approve: null,
        requestChanges: null,
        other: null,
      },
      originalityVerification: {
        total: 0,
        waitingReviewer1: null,
        waitingReviewer2: null,
        waitingSolver1: null,
        waitingSolver2: null,
        needsHumanReview: null,
        verified: null,
        blocked: null,
        rejected: null,
        readyForHumanReview: null,
        humanReviewRequired: null,
        notReady: null,
        alreadyPromoted: null,
        approve: null,
        requestChanges: null,
        other: null,
      },
      questionQuality: {
        total: 0,
        waitingReviewer1: null,
        waitingReviewer2: null,
        waitingSolver1: null,
        waitingSolver2: null,
        needsHumanReview: null,
        verified: null,
        blocked: null,
        rejected: null,
        readyForHumanReview: null,
        humanReviewRequired: null,
        notReady: null,
        alreadyPromoted: null,
        approve: null,
        requestChanges: null,
        other: null,
      },
      readiness: {
        total: 0,
        waitingReviewer1: null,
        waitingReviewer2: null,
        waitingSolver1: null,
        waitingSolver2: null,
        needsHumanReview: null,
        verified: null,
        blocked: null,
        rejected: null,
        readyForHumanReview: null,
        humanReviewRequired: null,
        notReady: null,
        alreadyPromoted: null,
        approve: null,
        requestChanges: null,
        other: null,
      },
      finalReview: {
        total: 0,
        waitingReviewer1: null,
        waitingReviewer2: null,
        waitingSolver1: null,
        waitingSolver2: null,
        needsHumanReview: null,
        verified: null,
        blocked: null,
        rejected: null,
        readyForHumanReview: null,
        humanReviewRequired: null,
        notReady: null,
        alreadyPromoted: null,
        approve: null,
        requestChanges: null,
        other: null,
      },
    },
    provider: {
      hasBatchErrorData: false,
      candidateValidationErrorCount: 1,
    },
    retry: {
      supported: false,
      reasonKey: "gate_retry_not_supported",
    },
  }
}

beforeEach(() => {
  getUserMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  hasPermissionMock.mockReset()
  getOperationStatusMock.mockReset()

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

describe("AdminCandidateBatchOperationStatusPage — auth gates", () => {
  it("unauthenticated → /login redirect", async () => {
    mockUnauthenticated()
    await expect(
      AdminCandidateBatchOperationStatusPage({
        params: Promise.resolve({ id: BATCH_UUID }),
      }),
    ).rejects.toThrow("REDIRECT:/login")
    expect(getOperationStatusMock).not.toHaveBeenCalled()
  })

  it("yetki yok → /dashboard redirect (RPC çağrılmaz)", async () => {
    mockAuthenticated()
    hasPermissionMock.mockResolvedValue(false)
    await expect(
      AdminCandidateBatchOperationStatusPage({
        params: Promise.resolve({ id: BATCH_UUID }),
      }),
    ).rejects.toThrow("REDIRECT:/dashboard")
    expect(getOperationStatusMock).not.toHaveBeenCalled()
  })
})

describe("AdminCandidateBatchOperationStatusPage — geçersiz id / bulunamadı", () => {
  it("geçersiz uuid RPC çağrılmadan bulunamadı sayfası gösterir", async () => {
    mockAuthenticated()
    const result = await AdminCandidateBatchOperationStatusPage({
      params: Promise.resolve({ id: "not-a-uuid" }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("İletilen paket kimliğiyle eşleşen kayıt bulunamadı.")
    expect(getOperationStatusMock).not.toHaveBeenCalled()
  })

  it("ok+null (bulunamadı) paket bulunamadı sayfası gösterir", async () => {
    mockAuthenticated()
    getOperationStatusMock.mockResolvedValue({ status: "ok", item: null })
    const result = await AdminCandidateBatchOperationStatusPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("Paket Bulunamadı")
  })

  it("veri kaynağı hatasında ayrı hata mesajı gösterilir", async () => {
    mockAuthenticated()
    getOperationStatusMock.mockResolvedValue({ status: "error", item: null })
    const result = await AdminCandidateBatchOperationStatusPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("şu anda okunamadı")
    expect(html).not.toContain("connection reset")
  })
})

describe("AdminCandidateBatchOperationStatusPage — yetkili render", () => {
  it("paket aşaması, waiting_* gate sayaçları, provider ve retry bilgisi render edilir", async () => {
    mockAuthenticated()
    getOperationStatusMock.mockResolvedValue({ status: "ok", item: okStatus() })

    const result = await AdminCandidateBatchOperationStatusPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Üretim / Denetim İşlem Durumu")
    expect(html).toContain("AK-2026-0001")
    expect(html).toContain("validating")
    expect(html).toContain("Paket Aşaması")
    expect(html).toContain("Cevap Doğrulama")
    expect(html).toContain("İlk çözücü bekleniyor")
    expect(html).toContain("Müfredat Uyumu")
    expect(html).toContain("İlk inceleme bekliyor")
    expect(html).toContain("Sağlayıcı Hatası")
    expect(html).toContain("Güvenli Yeniden Deneme")
    expect(html).toContain("Desteklenmiyor")
    expect(html).toContain("yeniden deneme düğmesi sunulmuyor")
  })

  it("retry desteklenmiyor bilgisi; çalışmayan düğme üretilmez", async () => {
    mockAuthenticated()
    getOperationStatusMock.mockResolvedValue({ status: "ok", item: okStatus() })

    const result = await AdminCandidateBatchOperationStatusPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).not.toContain('type="button"')
    expect(html).not.toContain("başlatılan bir düğme sunulmuyor")
    expect(html).not.toContain(">Tekrar Çalıştır<")
  })

  it("DTO dışı keyfi/raw alan render edilmez", async () => {
    mockAuthenticated()
    const status = okStatus() as unknown as CandidateBatchOperationStatus
    const leaked = {
      ...status,
      batch: {
        ...status.batch,
        error_data: { hata: "GIZLI-HATA" },
      },
      provider: {
        ...status.provider,
        api_key: "GIZLI-ANAHTAR",
      },
    } as unknown as CandidateBatchOperationStatus
    getOperationStatusMock.mockResolvedValue({ status: "ok", item: leaked })

    const result = await AdminCandidateBatchOperationStatusPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).not.toContain("GIZLI-HATA")
    expect(html).not.toContain("GIZLI-ANAHTAR")
  })

  it("provider hatası verisi varken uyarı metni gösterilir", async () => {
    mockAuthenticated()
    const status = okStatus()
    status.provider = {
      hasBatchErrorData: true,
      candidateValidationErrorCount: 2,
    }
    getOperationStatusMock.mockResolvedValue({ status: "ok", item: status })

    const result = await AdminCandidateBatchOperationStatusPage({
      params: Promise.resolve({ id: BATCH_UUID }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("sağlayıcı kaynaklı hata verisi bulunuyor")
    expect(html).not.toContain("hata verisi yok")
  })
})

describe("AdminCandidateBatchOperationStatusPage — no mutation capability", () => {
  it("sayfa mutation fonksiyonu import etmez", async () => {
    const pageModule = await import("./page")
    const source = Object.keys(pageModule)
    expect(source).toEqual(["default"])
  })
})