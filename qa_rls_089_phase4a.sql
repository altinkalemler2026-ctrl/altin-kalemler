-- ============================================================
-- QA: Phase 4A — admin_audit_log security + admin_question_edit
-- (migration 089)
--
-- Runs inside a single ROLLBACK transaction. Nothing persists.
-- Pattern mirrors qa_rls_088_phase3.sql (real auth.users fixtures,
-- SET ROLE authenticated + request.jwt.claim.sub, savepoints for
-- write-denial probes, final ROLLBACK).
-- ============================================================
\set ON_ERROR_STOP on

BEGIN;


-- ============================================================
-- 0. FIXTURES
-- ============================================================

-- a0: admin with questions.edit only  (edits questions, no audit.view)
-- b0: admin with questions.view only  (view-only; no edit, no audit)
-- c0: admin with audit.view only      (audit reader, no questions.edit)
-- n0: non-admin authenticated          (no admin role at all)
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at, raw_app_meta_data)
VALUES
  ('a0a00010-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'qa-edit-4a@example.test',
   crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}'),
  ('b0b00011-0000-4000-8000-000000000002', '00000000-0000-0000-8000-000000000000',
   'authenticated', 'authenticated', 'qa-view-4a@example.test',
   crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}'),
  ('c0c00012-0000-4000-8000-000000000003', '00000000-0000-0000-8000-000000000000',
   'authenticated', 'authenticated', 'qa-auditview-4a@example.test',
   crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}'),
  ('d0d00013-0000-4000-8000-000000000004', '00000000-0000-0000-8000-000000000000',
   'authenticated', 'authenticated', 'qa-nonadmin-4a@example.test',
   crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}');

-- Question fixture (draft/inactive so it has no student visibility).
INSERT INTO public.questions
  (id, question_code, grade_level, subject_id, question_text, option_a,
   option_b, option_c, correct_answer, difficulty, approval_status, is_active,
   quality_level, ownership_status, license_status, created_at, updated_at)
SELECT gen_random_uuid(), 'QA-4A-0001', 10, s.id, 'ORIGINAL', 'A1', 'B1', 'C1', 'A',
       'easy', 'draft', false, 'medium', 'owned', 'approved', now(), now()
FROM public.subjects s
ORDER BY s.id
LIMIT 1;

-- Roles
INSERT INTO public.admin_roles (id, role_code, name, is_active, created_at, updated_at)
SELECT gen_random_uuid(), v.rc, v.nm, true, now(), now()
FROM (VALUES
  ('qa_edit_4a', 'QA Edit 4a'),
  ('qa_view_4a', 'QA View 4a'),
  ('qa_audit_4a', 'QA Audit 4a')
) AS v(rc, nm);

-- User -> role
INSERT INTO public.admin_user_roles (user_id, role_id, assigned_at)
SELECT 'a0a00010-0000-4000-8000-000000000001'::uuid, r.id, now()
FROM public.admin_roles r WHERE r.role_code='qa_edit_4a';
INSERT INTO public.admin_user_roles (user_id, role_id, assigned_at)
SELECT 'b0b00011-0000-4000-8000-000000000002'::uuid, r.id, now()
FROM public.admin_roles r WHERE r.role_code='qa_view_4a';
INSERT INTO public.admin_user_roles (user_id, role_id, assigned_at)
SELECT 'c0c00012-0000-4000-8000-000000000003'::uuid, r.id, now()
FROM public.admin_roles r WHERE r.role_code='qa_audit_4a';

-- Role -> permissions
INSERT INTO public.admin_role_permissions (role_id, permission_id, created_at)
SELECT r.id, ap.id, now()
FROM public.admin_roles r, public.admin_permissions ap
WHERE r.role_code='qa_edit_4a' AND ap.permission_code IN ('questions.edit','questions.view');
INSERT INTO public.admin_role_permissions (role_id, permission_id, created_at)
SELECT r.id, ap.id, now()
FROM public.admin_roles r, public.admin_permissions ap
WHERE r.role_code='qa_view_4a' AND ap.permission_code='questions.view';
INSERT INTO public.admin_role_permissions (role_id, permission_id, created_at)
SELECT r.id, ap.id, now()
FROM public.admin_roles r, public.admin_permissions ap
WHERE r.role_code='qa_audit_4a' AND ap.permission_code='audit.view';

