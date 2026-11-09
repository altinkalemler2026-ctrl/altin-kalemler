-- ============================================================================
-- qa_sec1b_answer_key_local.sql — AK-SEC-ANSWER-02 İZOLE (DISPOSABLE) QA
-- ============================================================================
-- AMAÇ: 155 (SEC-1 fonksiyon ACL) + 156 (SEC-1b questions ACL+RLS)
--   birlikteliğini canlı kopyası üzerinde uçtan uca kanıtlamak.
--
-- ÖN KOŞUL: Yalnız 'sec1b_qa_%' / 'sec1_qa_%' önekli geçici DB'de koşar.
--   155 VE 156 ÖNCEDEN uygulanmış olmalıdır (PREFLIGHT doğrular).
--
-- KOŞUM SIRASI (koordinatör):
--   1) Canlı kopya: pg_dump günlük DB → createdb sec1b_qa_<uid> → psql -f restore
--   2) TABAN SAYIMLAR (migration ÖNCESİ): vaults=36, weeks=41,
--      candidate_batch_candidate_results=112, candidate_question_batches=3,
--      questions=0, competitions=0  → B00 sabitleriyle karşılaştırılır.
--   3) 155 + 156 uygula, sonra İKİSİNİ BİR KEZ DAHA uygula (idempotency).
--   4) qa_sec1_answer_key_local.sql koş (T01–T09; SEC-1 fonksiyon dili).
--   5) BU BETİĞİ koş (P00, B00–B10; SEC-1b + entegrasyon).
--   6) DROP DATABASE sec1b_qa_<uid>;
--
-- GÖREV SENARYO EŞLEMESİ (görev maddesi → test etiketi):
--   S1 anon RPC cevap        → qa_sec1 T02  (+ B01c tekrarı burada)
--   S2 auth  RPC cevap       → qa_sec1 T03  (+ B01d tekrarı burada)
--   S3 anon tablo dökemez    → B01
--   S4 öğrenci tablo dökemez → B02
--   S5 alternatif yol yok    → B03
--   S6 izinli metin+şıklar   → B04 (C1 paketi payload)
--   S7 tam 5 soru paketi     → B05
--   S8 yarışma cevap kontrol → B06
--   S9 antrenman+XP          → B07
--   S10 puanlama+rakip bonusu→ B08 (v3 sabit set)
--   S11 yönetici denetimi    → B09
--   S12 yabancı paket erişimi→ B10
--   S13 idempotency          → adım 3 + B11 (yerinde yeniden assert)
--   S14 veri koruması        → B00 (migration sonrası taban sabitleri)
-- ============================================================================

\set ON_ERROR_STOP on

do $guard$
begin
  if current_database() not like 'sec1b_qa_%'
     and current_database() not like 'sec1_qa_%' then
    raise exception
      'QA SEC1B: yalnız sec1b_qa_*/sec1_qa_* geçici DB''de koşulur; mevcut: %',
      current_database() using errcode = 'P0999';
  end if;
end;
$guard$;

begin;

create table public._qa_s1b_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS','FAIL','GAP')),
  detail text
);

create function public._qa_s1b_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
) returns void language plpgsql security definer set search_path = public as $f$
begin
  insert into public._qa_s1b_results values (p_label, p_title,
    case when p_ok then 'PASS' else 'FAIL' end, p_detail);
end;
$f$;

create function public._qa_s1b_expect(
  p_label text, p_title text, p_expect text, p_sql text
) returns void language plpgsql security invoker as $f$
declare v_state text; v_msg text;
begin
  begin
    execute p_sql;
    insert into public._qa_s1b_results values (p_label, p_title,
      case when p_expect = '' then 'PASS' else 'FAIL' end,
      case when p_expect = '' then 'beklendigi gibi uygulandi'
           else 'hata beklenmisti ama uygulandi; beklenen=' || p_expect end);
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    insert into public._qa_s1b_results values (p_label, p_title,
      case when p_expect <> '' and v_state = p_expect then 'PASS' else 'FAIL' end,
      'sqlstate=' || v_state || ' beklenen=' || coalesce(nullif(p_expect,''),'-')
        || ' | ' || left(v_msg, 160));
  end;
