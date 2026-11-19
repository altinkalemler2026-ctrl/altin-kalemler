-- ============================================================
-- 164_vault_gorunurluk_rpc.sql
-- AK-VAULT-VIS-02 — Haftalık kasa görünürlüğü: liste/stok RPC
--   sayfalaması + filtreler + yetkili kolonlar (difficulty_level,
--   week_number, vault_kind, is_active, total_count).
--
-- >>> DURUM: TASLAK — UYGULANMAMIŞTIR. Kullanıcı kararı olmadan
--     canlıya UYGULANMAZ. Bu faz yalnız izole QA'da doğrulanır.
--
-- KÖK NEDEN (AK-VAULT-VIS-01 raporu): 141/150 RPC'lerindeki
--   "WHERE is_active ORDER BY vault_code LIMIT 200" 3.654 haftalık
--   kasa döneminde paneli yalnız ilk 200 kodu (10. sınıf Biyoloji +
--   Coğrafya kolay/orta-kısmi) gösterir hâle getirdi; Zor kasaları
--   ve diğer sınıflar hiç görünmüyordu. Kasa listesi RPC'si
--   difficulty_level DÖNDÜRMÜYORDU → arayüz zorluğu eski `-`-formatlı
--   koddan tahmin ediyordu; week_number/vault_kind/is_active de
--   dönmüyordu.
--
-- DÜZELTME (yalnız OKUMA sözleşmesi; veri değişmez):
--   uretim_planlayici_list_vaults(p_grade, p_subject, p_week,
--     p_difficulty, p_vault_type, p_include_inactive, p_limit, p_offset)
--   uretim_planlayici_list_vault_stock(...aynı parametreler...)
--   - TÜM parametreler DEFAULT'ludur → eski çağrı biçimi
--     `uretim_planlayici_list_vaults()` BİREBİR eski davranışı verir
--     (is_active=true, vault_code sırası, LIMIT 200, ilk 15 kolon
--     aynı). Yeni kolonlar SONA eklenir; JSON tüketicileri tanınmayan
--     kolonu yok sayar (parseKasaListesi desen uyumu).
--   - Sayfalama: p_limit (1..1000 aralığa kenetlenir, varsayılan 200)
--     + p_offset; sıralama KARARLI: ORDER BY vault_code, id.
--   - total_count = filtrelenmiş toplam satır (COUNT(*) OVER());
--     LIMIT'ten bağımsız → istemci eksiksiz turlayabilir.
--   - p_include_inactive=true → pasif kasalar da (K42 genel_tekrar +
--     yöneticiye kapalı allow_*=false kasalar) listelenir; is_active
--     kolonu ayrımı taşır. Varsayılan false = eski davranış.
--
-- NEDEN DROP+CREATE: PostgreSQL'de RETURNS TABLE kolon
--   eklemek/değiştirmek CREATE OR REPLACE ile MÜMKÜN DEĞİLDİR
--   ("cannot change return type"); parametre listesi de imzadır.
--   150 dosyasının kendi notu (satır 103-107) aynı kalıbı kullanır.
--   DROP önce GUARD'da bağımlılık denetlenir: fonksiyona bağlı BAŞKA
--   nesne (view/fonksiyon/tetik) varsa migration DURUR (fail-closed).
--   PostgREST yeniden-keşfi bağımlılık sayılmaz (canlı 150 DROP
--   kalıbı kanıtlı çalıştı).
--
-- GÜVENLİK (değişmez — 141/150 sözleşmesi aynen korunur):
--   - SECURITY DEFINER + SET search_path = '' (boş).
--   - İç izin kapısı fail-closed 42501: service_role VEYA
--     private.current_user_has_admin_permission('ai.manage' /
--     'questions.approve'). Anon'a EXECUTE YOK; öğrenci (izinsiz
--     authenticated) çağrısı 42501. Yeni erişim YETKİSİ eklenmez —
--     yalnız yetkilinin görebildiği satır kümesi doğru sayfalama ile
--     açılır.
--   - RLS/FORCE RLS dokunulmaz (SECURITY DEFINER sahibinden okur;
--     satır düzeyi yeni tablo/mutex yok).
--   - REVOKE PUBLIC/anon + GRANT authenticated,service_role (yalnız
--     bu iki fonksiyon; başka GRANT/REVOKE YOK).
--   - Puan/eşleşme motoruna ve 161/162 katmanına DOKUNULMAZ.
--
-- İDEMPOTENCE: DROP IF EXISTS + CREATE + WHERE NOT EXISTS history
--   → tekrar koşum güvenli (son durum aynı). GUARD, beklenmeyen
--   overload/bağımlılık durumunda patlar. FINAL fail-closed: imza,
--   SECURITY DEFINER, search_path boşluğu, izin matrisi, yeni kolon
--   varlıkları ve history kaydı denetlenir.
-- ============================================================

