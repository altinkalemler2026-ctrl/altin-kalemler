"use server"

/**
 * Faz UI-P4C — süper admin rol atama/kaldırma sunucu aksiyonu.
 *
 * GÜVENLİK (katmanlı, fail-closed):
 *  1. Oturum yoksa `/login`'e yönlendirilir.
 *  2. `users.manage` izni sunucuda yeniden doğrulanır; tek başına yeterli
 *     DEĞİLDİR, yalnız sayfa erişim katmanıdır.
 *  3. `is_current_user_super_admin` yeniden doğrulanır; RPC hatası
 *     "süper yönetici değil" olarak işlenir (kapalı güvenlik).
 *  4. Kendi üzerinde işlem (self-target) RPC öncesi reddedilir; DB E3
 *     son otorite olarak aynı reddi uygular.
 *  5. `super_admin` rol kodu ön taramada ve katalog taramasında kategorik
 *     reddedilir (atama + kaldırma); DB E6/E7 son otoritedir.
 *  6. Tek yazma noktası `assign_admin_role` / `revoke_admin_role` RPC'sidir
 *     (migration 131). Başka hiçbir satır yazılmaz.
 *  7. RPC yanıtının durumu allowlist'li değilse hiçbir başarı iddiası
 *     gösterilmez (`generic`, fail-closed).
 *
 * YAZMA KAPSAMI:
 *  - `revalidatePath` yalnız admin rotalarına uygulanır; öğrenci rotaları
 *    geçersiz kılınmaz.
 *  - Flash yalnız `assigned`/`revoked` durumlarında `audit=1` ve hedef
 *    kimliğiyle döner; `already_*` için denetim kaydı oluşmadığından hiçbir
 *    denetim bağlantısı üretilmez.
 */

import { revalidatePath } from "next/cache"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  hasUsersManagePermission,
  isCurrentUserSuperAdmin,
  listActiveRoles,
  SUPER_ADMIN_ROLE_CODE,
  validateRoleMutationInput,
} from "@/lib/admin/role-management"
import {
  mapRoleMutationError,
  mapRoleMutationInputError,
  isRoleMutationOutcomeStatus,
  outcomeHasAudit,
  roleOutcomeMessage,
  ROLE_MUTATION_ERROR_MESSAGES,
  statusMatchesOperation,
} from "@/lib/admin/role-management-errors"

const ROLES_PATH = "/admin/roles"

type RoleMutationRpc = (
  functionName: "assign_admin_role" | "revoke_admin_role",
  args: { p_role_code: string; p_target_user_id: string },
) => Promise<{
  data: Record<string, unknown> | null
  error: { message: string } | null
}>

function readField(formData: FormData, key: string): string {
  const value = formData.get(key)
  return typeof value === "string" ? value : ""
}

function flash(
  path: string,
  kind: "ok" | "error",
  message: string,
  extra?: { target?: string; audit?: boolean },
): never {
  const params = new URLSearchParams()
  params.set(kind, message)
  if (extra?.target) {
    params.set("target", extra.target)
  }
  if (extra?.audit) {
    params.set("audit", "1")
  }
  redirect(`${path}?${params.toString()}`)
}

/**
 * Rol atama/kaldırma işlemini sunucuda doğrular ve uygular.
 * Ne `targetUserId` ne de `roleCode` istemciden güvenilir; ikisi de
 * allowlist'li biçime indirgenir ve katalog yeniden türetilir.
 */
export async function submitRoleMutationAction(formData: FormData): Promise<void> {
  const validated = validateRoleMutationInput({
    operation: readField(formData, "operation").trim(),
    targetUserId: readField(formData, "targetUserId").trim(),
    roleCode: readField(formData, "roleCode").trim(),
  })
  if (!validated.ok) {
    flash(ROLES_PATH, "error", mapRoleMutationInputError(validated.error))
  }
  // Allowlist'li, normalleştirilmiş değerler. Ham form değerlerine asla
  // tekrar bakılmaz; sonraki her denetim yalnız bu küme üzerindedir.
  const { operation, targetUserId, roleCode } = validated.value

  // 1) Oturum.
  const supabase = await createClient()
  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    redirect("/login")
  }
  const actorUserId = userData.user.id

  // 2) Sayfa katmanı yetkisi (yalnız erişim; mutasyon için yeterli değil).
  if (!(await hasUsersManagePermission())) {
    flash(ROLES_PATH, "error", ROLE_MUTATION_ERROR_MESSAGES.forbidden)
  }

  // 3) Süper yönetici yeniden doğrulaması — hata fail-closed "yetki yok".
  const superAdmin = await isCurrentUserSuperAdmin()
  if (superAdmin.status !== "ok" || !superAdmin.isSuperAdmin) {
    flash(ROLES_PATH, "error", ROLE_MUTATION_ERROR_MESSAGES.notSuperAdmin)
  }

  // 4) Self-target: hiçbir rol senaryosunda kendi üzerinde işlem yok.
  if (targetUserId === actorUserId) {
    flash(ROLES_PATH, "error", ROLE_MUTATION_ERROR_MESSAGES.selfTarget)
  }

  // 5) super_admin rol kodu kategorik ret (atama + kaldırma).
  if (roleCode === SUPER_ADMIN_ROLE_CODE) {
    flash(ROLES_PATH, "error", ROLE_MUTATION_ERROR_MESSAGES.superAdminRole)
  }

  // 6) Aktif katalog yeniden türetilir; istemci seçeneklerine güvenilmez.
  const catalog = await listActiveRoles()
  if (catalog.status !== "ok") {
    flash(ROLES_PATH, "error", ROLE_MUTATION_ERROR_MESSAGES.generic)
  }
  if (!catalog.items.some((entry) => entry.roleCode === roleCode)) {
    flash(ROLES_PATH, "error", ROLE_MUTATION_ERROR_MESSAGES.invalidRole)
  }

  // 7) Tek yazma noktası. Başka hiçbir satır DB'ye yazılmaz.
  const rpc = supabase.rpc.bind(supabase) as unknown as RoleMutationRpc
  const functionName =
    operation === "assign"
      ? "assign_admin_role"
      : "revoke_admin_role"
  const { data, error } = await rpc(functionName, {
    p_target_user_id: targetUserId,
    p_role_code: roleCode,
  })

  if (error) {
    flash(ROLES_PATH, "error", mapRoleMutationError(error))
  }

  const status = data?.status
  if (
    !isRoleMutationOutcomeStatus(status) ||
    !statusMatchesOperation(operation, status)
  ) {
    // Beklenmeyen yanıt: fail-closed, hiçbir başarı iddiası yok.
    flash(ROLES_PATH, "error", ROLE_MUTATION_ERROR_MESSAGES.generic)
  }

  // Yalnız admin rotaları; öğrenci rotaları kasıtlı olarak geçersiz kılınmaz.
  revalidatePath(ROLES_PATH)
  revalidatePath("/admin/audit")

  // `audit` yalnız gerçek yazmada taşınır; `already_*` hiçbir denetim
  // kaydı oluşturmadığından hedef kimliği de gönderilmez.
  const hasAudit = outcomeHasAudit(status)
  flash(ROLES_PATH, "ok", roleOutcomeMessage(status), {
    target: hasAudit ? targetUserId : undefined,
    audit: hasAudit,
  })
}