-- 025_security_hardening.sql
-- Altın Kalemler
--
-- Supabase Security Advisor temizliği:
-- - mutable search_path düzeltmeleri
-- - SECURITY DEFINER fonksiyon execute izinlerini daraltma
-- - yalnızca gerçekten client tarafından çağrılması gereken RPC'leri açma


-- =========================================================
-- 1. SEARCH_PATH MUTABLE UYARILARI
-- =========================================================

ALTER FUNCTION public.calculate_accuracy(integer, integer)
SET search_path = '';

ALTER FUNCTION public.validate_question_promotion()
SET search_path = '';


-- =========================================================
-- 2. TÜM HASSAS / INTERNAL FONKSİYONLARDA
-- PUBLIC, ANON, AUTHENTICATED EXECUTE KAPAT
-- =========================================================

REVOKE EXECUTE
ON FUNCTION public.advance_competition_progress(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.after_competition_answer_progress()
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.create_missing_competition_timeouts(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.current_user_has_admin_permission(text)
FROM PUBLIC, anon;

REVOKE EXECUTE
ON FUNCTION public.finalize_competition_if_ready(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.get_competition_question_payload(uuid)
FROM PUBLIC, anon;

REVOKE EXECUTE
ON FUNCTION public.get_internal_correct_answer(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.handle_new_user()
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.has_admin_permission(uuid, text)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.is_competition_participant(uuid, uuid)
FROM PUBLIC, anon;

REVOKE EXECUTE
ON FUNCTION public.is_current_user_admin()
FROM PUBLIC, anon;

REVOKE EXECUTE
ON FUNCTION public.is_current_user_super_admin()
FROM PUBLIC, anon;

REVOKE EXECUTE
ON FUNCTION public.recalculate_competition_player_score(uuid, uuid)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.release_competition_question(uuid, integer)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.resolve_competition_points(
  uuid,
  smallint,
  text,
  text,
  text
)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.resolve_competition_question_time_limit(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.resolve_competition_time_band(
  uuid,
  uuid,
  smallint,
  text,
  integer
)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.set_updated_at()
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.snapshot_competition_answer_band_name()
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.validate_competition_question_limit()
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.validate_question_promotion()
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public.validate_solve_time_profile_for_scoring()
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 3. CLIENT TARAFINDAN ÇAĞRILACAK RPC'LER
-- SADECE authenticated
-- =========================================================

REVOKE EXECUTE
ON FUNCTION public.submit_competition_answer(uuid, text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.submit_competition_answer(uuid, text)
TO authenticated;


REVOKE EXECUTE
ON FUNCTION public.set_competition_player_ready(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.set_competition_player_ready(uuid)
TO authenticated;


REVOKE EXECUTE
ON FUNCTION public.sync_competition_state(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.sync_competition_state(uuid)
TO authenticated;


REVOKE EXECUTE
ON FUNCTION public.get_current_competition_question()
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_current_competition_question()
TO authenticated;


REVOKE EXECUTE
ON FUNCTION public.get_competition_scoreboard(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_competition_scoreboard(uuid)
TO authenticated;


REVOKE EXECUTE
ON FUNCTION public.get_competition_question_payload(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_competition_question_payload(uuid)
TO authenticated;


REVOKE EXECUTE
ON FUNCTION public.is_competition_participant(uuid, uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.is_competition_participant(uuid, uuid)
TO authenticated;


REVOKE EXECUTE
ON FUNCTION public.current_user_has_admin_permission(text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.current_user_has_admin_permission(text)
TO authenticated;


REVOKE EXECUTE
ON FUNCTION public.is_current_user_admin()
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.is_current_user_admin()
TO authenticated;


REVOKE EXECUTE
ON FUNCTION public.is_current_user_super_admin()
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.is_current_user_super_admin()
TO authenticated;


-- =========================================================
-- 4. NORMAL FONKSİYONLAR
-- =========================================================

REVOKE EXECUTE
ON FUNCTION public.calculate_accuracy(integer, integer)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.calculate_accuracy(integer, integer)
TO authenticated;


-- =========================================================
-- 5. YENİ FONKSİYONLAR İÇİN DAHA GÜVENLİ VARSAYILAN
-- =========================================================

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA public
REVOKE EXECUTE ON FUNCTIONS
FROM PUBLIC;

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA public
REVOKE EXECUTE ON FUNCTIONS
FROM anon;

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA public
REVOKE EXECUTE ON FUNCTIONS
FROM authenticated;