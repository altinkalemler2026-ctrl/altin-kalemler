-- ============================================================
-- QA: Teacher Review RPC Security Hardening (migration 090)
--
-- Public SECURITY DEFINER sızıntısının kapandığını doğrular:
--   1. Katalog: public.* -> prosecdef=false (INVOKER), search_path=''
--      private.* -> prosecdef=true (DEFINER), search_path=''
--   2. Grant matrisi: PUBLIC/anon EXECUTE yok; authenticated var;
--      service_role yalnızca private implementasyonlarda.
--   3. Yetki (permission) matrisi decide_teacher_review üzerinden:
--      anon / non-admin / view-only admin REDDEDİLİR,
--      questions.approve ve questions.reject sahipleri başarılı olur,
--      correction proposal yalnızca aynı run + recheck_passed ise uygulanır,
--      cross-run proposal + malformed decision REDDEDİLİR.
--   4. EKLENMEZLİK (invariant): audit yazımı SECURITY DEFINER fonksiyonu
--      (sahip bağlamı) tarafından atomik yapılır; audit SELECT yetkisi
--      authenticated'e migration 047'den bu yana AÇILMAMIŞTIR (öncesinde
--      de böyleydi; 090 değiştirmez) -> audit doğrulaması bu QA'da sahip
--      (postgres) rolüyle yapılır.
--   5. RLS regression: "Admins can view teacher review audit" politikası
--      doğrudan değişmeden aynen durur ve hâlâ public sarmalayıcıyı
--      ('questions.view') kullanır (katalog üzerinden kanıtlanır).
--
-- Tek ROLLBACK transaction içinde çalışır; hiçbir şey kalıcı değildir.
-- Pattern: qa_rls_089_phase4a.sql (gerçek auth.users fixture'ları,
-- SET ROLE authenticated + request.jwt.claim.sub, SAVEPOINT denial
-- probe'ları, son ROLLBACK).
-- ============================================================
\set ON_ERROR_STOP on

BEGIN;


-- ============================================================
-- 0. FIXTURES
--
-- Senaryo başına AYRI staging + run + (gerekiyorsa) proposal:
--   R1: approve admin -> approve + correction
--   R2: reject admin   -> reject
--   R3: approve admin  -> önce cross-run / staging-mismatch RED,
--                        sonra kendi proposal'ı ile approve BAŞARILI
--   R4: denial probe'ları için (dokunulmayan negatif kontrol)
-- ============================================================

-- A: approve admin (questions.approve + questions.view)
-- B: reject admin  (questions.reject + questions.view)
-- C: view-only admin (questions.view only)
-- N: non-admin authenticated
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at, raw_app_meta_data)
VALUES
  ('f0900001-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'qa-tr-approve-090@example.test',
   crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}'),
  ('f0900002-0000-4000-8000-000000000002', '00000000-0000-0000-8000-000000000000',
   'authenticated', 'authenticated', 'qa-tr-reject-090@example.test',
   crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}'),
  ('f0900003-0000-4000-8000-000000000003', '00000000-0000-0000-8000-000000000000',
   'authenticated', 'authenticated', 'qa-tr-view-090@example.test',
   crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}'),
  ('f0900004-0000-4000-8000-000000000004', '00000000-0000-0000-8000-000000000000',
   'authenticated', 'authenticated', 'qa-tr-nonadmin-090@example.test',
   crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}');

-- Roles
INSERT INTO public.admin_roles (id, role_code, name, is_active, created_at, updated_at)
SELECT gen_random_uuid(), v.rc, v.nm, true, now(), now()
FROM (VALUES
  ('qa_tr_approve_090', 'QA TR Approve 090'),
  ('qa_tr_reject_090',  'QA TR Reject 090'),
  ('qa_tr_view_090',    'QA TR View 090')
) AS v(rc, nm);

-- User -> role
INSERT INTO public.admin_user_roles (user_id, role_id, assigned_at)
SELECT 'f0900001-0000-4000-8000-000000000001'::uuid, r.id, now()
FROM public.admin_roles r WHERE r.role_code='qa_tr_approve_090';
INSERT INTO public.admin_user_roles (user_id, role_id, assigned_at)
SELECT 'f0900002-0000-4000-8000-000000000002'::uuid, r.id, now()
FROM public.admin_roles r WHERE r.role_code='qa_tr_reject_090';
INSERT INTO public.admin_user_roles (user_id, role_id, assigned_at)
SELECT 'f0900003-0000-4000-8000-000000000003'::uuid, r.id, now()
FROM public.admin_roles r WHERE r.role_code='qa_tr_view_090';

