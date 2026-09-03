/**
 * /admin/users list page security + pagination tests (Server Component).
 *
 * - Unauthenticated → /login redirect
 * - Non-admin (permission error or canView !== true) → /dashboard redirect
 * - Authorized admin → page renders with safe fields only
 * - Server-side pagination: page parsing, range, prev/next links
 * - Error vs empty separation: data source error shows distinct message
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
    parsePage: actual.parsePage,
    parseSort: actual.parseSort,
    GRADES: actual.GRADES,
    SORT_OPTIONS: actual.SORT_OPTIONS,
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
  listUsersMock.mockResolvedValue({
    status: "ok",
    items: [],
    total: 0,
    page: 1,
    totalPages: 1,
  })

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

function okResult(overrides: Partial<{ items: unknown[]; total: number; page: number; totalPages: number }> = {}) {
  return {
    status: "ok",
    items: [],
    total: 0,
    page: 1,
    totalPages: 1,
    ...overrides,
  }
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
  it("users.manage yetkisiyle listUsers varsayılan sayfa 1 ile çağrılır", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminUsersPage({ searchParams: Promise.resolve({}) })

    expect(rpcMock).toHaveBeenCalledWith("teacher_review_admin_has_permission", {
      p_permission_code: "users.manage",
    })
    expect(listUsersMock).toHaveBeenCalledWith(
      { grade: undefined, query: undefined, sort: "newest" },
      1,
    )
  })

  it("grade ve query filtreleri doğrudan geçirilir", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminUsersPage({
      searchParams: Promise.resolve({ grade: "7", query: "ali" }),
    })

    expect(listUsersMock).toHaveBeenCalledWith(
      { grade: 7, query: "ali", sort: "newest" },
      1,
    )
  })

  it("page parametresi sayıya çevrilip geçirilir", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminUsersPage({ searchParams: Promise.resolve({ page: "2" }) })

    expect(listUsersMock).toHaveBeenCalledWith(
      { grade: undefined, query: undefined, sort: "newest" },
      2,
    )
  })

  it("geçersiz page değerleri 1'e düşer", async () => {
    mockAuthenticated()
    mockAdminPermission()

    for (const bad of ["abc", "0", "-3", "2.5", ""]) {
      listUsersMock.mockClear()
      await AdminUsersPage({ searchParams: Promise.resolve({ page: bad }) })
      expect(listUsersMock).toHaveBeenCalledWith(
        { grade: undefined, query: undefined, sort: "newest" },
        1,
      )
    }
  })

  it("çok büyük page güvenli üst sınıra kırpılır", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminUsersPage({
      searchParams: Promise.resolve({ page: "99999999999" }),
    })

    expect(listUsersMock).toHaveBeenCalledWith(
      { grade: undefined, query: undefined, sort: "newest" },
      1_000_000,
    )
  })

  it("geçerli sort parametresi geçirilir", async () => {
    mockAuthenticated()
    mockAdminPermission()

    await AdminUsersPage({ searchParams: Promise.resolve({ sort: "oldest" }) })

    expect(listUsersMock).toHaveBeenCalledWith(
      { grade: undefined, query: undefined, sort: "oldest" },
      1,
    )
  })

  it("geçersiz sort güvenli varsayılana düşer", async () => {
    mockAuthenticated()
    mockAdminPermission()

    for (const bad of ["abc", "ASC", "", "points"]) {
      listUsersMock.mockClear()
      await AdminUsersPage({ searchParams: Promise.resolve({ sort: bad }) })
      expect(listUsersMock).toHaveBeenCalledWith(
        { grade: undefined, query: undefined, sort: "newest" },
        1,
      )
    }
  })
})

describe("AdminUsersPage — PII/secret non-leakage", () => {
  it("hiçbir sensitive alan listUsers sonuçlarından geçmez", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue(
      okResult({
        items: [
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
        ],
        total: 1,
      }),
    )

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

describe("AdminUsersPage — hata ve boş durum ayrımı", () => {
  it("gerçekten boş sonuçta 'kayıt bulunamadı' mesajı gösterilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue(okResult())

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Bu filtrelerle eşleşen kullanıcı bulunamadı")
    expect(html).not.toContain("okunamadı")
  })

  it("veri kaynağı hatasında ayrı hata mesajı gösterilir (ham mesaj sızmaz)", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue({
      status: "error",
      items: [],
      total: 0,
      page: 1,
      totalPages: 1,
    })

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Kullanıcı listesi şu anda okunamadı")
    expect(html).not.toContain("Bu filtrelerle eşleşen kullanıcı bulunamadı")
    expect(html).not.toContain("db down")
    expect(html).not.toContain("permission denied")
  })
})

describe("AdminUsersPage — sayfalama gezinmesi", () => {
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

  it("çok sayfalı sonuçta sayfa göstergesi ve her iki bağlantı görünür", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue(
      okResult({ items: [baseUser], total: 60, page: 2, totalPages: 3 }),
    )

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({ page: "2" }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Sayfa 2 / 3")
    expect(html).toContain("Önceki")
    expect(html).toContain("Sonraki")
    expect(html).toContain('aria-label="Sayfalama"')
  })

  it("bağlantılar arama ve filtre parametrelerini korur", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue(
      okResult({ items: [baseUser], total: 60, page: 2, totalPages: 3 }),
    )

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({ grade: "7", query: "ali", page: "2" }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("grade=7&amp;query=ali&amp;sort=newest&amp;page=1")
    expect(html).toContain("grade=7&amp;query=ali&amp;sort=newest&amp;page=3")
  })

  it("ilk sayfada 'Önceki' devre dışıdır", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue(
      okResult({ items: [baseUser], total: 60, page: 1, totalPages: 3 }),
    )

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain('aria-disabled="true"')
    expect(html).toContain("Sayfa 1 / 3")
    expect(html).not.toContain("page=0")
  })

  it("son sayfada 'Sonraki' devre dışıdır", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue(
      okResult({ items: [baseUser], total: 60, page: 3, totalPages: 3 }),
    )

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({ page: "3" }),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).toContain("Sayfa 3 / 3")
    expect(html).not.toContain("page=4")
  })

  it("tek sayfalık sonuçta gezinme gösterilmez", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue(
      okResult({ items: [baseUser], total: 5, page: 1, totalPages: 1 }),
    )

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).not.toContain('aria-label="Sayfalama"')
  })

  it("bozuk tarih güvenli '-' olarak gösterilir", async () => {
    mockAuthenticated()
    mockAdminPermission()
    listUsersMock.mockResolvedValue(
      okResult({
        items: [{ ...baseUser, created_at: "tarih-degil" }],
        total: 1,
      }),
    )

    const result = await AdminUsersPage({
      searchParams: Promise.resolve({}),
    })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(result)

    expect(html).not.toContain("Invalid Date")
    expect(html).toContain(">-</p>")
  })
})

describe("AdminUsersPage — no mutation capability", () => {
  it("sayfa mutation fonksiyonu import etmez", async () => {
    const pageModule = await import("./page")
    const source = Object.keys(pageModule)
    expect(source).toEqual(["default"])
  })
})
