-- ============================================================
-- scripts/qa_faz4_local_validation.sql
-- Altin Kalemler - Migration Faz 4 yerel QA suite (rate limiting)
--
-- Kapsam (_faz4_consume_rate_limit 075 + RPC baglantisi 076):
--   T-01     : anon -> helper EXECUTE-denied (internal-only)
--   T-02..03 : istemci rolleri rpc_rate_limits icerigini GOREMEZ
--              (grant'siz ortamda 42501; grant'li ortamda RLS-deny
--              bos sonuc — _qa4_expect_env ile ortam-toleransli,
--              af7f74f kalibi)
--   T-04..06 : gecersiz ic yapilandirma fail-closed (P0001)
--   T-07..09 : dogal tuketim: limit dolusu OK, fazlasi RED,
--              reddedilen istek kota TUKETMEZ
--   T-10..12 : kullanici izolasyonu + epoch hizali pencere
--              matematigi + pencere kaydirma davranisi
--   T-13..15 : RPC kablolamasi (weekly_usage / training_select /
--              pack_prepare): esik sinirinda RATE mesaji; dogal
--              hata mesajlarindan ONCE devreye girdigi kanitlanir
--   T-16..20 : submit zinciri: K1 happy path + sayac=1, replay
--              duplicate=true ve KOTA TUKETMEZ, yeni anahtar RED
--   T-21..22 : ACL drift guard: helper EXECUTE kapali, istemci
--              tablo erisimi kapali (grant yok YA DA RLS+policy-yok
--              deny — her iki ortamda da ayni guvence)
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_faz4_local_validation.sql supabase_db_yarisma-programi:/tmp/
--   docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -f /tmp/qa_faz4_local_validation.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR (faz35 deseninin aynisi)
-- ============================================================

create table public._qa_faz4_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_faz4_results
  to anon, authenticated, service_role;

create function public._qa4_expect(p_label text, p_title text, p_expect text, p_sql text)
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
      insert into public._qa_faz4_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_faz4_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_faz4_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_faz4_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa4_expect_env(
  p_label text, p_title text, p_sql text
)
returns void
language plpgsql
security invoker
as $qa$
declare
  v_state     text;
  v_msg       text;
  v_cnt       integer;
  v_rls       boolean;
  v_policies  integer;
begin
  begin
    execute p_sql into v_cnt;

    -- Grant'li ortam (yerel stack): RLS acik + policy yok -> istemci
    -- hicbir satiri GOREMEZ (0 doner). Guvenlik ozelligi aynidir;
    -- yalniz hata tipi (42501 vs bos sonuc) ortama gore degisir.
    select relrowsecurity into v_rls
      from pg_class where oid = 'public.rpc_rate_limits'::regclass;

    select count(*) into v_policies
      from pg_policies
     where schemaname = 'public' and tablename = 'rpc_rate_limits';

    if v_cnt = 0 and v_rls and v_policies = 0 then
      insert into public._qa_faz4_results
      values (p_label, p_title, 'PASS',
              'grantli ortam: RLS-deny bos (cnt=0, policy=0)');
    else
      insert into public._qa_faz4_results
      values (p_label, p_title, 'FAIL',
              format('grantli ortam: cnt=%s rls=%s policy=%s',
                     v_cnt, v_rls, v_policies));
    end if;

  exception when insufficient_privilege then
    -- Grant'siz ortam (CI): dogrudan 42501 -> beklenen davranis.
    insert into public._qa_faz4_results
    values (p_label, p_title, 'PASS',
            '42501 insufficient_privilege (grant yok)');
  when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    insert into public._qa_faz4_results
    values (p_label, p_title, 'FAIL',
            'sqlstate=' || v_state || ' | ' || left(v_msg, 200));
  end;
end;
$qa$;

create function public._qa4_expect_msg(
  p_label text, p_title text, p_sql text,
  p_state text, p_msg_pattern text
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
    insert into public._qa_faz4_results
    values (p_label, p_title, 'FAIL',
            'hata beklenmisti ama uygulandi');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if v_state = p_state and upper(v_msg) like upper(p_msg_pattern) then
      insert into public._qa_faz4_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | mesaj eslesti');
    else
      insert into public._qa_faz4_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || p_state ||
              ' | msg=' || left(v_msg, 160));
    end if;
  end;
