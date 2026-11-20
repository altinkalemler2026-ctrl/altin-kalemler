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

/** 084 get_own_matchmaking_status durumları. */
export type OwnMatchmakingStatusValue =
  | "not_queued"
  | "waiting"
  | "matched"

/**
 * 084 get_own_matchmaking_status cevabi — kullanıcının KENDİ kuyruk
 * durumu. Rakip verisi icERMEZ; competition bilgileri yalnizca
 * matched durumunda ve yalnizca kullanici katilimciysa doner.
 */
export interface OwnMatchmakingStatus {
  status: OwnMatchmakingStatusValue
  competitionId: string | null
  competitionCode: string | null
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
 * Yarisma sonucu ogrencinin KENDİ sonucu — 099 my_result alanı.
 * winnerUserId ham değeri ASLA taşınmaz; sunucu tarafında türetilir.
 */
export type OwnCompetitionOutcome =
  | "win"
  | "loss"
  | "draw"
  | "forfeit_win"
  | "forfeit_loss"
  | "no_contest"

// ------------------------------------------------------------
// 163: Haftalık öğrenci kotası DTO'su
// ------------------------------------------------------------

/** Bir yarışma paketi için gereken soru sayısı (163 sözleşmesi: 5 soru). */
export const QUESTIONS_PER_COMPETITION = 5

/**
 * 163 weekly_quota_status() RPC cevabi — ogrencinin KENDİ haftalik durumu.
 * academicYear === null "gecerli akademik donem yok" demektir (teknik
 * durum): UI bu durumda kota sayisi GOSTERMEZ ve butonu kilitlemez;
 * fail-closed koruma sunucudadir.
 */
export interface WeeklyQuotaStatus {
  academicYear: string | null
  week: number | null
  competitionsUsed: number
  competitionsLimit: number
  newQuestionsUsed: number
  newQuestionsLimit: number
}

/** Hafta icinde kalan yarisma hakki. */
export function weeklyQuotaCompetitionsRemaining(q: WeeklyQuotaStatus): number {
  return Math.max(0, q.competitionsLimit - q.competitionsUsed)
}

/** Hafta icinde kalan yeni soru hakki. */
export function weeklyQuotaNewQuestionsRemaining(q: WeeklyQuotaStatus): number {
  return Math.max(0, q.newQuestionsLimit - q.newQuestionsUsed)
}

/**
 * Istemci tarafi katilim kilidi kontrolu (YALNIZ UX — güvenlik siniri
 * 163 sunucu tetikleri ve RPC'lerinde kalmalidir). Haftalik kota
 * tukendiyse (40 yarisma) veya bes yeni soruluk paket icin yeterli
 * yeni soru hakki kalmadiysa true. Teknik durumda (donem yok / veri
 * yok) kilitlemez; sunucu hatalari errors.ts uzerinden ayristirilir.
 */
export function weeklyQuotaBlocksJoin(q: WeeklyQuotaStatus | null): boolean {
  if (!q || q.academicYear === null) return false
  if (q.competitionsUsed >= q.competitionsLimit) return true
  return weeklyQuotaNewQuestionsRemaining(q) < QUESTIONS_PER_COMPETITION
}

// ------------------------------------------------------------
// 165: Ders bazlı haftalık kota DTO'su (AK-QUOTA-SUBJECT-01)
// ------------------------------------------------------------

/**
 * 165 weekly_quota_status_per_subject() RPC'sinin DERS bazlı durumu.
 * Kanonik ders kimliği subject_id (public.subjects.id).
 */
export interface SubjectWeeklyQuotaStatus {
  subjectId: string
  competitionsUsed: number
  competitionsLimit: number
  newQuestionsUsed: number
  newQuestionsLimit: number
}

/**
 * 165 RPC'nin tam yanıtı — öğrencinin KENDİ haftalık ders bazlı durumu.
 * academicYear === null "gecerli akademik donem yok" demektir (teknik
 * durum): UI bu durumda kota sayisi GOSTERMEZ ve buton kilitlemez;
 * fail-closed koruma sunucudadir.
 */
export interface SubjectWeeklyQuotaSnapshot {
  academicYear: string | null
  week: number | null
  subjects: SubjectWeeklyQuotaStatus[]
}

/** Derste hafta icinde kalan yarisma hakki. */
export function subjectQuotaCompetitionsRemaining(
  q: SubjectWeeklyQuotaStatus
): number {
  return Math.max(0, q.competitionsLimit - q.competitionsUsed)
}

/** Derste hafta icinde kalan yeni soru hakki. */
export function subjectQuotaNewQuestionsRemaining(
  q: SubjectWeeklyQuotaStatus
): number {
  return Math.max(0, q.newQuestionsLimit - q.newQuestionsUsed)
}

/**
 * Ders bazli katilim kilidi kontrolu (YALNIZ UX — guvenlik siniri 165
 * sunucu tetikleri ve RPC'lerinde kalmalidir). YALNIZ ILGILI ders
 * kapanir; diger ders kartlari etkilenmez (ürün karari 10).
 * Veri yoksa (RPC hatasi / ders kaydi yeni) KILITLEMEZ; sunucu
 * KOTA_165 ile gercek kapidayi zaten vurur.
 */
export function subjectQuotaBlocksJoin(
  q: SubjectWeeklyQuotaStatus | null
): boolean {
  if (!q) return false
  if (q.competitionsUsed >= q.competitionsLimit) return true
  return subjectQuotaNewQuestionsRemaining(q) < QUESTIONS_PER_COMPETITION
}

/**
 * Kisinin kendi yarisma sonucu — rakip verisi icERMEZ.
 * winnerUserId, players dizisi veya rakip bilgisi bulunmaz.
 * Soru bazında yalnizca KENDİ answer_result/submitted_answer bulunur;
 * doğru cevap veya rakibin cevabı ASLA bulunmaz (099 sözleşmesi).
 */
export interface OwnCompetitionResult {
  competitionId: string
  competitionCode: string
  competitionType: string
  gradeLevel: number
  subjectId: string
  questionCount: number
  resultType: string
  myResult: OwnCompetitionOutcome
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
    answerResult: string
    submittedAnswer: string | null
  }>
  startedAt: string | null
  completedAt: string | null
}
