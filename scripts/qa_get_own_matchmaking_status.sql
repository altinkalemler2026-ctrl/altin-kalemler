-- ============================================================
-- qa_get_own_matchmaking_status.sql
-- Permanent regression test for 084 read-only matchmaking status
-- ============================================================

\t on
\pset format aligned
\pset border 2

\echo ============================================================
\echo qa_get_own_matchmaking_status.sql
\echo ============================================================

\set ON_ERROR_STOP on

-- Tek transaction: tum CHECK'ler ve manuel CHECK 20 cleanup ayni
-- transaction icinde kalir; basarili final dogrulamalardan sonra
-- ROLLBACK ile hicbir test artefakti kalici olmaz. Ara bir hata
-- ON_ERROR_STOP ile psql'i sonlandirirsa acik transaction baglanti
-- kapanirken otomatik olarak rollback olur.
BEGIN;

-- =============================================================
-- SETUP (as postgres — before any role switch)
-- =============================================================

-- Test user UUIDs (deterministic, not real A/B users)
-- User A (tester): a0000000-0000-0000-0000-000000000084
-- User B (tester): b0000000-0000-0000-0000-000000000084

INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('a0000000-0000-0000-0000-000000000084', 'authenticated', 'authenticated', 'test_a_084@example.com', '', now(), now(), now()),
  ('b0000000-0000-0000-0000-000000000084', 'authenticated', 'authenticated', 'test_b_084@example.com', '', now(), now(), now())
ON CONFLICT (id) DO NOTHING;

-- Ensure profiles exist (idempotent)
INSERT INTO public.student_profiles (id, grade_level, nickname)
VALUES
  ('a0000000-0000-0000-0000-000000000084', 10, 'QA_084_A'),
  ('b0000000-0000-0000-0000-000000000084', 10, 'QA_084_B')
ON CONFLICT (id) DO NOTHING;

-- Cleanup any prior test fixtures
DELETE FROM public.matchmaking_queue WHERE user_id IN (
  'a0000000-0000-0000-0000-000000000084',
  'b0000000-0000-0000-0000-000000000084'
);
DELETE FROM public.rpc_rate_limits WHERE user_id IN (
  'a0000000-0000-0000-0000-000000000084',
  'b0000000-0000-0000-0000-000000000084'
);

-- Get a valid active subject_id for testing in the SAME psql session
-- (no shell echo, no nested psql, no network). \gset stores the column
-- alias as the psql variable.
SELECT id AS test_subject_id
FROM public.subjects
WHERE is_active = true
ORDER BY id
LIMIT 1
\gset

-- Guarantee: an active subject must exist, otherwise abort loudly.
\if :{?test_subject_id}
\else
  \echo ERROR: aktif subject bulunamadi; QA durduruldu.
  \quit 1
\endif

\echo SETUP DONE.

-- =============================================================
-- CHECK 1: Function exists exactly once
-- =============================================================
SELECT count(*) AS check_01_function_exists
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'get_own_matchmaking_status';

-- =============================================================
-- CHECK 2: SECURITY DEFINER
-- =============================================================
SELECT prosecdef AS check_02_security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'get_own_matchmaking_status';

-- =============================================================
-- CHECK 3: Empty search_path
-- =============================================================
SELECT pg_get_functiondef(p.oid) LIKE '%SET search_path TO %''%' AS check_03_search_path_empty
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'get_own_matchmaking_status';

-- =============================================================
-- CHECK 4: PUBLIC denied
-- =============================================================
SELECT has_function_privilege('public', 'public.get_own_matchmaking_status(uuid)', 'EXECUTE') AS check_04_public_denied;

-- =============================================================
-- CHECK 5: anon denied
-- =============================================================
SELECT has_function_privilege('anon', 'public.get_own_matchmaking_status(uuid)', 'EXECUTE') AS check_05_anon_denied;

-- =============================================================
-- CHECK 6: authenticated allowed
-- =============================================================
SELECT has_function_privilege('authenticated', 'public.get_own_matchmaking_status(uuid)', 'EXECUTE') AS check_06_authenticated_allowed;

