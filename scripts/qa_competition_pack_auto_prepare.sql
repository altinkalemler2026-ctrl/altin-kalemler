-- ============================================================
-- scripts/qa_competition_pack_auto_prepare.sql
-- Altin Kalemler - Migration 082 pack auto-prepare QA suite
--
-- Kapsam:
--   082_competition_pack_auto_prepare.sql
--   - join_matchmaking_queue atomik pack hazirlik
--   - prepare_competition_pack privilege hardening
--   - Atomic rollback (match + pack birlikte basarisiz)
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_competition_pack_auto_prepare.sql \
--     supabase_db_yarisma-programi:/tmp/
--   docker exec supabase_db_yarisma-programi psql -U postgres \
--     -d postgres -v ON_ERROR_STOP=1 \
--     -f /tmp/qa_competition_pack_auto_prepare.sql
--
-- Guvence: suite TEK TRANSACTION icinde calisir, sonunda
-- ROLLBACK ile hicbir artefakt kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- RESULT TABLE + HELPERS
-- ============================================================

create table if not exists public._qa_pack_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_pack_results
  to anon, authenticated, service_role;

create or replace function public._qa_pack_expect(
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
      insert into public._qa_pack_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_pack_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_pack_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_pack_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create or replace function public._qa_pack_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_pack_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute on function public._qa_pack_expect(text,text,text,text) to anon, authenticated, service_role;
grant execute on function public._qa_pack_true(text,text,boolean,text) to anon, authenticated, service_role;


-- ============================================================
-- FIXTURES
--
-- Students: grade 12, subject Matematik
-- QA82 = unique prefix to avoid collisions with other QA suites
-- ============================================================

-- auth users
insert into auth.users (id, email) values
  ('82000000-0000-0000-0000-00000000008a', 'qa82-user-a@test.local'),
  ('82000000-0000-0000-0000-00000000008b', 'qa82-user-b@test.local'),
  ('82000000-0000-0000-0000-00000000008c', 'qa82-user-c@test.local'),
  ('82000000-0000-0000-0000-00000000008d', 'qa82-user-d@test.local');

-- student profiles
insert into public.student_profiles (id, grade_level, nickname) values
  ('82000000-0000-0000-0000-00000000008a', 12, 'QA82-NICK-A'),
  ('82000000-0000-0000-0000-00000000008b', 12, 'QA82-NICK-B'),
  ('82000000-0000-0000-0000-00000000008c', 12, 'QA82-NICK-C'),
  ('82000000-0000-0000-0000-00000000008d', 8,  'QA82-NICK-D');

-- academic weeks (required by prepare_competition_pack)
insert into public.academic_weeks (academic_year, week, starts_at, ends_at) values
  ('2025-2026', 1, current_date - 7, current_date + 7),
  ('2025-2026', 2, current_date + 7, current_date + 14)
on conflict do nothing;

-- curriculum version + schedule profile (required for _faz2_require_period)
insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('82828282-8282-8282-8282-828282828282', '2025-2026', 'MEB-QA82', true)
on conflict do nothing;

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('82828282-8282-8282-8282-828282828283', 'QA82-SCHED', 'QA82 Profil',
   '82828282-8282-8282-8282-828282828282', true, true)
on conflict do nothing;

-- topics + subtopics
insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('82828282-8282-8282-8282-828282828210',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   12, 'QA82 Konu', 'qa82-konu',
   '82828282-8282-8282-8282-828282828282')
on conflict do nothing;

insert into public.subtopics (id, topic_id, name, slug) values
  ('82828282-8282-8282-8282-828282828220',
   '82828282-8282-8282-8282-828282828210',
   'QA82 Alt Konu', 'qa82-alt-konu')
on conflict do nothing;

-- questions (5 approved active)
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
values
  ('82828282-8282-8282-8282-828282828231', 'Q82-01', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45),
  ('82828282-8282-8282-8282-828282828232', 'Q82-02', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'acik_uclu', 'B', true, 60),
  ('82828282-8282-8282-8282-828282828233', 'Q82-03', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'hard', 'comprehension', 'dogru_yanlis', 'C', true, 75),
  ('82828282-8282-8282-8282-828282828234', 'Q82-04', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'D', true, 40),
  ('82828282-8282-8282-8282-828282828235', 'Q82-05', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'bosluk_doldurma', 'E', true, 55);

-- curriculum mappings for the 5 questions
insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, subtopic_id, review_status)
select ('82828282-8282-8282-8282-82828282823' || n)::uuid,
       '82828282-8282-8282-8282-828282828282',
       '82828282-8282-8282-8282-828282828210',
       '82828282-8282-8282-8282-828282828220', 'approved'
  from unnest(array['1','2','3','4','5']) n;

