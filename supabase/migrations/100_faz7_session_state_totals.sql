-- ============================================================
-- 100_faz7_session_state_totals.sql
-- Altın Kalemler - Faz 7 (Yarışma öğrenci UX'i)
--
-- Amaç:
--   sync_competition_state yanıtına question_count alanı eklenir.
--   Oturum ekranı "Soru x / N" göstergesi için toplam soru sayısına
--   ihtiyaç duyar; 023/027 sözleşmesinde bu alan yoktu ve istemci
--   totalQuestions=0 ile düşüyordu.
--
-- KORUNAN GÜVENLİK DAVRANIŞLARI
-- (SYSTEMIC_MIGRATION_REPLACEMENT_RISK dersi: CREATE OR REPLACE
-- içeren her migration "önceki güvenlik davranışları" listesi
-- zorunludur):
--   - SECURITY DEFINER + sabit search_path ('public')
--   - auth.uid() kimlik kapısı (anon → exception)
--   - is_competition_participant katılımcı kapısı
--   - advance_competition_progress çağrısı (timeout ilerletmesi)
--   - Yalnız çağıranın KENDİ alanları döner; rakip skoru
--     (opponent_current_score) yanıtta kalır ancak istemci
--     mapper'ı (mapSessionState) bu alanı düşürür — davranış
--     değişmez, rakip kimliği/özel verisi ASLA dönmez
--   - Yanıt yalnızca YENİ bir alanla genişletilir (additive);
--     mevcut alan adları ve değerleri aynen korunur
--   - completed dalı aynen korunur (yalnız status +
--     scoreboard_available)
--
-- Migration type: FORWARD ONLY (append-only dosya; eski migration
-- değiştirilmez).
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION private.sync_competition_state(
  p_competition_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;

  v_progress jsonb;

  v_status text;

  v_current_question_id uuid;
  v_current_question_order integer;

  v_sent_at timestamptz;
  v_deadline_at timestamptz;
  v_time_limit_seconds integer;

  v_has_answered boolean;

  v_my_points integer;
  v_opponent_points integer;

  v_question_count integer;
BEGIN

  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION
      'Authentication required.';
  END IF;

  IF NOT public.is_competition_participant(
    p_competition_id,
    v_user_id
  ) THEN
    RAISE EXCEPTION
      'You are not a participant in this competition.';
  END IF;

  -- -------------------------------------------------------
  -- Önce server state'i ilerlet.
  -- -------------------------------------------------------

  v_progress :=
    public.advance_competition_progress(
      p_competition_id
    );

  SELECT
    c.status,
    c.current_question_id,
    c.current_question_order,
    c.question_count

  INTO
    v_status,
    v_current_question_id,
    v_current_question_order,
    v_question_count

  FROM public.competitions c

  WHERE c.id = p_competition_id;

  -- -------------------------------------------------------
  -- Yarışma bitti.
  -- -------------------------------------------------------

  IF v_status = 'completed' THEN

    RETURN jsonb_build_object(
      'status',
      'completed',

      'scoreboard_available',
      true
    );

  END IF;

  -- -------------------------------------------------------
  -- Güncel soru zamanı.
  -- -------------------------------------------------------

  IF v_current_question_id IS NOT NULL THEN

    SELECT
      cq.sent_at,
      cq.deadline_at,
      cq.time_limit_seconds

    INTO
      v_sent_at,
      v_deadline_at,
      v_time_limit_seconds

    FROM public.competition_questions cq

    WHERE cq.id = v_current_question_id;

    SELECT EXISTS (
      SELECT 1

      FROM public.competition_answers ca

      WHERE ca.competition_question_id =
            v_current_question_id

        AND ca.user_id =
            v_user_id
    )

    INTO v_has_answered;

  END IF;

  -- -------------------------------------------------------
  -- Kendi anlık toplam skoru.
  -- -------------------------------------------------------

  SELECT cp.total_points
  INTO v_my_points

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id
    AND cp.user_id = v_user_id;

  -- -------------------------------------------------------
  -- Rakip anlık toplam skoru.
  --
  -- Bu ileride ürün kararına göre yarışma sırasında
  -- gizlenebilir. Şimdilik altyapı destekliyor.
  -- -------------------------------------------------------

  SELECT cp.total_points
  INTO v_opponent_points

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id
    AND cp.user_id <> v_user_id

  LIMIT 1;

  RETURN jsonb_build_object(
    'status',
    v_status,

    'progress',
    v_progress,

    'current_question_id',
    v_current_question_id,

    'current_question_order',
    v_current_question_order,

    'question_count',
    v_question_count,

    'sent_at',
    v_sent_at,

    'deadline_at',
    v_deadline_at,

    'time_limit_seconds',
    v_time_limit_seconds,

    'has_answered_current_question',
    COALESCE(
      v_has_answered,
      false
    ),

    'my_current_score',
    COALESCE(
      v_my_points,
      0
    ),

    'opponent_current_score',
    COALESCE(
      v_opponent_points,
      0
    )
  );

END;
$$;

COMMIT;

-- ============================================================
-- DOĞRULAMA
-- ============================================================

-- 1. Güvenlik davranışları korundu mu?
SELECT
  p.proname AS function_name,
  p.prosecdef AS is_security_definer,
  p.proconfig AS search_path_config
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'sync_competition_state';

-- 2. Public wrapper erişilebilirliği korunuyor mu?
--    (027: authenticated EXECUTE var, anon yok)
SELECT
  has_function_privilege('authenticated',
    'public.sync_competition_state(uuid)', 'EXECUTE')
    AS authenticated_must_be_true,
  has_function_privilege('anon',
    'public.sync_competition_state(uuid)', 'EXECUTE')
    AS anon_must_be_false;