-- Role -> permissions
INSERT INTO public.admin_role_permissions (role_id, permission_id, created_at)
SELECT r.id, ap.id, now()
FROM public.admin_roles r, public.admin_permissions ap
WHERE r.role_code='qa_tr_approve_090' AND ap.permission_code IN ('questions.approve','questions.view');
INSERT INTO public.admin_role_permissions (role_id, permission_id, created_at)
SELECT r.id, ap.id, now()
FROM public.admin_roles r, public.admin_permissions ap
WHERE r.role_code='qa_tr_reject_090' AND ap.permission_code IN ('questions.reject','questions.view');
INSERT INTO public.admin_role_permissions (role_id, permission_id, created_at)
SELECT r.id, ap.id, now()
FROM public.admin_roles r, public.admin_permissions ap
WHERE r.role_code='qa_tr_view_090' AND ap.permission_code IN ('questions.view');

-- Staging questions (S1..S4)
INSERT INTO public.ai_question_staging
  (id, staging_source, proposed_question_code, question_text, option_a, option_b,
   option_c, proposed_correct_answer, staging_status, metadata)
VALUES
  ('f0908001-0000-4000-8000-000000000001', 'ai_generated', 'QA-TR-090-1', 'ORIGINAL-1', 'A1', 'B1', 'C1', 'A', 'draft', '{}'),
  ('f0908002-0000-4000-8000-000000000002', 'ai_generated', 'QA-TR-090-2', 'ORIGINAL-2', 'A2', 'B2', 'C2', 'A', 'draft', '{}'),
  ('f0908003-0000-4000-8000-000000000003', 'ai_generated', 'QA-TR-090-3', 'ORIGINAL-3', 'A3', 'B3', 'C3', 'A', 'draft', '{}'),
  ('f0908004-0000-4000-8000-000000000004', 'ai_generated', 'QA-TR-090-4', 'ORIGINAL-4', 'A4', 'B4', 'C4', 'A', 'draft', '{}');

-- Teacher review runs (R1..R4) waiting for human review.
-- Tek subject kullanılır (CROSS JOIN test verisini katlar/çakıştırır).
INSERT INTO public.ai_teacher_review_runs
  (id, staging_question_id, subject_id, status, current_stage, overall_risk_level,
   correction_required, correction_completed, human_review_required, human_review_reason, metadata)
SELECT v.rid, v.sid,
   (SELECT s.id FROM public.subjects s ORDER BY s.id LIMIT 1) AS subject_id,
   'human_review_required', 'human_review', 'high',
   false, false, true, 'QA fixture', '{}'
FROM (VALUES
  ('f0903001-0000-4000-8000-000000000001'::uuid, 'f0908001-0000-4000-8000-000000000001'::uuid),
  ('f0903002-0000-4000-8000-000000000002'::uuid, 'f0908002-0000-4000-8000-000000000002'::uuid),
  ('f0903003-0000-4000-8000-000000000003'::uuid, 'f0908003-0000-4000-8000-000000000003'::uuid),
  ('f0903004-0000-4000-8000-000000000004'::uuid, 'f0908004-0000-4000-8000-000000000004'::uuid)
) AS v(rid, sid)
ORDER BY v.rid;

-- Correction proposal for R1 (recheck_passed) — approve-with-correction path.
INSERT INTO public.ai_teacher_correction_proposals
  (id, review_run_id, staging_question_id, status, proposed_question_text,
   proposed_option_b, proposed_correct_answer, proposed_solution, change_summary,
   confidence_score, requires_recheck, human_review_required, applied_to_staging, metadata)
VALUES
  ('f0909001-0000-4000-8000-000000000001', 'f0903001-0000-4000-8000-000000000001',
   'f0908001-0000-4000-8000-000000000001', 'recheck_passed', 'CORRECTED-1',
   'B1-FIXED', 'B', '{"steps":["verify"]}'::jsonb, 'qa fix 1',
   0.98, false, true, false, '{}');

