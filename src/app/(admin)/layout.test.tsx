/**
 * (admin) layout testleri (Server Component — menü kabuğu).
 *
 * - Oturum yoksa /login'e yönlendirilir (koruma korunur)
 * - questions.view reddi veya hatasında /dashboard'e yönlendirilir (fail-closed)
 * - Yetkili yönetici: menü yalnız izin verdiği rotaları içerir + home
 * - Menü izin RPC'leri tüm nav izin kodlarını kapsar (menü fail-closed)
 * - Çocuk içerik kabuğun altında render edilir
 * - Çocuk içerik odak yüzeyi (.admin-surface) içindedir (F4)
 * - AdminNav yalnız gezinme verisi alır (items + userLabel)
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
const AdminNavMock = vi.hoisted(() =>
  vi.fn((props: unknown) => {
    void props
    return null
  }),
)

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/components/admin/AdminNav", () => ({
  default: AdminNavMock,
}))

import AdminLayout from "./layout"

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  AdminNavMock.mockClear()

  createClientMock.mockImplementation(async () => ({
    auth: { getUser: getUserMock },
    rpc: rpcMock,
  }))
})

function mockAuthenticated() {
  getUserMock.mockResolvedValue({
    data: {
      user: {
        id: "99999999-8888-4000-8000-000000000911",
        email: "admin@altinkalem.test",
      },
    },
  })
}

function mockAuthenticatedWithoutEmail() {
  getUserMock.mockResolvedValue({
    data: { user: { id: "99999999-8888-4000-8000-000000000912", email: null } },
  })
}

function mockPermissionSet(
  permissions: Record<string, boolean>,
  errorCodes: string[] = [],
) {
  rpcMock.mockImplementation(
    async (
      _functionName: string,
      args: { p_permission_code: string },
    ) => ({
      data: errorCodes.includes(args.p_permission_code)
        ? null
        : permissions[args.p_permission_code] === true,
      error: errorCodes.includes(args.p_permission_code)
        ? { message: "permission denied" }
        : null,
    }),
  )
}

function mockUnauthenticated() {
  getUserMock.mockResolvedValue({ data: { user: null } })
}

function mockUserError() {
  getUserMock.mockResolvedValue({ data: { user: null }, error: { message: "auth down" } })
}

function mockFullAdmin() {
  mockPermissionSet({
    "questions.view": true,
    "ai.manage": true,
    "questions.approve": true,
    "calendar.manage": true,
    "users.manage": true,
    "curriculum.manage": true,
    "audit.view": true,
  })
}

function navProps() {
  return AdminNavMock.mock.calls[0]?.[0] as
    | { items: { href: string; title: string }[]; userLabel: string }
    | undefined
}

function itemHrefs(): string[] {
  return (navProps()?.items ?? []).map((item) => item.href)
}

async function renderLayout(children: React.ReactNode) {
  const element = await AdminLayout({ children })
  const { renderToString } = await import("react-dom/server")
  renderToString(element)
}

describe("AdminLayout — koruma kapıları korunuyor", () => {
  it("oturum yoksa /login'e yönlendirilir; hiçbir izin yoklaması yapılmaz", async () => {
    mockUnauthenticated()

    await expect(AdminLayout({ children: <div /> })).rejects.toThrow(
      "REDIRECT:/login",
    )

    expect(rpcMock).not.toHaveBeenCalled()
    expect(AdminNavMock).not.toHaveBeenCalled()
  })

  it("getUser hatasında /login'e yönlendirilir", async () => {
    mockUserError()

    await expect(AdminLayout({ children: <div /> })).rejects.toThrow(
      "REDIRECT:/login",
    )

    expect(AdminNavMock).not.toHaveBeenCalled()
  })

  it("questions.view reddinde /dashboard'e yönlendirilir", async () => {
    mockAuthenticated()
    mockPermissionSet({})

    await expect(AdminLayout({ children: <div /> })).rejects.toThrow(
      "REDIRECT:/dashboard",
    )

    expect(AdminNavMock).not.toHaveBeenCalled()
  })

  it("questions.view hata verirse fail-closed /dashboard'e yönlendirilir", async () => {
    mockAuthenticated()
    mockPermissionSet(
      { "questions.view": true },
      ["questions.view"],
    )

    await expect(AdminLayout({ children: <div /> })).rejects.toThrow(
      "REDIRECT:/dashboard",
    )

    expect(AdminNavMock).not.toHaveBeenCalled()
  })
})

describe("AdminLayout — yetkili yönetici menü kabuğu", () => {
  it("tam yetkiyle home + tüm gerçek admin rotaları menüye gelir", async () => {
    mockAuthenticated()
    mockFullAdmin()

    await renderLayout(<div>CHILD_MARKER</div>)

    expect(AdminNavMock).toHaveBeenCalledTimes(1)
    expect(itemHrefs()).toEqual([
      "/admin",
      "/admin/questions",
      "/admin/candidate-batches",
      "/admin/academic-calendar",
      "/admin/users",
      "/admin/teacher-reviews",
      "/admin/curriculum-teaching",
      "/admin/audit",
    ])
    expect(navProps()?.userLabel).toBe("admin@altinkalem.test")
  })

  it("yalnız questions.view ile home + Soru Bankası + Öğretmen İncelemeleri gösterilir", async () => {
    mockAuthenticated()
    mockPermissionSet({
      "questions.view": true,
      "questions.approve": true,
    })

    await renderLayout(<div>CHILD_MARKER</div>)

    expect(itemHrefs()).toEqual([
      "/admin",
      "/admin/questions",
      "/admin/candidate-batches",
      "/admin/teacher-reviews",
    ])
  })

  it("bir rota izin hatasında o bağlantı menüden gizlenir (fail-closed)", async () => {
    mockAuthenticated()
    mockPermissionSet(
      {
        "questions.view": true,
        "ai.manage": true,
        "questions.approve": true,
        "calendar.manage": true,
        "users.manage": true,
        "curriculum.manage": true,
        "audit.view": true,
      },
      ["users.manage"],
    )

    await renderLayout(<div>CHILD_MARKER</div>)

    const hrefs = itemHrefs()
    expect(hrefs).toContain("/admin/audit")
    expect(hrefs).not.toContain("/admin/users")
  })

  it("menü izin RPC'leri tüm nav izin kodlarını kapsar", async () => {
    mockAuthenticated()
    mockFullAdmin()

    await AdminLayout({ children: <div /> })

    for (const code of [
      "questions.view",
      "ai.manage",
      "questions.approve",
      "calendar.manage",
      "users.manage",
      "curriculum.manage",
      "audit.view",
    ]) {
      expect(rpcMock).toHaveBeenCalledWith(
        "teacher_review_admin_has_permission",
        { p_permission_code: code },
      )
    }
  })

  it("e-posta yoksa güvenli varsayılan kullanıcı etiketi gösterilir", async () => {
    mockAuthenticatedWithoutEmail()
    mockFullAdmin()

    await renderLayout(<div />)

    expect(navProps()?.userLabel).toBe("Yönetici")
  })

  it("çocuk içerik kabuğun altında render edilir", async () => {
    mockAuthenticated()
    mockFullAdmin()

    const element = await AdminLayout({ children: <div>CHILD_MARKER</div> })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(element)

    expect(html).toContain("CHILD_MARKER")
  })

  it("çocuk içerik odak yüzeyinin (.admin-surface) içinde render edilir", async () => {
    mockAuthenticated()
    mockFullAdmin()

    const element = await AdminLayout({ children: <div>CHILD_MARKER</div> })
    const { renderToString } = await import("react-dom/server")
    const html = renderToString(element)

    expect(html).toContain('class="admin-surface"')
    expect(html).toMatch(/admin-surface">\s*<div>CHILD_MARKER<\/div>/)
  })
})