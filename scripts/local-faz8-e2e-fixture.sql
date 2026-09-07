-- ============================================================
-- local-faz8-e2e-fixture.sql
-- Altin Kalemler - LOCAL-ONLY Faz 8 Lig E2E FIXTURE
--
-- REMOTE/PRODUCTION UZERINDE CALISTIRILMAMALIDIR.
-- LOCAL ONLY (disposable stack):
--   docker exec -i supabase_db_faz8iso psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 < local-faz8-e2e-fixture.sql
--
-- AMAC:
--   Lig E2E akisi icin deterministik baslangic:
--   - e2e8 oznekli lig verileri temizlenir (yalniz bu gorevin
--     fixture'lari; baska hicbir veriye dokunulmaz).
--   - Aktif sezon + 5 ogrencinin lig uyeligi/entry'si hazirlanir:
--     A (7.sinif, gorunur, 64p), B (7.sinif, gorunur, 88p),
--     C (7.sinif, GIZLI, 50p), D (6.sinif, gorunur, 30p),
--     E (8.sinif, gorunur, 30p).
--   - Kullanicilar runner tarafindan GoTrue signup ile yaratilir;
--     083 trigger'i student_profiles'u uretir. Bu dosya signup
--     SONRASI calistirilir.
--
-- GARANTILER:
--   - Yalniz e2e8 oznekli fixture kayitlarina dokunulur.
--   - Okul/sube verisi URETILMEZ; sifre/token yazilmaz.
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1) Onceki kosu kalintisi: e2e8 lig verileri (kullanicilar runner
--    tarafindan email uzerinden silinir; burada lig yuzeyleri).
DELETE FROM public.student_league_memberships
 WHERE user_id IN (
   SELECT id FROM auth.users WHERE email LIKE 'e2e8-%@e2e.test');
DELETE FROM public.leaderboard_entries
 WHERE user_id IN (
   SELECT id FROM auth.users WHERE email LIKE 'e2e8-%@e2e.test');
DELETE FROM public.student_league_history
 WHERE user_id IN (
   SELECT id FROM auth.users WHERE email LIKE 'e2e8-%@e2e.test');
DELETE FROM public.student_public_profiles
 WHERE user_id IN (
   SELECT id FROM auth.users WHERE email LIKE 'e2e8-%@e2e.test');
DELETE FROM public.leaderboard_seasons
 WHERE season_code LIKE 'FAZ8E2E-%';

-- 2) Aktif sezon (S1) + upcoming sezon (S2: kapanis testi icin yok;
--    E2E kapsami yalniz okuma/izolasyon).
INSERT INTO public.leaderboard_seasons
  (season_code, name, season_type, starts_at, ends_at, is_active)
VALUES
  ('FAZ8E2E-S1', 'E2E Faz 8 Sezon 1', 'monthly',
   now() - interval '1 day', now() + interval '7 days', true);

-- 3) Public profiller (nickname/avatar/gorunurluk).
INSERT INTO public.student_public_profiles
  (user_id, nickname, grade_level, avatar_key, is_visible)
SELECT u.id, v.nickname, v.grade_level, v.avatar_key, v.is_visible
  FROM (VALUES
    ('e2e8-ogrenci-a@e2e.test', 'E2E8_Ogrenci_A', 7, 'avatar_a8', true),
    ('e2e8-ogrenci-b@e2e.test', 'E2E8_Ogrenci_B', 7, 'avatar_b8', true),
    ('e2e8-ogrenci-c@e2e.test', 'E2E8_GIZLI_SENTINEL', 7, 'avatar_c8', false),
    ('e2e8-ogrenci-d@e2e.test', 'E2E8_SINIF6_SENTINEL', 6, 'avatar_d8', true),
    ('e2e8-ogrenci-e@e2e.test', 'E2E8_SINIF8_SENTINEL', 8, 'avatar_e8', true)
  ) AS v(email, nickname, grade_level, avatar_key, is_visible)
  JOIN auth.users u ON u.email = v.email;

-- 4) Lig uyelikleri (Bronz; attach trigger aktif sezonu baglar,
--    entry upsert trigger entry'yi uretir).
INSERT INTO public.student_league_memberships
  (user_id, league_id, membership_scope,
   points_at_entry, current_points, is_current, entered_at)
SELECT u.id,
       (SELECT id FROM public.leagues WHERE league_code = 'bronze'),
       'general',
       v.pts, v.pts, true,
       coalesce(v.ent, now())
  FROM (VALUES
    ('e2e8-ogrenci-a@e2e.test', 64::integer, null::timestamptz),
    ('e2e8-ogrenci-b@e2e.test', 88, null),
    ('e2e8-ogrenci-c@e2e.test', 50, null),
    ('e2e8-ogrenci-d@e2e.test', 30, null),
    ('e2e8-ogrenci-e@e2e.test', 30, null)
  ) AS v(email, pts, ent)
  JOIN auth.users u ON u.email = v.email;

COMMIT;

-- Dogrulama (runner ciktisinda gorunur; sifre/token yazilmaz).
SELECT 'season=' || count(*) FROM public.leaderboard_seasons
 WHERE season_code = 'FAZ8E2E-S1';
SELECT 'memberships=' || count(*)
  FROM public.student_league_memberships m
  JOIN auth.users u ON u.id = m.user_id
 WHERE u.email LIKE 'e2e8-%@e2e.test' AND m.is_current;
SELECT 'entries=' || count(*)
  FROM public.leaderboard_entries e
  JOIN auth.users u ON u.id = e.user_id
 WHERE u.email LIKE 'e2e8-%@e2e.test';