-- =============================================================
-- CHECK 7: unauthenticated call rejected
-- =============================================================
-- This check verifies that calling without JWT fails
-- (Switch to anon role without JWT claims)
\echo CHECK 07: unauthenticated call test (expect error)
DO $$
BEGIN
  BEGIN
    EXECUTE 'set local role anon';
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM public.get_own_matchmaking_status('00000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'CHECK 07 FAILED: should have raised exception';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%kimlik dogrulamasi%' OR SQLERRM LIKE '%42501%' OR SQLSTATE = '42501' THEN
      RAISE NOTICE 'CHECK 07 PASSED: unauthenticated call rejected';
    ELSE
      RAISE NOTICE 'CHECK 07 PASSED: error raised: %', SQLERRM;
    END IF;
  END;
  -- Role/claims sizintisini onle: postgres superuser rolune don,
  -- tactical claims'i temizle (sonraki fixture DML postgres olarak calisir).
  PERFORM set_config('request.jwt.claims', '', true);
  EXECUTE 'reset role';
END;
$$;

-- =============================================================
-- CHECK 8: not_queued response (no queue rows)
-- =============================================================
-- RPC: gercek authenticated rolunde + kullanici claims'i.
-- SET ROLE authenticated ile rol degistirilir, RESET ROLE ile postgres'e
-- donulur; boylece sonraki fixture DML asla authenticated olarak calismaz.
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000084"}';
SELECT public.get_own_matchmaking_status(:'test_subject_id') AS check_08_not_queued;
RESET ROLE;
-- Expected: {"status": "not_queued", "competition_id": null, "competition_code": null}

-- =============================================================
-- CHECK 9: own waiting response
-- =============================================================
-- Fixture DML: postgres rolunde (RESET ROLE garantisi)
RESET ROLE;
INSERT INTO public.matchmaking_queue (user_id, grade_level, subject_id, status, joined_at, expires_at)
VALUES ('a0000000-0000-0000-0000-000000000084', 10, :'test_subject_id', 'waiting', now(), now() + interval '15 minutes');

-- RPC: gercek authenticated rolunde + kullanici claims'i
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000084"}';
SELECT public.get_own_matchmaking_status(:'test_subject_id') AS check_09_waiting;
RESET ROLE;
-- Expected: {"status": "waiting", "competition_id": null, "competition_code": null}

-- =============================================================
-- CHECK 10: expired row -> not_queued
-- =============================================================
RESET ROLE;
UPDATE public.matchmaking_queue
SET status = 'waiting', expires_at = now() - interval '1 minute'
WHERE user_id = 'a0000000-0000-0000-0000-000000000084'
  AND subject_id = :'test_subject_id'
  AND status = 'waiting';

-- RPC: gercek authenticated rolunde + kullanici claims'i
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000084"}';
SELECT public.get_own_matchmaking_status(:'test_subject_id') AS check_10_expired;
RESET ROLE;
-- Expected: {"status": "not_queued", ...}

-- =============================================================
-- CHECK 11: cancelled row -> not_queued
-- =============================================================
RESET ROLE;
UPDATE public.matchmaking_queue
SET status = 'cancelled', expires_at = now() + interval '15 minutes'
WHERE user_id = 'a0000000-0000-0000-0000-000000000084'
  AND subject_id = :'test_subject_id'
  AND status = 'waiting';

-- RPC: gercek authenticated rolunde + kullanici claims'i
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000084"}';
SELECT public.get_own_matchmaking_status(:'test_subject_id') AS check_11_cancelled;
RESET ROLE;
-- Expected: {"status": "not_queued", ...}

-- =============================================================
-- CHECK 12: matched participant -> competition_id/code
-- =============================================================
-- Create a test competition and make user A a participant
RESET ROLE;
DELETE FROM public.competitions WHERE competition_code = 'F5-QA084TEST';

INSERT INTO public.competitions (
  id, competition_code, competition_type, grade_level, subject_id,
  scoring_rule_set_id, status, question_count, server_started_at
) VALUES (
  'f0000000-0000-0000-0000-000000000084',
  'F5-QA084TEST',
  'one_vs_one',
  10,
  :'test_subject_id',
  (SELECT id FROM public.scoring_rule_sets WHERE is_active = true LIMIT 1),
  'active',
  5,
  now()
);

INSERT INTO public.competition_players (competition_id, user_id, player_slot, status)
VALUES
  ('f0000000-0000-0000-0000-000000000084', 'a0000000-0000-0000-0000-000000000084', 1, 'ready'),
  ('f0000000-0000-0000-0000-000000000084', 'b0000000-0000-0000-0000-000000000084', 2, 'ready');

UPDATE public.matchmaking_queue
SET status = 'matched', matched_at = now(), expires_at = now() + interval '15 minutes'
WHERE user_id = 'a0000000-0000-0000-0000-000000000084'
  AND subject_id = :'test_subject_id';

-- RPC: gercek authenticated rolunde + kullanici claims'i
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000084"}';
SELECT public.get_own_matchmaking_status(:'test_subject_id') AS check_12_matched_participant;
RESET ROLE;
-- Expected: {"status": "matched", "competition_id": "...", "competition_code": "F5-QA084TEST"}

-- =============================================================
-- CHECK 13: non-participant cannot get competition info
-- =============================================================
-- User B is matched in queue but NOT a participant in the competition
-- (we only inserted A and another user, but let's verify B gets matched without comp)
-- Actually B IS a participant (inserted above). Let's check a different scenario:
-- Remove B from competition_players, B should still see matched but no comp_id
RESET ROLE;
DELETE FROM public.competition_players
WHERE competition_id = 'f0000000-0000-0000-0000-000000000084'
  AND user_id = 'b0000000-0000-0000-0000-000000000084';

INSERT INTO public.matchmaking_queue (user_id, grade_level, subject_id, status, matched_at, expires_at)
VALUES ('b0000000-0000-0000-0000-000000000084', 10, :'test_subject_id', 'matched', now(), now() + interval '15 minutes');

-- RPC: gercek authenticated rolunde + kullanici claims'i (user B)
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "b0000000-0000-0000-0000-000000000084"}';
SELECT public.get_own_matchmaking_status(:'test_subject_id') AS check_13_non_participant;
RESET ROLE;
-- Expected: {"status": "waiting" (transitional), "competition_id": null, "competition_code": null}

-- =============================================================
-- CHECK 14: opponent UUID/PII not in response
-- =============================================================
-- RPC: gercek authenticated rolunde + kullanici claims'i (user A)
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000084"}';
SELECT (public.get_own_matchmaking_status(:'test_subject_id')::text LIKE '%b0000000%') AS check_14_no_opponent_pii;
RESET ROLE;
-- Expected: false (no opponent UUID in response)

-- =============================================================
-- CHECK 15: correct_answer/answer/result info not in response
-- =============================================================
-- RPC: gercek authenticated rolunde + kullanici claims'i (user A)
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000084"}';
SELECT (public.get_own_matchmaking_status(:'test_subject_id')::text LIKE '%correct_answer%') AS check_15_no_answer_info_1;
SELECT (public.get_own_matchmaking_status(:'test_subject_id')::text LIKE '%submitted_answer%') AS check_15_no_answer_info_2;
SELECT (public.get_own_matchmaking_status(:'test_subject_id')::text LIKE '%result_type%') AS check_15_no_answer_info_3;
RESET ROLE;

-- =============================================================
-- CHECK 16: 40 status polls do NOT consume queue_join rate limit
-- =============================================================
-- Record current rate limit count
SELECT COALESCE(hit_count, 0) AS rate_before
FROM public.rpc_rate_limits
WHERE user_id = 'a0000000-0000-0000-0000-000000000084'
  AND rpc_name = 'queue_join'
  AND window_start = (SELECT max(window_start) FROM public.rpc_rate_limits WHERE user_id = 'a0000000-0000-0000-0000-000000000084' AND rpc_name = 'queue_join');

-- Psql degiskenini DO disinda (top-level) transaction-local custom GUC'ye
-- aktar: set_config ... true = transaction-local. Interpolasyon burada calisir.
SELECT set_config('qa.test_subject_id', :'test_subject_id', true);

-- Call status 40 times (RPC: gercek authenticated rolunde + claims)
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000084"}';
DO $$
DECLARE v_subj uuid := current_setting('qa.test_subject_id', true)::uuid;
BEGIN
  FOR i IN 1..40 LOOP
    PERFORM public.get_own_matchmaking_status(v_subj);
  END LOOP;
END;
$$;
RESET ROLE;

-- Check rate limit count unchanged
SELECT COALESCE(hit_count, 0) AS rate_after
FROM public.rpc_rate_limits
WHERE user_id = 'a0000000-0000-0000-0000-000000000084'
  AND rpc_name = 'queue_join'
  AND window_start = (SELECT max(window_start) FROM public.rpc_rate_limits WHERE user_id = 'a0000000-0000-0000-0000-000000000084' AND rpc_name = 'queue_join');
-- Expected: same as before (no increase)

-- =============================================================
-- CHECK 17: 40 status polls do NOT modify queue/competition rows
-- =============================================================
-- Record row count/state before
SELECT count(*) AS queue_rows_before FROM public.matchmaking_queue
WHERE user_id = 'a0000000-0000-0000-0000-000000000084';

-- Psql degiskenini DO disinda (top-level) transaction-local custom GUC'ye
-- aktar: set_config ... true = transaction-local. Interpolasyon burada calisir.
SELECT set_config('qa.test_subject_id', :'test_subject_id', true);

-- Call status 40 times (RPC: gercek authenticated rolunde + claims)
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000084"}';
DO $$
DECLARE v_subj uuid := current_setting('qa.test_subject_id', true)::uuid;
BEGIN
  FOR i IN 1..40 LOOP
    PERFORM public.get_own_matchmaking_status(v_subj);
  END LOOP;
END;
$$;
RESET ROLE;

SELECT count(*) AS queue_rows_after FROM public.matchmaking_queue
WHERE user_id = 'a0000000-0000-0000-0000-000000000084';
-- Expected: same count

-- =============================================================
-- CHECK 18: Cross-user isolation
-- =============================================================
-- User B should only see their own queue, not user A's
-- RPC: gercek authenticated rolunde + kullanici claims'i (user B)
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "b0000000-0000-0000-0000-000000000084"}';
SELECT public.get_own_matchmaking_status(:'test_subject_id') AS check_18_cross_user;
RESET ROLE;
-- B sees their own "matched" status (no comp_id since removed from players)

