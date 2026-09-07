-- ============================================================
-- qa_faz7_own_result_details.sql
-- Faz 7 kalıcı regresyon testi: 099 get_own_competition_result
-- (my_result + kendi answer_result/submitted_answer)
--
-- Beklenen ortam: disposable, tüm migration'lar (001..099)
-- uygulanmış temiz Supabase local stack'i.
-- ============================================================

\t on
\pset format aligned
\pset border 2

\echo ============================================================
\echo qa_faz7_own_result_details.sql
\echo ============================================================

-- =============================================================
-- SETUP (as postgres)
-- =============================================================

INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES
  ('a0000000-0000-0000-0000-000000000101', 'authenticated', 'authenticated', 'fz7_a@example.local', '', now(), now(), now()),
  ('a0000000-0000-0000-0000-000000000102', 'authenticated', 'authenticated', 'fz7_b@example.local', '', now(), now(), now())
ON CONFLICT (id) DO NOTHING;

-- Ana (win_loss) yarisma fixture'i
DELETE FROM public.competition_results WHERE competition_id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000204');
DELETE FROM public.competition_players WHERE competition_id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000204');
DELETE FROM public.competition_questions WHERE competition_id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000204');
DELETE FROM public.competition_answers WHERE competition_id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000204');
DELETE FROM public.competition_point_changes WHERE competition_id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000204');
DELETE FROM public.competitions WHERE id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000204');

-- 201: win_loss (A kazanir, B kaybeder)
INSERT INTO public.competitions (
  id, competition_code, competition_type, grade_level, subject_id,
  scoring_rule_set_id, status, question_count, server_started_at, server_completed_at
) VALUES (
  'f0000000-0000-0000-0000-000000000201',
  'F7-WINLOSS',
  'one_vs_one',
  5,
  (SELECT id FROM public.subjects LIMIT 1),
  (SELECT id FROM public.scoring_rule_sets WHERE is_active = true LIMIT 1),
  'completed',
  2,
  now() - interval '1 hour',
  now()
);

INSERT INTO public.competition_players (
  competition_id, user_id, player_slot, status, total_points,
  correct_count, wrong_count, pass_count, timeout_count, finished_at
) VALUES
  ('f0000000-0000-0000-0000-000000000201', 'a0000000-0000-0000-0000-000000000101', 1, 'finished', 300, 2, 0, 0, 0, now()),
  ('f0000000-0000-0000-0000-000000000201', 'a0000000-0000-0000-0000-000000000102', 2, 'finished', 100, 0, 1, 1, 0, now());

-- question_results: soru 1'de A dogru (A cevabi), soru 2'de B yarida
-- answer_result anahtari OLMAYAN element (coalesce 'timeout' yolu)
INSERT INTO public.competition_results (
  competition_id, winner_user_id, result_type,
  player_results, question_results, point_changes, final_scoreboard,
  calculated_at
) VALUES (
  'f0000000-0000-0000-0000-000000000201',
  'a0000000-0000-0000-0000-000000000101',
  'win_loss',
  '[{"user_id":"a0000000-0000-0000-0000-000000000101","player_slot":1,"total_points":300,"status":"finished"},{"user_id":"a0000000-0000-0000-0000-000000000102","player_slot":2,"total_points":100,"status":"finished"}]'::jsonb,
  '[{"question_order":1,"difficulty":"easy","players":[{"user_id":"a0000000-0000-0000-0000-000000000101","submitted_answer":"A","answer_result":"correct","points_awarded":100},{"user_id":"a0000000-0000-0000-0000-000000000102","submitted_answer":"B","answer_result":"wrong","points_awarded":0}]},{"question_order":2,"difficulty":"hard","players":[{"user_id":"a0000000-0000-0000-0000-000000000101","submitted_answer":"D","points_awarded":200},{"user_id":"a0000000-0000-0000-0000-000000000102","submitted_answer":null,"answer_result":"pass","points_awarded":0}]}]'::jsonb,
  '[]'::jsonb,
  '{}'::jsonb,
  now()
);