BEGIN;

-- ============================================================
-- 0. GUARD — bağımlılık ve imza denetimi (fail-closed)
-- ============================================================
DO $guard$
DECLARE
  v_name text;
  v_cnt integer;
  v_dep integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private' AND p.proname = 'current_user_has_admin_permission'
  ) THEN
    RAISE EXCEPTION 'GUARD_164: private.current_user_has_admin_permission yok — migration 026 uygulanmamış ortam.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = 'public' AND table_name = 'question_vaults')
  THEN
    RAISE EXCEPTION 'GUARD_164: public.question_vaults yok — migration 048 uygulanmamış ortam.';
  END IF;

  -- Yetkili kolonlar (161 sözleşmesi): week_number + vault_kind.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='question_vaults'
                   AND column_name='week_number')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='question_vaults'
                   AND column_name='vault_kind')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='question_vaults'
                   AND column_name='difficulty_level')
  THEN
    RAISE EXCEPTION 'GUARD_164: question_vaults.week_number/vault_kind/difficulty_level yok — 161 öncesi şema; bu migration anlamsız.';
  END IF;

  FOREACH v_name IN ARRAY ARRAY[
    'uretim_planlayici_list_vaults',
    'uretim_planlayici_list_vault_stock'
  ] LOOP
    -- Var olan overload sayısı ve imzaları: yalnız 0 argümanlı (141/150
    -- hâli) ya da bu migration'ın kendi 8 argümanlı hâli (yeniden koşum)
    -- kabul edilir. Başka overload → dur (kontrolsüz düşürme YOK).
    SELECT count(*) INTO v_cnt
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname = v_name;
    IF v_cnt = 0 THEN
      RAISE EXCEPTION 'GUARD_164: public.% hiç yok — 141/150 uygulanmamış ortam; beklemedik durum.', v_name;
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname='public' AND p.proname = v_name
         AND COALESCE(array_length(p.proargtypes::oid[], 1), 0) NOT IN (0, 8)
    ) THEN
      RAISE EXCEPTION 'GUARD_164: public.% beklenmeyen argüman imzası taşıyor — ölümcül imza çakışması, dur.', v_name;
    END IF;

    -- Bu fonksiyonlara BAĞLI başka nesne mi? (view/matview/kural/başka
    -- fonksiyon). pg_depend'de kendisi dışında HER referans varsa dur.
    SELECT count(*) INTO v_dep
      FROM pg_depend d
      JOIN pg_proc p ON p.oid = d.refobjid
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname = v_name
       AND d.refclassid = 'pg_proc'::regclass
       AND NOT (d.classid = 'pg_proc'::regclass AND d.objid = p.oid);
    IF v_dep > 0 THEN
      RAISE EXCEPTION 'GUARD_164: public.% fonksiyonuna bağlı % nesne/fonksiyon var — DROP güvenli değil, dur.', v_name, v_dep;
    END IF;
  END LOOP;
END
$guard$;

-- ============================================================
-- 1. uretim_planlayici_list_vaults — sayfalı/filtreli sürüm
--    (imza değişikliği → DROP+CREATE; GUARD bağımlılığı denetledi)
-- ============================================================

