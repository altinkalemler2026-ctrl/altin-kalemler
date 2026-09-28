-- ============================================================
-- 127_faz30c_competition_scoring_v2_negative_wrong_timeout.sql
-- Altin Kalemler - Faz 30C
--
-- ONAYLI URUN KURALLARI (sadece bu faz icin):
--
--   | Sonuc   | easy | medium | hard  |
--   |----------|------|--------|-------|
--   | correct  | +100 |  +150  | +200  |
--   | wrong    |  -20 |   -30  |  -40  |
--   | timeout  |  -20 |   -30  |  -40  |
--   | pass     |    0 |     0  |     0 |
--
--   - Pas her zaman 0 puandir.
--   - Pas kotasi / pas sayaci / ikinci-pas cezasi / pas odulu
--     TUTULMAZ. Bu migration hicbir sayac, kota veya ceza
--     kolonu EKLEMEZ ve hicbirini degistirmez.
--   - "Cozulemedi" ayri bir answer_result DEGILDIR:
--     yanlis cevap = wrong, cevap vermeme/sure gecmesi =
--     timeout. Mevcut 4 degerli sozluk (correct/wrong/
--     pass/timeout) aynen korunur.
--
-- KAPSAM (yalniz yarisma puani):
--   - Dogru cevap puntari DEGISMEZ (100/150/200).
--   - XP, lig rating, yarisma sonucu, mevcut basari akisi
--     DEGISMEZ. Bu migration XP/rating/sonuc fonksiyonlarina
--     DOKUNMAZ.
--
-- SURUMLEME VE GERIYE DONUK UYUMLULUK:
--   - Yeni kural seti: competition_scoring_v2_negative_wrong_timeout
--     (version = '2').
--   - competition_scoring_v1 KATALOGDA KALIR; yalnizca
--     is_active = FALSE yapilir. Puan satirlari (spr.is_active)
--     DORGU DEGILDIR, dokunulmaz.
--   - Gecmis yarismalar scoring_rule_set_id UUID FK'si ile
--     v1'e baglidir. resolve_competition_points (021:261-329)
--     kural SETINI is_active ile filtrelemez; yalnizca puan
--     satirini (spr.is_active = true) ve gelen rule_set_id
--     UUID'sini kullanir. Bu nedenle v1'i pasiflestirmek
--     GECMIS HESAPLARI DEGISTIREMEZ. Ayni gerekce 094:79-80
--     notu ile de ifade edilmistir.
--   - Gecmis competition_answers / competition_players /
--     competition_results / scoring_snapshot kayitlarina
--     BACKFILL veya RECALCULATE YAPILMAZ (sozlesme 8).
--
-- TEK VARSAYILAN (sozlesme 3):
--   - Yarisma olusturan iki yol da aktif seti secer:
--       079:204-209 ve 082:160-168
--         where srs.is_active = true
--         order by (srs.rule_set_code = 'faz5_default') desc,
--                  srs.created_at asc
--         limit 1
--   - Iki set ayni anda aktif olsaydi OLUSTAN (created_at asc)
--     v1 secilirdi ve v2 DEVRIMYE GIRMEZDI. Bu nedenle
--     migration sonunda TEK aktif set v2 olacak sekilde butun
--     diger aktif setler (v1 dahil) pasiflestirilir.
--   - Boylece "hangi rule_set?" sorusunun tek ve acik cevabi
--     v2'dir; iki yeni yarisma yolu da otomatik olarak v2 alir.
--
-- IDEMPOTENCY (sozlesme 8):
--   - Rule set: on conflict (rule_set_code) do update.
--   - Puan satirlari: 094 ile ayni NOT EXISTS guard'i kullanilir
--     (points degeri de esitlik kosuluna dahil). Tekrar
--     calistirma duplicate URETMEZ.
--   - Aktif set pasiflestirme idempotenttir.
--   - Migration veri sIFIRLAMAZ; tekrar uygulanabilir.
--
-- GUVENLIK:
--   - scoring_rule_sets / scoring_point_rules istemci rollerine
--     KAPALI kalir; acik REVOKE tekrarlanir (savunma derinligi,
--     094 ile ayni yaklasim, yeni grant YOK).
--
-- SINIR DEGERLERI:
--   - Tek soru araligi: -40 .. +200.
--   - 5 soruluk yarisma toplami: -200 .. +1000.
--   - competition_players.total_points (019:359) ve
--     competition_answers.points_awarded (019:511) uzerinde
--     CHECK (>= 0) YOKTUR; negatif deger kabul edilir.
--     015:140-141'deki student_public_profiles.total_points
--     CHECK'i yarisma puani YAZMAZ (tek yazici 107:153'te
--     avatar guncellemesidir) ve bu migration ona dokunmaz.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Versioned V2 kural seti
-- ------------------------------------------------------------
INSERT INTO public.scoring_rule_sets
  (rule_set_code, name, description, version, is_active)
