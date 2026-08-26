"use server"

/**
 * Yarisma sunucu aksiyonlari.
 *
 * - Kullanici kimligi ASLA istemciden alinmaz; oturumdan okunur.
 * - Rakip ozel verisi dondurulmez.
 * - Hatalar ham olarak dondurulmez; Turkce mesaja cevrilir.
 * - Full scoreboard/players/winnerUserId action response'da bulunmaz.
 * - auth.uid() JavaScript tarafinda kullanilmaz; yalnizca
 *   Supabase sunucu istemcisi uzerinden auth.getUser() kullanilir.
 */

import { createClient } from "@/lib/supabase/server"
import {
  mapCompetitionError,
  SESSION_EXPIRED_MESSAGE,
} from "@/lib/competition/errors"
import {
  CompetitionValidationError,
  getCurrentQuestion,
  getOwnResult,
  joinMatchmakingQueue,
  leaveMatchmakingQueue,
  setPlayerReady,
  submitAnswer,
  syncCompetitionState,
} from "@/lib/competition/service"
import type {
  AnswerSubmitResult,
  CompetitionQuestion,
  CompetitionSession,
  OwnCompetitionResult,
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

// ------------------------------------------------------------
// Faz 5b: Yarisma oturum aksiyonlari
// ------------------------------------------------------------

/** Mevcut soruyu getir: kimlik sunucudan, soru icerigi RPC'den. */
export async function getCurrentQuestionAction(): Promise<
  ActionResponse<{
    competitionId: string
    questionAvailable: boolean
    payload: CompetitionQuestion | null
    status: string
  }>
> {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { ok: false, message: SESSION_EXPIRED_MESSAGE }

  try {
    const data = await getCurrentQuestion(supabase)
    return { ok: true, data }
  } catch (error) {
    if (error instanceof CompetitionValidationError) {
      return { ok: false, message: error.message }
    }
    return { ok: false, message: mapCompetitionError(error) }
  }
}

/** Yarisma durumunu senkronize et: kimlik sunucudan. */
export async function syncCompetitionStateAction(
  competitionId: string
): Promise<ActionResponse<CompetitionSession>> {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { ok: false, message: SESSION_EXPIRED_MESSAGE }

  try {
    const data = await syncCompetitionState(supabase, competitionId)
    if (!data) {
      return { ok: false, message: "Yarisma bulunamadi." }
    }
    return { ok: true, data }
  } catch (error) {
    if (error instanceof CompetitionValidationError) {
      return { ok: false, message: error.message }
    }
    return { ok: false, message: mapCompetitionError(error) }
  }
}

/** Cevap gonder: dogruluk/puan sonucu client'a donmez. */
export async function submitAnswerAction(
  competitionQuestionId: string,
  submittedAnswer?: string
): Promise<ActionResponse<AnswerSubmitResult>> {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { ok: false, message: SESSION_EXPIRED_MESSAGE }

  try {
    const data = await submitAnswer(
      supabase,
      competitionQuestionId,
      submittedAnswer
    )
    return { ok: true, data }
  } catch (error) {
    if (error instanceof CompetitionValidationError) {
      return { ok: false, message: error.message }
    }
    return { ok: false, message: mapCompetitionError(error) }
  }
}

/** Hazir ol isareti: tek sefer cagirilmali. */
export async function setPlayerReadyAction(
  competitionId: string
): Promise<ActionResponse<{ status: string }>> {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { ok: false, message: SESSION_EXPIRED_MESSAGE }

  try {
    const data = await setPlayerReady(supabase, competitionId)
    return { ok: true, data }
  } catch (error) {
    if (error instanceof CompetitionValidationError) {
      return { ok: false, message: error.message }
    }
    return { ok: false, message: mapCompetitionError(error) }
  }
}

/**
 * Kullanicinin kendi yarisma sonucunu getir.
 *
 * GUVENLIK: Rakip satirlari, winnerUserId, full scoreboard
 * bu action response'da bulunmaz; yalnizca OwnCompetitionResult doner.
 * authenticatedUserId sunucu auth.getUser()'dan alinir.
 */
export async function getOwnCompetitionResultAction(
  competitionId: string
): Promise<ActionResponse<OwnCompetitionResult>> {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { ok: false, message: SESSION_EXPIRED_MESSAGE }

  try {
    const data = await getOwnResult(supabase, competitionId)
    return { ok: true, data }
  } catch (error) {
    if (error instanceof CompetitionValidationError) {
      return { ok: false, message: error.message }
    }
    return { ok: false, message: mapCompetitionError(error) }
  }
}