-- 202: draw
INSERT INTO public.competitions (
  id, competition_code, competition_type, grade_level, subject_id,
  scoring_rule_set_id, status, question_count, server_started_at, server_completed_at
) VALUES (
  'f0000000-0000-0000-0000-000000000202',
  'F7-DRAW',
  'one_vs_one',
  5,
  (SELECT id FROM public.subjects LIMIT 1),
  (SELECT id FROM public.scoring_rule_sets WHERE is_active = true LIMIT 1),
  'completed',
  1,
  now() - interval '1 hour',
  now()
);

INSERT INTO public.competition_players (
  competition_id, user_id, player_slot, status, total_points, finished_at
) VALUES
  ('f0000000-0000-0000-0000-000000000202', 'a0000000-0000-0000-0000-000000000101', 1, 'finished', 100, now()),
  ('f0000000-0000-0000-0000-000000000202', 'a0000000-0000-0000-0000-000000000102', 2, 'finished', 100, now());

INSERT INTO public.competition_results (
  competition_id, winner_user_id, result_type,
  player_results, question_results, point_changes, final_scoreboard,
  calculated_at
) VALUES (
  'f0000000-0000-0000-0000-000000000202',
  NULL,
  'draw',
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '{}'::jsonb,
  now()
);

-- 203: forfeit (B terk etti; A forfeit_win, B forfeit_loss)
INSERT INTO public.competitions (
  id, competition_code, competition_type, grade_level, subject_id,
  scoring_rule_set_id, status, question_count, server_started_at, server_completed_at
) VALUES (
  'f0000000-0000-0000-0000-000000000203',
  'F7-FORFEIT',
  'one_vs_one',
  5,
  (SELECT id FROM public.subjects LIMIT 1),
  (SELECT id FROM public.scoring_rule_sets WHERE is_active = true LIMIT 1),
  'completed',
  1,
  now() - interval '1 hour',
  now()
);

INSERT INTO public.competition_players (
  competition_id, user_id, player_slot, status, total_points, finished_at
) VALUES
  ('f0000000-0000-0000-0000-000000000203', 'a0000000-0000-0000-0000-000000000101', 1, 'finished', 100, now()),
  ('f0000000-0000-0000-0000-000000000203', 'a0000000-0000-0000-0000-000000000102', 2, 'forfeited', 0, NULL);

INSERT INTO public.competition_results (
  competition_id, winner_user_id, result_type,
  player_results, question_results, point_changes, final_scoreboard,
  calculated_at
) VALUES (
  'f0000000-0000-0000-0000-000000000203',
  'a0000000-0000-0000-0000-000000000101',
  'forfeit',
  '[{"user_id":"a0000000-0000-0000-0000-000000000101","player_slot":1,"status":"finished"},{"user_id":"a0000000-0000-0000-0000-000000000102","player_slot":2,"status":"forfeited"}]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '{}'::jsonb,
  now()
);

-- 204: win_loss ama winner_user_id NULL (beklenmedik veri) -> no_contest
INSERT INTO public.competitions (
  id, competition_code, competition_type, grade_level, subject_id,
  scoring_rule_set_id, status, question_count, server_started_at, server_completed_at
) VALUES (
  'f0000000-0000-0000-0000-000000000204',
  'F7-NULLWIN',
  'one_vs_one',
  5,
  (SELECT id FROM public.subjects LIMIT 1),
  (SELECT id FROM public.scoring_rule_sets WHERE is_active = true LIMIT 1),
  'completed',
  1,
  now() - interval '1 hour',
  now()
);

INSERT INTO public.competition_players (
  competition_id, user_id, player_slot, status, total_points, finished_at
) VALUES
  ('f0000000-0000-0000-0000-000000000204', 'a0000000-0000-0000-0000-000000000101', 1, 'finished', 0, now()),
  ('f0000000-0000-0000-0000-000000000204', 'a0000000-0000-0000-0000-000000000102', 2, 'finished', 0, now());

INSERT INTO public.competition_results (
  competition_id, winner_user_id, result_type,
  player_results, question_results, point_changes, final_scoreboard,
  calculated_at
) VALUES (
  'f0000000-0000-0000-0000-000000000204',
  NULL,
  'win_loss',
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '{}'::jsonb,
  now()
);

