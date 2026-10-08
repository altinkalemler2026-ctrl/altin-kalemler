/**
 * Faz UI-P4C — rol yönetimi okuma katmanı testleri.
 *
 * Saf türetmeler (uuid/rol ayrıştırma, katalog, hedef seçenekleri, self
 * çıkarımı) doğrudan test edilir. DB okuyucular `createClient` mock'u ile
 * hem ok hem hata durumları üzerinden doğrulanır; gerçek yazma TEMSİL
 * EDİLMEZ (bu fazda DB'ye hiçbir çağrı yapılmaz).
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({ createClient: createClientMock }))

import {
  SUPER_ADMIN_ROLE_CODE,
  assignableRolesForTarget,
  assignableRolesFromCatalog,
  buildRoleManagementView,
  groupRoleAssignments,
  isRoleMutationOperation,
  listActiveRoles,
  listRoleAssignments,
  parseRoleCode,
  parseRoleUserId,
  resolveUserNicknames,
  revokableRolesForTarget,
  shortUserId,
  validateRoleMutationInput,
  type RoleCatalogEntry,
  type RoleRosterEntry,
} from "./role-management"

const ACTOR_ID = "99999999-8888-4000-8000-000000000901"
const TARGET_ID = "11111111-2222-4333-8444-555555555551"
const SECOND_ADMIN = "22222222-3333-4444-8555-666666666662"
const STUDENT_ID = "33333333-4444-4555-8666-777777777773"

function okClient(options: {
  catalog?: unknown
  roster?: unknown
  profiles?: unknown
}) {
  createClientMock.mockResolvedValue({
    from: vi.fn((source: string) => {
      if (source === "admin_roles") {
        return buildChain(options.catalog ?? { data: [], error: null })
      }
      if (source === "admin_user_roles") {
        return buildChain(options.roster ?? { data: [], error: null })
      }
      if (source === "student_profiles") {
        return buildChain(options.profiles ?? { data: [], error: null })
      }
      throw new Error(`beklenmeyen tablo: ${source}`)
    }),
  })
}

/** `.select` basamakları (eq+order / order / in) için sahte zincir kurar. */
function buildChain(result: unknown) {
  return {
    select: vi.fn(() => ({
      eq: vi.fn(() => ({
        order: vi.fn(async () => result),
      })),
      order: vi.fn(async () => result),
      in: vi.fn(async () => result),
    })),
  }
}

function okRoster(rows: RoleRosterEntry[]): unknown {
  return {
    data: rows.map((row) => ({
      user_id: row.userId,
      admin_roles: { role_code: row.roleCode, name: row.roleName },
    })),
    error: null,
  }
}

beforeEach(() => {
  createClientMock.mockReset()
})

describe("girdi ayrıştırma", () => {
  it("parseRoleUserId geçerli UUID'yi küçük harfe normalleştirir", () => {
    expect(parseRoleUserId("11111111-2222-4333-8444-555555555551")).toBe(
      "11111111-2222-4333-8444-555555555551",
    )
    expect(parseRoleUserId("...")).toBeNull()
    expect(parseRoleUserId("AAAA1111-BBBB-4CCC-8DDD-EEEE1111EEEE")).toBe(
      "aaaa1111-bbbb-4ccc-8ddd-eeee1111eeee",
    )
  })

  it("parseRoleUserId geçersiz değerleri reddeder", () => {
    expect(parseRoleUserId("")).toBeNull()
    expect(parseRoleUserId("bozuk")).toBeNull()
    expect(parseRoleUserId("11111111-2222-4333-8444")).toBeNull()
  })

  it("parseRoleCode normalleştirilmiş rol kodunu üretir", () => {
    expect(parseRoleCode("question_reviewer")).toBe("question_reviewer")
    expect(parseRoleCode("  curriculum_editor ")).toBe("curriculum_editor")
  })

  it("parseRoleCode geçersiz kodları reddeder (büyük harf, boşluk, işaret)", () => {
    expect(parseRoleCode("")).toBeNull()
    expect(parseRoleCode("SüperAdmin")).toBeNull()
    expect(parseRoleCode("rol*")).toBeNull()
    expect(parseRoleCode("a".repeat(64))).toBeNull()
  })

  it("isRoleMutationOperation yalnız iki değeri kabul eder", () => {
    expect(isRoleMutationOperation("assign")).toBe(true)
    expect(isRoleMutationOperation("revoke")).toBe(true)
    expect(isRoleMutationOperation("sil")).toBe(false)
    expect(isRoleMutationOperation(null)).toBe(false)
  })

  it("validateRoleMutationInput tam geçerli girdiyi ayrıştırır", () => {
    const result = validateRoleMutationInput({
      operation: "assign",
      targetUserId: ` ${TARGET_ID} `,
      roleCode: " question_reviewer ",
    })
    expect(result.ok).toBe(true)
    if (result.ok) {
      expect(result.value).toEqual({
        operation: "assign",
        targetUserId: TARGET_ID,
        roleCode: "question_reviewer",
      })
    }
  })

  it("validateRoleMutationInput geçersiz alanları ayrı ayrı reddeder", () => {
    expect(
      validateRoleMutationInput({
        operation: "promote",
        targetUserId: TARGET_ID,
        roleCode: "x",
      }).ok,
    ).toBe(false)
    expect(
      validateRoleMutationInput({
        operation: "assign",
        targetUserId: "",
        roleCode: "x",
      }),
    ).toEqual({ ok: false, error: "invalidTarget" })
    expect(
      validateRoleMutationInput({
        operation: "revoke",
        targetUserId: TARGET_ID,
        roleCode: "",
      }),
    ).toEqual({ ok: false, error: "invalidRole" })
  })
})

