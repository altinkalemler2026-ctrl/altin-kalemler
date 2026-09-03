import { createClient } from "@/lib/supabase/server"

/**
 * Faz 4 admin soru bankası salt-okunur okuyucuları.
 *
 * - Yalnızca admin panelinden çağrılır (layout, questions.view yetkisini
 *   doğrular). RLS, satır görünürlüğünü yönetir:
 *     - questions.view sahibi admin: tüm approval_status / is_active görür.
 *     - admin olmayan authenticated: yalnızca öğrenci politikasının izin
 *       verdiği (approved + active) satırları görür.
 *   İstemci tarafında yapay approved/active kısıtı UYGULANMAZ; aksi halde
 *   admin yaşam döngüsü görünümü (draft/pending/rejected/inactive) imkansız
 *   olur. Öğrenciye dönük sorgular bu modülde yer almaz ve değişmez.
 * - Filtreler isteğe bağlıdır; doğrulanmış parametre değerleri kullanılır.
 */

export const EXAM_TRACKS = ["TYT", "AYT"] as const
export const GRADES = [5, 6, 7, 8, 9, 10, 11, 12] as const
export const DIFFICULTIES = ["easy", "medium", "hard"] as const
export const APPROVAL_STATUSES = [
  "approved",
  "pending",
  "draft",
  "rejected",
] as const

export type QuestionFilter = {
  examTrack?: string
  grade?: number
  subjectId?: string
  difficulty?: string
  approvalStatus?: string
  isActive?: boolean
  query?: string
}

/** Liste sorgularının sabit güvenli üst sınırı. */
export const QUESTION_LIST_LIMIT = 200

/** PostgREST `or` filtre dilbilgisini bozan karakterler (ayraç/parantez). */
const SEARCH_RESERVED_CHARS = /[,()]/g

/**
 * Serbest metin arama girdisini PostgREST `or` filtresi için güvenli hale
 * getirir: dilbilgisi ayraçları boşluğa indirilir, boşluklar tekilleştirilir
 * ve uzunluk sınırlandırılır. Geçersiz/boş girdi `undefined` döner.
 */
