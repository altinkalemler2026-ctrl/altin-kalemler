"use server"

/**
 * Training sunucu aksiyonları.
 *
 * - Kullanıcı kimliği ASLA istemciden alınmaz; oturumdan okunur.
 * - Doğruluk bilgisi ASLA istemciden kabul edilmez; sonuç RPC'den gelir.
 * - Hatalar ham olarak döndürülmez; Türkçe mesaja çevrilir.
 */

import { createClient } from "@/lib/supabase/server"
import { mapTrainingError, SESSION_EXPIRED_MESSAGE } from "@/lib/training/errors"
import {
  DEFAULT_QUESTION_LIMIT,
  selectTrainingQuestions,
  submitTrainingAttempt,
  TrainingValidationError,
} from "@/lib/training/service"
import type {
  QuestionSelection,
  SubmitAnswerInput,
  SubmitResult,
  TrainingScopeFilter,
} from "@/lib/training/types"

export type ActionResponse<T> =
  | { ok: true; data: T }
  | { ok: false; message: string }

/** Cevap gönderimi: kimlik sunucudan, sonuç RPC'den. */
export async function submitTrainingAttemptAction(
  input: SubmitAnswerInput
): Promise<ActionResponse<SubmitResult>> {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { ok: false, message: SESSION_EXPIRED_MESSAGE }

  try {
    const data = await submitTrainingAttempt(supabase, input)
    return { ok: true, data }
  } catch (error) {
    if (error instanceof TrainingValidationError) {
      return { ok: false, message: error.message }
    }
    return { ok: false, message: mapTrainingError(error) }
  }
}

/** Soru kuyruğu yenileme (oturum içinde tekrar yükleme için). */
export async function selectTrainingQuestionsAction(
  subjectId: string,
  limit: number = DEFAULT_QUESTION_LIMIT,
  scopeFilter: TrainingScopeFilter = {}
): Promise<ActionResponse<QuestionSelection>> {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return { ok: false, message: SESSION_EXPIRED_MESSAGE }

  try {
    const data = await selectTrainingQuestions(supabase, subjectId, limit, scopeFilter)
    return { ok: true, data }
  } catch (error) {
    if (error instanceof TrainingValidationError) {
      return { ok: false, message: error.message }
    }
    return { ok: false, message: mapTrainingError(error) }
  }
}