\echo SETUP DONE.

-- =============================================================
-- FZ testleri (user A olarak)
-- =============================================================
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000101"}';
SET role = 'authenticated';

\echo
\echo --- FZ1: kazanan my_result = win ---

SELECT
  CASE WHEN (result->>'my_result') = 'win'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ1' AS test_id,
  'winner sees my_result=win' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid) AS result
) sub;

\echo
\echo --- FZ2: answer_result kendi sorusunda mevcut (correct) ---

SELECT
  CASE WHEN result->'question_results'->0->>'answer_result' = 'correct'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ2' AS test_id,
  'own answer_result present (correct)' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid) AS result
) sub;

\echo
\echo --- FZ3: kendi submitted_answer mevcut, rakibin cevabi yok ---

SELECT
  CASE WHEN
    result->'question_results'->0->>'submitted_answer' = 'A'
    AND result::text NOT LIKE '%"B"%'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ3' AS test_id,
  'own submitted_answer present, opponent answer absent' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid) AS result
) sub;

\echo
\echo --- FZ4: answer_result anahtari olmayan element coalesce timeout ---

SELECT
  CASE WHEN result->'question_results'->1->>'answer_result' = 'timeout'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ4' AS test_id,
  'missing answer_result coalesced to timeout' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid) AS result
) sub;

\echo
\echo --- FZ5: rakip UUID'si hicbir yerde yok ---

SELECT
  CASE WHEN result::text NOT LIKE '%a0000000-0000-0000-0000-000000000102%'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ5' AS test_id,
  'no opponent uuid anywhere in result' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid) AS result
) sub;

\echo
\echo --- FZ6: winner_user_id ham alanı donmez ---

SELECT
  CASE WHEN NOT (result ? 'winner_user_id')
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ6' AS test_id,
  'winner_user_id raw value not returned' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid) AS result
) sub;

\echo
\echo --- FZ7: draw -> my_result = draw ---

SELECT
  CASE WHEN (result->>'my_result') = 'draw'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ7' AS test_id,
  'draw fixture yields my_result=draw' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000202'::uuid) AS result
) sub;

\echo
\echo --- FZ8: forfeit (kazanan taraf) -> my_result = forfeit_win ---

SELECT
  CASE WHEN (result->>'my_result') = 'forfeit_win'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ8' AS test_id,
  'forfeit winner sees my_result=forfeit_win' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000203'::uuid) AS result
) sub;

\echo
\echo --- FZ9: winner NULL + win_loss -> no_contest ---

SELECT
  CASE WHEN (result->>'my_result') = 'no_contest'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ9' AS test_id,
  'win_loss with NULL winner yields no_contest' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000204'::uuid) AS result
) sub;

\echo
\echo --- FZ10: dogru cevap anahtari/cozum sızması yok ---

SELECT
  CASE WHEN
    result::text NOT ILIKE '%correct_answer%'
    AND result::text NOT ILIKE '%solution%'
    AND result::text NOT ILIKE '%explanation%'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ10' AS test_id,
  'no correct_answer/solution/explanation leakage' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid) AS result
) sub;

\echo
\echo --- FZ11 hazirlik (postgres): yarisma 201 gecici olarak 'active' yapilir ---

RESET role;
RESET request.jwt.claims;

UPDATE public.competitions SET status = 'active'
  WHERE id = 'f0000000-0000-0000-0000-000000000201';

\echo
\echo --- FZ11: tamamlanmamis yarismada exception (authenticated) ---

SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000101"}';
SET role = 'authenticated';

DO
$$
DECLARE
  v_result jsonb;
BEGIN
  v_result := public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid);
  RAISE NOTICE 'FAIL|FZ11|incomplete competition: expected exception';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PASS|FZ11|incomplete competition access denied';
END
$$;

\echo
\echo --- FZ11 temizlik (postgres): yarisma 201 tekrar 'completed' ---

RESET role;
RESET request.jwt.claims;

UPDATE public.competitions SET status = 'completed'
  WHERE id = 'f0000000-0000-0000-0000-000000000201';