-- Correction proposal for R3 (recheck_passed) — legitimate R3 approve.
INSERT INTO public.ai_teacher_correction_proposals
  (id, review_run_id, staging_question_id, status, proposed_question_text,
   proposed_option_b, proposed_correct_answer, proposed_solution, change_summary,
   confidence_score, requires_recheck, human_review_required, applied_to_staging, metadata)
VALUES
  ('f0909003-0000-4000-8000-000000000003', 'f0903003-0000-4000-8000-000000000003',
   'f0908003-0000-4000-8000-000000000003', 'recheck_passed', 'CORRECTED-3',
   'B3-FIXED', 'C', '{"steps":["verify"]}'::jsonb, 'qa fix 3',
   0.99, false, true, false, '{}');

-- Correction proposal for R4 (recheck_passed) — cross-run / staging-mismatch
-- probe hedefi (R4'ün proposal'ı; R3'e ve R1'e yabancıdır).
INSERT INTO public.ai_teacher_correction_proposals
  (id, review_run_id, staging_question_id, status, proposed_question_text,
   proposed_correct_answer, confidence_score, requires_recheck, human_review_required,
   applied_to_staging, metadata)
VALUES
  ('f0909004-0000-4000-8000-000000000004', 'f0903004-0000-4000-8000-000000000004',
   'f0908004-0000-4000-8000-000000000004', 'recheck_passed', 'CORRECTED-4',
   'C', 0.97, false, true, false, '{}');


-- ============================================================
-- 1. KATALOG: SECURITY DEFINER sızıntısı kapandı mı?
-- ============================================================

SELECT
  'CATALOG_PUBLIC_INVOKER' AS probe,
  p.proname,
  p.prosecdef AS is_definer_expected_false
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('decide_teacher_review','teacher_review_admin_has_permission')
ORDER BY p.proname;

SELECT
  'CATALOG_PRIVATE_DEFINER' AS probe,
  p.proname,
  p.prosecdef AS is_definer_expected_true
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname IN ('decide_teacher_review','teacher_review_admin_has_permission')
ORDER BY p.proname;

SELECT
  'CATALOG_SEARCH_PATH_EMPTY' AS probe,
  n.nspname || '.' || p.proname AS fn,
  p.proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public','private')
  AND p.proname IN ('decide_teacher_review','teacher_review_admin_has_permission')
ORDER BY n.nspname, p.proname;

-- GRANT matrisi (has_function_privilege):
--   public funcs: public=anon=f, authenticated=t, service_role=f
--   private funcs: public=anon=f, authenticated=t, service_role=t
SELECT
  'GRANT_MATRIX' AS probe,
  n.nspname || '.' || p.proname AS fn,
  has_function_privilege('public', p.oid, 'EXECUTE') AS pub_grant,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_grant,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_grant,
  has_function_privilege('service_role', p.oid, 'EXECUTE') AS svc_grant
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public','private')
  AND p.proname IN ('decide_teacher_review','teacher_review_admin_has_permission')
ORDER BY n.nspname, p.proname;

-- Audit RLS politikası hâlâ duruyor ve hâlâ public sarmalayıcıyı kullanıyor
-- (090'da politika DROP/CREATE edilmedi — fonksiyon bağlamı değişmedi).
SELECT
  'AUDIT_RLS_POLICY_REF' AS probe,
  pol.polname,
  pg_get_expr(pol.polqual, pol.polrelid) AS qual
FROM pg_policy pol
JOIN pg_class c ON c.oid = pol.polrelid
WHERE c.relname = 'ai_teacher_human_review_audit'
  AND pol.polname = 'Admins can view teacher review audit';

-- authenticated'e audit SELECT açılmadığını doğrula (047'den bu yana
-- service_role dışında yok — 090 değiştirmedi).
SELECT
  'AUDIT_NO_AUTH_SELECT' AS probe,
  count(*) AS authenticated_select_grants
FROM information_schema.role_table_grants
WHERE table_schema='public'
  AND table_name='ai_teacher_human_review_audit'
  AND grantee='authenticated'
  AND privilege_type='SELECT';


-- ============================================================
-- 2. ANON: RPC çağıramaz (EXECUTE yok) -> reddedilir
-- ============================================================
SET ROLE anon;
\set ON_ERROR_STOP off
SAVEPOINT qa_anon_decide;
SELECT public.decide_teacher_review(
  'f0903001-0000-4000-8000-000000000001', 'approved'
);
ROLLBACK TO SAVEPOINT qa_anon_decide;
SELECT 'ANON_DECIDE_DENIED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

