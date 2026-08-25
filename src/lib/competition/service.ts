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

  // 079 migration RPC'leri generated types'ta henuz yok; cast gerekli.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (client as any).rpc(
    "join_matchmaking_queue",
    { p_subject_id: subjectId }
  ) as { data: unknown; error: unknown }
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
  // 079 migration RPC'leri generated types'ta henuz yok; cast gerekli.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (client as any).rpc(
    "leave_matchmaking_queue"
  ) as { data: unknown; error: unknown }
  if (error) throw error

  return mapQueueLeaveResult(data)
}