end;
$qa$;

create function public._qa4_true(p_label text, p_title text, p_ok boolean, p_detail text default null)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_faz4_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa4_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa4_expect_env(text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa4_expect_msg(text, text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa4_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR (sabit QA uuid'leri; rollback ile silinecek)
-- matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
-- Sorularin correct_answer degerleri bilinir:
--   Q4-01='C'  Q4-02='A'  Q4-03='B'  Q4-04='D'  Q4-05='E'
-- ============================================================

insert into auth.users (id, email) values
  ('99999999-9999-9999-9999-999999999921', 'qa4-user-a@test.local'),
  ('99999999-9999-9999-9999-999999999922', 'qa4-user-b@test.local'),
  ('99999999-9999-9999-9999-999999999923', 'qa4-student@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('99999999-9999-9999-9999-999999999921', 12, 'QA4-NICK-A'),
  ('99999999-9999-9999-9999-999999999922', 12, 'QA4-NICK-B'),
  ('99999999-9999-9999-9999-999999999923', 12, 'QA4-NICK-S');

insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('88888888-8888-8888-7777-888888888802', 'QA4-Y-2099', 'MEB-QA4', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('77777777-7777-7777-6666-777777777702', 'QA4-SCHED', 'QA4 Profil',
   '88888888-8888-8888-7777-888888888802', true, true);

insert into public.academic_weeks (academic_year, week, starts_at, ends_at) values
  ('QA4-Y-2099', 5, current_date - 3, current_date + 4),
  ('QA4-Y-2099', 6, current_date + 4, current_date + 11);

insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('66666666-6666-6666-5555-000000000002',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   12, 'QA4 Islenmis Konu', 'qa4-islenmis',
   '88888888-8888-8888-7777-888888888802');

insert into public.subtopics (id, topic_id, name, slug) values
  ('55555555-5555-5555-4444-000000000002',
   '66666666-6666-6666-5555-000000000002',
   'QA4 Alt Konu', 'qa4-alt-konu');

insert into public.curriculum_outcomes
  (id, curriculum_version_id, grade_level, subject_id, outcome_text) values
  ('44444444-4444-4444-3333-000000000002',
   '88888888-8888-8888-7777-888888888802', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   'QA4 kazanım metni');

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, start_week, end_week) values
  ('77777777-7777-7777-6666-777777777702', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '66666666-6666-6666-5555-000000000002', 1, 3);

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, outcome_id, start_week) values
  ('77777777-7777-7777-6666-777777777702', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '44444444-4444-4444-3333-000000000002', 2);

insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer)
values
  ('33333333-3333-3333-9999-000000000041', 'Q4-01', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'C'),
  ('33333333-3333-3333-9999-000000000042', 'Q4-02', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'acik_uclu', 'A'),
  ('33333333-3333-3333-9999-000000000043', 'Q4-03', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'hard', 'comprehension', 'dogru_yanlis', 'B'),
  ('33333333-3333-3333-9999-000000000044', 'Q4-04', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'D'),
  ('33333333-3333-3333-9999-000000000045', 'Q4-05', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'bosluk_doldurma', 'E');

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, subtopic_id, review_status)
select ('33333333-3333-3333-9999-0000000000' || n)::uuid,
       '88888888-8888-8888-7777-888888888802',
       '66666666-6666-6666-5555-000000000002',
       '55555555-5555-5555-4444-000000000002', 'approved'
  from unnest(array['41','42','43','44','45']) n;

insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('22222222-2222-2222-1111-00000000000b', 'QA4-V-PRACTICE',
   'QA4 Antrenman Kasasi', 'practice', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, practice_eligible)
select '22222222-2222-2222-1111-00000000000b',
       ('33333333-3333-3333-9999-0000000000' || n)::uuid, 'active', true
  from unnest(array['41','42','43','44','45']) n;

-- Submit testi icin dogrudan (postgres) exposure: istemci yolu
-- zaten Faz 3'te kanitlandi; burada yalniz rate-limit zinciri
-- izole ediliyor.
insert into public.student_question_exposures
  (user_id, question_id, attempt_context)
values
  ('99999999-9999-9999-9999-999999999923',
   '33333333-3333-3333-9999-000000000041', 'training');


-- ============================================================
-- T-01..03: YETKI SINIRLARI
-- ============================================================

do $blk$
begin
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);

  perform public._qa4_expect('T-01',
    'anon: rate-limit helper EXECUTE-denied (internal-only)',
    '42501',
    $sql$select public._faz4_consume_rate_limit('qa_x', 1, 60)$sql$);

  perform public._qa4_expect_env('T-02',
    'anon: rpc_rate_limits icerigi GOREMEZ (42501 ya da RLS-deny)',
    $sql$select count(*) from public.rpc_rate_limits$sql$);
