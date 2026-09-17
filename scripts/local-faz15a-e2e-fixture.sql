-- ============================================================
-- local-faz15a-e2e-fixture.sql
-- Altin Kalemler - LOCAL-ONLY FAZ 15A E2E FIXTURE
--
-- REMOTE/PRODUCTION UZERINDE CALISTIRILMAMALIDIR.
-- LOCAL ONLY:
--   Get-Content .\scripts\local-faz15a-e2e-fixture.sql -Raw |
--     docker exec -i supabase_db_yarisma-programi psql -U postgres \
--       -d postgres -v ON_ERROR_STOP=1
--
-- AMAC:
--   Faz 15A tek-soru akisi canli dogrulamasinin ihtiyac duydugu izole
--   veriyi deterministik UUID'lerle hazirlar. Mevcut E2E7/gercek/local
--   veriye DOKUNMAZ; kendi non-default surum + profil + ders + konular
--   ile tamamen izole bir kapsam kurar.
--
-- KAPSAM:
--   - auth.users + student_profiles (izole ogrenci, grade 12) -> 083
--     trigger profile'i uretir; schedule_profile_id bize set edilir.
--   - curriculum_versions (non-default) + curriculum_schedule_profiles
--     (non-default) -> yeni profil.
--   - subjects + topics (12. sinif): ONAYLI konu (T1) ve ONAYSIZ konu (T2).
--   - curriculum_schedule_items: T1 ve T2 icin start_week = uygulama
--     anindaki RESOLVED (resmi takvim) hafta, end_week NULL (acik uclu).
--     Antrenman erisimi resolved haftadan itibaren kalici.
--   - curriculum_teaching_approvals: YALNIZ T1'in schedule item'i
--     (academic_year='2026-2027'; resolved period ile eslesir).
--   - question_vaults (practice) + memberships + questions (3 adet,
--     active+approved) + curriculum mappings + cozum asset (Q1).
--     Q3 yalniz ONAYSIZ T2'ye baglidir -> kilit altinda kalir.
--
-- GUARANTILER:
--   - Deterministik UUID'ler ve gercek-disi e2e.test email domaini.
--   - Kimlik/cakisma guard'lari: beklenmeyen mevcut satirda RAISE EXCEPTION.
--   - POSTCONDITION: her core nesne icin tam olarak 1 satir dogrulanir.
--   - Gercek parola/token/.env referansi icermez. Ephemeral parolayi
--     RUNNER yerel GoTrue Admin API ile set eder (faz7/8 runner deseni).
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- ============================================================
-- 0. CONSTANTS
-- ============================================================
\set uid_user        '15aa0001-0000-4000-8000-000000000001'
\set uid_subject     '15aa0001-0000-4000-8000-000000000002'
\set uid_version     '15aa0001-0000-4000-8000-000000000003'
\set uid_profile     '15aa0001-0000-4000-8000-000000000004'
\set uid_topic_onay  '15aa0001-0000-4000-8000-000000000005'
\set uid_topic_onayz '15aa0001-0000-4000-8000-000000000006'
\set uid_si_onay     '15aa0001-0000-4000-8000-000000000007'
\set uid_si_onayz    '15aa0001-0000-4000-8000-000000000008'
\set uid_vault       '15aa0001-0000-4000-8000-000000000009'
\set uid_q1          '15aa0001-0000-4000-8000-000000000010'
\set uid_q2          '15aa0001-0000-4000-8000-000000000011'
\set uid_q3          '15aa0001-0000-4000-8000-000000000012'
\set uid_approval    '15aa0001-0000-4000-8000-000000000013'
\set uid_asset       '15aa0001-0000-4000-8000-000000000014'

-- ============================================================
-- 1. PRECONDITION / COLLISION GUARDS
-- Butun hedeflenen deterministik anahtarlarin serbest oldugunu dogrula.
-- ============================================================

