/**
 * Faz 6 — Hedefli Tekrar ve Kazanım Analitiği servis katmanı.
 * YALNIZ server tarafı.
 *
 * Güvenlik kuralları (training/analytics desenleriyle aynı):
 *  - Kullanıcı kimliği ASLA parametre olarak alınmaz; RPC'ler
 *    auth.uid()'den türetir (başkasının analitiği okunamaz).
 *  - RPC cevabı sıkı allowlist mapper'dan geçer; ham DB satırı DTO
 *    olarak doğrudan dışarı verilmez; PII ve soru gizli alanları bu
 *    modülden çıkmaz.
 *  - Formüller ve eşikler docs/project/faz6-tasarim.md §2/§5'te
 *    dokümante edilmiştir; DB (098) ile birebir aynıdır.
 *
 * Test edilebilirlik için fonksiyonlar istemciyi bağımlılık olarak
 * alır (DI); server component gerçek istemciyi, testler sahte istemci
 * verir.
 */

import type { SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "@/lib/supabase/types"
import {
  mapQuestionPayload,
  mapWeeklySnapshot,
} from "@/lib/training/service"
import {
  clampReviewLimit,
  isOutcomeBand,
  isTargetedReviewReason,
  type OutcomeBand,
  type OutcomeReviewRow,
  type TargetedReviewSelection,
} from "./types"

export type ReviewClient = SupabaseClient<Database>

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export class ReviewValidationError extends Error {}

function assertUuid(value: string, label: string): string {
  if (!UUID_PATTERN.test(value)) {
    throw new ReviewValidationError(`${label} geçerli bir UUID değil.`)
  }
  return value
}

function toInt(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value)
  }
  if (typeof value === "string") {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return Math.trunc(parsed)
  }
  return 0
}

function toNullableNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null
  if (typeof value === "number" && Number.isFinite(value)) return value
  if (typeof value === "string") {
    const parsed = Number(value)
    if (Number.isFinite(parsed)) return parsed
  }
  return null
}

function toNullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null
}

/** timestamptz çıktısını deterministik ISO (Z) biçimine normalleştirir. */
function toNullableTimestamp(value: unknown): string | null {
  const raw = toNullableString(value)
  if (raw === null) return null
  const parsed = new Date(raw)
  if (Number.isNaN(parsed.getTime())) return null
  return parsed.toISOString()
}

/**
 * Ham 098 satırını güvenli DTO'ya çevirir.
 *
 * Sıkı allowlist: yalnızca aşağıdaki alanlar geçer; bilinmeyen/ekstra
 * alanlar sessizce düşer. Band/ID anlamsız olan satır null döner
 * (atlanır) — bozuk satır tüm planı düşürmez.
 */
export function mapOutcomeReviewRow(raw: unknown): OutcomeReviewRow | null {
  if (typeof raw !== "object" || raw === null) return null
  const record = raw as Record<string, unknown>

  const outcomeId = record.outcome_id
  if (typeof outcomeId !== "string" || !UUID_PATTERN.test(outcomeId)) {
    return null
  }

  const band = record.band
  if (!isOutcomeBand(band)) return null

  const outcomeText = record.outcome_text
  if (typeof outcomeText !== "string" || outcomeText.trim().length === 0) {
    return null
  }

  return {
    outcomeId,
    outcomeText,
    band: band as OutcomeBand,
    totalAttempts: toInt(record.total_attempts),
    // Yetersiz veride RPC NULL döner; mapper NULL'ı aynen korur
    // (yanıltıcı yüzde engellenir).
    successRate: toNullableNumber(record.success_rate),
    repeatTotal: toInt(record.repeat_total),
    repeatSuccessRate: toNullableNumber(record.repeat_success_rate) ?? 0,
    pendingErrors: toInt(record.pending_errors),
    redeemed: toInt(record.redeemed),
    // Payda < 5 (MIN_REDEEM_EVIDENCE) ise RPC NULL döner.
    redeemRate: toNullableNumber(record.redeem_rate),
    lastReviewedAt: toNullableTimestamp(record.last_reviewed_at),
  }
}

/**
 * Öğrencinin kendi dönem-kapılı kazanımları için analitik + tekrar
 * etkisi planı (get_outcome_review_plan). Kullanıcı parametresi
 * ALMAZ; kimlik RPC'de auth.uid()'den gelir.
 */
export async function fetchOutcomeReviewPlan(
  client: ReviewClient,
  subjectId: string
): Promise<OutcomeReviewRow[]> {
  assertUuid(subjectId, "subjectId")

  const { data, error } = await client.rpc("get_outcome_review_plan", {
    p_subject_id: subjectId,
  })
  if (error) throw error

  const rows = Array.isArray(data) ? data : []
  const result: OutcomeReviewRow[] = []
  for (const raw of rows) {
    const mapped = mapOutcomeReviewRow(raw)
    if (mapped) result.push(mapped)
  }
  return result
}

/**
 * Deterministik hedefli tekrar oturumu seçimi
 * (select_targeted_review_questions). Hata havuzu öncelikli; kalan
 * slotlar yeni sorularla doldurulur. reason:
 *  - 'gecersiz_kapsam' → boş liste (fail-closed),
 *  - 'tekrar_gerekmiyor' → boş liste (pozitif kapanış).
 */
export async function startTargetedReview(
  client: ReviewClient,
  subjectId: string,
  outcomeId: string,
  limit: number = 5
): Promise<TargetedReviewSelection> {
  assertUuid(subjectId, "subjectId")
  assertUuid(outcomeId, "outcomeId")

  const { data, error } = await client.rpc(
    "select_targeted_review_questions",
    {
      p_subject_id: subjectId,
      p_outcome_id: outcomeId,
      p_limit: clampReviewLimit(limit),
    } as unknown as Database["public"]["Functions"]["select_targeted_review_questions"]["Args"]
  )
  if (error) throw error

  const record =
    typeof data === "object" && data !== null
      ? (data as Record<string, unknown>)
      : {}

  const rawQuestions = Array.isArray(record.questions) ? record.questions : []
  const questions: TargetedReviewSelection["questions"] = []
  for (const raw of rawQuestions) {
    const mapped = mapQuestionPayload(raw)
    if (mapped) questions.push(mapped)
  }

  const rawReason = record.reason
  const reason = isTargetedReviewReason(rawReason) ? rawReason : null

  return {
    questions,
    sessionKind:
      typeof record.session_kind === "string" ? record.session_kind : "",
    outcomeId:
      typeof record.outcome_id === "string" ? record.outcome_id : outcomeId,
    wrongReviewCount: toInt(record.wrong_review_count),
    newCount: toInt(record.new_count),
    reason,
    weekly: mapWeeklySnapshot(record.weekly),
  }
}
