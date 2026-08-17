/**
 * Uygulama sabitleri
 */

// Eğitim kademeleri
export const KADEME = {
  ILKOKUL: 'ilkokul',
  ORTAOKUL: 'ortaokul',
  LISE: 'lise',
} as const

// Sınıf seviyeleri
export const GRADE_LEVELS = {
  ILKOKUL: [1, 2, 3, 4],
  ORTAOKUL: [5, 6, 7, 8],
  LISE: [9, 10, 11, 12],
} as const

// Zorluk seviyeleri
export const DIFFICULTY = {
  EASY: 'easy',
  MEDIUM: 'medium',
  HARD: 'hard',
} as const

// Soru onay durumu
export const APPROVAL_STATUS = {
  PENDING_REVIEW: 'pending_review',
  APPROVED: 'approved',
  REJECTED: 'rejected',
} as const

// Yarışma durumu
export const COMPETITION_STATUS = {
  WAITING: 'waiting',
  ACTIVE: 'active',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
} as const

// Süre bantları
export const TIME_BANDS = {
  MUKEMMEL: 'mukemmel',
  IYI: 'iyi',
  ORTA: 'orta',
  KOTU: 'kotu',
} as const

// Kozmetik eşya tipleri
export const ITEM_TYPES = {
  SHOES: 'shoes',
  CAPE: 'cape',
  TSHIRT: 'tshirt',
  SHORTS: 'shorts',
} as const

// Abonelik durumu
export const SUBSCRIPTION_STATUS = {
  ACTIVE: 'active',
  CANCELLED: 'cancelled',
  EXPIRED: 'expired',
  PAUSED: 'paused',
} as const

// Plan billing interval
export const BILLING_INTERVAL = {
  FREE: 'free',
  MONTHLY: 'monthly',
  YEARLY: 'yearly',
} as const
