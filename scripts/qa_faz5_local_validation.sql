-- ============================================================
-- scripts/qa_faz5_local_validation.sql
-- Altin Kalemler - Migration Faz 5a yerel QA suite
--
-- Kapsam:
--   077 snapshot materializasyonu (prepare_competition_pack)
--   078 lig/rating motoru (_faz5_apply_competition_points)
--   079 giris noktalari (join/leave_matchmaking_queue)
--   080 hardening (search_path='' beyaz listesi)
--
-- Test haritasi:
--   T-01     : anon -> join_matchmaking_queue EXECUTE-denied
--   T-02     : ilk ogrenci kuyruga girer -> waiting (+expires_at)
--   T-03     : FIFO eslesme -> tek yarisma, question_count=5,
--              one_vs_one, slot1=once giren oyuncu
--   T-04     : bekleyen ikinci ogrenci leave -> cancelled=1
--   T-05..07 : pack hazirlama: 5 snapshot satiri (1..5 sirali,
--              zorluklar gecerli) + metadata; kasa ortusmesi;
--              replay RED
--   T-08     : hicbir eslesmede yer almayan D icin pack RED (42501)
--   T-08     : exposure yazimlari (kasa + soru bazli)
--   T-09     : dogrudan cevap simülasyonu + finalize ->
--              completed + results + winner (MVP #2 once bitiren)
--   T-10..11 : rating: kazanan +24 / kaybeden -12, before+delta=
--              after; tekrar finalize idempotent (2 kayit kalir)
--   T-12     : lig bandi gecisi: 95 puanla kazan -> promotion
--              history + yeni current uyelik (QA5-GUMUS)
--   T-13     : hardening: beyaz listede search_path=public kalmadi
--   T-14     : ACL: authenticated execute var / anon yok
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_faz5_local_validation.sql supabase_db_yarisma-programi:/tmp/
--   docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -f /tmp/qa_faz5_local_validation.sql
--
-- Guvence: suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR (faz4 deseninin aynisi)
-- ============================================================

create table public._qa_faz5_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_faz5_results
  to anon, authenticated, service_role;

create function public._qa5_expect(p_label text, p_title text, p_expect text, p_sql text)
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
      insert into public._qa_faz5_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_faz5_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_faz5_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_faz5_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa5_expect_msg(
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
    insert into public._qa_faz5_results
    values (p_label, p_title, 'FAIL',
            'hata beklenmisti ama uygulandi');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if v_state = p_state and upper(v_msg) like upper(p_msg_pattern) then
      insert into public._qa_faz5_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | mesaj eslesti');
    else
      insert into public._qa_faz5_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || p_state ||
              ' | msg=' || left(v_msg, 160));
    end if;
  end;
end;
$qa$;

create function public._qa5_true(p_label text, p_title text, p_ok boolean, p_detail text default null)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_faz5_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa5_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa5_expect_msg(text, text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa5_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR
-- matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
-- Sorularin correct_answer degerleri bilinir:
--   Q5-01='C'  Q5-02='A'  Q5-03='B'  Q5-04='D'  Q5-05='E'
-- ============================================================

insert into auth.users (id, email) values
  ('99999999-9999-9999-9999-999999999951', 'qa5-user-a@test.local'),
  ('99999999-9999-9999-9999-999999999952', 'qa5-user-b@test.local'),
  ('99999999-9999-9999-9999-999999999953', 'qa5-student@test.local'),
  ('99999999-9999-9999-9999-999999999954', 'qa5-user-d@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('99999999-9999-9999-9999-999999999951', 12, 'QA5-NICK-A'),
  ('99999999-9999-9999-9999-999999999952', 12, 'QA5-NICK-B'),
  ('99999999-9999-9999-9999-999999999953', 12, 'QA5-NICK-C'),
  ('99999999-9999-9999-9999-999999999954', 12, 'QA5-NICK-D');

-- Fixture ligleri sort_order 1/2: production seed bantlariyla
-- (bronze s10/0-999, silver s20/1000-2499 ...) çakışmaz; en düşük
-- sort sayesinde ilk üyelik ve band hedefi deterministik seçilir.
insert into public.leagues
  (league_code, name, sort_order, min_points, max_points, is_active) values
  ('QA5-BRONZ', 'QA5 Bronz', 1, 0, 99, true),
  ('QA5-GUMUS', 'QA5 Gümüş', 2, 100, null, true);

-- C ana yarisma öncesi mevcut üyeliğe sahip olsun (>=12 puan);
-- yoksa motor yeni üyelik açar ve -12 clamp ile 0 olarak yazılır.
insert into public.student_league_memberships
  (user_id, league_id, membership_scope,
   points_at_entry, current_points, is_current)
values
  ('99999999-9999-9999-9999-999999999953',
   (select id from public.leagues where league_code = 'QA5-BRONZ'),
   'general', 50, 50, true);

insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('88888888-8888-8888-7777-888888888805', 'QA5-Y-2099', 'MEB-QA5', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('77777777-7777-7777-6666-777777777705', 'QA5-SCHED', 'QA5 Profil',
   '88888888-8888-8888-7777-888888888805', true, true);

insert into public.academic_weeks (academic_year, week, starts_at, ends_at) values
  ('QA5-Y-2099', 5, current_date - 3, current_date + 4),
  ('QA5-Y-2099', 6, current_date + 4, current_date + 11);

insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('66666666-6666-6666-5555-000000000005',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   12, 'QA5 Islenmis Konu', 'qa5-islenmis',
   '88888888-8888-8888-7777-888888888805');

insert into public.subtopics (id, topic_id, name, slug) values
  ('55555555-5555-5555-4444-000000000005',
   '66666666-6666-6666-5555-000000000005',
   'QA5 Alt Konu', 'qa5-alt-konu');

insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
values
  ('33333333-3333-3333-9999-000000000051', 'Q5-01', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'C', true, 45),
  ('33333333-3333-3333-9999-000000000052', 'Q5-02', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'acik_uclu', 'A', true, 60),
  ('33333333-3333-3333-9999-000000000053', 'Q5-03', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'hard', 'comprehension', 'dogru_yanlis', 'B', true, 75),
  ('33333333-3333-3333-9999-000000000054', 'Q5-04', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'D', true, 40),
  ('33333333-3333-3333-9999-000000000055', 'Q5-05', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'bosluk_doldurma', 'E', true, 55);

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, subtopic_id, review_status)
select ('33333333-3333-3333-9999-0000000000' || n)::uuid,
       '88888888-8888-8888-7777-888888888805',
       '66666666-6666-6666-5555-000000000005',
       '55555555-5555-5555-4444-000000000005', 'approved'
  from unnest(array['51','52','53','54','55']) n;

-- one_v_one kasasi: TAM 5 aktif eligible uye (MVP #8).
insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('22222222-2222-2222-1111-000000000005', 'QA5-V-1V1',
   'QA5 1v1 Kasasi', 'one_v_one', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, one_v_one_eligible)
select '22222222-2222-2222-1111-000000000005',
       ('33333333-3333-3333-9999-0000000000' || n)::uuid, 'active', true
  from unnest(array['51','52','53','54','55']) n;


-- ============================================================
-- T-01: ANON EXECUTE DENIED
-- ============================================================

do $blk$
begin
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);

  perform public._qa5_expect('T-01',
    'anon: join_matchmaking_queue EXECUTE-denied',
    '42501',
    $sql$select public.join_matchmaking_queue(
      '430903f3-527e-4e12-b7e8-ac0afdb784aa')$sql$);

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$blk$;


-- ============================================================
-- T-02: ILK OGRENCI -> WAITING
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999953","role":"authenticated"}', true);

do $blk$
declare
  v_res jsonb;
begin
  select public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa') into v_res;

  perform public._qa5_true('T-02',
    'C kuyruga girer: status=waiting, expires_at tanimli',
    v_res ->> 'status' = 'waiting'
      and exists (
        select 1 from public.matchmaking_queue mq
         where mq.user_id = '99999999-9999-9999-9999-999999999953'
           and mq.status = 'waiting'
           and mq.expires_at is not null),
    'status=' || coalesce(v_res ->> 'status', '?'));
end;
$blk$;


-- ============================================================
-- T-03: FIFO ESLESME -> TEK YARISMA (q_count=5, one_vs_one)
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999951","role":"authenticated"}', true);

do $blk$
declare
  v_res jsonb;
  v_comp uuid;
begin
  select public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa') into v_res;

  v_comp := (v_res ->> 'competition_id')::uuid;

  perform public._qa5_true('T-03',
    'A+C eslesti: yarisma kurulu (count=5, one_vs_one, slot1=C)',
    v_res ->> 'status' = 'matched'
      and v_comp is not null
      and exists (
        select 1 from public.competitions c
         where c.id = v_comp
           and c.question_count = 5
           and c.competition_type = 'one_vs_one'
           and c.status = 'waiting')
      and exists (
        select 1 from public.competition_players cp
         where cp.competition_id = v_comp
           and cp.player_slot = 1
           and cp.user_id = '99999999-9999-9999-9999-999999999953')
      and exists (
        select 1 from public.competition_players cp
         where cp.competition_id = v_comp
           and cp.player_slot = 2
           and cp.user_id = '99999999-9999-9999-9999-999999999951')
      and not exists (
        select 1 from public.matchmaking_queue mq
         where mq.status = 'waiting'),
    'comp=' || coalesce(v_comp::text, 'yok'));

  -- Sonraki testler icin yarisma id'sini oturum degiskenine tasi.
  perform set_config('qa5.comp_id', coalesce(v_comp::text, ''), false);
end;
$blk$;


-- ============================================================
-- T-04: BEKLEYEN IKINCI OGRENCI + LEAVE
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999952","role":"authenticated"}', true);

do $blk$
declare
  v_res jsonb;
  v_leave jsonb;
begin
  select public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa') into v_res;

  select public.leave_matchmaking_queue() into v_leave;

  perform public._qa5_true('T-04',
    'B waiting sonrası leave: cancelled=1, kuyruk bos',
    v_res ->> 'status' = 'waiting'
      and v_leave ->> 'cancelled' = '1'
      and not exists (
        select 1 from public.matchmaking_queue mq
         where mq.user_id = '99999999-9999-9999-9999-999999999952'
           and mq.status = 'waiting'));
end;
$blk$;


-- ============================================================
-- T-05..08: PACK AUTO-PREPARE (082) + MATERIALIZASYON + EXPOSURE
-- (A kimliğiyle devam; qa5.comp_id oturum değişkeninden okunur)
-- 082: pack join_matchmaking_queue icinde otomatik hazirlanir;
--      manuel prepare_competition_pack cagrisi kaldirildi.
-- ============================================================

select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999951","role":"authenticated"}', true);

do $blk$
declare
  v_comp   uuid := nullif(current_setting('qa5.comp_id', true), '')::uuid;
  v_qcount integer;
  v_unique boolean;
  v_diff_ok boolean;
  v_vault  uuid;
begin
  -- 082: pack join_matchmaking_queue icinde otomatik hazirlanir.
  select count(*) into v_qcount
    from public.competition_questions cq
   where cq.competition_id = v_comp;

  select count(distinct cq.question_order) = 5 into v_unique
    from public.competition_questions cq
   where cq.competition_id = v_comp;

  select not exists (
    select 1 from public.competition_questions cq
     where cq.competition_id = v_comp
       and cq.difficulty not in ('easy','medium','hard')
  ) into v_diff_ok;

  perform public._qa5_true('T-05',
    'pack otomatik hazirlandi: 5 snapshot satiri (1..5, zorluklar gecerli)',
    v_qcount = 5 and v_unique and v_diff_ok,
    'qcount=' || v_qcount || ' unique=' || v_unique);

  -- Snapshot soru seti kasadaki eligible setin alt kümesi mi?
  select qv.id into v_vault
    from public.question_vaults qv
   where qv.vault_type = 'one_v_one'
     and qv.grade_level = 12
     and qv.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa'
   order by qv.created_at asc
   limit 1;

  perform public._qa5_true('T-06',
    'snapshot sorulari kasa uyeligiyle ortusuyor (5/5)',
    not exists (
      select 1 from public.competition_questions cq
       where cq.competition_id = v_comp
         and not exists (
           select 1 from public.question_vault_memberships m
            where m.vault_id = v_vault
              and m.question_id = cq.question_id
              and m.membership_status = 'active'
              and m.one_v_one_eligible = true)));
end;
$blk$;

select public._qa5_expect_msg('T-07',
  'replay: tekrar prepare RED (snapshot degistirilemez)',
  format($sql$select public.prepare_competition_pack(
           %L::uuid)$sql$,
         current_setting('qa5.comp_id', true)),
  'P0001', '%zaten olusturulmus%');

do $blk$
declare
  v_comp_deny uuid;
begin
  -- 077 akisinda 'snapshot zaten var / paket zaten secildi'
  -- kontrolleri katilim kontrolunden ONCE gelir; ana yarisma
  -- T-05'te hazirlandigi icin reddin izole kaniti icin
  -- snapshot/paket icermeyen bir 'waiting' yarisma kullanilir.
  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count)
  values
    ('F5-QA-T08', 'one_vs_one', 12,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'waiting', 5)
  returning id into v_comp_deny;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999954","role":"authenticated"}', true);

  perform public._qa5_expect('T-08',
    'katilimci olmayan D pack hazirlayamaz (42501)',
    '42501',
    format($sql$select public.prepare_competition_pack(%L::uuid)$sql$,
           v_comp_deny));

  execute 'reset role';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999951","role":"authenticated"}', true);
end;
$blk$;

do $blk$
declare
  v_comp uuid := nullif(current_setting('qa5.comp_id', true), '')::uuid;
begin
  perform public._qa5_true('T-09',
    'exposure yazildi: iki oyuncu icin kasa + soru bazli',
    (select count(*) from public.student_pack_exposures pe
      where pe.vault_id = '22222222-2222-2222-1111-000000000005') = 2
      and (select count(*) from public.student_question_exposures qe
            where qe.attempt_context = 'one_v_one'
              and qe.question_id between '33333333-3333-3333-9999-000000000051'
                                    and '33333333-3333-3333-9999-000000000055') > 0,
    format('pack=%s',
           (select count(*) from public.student_pack_exposures pe
             where pe.vault_id = '22222222-2222-2222-1111-000000000005')));
end;
$blk$;


-- ============================================================
-- T-10..11: CEVAP SIMULASYONU + FINALIZE + RATING MOTORU
-- (postgres olarak dogrudan cevap yazimi; akis RPC zinciri
--  Faz 3'te kanitlandi, burada yalniz Faz5 motoru izole edilir)
-- ============================================================

do $blk$
declare
  v_comp uuid := nullif(current_setting('qa5.comp_id', true), '')::uuid;
begin
  -- A 5/5 dogru (300 puanlik bant), C 2 dogru 3 yanlis.
  with qs as (
    select cq.id as cq_id, cq.question_order
      from public.competition_questions cq
     where cq.competition_id = v_comp
  )
  insert into public.competition_answers
    (competition_id, competition_question_id, user_id,
     submitted_answer, answer_result,
     sent_at, deadline_at, time_ms, points_awarded, server_validated)
  select v_comp, qs.cq_id,
         '99999999-9999-9999-9999-999999999951',
         'A', 'correct',
         now() - interval '10 seconds', now(),
         10000, 60, true
    from qs;

  with qs as (
    select cq.id as cq_id, cq.question_order
      from public.competition_questions cq
     where cq.competition_id = v_comp
  )
  insert into public.competition_answers
    (competition_id, competition_question_id, user_id,
     submitted_answer, answer_result,
     sent_at, deadline_at, time_ms, points_awarded, server_validated)
  select v_comp, qs.cq_id,
         '99999999-9999-9999-9999-999999999953',
         case when qs.question_order <= 2 then 'B' else 'C' end,
         case when qs.question_order <= 2 then 'correct' else 'wrong' end,
         now() - interval '10 seconds', now(),
         10000,
         case when qs.question_order <= 2 then 60 else 0 end,
         true
    from qs;

  update public.competition_players cp
     set total_points = case when cp.user_id =
              '99999999-9999-9999-9999-999999999951' then 300 else 120 end,
         correct_count = case when cp.user_id =
              '99999999-9999-9999-9999-999999999951' then 5 else 2 end,
         wrong_count = case when cp.user_id =
              '99999999-9999-9999-9999-999999999951' then 0 else 3 end,
         status = 'finished',
         finished_at = now()
   where cp.competition_id = v_comp;
end;
$blk$;

do $blk$
declare
  v_comp uuid := nullif(current_setting('qa5.comp_id', true), '')::uuid;
begin
  perform public.finalize_competition_if_ready(v_comp);

  perform public._qa5_true('T-10',
    'finalize: completed + results + winner=A (win_loss)',
    exists (
      select 1 from public.competitions c
       where c.id = v_comp
         and c.status = 'completed'
         and c.winner_user_id = '99999999-9999-9999-9999-999999999951')
      and exists (
        select 1 from public.competition_results cr
         where cr.competition_id = v_comp
           and cr.result_type = 'win_loss'));

  perform public._qa5_true('T-11',
    'rating: A +24 / C -12 ve before+change=after',
    (select count(*) = 2
       from public.competition_point_changes cpc
      where cpc.competition_id = v_comp
        and cpc.change_type = 'rating')
      and exists (
        select 1 from public.competition_point_changes cpc
         where cpc.competition_id = v_comp
           and cpc.user_id = '99999999-9999-9999-9999-999999999951'
           and cpc.points_change = 24
           and cpc.points_before + cpc.points_change = cpc.points_after)
      and exists (
        select 1 from public.competition_point_changes cpc
         where cpc.competition_id = v_comp
           and cpc.user_id = '99999999-9999-9999-9999-999999999953'
           and cpc.points_change = -12
           and cpc.points_after >= 0));

  -- Idempotency: tekrar finalize yeni rating yazmamali.
  perform public.finalize_competition_if_ready(v_comp);

  perform public._qa5_true('T-12',
    'idempotent finalize: hala 2 rating kaydi, uyelikte tek guncelleme',
    (select count(*) from public.competition_point_changes cpc
      where cpc.competition_id = v_comp
        and cpc.change_type = 'rating') = 2
      and (select count(*) from public.student_league_memberships m
            where m.user_id in (
              '99999999-9999-9999-9999-999999999951',
              '99999999-9999-9999-9999-999999999953')
              and m.is_current) = 2);
end;
$blk$;


-- ============================================================
-- T-13: LIG BANDI GECISI (promotion unit testi)
-- A=95 puan (QA5-BRONZ max 99); ikinci mini yarismayi kazanir
-- -> QA5-GUMUS'e promotion history + yeni current uyelik.
-- ============================================================

do $blk$
declare
  v_comp2 uuid;
  v_member_a uuid;
begin
  select m.id into v_member_a
    from public.student_league_memberships m
   where m.user_id = '99999999-9999-9999-9999-999999999951'
     and m.is_current;

  update public.student_league_memberships m
     set current_points = 95
   where m.id = v_member_a;

  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count,
     winner_user_id)
  values
    ('F5-QA-T13', 'one_vs_one', 12,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'completed', 5,
     '99999999-9999-9999-9999-999999999951')
  returning id into v_comp2;

  insert into public.competition_players
    (competition_id, user_id, player_slot, total_points, status)
  values
    (v_comp2, '99999999-9999-9999-9999-999999999951', 1, 250, 'finished'),
    (v_comp2, '99999999-9999-9999-9999-999999999953', 2, 80, 'finished');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type,
     player_results, calculated_at)
  values
    (v_comp2, '99999999-9999-9999-9999-999999999951', 'win_loss',
     '[]'::jsonb, now());

  perform public._faz5_apply_competition_points(v_comp2);

  perform public._qa5_true('T-13',
    'promotion: 95+24 -> QA5-GUMUS uyeligi + history kaydi',
    exists (
      select 1 from public.student_league_memberships m
       join public.leagues l on l.id = m.league_id
      where m.user_id = '99999999-9999-9999-9999-999999999951'
        and m.is_current
        and l.league_code = 'QA5-GUMUS'
        and m.current_points = 119)
      and exists (
        select 1 from public.student_league_history h
         join public.leagues lto on lto.id = h.to_league_id
        where h.user_id = '99999999-9999-9999-9999-999999999951'
          and lto.league_code = 'QA5-GUMUS'
           and h.transition_type = 'promotion'
           and h.points_at_transition = 119));
end;
$blk$;


-- ============================================================
-- T-14: HARDENING DOGRULAMASI (080)
-- ============================================================

select public._qa5_true('T-14',
  'hardening: beyaz listede search_path=public birakilmadi',
  not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prosecdef = true
       and p.proconfig is not null
       and 'search_path=public' = any (p.proconfig)
       and lower(p.proname) = any (array[
         'is_competition_participant',
         'get_internal_correct_answer',
         'resolve_competition_time_band',
         'resolve_competition_points',
         'recalculate_competition_player_score',
         'finalize_competition_if_ready',
         'submit_competition_answer',
         'get_competition_question_payload',
         'resolve_competition_question_time_limit',
         'release_competition_question',
         'set_competition_player_ready',
         'create_missing_competition_timeouts',
         'advance_competition_progress',
         'sync_competition_state',
         'after_competition_answer_progress',
         'get_current_competition_question',
         'validate_competition_question_limit',
         'snapshot_competition_answer_band_name'])));

do $blk$
declare
  v_join_auth boolean;
  v_join_anon boolean;
  v_leave_auth boolean;
begin
  select has_function_privilege('authenticated', p.oid, 'EXECUTE'),
         has_function_privilege('anon', p.oid, 'EXECUTE')
    into v_join_auth, v_join_anon
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'join_matchmaking_queue';

  select bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
    into v_leave_auth
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'leave_matchmaking_queue';

  perform public._qa5_true('T-15',
    'ACL: authenticated evet / anon hayir (join+leave)',
    v_join_auth and not v_join_anon and coalesce(v_leave_auth, false));
end;
$blk$;


-- ============================================================
-- RAPOR
-- ============================================================

\echo
\echo ===== FAZ5 QA SONUCLARI =====
select label, title, result,
       coalesce(detail, '-') as detail
  from public._qa_faz5_results
 order by label;

\echo
select format('OZET: %s PASS / %s FAIL',
       count(*) filter (where result = 'PASS'),
       count(*) filter (where result = 'FAIL')) as ozet
  from public._qa_faz5_results;

rollback;
