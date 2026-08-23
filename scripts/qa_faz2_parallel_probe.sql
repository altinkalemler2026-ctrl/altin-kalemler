-- ============================================================
-- scripts/qa_faz2_parallel_probe.sql
-- Altin Kalemler - Faz 2 paralel tuketim probe'u
--
-- IKI MOD:
--
-- 1) FARKLI-KULLANICI: iki bagimsiz psql oturumu (TAG=a / TAG=b)
--    farkli oyuncularla (C/D) ayni havuzdan eszamanli yeni soru
--    ceker. Her cagri ayri transaction'dadir (autocommit), boylece
--    haftalik sayac guncellemeleri gercek oturum paralelliginde
--    kosar. Beklenen deterministik sonuc:
--
--      used_c + used_d == 560   (havuz tamamen tuketilir)
--      used_c <= 500 ve used_d <= 500 (kisi basi sinir asilmaz)
--
-- 2) AYNI-KULLANICI (Faz 2 review F-2): TAG=a ve TAG=b AYNI
--    oyuncuyla (C) eszamanli secim yapar. FOR UPDATE sayaç kilidi
--    ve delta-tabanli consume altinda:
--
--      used_c <= 500 (paylasilan tavan ASLA asilmaz)
--      used_c == training exposure(C) (atomikligin kalici kaniti)
--
-- Kullanim (LOCAL ONLY):
--   docker cp scripts/qa_faz2_parallel_probe.sql supabase_db_yarisma-programi:/tmp/
--   # 1) fikstur kurulumu
--   docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -v MODE=setup -f /tmp/qa_faz2_parallel_probe.sql
--   # 2a) iki eszamanli isci (farkli kullanici), TAG=a ve TAG=b
--   # 2b) iki eszamanli isci (AYNI kullanici): -v MODE=same -v TAG=a|b
--   docker exec ... -v MODE=same -v TAG=a -f ...
--   docker exec ... -v MODE=same -v TAG=b -f ...
--   # 3) dogrulama (herhangi FAIL -> exit code != 0)
--   docker exec ... -v MODE=verify -f ...
--   # 4) temizlik
--   docker exec ... -v MODE=cleanup -f ...
-- ============================================================

\set ON_ERROR_STOP on

\if :{?MODE}
\else
\warn MODE tanimli degil: setup|work|same|verify|cleanup bekleniyor
\q
\endif

select :'MODE' = 'setup'   as m_setup,
       :'MODE' = 'work'    as m_work,
       :'MODE' = 'same'    as m_same,
       :'MODE' = 'cleanup' as m_cleanup,
       :'MODE' = 'verify'  as m_verify
\gset

-- ------------------------------------------------------------
-- MODE=setup : idempotent fikstur kurulumu
-- ------------------------------------------------------------
\if :m_setup

begin;

insert into auth.users (id, email) values
  ('99999999-9999-9999-9999-999999999903', 'qa2-par-c@test.local'),
  ('99999999-9999-9999-9999-999999999904', 'qa2-par-d@test.local')
on conflict (id) do nothing;

insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('88888888-8888-8888-8888-888888888802', 'QA-P-2099', 'MEB-QA2', true)
on conflict (academic_year, framework) do nothing;

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('77777777-7777-7777-7777-777777777702', 'QA2P-SCHED', 'QA2 Paralel Profil',
   '88888888-8888-8888-8888-888888888802', true, true)
on conflict (code) do nothing;

-- Idempotansiyon: onceki kismi kurulumda default kalmissa duzelt.
update public.curriculum_schedule_profiles
   set is_default = true, is_active = true
 where code = 'QA2P-SCHED';

insert into public.student_profiles (id, grade_level, nickname) values
  ('99999999-9999-9999-9999-999999999903', 12, 'QA2-NICK-C'),
  ('99999999-9999-9999-9999-999999999904', 12, 'QA2-NICK-D')
on conflict (id) do nothing;

insert into public.academic_weeks (academic_year, week, starts_at, ends_at)
select 'QA-P-2099', w, current_date - 30, current_date + 30
  from generate_series(1, 10) w
on conflict do nothing;