const CATALOG: RoleCatalogEntry[] = [
  { roleCode: "content_admin", name: "İçerik Yöneticisi", description: null },
  { roleCode: "copyright_reviewer", name: "Telif İnceleyici", description: null },
  { roleCode: "curriculum_editor", name: "Müfredat Editörü", description: null },
  { roleCode: "question_reviewer", name: "Soru İnceleyici", description: null },
  { roleCode: SUPER_ADMIN_ROLE_CODE, name: "Süper Yönetici", description: null },
]

describe("rol kataloğu türetmeleri", () => {
  it("assignableRolesFromCatalog super_admin'i her zaman çıkarır", () => {
    const assignable = assignableRolesFromCatalog(CATALOG).map(
      (entry) => entry.roleCode,
    )
    expect(assignable).toEqual([
      "content_admin",
      "copyright_reviewer",
      "curriculum_editor",
      "question_reviewer",
    ])
    expect(assignable).not.toContain(SUPER_ADMIN_ROLE_CODE)
  })

  it("assignableRolesForTarget atanmış rolleri de çıkarır", () => {
    const roles = assignableRolesForTarget(CATALOG, [
      "question_reviewer",
      "missing_role",
    ]).map((entry) => entry.roleCode)
    expect(roles).toEqual([
      "content_admin",
      "copyright_reviewer",
      "curriculum_editor",
    ])
  })

  it("revokableRolesForTarget yalnız atanmış ve aktif rolleri döndürür", () => {
    const roles = revokableRolesForTarget(CATALOG, [
      "question_reviewer",
      "super_admin",
      "gone_role",
    ]).map((entry) => entry.roleCode)
    // super_admin kategorik hariçtir; gone_role katalogda yoktur.
    expect(roles).toEqual(["question_reviewer"])
  })
})

describe("groupRoleAssignments ve shortUserId", () => {
  it("kullanıcı başına eşsiz rolleri kod sırasına göre gruplar", () => {
    const groups = groupRoleAssignments([
      { userId: TARGET_ID, roleCode: "question_reviewer", roleName: "Soru İnceleyici" },
      { userId: TARGET_ID, roleCode: "content_admin", roleName: "İçerik Yöneticisi" },
      { userId: TARGET_ID, roleCode: "question_reviewer", roleName: "Soru İnceleyici" },
    ])
    expect(groups).toEqual([
      {
        userId: TARGET_ID,
        roles: [
          { roleCode: "content_admin", roleName: "İçerik Yöneticisi" },
          { roleCode: "question_reviewer", roleName: "Soru İnceleyici" },
        ],
      },
    ])
  })

  it("shortUserId tam UUID kısaltır, kısa girdiyi aynen bırakır", () => {
    expect(shortUserId(TARGET_ID)).toBe("11111111")
    expect(shortUserId("abc")).toBe("abc")
  })
})

describe("buildRoleManagementView — hedef listesi ve self çıkarımı", () => {
  it("actor'yü hedef listesinden her zaman çıkarır", () => {
    const view = buildRoleManagementView({
      roster: [
        { userId: ACTOR_ID, roleCode: "question_reviewer", roleName: "Soru İnceleyici" },
        { userId: TARGET_ID, roleCode: "content_admin", roleName: "İçerik Yöneticisi" },
      ],
      searchResults: [{ id: ACTOR_ID, nickname: "kendim" }],
      labels: { [ACTOR_ID]: "kendim", [TARGET_ID]: "hedef" },
      actorUserId: ACTOR_ID,
    })
    const ids = view.targetOptions.map((option) => option.userId)
    expect(ids).not.toContain(ACTOR_ID)
    expect(ids).toContain(TARGET_ID)
  })

  it("kendi satırında Siz rozeti işaretlenir", () => {
    const view = buildRoleManagementView({
      roster: [{ userId: ACTOR_ID, roleCode: "question_reviewer", roleName: "Soru İnceleyici" }],
      searchResults: [],
      labels: {},
      actorUserId: ACTOR_ID,
    })
    expect(view.admins[0].isSelf).toBe(true)
    expect(view.admins[0].label).toBe(shortUserId(ACTOR_ID))
  })

  it("roster + arama sonuçlarını ayrıştırıp etiket önceliğini uygular", () => {
    const view = buildRoleManagementView({
      roster: [{ userId: TARGET_ID, roleCode: "content_admin", roleName: "İçerik Yöneticisi" }],
      searchResults: [{ id: TARGET_ID, nickname: "İkincil_takmaad" }, { id: STUDENT_ID, nickname: "Yeni" }],
      labels: { [TARGET_ID]: "Birincil" },
      actorUserId: ACTOR_ID,
    })
    const byUser = new Map(view.targetOptions.map((o) => [o.userId, o]))
    expect(byUser.get(TARGET_ID)?.label).toBe("Birincil")
    expect(byUser.get(TARGET_ID)?.isRosterAdmin).toBe(true)
    expect(byUser.get(TARGET_ID)?.assignedRoleCodes).toEqual(["content_admin"])
    expect(byUser.get(STUDENT_ID)?.label).toBe("Yeni")
    expect(byUser.get(STUDENT_ID)?.isRosterAdmin).toBe(false)
    expect(byUser.get(STUDENT_ID)?.assignedRoleCodes).toEqual([])
  })
})

