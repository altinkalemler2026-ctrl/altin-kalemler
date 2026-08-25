/**
 * Faz 5 Yarisma UI icin GUVENLI veri transfer tipleri.
 *
 * Bu dosyadaki tipler yalnizca istemciye gidebilir alanlari icerir.
 * Sunucu tarafinda mapper'lar (service.ts) RPC cevabindan bu semaya
 * sikı allowlist ile cevirir; opponent private veri, correct_answer,
 * veya ham DB hatalari bu katmandan ASLA gecmez.
 *
 * GUVENLIK SINIRI:
 *  - Bu dosyada opponentCurrentScore, userId, winnerUserId, players
 *    dizisi veya rakip verisi iceren interface TANIMLANMAZ.
 *  - Raw scoreboard tipi (RawScoreboard) bu dosyada bulunmaz;
 *    yalnizca service.ts icinde private olarak tanimlanir.
 *  - Full scoreboard hicbir exported action response uzerinden
 *    istemciye gonderilmez.
 */

export type QueueStatus = "waiting" | "matched" | "cancelled" | "expired"

export interface MatchResult {
  queueId: string
  competitionId: string
  competitionCode: string
  gradeLevel: number
  subjectId: string
}

export interface QueueJoinResult {
  status: QueueStatus
  queueId: string
  gradeLevel: number
  subjectId: string
  competitionId?: string
  competitionCode?: string
}

export interface QueueLeaveResult {
  cancelled: number
}

export interface CompetitionMatchResult {
  queueId: string
  competitionId: string
  competitionCode: string
  gradeLevel: number
  subjectId: string
}

// ------------------------------------------------------------
// Faz 5b: Yarisma oturumu tipleri
// ------------------------------------------------------------

export type ChoiceLetter = "A" | "B" | "C" | "D" | "E"

export const CHOICE_LETTERS: readonly ChoiceLetter[] = [
  "A",
  "B",
  "C",
  "D",
  "E",
]

/**
 * Guvenli soru icerigi — raw HTML alanlari strip edilmis olarak
 * QuestionRenderer'a gecer. Dogrudan DOM'a HTML eklenmez.
 */
export interface CompetitionQuestion {
  id: string
  questionOrder: number
  sentAt: string
  deadlineAt: string
  stemHtml: string
  options: Partial<Record<ChoiceLetter, string>>
  difficulty: string | null
}

/**
 * Aktif yarisma oturumu durumu (client'a giden guvenli DTO).
 * opponentCurrentScore, players, winnerUserId icERMEZ.
 */
export interface CompetitionSession {
  competitionId: string
  status: string
  currentQuestionOrder: number | null
  totalQuestions: number
  sentAt: string | null
  deadlineAt: string | null
  timeLimitSeconds: number | null
  hasAnsweredCurrentQuestion: boolean
  myCurrentScore: number
  competitionCode: string | null
  competitionType: string | null
}

/**
 * Cevap gonderim sonucu — aktif asamada yalnizca
 * accepted/submissionId/state doner; correct/wrong/pointsAwarded
 * icERMEZ.
 */
export interface AnswerSubmitResult {
  accepted: boolean
  submissionId: string | null
}

/**
 * Kisinin kendi yarisma sonucu — rakip verisi icERMEZ.
 * winnerUserId, players dizisi veya rakip bilgisi bulunmaz.
 */
export interface OwnCompetitionResult {
  competitionId: string
  competitionCode: string
  competitionType: string
  gradeLevel: number
  subjectId: string
  questionCount: number
  resultType: string
  myPlayerSlot: number
  myTotalPoints: number
  myCorrectCount: number
  myWrongCount: number
  myPassCount: number
  myTimeoutCount: number
  myFinishedAt: string | null
  questionResults: Array<{
    questionOrder: number
    difficulty: string
    pointsAwarded: number
    timeMs: number
  }>
  startedAt: string | null
  completedAt: string | null
}
