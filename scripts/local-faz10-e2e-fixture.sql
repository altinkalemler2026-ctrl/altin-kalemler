-- ============================================================
-- local-faz10-e2e-fixture.sql
-- Altin Kalemler - LOCAL-ONLY Faz 10 Profil/Avatar E2E FIXTURE
--
-- REMOTE/PRODUCTION UZERINDE CALISTIRILMAMALIDIR.
-- LOCAL ONLY (disposable stack: faz10iso).
--
-- AMAC: Profil + lig akisi icin deterministik baslangic:
--   - e2e10 oznekli lig/profil verileri temizlenir.
--   - Aktif sezon + ogrencilerin pp/lig uyeligi/entry'si hazirlanir.
--   - Kullanicilar runner tarafindan GoTrue signup ile yaratilir;
--     083 trigger'i student_profiles'u uretir. Bu dosya signup
--     SONRASI calistirilir.
--
-- GARANTILER: Yalniz e2e10 oznekli fixture kayitlarina dokunulur;
-- sifre/token yazilmaz; gorev sonunda kalinti birakilmaz.
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1) Onceki kosu kalintisi: e2e10 profil/lig yuzeyleri.
DELETE FROM public.student_league_memberships
 WHERE user_id IN (
   SELECT id FROM auth.users WHERE email LIKE 'e2e10-%@e2e.test');
DELETE FROM public.leaderboard_entries
 WHERE user_id IN (
   SELECT id FROM auth.users WHERE email LIKE 'e2e10-%@e2e.test');
DELETE FROM public.student_league_history
 WHERE user_id IN (
   SELECT id FROM auth.users WHERE email LIKE 'e2e10-%@e2e.test');
DELETE FROM public.student_loadouts
 WHERE user_id IN (
   SELECT id FROM auth.users WHERE email LIKE 'e2e10-%@e2e.test');
DELETE FROM public.student_public_profiles
 WHERE user_id IN (
   SELECT id FROM auth.users WHERE email LIKE 'e2e10-%@e2e.test');
DELETE FROM public.leaderboard_seasons
 WHERE season_code LIKE 'FAZ10E2E-%';

-- 2) Aktif sezon.
INSERT INTO public.leaderboard_seasons
  (season_code, name, season_type, starts_at, ends_at, is_active)
VALUES
  ('FAZ10E2E-S1', 'E2E Faz 10 Sezon 1', 'monthly',
   now() - interval '1 day', now() + interval '7 days', true);

-- 3) Public profiller (A/B gorunur; C gizli sentinel).
INSERT INTO public.student_public_profiles
  (user_id, nickname, grade_level, avatar_key, is_visible)
SELECT u.id, v.nickname, v.grade_level, v.avatar_key, v.is_visible
  FROM (VALUES
    ('e2e10-ogrenci-a@e2e.test', 'E2E10_Ogrenci_A', 7, 'E2E10_AVATAR_A', true),
    ('e2e10-ogrenci-b@e2e.test', 'E2E10_Ogrenci_B', 7, 'E2E10_AVATAR_B', true),
    ('e2e10-ogrenci-c@e2e.test', 'E2E10_GIZLI_SENTINEL', 7, null, false),
    ('e2e10-sinif6@e2e.test', 'E2E10_SINIF6_SENTINEL', 6, null, true),
    ('e2e10-sinif8@e2e.test', 'E2E10_SINIF8_SENTINEL', 8, null, true)
  ) AS v(email, nickname, grade_level, avatar_key, is_visible)
  JOIN auth.users u ON u.email = v.email;

-- 4) Lig uyelikleri (Bronz; attach trigger entry uretir).
INSERT INTO public.student_league_memberships
  (user_id, league_id, membership_scope,
   points_at_entry, current_points, is_current, entered_at)
SELECT u.id,
       (SELECT id FROM public.leagues WHERE league_code = 'bronze'),
       'general',
       v.pts, v.pts, true,
       coalesce(v.ent, now())
  FROM (VALUES
    ('e2e10-ogrenci-a@e2e.test', 64::integer, now() - interval '2 hour'),
    ('e2e10-ogrenci-b@e2e.test', 88, now() - interval '1 hour'),
    ('e2e10-ogrenci-c@e2e.test', 50, null)
  ) AS v(email, pts, ent)
  JOIN auth.users u ON u.email = v.email;

COMMIT;

-- Dogrulama (runner ciktisinda gorunur; sifre/token yazilmaz).
SELECT 'season=' || count(*) FROM public.leaderboard_seasons
 WHERE season_code = 'FAZ10E2E-S1';
SELECT 'public_profiles=' || count(*)
  FROM public.student_public_profiles pp
  JOIN auth.users u ON u.id = pp.user_id
 WHERE u.email LIKE 'e2e10-%@e2e.test';
SELECT 'memberships=' || count(*)
  FROM public.student_league_memberships m
  JOIN auth.users u ON u.id = m.user_id
 WHERE u.email LIKE 'e2e10-%@e2e.test' AND m.is_current;
