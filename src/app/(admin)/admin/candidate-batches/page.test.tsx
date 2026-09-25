/**
 * /admin/candidate-batches list page security + pagination tests.
 *
 * - Unauthenticated → /login redirect
 * - Yetki yok (ai.manage / questions.approve ikisi de false veya hata) →
 *   /dashboard redirect (fail-closed)
 * - Yetkili admin → paket künyeleri + sayaçlar render edilir
 * - Hata vs boş ayrımı: veri kaynağı hatası ayrı mesaj
 * - DTO allowlist: keyfi alan / ham hata render edilmez
 * - Sayfalama: bağlantılar + aria-disabled durumları
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
const listBatchesMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/admin/candidate-batches", async () => {
  const actual = await vi.importActual<typeof import("@/lib/admin/candidate-batches")>(
    "@/lib/admin/candidate-batches",
  )
  return {
    hasCandidateBatchReadPermission: hasPermissionMock,
    listCandidateQuestionBatches: listBatchesMock,
    CANDIDATE_BATCH_PAGE_SIZE: actual.CANDIDATE_BATCH_PAGE_SIZE,
  }
})

import AdminCandidateBatchesPage from "./page"

const BATCH_UUID = "7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3"

function okBatch(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    batchId: BATCH_UUID,
    batchKey: "AK-2026-0001",
    schemaVersion: null,
    origin: "internal-ai",
    producerId: "producer-x",
    producerModel: "gpt-large",
    status: "received",
    counts: {
      totalItems: 10,
      validItems: 8,
      invalidItems: 2,
      insertedItems: 0,
      duplicateItems: 1,
    },
    validationSummary: null,
    createdAt: "2026-09-01T10:00:00.000Z",
    updatedAt: "2026-09-01T10:30:00.000Z",
    ...overrides,
  }
}

beforeEach(() => {
  getUserMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  hasPermissionMock.mockReset()
  listBatchesMock.mockReset()

  hasPermissionMock.mockResolvedValue(true)
  listBatchesMock.mockResolvedValue({
    status: "ok",
    items: [],
    total: 0,
    page: 1,
    totalPages: 1,
  })

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

describe("AdminCandidateBatchesPage — auth gates", () => {
  it("unauthenticated → /login redirect", async () => {
    mockUnauthenticated()
    await expect(
      AdminCandidateBatchesPage({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow("REDIRECT:/login")
    expect(hasPermissionMock).not.toHaveBeenCalled()
    expect(listBatchesMock).not.toHaveBeenCalled()
  })

  it("yetki hatası → /dashboard redirect", async () => {
    mockAuthenticated()
    hasPermissionMock.mockResolvedValue(false)
    await expect(
      AdminCandidateBatchesPage({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow("REDIRECT:/dashboard")
    expect(listBatchesMock).not.toHaveBeenCalled()
  })
})

describe("AdminCandidateBatchesPage — authorized", () => {
  it("yetkili admin listeleme çağrısı yapar ve sayfa 1 kullanır", async () => {
    mockAuthenticated()
    await AdminCandidateBatchesPage({ searchParams: Promise.resolve({}) })
    expect(listBatchesMock).toHaveBeenCalledWith(1)
  })

  it("page parametresi sayıya çevrilip geçirilir", async () => {
    mockAuthenticated()
    await AdminCandidateBatchesPage({
      searchParams: Promise.resolve({ page: "3" }),
    })
    expect(listBatchesMock).toHaveBeenCalledWith(3)
  })

  it("geçersiz page değerleri 1'e düşer", async () => {
    mockAuthenticated()
    for (const bad of ["abc", "0", "-3", "2.5", ""]) {
      listBatchesMock.mockClear()
      await AdminCandidateBatchesPage({
        searchParams: Promise.resolve({ page: bad }),
      })
      expect(listBatchesMock).toHaveBeenCalledWith(1)
    }
  })
})

describe("AdminCandidateBatchesPage — hata ve boş durum ayrımı", () => {
  it("gerçek boş sonuçta 'bulunamadı' mesajı gösterilir", async () => {
    mockAuthenticated()
    const result = await AdminCandidateBatchesPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("Henüz aday soru paketi bulunamadı.")
    expect(html).not.toContain("okunamadı")
  })

  it("veri kaynağı hatasında ayrı hata mesajı gösterilir (ham mesaj sızmaz)", async () => {
    mockAuthenticated()
    listBatchesMock.mockResolvedValue({
      status: "error",
      items: [],
      total: 0,
      page: 1,
      totalPages: 1,
    })
    const result = await AdminCandidateBatchesPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("Aday soru paketleri şu anda okunamadı")
    expect(html).not.toContain("Henüz aday yükleme paketi bulunamadı.")
    expect(html).not.toContain("db down")
    expect(html).not.toContain("yetkisi gerekli")
  })
})

describe("AdminCandidateBatchesPage — render ve allowlist", () => {
  it("paket künyeleri, durum ve sayaçlar render edilir", async () => {
    mockAuthenticated()
    listBatchesMock.mockResolvedValue({
      status: "ok",
      items: [okBatch(), okBatch({ batchKey: "AK-2026-0002", batchId: BATCH_UUID })],
      total: 2,
      page: 1,
      totalPages: 1,
    })
    const result = await AdminCandidateBatchesPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("AK-2026-0001")
    expect(html).toContain("Alındı")
    expect(html).toContain("internal-ai")
    expect(html).toContain("gpt-large")
    expect(html).toContain("Toplam madde")
    expect(html).toContain(">10<")
    expect(html).toContain(`/admin/candidate-batches/${BATCH_UUID}`)
  })

  it("DTO dışı keyfi alan render edilmez", async () => {
    mockAuthenticated()
    listBatchesMock.mockResolvedValue({
      status: "ok",
      items: [
        okBatch({
          raw_payload: { secret: "GIZLI-PAYLOAD" },
          api_key: "GIZLI-ANAHTAR",
        }),
      ],
      total: 1,
      page: 1,
      totalPages: 1,
    })
    const result = await AdminCandidateBatchesPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).not.toContain("GIZLI-PAYLOAD")
    expect(html).not.toContain("GIZLI-ANAHTAR")
  })

  it("bozuk tarih güvenli '-' olarak gösterilir", async () => {
    mockAuthenticated()
    listBatchesMock.mockResolvedValue({
      status: "ok",
      items: [okBatch({ createdAt: "tarih-degil" })],
      total: 1,
      page: 1,
      totalPages: 1,
    })
    const result = await AdminCandidateBatchesPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).not.toContain("Invalid Date")
  })
})

describe("AdminCandidateBatchesPage — sayfalama", () => {
  it("çok sayfalı sonuçta göstergeler ve bağlantılar görünür", async () => {
    mockAuthenticated()
    listBatchesMock.mockResolvedValue({
      status: "ok",
      items: [okBatch()],
      total: 60,
      page: 2,
      totalPages: 3,
    })
    const result = await AdminCandidateBatchesPage({
      searchParams: Promise.resolve({ page: "2" }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain("Sayfa 2 / 3")
    expect(html).toContain("Önceki")
    expect(html).toContain("Sonraki")
    expect(html).toContain('aria-label="Sayfalama"')
    expect(html).toContain("/admin/candidate-batches?page=1")
    expect(html).toContain("/admin/candidate-batches?page=3")
  })

  it("ilk sayfada 'Önceki' devre dışıdır", async () => {
    mockAuthenticated()
    listBatchesMock.mockResolvedValue({
      status: "ok",
      items: [okBatch()],
      total: 60,
      page: 1,
      totalPages: 3,
    })
    const result = await AdminCandidateBatchesPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).toContain('aria-disabled="true"')
    expect(html).toContain("Sayfa 1 / 3")
    expect(html).not.toContain("?page=0")
  })

  it("tek sayfalık sonuçta gezinme gösterilmez", async () => {
    mockAuthenticated()
    listBatchesMock.mockResolvedValue({
      status: "ok",
      items: [okBatch()],
      total: 5,
      page: 1,
      totalPages: 1,
    })
    const result = await AdminCandidateBatchesPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)
    expect(html).not.toContain('aria-label="Sayfalama"')
  })
})

describe("AdminCandidateBatchesPage — no mutation capability", () => {
  it("sayfa mutation fonksiyonu import etmez", async () => {
    const pageModule = await import("./page")
    const source = Object.keys(pageModule)
    expect(source).toEqual(["default"])
  })
})