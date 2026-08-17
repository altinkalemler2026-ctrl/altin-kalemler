-- 026_private_security_helpers.sql
-- Altın Kalemler
--
-- Amaç:
-- SECURITY DEFINER helper fonksiyonlarını API'ye açık
-- public şemadan private şemaya taşımak.
--
-- Mevcut RLS policy ve diğer fonksiyonların kullandığı
-- public fonksiyon isimleri korunur.
--
-- Public tarafta sadece SECURITY INVOKER wrapper kalır.
--
-- ÖNEMLİ:
-- private şeması Supabase "Exposed Schemas" listesine
-- EKLENMEMELİDİR.

BEGIN;


-- =========================================================
-- 1. PRIVATE ŞEMA
-- =========================================================

CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL
ON SCHEMA private
FROM PUBLIC;

REVOKE ALL
ON SCHEMA private
FROM anon;

REVOKE ALL
ON SCHEMA private
FROM authenticated;

GRANT USAGE
ON SCHEMA private
TO authenticated;

GRANT USAGE
ON SCHEMA private
TO service_role;


-- =========================================================
-- 2. has_admin_permission(uuid, text)
--
-- Güçlü fonksiyonu private'a taşı.
-- =========================================================

ALTER FUNCTION public.has_admin_permission(uuid, text)
SET SCHEMA private;


-- Public isim korunuyor.
-- Client'ın bunu doğrudan kullanmasına gerek yok.
CREATE FUNCTION public.has_admin_permission(
  p_user_id uuid,
  p_permission_code text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.has_admin_permission(
    p_user_id,
    p_permission_code
  );
$$;


-- =========================================================
-- 3. is_current_user_admin()
-- =========================================================

ALTER FUNCTION public.is_current_user_admin()
SET SCHEMA private;


CREATE FUNCTION public.is_current_user_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.is_current_user_admin();
$$;


-- =========================================================
-- 4. is_current_user_super_admin()
-- =========================================================

ALTER FUNCTION public.is_current_user_super_admin()
SET SCHEMA private;


CREATE FUNCTION public.is_current_user_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.is_current_user_super_admin();
$$;


-- =========================================================
-- 5. current_user_has_admin_permission(text)
-- =========================================================

ALTER FUNCTION public.current_user_has_admin_permission(text)
SET SCHEMA private;


CREATE FUNCTION public.current_user_has_admin_permission(
  p_permission_code text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.current_user_has_admin_permission(
    p_permission_code
  );
$$;


-- =========================================================
-- 6. is_competition_participant(uuid, uuid)
-- =========================================================

ALTER FUNCTION public.is_competition_participant(uuid, uuid)
SET SCHEMA private;


CREATE FUNCTION public.is_competition_participant(
  p_competition_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.is_competition_participant(
    p_competition_id,
    p_user_id
  );
$$;


-- =========================================================
-- 7. PRIVATE FONKSİYONLARIN EXECUTE YETKİLERİNİ TEMİZLE
-- =========================================================

REVOKE ALL
ON FUNCTION private.has_admin_permission(uuid, text)
FROM PUBLIC, anon, authenticated;

REVOKE ALL
ON FUNCTION private.is_current_user_admin()
FROM PUBLIC, anon, authenticated;

REVOKE ALL
ON FUNCTION private.is_current_user_super_admin()
FROM PUBLIC, anon, authenticated;

REVOKE ALL
ON FUNCTION private.current_user_has_admin_permission(text)
FROM PUBLIC, anon, authenticated;

REVOKE ALL
ON FUNCTION private.is_competition_participant(uuid, uuid)
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 8. WRAPPER'LARIN ÇALIŞABİLMESİ İÇİN
-- GEREKLİ PRIVATE EXECUTE YETKİLERİ
-- =========================================================

-- authenticated kullanıcının public wrapper üzerinden
-- kendi admin durumunu / permission durumunu kontrol etmesi
-- gerekebilir.

GRANT EXECUTE
ON FUNCTION private.is_current_user_admin()
TO authenticated;

GRANT EXECUTE
ON FUNCTION private.is_current_user_super_admin()
TO authenticated;

GRANT EXECUTE
ON FUNCTION private.current_user_has_admin_permission(text)
TO authenticated;

GRANT EXECUTE
ON FUNCTION private.is_competition_participant(uuid, uuid)
TO authenticated;


-- has_admin_permission arbitrary user_id aldığı için
-- authenticated role'a doğrudan vermiyoruz.
-- Bu fonksiyon internal/helper olarak kalacak.

GRANT EXECUTE
ON FUNCTION private.has_admin_permission(uuid, text)
TO service_role;


-- Service role gerektiğinde tüm helper'ları kullanabilir.

GRANT EXECUTE
ON FUNCTION private.is_current_user_admin()
TO service_role;

GRANT EXECUTE
ON FUNCTION private.is_current_user_super_admin()
TO service_role;

GRANT EXECUTE
ON FUNCTION private.current_user_has_admin_permission(text)
TO service_role;

GRANT EXECUTE
ON FUNCTION private.is_competition_participant(uuid, uuid)
TO service_role;


-- =========================================================
-- 9. PUBLIC WRAPPER EXECUTE YETKİLERİ
-- =========================================================

-- ---------------------------------------------------------
-- has_admin_permission(uuid,text)
-- Arbitrary user_id alabildiği için öğrenciye açık değil.
-- ---------------------------------------------------------

REVOKE ALL
ON FUNCTION public.has_admin_permission(uuid, text)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.has_admin_permission(uuid, text)
TO service_role;


-- ---------------------------------------------------------
-- Current-user helper'ları authenticated kullanabilir.
-- Bunlar artık SECURITY INVOKER'dır.
-- ---------------------------------------------------------

REVOKE ALL
ON FUNCTION public.is_current_user_admin()
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.is_current_user_admin()
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION public.is_current_user_super_admin()
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.is_current_user_super_admin()
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION public.current_user_has_admin_permission(text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.current_user_has_admin_permission(text)
TO authenticated, service_role;


REVOKE ALL
ON FUNCTION public.is_competition_participant(uuid, uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.is_competition_participant(uuid, uuid)
TO authenticated, service_role;


-- =========================================================
-- 10. PRIVATE ŞEMA İÇİN GÜVENLİ DEFAULT PRIVILEGES
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
-- Migration başarılı olduktan sonra aşağıdaki SELECT
-- sonuç verir.
--
-- Public fonksiyonlarda security_definer = false,
-- private fonksiyonlarda security_definer = true
-- görmemiz gerekiyor.
-- =========================================================

SELECT
  n.nspname AS schema_name,
  p.proname AS function_name,
  p.prosecdef AS security_definer,
  p.proconfig AS configuration
FROM pg_proc p
JOIN pg_namespace n
  ON n.oid = p.pronamespace
WHERE
  n.nspname IN ('public', 'private')
  AND p.proname IN (
    'has_admin_permission',
    'is_current_user_admin',
    'is_current_user_super_admin',
    'current_user_has_admin_permission',
    'is_competition_participant'
  )
ORDER BY
  p.proname,
  n.nspname;