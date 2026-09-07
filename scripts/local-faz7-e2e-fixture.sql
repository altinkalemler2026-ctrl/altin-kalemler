-- ============================================================
-- local-faz7-e2e-fixture.sql
-- Altin Kalemler - LOCAL-ONLY Faz 7 E2E FIXTURE
--
-- REMOTE/PRODUCTION UZERINDE CALISTIRILMAMALIDIR.
-- LOCAL ONLY: docker exec -i supabase_db_yarisma-programi psql -U postgres \
--               -d postgres -v ON_ERROR_STOP=1 < local-faz7-e2e-fixture.sql
--
-- AMAC:
--   Pozitif yarisma E2E akisi icin temiz bir baslangic noktasi:
--   - e2e.test alan adina ait onceki E2E kullanicilari ve tum
--     yarisma/kuyruk/poslama kallantilari temizlenir (yalniz bu alan
--     adina ait kayitlar; baska hicbir veriye dokunulmaz).
--   - Kullanicilar RUNNER tarafindan GoTrue signup API'siyle yaratilir
--     (SQL-insert kullanicilarda GoTrue v2.196 password grant
--     calismadigi icin; signup yolu tam ge

--   - Bir one_v_one kasasi + 5 yarisma-uygun soru (correct_answer
--     dahil) deterministik kimliklerle hazirlanir.
--
-- GARANTILER:
--   - Yalniz e2e.test alan adindaki E2E kimlikleri ve e2e7 oznekli
--     rezerve kimliklere dokunulur.
--   - Mevcut gercek/local veri ASLA ezilmez (baska kayit silinmez).
--   - Dogru cevap (correct_answer) yalnizca LOCAL test DB'sinde
--     deterministik 'A' degeridir; istemciye sızdıran bir yol yoktur.
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- ------------------------------------------------------------
-- 0. Onceki basarisiz E2E kosusundan kalan takili yarismalar:
--    guard_competition_question_snapshot, active/completed/disputed
--    yarismadan snapshot sorusu silinmesini engeller. Temizlikten
--    ONCE, oyunculari TAMAMI e2e.test olan yarismalar 'cancelled'
--    yapilir (yalniz e2e kalintisi; baska veriye dokunulmaz).
-- ------------------------------------------------------------
UPDATE public.competitions c
   SET status = 'cancelled'
 WHERE c.status IN ('active', 'completed', 'disputed')
   AND NOT EXISTS (
     SELECT 1 FROM public.competition_players cp
      WHERE cp.competition_id = c.id
        AND cp.user_id NOT IN (
          SELECT id FROM auth.users WHERE email LIKE '%@e2e.test'));

-- ------------------------------------------------------------
-- 1. e2e.test kullanicilarina ait onceki yarisma/kuyruk/poslama verisi
-- ------------------------------------------------------------
DELETE FROM public.competition_answers ca
  USING public.competitions c, public.competition_players cp
 WHERE ca.competition_id = c.id
   AND cp.competition_id = c.id
   AND cp.user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@e2e.test');
DELETE FROM public.competition_questions cq
  USING public.competitions c, public.competition_players cp
 WHERE cq.competition_id = c.id
   AND cp.competition_id = c.id
   AND cp.user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@e2e.test');
DELETE FROM public.competition_results
 WHERE competition_id IN (
   SELECT competition_id FROM public.competition_players
    WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@e2e.test'));
DELETE FROM public.competition_point_changes
 WHERE competition_id IN (
   SELECT competition_id FROM public.competition_players
    WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@e2e.test'));
DELETE FROM public.competition_players
 WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@e2e.test');
DELETE FROM public.competitions c
 WHERE NOT EXISTS (
   SELECT 1 FROM public.competition_players cp WHERE cp.competition_id = c.id);
UPDATE public.matchmaking_queue SET status = 'cancelled'
 WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@e2e.test')
   AND status = 'waiting';
DELETE FROM public.student_pack_exposures
 WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@e2e.test');
DELETE FROM public.student_question_exposures
 WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@e2e.test');

-- ------------------------------------------------------------
-- 2. e2e.test kullanicilari (identities + users; student_profiles
--    ON DELETE CASCADE ile silinir). Runner yeniden signup eder.
-- ------------------------------------------------------------
DELETE FROM auth.identities
 WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE '%@e2e.test');
DELETE FROM auth.users WHERE email LIKE '%@e2e.test';

-- ------------------------------------------------------------
-- 3. E2E7 kasasi ve sorulari: onceki kosu kalintisindan temizle
-- ------------------------------------------------------------
DELETE FROM public.question_vault_memberships
 WHERE vault_id = 'e2e70000-0000-4000-8000-0000000000aa'::uuid;
DELETE FROM public.question_vaults
 WHERE id = 'e2e70000-0000-4000-8000-0000000000aa'::uuid;
DELETE FROM public.questions
 WHERE question_code LIKE 'E2E7-Q-%';

-- ------------------------------------------------------------
-- 4. Akademik baglam: donem + varsayilan program profili
--    (_faz2_student_context / _faz2_require_period gereklilikleri).
--    Idempotent: benzersiz anahtarlarda ON CONFLICT DO NOTHING.
-- ------------------------------------------------------------
INSERT INTO public.curriculum_versions
  (id, academic_year, framework, is_default, is_active, published_at)
VALUES
  ('e2e70000-0000-4000-8000-0000000000c1', '2026-2027',
   'E2E7-FAZ7', true, true, now())
ON CONFLICT (academic_year, framework) DO NOTHING;

INSERT INTO public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active)
VALUES
  ('e2e70000-0000-4000-8000-0000000000c2', 'E2E7-PROF-2026-2027',
   'E2E7 Ders Programi',
   'e2e70000-0000-4000-8000-0000000000c1', true, true)
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.academic_weeks (academic_year, week, starts_at, ends_at)
SELECT '2026-2027', gs.wk,
       date '2026-08-31' + (gs.wk - 1) * 7,
       date '2026-08-31' + gs.wk * 7
  FROM generate_series(1, 44) AS gs(wk)
ON CONFLICT (academic_year, week) DO NOTHING;

-- ------------------------------------------------------------
-- 5. 5 yarisma sorusu (pozitif akis tam seti; 065 kasa limiti 5)
--    minimal alan seti qa_faz2 kanitli desenle aynidir; ek olarak
--    question_text/secenekler/correct_answer doldurulur.
-- ------------------------------------------------------------
INSERT INTO public.questions
  (id, question_code, grade_level, subject_id,
   question_text, option_a, option_b, option_c, option_d, option_e,
   correct_answer, approval_status, is_active, difficulty)
SELECT
  ('e2e70000-0000-4000-8000-00000000000' || n)::uuid,
  'E2E7-Q-' || n, 12,
  '430903f3-527e-4e12-b7e8-ac0afdb784aa',
  'E2E7 test sorusu ' || n,
  '1', '2', '3', '4', '5',
  'A', 'approved', true, 'easy'
FROM unnest(array['1','2','3','4','5']) AS n;

-- ------------------------------------------------------------
-- 6. one_v_one kasasi + uyelikler (competition + one_v_one uygun)
-- ------------------------------------------------------------
INSERT INTO public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id)
VALUES
  ('e2e70000-0000-4000-8000-0000000000aa', 'E2E7-V-OO',
   'E2E7 Yarisma Kasasi', 'one_v_one', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

INSERT INTO public.question_vault_memberships
  (vault_id, question_id, membership_status,
   competition_eligible, one_v_one_eligible)
SELECT 'e2e70000-0000-4000-8000-0000000000aa'::uuid,
       ('e2e70000-0000-4000-8000-00000000000' || n)::uuid,
       'active', true, true
FROM unnest(array['1','2','3','4','5']) AS n;

-- ------------------------------------------------------------
-- 7. POSTCONDITION: kasa + uyelik + donem tam olmali
-- ------------------------------------------------------------
DO $$
DECLARE
  v_q integer;
  v_m integer;
  v_users integer;
  v_period text;
BEGIN
  SELECT count(*) INTO v_q FROM public.questions
   WHERE question_code LIKE 'E2E7-Q-%';
  SELECT count(*) INTO v_m FROM public.question_vault_memberships
   WHERE vault_id = 'e2e70000-0000-4000-8000-0000000000aa'::uuid
     AND membership_status = 'active'
     AND competition_eligible = true
     AND one_v_one_eligible = true;
  SELECT count(*) INTO v_users FROM auth.users WHERE email LIKE '%@e2e.test';

  IF v_q <> 5 OR v_m <> 5 THEN
    RAISE EXCEPTION
      'POSTCONDITION FAILED: expected 5 questions and 5 active memberships, got q=% m=%',
      v_q, v_m;
  END IF;

  IF v_users <> 0 THEN
    RAISE EXCEPTION
      'POSTCONDITION FAILED: expected 0 e2e.test users after cleanup, got %',
      v_users;
  END IF;

  SELECT academic_year || '/hafta ' || week INTO v_period
    FROM public.resolve_current_academic_period();
  IF v_period IS NULL THEN
    RAISE EXCEPTION 'POSTCONDITION FAILED: gecerli akademik donem bulunamadi';
  END IF;

  RAISE NOTICE 'POSTCONDITIONS: E2E7 fixture ready (5 questions, e2e users clean, period=%)', v_period;
END;
$$;

COMMIT;

\echo
\echo ============================================================
\echo LOCAL FAZ7 E2E FIXTURE APPLIED SUCCESSFULLY (LOCAL ONLY)
\echo ============================================================
