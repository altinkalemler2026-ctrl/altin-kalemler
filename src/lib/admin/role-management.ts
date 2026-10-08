import { createClient } from "@/lib/supabase/server"
import {
  mapRoleCatalogEntry,
  type RoleCatalogResult,
  type RoleRosterEntry,
  type RoleRosterResult,
} from "./role-management-shared"

/**
 * Faz UI-P4C — süper admin rol yönetimi okuma katmanı.
 *
 * Bu modül YALNIZCA salt-okunur veri yoludur. Rol atama/kaldırma yazımı
 * DB'ye yalnız `assign_admin_role` / `revoke_admin_role` RPC'leri tarafından
 * yazılır (migration 131); mutasyon `(admin)/admin/roles/actions.ts` içindedir.
 *
 * Güvenlik kararları (fail-closed):
 * - `super_admin` bu ekrandan asla atanamaz veya kaldırılamaz (kategorik
 *   ret; DB aynı reddi RPC'de uygular). Değişiklik yalnız veritabanı
 *   yöneticisinindir.
 * - Okuma erişimi isteğe bağlı değildir: sayfa yalnız `users.manage` ile
 *   açılır, mutasyon yalnız `is_current_user_super_admin` ile açılır.
 * - `isCurrentUserSuperAdmin` RPC hatası durumunda `status: "error"` ve
 *   `isSuperAdmin: false` döner; arayan bunu "süper yönetici değil" olarak
 *   işler (kapalı güvenlik), asla açık değil.
 *
 * Veri erişimi (RLS):
 * - `admin_roles` katalog okumaları 014 "admins read admin roles" (SELECT)
 *   politikasıyladır; görüntüleyen her zaman `users.manage` izinli olduğu
 *   için okuma hakkı vardır.
 * - `admin_user_roles` roster okuması 014 "admin reads own roles" SELECT
 *   politikasının `current_user_has_admin_permission('users.manage')`
 *   dalıyladır (131 bu politikayı korur).
 * - Öğrenci takma adları `student_profiles` üzerinden yalnız `nickname`
 *   alanıyla ve yalnız mevcut yönetici SELECT politikasının izin verdiği
 *   kümeyle okunur (admin_users.ts ile aynı veri minimizasyonu).
 *
 * Saf katman (tipler, girdi doğrulama, katalog/sunum türetmeleri) istemci
 * bileşenlerinin de kullanabilmesi için `./role-management-shared` içinde
 * tutulur ve buradan yeniden dışa aktarılır — bu modül `next/headers`'a
 * bağlıdır ve yalnız sunucu taraflıdır.
 */

export * from "./role-management-shared"

// ---------------------------------------------------------------------------
// Rol kataloğu
// ---------------------------------------------------------------------------

export async function listActiveRoles(): Promise<RoleCatalogResult> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from("admin_roles")
    .select("role_code, name, description, is_active")
    .eq("is_active", true)
    .order("role_code", { ascending: true })

  if (error) {
    return { status: "error", items: [] }
  }

  const items = (data ?? [])
    .map((row) =>
      mapRoleCatalogEntry(row as Record<string, unknown>),
    )
    .filter((entry) => entry.roleCode.length > 0)

  return { status: "ok", items }
}

// ---------------------------------------------------------------------------
// Roster (admin_user_roles + admin_roles)
// ---------------------------------------------------------------------------

/**
 * Tüm rol atamalarını yönetici künyesiyle (join) okur. Many-to-one embed'in
 * dönebileceği nesne veya dizi gövdesine karşı savunmacıdır.
 */
export async function listRoleAssignments(): Promise<RoleRosterResult> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from("admin_user_roles")
    .select("user_id, admin_roles(role_code, name)")
    .order("user_id", { ascending: true })

  if (error) {
    return { status: "error", items: [] }
  }

  const items: RoleRosterEntry[] = []
  for (const row of data ?? []) {
    const r = row as Record<string, unknown>
    const userId = typeof r.user_id === "string" ? r.user_id : ""
    if (userId.length === 0) continue

    const embedded = r.admin_roles as unknown
    const role = Array.isArray(embedded)
      ? (embedded[0] as Record<string, unknown> | undefined)
      : (embedded as Record<string, unknown> | null | undefined)
    if (!role || typeof role !== "object") continue

    const roleCode = typeof role.role_code === "string" ? role.role_code : ""
    if (roleCode.length === 0) continue

    items.push({
      userId,
      roleCode,
      roleName: typeof role.name === "string" ? role.name : roleCode,
    })
  }

  return { status: "ok", items }
}

// ---------------------------------------------------------------------------
// Öğrenci etiketleri (salt-okunur, veri minimizasyonlu)
// ---------------------------------------------------------------------------

export interface UserLabelResult {
  status: "ok" | "error"
  labels: Record<string, string>
}

/**
 * Kimliklerin takma adlarını `student_profiles.nickname` üzerinden okur.
 * Hata, ayrı bir `status` ile bildirilir; arayan kısa kimlik fallback'ine
 * geçer. İçerik dışı (boş) takma adlar yok sayılır.
 */
export async function resolveUserNicknames(
  userIds: readonly string[],
): Promise<UserLabelResult> {
  const unique = Array.from(new Set(userIds.filter((id) => id.length > 0)))
  if (unique.length === 0) {
    return { status: "ok", labels: {} }
  }

  const supabase = await createClient()
  const { data, error } = await supabase
    .from("student_profiles")
    .select("id, nickname")
    .in("id", unique)

  if (error) {
    return { status: "error", labels: {} }
  }

  const labels: Record<string, string> = {}
  for (const row of data ?? []) {
    const r = row as Record<string, unknown>
    const id = typeof r.id === "string" ? r.id : ""
    const nickname = typeof r.nickname === "string" ? r.nickname.trim() : ""
    if (id.length > 0 && nickname.length > 0) {
      labels[id] = nickname
    }
  }

  return { status: "ok", labels }
}

// ---------------------------------------------------------------------------
// Yetki okuyucuları
// ---------------------------------------------------------------------------

type PermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

export async function hasUsersManagePermission(): Promise<boolean> {
  const supabase = await createClient()
  const rpc = supabase.rpc.bind(supabase) as unknown as PermissionRpc
  const { data, error } = await rpc("teacher_review_admin_has_permission", {
    p_permission_code: "users.manage",
  })
  return !error && data === true
}

export interface SuperAdminResult {
  status: "ok" | "error" | "unauthenticated"
  isSuperAdmin: boolean
}

type IsCurrentUserSuperAdminRpc = (
  functionName: "is_current_user_super_admin",
) => Promise<{ data: boolean | null; error: { message: string } | null }>

/**
 * `is_current_user_super_admin` RPC'sini güvenli biçimde okur.
 * RPC hatası veya oturum yokluğunda `isSuperAdmin: false` döner (fail-closed).
 */
export async function isCurrentUserSuperAdmin(): Promise<SuperAdminResult> {
  const supabase = await createClient()
  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    return { status: "unauthenticated", isSuperAdmin: false }
  }

  const rpc = supabase.rpc.bind(
    supabase,
  ) as unknown as IsCurrentUserSuperAdminRpc
  const { data, error } = await rpc("is_current_user_super_admin")
  if (error) {
    return { status: "error", isSuperAdmin: false }
  }

  return { status: "ok", isSuperAdmin: data === true }
}