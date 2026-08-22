-- 001_auth_foundation.sql
-- Temel auth ve student_profiles altyapısı (ilk kurulum migration'ı)

-- updated_at trigger fonksiyonu
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- student_profiles tablosu
CREATE TABLE IF NOT EXISTS public.student_profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  grade_level smallint NOT NULL CHECK (grade_level BETWEEN 1 AND 12),
  nickname text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- RLS aktif
ALTER TABLE public.student_profiles ENABLE ROW LEVEL SECURITY;

-- Kullanıcı sadece kendi profilini okuyabilir
DROP POLICY IF EXISTS select_own ON public.student_profiles;
CREATE POLICY select_own
ON public.student_profiles
FOR SELECT
TO authenticated
USING (auth.uid() = id);

-- Kullanıcı sadece kendi profilini güncelleyebilir
DROP POLICY IF EXISTS update_own ON public.student_profiles;
CREATE POLICY update_own
ON public.student_profiles
FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- Kullanıcı sadece kendi profilini oluşturabilir
DROP POLICY IF EXISTS insert_own ON public.student_profiles;
CREATE POLICY insert_own
ON public.student_profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- updated_at trigger
DROP TRIGGER IF EXISTS trigger_set_updated_at
ON public.student_profiles;

CREATE TRIGGER trigger_set_updated_at
BEFORE UPDATE ON public.student_profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
-- ============================================================
-- YETKILER (GRANT)
--
-- RLS politikalari yetki VERMEZ; yeni CLI davranisinda postgres
-- tarafindan olusturulan tablolar otomatik expose edilmedigi icin
-- yetkiler acikca verilmelidir.
--   - anon          : erisim yok.
--   - authenticated : yalniz kendi satiri (RLS: select_own /
--                     update_own / insert_own).
--   - service_role  : tam yetki (sunucu tarafi akislari).
-- ============================================================

REVOKE ALL ON TABLE public.student_profiles FROM anon, authenticated;

GRANT SELECT, INSERT, UPDATE
ON public.student_profiles
TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.student_profiles
TO service_role;
