-- ============================================================
-- QA: Phase 4B — Schema + Grant Hardening (migration 091)
--
-- Doğrulanacaklar:
--   1. question_similarity_matches.copyright_risk sütunu var mı?
--   2. decide_teacher_review: EXECUTE yalnız authenticated'de mi?
--   3. teacher_review_admin_has_permission: EXECUTE yalnız authenticated'de mi?
--   4. ai_teacher_human_review_audit: anon/authenticated DML yok,
--      service_role DML yok; SELECT yalnız authenticated + service_role'da.
--   5. Audit tablosu RLS açık ve policy aynen duruyor.
--   6. private.submit_originality_review yolu question_similarity_matches'a
--      copyright_risk sütunuyla INSERT edebiliyor mu?
--
-- Tek ROLLBACK transaction; hiçbir şey kalıcı değildir.
-- ============================================================
\set ON_ERROR_STOP on

BEGIN;


-- ============================================================
-- 1. COPYRIGHT RISK SÜTUNU MEVCUT MU?
-- ============================================================

SELECT CASE WHEN EXISTS (
  SELECT 1
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name   = 'question_similarity_matches'
    AND column_name  = 'copyright_risk'
    AND data_type    = 'boolean'
    AND is_nullable  = 'NO'
)
THEN 'PASS' ELSE 'FAIL: copyright_risk column missing or wrong type'
END AS "T-01 copyright_risk column"
;

-- DEFAULT false mü?
SELECT CASE WHEN (
  SELECT column_default
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name   = 'question_similarity_matches'
    AND column_name  = 'copyright_risk'
) = 'false'
THEN 'PASS' ELSE 'FAIL: default is not false'
END AS "T-02 copyright_risk default false"
;


-- ============================================================
-- 2–3. WRAPPER GRANT MATRİSİ
-- ============================================================

-- decide_teacher_review(uuid,text,uuid,text)
SELECT CASE WHEN NOT has_function_privilege(
  'service_role',
  'public.decide_teacher_review(uuid, text, uuid, text)',
  'EXECUTE'
)
THEN 'PASS' ELSE 'FAIL: service_role still has EXECUTE on decide_teacher_review'
END AS "T-03 decide_teacher_review: service_role no EXECUTE"
;

SELECT CASE WHEN has_function_privilege(
  'authenticated',
  'public.decide_teacher_review(uuid, text, uuid, text)',
  'EXECUTE'
)
THEN 'PASS' ELSE 'FAIL: authenticated lost EXECUTE on decide_teacher_review'
END AS "T-04 decide_teacher_review: authenticated EXECUTE"
;

SELECT CASE WHEN NOT has_function_privilege(
  'anon',
  'public.decide_teacher_review(uuid, text, uuid, text)',
  'EXECUTE'
)
THEN 'PASS' ELSE 'FAIL: anon has EXECUTE on decide_teacher_review'
END AS "T-05 decide_teacher_review: anon no EXECUTE"
;

-- teacher_review_admin_has_permission(text)
SELECT CASE WHEN NOT has_function_privilege(
  'service_role',
  'public.teacher_review_admin_has_permission(text)',
  'EXECUTE'
)
THEN 'PASS' ELSE 'FAIL: service_role still has EXECUTE on teacher_review_admin_has_permission'
END AS "T-06 teacher_review_admin_has_permission: service_role no EXECUTE"
;

SELECT CASE WHEN has_function_privilege(
  'authenticated',
  'public.teacher_review_admin_has_permission(text)',
  'EXECUTE'
)
THEN 'PASS' ELSE 'FAIL: authenticated lost EXECUTE on teacher_review_admin_has_permission'
END AS "T-07 teacher_review_admin_has_permission: authenticated EXECUTE"
;

SELECT CASE WHEN NOT has_function_privilege(
  'anon',
  'public.teacher_review_admin_has_permission(text)',
  'EXECUTE'
)
THEN 'PASS' ELSE 'FAIL: anon has EXECUTE on teacher_review_admin_has_permission'
END AS "T-08 teacher_review_admin_has_permission: anon no EXECUTE"
;


-- ============================================================
-- 4. AUDIT TABLE GRANT MATRİSİ
-- ============================================================

