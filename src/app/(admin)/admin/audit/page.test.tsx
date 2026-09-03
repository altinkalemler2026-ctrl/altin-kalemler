/**
 * /admin/audit page security tests (Server Component).
 *
 * - Unauthenticated → /login redirect
 * - audit.view denied/error → /dashboard redirect (fail-closed)
 * - Authorized admin → entries render as allowlist künye
 * - DTO allowlist: before_data/after_data payload'ları render edilmez
 * - Data source error → distinct "okunamadı" message, raw leak yok
 * - Empty state ayrı mesaj
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())
const redirectMock = vi.hoisted(() =>
  vi.fn((url: string) => {
    throw new Error(`REDIRECT:${url}`)
  }),
)
const hasAuditViewPermissionMock = vi.hoisted(() => vi.fn())
const listAuditLogMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/admin/audit-log", () => ({
  AUDIT_ACTION_CODES: ["question.edit"],
  hasAuditViewPermission: hasAuditViewPermissionMock,
  listAuditLog: listAuditLogMock,
  parseAuditActionCode: (v?: string) =>
    v === "question.edit" ? v : undefined,
  parseAuditEntityId: (v?: string) =>
    v && /^[0-9a-f-]{36}$/i.test(v) ? v : undefined,
}))

function auditEntry(overrides: Record<string, unknown> = {}) {
  return {
    id: "dddddddd-0000-4000-8000-00000000000d",
    actionCode: "question.edit",
    entityType: "question",
    entityId: "aaaaaaaa-1111-4000-8000-000000000001",
    actorUserId: "99999999-8888-4000-8000-000000000901",
    performedAt: "2026-09-03T10:00:00.000Z",
    ...overrides,
  }
}

async function renderHtml(searchParams: Record<string, string> = {}) {
  const { default: AdminAuditPage } = await import("./page")
  const result = await AdminAuditPage({
    searchParams: Promise.resolve(searchParams),
  })
  const { renderToString } = await import("react-dom/server")
  return renderToString(result)
}

beforeEach(() => {
  getUserMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  hasAuditViewPermissionMock.mockReset()
  listAuditLogMock.mockReset()
  getUserMock.mockResolvedValue({
    data: { user: { id: "99999999-8888-4000-8000-000000000901" } },
  })
  hasAuditViewPermissionMock.mockResolvedValue(true)
  listAuditLogMock.mockResolvedValue({
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

describe("AdminAuditPage — auth gates", () => {
  it("unauthenticated → /login redirect", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })

    const { default: AdminAuditPage } = await import("./page")
    await expect(
      AdminAuditPage({ searchParams: Promise.resolve({}) })
    ).rejects.toThrow("REDIRECT:/login")

    expect(hasAuditViewPermissionMock).not.toHaveBeenCalled()
    expect(listAuditLogMock).not.toHaveBeenCalled()
  })

  it("audit.view reddi → /dashboard redirect (fail-closed)", async () => {
    hasAuditViewPermissionMock.mockResolvedValue(false)

    const { default: AdminAuditPage } = await import("./page")
    await expect(
      AdminAuditPage({ searchParams: Promise.resolve({}) })
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(listAuditLogMock).not.toHaveBeenCalled()
  })

  it("izin RPC çökerse sayfa veri OKUMADAN hatayı yukarı taşır (fail-closed)", async () => {
    hasAuditViewPermissionMock.mockRejectedValue(
      new Error("permission denied")
    )

    const { default: AdminAuditPage } = await import("./page")
    await expect(
      AdminAuditPage({ searchParams: Promise.resolve({}) })
    ).rejects.toThrow("permission denied")

    expect(listAuditLogMock).not.toHaveBeenCalled()
  })
})

describe("AdminAuditPage — authorized admin", () => {
  it("kayıt künyesi render edilir; filtreler listAuditLog'a iletilir", async () => {
    listAuditLogMock.mockResolvedValue({
      status: "ok",
      items: [auditEntry()],
      total: 1,
      page: 1,
      totalPages: 1,
    })

    const html = await renderHtml({
      action: "question.edit",
      entity: "aaaaaaaa-1111-4000-8000-000000000001",
    })

    expect(listAuditLogMock).toHaveBeenCalledWith(
      {
        actionCode: "question.edit",
        entityId: "aaaaaaaa-1111-4000-8000-000000000001",
      },
      1
    )
    expect(html).toContain("question.edit")
    expect(html).toContain("2026-09-03 10:00:00")
    expect(html).toContain("99999999-8888-4000-8000-000000000901")
  })

  it("geçersiz filtre parametreleri temizlenir (keyfi metin DB'ye gitmez)", async () => {
    await renderHtml({ action: "DROP TABLE", entity: "garbage", page: "2" })

    expect(listAuditLogMock).toHaveBeenCalledWith(
      { actionCode: undefined, entityId: undefined },
      2
    )
  })

  it("payload (before_data/after_data) listAuditLog'dan gelse bile render edilmez", async () => {
    listAuditLogMock.mockResolvedValue({
      status: "ok",
      items: [
        auditEntry({
          before_data: { secret: "PAGE-GIZLI-BEFORE" },
          after_data: { secret: "PAGE-GIZLI-AFTER" },
        }),
      ],
      total: 1,
      page: 1,
      totalPages: 1,
    })

    const html = await renderHtml()

    expect(html).not.toContain("PAGE-GIZLI-BEFORE")
    expect(html).not.toContain("PAGE-GIZLI-AFTER")
    expect(html).not.toContain("before_data")
    expect(html).not.toContain("after_data")
  })

  it("boş durum ayrı mesajla gösterilir", async () => {
    listAuditLogMock.mockResolvedValue({
      status: "ok",
      items: [],
      total: 0,
      page: 1,
      totalPages: 1,
    })

    const html = await renderHtml()

    expect(html).toContain(
      "Bu filtrelerle eşleşen denetim kaydı bulunamadı"
    )
    expect(html).not.toContain("okunamadı")
  })

  it("veri kaynağı hatasında 'okunamadı' mesajı gösterilir; ham mesaj sızmaz", async () => {
    listAuditLogMock.mockResolvedValue({
      status: "error",
      items: [],
      total: 0,
      page: 1,
      totalPages: 1,
    })

    const html = await renderHtml()

    expect(html).toContain("Denetim kaydı şu anda okunamadı")
    expect(html).not.toContain("db down")
    expect(html).not.toContain("permission denied")
  })

  it("sayfalama filtreleri korur", async () => {
    listAuditLogMock.mockResolvedValue({
      status: "ok",
      items: [auditEntry()],
      total: 30,
      page: 1,
      totalPages: 2,
    })

    const html = await renderHtml({ action: "question.edit" })

    expect(html).toContain("Sayfa 1 / 2")
    expect(html).toContain("action=question.edit&amp;page=2")
  })
})
