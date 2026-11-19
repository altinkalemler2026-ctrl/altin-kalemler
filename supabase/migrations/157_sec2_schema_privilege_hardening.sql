-- ============================================================
-- 157_sec2_schema_privilege_hardening.sql
-- AK-SEC-HARDEN-157A: Şema geneli yetki sertleştirmesi (en dar dilim)
-- ============================================================
-- ÖN KOŞUL / UYGULAMA SIRASI:
--   155 (SEC-1) ve 156 (SEC-1b) UYGULANMIŞ olmalı (PREFLIGHT assert edilir).
--   Tek transaction: -v ON_ERROR_STOP=1 -1 ile koşulur.
--
-- KÖKEN (kanıt, 10 Kas 2026 salt-okunur canlı envanteri):
--   2026-10 cloud-recovery 108-öncesi taban geri sarması:
--     * 158 tabloda anon SELECT+INSERT+UPDATE+DELETE (+TRUNCATE/REF/TRIGGER),
--     * 160 tabloda authenticated TRUNCATE/REF/TRIGGER (+yazma),
--     * 161/161 tabloda kolon düzeyi ek hak kayıtları (anon/auth),
--     * lig üçlüsünde (leaderboard_entries, student_league_history,
--       student_league_memberships) anon+authenticated doğrudan SELECT —
--       108 RPC-only sözleşmesi bozuk (M6×3),
--     * pg_default_acl postgres/r ve postgres/S satırları tam grant'a
--       dönmüş — 108 §4 default-privilege sertleştirmesi geri sarılmış
--       (drift ÜRETİM KANALI açık).
--   108 körlemesine YENİDEN ÇALIŞTIRILMAZ: 109+ zinciri meşru istisnalar
--   verdi (133 admin_bulk_gate_* SELECT, 108 kendi loadouts/characters
--   SELECT'leri, 156 questions authenticated SELECT + kolon SELECT
--   kayıtları). Bu migration yalnız KANITLI drift'i kapatır, meşru
--   zincir içi yetkilere dokunmaz.
--
-- SOZLESME (en dar ilke):
--   A) anon: public tablo+VIEW+SEQUENCE'larda TAM yetki iptali.
--      Kanıt: kod tabanında anon tablo/view okuması YOK
--      (src taraması: tüm .from() çağrıları (auth)/(student)/(admin)
--      oturumlu rotalarda; landing yalnız auth.getUser(); API rotaların-
--      da tablo erişimi yok). RLS'te hiçbir anon YAZMA politikası yok.
--      Kolon düzeyi anon kayıtları ayrı loop'la silinir (156 PG bulgusu:
--      tablo REVOKE'u kolon kayıtlarını silmez).
--   B) authenticated: TÜM public tablolarda TRUNCATE/REFERENCES/TRIGGER/
--      MAINTAIN iptali (108 §1 sözleşmesi + 156 MAINTAIN hijyeni).
--      TRIGGER iptali tetikleyici ÇALIŞMASINI etkilemez (yalnız
--      CREATE/DROP TRIGGER hakkıdır); REFERENCES yalnız FK TANIMLAMA-
--      dır; owner postgres etkilenmez.
--   C) authenticated: yazma yetkisi olup KENDİNE ait INSERT/UPDATE/
--      DELETE politikası BULUNMAYAN tablolarda INSERT/UPDATE/DELETE
--      iptali. Kanıt: RLS açıktır ve yazma politikası olmayan tabloda
--      her yazma zaten politika katmanında reddedilir → yetki iptali
--      davranışı DEĞİŞTİRMEZ, savunma-derinleştirmedir. Bu küme öğrenci
--      puan/rating/kasa/lig manipülasyon yollarını içerir (97 tablo;
--      QA'da assert: kalan yazılabilir tablo sayısı == authenticated
--      yazma politikası olan tablo sayısı).
--      Meşru yazma politikaları KORUNUR (63 tablo): admin modül ALL
--      politikaları (~58) + student_profiles/ student_loadouts/
--      student_visibility_settings update_own/insert_own +
--      question_promotion_audit & question_review_decisions INSERT.
--      Kolon yazma kayıtları yalnız bu 97 tablada silinir (156 kalıbı:
--      INSERT, UPDATE, REFERENCES tek tek adlandırılır; SELECT
--      kayıtlarına dokunulmaz — eş-yaratım bağımlılığı nedeniyle
--      yalnız yazma kaydı silme tablo SELECT'ini düşürmüyor 156'da
--      kanıtlandı).
--   D) Lig üçlüsü (RPC-only, 108 §6): authenticated doğrudan SELECT
--      tablo + KOLON kayıtlarıyla birlikte geri alınır. Kanıt: src'de
--      üç tablo yalnız üretilmiş tiplerde geçer; okuma yolu
--      get_my_league_ranking allowlist RPC'sidir. anon zaten A'dadır.
--   E) Sequence'ler: anon+authenticated tam iptal. Kanıt: nextval
--      varsayılanı YALNIZ faz30d_* defter tablolarında (yazma politikası
--      yok, yazmalar service_role/definer yollarında); identity
--      kolonlar istemciye sequence hakkı gerektirmez.
--   F) PUBLIC: 0 kayıt (envanter) — hijyen garanti.
--   G) Default privileges (108 §7 kapsam kararı Yeniden): YALNIZ
--      postgres rolü (180/180 public nesne sahibi postgres — 10 Kas
--      envanteri). supabase_admin default ACL'sine dokunulmaz (108 §7
--      hosted-kanıt gerekçesi aynen geçerli; kalan risk raporda).
--   H) service_role, postgres ve fonksiyon EXECUTE ACL'lerine
--      DOKUNULMAZ. DROP/ALTER TABLE yok, veri yok, kod yok.
--
-- FAIL-CLOSED: sonda beklenen matris assert edilir; sapma = EXCEPTION
--   (tek transaction, iz bırakmaz). İdempotent: tekrar koşum no-op.
--
-- ROLLBACK (yalnız açık yetkiyle; semptom geri-alımı — önerilmez):
--   108-öncesi taban bootstrap grant'ı geri verilmez; rollback en dar
--   biçimde B için 108 §1'in tersi GRANT'lar, C/D için ilgili tablo
--   GRANT'larıdır ve yeniden drift üretir. Kalıcı çözüm: 157+default
--   privileges.
-- ============================================================