export function sanitizeSearchQuery(
  value: string | undefined
): string | undefined {
  const cleaned = (value ?? "")
    .trim()
    .replace(SEARCH_RESERVED_CHARS, " ")
    .replace(/\s+/g, " ")
    .slice(0, 100)
    .trim()
  return cleaned.length > 0 ? cleaned : undefined
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * Sorgu parametresinden güvenli UUID değeri (geçersizse undefined).
 * Geçersiz uuid PostgREST'te 400 hatası üretir; burada erken reddedilir.
 */
export function parseUuid(value: string | undefined): string | undefined {
  const trimmed = value?.trim()
  return trimmed && UUID_PATTERN.test(trimmed) ? trimmed : undefined
}

export interface QuestionListItem {
  id: string
  question_code: string
  question_text: string | null
  exam_track: string | null
  grade_level: number
  difficulty: string | null
  approval_status: string | null
  is_active: boolean
  correct_answer: string | null
  created_at: string
  subject_name: string | null
}

export interface QuestionDetail extends QuestionListItem {
  option_a: string | null
  option_b: string | null
  option_c: string | null
  option_d: string | null
  option_e: string | null
  quality_level: string | null
  ownership_status: string | null
  license_status: string | null
  estimated_solve_time_seconds: number | null
  subject_id: string
}

/** Ham subjects satırı (yalnızca listede gösterilecek alanlar). */
export interface SubjectRow {
  id: string
  name: string
}

/** Ham questions satırından yalnızca izinli listeleme alanlarını okur. */
export function subjectNameFrom(
  subjects: unknown
): string | null {
  if (
    subjects &&
    typeof subjects === "object" &&
    !Array.isArray(subjects) &&
    "name" in subjects
  ) {
    const name = (subjects as { name: unknown }).name
    return typeof name === "string" ? name : null
  }
  return null
}

/** Sorgu parametresinden güvenli sınıf değeri (geçersizse null). */
export function parseGrade(value: string | undefined): number | null {
  if (!value) return null
  const n = Number(value)
  return Number.isInteger(n) && GRADES.includes(n as (typeof GRADES)[number])
    ? n
    : null
}

/**
 * Ham questions listeleme satırı → izinli DTO (keyfi alan okumaz).
 * Gizli/PII alan (email, nickname vb.) hiçbir koşulda taşınmaz.
 */
export function mapQuestionListItem(row: Record<string, unknown>): QuestionListItem {
  return {
    id: typeof row.id === "string" ? row.id : "",
    question_code: typeof row.question_code === "string" ? row.question_code : "",
    question_text:
      typeof row.question_text === "string" ? row.question_text : null,
    exam_track: typeof row.exam_track === "string" ? row.exam_track : null,
    grade_level: typeof row.grade_level === "number" ? row.grade_level : 0,
    difficulty: typeof row.difficulty === "string" ? row.difficulty : null,
    approval_status:
      typeof row.approval_status === "string" ? row.approval_status : null,
    is_active: typeof row.is_active === "boolean" ? row.is_active : false,
    correct_answer:
      typeof row.correct_answer === "string" ? row.correct_answer : null,
    created_at: typeof row.created_at === "string" ? row.created_at : "",
    subject_name: subjectNameFrom(row.subjects),
  }
}

/**
 * Ham questions detay satırı → izinli DTO. Yalnızca soru içeriği künyesi
 * taşınır; kullanıcı/kimlik bilgisi dahil edilmez.
 */
export function mapQuestionDetail(row: Record<string, unknown>): QuestionDetail {
  const base = mapQuestionListItem(row)
  return {
    ...base,
    option_a: typeof row.option_a === "string" ? row.option_a : null,
    option_b: typeof row.option_b === "string" ? row.option_b : null,
    option_c: typeof row.option_c === "string" ? row.option_c : null,
    option_d: typeof row.option_d === "string" ? row.option_d : null,
    option_e: typeof row.option_e === "string" ? row.option_e : null,
    quality_level: typeof row.quality_level === "string" ? row.quality_level : null,
    ownership_status:
      typeof row.ownership_status === "string" ? row.ownership_status : null,
    license_status:
      typeof row.license_status === "string" ? row.license_status : null,
    estimated_solve_time_seconds:
      typeof row.estimated_solve_time_seconds === "number"
        ? row.estimated_solve_time_seconds
        : null,
    subject_id: typeof row.subject_id === "string" ? row.subject_id : "",
    subject_name: subjectNameFrom(row.subjects),
  }
}

export async function listSubjects(): Promise<SubjectRow[]> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from("subjects")
    .select("id, name")
    .order("sort_order", { ascending: true })

  if (error) return []
  return (data ?? []) as SubjectRow[]
}

export async function listQuestions(
  filter: QuestionFilter
): Promise<QuestionListItem[]> {
  const supabase = await createClient()

  let query = supabase
    .from("questions")
    .select(
      "id, question_code, question_text, exam_track, grade_level, difficulty, approval_status, is_active, correct_answer, created_at, subjects(name)"
    )
    .order("created_at", { ascending: false })
    .limit(QUESTION_LIST_LIMIT)

  if (filter.examTrack) {
    query = query.eq("exam_track", filter.examTrack)
  }
  if (filter.grade !== undefined && filter.grade !== null) {
    query = query.eq("grade_level", filter.grade)
  }
  if (filter.subjectId) {
    query = query.eq("subject_id", filter.subjectId)
  }
  if (filter.difficulty) {
    query = query.eq("difficulty", filter.difficulty)
  }
  if (filter.approvalStatus) {
    query = query.eq("approval_status", filter.approvalStatus)
  }
  if (filter.isActive !== undefined) {
    query = query.eq("is_active", filter.isActive)
  }
  const searchQuery = sanitizeSearchQuery(filter.query)
  if (searchQuery) {
    query = query.or(
      `question_code.ilike.%${searchQuery}%,question_text.ilike.%${searchQuery}%`
    )
  }

  const { data, error } = await query
  if (error) return []

  return (data ?? []).map((row) =>
    mapQuestionListItem(row as unknown as Record<string, unknown>)
  )
}

export async function getQuestionDetail(
  id: string
): Promise<QuestionDetail | null> {
  const supabase = await createClient()

  const { data, error } = await supabase
    .from("questions")
    .select(
      "id, question_code, question_text, exam_track, grade_level, difficulty, approval_status, is_active, correct_answer, created_at, option_a, option_b, option_c, option_d, option_e, quality_level, ownership_status, license_status, estimated_solve_time_seconds, subject_id, subjects(name)"
    )
    .eq("id", id)
    .maybeSingle()

  if (error || !data) return null

  return mapQuestionDetail(data as unknown as Record<string, unknown>)
}
