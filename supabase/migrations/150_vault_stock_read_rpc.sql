-- ============================================================
-- 150_vault_stock_read_rpc.sql
-- Altın Kalemler — VAULT-SETUP-01 hazırlık paketi, dilim 3:
--   Kasa stok OKUMA RPC'si (DAR, salt-okunur, additive).
--
-- >>> DURUM: TASLAK — UYGULANMAMIŞTIR. Bu dosya kullanıcı kararı
--     olmadan ÇALIŞTIRILMAZ / uygulanmaz. DB'ye yazım yoktur;
--     tablo/RLS DEĞİŞİKLİĞİ YOKTUR (yalnız YENİ fonksiyon).
--
-- DESEN: 141_admin_uretim_planlayici_islevsel.sql §3
--   uretim_planlayici_list_vaults BİREBİR:
--     - STABLE + SECURITY DEFINER + SET search_path = ''
--     - iç izin kontrolü (fail-closed 42501):
--         service_role OR private.current_user_has_admin_permission('ai.manage')
--                      OR private.current_user_has_admin_permission('questions.approve')
--     - REVOKE PUBLIC/anon + GRANT authenticated,service_role (yalnız YENİ fonksiyon;
--       mevcut roller/izinler DEĞİŞMEZ)
--     - ORDER BY vault_code, LIMIT 200; WHERE is_active = true
--   Kapsam kararı: 141 davranışıyla AYNI — yalnız LEAF kasalar değil,
--   TÜM aktif kasalar döner (kök/ebeveyn dahil; hedefleri zaten
--   'unknown' çıkar). Filtre parametresi EKLENMEZ (dar okuma).
--
-- DÖNDÜRDÜĞÜ (tek satır = bir kasa; agregatlar aktif üyelikten):
--   vault_id, vault_code, name, vault_type, grade_level, subject_id,
--   subject_name, difficulty_level          — 048 kolonları (doğrudan okuma)
--   hedef, hedef_kaynak                     — vault.metadata.target_question_count
--                                             (141 target_basis aynası; yoksa NULL/'unknown')
--   kullanilabilir                          — aktif üyelik sayısı (051 özeti;
--                                             membership_status='active')
--   practice_eligible, competition_eligible,
--   one_v_one_eligible                      — AYRI kolonlar: aktif üyelikler
--                                             içinde ilgili eligibility=true adet;
--                                             HİÇBİR KOŞULDA tek sayıda BİRLEŞTİRİLMEZ
--   eksik                                   — GREATEST(hedef - kullanilabilir, 0);
--                                             hedef bilinmiyorsa NULL (uydurma yok)
--   exam_eligible bilinçli döndürülmez (görünüm sözleşmesi kapsamı dışı).
--
-- GÜVENLİK NOTU: 051 üyelik okuması normalde service_role'dur; görünüm
--   katmanı aktif üyelik sayısını okuyamadığı için "okunamıyor" yazar
--   (kasa-gorunum.ts sözleşmesi). Bu fonksiyon admin perm sahibine DAR
--   agregat okuma verir; satır düzeyinde üyelik/soru kimliği DÖNMEZ.
--
-- İDEMPOTENCE (146/147/148/149 deseni):
--   - create or replace + REVOKE/GRANT tekrar koşumda güvenli.
--   - history: supabase_migrations.schema_migrations'a version='150'
--     WHERE NOT EXISTS ile idempotent eklenir (statements=NULL).
--   - GUARD/FINAL fail-closed: bağımlılık ve izin denetimi; beklentiye
--     aykırı durum transaction'ı PATLATIR (kısmi uygulama YOK).
-- ============================================================

BEGIN;

-- ============================================================
-- 0. GUARD — bağımlılık denetimi (fail-closed)
-- ============================================================
DO $guard$
BEGIN
  -- İzin yardımcısı (026) yoksa izin kontrolü sessizce false dönerdi →
  -- fail-closed yerine fail-OPEN olurdu; bu durumda dur.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private' AND p.proname = 'current_user_has_admin_permission'
  ) THEN
    RAISE EXCEPTION 'GUARD_150: private.current_user_has_admin_permission yok — migration 026 uygulanmamış ortam.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = 'public' AND table_name = 'question_vaults')
  THEN
    RAISE EXCEPTION 'GUARD_150: public.question_vaults yok — migration 048 uygulanmamış ortam.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = 'public' AND table_name = 'question_vault_memberships')
  THEN
    RAISE EXCEPTION 'GUARD_150: public.question_vault_memberships yok — migration 051 uygulanmamış ortam.';
  END IF;

  -- Gövde subjects'e LEFT JOIN yapar; public.subjects yoksa CREATE sonrası
  -- çalışma anında mesajsız patlar → bağımlılık açıkça denetlenir (mevcut - migration 045).
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = 'public' AND table_name = 'subjects')
  THEN
    RAISE EXCEPTION 'GUARD_150: public.subjects yok — beklenen tablo (migration 045) uygulanmamış ortam.';
  END IF;

  -- Hedef sütunların varlığı (048/051 şema sözleşmesi).
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='question_vaults'
                   AND column_name='difficulty_level')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='question_vault_memberships'
                   AND column_name='one_v_one_eligible')
  THEN
    RAISE EXCEPTION 'GUARD_150: beklenen sütunlar (difficulty_level / one_v_one_eligible) yok — şema sürümü beklenmedik.';
  END IF;
