-- ============================================================
-- 166_student_profile_write_convergence.sql
-- AK-SEC-GRADE-01 — GAP-SEC-01 onarimi (kaynak:
--   docs/reports/ak-git-checkpoint-03-legacy-qa-ci-regresyon.md §3)
--
-- KOK NEDEN:
--   093 ogrenci profil yazimasini kolon ayricaigina cevirir:
--   tablo-seviyeli UPDATE revoked, yalniz GRANT UPDATE (nickname).
--   Ancak 157 §C sozlesmesi ("yazilabilir tablo kumesi == yazma
--   politikali tablo kumesi") ve 157 §6 guard'i
--   has_table_privilege('authenticated','student_profiles','UPDATE')
--   ister; PostgreSQL'de KOLON yetkisi bu kontrolu KARSILAMAZ
--   (olcumle dogrulandi). Bu yuzden temiz kurulum on-kosul adimi
--   (scripts/qa-clean-install/hook_after156_write_matrix_baseline.sql)
--   157'den ONCE tum yazma politikali tablolarda tablo-genel
--   INSERT/UPDATE/DELETE verir. Sonuc:
--     * student_profiles tablo-genel UPDATE dirulur; update_own RLS
--       politikasi yalniz SATIR sinirlar -> ogrenci kendi
--       grade_level degerini degistirebilir (sinif kapisi baypasi).
--     * student_loadouts 108 sozlesmesi (authenticated = SELECT only,
--       yazma yalniz SECURITY DEFINER RPC) INSERT/UPDATE/DELETE ile
--       delinir (095 RPC-only siniri ihlali).
--   Ayni ihlal CANLIDA da olculdu (modul-donemi manuel GRANT ALL
--   mirasi + kolon düzeyinde fazladan UPDATE(grade_level) drift'i).
--
-- COZUM — POST-KONVERJANS (FORWARD ONLY):
--   Hook kaldirilamaz (157 §6 hook'suz zinciri kirar); zincirin
--   KENDISININ istedigi fail-closed sozlesmeye (<=131 yesil durumu)
--   zincir SONUNDA konverje edilir:
--     student_profiles : authenticated = SELECT, INSERT
--                        + UPDATE (nickname) kolon ayricaigi
--                        (tablo UPDATE/DELETE yok; RLS update_own
--                        satir kapsami korunur, kolon kapsami artik
--                        ayricaigdir)
--     student_loadouts : authenticated = SELECT yalniz (108);
--                        yazma yalniz RPC (107 select_own_avatar)
--   RLS politikasi yalniz SECIME indirgenir: loadouts'un 017 donemi
--   INSERT/UPDATE politikari kaldirilir (hook tohumu — bkz. 4b);
--   157 §6 guard'i ve hook sozlesmesine DOKUNULMAZ; 157 bu dosyadan
--   once kosar ve kendi adiminda hook grant'iyle zaten gecer.
--   service_role / tablo sahibi yonetim yollari degismez.
--
-- IDEMPOTENT: REVOKE/GRANT yalniz ACL'de olculen hedefe uygulanir.
-- FAIL-CLOSED: sonunda sozlesme assert edilir; sapma varsa zincir
-- durur. Migration type: FORWARD ONLY; gecmis dosyalar degismez.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1) student_profiles: tablo-genel UPDATE/DELETE geri aliniyor
--    (authenticated + anon). Kolon ayricalarlari AYRI ACL
--    kayitlaridir; tablo duzeyi REVOKE onlari silmez.
-- ------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT pg_get_userbyid(x.grantee) AS rol, x.privilege_type
      FROM aclexplode(
             (SELECT relacl FROM pg_class
               WHERE oid = 'public.student_profiles'::regclass)
           ) x
     WHERE x.privilege_type IN ('UPDATE','DELETE')
       AND x.grantee IN ('authenticated'::regrole, 'anon'::regrole)
  LOOP
    EXECUTE format(
      'REVOKE %s ON TABLE public.student_profiles FROM %I',
      r.privilege_type, r.rol);
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- 2) student_profiles kolon yazma allow-list'i: nickname/UPDATE/
--    authenticated disinda hicbir kolon yazma kaydi kalamaz
--    (canli drift'i UPDATE(grade_level) dahil).
-- ------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT a.attname,
           pg_get_userbyid(x.grantee) AS rol,
           x.privilege_type
      FROM pg_attribute a
     CROSS JOIN LATERAL aclexplode(a.attacl) x
     WHERE a.attrelid = 'public.student_profiles'::regclass
       AND a.attnum > 0 AND NOT a.attisdropped
       AND x.grantee IN ('authenticated'::regrole, 'anon'::regrole)
       AND x.privilege_type IN ('INSERT','SELECT','UPDATE','REFERENCES')
       AND x.privilege_type <> 'SELECT'  -- kolon SELECT hijyeni 157 kapsaminda
       AND NOT (a.attname = 'nickname'
                AND x.grantee = 'authenticated'::regrole
                AND x.privilege_type = 'UPDATE')
  LOOP
    EXECUTE format(
      'REVOKE %s (%I) ON TABLE public.student_profiles FROM %I',
      r.privilege_type, r.attname, r.rol);
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- 3) Meşru ogrenci alan iadesi (idempotent; 093 allow-list'i).
-- ------------------------------------------------------------
GRANT UPDATE (nickname) ON TABLE public.student_profiles TO authenticated;

-- ------------------------------------------------------------
-- 4) student_loadouts: 108 sozlesmesine donus — authenticated/anon
--    tablo duzeyi I/U/D + kolon yazma kayitlari sifirlanir
--    (yazma yalniz SECURITY DEFINER RPC: 107 select_own_avatar).
--    SELECT yollari (108 UI) aynen kalir.
-- ------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT pg_get_userbyid(x.grantee) AS rol, x.privilege_type
      FROM aclexplode(
             (SELECT relacl FROM pg_class
               WHERE oid = 'public.student_loadouts'::regclass)
           ) x
     WHERE x.privilege_type IN ('INSERT','UPDATE','DELETE')
       AND x.grantee IN ('authenticated'::regrole, 'anon'::regrole)
  LOOP
    EXECUTE format(
      'REVOKE %s ON TABLE public.student_loadouts FROM %I',
      r.privilege_type, r.rol);
  END LOOP;

  FOR r IN
    SELECT a.attname,
           pg_get_userbyid(x.grantee) AS rol,
           x.privilege_type
      FROM pg_attribute a
     CROSS JOIN LATERAL aclexplode(a.attacl) x
     WHERE a.attrelid = 'public.student_loadouts'::regclass
       AND a.attnum > 0 AND NOT a.attisdropped
       AND x.grantee IN ('authenticated'::regrole, 'anon'::regrole)
       AND x.privilege_type IN ('INSERT','UPDATE','REFERENCES')
  LOOP
    EXECUTE format(
      'REVOKE %s (%I) ON TABLE public.student_loadouts FROM %I',
      r.privilege_type, r.attname, r.rol);
  END LOOP;
END $$;

-- ------------------------------------------------------------
-- 4b) 017 donemi INSERT/UPDATE politikalari kaldiriliyor
--     ("student updates/inserts own loadout"). Yetki geri alindiktan
--     sonra bu politikalar ETKSIZ permit'lerdir; ancak
--     hook_after156 grant'leri pg_policies'ten TURETTIGI icin bu
--     politikalar her temiz kurulumda yazma yetkisini YENIDEN
--     tohumler. Politika kaldirilmadan konverjans kalici olmaz
--     (fail-closed tohumun kurutulmasi). SELECT politikasi
--     ("student reads own loadout") ve RLS acik kalir; SELECT
--     politikalarina dokunulmaz. 157 §C yazilabilirlik paritesi
--     bu kaldirmayla korunur (yazmasiz tablo = yazma politkasiz).
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "student updates own loadout" ON public.student_loadouts;
DROP POLICY IF EXISTS "student inserts own loadout" ON public.student_loadouts;

