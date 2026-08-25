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

type MissingRpcName = "join_matchmaking_queue" | "leave_matchmaking_queue"

type MissingRpcArgsMap = {
  join_matchmaking_queue: { p_subject_id: string }
  leave_matchmaking_queue: Record<string, never>
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
// PRIVATE: Raw scoreboard — hicbir export ile istemciye gecmez
// ------------------------------------------------------------

/**
 * INTERNAL: Ham skor tablosu verisi.
 * Bu tip service.ts disinda export edilmez;
 * client component veya action response uzerinden erisebilir degildir.
 */
interface RawScoreboardPlayer {
  user_id: string
  player_slot: number
  total_points: number
  correct_count: number
  wrong_count: number
  pass_count: number
  timeout_count: number
  finished_at: string | null
}

interface RawScoreboardQuestion {
  question_order: number
  question_id: string
  difficulty: string
  question_result: string | null
  points_awarded: number
  time_ms: number
}

interface RawScoreboard {
  competition_id: string
  competition_code: string
  competition_type: string
  grade_level: number
  subject_id: string
  question_count: number
  winner_user_id: string | null
  result_type: string
  players: RawScoreboardPlayer[]
  questions: RawScoreboardQuestion[]
  started_at: string | null
  completed_at: string | null
}

/**
 * INTERNAL: Ham skor tablosu RPC'si.
 * Export edilmez; yalnizca getOwnResult icinde kullanilir.
 */
async function getRawScoreboard(
  client: CompetitionClient,
  competitionId: string
): Promise<RawScoreboard> {
  assertUuid(competitionId, "competitionId")
  const { data, error } = await client.rpc("get_competition_scoreboard", {
    p_competition_id: competitionId,
  })
  if (error) throw error
  const record =
    typeof data === "object" && data !== null
      ? (data as Record<string, unknown>)
      : {}

  const players = Array.isArray(record.players)
    ? (record.players as RawScoreboardPlayer[])
    : []
  const questions = Array.isArray(record.questions)
    ? (record.questions as RawScoreboardQuestion[])
    : []

  return {
    competition_id:
      typeof record.competition_id === "string" ? record.competition_id : "",
    competition_code:
      typeof record.competition_code === "string"
        ? record.competition_code
        : "",
    competition_type:
      typeof record.competition_type === "string"
        ? record.competition_type
        : "",
    grade_level:
      typeof record.grade_level === "number" ? record.grade_level : 0,
    subject_id:
      typeof record.subject_id === "string" ? record.subject_id : "",
    question_count:
      typeof record.question_count === "number" ? record.question_count : 0,
    winner_user_id:
      typeof record.winner_user_id === "string"
        ? record.winner_user_id
        : null,
    result_type:
      typeof record.result_type === "string" ? record.result_type : "",
    players,
    questions,
    started_at:
      typeof record.started_at === "string" ? record.started_at : null,
    completed_at:
      typeof record.completed_at === "string" ? record.completed_at : null,
  }
}

// ------------------------------------------------------------
// Faz 5b: Own result export
// ------------------------------------------------------------

/**
 * Kullanicinin kendi yarisma sonucunu dondurur.
 *
 * GUVENLIK:
 *  - Rakip satirlari mapper'da atilir.
 *  - winnerUserId DTO'ya girmez.
 *  - Full scoreboard hicbir sekilde client'a gecmez.
 *  - authenticatedUserId parametresi sunucu auth.getUser()'dan gelir;
 *    JS tarafinda auth.uid() kullanilmaz (PostgreSQL fonksiyonudur).
 */
export async function getOwnResult(
  client: CompetitionClient,
  competitionId: string,
  authenticatedUserId: string
): Promise<OwnCompetitionResult> {
  const raw = await getRawScoreboard(client, competitionId)

  const ownPlayer = raw.players.find(
    (p) => p.user_id === authenticatedUserId
  )

  const ownQuestions = raw.questions
    .filter((q) => {
      if (!ownPlayer) return false
      const ownAnswerForQuestion = raw.questions.find(
        (oq) => oq.question_order === q.question_order
      )
      return ownAnswerForQuestion !== undefined
    })
    .sort((a, b) => a.question_order - b.question_order)

  return {
    competitionId: raw.competition_id,
    competitionCode: raw.competition_code,
    competitionType: raw.competition_type,
    gradeLevel: raw.grade_level,
    subjectId: raw.subject_id,
    questionCount: raw.question_count,
    resultType: raw.result_type,
    myPlayerSlot: ownPlayer?.player_slot ?? 0,
    myTotalPoints: ownPlayer?.total_points ?? 0,
    myCorrectCount: ownPlayer?.correct_count ?? 0,
    myWrongCount: ownPlayer?.wrong_count ?? 0,
    myPassCount: ownPlayer?.pass_count ?? 0,
    myTimeoutCount: ownPlayer?.timeout_count ?? 0,
    myFinishedAt: ownPlayer?.finished_at ?? null,
    questionResults: ownQuestions.map((q) => ({
      questionOrder: q.question_order,
      difficulty: q.difficulty,
      pointsAwarded: q.points_awarded,
      timeMs: q.time_ms,
    })),
    startedAt: raw.started_at,
    completedAt: raw.completed_at,
  }
}
