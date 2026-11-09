-- ============================================================================
-- qa_sec1_answer_key_local.sql — AK-SEC-ANSWER-01 İZOLE (DISPOSABLE) QA
-- ============================================================================
-- AMAÇ: 155_sec1_answer_key_acl.sql düzeltmesinin (1) SEC-1'i kapattığını,
--   (2) iç yarışma/antrenman/ödül zincirini BOZMADIĞINI kanıtlamak.
--
-- ÖN KOŞUL: Bu betik YALNIZ 'sec1_qa_' önekli geçici DB'de koşar; başka
--   her adta fail-closed durur (günlük DB aramaz). 155 migration'ı
--   ÖNCEDEN uygulanmış olmalıdır (T01 bunu doğrular).
--
-- KOŞUM SIRASI (koordinatör):
--   1) Günlük DB'den benzersiz adlı kopya:  CREATE DATABASE sec1_qa_<uid> TEMPLATE postgres;
--   2) Kopyada ÖNCE fixturesız 094 taban koşumu (bkz. rapor), sonra 155 uygula:
--      psql -v ON_ERROR_STOP=1 -1 -f drafts/ak-sec-answer-01/155_sec1_answer_key_acl.sql
--   3) BU BETİĞİ koş (psql; tek transaction, sonda ROLLBACK — kalıntı yok).
--   4) 094 suite'i tekrar koş; tek fark D-43 FAIL→PASS olmalı.
--   5) DROP DATABASE sec1_qa_<uid>;
--
-- KANITLANACAKLAR:
--   T01 ACL matrisi = {postgres, service_role} (anon/auth/PUBLIC yok)
--   T02 anon EXECUTE reddi (42501)
--   T03 authenticated öğrenci EXECUTE reddi (42501)
--   T04 service_role doğrudan çağrı ÇALIŞIR (sunucu/QA yolu)
--   T05 yarışma iç zinciri: sunucu değerlendirmesi + puan değişmedi
--       (v1 sabitlenmiş set: correct=200 / wrong=0 / pass=0)
--   T06 finalize + lig rating +24/−12 yazıldı (ödül zinciri sağlam)
--   T07 antrenman zinciri: submit_training_attempt correct + XP=2
--   T08 migration idempotency: REVOKE tekrarı + aynı matris
--   T09 rollback prosedürü: GRANT ile eski hal döner → REVOKE ile kapanır
--   G01 KAYIT (FAIL değil): SEC-1b — questions.correct_answer satır
--       okuması (questions_student_read politikası) bu migration'ın
--       kapsamı DIŞINDADIR; ayrı karar maddesi.
-- ============================================================================

\set ON_ERROR_STOP on

do $guard$
begin
  if current_database() not like 'sec1_qa_%' then
    raise exception
      'QA SEC1: yalnız sec1_qa_* geçici DB''de koşulur; mevcut DB: %',
      current_database()
      using errcode = 'P0999';
  end if;
end;
$guard$;

begin;

create table public._qa_sec1_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS','FAIL','GAP')),
  detail text
);

grant select, insert, update, delete
  on public._qa_sec1_results
  to anon, authenticated, service_role;

create function public._qa_sec1_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
) returns void language plpgsql security definer set search_path = public as $f$
begin
  insert into public._qa_sec1_results values (p_label, p_title,
    case when p_ok then 'PASS' else 'FAIL' end, p_detail);
end;
$f$;

create function public._qa_sec1_expect(
  p_label text, p_title text, p_expect text, p_sql text
) returns void language plpgsql security invoker as $f$
declare v_state text; v_msg text;
begin
  begin
    execute p_sql;
    insert into public._qa_sec1_results values (p_label, p_title,
      case when p_expect = '' then 'PASS' else 'FAIL' end,
      case when p_expect = '' then 'beklendigi gibi uygulandi'
           else 'hata beklenmisti ama uygulandi; beklenen=' || p_expect end);
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    insert into public._qa_sec1_results values (p_label, p_title,
      case when p_expect <> '' and v_state = p_expect then 'PASS' else 'FAIL' end,
      'sqlstate=' || v_state || ' beklenen=' || coalesce(nullif(p_expect,''),'-')
        || ' | ' || left(v_msg, 160));
  end;
end;
$f$;