end;
$blk$;

do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999923","role":"authenticated"}', true);

  perform public._qa4_expect_env('T-03',
    'authenticated: rpc_rate_limits icerigi GOREMEZ (42501 ya da RLS-deny)',
    $sql$select count(*) from public.rpc_rate_limits$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-04..06: GECERSIZ IC YAPILANDIRMA -> FAIL-CLOSED
-- (config kontrolu auth.uid()'den ONCE; claims bos iken de tetiklenir)
-- ============================================================

select public._qa4_expect_msg('T-04',
  'config fail-closed: p_limit=0',
  $sql$select public._faz4_consume_rate_limit('qa_cfg', 0, 60)$sql$,
  'P0001', '%gecersiz (p_limit)%');

select public._qa4_expect_msg('T-05',
  'config fail-closed: p_window_seconds=0',
  $sql$select public._faz4_consume_rate_limit('qa_cfg', 5, 0)$sql$,
  'P0001', '%gecersiz (p_window_seconds)%');

select public._qa4_expect_msg('T-06',
  'config fail-closed: bos rpc_name',
  $sql$select public._faz4_consume_rate_limit('', 5, 60)$sql$,
  'P0001', '%gecersiz (rpc_name)%');


-- ============================================================
-- T-07..12: DOGAL TUKETIM / IZOLASYON / PENCERE MATEMATIGI
-- Helper'a cagrilar postgres + claims kimligiyle yapilir
-- (EXECUTE istemcilerden alinmis durumda; bu kasitli).
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999921","role":"authenticated"}', true);

-- Uc serbest tuketim (limit=3).
select public._faz4_consume_rate_limit('qa_rl', 3, 3600);
select public._faz4_consume_rate_limit('qa_rl', 3, 3600);
select public._faz4_consume_rate_limit('qa_rl', 3, 3600);

select public._qa4_true('T-07',
  'dogal tuketim: limit dolusu 3 cagri tek pencerede birikir',
  (select count(*) = 1 and bool_and(hit_count = 3)
     from public.rpc_rate_limits
    where user_id = '99999999-9999-9999-9999-999999999921'
      and rpc_name = 'qa_rl'),
  format('satir=%s hit=%s',
         (select count(*) from public.rpc_rate_limits
           where user_id = '99999999-9999-9999-9999-999999999921'
             and rpc_name = 'qa_rl'),
         (select max(hit_count) from public.rpc_rate_limits
           where user_id = '99999999-9999-9999-9999-999999999921'
             and rpc_name = 'qa_rl')));

select public._qa4_expect_msg('T-08',
  'limit asimi: 4. cagri RED (P0001 rate mesaji)',
  $sql$select public._faz4_consume_rate_limit('qa_rl', 3, 3600)$sql$,
  'P0001', '%Cok fazla istek%');

select public._qa4_true('T-09',
  'reddedilen istek kota TUKETMEZ: hit_count=3 kalir',
  (select hit_count = 3
     from public.rpc_rate_limits
    where user_id = '99999999-9999-9999-9999-999999999921'
      and rpc_name = 'qa_rl'
      and window_start = to_timestamp(
            floor(extract(epoch from clock_timestamp()) / 3600) * 3600)),
  'hit=' || (select hit_count from public.rpc_rate_limits
              where user_id = '99999999-9999-9999-9999-999999999921'
                and rpc_name = 'qa_rl'));

-- Kullanici izolasyonu: B'nin sayaci A'dan bagimsiz.
select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999922","role":"authenticated"}', true);

do $blk$
declare
  v_win timestamptz;
  v_hit integer;
begin
  v_win := to_timestamp(
    floor(extract(epoch from clock_timestamp()) / 300) * 300);

  perform public._faz4_consume_rate_limit('qa_win', 5, 300);

  select rl.hit_count into v_hit
    from public.rpc_rate_limits rl
   where rl.user_id = '99999999-9999-9999-9999-999999999922'
     and rl.rpc_name = 'qa_win';

  perform public._qa4_true('T-10',
    'kullanici izolasyonu: B kendi sayacinda tuketir (A etkilenmez)',
    v_hit = 1
      and not exists (
        select 1 from public.rpc_rate_limits
         where user_id = '99999999-9999-9999-9999-999999999921'
           and rpc_name = 'qa_win'),
    'B.hit=' || coalesce(v_hit, -1));

  perform public._qa4_true('T-12',
    'pencere EPOCH HIZALI: kaydedilen window_start beklenen degere esit',
    exists (
      select 1 from public.rpc_rate_limits
       where user_id = '99999999-9999-9999-9999-999999999922'
         and rpc_name = 'qa_win'
         and window_start = v_win),
    'v_win=' || v_win);
end;
$blk$;

-- Pencere izolasyonu: A'nin dolu satiri Onceki pencereye kaydirilir
-- (saat geri alinmis gibi); mevcut pencerede yeni satir acilir.
update public.rpc_rate_limits
   set window_start = window_start - interval '3600 seconds'
 where user_id = '99999999-9999-9999-9999-999999999921'
   and rpc_name = 'qa_rl';

select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999921","role":"authenticated"}', true);

do $blk$
declare
  v_cur timestamptz;
  v_new_hit integer;
  v_old_hit integer;
begin
  v_cur := to_timestamp(
    floor(extract(epoch from clock_timestamp()) / 3600) * 3600);

  perform public._faz4_consume_rate_limit('qa_rl', 3, 3600);

  select rl.hit_count into v_new_hit
    from public.rpc_rate_limits rl
   where rl.user_id = '99999999-9999-9999-9999-999999999921'
     and rl.rpc_name = 'qa_rl'
     and rl.window_start = v_cur;

  select rl.hit_count into v_old_hit
    from public.rpc_rate_limits rl
   where rl.user_id = '99999999-9999-9999-9999-999999999921'
     and rl.rpc_name = 'qa_rl'
     and rl.window_start = v_cur - interval '3600 seconds';

  perform public._qa4_true('T-11',
    'pencere izolasyonu: kaydirilan satir yeni pencereyi bloklamaz',
    v_new_hit = 1 and v_old_hit = 3,
    format('yeni=%s eski=%s', v_new_hit, v_old_hit));
end;
$blk$;

select set_config('request.jwt.claims', '', true);


-- ============================================================
-- T-13..15: RPC KABLOLAMASI (esik sinirinda bilet kesme)
-- Postgres tarafindan sayaclar sinira tasiniyor; RPC cagrisinin
-- RATE mesaji vermesi, gate'in dogal akisdan ONCE calistigini
-- kanitlar (period/context/competition hatalarindan ayirt edilir).
-- ============================================================

insert into public.rpc_rate_limits
  (user_id, rpc_name, window_start, hit_count)
values
  ('99999999-9999-9999-9999-999999999923', 'weekly_usage',
   to_timestamp(floor(extract(epoch from clock_timestamp()) / 300) * 300), 60),
  ('99999999-9999-9999-9999-999999999923', 'training_select',
   to_timestamp(floor(extract(epoch from clock_timestamp()) / 3600) * 3600), 90),
  ('99999999-9999-9999-9999-999999999923', 'pack_prepare',
   to_timestamp(floor(extract(epoch from clock_timestamp()) / 3600) * 3600), 30)
on conflict (user_id, rpc_name, window_start)
do update set hit_count = excluded.hit_count;

select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999923","role":"authenticated"}', true);

select public._qa4_expect_msg('T-13',
  'get_my_weekly_usage: esikte RATE (period hatasi DEGIL)',
  $sql$select public.get_my_weekly_usage()$sql$,
  'P0001', '%Cok fazla istek%');

select public._qa4_expect_msg('T-14',
  'select_training_questions: esikte RATE (baglam hatasi DEGIL)',
  $sql$select public.select_training_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10)$sql$,
  'P0001', '%Cok fazla istek%');

select public._qa4_expect_msg('T-15',
  'prepare_competition_pack: esikte RATE (yarisma aramasindan ONCE)',
  $sql$select public.prepare_competition_pack(
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1'::uuid)$sql$,
  'P0001', '%Cok fazla istek%');


-- ============================================================
-- T-16..20: SUBMIT ZINCIRI (replay muafiyeti siralamasi)
-- ============================================================

do $blk$
declare
  v_r jsonb;
begin
  select public.submit_training_attempt(
    '33333333-3333-3333-9999-000000000041', 'A', null, 45000,
    'cccccccc-cccc-cccc-cccc-000000000901')
    into v_r;

  perform public._qa4_true('T-16',
    'submit K1: DB-side grading + duplicate=false',
    (v_r->>'result') = 'wrong'
      and (v_r->>'duplicate') = 'false'
      and (v_r->>'attempt_number') = '1',
    'resp=' || left(v_r::text, 160));

  perform public._qa4_true('T-17',
    'submit K1 rate bileti kesildi: training_submit hit=1',
    (select hit_count = 1
       from public.rpc_rate_limits
      where user_id = '99999999-9999-9999-9999-999999999923'
        and rpc_name = 'training_submit'
        and window_start = to_timestamp(
              floor(extract(epoch from clock_timestamp()) / 3600) * 3600)),
    'hit=' || coalesce((select hit_count from public.rpc_rate_limits
                         where user_id = '99999999-9999-9999-9999-999999999923'
                           and rpc_name = 'training_submit'), -1));
end;
$blk$;

-- Sayaci sinira tasi.
update public.rpc_rate_limits
   set hit_count = 240
 where user_id = '99999999-9999-9999-9999-999999999923'
   and rpc_name = 'training_submit';

do $blk$
declare
  v_r jsonb;
begin
  -- REPLAY: ayni client_key; rate-limitten ONCE erken doner.
  select public.submit_training_attempt(
    '33333333-3333-3333-9999-000000000041', 'A', null, 45000,
    'cccccccc-cccc-cccc-cccc-000000000901')
    into v_r;

  perform public._qa4_true('T-18',
    'replay K1: duplicate=true (kota harcanmadan gercek yanit)',
    (v_r->>'duplicate') = 'true'
      and (v_r->>'result') = 'wrong'
      and (v_r->>'attempt_number') = '1',
    'resp=' || left(v_r::text, 160));

  perform public._qa4_true('T-19',
    'replay K1 KOTA TUKETMEZ: hit hala 240',
    (select hit_count = 240
       from public.rpc_rate_limits
      where user_id = '99999999-9999-9999-9999-999999999923'
        and rpc_name = 'training_submit'),
    'hit=' || coalesce((select hit_count from public.rpc_rate_limits
                         where user_id = '99999999-9999-9999-9999-999999999923'
                           and rpc_name = 'training_submit'), -1));
end;
$blk$;

select public._qa4_expect_msg('T-20',
  'sinirda YENI anahtar (K2) RED: rate mesaji',
  $sql$select public.submit_training_attempt(
    '33333333-3333-3333-9999-000000000041', 'C', null, 30000,
    'cccccccc-cccc-cccc-cccc-000000000902')$sql$,
  'P0001', '%Cok fazla istek%');

select set_config('request.jwt.claims', '', true);


-- ============================================================
-- T-21..22: ACL DRIFT GUARD (075 son durumu)
-- ============================================================

do $blk$
declare
  v_rls      boolean;
  v_policies integer;
begin
  perform public._qa4_true('T-21',
    'drift guard: helper EXECUTE anon/authenticated KAPALI',
    not has_function_privilege('anon',
      'public._faz4_consume_rate_limit(text,integer,integer)', 'EXECUTE')
      and not has_function_privilege('authenticated',
      'public._faz4_consume_rate_limit(text,integer,integer)', 'EXECUTE'),
    null);

  -- Grant'siz ortam (CI): tablo grant YOK beklenir. Grant'li ortam
  -- (yerel stack): RLS acik + policy YOK -> istemci SELECT/INSERT
  -- erisimi RLS-deny ile butunler; ozellik (icerik gorunmez/yazilamaz)
  -- her iki ortamda da korunur.
  select relrowsecurity into v_rls
    from pg_class where oid = 'public.rpc_rate_limits'::regclass;

  select count(*) into v_policies
    from pg_policies
   where schemaname = 'public' and tablename = 'rpc_rate_limits';

  perform public._qa4_true('T-22',
    'drift guard: rpc_rate_limits istemcilere KAPALI (grant yok YA DA RLS+policy-yok deny)',
    (not has_table_privilege('anon', 'public.rpc_rate_limits', 'SELECT')
      and not has_table_privilege('authenticated', 'public.rpc_rate_limits', 'SELECT')
      and not has_table_privilege('anon', 'public.rpc_rate_limits', 'INSERT'))
    or (v_rls and v_policies = 0),
    format('rls=%s policy=%s', v_rls::text, v_policies::text));
end;
$blk$;


-- ============================================================
-- TEMIZLIK (suite ici dogrulama; final ROLLBACK her seyi geri alir)
-- ============================================================

delete from public.student_question_attempts
 where user_id = '99999999-9999-9999-9999-999999999923'
   and metadata ->> 'client_key' in
       ('cccccccc-cccc-cccc-cccc-000000000901',
        'cccccccc-cccc-cccc-cccc-000000000902');

delete from public.student_question_exposures
 where user_id = '99999999-9999-9999-9999-999999999923'
   and question_id = '33333333-3333-3333-9999-000000000041';

delete from public.question_vault_memberships
 where vault_id = '22222222-2222-2222-1111-00000000000b';
delete from public.question_vaults
 where id = '22222222-2222-2222-1111-00000000000b';
delete from public.question_curriculum_mappings
 where curriculum_version_id = '88888888-8888-8888-7777-888888888802';
delete from public.questions where question_code like 'Q4-%';
delete from public.curriculum_schedule_items
 where schedule_profile_id = '77777777-7777-7777-6666-777777777702';
delete from public.curriculum_outcomes
 where curriculum_version_id = '88888888-8888-8888-7777-888888888802';
delete from public.subtopics where topic_id = '66666666-6666-6666-5555-000000000002';
delete from public.topics where id = '66666666-6666-6666-5555-000000000002';
delete from public.academic_weeks where academic_year = 'QA4-Y-2099';
delete from public.curriculum_schedule_profiles
 where id = '77777777-7777-7777-6666-777777777702';
delete from public.curriculum_versions
 where id = '88888888-8888-8888-7777-888888888802';
delete from public.student_profiles
 where id in ('99999999-9999-9999-9999-999999999921',
              '99999999-9999-9999-9999-999999999922',
              '99999999-9999-9999-9999-999999999923');
delete from auth.users where email like 'qa4-%@test.local';


-- Temizlik dogrulamasi (rollback oncesi durum).
select
  (select count(*) from auth.users
    where email like 'qa4-%@test.local')                       as users_kalan,
  (select count(*) from public.rpc_rate_limits)                 as sayaclar_kalan,
  (select count(*) from public.student_question_attempts
    where metadata ? 'client_key')                              as attempts_kalan,
  (select count(*) from public.questions
    where question_code like 'Q4-%')                            as questions_kalan;


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
from public._qa_faz4_results
group by label
order by label;

with g as (
  select label, bool_and(result = 'PASS') as ok
  from public._qa_faz4_results
  group by label
)
select
  count(*)                        as toplam_test,
  count(*) filter (where ok)      as gecen,
  count(*) filter (where not ok)  as kalan
from g;


drop function public._qa4_true(text, text, boolean, text);
drop function public._qa4_expect_msg(text, text, text, text, text);
drop function public._qa4_expect(text, text, text, text);
drop table public._qa_faz4_results;

rollback;
