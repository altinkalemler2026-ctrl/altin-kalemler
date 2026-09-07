-- ============================================================
-- 099_faz7_own_result_details.sql
-- Altın Kalemler - Faz 7 (Yarışma öğrenci UX'i)
--
-- Amaç:
--   get_own_competition_result çağrısına öğrencinin KENDİ sonuç
--   detayları eklenir:
--
--   1. my_result: win / loss / draw / forfeit_win / forfeit_loss /
--      no_contest
--      winner_user_id yalnızca bu türevi hesaplamak için fonksiyon
--      İÇİNDE kullanılır; ham winner_user_id değeri ASLA
--      DÖNDÜRÜLMEZ.
--   2. Soru bazında KENDİ cevap durumu (answer_result) ve KENDİ
--      gönderdiği seçenek (submitted_answer) — sonuç ekranındaki
--      hata inceleme görünümü için. Rakip verisi (rakip cevabı,
--      rakip skoru, rakip kimliği) ASLA dönmez.
--
-- KORUNAN GÜVENLİK DAVRANIŞLARI
-- (SYSTEMIC_MIGRATION_REPLACEMENT_RISK dersi: CREATE OR REPLACE
-- içeren her migration "önceki güvenlik davranışları" listesi
-- zorunludur; 081'den birebir korunur):
--   - SECURITY DEFINER + sabit search_path ('public, pg_catalog')
--   - auth.uid() kimlik kapısı (anon → exception)
--   - is_competition_participant katılımcı kapısı
--   - Yalnız 'completed' yarışmada sonuç döner
--   - Yalnız çağıranın KENDİ satırı/alanları döner; winner_user_id,
--     players dizisi, rakip user_id/skoru DÖNDÜRÜLMEZ
--   - ACL: 081'deki GRANT (authenticated, service_role) CREATE OR
--     REPLACE ile değişmez; aşağıda doğrulama sorgusu vardır
--
-- Değişiklik additive'dir: mevcut alan adları ve değerleri
-- aynen korunur, yalnız yeni alanlar eklenir.
-- Migration type: FORWARD ONLY (append-only dosya; eski migration
-- değiştirilmez).
-- ============================================================

BEGIN;

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

  -- 081 KORUNAN: kimlik kapısı
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  -- 081 KORUNAN: katılımcı kapısı
  IF NOT public.is_competition_participant(
    p_competition_id,
    v_user_id
  ) THEN
    RAISE EXCEPTION 'You are not a participant in this competition.';
  END IF;

  -- 081 KORUNAN: yarışma varlık + completed kapısı
  SELECT c.status INTO v_status
  FROM public.competitions c
  WHERE c.id = p_competition_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Competition not found.';
  END IF;

  IF v_status <> 'completed' THEN
    RAISE EXCEPTION 'Result is available after the competition ends.';
  END IF;

  -- 081 gövdesi + FAZ 7 ekleri (my_result, answer_result,
  -- submitted_answer). Yalnız kendi verisi filtrelenerek.
  SELECT jsonb_build_object(
    'competition_id', c.id,
    'competition_code', c.competition_code,
    'competition_type', c.competition_type,
    'grade_level', c.grade_level,
    'subject_id', c.subject_id,
    'question_count', c.question_count,
    'result_type', cr.result_type,
    'my_result', CASE
      WHEN cr.result_type = 'draw'
        THEN 'draw'
      WHEN cr.result_type = 'win_loss'
        AND cr.winner_user_id IS NULL
        THEN 'no_contest'
      WHEN cr.result_type = 'win_loss'
        AND cr.winner_user_id = v_user_id
        THEN 'win'
      WHEN cr.result_type = 'win_loss'
        THEN 'loss'
      WHEN cr.result_type = 'forfeit'
        AND COALESCE(own.own_status, '') = 'forfeited'
        THEN 'forfeit_loss'
      WHEN cr.result_type = 'forfeit'
        THEN 'forfeit_win'
      ELSE 'no_contest'
    END,
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
            'time_ms', p->>'time_ms',
            'answer_result', COALESCE(
              p->>'answer_result',
              'timeout'
            ),
            'submitted_answer', p->>'submitted_answer'
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
      own_elem.elem->>'finished_at' AS finished_at,
      own_elem.elem->>'status' AS own_status
  ) own ON true
  WHERE c.id = p_competition_id;

  RETURN v_result;

END;
$$;

COMMIT;

-- ============================================================
-- ACL SIKILASTIRMASI (084 deseni: tam revoke -> authenticated grant)
--
-- 081'de default PUBLIC execute ayricaligi acikca revoke edilmedigi
-- icin anon EXECUTE Gorebiliyordu (fonksiyon auth kapisiyla yine de
-- fail-closed). Faz 7 bu ACL'yi proje konvansiyonuna ceker:
-- PUBLIC/anon revoke, authenticated + service_role grant.
-- ============================================================

REVOKE ALL ON FUNCTION public.get_own_competition_result(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_own_competition_result(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_own_competition_result(uuid)
  TO authenticated, service_role;


-- ============================================================
-- DOĞRULAMA
-- ============================================================

-- 1. Güvenlik davranışları korundu mu?
select
  p.proname as function_name,
  p.prosecdef as is_security_definer,
  p.proconfig as search_path_config,
  has_function_privilege('authenticated', p.oid, 'EXECUTE')
    as authenticated_can_execute,
  has_function_privilege('service_role', p.oid, 'EXECUTE')
    as service_role_can_execute,
  has_function_privilege('anon', p.oid, 'EXECUTE')
    as anon_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'get_own_competition_result';

-- 2. 081 REVOKE korunuyor mu? (authenticated scoreboard erişimi yok)
select
  has_function_privilege('authenticated',
    'public.get_competition_scoreboard(uuid)', 'EXECUTE')
    as authenticated_scoreboard_must_be_false;
