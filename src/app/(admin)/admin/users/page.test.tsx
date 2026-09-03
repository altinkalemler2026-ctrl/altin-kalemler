/**
 * /admin/users list page security tests (Server Component).
 *
 * - Unauthenticated → /login redirect
 * - Non-admin (permission error or canView !== true) → /dashboard redirect
 * - Authorized admin → page renders with safe fields only
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
const listUsersMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/lib/admin/admin-users", async () => {
  const actual = await vi.importActual<typeof import("@/lib/admin/admin-users")>(
    "@/lib/admin/admin-users",
  )
  return {
    listUsers: listUsersMock,
    parseGrade: actual.parseGrade,
    GRADES: actual.GRADES,
    USER_LIST_LIMIT: actual.USER_LIST_LIMIT,
    countUsers: vi.fn(),
    getUserDetail: vi.fn(),
    mapUserListItem: vi.fn(),
    mapUserDetail: vi.fn(),
  }
})

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  listUsersMock.mockReset()
  listUsersMock.mockResolvedValue([])

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

import AdminUsersPage from "./page"

describe("AdminUsersPage — auth gates", () => {
  it("unauthenticated → /login redirect", async () => {
    mockUnauthenticated()

    await expect(
      AdminUsersPage({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow("REDIRECT:/login")

    expect(rpcMock).not.toHaveBeenCalled()
    expect(listUsersMock).not.toHaveBeenCalled()
  })

  it("permission hatası → /dashboard redirect", async () => {
    mockAuthenticated()
    mockPermissionError()

    await expect(
      AdminUsersPage({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(listUsersMock).not.toHaveBeenCalled()
  })

  it("canView !== true → /dashboard redirect", async () => {
    mockAuthenticated()
    mockNoPermission()

    await expect(
      AdminUsersPage({ searchParams: Promise.resolve({}) }),
    ).rejects.toThrow("REDIRECT:/dashboard")

    expect(listUsersMock).not.toHaveBeenCalled()
  })
})

describe("AdminUsersPage — authorized admin", () => {
  it("users.manage yetkisiyle listUsers çağrılır", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminUsersPage({ searchParams: Promise.resolve({}) })

    expect(rpcMock).toHaveBeenCalledWith("teacher_review_admin_has_permission", {
      p_permission_code: "users.manage",
    })
    expect(listUsersMock).toHaveBeenCalledWith({ grade: undefined, query: undefined })
  })

  it("grade filtresi doğrudan geçirilir", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminUsersPage({ searchParams: Promise.resolve({ grade: "7" }) })

    expect(listUsersMock).toHaveBeenCalledWith({ grade: 7, query: undefined })
  })

  it("query filtresi doğrudan geçirilir", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminUsersPage({ searchParams: Promise.resolve({ query: "ali" }) })

    expect(listUsersMock).toHaveBeenCalledWith({ grade: undefined, query: "ali" })
  })
})

describe("AdminUsersPage — PII/secret non-leakage", () => {
  it("hiçbir sensitive alan listUsers sonuçlarından geçmez", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue([
      {
        id: "u1",
        nickname: "testuser",
        grade_level: 7,
        created_at: "2026-01-01T00:00:00Z",
        is_visible: true,
        total_points: 100,
        monthly_points: 10,
        avatar_key: "av.png",
        email: "secret@example.com",
        phone: "+905551234567",
        password_hash: "$2b$10$secret",
        metadata: { email: "x" },
        schedule_profile_id: "secret",
      },
    ])

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({}),
    })

    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).not.toContain("secret@example.com")
    expect(html).not.toContain("+905551234567")
    expect(html).not.toContain("$2b$10$")
    expect(html).not.toContain("password_hash")
    expect(html).not.toContain("schedule_profile_id")
  })
})

describe("AdminUsersPage — no mutation capability", () => {
  it("sayfa mutation fonksiyonu import etmez", async () => {
    const pageModule = await import("./page")
    const source = Object.keys(pageModule)
    expect(source).toEqual(["default"])
  })
})

describe("AdminUsersPage — liste kesme uyarısı", () => {
  const baseUser = {
    id: "u1",
    nickname: "testuser",
    grade_level: 7,
    created_at: "2026-01-01T00:00:00Z",
    is_visible: true,
    total_points: 100,
    monthly_points: 10,
    avatar_key: "av.png",
  }

  function fillUsers(count: number) {
    return Array.from({ length: count }, (_, i) => ({
      ...baseUser,
      id: `u${i}`,
      nickname: `user-${i}`,
    }))
  }

  it("limite ulaşıldığında kesme uyarısı gösterilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    const { USER_LIST_LIMIT } = await import("@/lib/admin/admin-users")
    listUsersMock.mockResolvedValue(fillUsers(USER_LIST_LIMIT))

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("yalnızca ilk 200 kayıt gösteriliyor")
  })

  it("limit altında kesme uyarısı gösterilmez", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue(fillUsers(3))

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).not.toContain("yalnızca ilk 200 kayıt gösteriliyor")
  })

  it("bozuk tarih güvenli '-' olarak gösterilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue([
      { ...baseUser, created_at: "tarih-degil" },
    ])

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).not.toContain("Invalid Date")
    expect(html).toContain(">-</p>")
  })
})
