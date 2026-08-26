-- ============================================================
-- 083_auth_user_profile_trigger.sql
-- Altin Kalemler - Auth user profile auto-create trigger
--
-- Purpose:
-- When a new auth.users row is created (any source: register,
-- OAuth, admin), automatically create a student_profiles row
-- from user_metadata if valid. This eliminates the dependency
-- on the email confirmation callback for profile creation.
--
-- Security:
-- - SECURITY DEFINER: runs as postgres (table owner)
-- - SET search_path = '': fully qualified references only
-- - REVOKE direct EXECUTE: authenticated cannot call directly
-- - Idempotent: ON CONFLICT DO NOTHING
-- - No PII logged or exposed in errors
--
-- Migration type: FORWARD ONLY
-- ============================================================

BEGIN;

-- ============================================================
-- 1. CREATE trigger function
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_nickname text;
  v_grade    text;
  v_grade_i  integer;
BEGIN
  -- Safe string parse — no cast until validated
  v_nickname := trim(NEW.raw_user_meta_data ->> 'nickname');
  v_grade    := trim(NEW.raw_user_meta_data ->> 'grade_level');

  -- Missing or empty nickname → skip (OAuth/admin user)
  IF v_nickname IS NULL OR length(v_nickname) = 0 THEN
    RETURN NEW;
  END IF;

  -- Safe numeric validation — no integer cast on untrusted input
  IF v_grade IS NULL OR length(v_grade) = 0 THEN
    RETURN NEW;
  END IF;

  -- Only allow exact values 1-12 as text
  IF v_grade NOT IN (
    '1','2','3','4','5','6','7','8','9','10','11','12'
  ) THEN
    RETURN NEW;
  END IF;

  v_grade_i := v_grade::integer;

  INSERT INTO public.student_profiles (id, grade_level, nickname)
  VALUES (NEW.id, v_grade_i, v_nickname)
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$function$;

-- ============================================================
-- 2. CREATE trigger on auth.users (exactly once)
-- ============================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 3. REVOKE direct execution (safety net)
-- ============================================================

REVOKE EXECUTE ON FUNCTION public.handle_new_user()
  FROM PUBLIC, anon, authenticated;

COMMIT;
