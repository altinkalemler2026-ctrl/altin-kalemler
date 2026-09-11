-- ============================================================
-- local-faz11-e2e-fixture.sql
-- LOCAL-ONLY Faz 11 E2E fixture (disposable stack: faz11iso).
--
-- Idempotent: tekrar uygulanabilir. Yalnizca sabit QA uuid'leri
-- kullanir; gerçek/kalici veriye dokunmaz. Runner (run-faz11-e2e.ps1)
-- signup SONRASI uygular (student_profiles trigger tarafindan).
-- ============================================================

-- ============================================================
-- Idempotent rerun temizligi: E2E11 kullanicilarinin onceki kosu
-- artiklari silinir (yalnizca disposable stack'te calisir).
-- ============================================================
delete from public.student_question_attempts
 where user_id in (
   select id from public.student_profiles where nickname like 'E2E11_%'
);
delete from public.student_question_exposures
 where user_id in (
   select id from public.student_profiles where nickname like 'E2E11_%'
);
delete from public.student_dimension_metrics
 where user_id in (
   select id from public.student_profiles where nickname like 'E2E11_%'
);
delete from public.student_weekly_counters
 where user_id in (
   select id from public.student_profiles where nickname like 'E2E11_%'
);

-- Ders: mevcut matematik seed'i.
-- Akademik donem + mufredat baglami (7. sinif ogrenciler).
insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('77777777-7777-7777-7777-777777770001', 'QA11E-Y', 'MEB-QA11E', true)
on conflict (id) do nothing;

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('77777777-7777-7777-7777-777777770002', 'QA11E-SCHED', 'QA11E Profil',
   '77777777-7777-7777-7777-777777770001', true, true)
on conflict (id) do nothing;

insert into public.academic_weeks (academic_year, week, starts_at, ends_at)
select 'QA11E-Y', 5, current_date - 3, current_date + 4
where not exists (
  select 1 from public.academic_weeks
   where academic_year = 'QA11E-Y' and week = 5
)
on conflict do nothing;

insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('77777777-7777-7777-7777-777777770010',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   7, 'QA11E Islenmis Konu', 'qa11e-konu',
   '77777777-7777-7777-7777-777777770001')
on conflict (id) do nothing;

insert into public.curriculum_outcomes
  (id, curriculum_version_id, subject_id, grade_level, topic_id,
   outcome_code, outcome_text) values
  ('77777777-7777-7777-7777-777777770020',
   '77777777-7777-7777-7777-777777770001',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 7,
   '77777777-7777-7777-7777-777777770010',
   'QA11E-O1', 'QA11E Kazanim O1')
on conflict (id) do nothing;

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, outcome_id,
   start_week, end_week)
select '77777777-7777-7777-7777-777777770002', 7,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa',
       '77777777-7777-7777-7777-777777770010',
       '77777777-7777-7777-7777-777777770020', 1, null
where not exists (
  select 1 from public.curriculum_schedule_items
   where schedule_profile_id = '77777777-7777-7777-7777-777777770002'
     and outcome_id = '77777777-7777-7777-7777-777777770020'
);

-- Sorular (deterministik siralama: question_id ASC).
--   Q1: cozum aciklamasi ONAYLI (valid text_solution)
--   Q2: soru metninde XSS sentinel; cozumu var
--   Q3: cozumu YOK (hazirlaniyor yolu)
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type,
   question_text, option_a, option_b, option_c, option_d, option_e,
   correct_answer, estimated_solve_time_seconds)
values
  ('77777777-7777-7777-7777-777777771001', 'QA11E-Q1', 7,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli',
   '2^10 sayisi ile 3/4 kesri karsilastirildiginda hangisi buyuktur?',
   '3/4', '2^10', 'Esittir', 'Karsilastirilamaz', 'Yoktur',
   'B', 45),
  ('77777777-7777-7777-7777-777777771002', 'QA11E-Q2', 7,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli',
   '<img src=x onerror=window.__xss=1> 1/2 kesri asagidakilerden hangisidir?',
   '0,2', '0,5', '0,7', '1/1', '2/1',
   'C', 45),
  ('77777777-7777-7777-7777-777777771003', 'QA11E-Q3', 7,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli',
   '5^2 isleminin sonucu kactir?',
   '10', '25', '52', '7', '125',
   'B', 45)
on conflict (id) do nothing;

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, review_status)
select q.id, '77777777-7777-7777-7777-777777770001',
       '77777777-7777-7777-7777-777777770010', 'approved'
  from public.questions q
 where q.question_code like 'QA11E-%'
   and not exists (
     select 1 from public.question_curriculum_mappings m
      where m.question_id = q.id
        and m.curriculum_version_id = '77777777-7777-7777-7777-777777770001'
   );

insert into public.question_outcome_mappings
  (question_id, outcome_id, review_status)
select q.id, '77777777-7777-7777-7777-777777770020', 'approved'
  from public.questions q
 where q.question_code like 'QA11E-%'
   and not exists (
     select 1 from public.question_outcome_mappings m
      where m.question_id = q.id
        and m.outcome_id = '77777777-7777-7777-7777-777777770020'
   );

-- Antrenman kasasi + uyelikler.
insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('77777777-7777-7777-7777-777777774001', 'QA11E-V-PRACTICE',
   'QA11E Antrenman Kasasi', 'practice', 7,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa')
on conflict (id) do nothing;

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, practice_eligible)
select '77777777-7777-7777-7777-777777774001', q.id, 'active', true
  from public.questions q
 where q.question_code like 'QA11E-%'
   and not exists (
     select 1 from public.question_vault_memberships m
      where m.vault_id = '77777777-7777-7777-7777-777777774001'
        and m.question_id = q.id
   );

-- Cozum aciklamalari: Q1 + Q2 ONAYLI (valid); Q3 yok.
insert into public.question_solution_assets
  (question_id, asset_type, asset_text, source_type, validation_status,
   is_active, created_at)
select q.id, 'text_solution',
       case
         when q.question_code = 'QA11E-Q1' then
           '2^10 sayisi 1024 eder; 3/4 kesri 1den kucuktur. Oran: 3/4, us: 2^5.'
         else '1/2 kesri 0,5 degerine esittir: 1/2 = 0,5.'
       end,
       'manual', 'valid', true, now()
  from public.questions q
 where q.question_code in ('QA11E-Q1', 'QA11E-Q2')
   and not exists (
     select 1 from public.question_solution_assets a
      where a.question_id = q.id
        and a.asset_type = 'text_solution'
        and a.validation_status = 'valid'
   );

-- B karsi-tarafinin AYRI verisi (izolasyon sentinel'i).
-- B'nin kendi konu metrigi; A'nin /ilerleme sayfasinda GORUNMEMELI.
insert into public.student_dimension_metrics
  (user_id, metric_scope, scope_key, total_attempts, correct_count,
   wrong_count, blank_count, pass_timeout_count, repeat_total,
   repeat_correct, total_time_ms, last_attempted_at)
select u.id, 'topic', '77777777-7777-7777-7777-777777770010',
       9, 9, 0, 0, 0, 0, 0, 81000, now()
  from public.student_profiles u
 where u.nickname = 'E2E11_Ogrenci_B'
   and not exists (
     select 1 from public.student_dimension_metrics m
      where m.user_id = u.id
        and m.metric_scope = 'topic'
        and m.scope_key = '77777777-7777-7777-7777-777777770010'
   );