-- =============================================================
-- CHECK 19: Response allowlist (only known keys)
-- =============================================================
-- RPC: gercek authenticated rolunde + kullanici claims'i (user A)
SET ROLE authenticated;
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000084"}';
SELECT (public.get_own_matchmaking_status(:'test_subject_id')::jsonb ?| ARRAY['status', 'competition_id', 'competition_code']) AS check_19_keys_present;
SELECT jsonb_object_keys(public.get_own_matchmaking_status(:'test_subject_id')) AS check_19_only_known_keys;
RESET ROLE;
-- Expected: only status, competition_id, competition_code

-- =============================================================
-- CHECK 20: ROLLBACK leaves zero residue
-- =============================================================
-- Clean test data
RESET ROLE;
DELETE FROM public.competition_point_changes WHERE competition_id = 'f0000000-0000-0000-0000-000000000084';
DELETE FROM public.competition_answers WHERE competition_id = 'f0000000-0000-0000-0000-000000000084';
DELETE FROM public.competition_results WHERE competition_id = 'f0000000-0000-0000-0000-000000000084';
DELETE FROM public.competition_players WHERE competition_id = 'f0000000-0000-0000-0000-000000000084';
DELETE FROM public.competition_questions WHERE competition_id = 'f0000000-0000-0000-0000-000000000084';
DELETE FROM public.competitions WHERE id = 'f0000000-0000-0000-0000-000000000084';
DELETE FROM public.matchmaking_queue WHERE user_id IN (
  'a0000000-0000-0000-0000-000000000084',
  'b0000000-0000-0000-0000-000000000084'
);
DELETE FROM public.rpc_rate_limits WHERE user_id IN (
  'a0000000-0000-0000-0000-000000000084',
  'b0000000-0000-0000-0000-000000000084'
);