\echo
\echo --- FZ12: katilimci olmayan kullanici exception (authenticated) ---

SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000101"}';
SET role = 'authenticated';

DO
$$
DECLARE
  v_result jsonb;
BEGIN
  SET LOCAL request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000009999"}';
  v_result := public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid);
  RAISE NOTICE 'FAIL|FZ12|non-participant: expected exception';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PASS|FZ12|non-participant access denied';
END
$$;

-- =============================================================
-- User B perspektifi (loss + forfeit_loss)
-- =============================================================
RESET role;
RESET request.jwt.claims;
SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000102"}';
SET role = 'authenticated';

\echo
\echo --- FZ13: kaybeden my_result = loss ---

SELECT
  CASE WHEN (result->>'my_result') = 'loss'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ13' AS test_id,
  'loser sees my_result=loss' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid) AS result
) sub;

\echo
\echo --- FZ14: terk eden oyuncu my_result = forfeit_loss ---

SELECT
  CASE WHEN (result->>'my_result') = 'forfeit_loss'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ14' AS test_id,
  'forfeited player sees my_result=forfeit_loss' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000203'::uuid) AS result
) sub;

-- =============================================================
-- ACL + idempotency + role yapisi (postgres olarak)
-- =============================================================
RESET role;
RESET request.jwt.claims;

\echo
\echo --- FZ15: anon EXECUTE yok, authenticated var ---

SELECT
  CASE WHEN
    NOT has_function_privilege('anon', 'public.get_own_competition_result(uuid)', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.get_own_competition_result(uuid)', 'EXECUTE')
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ15' AS test_id,
  'anon execute revoked, authenticated granted' AS description;

\echo
\echo --- FZ16: anon cagri auth hatasi verir ---

DO
$$
DECLARE
  v_result jsonb;
BEGIN
  SET LOCAL role = 'anon';
  v_result := public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid);
  RESET role;
  RAISE NOTICE 'FAIL|FZ16|anon call: expected auth exception';
EXCEPTION WHEN OTHERS THEN
  RESET role;
  RAISE NOTICE 'PASS|FZ16|anon call auth required';
END
$$;

\echo
\echo --- FZ17: 099 idempotent yeniden uygulama x2 sonrasi calisir (authenticated) ---

SET request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000101"}';
SET role = 'authenticated';

SELECT
  CASE WHEN (result->>'my_result') = 'win'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ17' AS test_id,
  'function works after idempotent re-apply (checked externally)' AS description
FROM (
  SELECT public.get_own_competition_result('f0000000-0000-0000-0000-000000000201'::uuid) AS result
) sub;

RESET role;
RESET request.jwt.claims;

\echo
\echo --- FZ18: SECURITY DEFINER + sabit search_path korundu ---

SELECT
  CASE WHEN
    p.prosecdef = true
    AND array_to_string(p.proconfig, ',') = 'search_path="public, pg_catalog"'
  THEN 'PASS' ELSE 'FAIL'
  END AS status,
  'FZ18' AS test_id,
  'security definer + fixed search_path preserved' AS description
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'get_own_competition_result';

-- =============================================================
-- CLEANUP
-- =============================================================

\echo
\echo --- CLEANUP ---

DELETE FROM public.competition_results WHERE competition_id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000204');
DELETE FROM public.competition_players WHERE competition_id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000204');
DELETE FROM public.competition_questions WHERE competition_id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000204');
DELETE FROM public.competition_answers WHERE competition_id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000204');
DELETE FROM public.competition_point_changes WHERE competition_id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000204');
DELETE FROM public.competitions WHERE id IN (
  'f0000000-0000-0000-0000-000000000201',
  'f0000000-0000-0000-0000-000000000203',
  'f0000000-0000-0000-0000-000000000202',
  'f0000000-0000-0000-0000-000000000204');
DELETE FROM auth.users WHERE id IN (
  'a0000000-0000-0000-0000-000000000101',
  'a0000000-0000-0000-0000-000000000102'
) AND email LIKE '%fz7_%';

\echo CLEANUP DONE.
\echo ============================================================
\echo qa_faz7_own_result_details.sql COMPLETE
\echo ============================================================
