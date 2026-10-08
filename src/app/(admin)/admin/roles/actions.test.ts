// @vitest-environment node
/**
 * Faz UI-P4C — süper admin rol atama/kaldırma sunucu aksiyonu testleri.
 *
 * Kanıtlanan güvenlik sözleşmeleri:
 * - Oturum yoksa /login'e yönlendirilir; hiçbir RPC çağrılmaz.
 * - `users.manage` yoksa ve is_current_user_super_admin fail-closed ise
 *   mutasyon RPC'si HİÇ çağrılmaz.
 * - Kendi üzerinde işlem ve super_admin rol kodu RPC ÖNCESİ reddedilir.
 * - Rol kataloğu SUNUCUDA yeniden türetilir; istemci değerlerine güvenilmez.
 * - Tek yazma noktası assign_admin_role / revoke_admin_role'dur; argümanlar
 *   migration 131 imzasına birebir uyar; revalidatePath yalnız admin rotaları.
 * - RPC hataları Türkçeye eşlenir; ham DB mesajı URL'e taşınmaz; eşleşmeyen
 *   hata generic (fail-closed).
 * - `already_*` durumları başarı gösterilir ama denetim bağlantısı (`audit=1`,
 *   `target`) taşımaz; beklenen işlemle uyuşmayan durum başarı iddiası sayılmaz.
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const getUserMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())
const revalidateMock = vi.hoisted(() => vi.fn())
const redirectMock = vi.hoisted(() =>
  vi.fn((url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`)
  }),
)
const hasPermissionMock = vi.hoisted(() => vi.fn())
const superAdminMock = vi.hoisted(() => vi.fn())
const listRolesMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({ createClient: createClientMock }))
vi.mock("next/navigation", () => ({ redirect: redirectMock }))
vi.mock("next/cache", () => ({ revalidatePath: revalidateMock }))
vi.mock("@/lib/admin/role-management", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/admin/role-management")>()
  return {
    ...actual,
    hasUsersManagePermission: hasPermissionMock,
    isCurrentUserSuperAdmin: superAdminMock,
    listActiveRoles: listRolesMock,
  }
})

import { submitRoleMutationAction } from "./actions"

const ACTOR_ID = "99999999-8888-4000-8000-000000000901"
const TARGET_ID = "11111111-2222-4333-8444-555555555551"

// `listActiveRoles` sözleşmesi (RoleCatalogEntry[]): camelCase künye.
const ACTIVE_ROLES = [
  { roleCode: "content_admin", name: "İçerik Yöneticisi", description: null },
  { roleCode: "question_reviewer", name: "Soru İnceleyici", description: null },
]

function fromChain(result: unknown) {
  return {
    from: vi.fn(() => ({
      select: vi.fn(() => ({
        eq: vi.fn(() => ({
          order: vi.fn(async () => result),
        })),
      })),
    })),
  }
}

function formData(fields: Record<string, string>): FormData {
  const data = new FormData()
  for (const [key, value] of Object.entries(fields)) data.set(key, value)
  return data
}

function validForm(overrides: Record<string, string> = {}): FormData {
  return formData({
    operation: "assign",
    targetUserId: TARGET_ID,
    roleCode: "question_reviewer",
    ...overrides,
  })
}

function flashUrl(): string {
  const call = redirectMock.mock.calls.at(-1)
  expect(call).toBeDefined()
  return String(call![0])
}

function flashMessage(kind: "ok" | "error"): string {
  const url = new URL(flashUrl(), "http://localhost")
  return url.searchParams.get(kind) ?? ""
}

function flashParam(name: string): string {
  const url = new URL(flashUrl(), "http://localhost")
  return url.searchParams.get(name) ?? ""
}

beforeEach(() => {
  getUserMock.mockReset()
  rpcMock.mockReset()
  createClientMock.mockReset()
  redirectMock.mockClear()
  revalidateMock.mockReset()
  hasPermissionMock.mockReset()
  superAdminMock.mockReset()
  listRolesMock.mockReset()

  getUserMock.mockResolvedValue({ data: { user: { id: ACTOR_ID } } })
  hasPermissionMock.mockResolvedValue(true)
  superAdminMock.mockResolvedValue({ status: "ok", isSuperAdmin: true })
  listRolesMock.mockResolvedValue({ status: "ok", items: ACTIVE_ROLES })

  const chain = fromChain({ data: ACTIVE_ROLES, error: null })
  createClientMock.mockImplementation(async () => ({
    auth: { getUser: getUserMock },
    rpc: rpcMock,
    ...chain,
  }))

  rpcMock.mockImplementation(
    (functionName: string, args: Record<string, unknown>) => {
      if (functionName === "assign_admin_role" || functionName === "revoke_admin_role") {
        return Promise.resolve({
          data: {
            status: functionName === "assign_admin_role" ? "assigned" : "revoked",
            target_user_id: TARGET_ID,
            role_code: args.p_role_code,
            audit_id: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
          },
          error: null,
        })
      }
      return Promise.resolve({ data: null, error: { message: "unexpected rpc" } })
    },
  )
})

async function catchRedirect(call: () => Promise<void>): Promise<void> {
  await call().catch((error: unknown) => {
    if (!(error instanceof Error)) throw error
    expect(error.message).toContain("NEXT_REDIRECT")
  })
}

describe("submitRoleMutationAction — oturum ve yetki kapıları", () => {
  it("oturum yoksa /login'e yönlendirir, RPC ve katalog çağrılmaz", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } })

    await catchRedirect(() => submitRoleMutationAction(validForm()))

    expect(flashUrl()).toBe("/login")
    expect(rpcMock).not.toHaveBeenCalled()
    expect(listRolesMock).not.toHaveBeenCalled()
  })

  it("users.manage yoksa reddeder; mutasyon RPC'si hiç çağrılmaz", async () => {
    hasPermissionMock.mockResolvedValue(false)

    await catchRedirect(() => submitRoleMutationAction(validForm()))

    expect(flashMessage("error")).toMatch(/yetkiniz yok/)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("is_current_user_super_admin hatası fail-closed: RPC çağrılmaz", async () => {
    superAdminMock.mockResolvedValue({ status: "error", isSuperAdmin: false })

    await catchRedirect(() => submitRoleMutationAction(validForm()))

    expect(flashMessage("error")).toMatch(/yalnız süper yönetici/)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("süper yönetici değilse reddeder; RPC çağrılmaz", async () => {
    superAdminMock.mockResolvedValue({ status: "ok", isSuperAdmin: false })

    await catchRedirect(() => submitRoleMutationAction(validForm()))

    expect(flashMessage("error")).toMatch(/yalnız süper yönetici/)
    expect(rpcMock).not.toHaveBeenCalled()
  })
})

describe("submitRoleMutationAction — RPC öncesi korumalar", () => {
  it("self-target RPC öncesi reddedilir", async () => {
    await catchRedirect(() =>
      submitRoleMutationAction(validForm({ targetUserId: ACTOR_ID })),
    )

    expect(flashMessage("error")).toMatch(/Kendi admin rollerinizi/)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("super_admin rol kodu kategorik reddedilir (atamada)", async () => {
    await catchRedirect(() =>
      submitRoleMutationAction(validForm({ roleCode: "super_admin" })),
    )

    expect(flashMessage("error")).toMatch(/Süper yönetici rolü bu ekrandan/)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("katalog okunamadıysa generic red (fail-closed)", async () => {
    listRolesMock.mockResolvedValue({ status: "error", items: [] })

    await catchRedirect(() => submitRoleMutationAction(validForm()))

    expect(flashMessage("error")).toMatch(/Rol işlemi tamamlanamadı/)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("katalogda aktif olmayan rol kodu reddedilir", async () => {
    listRolesMock.mockResolvedValue({
      status: "ok",
      items: ACTIVE_ROLES.filter((role) => role.roleCode === "content_admin"),
    })

    await catchRedirect(() =>
      submitRoleMutationAction(validForm({ roleCode: "question_reviewer" })),
    )

    expect(flashMessage("error")).toMatch(/aktif değil/)
    expect(rpcMock).not.toHaveBeenCalled()
  })

  it("geçersiz girdi (işlem dışı değer) katalogdan önce reddedilir", async () => {
    await catchRedirect(() =>
      submitRoleMutationAction(validForm({ operation: "sil" })),
    )

    expect(flashMessage("error")).toMatch(/Geçersiz bir işlem/)
    expect(listRolesMock).not.toHaveBeenCalled()
    expect(rpcMock).not.toHaveBeenCalled()
  })
})

describe("submitRoleMutationAction — başarılı yazma", () => {
  it("assign: doğru RPC imzasını çağırır ve audit bağlantısı üretir", async () => {
    await catchRedirect(() => submitRoleMutationAction(validForm()))

    expect(rpcMock).toHaveBeenCalledWith("assign_admin_role", {
      p_target_user_id: TARGET_ID,
      p_role_code: "question_reviewer",
    })
    expect(flashMessage("ok")).toMatch(/Rol atandı/)
    expect(flashParam("audit")).toBe("1")
    expect(flashParam("target")).toBe(TARGET_ID)
    expect(revalidateMock).toHaveBeenCalledWith("/admin/roles")
    expect(revalidateMock).toHaveBeenCalledWith("/admin/audit")
  })

  it("revoke: revoke_admin_role RPC'sini çağırır", async () => {
    await catchRedirect(() =>
      submitRoleMutationAction(validForm({ operation: "revoke" })),
    )

    expect(rpcMock).toHaveBeenCalledWith("revoke_admin_role", {
      p_target_user_id: TARGET_ID,
      p_role_code: "question_reviewer",
    })
    expect(flashMessage("ok")).toMatch(/Rol kaldırıldı/)
    expect(flashParam("audit")).toBe("1")
  })

  it("already_assigned: başarı ama denetim bağlantısı ve hedef parametresi yok", async () => {
    rpcMock.mockImplementation((functionName: string) =>
      Promise.resolve({
        data: {
          status:
            functionName === "assign_admin_role"
              ? "already_assigned"
              : "revoked",
          target_user_id: TARGET_ID,
          role_code: "question_reviewer",
          audit_id: null,
        },
        error: null,
      }),
    )

    await catchRedirect(() => submitRoleMutationAction(validForm()))

    expect(flashMessage("ok")).toMatch(/zaten atanmış/)
    expect(flashMessage("ok")).toMatch(/denetim kaydı yazılmadı/)
    expect(flashParam("audit")).toBe("")
    expect(flashParam("target")).toBe("")
  })

  it("beklenmeyen status değeri başarı olarak sunulmaz (fail-closed)", async () => {
    rpcMock.mockResolvedValue({
      data: { status: "promoted", target_user_id: TARGET_ID, audit_id: "x" },
      error: null,
    })

    await catchRedirect(() => submitRoleMutationAction(validForm()))

    expect(flashMessage("ok")).toBe("")
    expect(flashMessage("error")).toMatch(/Rol işlemi tamamlanamadı/)
  })

  it("işlemle uyuşmayan durum (assign için revoked) başarı sayılmaz", async () => {
    rpcMock.mockResolvedValue({
      data: { status: "revoked", target_user_id: TARGET_ID, audit_id: null },
      error: null,
    })

    await catchRedirect(() => submitRoleMutationAction(validForm()))

    expect(flashMessage("ok")).toBe("")
    expect(flashMessage("error")).toMatch(/Rol işlemi tamamlanamadı/)
  })
})

describe("submitRoleMutationAction — RPC hata eşleme (ham metin taşınmaz)", () => {
  it.each([
    ["Human authentication required.", /giriş yapmalısınız/],
    ["Admin role management requires super admin.", /yalnız süper yönetici/],
    ["Target user not found.", /Hedef kullanıcı bulunamadı/],
    ["Admins cannot change their own admin roles.", /Kendi admin rollerinizi/],
    ["Invalid admin role code.", /aktif değil/],
    ["Cannot remove the last super admin.", /Son süper yönetici/],
    [
      "The super admin role cannot be assigned or revoked through the admin role management interface.",
      /Süper yönetici rolü bu ekrandan/,
    ],
  ])("RPC '%s' Türkçe mesaja çevrilir", async (dbMessage, matcher) => {
    rpcMock.mockResolvedValue({
      data: null,
      error: { message: dbMessage },
    })

    await catchRedirect(() => submitRoleMutationAction(validForm()))

    expect(flashMessage("ok")).toBe("")
    expect(flashMessage("error")).toMatch(matcher)
    expect(flashUrl()).not.toContain(dbMessage)
  })

  it("bilinmeyen RPC hatası generic olur", async () => {
    rpcMock.mockResolvedValue({
      data: null,
      error: { message: "unexpected böö" },
    })

    await catchRedirect(() => submitRoleMutationAction(validForm()))

    expect(flashMessage("error")).toMatch(/Rol işlemi tamamlanamadı/)
  })
})