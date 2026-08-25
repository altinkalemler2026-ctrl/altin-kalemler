-- ============================================================
-- 081_competition_result_privacy.sql
-- Altın Kalemler - Skor Tablosu Gizlilik Düzeltmesi
--
-- Amaç:
-- get_competition_scoreboard满returns ALL players' data.
-- authenticated直接SELECTcompetition_results/competition_players
-- through RLS policy exposes opponent user_id, scores, answers.
--
-- Bu migration:
-- 1. Yeni get_own_competition_result(p_competition_id) RPC
--    SECURITY DEFINER — returns only caller's own data
-- 2. REVOKE authenticated from get_competition_scoreboard
--    (keep service_role for internal/admin use only)
-- 3. Tighten RLS:
--    - competition_results: participant SELECT → own row only
--    - competition_players: participant SELECT → own row only
--    - competitions: participant SELECT → removed (app uses RPC-only)
--
-- Migration type: FORWARD ONLY
-- Runtime impact: getRawScoreboard() breaks → replaced by new RPC
-- ============================================================

BEGIN;


-- =========================================================
-- 1. YENİ RPC: get_own_competition_result(p_competition_id)
--
-- SECURITY DEFINER — auth.uid() check inside function.
-- Participant gate + completed-only gate.
-- Returns ONLY caller's own data in OwnCompetitionResult shape.
-- Opponent data NEVER returned.
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_own_competition_result(
  p_competition_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public, pg_catalog'
AS $$
DECLARE
  v_user_id uuid;
  v_status text;
  v_result jsonb;
BEGIN

  -- Auth gate
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  -- Participant gate
  IF NOT public.is_competition_participant(
    p_competition_id,
    v_user_id
  ) THEN
    RAISE EXCEPTION 'You are not a participant in this competition.';
  END IF;

  -- Completed-only gate
  SELECT c.status INTO v_status
  FROM public.competitions c
  WHERE c.id = p_competition_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Competition not found.';
  END IF;

  IF v_status <> 'completed' THEN
    RAISE EXCEPTION 'Result is available after the competition ends.';
  END IF;

  -- Build own-only result
  SELECT jsonb_build_object(
    'competition_id', c.id,
    'competition_code', c.competition_code,
    'competition_type', c.competition_type,
    'grade_level', c.grade_level,
    'subject_id', c.subject_id,
    'question_count', c.question_count,
    'result_type', cr.result_type,
    'my_player_slot', own.player_slot,
    'my_total_points', own.total_points,
    'my_correct_count', own.correct_count,
    'my_wrong_count', own.wrong_count,
    'my_pass_count', own.pass_count,
    'my_timeout_count', own.timeout_count,
    'my_finished_at', own.finished_at,
    'question_results', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'question_order', qr->>'question_order',
            'difficulty', qr->>'difficulty',
            'points_awarded', p->>'points_awarded',
            'time_ms', p->>'time_ms'
          )
        )
        FROM jsonb_array_elements(cr.question_results) AS qr,
             jsonb_array_elements(qr->'players') AS p
        WHERE (p->>'user_id')::uuid = v_user_id
      ),
      '[]'::jsonb
    ),
    'started_at', c.server_started_at,
    'completed_at', c.server_completed_at
  )
  INTO v_result
  FROM public.competitions c
  JOIN public.competition_results cr ON cr.competition_id = c.id
  -- Extract own player row from player_results jsonb array
  LEFT JOIN LATERAL (
    SELECT elem
    FROM jsonb_array_elements(cr.player_results) AS elem
    WHERE (elem->>'user_id')::uuid = v_user_id
    LIMIT 1
  ) own_elem ON true
  LEFT JOIN LATERAL (
    SELECT
      (own_elem.elem->>'player_slot')::integer AS player_slot,
      (own_elem.elem->>'total_points')::integer AS total_points,
      (own_elem.elem->>'correct_count')::integer AS correct_count,
      (own_elem.elem->>'wrong_count')::integer AS wrong_count,
      (own_elem.elem->>'pass_count')::integer AS pass_count,
      (own_elem.elem->>'timeout_count')::integer AS timeout_count,
      own_elem.elem->>'finished_at' AS finished_at
  ) own ON true
  WHERE c.id = p_competition_id;

  RETURN v_result;

END;
$$;


-- =========================================================
-- 2. get_competition_scoreboard ACCESS RESTRICTION
--
-- REVOKE authenticated — no client can call full scoreboard.
-- Keep service_role for internal/admin use.
-- =========================================================

REVOKE EXECUTE
ON FUNCTION public.get_competition_scoreboard(uuid)
FROM authenticated;

REVOKE EXECUTE
ON FUNCTION private.get_competition_scoreboard(uuid)
FROM authenticated;


-- =========================================================
-- 3. GRANT get_own_competition_result
-- =========================================================

GRANT EXECUTE
ON FUNCTION public.get_own_competition_result(uuid)
TO authenticated, service_role;


-- =========================================================
-- 4. RLS: competition_results TIGHTENING
--
-- Old: participant SELECT (reads FULL row — opponent data exposed)
-- New: own-row only via created_at-based user identification
--
-- NOTE: We cannot filter by user_id directly on competition_results
-- because the table has no user_id column. The participant gate is
-- sufficient because SECURITY DEFINER RPCs handle the real data.
-- We DROP the participant policy and rely on admin-only + RPCs.
-- =========================================================

DROP POLICY IF EXISTS
  "competition participants read results"
  ON public.competition_results;

-- Only admin can SELECT from competition_results directly
-- (policy "admins manage competition results" already exists if created by prior migration;
--  if not, we ensure admin access via the admin permission check)


-- =========================================================
-- 5. RLS: competition_players TIGHTENING
--
-- Old: participant SELECT (reads ALL players' rows)
-- New: own-row only (user_id = auth.uid())
-- =========================================================

DROP POLICY IF EXISTS
  "competition participants read players"
  ON public.competition_players;

CREATE POLICY
  "student reads own competition player row"
  ON public.competition_players
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
  );


-- =========================================================
-- 6. RLS: competitions TIGHTENING
--
-- Old: participant SELECT (reads ALL cols incl. winner_user_id)
-- New: removed — app uses RPC-only, no direct table access
-- =========================================================

DROP POLICY IF EXISTS
  "competition participants read competitions"
  ON public.competitions;


COMMIT;