end;
$f$;

-- ---------------------------------------------------------------------------
-- PREFLIGHT: 155 + 156 birlikte uygulanmış olmalı (matris kontrolü)
-- ---------------------------------------------------------------------------
do $pre$
declare v_oid oid; v_pol int;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='get_internal_correct_answer';
  if v_oid is null
     or has_function_privilege('anon', v_oid, 'EXECUTE')
     or has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'PREFLIGHT: 155 uygulanmamış/eksik (get_internal_correct_answer ACL)';
  end if;
  if has_table_privilege('anon','public.questions','SELECT') then
    raise exception 'PREFLIGHT: 156 uygulanmamış (anon questions SELECT duruyor)';
  end if;
  select count(*) into v_pol from pg_policy
   where polrelid='public.questions'::regclass and polname='questions_student_read';
  if v_pol <> 0 then
    raise exception 'PREFLIGHT: 156 uygulanmamış (questions_student_read duruyor)';
  end if;
end;
$pre$;

-- ---------------------------------------------------------------------------
-- B00 (S14): veri koruması — taban sabitleri (canlı anlık görüntü 2026-11-09)
-- ---------------------------------------------------------------------------
do $b00$
declare v1 int; v2 int; v3 int; v4 int; v5 int; v6 int;
begin
  select count(*) into v1 from public.question_vaults;
  select count(*) into v2 from public.academic_weeks;
  select count(*) into v3 from public.candidate_batch_candidate_results;
  select count(*) into v4 from public.candidate_question_batches;
  select count(*) into v5 from public.questions;
  select count(*) into v6 from public.competitions;
  perform public._qa_s1b_true('B00',
    'S14 veri korumasi: 36 kasa + 41 hafta + 112 aday + 3 parti + 0 soru/yarisma',
    v1 = 36 and v2 = 41 and v3 = 112 and v4 = 3 and v5 = 0 and v6 = 0,
    'kasa=' || v1 || ' hafta=' || v2 || ' aday=' || v3
      || ' parti=' || v4 || ' soru=' || v5 || ' yarisma=' || v6);
end;
$b00$;

-- ---------------------------------------------------------------------------
-- FIXTURES (transaction içi; sonda ROLLBACK — kalıntı yok)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('95200000-0000-0000-0000-000000000091', 'qa-s1b-a@test.local'),
  ('95200000-0000-0000-0000-000000000092', 'qa-s1b-b@test.local'),
  ('95200000-0000-0000-0000-000000000093', 'qa-s1b-c@test.local'),
  ('95200000-0000-0000-0000-000000000a91', 'qa-s1b-admin@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('95200000-0000-0000-0000-000000000091', 5, 'QA-S1B-A'),
  ('95200000-0000-0000-0000-000000000092', 5, 'QA-S1B-B'),
  ('95200000-0000-0000-0000-000000000093', 5, 'QA-S1B-C');

insert into public.admin_user_roles (user_id, role_id, assigned_by, assigned_at)
select '95200000-0000-0000-0000-000000000a91', r.id,
       '95200000-0000-0000-0000-000000000a91', now()
  from public.admin_roles r
 where r.role_code = 'super_admin'
on conflict do nothing;

-- C1 paketi (5 soru) + antrenman sorusu Q6 + v3 bonusu sorusu Q7
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds, question_text,
   option_a, option_b, expert_solution_time_seconds)
