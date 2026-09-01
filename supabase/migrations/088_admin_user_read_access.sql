-- ============================================================
-- 088_admin_user_read_access.sql
-- Phase 3 admin users — SALT-OKUNUR KULLANICI ERİŞİMİ (RLS + GRANT)
--
-- Amaç:
--   Yetkili (users.manage sahibi) admin'in student_profiles ve
--   student_public_profiles tablolarını okuyabilmesini sağlamak.
--
--   Kapsam YALNIZCA ADMIN SELECT'tir:
--     - INSERT/UPDATE/DELETE yetkisi EKLENMEZ.
--     - RLS AÇIK kalır; GRANT tek başına satır açmaz.
--     - Mevcut öğrenci görünürlük semantiği DEĞİŞMEZ.
--
-- Yaklaşım:
--   PostgreSQL permissive politikalar OR birleşir; bu nedenle
--   mevcut öğrenci politikalarına dokunulmadan AYRI bir admin
--   SELECT politikası eklenir (SEPARATE_POLICY). Böylece:
--     - admin olmayan authenticated: mevcut politikaların izin
--       verdiği satırları görür (own-row / is_visible).
--     - users.manage admin'i: tüm satırları görür.
--
--   Canonical helper: public.current_user_has_admin_permission('users.manage')
-- ============================================================

BEGIN;


-- ============================================================
-- A) public.student_profiles
--    Mevcut öğrenci politikaları (select_own, update_own,
--    insert_own) AYNEN korunur; yalnızca SELECT grant + admin policy.
-- ============================================================

GRANT SELECT
ON public.student_profiles
TO authenticated;

DROP POLICY IF EXISTS "admin read all student profiles"
ON public.student_profiles;

CREATE POLICY "admin read all student profiles"
ON public.student_profiles
FOR SELECT
TO authenticated
USING (
  public.current_user_has_admin_permission('users.manage')
);


-- ============================================================
-- B) public.student_public_profiles
--    Mevcut öğrenci politikası (authenticated read visible
--    public profiles) AYNEN korunur; yalnızca SELECT grant +
--    admin policy.
-- ============================================================

GRANT SELECT
ON public.student_public_profiles
TO authenticated;

DROP POLICY IF EXISTS "admin read all public profiles"
ON public.student_public_profiles;

CREATE POLICY "admin read all public profiles"
ON public.student_public_profiles
FOR SELECT
TO authenticated
USING (
  public.current_user_has_admin_permission('users.manage')
);


COMMIT;