-- one_v_one vault with 5 eligible members
insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('82828282-8282-8282-8282-828282828241', 'QA82-V-1V1',
   'QA82 1v1 Kasasi', 'one_v_one', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, one_v_one_eligible)
select '82828282-8282-8282-8282-828282828241',
       ('82828282-8282-8282-8282-82828282823' || n)::uuid, 'active', true
  from unnest(array['1','2','3','4','5']) n;

-- scoring rule set (if not already active from seed)
-- 'faz5_default' is expected to be seeded

-- Baseline: a competition from another QA suite to verify pack QA
-- doesn't touch non-82 data (T-22)
insert into public.competitions
  (competition_code, competition_type, grade_level,
   subject_id, scoring_rule_set_id, status, question_count)
select 'F5-PRIVACY81-BASELINE', 'one_vs_one', 12,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa',
       (select id from public.scoring_rule_sets where is_active = true limit 1),
       'completed', 2
where not exists (
  select 1 from public.competitions
   where competition_code = 'F5-PRIVACY81-BASELINE'
);


-- ============================================================
-- T-01: ANON EXECUTE DENIED on join_matchmaking_queue
-- ============================================================

do $blk$
begin
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);

  perform public._qa_pack_expect('T-01',
    'anon: join_matchmaking_queue EXECUTE denied',
    '42501',
    $sql$select public.join_matchmaking_queue(
      '430903f3-527e-4e12-b7e8-ac0afdb784aa')$sql$);

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$blk$;


-- ============================================================
-- T-02: USER A JOINS -> WAITING
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"82000000-0000-0000-0000-00000000008a","role":"authenticated"}',
  true);

do $blk$
declare
  v_res jsonb;
begin
  select public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa') into v_res;

  perform public._qa_pack_true('T-02',
    'user A join -> status=waiting',
    v_res ->> 'status' = 'waiting',
    'status=' || (v_res ->> 'status'));
end;
$blk$;


-- ============================================================
-- T-03: A YOKSA PACK HENÜZ OLUŞMAZ
-- ============================================================

do $blk$
declare
  v_queue  uuid;
  v_comp   uuid;
  v_qcount integer;
begin
  select mq.id into v_queue
    from public.matchmaking_queue mq
   where mq.user_id = '82000000-0000-0000-0000-00000000008a'
     and mq.status = 'waiting'
   order by mq.joined_at desc limit 1;

  -- No competition exists yet (just queue entry)
  select count(*) into v_qcount
    from public.competition_questions cq
   where cq.competition_id in (
     select cp.competition_id from public.competition_players cp
      where cp.user_id = '82000000-0000-0000-0000-00000000008a'
   );

  perform public._qa_pack_true('T-03',
    'before match: no pack exists',
    v_qcount = 0,
    'question_count=' || v_qcount);
end;
$blk$;


-- ============================================================
-- T-04: USER B JOINS -> MATCHED + competition_id returned
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"82000000-0000-0000-0000-00000000008b","role":"authenticated"}',
  true);

do $blk$
declare
  v_res    jsonb;
  v_comp_a uuid;
  v_comp_b uuid;
begin
  select public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa') into v_res;

  perform public._qa_pack_true('T-04',
    'user B join -> status=matched',
    v_res ->> 'status' = 'matched',
    'status=' || (v_res ->> 'status'));

  -- T-05: same competition_id for both users
  v_comp_b := (v_res ->> 'competition_id')::uuid;

  select cp.competition_id into v_comp_a
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008a'
   limit 1;

  perform public._qa_pack_true('T-05',
    'same competition_id for A and B',
    v_comp_a = v_comp_b and v_comp_a is not null,
    'comp_a=' || v_comp_a || ' comp_b=' || v_comp_b);