values
  ('95202020-0202-0202-0202-020202020201', 'QAS1B-C1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45,
   'QAS1B paket sorusu 1', 'dogru-secik-A', 'yanlis-secik-B', NULL),
  ('95202020-0202-0202-0202-020202020202', 'QAS1B-C2', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45,
   'QAS1B paket sorusu 2', 'dogru-secik-A', 'yanlis-secik-B', NULL),
  ('95202020-0202-0202-0202-020202020203', 'QAS1B-C3', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45,
   'QAS1B paket sorusu 3', 'dogru-secik-A', 'yanlis-secik-B', NULL),
  ('95202020-0202-0202-0202-020202020204', 'QAS1B-C4', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45,
   'QAS1B paket sorusu 4', 'dogru-secik-A', 'yanlis-secik-B', NULL),
  ('95202020-0202-0202-0202-020202020205', 'QAS1B-C5', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45,
   'QAS1B paket sorusu 5', 'dogru-secik-A', 'yanlis-secik-B', NULL),
  ('95202020-0202-0202-0202-020202020206', 'QAS1B-T1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45,
   'QAS1B antrenman sorusu', 'dogru-secik-A', 'yanlis-secik-B', NULL),
  ('95202020-0202-0202-0202-020202020207', 'QAS1B-V1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45,
   'QAS1B v3 bonus sorusu', 'dogru-secik-A', 'yanlis-secik-B', 120);

-- one_v_one kasası: tam 5 uygun üyelik (A-önceliği kuralı: sayı = 5)
insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id,
   is_dynamic, is_active, allow_practice, allow_competition,
   allow_one_v_one, allow_exam)
values
  ('95203030-0303-0303-0303-030303030301', 'QAS1B-1V1-G5', 'QA S1B one_v_one',
   'one_v_one', 5, '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   false, true, false, false, true, false);

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, one_v_one_eligible)
values
  ('95203030-0303-0303-0303-030303030301', '95202020-0202-0202-0202-020202020201', 'active', true),
  ('95203030-0303-0303-0303-030303030301', '95202020-0202-0202-0202-020202020202', 'active', true),
  ('95203030-0303-0303-0303-030303030301', '95202020-0202-0202-0202-020202020203', 'active', true),
  ('95203030-0303-0303-0303-030303030301', '95202020-0202-0202-0202-020202020204', 'active', true),
  ('95203030-0303-0303-0303-030303030301', '95202020-0202-0202-0202-020202020205', 'active', true);

-- ---------------------------------------------------------------------------
-- B01 (S3): anon tablo dökemez — yetki hatası (42501) beklenir
-- ---------------------------------------------------------------------------
do $b01$
begin
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  perform public._qa_s1b_expect('B01a',
    'S3 anon: correct_answer dökümü reddedilir',
    '42501',
    'select correct_answer from public.questions limit 1');
  perform public._qa_s1b_expect('B01b',
    'S3 anon: id dökümü de reddedilir (tam yetki iptali)',
    '42501',
    'select id from public.questions limit 1');
  -- S1/S2 self-contained tekrarı (qa_sec1 T02/T03 ile aynı gerçek)
  perform public._qa_s1b_expect('B01c',
    'S1 anon: get_internal_correct_answer EXECUTE reddi',
    '42501',
    $sql$select public.get_internal_correct_answer(
      '95202020-0202-0202-0202-020202020201'::uuid)$sql$);
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$b01$;

do $b01d$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  perform public._qa_s1b_expect('B01d',
    'S2 auth ogrenci: get_internal_correct_answer EXECUTE reddi',
    '42501',
    $sql$select public.get_internal_correct_answer(
      '95202020-0202-0202-0202-020202020201'::uuid)$sql$);
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$b01d$;

-- ---------------------------------------------------------------------------
-- B02 (S4): authenticated öğrenci tablo okuma hakkına sahip ama RLS
--           0 satır verir (correct_answer dahil hiçbir satır görünmez)
-- ---------------------------------------------------------------------------
do $b02$
declare v_rows int; v_ans text := '<OKUNDU>';
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select count(*) into v_rows from public.questions;
  select coalesce(max(q.correct_answer), '<0-satir>') into v_ans
    from public.questions q;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  perform public._qa_s1b_true('B02',
    'S4 auth ogrenci: questions 0 satir (RLS), correct_answer gorunmez',
    v_rows = 0 and v_ans = '<0-satir>',
    'satir=' || v_rows || ' cevap=' || coalesce(v_ans,'<NULL>'));
end;
$b02$;

