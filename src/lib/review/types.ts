/**
 * Faz 6 — Hedefli Tekrar ve Kazanım Analitiği için GÜVENLİ veri
 * transfer tipleri.
 *
 * Bu dosyadaki tipler yalnızca istemciye gidebilir alanları içerir.
 * service.ts mapper'ları RPC cevabından bu şemaya sıkı allowlist ile
 * çeviri yapar; PII ve soru gizli alanları (correct_answer, solution,
 * explanation, review vb.) bu katmandan ASLA geçmez.
 *
 * Sabitler SABİT ürün kararlarıdır (docs/project/faz6-tasarim.md);
 * DB tarafındaki 098 eşikleriyle birebir aynıdır.
 */

import type { TrainingQuestion, WeeklyUsageSnapshot } from "@/lib/training/types"

/** 098 get_outcome_review_plan band değerleri. */
export type OutcomeBand =
  | "weak"
  | "developing"
  | "strong"
  | "insufficient_data"

export const OUTCOME_BANDS: readonly OutcomeBand[] = [
  "weak",
  "developing",
  "strong",
  "insufficient_data",
]

export function isOutcomeBand(value: unknown): value is OutcomeBand {
  return (
    typeof value === "string" &&
    (OUTCOME_BANDS as readonly string[]).includes(value)
  )
}

/**
 * Tekrar etkisi ölçümü için gereken minimum payda (pending + redeemed).
 * Payda bu değerin altındaysa redeem_rate NULL döner ve UI yüzde
 * GÖSTERMEZ (yanıltıcı yüzde engellenir; açıklayıcı durum metni var).
 */
export const MIN_REDEEM_EVIDENCE = 5

/** Tekrar etkisi özet satırı — kazanım bazında analitik. */
export interface OutcomeReviewRow {
  outcomeId: string
  outcomeText: string
  /** weak | developing | strong | insufficient_data */
  band: OutcomeBand
  totalAttempts: number
  /** Yetersiz veride NULL — UI yüzde göstermez. */
  successRate: number | null
  repeatTotal: number
  /** 085 konvansiyonu: tekrar yoksa 0. */
  repeatSuccessRate: number
  /** En son training denemesi 'correct' olmayan soru sayısı. */
  pendingErrors: number
  /** Önce başarısız → sonra 'correct' telafi edilen soru sayısı. */
  redeemed: number
  /** redeemed/(redeemed+pending); payda < 5 ise NULL. */
  redeemRate: number | null
  /** Outcome'daki training fact'lerindeki en güncel deneme (ISO). */
  lastReviewedAt: string | null
}

/** select_targeted_review_questions oturum kind sabiti. */
export const TARGETED_REVIEW_SESSION_KIND = "targeted_review"

/**
 * RPC reason değerleri:
 *  - gecersiz_kapsam: outcome, öğrencinin dönem kapsamında değil
 *    (fail-closed; kapsam dışı veri sızmaz).
 *  - tekrar_gerekmiyor: hata havuzu boş (pozitif kapanış; açıklayıcı
 *    durum).
 *  - gunluk_kota_doldu: günlük 500 soru hakkı tüklendi (Faz 9;
 *    soru teslim edilmez).
 */
export type TargetedReviewReason =
  | "gecersiz_kapsam"
  | "tekrar_gerekmiyor"
  | "gunluk_kota_doldu"

export const TARGETED_REVIEW_REASONS: readonly TargetedReviewReason[] = [
  "gecersiz_kapsam",
  "tekrar_gerekmiyor",
  "gunluk_kota_doldu",
]

export function isTargetedReviewReason(
  value: unknown
): value is TargetedReviewReason {
  return (
    typeof value === "string" &&
    (TARGETED_REVIEW_REASONS as readonly string[]).includes(value)
  )
}

/** Tekrar oturumu seçim sonucu (soru listesi 096 payload şeması). */
export interface TargetedReviewSelection {
  questions: TrainingQuestion[]
  sessionKind: string
  outcomeId: string
  /** Hata havuzundan gelen (cooldown dışı bekleyen yanlış) soru sayısı. */
  wrongReviewCount: number
  /** Havuz doldurulamadıysa eklenen yeni soru sayısı. */
  newCount: number
  reason: TargetedReviewReason | null
  weekly: WeeklyUsageSnapshot
}

/** Tekrar oturumu p_limit aralığı (SABİT ürün kararı: 1..10, default 5). */
export const MIN_REVIEW_LIMIT = 1
export const MAX_REVIEW_LIMIT = 10
export const DEFAULT_REVIEW_LIMIT = 5

export function clampReviewLimit(limit: number): number {
  if (!Number.isFinite(limit)) return DEFAULT_REVIEW_LIMIT
  const rounded = Math.round(limit)
  return Math.min(MAX_REVIEW_LIMIT, Math.max(MIN_REVIEW_LIMIT, rounded))
}
