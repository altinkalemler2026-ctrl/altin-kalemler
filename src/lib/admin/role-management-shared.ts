/**
 * Faz UI-P4C — rol yönetimi SAF katmanı (tipler, girdi ayrıştırma, katalog ve
 * sunum türetmeleri).
 *
 * Bu modül hiçbir sunucu bağımlılığı (Supabase / `next/headers`) İÇERMEZ ve
 * istemci bileşenleri tarafından güvenle import edilebilir. Veritabanı
 * okuyucuları ve yetki RPC'leri `./role-management` içinde tutulur; bu modül
 * oradan yeniden dışa aktarılır.
 */
export const SUPER_ADMIN_ROLE_CODE = "super_admin"

// ---------------------------------------------------------------------------
// Girdi ayrıştırma (saf)
// ---------------------------------------------------------------------------

export type RoleMutationOperation = "assign" | "revoke"

export function isRoleMutationOperation(value: unknown): value is RoleMutationOperation {
  return value === "assign" || value === "revoke"
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** Form değerinden normalleştirilmiş geçerli UUID üretir; geçersizde `null`. */
export function parseRoleUserId(value: string): string | null {
  const trimmed = value.trim()
  return UUID_PATTERN.test(trimmed) ? trimmed.toLowerCase() : null
}

const ROLE_CODE_PATTERN = /^[a-z][a-z0-9_]{0,62}$/

/** Form değerinden normalleştirilmiş rol kodu üretir; geçersizde `null`. */
export function parseRoleCode(value: string): string | null {
  const trimmed = value.trim()
  return ROLE_CODE_PATTERN.test(trimmed) ? trimmed : null
}

export type RoleMutationInputError =
  | "invalidOperation"
  | "invalidTarget"
  | "invalidRole"

export interface ValidRoleMutationInput {
  operation: RoleMutationOperation
  targetUserId: string
  roleCode: string
}

/**
 * Mutasyon girdisinin tamamını doğrular. Form değerleri yalnızca
 * allowlist'li biçimlere indirgenir; ayrıştırılamayan her alan reddedilir.
 */
export function validateRoleMutationInput(input: {
  operation: string
  targetUserId: string
  roleCode: string
}): { ok: true; value: ValidRoleMutationInput } | { ok: false; error: RoleMutationInputError } {
  if (!isRoleMutationOperation(input.operation)) {
    return { ok: false, error: "invalidOperation" }
  }
  const targetUserId = parseRoleUserId(input.targetUserId)
  if (targetUserId === null) {
    return { ok: false, error: "invalidTarget" }
  }
  const roleCode = parseRoleCode(input.roleCode)
  if (roleCode === null) {
    return { ok: false, error: "invalidRole" }
  }
  return { ok: true, value: { operation: input.operation, targetUserId, roleCode } }
}

// ---------------------------------------------------------------------------
// Rol kataloğu
// ---------------------------------------------------------------------------

export interface RoleCatalogEntry {
  roleCode: string
  name: string
  description: string | null
}

export interface RoleCatalogResult {
  status: "ok" | "error"
  items: RoleCatalogEntry[]
}

/** Ham active `admin_roles` satırından yalnız izinli alanları okur. */
export function mapRoleCatalogEntry(row: Record<string, unknown>): RoleCatalogEntry {
  return {
    roleCode: typeof row.role_code === "string" ? row.role_code : "",
    name: typeof row.name === "string" ? row.name : "",
    description: typeof row.description === "string" ? row.description : null,
  }
}

/**
 * Mutasyon kataloğu: aktif rollerden `super_admin` çıkarılır. Kategorik
 * ret hem atama hem kaldırmada geçerlidir; bu kulağa ters gelse de amacı
 * korumadır — `super_admin` yalnız doğrudan veritabanı yöneticisi tarafından
 * değiştirilir.
 */
export function assignableRolesFromCatalog(
  entries: readonly RoleCatalogEntry[],
): RoleCatalogEntry[] {
  return entries.filter((entry) => entry.roleCode !== SUPER_ADMIN_ROLE_CODE)
}

/** Hedefe atanabilir roller: `super_admin` hariç, henüz atanmamış olanlar. */
export function assignableRolesForTarget(
  entries: readonly RoleCatalogEntry[],
  assignedRoleCodes: readonly string[],
): RoleCatalogEntry[] {
  const assigned = new Set(assignedRoleCodes)
  return assignableRolesFromCatalog(entries).filter(
    (entry) => !assigned.has(entry.roleCode),
  )
}

/** Hedeften kaldırılabilir roller: `super_admin` hariç, atanmış ve aktif olanlar. */
export function revokableRolesForTarget(
  entries: readonly RoleCatalogEntry[],
  assignedRoleCodes: readonly string[],
): RoleCatalogEntry[] {
  const active = new Set(assignableRolesFromCatalog(entries).map((e) => e.roleCode))
  return assignableRolesFromCatalog(entries).filter(
    (entry) => active.has(entry.roleCode) && assignedRoleCodes.includes(entry.roleCode),
  )
}

// ---------------------------------------------------------------------------
// Roster modeli (admin_user_roles + admin_roles)
// ---------------------------------------------------------------------------

export interface RoleRosterEntry {
  userId: string
  roleCode: string
  roleName: string
}

export interface RoleRosterResult {
  status: "ok" | "error"
  items: RoleRosterEntry[]
}

// ---------------------------------------------------------------------------
// Sunum türetmeleri (saf)
// ---------------------------------------------------------------------------

export interface RoleAssignmentGroup {
  roleCode: string
  roleName: string
}

export interface RosterAdmin {
  userId: string
  label: string
  isSelf: boolean
  roles: RoleAssignmentGroup[]
}

/** Kısa kimlik etiketi: tam UUID'nin ilk 8 karakteri. */
export function shortUserId(userId: string): string {
  return userId.length > 8 ? userId.slice(0, 8) : userId
}

/** Roster satırlarını kullanıcı başına eşsiz rol kümesiyle gruplar. */
export function groupRoleAssignments(
  items: readonly RoleRosterEntry[],
): Array<{ userId: string; roles: RoleAssignmentGroup[] }> {
  const byUser = new Map<string, Map<string, RoleAssignmentGroup>>()
  for (const entry of items) {
    const seen = byUser.get(entry.userId) ?? new Map()
    if (!seen.has(entry.roleCode)) {
      seen.set(entry.roleCode, { roleCode: entry.roleCode, roleName: entry.roleName })
    }
    byUser.set(entry.userId, seen)
  }

  return Array.from(byUser.entries()).map(([userId, roles]) => ({
    userId,
    roles: Array.from(roles.values()).sort((a, b) =>
      a.roleCode.localeCompare(b.roleCode),
    ),
  }))
}

export interface RosterDisplay {
  admins: RosterAdmin[]
  targetOptions: RoleTargetOption[]
}

export interface RoleTargetOption {
  userId: string
  label: string
  isRosterAdmin: boolean
  assignedRoleCodes: string[]
}

/**
 * Roster + arama sonuçlarını birleştirip hedef seçeneklerini üretir.
 * `actorUserId` (oturum sahibi) HER ZAMAN hedef listesinden çıkarılır;
 * kimlikli hedef kendi admin rollerini bu ekrandan değiştiremez.
 * Etiket önceliği: öğrenci takma adı > kısa kimlik.
 */
export function buildRoleManagementView(input: {
  roster: readonly RoleRosterEntry[]
  searchResults: readonly { id: string; nickname: string }[]
  labels: Readonly<Record<string, string>>
  actorUserId: string
}): RosterDisplay {
  const groups = groupRoleAssignments(input.roster)
  const searchByUser = new Map<string, string>()
  for (const hit of input.searchResults) {
    if (hit.nickname.trim().length > 0 && !searchByUser.has(hit.id)) {
      searchByUser.set(hit.id, hit.nickname.trim())
    }
  }

  const rosterAdmins: RosterAdmin[] = groups.map((group) => ({
    userId: group.userId,
    label: input.labels[group.userId] ?? shortUserId(group.userId),
    isSelf: group.userId === input.actorUserId,
    roles: group.roles,
  }))

  const merged = new Map<string, RoleTargetOption>()
  for (const group of groups) {
    if (group.userId === input.actorUserId) continue
    merged.set(group.userId, {
      userId: group.userId,
      label: input.labels[group.userId] ?? shortUserId(group.userId),
      isRosterAdmin: true,
      assignedRoleCodes: group.roles.map((r) => r.roleCode),
    })
  }
  for (const hit of input.searchResults) {
    if (hit.id === input.actorUserId) continue
    const existing = merged.get(hit.id)
    if (existing) {
      existing.label = input.labels[hit.id] ?? searchByUser.get(hit.id) ?? existing.label
      continue
    }
    merged.set(hit.id, {
      userId: hit.id,
      label: input.labels[hit.id] ?? searchByUser.get(hit.id) ?? shortUserId(hit.id),
      isRosterAdmin: false,
      assignedRoleCodes: [],
    })
  }

  return {
    admins: rosterAdmins,
    targetOptions: Array.from(merged.values()),
  }
}