insert into public.topics (id, subject_id, grade_level, name, slug,
                           curriculum_version_id) values
  ('66666666-6666-6666-6666-000000000003',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 12,
   'QA2 Paralel Konu', 'qa2-paralel',
   '88888888-8888-8888-8888-888888888802')
on conflict (curriculum_version_id, subject_id, grade_level, slug) do nothing;

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, start_week, end_week)
select '77777777-7777-7777-7777-777777777702', 12,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa',
       '66666666-6666-6666-6666-000000000003', 0, null
 where not exists (
   select 1 from public.curriculum_schedule_items
    where schedule_profile_id = '77777777-7777-7777-7777-777777777702'
      and topic_id = '66666666-6666-6666-6666-000000000003'
 );

insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('22222222-2222-2222-2222-00000000000e', 'QA2-V-PARALLEL',
   'QA2 Paralel Kasasi', 'practice', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa')
on conflict (vault_code) do nothing;

insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type)
select ('33333333-3333-3333-3333-200000000' || lpad(g::text, 3, '0'))::uuid,
       'Q2-P-' || lpad(g::text, 3, '0'), 12,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
       'easy', 'learning', 'coktan_secmeli'
  from generate_series(1, 560) g
on conflict (id) do nothing;

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, practice_eligible)
select '22222222-2222-2222-2222-00000000000e',
       ('33333333-3333-3333-3333-200000000' || lpad(g::text, 3, '0'))::uuid,
       'active', true
  from generate_series(1, 560) g
on conflict do nothing;

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, review_status)
select ('33333333-3333-3333-3333-200000000' || lpad(g::text, 3, '0'))::uuid,
       '88888888-8888-8888-8888-888888888802',
       '66666666-6666-6666-6666-000000000003', 'approved'
  from generate_series(1, 560) g
on conflict do nothing;

commit;

\echo SETUP_OK

\endif


-- ------------------------------------------------------------
-- MODE=work : -v TAG=a|b ile calisir; 12 tur x 50 soru ceker.
-- Her cagri autocommit oldugu icin ayri transaction'dadir;
-- request.jwt.claims oturum duzeyinde (is_local=false) ayarlanir.
-- auth.uid() yalnizca bu ayardan okur; rol degisimi gerekmez.
-- ------------------------------------------------------------

\if :m_work

\if :{?TAG}
\else
\set TAG none
\endif

select :'TAG' = 'a' as tag_a,
       :'TAG' = 'b' as tag_b
\gset

\if :tag_a
select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999903","role":"authenticated"}',
  false) as claims_set;
\endif

\if :tag_b
select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999904","role":"authenticated"}',
  false) as claims_set;
\endif

select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_01;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_02;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_03;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_04;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_05;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_06;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_07;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_08;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_09;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_10;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_11;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_12;

select set_config('request.jwt.claims', '', false) as claims_cleared;

\if :tag_a
select 'FINAL_USED=' || c.new_questions_used as sonuc
  from public.student_weekly_counters c
 where c.user_id = '99999999-9999-9999-9999-999999999903'
   and c.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';
\endif

\if :tag_b
select 'FINAL_USED=' || c.new_questions_used as sonuc
  from public.student_weekly_counters c
 where c.user_id = '99999999-9999-9999-9999-999999999904'
   and c.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';
\endif

\endif


-- ------------------------------------------------------------
-- MODE=same : F-2 ayni-kullanici paralel secim. TAG=a ve TAG=b
-- AYNI oyuncuyla (C) calisir; iki oturum ayni haftalik sayac
-- satiri icin yarisir. 12 tur x 50 soru -> toplam talep 1200,
-- paylasilan tavan 500'dir.
-- ------------------------------------------------------------

\if :m_same

\if :{?TAG}
\else
\set TAG none
\endif

select :'TAG' = 'a' as stag_a,
       :'TAG' = 'b' as stag_b
\gset

\if :stag_a
select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999903","role":"authenticated"}',
  false) as claims_set;
\endif

-- DIPNOT: tag_b de BILINCI OLARAK ayni kullaniciyi (C) kullanir;
-- bu modun amaci tam olarak ayni sayacin paralel yarisi testidir.
\if :stag_b
select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999903","role":"authenticated"}',
  false) as claims_set;
\endif

select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_01;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_02;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_03;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_04;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_05;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_06;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_07;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_08;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_09;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_10;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_11;
select public.select_training_questions(
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 50) as tur_12;

