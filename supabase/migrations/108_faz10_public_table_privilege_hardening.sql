-- ============================================================
-- 108_faz10_public_table_privilege_hardening.sql
-- Altin Kalemler - Faz 10B: public tablo ayricalik sertlestirmesi
--
-- AMAC:
--   Faz 10A denetiminde kanitlanan kritik guvenlik aciginin giderilmesi:
--   Supabase bootstrap default ayricaliklari nedeniyle authenticated ve
--   anon rolleri public tablolarin tamamina yakininda TRUNCATE,
--   REFERENCES ve TRIGGER ayricaliklarina sahipti. RLS TRUNCATE'i
--   KORUMAZ; gercek ogrenci oturumuyla student_public_profiles,
--   student_loadouts, student_wallets, student_league_memberships,
--   student_league_history ve leaderboard_entries CASCADE tablolarinin
--   TRUNCATE'i basarili oldu (tum ogrenci/sistem verisi silinebiliyordu).
--
-- SOZLESME:
--   1) Idempotent: tekrar uygulanmasi sonucu degistirmez.
--   2) Fail-closed: sonunda assert edilir; herhangi bir public tabloda
--      hala tehlikeli ayricalik varsa migration EXCEPTION ile duser.
--   3) Tek transaction: BEGIN/COMMIT; ara durum iz birakmaz.
--   4) Kapsam: authenticated + anon rollerinden public tablolarda
--      TRUNCATE / REFERENCES / TRIGGER geri alinir.
--      SELECT/INSERT/UPDATE/DELETE dokunulmaz (kismi bilincli
--      erisimler bozulmaz).
--   5) service_role ve postgres yollarina dokunulmaz.
--   6) RPC-only lig tablolari (leaderboard_entries,
--      student_league_memberships, student_league_history) icin
--      authenticated/anon dogrudan SELECT geri alinir; lig okumasi
--      yalniz get_my_league_ranking allowlist RPC'si uzerinden calisir
--      (kod tabaninda bu tablolara dogrudan istemci erisimi YOKTUR:
--      src altinda yalniz uretilmis tiplerde gecer).
--   7) Gelecek tablolar: ALTER DEFAULT PRIVILEGES FOR ROLE postgres
--      IN SCHEMA public ile yeni tablolar bu ayricaliklari YENIDEN
--      ALMAZ. Tablo olusturan rol, migration zincirinde kanitli olarak
--      yalniz postgres'tir (ana local stack envanteri: 136/136 public
--      tablo sahibi postgres). supabase_admin default ACL'sine
--      dokunulmaz: bu rol migration zincirimizde tablo OLUSTURMAZ ve
--      hosted ortamda postgres rolunun onun default ACL'sini
--      degistirebilmesi kanitlanamaz (yetki hatasi sessizce yutulmaz).
--   8) Event trigger veya superuser bagimli kalici mekanizma eklenmez.
--
-- HOSTED UYUMU:
--   ALTER DEFAULT PRIVILEGES FOR ROLE postgres ... ifadesi hosted
--   Supabase'de migration runner (postgres rol) tarafindan
--   calistirilabilir (kendi rolunun default ACL'si); Supabase
--   dokumanlarindaki standart sertlestirme desenidir.
--
-- Type: FORWARD ONLY. Migration type drift yaratmaz (ACL-only).
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1) Mevcut public tablolarda tehlikeli ayricaliklarin geri alinmasi
-- ------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.oid::regclass AS tbl
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relkind IN ('r', 'p')
  LOOP
    EXECUTE format(
      'REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE %s FROM authenticated',
      r.tbl);
    EXECUTE format(
      'REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE %s FROM anon',
      r.tbl);
  END LOOP;
END;
$$;

-- ------------------------------------------------------------
-- 2) RPC-only lig tablolari: dogrudan SELECT geri alinir
--    (okuma yalniz get_my_league_ranking allowlist RPC'si ile)
-- ------------------------------------------------------------
REVOKE SELECT ON public.leaderboard_entries
  FROM authenticated, anon;
REVOKE SELECT ON public.student_league_memberships
  FROM authenticated, anon;
REVOKE SELECT ON public.student_league_history
  FROM authenticated, anon;

-- ------------------------------------------------------------
-- 3) Faz 10 profil/avatar UI icin minimal fix-forward SELECT
--    grant'leri (066/072/095 oncedili: yeni CLI "no-auto-expose"
--    bootstrap'inda dogustan SELECT verilmeyen tablolar).
--    Uygulama cagri zinciri (kanit):
--      - profile/page.tsx -> fetchOwnProfileSummary ->
--        student_loadouts SELECT (kendi satiri)
--      - profile/page.tsx -> fetchAvatarCatalog -> characters
--        SELECT (aktif katalog)
--    Guvenlik: iki tabloda da RLS ACIK; student_loadouts policy'si
--    yalniz auth.uid() satirini gosterir, characters policy'si
--    yalniz is_active = true satirlari gosterir. Kilitli/pasif
--    karakter metadata'si acilmaz.
-- ------------------------------------------------------------
GRANT SELECT ON public.student_loadouts TO authenticated;
GRANT SELECT ON public.characters TO authenticated;

