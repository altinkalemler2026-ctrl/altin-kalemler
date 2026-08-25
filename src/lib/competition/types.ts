/**
 * Faz 5 Yarisma UI icin GUVENLI veri transfer tipleri.
 *
 * Bu dosyadaki tipler yalnizca istemciye gidebilir alanlari icerir.
 * Sunucu tarafinda mapper'lar (service.ts) RPC cevabindan bu semaya
 * sikı allowlist ile cevirir; opponent private veri, correct_answer,
 * veya ham DB hatalari bu katmandan ASLA gecmez.
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
