"use server"

/**
 * Admin soru düzenleme + yayın kontrolü sunucu aksiyonları.
 *
 * - Yetki burada ve RPC guard'ında (089: questions.edit; 040:
 *   questions.approve|ai.manage) İKİKEZ doğrulanır; istemciden gelen
 *   hiçbir rol/izin değeri güvenilmez ve hiçbir koşulda kullanılmaz.
 * - Girdiler RPC'ye gitmeden doğrulanır (089/040 DB kısıtlarıyla uyumlu).
 * - RPC hataları Türkçe mesaja çevrilir; ham DB mesajı flash URL'ine
 *   dahi taşınmaz.
 * - audit: admin_question_edit (089) mutation + admin_audit_log INSERT'ü
 *   AYNI transaction içinde atomik olarak yapar; activate/deactivate
 *   (040) question_publication_events kaydı tutar.
 */

import { revalidatePath } from "next/cache"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  getPublicationReadiness,
  hasAdminPermission,
} from "@/lib/admin/question-edit"
import {
  QUESTION_EDIT_ERROR_MESSAGES,
  QUESTION_EDIT_INPUT_MESSAGES,
  QUESTION_EDIT_SUCCESS_MESSAGES,
  QUESTION_PUBLICATION_MESSAGES,
  QUESTION_PUBLICATION_STATUS_MESSAGES,
  formatBlockerFlash,
  isValidQuestionId,
  mapQuestionEditError,
  validateActivateReason,
  validateDeactivateReason,
  validateQuestionEditInput,
} from "@/lib/admin/question-edit-errors"

type EditRpc = (
  functionName: "admin_question_edit",
  args: {
    p_question_id: string
    p_question_text: string
    p_option_a: string
    p_option_b: string
    p_option_c: string
    p_option_d: string
    p_option_e: string
    p_correct_answer: string
  },
) => Promise<{
  data: Record<string, unknown> | null
  error: { message: string } | null
}>

type PublishRpc = (
  functionName:
    | "activate_question_for_students"
    | "deactivate_question_for_students",
  args: { p_question_id: string; p_reason?: string },
) => Promise<{
  data: Record<string, unknown> | null
  error: { message: string } | null
}>

function flash(
  questionId: string,
  kind: "ok" | "error",
  message: string
): never {
  const params = new URLSearchParams()
  params.set(kind, message)
  redirect(`/admin/questions/${questionId}?${params.toString()}`)
}

/** Soru kimliği geçersizse detay sayfası hedeflenemez; listeye flash. */
function flashToList(message: string): never {
  const params = new URLSearchParams()
  params.set("error", message)
  redirect(`/admin/questions?${params.toString()}`)
}

async function requireSession() {
  const supabase = await createClient()
  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    redirect("/login")
  }
  return supabase
}

/** Yayın (activate/deactivate) izni: questions.approve VEYA ai.manage. */
async function canPublish(): Promise<boolean> {
  if (await hasAdminPermission("questions.approve")) return true
  return hasAdminPermission("ai.manage")
}

function parseId(formData: FormData): string {
  return String(formData.get("questionId") ?? "").trim()
}

/** Soru düzenleme (089 admin_question_edit). */
export async function editQuestionAction(formData: FormData): Promise<void> {
  const validated = validateQuestionEditInput({
    questionId: parseId(formData),
    questionText: String(formData.get("questionText") ?? ""),
    optionA: String(formData.get("optionA") ?? ""),
    optionB: String(formData.get("optionB") ?? ""),
    optionC: String(formData.get("optionC") ?? ""),
    optionD: String(formData.get("optionD") ?? ""),
    optionE: String(formData.get("optionE") ?? ""),
    correctAnswer: String(formData.get("correctAnswer") ?? ""),
  })

  if (!validated.ok) {
    flashToList(validated.message)
  }

  const questionId = validated.value.questionId
  const supabase = await requireSession()

  // Fail-closed UI ön kontrolü; otoriter guard RPC içindedir (089:42501).
  if (!(await hasAdminPermission("questions.edit"))) {
    flash(questionId, "error", QUESTION_EDIT_ERROR_MESSAGES.forbidden)
  }

  const rpc = supabase.rpc.bind(supabase) as unknown as EditRpc
  const { error } = await rpc("admin_question_edit", {
    p_question_id: validated.value.questionId,
    p_question_text: validated.value.questionText,
    p_option_a: validated.value.optionA,
    p_option_b: validated.value.optionB,
    p_option_c: validated.value.optionC,
    p_option_d: validated.value.optionD,
    p_option_e: validated.value.optionE,
    p_correct_answer: validated.value.correctAnswer,
  })

  if (error) {
    flash(questionId, "error", mapQuestionEditError(error))
  }

  revalidatePath(`/admin/questions/${questionId}`)
  revalidatePath("/admin/questions")
  flash(questionId, "ok", QUESTION_EDIT_SUCCESS_MESSAGES.edit)
}