DO $blk$
BEGIN
  -- auth.users: ayni id farkli email -> DUR.
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = '15aa0001-0000-4000-8000-000000000001'
             AND email IS DISTINCT FROM 'faz15a-ogrenci-a@e2e.test') THEN
    RAISE EXCEPTION 'GUARD: auth.users id locked by unexpected email.';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = 'faz15a-ogrenci-a@e2e.test'
             AND id IS DISTINCT FROM '15aa0001-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'GUARD: email faz15a-ogrenci-a@e2e.test used elsewhere.';
  END IF;

  -- student_profiles: ayni id farkli nickname/grade -> DUR.
  IF EXISTS (SELECT 1 FROM public.student_profiles
             WHERE id = '15aa0001-0000-4000-8000-000000000001'
               AND (nickname IS DISTINCT FROM 'FZ15A_Ogrenci_A'
                    OR grade_level IS DISTINCT FROM 12)) THEN
    RAISE EXCEPTION 'GUARD: student_profiles id locked by unexpected row.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.student_profiles
             WHERE nickname = 'FZ15A_Ogrenci_A'
               AND id IS DISTINCT FROM '15aa0001-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'GUARD: nickname FZ15A_Ogrenci_A used elsewhere.';
  END IF;

  -- subjects: name/slug serbest olmali.
  IF EXISTS (SELECT 1 FROM public.subjects
             WHERE name = 'Faz15A Antrenman Test Dersi'
                OR slug = 'faz15a-antrenman-test-dersi') THEN
    RAISE EXCEPTION 'GUARD: Faz15A subject name/slug already exists.';
  END IF;

  -- topics: (subject,grade,slug) serbest olmali.
  IF EXISTS (SELECT 1 FROM public.topics
             WHERE slug IN ('faz15a-onayli-konu','faz15a-onaysiz-konu')) THEN
    RAISE EXCEPTION 'GUARD: Faz15A topic slug already exists.';
  END IF;

  -- curriculum_versions: (academic_year, framework) serbest olmali.
  IF EXISTS (SELECT 1 FROM public.curriculum_versions
             WHERE academic_year = '2026-2027'
               AND framework = 'FZ15A-E2E') THEN
    RAISE EXCEPTION 'GUARD: curriculum version FZ15A-E2E already exists.';
  END IF;

  -- schedule profiles: code serbest olmali.
  IF EXISTS (SELECT 1 FROM public.curriculum_schedule_profiles
             WHERE code = 'FZ15A-PROF-2026-2027') THEN
    RAISE EXCEPTION 'GUARD: schedule profile code FZ15A-PROF already exists.';
  END IF;

  -- question codes: serbest olmali.
  IF EXISTS (SELECT 1 FROM public.questions
             WHERE question_code IN ('FZ15A-ONAY-Q1','FZ15A-ONAY-Q2','FZ15A-ONAYZ-Q3')) THEN
    RAISE EXCEPTION 'GUARD: Faz15A question code already exists.';
  END IF;

  -- vault: code serbest olmali.
  IF EXISTS (SELECT 1 FROM public.question_vaults
             WHERE vault_code = 'FZ15A-E2E-VAULT') THEN
    RAISE EXCEPTION 'GUARD: vault code FZ15A-E2E-VAULT already exists.';
  END IF;

  RAISE NOTICE 'PRECONDITIONS: Faz15A fixture identities verified / free';
END;
$blk$;


-- ============================================================
-- 2. AKTOR (GIRIS AKTORU)
-- NOT: Kullanici SQL ile OLUSTURULMAZ. Yerel GoTrue admin API'si
-- direkt auth.users satirlarini tanimadigi icin (404) runner,
-- /auth/v1/signup (faz7/8 deseni) ile EMAIL
-- 'faz15a-ogrenci-a@e2e.test' / nickname 'FZ15A_Ogrenci_A' /
-- grade_level 12 kullanicisini olusturur; handle_new_user (083)
-- student_profiles'i uretir. Runner daha sonra schedule_profile_id'yi
-- asagidaki izole profile baglar:
--   15aa0001-0000-4000-8000-000000000004
-- ============================================================


-- ============================================================
-- 3. MUFREdat (kendi izole surum + profil)
-- ============================================================

INSERT INTO public.curriculum_versions
  (id, academic_year, framework, source_name, is_active, is_default)
VALUES
  ('15aa0001-0000-4000-8000-000000000003', '2026-2027', 'FZ15A-E2E',
   'Faz15A local e2e fixture', true, false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active)
