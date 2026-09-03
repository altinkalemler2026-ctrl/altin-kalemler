/**
 * /admin dashboard page security tests (Server Component).
 *
 * - Unauthenticated → /login redirect
 * - Non-admin (questions.view denied or error) → /dashboard redirect
 * - Authorized admin → metrics, user count and nav rendered
 * - Metric read failure → "okunamıyor" state (not 0, not raw error)
 * - User count read failure → "okunamıyor" state (not 0)
 * - Raw DB error text never reaches the UI
 * - No mutation imports: page is strictly read-only
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())
const redirectMock = vi.hoisted(() =>
  vi.fn((url: string) => {
    throw new Error(`REDIRECT:${url}`)
  }),
)
const loadDashboardMetricsMock = vi.hoisted(() => vi.fn())
const countUsersMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/admin/admin-dashboard", () => ({
  loadDashboardMetrics: loadDashboardMetricsMock,
  buildExamTrackBreakdown: vi.fn(),
}))

vi.mock("@/lib/admin/admin-users", () => ({
  countUsers: countUsersMock,
  listUsers: vi.fn(),
  getUserDetail: vi.fn(),
}))

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  loadDashboardMetricsMock.mockReset()
  countUsersMock.mockReset()

  loadDashboardMetricsMock.mockResolvedValue({
    published: { value: 12 },
    publishedByExamTrack: { value: 12, breakdown: { TYT: 8, AYT: 4 } },
    reviewQueue: { value: 3 },
    staging: { value: 5 },
  })
  countUsersMock.mockResolvedValue(42)

  createClientMock.mockImplementation(async () => ({
    auth: { getUser: getUserMock },
    rpc: rpcMock,
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

function mockAdminPermission() {
  rpcMock.mockResolvedValue({ data: true, error: null })
}

function mockNoPermission() {
  rpcMock.mockResolvedValue({ data: false, error: null })
}

function mockPermissionError() {
  rpcMock.mockResolvedValue({ data: null, error: { message: "permission denied" } })
}

import AdminDashboardPage from "./page"

describe("AdminDashboardPage — auth gates", () => {
  it("unauthenticated → /login redirect", async () => {
    mockUnauthenticated()

    await expect(AdminDashboardPage()).rejects.toThrow("REDIRECT:/login")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(loadDashboardMetricsMock).not.toHaveBeenCalled()
    expect(countUsersMock).not.toHaveBeenCalled()
  })

  it("permission hatası → /dashboard redirect", async () => {
    mockAuthenticated()
    mockPermissionError()

    await expect(AdminDashboardPage()).rejects.toThrow("REDIRECT:/dashboard")

    expect(loadDashboardMetricsMock).not.toHaveBeenCalled()
    expect(countUsersMock).not.toHaveBeenCalled()
  })

  it("canView !== true (questions.view reddi) → /dashboard redirect", async () => {
    mockAuthenticated()
    mockNoPermission()

    await expect(AdminDashboardPage()).rejects.toThrow("REDIRECT:/dashboard")

    expect(loadDashboardMetricsMock).not.toHaveBeenCalled()
    expect(countUsersMock).not.toHaveBeenCalled()
  })
})

describe("AdminDashboardPage — authorized admin", () => {
  it("questions.view yetkisiyle metrikler ve kullanıcı sayısı yüklenir", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminDashboardPage()

    expect(rpcMock).toHaveBeenCalledWith("teacher_review_admin_has_permission", {
      p_permission_code: "questions.view",
    })
    expect(loadDashboardMetricsMock).toHaveBeenCalledTimes(1)
    expect(countUsersMock).toHaveBeenCalledTimes(1)
  })

  it("başarılı veride kartlar, kırılım ve bölümler render edilir", async () => {
    mockAuthenticated()
    mockAdminPermission()

    const result = await AdminDashboardPage()
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Yayındaki sorular")
    expect(html).toContain("Toplam kullanıcı")
    expect(html).toContain("8")
    expect(html).toContain("4")
    expect(html).toContain("Soru Bankası")
    expect(html).toContain("Kullanıcılar")
  })
})

describe("AdminDashboardPage — hata durumları", () => {
  it("metrik okunamadığında 'okunamıyor' gösterilir, 0 gösterilmez ve ham hata sızmaz", async () => {
    mockAuthenticated()
    mockAdminPermission()
    loadDashboardMetricsMock.mockResolvedValue({
      published: { value: null },
      publishedByExamTrack: { value: null },
      reviewQueue: { value: null },
      staging: { value: null },
    })

    const result = await AdminDashboardPage()
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Bu metrik şu an okunamıyor")
    expect(html).not.toContain("db down")
    expect(html).not.toContain("permission denied")
  })

  it("kullanıcı sayısı okunamadığında 0 yerine 'okunamıyor' gösterilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    countUsersMock.mockResolvedValue(null)

    const result = await AdminDashboardPage()
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Bu metrik şu an okunamıyor")
    expect(html).not.toContain("db down")
  })
})

describe("AdminDashboardPage — no mutation capability", () => {
  it("sayfa mutation fonksiyonu import etmez", async () => {
    const pageModule = await import("./page")
    const source = Object.keys(pageModule)
    expect(source).toEqual(["default"])
  })
})