select set_config('request.jwt.claims', '', false) as claims_cleared;

select 'FINAL_USED=' || c.new_questions_used as sonuc
  from public.student_weekly_counters c
 where c.user_id = '99999999-9999-9999-9999-999999999903'
   and c.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

\endif


-- ------------------------------------------------------------
-- MODE=verify : atomiklik/tavan dogrulamasi (work VEYA same sonrasi)
--   - kisi basi kullanilan <= 500
--   - sayac == o kisinin training exposure satir sayisi
--     (show-time atomikliginin kalici kaniti)
--   Herhangi bir satir FAIL ise veya hic sayac yoksa DO blogu
--   exception firlatir -> ON_ERROR_STOP ile psql exit code != 0.
-- ------------------------------------------------------------

\if :{?MODE}
\else
\set MODOFF 1
\endif

\if :m_verify

select c.user_id,
       c.new_questions_used                                        as kullanilan,
       (select count(*)
          from public.student_question_exposures e
         where e.user_id = c.user_id
           and e.attempt_context = 'training')                     as exposure,
       case when c.new_questions_used <= 500
             and c.new_questions_used =
                 (select count(*)
                    from public.student_question_exposures e
                   where e.user_id = c.user_id
                     and e.attempt_context = 'training')
           then 'PASS' else 'FAIL' end                             as durum
  from public.student_weekly_counters c
 where c.academic_year = 'QA-P-2099'
 order by c.user_id;

do $$
declare
  v_rows integer;
  v_bad  integer;
begin
  select count(*),
         count(*) filter (
           where c.new_questions_used > 500
              or c.new_questions_used <>
                 (select count(*)
                    from public.student_question_exposures e
                   where e.user_id = c.user_id
                     and e.attempt_context = 'training'))
    into v_rows, v_bad
    from public.student_weekly_counters c
   where c.academic_year = 'QA-P-2099';

  if v_rows = 0 then
    raise exception 'VERIFY_FAIL: QA-P-2099 icin sayac satiri yok'
      using errcode = 'P0001';
  end if;

  if v_bad > 0 then
    raise exception 'VERIFY_FAIL: % sayac satiri tutarsiz', v_bad
      using errcode = 'P0001';
  end if;
end $$;

\echo VERIFY_PASS

\endif


-- ------------------------------------------------------------
-- MODE=cleanup : tum probe artefaktlarini siler (committed)
-- ------------------------------------------------------------

\if :m_cleanup

begin;

delete from public.student_question_attempts
 where user_id in ('99999999-9999-9999-9999-999999999903',
                   '99999999-9999-9999-9999-999999999904');

delete from public.student_dimension_metrics
 where user_id in ('99999999-9999-9999-9999-999999999903',
                   '99999999-9999-9999-9999-999999999904');

delete from public.student_question_exposures
 where user_id in ('99999999-9999-9999-9999-999999999903',
                   '99999999-9999-9999-9999-999999999904');

delete from public.student_pack_exposures
 where user_id in ('99999999-9999-9999-9999-999999999903',
                   '99999999-9999-9999-9999-999999999904');

delete from public.student_weekly_counters
 where user_id in ('99999999-9999-9999-9999-999999999903',
                   '99999999-9999-9999-9999-999999999904');

delete from public.question_curriculum_mappings
 where question_id::text like '33333333-3333-3333-3333-200000000%';

delete from public.question_vault_memberships
 where vault_id = '22222222-2222-2222-2222-00000000000e';

delete from public.question_vaults
 where vault_code = 'QA2-V-PARALLEL';

delete from public.questions
 where question_code like 'Q2-P-%';

delete from public.topics where slug = 'qa2-paralel';

delete from public.curriculum_schedule_profiles where code = 'QA2P-SCHED';

delete from public.academic_weeks where academic_year = 'QA-P-2099';

delete from public.curriculum_versions where academic_year = 'QA-P-2099';

delete from public.student_profiles
 where nickname in ('QA2-NICK-C', 'QA2-NICK-D');

delete from auth.users
 where email in ('qa2-par-c@test.local', 'qa2-par-d@test.local');

commit;

\echo CLEANUP_OK

\endif