VALUES
  ('competition_scoring_v2_negative_wrong_timeout',
   'Yarisma Puanlama Sozlesmesi V2 (Negatif Wrong/Timeout)',
   'Sunucu-otoriter yarisma performans puani V2: correct=100/150/200, wrong/timeout=-20/-30/-40, pass=0. Pas her zaman 0 puandir; pas kotasi, pas sayaci, ikinci-pas cezasi ve pas odulu yoktur. Cozulemedi ayri bir sonuc degildir.',
   '2',
   TRUE)
ON CONFLICT (rule_set_code) DO UPDATE
SET
  name        = EXCLUDED.name,
  description = EXCLUDED.description,
  version     = EXCLUDED.version,
  is_active   = TRUE;

-- ------------------------------------------------------------
-- 2. Fallback (band_code IS NULL) puan satirlari
--    12 sinif x 3 zorluk x 4 sonuc = 144 satir.
--    NOT EXISTS guard: tekrar calistirmada duplicate yok.
--
--    Puan ifadesi (V1 ile ayni kalip, negatifli):
--      correct            -> 100 / 150 / 200
--      wrong, timeout     -> -20 / -30 / -40
--      pass               -> 0
--
--    NOT: v1 kural satirlarina HIC dokunulmaz; v1'in
--    puanlari 100/150/200 ve 0 olarak KALIR.
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
    WHEN r.answer_result = 'correct' THEN
      CASE d.difficulty
        WHEN 'easy'   THEN 100
        WHEN 'medium' THEN 150
        WHEN 'hard'   THEN 200
      END
    WHEN r.answer_result IN ('wrong', 'timeout') THEN
      CASE d.difficulty
        WHEN 'easy'   THEN -20
        WHEN 'medium' THEN -30
        WHEN 'hard'   THEN -40
      END
    WHEN r.answer_result = 'pass' THEN 0
  END,
  TRUE
FROM public.scoring_rule_sets srs
CROSS JOIN (VALUES (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12))
     AS g(grade_level)
CROSS JOIN (VALUES ('easy'), ('medium'), ('hard'))
     AS d(difficulty)
CROSS JOIN (VALUES ('correct'), ('wrong'), ('pass'), ('timeout'))
     AS r(answer_result)
WHERE srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'
  AND NOT EXISTS (
    SELECT 1
    FROM public.scoring_point_rules e
    WHERE e.rule_set_id = srs.id
      AND e.grade_level = g.grade_level
      AND e.difficulty = d.difficulty
      AND e.answer_result = r.answer_result
      AND e.band_code is null
      AND e.is_active = true
      AND e.points = CASE
            WHEN r.answer_result = 'correct' THEN
              CASE d.difficulty
                WHEN 'easy'   THEN 100
                WHEN 'medium' THEN 150
                WHEN 'hard'   THEN 200
              END
            WHEN r.answer_result IN ('wrong', 'timeout') THEN
              CASE d.difficulty
                WHEN 'easy'   THEN -20
                WHEN 'medium' THEN -30
                WHEN 'hard'   THEN -40
              END
            WHEN r.answer_result = 'pass' THEN 0
          END
  );

-- ------------------------------------------------------------
-- 3. TEK AKTIF VARSAYILAN
--    v1 dahil butun diger aktif setler pasiflestirilir; boylece
--    079/082'nin "is_active = true ... limit 1" secimi
--    belirsizligi olmadan v2'yi secer.
--    Gecmis yarismalar UUID FK ile v1'e bagli kaldigi icin bu
--    islem hesaplarina dokunmaz (baskca bkz. dosya basi).
-- ------------------------------------------------------------
UPDATE public.scoring_rule_sets
   SET is_active = FALSE
 WHERE rule_set_code <> 'competition_scoring_v2_negative_wrong_timeout'
   AND is_active = TRUE;

-- ------------------------------------------------------------
-- 4. Yetki sertlestirme (savunma derinligi; yeni grant YOK)
-- ------------------------------------------------------------
REVOKE ALL
  ON public.scoring_rule_sets
  FROM anon, authenticated;

REVOKE ALL
  ON public.scoring_point_rules
  FROM anon, authenticated;

COMMIT;
