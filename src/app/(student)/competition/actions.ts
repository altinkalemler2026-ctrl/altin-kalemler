"use server"

/**
 * Yarisma sunucu aksiyonlari.
 *
 * - Kullanici kimligi ASLA istemciden alinmaz; oturumdan okunur.
 * - Rakip ozel verisi dondurulmez.
 * - Hatalar ham olarak dondurulmez; Turkce mesaja cevrilir.
 */

import { createClient } from "@/lib/supabase/server"
import {
  mapCompetitionError,
  SESSION_EXPIRED_MESSAGE,
} from "@/lib/competition/errors"
import {
  CompetitionValidationError,
  joinMatchmakingQueue,
  leaveMatchmakingQueue,
} from "@/lib/competition/service"
import type {
  QueueJoinResult,
  QueueLeaveResult,
} from "@/lib/competition/types"

export type ActionResponse<T> =
  | { ok: true; data: T }
  | { ok: false; message: string }

/** Kuyruga katil: kimlik sunucudan, sonuc RPC'den. */
export async function joinMatchmakingQueueAction(
  subjectId: string
): Promise<ActionResponse<QueueJoinResult>> {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { ok: false, message: SESSION_EXPIRED_MESSAGE }

  try {
    const data = await joinMatchmakingQueue(supabase, subjectId)
    return { ok: true, data }
  } catch (error) {
    if (error instanceof CompetitionValidationError) {
      return { ok: false, message: error.message }
    }
    return { ok: false, message: mapCompetitionError(error) }
  }
}

/** Kuyruktan cik: kimlik sunucudan, sonuc RPC'den. */
export async function leaveMatchmakingQueueAction(): Promise<
  ActionResponse<QueueLeaveResult>
> {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { ok: false, message: SESSION_EXPIRED_MESSAGE }

  try {
    const data = await leaveMatchmakingQueue(supabase)
    return { ok: true, data }
  } catch (error) {
    if (error instanceof CompetitionValidationError) {
      return { ok: false, message: error.message }
    }
    return { ok: false, message: mapCompetitionError(error) }
  }
}
