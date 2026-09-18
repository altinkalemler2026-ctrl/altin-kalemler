import { createClient } from "@/lib/supabase/server"

/**
 * Faz 16 P0.1 — Admin Öğretmen Konu-Açma (veri kıyısı).
 *
 * - 110/119 RPC'leri üzerinden çalışır: list_curriculum_teaching_approvals
 *   (ders + yıl → schedule item + onay durumu) ve
 *   set_curriculum_teaching_approval (atomik audit'li yazma).
 * - Yetki yalnız curriculum.manage üzerinden (RPC tarafı SECURITY DEFINER
 *   olarak tekrar doğrular); buradaki kapı yalnız UI gating içindir
 *   (fail-closed: data === true değilse yetki YOK).
 * - DTO allowlist: alt alta keyfi JSON alanı taşınmaz; her alan tip
 *   kontrolünden geçer. Ham RPC hatası ASLA dışarı sızmaz.
 * - Onay kapsamı (kullanıcı kararı): schedule profile + sınıf + ders +
 *   konu/kazanım + akademik yıl + takvim öğesi; şube/okul paneli YOK.
 */

export type TeachingApprovalStatus = "approved" | "rejected"

export interface CurriculumTeachingItem {
  scheduleItemId: string
  scheduleProfileId: string | null
  profileCode: string | null
  profileName: string | null
  gradeLevel: number
  topicName: string | null
  outcomeText: string | null
  startWeek: number | null
  status: TeachingApprovalStatus | null
  updatedAt: string | null
}

export interface CurriculumTeachingListResult {
  status: "ok" | "error"
  items: CurriculumTeachingItem[]
}

export interface CurriculumTeachingSubject {
  id: string
  name: string
}

export interface CurriculumTeachingYear {
  academicYear: string
}

export interface CurriculumTeachingMetaResult {
  status: "ok" | "error"
  subjects: CurriculumTeachingSubject[]
  years: CurriculumTeachingYear[]
}

type HasPermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

type ListApprovalsRpc = (
  functionName: "list_curriculum_teaching_approvals",
  args: { p_subject_id: string; p_academic_year: string },
) => Promise<{
  data: { items?: unknown[] } | null
  error: { message: string } | null
}>

export async function hasCurriculumTeachingPermission(): Promise<boolean> {
  const supabase = await createClient()
  const { data, error } = await (
    supabase.rpc.bind(supabase) as unknown as HasPermissionRpc
  )("teacher_review_admin_has_permission", {
    p_permission_code: "curriculum.manage",
  })
  return !error && data === true
}

function asString(value: unknown): string | null {
  return typeof value === "string" ? value : null
}

function asNullableString(value: unknown): string | null {
  if (value === null || value === undefined) return null
  return typeof value === "string" ? value : null
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null
}

/** Ham schedule item satırı → izinli DTO (allowlist). */
export function mapCurriculumTeachingItem(
  row: Record<string, unknown>
): CurriculumTeachingItem {
  const status = asNullableString(row.status)
  const safeStatus: TeachingApprovalStatus | null =
    status === "approved" || status === "rejected" ? status : null

  return {
    scheduleItemId: asString(row.schedule_item_id) ?? "",
    scheduleProfileId: asNullableString(row.schedule_profile_id),
    profileCode: asNullableString(row.profile_code),
    profileName: asNullableString(row.profile_name),
    gradeLevel: asNumber(row.grade_level) ?? 0,
    topicName: asNullableString(row.topic_name),
    outcomeText: asNullableString(row.outcome_text),
    startWeek: asNumber(row.start_week),
    status: safeStatus,
    updatedAt: asNullableString(row.updated_at),
  }
}

export async function listCurriculumTeachingApprovals(
  subjectId: string,
  academicYear: string
): Promise<CurriculumTeachingListResult> {
  const supabase = await createClient()
  const { data, error } = await (
    supabase.rpc.bind(supabase) as unknown as ListApprovalsRpc
  )("list_curriculum_teaching_approvals", {
    p_subject_id: subjectId,
    p_academic_year: academicYear,
  })

  if (error) return { status: "error", items: [] }

  const rawItems = Array.isArray(data?.items) ? data.items : []
  return {
    status: "ok",
    items: rawItems.map((row) =>
      mapCurriculumTeachingItem(
        (row && typeof row === "object"
          ? row
          : {}) as Record<string, unknown>
      )
    ),
  }
}

/**
 * Ders + yıl künyelerini okur (subject: RLS active; yıl: curriculum_versions
 * is_active). Bu modülün seçim çubuklarını besler.
 */
export async function listCurriculumTeachingMeta(): Promise<CurriculumTeachingMetaResult> {
  const supabase = await createClient()

  const { data: subjects, error: subjectError } = await supabase
    .from("subjects")
    .select("id, name")
    .order("sort_order", { ascending: true })

  const { data: versions, error: versionError } = await supabase
    .from("curriculum_versions")
    .select("academic_year")
    .eq("is_active", true)
    .order("academic_year", { ascending: false })

  if (subjectError || versionError) {
    return { status: "error", subjects: [], years: [] }
  }

  const seen = new Set<string>()
  const years: CurriculumTeachingYear[] = []
  for (const row of versions ?? []) {
    const year = asString(row?.academic_year)
    if (year && !seen.has(year)) {
      seen.add(year)
      years.push({ academicYear: year })
    }
  }

  return {
    status: "ok",
    subjects: (subjects ?? []).map((row) => ({
      id: asString(row?.id) ?? "",
      name: asString(row?.name) ?? "",
    })),
    years,
  }
}