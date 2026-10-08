/**
 * Faz UI-P4C — süper admin rol yönetimi (UI-P4C) hata/mesaj sözleşmesi.
 *
 * `private.assign_admin_role` / `private.revoke_admin_role` (migration 131)
 * İngilizce hata üretir. Burada ham metin üzerinden yalnız güvenli bir sınıf
 * (kind) çıkarılır ve kullanıcı Türkçe metnine çevrilir.
 *
 * Fail-closed kural: eşleşmeyen her hata `generic` döner; ham DB mesajı asla
 * istemciye taşınmaz. Aynı desen `candidate-decisions-errors.ts` iledir.
 *
 * Kaynak satırlar (migration 131):
 *   150 'Human authentication required.'
 *   154 'Admin role management requires super admin.'
 *   158 'Target user not found.'
 *   162 'Admins cannot change their own admin roles.'
 *   177 'Invalid admin role code.'
 *   181 'The super admin role cannot be assigned or revoked through the admin
 *        role management interface.'
 *   315 'Cannot remove the last super admin.'
 *
 * Sonuç durumları (migration 131):
 *   assign  -> assigned | already_assigned  (audit_id dolu / null)
 *   revoke  -> revoked  | already_revoked   (audit_id dolu / null)
 */

import type { RoleMutationInputError, RoleMutationOperation } from "./role-management"

// ---------------------------------------------------------------------------
// Girdi doğrulama mesajları
// ---------------------------------------------------------------------------

export const ROLE_MUTATION_INPUT_MESSAGES = {
  invalidOperation:
    "Geçersiz bir işlem seçildi. Lütfen sayfayı yenileyip tekrar deneyin.",
  invalidTarget:
    "Hedef kullanıcı kimliği eksik veya geçersiz. Lütfen hedefi listeden yeniden seçin.",
  invalidRole:
    "Seçilen rol geçersiz. Lütfen rolü listeden yeniden seçin.",
} as const

export type RoleMutationInputErrorKind = keyof typeof ROLE_MUTATION_INPUT_MESSAGES

/** Girdi doğrulama hatasını Türkçe mesaja çevirir (fail-closed). */
export function mapRoleMutationInputError(
  error: RoleMutationInputError,
): string {
  if (error in ROLE_MUTATION_INPUT_MESSAGES) {
    return ROLE_MUTATION_INPUT_MESSAGES[
      error as RoleMutationInputErrorKind
    ]
  }
  return ROLE_MUTATION_INPUT_MESSAGES.invalidOperation
}

// ---------------------------------------------------------------------------
// RPC hata sınıfları
// ---------------------------------------------------------------------------

export const ROLE_MUTATION_ERROR_MESSAGES = {
  /** auth.uid() yok. */
  authRequired: "Bu işlemi tamamlamak için giriş yapmalısınız.",
  /** Sunucu tarafı `users.manage` yeniden doğrulaması başarısız. */
  forbidden:
    "Bu işlemi yapmaya yetkiniz yok. Lütfen sistem yöneticinizle iletişime geçin.",
  /** `private.is_current_user_super_admin()` false. */
  notSuperAdmin:
    "Rol atama ve kaldırma yalnız süper yönetici tarafından yapılabilir.",
  /** Hedef gerçek bir kullanıcı değil (ya da girdi eksik). */
  targetNotFound:
    "Hedef kullanıcı bulunamadı. Liste güncel olmayabilir; sayfayı yenileyin.",
  /** Aktör kendi admin rollerini değiştirmeye çalıştı. */
  selfTarget:
    "Kendi admin rollerinizi bu ekrandan değiştiremezsiniz.",
  /** Aktif katalogda böyle bir rol kodu yok. */
  invalidRole:
    "Seçilen rol şu anda aktif değil. Sayfayı yenileyip güncel listeyi kullanın.",
  /** super_admin rolü kategorik reddedilir (atama ve kaldırma). */
  superAdminRole:
    "Süper yönetici rolü bu ekrandan atanamaz veya kaldırılamaz; bu değişiklik yalnız veritabanı yöneticisince yapılır.",
  /** Kaldırma yoluyla son süper yönetici kaldırılmak istendi. */
  lastSuperAdmin:
    "Son süper yönetici kaldırılamaz. Bu ekrandan en az bir süper yönetici bırakılması zorunludur.",
  /** Bilinmeyen hata. */
  generic:
    "Rol işlemi tamamlanamadı. Lütfen daha sonra tekrar deneyin.",
} as const

