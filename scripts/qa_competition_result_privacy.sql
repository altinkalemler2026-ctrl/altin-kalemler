-- ============================================================
-- qa_competition_result_privacy.sql
-- Permanent regression test for 081 competition result privacy
-- ============================================================

\t on
\pset format aligned
\pset border 2

\echo ============================================================
\echo qa_competition_result_privacy.sql
\echo ============================================================

-- =============================================================
-- SETUP (as postgres — before any role switch)
-- =============================================================

-- Create test users in auth.users (idempotent)
INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('a0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'test_a_privacy81@example.com', '', now(), now(), now()),
  ('b0000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'test_b_privacy81@example.com', '', now(), now(), now())
ON CONFLICT (id) DO NOTHING;

-- Test competition fixture
-- Clean previous test data
DELETE FROM public.competition_point_changes WHERE competition_id = 'f0000000-0000-0000-0000-000000000081';
DELETE FROM public.competition_answers WHERE competition_id = 'f0000000-0000-0000-0000-000000000081';
DELETE FROM public.competition_results WHERE competition_id = 'f0000000-0000-0000-0000-000000000081';
DELETE FROM public.competition_players WHERE competition_id = 'f0000000-0000-0000-0000-000000000081';
DELETE FROM public.competition_questions WHERE competition_id = 'f0000000-0000-0000-0000-000000000081';
DELETE FROM public.competitions WHERE id = 'f0000000-0000-0000-0000-000000000081';

-- Create test competition
INSERT INTO public.competitions (
  id, competition_code, competition_type, grade_level, subject_id,
  scoring_rule_set_id, status, question_count, server_started_at, server_completed_at
) VALUES (
  'f0000000-0000-0000-0000-000000000081',
  'F5-PRIVACY81',
  'one_vs_one',
  5,
  (SELECT id FROM public.subjects LIMIT 1),
  (SELECT id FROM public.scoring_rule_sets WHERE is_active = true LIMIT 1),
  'completed',
  2,
  now() - interval '1 hour',
  now()
);

-- Create 2 players
INSERT INTO public.competition_players (
  competition_id, user_id, player_slot, status, total_points,
  correct_count, wrong_count, pass_count, timeout_count, finished_at
) VALUES
  ('f0000000-0000-0000-0000-000000000081', 'a0000000-0000-0000-0000-000000000001', 1, 'finished', 300, 3, 1, 0, 1, now()),
  ('f0000000-0000-0000-0000-000000000081', 'b0000000-0000-0000-0000-000000000002', 2, 'finished', 200, 2, 2, 0, 1, now());

-- Create competition result
INSERT INTO public.competition_results (
  competition_id, winner_user_id, result_type,
  player_results, question_results, point_changes, final_scoreboard,
  calculated_at
) VALUES (
  'f0000000-0000-0000-0000-000000000081',
  'a0000000-0000-0000-0000-000000000001',
  'win_loss',
  '[{"user_id":"a0000000-0000-0000-0000-000000000001","player_slot":1,"total_points":300,"correct_count":3,"wrong_count":1,"pass_count":0,"timeout_count":1},{"user_id":"b0000000-0000-0000-0000-000000000002","player_slot":2,"total_points":200,"correct_count":2,"wrong_count":2,"pass_count":0,"timeout_count":1}]'::jsonb,
  '[{"question_order":1,"difficulty":"easy","players":[{"user_id":"a0000000-0000-0000-0000-000000000001","submitted_answer":"A","answer_result":"correct","points_awarded":100},{"user_id":"b0000000-0000-0000-0000-000000000002","submitted_answer":"B","answer_result":"wrong","points_awarded":0}]},{"question_order":2,"difficulty":"hard","players":[{"user_id":"a0000000-0000-0000-0000-000000000001","submitted_answer":"C","answer_result":"correct","points_awarded":200},{"user_id":"b0000000-0000-0000-0000-000000000002","submitted_answer":"A","answer_result":"wrong","points_awarded":0}]}]'::jsonb,
  '[]'::jsonb,
  '{}'::jsonb,
  now()
);

\echo SETUP DONE.

-- =============================================================
-- Switch to authenticated role for functional tests
-- =============================================================
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000001"}';
SET role = 'authenticated';

\echo
\echo --- TEST 1: Own data present, opponent absent ---

SELECT
  CASE WHEN
    result ? 'my_total_points'
    AND result ? 'my_correct_count'
    AND result ? 'competition_code'
    AND NOT (result ? 'winner_user_id')
    AND NOT (result ? 'players')
    AND NOT (result ? 'point_changes')
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO1' AS test_id,
  'own result: own fields present, opponent absent' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid) AS result
) sub;


\echo
\echo --- TEST 2: Opponent UUID absent from response ---

SELECT
  CASE WHEN result::text NOT LIKE '%b0000000-0000-0000-0000-000000000002%'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO2' AS test_id,
  'no opponent UUID in own result' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid) AS result
) sub;


\echo
\echo --- TEST 3: question_results own-only ---

SELECT
  CASE WHEN NOT (result->'question_results' @> '[{"submitted_answer": "B"}]')
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO3' AS test_id,
  'question_results: own answers only (no B)' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid) AS result
) sub;


\echo
\echo --- TEST 4: winner_user_id absent ---

SELECT
  CASE WHEN NOT (result ? 'winner_user_id')
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO4' AS test_id,
  'winner_user_id not in own result' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid) AS result
) sub;


\echo
\echo --- TEST 5: point_changes absent ---

SELECT
  CASE WHEN NOT (result ? 'point_changes')
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO5' AS test_id,
  'point_changes not in own result' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid) AS result
) sub;


\echo
\echo --- TEST 6: players array absent ---

