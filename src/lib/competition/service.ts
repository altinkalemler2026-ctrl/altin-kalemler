/**
 * Faz 5 Yarisma servis katmani — YALNIZ server tarafı.
 *
 * Guvenlik kurallari:
 *  - Kullanici kimligi ASLA parametre olarak alinmaz; Supabase istemcisi
 *    oturum cerezini tasir ve RPC'ler auth.uid()'den turetir.
 *  - Rakip ozel verisi (email, isim, ozel ID) dondurulmez.
 *  - correct_answer veya soru icerigi bu dilimde hic bulunmaz.
 *  - Ham Postgres/Supabase hata ayrintilari istemciye gonderilmez.
 *
 * Test edilebilirlik icin tum fonksiyonlar istemciyi bagimlilik olarak
 * alir (DI); Next.js sunucu bileşen/aksiyonlari gercek istemci verir,
 * testler sahte istemci verir.
 */

import type { SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "@/lib/supabase/types"

import type {
  AnswerSubmitResult,
  CompetitionQuestion,
  CompetitionSession,
  OwnCompetitionResult,
  QueueJoinResult,
  QueueLeaveResult,
  QueueStatus,
} from "./types"

export type CompetitionClient = SupabaseClient<Database>

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export class CompetitionValidationError extends Error {}

function assertUuid(value: string, label: string): string {
  if (!UUID_PATTERN.test(value)) {
    throw new CompetitionValidationError(`${label} gecerli bir UUID degil.`)
  }
  return value
}

// ------------------------------------------------------------
// 079 migration: generated types'ta eksik RPC'ler
// ------------------------------------------------------------
// Bu RPC'ler 079 migration ile eklenmis ancak supabase gen types
// calistirilmadigindan Database tipinde tanimli degildir.
// Tipler 079 migration sozlesmesinden turetilmistir.

type MissingRpcName =
  | "join_matchmaking_queue"
  | "leave_matchmaking_queue"
  | "get_own_competition_result"

type MissingRpcArgsMap = {
  join_matchmaking_queue: { p_subject_id: string }
  leave_matchmaking_queue: Record<string, never>
  get_own_competition_result: { p_competition_id: string }
}

/**
 * Supabase client'in yalnizca 079 eksik RPC'lerini kabul eden dar turlu versiyonu.
 * Disaridan bilinmeyen RPC adlari compile-time'da reddedilir.
 */
interface NarrowMissingRpcClient {
  rpc<Name extends MissingRpcName>(
    fn: Name,
    args: MissingRpcArgsMap[Name]
  ): Promise<{ data: unknown; error: unknown }>
}

/** Supabase client'i dar RPC arayuzune cevirir. */
function toNarrowClient(client: CompetitionClient): NarrowMissingRpcClient {
  return client as unknown as NarrowMissingRpcClient
}

/** Yalnizca allowlisted exact RPC adlarini kabul eden guvenli cagri. */
function callMissingGeneratedRpc<Name extends MissingRpcName>(
  client: NarrowMissingRpcClient,
  name: Name,
  args: MissingRpcArgsMap[Name]
): Promise<{ data: unknown; error: unknown }> {
  return client.rpc(name, args)
}

// ------------------------------------------------------------
// Allowlist mapper'lar
// ------------------------------------------------------------

const VALID_QUEUE_STATUSES: readonly QueueStatus[] = [
  "waiting",
  "matched",
  "cancelled",
  "expired",
]

/**
 * join_matchmaking_queue RPC cevabini guvenli DTO'ya cevirir.
 * Bilinmeyen her anahtar sessizce dusurulur (defense in depth).
 * Rakip verisi dondurulmez.
 */
export function mapQueueJoinResult(raw: unknown): QueueJoinResult {
  const record =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {}

  const status: QueueStatus =
    typeof record.status === "string" &&
    (VALID_QUEUE_STATUSES as readonly string[]).includes(record.status)
      ? (record.status as QueueStatus)
      : "waiting"

  const queueId =
    typeof record.queue_id === "string" ? record.queue_id : ""

  const gradeLevel =
    typeof record.grade_level === "number" ? record.grade_level : 0

  const subjectId =
    typeof record.subject_id === "string" ? record.subject_id : ""

  const competitionId =
    typeof record.competition_id === "string"
      ? record.competition_id
      : undefined

  const competitionCode =
    typeof record.competition_code === "string"
      ? record.competition_code
      : undefined

  return {
    status,
    queueId,
    gradeLevel,
    subjectId,
    competitionId,
    competitionCode,
  }
}

/**
 * leave_matchmaking_queue RPC cevabini guvenli DTO'ya cevirir.
 */
export function mapQueueLeaveResult(raw: unknown): QueueLeaveResult {
  const record =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {}

  return {
    cancelled: typeof record.cancelled === "number" ? record.cancelled : 0,
  }
}

// ------------------------------------------------------------
// RPC cagrilari
// ------------------------------------------------------------

/**
 * Kuyruga katil (join_matchmaking_queue).
 *
 * - user_id ALMAZ; kimlik sunucu oturumundan gelir.
 * - Duplicate join idempotent: ayni ogrenci zaten bekliyorsa eslesme
 *   firsati yeniden denenir.
 * - Rate limit RPC icinde uygulanir (queue_join: 10/300sn).
 */
export async function joinMatchmakingQueue(
  client: CompetitionClient,
  subjectId: string
): Promise<QueueJoinResult> {
  assertUuid(subjectId, "subjectId")

  const { data, error } = await callMissingGeneratedRpc(
    toNarrowClient(client),
    "join_matchmaking_queue",
    { p_subject_id: subjectId }
  )
  if (error) throw error

  return mapQueueJoinResult(data)
}

/**
 * Kuyruktan cik (leave_matchmaking_queue).
 *
 * - Yalniz kullaniciya ait 'waiting' durumundaki kayitlari etkiler.
 * - Basariyla iptal edilen satir sayisini dondurur.
 */
export async function leaveMatchmakingQueue(
  client: CompetitionClient
): Promise<QueueLeaveResult> {
  const { data, error } = await callMissingGeneratedRpc(
    toNarrowClient(client),
    "leave_matchmaking_queue",
    {}
  )
  if (error) throw error

  return mapQueueLeaveResult(data)
}

// ------------------------------------------------------------
// Faz 5b: Yarisma oturumu mapper'lari
// ------------------------------------------------------------

/**
 * get_current_competition_question icin guvenli soru payload'i olusturur.
 * Raw HTML alanlarini oldugu gibi birakir; guvenli render QuestionRenderer'da yapilir.
 */
function mapQuestionPayloadFromRaw(
  raw: Record<string, unknown>
): CompetitionQuestion | null {
  const cpid =
    typeof raw.competition_question_id === "string"
      ? raw.competition_question_id
      : null
  if (!cpid) return null

  const question =
    typeof raw.question === "object" && raw.question !== null
      ? (raw.question as Record<string, unknown>)
      : null
  if (!question) return null

  const qId = typeof question.id === "string" ? question.id : cpid

  const options: CompetitionQuestion["options"] = {}
  const optionFields = [
    ["option_a_html", "A"],
    ["option_b_html", "B"],
    ["option_c_html", "C"],
    ["option_d_html", "D"],
    ["option_e_html", "E"],
  ] as const
  for (const [field, letter] of optionFields) {
    const val = question[field]
    if (typeof val === "string" && val.length > 0) {
      options[letter] = val
    }
  }

  return {
    id: qId,
    questionOrder:
      typeof raw.question_order === "number" ? raw.question_order : 0,
    sentAt: typeof raw.sent_at === "string" ? raw.sent_at : "",
    deadlineAt: typeof raw.deadline_at === "string" ? raw.deadline_at : "",
    stemHtml:
      typeof question.stem_html === "string" ? question.stem_html : "",
    options,
    difficulty:
      typeof question.difficulty === "string" ? question.difficulty : null,
  }
}

/**
 * get_current_competition_question cevabini guvenli DTO'ya cevirir.
 * correct_answer, solution, explanation bu mapper'dan gecmez.
 */
export function mapQuestionResult(raw: unknown): {
  competitionId: string
  questionAvailable: boolean
  payload: CompetitionQuestion | null
  status: string
} {
  const record =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {}

  const competitionId =
    typeof record.competition_id === "string" ? record.competition_id : ""
  const status = typeof record.status === "string" ? record.status : ""
  const questionAvailable = record.question_available === true

  let payload: CompetitionQuestion | null = null
  if (questionAvailable && typeof record.payload === "object" && record.payload !== null) {
    payload = mapQuestionPayloadFromRaw(record.payload as Record<string, unknown>)
  }

  return { competitionId, questionAvailable, payload, status }
}

/**
 * sync_competition_state cevabini guvenli oturum DTO'ya cevirir.
 * opponent_current_score, progress bu mapper'dan dusurulur.
 */
export function mapSessionState(raw: unknown): CompetitionSession | null {
  const record =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {}

  const competitionId =
    typeof record.competition_id === "string" ? record.competition_id : null
  if (!competitionId) return null

  return {
    competitionId,
    status: typeof record.status === "string" ? record.status : "",
    currentQuestionOrder:
      typeof record.current_question_order === "number"
        ? record.current_question_order
        : null,
    totalQuestions:
      typeof record.question_count === "number" ? record.question_count : 0,
    sentAt:
      typeof record.sent_at === "string" ? record.sent_at : null,
    deadlineAt:
      typeof record.deadline_at === "string" ? record.deadline_at : null,
    timeLimitSeconds:
      typeof record.time_limit_seconds === "number"
        ? record.time_limit_seconds
        : null,
    hasAnsweredCurrentQuestion:
      record.has_answered_current_question === true,
    myCurrentScore:
      typeof record.my_current_score === "number"
        ? record.my_current_score
        : 0,
    competitionCode:
      typeof record.competition_code === "string"
        ? record.competition_code
        : null,
    competitionType:
      typeof record.competition_type === "string"
        ? record.competition_type
        : null,
  }
}

/**
 * submit_competition_answer cevabini guvenli DTO'ya cevirir.
 * correct/wrong/pointsAwarded/timeBand icERMEZ; yalnizca accepted/submissionId.
 */
export function mapAnswerSubmitResult(raw: unknown): AnswerSubmitResult {
  const record =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {}

  return {
    accepted: typeof record.answer_id === "string",
    submissionId:
      typeof record.answer_id === "string" ? record.answer_id : null,
  }
}

// ------------------------------------------------------------
// Faz 5b: RPC cagrilari (export)
// ------------------------------------------------------------

/**
 * Mevcut soruyu getir (get_current_competition_question).
 * Parametre almaz; sunucu RPC'si kendi kullanici bulur.
 */
export async function getCurrentQuestion(
  client: CompetitionClient
): Promise<{
  competitionId: string
  questionAvailable: boolean
  payload: CompetitionQuestion | null
  status: string
}> {
  const { data, error } = await client.rpc(
    "get_current_competition_question"
  )
  if (error) throw error
  return mapQuestionResult(data)
}

/**
 * Yarisma durumunu senkronize et (sync_competition_state).
 * Timeout ve soru ilerlemesini sunucu tarafinda tetikler.
 */
export async function syncCompetitionState(
  client: CompetitionClient,
  competitionId: string
): Promise<CompetitionSession | null> {
  assertUuid(competitionId, "competitionId")
  const { data, error } = await client.rpc("sync_competition_state", {
    p_competition_id: competitionId,
  })
  if (error) throw error
  return mapSessionState(data)
}

/**
 * Cevap gonder (submit_competition_answer).
 * Dogruluk/puan sonucu sunucuda hesaplanir; client yalnizca
 * accepted/submissionId alir.
 */
export async function submitAnswer(
  client: CompetitionClient,
  competitionQuestionId: string,
  submittedAnswer?: string
): Promise<AnswerSubmitResult> {
  assertUuid(competitionQuestionId, "competitionQuestionId")
  const { data, error } = await client.rpc("submit_competition_answer", {
    p_competition_question_id: competitionQuestionId,
    ...(submittedAnswer !== undefined
      ? { p_submitted_answer: submittedAnswer }
      : {}),
  })
  if (error) throw error
  return mapAnswerSubmitResult(data)
}

/**
 * Hazir ol isareti (set_competition_player_ready).
 * Tek sefer cagirilmalidir; tekrarli cagrilarda idempotent davranir.
 */
export async function setPlayerReady(
  client: CompetitionClient,
  competitionId: string
): Promise<{ status: string }> {
  assertUuid(competitionId, "competitionId")
  const { data, error } = await client.rpc("set_competition_player_ready", {
    p_competition_id: competitionId,
  })
  if (error) throw error
  const record =
    typeof data === "object" && data !== null
      ? (data as Record<string, unknown>)
      : {}
  return {
    status: typeof record.status === "string" ? record.status : "",
  }
}

// ------------------------------------------------------------
// 081: Own result — get_own_competition_result RPC
// ------------------------------------------------------------

/**
 * mapOwnCompetitionResult — get_own_competition_result RPC cevabini
 * OwnCompetitionResult DTO'ya cevirir. Rakip verisi zaten RPC tarafinda
 * filtrelenmistir; bu mapper yalnizca tip donusumu yapar.
 */
export function mapOwnCompetitionResult(raw: unknown): OwnCompetitionResult {
  const record =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {}

  return {
    competitionId:
      typeof record.competition_id === "string" ? record.competition_id : "",
    competitionCode:
      typeof record.competition_code === "string"
        ? record.competition_code
        : "",
    competitionType:
      typeof record.competition_type === "string"
        ? record.competition_type
        : "",
    gradeLevel:
      typeof record.grade_level === "number" ? record.grade_level : 0,
    subjectId:
      typeof record.subject_id === "string" ? record.subject_id : "",
    questionCount:
      typeof record.question_count === "number" ? record.question_count : 0,
    resultType:
      typeof record.result_type === "string" ? record.result_type : "",
    myPlayerSlot:
      typeof record.my_player_slot === "number" ? record.my_player_slot : 0,
    myTotalPoints:
      typeof record.my_total_points === "number" ? record.my_total_points : 0,
    myCorrectCount:
      typeof record.my_correct_count === "number"
        ? record.my_correct_count
        : 0,
    myWrongCount:
      typeof record.my_wrong_count === "number" ? record.my_wrong_count : 0,
    myPassCount:
      typeof record.my_pass_count === "number" ? record.my_pass_count : 0,
    myTimeoutCount:
      typeof record.my_timeout_count === "number"
        ? record.my_timeout_count
        : 0,
    myFinishedAt:
      typeof record.my_finished_at === "string" ? record.my_finished_at : null,
    questionResults: Array.isArray(record.question_results)
      ? (record.question_results as Array<Record<string, unknown>>)
          .map((q) => ({
            questionOrder:
              typeof q.question_order === "number" ? q.question_order : 0,
            difficulty:
              typeof q.difficulty === "string" ? q.difficulty : "",
            pointsAwarded:
              typeof q.points_awarded === "number" ? q.points_awarded : 0,
            timeMs: typeof q.time_ms === "number" ? q.time_ms : 0,
          }))
          .sort((a, b) => a.questionOrder - b.questionOrder)
      : [],
    startedAt:
      typeof record.started_at === "string" ? record.started_at : null,
    completedAt:
      typeof record.completed_at === "string" ? record.completed_at : null,
  }
}

/**
 * Kullanicinin kendi yarisma sonucunu getir.
 *
 * 081 SONRASI: get_competition_scoreboard yerine
 * get_own_competition_result kullanilir. RPC zaten yalnizca
 * kendi verisini dondurur; rakip verisi fonksiyon icerisinde
 * filtrelenmistir.
 *
 * authenticatedUserId parametresi suan artik kullanilmiyor
 * (RPC auth.uid() ile kendi kullanici bulur) ancak geriye donuk
 * uyumluluk icin korunmustur.
 */
export async function getOwnResult(
  client: CompetitionClient,
  competitionId: string,
  _authenticatedUserId?: string
): Promise<OwnCompetitionResult> {
  assertUuid(competitionId, "competitionId")
  const { data, error } = await callMissingGeneratedRpc(
    toNarrowClient(client),
    "get_own_competition_result",
    { p_competition_id: competitionId }
  )
  if (error) throw error
  return mapOwnCompetitionResult(data)
}
