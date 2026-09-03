import { createClient } from "@/lib/supabase/server"
import { mapBlockerMessage } from "@/lib/admin/question-edit-errors"

/**
 * Admin soru düzenleme / yayın kontrolü sunucu okumaları.
 *
 * - Yetki istemciden ASLA okunmaz; her çağrıda sunucu, authenticated
 *   oturum üzerinden izin RPC'sine sorulur (fail-closed: data === true
 *   değilse yetki YOK kabul edilir).
 * - RPC'nin kendi SECURITY DEFINER guard'ı (089: questions.edit,
 *   040: questions.edit|questions.approve|ai.manage) otoriterdir;
 *   buradaki kontrol yalnız UI gating + UX içindir.
 */

export type AdminQuestionPermission =
  | "questions.view"
  | "questions.edit"
  | "questions.approve"
  | "ai.manage"

export async function hasAdminPermission(
  permissionCode: AdminQuestionPermission
): Promise<boolean> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc(
    "teacher_review_admin_has_permission",
    { p_permission_code: permissionCode }
  )
  return !error && data === true
}

export interface ReadinessIssue {
  code: string
  message: string
}

export interface PublicationReadiness {
  /** "error" = readiness verisi okunamadı (ham hata taşınmaz). */
  status: "ok" | "error"
  currentIsActive: boolean | null
  canActivate: boolean
  blockers: ReadinessIssue[]
  warnings: ReadinessIssue[]
}

function mapIssues(value: unknown): ReadinessIssue[] {
  if (!Array.isArray(value)) return []
  const issues: ReadinessIssue[] = []
  for (const entry of value) {
    if (
      entry &&
      typeof entry === "object" &&
      typeof (entry as { code?: unknown }).code === "string"
    ) {
      const code = (entry as { code: string }).code
      // 040'ın İngilizce mesajı taşınp sızmaz; kod Türkçe açıklamaya
      // çevrilir. Bilinmeyen kodlar genel mesaja düşer (fail-closed).
      issues.push({ code, message: mapBlockerMessage(code) })
    }
  }
  return issues
}

/**
 * check_question_activation_readiness (040) yanıtını izinli DTO'ya
 * eşler. Yanıt jsonb'dir; yalnız allowlist alanlar okunur.
 */
export async function getPublicationReadiness(
  questionId: string
): Promise<PublicationReadiness> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc(
    "check_question_activation_readiness",
    { p_question_id: questionId }
  )

  if (error || typeof data !== "object" || data === null) {
    return {
      status: "error",
      currentIsActive: null,
      canActivate: false,
      blockers: [],
      warnings: [],
    }
  }

  const raw = data as Record<string, unknown>
  return {
    status: "ok",
    currentIsActive:
      typeof raw.current_is_active === "boolean"
        ? raw.current_is_active
        : null,
    canActivate: raw.can_activate === true,
    blockers: mapIssues(raw.blocking_reasons),
    warnings: mapIssues(raw.warnings),
  }
}