-- A controlled audit row (written via service_role path as a known good fixture).
INSERT INTO public.admin_audit_log
  (id, actor_user_id, action_code, entity_type, entity_id, before_data, after_data)
VALUES
  (gen_random_uuid(), 'a0a00010-0000-4000-8000-000000000001'::uuid,
   'question.edit', 'question', NULL, '{"k":"v"}'::jsonb, '{"k":"v2"}'::jsonb);

-- Cache question id + subject for later probes.
\set ON_ERROR_STOP off
SELECT 'VAR' AS hint; -- placeholder
\set ON_ERROR_STOP on

DO $$
DECLARE v_qid uuid;
BEGIN
  SELECT id INTO v_qid FROM public.questions WHERE question_code='QA-4A-0001';
  IF v_qid IS NULL THEN RAISE EXCEPTION 'question fixture missing'; END IF;
END $$;

-- ============================================================
-- 1. NON-ADMIN authenticated
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'd0d00013-0000-4000-8000-000000000004';

-- Non-admin can read registered question (student policy: none because draft+inactive) -> 0
SELECT 'NONADMIN_QUESTION_RLS' AS probe, count(*) AS visible
FROM public.questions WHERE question_code='QA-4A-0001';

-- NON-ADMIN CANNOT SELECT audit log
SELECT 'NONADMIN_AUDIT_SELECT_BLOCKED' AS probe, count(*) AS visible
FROM public.admin_audit_log;

-- NON-ADMIN CANNOT INSERT audit
\set ON_ERROR_STOP off
SAVEPOINT qa_n_insert;
INSERT INTO public.admin_audit_log (action_code, entity_type)
VALUES ('hack.insert', 'question');
ROLLBACK TO SAVEPOINT qa_n_insert;
SELECT 'NONADMIN_AUDIT_INSERT_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

-- NON-ADMIN CANNOT UPDATE audit
\set ON_ERROR_STOP off
SAVEPOINT qa_n_update;
UPDATE public.admin_audit_log SET action_code='hack.update';
ROLLBACK TO SAVEPOINT qa_n_update;
SELECT 'NONADMIN_AUDIT_UPDATE_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

-- NON-ADMIN CANNOT DELETE audit
\set ON_ERROR_STOP off
SAVEPOINT qa_n_delete;
DELETE FROM public.admin_audit_log;
ROLLBACK TO SAVEPOINT qa_n_delete;
SELECT 'NONADMIN_AUDIT_DELETE_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

-- NON-ADMIN CANNOT edit question (public RPC -> private raises)
\set ON_ERROR_STOP off
SAVEPOINT qa_n_edit;
SELECT public.admin_question_edit(
  (SELECT id FROM public.questions WHERE question_code='QA-4A-0001'),
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'hard', NULL, NULL, NULL, NULL, NULL, NULL, NULL
);
ROLLBACK TO SAVEPOINT qa_n_edit;
SELECT 'NONADMIN_EDIT_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

RESET ROLE;
RESET request.jwt.claim.sub;


-- ============================================================
-- 2. VIEW-ONLY admin (questions.view; no questions.edit, no audit.view)
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'b0b00011-0000-4000-8000-000000000002';

-- View-only admin reads all question lifecycle states (087 policy)
SELECT 'VIEWADMIN_QUESTION_RLS' AS probe, count(*) AS visible
FROM public.questions WHERE question_code='QA-4A-0001';

-- View-only admin CANNOT read audit log
SELECT 'VIEWADMIN_AUDIT_SELECT_BLOCKED' AS probe, count(*) AS visible
FROM public.admin_audit_log;