-- ------------------------------------------------------------
-- PREFLIGHT: 155 + 156 kapalı olmalı (156 bağımlılığı)
-- ------------------------------------------------------------
DO $$
BEGIN
  IF has_function_privilege('anon',
       'public.get_internal_correct_answer(uuid)'::regprocedure, 'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.get_internal_correct_answer(uuid)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION '157 PREFLIGHT: 155 uygulanmamış (SEC-1 fonksiyon ACL açık)'
      USING errcode='P0001';
  END IF;
  IF has_table_privilege('anon','public.questions','SELECT')
     OR EXISTS (SELECT 1 FROM pg_policy
                 WHERE polrelid='public.questions'::regclass
                   AND polname='questions_student_read') THEN
    RAISE EXCEPTION '157 PREFLIGHT: 156 uygulanmamış (SEC-1b yüzeyi açık)'
      USING errcode='P0001';
  END IF;
END;
$$;

-- ------------------------------------------------------------
-- A1) anon + PUBLIC: tablo+view tam iptal (kolon kayıtları A2'de)
-- ------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon, PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, PUBLIC, authenticated;

-- ------------------------------------------------------------
-- A2) anon: kolon düzeyi yetki kayıtları (tablo REVOKE silmez — 156 D5)
-- ------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT table_name, column_name
      FROM information_schema.column_privileges
     WHERE table_schema='public' AND grantee='anon'
  LOOP
    EXECUTE format(
      'REVOKE SELECT, INSERT, UPDATE, REFERENCES (%I) ON public.%I FROM anon',
      r.column_name, r.table_name);
  END LOOP;
END;
$$;

-- ------------------------------------------------------------
-- B) authenticated: TRUNCATE / REFERENCES / TRIGGER / MAINTAIN (108 §1 +
--    156 MAINTAIN) — tüm public tablolarda
-- ------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.oid::regclass AS tbl
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname='public' AND c.relkind IN ('r','p')
  LOOP
    EXECUTE format(
      'REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE %s FROM authenticated',
      r.tbl);
  END LOOP;
END;
$$;

-- ------------------------------------------------------------
-- C) authenticated: yazma yetkisi olup kendine yazma politikası
--    bulunmayan tablolada INSERT/UPDATE/DELETE + kolon yazma kayıtları.
--    Komut bazında değerlendirme (question_promotion_audit INSERT-only
--    gibi kısmi meşru yazmalar korunur).
--    Ek assert: yazma politikaları PERMISSIVE olmalı (restrictive-only
--    politika fiilen YASAKTIR → 'yazma politikası var' sayılmaz; öyle
--    bir tablo varsa fail-closed düşür, yanlışlıkla açma/yorma).
-- ------------------------------------------------------------
DO $$
DECLARE
  v_tbl   record;
  v_col   record;
  v_cmd   text;
  v_cmds  text[] := ARRAY['INSERT','UPDATE','DELETE'];
