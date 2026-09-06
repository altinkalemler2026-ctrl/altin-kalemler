-- ============================================================
-- scripts/qa_faz6_targeted_review_local.sql
-- Altin Kalemler - Migration 098 yerel QA suite
-- (Faz 6: Hedefli Tekrar ve Kazanım Analitiği)
--
-- Kapsam:
--   T-00 : ACL matrisi (EXECUTE yalniz authenticated)
--   T-01 : anon -> get_outcome_review_plan 42501
--   T-02 : anon -> select_targeted_review_questions 42501
--   T-03 : plan band esikleri (insufficient_data/weak/strong) +
--          yetersiz veride success_rate NULL
--   T-04 : izolasyon: B'nin plani yalniz KENDI sinif kazanimlarini
--          icerir; A'nin metrikleri gorunmez
--   T-05 : cooldown: bugun yanlis yapilan soru havuz disi ->
--          tekrar_gerekmiyor (pozitif kapanis)
--   T-06 : dunku yanlis havuzda; bugunku cooldown disi
--   T-07 : determinizm: ayni fixture'da iki secim ozdes
--   T-08 : p_limit sinirlari (0/11 -> 22023)
--   T-09 : kapsam fail-closed (A->B outcome, B->A outcome)
--   T-10 : hata havuzu onceligi + yeni soru doldurma + haftalik
--          kapasite yalniz YENI sorular icin tuketilir
--   T-11 : telafi: correct sonrasi soru havuzdan cikar; plan
--          pending/redeemed/redeem_rate guncellenir
--   T-12 : redeem_rate paydasi < 5 ise NULL
--   T-12 : rate limit esikte P0001 (targeted_review_select)
--
-- Calistirma (LOCAL ONLY, disposable ortam):
--   docker cp scripts/qa_faz6_targeted_review_local.sql <db>:/tmp/
--   docker exec <db> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -A -t -f /tmp/qa_faz6_targeted_review_local.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR
-- ============================================================

create table public._qa_f6_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_f6_results
  to anon, authenticated, service_role;

