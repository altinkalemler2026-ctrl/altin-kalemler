-- 027_competition_rpc_security.sql
-- Altın Kalemler
--
-- Amaç:
-- Client tarafından çağrılan 6 yarışma RPC'sinin güçlü
-- SECURITY DEFINER implementasyonlarını public şemadan çıkarıp
-- private şemaya taşımak.
--
-- Public şemada aynı isim/signature ile SECURITY INVOKER
-- wrapper bırakılır.
--
-- Böylece uygulamadaki mevcut RPC çağrıları değişmez:
--
-- public.get_competition_question_payload(...)
-- public.get_competition_scoreboard(...)
-- public.get_current_competition_question()
-- public.set_competition_player_ready(...)
-- public.submit_competition_answer(...)
-- public.sync_competition_state(...)
--
-- ÖNEMLİ:
-- private şeması Supabase Data API "Exposed Schemas"
-- listesine eklenmemelidir.

BEGIN;


-- =========================================================
-- 1. PRIVATE ŞEMA GÜVENLİĞİ
-- =========================================================

CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL
ON SCHEMA private
FROM PUBLIC;

REVOKE ALL
ON SCHEMA private
FROM anon;

-- Public SECURITY INVOKER wrapper'ın private fonksiyonu
-- çağırabilmesi için authenticated role schema USAGE gerekir.
GRANT USAGE
ON SCHEMA private
TO authenticated;

GRANT USAGE
ON SCHEMA private
TO service_role;


-- =========================================================
-- 2. get_competition_question_payload(uuid)
-- =========================================================

ALTER FUNCTION
  public.get_competition_question_payload(uuid)
SET SCHEMA private;


CREATE FUNCTION public.get_competition_question_payload(
  p_competition_question_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.get_competition_question_payload(
    p_competition_question_id
  );
$$;


-- =========================================================
-- 3. get_competition_scoreboard(uuid)
-- =========================================================

ALTER FUNCTION
  public.get_competition_scoreboard(uuid)
SET SCHEMA private;


CREATE FUNCTION public.get_competition_scoreboard(
  p_competition_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.get_competition_scoreboard(
    p_competition_id
  );
$$;


-- =========================================================
-- 4. get_current_competition_question()
-- =========================================================

ALTER FUNCTION
  public.get_current_competition_question()
SET SCHEMA private;


CREATE FUNCTION public.get_current_competition_question()
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.get_current_competition_question();
$$;


-- =========================================================
-- 5. set_competition_player_ready(uuid)
-- =========================================================

ALTER FUNCTION
  public.set_competition_player_ready(uuid)
SET SCHEMA private;


CREATE FUNCTION public.set_competition_player_ready(
  p_competition_id uuid
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.set_competition_player_ready(
    p_competition_id
  );
$$;


-- =========================================================
-- 6. submit_competition_answer(uuid, text)
-- =========================================================

ALTER FUNCTION
  public.submit_competition_answer(uuid, text)
SET SCHEMA private;


CREATE FUNCTION public.submit_competition_answer(
  p_competition_question_id uuid,
  p_submitted_answer text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.submit_competition_answer(
    p_competition_question_id,
    p_submitted_answer
  );
$$;


-- =========================================================
-- 7. sync_competition_state(uuid)
-- =========================================================

ALTER FUNCTION
  public.sync_competition_state(uuid)
SET SCHEMA private;


CREATE FUNCTION public.sync_competition_state(
  p_competition_id uuid
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.sync_competition_state(
    p_competition_id
  );
$$;


-- =========================================================
-- 8. PRIVATE IMPLEMENTATION İZİNLERİ
--
-- Public wrapper SECURITY INVOKER olduğu için,
-- authenticated rolünün private implementation'ı execute
-- edebilmesi gerekir.
--
-- private şema Data API'ye expose edilmediği için bu
-- fonksiyonlar /rest/v1/rpc/... yüzeyinde görünmez.
-- =========================================================

REVOKE ALL
ON FUNCTION private.get_competition_question_payload(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION private.get_competition_question_payload(uuid)
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION private.get_competition_scoreboard(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION private.get_competition_scoreboard(uuid)
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION private.get_current_competition_question()
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION private.get_current_competition_question()
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION private.set_competition_player_ready(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION private.set_competition_player_ready(uuid)
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION private.submit_competition_answer(uuid, text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION private.submit_competition_answer(uuid, text)
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION private.sync_competition_state(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION private.sync_competition_state(uuid)
TO authenticated, service_role;


-- =========================================================
-- 9. PUBLIC WRAPPER İZİNLERİ
--
-- Anon erişimi yok.
-- Sadece giriş yapmış öğrenci ve service_role.
-- =========================================================

REVOKE ALL
ON FUNCTION public.get_competition_question_payload(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_competition_question_payload(uuid)
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION public.get_competition_scoreboard(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_competition_scoreboard(uuid)
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION public.get_current_competition_question()
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_current_competition_question()
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION public.set_competition_player_ready(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.set_competition_player_ready(uuid)
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION public.submit_competition_answer(uuid, text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.submit_competition_answer(uuid, text)
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION public.sync_competition_state(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.sync_competition_state(uuid)
TO authenticated, service_role;


-- =========================================================
-- 10. PRIVATE ŞEMADA YENİ FONKSİYONLAR İÇİN
-- GÜVENLİ DEFAULT PRIVILEGES
-- =========================================================

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA private
REVOKE EXECUTE ON FUNCTIONS
FROM PUBLIC;

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA private
REVOKE EXECUTE ON FUNCTIONS
FROM anon;

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA private
REVOKE EXECUTE ON FUNCTIONS
FROM authenticated;


COMMIT;


-- =========================================================
-- 11. DOĞRULAMA
--
-- Her fonksiyon için:
--
-- private = security_definer true
-- public  = security_definer false
--
-- görmemiz gerekiyor.
-- =========================================================

SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  p.prosecdef AS security_definer,
  p.proconfig AS configuration
FROM pg_proc p
JOIN pg_namespace n
  ON n.oid = p.pronamespace
WHERE
  n.nspname IN ('public', 'private')
  AND p.proname IN (
    'get_competition_question_payload',
    'get_competition_scoreboard',
    'get_current_competition_question',
    'set_competition_player_ready',
    'submit_competition_answer',
    'sync_competition_state'
  )
ORDER BY
  p.proname,
  n.nspname;