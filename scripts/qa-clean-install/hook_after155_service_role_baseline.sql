-- AK-DB-CONSISTENCY-02 — İzole temiz kurulum ÖN-KOŞUL ADIMI #1 (155 uygulandıktan
-- hemen sonra, 156 uygulanmadan önce çalıştırılır).
--
-- NEDEN (kök neden kanıtı):
--   * 156_sec1b_questions_answer_key_hardening.sql:154-156 — fail-closed guard:
--       IF NOT has_table_privilege('service_role','public.questions','SELECT')
--         THEN RAISE 'SEC1B fail-closed: service_role SELECT hakki kaybedildi'
--     Guard, service_role'un questions SELECT yetkisinin 156 SONRASINDA da
--     var olmasini ister. Zincirin kendisi (001-155) bu yetkiyi HIC vermez;
--     155 yalniz "mevcut izin korunur" mantigindadir (155:16).
--   * 157_sec2_schema_privilege_hardening.sql:425-430 — fail-closed guard:
--     service_role SELECT; league_season_close_results + questions +
--     student_league_memberships + leaderboard_entries tablolarinda sart kosar.
--   * Drift denetimi M1: get_internal_correct_answer(uuid) EXECUTE kümesi
--     {postgres, service_role} olmali; canli proacl service_role=X icerir,
--     zincir 155 yalniz "zaten varsa korur" davranisir.
--   CANLIDA NASIL COZULDU: service_role yetkileri cloud-recovery/modul-era
--   doneminde manuel verilmistir (091_comment: "GRANT ALL after live deploy"
--   uygulamasi). Migration dosyalari bu yetkileri hic icermiyordur.
--
-- Guven siniri analizi:
--   * service_role tarayiciya acik rol DEGILDIR (yalniz sunucu/servis anahtari);
--     verilen yetkiler canlida OLCULMUS mevcut ACL'lerin birebir aynasidir.
--   * RLS/politika degismez; bu adim yeni guvenlik siniri TANIMLAMAZ.
-- Idempotent: GRANT tekrarinda hata olusmaz.

\set ON_ERROR_STOP on

-- 156 guard girdisi: service_role.questions (canli olcumuyle birebir yetki kumesi)
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.questions TO service_role;

-- 157:425-430 guard girdisi: lig bakim yolu SELECT'leri (canli olcumu)
GRANT SELECT ON public.league_season_close_results,
                 public.student_league_memberships,
                 public.leaderboard_entries TO service_role;

-- M1 sozlesmesi: 155'in urettigi fonksiyonun service_role EXECUTE'u (canli proacl)
GRANT EXECUTE ON FUNCTION public.get_internal_correct_answer(uuid) TO service_role;

SELECT 'PRE156_BASELINE_OK';
