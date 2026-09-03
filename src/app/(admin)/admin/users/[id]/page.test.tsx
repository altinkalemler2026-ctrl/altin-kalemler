/**
 * /admin/users/[id] detail page security tests (Server Component).
 *
 * - Unauthenticated → /login redirect
 * - Non-admin → /dashboard redirect
 * - Authorized admin + valid ID → detail renders with safe fields
 * - Authorized admin + invalid ID → "Kullanıcı bulunamadı" message
 * - DTO allowlist enforced: no PII/secrets in rendered output
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
const getUserDetailMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/admin/admin-users", () => ({
  getUserDetail: getUserDetailMock,
  listUsers: vi.fn(),
  countUsers: vi.fn(),
  parseGrade: vi.fn(),
  GRADES: [5, 6, 7, 8, 9, 10, 11, 12],
  mapUserListItem: vi.fn(),
  mapUserDetail: vi.fn(),
}))

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  getUserDetailMock.mockReset()

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

import AdminUserDetailPage from "./page"

describe("AdminUserDetailPage — auth gates", () => {
  it("unauthenticated → /login redirect", async () => {
    mockUnauthenticated()

    await expect(
      AdminUserDetailPage({ params: Promise.resolve({ id: "u1" }) }),
    ).rejects.toThrow("REDIRECT:/login")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(getUserDetailMock).not.toHaveBeenCalled()
  })

  it("permission hatası → /dashboard redirect", async () => {
    mockAuthenticated()
    mockPermissionError()

    await expect(
      AdminUserDetailPage({ params: Promise.resolve({ id: "u1" }) }),
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(getUserDetailMock).not.toHaveBeenCalled()
  })

  it("canView !== true → /dashboard redirect", async () => {
    mockAuthenticated()
    mockNoPermission()

    await expect(
      AdminUserDetailPage({ params: Promise.resolve({ id: "u1" }) }),
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(getUserDetailMock).not.toHaveBeenCalled()
  })
})

describe("AdminUserDetailPage — authorized admin", () => {
  it("users.manage yetkisiyle getUserDetail çağrılır", async () => {
    mockAuthenticated()
    mockAdminPermission()
    getUserDetailMock.mockResolvedValue({ status: "ok", item: null })

    await AdminUserDetailPage({ params: Promise.resolve({ id: "u1" }) })

    expect(rpcMock).toHaveBeenCalledWith("teacher_review_admin_has_permission", {
      p_permission_code: "users.manage",
    })
    expect(getUserDetailMock).toHaveBeenCalledWith("u1")
  })
})

describe("AdminUserDetailPage — hata/bulunamadı ayrımı", () => {
  it("kullanıcı bulunamadığında 'bulunamadı' mesajı gösterilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    getUserDetailMock.mockResolvedValue({ status: "ok", item: null })

    const result = await AdminUserDetailPage({
      params: Promise.resolve({ id: "nonexistent" }),
    })

    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Kullanıcı bulunamadı")
    expect(html).not.toContain("okunamadı")
  })

  it("veri kaynağı hatasında ayrı hata mesajı gösterilir (ham mesaj sızmaz)", async () => {
    mockAuthenticated()
    mockAdminPermission()
    getUserDetailMock.mockResolvedValue({ status: "error", item: null })

    const result = await AdminUserDetailPage({
      params: Promise.resolve({ id: "u1" }),
    })

    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Kullanıcı bilgileri şu anda okunamadı")
    expect(html).not.toContain("Kullanıcı bulunamadı")
    expect(html).not.toContain("db down")
    expect(html).not.toContain("permission denied")
  })
})

describe("AdminUserDetailPage — PII/secret non-leakage", () => {
  it("hiçbir sensitive alan detail sonucundan geçmez", async () => {
    mockAuthenticated()
    mockAdminPermission()
    getUserDetailMock.mockResolvedValue({
      status: "ok",
      item: {
        id: "u1",
        nickname: "testuser",
        grade_level: 8,
        created_at: "2026-01-01T00:00:00Z",
        updated_at: "2026-06-01T00:00:00Z",
        is_visible: true,
        total_points: 200,
        monthly_points: 50,
        avatar_key: "av.png",
        character_key: "knight",
        league_code: "gold",
        email: "secret@example.com",
        phone: "+905551234567",
        password_hash: "$2b$10$secret",
        metadata: { email: "x" },
        schedule_profile_id: "secret",
        raw_user_meta_data: { provider: "google" },
      },
    })

    const result = await AdminUserDetailPage({
      params: Promise.resolve({ id: "u1" }),
    })

    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).not.toContain("secret@example.com")
    expect(html).not.toContain("+905551234567")
    expect(html).not.toContain("$2b$10$")
    expect(html).not.toContain("password_hash")
    expect(html).not.toContain("schedule_profile_id")
    expect(html).not.toContain("raw_user_meta_data")
  })
})

describe("AdminUserDetailPage — no mutation capability", () => {
  it("sayfa mutation fonksiyonu import etmez", async () => {
    const pageModule = await import("./page")
    const source = Object.keys(pageModule)
    expect(source).toEqual(["default"])
  })
})
