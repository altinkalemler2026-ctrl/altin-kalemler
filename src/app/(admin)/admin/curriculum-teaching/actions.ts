"use server"

/**
 * Faz 16 P0.1 — Öğretmen Konu-Açma sunucu aksiyonları.
 *
 * - Yetki RPC içinde (curriculum.manage) tekrar doğrulanır; buradaki
 *   kontroller yalnız kullanıcı deneyimi içindir.
 * - Yazma yalnızca set_curriculum_teaching_approval RPC'si üzerinden
 *   yapılır (doğrudan tablo UPDATE/DELETE yok); RPC atomik audit kaydı
 *   yazar (089 deseni, 119).
 * - Hatalar ham DB mesajı olarak döndürülmez; Türkçe flash mesajıyla
 *   sayfaya yönlendirilir.
 */

import { revalidatePath } from "next/cache"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  CURRICULUM_TEACHING_INPUT_MESSAGES,
  CURRICULUM_TEACHING_SUCCESS_MESSAGES,
  mapCurriculumTeachingError,
} from "@/lib/admin/curriculum-teaching-errors"

type SetApprovalRpc = (
  functionName: "set_curriculum_teaching_approval",
  args: {
    p_schedule_item_id: string
    p_academic_year: string
    p_status: string
    p_notes: string | null
  },
) => Promise<{ error: { message: string } | null }>

function flash(
  subjectId: string,
  year: string,
  kind: "ok" | "error",
  message: string
): never {
  const params = new URLSearchParams()
  if (subjectId) params.set("subject", subjectId)
  if (year) params.set("year", year)
  params.set(kind, message)
  redirect(`/admin/curriculum-teaching?${params.toString()}`)
}

/** Schedule item / yıl / durum / not doğrulama + onay yazma. */
export async function setTeachingApprovalAction(
  formData: FormData
): Promise<void> {
  const scheduleItemId = String(
    formData.get("schedule_item_id") ?? ""
  ).trim()
  const academicYear = String(formData.get("academic_year") ?? "").trim()
  const status = String(formData.get("status") ?? "").trim()
  const notes = String(formData.get("notes") ?? "").trim()
  const subjectId = String(formData.get("subject_id") ?? "").trim()

  if (!scheduleItemId) {
    flash(subjectId, academicYear, "error",
      CURRICULUM_TEACHING_INPUT_MESSAGES.scheduleItemRequired)
  }
  if (!academicYear) {
    flash(subjectId, academicYear, "error",
      CURRICULUM_TEACHING_INPUT_MESSAGES.academicYearRequired)
  }
  if (status !== "approved" && status !== "rejected") {
    flash(subjectId, academicYear, "error",
      CURRICULUM_TEACHING_INPUT_MESSAGES.invalidStatus)
  }

  const supabase = await createClient()

  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    flash(subjectId, academicYear, "error",
      "Bu işlem için giriş yapmalısınız.")
  }

  const rpc = supabase.rpc.bind(supabase) as unknown as SetApprovalRpc
  const { error } = await rpc("set_curriculum_teaching_approval", {
    p_schedule_item_id: scheduleItemId,
    p_academic_year: academicYear,
    p_status: status,
    p_notes: notes ? notes : null,
  })

  if (error) {
    flash(subjectId, academicYear, "error", mapCurriculumTeachingError(error))
  }

  revalidatePath("/admin/curriculum-teaching")
  flash(subjectId, academicYear, "ok",
    CURRICULUM_TEACHING_SUCCESS_MESSAGES.saved)
}