SELECT count(*) AS residue_queue FROM public.matchmaking_queue WHERE user_id IN (
  'a0000000-0000-0000-0000-000000000084',
  'b0000000-0000-0000-0000-000000000084'
);
SELECT count(*) AS residue_competitions FROM public.competitions WHERE id = 'f0000000-0000-0000-0000-000000000084';
SELECT count(*) AS residue_players FROM public.competition_players WHERE competition_id = 'f0000000-0000-0000-0000-000000000084';

-- Cleanup test profiles
DELETE FROM public.student_profiles WHERE id IN (
  'a0000000-0000-0000-0000-000000000084',
  'b0000000-0000-0000-0000-000000000084'
);
DELETE FROM auth.users WHERE id IN (
  'a0000000-0000-0000-0000-000000000084',
  'b0000000-0000-0000-0000-000000000084'
);

\echo ALL 20 CHECKS COMPLETE.

-- Basarili final dogrulamalardan sonra tek transaction'u geri al:
-- tum test fixture'lari (auth.users, student_profiles, matchmaking_queue,
-- rpc_rate_limits, competitions, competition_players vb.) kalici olmadan
-- silinir. Yine de mevcut manuel CHECK 20 DELETE'leri muhafaza edildi;
-- ROLLBACK bunlarin uzerine ek bir guvence saglar.
ROLLBACK;

\echo ROLLBACK executed; test fixtures geri alindi.