\set ON_ERROR_STOP off
SAVEPOINT qa_anon_helper;
SELECT public.teacher_review_admin_has_permission('questions.view');
ROLLBACK TO SAVEPOINT qa_anon_helper;
SELECT 'ANON_HELPER_DENIED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on
RESET ROLE;
RESET request.jwt.claim.sub;


-- ============================================================
-- 3. NON-ADMIN authenticated: helper false + decide reddedilir
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'f0900004-0000-4000-8000-000000000004';

SELECT
  'NONADMIN_HELPER_FALSE' AS probe,
  public.teacher_review_admin_has_permission('questions.approve') AS can_approve,
  public.teacher_review_admin_has_permission('questions.reject') AS can_reject,
  public.teacher_review_admin_has_permission('questions.view') AS can_view;

\set ON_ERROR_STOP off
SAVEPOINT qa_n_decide;
SELECT public.decide_teacher_review(
  'f0903004-0000-4000-8000-000000000004', 'approved'
);
ROLLBACK TO SAVEPOINT qa_n_decide;
SELECT 'NONADMIN_DECIDE_DENIED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on
RESET ROLE;
RESET request.jwt.claim.sub;


-- ============================================================
-- 4. VIEW-ONLY ADMIN: questions.view var, approve/reject yok
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'f0900003-0000-4000-8000-000000000003';

SELECT
  'VIEWADMIN_HELPER_PERMS' AS probe,
  public.teacher_review_admin_has_permission('questions.view') AS can_view,
  public.teacher_review_admin_has_permission('questions.approve') AS can_approve,
  public.teacher_review_admin_has_permission('questions.reject') AS can_reject;

\set ON_ERROR_STOP off
SAVEPOINT qa_v_approve;
SELECT public.decide_teacher_review(
  'f0903004-0000-4000-8000-000000000004', 'approved'
);
ROLLBACK TO SAVEPOINT qa_v_approve;
SELECT 'VIEWADMIN_APPROVE_DENIED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

\set ON_ERROR_STOP off
SAVEPOINT qa_v_reject;
SELECT public.decide_teacher_review(
  'f0903004-0000-4000-8000-000000000004', 'rejected'
);
ROLLBACK TO SAVEPOINT qa_v_reject;
SELECT 'VIEWADMIN_REJECT_DENIED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on
RESET ROLE;
RESET request.jwt.claim.sub;


-- ============================================================
-- 5. APPROVE ADMIN: R1 approve + correction atomik uygulanır
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'f0900001-0000-4000-8000-000000000001';

SELECT
  'APPROVEADMIN_HELPER' AS probe,
  public.teacher_review_admin_has_permission('questions.approve') AS can_approve;

SELECT
  'APPROVE_WITH_CORRECTION_RESULT' AS probe,
  public.decide_teacher_review(
    'f0903001-0000-4000-8000-000000000001',
    'approved',
    'f0909001-0000-4000-8000-000000000001',
    'qa approve with correction'
  ) AS result_json;

SELECT 'CORRECTION_STAGING_APPLIED' AS probe, question_text, option_b, proposed_correct_answer
FROM public.ai_question_staging
WHERE id = 'f0908001-0000-4000-8000-000000000001';

SELECT 'CORRECTION_PROPOSAL_STATE' AS probe, status, human_review_required, applied_to_staging, applied_by
FROM public.ai_teacher_correction_proposals
WHERE id = 'f0909001-0000-4000-8000-000000000001';

SELECT 'APPROVE_RUN_STATE' AS probe, status, current_stage, human_review_required, human_decision
FROM public.ai_teacher_review_runs
WHERE id = 'f0903001-0000-4000-8000-000000000001';
RESET ROLE;
RESET request.jwt.claim.sub;


-- ============================================================
-- 6. REJECT ADMIN: R2 reject edilir
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'f0900002-0000-4000-8000-000000000002';

SELECT
  'REJECT_RESULT' AS probe,
  public.decide_teacher_review(
    'f0903002-0000-4000-8000-000000000002',
    'rejected',
    NULL,
    'qa reject'
  ) AS result_json;

SELECT 'REJECT_RUN_STATE' AS probe, status, current_stage, human_review_required, human_decision
FROM public.ai_teacher_review_runs
WHERE id = 'f0903002-0000-4000-8000-000000000002';
RESET ROLE;
RESET request.jwt.claim.sub;