-- ------------------------------------------------------------
-- 4) Gelecek tablolar: default ayricalik sertlestirmesi
--    Tablo olusturan kanitlanmis rol: postgres (migration runner).
--    Yeni tablolar TRUNCATE/REFERENCES/TRIGGER'i authenticated/anon'a
--    yeniden vermez.
-- ------------------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLES
  FROM authenticated, anon;

-- ------------------------------------------------------------
-- 5) FAIL-CLOSED DOGRULAMA
--    Tek bir public tabloda bile tehlikeli ayricalik kaldiysa
--    migration EXCEPTION ile duser (tum islem geri alinir).
-- ------------------------------------------------------------
DO $$
DECLARE
  v_dangerous integer;
  v_league_open integer;
BEGIN
  SELECT count(*) INTO v_dangerous
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relkind IN ('r', 'p')
     AND (
           has_table_privilege('authenticated', c.oid, 'TRUNCATE')
        OR has_table_privilege('anon', c.oid, 'TRUNCATE')
        OR has_table_privilege('authenticated', c.oid, 'REFERENCES')
        OR has_table_privilege('anon', c.oid, 'REFERENCES')
        OR has_table_privilege('authenticated', c.oid, 'TRIGGER')
        OR has_table_privilege('anon', c.oid, 'TRIGGER')
         );

  IF v_dangerous > 0 THEN
    RAISE EXCEPTION
      'FAZ10B_PRIVILEGE_HARDENING_FAIL: % public tabloda hala TRUNCATE/REFERENCES/TRIGGER ayricaligi var.',
      v_dangerous
      USING errcode = 'P0001';
  END IF;

  SELECT count(*) INTO v_league_open
    FROM (VALUES
      ('public.leaderboard_entries'::regclass),
      ('public.student_league_memberships'::regclass),
      ('public.student_league_history'::regclass)
    ) AS t(oid)
   WHERE has_table_privilege('authenticated', t.oid, 'SELECT')
      OR has_table_privilege('anon', t.oid, 'SELECT');

  IF v_league_open > 0 THEN
    RAISE EXCEPTION
      'FAZ10B_RPC_ONLY_FAIL: RPC-only lig tablolarinda dogrudan SELECT acik (%).',
      v_league_open
      USING errcode = 'P0001';
  END IF;

  IF NOT has_table_privilege('service_role', 'public.league_season_close_results', 'SELECT') THEN
    RAISE EXCEPTION
      'FAZ10B_SERVICE_PATH_FAIL: service_role bakim yolu (league_season_close_results SELECT) bozuldu.'
      USING errcode = 'P0001';
  END IF;

  IF NOT has_table_privilege('authenticated', 'public.student_loadouts', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.characters', 'SELECT') THEN
    RAISE EXCEPTION
      'FAZ10B_UI_GRANT_FAIL: Faz 10 profil/avatar UI SELECT yollari acik degil.'
      USING errcode = 'P0001';
  END IF;
END;
$$;

COMMENT ON TABLE public.leaderboard_entries IS
  'Faz 10B: RPC-only. authenticated/anon dogrudan SELECT kapali; okuma yalniz get_my_league_ranking allowlist RPC''si ile. TRUNCATE/REFERENCES/TRIGGER authenticated/anon''dan geri alindi (108).';

COMMENT ON TABLE public.student_league_memberships IS
  'Faz 10B: RPC-only. authenticated/anon dogrudan SELECT kapali; TRUNCATE/REFERENCES/TRIGGER geri alindi (108).';

COMMENT ON TABLE public.student_league_history IS
  'Faz 10B: RPC-only. authenticated/anon dogrudan SELECT kapali; TRUNCATE/REFERENCES/TRIGGER geri alindi (108).';

COMMIT;