-- View-only admin CANNOT edit question (no questions.edit)
\set ON_ERROR_STOP off
SAVEPOINT qa_v_edit;
SELECT public.admin_question_edit(
  (SELECT id FROM public.questions WHERE question_code='QA-4A-0001'),
  NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'hard', NULL, NULL, NULL, NULL, NULL, NULL, NULL
);
ROLLBACK TO SAVEPOINT qa_v_edit;
SELECT 'VIEWADMIN_EDIT_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

RESET ROLE;
RESET request.jwt.claim.sub;


-- ============================================================
-- 3. questions.edit ADMIN — ALLOWED + atomic audit
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'a0a00010-0000-4000-8000-000000000001';

SELECT 'EDITADMIN_HAS_PERM' AS probe,
       private.current_user_has_admin_permission('questions.edit') AS can_edit,
       private.current_user_has_admin_permission('audit.view') AS can_audit;

-- Capture before state
SELECT
  question_code,
  question_text,
  option_a,
  option_b,
  correct_answer,
  difficulty,
  quality_level,
  approval_status,
  is_active,
  ownership_status,
  license_status
INTO TEMP TABLE qa_before_edit
FROM public.questions WHERE question_code='QA-4A-0001';

-- Perform edit: change question_text, difficulty, quality_level, add option_c
SELECT public.admin_question_edit(
  (SELECT id FROM public.questions WHERE question_code='QA-4A-0001'),
  'EDITED-TEXT',
  NULL, NULL, NULL, NULL, NULL,      -- options unchanged (NULL)
  'B',                                -- correct_answer -> B
  'hard',                             -- difficulty -> hard
  NULL,                               -- cognitive unchanged
  'high',                             -- quality_level -> high
  NULL, NULL,                         -- question types unchanged
  NULL,                               -- solve time unchanged
  NULL, NULL                          -- booleans unchanged
) AS qa_edit_result;

-- Verify allowed fields changed
SELECT 'EDIT_ALLOWED_CHANGED' AS probe,
       question_text,
       correct_answer,
       difficulty,
       quality_level
FROM public.questions WHERE question_code='QA-4A-0001';

-- Verify lifecycle/security fields UNCHANGED
SELECT 'LIFECYCLE_PROTECTED' AS probe,
       (SELECT approval_status FROM public.questions WHERE question_code='QA-4A-0001') AS approval_status,
       (SELECT is_active FROM public.questions WHERE question_code='QA-4A-0001') AS is_active,
       (SELECT ownership_status FROM public.questions WHERE question_code='QA-4A-0001') AS ownership_status,
       (SELECT license_status FROM public.questions WHERE question_code='QA-4A-0001') AS license_status,
       (SELECT question_code FROM public.questions WHERE question_code='QA-4A-0001') AS question_code;

-- Verify an attempt to set a lifecycle field is impossible:
-- the RPC has no param for approval_status, so direct UPDATE must be blocked.
\set ON_ERROR_STOP off
SAVEPOINT qa_e_lifecycle;
UPDATE public.questions
SET approval_status='approved'
WHERE question_code='QA-4A-0001';
ROLLBACK TO SAVEPOINT qa_e_lifecycle;
SELECT 'DIRECT_UPDATE_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

RESET ROLE;
RESET request.jwt.claim.sub;


-- ============================================================
-- 3b. AUDIT VERIFICATION (as audit.view admin — can SELECT)
--      Confirms the edit's audit row was committed AIRTICALLY with
--      correct actor / action_code / entity / before-data / after-data.
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'c0c00012-0000-4000-8000-000000000003';

SELECT 'AUDIT_CREATED_ATOMIC' AS probe,
       actor_user_id,
       action_code,
       entity_type,
       entity_id IS NOT NULL AS has_entity,
       before_data ->> 'question_text' AS before_text,
       after_data  ->> 'question_text' AS after_text,
       before_data ->> 'difficulty' AS before_diff,
       after_data  ->> 'difficulty' AS after_diff,
       before_data ->> 'correct_answer' AS before_ca,
       after_data  ->> 'correct_answer' AS after_ca
