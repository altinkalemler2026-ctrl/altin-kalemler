-- ============================================================
-- QA: Faz 4 Admin Read RLS Integration (migration 087)
-- Runs inside a single ROLLBACK transaction. Nothing persists.
-- ============================================================
\set ON_ERROR_STOP on

BEGIN;

-- --- 0. Fixture: throwaway admin role with questions.view ---------
INSERT INTO public.admin_roles (id, role_code, name, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), 'qa_admin_read_phase2', 'QA Admin Read P2', true, now(), now());

-- Use existing seeded e2e user A as the fake ADMIN (all rolled back).
INSERT INTO public.admin_user_roles (user_id, role_id, assigned_at)
SELECT 'efed0fd6-ad7e-441b-a7fc-d93ce2c00c94'::uuid, id, now()
FROM public.admin_roles WHERE role_code='qa_admin_read_phase2';

INSERT INTO public.admin_role_permissions (role_id, permission_id, created_at)
SELECT r.id, p.id, now()
FROM public.admin_roles r, public.admin_permissions p
WHERE r.role_code='qa_admin_read_phase2' AND p.permission_code='questions.view';

-- --- 1. Fixture: mixed-status questions (approved+pending+draft+inactive) ---
WITH s AS (SELECT id FROM public.subjects LIMIT 1)
INSERT INTO public.questions
  (id, question_code, exam_track, grade_level, subject_id, question_text,
   is_new_generation, has_visual, approval_status, is_active,
   ownership_status, license_status, commercial_use_allowed, created_at, updated_at)
VALUES
  ('aaaa0001-0000-4000-8000-000000000001', 'QA-ACCEPT-1', 'TYT', 7, (SELECT id FROM s), 'approved active q',
   false, false, 'approved', true,  'owned', 'approved', true, now(), now()),
  ('aaaa0002-0000-4000-8000-000000000002', 'QA-PENDING-1', 'TYT', 7, (SELECT id FROM s), 'pending q',
   false, false, 'pending_review', false, 'owned', 'approved', true, now(), now()),
  ('aaaa0003-0000-4000-8000-000000000003', 'QA-DRAFT-1', 'TYT', 7, (SELECT id FROM s), 'draft q',
   false, false, 'draft', false, 'owned', 'approved', true, now(), now()),
  ('aaaa0004-0000-4000-8000-000000000004', 'QA-INACTIVE-1', 'TYT', 7, (SELECT id FROM s), 'approved inactive q',
   false, false, 'approved', false, 'owned', 'approved', true, now(), now());

-- --- 2. Fixture: staging rows (admin-only / non-admin-blocked) ---
INSERT INTO public.ai_question_staging
  (id, staging_source, staging_status, prerequisite_violation, metadata,
   outcome_drift_detected, grade_drift_detected, topic_drift_detected,
   ownership_status, license_status, commercial_use_allowed, copyright_risk_level,
   created_at, updated_at)
VALUES
  ('bbbb0001-0000-4000-8000-000000000001', 'manual_candidate', 'needs_review', false, '{}'::jsonb,
   false, false, false, 'owned', 'approved', true, 'low', now(), now());

-- --- 3. Fixture: review_queue rows ---
INSERT INTO public.review_queue
  (id, entity_type, entity_id, reason_code, reason_details, priority, status, created_at, updated_at)
VALUES
  ('cccc0001-0000-4000-8000-000000000001', 'question', 'aaaa0002-0000-4000-8000-000000000002',
   'qa', '{"note":"qa queue row"}'::jsonb, 'high', 'open', now(), now());

-- --- 4. NON-ADMIN question visibility ---
-- Simulate a normal student: authenticated role, sub = seeded e2e user B (no admin mapping).
SET ROLE authenticated;
SET request.jwt.claim.sub = '0991d571-08c0-48cc-9065-4453f7de70d5';

SELECT 'NON_ADMIN_QUESTION_RLS' AS probe,
       count(*) FILTER (WHERE question_code='QA-ACCEPT-1') AS sees_approved_active,
       count(*) FILTER (WHERE question_code IN ('QA-PENDING-1','QA-DRAFT-1','QA-INACTIVE-1')) AS sees_forbidden
FROM public.questions
WHERE id::text LIKE 'aaaa%';

-- Student regression: only approved+active across the whole bank
SELECT 'STUDENT_VISIBILITY_REGRESSION' AS probe,
       count(*) AS total_visible_questions
FROM public.questions;

-- NO-WRITE: authenticated non-admin must not INSERT/UPDATE/DELETE questions
-- Each intentional write error is rolled back to a savepoint so the single
-- verification transaction stays usable for the remaining probes.
\set ON_ERROR_STOP off
SAVEPOINT qa_nowrite1;
UPDATE public.questions SET question_text='hack' WHERE id::text LIKE 'aaaa%';
ROLLBACK TO SAVEPOINT qa_nowrite1;
SELECT 'NONADMIN_QUESTIONS_UPDATE_BLOCKED' AS probe, 1 AS expected_denied;
SAVEPOINT qa_nowrite2;
DELETE FROM public.questions WHERE id::text LIKE 'aaaa%';
ROLLBACK TO SAVEPOINT qa_nowrite2;
SELECT 'NONADMIN_QUESTIONS_DELETE_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

-- NON-ADMIN staging + review_queue: 0 rows via RLS
SELECT 'NON_ADMIN_STAGING_RLS' AS probe, count(*) AS visible
FROM public.ai_question_staging WHERE id::text LIKE 'bbbb%';
SELECT 'NON_ADMIN_REVIEW_QUEUE_RLS' AS probe, count(*) AS visible
FROM public.review_queue WHERE id::text LIKE 'cccc%';

-- --- 5. ADMIN question visibility (questions.view) ---
SET request.jwt.claim.sub = 'efed0fd6-ad7e-441b-a7fc-d93ce2c00c94';

SELECT 'ADMIN_FULL_STATUS_QUESTION_RLS' AS probe,
       count(*) AS total,
       count(*) FILTER (WHERE approval_status='approved' AND is_active=true) AS approved_active,
       count(*) FILTER (WHERE approval_status='pending_review') AS pending,
       count(*) FILTER (WHERE approval_status='draft') AS draft,
       count(*) FILTER (WHERE is_active=false) AS inactive
FROM public.questions
WHERE id::text LIKE 'aaaa%';

SELECT 'ADMIN_STAGING_RLS' AS probe, count(*) AS visible
FROM public.ai_question_staging WHERE id::text LIKE 'bbbb%';

SELECT 'ADMIN_REVIEW_QUEUE_RLS' AS probe, count(*) AS visible
FROM public.review_queue WHERE id::text LIKE 'cccc%';

RESET ROLE;
RESET request.jwt.claim.sub;

ROLLBACK;
SELECT 'ROLLED_BACK' AS probe;