BEGIN
  -- H0-pre: restrictive yazma politikası varsa dur.
  IF EXISTS (
    SELECT 1
      FROM pg_policy p
     WHERE p.polrelid IN (SELECT c.oid FROM pg_class c
                           JOIN pg_namespace n ON n.oid=c.relnamespace
                          WHERE n.nspname='public' AND c.relkind IN ('r','p'))
       AND p.polcmd IN ('a','w','d','*')
       AND p.polroles @> ARRAY['authenticated'::regrole::oid]
       AND NOT p.polpermissive
  ) THEN
    RAISE EXCEPTION '157 C: authenticated restrictive yazma politikasi bulundu — küme yeniden değerlendirilmeli; fail-closed.'
      USING errcode='P0001';
  END IF;

  FOR v_tbl IN
    SELECT c.oid, c.oid::regclass AS tbl, c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname='public' AND c.relkind IN ('r','p')
       AND c.relispartition = false
       AND (has_table_privilege('authenticated', c.oid, 'INSERT')
            OR has_table_privilege('authenticated', c.oid, 'UPDATE')
            OR has_table_privilege('authenticated', c.oid, 'DELETE'))
     ORDER BY c.relname
  LOOP
    FOREACH v_cmd IN ARRAY v_cmds LOOP
      CONTINUE WHEN NOT has_table_privilege('authenticated', v_tbl.oid, v_cmd);
      -- Bu komutu kapsayan (a/w/d eşleşmesi veya '*') PERMISSIVE
      -- authenticated politikası var mı?
      IF NOT EXISTS (
        SELECT 1 FROM pg_policy p
         WHERE p.polrelid = v_tbl.oid
           AND p.polcmd IN (CASE v_cmd WHEN 'INSERT' THEN 'a'
                                       WHEN 'UPDATE' THEN 'w'
                                       ELSE 'd' END, '*')
           AND p.polroles @> ARRAY['authenticated'::regrole::oid]
           AND p.polpermissive
      ) THEN
        EXECUTE format(
          'REVOKE %s ON TABLE %s FROM authenticated', v_cmd, v_tbl.tbl);
      END IF;
    END LOOP;

    -- Silinen komutların kolon yazma kayıtlarını da temizle: tabloda
    -- artık hiç yazma yetkisi kalmadıysa kolon INSERT/UPDATE/REFERENCES
    -- kayıtları da silinir (156 kalıbı; SELECT kayıtlarına dokunulmaz).
    IF NOT has_table_privilege('authenticated', v_tbl.oid, 'INSERT')
       AND NOT has_table_privilege('authenticated', v_tbl.oid, 'UPDATE')
       AND NOT has_table_privilege('authenticated', v_tbl.oid, 'DELETE') THEN
      FOR v_col IN
        SELECT DISTINCT column_name
          FROM information_schema.column_privileges
         WHERE table_schema='public'
           AND table_name = v_tbl.relname
           AND grantee='authenticated'
           AND privilege_type <> 'SELECT'
      LOOP
        EXECUTE format(
          'REVOKE INSERT, UPDATE, REFERENCES (%I) ON public.%I FROM authenticated',
          v_col.column_name, v_tbl.relname);
      END LOOP;
    END IF;
  END LOOP;
END;
$$;

-- ------------------------------------------------------------
-- D) Lig üçlüsü: authenticated SELECT tablo + kolon kayıtları (108 §6
--    RPC-only restorasyonu; M6×3 kapatma).
-- ------------------------------------------------------------
DO $$
DECLARE
  v_tbl record; v_col record;
BEGIN
  FOR v_tbl IN
    SELECT c.oid, c.oid::regclass AS tbl, c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname='public'
       AND c.relname IN ('leaderboard_entries','student_league_history',
                         'student_league_memberships')
  LOOP
    EXECUTE format('REVOKE SELECT ON TABLE %s FROM authenticated, anon', v_tbl.tbl);
    FOR v_col IN
      SELECT DISTINCT column_name
        FROM information_schema.column_privileges
       WHERE table_schema='public' AND table_name=v_tbl.relname
         AND grantee IN ('authenticated','anon')
    LOOP
      EXECUTE format(
        'REVOKE SELECT, INSERT, UPDATE, REFERENCES (%I) ON public.%I FROM authenticated, anon',
        v_col.column_name, v_tbl.relname);
    END LOOP;
  END LOOP;
END;
$$;

