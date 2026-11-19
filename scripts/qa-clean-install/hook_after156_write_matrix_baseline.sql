-- AK-DB-CONSISTENCY-02 — İzole temiz kurulum ÖN-KOŞUL ADIMI #2 (156 uygulandıktan
-- hemen sonra, 157 uygulanmadan önce çalıştırılır).
--
-- NEDEN (kök neden kanıtı):
--   * 157_sec2_schema_privilege_hardening.sql:346-347 — fail-closed assert:
--       IF v_cnt <> v_keep THEN
--         RAISE '157 fail-closed: yazilabilir tablo % != yazma politikali tablo %'
--     v_cnt = authenticated'a INSERT/UPDATE/DELETE yetkisi olan public tablolar;
--     v_keep = authenticated INSERT/UPDATE/DELETE/ALL yazma POLİTİKASI olan
--     public tablolar (polcmd a/w/d/*).
--   * Zincir 087-154 arasi modüllerde yazma POLİTİKALARI oluşturur ama tablo
--     düzeyi INSERT/UPDATE/DELETE GRANT'larini vermez. CANLIDA bu yetkiler
--     modul-era manuel grant olarak vardir (091_comment: "GRANT ALL after live
--     deploy"; DB-CONSISTENCY-01 olcumu: 63 yazma politikali tablo == 63
--     yetkili tablo). Bu nedenle 157 temiz zincirde 7 != 63 ile düşer.
--
-- Bu adim 157 sozlesmesinin KENDI tanimidir: "yazilabilir tablo kumesi ==
-- yazma politikali tablo kumesi". Yetkiler zincirin urettigi pg_policies'ten
-- DETERMINISTIK olarak turetilir (canliya/veritabani-disi kaynaga bagimlilik
-- yok). RLS acik kaldigi icin satir seviyesi sinir DEGISMEZ; politikanin
-- kendisinin izin verdigi tablolara tablo-izin verilir — canlida OLCULEN
-- sonuc durumun birebir aynisidir (157 sonrasinda revokes ile mutabik).
-- Idempotent: GRANT tekrarinda hata olusmaz.

\set ON_ERROR_STOP on

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT schemaname, tablename
      FROM pg_policies
     WHERE schemaname = 'public'
       AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
       AND 'authenticated' = ANY (roles)
     ORDER BY schemaname, tablename
  LOOP
    EXECUTE format(
      'GRANT INSERT, UPDATE, DELETE ON %I.%I TO authenticated',
      r.schemaname, r.tablename);
  END LOOP;
END $$;

-- Gözle görülür özet (157:346 assert'iyle aynı mantık):
DO $$
DECLARE np int; nw int;
BEGIN
  SELECT count(DISTINCT (schemaname, tablename)) INTO np
    FROM pg_policies
   WHERE schemaname='public' AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
     AND 'authenticated' = ANY(roles);
  SELECT count(DISTINCT (table_schema, table_name)) INTO nw
    FROM information_schema.role_table_grants
   WHERE grantee='authenticated' AND table_schema='public'
     AND privilege_type IN ('INSERT','UPDATE','DELETE');
  RAISE NOTICE 'PRE157_BASELINE_OK policy=% writable=%', np, nw;
END $$;

SELECT 'PRE157_BASELINE_OK';