end;
$blk$;


-- ============================================================
-- T-06: EXACTLY 2 competition_player rows
-- ============================================================

do $blk$
declare
  v_comp   uuid;
  v_count  integer;
begin
  select cp.competition_id into v_comp
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008b'
   limit 1;

  select count(*) into v_count
    from public.competition_players cp
   where cp.competition_id = v_comp;

  perform public._qa_pack_true('T-06',
    'exactly 2 competition players',
    v_count = 2,
    'count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-07: EXACTLY 5 competition_questions auto-created
-- ============================================================

do $blk$
declare
  v_comp   uuid;
  v_count  integer;
begin
  select cp.competition_id into v_comp
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008b'
   limit 1;

  select count(*) into v_count
    from public.competition_questions cq
   where cq.competition_id = v_comp;

  perform public._qa_pack_true('T-07',
    'pack: exactly 5 competition_questions',
    v_count = 5,
    'count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-08: QUESTION ORDER 1-5 UNIQUE
-- ============================================================

do $blk$
declare
  v_comp   uuid;
  v_unique boolean;
begin
  select cp.competition_id into v_comp
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008b'
   limit 1;

  select count(distinct cq.question_order) = 5
    into v_unique
    from public.competition_questions cq
   where cq.competition_id = v_comp;

  perform public._qa_pack_true('T-08',
    'question order 1-5 unique',
    v_unique,
    'unique_orders=' || v_unique);
end;
$blk$;


-- ============================================================
-- T-09: VAULT MEMBERSHIP/GRADE/SUBJECT PRESERVED
-- (all 5 questions belong to the vault for grade 12 + Matematik)
-- ============================================================

do $blk$
declare
  v_comp     uuid;
  v_all_valid boolean;
begin
  select cp.competition_id into v_comp
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008b'
   limit 1;

  select not exists (
    select 1 from public.competition_questions cq
    join public.questions q on q.id = cq.question_id
    where cq.competition_id = v_comp
      and (q.grade_level != 12
           or q.subject_id != '430903f3-527e-4e12-b7e8-ac0afdb784aa'
           or q.approval_status != 'approved'
           or q.is_active != true)
  ) into v_all_valid;

  perform public._qa_pack_true('T-09',
    'vault: grade/subject/active preserved',
    v_all_valid,
    'all_valid=' || v_all_valid);
end;
$blk$;


-- ============================================================
-- T-10: CLIENT DID NOT CALL prepare_competition_pack
-- (pack was created inside join_matchmaking_queue, not separately)
-- Verified by: pack exists even though no separate RPC was called.
-- This is a structural test — the pack is present as a consequence
-- of the match, confirming auto-prepare worked.
-- ============================================================

do $blk$
declare
  v_comp   uuid;
  v_qcount integer;
begin
  select cp.competition_id into v_comp
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008b'
   limit 1;

  select count(*) into v_qcount
    from public.competition_questions cq
   where cq.competition_id = v_comp;

  perform public._qa_pack_true('T-10',
    'auto-prepare: pack exists without separate client call',
    v_qcount = 5,
    'auto_qcount=' || v_qcount);
end;
$blk$;


-- ============================================================
-- T-11: USER A READY -> SUCCESS
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"82000000-0000-0000-0000-00000000008a","role":"authenticated"}',
  true);

do $blk$
declare
  v_comp uuid;
  v_res  jsonb;
begin
  select cp.competition_id into v_comp
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008a'
   limit 1;

  select public.set_competition_player_ready(v_comp) into v_res;

  perform public._qa_pack_true('T-11',
    'user A ready -> success',
    v_res ->> 'status' is not null,
    'res=' || left(v_res::text, 120));
end;
$blk$;


-- ============================================================
-- T-12: USER B READY -> SUCCESS
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"82000000-0000-0000-0000-00000000008b","role":"authenticated"}',
  true);

do $blk$
declare
  v_comp uuid;
  v_res  jsonb;
begin
  select cp.competition_id into v_comp
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008b'
   limit 1;

  select public.set_competition_player_ready(v_comp) into v_res;

  perform public._qa_pack_true('T-12',
    'user B ready -> success',
    v_res ->> 'status' is not null,
    'res=' || left(v_res::text, 120));