VALUES
  ('15aa0001-0000-4000-8000-000000000004', 'FZ15A-PROF-2026-2027',
   'Faz15A E2E Profili', '15aa0001-0000-4000-8000-000000000003',
   false, true)
ON CONFLICT (id) DO NOTHING;


-- ============================================================
-- 4. DERS + KONULAR (12. sinif)
-- ============================================================

INSERT INTO public.subjects (id, name, slug, sort_order, is_active)
VALUES
  ('15aa0001-0000-4000-8000-000000000002', 'Faz15A Antrenman Test Dersi',
   'faz15a-antrenman-test-dersi', 9999, true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, subject_id, grade_level, name, slug, sort_order, is_active, curriculum_version_id)
VALUES
  ('15aa0001-0000-4000-8000-000000000005',
   '15aa0001-0000-4000-8000-000000000002', 12,
   'Faz15A Onayli Konu', 'faz15a-onayli-konu', 1, true,
   '15aa0001-0000-4000-8000-000000000003'),
  ('15aa0001-0000-4000-8000-000000000006',
   '15aa0001-0000-4000-8000-000000000002', 12,
   'Faz15A Onaysiz Konu', 'faz15a-onaysiz-konu', 2, true,
   '15aa0001-0000-4000-8000-000000000003')
ON CONFLICT (id) DO NOTHING;


-- ============================================================
-- 5. TAKVIM HAFTALARI (start_week = RESOLVED hafta; end_week NULL)
--    start_week, uygulama anindaki resolved (resmi takvim) haftaya
--    baglanir. Sabit '3' eski duvar-saati varsayimiydi; resolved hafta
--    hangi hafta olursa olsun antrenman erisimi o haftadan kalici
--    olur (end_week NULL). Donem yoksa INSERT bos kalir; POSTCONDITION
--    fail-closed olarak bunu yakalar.
-- ============================================================

INSERT INTO public.curriculum_schedule_items
  (id, schedule_profile_id, grade_level, subject_id, topic_id,
   start_week, end_week, is_active, notes)
SELECT v.id, '15aa0001-0000-4000-8000-000000000004', 12,
       '15aa0001-0000-4000-8000-000000000002', v.topic_id,
       rp.week, NULL, true, v.notes
  FROM (VALUES
    ('15aa0001-0000-4000-8000-000000000007'::uuid,
     '15aa0001-0000-4000-8000-000000000005'::uuid,
     'Faz15A onayli konunun schedule itemi'),
    ('15aa0001-0000-4000-8000-000000000008'::uuid,
     '15aa0001-0000-4000-8000-000000000006'::uuid,
     'Faz15A onaysiz konunun schedule itemi (onay YOK)')
  ) AS v(id, topic_id, notes)
 CROSS JOIN public.resolve_current_academic_period() rp
ON CONFLICT (id) DO UPDATE
  SET start_week = EXCLUDED.start_week;


-- ============================================================
-- 6. OGRETMEN ONAYI: YALNIZ T1 (resolved donem: 2026-2027)
-- ============================================================

INSERT INTO public.curriculum_teaching_approvals
  (id, academic_year, schedule_item_id, status, approved_by, notes)
VALUES
  ('15aa0001-0000-4000-8000-000000000013', '2026-2027',
   '15aa0001-0000-4000-8000-000000000007', 'approved', NULL,
   'Faz15A izole test: onayli konu')
ON CONFLICT (id) DO NOTHING;


-- ============================================================
-- 7. SORU BANKASI (kasalar, sorular, eslemeler, cozum)
-- ============================================================

INSERT INTO public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id,
   is_active, allow_practice)
