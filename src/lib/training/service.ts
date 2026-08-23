/**
 * Faz 2/3 training servis katmanı — YALNIZ server tarafı.
 *
 * Güvenlik kuralları:
 *  - Kullanıcı kimliği ASLA parametre olarak alınmaz; Supabase istemcisi
 *    oturum çerezini taşır ve RPC'ler auth.uid()'den türetir.
 *  - Cevabın doğruluğu ASLA istemciden kabul edilmez; sonuç yalnızca
 *    submit_training_attempt RPC cevabından okunur.
 *  - Soru payload'ı sıkı allowlist ile güvenli DTO'ya çevrilir;
 *    correct_answer / solution / explanation / review gibi alanlar
 *    bu modülden çıkmaz.
 *
 * Test edilebilirlik için tüm fonksiyonlar istemciyi bağımlılık olarak
 * alır (DI); Next.js sunucu bileşen/aksiyonları gerçek istemciyi verir,
 * testler sahte istemci verir.
 */

import type { SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "@/lib/supabase/types"

import {
  isAttemptAction,
  isChoiceLetter,
  type QuestionSelection,
  type SubmitAnswerInput,
  type SubmitOutcome,
  type SubmitResult,
  type TrainingQuestion,
  type WeeklyUsage,
  type WeeklyUsageSnapshot,
} from "./types"

export type TrainingClient = SupabaseClient<Database>

/** RPC'nin select_training_questions için üst sınırı (068). */
export const MAX_QUESTION_LIMIT = 50
export const DEFAULT_QUESTION_LIMIT = 10

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export class TrainingValidationError extends Error {}

function assertUuid(value: string, label: string): string {
  if (!UUID_PATTERN.test(value)) {
    throw new TrainingValidationError(`${label} geçerli bir UUID değil.`)
  }
  return value
}

export function clampQuestionLimit(limit: number): number {
  if (!Number.isFinite(limit)) return DEFAULT_QUESTION_LIMIT
  const rounded = Math.round(limit)
  return Math.min(MAX_QUESTION_LIMIT, Math.max(1, rounded))
}

export function clampTimeMs(timeMs: number): number {
  if (!Number.isFinite(timeMs) || timeMs < 0) return 0
  // DB tarafındaki clamp ile aynı üst sınır (070).
  return Math.min(3_600_000, Math.round(timeMs))
}

// ------------------------------------------------------------
// Allowlist mapper'lar
// ------------------------------------------------------------

/**
 * RPC'nin döndürdüğü sanitize edilmiş soru nesnesini güvenli DTO'ya çevirir.
 * Bilinmeyen her anahtar sessizce düşürülür (defense in depth).
 */
export function mapQuestionPayload(raw: unknown): TrainingQuestion | null {
  if (typeof raw !== "object" || raw === null) return null

  const record = raw as Record<string, unknown>
  const id = typeof record.id === "string" ? record.id : null
  if (!id || !UUID_PATTERN.test(id)) return null

  const optionText = (value: unknown): string | null =>
    typeof value === "string" && value.trim().length > 0 ? value : null

  const options: TrainingQuestion["options"] = {}
  for (const [key, letter] of [
    ["option_a", "A"],
    ["option_b", "B"],
    ["option_c", "C"],
    ["option_d", "D"],
    ["option_e", "E"],
  ] as const) {
    const text = optionText(record[key])
    if (text) options[letter] = text
  }

  return {
    id,
    questionCode:
      typeof record.question_code === "string" ? record.question_code : null,
    questionText:
      typeof record.question_text === "string" ? record.question_text : null,
    options,
    difficulty:
      typeof record.difficulty === "string" ? record.difficulty : null,
    estimatedSolveTimeSeconds:
      typeof record.estimated_solve_time_seconds === "number"
        ? record.estimated_solve_time_seconds
        : null,
    hasVisual: record.has_visual === true,
  }
}

export function mapWeeklyUsage(raw: unknown): WeeklyUsage {
  const record =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {}

  const subjects: WeeklyUsage["subjects"] = []
  if (Array.isArray(record.subjects)) {
    for (const entry of record.subjects) {
      if (typeof entry !== "object" || entry === null) continue
      const item = entry as Record<string, unknown>
      if (typeof item.subject_id !== "string") continue
      subjects.push({
        subjectId: item.subject_id,
        newQuestionsUsed:
          typeof item.new_questions_used === "number"
            ? item.new_questions_used
            : 0,
        limit: typeof item.limit === "number" ? item.limit : 500,
      })
    }
  }

  return {
    academicYear:
      typeof record.academic_year === "string" ? record.academic_year : null,
    week: typeof record.week === "number" ? record.week : null,
    subjects,
  }
}

/** Seçim RPC'sindeki tek-derslik weekly nesnesi için daraltılmış eşleyici. */
export function mapWeeklySnapshot(raw: unknown): WeeklyUsageSnapshot {
  const record =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {}

  return {
    academicYear:
      typeof record.academic_year === "string" ? record.academic_year : null,
    week: typeof record.week === "number" ? record.week : null,
    subjectId:
      typeof record.subject_id === "string" ? record.subject_id : null,
    newQuestionsUsed:
      typeof record.new_questions_used === "number"
        ? record.new_questions_used
        : 0,
    limit: typeof record.limit === "number" ? record.limit : 500,
  }
}

const VALID_OUTCOMES: readonly SubmitOutcome[] = [
  "correct",
  "wrong",
  "pass",
  "timeout",
  "blank",
]

export function mapSubmitResult(raw: unknown): SubmitResult {
  const record =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {}

  const result =
    typeof record.result === "string" &&
    (VALID_OUTCOMES as readonly string[]).includes(record.result)
      ? (record.result as SubmitOutcome)
      : "wrong"

  return {
    attemptId:
      typeof record.attempt_id === "string" ? record.attempt_id : null,
    attemptNumber:
      typeof record.attempt_number === "number" ? record.attempt_number : 0,
    result,
    duplicate: record.duplicate === true,
  }
}

// ------------------------------------------------------------
// RPC çağrıları
// ------------------------------------------------------------

export interface SubjectListRow {
  id: string
  name: string
  slug: string
}

/** Aktif dersler (subjects_read_active policy: authenticated SELECT). */
export async function listTrainingSubjects(
  client: TrainingClient
): Promise<SubjectListRow[]> {
  const { data, error } = await client
    .from("subjects")
    .select("id, name, slug")
    .eq("is_active", true)
    .order("sort_order", { ascending: true })
    .order("name", { ascending: true })

  if (error) throw error
  return data ?? []
}

/** Haftalık kullanım görünümü (get_my_weekly_usage). */
export async function fetchWeeklyUsage(
  client: TrainingClient
): Promise<WeeklyUsage> {
  const { data, error } = await client.rpc("get_my_weekly_usage")
  if (error) throw error
  return mapWeeklyUsage(data)
}

/**
 * Soru kuyruğu seçimi (select_training_questions).
 * Dönem yoksa DB P0001 fırlatır; çağıran mapTrainingError ile çevirir.
 */
export async function selectTrainingQuestions(
  client: TrainingClient,
  subjectId: string,
  limit: number = DEFAULT_QUESTION_LIMIT
): Promise<QuestionSelection> {
  assertUuid(subjectId, "subjectId")

  const { data, error } = await client.rpc("select_training_questions", {
    p_subject_id: subjectId,
    p_limit: clampQuestionLimit(limit),
  })
  if (error) throw error

  const record =
    typeof data === "object" && data !== null
      ? (data as Record<string, unknown>)
      : {}

  const rawQuestions = Array.isArray(record.questions) ? record.questions : []
  const questions: TrainingQuestion[] = []
  for (const raw of rawQuestions) {
    const mapped = mapQuestionPayload(raw)
    if (mapped) questions.push(mapped)
  }

  return {
    questions,
    weekly: mapWeeklySnapshot(record.weekly),
    reason: typeof record.reason === "string" ? record.reason : null,
  }
}

/**
 * Cevap gönderimi (submit_training_attempt).
 *
 * - user_id ALMAZ; kimlik sunucu oturumundan gelir.
 * - choice/action doğrulaması burada da yapılır (hızlı geri bildirim),
 *   nihai doğrulama DB'dedir.
 * - clientKey zorunlu ve UUID olmalıdır (idempotency anahtarı).
 */
export async function submitTrainingAttempt(
  client: TrainingClient,
  input: SubmitAnswerInput
): Promise<SubmitResult> {
  assertUuid(input.questionId, "questionId")
  assertUuid(input.clientKey, "clientKey")

  const hasChoice = input.choice !== undefined
  const hasAction = input.action !== undefined

  if (!hasChoice && !hasAction) {
    throw new TrainingValidationError(
      "Cevap gönderimi için seçenek veya işlem gereklidir."
    )
  }

  if (
    hasChoice &&
    input.choice !== undefined &&
    !isChoiceLetter(input.choice)
  ) {
    throw new TrainingValidationError(
      "Geçersiz seçenek. A, B, C, D veya E seçin."
    )
  }

  if (hasAction && input.action !== undefined && !isAttemptAction(input.action)) {
    throw new TrainingValidationError(
      "Geçersiz işlem. Pas, boş veya süre dolması beklenir."
    )
  }

  const args = {
    p_question_id: input.questionId,
    p_choice: input.choice ?? null,
    p_action: input.action ?? null,
    p_time_ms: clampTimeMs(input.timeMs),
    p_client_key: input.clientKey,
  }

  const { data, error } = await client.rpc(
    "submit_training_attempt",
    args as unknown as Database["public"]["Functions"]["submit_training_attempt"]["Args"]
  )
  if (error) throw error

  return mapSubmitResult(data)
}
