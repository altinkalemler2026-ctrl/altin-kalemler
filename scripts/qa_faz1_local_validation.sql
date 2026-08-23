-- ============================================================
-- scripts/qa_faz1_local_validation.sql
-- Altin Kalemler - Migration 059 Faz 1 yerel QA suite (21 test)
--
-- Kapsam:
--   T-01..T-02 : migration gecmisi + ders seed
--   T-03..T-05 : Faz1 tablolari / RLS / kritik indeksler
--   T-06..T-08 : curriculum_schedule_profiles + items kurallari (059)
--   T-09..T-12 : annual_stock_targets kapsam kurallari (060)
--   T-13       : student_weekly_counters 500 siniri (063)
--   T-14..T-19 : competition/one_v_one kasa uye limit triggerlari (065)
--   T-20       : RLS / grant modeli (rol taklidi ile)
--   T-21       : student_profiles.schedule_profile_id guard triggeri (059)
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_faz1_local_validation.sql supabase_db_yarisma-programi:/tmp/
--   docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -f /tmp/qa_faz1_local_validation.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCI FONKSIYON
-- ============================================================

create table public._qa_faz1_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

-- Rol taklidinde calisan kisimlarin da sonuc yazabilmesi icin.
grant select, insert, update, delete
  on public._qa_faz1_results
  to anon, authenticated, service_role;

create function public._qa_expect(p_label text, p_title text, p_expect text, p_sql text)
returns void
language plpgsql
security invoker
as $qa$
declare
  v_state text;
  v_msg   text;
begin
  begin
    execute p_sql;

    if p_expect = '' then
      insert into public._qa_faz1_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_faz1_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_faz1_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_faz1_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