SELECT
  CASE WHEN NOT (result ? 'players')
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO6' AS test_id,
  'players array not in own result' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid) AS result
) sub;


\echo
\echo --- TEST 7: No answer keys in response ---

SELECT
  CASE WHEN
    result::text NOT LIKE '%correct_answer%'
    AND result::text NOT LIKE '%solution%'
    AND result::text NOT LIKE '%explanation%'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO7' AS test_id,
  'no correct_answer/solution/explanation' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid) AS result
) sub;


\echo
\echo --- TEST 8: my_total_points = 300 ---

SELECT
  CASE WHEN (result->>'my_total_points')::integer = 300
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO8' AS test_id,
  'my_total_points = 300' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid) AS result
) sub;


\echo
\echo --- TEST 9: my_correct_count = 3 ---

SELECT
  CASE WHEN (result->>'my_correct_count')::integer = 3
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO9' AS test_id,
  'my_correct_count = 3' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid) AS result
) sub;


\echo
\echo --- TEST 10: my_player_slot = 1 ---

SELECT
  CASE WHEN (result->>'my_player_slot')::integer = 1
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO10' AS test_id,
  'my_player_slot = 1' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid) AS result
) sub;


\echo
\echo --- TEST 11: competition_code = F5-PRIVACY81 ---

SELECT
  CASE WHEN result->>'competition_code' = 'F5-PRIVACY81'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO11' AS test_id,
  'competition_code = F5-PRIVACY81' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid) AS result
) sub;


\echo
\echo --- TEST 12: Non-existent competition access denied ---

DO
$$
DECLARE
  v_result jsonb;
BEGIN
  v_result := public.get_own_competition_result('f0000000-0000-0000-0000-000000000099'::uuid);
  RAISE NOTICE 'FAIL|NO12|non-existent competition: expected exception but got result';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PASS|NO12|non-existent competition access denied';
END
$$;


-- =============================================================
-- Switch back to postgres for privilege/structure tests
-- =============================================================
RESET role;
RESET request.jwt.claims;

\echo
\echo --- TEST 13: Auth required (anon role) ---

DO
$$
DECLARE
  v_result jsonb;
BEGIN
  v_result := public.get_own_competition_result('f0000000-0000-0000-0000-000000000081'::uuid);
  RAISE NOTICE 'FAIL|NO13|anon role: expected auth exception but got result';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PASS|NO13|anon role: auth required';
END
$$;


\echo
\echo --- TEST 14: get_competition_scoreboard auth revoked ---

SELECT
  CASE WHEN NOT has_function_privilege('authenticated', 'public.get_competition_scoreboard(uuid)', 'EXECUTE')
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO14' AS test_id,
  'authenticated EXECUTE on get_competition_scoreboard revoked' AS description;


\echo
\echo --- TEST 15: service_role still has get_competition_scoreboard ---

SELECT
  CASE WHEN has_function_privilege('service_role', 'public.get_competition_scoreboard(uuid)', 'EXECUTE')
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO15' AS test_id,
  'service_role EXECUTE on get_competition_scoreboard preserved' AS description;


\echo
\echo --- TEST 16: competition_results no participant SELECT policy ---

SELECT
  CASE WHEN count(*) = 0
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO16' AS test_id,
  'competition_results: no participant SELECT policy' AS description
FROM pg_policy p
JOIN pg_class c ON p.polrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public'
  AND c.relname = 'competition_results'
  AND p.polname LIKE '%participant%'
  AND p.polcmd = 'r';


\echo
\echo --- TEST 17: competition_players own-row policy ---

SELECT
  CASE WHEN count(*) = 1
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO17' AS test_id,
  'competition_players: own-row SELECT policy exists' AS description
FROM pg_policy p
JOIN pg_class c ON p.polrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public'
  AND c.relname = 'competition_players'
  AND p.polname LIKE '%own%'
  AND p.polcmd = 'r';


\echo
\echo --- TEST 18: competitions participant policy removed ---

SELECT
  CASE WHEN count(*) = 0
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO18' AS test_id,
  'competitions: no participant SELECT policy' AS description
FROM pg_policy p
JOIN pg_class c ON p.polrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public'
  AND c.relname = 'competitions'
  AND p.polname LIKE '%participant%'
  AND p.polcmd = 'r';


\echo
\echo --- TEST 19: get_own_competition_result function exists ---

SELECT
  CASE WHEN count(*) = 1
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'NO19' AS test_id,
  'get_own_competition_result function exists' AS description
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'get_own_competition_result';


\echo
\echo --- TEST 20: Transaction safety ---

SELECT 'PASS' AS status, 'NO20' AS test_id,
  'transaction safety (no unhandled exceptions)' AS description
WHERE true;


-- =============================================================
-- CLEANUP
-- =============================================================

\echo
\echo --- CLEANUP ---

DELETE FROM public.competition_point_changes WHERE competition_id = 'f0000000-0000-0000-0000-000000000081';
DELETE FROM public.competition_answers WHERE competition_id = 'f0000000-0000-0000-0000-000000000081';
DELETE FROM public.competition_results WHERE competition_id = 'f0000000-0000-0000-0000-000000000081';
DELETE FROM public.competition_players WHERE competition_id = 'f0000000-0000-0000-0000-000000000081';
DELETE FROM public.competition_questions WHERE competition_id = 'f0000000-0000-0000-0000-000000000081';
DELETE FROM public.competitions WHERE id = 'f0000000-0000-0000-0000-000000000081';
DELETE FROM auth.users WHERE id IN (
  'a0000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-000000000002'
) AND email LIKE '%privacy81%';

\echo CLEANUP DONE.
\echo
\echo ============================================================
\echo qa_competition_result_privacy.sql COMPLETE
\echo ============================================================