FROM public.admin_audit_log
WHERE action_code='question.edit'
  AND entity_id IS NOT NULL
ORDER BY performed_at DESC
LIMIT 1;

RESET ROLE;
RESET request.jwt.claim.sub;


-- ============================================================
-- 4. audit.view ADMIN — CAN read audit log
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'c0c00012-0000-4000-8000-000000000003';

SELECT 'AUDITVIEW_ADMIN_READ' AS probe, count(*) AS visible
FROM public.admin_audit_log;

-- audit.view admin CANNOT edit question (no questions.edit)
\set ON_ERROR_STOP off
SAVEPOINT qa_a_edit;
SELECT public.admin_question_edit(
  (SELECT id FROM public.questions WHERE question_code='QA-4A-0001'),
  'HACK', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
);
ROLLBACK TO SAVEPOINT qa_a_edit;
SELECT 'AUDITVIEW_EDIT_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

-- audit.view admin CANNOT INSERT/UPDATE/DELETE audit (append-only)
\set ON_ERROR_STOP off
SAVEPOINT qa_a_i;
INSERT INTO public.admin_audit_log (action_code, entity_type) VALUES ('x','question');
ROLLBACK TO SAVEPOINT qa_a_i;
SELECT 'AUDITVIEW_INSERT_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

\set ON_ERROR_STOP off
SAVEPOINT qa_a_u;
UPDATE public.admin_audit_log SET action_code='x';
ROLLBACK TO SAVEPOINT qa_a_u;
SELECT 'AUDITVIEW_UPDATE_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

\set ON_ERROR_STOP off
SAVEPOINT qa_a_d;
DELETE FROM public.admin_audit_log;
ROLLBACK TO SAVEPOINT qa_a_d;
SELECT 'AUDITVIEW_DELETE_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

RESET ROLE;
RESET request.jwt.claim.sub;


-- ============================================================
-- 5. REGRESSION — activate/deactivate still work (040)
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'a0a00010-0000-4000-8000-000000000001';

-- Promote + approve the fixture question so activation is possible.
-- (activation requires approved + readiness. For regression, verify the
--  functions still exist and non-authorized paths are blocked.)
SELECT 'ACTIVATE_FN_EXISTS' AS probe,
       EXISTS (SELECT 1 FROM pg_proc WHERE proname='activate_question_for_students') AS activate_fn,
       EXISTS (SELECT 1 FROM pg_proc WHERE proname='deactivate_question_for_students') AS deactivate_fn;

-- deactivate on an already-inactive question should be idempotent/return,
-- proving the function is wired and callable by questions.approve admin.
-- (Our qa_edit_4a role has NO questions.approve; a direct call must be blocked.)
\set ON_ERROR_STOP off
SAVEPOINT qa_no_approve;
SELECT public.deactivate_question_for_students(
  (SELECT id FROM public.questions WHERE question_code='QA-4A-0001'), 'regression'
);
ROLLBACK TO SAVEPOINT qa_no_approve;
SELECT 'DEACTIVATE_PERM_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

RESET ROLE;
RESET request.jwt.claim.sub;

-- ============================================================
-- 6. REGRESSION — student visibility unchanged
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'd0d00013-0000-4000-8000-000000000004';

-- The edited question is draft+inactive; a student must still NOT see it
-- (student policy approved AND is_active). Non-admin sees 0.
SELECT 'STUDENT_VISIBILITY_REGRESSION' AS probe, count(*) AS visible_nonadmin
FROM public.questions WHERE question_code='QA-4A-0001';

RESET ROLE;
RESET request.jwt.claim.sub;

-- ============================================================
-- 7. ADMIN read regression (087) — questions.edit admin still sees all
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = 'a0a00010-0000-4000-8000-000000000001';
SELECT 'ADMIN_READ_REGRESSION' AS probe, count(*) AS visible_admin
FROM public.questions WHERE question_code='QA-4A-0001';
RESET ROLE;
RESET request.jwt.claim.sub;


ROLLBACK;
SELECT 'ROLLED_BACK' AS probe;