export type RoleMutationErrorKind = keyof typeof ROLE_MUTATION_ERROR_MESSAGES

// Eşleme sırası önemlidir: daha spesifik kalıplar önce denenir.
// `lastSuperAdmin` (315) benzersizdir ve `superAdminRole`'dan (181) önce
// kontrol edilmelidir; aksi hâlde son-süper-admin durumu genel sınıfa düşer.
const ERROR_PATTERNS: ReadonlyArray<
  readonly [RoleMutationErrorKind, RegExp]
> = [
  ["authRequired", /Human authentication required/i],
  ["notSuperAdmin", /Admin role management requires super admin/i],
  ["targetNotFound", /Target user not found/i],
  ["selfTarget", /Admins cannot change their own admin roles/i],
  ["invalidRole", /Invalid admin role code/i],
  ["lastSuperAdmin", /Cannot remove the last super admin/i],
  ["superAdminRole", /super admin role cannot be assigned or revoked/i],
]

function errorText(error: unknown): string {
  if (error instanceof Error) return `${error.message}`
  if (typeof error === "string") return error
  if (typeof error === "object" && error !== null && "message" in error) {
    const message = (error as { message?: unknown }).message
    if (typeof message === "string") return message
  }
  return ""
}

/** Ham RPC hatasından güvenli sınıf çıkarır; eşleşme yoksa `generic`. */
export function roleMutationErrorKind(error: unknown): RoleMutationErrorKind {
  const text = errorText(error)
  for (const [kind, pattern] of ERROR_PATTERNS) {
    if (pattern.test(text)) return kind
  }
  return "generic"
}

/** Bilinen RPC hatalarını Türkçe kullanıcı mesajına çevirir. */
export function mapRoleMutationError(error: unknown): string {
  return ROLE_MUTATION_ERROR_MESSAGES[roleMutationErrorKind(error)]
}

// ---------------------------------------------------------------------------
// Başarı / sonuç mesajları
// ---------------------------------------------------------------------------

export type RoleMutationOutcomeStatus =
  | "assigned"
  | "already_assigned"
  | "revoked"
  | "already_revoked"

export function isRoleMutationOutcomeStatus(
  value: unknown,
): value is RoleMutationOutcomeStatus {
  return (
    value === "assigned" ||
    value === "already_assigned" ||
    value === "revoked" ||
    value === "already_revoked"
  )
}

/** Durum, manuel tıklamayla yazılmış mı (audit kaydı içeren) bir yazma mı? */
export function outcomeHasAudit(status: RoleMutationOutcomeStatus): boolean {
  return status === "assigned" || status === "revoked"
}

/**
 * Durum'un istenen işlemlerle tutarlı olup olmadığını denetler.
 * `assign` için assigned/already_assigned; `revoke` için revoked/
 * already_revoked. Farklı bir eşleşme beklenen durumdaki tutarsızlıktır.
 */
export function statusMatchesOperation(
  operation: RoleMutationOperation,
  status: RoleMutationOutcomeStatus,
): boolean {
  return operation === "assign"
    ? status === "assigned" || status === "already_assigned"
    : status === "revoked" || status === "already_revoked"
}

/** Rol işlemi sonrası kullanıcı mesajı. `already_*` hiçbir şey yazmadığını bildirir. */
export function roleOutcomeMessage(status: RoleMutationOutcomeStatus): string {
  switch (status) {
    case "assigned":
      return "Rol atandı. Değişiklik kaydedildi ve denetim kaydına eklendi."
    case "revoked":
      return "Rol kaldırıldı. Değişiklik kaydedildi ve denetim kaydına eklendi."
    case "already_assigned":
      return "Bu rol bu kullanıcıya zaten atanmış durumda. Yeni bir kayıt oluşturulmadı; denetim kaydı yazılmadı."
    case "already_revoked":
      return "Bu rol zaten bu kullanıcıdan kaldırılmış durumda. Yeni bir kayıt oluşturulmadı; denetim kaydı yazılmadı."
  }
}

/** İşlem etiketleri (onay adımı ve seçim için). */
export const ROLE_MUTATION_OPERATION_LABELS: Record<
  RoleMutationOperation,
  string
> = {
  assign: "Rol Ata",
  revoke: "Rol Kaldır",
}