create function public._qa_f6_expect(
  p_label text, p_title text, p_expect text, p_sql text
)
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
      insert into public._qa_f6_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_f6_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_f6_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_f6_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa_f6_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_f6_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa_f6_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_f6_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR (sabit QA uuid'leri; rollback ile silinecek)
-- matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
--   A : 5. sinif (hedef ogrenci)
--   B : 6. sinif (izolasyon karsi-tarafi)
-- ============================================================

insert into auth.users (id, email) values
  ('98989898-9898-9898-9898-000000000091', 'qa6-user-a@test.local'),
  ('98989898-9898-9898-9898-000000000092', 'qa6-user-b@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('98989898-9898-9898-9898-000000000091', 5, 'QA6-NICK-A'),
  ('98989898-9898-9898-9898-000000000092', 6, 'QA6-NICK-B');

-- Akademik donem + mufredat baglami.
insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('98989898-9898-9898-9898-989898980001', 'QA6-Y', 'MEB-QA6', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('98989898-9898-9898-9898-989898980002', 'QA6-SCHED', 'QA6 Profil',
   '98989898-9898-9898-9898-989898980001', true, true);

insert into public.academic_weeks (academic_year, week, starts_at, ends_at) values
  ('QA6-Y', 5, current_date - 3, current_date + 4);

-- Islenmis konular (5. ve 6. sinif).
insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('98989898-9898-9898-9898-989898980010',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   5, 'QA6 Islenmis Konu 5', 'qa6-konu5',
   '98989898-9898-9898-9898-989898980001'),
  ('98989898-9898-9898-9898-989898980011',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   6, 'QA6 Islenmis Konu 6', 'qa6-konu6',
   '98989898-9898-9898-9898-989898980001');

-- Kazanimlar: O1/O2/O4/O5 (5. sinif, A kapsam) + O3 (6. sinif, B kapsam).
insert into public.curriculum_outcomes
  (id, curriculum_version_id, subject_id, grade_level, topic_id,
   outcome_code, outcome_text) values
  ('98989898-9898-9898-9898-989898980020',
   '98989898-9898-9898-9898-989898980001',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 5,
   '98989898-9898-9898-9898-989898980010',
   'QA6-O1', 'QA6 Kazanim O1 (weak)'),
  ('98989898-9898-9898-9898-989898980021',
   '98989898-9898-9898-9898-989898980001',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 5,
   '98989898-9898-9898-9898-989898980010',
   'QA6-O2', 'QA6 Kazanim O2 (insufficient)'),
  ('98989898-9898-9898-9898-989898980022',
   '98989898-9898-9898-9898-989898980001',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 6,
   '98989898-9898-9898-9898-989898980011',
   'QA6-O3', 'QA6 Kazanim O3 (B-sinifi)'),
  ('98989898-9898-9898-9898-989898980023',
   '98989898-9898-9898-9898-989898980001',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 5,
   '98989898-9898-9898-9898-989898980010',
   'QA6-O4', 'QA6 Kazanim O4 (strong)'),
  ('98989898-9898-9898-9898-989898980024',
   '98989898-9898-9898-9898-989898980001',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 5,
   '98989898-9898-9898-9898-989898980010',
   'QA6-O5', 'QA6 Kazanim O5 (weak, az hata)');

-- Donem kapili islenmis kazanim program satirlari.
insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, outcome_id,
   start_week, end_week) values
  ('98989898-9898-9898-9898-989898980002', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '98989898-9898-9898-9898-989898980010',
   '98989898-9898-9898-9898-989898980020', 1, null),
  ('98989898-9898-9898-9898-989898980002', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '98989898-9898-9898-9898-989898980010',
   '98989898-9898-9898-9898-989898980021', 1, null),
  ('98989898-9898-9898-9898-989898980002', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '98989898-9898-9898-9898-989898980010',
   '98989898-9898-9898-9898-989898980023', 1, null),
  ('98989898-9898-9898-9898-989898980002', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '98989898-9898-9898-9898-989898980010',
   '98989898-9898-9898-9898-989898980024', 1, null),
  ('98989898-9898-9898-9898-989898980002', 6,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '98989898-9898-9898-9898-989898980011',
   '98989898-9898-9898-9898-989898980022', 1, null);

-- Sorular:
--   W1/W2 : dun yanlis (hata havuzu)
--   T1    : BUGUN yanlis (cooldown disi)
--   P1-P3 : 3 gun once yanlis (hata havuzu + redeem paydasi)
--   N1-N4 : hic gorulmemis yeni sorular (doldurma)
--   R1    : O5 icin tek bekleyen hata (redeem paydasi < 5)
--   B1    : 6. sinif TUZAK (A kapsaminda ASLA cikmamali)
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
values
  ('98989898-9898-9898-9898-989898981001', 'QA6-W1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45),
  ('98989898-9898-9898-9898-989898981002', 'QA6-W2', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'B', true, 45),
  ('98989898-9898-9898-9898-989898981003', 'QA6-T1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'C', true, 45),
  ('98989898-9898-9898-9898-989898981005', 'QA6-P1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'coktan_secmeli', 'A', true, 60),
  ('98989898-9898-9898-9898-989898981006', 'QA6-P2', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'coktan_secmeli', 'B', true, 60),
  ('98989898-9898-9898-9898-989898981007', 'QA6-P3', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'coktan_secmeli', 'C', true, 60),
  ('98989898-9898-9898-9898-989898981008', 'QA6-R1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45),
  ('98989898-9898-9898-9898-989898982001', 'QA6-N1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45),
  ('98989898-9898-9898-9898-989898982002', 'QA6-N2', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'B', true, 45),
  ('98989898-9898-9898-9898-989898982003', 'QA6-N3', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'C', true, 45),
  ('98989898-9898-9898-9898-989898982004', 'QA6-N4', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'D', true, 45),
  ('98989898-9898-9898-9898-989898981099', 'QA6-B1', 6,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'D', true, 45);

-- Mufredat eslemeleri (tum sorular; sinif uygun konuya).
insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, review_status)
select q.id, '98989898-9898-9898-9898-989898980001',
       case when q.grade_level = 6
            then '98989898-9898-9898-9898-989898980011'::uuid
            else '98989898-9898-9898-9898-989898980010'::uuid
       end,
       'approved'
  from public.questions q
 where q.question_code like 'QA6-%';

-- Kazanim eslemeleri: 5. sinif sorular -> O1; R1 -> O5; B1 -> O3.
insert into public.question_outcome_mappings
  (question_id, outcome_id, review_status)
select q.id, '98989898-9898-9898-9898-989898980020'::uuid, 'approved'
  from public.questions q
 where q.question_code in
       ('QA6-W1', 'QA6-W2', 'QA6-T1', 'QA6-P1', 'QA6-P2', 'QA6-P3',
        'QA6-N1', 'QA6-N2', 'QA6-N3', 'QA6-N4');

insert into public.question_outcome_mappings
  (question_id, outcome_id, review_status)
select q.id, '98989898-9898-9898-9898-989898980024'::uuid, 'approved'
  from public.questions q
 where q.question_code = 'QA6-R1';

insert into public.question_outcome_mappings
  (question_id, outcome_id, review_status)
select q.id, '98989898-9898-9898-9898-989898980022'::uuid, 'approved'
  from public.questions q
 where q.question_code = 'QA6-B1';

-- Pratik kasasi + uyelikler (antrenman eligible).
insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('98989898-9898-9898-9898-989898984001', 'QA6-V-PRACTICE',
   'QA6 Antrenman Kasasi', 'practice', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, practice_eligible)
select '98989898-9898-9898-9898-989898984001', q.id, 'active', true
  from public.questions q
 where q.question_code like 'QA6-%'
   and q.grade_level = 5;

-- A'nin training exposure'lari (W1/W2/T1/P1-P3/R1).
insert into public.student_question_exposures
  (user_id, question_id, attempt_context)
select '98989898-9898-9898-9898-000000000091', q.id, 'training'
  from public.questions q
 where q.question_code in
       ('QA6-W1', 'QA6-W2', 'QA6-T1', 'QA6-P1', 'QA6-P2', 'QA6-P3', 'QA6-R1');

-- O5 icin tek bekleyen hata (R1): redeem paydasi < 5 senaryosu.
insert into public.student_question_attempts
  (user_id, question_id, subject_id, attempt_context, result,
   attempt_number, time_ms, academic_year, week, answered_at, metadata)
values
  ('98989898-9898-9898-9898-000000000091',
   '98989898-9898-9898-9898-989898981008',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'training', 'wrong',
   1, 20000, 'QA6-Y', 5,
   ((current_timestamp at time zone 'utc')::date - 3)::timestamptz
     + interval '08 hours',
   '{"source":"qa6"}'::jsonb);

-- A'nin metrikleri (band esikleri + yetersiz veri + NULL yuzde).
insert into public.student_dimension_metrics
  (user_id, metric_scope, scope_key, total_attempts, correct_count,
   wrong_count, blank_count, pass_timeout_count, repeat_total,
   repeat_correct, total_time_ms, last_attempted_at) values
  ('98989898-9898-9898-9898-000000000091', 'outcome',
   '98989898-9898-9898-9898-989898980020', 12, 4, 6, 1, 1, 4, 2, 480000,
   now() - interval '2 hours'),
  ('98989898-9898-9898-9898-000000000091', 'outcome',
   '98989898-9898-9898-9898-989898980021', 4, 2, 1, 1, 0, 1, 1, 120000,
   now() - interval '1 day'),
  ('98989898-9898-9898-9898-000000000091', 'outcome',
   '98989898-9898-9898-9898-989898980023', 10, 10, 0, 0, 0, 0, 0, 300000,
   now() - interval '1 day'),
  ('98989898-9898-9898-9898-000000000091', 'outcome',
   '98989898-9898-9898-9898-989898980024', 5, 1, 4, 0, 0, 0, 0, 150000,
   now() - interval '3 days');

-- Soru basina UTC takvim gunu yardimcisi.
create function public._qa_f6_utc_day(p_offset_days integer)
returns date
language sql
immutable
as $qa$
  select ((current_timestamp at time zone 'utc')::date - p_offset_days)
$qa$;


-- ============================================================
-- T-00: ACL MATRISI
-- ============================================================

do $blk$
begin
  perform public._qa_f6_true('T-00a',
    'authenticated: get_outcome_review_plan EXECUTE VAR',
    has_function_privilege('authenticated',
      'public.get_outcome_review_plan(uuid)', 'EXECUTE'));

  perform public._qa_f6_true('T-00b',
    'anon: get_outcome_review_plan EXECUTE YOK',
    not has_function_privilege('anon',
      'public.get_outcome_review_plan(uuid)', 'EXECUTE'));

  perform public._qa_f6_true('T-00c',
    'authenticated: select_targeted_review_questions EXECUTE VAR',
    has_function_privilege('authenticated',
      'public.select_targeted_review_questions(uuid,uuid,integer)', 'EXECUTE'));

  perform public._qa_f6_true('T-00d',
    'anon: select_targeted_review_questions EXECUTE YOK',
    not has_function_privilege('anon',
      'public.select_targeted_review_questions(uuid,uuid,integer)', 'EXECUTE'));

  perform public._qa_f6_true('T-00e',
    'tek overload: get_outcome_review_plan(uuid) baska imza yok',
    (select count(*) from pg_proc
      where proname = 'get_outcome_review_plan'
        and pronamespace = 'public'::regnamespace) = 1);

  perform public._qa_f6_true('T-00f',
    'tek overload: select_targeted_review_questions tek imza',
    (select count(*) from pg_proc
      where proname = 'select_targeted_review_questions'
        and pronamespace = 'public'::regnamespace) = 1);
end;
$blk$;


-- ============================================================
-- T-01/T-02: ANON ERISIMI 42501
-- ============================================================

do $blk$
begin
  perform public._qa_f6_expect('T-01',
    'anon: plan RPC 42501', '42501',
    $sql$select public.get_outcome_review_plan(
      '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid)$sql$);

  perform public._qa_f6_expect('T-02',
    'anon: secim RPC 42501', '42501',
    $sql$select public.select_targeted_review_questions(
      '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
      '98989898-9898-9898-9898-989898980020'::uuid,
      5)$sql$);
end;
$blk$;


-- ============================================================
-- T-03: A'nin PLANI — band esikleri + yetersiz veride NULL yuzde
-- ============================================================

do $blk$
declare
  v_plan jsonb;
  v_row  jsonb;
  v_o1   jsonb;
  v_o2   jsonb;
  v_o4   jsonb;
  v_o5   jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000091","role":"authenticated"}', true);

  v_plan := public.get_outcome_review_plan(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  for v_row in select * from jsonb_array_elements(v_plan) loop
    if v_row ->> 'outcome_id' = '98989898-9898-9898-9898-989898980020' then
      v_o1 := v_row;
    elsif v_row ->> 'outcome_id' = '98989898-9898-9898-9898-989898980021' then
      v_o2 := v_row;
    elsif v_row ->> 'outcome_id' = '98989898-9898-9898-9898-989898980023' then
      v_o4 := v_row;
    elsif v_row ->> 'outcome_id' = '98989898-9898-9898-9898-989898980024' then
      v_o5 := v_row;
    end if;
  end loop;

  perform public._qa_f6_true('T-03a',
    'O1 (4/12): band=weak, success_rate=33.3',
    v_o1 ->> 'band' = 'weak' and v_o1 ->> 'success_rate' = '33.3',
    jsonb_build_object('band', v_o1 ->> 'band',
                       'rate', v_o1 ->> 'success_rate')::text);

  perform public._qa_f6_true('T-03b',
    'O2 (4 deneme): band=insufficient_data, success_rate NULL',
    v_o2 ->> 'band' = 'insufficient_data'
      and (v_o2 ->> 'success_rate') is null,
    jsonb_build_object('band', v_o2 ->> 'band',
                       'rate', v_o2 ->> 'success_rate')::text);

  perform public._qa_f6_true('T-03c',
    'O4 (10/10): band=strong, success_rate=100.0',
    v_o4 ->> 'band' = 'strong' and v_o4 ->> 'success_rate' = '100.0',
    jsonb_build_object('band', v_o4 ->> 'band',
                       'rate', v_o4 ->> 'success_rate')::text);

  perform public._qa_f6_true('T-03d',
    'O5 (1/5): band=weak; pending=1, redeemed=0; redeem_rate NULL (payda<5)',
    v_o5 ->> 'band' = 'weak'
      and (v_o5 ->> 'pending_errors')::int = 1
      and (v_o5 ->> 'redeemed')::int = 0
      and (v_o5 ->> 'redeem_rate') is null
      and (v_o5 ->> 'success_rate') = '20.0',
    v_o5::text);

  perform public._qa_f6_true('T-03e',
    '6. sinif O3, A planinda YOK',
    v_o1 is not null and v_o2 is not null and v_o4 is not null
      and not exists (
        select 1 from jsonb_array_elements(v_plan) e
         where e ->> 'outcome_id' = '98989898-9898-9898-9898-989898980022'),
    null);
end;
$blk$;


-- ============================================================
-- T-04: IZOLASYON — B yalniz KENDI kapsamini gorur
-- ============================================================

do $blk$
declare
  v_plan jsonb;
  v_ids  text[];
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000092","role":"authenticated"}', true);

  v_plan := public.get_outcome_review_plan(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select array_agg(e ->> 'outcome_id')
    into v_ids
    from jsonb_array_elements(v_plan) e;

  perform public._qa_f6_true('T-04a',
    'B plani yalniz 6. sinif O3''u icerir',
    v_ids = array['98989898-9898-9898-9898-989898980022'],
    coalesce(array_to_string(v_ids, ','), 'bos'));

  perform public._qa_f6_true('T-04b',
    'B''nin O3 metrikleri bos: A verisi sizmaz',
    (select e ->> 'band'
       from jsonb_array_elements(v_plan) e
      where e ->> 'outcome_id' = '98989898-9898-9898-9898-989898980022')
    = 'insufficient_data',
    null);
end;
$blk$;


-- ============================================================
-- T-05/T-06: COOLDOWN + HATA HAVUZU
--
-- Asama 1: yalniz T1 BUGUN yanlis -> tekrar_gerekmiyor.
-- Asama 2: W1/W2 dun yanlis eklenir -> havuzda; T1 yine disarida.
-- ============================================================

do $blk$
declare
  v_res jsonb;
begin
  -- Bugun yanlis (T1): cooldown disi kalacak tek kayit.
  insert into public.student_question_attempts
    (user_id, question_id, subject_id, attempt_context, result,
     attempt_number, time_ms, academic_year, week, answered_at, metadata)
  values
    ('98989898-9898-9898-9898-000000000091',
     '98989898-9898-9898-9898-989898981003',
     '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'training', 'wrong',
     1, 20000, 'QA6-Y', 5,
     (public._qa_f6_utc_day(0))::timestamptz + interval '10 hours',
     '{"source":"qa6"}'::jsonb);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000091","role":"authenticated"}', true);

  v_res := public.select_targeted_review_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
    '98989898-9898-9898-9898-989898980020'::uuid,
    5);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_f6_true('T-05',
    'cooldown: yalniz bugunku yanlis varken tekrar_gerekmiyor',
    v_res ->> 'reason' = 'tekrar_gerekmiyor'
      and jsonb_array_length(v_res -> 'questions') = 0
      and (v_res ->> 'wrong_review_count')::int = 0,
    v_res::text);
end;
$blk$;

do $blk$
declare
  v_res  jsonb;
  v_ids  text[];
begin
  -- Dun yanlis (W1/W2): cooldown sureci gecmis havuz adaylari.
  insert into public.student_question_attempts
    (user_id, question_id, subject_id, attempt_context, result,
     attempt_number, time_ms, academic_year, week, answered_at, metadata)
  values
    ('98989898-9898-9898-9898-000000000091',
     '98989898-9898-9898-9898-989898981001',
     '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'training', 'wrong',
     1, 25000, 'QA6-Y', 5,
     (public._qa_f6_utc_day(1))::timestamptz + interval '09 hours',
     '{"source":"qa6"}'::jsonb),
    ('98989898-9898-9898-9898-000000000091',
     '98989898-9898-9898-9898-989898981002',
     '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'training', 'wrong',
     1, 30000, 'QA6-Y', 5,
     (public._qa_f6_utc_day(1))::timestamptz + interval '11 hours',
     '{"source":"qa6"}'::jsonb);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000091","role":"authenticated"}', true);

  v_res := public.select_targeted_review_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
    '98989898-9898-9898-9898-989898980020'::uuid,
    5);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select coalesce(array_agg(q ->> 'id'), '{}')
    into v_ids
    from jsonb_array_elements(v_res -> 'questions') q;

  perform public._qa_f6_true('T-06a',
    'dunku yanlilar havuzda (W1,W2) + doldurma N1-N3; bugunku (T1) cooldown disi',
    v_ids = array[
      '98989898-9898-9898-9898-989898981001',
      '98989898-9898-9898-9898-989898981002',
      '98989898-9898-9898-9898-989898982001',
      '98989898-9898-9898-9898-989898982002',
      '98989898-9898-9898-9898-989898982003'],
    array_to_string(v_ids, ','));

  perform public._qa_f6_true('T-06b',
    'wrong_review_count=2, new_count=3, reason NULL',
    (v_res ->> 'wrong_review_count')::int = 2
      and (v_res ->> 'new_count')::int = 3
      and (v_res ->> 'reason') is null
      and v_res ->> 'session_kind' = 'targeted_review',
    v_res::text);
end;
$blk$;


-- ============================================================
-- T-07: DETERMİNİZM (iki secim ozdes)
-- ============================================================

do $blk$
declare
  v_a jsonb;
  v_b jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000091","role":"authenticated"}', true);

  -- p_limit havuz boyutuna esit: doldurma YOK, tam determinizm.
  v_a := public.select_targeted_review_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
    '98989898-9898-9898-9898-989898980020'::uuid,
    2);
  v_b := public.select_targeted_review_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
    '98989898-9898-9898-9898-989898980020'::uuid,
    2);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_f6_true('T-07',
    'iki ardışık seçim birebir aynı (random yok)',
    v_a -> 'questions' = v_b -> 'questions',
    null);
end;
$blk$;


-- ============================================================
-- T-08: p_limit SINIRLARI
-- ============================================================

do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000091","role":"authenticated"}', true);

  perform public._qa_f6_expect('T-08a',
    'p_limit=0 -> 22023', '22023',
    $sql$select public.select_targeted_review_questions(
      '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
      '98989898-9898-9898-9898-989898980020'::uuid,
      0)$sql$);

  perform public._qa_f6_expect('T-08b',
    'p_limit=11 -> 22023', '22023',
    $sql$select public.select_targeted_review_questions(
      '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
      '98989898-9898-9898-9898-989898980020'::uuid,
      11)$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-09: KAPSAM FAIL-CLOSED
-- ============================================================

do $blk$
declare
  v_res_a jsonb;
  v_res_b jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000091","role":"authenticated"}', true);

  -- A, B'nin 6. sinif kazanimini ister -> kapsam disi.
  v_res_a := public.select_targeted_review_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
    '98989898-9898-9898-9898-989898980022'::uuid,
    5);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000092","role":"authenticated"}', true);

  -- B, A'nin 5. sinif kazanimini ister -> kapsam disi.
  v_res_b := public.select_targeted_review_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
    '98989898-9898-9898-9898-989898980020'::uuid,
    5);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_f6_true('T-09a',
    'A -> B kapsam fail-closed (gecersiz_kapsam, bos liste)',
    v_res_a ->> 'reason' = 'gecersiz_kapsam'
      and jsonb_array_length(v_res_a -> 'questions') = 0,
    v_res_a::text);

  perform public._qa_f6_true('T-09b',
    'B -> A kapsam fail-closed (gecersiz_kapsam, bos liste)',
    v_res_b ->> 'reason' = 'gecersiz_kapsam'
      and jsonb_array_length(v_res_b -> 'questions') = 0,
    null);
end;
$blk$;


-- ============================================================
-- T-10: HATA HAVUZU ONELIGI + YENI DOLDURMA + HAFTALIK KAPASITE
-- ============================================================

do $blk$
declare
  v_res  jsonb;
  v_ids  text[];
  v_used integer;
begin
  -- 3 gun once yanlis (P1-P3): redeem paydasi icin ek bekleyen hatalar.
  insert into public.student_question_attempts
    (user_id, question_id, subject_id, attempt_context, result,
     attempt_number, time_ms, academic_year, week, answered_at, metadata)
  select '98989898-9898-9898-9898-000000000091',
         q.id,
         '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'training', 'wrong',
         1, 40000, 'QA6-Y', 5,
         (public._qa_f6_utc_day(3))::timestamptz + interval '08 hours',
         '{"source":"qa6"}'::jsonb
    from public.questions q
   where q.question_code in ('QA6-P1', 'QA6-P2', 'QA6-P3');

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000091","role":"authenticated"}', true);

  v_res := public.select_targeted_review_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
    '98989898-9898-9898-9898-989898980020'::uuid,
    10);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select coalesce(array_agg(q ->> 'id'), '{}')
    into v_ids
    from jsonb_array_elements(v_res -> 'questions') q;

  perform public._qa_f6_true('T-10a',
    'havuz onceligi + deterministik sir + yeni doldurma (5 havuz + 1 yeni)',
    v_ids = array[
      '98989898-9898-9898-9898-989898981001',
      '98989898-9898-9898-9898-989898981002',
      '98989898-9898-9898-9898-989898981005',
      '98989898-9898-9898-9898-989898981006',
      '98989898-9898-9898-9898-989898981007',
      '98989898-9898-9898-9898-989898982004'],
    array_to_string(v_ids, ','));

  perform public._qa_f6_true('T-10b',
    'wrong_review_count=5, new_count=1',
    (v_res ->> 'wrong_review_count')::int = 5
      and (v_res ->> 'new_count')::int = 1,
    null);

  perform public._qa_f6_true('T-10c',
    'haftalik kapasite yalniz YENI soru icin tuketildi (used=4, limit=500)',
    (v_res -> 'weekly' ->> 'new_questions_used')::int = 4
      and (v_res -> 'weekly' ->> 'limit')::int = 500
      and v_res -> 'weekly' ->> 'academic_year' = 'QA6-Y'
      and (v_res -> 'weekly' ->> 'week')::int = 5,
    (v_res -> 'weekly')::text);

  select count(*) into v_used
    from public.student_question_exposures e
   where e.user_id = '98989898-9898-9898-9898-000000000091'
     and e.question_id in (
       '98989898-9898-9898-9898-989898982001',
       '98989898-9898-9898-9898-989898982002',
       '98989898-9898-9898-9898-989898982003',
       '98989898-9898-9898-9898-989898982004')
     and e.attempt_context = 'training';

  perform public._qa_f6_true('T-10d',
    'yeni 4 soru icin training exposure yazildi',
    v_used = 4,
    'exposures=' || v_used);
end;
$blk$;


-- ============================================================
-- T-11: TELAFI — correct sonrasi havuzdan cikar; plan guncellenir
-- ============================================================

do $blk$
declare
  v_submit jsonb;
  v_res    jsonb;
  v_ids    text[];
  v_o1     jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000091","role":"authenticated"}', true);

  -- A, dunku yanlis yaptigi W2'ye dogru cevap verir (RPC yolu).
  v_submit := public.submit_training_attempt(
    '98989898-9898-9898-9898-989898981002'::uuid,
    'B', null, 30000,
    '98989898-9898-9898-9898-00000000aaaa'::uuid);

  v_res := public.select_targeted_review_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
    '98989898-9898-9898-9898-989898980020'::uuid,
    10);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_f6_true('T-11a',
    'submit dogru sonuc uretti (correct)',
    v_submit ->> 'result' = 'correct',
    v_submit::text);

  select coalesce(array_agg(q ->> 'id'), '{}')
    into v_ids
    from jsonb_array_elements(v_res -> 'questions') q;

  perform public._qa_f6_true('T-11b',
    'telafi edilen W2 havuzdan cikti (gereksiz tekrar engellendi)',
    not ('98989898-9898-9898-9898-989898981002' = any(v_ids))
      and (v_res ->> 'wrong_review_count')::int = 4,
    array_to_string(v_ids, ','));

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000091","role":"authenticated"}', true);

  select e into v_o1
    from jsonb_array_elements(public.get_outcome_review_plan(
      '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid)) e
   where e ->> 'outcome_id' = '98989898-9898-9898-9898-989898980020';

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_f6_true('T-11c',
    'plan guncel: pending=5 (T1 dahil), redeemed=1, redeem_rate=16.7 (payda=6)',
    (v_o1 ->> 'pending_errors')::int = 5
      and (v_o1 ->> 'redeemed')::int = 1
      and v_o1 ->> 'redeem_rate' = '16.7',
    v_o1::text);
end;
$blk$;


-- ============================================================
-- T-12: RATE LIMIT (esikte P0001)
-- ============================================================

do $blk$
begin
  -- Sabit pencereyi PRIME et: hit_count=30 (limit 30).
  -- PostgreSQL (guvenilir QA rolu) yazar; istemci rolleri bu tabloya
  -- yazamaz (075 modeli).
  insert into public.rpc_rate_limits
    (user_id, rpc_name, window_start, hit_count)
  values
    ('98989898-9898-9898-9898-000000000091', 'targeted_review_select',
     to_timestamp(floor(extract(epoch from clock_timestamp()) / 3600) * 3600),
     30)
  on conflict (user_id, rpc_name, window_start)
  do update set hit_count = 30;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"98989898-9898-9898-9898-000000000091","role":"authenticated"}', true);

  perform public._qa_f6_expect('T-12',
    'esikte rate limit P0001 (cok fazla istek)', 'P0001',
    $sql$select public.select_targeted_review_questions(
      '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
      '98989898-9898-9898-9898-989898980020'::uuid,
      5)$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- KALANTI KONTROLU (rollback oncesi tespit)
-- ============================================================

select
  (select count(*) from public.student_profiles
    where nickname like 'QA6-%')            as profiles_kalan,
  (select count(*) from public.questions
    where question_code like 'QA6-%')       as questions_kalan,
  (select count(*) from public.question_vaults
    where vault_code like 'QA6-%')          as vaults_kalan,
  (select count(*) from public.student_question_attempts
    where user_id::text like '98989898%')   as attempts_kalan,
  (select count(*) from public.student_question_exposures
    where user_id::text like '98989898%')   as exposures_kalan,
  (select count(*) from public.rpc_rate_limits
    where user_id::text like '98989898%')   as ratelimit_kalan;


-- ============================================================
-- SONUC RAPORU (CI parsed deseni: son satir toplam|gecen|kalan)
-- ============================================================

select
  label                                                        as test_id,
  case when bool_and(result = 'PASS') then 'PASS' else 'FAIL' end as durum,
  count(*) filter (where result = 'FAIL')                      as alt_fail,
  string_agg(
    case when result = 'PASS' then title
         else title || ' >>> ' || coalesce(detail, '') end,
    ' | ' order by title)                                      as detay
from public._qa_f6_results
group by label
order by label;

with g as (
  select label, bool_and(result = 'PASS') as ok
  from public._qa_f6_results
  group by label
)
select
  count(*)                        as toplam,
  count(*) filter (where ok)      as gecen,
  count(*) filter (where not ok)  as kalan
from g;


drop function public._qa_f6_true(text, text, boolean, text);
drop function public._qa_f6_expect(text, text, text, text);
drop function public._qa_f6_utc_day(integer);
drop table public._qa_f6_results;

rollback;
