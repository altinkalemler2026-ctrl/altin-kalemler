/**
 * 165 ders bazli kota aktivasyon bayragi (AK-QUOTA-SUBJECT-01).
 *
 * AKTIVASYON SIRASI (/ayrisiz):
 *  1. Migration 165 canliya uygulanir (ayrica kullanici onayi gerekir).
 *  2. QUOTA_PER_SUBJECT_ENABLED=1 set edilir ve uygulama yeniden dagitilir.
 *
 * 165 uygulanimis ama bayrak KAPALI ise: eski weekly_quota_status()
 * artik KOTA_165_DEPRECATED firlatir; getWeeklyQuotaStatus hata yakalar,
 * banner hicbir sayi uydurmadan kendisini gizler ve butonlar acik kalir
 * (gercek kapilar sunucu tetiklerindedir). Bu gecide urun akisi bozulmaz.
 *
 * Bayrak KAPALI iken (varsayilan) arayuz 163 kuresel davranisiyla
 * birebir aynen kalir — migration yayinina kadar guvenli kapali.
 *
 * Sunucu tarafi: yalniz server component / service katmani okur;
 * NEXT_PUBLIC_* degildir (istemciye sizmaz).
 */
export function isSubjectQuotaEnabled(
  env: Record<string, string | undefined> = process.env
): boolean {
  const value = env.QUOTA_PER_SUBJECT_ENABLED
  return value === "1" || value === "true"
}