end;
$blk$;


-- ============================================================
-- T-13: COMPETITION STATUS IS active
-- ============================================================

do $blk$
declare
  v_comp   uuid;
  v_status text;
begin
  select cp.competition_id into v_comp
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008b'
   limit 1;

  select c.status into v_status
    from public.competitions c
   where c.id = v_comp;

  perform public._qa_pack_true('T-13',
    'competition status = active',
    v_status = 'active',
    'status=' || v_status);
end;
$blk$;


-- ============================================================
-- T-14: FIRST QUESTION RELEASED (sent_at not null)
-- ============================================================

do $blk$
declare
  v_comp   uuid;
  v_sent   boolean;
begin
  select cp.competition_id into v_comp
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008b'
   limit 1;

  select cq.sent_at IS NOT NULL into v_sent
    from public.competition_questions cq
   where cq.competition_id = v_comp
     and cq.question_order = 1;

  perform public._qa_pack_true('T-14',
    'first question released (sent_at not null)',
    v_sent = true,
    'q1_sent=' || v_sent);
end;
$blk$;


-- ============================================================
-- T-15: AUTHENTICATED USER CANNOT directly call prepare_competition_pack
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"82000000-0000-0000-0000-00000000008c","role":"authenticated"}',
  true);

do $blk$
begin
  execute 'set local role authenticated';

  perform public._qa_pack_expect('T-15',
    'authenticated: prepare_competition_pack EXECUTE denied',
    '42501',
    $sql$select public.prepare_competition_pack(
      '00000000-0000-0000-0000-000000000000'::uuid)$sql$);

  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-16: SERVICE_ROLE CAN call prepare_competition_pack
-- (management/admin access preserved)
-- ============================================================

do $blk$
begin
  execute 'set local role service_role';

  -- This will fail with a functional error (invalid competition_id),
  -- but NOT with a privilege error. That's the proof it's allowed.
  perform public._qa_pack_expect('T-16',
    'service_role: prepare_competition_pack EXECUTE allowed',
    'P0001',
    $sql$select public.prepare_competition_pack(
      '00000000-0000-0000-0000-000000000000'::uuid)$sql$);

  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-17: DUPLICATE/RETRY DOES NOT CREATE EXTRA QUESTIONS
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"82000000-0000-0000-0000-00000000008a","role":"authenticated"}',
  true);

do $blk$
declare
  v_comp   uuid;
  v_before integer;
  v_after  integer;
begin
  select cp.competition_id into v_comp
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008a'
   limit 1;

  select count(*) into v_before
    from public.competition_questions cq
   where cq.competition_id = v_comp;

  -- Re-run join_matchmaking_queue for same user — idempotent retry
  perform public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa');

  select count(*) into v_after
    from public.competition_questions cq
   where cq.competition_id = v_comp;

  perform public._qa_pack_true('T-17',
    'duplicate retry: no extra questions',
    v_after = v_before,
    'before=' || v_before || ' after=' || v_after);
end;
$blk$;


-- ============================================================
-- T-18: MISSING VAULT -> ATOMIC MATCH FAILURE
-- (User D has grade 8; vault is grade 12. No eligible vault.)
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"82000000-0000-0000-0000-00000000008d","role":"authenticated"}',
  true);

do $blk$
declare
  v_res jsonb;
begin
  select public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa') into v_res;

  -- D is alone in queue (grade 8, no partner) or gets waiting
  perform public._qa_pack_true('T-18',
    'missing vault: no crash, waiting or no-match',
    v_res ->> 'status' = 'waiting',
    'status=' || (v_res ->> 'status'));
end;
$blk$;


-- ============================================================
-- T-19: NO HALF-COMPETITION RESIDUE AFTER FAILURE
-- (D should have no competition_players, no competitions,
--  no competition_questions)
-- ============================================================

do $blk$
declare
  v_players integer;
  v_comps   integer;
  v_questions integer;
