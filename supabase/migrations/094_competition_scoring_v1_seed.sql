-- ============================================================
-- 094_competition_scoring_v1_seed.sql
-- Altın Kalemler - Yarışma puanlama sözleşmesi V1 (seed)
--
-- PROBLEM:
--   021'teki puan çözümleyici (resolve_competition_points) puanı
--   yalnızca scoring_point_rules satırlarından bulur; satır yoksa
--   COALESCE(..., 0) ile sessizce 0 döner. Migration zincirinde
--   hiçbir puan kuralı seed'i bulunmadığı için temiz bir
--   veritabanında bütün yarışma cevapları 0 puan alır.
--
-- ÇÖZÜM (V1):
--   1) Versioned, tek-aktif kural seti: 'competition_scoring_v1'.
--      - 079/082'deki kurulum seçicisi yalnız AKTIF setler
--        arasından seçer (faz5_default tercihli). faz5_default
--        pasife çekilerek temiz DB'de tam bir aktif set garantisi
--        sağlanır (çoklu-aktif belirsizliği engellenir).
--   2) Puan matrisi V1 (kullanıcı onaylı) — yalnız fallback
--      (band_code IS NULL) satırları seed edilir:
--        doğru : easy=100, medium=150, hard=200
--        wrong / pass / timeout = 0
--   3) Süre bandı katmanı: Şemada onaylı hiçbir süre bandı
--      seed'i yoktur ve kaynaktek keyfi-ms sözleşmesi bulunmaz.
--      Bu nedenle keyfi milisaniyeli bantlar UYDURULMAZ; bantlı
--      (Normal/Hızlı) matris değerleri (120/150/225, 150/180/225,
--      200/240/300) onaylı bantlar tanımlandığında eklenecek
--      ayrılmış değerlerdir. Bant bulunamayan doğru cevap
--      fallback (temel) puanını alır — 021'in mevcut fail-closed
--      davranışı korunur.
--
-- KORUNAN SÖZLEŞMELER:
--   - Puan yalnız sunucuda hesaplanır (021); istemci puan/süre/
--     doğruluk/zorluk gönderemez.
--   - Lig rating (+24/-12/0, 078) bu seed'den bağımsızdır ve
--     değişmez.
--   - Yarışma puanı XP veya harcanabilir para değildir; wallet/
--     badge/avatar/mağaza tablolarına dokunulmaz.
--   - Geçmiş competition_results/scoring_snapshot kayıtları
--     yeniden hesaplanmaz; bu seed yalnız GELECEK yarışmaları
--     etkiler.
--   - Yarışma puanı negatif olamaz; tek soru üst sınırı (bantlı
--     matrisin tamamı devredeyken) 300'dür; seed edilen en yüksek
--     değer 200'dür (fallback).
--
-- IDEMPOTENCY:
--   - Rule set: on conflict (rule_set_code) do update.
--   - Puan satırları: scoring_point_rules üzerinde semantik
--     unique kısıt olmadığı için her satır NOT EXISTS guard'ı
--     ile insert edilir; tekrar çalıştırma duplicate üretmez.
--   - faz5_default pasifleştirme idempotenttir.
--
-- GÜVENLİK:
--   - scoring_rule_sets / scoring_point_rules istemci rollerine
--     kapalıdır; savunma derinliği için açık REVOKE tekrarlanır
--     (yeni grant YOK). RPC zinciri SECURITY DEFINER olarak
--     sahibi üzerinden okur.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Versioned V1 kural seti (tek aktif varsayılan)
-- ------------------------------------------------------------
INSERT INTO public.scoring_rule_sets
  (rule_set_code, name, description, version, is_active)
VALUES
  ('competition_scoring_v1',
   'Yarışma Puanlama Sözleşmesi V1',
   'Sunucu-otoriter yarışma performans puanı V1: doğru=100/150/200 (fallback), diğer sonuçlar 0. Bantlı matris onaylı süre bantlarıyla genişletilecek.',
   '1',
   TRUE)
ON CONFLICT (rule_set_code) DO UPDATE
SET
  name        = EXCLUDED.name,
  description = EXCLUDED.description,
  version     = EXCLUDED.version,
  is_active   = TRUE;

-- Tek aktif varsayılan garantisi: eski varsayılan set pasife
-- çekilir. Mevcut yarışmaların FK referansları etkilenmez.
UPDATE public.scoring_rule_sets
   SET is_active = FALSE
 WHERE rule_set_code = 'faz5_default'
   AND is_active = TRUE;

-- ------------------------------------------------------------
-- 2. Fallback (band_code IS NULL) puan satırları
--    12 sınıf x 3 zorluk x 4 sonuç = 144 satır.
--    NOT EXISTS guard: tekrar çalıştırmada duplicate yok.
-- ------------------------------------------------------------
INSERT INTO public.scoring_point_rules
  (rule_set_id, grade_level, difficulty, answer_result, band_code, points, is_active)
SELECT
  srs.id,
  g.grade_level,
  d.difficulty,
  r.answer_result,
  NULL::text,
  CASE
    WHEN r.answer_result <> 'correct' THEN 0
    WHEN d.difficulty = 'easy'   THEN 100
    WHEN d.difficulty = 'medium' THEN 150
    WHEN d.difficulty = 'hard'   THEN 200
  END,
  TRUE
FROM public.scoring_rule_sets srs
CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) AS g(grade_level)
CROSS JOIN (VALUES ('easy'),('medium'),('hard'))                        AS d(difficulty)
CROSS JOIN (VALUES ('correct'),('wrong'),('pass'),('timeout'))          AS r(answer_result)
WHERE srs.rule_set_code = 'competition_scoring_v1'
  AND NOT EXISTS (
    SELECT 1
      FROM public.scoring_point_rules existing
     WHERE existing.rule_set_id   = srs.id
       AND existing.grade_level   = g.grade_level
       AND existing.difficulty    = d.difficulty
       AND existing.answer_result = r.answer_result
       AND existing.band_code IS NULL
       AND existing.points = CASE
         WHEN r.answer_result <> 'correct' THEN 0
         WHEN d.difficulty = 'easy'   THEN 100
         WHEN d.difficulty = 'medium' THEN 150
         WHEN d.difficulty = 'hard'   THEN 200
       END
       AND existing.is_active = TRUE
  );

-- ------------------------------------------------------------
-- 3. Yetki sertleştirmesi (savunma derinliği; yeni grant YOK)
--    Kural tabloları yalnız sunucu-içi SECURITY DEFINER
--    zinciri tarafından okunur.
-- ------------------------------------------------------------
REVOKE ALL ON TABLE public.scoring_rule_sets  FROM anon, authenticated;
REVOKE ALL ON TABLE public.scoring_point_rules FROM anon, authenticated;

COMMENT ON TABLE public.scoring_point_rules IS
  'V1 (094): yarisma performans puani. Yalniz sunucu okur; ogrenci/anon yazma ve okuma yetkisi YOKTUR. Fallback (band_code NULL): correct easy=100/medium=150/hard=200, diger sonuclar 0. Bantli matris (120/150/225, 150/180/225, 200/240/300) onayli sure bantlariyla eklenecek ayrilmis degerlerdir.';

COMMIT;