END
$guard$;

-- ============================================================================
-- 1. FONKSİYON — DAR salt-okunur kasa stok okuma
--    NOT: RETURNS TABLE kolon tipleri değişirse (bigint/int4 düzeltmesi
--    gibi) CREATE OR REPLACE yeterli DEĞİLDİR — PG kolon tipini çıkaramaz
--    (cannot change return type). Bu nedenle önce DROP IF EXISTS:
--    idempotent koşumda fonksiyon aynı tipteyse re-CREATE ve davranış
--    korunur (history WHERE NOT EXISTS olduğu için güncel sayım etkisi 0).
-- ============================================================================

DROP FUNCTION IF EXISTS public.uretim_planlayici_list_vault_stock();

CREATE OR REPLACE FUNCTION public.uretim_planlayici_list_vault_stock()
RETURNS TABLE (
  vault_id uuid,
  vault_code text,
  name text,
  vault_type text,
  grade_level smallint,
  subject_id uuid,
  subject_name text,
  difficulty_level text,
  hedef integer,
  hedef_kaynak text,
  kullanilabilir bigint,
  practice_eligible bigint,
  competition_eligible bigint,
  one_v_one_eligible bigint,
  eksik bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $body$
BEGIN
  -- Yetki (fail-closed; 141:895-903 birebir desen):
  -- service_role VEYA planner izni (ai.manage OR questions.approve).
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Kasa stok okuma için admin yetkisi gerekli.'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT
      v.id,
      v.vault_code,
      v.name,
      v.vault_type,
      v.grade_level,
      v.subject_id,
      sb.name,
      v.difficulty_level,
      -- hedef: yalnız vault.metadata.target_question_count (141:924-928 aynası)
      CASE
        WHEN v.metadata ? 'target_question_count'
             AND (v.metadata ->> 'target_question_count') ~ '^[0-9]+$'
        THEN (v.metadata ->> 'target_question_count')::integer
      END,
      -- hedef_kaynak: 141:929-934 target_basis aynası
      CASE
        WHEN v.metadata ? 'target_question_count'
             AND (v.metadata ->> 'target_question_count') ~ '^[0-9]+$'
        THEN 'vault.metadata.target_question_count'
        ELSE 'unknown'
      END,
      -- kullanilabilir: aktif üyelik sayısı (051 özeti)
      COALESCE(ms.aktif_adet, 0)::bigint,
      -- AYRI kapsam sayıları — birleştirilmez (görünüm sözleşmesi)
      COALESCE(ms.practice_adet, 0)::bigint,
      COALESCE(ms.competition_adet, 0)::bigint,
      COALESCE(ms.one_v_one_adet, 0)::bigint,
      -- eksik = hedef - kullanilabilir (negatife düşmez); hedef unknown → NULL
      CASE
        WHEN v.metadata ? 'target_question_count'
             AND (v.metadata ->> 'target_question_count') ~ '^[0-9]+$'
        THEN GREATEST(
               (v.metadata ->> 'target_question_count')::integer
                 - COALESCE(ms.aktif_adet, 0),
               0)
      END
    FROM public.question_vaults v
    LEFT JOIN public.subjects sb ON sb.id = v.subject_id
    LEFT JOIN (
      SELECT m.vault_id AS mvault_id,
             count(*) FILTER (WHERE m.membership_status = 'active') AS aktif_adet,
             count(*) FILTER (WHERE m.membership_status = 'active'
                               AND m.practice_eligible = true) AS practice_adet,
             count(*) FILTER (WHERE m.membership_status = 'active'
                               AND m.competition_eligible = true) AS competition_adet,
             count(*) FILTER (WHERE m.membership_status = 'active'
                               AND m.one_v_one_eligible = true) AS one_v_one_adet
      FROM public.question_vault_memberships m
      GROUP BY m.vault_id
    ) ms ON ms.mvault_id = v.id
    WHERE v.is_active = true
    ORDER BY v.vault_code
    LIMIT 200;
END;
$body$;

-- ============================================================
-- 2. İZİN MATRİSİ — yalnız YENİ fonksiyon (141:1443-1448 birebir desen);
--    mevcut roller/izinler DEĞİŞMEZ.
-- ============================================================
REVOKE ALL ON FUNCTION
  public.uretim_planlayici_list_vault_stock()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.uretim_planlayici_list_vault_stock()
  TO authenticated, service_role;

COMMENT ON FUNCTION public.uretim_planlayici_list_vault_stock()
  IS 'VAULT-SETUP-01: dar salt-okunur kasa stok okuma (hedef=metadata; kullanilabilir=aktif üyelik; practice/competition/one_v_one AYRI; eksik=hedef-kullanilabilir). 141 uretim_planlayici_list_vaults deseni; tümü aktif kasalar.';

-- ============================================================
-- 3. MIGRATION HISTORY — idempotent kayıt (146:377-381 deseni;
--    psql koşumunda statements=NULL; CLI koşan ortamda CLI'ın kendi
--    kaydı varsa bu INSERT atlanır).
-- ============================================================
insert into supabase_migrations.schema_migrations (version, name, statements)
select '150', '150_vault_stock_read_rpc', NULL
 where not exists (
   select 1 from supabase_migrations.schema_migrations where version = '150'
 );

-- ============================================================
-- 4. FINAL — son denetim (fail-closed; beklentiden sapan durum
--    COMMIT'i durdurur). 146 $final$ deseni.
-- ============================================================
DO $final$
DECLARE
  v_identity_ok boolean;
  v_anon_exec boolean;
  v_authed_exec boolean;
BEGIN
  -- Fonksiyon var + imza/öznitelikler beklentide mi?
  -- proconfig İÇERİĞİ de denetlenir: 'search_path' ayarının gerçekten boş
  -- ('') olduğu; yalnız 'IS NOT NULL' birini proconfig'i değiştirip
  -- security tripwire'ı körleştirebilirdi (reviewer bulgusu m2).
  -- Not: agg fonksiyonu bool_and'dır (min(boolean) PostgreSQL'de yoktur).
  SELECT count(*) = 1
       AND bool_and(p.prosecdef)          -- SECURITY DEFINER
       AND bool_and(p.proconfig IS NOT NULL) -- search_path ayarı VAR
       -- pg_get_functiondef çıktısındaki temsil: "SET search_path TO ''"
       -- (tümü-alpha; '=' değil 'TO' formu — canlı kanıt denerim)
       AND bool_and(position('search_path TO ' || chr(39) || chr(39) in pg_get_functiondef(p.oid)) <> 0
             AND position('search_path TO ' || chr(39) || 'public' in pg_get_functiondef(p.oid)) = 0
             AND position('search_path TO ' || chr(39) || 'private' in pg_get_functiondef(p.oid)) = 0)
     INTO v_identity_ok
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'uretim_planlayici_list_vault_stock';

  IF v_identity_ok IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FINAL_150: fonksiyon beklentideki tanımla bulunamadı (SECURITY DEFINER / search_path TO içeriği) — fail-closed.';
  END IF;

  SELECT has_function_privilege('anon', 'public.uretim_planlayici_list_vault_stock()', 'EXECUTE')
    INTO v_anon_exec;
  SELECT has_function_privilege('authenticated', 'public.uretim_planlayici_list_vault_stock()', 'EXECUTE')
    INTO v_authed_exec;

  IF v_anon_exec THEN
    RAISE EXCEPTION 'FINAL_150: anon EXECUTE yetkisi VAR — izin matrisi bozuk, fail-closed.';
  END IF;
  IF NOT v_authed_exec THEN
    RAISE EXCEPTION 'FINAL_150: authenticated EXECUTE yetkisi YOK — izin matrisi bozuk, fail-closed.';
  END IF;
  -- PUBLIC (ve PUBLIC''i kapsayan anon) dışında service_role da DENETLENİR:
  -- GRANT çifti tek satırda (authenticated,service_role) verildiğinden
  -- authenticated + anon-denetimi genelde yeter; service_role'nun YOKLUĞU da
  -- ayrı tip hatasıdır (izni geri almak için tek rol revokesi yeterli olurdu).
  IF NOT has_function_privilege('service_role', 'public.uretim_planlayici_list_vault_stock()', 'EXECUTE') THEN
    RAISE EXCEPTION 'FINAL_150: service_role EXECUTE yetkisi YOK — izin matrisi bozuk, fail-closed.';
  END IF;

  -- History kaydı mutlaka durmalı.
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '150') THEN
    RAISE EXCEPTION 'FINAL_150: history kaydı (version=150) yok — beklenmeyen durum.';
  END IF;
END
$final$;

COMMIT;