-- ---------------------------------------------------------------------------
-- B03 (S5): alternatif erişim yolları kapalı
-- ---------------------------------------------------------------------------
do $b03$
declare v_col int; v_view int; v_gql int;
begin
  select count(*) into v_col
    from information_schema.column_privileges
   where table_schema='public' and table_name='questions'
     and (grantee in ('anon','public')
          or (grantee = 'authenticated' and privilege_type <> 'SELECT'));
  select count(*) into v_view
    from pg_views
   where definition ilike '%public.questions%'
      or definition ilike '%correct_answer%';
  select count(*) into v_gql from pg_extension where extname='pg_graphql';
  perform public._qa_s1b_true('B03',
    'S5 alternatif yol yok: kolon kiriligi 0 + view 0 + graphql yok + yazma/tehlike haklari yok',
    v_col = 0 and v_view = 0 and v_gql = 0
      and not has_table_privilege('anon','public.questions','SELECT')
      and not has_table_privilege('authenticated','public.questions','INSERT')
      and not has_table_privilege('authenticated','public.questions','UPDATE')
      and not has_table_privilege('authenticated','public.questions','DELETE')
      and not has_table_privilege('authenticated','public.questions','TRUNCATE')
      and not has_table_privilege('authenticated','public.questions','MAINTAIN')
      and has_table_privilege('authenticated','public.questions','SELECT')
      and has_table_privilege('service_role','public.questions','SELECT'),
    'kolon_kayit=' || v_col || ' view=' || v_view || ' graphql=' || v_gql
      || ' | PostgREST ayni kernel ACL/RLS''ini kullanir');
end;
$b03$;

-- ---------------------------------------------------------------------------
-- B05 (S7): matchmaking → tam 5 soruluk paket (kasa tabanlı, A-önceliği)
-- ---------------------------------------------------------------------------
do $b05$
declare v_ret jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa') into v_ret;
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000092","role":"authenticated"}', true);
  select public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa') into v_ret;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$b05$;

-- eşleşme + paket doğrulaması (postgres bağlamında sayım)
do $b05b$
declare v_comp uuid; v_q int;
begin
  select c.id into v_comp
    from public.competitions c
    join public.competition_players cp on cp.competition_id = c.id
   where cp.user_id = '95200000-0000-0000-0000-000000000091'
   order by c.created_at desc limit 1;
  if v_comp is null then
    perform public._qa_s1b_true('B05',
      'S7 matchmaking + tam 5 soruluk kasa paketi', false, 'yarisma olusmadi');
    return;
  end if;
  select count(*) into v_q from public.competition_questions
   where competition_id = v_comp;
  perform public._qa_s1b_true('B05',
    'S7 matchmaking + tam 5 soruluk kasa paketi',
    v_q = 5, 'yarisma=' || v_comp || ' soru=' || v_q);
end;
$b05b$;

-- ---------------------------------------------------------------------------
-- B04 (S6): öğrenci RPC payload'ında metin+şıklar VAR, correct_answer YOK
--   Yaşam döngüsü notu: queue 'waiting' üretir; waiting→active başlatıcısı
--   UYGULAMADA HENÜZ YOK (bilinen boşluk) — QA yaşam adımı olarak postgres
--   bağlamında 'active'ye çeker (094/qa_sec1 fixture kalıbı).
-- ---------------------------------------------------------------------------
do $b04pre$
declare v_comp uuid; v_cq uuid;
begin
  select c.id into v_comp
    from public.competitions c
    join public.competition_players cp on cp.competition_id = c.id
   where cp.user_id = '95200000-0000-0000-0000-000000000091'
   order by c.created_at desc limit 1;

  update public.competitions set status = 'active'
   where id = v_comp and status = 'waiting';

  select cq.id into v_cq
    from public.competition_questions cq
   where cq.competition_id = v_comp and cq.question_order = 1;

  update public.competition_questions
     set sent_at = now() - interval '1 minute',
         deadline_at = now() + interval '30 minutes'
   where id = v_cq and sent_at is null;

  update public.competitions
     set current_question_id = v_cq, current_question_order = 1
   where id = v_comp;
end;
$b04pre$;

