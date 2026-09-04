/**
 * Faz 3 Training UI için GÜVENLİ veri transfer tipleri.
 *
 * Bu dosyadaki tipler yalnızca istemciye gidebilir alanları içerir.
 * Sunucu tarafı mapper'lar (service.ts) RPC cevabından bu şemaya
 * sıkı allowlist ile çeviri yapar; correct_answer, solution,
 * explanation, review vb. hassas alanlar bu katmandan ASLA geçmez.
 */

export type ChoiceLetter = "A" | "B" | "C" | "D" | "E"

export const CHOICE_LETTERS: readonly ChoiceLetter[] = [
  "A",
  "B",
  "C",
  "D",
  "E",
]

export function isChoiceLetter(value: unknown): value is ChoiceLetter {
  return (
    typeof value === "string" &&
    (CHOICE_LETTERS as readonly string[]).includes(value)
  )
}

export type AttemptAction = "pass" | "timeout" | "blank"

export const ATTEMPT_ACTIONS: readonly AttemptAction[] = [
  "pass",
  "timeout",
  "blank",
]

export function isAttemptAction(value: unknown): value is AttemptAction {
  return (
    typeof value === "string" &&
    (ATTEMPT_ACTIONS as readonly string[]).includes(value)
  )
}

export interface TrainingSubject {
  id: string
  name: string
  slug: string
}

export interface TrainingQuestion {
  id: string
  questionCode: string | null
  questionText: string | null
  /** A-E seçenek metinleri; olmayan seçenek anahtarı bulunmaz. */
  options: Partial<Record<ChoiceLetter, string>>
  difficulty: string | null
  estimatedSolveTimeSeconds: number | null
  hasVisual: boolean
}

/** Bir ders için haftalık yeni soru kullanım görünümü. */
export interface WeeklyUsageSnapshot {
  academicYear: string | null
  week: number | null
  subjectId: string | null
  newQuestionsUsed: number
  limit: number
}

export interface SubjectWeeklyUsage {
  subjectId: string
  newQuestionsUsed: number
  limit: number
}

export interface WeeklyUsage {
  academicYear: string | null
  week: number | null
  subjects: SubjectWeeklyUsage[]
}

export interface QuestionSelection {
  questions: TrainingQuestion[]
  weekly: WeeklyUsageSnapshot
  /**
   * RPC'nin isteğe bağlı açıklaması; örn. 'sorulabilir_kapsam_bos'.
   * Yalnız bilinen değerler UI'da özel mesaja çevrilir.
   */
  reason: string | null
}

/** list_training_topics satırı — öğrencinin kendi sınıf/dönem kapsamı. */
export interface TrainingTopicOption {
  topicId: string
  topicName: string
}

/** list_training_outcomes satırı — öğrencinin kendi sınıf/dönem kapsamı. */
export interface TrainingOutcomeOption {
  outcomeId: string
  outcomeText: string
}

/** Antrenman kapsam filtresi; konu ve kazanım aynı anda kullanılamaz. */
export interface TrainingScopeFilter {
  topicId?: string
  outcomeId?: string
}

export interface SubmitAnswerInput {
  questionId: string
  /**
   * Her (kullanıcı, soru, deneme) çifti için bir kez üretilen ve ağ
   * yeniden denemelerinde SAKLANAN idempotency anahtarı (UUID v4).
   * Aynı key ile tekrar gönderim DB'de duplicate:true döner.
   */
  clientKey: string
  timeMs: number
  choice?: ChoiceLetter
  action?: AttemptAction
}

export type SubmitOutcome = "correct" | "wrong" | AttemptAction

export interface SubmitResult {
  attemptId: string | null
  attemptNumber: number
  result: SubmitOutcome
  duplicate: boolean
}