grant execute
  on function public._qa_expect(text, text, text, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR (sabit QA uuid'leri; rollback ile silinecek)
-- matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
-- ============================================================

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111101', 'qa-user-a@test.local'),
  ('11111111-1111-1111-1111-111111111102', 'qa-user-b@test.local');

insert into public.curriculum_versions (id, academic_year, framework, is_default, is_active) values
  ('22222222-2222-2222-2222-222222222201', 'QA-YEAR-2099', 'MEB-TEST-A', true,  true),
  ('22222222-2222-2222-2222-222222222202', 'QA-YEAR-2099', 'MEB-TEST-B', false, true);

insert into public.topics (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('66666666-6666-6666-6666-666666666601',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   12, 'QA Topic', 'qa-topic',
   '22222222-2222-2222-2222-222222222201');

insert into public.curriculum_outcomes (id, curriculum_version_id, grade_level, subject_id, outcome_text) values
  ('66666666-6666-6666-6666-666666666602',
   '22222222-2222-2222-2222-222222222201', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   'QA outcome metni');

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active, metadata)
values
  ('33333333-3333-3333-3333-333333333301', 'QA-SCHED-PROF', 'QA Profil',
   '22222222-2222-2222-2222-222222222201', true, true, '{"qa":true}'::jsonb);

insert into public.questions (id, question_code, grade_level, subject_id, approval_status, is_active)
values
  ('44444444-4444-4444-4444-444444444401', 'QA-Q1', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', false),
  ('44444444-4444-4444-4444-444444444402', 'QA-Q2', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', false),
  ('44444444-4444-4444-4444-444444444403', 'QA-Q3', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', false),
  ('44444444-4444-4444-4444-444444444404', 'QA-Q4', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', false),
  ('44444444-4444-4444-4444-444444444405', 'QA-Q5', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', false),
  ('44444444-4444-4444-4444-444444444406', 'QA-Q6', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', false),
  ('44444444-4444-4444-4444-444444444407', 'QA-Q7', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', false),
  ('44444444-4444-4444-4444-444444444408', 'QA-Q8', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', false);

insert into public.question_vaults (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('55555555-5555-5555-5555-555555555501', 'QA-V-COMP', 'QA Yarisma Kasasi', 'competition', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa'),
  ('55555555-5555-5555-5555-555555555502', 'QA-V-ACAD', 'QA Akademik Kasa', 'academic', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.question_vault_memberships (vault_id, question_id, membership_status) values
  ('55555555-5555-5555-5555-555555555501', '44444444-4444-4444-4444-444444444401', 'active'),
  ('55555555-5555-5555-5555-555555555501', '44444444-4444-4444-4444-444444444402', 'active'),
  ('55555555-5555-5555-5555-555555555501', '44444444-4444-4444-4444-444444444403', 'active'),
  ('55555555-5555-5555-5555-555555555501', '44444444-4444-4444-4444-444444444404', 'active'),
  ('55555555-5555-5555-5555-555555555501', '44444444-4444-4444-4444-444444444405', 'active'),
  ('55555555-5555-5555-5555-555555555502', '44444444-4444-4444-4444-444444444406', 'active'),
  ('55555555-5555-5555-5555-555555555502', '44444444-4444-4444-4444-444444444407', 'active'),
  ('55555555-5555-5555-5555-555555555502', '44444444-4444-4444-4444-444444444408', 'active');

insert into public.student_weekly_counters (user_id, academic_year, week, subject_id, new_questions_used) values
  ('11111111-1111-1111-1111-111111111101', 'QA-YEAR-RLS',   1, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 100),
  ('11111111-1111-1111-1111-111111111102', 'QA-YEAR-RLS',   1, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 200),
  ('11111111-1111-1111-1111-111111111101', 'QA-YEAR-LIMIT', 2, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 0);

insert into public.annual_stock_targets
  (curriculum_version_id, stock_scope, grade_level, subject_id, week, base_target_count, metadata)
values
  ('22222222-2222-2222-2222-222222222201', 'weekly_competition',   12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 45, 300, '{"qa":true}'::jsonb),
  ('22222222-2222-2222-2222-222222222201', 'training',             12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 46, 50,  '{"qa":true}'::jsonb),
  ('22222222-2222-2222-2222-222222222201', 'rewarded_competition', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 47, 10,  '{"qa":true}'::jsonb);


-- ============================================================
-- BOLUM A - MIGRATION GECMISI VE SEED (T-01, T-02)
-- ============================================================

do $blk$
declare
  v_ok boolean;
begin
  -- T-01: Faz 1 gecmisi eksiksiz (001..066, 050 haric).
  -- Not: 067+ Faz 2 surumleri eklenmis olabilir; bu test Faz 1
  -- surumlerinin TAMAMININ uygulandigini dogrular, daha yeni
  -- surumlerin varligini yasaklamaz (yasak, Faz 2 ile yapisal
  -- olarak celisir; 2026-08 F-4/F-5 duzeltme dongusunde giderildi).
  select not exists (
           select 1
             from (
               select lpad(g::text, 3, '0') as version
                 from generate_series(1, 66) g
                where g <> 50
             ) e
            where not exists (
              select 1
                from supabase_migrations.schema_migrations s
               where s.version = e.version
            )
         )
    into v_ok;

  insert into public._qa_faz1_results
  select 'T-01', 'migration gecmisi: Faz 1 surumleri eksiksiz (001..066, 050 haric)',
         case when v_ok then 'PASS' else 'FAIL' end, null;
end;
$blk$;

do $blk$
declare
  v_cnt   bigint;
  v_mat   uuid;
  v_slugs text[];
begin
  select count(*) into v_cnt from public.subjects;
  select id    into v_mat from public.subjects where slug = 'matematik';
  select coalesce(array_agg(slug order by slug), '{}') into v_slugs from public.subjects;

  insert into public._qa_faz1_results
  select 'T-02', 'ders seed: 10 kanonik ders + matematik uuid sabiti',
         case when v_cnt = 10
               and v_mat = '430903f3-527e-4e12-b7e8-ac0afdb784aa'
               and v_slugs = array[
                 'biyoloji','cografya','edebiyat','felsefe','fizik',
                 'geometri','kimya','matematik','tarih','turkce']
              then 'PASS' else 'FAIL' end,
         format('count=%s matematik=%s', v_cnt, v_mat);
end;
$blk$;


-- ============================================================
-- BOLUM B - FAZ1 TABLOLARI / RLS / INDEKSLER (T-03..T-05)
-- ============================================================

do $blk$
declare
  v_tables int;
  v_rls    int;
begin
  with t(name) as (values
    ('curriculum_schedule_profiles'), ('curriculum_schedule_items'),
    ('annual_stock_targets'),         ('student_question_attempts'),
    ('student_question_exposures'),   ('student_pack_exposures'),
    ('student_weekly_counters'),      ('student_dimension_metrics'))
  select count(*) into v_tables
  from t join pg_class c on c.relname = t.name
         join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r';

  with t(name) as (values
    ('curriculum_schedule_profiles'), ('curriculum_schedule_items'),
    ('annual_stock_targets'),         ('student_question_attempts'),
    ('student_question_exposures'),   ('student_pack_exposures'),
    ('student_weekly_counters'),      ('student_dimension_metrics'))
  select count(*) into v_rls
  from t join pg_class c on c.relname = t.name
         join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity;

  insert into public._qa_faz1_results
  select 'T-03', '8 Faz1 tablosu mevcut',
         case when v_tables = 8 then 'PASS' else 'FAIL' end,
         format('bulunan=%s', v_tables);

  insert into public._qa_faz1_results
  select 'T-04', '8 Faz1 tablosunda RLS acik',
         case when v_rls = 8 then 'PASS' else 'FAIL' end,
         format('rls_acik=%s', v_rls);
end;
$blk$;

do $blk$
declare
  v_missing int;
begin
  with expected(idx) as (values
    ('idx_curriculum_versions_one_default_per_year'),
    ('idx_curriculum_schedule_profiles_one_default'),
    ('idx_curriculum_schedule_items_lookup'),
    ('idx_student_profiles_schedule_profile'),
    ('idx_annual_stock_targets_scope'),
    ('idx_annual_stock_targets_lookup'),
    ('idx_student_question_attempts_week_subject'),
    ('idx_student_question_exposures_question'),
    ('idx_student_pack_exposures_vault_unsolved'),
    ('idx_student_dimension_metrics_scope'))
  select count(*) into v_missing
  from expected e left join pg_indexes pi
       on pi.schemaname = 'public' and pi.indexname = e.idx
  where pi.indexname is null;

  insert into public._qa_faz1_results
  select 'T-05', 'kritik Faz1 indeksleri mevcut (10 adet)',
         case when v_missing = 0 then 'PASS' else 'FAIL' end,
         format('eksik=%s', v_missing);
end;
$blk$;


-- ============================================================
-- BOLUM C - SCHEDULE PROFILE / ITEM KURALLARI (T-06..T-08)
-- ============================================================

select public._qa_expect(
  'T-06',
  'ayni egitim yilinda ikinci default versiyon engellenir',
  '23505',
  $sql$update public.curriculum_versions
      set is_default = true
    where id = '22222222-2222-2222-2222-222222222202'$sql$);

select public._qa_expect(
  'T-07a',
  'schedule item: end_week <= start_week reddedilir',
  '23514',
  $sql$insert into public.curriculum_schedule_items
      (schedule_profile_id, grade_level, subject_id, topic_id, start_week, end_week, metadata)
      values ('33333333-3333-3333-3333-333333333301', 12,
              '430903f3-527e-4e12-b7e8-ac0afdb784aa',
              '66666666-6666-6666-6666-666666666601', 5, 5, '{"qa":true}'::jsonb)$sql$);

select public._qa_expect(
  'T-07b',
  'schedule item: start 5 / end 6 kabul edilir',
  '',
  $sql$insert into public.curriculum_schedule_items
      (schedule_profile_id, grade_level, subject_id, topic_id, start_week, end_week, metadata)
      values ('33333333-3333-3333-3333-333333333301', 12,
              '430903f3-527e-4e12-b7e8-ac0afdb784aa',
              '66666666-6666-6666-6666-666666666601', 5, 6, '{"qa":true}'::jsonb)$sql$);

select public._qa_expect(
  'T-08a',
  'schedule item: topic ve outcome bos birakilamaz',
  '23514',
  $sql$insert into public.curriculum_schedule_items
      (schedule_profile_id, grade_level, subject_id, topic_id, subtopic_id, outcome_id, start_week, metadata)
      values ('33333333-3333-3333-3333-333333333301', 12,
              '430903f3-527e-4e12-b7e8-ac0afdb784aa',
              null, null, null, 7, '{"qa":true}'::jsonb)$sql$);

select public._qa_expect(
  'T-08b',
  'schedule item: yalniz outcome hedefiyle kabul',
  '',
  $sql$insert into public.curriculum_schedule_items
      (schedule_profile_id, grade_level, subject_id, topic_id, subtopic_id, outcome_id, start_week, metadata)
      values ('33333333-3333-3333-3333-333333333301', 12,
              '430903f3-527e-4e12-b7e8-ac0afdb784aa',
              null, null, '66666666-6666-6666-6666-666666666602', 8, '{"qa":true}'::jsonb)$sql$);


-- ============================================================
-- BOLUM D - ANNUAL_STOCK_TARGETS KAPSAM KURALLARI (T-09..T-12)
-- ============================================================

select public._qa_expect(
  'T-09',
  'weekly_competition: 299 hedef reddedilir (min 300)',
  '23514',
  $sql$insert into public.annual_stock_targets
      (curriculum_version_id, stock_scope, grade_level, subject_id, week, base_target_count, metadata)
      values ('22222222-2222-2222-2222-222222222201', 'weekly_competition', 12,
              '430903f3-527e-4e12-b7e8-ac0afdb784aa', 48, 299, '{"qa":true}'::jsonb)$sql$);

do $blk$
declare
  v_wc bigint; v_tr bigint; v_rw bigint;
begin
  select count(*) into v_wc from public.annual_stock_targets
   where stock_scope = 'weekly_competition' and base_target_count >= 300 and metadata @> '{"qa":true}';
  select count(*) into v_tr from public.annual_stock_targets
   where stock_scope = 'training' and base_target_count < 300 and metadata @> '{"qa":true}';
  select count(*) into v_rw from public.annual_stock_targets
   where stock_scope = 'rewarded_competition' and base_target_count < 300 and metadata @> '{"qa":true}';

  insert into public._qa_faz1_results
  select 'T-10', 'kapsam ayrimi: weekly>=300, training/rewarded serbest',
         case when v_wc = 1 and v_tr = 1 and v_rw = 1 then 'PASS' else 'FAIL' end,
         format('weekly=%s training=%s rewarded=%s', v_wc, v_tr, v_rw);
end;
$blk$;

select public._qa_expect(
  'T-11',
  'zorluk kirilimi toplami base hedefini asamaz',
  '23514',
  $sql$insert into public.annual_stock_targets
      (curriculum_version_id, stock_scope, grade_level, subject_id, week,
       base_target_count, easy_target_count, medium_target_count, hard_target_count, metadata)
      values ('22222222-2222-2222-2222-222222222201', 'weekly_competition', 12,
              '430903f3-527e-4e12-b7e8-ac0afdb784aa', 51,
              300, 200, 200, 0, '{"qa":true}'::jsonb)$sql$);

select public._qa_expect(
  'T-12',
  'ayni stok hucresi (versiyon+scope+sinif+ders+hafta) tekrar edemez',
  '23505',
  $sql$insert into public.annual_stock_targets
      (curriculum_version_id, stock_scope, grade_level, subject_id, week, base_target_count, metadata)
      values ('22222222-2222-2222-2222-222222222201', 'weekly_competition', 12,
              '430903f3-527e-4e12-b7e8-ac0afdb784aa', 45, 320, '{"qa":true}'::jsonb)$sql$);


-- ============================================================
-- BOLUM E - STUDENT_WEEKLY_COUNTERS SINIRI (T-13)
-- ============================================================

select public._qa_expect(
  'T-13a',
  'haftalik yeni soru sayaci: 500 kabul edilir',
  '',
  $sql$update public.student_weekly_counters
      set new_questions_used = 500
    where user_id = '11111111-1111-1111-1111-111111111101'
      and academic_year = 'QA-YEAR-LIMIT'$sql$);

select public._qa_expect(
  'T-13b',
  'haftalik yeni soru sayaci: 501 reddedilir (max 500)',
  '23514',
  $sql$update public.student_weekly_counters
      set new_questions_used = 501
    where user_id = '11111111-1111-1111-1111-111111111101'
      and academic_year = 'QA-YEAR-LIMIT'$sql$);

select public._qa_expect(
  'T-13c',
  'hafta araligi disi (week=53) reddedilir',
  '23514',
  $sql$insert into public.student_weekly_counters
      (user_id, academic_year, week, subject_id, new_questions_used)
      values ('11111111-1111-1111-1111-111111111101', 'QA-YEAR-LIMIT', 53,
              '430903f3-527e-4e12-b7e8-ac0afdb784aa', 1)$sql$);


-- ============================================================
-- BOLUM F - KASA UYE LIMIT TRIGGERLARI (T-14..T-19)
-- ============================================================

select public._qa_expect(
  'T-14',
  'dolu competition kasasina 6. aktif uye eklenemez',
  'P0001',
  $sql$insert into public.question_vault_memberships
      (vault_id, question_id, membership_status)
      values ('55555555-5555-5555-5555-555555555501',
              '44444444-4444-4444-4444-444444444406', 'active')$sql$);

select public._qa_expect(
  'T-15',
  'academic kasada limit yok (5 aktif uye daha kabul, toplam 8)',
  '',
  $sql$insert into public.question_vault_memberships
      (vault_id, question_id, membership_status)
      values
        ('55555555-5555-5555-5555-555555555502', '44444444-4444-4444-4444-444444444401', 'active'),
        ('55555555-5555-5555-5555-555555555502', '44444444-4444-4444-4444-444444444402', 'active'),
        ('55555555-5555-5555-5555-555555555502', '44444444-4444-4444-4444-444444444403', 'active'),
        ('55555555-5555-5555-5555-555555555502', '44444444-4444-4444-4444-444444444404', 'active'),
        ('55555555-5555-5555-5555-555555555502', '44444444-4444-4444-4444-444444444405', 'active')$sql$);

select public._qa_expect(
  'T-16',
  'dolu competition kasasina inactive uye eklenebilir (sayim yalniz aktif)',
  '',
  $sql$insert into public.question_vault_memberships
      (vault_id, question_id, membership_status, removed_at)
      values ('55555555-5555-5555-5555-555555555501',
              '44444444-4444-4444-4444-444444444408', 'inactive', now())$sql$);

select public._qa_expect(
  'T-17',
  'dolu kasada inactive -> active donusumu engellenir',
  'P0001',
  $sql$update public.question_vault_memberships
      set membership_status = 'active'
    where vault_id = '55555555-5555-5555-5555-555555555501'
      and question_id = '44444444-4444-4444-4444-444444444408'$sql$);

select public._qa_expect(
  'T-18',
  '5+ aktif uyeli academic kasa competition tipina cevrilemez',
  'P0001',
  $sql$update public.question_vaults
      set vault_type = 'competition'
    where id = '55555555-5555-5555-5555-555555555502'$sql$);

select public._qa_expect(
  'T-19',
  'aktif uye dolu baska competition kasasina tasinamaz',
  'P0001',
  $sql$update public.question_vault_memberships
      set vault_id = '55555555-5555-5555-5555-555555555501'
    where vault_id = '55555555-5555-5555-5555-555555555502'
      and question_id = '44444444-4444-4444-4444-444444444406'$sql$);


-- ============================================================
-- BOLUM G - RLS / GRANT MODELI (T-20, rol taklidi)
-- ============================================================

do $blk$
declare
  v_count bigint;
  v_state text;
begin
  -- ---- anon ----
  execute 'set local role anon';

  begin
    execute 'select count(*) from public.student_weekly_counters';
    insert into public._qa_faz1_results
    values ('T-20a', 'anon: student_weekly_counters secim erisimi', 'FAIL', 'erisim engellenmedi');
  exception when insufficient_privilege then
    insert into public._qa_faz1_results
    values ('T-20a', 'anon: student_weekly_counters secim erisimi', 'PASS', '42501 ile engellendi');
  end;

  begin
    execute 'select count(*) from public.annual_stock_targets';
    insert into public._qa_faz1_results
    values ('T-20b', 'anon: annual_stock_targets secim erisimi', 'FAIL', 'erisim engellenmedi');
  exception when insufficient_privilege then
    insert into public._qa_faz1_results
    values ('T-20b', 'anon: annual_stock_targets secim erisimi', 'PASS', '42501 ile engellendi');
  end;

  execute 'reset role';

  -- ---- authenticated (jwt claims ile u_a) ----
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111101","role":"authenticated"}', true);

  execute 'select count(*) from public.student_weekly_counters
           where academic_year = ''QA-YEAR-RLS''' into v_count;

  insert into public._qa_faz1_results
  select 'T-20c', 'authenticated yalniz kendi haftalik sayacini gorur',
         case when v_count = 1 then 'PASS' else 'FAIL' end,
         'gorunen_satir=' || v_count || ' (beklenen 1; diger ogrencinin satiri gizli)';

  perform public._qa_expect(
    'T-20d',
    'authenticated: student_weekly_counters INSERT yetkisi yok',
    '42501',
    $sql$insert into public.student_weekly_counters
        (user_id, academic_year, week, subject_id, new_questions_used)
        values ('11111111-1111-1111-1111-111111111101', 'QA-DENIED', 9,
                '430903f3-527e-4e12-b7e8-ac0afdb784aa', 1)$sql$);

  perform public._qa_expect(
    'T-20e',
    'authenticated: student_question_attempts DELETE yetkisi yok',
    '42501',
    $sql$delete from public.student_question_attempts$sql$);

  execute 'reset role';

  -- ---- service_role ----
  execute 'set local role service_role';

  begin
    insert into public.student_weekly_counters
      (user_id, academic_year, week, subject_id, new_questions_used)
      values ('11111111-1111-1111-1111-111111111102', 'QA-YEAR-SR', 3,
              '430903f3-527e-4e12-b7e8-ac0afdb784aa', 5);

    execute 'select count(*) from public.student_weekly_counters' into v_count;

    insert into public._qa_faz1_results
    select 'T-20f', 'service_role yazar ve RLS bypass ile tum satirlari gorur',
           case when v_count = 4 then 'PASS' else 'FAIL' end,
           'gorunen_satir=' || v_count || ' (beklenen 4)';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    insert into public._qa_faz1_results
    values ('T-20f', 'service_role yazar ve RLS bypass ile tum satirlari gorur', 'FAIL',
            'sqlstate=' || v_state);
  end;

  execute 'reset role';
end;
$blk$;


-- ============================================================
-- BOLUM H - SCHEDULE_PROFILE GUARD TRIGGERI (T-21)
-- ============================================================

do $blk$
begin
  -- u_a: NULL atama serbest (MEB varsayilan plani)
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111101","role":"authenticated"}', true);

  perform public._qa_expect(
    'T-21a',
    'ogrenci profili NULL schedule_profile_id ile olusturulabilir',
    '',
    $sql$insert into public.student_profiles (id, grade_level, nickname)
        values ('11111111-1111-1111-1111-111111111101', 12, 'QA-NICK-A')$sql$);

  -- u_b: NULL OLMAYAN deger INSERT'te guard tarafindan reddedilir
  perform set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111102","role":"authenticated"}', true);

  perform public._qa_expect(
    'T-21b',
    'guard: INSERT ile non-null schedule_profile_id engellenir',
    '42501',
    $sql$insert into public.student_profiles (id, grade_level, nickname, schedule_profile_id)
        values ('11111111-1111-1111-1111-111111111102', 12, 'QA-NICK-B',
                '33333333-3333-3333-3333-333333333301')$sql$);

  perform public._qa_expect(
    'T-21c',
    'u_b profili NULL schedule_profile_id ile olusturulabilir',
    '',
    $sql$insert into public.student_profiles (id, grade_level, nickname)
        values ('11111111-1111-1111-1111-111111111102', 12, 'QA-NICK-B')$sql$);

  -- claims u_a'ya geri alinir; T-21d kendi satirini guncellemeyi dener
  -- (RLS update_own satiri gorur -> guard trigger devreye girer).
  perform set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111101","role":"authenticated"}', true);

  perform public._qa_expect(
    'T-21d',
    'guard: UPDATE ile schedule_profile_id degisikligi engellenir',
    '42501',
    $sql$update public.student_profiles
        set schedule_profile_id = '33333333-3333-3333-3333-333333333301'
      where id = '11111111-1111-1111-1111-111111111101'$sql$);

  execute 'reset role';

  -- guvenilir rol: sunucu tarafi atama serbest
  perform public._qa_expect(
    'T-21e',
    'postgres (guvenilir rol) schedule_profile_id atayabilir',
    '',
    $sql$update public.student_profiles
        set schedule_profile_id = '33333333-3333-3333-3333-333333333301'
      where id = '11111111-1111-1111-1111-111111111101'$sql$);
end;
$blk$;


-- ============================================================
-- TEMIZLIK (suite ici; ayrica tum suite tek transaction'da
-- oldugu icin final ROLLBACK her seyi geri alir)
-- ============================================================

delete from public.question_vault_memberships m
using public.question_vaults v
where m.vault_id = v.id and v.vault_code like 'QA-V-%';

delete from public.question_vaults where vault_code like 'QA-V-%';

delete from public.student_question_attempts a
using public.questions q
where a.question_id = q.id and q.question_code like 'QA-Q%';

delete from public.student_question_exposures e
using public.questions q
where e.question_id = q.id and q.question_code like 'QA-Q%';

delete from public.student_pack_exposures p
using public.question_vaults v
where p.vault_id = v.id and v.vault_code like 'QA-V-%';

delete from public.student_dimension_metrics
where user_id in ('11111111-1111-1111-1111-111111111101',
                  '11111111-1111-1111-1111-111111111102');

delete from public.student_weekly_counters where academic_year like 'QA-%';

delete from public.annual_stock_targets where metadata @> '{"qa":true}';

delete from public.curriculum_schedule_items i
using public.curriculum_schedule_profiles sp
where i.schedule_profile_id = sp.id and sp.code = 'QA-SCHED-PROF';

delete from public.curriculum_schedule_profiles where code = 'QA-SCHED-PROF';

delete from public.student_profiles where nickname like 'QA-NICK-%';

delete from public.curriculum_outcomes where outcome_text like 'QA %';

delete from public.topics where slug = 'qa-topic';

delete from public.curriculum_versions where academic_year like 'QA-%';

delete from public.questions where question_code like 'QA-Q%';

delete from auth.users where email like '%@test.local';


-- ============================================================
-- TEMIZLIK DOGRULAMASI
-- ============================================================

select
  (select count(*) from auth.users
    where email like '%@test.local')                                          as users_kalan,
  (select count(*) from public.questions
    where question_code like 'QA-Q%')                                         as questions_kalan,
  (select count(*) from public.question_vaults
    where vault_code like 'QA-V-%')                                           as vaults_kalan,
  (select count(*) from public.question_vault_memberships m
    join public.question_vaults v on v.id = m.vault_id
    where v.vault_code like 'QA-V-%')                                         as memberships_kalan,
  (select count(*) from public.student_weekly_counters
    where academic_year like 'QA-%')                                          as counters_kalan,
  (select count(*) from public.annual_stock_targets
    where metadata @> '{"qa":true}')                                          as targets_kalan,
  (select count(*) from public.curriculum_schedule_items i
    join public.curriculum_schedule_profiles sp on sp.id = i.schedule_profile_id
    where sp.code = 'QA-SCHED-PROF')                                          as sched_items_kalan,
  (select count(*) from public.curriculum_schedule_profiles
    where code = 'QA-SCHED-PROF')                                             as sched_profiles_kalan,
  (select count(*) from public.student_profiles
    where nickname like 'QA-NICK-%')                                          as profiles_kalan,
  (select count(*) from public.curriculum_versions
    where academic_year like 'QA-%')                                          as versions_kalan,
  (select count(*) from public.topics where slug = 'qa-topic')                as topics_kalan,
  (select count(*) from public.curriculum_outcomes
    where outcome_text like 'QA %')                                           as outcomes_kalan;


-- ============================================================
-- SONUC RAPORU
-- ============================================================

select
  label                                                        as test_id,
  case when bool_and(result = 'PASS') then 'PASS' else 'FAIL' end as durum,
  count(*) filter (where result = 'FAIL')                      as alt_fail,
  string_agg(
    case when result = 'PASS' then title
         else title || ' >>> ' || coalesce(detail, '') end,
    ' | ' order by title)                                      as detay
from public._qa_faz1_results
group by label
order by label;

with g as (
  select label, bool_and(result = 'PASS') as ok
  from public._qa_faz1_results
  group by label
)
select
  count(*)                        as toplam_test,
  count(*) filter (where ok)      as gecen,
  count(*) filter (where not ok)  as kalan
from g;


drop function public._qa_expect(text, text, text, text);
drop table public._qa_faz1_results;

rollback;
