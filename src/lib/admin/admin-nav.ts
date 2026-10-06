/**
 * Admin menü (kabuk) izin sözleşmesi — ortak kaynak.
 *
 * Dashboard ve (admin) layout'u bu tabloyu kullanarak menü öğelerini
 * fail-closed biçimde izinle eşler. Sayfa düzeyindeki mevcut sunucu
 * korumaları değişmez; bu modül yalnız görünür navigasyonun yol
 * haritasıdır ve hiçbir veri okuma/yazma yapmaz.
 */

export type AdminNavPermissionRequirement = {
  mode: "all" | "any"
  codes: readonly string[]
}

export const ADMIN_NAV_PERMISSION_REQUIREMENTS: Readonly<
  Record<string, AdminNavPermissionRequirement>
> = {
  "/admin/questions": { mode: "all", codes: ["questions.view"] },
  "/admin/candidate-batches": {
    mode: "any",
    codes: ["ai.manage", "questions.approve"],
  },
  "/admin/academic-calendar": {
    mode: "all",
    codes: ["calendar.manage"],
  },
  "/admin/users": { mode: "all", codes: ["users.manage"] },
  "/admin/teacher-reviews": { mode: "all", codes: ["questions.view"] },
  "/admin/curriculum-teaching": {
    mode: "all",
    codes: ["curriculum.manage"],
  },
  "/admin/audit": { mode: "all", codes: ["audit.view"] },
}

export function canAccessAdminNavItem(
  href: string,
  permissions: Readonly<Record<string, boolean>>,
): boolean {
  const requirement = ADMIN_NAV_PERMISSION_REQUIREMENTS[href]
  if (!requirement || requirement.codes.length === 0) {
    return false
  }

  return requirement.mode === "all"
    ? requirement.codes.every((code) => permissions[code] === true)
    : requirement.codes.some((code) => permissions[code] === true)
}

/** Menü eşlemesinde geçen tüm izin kodlarının tekilleştirilmiş listesi. */
export function collectAdminNavPermissionCodes(): readonly string[] {
  const codes = new Set<string>()
  for (const requirement of Object.values(
    ADMIN_NAV_PERMISSION_REQUIREMENTS,
  )) {
    for (const code of requirement.codes) {
      codes.add(code)
    }
  }
  return Array.from(codes).sort()
}