-- ------------------------------------------------------------
-- 5) FAIL-CLOSED sozlesme assertleri (GAP-SEC-01 kapanis kapisi).
-- ------------------------------------------------------------
DO $final$
DECLARE v_cnt int;
BEGIN
  -- 5a) ogrenci: tablo-genel UPDATE/DELETE YOK; INSERT (insert_own
  --     signup yolu) DURUYOR.
  IF has_table_privilege('authenticated','public.student_profiles','UPDATE')
     OR has_table_privilege('authenticated','public.student_profiles','DELETE')
     OR NOT has_table_privilege('authenticated','public.student_profiles','INSERT')
     OR NOT has_table_privilege('authenticated','public.student_profiles','SELECT') THEN
    RAISE EXCEPTION 'FINAL_166: student_profiles tablo ACL sozlesmesi ihlali'
      USING errcode='P0001';
  END IF;

  -- 5b) kolon allow-listi: yalniz nickname/UPDATE/authenticated.
  IF NOT has_column_privilege('authenticated','public.student_profiles',
                              'nickname','UPDATE')
     OR has_column_privilege('authenticated','public.student_profiles',
                             'grade_level','UPDATE') THEN
    RAISE EXCEPTION 'FINAL_166: kolon allow-list ihlali (nickname/grade_level)'
      USING errcode='P0001';
  END IF;
  SELECT count(*) INTO v_cnt
    FROM pg_attribute a
   CROSS JOIN LATERAL aclexplode(a.attacl) x
   WHERE a.attrelid = 'public.student_profiles'::regclass
     AND a.attnum > 0 AND NOT a.attisdropped
     AND x.grantee IN ('authenticated'::regrole, 'anon'::regrole)
     AND x.privilege_type <> 'SELECT'
     AND NOT (a.attname = 'nickname'
              AND x.grantee = 'authenticated'::regrole
              AND x.privilege_type = 'UPDATE');
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FINAL_166: student_profiles allow-list disi kolon yazma kaydi: %', v_cnt
      USING errcode='P0001';
  END IF;

  -- 5c) loadouts RPC-only siniri (108/095): I/U/D YOK, SELECT VAR.
  IF has_table_privilege('authenticated','public.student_loadouts','INSERT')
     OR has_table_privilege('authenticated','public.student_loadouts','UPDATE')
     OR has_table_privilege('authenticated','public.student_loadouts','DELETE')
     OR has_table_privilege('anon','public.student_loadouts','INSERT')
     OR has_table_privilege('anon','public.student_loadouts','UPDATE')
     OR has_table_privilege('anon','public.student_loadouts','DELETE')
     OR NOT has_table_privilege('authenticated','public.student_loadouts','SELECT') THEN
    RAISE EXCEPTION 'FINAL_166: student_loadouts RPC-only siniri ihlali'
      USING errcode='P0001';
  END IF;

  -- 5d) yonetim/bakim yollari DURUYOR.
  IF NOT has_table_privilege('service_role','public.student_profiles','UPDATE')
     OR NOT has_table_privilege('service_role','public.student_loadouts','SELECT') THEN
    RAISE EXCEPTION 'FINAL_166: service_role yonetim yolu bozuldu'
      USING errcode='P0001';
  END IF;

  -- 5e) 157 §6 meshru yazma yollari (bu dosyanin dokmadigi taraflar)
  --     hâlâ yerinde — geri sarma tespit cihazi.
  IF NOT has_table_privilege('authenticated','public.student_visibility_settings','INSERT')
     OR NOT has_table_privilege('authenticated','public.question_promotion_audit','INSERT')
     OR NOT has_table_privilege('authenticated','public.question_review_decisions','INSERT') THEN
    RAISE EXCEPTION 'FINAL_166: 157 meşru yazma yollari geri sarildi'
      USING errcode='P0001';
  END IF;

  -- 5f) RLS kapanisi: her iki tabloda RLS ACIK; profil politikalarina
  --     dokunulmadi, loadouts'ta yalniz 4b'deki iki yazma politikasi
  --     kaldirildi (SELECT politikasi duruyor).
  --     Not: FORCE RLS zincir sozlesmesinde YOK (olcum: her iki
  --     tabloda relforcerowsecurity=false, <=131'den beri); RPC
  --     sahibi (postgres) owner-pass yolu buna bagli — FORCE
  --     eklemek ayri urun kararidir (bkz. rapor §4).
  IF EXISTS (
       SELECT 1 FROM (VALUES
         ('public.student_profiles'::regclass, 4),  -- select_own/update_own/insert_own/admin read all
         ('public.student_loadouts'::regclass, 1)   -- reads own (017 yazma politikalari kuruildi)
       ) t(oid, expected_policies)
      WHERE NOT (SELECT relrowsecurity FROM pg_class WHERE oid = t.oid)
         OR (SELECT count(*) FROM pg_policy WHERE polrelid = t.oid) <> t.expected_policies
  ) THEN
    RAISE EXCEPTION 'FINAL_166: RLS acik degil ya da politika kumesi degisti'
      USING errcode='P0001';
  END IF;

  -- 5g) 157 §C paritesinin SON DURUMDA da surdugu (yazilabilir tablo
  --     kumesi == yazma politikali tablo kumesi; 157 ile ayni
  --     tanim). Tohum kurutulmasi dogrulanir: parite bozuksa
  --     ya konverjans eksik ya da zincire yeni drift girdi.
  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relispartition=false
     AND (has_table_privilege('authenticated',c.oid,'INSERT')
          OR has_table_privilege('authenticated',c.oid,'UPDATE')
          OR has_table_privilege('authenticated',c.oid,'DELETE'));
  IF v_cnt <> (
       SELECT count(*)
         FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relispartition=false
          AND EXISTS (SELECT 1 FROM pg_policy p
                       WHERE p.polrelid=c.oid AND p.polcmd IN ('a','w','d','*')
                         AND p.polroles @> ARRAY['authenticated'::regrole::oid]
                         AND p.polpermissive)
     ) THEN
    RAISE EXCEPTION 'FINAL_166: 157 §C paritesi son durumda bozuk (yazilabilir=%)', v_cnt
      USING errcode='P0001';
  END IF;

  RAISE NOTICE 'FINAL_166 OK: student_profiles 093 kolon sozlesmesi + student_loadouts 108 RPC-only siniri yeniden yururlukte (GAP-SEC-01 kapandi)';
END $final$;

COMMENT ON TABLE public.student_profiles IS
  'Ogrenci profili. 093+166: authenticated yalniz nickname kolonunu guncelleyebilir (tablo UPDATE/DELETE yok); grade_level/schedule_profile_id degisimi yalniz service_role/tablo sahibi icin aciktir (fail-closed).';

COMMENT ON TABLE public.student_loadouts IS
  'Ogrenci yuklemesi. 108+166: authenticated icin SELECT yalniz; yazma yalniz SECURITY DEFINER RPC (107 select_own_avatar).';

INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
SELECT '166', '166_student_profile_write_convergence', NULL
WHERE NOT EXISTS (
  SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '166'
);

COMMIT;