-- ------------------------------------------------------------
-- G) Default privileges restorasyonu (yalnız postgres rolü — 108 §7
--    kapsam kararı; drift üretim kanalı kapatılır).
-- ------------------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM authenticated, anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON TABLES FROM authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon, authenticated;

-- ------------------------------------------------------------
-- FAIL-CLOSED ASSERT — beklenen son matris
-- ------------------------------------------------------------
DO $$
DECLARE
  v_cnt int; v_keep int;
BEGIN
  -- 1) anon: public tablo/view/sequence hiçbir hakkı yok
  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p','v')
     AND (has_table_privilege('anon',c.oid,'SELECT')
          OR has_table_privilege('anon',c.oid,'INSERT')
          OR has_table_privilege('anon',c.oid,'UPDATE')
          OR has_table_privilege('anon',c.oid,'DELETE')
          OR has_table_privilege('anon',c.oid,'TRUNCATE')
          OR has_table_privilege('anon',c.oid,'REFERENCES')
          OR has_table_privilege('anon',c.oid,'TRIGGER')
          OR has_table_privilege('anon',c.oid,'MAINTAIN'));
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION '157 fail-closed: anon hak kiriligi % nesnede duruyor', v_cnt USING errcode='P0001';
  END IF;

  SELECT count(*) INTO v_cnt
    FROM information_schema.column_privileges
   WHERE table_schema='public' AND grantee IN ('anon','public');
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION '157 fail-closed: anon/public kolon kayiti % duruyor', v_cnt USING errcode='P0001';
  END IF;

  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='S'
     AND (has_sequence_privilege('anon',c.oid,'USAGE')
          OR has_sequence_privilege('anon',c.oid,'SELECT')
          OR has_sequence_privilege('anon',c.oid,'UPDATE')
          OR has_sequence_privilege('authenticated',c.oid,'USAGE')
          OR has_sequence_privilege('authenticated',c.oid,'SELECT')
          OR has_sequence_privilege('authenticated',c.oid,'UPDATE'));
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION '157 fail-closed: sequence hak kiriligi % duruyor', v_cnt USING errcode='P0001';
  END IF;

  -- 2) authenticated: tehlikeli hak sifir (B)
  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p')
     AND (has_table_privilege('authenticated',c.oid,'TRUNCATE')
          OR has_table_privilege('authenticated',c.oid,'REFERENCES')
          OR has_table_privilege('authenticated',c.oid,'TRIGGER')
          OR has_table_privilege('authenticated',c.oid,'MAINTAIN'));
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION '157 fail-closed: authenticated tehlikeli hak % tabloda duruyor', v_cnt USING errcode='P0001';
  END IF;

  -- 3) C matrisi: yazilabilir tablo sayisi == authenticated yazma
  --    politikasi olan tablo sayisi (dinamik esitlik; partition parent'lari)
  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relispartition=false
     AND (has_table_privilege('authenticated',c.oid,'INSERT')
          OR has_table_privilege('authenticated',c.oid,'UPDATE')
          OR has_table_privilege('authenticated',c.oid,'DELETE'));
  SELECT count(*) INTO v_keep
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relispartition=false
     AND EXISTS (SELECT 1 FROM pg_policy p
                  WHERE p.polrelid=c.oid AND p.polcmd IN ('a','w','d','*')
                    AND p.polroles @> ARRAY['authenticated'::regrole::oid]
                    AND p.polpermissive);
  IF v_cnt <> v_keep THEN
    RAISE EXCEPTION '157 fail-closed: yazilabilir tablo % != yazma politikali tablo %', v_cnt, v_keep USING errcode='P0001';
  END IF;

  -- 3b) C kolon hijyeni: authenticated kolon YAZMA kaydi yalniz
  --     yazma politikasi olan parent tablolarda kalmali (acl kaydi
  --     pg_attribute.attacl uzerinden sayilir; view/partition hariç)
  SELECT count(*) INTO v_cnt
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relispartition=false
     AND a.attnum > 0 AND NOT a.attisdropped
     AND EXISTS (SELECT 1 FROM aclexplode(a.attacl) x
                  WHERE x.grantee = 'authenticated'::regrole
                    AND x.privilege_type <> 'SELECT')
     AND NOT EXISTS (
       SELECT 1 FROM pg_policy p
        WHERE p.polrelid = c.oid
          AND p.polcmd IN ('a','w','d','*')
          AND p.polroles @> ARRAY['authenticated'::regrole::oid]
          AND p.polpermissive);
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION '157 fail-closed: yazma politikasi olmayan tablolarda authenticated kolon yazma kaydi % kaldi', v_cnt USING errcode='P0001';
  END IF;

  -- 4) Lig üçlüsü RPC-only (D): tablo+kolon SELECT sifir
  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public'
     AND c.relname IN ('leaderboard_entries','student_league_history',
                       'student_league_memberships')
     AND (has_table_privilege('authenticated',c.oid,'SELECT')
          OR has_table_privilege('anon',c.oid,'SELECT'));
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION '157 fail-closed: lig tablolarinda dogrudan SELECT acik (% tablo)', v_cnt USING errcode='P0001';
  END IF;

  -- 5) SEC-1/SEC-1b kapanislari KORUNDU (geri sarma tespit cihazı)
  IF has_function_privilege('anon',
       'public.get_internal_correct_answer(uuid)'::regprocedure,'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.get_internal_correct_answer(uuid)'::regprocedure,'EXECUTE') THEN
    RAISE EXCEPTION '157 fail-closed: SEC-1 geri sarildi' USING errcode='P0001';
  END IF;
  IF has_table_privilege('anon','public.questions','SELECT')
     OR NOT has_table_privilege('authenticated','public.questions','SELECT')
     OR (SELECT count(*) FROM pg_policy
          WHERE polrelid='public.questions'::regclass AND polcmd IN ('r','*')) <> 1 THEN
    RAISE EXCEPTION '157 fail-closed: SEC-1b matrisi bozuldu' USING errcode='P0001';
  END IF;
  SELECT count(*) INTO v_cnt
    FROM information_schema.column_privileges
   WHERE table_schema='public' AND table_name='questions'
     AND grantee='authenticated' AND privilege_type='SELECT';
  IF v_cnt <> 30 THEN
    RAISE EXCEPTION '157 fail-closed: questions authenticated kolon SELECT kaydi % (beklenen 30)' , v_cnt USING errcode='P0001';
  END IF;

  -- 6) Meşru zincir içi istisnalar KORUNDU
  IF NOT has_table_privilege('authenticated','public.student_loadouts','SELECT')
     OR NOT has_table_privilege('authenticated','public.characters','SELECT') THEN
    RAISE EXCEPTION '157 fail-closed: 108 Faz10 UI SELECT yollari kapandi' USING errcode='P0001';
  END IF;
  IF NOT has_table_privilege('authenticated','public.admin_bulk_gate_runs','SELECT')
     OR NOT has_table_privilege('authenticated','public.admin_bulk_gate_tasks','SELECT') THEN
    RAISE EXCEPTION '157 fail-closed: 133 admin bulk gate SELECT kapandi' USING errcode='P0001';
  END IF;
  IF NOT has_table_privilege('authenticated','public.student_profiles','UPDATE')
     OR NOT has_table_privilege('authenticated','public.student_profiles','INSERT')
     OR NOT has_table_privilege('authenticated','public.student_loadouts','INSERT')
     OR NOT has_table_privilege('authenticated','public.student_loadouts','UPDATE')
     OR NOT has_table_privilege('authenticated','public.student_visibility_settings','INSERT')
     OR NOT has_table_privilege('authenticated','public.student_visibility_settings','UPDATE')
     OR NOT has_table_privilege('authenticated','public.question_promotion_audit','INSERT')
     OR NOT has_table_privilege('authenticated','public.question_review_decisions','INSERT') THEN
    RAISE EXCEPTION '157 fail-closed:_meshru insert_own/update_own yazma yollari kapandi' USING errcode='P0001';
  END IF;

  -- 7) service_role bakım yollari DURUYOR (108 §5 + 156 M7 emsalleri)
  IF NOT has_table_privilege('service_role','public.league_season_close_results','SELECT')
     OR NOT has_table_privilege('service_role','public.questions','SELECT')
     OR NOT has_table_privilege('service_role','public.student_league_memberships','SELECT')
     OR NOT has_table_privilege('service_role','public.leaderboard_entries','SELECT') THEN
    RAISE EXCEPTION '157 fail-closed: service_role bakim yolu bozuldu' USING errcode='P0001';
  END IF;

  -- 8) RLS her tablo/larda hâlâ açık (sertlestirme RLS'e yaslanir)
  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relrowsecurity=false;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION '157 fail-closed: RLS kapali % tablo var (beklenen 0)' , v_cnt USING errcode='P0001';
  END IF;

  RAISE NOTICE 'SEC2 OK: anon sifirlandi; authenticated tehlikeli hak 0, yazilabilir tablo = yazma-p tablosi (%); lig RPC-only; SEC-1/1b + meşru yollar + service_role korundu', v_keep;
END;
$$;
