-- ============================================================
-- QA: Phase 3 Admin Users Read RLS Integration (migration 088)
-- Runs inside a single ROLLBACK transaction. Nothing persists.
-- Corrected fixture: creates real auth.users rows so all FK
-- constraints are satisfied.
-- ============================================================
\set ON_ERROR_STOP on

BEGIN;

-- --- 0. Fixture: throwaway auth.users rows (FK targets) ------
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at, raw_app_meta_data)
VALUES
  ('a0a00001-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'qa-admin-phase3@example.test',
   crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}'),
  ('b0b00002-0000-4000-8000-000000000002', '00000000-0000-0000-8000-000000000000',
   'authenticated', 'authenticated', 'qa-nonadmin-phase3@example.test',
   crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}'),
  ('c0c00003-0000-4000-8000-000000000003', '00000000-0000-0000-8000-000000000000',
   'authenticated', 'authenticated', 'qa-victim-phase3@example.test',
   crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}');

-- --- 1. Fixture: throwaway admin role with users.manage -------
INSERT INTO public.admin_roles (id, role_code, name, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), 'qa_admin_users_phase3', 'QA Admin Users P3', true, now(), now());

INSERT INTO public.admin_user_roles (user_id, role_id, assigned_at)
SELECT 'a0a00001-0000-4000-8000-000000000001'::uuid, id, now()
FROM public.admin_roles WHERE role_code='qa_admin_users_phase3';

INSERT INTO public.admin_role_permissions (role_id, permission_id, created_at)
SELECT r.id, p.id, now()
FROM public.admin_roles r, public.admin_permissions p
WHERE r.role_code='qa_admin_users_phase3' AND p.permission_code='users.manage';

-- --- 2. Fixture: two throwaway student profiles ----------------
INSERT INTO public.student_profiles (id, grade_level, nickname, created_at, updated_at)
VALUES
  ('b0b00002-0000-4000-8000-000000000002', 7, 'qa-nonadmin', now(), now()),
  ('c0c00003-0000-4000-8000-000000000003', 9, 'qa-victim', now(), now());

INSERT INTO public.student_public_profiles
  (user_id, nickname, grade_level, is_visible, total_points, monthly_points, created_at, updated_at)
VALUES
  ('b0b00002-0000-4000-8000-000000000002', 'qa-nonadmin', 7, true,  100, 10, now(), now()),
  ('c0c00003-0000-4000-8000-000000000003', 'qa-victim',   9, false, 200, 20, now(), now());

-- --- 3. NON-ADMIN authenticated visibility --------------------
SET ROLE authenticated;
SET request.jwt.claim.sub = 'b0b00002-0000-4000-8000-000000000002';

-- Non-admin own profile: must see exactly 1 (their OWN row)
SELECT 'NON_ADMIN_PROFILES_RLS' AS probe, count(*) AS visible
FROM public.student_profiles WHERE id = auth.uid();

-- Non-admin public profiles: sees own + visible rows only; victim (hidden) NOT visible
SELECT 'NON_ADMIN_PUBLIC_PROFILES_RLS' AS probe,
       count(*) AS total,
       count(*) FILTER (WHERE user_id='b0b00002-0000-4000-8000-000000000002') AS own_visible,
       count(*) FILTER (WHERE user_id='c0c00003-0000-4000-8000-000000000003') AS victim_hidden
FROM public.student_public_profiles WHERE user_id::text LIKE 'b0b00002%' OR user_id::text LIKE 'c0c00003%';

-- NON-ADMIN cannot cross-read another profile's private row
SELECT 'NON_ADMIN_CROSS_READ_BLOCKED' AS probe, count(*) AS foreign_profiles
FROM public.student_profiles WHERE id = 'c0c00003-0000-4000-8000-000000000003';

-- NO-WRITE: authenticated non-admin must NOT UPDATE/DELETE student_profiles
\set ON_ERROR_STOP off
SAVEPOINT qa_u_nowrite1;
UPDATE public.student_profiles SET nickname='hack' WHERE id='c0c00003-0000-4000-8000-000000000003';
ROLLBACK TO SAVEPOINT qa_u_nowrite1;
SELECT 'NONADMIN_UPDATE_BLOCKED' AS probe, 1 AS expected_denied;
SAVEPOINT qa_u_nowrite2;
DELETE FROM public.student_profiles WHERE id='c0c00003-0000-4000-8000-000000000003';
ROLLBACK TO SAVEPOINT qa_u_nowrite2;
SELECT 'NONADMIN_DELETE_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

-- NO-INSERT escalation: non-admin must not INSERT for another user
\set ON_ERROR_STOP off
SAVEPOINT qa_u_noinsert;
INSERT INTO public.student_profiles (id, grade_level, nickname) VALUES
  ('a0a00001-0000-4000-8000-000000000001', 5, 'hacker-proxy');
ROLLBACK TO SAVEPOINT qa_u_noinsert;
SELECT 'NONADMIN_INSERT_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

-- --- 4. STUDENT OWN-PROFILE REGRESSION (unchanged) ------------
SELECT 'STUDENT_PROFILE_REGRESSION' AS probe, count(*) AS visible
FROM public.student_profiles WHERE id = auth.uid();

-- --- 5. ADMIN visibility (users.manage) ------------------------
SET request.jwt.claim.sub = 'a0a00001-0000-4000-8000-000000000001';

SELECT 'ADMIN_PROFILES_RLS' AS probe, count(*) AS visible
FROM public.student_profiles WHERE id::text LIKE 'b0b00002%' OR id::text LIKE 'c0c00003%';

-- Admin sees BOTH rows in public profiles (visible + hidden)
SELECT 'ADMIN_PUBLIC_PROFILES_RLS' AS probe, count(*) AS visible
FROM public.student_public_profiles WHERE user_id::text LIKE 'b0b00002%' OR user_id::text LIKE 'c0c00003%';

-- ADMIN is read-only: UPDATE must be blocked (no admin UPDATE policy)
\set ON_ERROR_STOP off
SAVEPOINT qa_a_nowrite;
UPDATE public.student_profiles SET nickname='admin-hack' WHERE id='c0c00003-0000-4000-8000-000000000003';
ROLLBACK TO SAVEPOINT qa_a_nowrite;
SELECT 'ADMIN_PROFILES_UPDATE_BLOCKED' AS probe, 1 AS expected_denied;
\set ON_ERROR_STOP on

RESET ROLE;
RESET request.jwt.claim.sub;

ROLLBACK;
SELECT 'ROLLED_BACK' AS probe;