const ADMIN_ROLES_DATA = [
  { role_code: "content_admin", name: "İçerik Yöneticisi", description: null, is_active: true },
  { role_code: "question_reviewer", name: "Soru İnceleyici", description: null, is_active: true },
  { role_code: SUPER_ADMIN_ROLE_CODE, name: "Süper Yönetici", description: null, is_active: true },
]

describe("listActiveRoles — okuyucu", () => {
  it("yalnız aktif roller döner (status ok)", async () => {
    okClient({ catalog: { data: ADMIN_ROLES_DATA, error: null } })
    const result = await listActiveRoles()
    expect(result.status).toBe("ok")
    expect(result.items.map((entry) => entry.roleCode)).toEqual([
      "content_admin",
      "question_reviewer",
      SUPER_ADMIN_ROLE_CODE,
    ])
  })

  it("hata durumunu ayrı `status` ile bildirir", async () => {
    okClient({ catalog: { data: null, error: { message: "denied" } } })
    const result = await listActiveRoles()
    expect(result.status).toBe("error")
    expect(result.items).toEqual([])
  })
})

describe("listRoleAssignments — okuyucu", () => {
  it("join künyesiyle roster döndürür", async () => {
    okClient({
      roster: okRoster([
        { userId: TARGET_ID, roleCode: "content_admin", roleName: "İçerik Yöneticisi" },
        { userId: TARGET_ID, roleCode: "super_admin", roleName: "Süper Yönetici" },
      ]),
    })
    const result = await listRoleAssignments()
    expect(result.status).toBe("ok")
    expect(result.items).toEqual([
      { userId: TARGET_ID, roleCode: "content_admin", roleName: "İçerik Yöneticisi" },
      { userId: TARGET_ID, roleCode: "super_admin", roleName: "Süper Yönetici" },
    ])
  })

  it("dizi gövdesindeki embed'e karşı savunmacıdır", async () => {
    createClientMock.mockResolvedValue({
      from: vi.fn(() => ({
        select: vi.fn(() => ({
          order: vi.fn(async () => ({
            data: [
              {
                user_id: TARGET_ID,
                admin_roles: [
                  { role_code: "question_reviewer", name: "Soru İnceleyici" },
                ],
              },
            ],
            error: null,
          })),
        })),
      })),
    })
    const result = await listRoleAssignments()
    expect(result.status).toBe("ok")
    expect(result.items[0].roleCode).toBe("question_reviewer")
  })

  it("embed boşsa veya eksikse o satırı yok sayar", async () => {
    okClient({
      roster: {
        data: [{ user_id: TARGET_ID, admin_roles: null }],
        error: null,
      },
    })
    const result = await listRoleAssignments()
    expect(result.status).toBe("ok")
    expect(result.items).toEqual([])
  })

  it("hata durumunu ayrı `status` ile bildirir", async () => {
    okClient({ roster: { data: null, error: { message: "denied" } } })
    const result = await listRoleAssignments()
    expect(result.status).toBe("error")
    expect(result.items).toEqual([])
  })
})

describe("resolveUserNicknames — okuyucu", () => {
  it("yalnız dolu takma adları eşler", async () => {
    okClient({
      profiles: {
        data: [
          { id: TARGET_ID, nickname: "Hedef" },
          { id: STUDENT_ID, nickname: "   " },
          { id: SECOND_ADMIN, nickname: "" },
        ],
        error: null,
      },
    })
    const result = await resolveUserNicknames([TARGET_ID, STUDENT_ID, SECOND_ADMIN])
    expect(result.status).toBe("ok")
    expect(result.labels).toEqual({ [TARGET_ID]: "Hedef" })
  })

  it("boş liste için ok döner ve DB'ye gitmez", async () => {
    const result = await resolveUserNicknames([])
    expect(result.status).toBe("ok")
    expect(result.labels).toEqual({})
    expect(createClientMock).not.toHaveBeenCalled()
  })

  it("hata durumunu ayrı `status` ile bildirir", async () => {
    okClient({ profiles: { data: null, error: { message: "denied" } } })
    const result = await resolveUserNicknames([TARGET_ID])
    expect(result.status).toBe("error")
    expect(result.labels).toEqual({})
  })
})