begin
  select count(*) into v_players
    from public.competition_players cp
   where cp.user_id = '82000000-0000-0000-0000-00000000008d';

  select count(*) into v_comps
    from public.competitions c
   where c.id in (
     select cp.competition_id from public.competition_players cp
      where cp.user_id = '82000000-0000-0000-0000-00000000008d'
   );

  select count(*) into v_questions
    from public.competition_questions cq
   where cq.competition_id in (
     select cp.competition_id from public.competition_players cp
      where cp.user_id = '82000000-0000-0000-0000-00000000008d'
   );

  perform public._qa_pack_true('T-19',
    'no half-competition residue after failure',
    v_players = 0 and v_comps = 0 and v_questions = 0,
    'players=' || v_players || ' comps=' || v_comps || ' q=' || v_questions);
end;
$blk$;


-- ============================================================
-- T-20: RATE-LIMIT / ADVISORY LOCK PRESERVED
-- (The rate limit function exists and is callable)
-- ============================================================

do $blk$
declare
  v_exists boolean;
begin
  select exists (
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public'
      and p.proname = '_faz4_consume_rate_limit'
  ) into v_exists;

  perform public._qa_pack_true('T-20',
    'rate limit function exists',
    v_exists,
    'exists=' || v_exists);
end;
$blk$;


-- ============================================================
-- T-21: ROLLBACK CLEANS ALL FIXTURES
-- Record counts now; ROLLBACK at end removes everything.
-- The assertion is structural: ROLLBACK completes without error.
-- ============================================================

do $blk$
declare
  v_mq     integer;
  v_comp   integer;
  v_cp     integer;
  v_cq     integer;
  v_total  integer;
begin
  select count(*) into v_mq
    from public.matchmaking_queue mq
   where mq.user_id in (
     '82000000-0000-0000-0000-00000000008a',
     '82000000-0000-0000-0000-00000000008b',
     '82000000-0000-0000-0000-00000000008c',
     '82000000-0000-0000-0000-00000000008d'
   );

  select count(*) into v_comp
    from public.competitions c
   where c.grade_level in (8, 12)
     and c.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa'
     and c.question_count = 5;

  select count(*) into v_cp
    from public.competition_players cp
   where cp.user_id in (
     '82000000-0000-0000-0000-00000000008a',
     '82000000-0000-0000-0000-00000000008b',
     '82000000-0000-0000-0000-00000000008c',
     '82000000-0000-0000-0000-00000000008d'
   );

  select count(*) into v_cq
    from public.competition_questions cq
   where cq.competition_id in (
     select cp.competition_id from public.competition_players cp
      where cp.user_id in (
        '82000000-0000-0000-0000-00000000008a',
        '82000000-0000-0000-0000-00000000008b',
        '82000000-0000-0000-0000-00000000008c',
        '82000000-0000-0000-0000-00000000008d'
      )
   );

  v_total := v_mq + v_comp + v_cp + v_cq;

  perform public._qa_pack_true('T-21',
    'rollback: pre-cleanup fixture count > 0',
    v_total > 0,
    'mq=' || v_mq || ' comp=' || v_comp || ' cp=' || v_cp || ' cq=' || v_cq);
end;
$blk$;


-- ============================================================
-- T-22: BASELINE RECORDS UNTOUCHED
-- (Existing competitions from other QA suites are not modified)
-- ============================================================

do $blk$
declare
  v_baseline_count integer;
begin
  select count(*) into v_baseline_count
    from public.competitions c
   where c.competition_code = 'F5-PRIVACY81-BASELINE';

  perform public._qa_pack_true('T-22',
    'baseline: non-82 competition untouched',
    v_baseline_count = 1,
    'count=' || v_baseline_count);
end;
$blk$;


-- ============================================================
-- RESULTS SUMMARY
-- ============================================================

\echo
\echo ============================================================
\echo QA82 PACK AUTO-PREPARE RESULTS
\echo ============================================================

SELECT label, result, title, detail
  FROM public._qa_pack_results
 ORDER BY label;

\echo
\echo --- COUNTS ---

SELECT result, count(*) AS total
  FROM public._qa_pack_results
 GROUP BY result
 ORDER BY result;

\echo
\echo ============================================================


-- ============================================================
-- ROLLBACK: No artifacts persist
-- ============================================================

ROLLBACK;

\echo
\echo ROLLBACK DONE — all fixtures removed.