do $b04$
declare v_ret jsonb; v_q jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select public.get_current_competition_question() into v_ret;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  v_q := v_ret -> 'payload' -> 'question';
  perform public._qa_s1b_true('B04',
    'S6 RPC payload: soru metni+secikler var, correct_answer yok',
    (v_ret->>'question_available') is not null
      and coalesce(v_q ->> 'question_text','') <> ''
      and coalesce(v_q ?| array['option_a','option_b','option_c'], false)
      and not (v_q ? 'correct_answer')
      and not (v_q ?| array['correct_option','correct_choice','answer','answer_key']),
    'status=' || coalesce(v_ret->>'status','?')
      || ' metin=' || left(coalesce(v_q->>'question_text','<YOK>'), 30)
      || ' anahtarlar=' || coalesce(
           (select string_agg(k,',' order by k) from jsonb_object_keys(v_q) k), '-'));
end;
$b04$;

-- ---------------------------------------------------------------------------
-- B06 (S8): yarışma cevap kontrolü (kasa paketinin 1. sorusu, her iki oyuncu)
-- ---------------------------------------------------------------------------
do $b06$
declare v_cq uuid; v_res jsonb; v_ok1 boolean := false; v_ok2 boolean := false;
begin
  select cq.id into v_cq
    from public.competition_questions cq
    join public.competitions c on c.id = cq.competition_id
    join public.competition_players cp on cp.competition_id = c.id
   where cp.user_id = '95200000-0000-0000-0000-000000000091'
   order by c.created_at desc, cq.question_order limit 1;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  begin
    select public.submit_competition_answer(v_cq, 'A') into v_res;
    v_ok1 := v_res->>'result' = 'correct' and (v_res->>'points_awarded')::int >= 100;
  exception when others then
    v_ok1 := false;
  end;
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000092","role":"authenticated"}', true);
  begin
    select public.submit_competition_answer(v_cq, 'A') into v_res;
    v_ok2 := v_res->>'result' = 'correct' and (v_res->>'points_awarded')::int >= 100;
  exception when others then
    v_ok2 := false;
  end;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  perform public._qa_s1b_true('B06',
    'S8 yarisma cevap kontrolu: iki oyuncu correct, v3 puani >= 100',
    v_ok1 and v_ok2, 'cq=' || coalesce(v_cq::text,'<YOK>'));
end;
$b06$;

