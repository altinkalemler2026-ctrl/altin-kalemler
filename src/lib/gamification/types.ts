/**
 * Faz 9 oyunlaştırma DTO'ları — YALNIZ gerçek değerler.
 *
 * Sözleşme (103/104 migration + kullanıcı onayı):
 *  - XP, kişisel seviye, seri, rozet ve günlük kota AYRI değerlerdir;
 *    yarışma puanı, lig rating'i ve yıldız bu modüle girmez.
 *  - Seviye sunucuda toplam XP'den hesaplanır; istemciden kabul edilmez.
 *  - DTO alanları sunucu RPC'sinin (get_own_gamification_profile)
 *    sıkı allowlist eşleyicisinden geçer; bilinmeyen alan düşürülür.
 */

export interface GamificationXp {
  totalXp: number
  level: number
  maxLevel: number
  /** Sonraki seviye için gereken toplam XP; maksimum seviyede null. */
  nextLevelRequiredTotalXp: number | null
  /** Sonraki seviyeye kalan XP; maksimum seviyede null. */
  xpToNextLevel: number | null
}

export interface GamificationStreak {
  current: number
  longest: number
  lastActivityDay: string | null
}

export interface DailyQuota {
  day: string | null
  questionsUsed: number
  limit: number
  remaining: number
}

export interface GamificationBadge {
  badgeCode: string
  name: string
  grantedAt: string | null
}

export interface GamificationProfile {
  xp: GamificationXp
  streak: GamificationStreak
  dailyQuota: DailyQuota
  badges: GamificationBadge[]
}
