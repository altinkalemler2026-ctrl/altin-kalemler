/**
 * /admin/roles — Süper admin rol yönetimi sayfa (server component) testleri.
 *
 * Kanıtlanan sözleşmeler:
 * - Giriş yoksa → /login; `questions.view` (admin layout ile aynı düzey)
 *   yoksa veya RPC hata verirse → /dashboard (fail-closed).
 * - RC-2 kapalı durum: `users.manage` ve/veya süper yönetici olmayan bir
 *   yönetici SAYFAYA GİRER ama yalnız kapalı durum kartını görür; rol
 *   listesi, hedef kullanıcı verisi, arama formu ve mutasyon kontrolü hiç
 *   okunmaz/render edilmez (sahte buton yok, veri sızmaz).
 * - Süper yönetici görünürlüğü: isSuperAdmin true (ve users.manage true)
 *   ise panel + arama formu render edilir.
 * - Self koruması: roster'da kendi satırı "Siz" rozetiyle listelenir ama
 *   hedef radyolarında `value={actor}` bulunmadığı doğrulanır.
 * - Denetim bağlantısı yalnız gerçek yazma (`ok` + `audit=1` + geçerli
 *   hedef) VE `audit.view` izni varken gösterilir.
 * - Hata durumları ayrık: roster okunamadı vs takma ad okunamadı vs
 *   katalog okunamadı ayrı mesajlarla bildirilir.
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())
const redirectMock = vi.hoisted(() =>
  vi.fn((url: string) => {
    throw new Error(`REDIRECT:${url}`)
  }),
)
const hasPermissionMock = vi.hoisted(() => vi.fn())
const superAdminMock = vi.hoisted(() => vi.fn())
const rosterMock = vi.hoisted(() => vi.fn())
const rolesMock = vi.hoisted(() => vi.fn())
const labelsMock = vi.hoisted(() => vi.fn())
const listUsersMock = vi.hoisted(() => vi.fn())
const auditViewMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({ redirect: redirectMock }))
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }))
vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: getUserMock },
    rpc: rpcMock,
  })),
}))
vi.mock("@/lib/admin/role-management", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/admin/role-management")>()
  return {
    ...actual,
    hasUsersManagePermission: hasPermissionMock,
    isCurrentUserSuperAdmin: superAdminMock,
    listRoleAssignments: rosterMock,
    listActiveRoles: rolesMock,
    resolveUserNicknames: labelsMock,
  }
})
vi.mock("@/lib/admin/admin-users", () => ({ listUsers: listUsersMock }))
vi.mock("@/lib/admin/audit-log", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/admin/audit-log")>()
  return {
    ...actual,
    hasAuditViewPermission: auditViewMock,
  }
})
vi.mock("./actions", () => ({ submitRoleMutationAction: vi.fn() }))

import AdminRolesPage from "./page"

const ACTOR_ID = "99999999-8888-4000-8000-000000000901"
const TARGET_ID = "11111111-2222-4333-8444-555555555551"
const STUDENT_ID = "33333333-4444-4555-8666-777777777773"

const ACTIVE_ROLES = [
  { roleCode: "content_admin", name: "İçerik Yöneticisi", description: null },
  { roleCode: "question_reviewer", name: "Soru İnceleyici", description: null },
  { roleCode: "super_admin", name: "Süper Yönetici", description: null },
]

function mockAuthenticated(userId = ACTOR_ID) {
  getUserMock.mockResolvedValue({ data: { user: { id: userId } } })
}

function mockUnauthenticated() {
  getUserMock.mockResolvedValue({ data: { user: null } })
}

async function renderPage(searchParams: Record<string, string>) {
  const result = await AdminRolesPage({
    searchParams: Promise.resolve(searchParams),
  })
  const { renderToString } = await import("react-dom/server")
  return renderToString(result)
}

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  rpcMock.mockResolvedValue({ data: true, error: null })
  redirectMock.mockClear()
  hasPermissionMock.mockReset()
  superAdminMock.mockReset()
  rosterMock.mockReset()
  rolesMock.mockReset()
  labelsMock.mockReset()
  listUsersMock.mockReset()
  auditViewMock.mockReset()

  mockAuthenticated()
  hasPermissionMock.mockResolvedValue(true)
  superAdminMock.mockResolvedValue({ status: "ok", isSuperAdmin: true })
  rosterMock.mockResolvedValue({ status: "ok", items: [] })
  rolesMock.mockResolvedValue({ status: "ok", items: ACTIVE_ROLES })
  labelsMock.mockResolvedValue({ status: "ok", labels: {} })
  listUsersMock.mockResolvedValue({
    status: "ok",
    items: [],
    total: 0,
    page: 1,
    totalPages: 1,
  })
  auditViewMock.mockResolvedValue(true)
})

describe("AdminRolesPage — oturum ve yetki kapıları", () => {
  it("giriş yoksa /login'e yönlendirilir", async () => {
    mockUnauthenticated()

    await expect(renderPage({})).rejects.toThrow("REDIRECT:/login")
    expect(rosterMock).not.toHaveBeenCalled()
  })

  it("questions.view yoksa /dashboard'a yönlendirilir (admin olmayan)", async () => {
    rpcMock.mockResolvedValue({ data: false, error: null })

    await expect(renderPage({})).rejects.toThrow("REDIRECT:/dashboard")
    expect(hasPermissionMock).not.toHaveBeenCalled()
    expect(rosterMock).not.toHaveBeenCalled()
    expect(listUsersMock).not.toHaveBeenCalled()
  })

  it("izin RPC'si hata verirse fail-closed /dashboard'a yönlendirilir", async () => {
    rpcMock.mockResolvedValue({
      data: null,
      error: { message: "permission denied" },
    })

    await expect(renderPage({})).rejects.toThrow("REDIRECT:/dashboard")
    expect(hasPermissionMock).not.toHaveBeenCalled()
    expect(rosterMock).not.toHaveBeenCalled()
  })
})

describe("AdminRolesPage — RC-2 kapalı durum kartı (erişilebilir)", () => {
  it("question_reviewer yalnız kapalı kartı görür; rol/hedef verisi ve mutasyon yüzeyi yok", async () => {
    hasPermissionMock.mockResolvedValue(false)
    superAdminMock.mockResolvedValue({ status: "ok", isSuperAdmin: false })
    rosterMock.mockResolvedValue({
      status: "ok",
      items: [
        { userId: TARGET_ID, roleCode: "content_admin", roleName: "İçerik Yöneticisi" },
      ],
    })
    labelsMock.mockResolvedValue({
      status: "ok",
      labels: { [TARGET_ID]: "Hedef" },
    })

    const html = await renderPage({})

    expect(html).toContain("Rol Atama ve Kaldırma Kapalı")
    expect(html).toContain("yalnız süper yönetici yapabilir")
    expect(html).toContain("Rol Yönetimi")
    expect(html).toContain("Panele dön")

    // Rol listesi, hedef kullanıcı verisi ve etiketler HİÇ okunmaz.
    expect(rosterMock).not.toHaveBeenCalled()
    expect(listUsersMock).not.toHaveBeenCalled()
    expect(labelsMock).not.toHaveBeenCalled()
    expect(html).not.toContain('aria-labelledby="roster-heading"')
    expect(html).not.toContain("Yönetici Rolleri")
    expect(html).not.toContain(TARGET_ID)

    // Mutasyon kontrolü, arama formu ve denetim bağlantısı yok.
    expect(html).not.toContain('name="role-target"')
    expect(html).not.toContain('name="operation"')
    expect(html).not.toContain('name="q"')
    expect(html).not.toContain("/admin/audit")
  })

  it("RolesHeader 'Panele dön' bağlantısı ≥44px dokunma hedefi sözleşmesini korur", async () => {
    hasPermissionMock.mockResolvedValue(false)
    superAdminMock.mockResolvedValue({ status: "ok", isSuperAdmin: false })

    const html = await renderPage({})

    // Erişilebilir ad ve rota hedefi değişmez.
    const nameIndex = html.indexOf("Panele dön")
    expect(nameIndex).toBeGreaterThan(-1)
    const tagStart = html.lastIndexOf("<a ", nameIndex)
    expect(tagStart).toBeGreaterThan(-1)
    const tag = html.slice(tagStart, html.indexOf(">", tagStart) + 1)

    // Yön (rol sayfasındaki tek "Panele dön" bağlantısı) /admin'dir.
    expect(tag).toContain('href="/admin"')

    // 44px hit-area sınıf sözleşmesi (candidate-batches eşdeğer deseniyle aynı).
    expect(tag).toContain("min-h-[44px]")
    expect(tag).toContain("inline-flex")
    expect(tag).toContain("items-center")
  })

  it("users.manage olan ama süper yönetici olmayan da yalnız kapalı kartı görür", async () => {
    hasPermissionMock.mockResolvedValue(true)
    superAdminMock.mockResolvedValue({ status: "ok", isSuperAdmin: false })

    const html = await renderPage({})

    expect(html).toContain("Rol Atama ve Kaldırma Kapalı")
    expect(rosterMock).not.toHaveBeenCalled()
    expect(listUsersMock).not.toHaveBeenCalled()
    expect(html).not.toContain('aria-labelledby="roster-heading"')
    expect(html).not.toContain('name="role-target"')
    expect(html).not.toContain('name="q"')
  })
})

describe("AdminRolesPage — süper yönetici görünürlüğü", () => {
  it("süper yöneticiyse panel ve hedef arama formu render edilir", async () => {
    rosterMock.mockResolvedValue({
      status: "ok",
      items: [
        { userId: TARGET_ID, roleCode: "content_admin", roleName: "İçerik Yöneticisi" },
      ],
    })
    labelsMock.mockResolvedValue({
      status: "ok",
      labels: { [TARGET_ID]: "Hedef" },
    })

    const html = await renderPage({})

    expect(html).toContain("Yönetici Rolleri")
    expect(html).toContain("1. İşlemi Seç")
    expect(html).toContain('name="role-target"')
    expect(html).toContain('name="q"')
    expect(html).not.toContain("mutationClosedBody")
    expect(html).not.toContain("Rol Atama ve Kaldırma Kapalı")
  })

  it("süper yönetici değilse mutasyon alanı ve arama formu render edilmez", async () => {
    superAdminMock.mockResolvedValue({ status: "ok", isSuperAdmin: false })

    const html = await renderPage({})

    expect(html).toContain("Rol Atama ve Kaldırma Kapalı")
    expect(html).toContain("yalnız süper yönetici yapabilir")
    expect(html).not.toContain('name="role-target"')
    expect(html).not.toContain('name="q"')
    expect(html).not.toContain('name="operation"')
    expect(html).not.toContain('href="/admin/audit')
    expect(listUsersMock).not.toHaveBeenCalled()
    // RC-2: salt-okunur rol listesi de yalnızca yönetim yüzeyinde okunur.
    expect(rosterMock).not.toHaveBeenCalled()
    expect(html).not.toContain('aria-labelledby="roster-heading"')
  })

  it("is_current_user_super_admin hatası kapalı duruma düşer (fail-closed)", async () => {
    superAdminMock.mockResolvedValue({ status: "error", isSuperAdmin: false })

    const html = await renderPage({})

    expect(html).toContain("Rol Atama ve Kaldırma Kapalı")
    expect(html).not.toContain('name="role-target"')
  })

  it("roster kendi satırını Siz rozetiyle gösterir ama hedeften çıkarır", async () => {
    rosterMock.mockResolvedValue({
      status: "ok",
      items: [
        { userId: ACTOR_ID, roleCode: "super_admin", roleName: "Süper Yönetici" },
        { userId: TARGET_ID, roleCode: "content_admin", roleName: "İçerik Yöneticisi" },
      ],
    })

    const html = await renderPage({})

    expect(html).toContain("Siz")
    expect(html).toContain(">Süper Yönetici<")
    // Super_admin rozeti yalnız salt-okunur listede; hedef seçiminde yok.
    expect(html).not.toContain(`value="${ACTOR_ID}"`)
    expect(html).toContain(`value="${TARGET_ID}"`)
    // Kategorik ret, kullanıcıya görünür biçimde iletilir.
    expect(html).toContain("Süper yönetici rolü bu ekrandan yönetilemez")
  })
})

describe("AdminRolesPage — denetim bağlantısı sözleşmesi", () => {
  it("ok + audit=1 + hedef + audit.view izni varken bağlantı gösterilir", async () => {
    const html = await renderPage({
      ok: "Rol atandı. ...",
      audit: "1",
      target: TARGET_ID,
    })

    expect(html).toContain("Denetim kaydını görüntüle")
    expect(html).toContain(`/admin/audit?entity=${TARGET_ID}`)
  })

  it("audit izni yoksa bağlantı gösterilmez", async () => {
    auditViewMock.mockResolvedValue(false)

    const html = await renderPage({
      ok: "Rol atandı. ...",
      audit: "1",
      target: TARGET_ID,
    })

    expect(html).not.toContain("Denetim kaydını görüntüle")
    expect(html).not.toContain("/admin/audit?entity=")
  })

  it("already_* flash (`audit` yok) bağlantı üretmez", async () => {
    const html = await renderPage({ ok: "Bu rol zaten atanmış durumda." })

    expect(html).not.toContain("Denetim kaydını görüntüle")
    expect(html).not.toContain("/admin/audit?entity=")
  })

  it("hata flash'ı denetim bağlantısı üretmez", async () => {
    const html = await renderPage({ error: "Rol işlemi tamamlanamadı." })

    expect(html).toContain("Rol işlemi tamamlanamadı.")
    expect(html).not.toContain('/admin/audit?entity=')
  })
})

describe("AdminRolesPage — hata durumları ayrışması", () => {
  it("roster okunamadığında ayrı mesaj gösterilir", async () => {
    rosterMock.mockResolvedValue({ status: "error", items: [] })

    const html = await renderPage({})

    expect(html).toContain("Rol listesi şu anda okunamadı")
  })

  it("takma adlar okunamadığında kısa kimlik fallback'i ve uyarı gösterilir", async () => {
    rosterMock.mockResolvedValue({
      status: "ok",
      items: [
        { userId: TARGET_ID, roleCode: "content_admin", roleName: "İçerik Yöneticisi" },
      ],
    })
    labelsMock.mockResolvedValue({ status: "error", labels: {} })

    const html = await renderPage({})

    expect(html).toContain("Kullanıcı takma adları şu anda okunamadı")
    expect(html).toContain(TARGET_ID.slice(0, 8))
  })

  it("katalog okunamadığında panel yerine katalog hatası gösterilir", async () => {
    rolesMock.mockResolvedValue({ status: "error", items: [] })

    const html = await renderPage({})

    expect(html).toContain("Rol kataloğu şu anda okunamadı")
    expect(html).not.toContain('name="role-target"')
  })

  it("arama sonucu hatası ayrı bildirilir ama panel mevcut yönetici hedefiyle yine render edilir", async () => {
    rosterMock.mockResolvedValue({
      status: "ok",
      items: [
        { userId: TARGET_ID, roleCode: "content_admin", roleName: "İçerik Yöneticisi" },
      ],
    })
    listUsersMock.mockResolvedValue({
      status: "error",
      items: [],
      total: 0,
      page: 1,
      totalPages: 1,
    })

    const html = await renderPage({ q: "ali" })

    expect(html).toContain("Hedef kullanıcı araması şu anda yapılamadı")
    // Panel, kataloğu kullanılamayan aramaya rağmen mevcut yöneticiyi hedef olarak sunar.
    expect(html).toContain('name="role-target"')
    expect(html).toContain(`value="${TARGET_ID}"`)
  })

  it("arama sonucu sayfa özetini gösterir", async () => {
    listUsersMock.mockResolvedValue({
      status: "ok",
      items: [
        {
          id: STUDENT_ID,
          nickname: "Yeni Öğrenci",
          grade_level: 5,
          created_at: "2026-01-01",
          is_visible: null,
          total_points: null,
          monthly_points: null,
          avatar_key: null,
        },
      ],
      total: 1,
      page: 1,
      totalPages: 1,
    })
    labelsMock.mockResolvedValue({
      status: "ok",
      labels: { [STUDENT_ID]: "Yeni Öğrenci" },
    })

    const html = await renderPage({ q: "Yeni" })

    expect(html).toContain("1 öğrenci eşleşti")
    expect(html).toContain(`value="${STUDENT_ID}"`)
    expect(html).toContain("Yeni Öğrenci")
  })

  it("arama eşleşmesi yoksa boş bilgisi görünür", async () => {
    const html = await renderPage({ q: "hiçkimse" })

    expect(html).toContain("Bu aramayla eşleşen öğrenci bulunamadı")
  })
})