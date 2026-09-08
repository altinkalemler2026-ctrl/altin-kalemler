import type { GamificationProfile } from "@/lib/gamification/types"

/**
 * Faz 9 — Ana sayfa oyunlaştırma kartı.
 * Yalnız gerçek sunucu değerleri gösterilir; XP, seviye, seri, rozet
 * ve günlük kota ayrı alanlardır. Yarışma puanı, lig rating'i ve
 * yıldız bu kartta GÖSTERİLMEZ (ayrı değerler ayrı yerlerde).
 */
export default function StudentGamification({
  profile,
}: {
  profile: GamificationProfile
}) {
  const { xp, streak, dailyQuota, badges } = profile

  return (
    <section
      aria-labelledby="gamification-heading"
      className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm"
    >
      <h2 id="gamification-heading" className="text-xl font-semibold text-gray-900">
        Gelişimin
      </h2>

      <dl className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="rounded-xl border border-gray-200 p-4">
          <dt className="text-sm font-medium text-gray-500">
            Seviye ve XP
          </dt>
          <dd className="mt-1">
            <span className="text-2xl font-bold text-gray-900">
              {xp.level}. Seviye
            </span>
            <span className="ml-2 text-sm text-gray-600">
              {xp.totalXp} XP
            </span>
            <p className="mt-1 text-sm text-gray-600">
              {xp.nextLevelRequiredTotalXp === null
                ? "Maksimum seviyedesin."
                : `Sonraki seviyeye ${xp.xpToNextLevel} XP kaldı.`}
            </p>
          </dd>
        </div>

        <div className="rounded-xl border border-gray-200 p-4">
          <dt className="text-sm font-medium text-gray-500">Çalışma serisi</dt>
          <dd className="mt-1">
            <span className="text-2xl font-bold text-gray-900">
              {streak.current} gün
            </span>
            <p className="mt-1 text-sm text-gray-600">
              En uzun serin: {streak.longest} gün
            </p>
          </dd>
        </div>

        <div className="rounded-xl border border-gray-200 p-4">
          <dt className="text-sm font-medium text-gray-500">
            Bugünkü soru hakkı
          </dt>
          <dd className="mt-1">
            <span className="text-2xl font-bold text-gray-900">
              {dailyQuota.remaining}
            </span>
            <span className="ml-2 text-sm text-gray-600">
              / {dailyQuota.limit} soru kaldı
            </span>
          </dd>
        </div>

        <div className="rounded-xl border border-gray-200 p-4">
          <dt className="text-sm font-medium text-gray-500">Rozetler</dt>
          <dd className="mt-1">
            {badges.length === 0 ? (
              <p className="text-sm text-gray-600">
                Henüz rozetin yok. İlk doğru cevabınla &quot;İlk
                Adım&quot; rozetini kazanabilirsin.
              </p>
            ) : (
              <ul className="mt-1 flex flex-wrap gap-2">
                {badges.map((badge) => (
                  <li
                    key={badge.badgeCode}
                    className="rounded-full border border-teal-700 bg-teal-50 px-3 py-1 text-sm font-medium text-teal-900"
                  >
                    {badge.name}
                  </li>
                ))}
              </ul>
            )}
          </dd>
        </div>
      </dl>
    </section>
  )
}