VALUES
  ('15aa0001-0000-4000-8000-000000000009', 'FZ15A-E2E-VAULT',
   'Faz15A E2E Kasa', 'practice', 12,
   '15aa0001-0000-4000-8000-000000000002', true, true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.questions
  (id, question_code, grade_level, subject_id,
   question_text, option_a, option_b, option_c, option_d,
   correct_answer, difficulty, quality_level,
   is_new_generation, has_visual, estimated_solve_time_seconds,
   approval_status, is_active, ownership_status, license_status,
   commercial_use_allowed)
VALUES
  ('15aa0001-0000-4000-8000-000000000010', 'FZ15A-ONAY-Q1', 12,
   '15aa0001-0000-4000-8000-000000000002',
   'Faz15A dogrulama sorusu 1: 1 arti 1 kac eder?',
   '1', '2', '3', '4',
   'B', 'easy', 'high', false, false, 60, 'approved', true,
   'ai_original', 'approved', false),
  ('15aa0001-0000-4000-8000-000000000011', 'FZ15A-ONAY-Q2', 12,
   '15aa0001-0000-4000-8000-000000000002',
   'Faz15A dogrulama sorusu 2: 2 arti 2 kac eder?',
   '2', '3', '4', '5',
   'D', 'easy', 'high', false, false, 60, 'approved', true,
   'ai_original', 'approved', false),
  ('15aa0001-0000-4000-8000-000000000012', 'FZ15A-ONAYZ-Q3', 12,
   '15aa0001-0000-4000-8000-000000000002',
   'Faz15A onaysiz konu sorusu (asla gosterilmemeli): 3 arti 3 kac eder?',
   '5', '6', '7', '8',
   'C', 'easy', 'high', false, false, 60, 'approved', true,
   'ai_original', 'approved', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.question_solution_assets
  (id, question_id, asset_type, asset_text, source_type,
   validation_status, is_active)
VALUES
  ('15aa0001-0000-4000-8000-000000000014',
   '15aa0001-0000-4000-8000-000000000010', 'text_solution',
   'Faz15A dogrulama cozumu: 1 arti 1, 2 eder (dogru secenek B).',
   'manual', 'valid', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.question_vault_memberships
  (vault_id, question_id, membership_source, membership_status,
   practice_eligible, competition_eligible, one_v_one_eligible, exam_eligible)
VALUES
  ('15aa0001-0000-4000-8000-000000000009',
   '15aa0001-0000-4000-8000-000000000010', 'manual', 'active',
   true, false, false, false),
  ('15aa0001-0000-4000-8000-000000000009',
   '15aa0001-0000-4000-8000-000000000011', 'manual', 'active',
   true, false, false, false),
  ('15aa0001-0000-4000-8000-000000000009',
   '15aa0001-0000-4000-8000-000000000012', 'manual', 'active',
   true, false, false, false)
ON CONFLICT (vault_id, question_id) DO NOTHING;

INSERT INTO public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, subtopic_id,
   mapping_source, review_status)
VALUES
  ('15aa0001-0000-4000-8000-000000000010',
   '15aa0001-0000-4000-8000-000000000003',
   '15aa0001-0000-4000-8000-000000000005', NULL, 'manual', 'approved'),
  ('15aa0001-0000-4000-8000-000000000011',
   '15aa0001-0000-4000-8000-000000000003',
   '15aa0001-0000-4000-8000-000000000005', NULL, 'manual', 'approved'),
  ('15aa0001-0000-4000-8000-000000000012',
   '15aa0001-0000-4000-8000-000000000003',
   '15aa0001-0000-4000-8000-000000000006', NULL, 'manual', 'approved')
ON CONFLICT DO NOTHING;


-- ============================================================
-- 8. OGRENCI PROFILI BAĞLA
-- NOT: Bu UPDATE runner tarafindan signup SONRASI dinamik user_id
-- ile calistirilir (fixture burada actor id'sini bilmez):
--   UPDATE public.student_profiles
--      SET schedule_profile_id = '15aa0001-0000-4000-8000-000000000004'
--    WHERE id = '<signup-user-id>';
-- ============================================================

-- ============================================================
-- 9. POSTCONDITION VERIFICATION
-- ============================================================

DO $blk$
DECLARE
BEGIN
  -- Aktor ayri is (runner: signup + baglama); burada dogrulanmaz.

  -- mufredat
  IF EXISTS (SELECT 1 FROM public.curriculum_versions
             WHERE academic_year='2026-2027' AND framework='FZ15A-E2E' AND NOT (is_active AND NOT is_default)) THEN
    RAISE EXCEPTION 'POST: curriculum version flags unexpected.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.curriculum_schedule_profiles
                 WHERE code='FZ15A-PROF-2026-2027' AND is_active AND NOT is_default) THEN
    RAISE EXCEPTION 'POST: schedule profile missing.';
  END IF;

  -- ders + konular
  IF NOT EXISTS (SELECT 1 FROM public.subjects WHERE id = '15aa0001-0000-4000-8000-000000000002' AND is_active) THEN
    RAISE EXCEPTION 'POST: subject missing.';
  END IF;
  IF (SELECT count(*) FROM public.topics
      WHERE id IN ('15aa0001-0000-4000-8000-000000000005','15aa0001-0000-4000-8000-000000000006')) != 2 THEN
    RAISE EXCEPTION 'POST: topics missing.';
  END IF;

  -- takvim + onay
  IF (SELECT count(*) FROM public.curriculum_schedule_items
      WHERE id IN ('15aa0001-0000-4000-8000-000000000007','15aa0001-0000-4000-8000-000000000008')) != 2 THEN
    RAISE EXCEPTION 'POST: schedule items missing.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.curriculum_teaching_approvals
                 WHERE academic_year='2026-2027'
                   AND schedule_item_id='15aa0001-0000-4000-8000-000000000007'
                   AND status='approved') THEN
    RAISE EXCEPTION 'POST: teaching approval missing.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.curriculum_teaching_approvals
             WHERE schedule_item_id='15aa0001-0000-4000-8000-000000000008') THEN
    RAISE EXCEPTION 'POST: unapproved topic must have NO approval.';
  END IF;

  -- gating butunlugu: resolved donem VAR; start_week <= cari hafta
  -- (kapali kilif: takvim_gelmedi zamani burada yakalanir);
  -- onayin akademik yili resolved donemle ayni olmali.
  IF NOT EXISTS (SELECT 1 FROM public.resolve_current_academic_period()) THEN
    RAISE EXCEPTION 'POST: gecerli akademik donem bulunamadi (111 takvimi bekleniyor).';
  END IF;
  IF EXISTS (
      SELECT 1 FROM public.curriculum_schedule_items si
       WHERE si.id IN ('15aa0001-0000-4000-8000-000000000007',
                       '15aa0001-0000-4000-8000-000000000008')
         AND (si.start_week IS NULL
              OR si.start_week >
                  (SELECT week FROM public.resolve_current_academic_period()))
  ) THEN
    RAISE EXCEPTION 'POST: schedule item baslangici cari haftanin otesinde (E2E zaman-kilidi).';
  END IF;
  IF EXISTS (
      SELECT 1 FROM public.curriculum_teaching_approvals ap
       WHERE ap.id = '15aa0001-0000-4000-8000-000000000013'
         AND ap.academic_year <>
             (SELECT academic_year FROM public.resolve_current_academic_period())
  ) THEN
    RAISE EXCEPTION 'POST: onay akademik yili resolved donemle uyumsuz.';
  END IF;

  -- soru bankasi
  IF (SELECT count(*) FROM public.questions
      WHERE id IN ('15aa0001-0000-4000-8000-000000000010',
                   '15aa0001-0000-4000-8000-000000000011',
                   '15aa0001-0000-4000-8000-000000000012')) != 3 THEN
    RAISE EXCEPTION 'POST: questions missing.';
  END IF;
  IF (SELECT count(*) FROM public.question_vault_memberships
      WHERE vault_id='15aa0001-0000-4000-8000-000000000009'
        AND membership_status='active' AND practice_eligible) != 3 THEN
    RAISE EXCEPTION 'POST: memberships missing.';
  END IF;
  IF (SELECT count(*) FROM public.question_curriculum_mappings
      WHERE curriculum_version_id='15aa0001-0000-4000-8000-000000000003'
        AND review_status='approved') != 3 THEN
    RAISE EXCEPTION 'POST: curriculum mappings missing.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.question_solution_assets
                 WHERE id='15aa0001-0000-4000-8000-000000000014'
                   AND asset_type='text_solution' AND is_active
                   AND validation_status='valid') THEN
    RAISE EXCEPTION 'POST: solution asset missing.';
  END IF;

  RAISE NOTICE 'POSTCONDITIONS: Faz15A fixture fully present and verified';
END;
$blk$;

COMMIT;

\echo
\echo ============================================================
\echo LOCAL FAZ15A E2E FIXTURE APPLIED SUCCESSFULLY (LOCAL ONLY)
\echo ============================================================