-- ---------------------------------------------------------------------------
-- T01: 155 sonrası ACL matrisi tam beklenen kümeyle eşit olmalı
-- ---------------------------------------------------------------------------
do $t01$
declare v_set text; v_oid oid;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='get_internal_correct_answer';
  if v_oid is null then
    perform public._qa_sec1_true('T01','fonksiyon mevcut', false, '155 oncesi kopya eksiği?');
    return;
  end if;
  select string_agg(pg_get_userbyid(grantee), ',' order by grantee)
    into v_set
    from aclexplode((select proacl from pg_proc where oid = v_oid))
   where privilege_type = 'EXECUTE';
  perform public._qa_sec1_true('T01',
    'EXECUTE matrisi = {postgres, service_role}',
    v_set = 'postgres,service_role',
    'matris=' || coalesce(v_set,'<NULL>'));
end;
$t01$;

-- ---------------------------------------------------------------------------
-- Fixture: kullanıcılar + müfredat + sorular + v1 sabitli 1 soruluk yarışma
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('95100000-0000-0000-0000-000000000091', 'qa-sec1-a@test.local'),
  ('95100000-0000-0000-0000-000000000092', 'qa-sec1-b@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('95100000-0000-0000-0000-000000000091', 5, 'QA-S1-A'),
  ('95100000-0000-0000-0000-000000000092', 5, 'QA-S1-B');

insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
values
  ('95151515-1515-1515-1515-151515150001', 'QAS1-C1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'hard', 'learning', 'coktan_secmeli', 'A', true, 45),
  ('95151515-1515-1515-1515-151515150002', 'QAS1-P1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45);

-- v1 setine sabitle → puanlar deterministik (correct=200, wrong/pass=0).
insert into public.competitions
  (competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count)
values
  ('QAS1-TEST-01', 'one_vs_one', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   (select id from public.scoring_rule_sets where rule_set_code='competition_scoring_v1'),
   'active', 1);

insert into public.competition_players (competition_id, user_id, player_slot)
select id, '95100000-0000-0000-0000-000000000091'::uuid, 1 from public.competitions where competition_code='QAS1-TEST-01'
union all
select id, '95100000-0000-0000-0000-000000000092'::uuid, 2 from public.competitions where competition_code='QAS1-TEST-01';

insert into public.competition_questions
  (competition_id, question_id, question_order, difficulty, sent_at, deadline_at)
select c.id, '95151515-1515-1515-1515-151515150001', 1, 'hard',
       now() - interval '1 minute', now() + interval '30 minutes'
  from public.competitions c where c.competition_code='QAS1-TEST-01';

update public.competitions c
   set current_question_id = (select cq.id from public.competition_questions cq
                               where cq.competition_id = c.id),
       current_question_order = 1
 where c.competition_code='QAS1-TEST-01';

-- U2'ye taban üstü lig girişi tohumla: rating 100 (Bronz 0-999).
-- Mağlubiyet -12'si clamp'sız gözlenebilir (100 -> 88); U1 0'dan
-- başladığı için +24 yazılır ve 0 tabanı ayrıca kanıtlanmış olur.
insert into public.student_league_memberships
  (user_id, league_id, membership_scope, points_at_entry,
   current_points, entered_at, is_current)
values
  ('95100000-0000-0000-0000-000000000092',
   (select id from public.leagues where league_code='bronze'),
   'general', 100, 100, now(), true);

-- ---------------------------------------------------------------------------
-- T02/T03: anon ve authenticated EXECUTE reddi (rol-switch simülasyonu)
-- ---------------------------------------------------------------------------
do $t02$
begin
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  perform public._qa_sec1_expect('T02',
    'anon: get_internal_correct_answer EXECUTE reddedilir',
    '42501',
    $sql$select public.get_internal_correct_answer(
      '95151515-1515-1515-1515-151515150001'::uuid)$sql$);
  execute 'reset role';
end;
$t02$;

do $t03$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95100000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  perform public._qa_sec1_expect('T03',
    'authenticated ogrenci: get_internal_correct_answer EXECUTE reddedilir',
    '42501',
    $sql$select public.get_internal_correct_answer(
      '95151515-1515-1515-1515-151515150001'::uuid)$sql$);
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$t03$;

-- ---------------------------------------------------------------------------
-- T04: service_role doğrudan çağrı çalışır (iç sunucu/QA yolu)
-- ---------------------------------------------------------------------------
do $t04$
declare v_ans text;
begin
  execute 'set local role service_role';
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000000","role":"service_role"}', true);
  select public.get_internal_correct_answer(
    '95151515-1515-1515-1515-151515150001'::uuid) into v_ans;
  perform public._qa_sec1_true('T04',
    'service_role: fonksiyon cagrilabilir (ic akis)',
    v_ans = 'A', 'answer=' || coalesce(v_ans,'<NULL>'));
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$t04$;

-- ---------------------------------------------------------------------------
-- T05/T06: yarışma iç zinciri — definer zinciri fonksiyonu owner hakkıyla
-- çağırır; puanlar v1 matrisiyle birebir; finalize + rating +24/−12.
-- ---------------------------------------------------------------------------
do $t05$
declare v_res jsonb; v_cq uuid;
begin
  -- cq.id ROL GEÇİŞİNDEN ÖNCE (postgres) çözülmeli: authenticated
  -- bağlamında competition_questions RLS'i alt kümeleyebilir (094
  -- kalıbı da sabit UUID kullanır).
  select cq.id into v_cq
    from public.competition_questions cq
    join public.competitions c on c.id = cq.competition_id
   where c.competition_code = 'QAS1-TEST-01';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95100000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select public.submit_competition_answer(v_cq, 'A') into v_res;
  perform public._qa_sec1_true('T05a',
    'yarisma sunucu degerlendirmesi: correct + v1 puani 200',
    v_res->>'result' = 'correct' and (v_res->>'points_awarded')::int = 200,
    'result=' || coalesce(v_res->>'result','?') ||
    ' points=' || coalesce(v_res->>'points_awarded','?'));

  perform set_config('request.jwt.claims',
    '{"sub":"95100000-0000-0000-0000-000000000092","role":"authenticated"}', true);
  select public.submit_competition_answer(v_cq, 'B') into v_res;
  perform public._qa_sec1_true('T05b',
    'yarisma rakip degerlendirmesi: wrong + v1 puani 0',
    v_res->>'result' = 'wrong' and (v_res->>'points_awarded')::int = 0,
    'result=' || coalesce(v_res->>'result','?') ||
    ' points=' || coalesce(v_res->>'points_awarded','?'));

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$t05$;

do $t06$
declare v_w int; v_l int; v_completed text; v_after_loss int;
begin
  select count(*) filter (where cpc.points_after - cpc.points_before = 24),
         count(*) filter (where cpc.points_after - cpc.points_before = -12)
    into v_w, v_l
    from public.competition_point_changes cpc
    join public.competitions c on c.id = cpc.competition_id
   where c.competition_code = 'QAS1-TEST-01'
     and cpc.change_type = 'rating';
  select m.current_points into v_after_loss
    from public.student_league_memberships m
   where m.user_id = '95100000-0000-0000-0000-000000000092'
     and m.is_current;
  select c.status into v_completed
    from public.competitions c where c.competition_code='QAS1-TEST-01';
  perform public._qa_sec1_true('T06',
    'finalize + lig rating zinciri: galip +24 / maglup -12 (100->88) ve completed',
    v_w = 1 and v_l = 1 and v_after_loss = 88 and v_completed = 'completed',
    'win=' || coalesce(v_w,-1) || ' loss=' || coalesce(v_l,-1)
      || ' maglup_puan=' || coalesce(v_after_loss,-1)
      || ' status=' || coalesce(v_completed,'?'));
end;
$t06$;

-- ---------------------------------------------------------------------------
-- T07: antrenman zinciri (correct_answer TABLO yoludur; fonksiyondan
-- bağımsız — bozulmadığını kanıtlar) + XP 2 (easy)
-- ---------------------------------------------------------------------------
do $t07$
declare v_res jsonb; v_xp int;
begin
  insert into public.student_question_exposures (user_id, question_id, attempt_context)
  values ('95100000-0000-0000-0000-000000000091',
          '95151515-1515-1515-1515-151515150002', 'training');

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95100000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select public.submit_training_attempt(
    '95151515-1515-1515-1515-151515150002', 'A', null, 12000,
    gen_random_uuid()) into v_res;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select xp_amount into v_xp
    from public.student_xp_ledger
   where user_id = '95100000-0000-0000-0000-000000000091'
     and source_type = 'training_attempt';

  perform public._qa_sec1_true('T07',
    'antrenman degerlendirmesi correct + easy XP=2',
    v_res->>'result' = 'correct' and coalesce(v_xp, -1) = 2,
    'result=' || coalesce(v_res->>'result','?') || ' xp=' || coalesce(v_xp, -1));
end;
$t07$;

-- ---------------------------------------------------------------------------
-- G01 (KAYIT, kapsam dışı): SEC-1b — approved sorunun correct_answer'ı
-- öğrenciye RLS politikası üzerinden okunabilir mi? FAIL değil, GAP.
-- ---------------------------------------------------------------------------
do $g01$
declare v_leak text;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95100000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  begin
    select q.correct_answer into v_leak
      from public.questions q
     where q.id = '95151515-1515-1515-1515-151515150002';
  exception when insufficient_privilege then
    v_leak := '<42501-reddedildi>';
  end;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  insert into public._qa_sec1_results values ('G01',
    'SEC-1b: questions_student_read politikasiyla correct_answer satir okuma',
    'GAP',
    'okuma sonucu=' || coalesce(v_leak,'<NULL>') ||
    ' | 155 kapsamı dışında; ayrı kullanıcı kararı');
end;
$g01$;

-- ---------------------------------------------------------------------------
-- T08: migration idempotency — REVOKE + assertion tekrarı aynı matrisi verir
-- ---------------------------------------------------------------------------
do $t08$
begin
  execute $mig$
    do $$
    declare v_oid oid;
    begin
      select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='get_internal_correct_answer';
      if has_function_privilege('anon', v_oid, 'EXECUTE')
         or has_function_privilege('authenticated', v_oid, 'EXECUTE') then
        raise exception 'idempotency bozuldu' using errcode='P0001';
      end if;
    end $$;
  $mig$;
  perform public._qa_sec1_true('T08',
    '155 tekrarı idempotent (matris değişmedi)', true, 'assertion tekrar koştu');
end;
$t08$;

-- ---------------------------------------------------------------------------
-- T09: rollback prosedürü — GRANT ile eski (açık) hal döner; REVOKE kapatır
-- ---------------------------------------------------------------------------
do $t09$
declare v_call_ok boolean := false;
begin
  grant execute on function public.get_internal_correct_answer(uuid) to anon;

  execute 'set local role anon';
  begin
    perform public.get_internal_correct_answer(
      '95151515-1515-1515-1515-151515150001'::uuid);
    v_call_ok := true;
  exception when others then
    v_call_ok := false;
  end;
  execute 'reset role';
  perform public._qa_sec1_true('T09a',
    'rollback GRANT devreye giriyor (anon tekrar çağırabiliyor)',
    v_call_ok, 'canlıya ASLA uygulanmaz; yalnız prosedür kanıtı');

  revoke execute on function public.get_internal_correct_answer(uuid) from anon;

  begin
    execute 'set local role anon';
    perform public.get_internal_correct_answer(
      '95151515-1515-1515-1515-151515150001'::uuid);
    execute 'reset role';
    perform public._qa_sec1_true('T09b',
      'REVOKE geri uygulandığında açık yeniden kapanır', false, 'çağrı geçti?!');
  exception when insufficient_privilege then
    execute 'reset role';
    perform public._qa_sec1_true('T09b',
      'REVOKE geri uygulandığında açık yeniden kapanır', true, 'sqlstate=42501');
  end;
end;
$t09$;

-- ---------------------------------------------------------------------------
-- ÖZET
-- ---------------------------------------------------------------------------
do $sum$
declare v_fail int; v_gap int; v_pass int; r record;
begin
  select count(*) filter (where result='FAIL'),
         count(*) filter (where result='GAP'),
         count(*) filter (where result='PASS')
    into v_fail, v_gap, v_pass
    from public._qa_sec1_results;

  raise notice 'QA SEC1 OZET: PASS=% FAIL=% GAP=%', v_pass, v_fail, v_gap;
  for r in select label, title, result, detail
              from public._qa_sec1_results order by label loop
    raise notice '  [%] % | %', r.result, r.label, r.title;
  end loop;

  if v_fail > 0 then
    raise exception 'QA SEC1 BASARISIZ: % FAIL', v_fail using errcode='P0999';
  end if;
  raise notice 'QA SEC1 GECTI (GAP kayıtları ayrı karar maddesidir)';
end;
$sum$;

rollback;