-- ---------------------------------------------------------------------------
-- B07 (S9): antrenman cevap kontrolü + XP (definer yolu, 156'dan bağımsız)
-- ---------------------------------------------------------------------------
do $b07$
declare v_res jsonb; v_xp int;
begin
  insert into public.student_question_exposures
    (user_id, question_id, attempt_context)
  values ('95200000-0000-0000-0000-000000000091',
          '95202020-0202-0202-0202-020202020206', 'training');

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select public.submit_training_attempt(
    '95202020-0202-0202-0202-020202020206', 'A', null, 12000,
    gen_random_uuid()) into v_res;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select xp_amount into v_xp
    from public.student_xp_ledger
   where user_id = '95200000-0000-0000-0000-000000000091'
     and source_type = 'training_attempt';

  perform public._qa_s1b_true('B07',
    'S9 antrenman cevap kontrolu correct + easy XP=2',
    v_res->>'result' = 'correct' and coalesce(v_xp, -1) = 2,
    'result=' || coalesce(v_res->>'result','?') || ' xp=' || coalesce(v_xp, -1));
end;
$b07$;

-- ---------------------------------------------------------------------------
-- B08 (S10): v3 puanlama + rakip bonusu (doğrudan fixture yarışması)
--   U1 correct (easy base B) + rakip wrong → +20 bonus → total = B + 20
--   U2 wrong (penalty P) → total = P ; bonus olay satırı U1 için 1 adet
-- ---------------------------------------------------------------------------
insert into public.competitions
  (competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count)
values
  ('QAS1B-V3-01', 'one_vs_one', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   (select id from public.scoring_rule_sets
     where rule_set_code = 'competition_scoring_v3_fixed'),
   'active', 1);

insert into public.competition_players (competition_id, user_id, player_slot)
select id, '95200000-0000-0000-0000-000000000091'::uuid, 1
  from public.competitions where competition_code='QAS1B-V3-01'
union all
select id, '95200000-0000-0000-0000-000000000092'::uuid, 2
  from public.competitions where competition_code='QAS1B-V3-01';

insert into public.competition_questions
  (competition_id, question_id, question_order, difficulty, sent_at, deadline_at)
select c.id, '95202020-0202-0202-0202-020202020207', 1, 'easy',
       now() - interval '1 minute', now() + interval '30 minutes'
  from public.competitions c where c.competition_code='QAS1B-V3-01';

update public.competitions c
   set current_question_id = (select cq.id from public.competition_questions cq
                                where cq.competition_id = c.id),
       current_question_order = 1
 where c.competition_code='QAS1B-V3-01';

do $b08a$
declare v_cq uuid; v_res jsonb;
begin
  select cq.id into v_cq
    from public.competition_questions cq
    join public.competitions c on c.id = cq.competition_id
   where c.competition_code = 'QAS1B-V3-01';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select public.submit_competition_answer(v_cq, 'A') into v_res;
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000092","role":"authenticated"}', true);
  select public.submit_competition_answer(v_cq, 'B') into v_res;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$b08a$;

do $b08b$
declare v_base int; v_pen int; v_t1 int; v_t2 int; v_ob int; v_bonus int; v_status text;
begin
  -- Cevaplanan puanlar (bonus dahil DEĞİL — yanıt satırından okunur)
  select max(points_awarded) filter (where user_id='95200000-0000-0000-0000-000000000091'),
         max(points_awarded) filter (where user_id='95200000-0000-0000-0000-000000000092')
    into v_base, v_pen
    from public.competition_answers
   where competition_question_id = (
     select cq.id from public.competition_questions cq
       join public.competitions c on c.id = cq.competition_id
      where c.competition_code='QAS1B-V3-01');

  select cp.total_points into v_t1
    from public.competition_players cp
    join public.competitions c on c.id = cp.competition_id
   where c.competition_code='QAS1B-V3-01'
     and cp.user_id='95200000-0000-0000-0000-000000000091';
  select cp.total_points into v_t2
    from public.competition_players cp
    join public.competitions c on c.id = cp.competition_id
   where c.competition_code='QAS1B-V3-01'
     and cp.user_id='95200000-0000-0000-0000-000000000092';
  select cp.opponent_bonus_points into v_ob
    from public.competition_players cp
    join public.competitions c on c.id = cp.competition_id
   where c.competition_code='QAS1B-V3-01'
     and cp.user_id='95200000-0000-0000-0000-000000000091';
  select count(*) into v_bonus
    from public.faz30d_global_points_events
   where user_id = '95200000-0000-0000-0000-000000000091'
     and event_kind = 'opponent_bonus';
  select status into v_status
    from public.competitions where competition_code='QAS1B-V3-01';

  -- 128 sözleşmesi (satır ~1042): bantlar doluysa golge bonus = +fault(20),
  -- total_points = temel puanlar + golge bonus. Bant NULL ise bonus 0 kalır
  -- (QA 1. koşum kanıtı). Fixture sorusu expert_solution_time=120 → bant var.
  perform public._qa_s1b_true('B08',
    'S10 v3 puanlama degismez: total=base+bonus(20), golge kolon=20, olay>=1, completed',
    v_t1 = v_base + 20 and v_ob = 20 and v_bonus >= 1 and v_t2 = v_pen and v_status = 'completed',
    'base=' || coalesce(v_base,-999) || ' penalti=' || coalesce(v_pen,-999)
      || ' U1_total=' || coalesce(v_t1,-999) || ' U2_total=' || coalesce(v_t2,-999)
      || ' golge_bonus=' || coalesce(v_ob,-999)
      || ' bonus_olay=' || coalesce(v_bonus,-1) || ' status=' || coalesce(v_status,'?'));
end;
$b08b$;

-- ---------------------------------------------------------------------------
-- B09 (S11): yönetici soru denetimi — questions.view yöneticisi
--            correct_answer dahil satırları okuyabilir
-- ---------------------------------------------------------------------------
do $b09$
declare v_ans text; v_rows int;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000a91","role":"authenticated"}', true);
  select max(q.correct_answer) into v_ans
    from public.questions q
   where q.id = '95202020-0202-0202-0202-020202020201';
  select count(*) into v_rows from public.questions;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  perform public._qa_s1b_true('B09',
    'S11 yonetici denetimi: super_admin correct_answer + tum satirlari gorur',
    v_ans = 'A' and v_rows = 7,
    'cevap=' || coalesce(v_ans,'<YOK>') || ' satir=' || coalesce(v_rows,-1));
end;
$b09$;

-- ---------------------------------------------------------------------------
-- B10 (S12): yetkisiz öğrenci başka yarışmacının paketini okuyamaz
-- ---------------------------------------------------------------------------
do $b10$
declare v_comp uuid; v_own jsonb;
begin
  select c.id into v_comp
    from public.competitions c
    join public.competition_players cp on cp.competition_id = c.id
   where cp.user_id = '95200000-0000-0000-0000-000000000091'
   order by c.created_at desc limit 1;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95200000-0000-0000-0000-000000000093","role":"authenticated"}', true);
  perform public._qa_s1b_expect('B10a',
    'S12 yetkisiz ogrenci: sync_competition_state(yabanci) reddedilir',
    'P0001',
    'select public.sync_competition_state(' || quote_literal(v_comp) || '::uuid)');
  select public.get_current_competition_question() into v_own;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  perform public._qa_s1b_true('B10b',
    'S12 yabanci ogrencinin get_current_payload''i kendi baglaminda bos',
    coalesce(v_own->>'status','') = 'no_active_competition',
    'status=' || coalesce(v_own->>'status','?'));
end;
$b10$;

-- ---------------------------------------------------------------------------
-- B11 (S13 yerinde bölümü): 156 REVOKELARI + ASSERT tekrar koşar, matris
--     değişmez (dosyanın tamamı dışarıda da 2 kez koşulmuş olur — adım 3)
-- ---------------------------------------------------------------------------
do $b11$
DECLARE r record; v_cnt int;
begin
  FOR r IN
    SELECT DISTINCT grantee, column_name
      FROM information_schema.column_privileges
     WHERE table_schema='public' AND table_name='questions'
       AND grantee IN ('anon','authenticated','public')
  LOOP
    IF r.grantee = 'authenticated' THEN
      EXECUTE format(
        'REVOKE INSERT, UPDATE, REFERENCES (%I) ON public.questions FROM authenticated',
        r.column_name);
    ELSE
      EXECUTE format(
        'REVOKE SELECT, INSERT, UPDATE, REFERENCES (%I) ON public.questions FROM %I',
        r.column_name, r.grantee);
    END IF;
  END LOOP;
  REVOKE ALL ON public.questions FROM anon;
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.questions FROM authenticated;

  select count(*) into v_cnt
    from information_schema.column_privileges
   where table_schema='public' and table_name='questions'
     and (grantee in ('anon','public')
          or (grantee = 'authenticated' and privilege_type <> 'SELECT'));
  perform public._qa_s1b_true('B11',
    'S13 idempotency: revoke tekrari matrisi bozmedi (anon 0 hak, auth yalniz SELECT)',
    v_cnt = 0
      and not has_table_privilege('anon','public.questions','SELECT')
      and has_table_privilege('authenticated','public.questions','SELECT')
      and not has_table_privilege('authenticated','public.questions','INSERT'),
    'kolon_kayit=' || v_cnt);
end;
$b11$;

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
    from public._qa_s1b_results;

  raise notice 'QA SEC1B OZET: PASS=% FAIL=% GAP=%', v_pass, v_fail, v_gap;
  for r in select label, title, result, detail
              from public._qa_s1b_results order by label loop
    raise notice '  [%] % | % | %', r.result, r.label, r.title, coalesce(r.detail,'');
  end loop;

  if v_fail > 0 then
    raise exception 'QA SEC1B BASARISIZ: % FAIL', v_fail using errcode='P0999';
  end if;
  raise notice 'QA SEC1B GECTI';
end;
$sum$;

rollback;