/** Soruyu öğrencilere yayınla (040 activate_question_for_students). */
export async function activateQuestionAction(
  formData: FormData
): Promise<void> {
  const questionId = parseId(formData)
  if (!isValidQuestionId(questionId)) {
    flashToList(QUESTION_EDIT_INPUT_MESSAGES.questionIdInvalid)
  }

  const reason = validateActivateReason(String(formData.get("reason") ?? ""))
  if (!reason.ok) {
    flash(questionId, "error", reason.message)
  }

  const supabase = await requireSession()

  // Fail-closed UI ön kontrolü; otoriter guard RPC içindedir (040).
  if (!(await canPublish())) {
    flash(questionId, "error", QUESTION_EDIT_ERROR_MESSAGES.publishForbidden)
  }

  // Readiness PASS değilse activate RPC'si hiç çağrılmaz; bloker sebepleri
  // Türkçe olarak gösterilir (040 bloker kodları).
  const readiness = await getPublicationReadiness(questionId)
  if (readiness.status === "error") {
    flash(
      questionId,
      "error",
      QUESTION_PUBLICATION_MESSAGES.readinessUnavailable
    )
  }

  if (readiness.currentIsActive === true) {
    flash(
      questionId,
      "error",
      QUESTION_PUBLICATION_STATUS_MESSAGES.alreadyActive
    )
  }

  if (!readiness.canActivate) {
    flash(
      questionId,
      "error",
      `${QUESTION_PUBLICATION_MESSAGES.blockedTitle} ${formatBlockerFlash(
        readiness.blockers.map((blocker) => blocker.message)
      )}`
    )
  }

  const rpc = supabase.rpc.bind(supabase) as unknown as PublishRpc
  const { data, error } = await rpc("activate_question_for_students", {
    p_question_id: questionId,
    ...(reason.value ? { p_reason: reason.value } : {}),
  })

  if (error) {
    flash(questionId, "error", mapQuestionEditError(error))
  }

  if (data?.status === "already_active") {
    flash(
      questionId,
      "error",
      QUESTION_PUBLICATION_STATUS_MESSAGES.alreadyActive
    )
  }

  revalidatePath(`/admin/questions/${questionId}`)
  revalidatePath("/admin/questions")
  flash(questionId, "ok", QUESTION_EDIT_SUCCESS_MESSAGES.activate)
}

/** Soruyu öğrencilerden geri çek (040 deactivate_question_for_students). */
export async function deactivateQuestionAction(
  formData: FormData
): Promise<void> {
  const questionId = parseId(formData)
  if (!isValidQuestionId(questionId)) {
    flashToList(QUESTION_EDIT_INPUT_MESSAGES.questionIdInvalid)
  }

  const reason = validateDeactivateReason(
    String(formData.get("reason") ?? "")
  )
  if (!reason.ok) {
    flash(questionId, "error", reason.message)
  }

  const supabase = await requireSession()

  if (!(await canPublish())) {
    flash(questionId, "error", QUESTION_EDIT_ERROR_MESSAGES.publishForbidden)
  }

  const rpc = supabase.rpc.bind(supabase) as unknown as PublishRpc
  const { data, error } = await rpc("deactivate_question_for_students", {
    p_question_id: questionId,
    p_reason: reason.value,
  })

  if (error) {
    flash(questionId, "error", mapQuestionEditError(error))
  }

  if (data?.status === "already_inactive") {
    flash(
      questionId,
      "error",
      QUESTION_PUBLICATION_STATUS_MESSAGES.alreadyInactive
    )
  }

  revalidatePath(`/admin/questions/${questionId}`)
  revalidatePath("/admin/questions")
  flash(questionId, "ok", QUESTION_EDIT_SUCCESS_MESSAGES.deactivate)
}
