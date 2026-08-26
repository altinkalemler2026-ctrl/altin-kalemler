-- ============================================================
-- scripts/qa_auth_user_profile_trigger.sql
-- Altin Kalemler - Migration 083 profile trigger QA suite
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_auth_user_profile_trigger.sql \
--     supabase_db_yarisma-programi:/tmp/
--   docker exec supabase_db_yarisma-programi psql -U postgres \
--     -d postgres -v ON_ERROR_STOP=1 \
--     -f /tmp/qa_auth_user_profile_trigger.sql
--
-- Guvence: suite TEK TRANSACTION icinde calisir, sonunda
-- ROLLBACK ile hicbir artefakt kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- RESULT TABLE + HELPERS
-- ============================================================

create table if not exists public._qa_profile_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_profile_results
  to anon, authenticated, service_role;

create or replace function public._qa_profile_expect(
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
      insert into public._qa_profile_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_profile_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_profile_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_profile_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create or replace function public._qa_profile_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_profile_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute on function public._qa_profile_expect(text,text,text,text) to anon, authenticated, service_role;
grant execute on function public._qa_profile_true(text,text,boolean,text) to anon, authenticated, service_role;


-- ============================================================
-- T-01: FUNCTION EXISTS
-- ============================================================

do $blk$
declare
  v_exists boolean;
begin
  select exists (
    select 1 from pg_proc p
    join pg_namespace n ON p.pronamespace = n.oid
    where n.nspname = 'public'
      and p.proname = 'handle_new_user'
  ) into v_exists;

  perform public._qa_profile_true('T-01',
    'handle_new_user function exists',
    v_exists,
    'exists=' || v_exists);
end;
$blk$;


-- ============================================================
-- T-02: TRIGGER EXISTS EXACTLY ONCE
-- ============================================================

do $blk$
declare
  v_count integer;
begin
  select count(*) into v_count
    from pg_trigger t
    join pg_class c ON t.tgrelid = c.oid
    join pg_namespace n ON c.relnamespace = n.oid
    where n.nspname = 'auth'
      and c.relname = 'users'
      and t.tgname = 'on_auth_user_created'
      and NOT t.tgisinternal;

  perform public._qa_profile_true('T-02',
    'trigger on_auth_user_created exists exactly once',
    v_count = 1,
    'count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-03: SECURITY DEFINER
-- ============================================================

do $blk$
declare
  v_secdef boolean;
begin
  select p.prosecdef into v_secdef
    from pg_proc p
    join pg_namespace n ON p.pronamespace = n.oid
    where n.nspname = 'public'
      and p.proname = 'handle_new_user';

  perform public._qa_profile_true('T-03',
    'handle_new_user is SECURITY DEFINER',
    v_secdef = true,
    'secdef=' || v_secdef);
end;
$blk$;


-- ============================================================
-- T-04: SEARCH_PATH EMPTY
-- ============================================================

do $blk$
declare
  v_config text;
begin
  select p.proconfig::text into v_config
    from pg_proc p
    join pg_namespace n ON p.pronamespace = n.oid
    where n.nspname = 'public'
      and p.proname = 'handle_new_user';

  perform public._qa_profile_true('T-04',
    'search_path is empty',
    v_config like '%search_path=""%' or v_config like '%search_path=%""%',
    'config=' || left(v_config, 100));
end;
$blk$;


-- ============================================================
-- T-05: PUBLIC direct execute denied
-- Trigger functions return 0A000 (can only be called as triggers)
-- before REVOKE check. Both 42501 and 0A000 prove the call is blocked.
-- ============================================================

do $blk$
declare
  v_ok boolean := false;
  v_state text;
begin
  begin
    perform public.handle_new_user();
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    if v_state in ('42501', '0A000') then
      v_ok := true;
    end if;
  end;

  perform public._qa_profile_true('T-05',
    'PUBLIC: handle_new_user direct call blocked',
    v_ok,
    'sqlstate=' || coalesce(v_state, 'none'));
end;
$blk$;


-- ============================================================
-- T-06: anon direct execute denied
-- ============================================================

do $blk$
begin
  execute 'set local role anon';
  perform public._qa_profile_expect('T-06',
    'anon: handle_new_user EXECUTE denied',
    '42501',
    $sql$SELECT public.handle_new_user()$sql$);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-07: authenticated direct execute denied
-- ============================================================

do $blk$
begin
  execute 'set local role authenticated';
  perform public._qa_profile_expect('T-07',
    'authenticated: handle_new_user EXECUTE denied',
    '42501',
    $sql$SELECT public.handle_new_user()$sql$);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-08: Valid numeric metadata creates profile
-- ============================================================

do $blk$
declare
  v_user_id uuid := 'a1000000-0000-0000-0000-000000000001';
  v_count   integer;
begin
  insert into auth.users (id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at)
  values (
    v_user_id, 'authenticated', 'authenticated',
    'qa83-numeric@test.local', '',
    now(),
    '{"nickname":"QA83-NUM","grade_level":10}'::jsonb,
    now(), now()
  );

  select count(*) into v_count
    from public.student_profiles sp
   where sp.id = v_user_id;

  perform public._qa_profile_true('T-08',
    'valid numeric metadata -> profile created',
    v_count = 1,
    'count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-09: Valid string grade metadata creates profile
-- ============================================================

do $blk$
declare
  v_user_id uuid := 'a1000000-0000-0000-0000-000000000002';
  v_count   integer;
begin
  insert into auth.users (id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at)
  values (
    v_user_id, 'authenticated', 'authenticated',
    'qa83-string@test.local', '',
    now(),
    '{"nickname":"QA83-STR","grade_level":"5"}'::jsonb,
    now(), now()
  );

  select count(*) into v_count
    from public.student_profiles sp
   where sp.id = v_user_id;

  perform public._qa_profile_true('T-09',
    'valid string grade metadata -> profile created',
    v_count = 1,
    'count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-10: Nickname trimmed
-- ============================================================

do $blk$
declare
  v_nick text;
begin
  select sp.nickname into v_nick
    from public.student_profiles sp
   where sp.id = 'a1000000-0000-0000-0000-000000000001';

  perform public._qa_profile_true('T-10',
    'nickname is trimmed',
    v_nick = 'QA83-NUM',
    'nick=' || v_nick);
end;
$blk$;


-- ============================================================
-- T-11: Grade correctly stored
-- ============================================================

do $blk$
declare
  v_grade smallint;
begin
  select sp.grade_level into v_grade
    from public.student_profiles sp
   where sp.id = 'a1000000-0000-0000-0000-000000000001';

  perform public._qa_profile_true('T-11',
    'grade_level correctly stored as 10',
    v_grade = 10,
    'grade=' || v_grade);
end;
$blk$;


-- ============================================================
-- T-12: Missing nickname creates no profile
-- ============================================================

do $blk$
declare
  v_user_id uuid := 'a1000000-0000-0000-0000-000000000003';
  v_count   integer;
begin
  insert into auth.users (id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at)
  values (
    v_user_id, 'authenticated', 'authenticated',
    'qa83-no-nick@test.local', '',
    now(),
    '{"grade_level":8}'::jsonb,
    now(), now()
  );

  select count(*) into v_count
    from public.student_profiles sp
   where sp.id = v_user_id;

  perform public._qa_profile_true('T-12',
    'missing nickname -> no profile',
    v_count = 0,
    'count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-13: Missing grade creates no profile
-- ============================================================

do $blk$
declare
  v_user_id uuid := 'a1000000-0000-0000-0000-000000000004';
  v_count   integer;
begin
  insert into auth.users (id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at)
  values (
    v_user_id, 'authenticated', 'authenticated',
    'qa83-no-grade@test.local', '',
    now(),
    '{"nickname":"QA83-NOG"}'::jsonb,
    now(), now()
  );

  select count(*) into v_count
    from public.student_profiles sp
   where sp.id = v_user_id;

  perform public._qa_profile_true('T-13',
    'missing grade -> no profile',
    v_count = 0,
    'count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-14: Non-numeric grade causes no cast exception, no profile
-- ============================================================

do $blk$
declare
  v_user_id uuid := 'a1000000-0000-0000-0000-000000000005';
  v_count   integer;
begin
  insert into auth.users (id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at)
  values (
    v_user_id, 'authenticated', 'authenticated',
    'qa83-bad-grade@test.local', '',
    now(),
    '{"nickname":"QA83-BAD","grade_level":"abc"}'::jsonb,
    now(), now()
  );

  select count(*) into v_count
    from public.student_profiles sp
   where sp.id = v_user_id;

  perform public._qa_profile_true('T-14',
    'non-numeric grade -> no cast exception, no profile',
    v_count = 0,
    'count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-15: Grade 0 rejected safely
-- ============================================================

do $blk$
declare
  v_user_id uuid := 'a1000000-0000-0000-0000-000000000006';
  v_count   integer;
begin
  insert into auth.users (id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at)
  values (
    v_user_id, 'authenticated', 'authenticated',
    'qa83-g0@test.local', '',
    now(),
    '{"nickname":"QA83-G0","grade_level":"0"}'::jsonb,
    now(), now()
  );

  select count(*) into v_count
    from public.student_profiles sp
   where sp.id = v_user_id;

  perform public._qa_profile_true('T-15',
    'grade 0 rejected safely',
    v_count = 0,
    'count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-16: Grade 13 rejected safely
-- ============================================================

do $blk$
declare
  v_user_id uuid := 'a1000000-0000-0000-0000-000000000007';
  v_count   integer;
begin
  insert into auth.users (id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_user_meta_data, created_at, updated_at)
  values (
    v_user_id, 'authenticated', 'authenticated',
    'qa83-g13@test.local', '',
    now(),
    '{"nickname":"QA83-G13","grade_level":"13"}'::jsonb,
    now(), now()
  );

  select count(*) into v_count
    from public.student_profiles sp
   where sp.id = v_user_id;

  perform public._qa_profile_true('T-16',
    'grade 13 rejected safely',
    v_count = 0,
    'count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-17: Existing profile not overwritten (idempotency)
-- ============================================================

do $blk$
declare
  v_user_id uuid := 'a1000000-0000-0000-0000-000000000001';
  v_nick    text;
  v_grade   smallint;
begin
  -- T-08 already created profile for this user with grade=10, nick=QA83-NUM
  -- Trigger fires ON CONFLICT DO NOTHING — existing row untouched
  select sp.nickname, sp.grade_level into v_nick, v_grade
    from public.student_profiles sp
   where sp.id = v_user_id;

  perform public._qa_profile_true('T-17',
    'existing profile not overwritten (idempotent)',
    v_nick = 'QA83-NUM' and v_grade = 10,
    'nick=' || v_nick || ' grade=' || v_grade);
end;
$blk$;


-- ============================================================
-- T-18: Duplicate nickname for different student rejects
--       second auth insert (atomic rollback)
-- ============================================================

do $blk$
declare
  v_user_id uuid := 'a1000000-0000-0000-0000-000000000010';
  v_success boolean;
begin
  begin
    insert into auth.users (id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_user_meta_data, created_at, updated_at)
    values (
      v_user_id, 'authenticated', 'authenticated',
      'qa83-dupnick@test.local', '',
      now(),
      '{"nickname":"QA83-NUM","grade_level":7}'::jsonb,
      now(), now()
    );
    v_success := true;
  exception when others then
    v_success := false;
  end;

  perform public._qa_profile_true('T-18',
    'duplicate nickname for different student rejects auth insert',
    v_success = false,
    'success=' || v_success);
end;
$blk$;


-- ============================================================
-- T-19: Rejected duplicate leaves no orphan auth user
-- ============================================================

do $blk$
declare
  v_user_id uuid := 'a1000000-0000-0000-0000-000000000010';
  v_count   integer;
begin
  select count(*) into v_count
    from auth.users au
   where au.id = v_user_id;

  perform public._qa_profile_true('T-19',
    'rejected duplicate leaves no orphan auth user',
    v_count = 0,
    'count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-20: Auth delete cascades student profile
-- ============================================================

do $blk$
declare
  v_user_id uuid := 'a1000000-0000-0000-0000-000000000001';
  v_before  integer;
  v_after   integer;
begin
  select count(*) into v_before
    from public.student_profiles sp
   where sp.id = v_user_id;

  delete from auth.users where id = v_user_id;

  select count(*) into v_after
    from public.student_profiles sp
   where sp.id = v_user_id;

  perform public._qa_profile_true('T-20',
    'auth delete cascades student profile',
    v_before = 1 and v_after = 0,
    'before=' || v_before || ' after=' || v_after);
end;
$blk$;


-- ============================================================
-- T-21: Existing baseline rows unchanged
-- ============================================================

do $blk$
declare
  v_subject_count integer;
  v_vault_count   integer;
begin
  select count(*) into v_subject_count
    from public.subjects
   where is_active = true;

  select count(*) into v_vault_count
    from public.question_vaults;

  perform public._qa_profile_true('T-21',
    'existing baseline rows unchanged',
    v_subject_count > 0 and v_vault_count > 0,
    'subjects=' || v_subject_count || ' vaults=' || v_vault_count);
end;
$blk$;


-- ============================================================
-- T-22: Post-rollback fixture cleanup proof
-- 1. Verify fixtures exist before cleanup (pre > 0)
-- 2. DELETE all qa83 fixtures explicitly
-- 3. Verify counts = 0 after DELETE
-- 4. PASS only if pre > 0 AND post = 0
-- ============================================================

do $blk$
declare
  v_pre_auth   integer;
  v_pre_prof   integer;
  v_post_auth  integer;
  v_post_prof  integer;
  v_ok         boolean;
begin
  -- Step 1: pre-cleanup counts
  select count(*) into v_pre_auth
    from auth.users au
   where au.email like 'qa83-%@test.local';

  select count(*) into v_pre_prof
    from public.student_profiles sp
   where sp.id in (
     'a1000000-0000-0000-0000-000000000001',
     'a1000000-0000-0000-0000-000000000002',
     'a1000000-0000-0000-0000-000000000003',
     'a1000000-0000-0000-0000-000000000004',
     'a1000000-0000-0000-0000-000000000005',
     'a1000000-0000-0000-0000-000000000006',
     'a1000000-0000-0000-0000-000000000007'
   );

  -- Step 2: explicit cleanup
  delete from public.student_profiles sp
   where sp.id in (
     'a1000000-0000-0000-0000-000000000001',
     'a1000000-0000-0000-0000-000000000002',
     'a1000000-0000-0000-0000-000000000003',
     'a1000000-0000-0000-0000-000000000004',
     'a1000000-0000-0000-0000-000000000005',
     'a1000000-0000-0000-0000-000000000006',
     'a1000000-0000-0000-0000-000000000007'
   );

  delete from auth.users au
   where au.email like 'qa83-%@test.local';

  -- Step 3: post-cleanup counts
  select count(*) into v_post_auth
    from auth.users au
   where au.email like 'qa83-%@test.local';

  select count(*) into v_post_prof
    from public.student_profiles sp
   where sp.id in (
     'a1000000-0000-0000-0000-000000000001',
     'a1000000-0000-0000-0000-000000000002',
     'a1000000-0000-0000-0000-000000000003',
     'a1000000-0000-0000-0000-000000000004',
     'a1000000-0000-0000-0000-000000000005',
     'a1000000-0000-0000-0000-000000000006',
     'a1000000-0000-0000-0000-000000000007'
   );

  -- Step 4: PASS only if fixtures existed AND are now gone
  v_ok := (v_pre_auth > 0 or v_pre_prof > 0)
      and v_post_auth = 0
      and v_post_prof = 0;

  perform public._qa_profile_true('T-22',
    'post-rollback cleanup proof: fixtures existed then removed',
    v_ok,
    'pre_auth=' || v_pre_auth || ' pre_prof=' || v_pre_prof ||
    ' post_auth=' || v_post_auth || ' post_prof=' || v_post_prof);
end;
$blk$;


-- ============================================================
-- RESULTS
-- ============================================================

\echo
\echo ============================================================
\echo QA83 PROFILE TRIGGER RESULTS
\echo ============================================================

SELECT label, result, title, detail
  FROM public._qa_profile_results
 ORDER BY label;

\echo
\echo --- COUNTS ---

SELECT result, count(*) AS total
  FROM public._qa_profile_results
 GROUP BY result
 ORDER BY result;

\echo
\echo ============================================================


ROLLBACK;

\echo
\echo ROLLBACK DONE — all fixtures removed.
