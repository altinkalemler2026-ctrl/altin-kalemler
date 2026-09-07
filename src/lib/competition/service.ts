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
  OwnCompetitionOutcome,
  OwnCompetitionResult,
  OwnMatchmakingStatus,
  OwnMatchmakingStatusValue,
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

  // submit_competition_answer FK olarak competition_questions.id
  // bekler; payload kimliği BU değerdir. Soru bankası kimliği
  // (question.id) gönderimde kullanılamaz.

  const options: CompetitionQuestion["options"] = {}
  // RPC (023) soru satirini oldugu gibi dondurur: tabloda alanlar
  // option_a..option_e'dir; _html varyantlari gelecekteki HTML destekli
  // senaryolar icin tercih edilir.
  const optionFields = [
    ["option_a_html", "option_a", "A"],
    ["option_b_html", "option_b", "B"],
    ["option_c_html", "option_c", "C"],
    ["option_d_html", "option_d", "D"],
    ["option_e_html", "option_e", "E"],
  ] as const
  for (const [htmlField, textField, letter] of optionFields) {
    const htmlVal = question[htmlField]
    if (typeof htmlVal === "string" && htmlVal.length > 0) {
      options[letter] = htmlVal
      continue
    }
    const textVal = question[textField]
    if (typeof textVal === "string" && textVal.length > 0) {
      options[letter] = textVal
    }
  }

  return {
    id: cpid,
    questionOrder:
      typeof raw.question_order === "number" ? raw.question_order : 0,
    sentAt: typeof raw.sent_at === "string" ? raw.sent_at : "",
    deadlineAt: typeof raw.deadline_at === "string" ? raw.deadline_at : "",
    stemHtml:
      typeof question.stem_html === "string" && question.stem_html.length > 0
        ? question.stem_html
        : typeof question.question_text === "string"
          ? question.question_text
          : "",
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
 *
 * NOT: RPC (023) yanitinda competition_id alanı DONMEZ; mapper
 * bu alani zorunlu tuttugu icin çağıranın bildiği p_competition_id
 * ham yanıta enjekte edilir. Aynı şekilde completed dalı yalnızca
 * status döner; mapper bu yanıtta da çalışabilir olmalıdır.
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
  if (typeof data !== "object" || data === null) return null
  const raw = data as Record<string, unknown>
  return mapSessionState({ ...raw, competition_id: competitionId })
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
// 084: Kuyruk durumu sorgusu (rate-limit tuketmez)
// ------------------------------------------------------------

const VALID_OWN_MATCHMAKING_STATUSES: readonly OwnMatchmakingStatusValue[] = [
  "not_queued",
  "waiting",
  "matched",
]

/**
 * get_own_matchmaking_status RPC cevabini guvenli DTO'ya cevirir.
 * Bilinmeyen durum not_queued'a dusurulur (fail-closed).
 */
export function mapOwnMatchmakingStatus(raw: unknown): OwnMatchmakingStatus {
  const record =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {}

  const status =
    typeof record.status === "string" &&
    (VALID_OWN_MATCHMAKING_STATUSES as readonly string[]).includes(
      record.status
    )
      ? (record.status as OwnMatchmakingStatusValue)
      : "not_queued"

  return {
    status,
    competitionId:
      typeof record.competition_id === "string" && record.competition_id.length > 0
        ? record.competition_id
        : null,
    competitionCode:
      typeof record.competition_code === "string" &&
      record.competition_code.length > 0
        ? record.competition_code
        : null,
  }
}

/**
 * Kullanicinin kendi kuyruk durumunu sorgular (084).
 *
 * - Rate limit TUKETMEZ; beklerken periyodik polling bu RPC ile yapilir.
 * - Kimlik sunucu oturumundan gelir; user parametresi yoktur.
 * - matched durumunda yalnizca kullanici katilimciysa yarisma bilgisi doner.
 */
export async function getOwnMatchmakingStatus(
  client: CompetitionClient,
  subjectId: string
): Promise<OwnMatchmakingStatus> {
  assertUuid(subjectId, "subjectId")
  const { data, error } = await client.rpc("get_own_matchmaking_status", {
    p_subject_id: subjectId,
  })
  if (error) throw error
  return mapOwnMatchmakingStatus(data)
}

// ------------------------------------------------------------
// 081 + 099: Own result — get_own_competition_result RPC
// ------------------------------------------------------------

const VALID_OWN_OUTCOMES: readonly OwnCompetitionOutcome[] = [
  "win",
  "loss",
  "draw",
  "forfeit_win",
  "forfeit_loss",
  "no_contest",
]

/**
 * RPC'nin ->>' ile metin olarak dondurdugu sayısal alanları güvenle
 * sayıya cevirir; 081/099 jsonb sözleşmesi string veya number
 * verebilir. Geçersiz değerlerde fallback doner.
 */
function coerceNumber(value: unknown, fallback: number): number {
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return parsed
  }
  return fallback
}

/**
 * mapOwnCompetitionResult — get_own_competition_result RPC cevabini
 * OwnCompetitionResult DTO'ya cevirir. Rakip verisi zaten RPC tarafinda
 * filtrelenmistir; bu mapper yalnizca tip donusumu yapar. 099 ile
 * my_result + kendi answer_result/submitted_answer alanlari eklenir;
 * winner_user_id/players bu mapper'dan ASLA gecmez.
 */
export function mapOwnCompetitionResult(raw: unknown): OwnCompetitionResult {
  const record =
    typeof raw === "object" && raw !== null
      ? (raw as Record<string, unknown>)
      : {}

  const myResult: OwnCompetitionOutcome =
    typeof record.my_result === "string" &&
    (VALID_OWN_OUTCOMES as readonly string[]).includes(record.my_result)
      ? (record.my_result as OwnCompetitionOutcome)
      : "no_contest"

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
    gradeLevel: coerceNumber(record.grade_level, 0),
    subjectId:
      typeof record.subject_id === "string" ? record.subject_id : "",
    questionCount: coerceNumber(record.question_count, 0),
    resultType:
      typeof record.result_type === "string" ? record.result_type : "",
    myResult,
    myPlayerSlot: coerceNumber(record.my_player_slot, 0),
    myTotalPoints: coerceNumber(record.my_total_points, 0),
    myCorrectCount: coerceNumber(record.my_correct_count, 0),
    myWrongCount: coerceNumber(record.my_wrong_count, 0),
    myPassCount: coerceNumber(record.my_pass_count, 0),
    myTimeoutCount: coerceNumber(record.my_timeout_count, 0),
    myFinishedAt:
      typeof record.my_finished_at === "string" ? record.my_finished_at : null,
    questionResults: Array.isArray(record.question_results)
      ? (record.question_results as Array<Record<string, unknown>>)
          .map((q) => ({
            questionOrder: coerceNumber(q.question_order, 0),
            difficulty: typeof q.difficulty === "string" ? q.difficulty : "",
            pointsAwarded: coerceNumber(q.points_awarded, 0),
            timeMs: coerceNumber(q.time_ms, 0),
            answerResult:
              typeof q.answer_result === "string" ? q.answer_result : "timeout",
            submittedAnswer:
              typeof q.submitted_answer === "string" ? q.submitted_answer : null,
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
