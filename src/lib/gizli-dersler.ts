/**
 * CURRICULUM-ALL-01 — kullanıcı kararı (2026-10-27): "Geometri/Türkçe kararı"
 *
 - Resmî müfredat yürüyüşü: Geometri içeriği MATEMATİK, Türkçe kapsamı
   TÜRK DİLİ VE EDEBİYATI kaynakları altında yürür (TYMM 2026'da ayrı
   "Geometri" dersi programı yok; ayrı "Türkçe" dersi yalnız ilkokulda var).
 - subjects tablosundaki "Geometri" ve "Türkçe" kayıtları SİLİNMEZ ve
   YENİDEN ADLANDIRILMAZ; bu modül yalnız SEÇİM LİSTELERİNDE gizler.
 - Ön koşul (uygulama öncesi doğrulandı): bu iki dersin veri kullanımı
   SIFIR (question_vaults=0, ai_question_staging=0, topics/outcomes=0,
   P01/P02 paketi yok). Karar, ileride ayrı çalışma kategorileri sunmayı
   engellemez.
 */

export const GIZLENEN_DERS_ADLARI: readonly string[] = ["Geometri", "Türkçe"] as const

/** Ders adı seçim listelerinde gizlenecek mi? (ad birebir eşleşme) */
export function dersGizlenecekMi(dersAdi: string): boolean {
  return GIZLENEN_DERS_ADLARI.includes(dersAdi)
}

/** Liste filtresi: gizlenen dersleri düşürür. */
export function dersListesiniFiltrele<T extends { name: string }>(liste: readonly T[]): T[] {
  return liste.filter((d) => !dersGizlenecekMi(d.name))
}
