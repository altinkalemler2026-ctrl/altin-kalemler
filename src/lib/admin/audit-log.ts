import { createClient } from "@/lib/supabase/server"
import { parsePage, parseUuid } from "@/lib/admin/question-bank"

/**
 * Denetim kaydı (admin_audit_log, migration 089) salt-okunur okuyucuları.
 *
 * - Erişim yalnız audit.view iznine tabidir (RLS + 089 SELECT policy);
 *   buradaki kontrol yalnız UI gating içindir (fail-closed: data === true
 *   değilse yetki YOK).
 * - DTO allowlist: before_data / after_data payload'ları BU fazda
 *   taşınmaz ve render edilmez (veri minimizasyonu); yalnız künye
 *   alanları okunur. Payload görüntüleyici ayrı bir görevdir.
 * - action_code filtresi allowlist'lidir; keyfi metin DB'ye gönderilmez.
 */

export const AUDIT_PAGE_SIZE = 25

/** 089 itibarıyla bilinen action_code'lar; yenileri katalogla genişler. */
export const AUDIT_ACTION_CODES = ["question.edit"] as const

export type AuditActionCode = (typeof AUDIT_ACTION_CODES)[number]

export function parseAuditActionCode(
  value: string | undefined
): AuditActionCode | undefined {
  return (AUDIT_ACTION_CODES as readonly string[]).includes(value ?? "")
    ? (value as AuditActionCode)
    : undefined
}

export interface AuditLogEntry {
  id: string
  actionCode: string
  entityType: string
  entityId: string | null
  actorUserId: string | null
  performedAt: string
}

export interface AuditLogPageResult {
  status: "ok" | "error"
  items: AuditLogEntry[]
  total: number
  page: number
  totalPages: number
}

export async function hasAuditViewPermission(): Promise<boolean> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc(
    "teacher_review_admin_has_permission",
    { p_permission_code: "audit.view" }
  )
  return !error && data === true
}

/** Ham admin_audit_log satırı → izinli DTO (allowlist; payload taşınmaz). */
export function mapAuditLogEntry(row: Record<string, unknown>): AuditLogEntry {
  return {
    id: typeof row.id === "string" ? row.id : "",
    actionCode:
      typeof row.action_code === "string" ? row.action_code : "",
    entityType:
      typeof row.entity_type === "string" ? row.entity_type : "",
    entityId:
      typeof row.entity_id === "string" ? row.entity_id : null,
    actorUserId:
      typeof row.actor_user_id === "string" ? row.actor_user_id : null,
    performedAt:
      typeof row.performed_at === "string" ? row.performed_at : "",
  }
}

const AUDIT_LIST_COLUMNS =
  "id, action_code, entity_type, entity_id, actor_user_id, performed_at"

export async function listAuditLog(
  filter: { actionCode?: AuditActionCode; entityId?: string },
  page: number
): Promise<AuditLogPageResult> {
  const supabase = await createClient()
  const safePage = parsePage(String(page))

  let countQuery = supabase
    .from("admin_audit_log")
    .select("id", { count: "exact", head: true })
  if (filter.actionCode) {
    countQuery = countQuery.eq("action_code", filter.actionCode)
  }
  if (filter.entityId) {
    countQuery = countQuery.eq("entity_id", filter.entityId)
  }

  const { count, error: countError } = await countQuery
  if (countError || count === null) {
    return { status: "error", items: [], total: 0, page: safePage, totalPages: 1 }
  }

  const total = count
  const totalPages = Math.max(1, Math.ceil(total / AUDIT_PAGE_SIZE))
  if (total === 0 || safePage > totalPages) {
    return { status: "ok", items: [], total, page: safePage, totalPages }
  }

  const from = (safePage - 1) * AUDIT_PAGE_SIZE
  let dataQuery = supabase
    .from("admin_audit_log")
    .select(AUDIT_LIST_COLUMNS)
    .order("performed_at", { ascending: false })
    .range(from, from + AUDIT_PAGE_SIZE - 1)
  if (filter.actionCode) {
    dataQuery = dataQuery.eq("action_code", filter.actionCode)
  }
  if (filter.entityId) {
    dataQuery = dataQuery.eq("entity_id", filter.entityId)
  }

  const { data, error } = await dataQuery
  if (error) {
    return { status: "error", items: [], total, page: safePage, totalPages }
  }

  return {
    status: "ok",
    items: (data ?? []).map((row) =>
      mapAuditLogEntry(row as unknown as Record<string, unknown>)
    ),
    total,
    page: safePage,
    totalPages,
  }
}

/** Sorgu parametresinden güvenli entity filtresi (geçersizse undefined). */
export function parseAuditEntityId(value: string | undefined): string | undefined {
  return parseUuid(value)
}