DROP FUNCTION IF EXISTS public.uretim_planlayici_list_vaults();
DROP FUNCTION IF EXISTS public.uretim_planlayici_list_vaults(
  smallint, uuid, integer, text, text, boolean, integer, integer);

CREATE OR REPLACE FUNCTION public.uretim_planlayici_list_vaults(
  p_grade smallint DEFAULT NULL,
  p_subject uuid DEFAULT NULL,
  p_week integer DEFAULT NULL,
  p_difficulty text DEFAULT NULL,
  p_vault_type text DEFAULT NULL,
  p_include_inactive boolean DEFAULT false,
  p_limit integer DEFAULT 200,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  vault_id uuid,
  vault_code text,
  name text,
  vault_type text,
  grade_level smallint,
  subject_id uuid,
  subject_name text,
  allow_practice boolean,
  allow_competition boolean,
  allow_one_v_one boolean,
  allow_exam boolean,
  policy_inventory_scope text,
  target_question_count integer,
  target_basis text,
  activation_windows jsonb,
  difficulty_level text,
  week_number integer,
  vault_kind text,
  is_active boolean,
  total_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $body$
BEGIN
  -- Yetki kapısı — 141:895-903 BİREBİR (fail-closed 42501).
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Üretim planlayıcı için admin yetkisi gerekli.'
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
      v.allow_practice,
      v.allow_competition,
      v.allow_one_v_one,
      v.allow_exam,
      (SELECT p.inventory_scope
         FROM public.question_vault_demand_policies p
        WHERE p.vault_id = v.id
          AND p.is_active = true
        ORDER BY p.created_at DESC
        LIMIT 1),
      CASE
        WHEN v.metadata ? 'target_question_count'
             AND (v.metadata ->> 'target_question_count') ~ '^[0-9]+$'
        THEN (v.metadata ->> 'target_question_count')::integer
      END,
      CASE
        WHEN v.metadata ? 'target_question_count'
             AND (v.metadata ->> 'target_question_count') ~ '^[0-9]+$'
        THEN 'vault.metadata.target_question_count'
        ELSE 'unknown'
      END,
      COALESCE(
        (SELECT jsonb_agg(
                  jsonb_build_object(
                    'window_name', w.window_name,
                    'start_week', w.start_week,
                    'end_week', w.end_week,
                    'is_enabled', w.is_enabled)
                  ORDER BY w.start_week NULLS FIRST)
           FROM public.question_vault_activation_windows w
          WHERE w.vault_id = v.id),
        '[]'::jsonb),
      -- AK-VAULT-VIS-02: yetkili kolonlar (tahmin YOK).
      v.difficulty_level,
      v.week_number::integer,
      v.vault_kind,
      v.is_active,
      COUNT(*) OVER ()::bigint
    FROM public.question_vaults v
    LEFT JOIN public.subjects sb ON sb.id = v.subject_id
    WHERE (p_include_inactive OR v.is_active = true)
      AND (p_grade IS NULL OR v.grade_level = p_grade)
      AND (p_subject IS NULL OR v.subject_id = p_subject)
      AND (p_week IS NULL OR v.week_number = p_week)
      AND (p_difficulty IS NULL OR v.difficulty_level = p_difficulty)
      AND (p_vault_type IS NULL OR v.vault_type = p_vault_type)
    ORDER BY v.vault_code, v.id
    LIMIT least(greatest(coalesce(p_limit, 200), 1), 1000)
    OFFSET greatest(coalesce(p_offset, 0), 0);
END;
$body$;

-- ============================================================
-- 2. uretim_planlayici_list_vault_stock — aynı parametreler +
--    week_number/vault_kind/is_active/total_count kolonları
-- ============================================================

DROP FUNCTION IF EXISTS public.uretim_planlayici_list_vault_stock();
DROP FUNCTION IF EXISTS public.uretim_planlayici_list_vault_stock(
  smallint, uuid, integer, text, text, boolean, integer, integer);

CREATE OR REPLACE FUNCTION public.uretim_planlayici_list_vault_stock(
  p_grade smallint DEFAULT NULL,
  p_subject uuid DEFAULT NULL,
  p_week integer DEFAULT NULL,
  p_difficulty text DEFAULT NULL,
  p_vault_type text DEFAULT NULL,
  p_include_inactive boolean DEFAULT false,
  p_limit integer DEFAULT 200,
  p_offset integer DEFAULT 0
)
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
  eksik bigint,
  week_number integer,
  vault_kind text,
  is_active boolean,
  total_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $body$
BEGIN
  -- Yetki kapısı — 150:136-146 BİREBİR.
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
      CASE
        WHEN v.metadata ? 'target_question_count'
             AND (v.metadata ->> 'target_question_count') ~ '^[0-9]+$'
        THEN (v.metadata ->> 'target_question_count')::integer
      END,
      CASE
        WHEN v.metadata ? 'target_question_count'
             AND (v.metadata ->> 'target_question_count') ~ '^[0-9]+$'
        THEN 'vault.metadata.target_question_count'
        ELSE 'unknown'
      END,
      COALESCE(ms.aktif_adet, 0)::bigint,
      COALESCE(ms.practice_adet, 0)::bigint,
      COALESCE(ms.competition_adet, 0)::bigint,
      COALESCE(ms.one_v_one_adet, 0)::bigint,
      CASE
        WHEN v.metadata ? 'target_question_count'
             AND (v.metadata ->> 'target_question_count') ~ '^[0-9]+$'
        THEN GREATEST(
               (v.metadata ->> 'target_question_count')::integer
                 - COALESCE(ms.aktif_adet, 0),
               0)
      END,
      v.week_number::integer,
      v.vault_kind,
      v.is_active,
      COUNT(*) OVER ()::bigint
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
    WHERE (p_include_inactive OR v.is_active = true)
      AND (p_grade IS NULL OR v.grade_level = p_grade)
      AND (p_subject IS NULL OR v.subject_id = p_subject)
      AND (p_week IS NULL OR v.week_number = p_week)
      AND (p_difficulty IS NULL OR v.difficulty_level = p_difficulty)
      AND (p_vault_type IS NULL OR v.vault_type = p_vault_type)
    ORDER BY v.vault_code, v.id
    LIMIT least(greatest(coalesce(p_limit, 200), 1), 1000)
    OFFSET greatest(coalesce(p_offset, 0), 0);
END;
$body$;

-- ============================================================
-- 3. İZİN MATRİSİ — yalnız bu iki fonksiyon (141:1443 / 150:210
--    desenleri birebir); mevcut roller/izinler DEĞİŞMEZ.
-- ============================================================
REVOKE ALL ON FUNCTION
  public.uretim_planlayici_list_vaults(
    smallint, uuid, integer, text, text, boolean, integer, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.uretim_planlayici_list_vaults(
    smallint, uuid, integer, text, text, boolean, integer, integer)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.uretim_planlayici_list_vault_stock(
    smallint, uuid, integer, text, text, boolean, integer, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.uretim_planlayici_list_vault_stock(
    smallint, uuid, integer, text, text, boolean, integer, integer)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.uretim_planlayici_list_vaults(
  smallint, uuid, integer, text, text, boolean, integer, integer)
  IS 'AK-VAULT-VIS-02: sayfalı/filtreli kasa listesi; yetkili difficulty_level/week_number/vault_kind/is_active + total_count. Varsayılan args = 141 davranışı (is_active, vault_code sırası, LIMIT 200). Yetki kapısı 141 ile birebir.';

COMMENT ON FUNCTION public.uretim_planlayici_list_vault_stock(
  smallint, uuid, integer, text, text, boolean, integer, integer)
  IS 'AK-VAULT-VIS-02: 150 stok okumanın sayfalı/filtreli sürümü; week_number/vault_kind/is_active/total_count eklenir. Varsayılan args = 150 davranışı. Kapsam sayıları AYRI kalır (birleştirilmez).';

-- ============================================================
-- 4. MIGRATION HISTORY — idempotent kayıt (150:225-229 deseni)
-- ============================================================
insert into supabase_migrations.schema_migrations (version, name, statements)
select '164', '164_vault_gorunurluk_rpc', NULL
 where not exists (
   select 1 from supabase_migrations.schema_migrations where version = '164'
 );

-- ============================================================
-- 5. FINAL — fail-closed son denetim (150 $final$ deseni genişletilmiş)
-- ============================================================
DO $final$
DECLARE
  v_name text;
  v_identity_ok boolean;
  v_args integer;
  v_res text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY[
    'uretim_planlayici_list_vaults',
    'uretim_planlayici_list_vault_stock'
  ] LOOP
    -- Tek overload, 8 parametre, SECURITY DEFINER, search_path='' boş.
    SELECT count(*) = 1
         AND bool_and(p.prosecdef)
         AND bool_and(p.proconfig IS NOT NULL)
         AND bool_and(position('search_path TO ' || chr(39) || chr(39)
                               in pg_get_functiondef(p.oid)) <> 0)
         AND bool_and(COALESCE(array_length(p.proargtypes::oid[], 1), 0) = 8)
      INTO v_identity_ok
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = v_name;

    IF v_identity_ok IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'FINAL_164: %. beklenenden farklı (overload/DEFINER/search_path/8-arg) — fail-closed.', v_name;
    END IF;

    -- Tüm parametrelerin DEFAULT'u var (eski () çağrısı korunur).
    -- proargdefaults pg_node_tree'dir (sayılamaz) → kullanıcı sözleşmesi
    -- pg_get_function_arguments içindeki ' DEFAULT ' sayısı = 8 olmalı.
    SELECT count(*) INTO v_args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname = v_name
       AND (length(pg_get_function_arguments(p.oid))
            - length(replace(pg_get_function_arguments(p.oid), ' DEFAULT ', ''))) / 9 = 8;
    IF v_args <> 1 THEN
      RAISE EXCEPTION 'FINAL_164: %. parametre default seti eksik — geriye dönük () çağrısı bozulur, fail-closed.', v_name;
    END IF;
    RAISE NOTICE 'FINAL_164: % imza/varsayılanlar/kolonlar/izinler OK', v_name;

    -- Yeni yetkili kolonlar dönüş tipinde var mı?
    v_res := pg_get_function_result(
      (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname='public' AND p.proname = v_name LIMIT 1));
    IF v_res NOT LIKE '%difficulty_level%' OR v_res NOT LIKE '%week_number%'
       OR v_res NOT LIKE '%vault_kind%' OR v_res NOT LIKE '%is_active%'
       OR v_res NOT LIKE '%total_count%'
    THEN
      RAISE EXCEPTION 'FINAL_164: %. dönüş tipinde yetkili kolonlar eksik — fail-closed.', v_name;
    END IF;

    -- İzin matrisi: anon YOK; authenticated + service_role VAR.
    IF has_function_privilege('anon', format('public.%s(smallint,uuid,integer,text,text,boolean,integer,integer)', v_name), 'EXECUTE') THEN
      RAISE EXCEPTION 'FINAL_164: %. için anon EXECUTE VAR — izin matrisi bozuk, fail-closed.', v_name;
    END IF;
    IF NOT has_function_privilege('authenticated', format('public.%s(smallint,uuid,integer,text,text,boolean,integer,integer)', v_name), 'EXECUTE') THEN
      RAISE EXCEPTION 'FINAL_164: %. için authenticated EXECUTE YOK — izin matrisi bozuk, fail-closed.', v_name;
    END IF;
    IF NOT has_function_privilege('service_role', format('public.%s(smallint,uuid,integer,text,text,boolean,integer,integer)', v_name), 'EXECUTE') THEN
      RAISE EXCEPTION 'FINAL_164: %. için service_role EXECUTE YOK — izin matrisi bozuk, fail-closed.', v_name;
    END IF;
  END LOOP;

  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '164') THEN
    RAISE EXCEPTION 'FINAL_164: history kaydı (version=164) yok — beklenmeyen durum.';
  END IF;

  RAISE NOTICE 'FINAL_164 OK';
END
$final$;

COMMIT;