-- anon: hiçbir privilege yok
SELECT CASE WHEN NOT has_table_privilege(
  'anon', 'public.ai_teacher_human_review_audit', 'SELECT'
) AND NOT has_table_privilege(
  'anon', 'public.ai_teacher_human_review_audit', 'INSERT'
) AND NOT has_table_privilege(
  'anon', 'public.ai_teacher_human_review_audit', 'UPDATE'
) AND NOT has_table_privilege(
  'anon', 'public.ai_teacher_human_review_audit', 'DELETE'
)
THEN 'PASS' ELSE 'FAIL: anon has unexpected privilege on audit table'
END AS "T-09 audit: anon no privileges"
;

-- authenticated: yalnız SELECT
SELECT CASE WHEN has_table_privilege(
  'authenticated', 'public.ai_teacher_human_review_audit', 'SELECT'
) AND NOT has_table_privilege(
  'authenticated', 'public.ai_teacher_human_review_audit', 'INSERT'
) AND NOT has_table_privilege(
  'authenticated', 'public.ai_teacher_human_review_audit', 'UPDATE'
) AND NOT has_table_privilege(
  'authenticated', 'public.ai_teacher_human_review_audit', 'DELETE'
)
THEN 'PASS' ELSE 'FAIL: authenticated has unexpected privilege on audit table'
END AS "T-10 audit: authenticated SELECT only"
;

-- service_role: yalnız SELECT
SELECT CASE WHEN has_table_privilege(
  'service_role', 'public.ai_teacher_human_review_audit', 'SELECT'
) AND NOT has_table_privilege(
  'service_role', 'public.ai_teacher_human_review_audit', 'INSERT'
) AND NOT has_table_privilege(
  'service_role', 'public.ai_teacher_human_review_audit', 'UPDATE'
) AND NOT has_table_privilege(
  'service_role', 'public.ai_teacher_human_review_audit', 'DELETE'
)
THEN 'PASS' ELSE 'FAIL: service_role has unexpected privilege on audit table'
END AS "T-11 audit: service_role SELECT only"
;


-- ============================================================
-- 5. AUDIT TABLOSU RLS + POLICY KONTROLÜ
-- ============================================================

SELECT CASE WHEN (
  SELECT relrowsecurity
  FROM pg_class
  WHERE oid = 'public.ai_teacher_human_review_audit'::regclass
)
THEN 'PASS' ELSE 'FAIL: RLS not enabled on audit table'
END AS "T-12 audit: RLS enabled"
;

SELECT CASE WHEN EXISTS (
  SELECT 1
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename  = 'ai_teacher_human_review_audit'
    AND policyname = 'Admins can view teacher review audit'
    AND permissive = 'PERMISSIVE'
    AND roles       = '{authenticated}'
    AND cmd         = 'SELECT'
)
THEN 'PASS' ELSE 'FAIL: admin SELECT policy missing or changed'
END AS "T-13 audit: admin SELECT policy intact"
;


-- ============================================================
-- 6. SUBMIT_ORIGINALITY_REVIEW: COPYRIGHT_RISK INSERT YOLU
-- ============================================================
-- private.submit_originality_review() iki reviewer tamamladığında
-- question_similarity_matches tablosuna INSERT yapar.
-- copyright_risk sütunu eklendikten sonra bu INSERT artık hatasız
-- çalışmalıdır.

DO $$
DECLARE
  v_staging_source  uuid;
  v_staging_target  uuid;
  v_run_id          uuid;
  v_review_result   jsonb;
  v_match_count     bigint;
  v_copyright_risk  boolean;