-- ============================================================
-- 7. R3: malformed / cross-run / staging-mismatch RED, doğru path BAŞARILI
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'f0900001-0000-4000-8000-000000000001';

-- (a) Malformed decision
\set ON_ERROR_STOP off
SAVEPOINT qa_malformed;
SELECT public.decide_teacher_review(
  'f0903003-0000-4000-8000-000000000003', 'bogus_decision'
);
ROLLBACK TO SAVEPOINT qa_malformed;
SELECT 'MALFORMED_DECISION_DENIED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

-- (b) Cross-run proposal: R1'in proposal'ını R3'e uygulamaya çalış => RED
\set ON_ERROR_STOP off
SAVEPOINT qa_cross_run;
SELECT public.decide_teacher_review(
  'f0903003-0000-4000-8000-000000000003',
  'approved',
  'f0909001-0000-4000-8000-000000000001',  -- R1'e ait
  'cross-run proposal'
);
ROLLBACK TO SAVEPOINT qa_cross_run;
SELECT 'CROSSRUN_PROPOSAL_DENIED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

-- (c) Staging-mismatch: R4'ün proposal'ını R3'e uygulamaya çalış => RED
--     (proposal R4'e ait => önce run eşleşme (b) ile aynı reddi verir;
--      izole staging kontrolü (d)'de doğrulanır.)
\set ON_ERROR_STOP off
SAVEPOINT qa_stage_mismatch;
SELECT public.decide_teacher_review(
  'f0903003-0000-4000-8000-000000000003',
  'approved',
  'f0909004-0000-4000-8000-000000000004',  -- R4'ün proposal'ı
  'staging mismatch'
);
ROLLBACK TO SAVEPOINT qa_stage_mismatch;
SELECT 'WILDCARD_PROPOSAL_DENIED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

-- (d) Doğru bağlam: R3 kendi proposal'ı ile approve => BAŞARILI
SELECT 'APPROVE_R3_OK' AS probe,
       public.decide_teacher_review(
         'f0903003-0000-4000-8000-000000000003',
         'approved',
         'f0909003-0000-4000-8000-000000000003',
         'qa approve r3'
       ) AS result_json;

SELECT 'R3_STAGING_APPLIED' AS probe, question_text, option_b, proposed_correct_answer
FROM public.ai_question_staging
WHERE id = 'f0908003-0000-4000-8000-000000000003';

SELECT 'R3_RUN_STATE' AS probe, status, current_stage, human_review_required, human_decision
FROM public.ai_teacher_review_runs
WHERE id = 'f0903003-0000-4000-8000-000000000003';
RESET ROLE;
RESET request.jwt.claim.sub;


-- ============================================================
-- 8. R4 dokunulmamış kalmalı; audit atomik yazıldı (sahip okur)
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'f0900004-0000-4000-8000-000000000004';

SELECT 'R4_UNTOUCHED' AS probe, status, current_stage
FROM public.ai_teacher_review_runs
WHERE id = 'f0903004-0000-4000-8000-000000000004';
RESET ROLE;
RESET request.jwt.claim.sub;

-- Audit yazımı SECURITY DEFINER fonksiyonu (sahip bağlamı) ile atomik yapılır.
-- (authenticated bu tabloyu SELECT edemez — 047'den bu yana tasarım böyledir;
--  okuma, audit.view dışında değil, hiçbir browser rolüne açılmamıştır.)
SELECT 'RUN1_AUDIT_ATOMIC' AS probe, action, correction_proposal_id, performed_by, notes
FROM public.ai_teacher_human_review_audit
WHERE review_run_id = 'f0903001-0000-4000-8000-000000000001'
ORDER BY created_at;

SELECT 'RUN2_AUDIT_ATOMIC' AS probe, action, correction_proposal_id, performed_by, notes
FROM public.ai_teacher_human_review_audit
WHERE review_run_id = 'f0903002-0000-4000-8000-000000000002'
ORDER BY created_at;

SELECT 'RUN3_AUDIT_ATOMIC' AS probe, action, correction_proposal_id, performed_by, notes
FROM public.ai_teacher_human_review_audit
WHERE review_run_id = 'f0903003-0000-4000-8000-000000000003'
ORDER BY created_at;


ROLLBACK;
SELECT 'ROLLED_BACK' AS probe;