BEGIN
  -- -- aid: staging question (source) — submit_originality_review bunu kullanır
  INSERT INTO public.ai_question_staging
    (staging_source, question_text, option_a, option_b,
     option_c, option_d, option_e, proposed_correct_answer)
  VALUES
    ('manual_candidate', 'QA-091 source question',
     'A', 'B', 'C', 'D', 'E', 'A')
  RETURNING id INTO v_staging_source;

  -- staging question (target) — matched_staging_id olarak kullanılacak
  INSERT INTO public.ai_question_staging
    (staging_source, question_text, option_a, option_b,
     option_c, option_d, option_e, proposed_correct_answer)
  VALUES
    ('manual_candidate', 'QA-091 match target question',
     'A', 'B', 'C', 'D', 'E', 'A')
  RETURNING id INTO v_staging_target;

  -- verification run: waiting_reviewer_1
  INSERT INTO public.ai_originality_verification_runs
    (staging_question_id, status,
     minimum_originality_score, maximum_similarity_score,
     critical_similarity_score, minimum_confidence)
  VALUES
    (v_staging_source, 'waiting_reviewer_1',
     0.90, 0.80, 0.92, 0.90)
  RETURNING id INTO v_run_id;

  -- service_role bağlamını ayarla
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);

  -- Reviewer 1: high similarity, matched_staging_id ile
  v_review_result := private.submit_originality_review(
    p_verification_run_id        := v_run_id,
    p_reviewer_number            := 1,
    p_originality_score          := 0.95,
    p_exact_similarity_score     := 0.85,
    p_text_similarity_score      := 0.70,
    p_semantic_similarity_score  := 0.60,
    p_structural_similarity_score:= 0.50,
    p_concept_similarity_score   := 0.55,
    p_solution_path_similarity_score := 0.40,
    p_highest_similarity_type    := 'exact',
    p_matched_question_id        := NULL,
    p_matched_staging_id         := v_staging_target,
    p_matched_source_id          := NULL,
    p_superficial_rewrite_detected := false,
    p_template_copy_detected     := false,
    p_solution_path_copy_risk    := false,
    p_copyright_risk_level       := 'low',
    p_confidence_score           := 0.95,
    p_provider_name              := 'qa',
    p_model_name                 := 'test',
    p_prompt_version             := 'v1',
    p_review_summary             := 'QA-091 reviewer 1',
    p_evidence                   := '{}'::jsonb,
    p_metadata                   := '{}'::jsonb
  );

  IF (v_review_result ->> 'status') IS DISTINCT FROM 'stored' THEN
    RAISE EXCEPTION 'T-14: reviewer 1 unexpected status: %', v_review_result;
  END IF;

  -- Reviewer 2: high similarity, matched_staging_id ile
  v_review_result := private.submit_originality_review(
    p_verification_run_id        := v_run_id,
    p_reviewer_number            := 2,
    p_originality_score          := 0.93,
    p_exact_similarity_score     := 0.82,
    p_text_similarity_score      := 0.68,
    p_semantic_similarity_score  := 0.55,
    p_structural_similarity_score:= 0.45,
    p_concept_similarity_score   := 0.50,
    p_solution_path_similarity_score := 0.38,
    p_highest_similarity_type    := 'exact',
    p_matched_question_id        := NULL,
    p_matched_staging_id         := v_staging_target,
    p_matched_source_id          := NULL,
    p_superficial_rewrite_detected := false,
    p_template_copy_detected     := false,
    p_solution_path_copy_risk    := false,
    p_copyright_risk_level       := 'low',
    p_confidence_score           := 0.93,
    p_provider_name              := 'qa',
    p_model_name                 := 'test',
    p_prompt_version             := 'v1',
    p_review_summary             := 'QA-091 reviewer 2',
    p_evidence                   := '{}'::jsonb,
    p_metadata                   := '{}'::jsonb
  );

  -- question_similarity_matches'a INSERT oldu mu?
  SELECT count(*), bool_or(copyright_risk)
  INTO v_match_count, v_copyright_risk
  FROM public.question_similarity_matches
  WHERE candidate_staging_id = v_staging_source;

  IF v_match_count IS NULL OR v_match_count < 1 THEN
    RAISE EXCEPTION 'T-14: no similarity match row inserted (count=%)', v_match_count;
  END IF;

  -- copyright_risk sütunu boolean ve default false olmalı
  IF v_copyright_risk IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'T-14: copyright_risk expected false, got %', v_copyright_risk;
  END IF;

  RAISE NOTICE 'T-14 PASS: similarity match inserted with copyright_risk=false';

  -- Temizlik (ROLLBACK zaten yapar ama garanti olsun)
  DELETE FROM public.question_similarity_matches
    WHERE candidate_staging_id = v_staging_source;
  DELETE FROM public.ai_originality_verification_runs WHERE id = v_run_id;
  DELETE FROM public.ai_originality_reviews WHERE verification_run_id = v_run_id;
  DELETE FROM public.ai_question_staging WHERE id IN (v_staging_source, v_staging_target);

END $$;


-- ============================================================
-- ÖZET
-- ============================================================

SELECT '--- QA Phase 4B Summary ---' AS info;


ROLLBACK;
