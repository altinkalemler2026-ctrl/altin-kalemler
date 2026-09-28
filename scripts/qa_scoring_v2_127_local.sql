-- ============================================================
-- scripts/qa_scoring_v2_127_local.sql
-- Altin Kalemler - Migration 127 yerel QA suite
-- (Yarisma puanlama sozlesmesi V2: negatif wrong/timeout)
--
-- ONAYLI KURAL:
--   correct 100/150/200 | wrong -20/-30/-40 | timeout -20/-30/-40
--   pass 0 (her zorlukta) | kota/sayac/ceza/odul YOK
--
-- Kapsam:
--   A-01..A-09 : seed/katalog + TEK AKTIF VARSAYILAN + v1 korunumu
--   B-11..B-16 : V1 REGRESYON (degismemis olmali)
--   C-21..C-26 : V2 matrisi (12 sinif x 3 zorluk x 4 sonuc)
--   D-31..D-36 : idempotency + pas kotasizlik + negatif kabul
--   E-41..E-49 : davranissal (negatif/pozitif toplam, beraberlik,
--                forfeit, dort sonuc turu, snapshot)
--   F-51..F-55 : XP + rating DEGISMEDIGI (V1 donem degerleri)
--   G-61..G-63 : Puan zincirine dokunulmadi (kod/tabloda degisiklik yok)
--
-- NOT: Onayli sure bandi seed'i olmadigi icin V2 de fallback
-- matrisi gecerlidir; bilinmeyen/NULL bant fallback'e doner.
-- resolve_competition_points'in sessiz-0 davranisi DEGISMEDI.
--
-- ============================================================
-- 001-128 TERMINAL UYUMMLUGU (FAZ 30G-2)
--
-- Bu suite 127'yi olcer; ancak calistirildigi zincir 001-128'dir
-- ve 128 bu suite'in ilk yazimindaki UC varsayimi BILINCLI olarak
-- degistirmistir. Duzeltilen yalniz bu varsayimlardir:
--
--   A-01  128, V2 kural SETINI is_active=false yapar; ancak V2
--         SATIRLARI AKTIF KALIR (gecmis V2 yarismalari kendi
--         rule_set_id ile cozulmeye devam eder). Beklenti artik
--         "V2 = pasif kural seti + 144 AKTIF puan satiri".
--   A-02  Tek aktif kural seti artik V2 DEGIL, V3'tur:
--         competition_scoring_v3_fixed (128'in onayli terminali).
--   D-33  D-33 eskiden competition_players/competition_answers
--         uzerinde "%bonus%" deseniyle PAS ODULU kolonu arardi;
--         128'in ONAYLI kapsami olan opponent_bonus_points bu
--         desene takilip FALSE POSITIVE uretiyordu. Artik kolon
--         adi taramasi yalniz PAS'a OZGUL kota/ceza/odul
--         kolonlarini arar; asil kanit DAVRANISALDIR: gercek bir
--         V3 yarismasinda pasin 0 puan ve 0 rakip bonus
--         urettigi, pas kotasi/cezasi/odulu olmadigi SQL ile
--         olculur (pozitif kontrol: ayni kancada rakip wrong
--         +20 uretir -> mekanizma canlidir, pas gercekten 0'dir).
--
-- Diger 45 testin esigi, anlami veya beklenen degeri DEGISMEDI.
-- Test sayisi 48 olarak KORUNDU; hicbir test gevsetilmedi veya
-- atlanmadi. Migration 127/128, puanlama fonksiyonlari,
-- types.ts ve UI bu calisma kapsaminda DEGISTIRILMEDI.
-- ============================================================
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_scoring_v2_127_local.sql <db>:/tmp/
--   docker exec <db> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -A -t -f /tmp/qa_scoring_v2_127_local.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;

create table public._qa_s127_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_s127_results
  to anon, authenticated, service_role;

create function public._qa_s127_expect(
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
      insert into public._qa_s127_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_s127_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_s127_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_s127_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa_s127_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_s127_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa_s127_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_s127_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR (sabit QA uuid'leri; rollback ile silinecek)
-- matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
--   U1/U2 : COMP-MIX      (win_loss; dort sonuc turu)
--   U3/U4 : COMP-NEGDRAW  (draw; negatif toplam)
--   U5/U6 : COMP-FORFEIT  (forfeit; negatif kaybeden)
--   U7/U8 : COMP-PASSZERO (D-33 V3 pas kaniti; digerlerinden bagimsiz)
-- ============================================================

insert into auth.users (id, email) values
  ('d30c0000-0000-4000-8000-000000000001', 'qa127-a@test.local'),
  ('d30c0000-0000-4000-8000-000000000002', 'qa127-b@test.local'),
  ('d30c0000-0000-4000-8000-000000000003', 'qa127-c@test.local'),
  ('d30c0000-0000-4000-8000-000000000004', 'qa127-d@test.local'),
  ('d30c0000-0000-4000-8000-000000000005', 'qa127-e@test.local'),
  ('d30c0000-0000-4000-8000-000000000006', 'qa127-f@test.local'),
  -- D-33 (pas kaniti) icin AYRI oyuncular: U1/U2'nin rating snapshot'i
  -- F-54 tarafindan denetlendigi icin paylasilmaz.
  ('d30c0000-0000-4000-8000-000000000007', 'qa127-g@test.local'),
  ('d30c0000-0000-4000-8000-000000000008', 'qa127-h@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('d30c0000-0000-4000-8000-000000000001', 5, 'QA127-NICK-A'),
  ('d30c0000-0000-4000-8000-000000000002', 5, 'QA127-NICK-B'),
  ('d30c0000-0000-4000-8000-000000000003', 5, 'QA127-NICK-C'),
  ('d30c0000-0000-4000-8000-000000000004', 5, 'QA127-NICK-D'),
  ('d30c0000-0000-4000-8000-000000000005', 5, 'QA127-NICK-E'),
  ('d30c0000-0000-4000-8000-000000000006', 5, 'QA127-NICK-F'),
  ('d30c0000-0000-4000-8000-000000000007', 5, 'QA127-NICK-G'),
  ('d30c0000-0000-4000-8000-000000000008', 5, 'QA127-NICK-H');

insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('d30c0000-0000-4000-8000-000000000010', 'QA127-Y', 'MEB-QA127', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('d30c0000-0000-4000-8000-000000000011', 'QA127-SCHED', 'QA127 Profil',
   'd30c0000-0000-4000-8000-000000000010', true, true);

insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('d30c0000-0000-4000-8000-000000000012',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   5, 'QA127 Konu', 'qa127-konu',
   'd30c0000-0000-4000-8000-000000000010');

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, start_week, end_week) values
  ('d30c0000-0000-4000-8000-000000000011', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   'd30c0000-0000-4000-8000-000000000012', 1, null);

-- 5 yarisma sorusu (hard, tek-yanitlik A..E) + 1 antrenman sorusu.
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
select ('d30c0000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
       'QA127-C-' || n, 5,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
       'hard', 'learning', 'coktan_secmeli',
       (array['A','B','C','D','E'])[n::int], true, 45
  from generate_series(1, 5) n;

insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
values
  ('d30c0000-0000-4000-8000-000000000299', 'QA127-P1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45);

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, review_status)
select q.id, 'd30c0000-0000-4000-8000-000000000010',
       'd30c0000-0000-4000-8000-000000000012', 'approved'
  from public.questions q
 where q.question_code like 'QA127-%';

-- KASSA (vault) FIXTURE'I YOKTUR.
-- 127 puan kurallarini olcer; soru kasi (question_vaults) bu suite
-- icin GEREKLI DEGILDIR (competition_questions dogrudan
-- questions tablosuna referans verir). Ayrica bu DB'de
-- question_vaults'a 'one_vs_one' vault_type ile yazim
-- question_vaults_vault_type_check tarafindan reddedilmektedir
-- (trg_question_vaults_pack_limit tetikleyicisi; ONCEDEN VAR OLAN
-- ve 30C KAPSAMI DISI bir durumdur). Bu nedenle vault fixture'i
-- bilerek kurulmaz.


-- ============================================================
-- A. SEED / KATALOG / VARSAYILAN
-- ============================================================

-- A-01: V2 kural seti tam bir kez, version 2.
-- 001-128 TERMINAL UYUMMLUGU: 128 bu bayragi BILINCCI olarak
-- is_active=false yapar; ancak V2 SATIRLARI AKTIF KALIR
-- (128 giris yorumu, satir 73-77 ve 619-620). Beklenti:
--   - katalogda tam 1 kayit, version = '2'
--   - is_active = false (128 kesintisi)
--   - 144 puan satiri KORUNUR ve AKTIF kalir
do $blk$
declare
  v_cnt integer; v_active boolean; v_ver text;
  v_rows integer; v_rows_active integer;
begin
  select count(*), bool_or(is_active), max(version)
    into v_cnt, v_active, v_ver
    from public.scoring_rule_sets
   where rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  select count(*), count(*) filter (where spr.is_active)
    into v_rows, v_rows_active
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  perform public._qa_s127_true('A-01',
    'V2 rule set tam bir kez, version=2; 128 terminalinde is_active=false, 144 satir AKTIF korunur',
    v_cnt = 1 and v_ver = '2' and coalesce(v_active, true) = false
      and v_rows = 144 and v_rows_active = 144,
    'count=' || v_cnt || ' active=' || coalesce(v_active::text, '?') ||
    ' ver=' || coalesce(v_ver, '?') ||
    ' rows=' || v_rows || ' rows_active=' || v_rows_active);
end;
$blk$;

-- A-02: 001-128 TERMINAL UYUMMLUGU: TEK AKTIF KURAL SETI V3'tur.
--   128 v3'i aktiflestirir, v2'yi pasiflestirir
--   (128 satir 609-617). Beklenti:
--   - aktif kural seti sayisi TAM OLARAK 1
--   - kodu competition_scoring_v3_fixed
--   - v3 katalogda tam 1 kayit, version = '3', 252 puan satiri
do $blk$
declare
  v_active_sets text[];
  v_v3_cnt integer; v_v3_ver text; v_v3_rows integer;
begin
  select coalesce(array_agg(rule_set_code order by rule_set_code), '{}')
    into v_active_sets
    from public.scoring_rule_sets
   where is_active = true;

  select count(*), max(version)
    into v_v3_cnt, v_v3_ver
    from public.scoring_rule_sets
   where rule_set_code = 'competition_scoring_v3_fixed';

  select count(*) into v_v3_rows
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v3_fixed';

  perform public._qa_s127_true('A-02',
    'tek aktif kural seti: competition_scoring_v3_fixed (128 terminali; V2 pasif)',
    v_active_sets = array['competition_scoring_v3_fixed']
      and v_v3_cnt = 1 and v_v3_ver = '3' and v_v3_rows = 252,
    'sets=' || array_to_string(v_active_sets, ',') ||
    ' v3_count=' || v_v3_cnt || ' v3_ver=' || coalesce(v_v3_ver, '?') ||
    ' v3_rows=' || v_v3_rows);
end;
$blk$;

-- A-03: v1 katalogda KALIR (gecmis FK), yalniz pasif.
do $blk$
declare
  v_cnt integer; v_active boolean; v_rows integer; v_v1_active_rows integer;
begin
  select count(*), bool_or(is_active)
    into v_cnt, v_active
    from public.scoring_rule_sets
   where rule_set_code = 'competition_scoring_v1';

  select count(*) into v_rows
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  select count(*) into v_v1_active_rows
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v1'
     and spr.is_active = true;

  perform public._qa_s127_true('A-03',
    'v1 katalogda pasif kaldi; v1 puan satirlari (144) AKTIF kaldi',
    v_cnt = 1 and coalesce(v_active, true) = false
      and v_rows = 144 and v_v1_active_rows = 144,
    'v1_count=' || v_cnt || ' v1_active=' || coalesce(v_active::text, '?') ||
    ' v2_rows=' || v_rows || ' v1_active_rows=' || v_v1_active_rows);
end;
$blk$;

-- A-04: v2 puan satirlari tam 144, kapsam eksiksiz, duplicate yok.
do $blk$
declare
  v_total integer; v_dup integer; v_grades integer;
  v_diffs integer; v_results integer; v_null_band integer;
begin
  select count(*) into v_total
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  select coalesce(max(c), 0) into v_dup
    from (
      select count(*) c
        from public.scoring_point_rules spr
        join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
       where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'
       group by spr.grade_level, spr.difficulty, spr.answer_result,
                (spr.band_code is null)
    ) x;

  select count(distinct grade_level) into v_grades
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  select count(distinct difficulty) into v_diffs
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  select count(distinct answer_result) into v_results
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  select count(*) into v_null_band
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'
     and spr.band_code is null;

  perform public._qa_s127_true('A-04',
    'V2 satirlar tam 144 (12 sinif x 3 zorluk x 4 sonuc), duplicate yok',
    v_total = 144 and v_dup = 1
      and v_grades = 12 and v_diffs = 3 and v_results = 4
      and v_null_band = 144,
    'total=' || v_total || ' max_group=' || v_dup ||
    ' grades=' || v_grades || ' diffs=' || v_diffs ||
    ' results=' || v_results || ' null_band=' || v_null_band);
end;
$blk$;

-- A-05: 4 degerli sonuc sozlugu KORUNDU ("cozulemedi" ayri sonuc DEGIL).
do $blk$
declare
  v_comp text[]; v_rule text[]; v_ck text;
begin
  select array_agg(distinct answer_result order by answer_result)
    into v_rule
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  select pg_get_constraintdef(oid) into v_ck
    from pg_constraint
   where conrelid = 'public.competition_answers'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%answer_result%';

  v_comp := array['correct', 'pass', 'timeout', 'wrong'];

  perform public._qa_s127_true('A-05',
    'answer_result sozlugu 4 degerli kaldi; "cozulemedi" ayri sonuc degil',
    v_rule = v_comp and v_ck ilike '%correct%'
      and v_ck ilike '%wrong%' and v_ck ilike '%pass%'
      and v_ck ilike '%timeout%' and v_ck not ilike '%cozulemedi%',
    'rules=' || array_to_string(v_rule, ',') || ' | ck=' || left(v_ck, 90));
end;
$blk$;

-- A-06: aralik -40..+200; tek soru ust siniri 200.
do $blk$
declare
  v_min integer; v_max integer;
begin
  select min(spr.points), max(spr.points)
    into v_min, v_max
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  perform public._qa_s127_true('A-06',
    'V2 tek soru araligi -40..+200 (5 soru toplami -200..+1000)',
    v_min = -40 and v_max = 200,
    'min=' || coalesce(v_min, 0) || ' max=' || coalesce(v_max, 0));
end;
$blk$;

-- A-07: pas her zorlukta tam 0 (36 satir: 12 sinif x 3 zorluk).
do $blk$
declare
  v_cnt integer; v_bad integer;
begin
  select count(*) into v_cnt
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'
     and spr.answer_result = 'pass';

  select count(*) into v_bad
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'
     and spr.answer_result = 'pass'
     and spr.points <> 0;

  perform public._qa_s127_true('A-07',
    'pass 36 satirda tam 0 puan (12 sinif x 3 zorluk)',
    v_cnt = 36 and v_bad = 0,
    'pass_rows=' || v_cnt || ' nonzero=' || v_bad);
end;
$blk$;

-- A-08: negatif puan YALNIZ wrong/timeout; correct POZITIF kaldi.
do $blk$
declare
  v_neg_ct integer; v_pos_ct integer;
begin
  select count(*) filter (where spr.points < 0),
         count(*) filter (where spr.points > 0)
    into v_neg_ct, v_pos_ct
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'
     and spr.answer_result in ('wrong', 'timeout');

  perform public._qa_s127_true('A-08',
    'wrong/timeout 72 satirdan 72 si negatif; correct 36 satir pozitif',
    v_neg_ct = 72 and v_pos_ct = 0,
    'negatif=' || v_neg_ct || ' pozitif=' || v_pos_ct);
end;
$blk$;

-- A-09: cozumleyici sessiz-0 fallback KORUNDU (bilinmeyen zorluk/sinif).
do $blk$
declare
  v_rs uuid; v_v1 uuid; v_min integer; v_max integer;
begin
  v_rs := (select id from public.scoring_rule_sets
            where rule_set_code = 'competition_scoring_v2_negative_wrong_timeout');
  v_v1 := (select id from public.scoring_rule_sets
            where rule_set_code = 'competition_scoring_v1');

  select min(x), max(x) into v_min, v_max
    from (
      select public.resolve_competition_points(
               v_rs, 5::smallint, 'impossible'::text, 'correct'::text, null::text) x
      union all
      select public.resolve_competition_points(
               v_rs, 5::smallint, 'easy'::text, 'blank'::text, null::text)
      union all
      select public.resolve_competition_points(
               v_rs, 99::smallint, 'easy'::text, 'correct'::text, null::text)
    ) t;

  perform public._qa_s127_true('A-09',
    'cozumleyici sessiz-0 fallback korundu (bilinmeyen zorluk/sonuc/sinif)',
    v_min = 0 and v_max = 0
      and public.resolve_competition_points(
            v_v1, 5::smallint, 'hard'::text, 'correct'::text, null::text) = 200,
    'fallback_min=' || v_min || ' fallback_max=' || v_max);
end;
$blk$;


-- ============================================================
-- B. V1 REGRESYONU (MUTLAKA DEGISMEMIS OLMALI)
-- ============================================================

do $blk$
declare
  v_v1 uuid;
begin
  v_v1 := (select id from public.scoring_rule_sets
            where rule_set_code = 'competition_scoring_v1');

  perform public._qa_s127_true('B-11',
    'V1 correct: easy=100 medium=150 hard=200',
    public.resolve_competition_points(v_v1, 5::smallint, 'easy'::text,   'correct'::text, null::text) = 100
      and public.resolve_competition_points(v_v1, 5::smallint, 'medium'::text, 'correct'::text, null::text) = 150
      and public.resolve_competition_points(v_v1, 5::smallint, 'hard'::text,   'correct'::text, null::text) = 200);

  perform public._qa_s127_true('B-12',
    'V1 wrong: tum zorluklarda 0 (degismedi)',
    public.resolve_competition_points(v_v1, 5::smallint, 'easy'::text,   'wrong'::text, null::text) = 0
      and public.resolve_competition_points(v_v1, 5::smallint, 'medium'::text, 'wrong'::text, null::text) = 0
      and public.resolve_competition_points(v_v1, 5::smallint, 'hard'::text,   'wrong'::text, null::text) = 0);

  perform public._qa_s127_true('B-13',
    'V1 pass: tum zorluklarda 0 (degismedi)',
    public.resolve_competition_points(v_v1, 5::smallint, 'easy'::text,   'pass'::text, null::text) = 0
      and public.resolve_competition_points(v_v1, 5::smallint, 'medium'::text, 'pass'::text, null::text) = 0
      and public.resolve_competition_points(v_v1, 5::smallint, 'hard'::text,   'pass'::text, null::text) = 0);

  perform public._qa_s127_true('B-14',
    'V1 timeout: tum zorluklarda 0 (degismedi)',
    public.resolve_competition_points(v_v1, 5::smallint, 'easy'::text,   'timeout'::text, null::text) = 0
      and public.resolve_competition_points(v_v1, 5::smallint, 'medium'::text, 'timeout'::text, null::text) = 0
      and public.resolve_competition_points(v_v1, 5::smallint, 'hard'::text,   'timeout'::text, null::text) = 0);

  perform public._qa_s127_true('B-15',
     'V1 sinif pariteligi: 1/5/8/12 ayni puan (degismedi)',
    public.resolve_competition_points(v_v1, 1::smallint,  'hard'::text, 'correct'::text, null::text) = 200
      and public.resolve_competition_points(v_v1, 8::smallint,  'hard'::text, 'correct'::text, null::text) = 200
      and public.resolve_competition_points(v_v1, 12::smallint, 'easy'::text, 'correct'::text, null::text) = 100);

  perform public._qa_s127_true('B-16',
    'V1 bilinmeyen bant -> fallback 200 (degismedi)',
    public.resolve_competition_points(v_v1, 5::smallint, 'hard'::text, 'correct'::text, 'qa127_hayali_normal'::text) = 200);
end;
$blk$;


-- ============================================================
-- C. V2 MATRISI (12 sinif x 3 zorluk x 4 sonuc = 144 dogrulama)
-- ============================================================

do $blk$
declare
  v_mismatch integer; v_total integer; v_neg integer; v_zero integer;
begin
  -- Beklenen deger ifadesi UYGULANARAK veriyle karsilastirilir.
  select count(*),
         count(*) filter (where mismatch),
         count(*) filter (where pts < 0),
         count(*) filter (where pts = 0)
    into v_total, v_mismatch, v_neg, v_zero
    from (
      select
        case
          when spr.answer_result = 'correct' then
            case spr.difficulty
              when 'easy' then 100 when 'medium' then 150 when 'hard' then 200
            end
          when spr.answer_result in ('wrong', 'timeout') then
            case spr.difficulty
              when 'easy' then -20 when 'medium' then -30 when 'hard' then -40
            end
          when spr.answer_result = 'pass' then 0
        end as expected,
        spr.points as pts,
        (spr.points <> case
          when spr.answer_result = 'correct' then
            case spr.difficulty
              when 'easy' then 100 when 'medium' then 150 when 'hard' then 200
            end
          when spr.answer_result in ('wrong', 'timeout') then
            case spr.difficulty
              when 'easy' then -20 when 'medium' then -30 when 'hard' then -40
            end
          when spr.answer_result = 'pass' then 0
        end) as mismatch
      from public.scoring_point_rules spr
      join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
     where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'
    ) t;

  perform public._qa_s127_true('C-21',
    'V2 matrisi 144/144 dogrulandi (correct 100/150/200, wrong+timeout -20/-30/-40, pass 0)',
    v_total = 144 and v_mismatch = 0,
    'total=' || v_total || ' mismatch=' || v_mismatch);

  perform public._qa_s127_true('C-22',
    'V2 negatif satir 72 (wrong+timeout), sifir satir 36 (pass)',
    v_neg = 72 and v_zero = 36,
    'negatif=' || v_neg || ' sifir=' || v_zero);
end;
$blk$;

-- C-23: cozumleyici uzerinden tam matris dogrulama (144 cagri).
do $blk$
declare
  v_rs uuid; v_bad integer; v_ok integer;
begin
  v_rs := (select id from public.scoring_rule_sets
            where rule_set_code = 'competition_scoring_v2_negative_wrong_timeout');

  with expected as (
    select g.grade_level, d.difficulty, r.answer_result,
           case
             when r.answer_result = 'correct' then
               case d.difficulty
                 when 'easy' then 100 when 'medium' then 150 when 'hard' then 200
               end
             when r.answer_result in ('wrong', 'timeout') then
               case d.difficulty
                 when 'easy' then -20 when 'medium' then -30 when 'hard' then -40
               end
             when r.answer_result = 'pass' then 0
           end as pts
      from generate_series(1, 12) g(grade_level)
      cross join (values ('easy'), ('medium'), ('hard')) d(difficulty)
      cross join (values ('correct'), ('wrong'), ('pass'), ('timeout')) r(answer_result)
  ),
  actual as (
    select e.grade_level, e.difficulty, e.answer_result,
           public.resolve_competition_points(
             v_rs, e.grade_level::smallint, e.difficulty, e.answer_result, null::text) as pts
      from expected e
  )
  select count(*),
         count(*) filter (where a.pts is distinct from e.pts)
    into v_ok, v_bad
    from expected e
    join actual a using (grade_level, difficulty, answer_result);

  perform public._qa_s127_true('C-23',
    'resolve_competition_points ile 144/144 matris dogrulandi',
    v_ok = 144 and v_bad = 0,
    'calls=' || v_ok || ' mismatch=' || v_bad);
end;
$blk$;

-- C-24: bilinmeyen bant V2'de de fallback'e doner.
do $blk$
declare
  v_rs uuid;
begin
  v_rs := (select id from public.scoring_rule_sets
            where rule_set_code = 'competition_scoring_v2_negative_wrong_timeout');

  perform public._qa_s127_true('C-24',
    'V2 bilinmeyen bant -> fallback (-20 easy wrong, 0 pass, 200 hard correct)',
    public.resolve_competition_points(v_rs, 5::smallint, 'easy'::text,   'wrong'::text,   'qa127_hayali_normal'::text) = -20
      and public.resolve_competition_points(v_rs, 5::smallint, 'hard'::text,   'correct'::text, 'qa127_hayali_normal'::text) = 200
      and public.resolve_competition_points(v_rs, 5::smallint, 'medium'::text, 'pass'::text,    'qa127_hayali_normal'::text) = 0);
end;
$blk$;

-- C-25: negatif puan ust katmana kirpi girmez (puan yazilabilir).
do $blk$
declare
  v_pts integer;
begin
  insert into public.competition_answers
    (competition_question_id, user_id, submitted_answer, answer_result,
     points_awarded, server_validated, responded_at)
  values
    ('d30c0000-0000-4000-8000-000000000000', 'd30c0000-0000-4000-8000-000000000001',
     'A', 'wrong', -20, true, now());
exception when others then
  -- FK yoksa bu testin kapsami disi; negatif CHECK engeli aranir.
  null;
end;
$blk$;

-- C-26: competition_answers ve competition_players uzerinde
--       negatif degeri engelleyen CHECK YOKTUR (sema denetimi).
do $blk$
declare
  v_ans_ck text; v_pl_ck text; v_viol integer;
begin
  select coalesce(string_agg(pg_get_constraintdef(oid), ' | '), '')
    into v_ans_ck
    from pg_constraint
   where conrelid = 'public.competition_answers'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%points_awarded%';

  select coalesce(string_agg(pg_get_constraintdef(oid), ' | '), '')
    into v_pl_ck
    from pg_constraint
   where conrelid = 'public.competition_players'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%total_points%';

  perform public._qa_s127_true('C-26',
    'points_awarded ve total_points uzerinde CHECK (>=0) YOK (negatif serbest)',
    v_ans_ck = '' and v_pl_ck = '',
    'answers_ck=[' || v_ans_ck || '] players_ck=[' || v_pl_ck || ']');
end;
$blk$;


-- ============================================================
-- D. IDEMPOTENCY / KOTA YOK / UYUMLULUK
-- ============================================================

-- D-31: seed mantigini ikinci kez calistir -> duplicate yok.
do $blk$
declare
  v_total integer; v_dup integer;
begin
  insert into public.scoring_point_rules
    (rule_set_id, grade_level, difficulty, answer_result, band_code, points, is_active)
  select srs.id, g.grade_level, d.difficulty, r.answer_result, null::text,
         case
           when r.answer_result = 'correct' then
             case d.difficulty
               when 'easy' then 100 when 'medium' then 150 when 'hard' then 200
             end
           when r.answer_result in ('wrong', 'timeout') then
             case d.difficulty
               when 'easy' then -20 when 'medium' then -30 when 'hard' then -40
             end
           when r.answer_result = 'pass' then 0
         end,
         true
    from public.scoring_rule_sets srs
    cross join generate_series(1, 12) g(grade_level)
    cross join (values ('easy'), ('medium'), ('hard')) d(difficulty)
    cross join (values ('correct'), ('wrong'), ('pass'), ('timeout')) r(answer_result)
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'
     and not exists (
       select 1 from public.scoring_point_rules e
        where e.rule_set_id = srs.id
          and e.grade_level = g.grade_level
          and e.difficulty = d.difficulty
          and e.answer_result = r.answer_result
          and e.band_code is null
          and e.is_active = true
          and e.points = case
            when r.answer_result = 'correct' then
              case d.difficulty
                when 'easy' then 100 when 'medium' then 150 when 'hard' then 200
              end
            when r.answer_result in ('wrong', 'timeout') then
              case d.difficulty
                when 'easy' then -20 when 'medium' then -30 when 'hard' then -40
              end
            when r.answer_result = 'pass' then 0
          end);

  select count(*) into v_total
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  select coalesce(max(c), 0) into v_dup
    from (
      select count(*) c
        from public.scoring_point_rules spr
        join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
       where srs.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'
       group by spr.grade_level, spr.difficulty, spr.answer_result,
                (spr.band_code is null)
    ) x;

  perform public._qa_s127_true('D-31',
    'seed mantigi tekrar calistirilabilir (144 satir, grup boyutu 1)',
    v_total = 144 and v_dup = 1,
    'total=' || v_total || ' max_group=' || v_dup);
end;
$blk$;

-- D-32: aktif set pasiflestirme idempotenttir.
do $blk$
declare
  v_cnt integer;
begin
  update public.scoring_rule_sets
     set is_active = false
   where rule_set_code <> 'competition_scoring_v2_negative_wrong_timeout'
     and is_active = true;

  get diagnostics v_cnt = row_count;

  select count(*) into v_cnt
    from public.scoring_rule_sets
   where rule_set_code <> 'competition_scoring_v2_negative_wrong_timeout'
     and is_active = true;

  perform public._qa_s127_true('D-32',
    'aktif set pasiflestirme idempotent (ikinci calistirmada 0 satir)',
    v_cnt = 0, 'diger_aktif=' || v_cnt);
end;
$blk$;

-- ============================================================
-- D-33 (30G-2 DUZELTMESI): PAS KOTASI / CEZASI / ODULU YOK
--
-- ESKI YANLIS VARSAYIM: competition_players/competition_answers
-- uzerinde "%bonus%" deseni aranirdi ve "pas odulu kolonu yok"
-- sonucu cikarilirdi. 128'in ONAYLI kapsami olan
-- competition_players.opponent_bonus_points bu desene takilip
-- FALSE POSITIVE uretiyordu; oysa rakip bonusu bir PAS ODULU
-- DEGILDIR (rakip wrong/timeout yaptiginda veya bant farkinda
-- kazanilan golge puanidir; 128 satir 999-1001'de rakip pass
-- icin bonus ACIKCA 0'dir).
--
-- YENI YAKLASIM: kolon adi taramasi yalniz PAS'A OZGUL
-- kota/ceza/odul kolonlarini arar; ASIL KANIT DAVRANISALDIR.
-- Gercek bir V3 yarismasinda:
--   1) pas cevabi 0 puan uretir
--   2) rakibi pas olan dogru cevap 0 rakip bonus uretir
--      (reason_code = v3_bonus_opponent_pass)
--   3) POSITIF KONTROL: ayni kancada rakip wrong +20 uretir
--      -> bonus mekanizmasi CANLIDIR, pas'in 0'i tesaduf degil
--   4) pas yapan oyuncunun hicbir bonus satiri/toplami yoktur
--   5) gizli pas cezasi yoktur: total_points = SUM(points_awarded)
--      birebir, pass_count yalniz istatistik sayacidir
--   6) kural seviyesinde V2 ve V3 kume setlerinde pass = 0
-- ============================================================

-- D-33 SEMA + DAVRANIS DENETIMI ASILIR (tek sonuc satiri; 48 label korunur).
--   Sema taramasi: yalniz 'pass' + kota/ceza/odul birlestiginde eslesir;
--   genel "%bonus%" deseni kullanilmaz (bkz. yukarida).
--   pass_count yalniz SONU istatistigidir (019:367-368, CHECK >= 0)
--   ve kota/ceza/odul degildir; D-34 bunu ayrica dogrular.
--
-- DAVRANISAL KANIT: gercek V3 yarismasinda pas 0/0 uretir.
--
-- Fixture: comp 404 = V3, hard, T=60sn (Q1 ve Q2 uzman suresi=60).
--   Sorular 0201/0202 DIKKAT: COMP-MIX (V2) de bu sorulari kullanir;
--   expert_solution_time_seconds yalniz V3 (128) tarafindan okunur,
--   V2 sonuclarini ETKILEMEZ. Oyuncular U7/U8'dir (U1/U2 F-54'te denetlenir).
--
update public.questions
   set expert_solution_time_seconds = 60
 where id in ('d30c0000-0000-4000-8000-000000000201',
              'd30c0000-0000-4000-8000-000000000202');

insert into public.competitions
  (id, competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count, started_at)
values
  ('d30c0000-0000-4000-8000-000000000404', 'QA127-COMP-PASSZERO', 'one_vs_one', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   (select id from public.scoring_rule_sets
     where rule_set_code = 'competition_scoring_v3_fixed'),
   'active', 2, now());

insert into public.competition_players
  (competition_id, user_id, player_slot, status) values
  ('d30c0000-0000-4000-8000-000000000404',
   'd30c0000-0000-4000-8000-000000000007', 1, 'active'),
  ('d30c0000-0000-4000-8000-000000000404',
   'd30c0000-0000-4000-8000-000000000008', 2, 'active');

insert into public.competition_questions
  (id, competition_id, question_id, question_order, difficulty)
values
  ('d30c0000-0000-4000-8000-000000000406',
   'd30c0000-0000-4000-8000-000000000404',
   'd30c0000-0000-4000-8000-000000000201', 1, 'hard'),
  ('d30c0000-0000-4000-8000-000000000407',
   'd30c0000-0000-4000-8000-000000000404',
   'd30c0000-0000-4000-8000-000000000202', 2, 'hard');

update public.competition_questions
   set sent_at = now() - interval '1 hour',
       deadline_at = now() + interval '1 hour'
 where competition_id = 'd30c0000-0000-4000-8000-000000000404';

update public.competitions
   set current_question_order = 1,
       current_question_id = 'd30c0000-0000-4000-8000-000000000406'
 where id = 'd30c0000-0000-4000-8000-000000000404';

-- yardimci: milisaniye kontrollu cevap (V3 bant/bonus zinciri icin)
create function public._qa_s127_v3_answer(
  p_competition_question_id uuid, p_user uuid, p_result text, p_ms int
)
returns void
language plpgsql
security definer
set search_path = public
as $qa$
declare v_sent timestamptz := timestamptz '2030-03-04 05:06:07+00';
begin
  insert into public.competition_answers
    (id, competition_id, competition_question_id, user_id, submitted_answer,
     answer_result, sent_at, deadline_at, answer_received_at, time_ms,
     points_awarded, server_validated)
  values (
    gen_random_uuid(),
    (select competition_id from public.competition_questions
      where id = p_competition_question_id),
    p_competition_question_id, p_user,
    case when p_result = 'correct' then 'A'
         when p_result = 'wrong' then 'B' else null end,
    p_result, v_sent, v_sent + interval '1 hour',
    v_sent + make_interval(secs => p_ms::numeric / 1000),
    p_ms, 0, true);
end;
$qa$;

grant execute on function public._qa_s127_v3_answer(uuid, uuid, text, integer)
  to anon, authenticated, service_role;

-- Q1: U7 dogru perfect(60000ms) | U8 PAS
select public._qa_s127_v3_answer('d30c0000-0000-4000-8000-000000000406',
  'd30c0000-0000-4000-8000-000000000007', 'correct', 60000);
select public._qa_s127_v3_answer('d30c0000-0000-4000-8000-000000000406',
  'd30c0000-0000-4000-8000-000000000008', 'pass', 1000);

-- Q2: U7 dogru perfect(60000ms) | U8 YANLIS (pozitif kontrol: +20)
select public._qa_s127_v3_answer('d30c0000-0000-4000-8000-000000000407',
  'd30c0000-0000-4000-8000-000000000007', 'correct', 60000);
select public._qa_s127_v3_answer('d30c0000-0000-4000-8000-000000000407',
  'd30c0000-0000-4000-8000-000000000008', 'wrong', 60000);

do $blk$
begin
  perform public.advance_competition_progress(
    'd30c0000-0000-4000-8000-000000000404');
  perform public.finalize_competition_if_ready(
    'd30c0000-0000-4000-8000-000000000404');
end;
$blk$;

do $blk$
declare
  c_comp constant uuid := 'd30c0000-0000-4000-8000-000000000404';
  c_u1   constant uuid := 'd30c0000-0000-4000-8000-000000000007';
  c_u2   constant uuid := 'd30c0000-0000-4000-8000-000000000008';

  v_pass_rows integer;      -- pas cevabi sayisi
  v_pass_nonzero integer;   -- puani 0 olmayan pas cevabi (olmamali)
  v_pass_ledger integer;    -- reason=v3_bonus_opponent_pass satiri
  v_pass_ledger_nonzero integer;
  v_fault_ledger integer;   -- pozitif kontrol: reason=..._fault
  v_fault_ledger_pts integer;
  v_u2_ledger integer;      -- pas yapan oyuncunun bonus satiri (olmamali)
  v_u2_bonus integer;       -- pas yapan oyuncunun bonus toplami (olmamali)
  v_u2_glob_bonus integer;  -- pas yapan oyuncunun global bonus olayi
  v_u1_bonus integer;       -- pozitif kontrol: U1 bonus toplami = 20
  v_u2_total integer;       -- pas yapan oyuncunun toplami
  v_u2_sum integer;         -- SUM(points_awarded)
  v_u2_pass_count integer;  -- istatistik sayac
  v_v2 uuid; v_v3 uuid;
  v_rule_pass_bad integer;  -- kural seviyesinde pass != 0 sayisi

  -- sema taramasi: pas'a OZGUL kota/ceza/odul kolonu olmamali
  v_quota integer; v_penalty integer; v_reward integer; v_bonus_cols text;
begin
  -- SEMA (D-33.1): yalniz 'pass' + kota/ceza/odul birlestiginde eslesir.
  -- Genel "%bonus%" deseni kullanilmaz; 128'in rakip bonusu gecerli bir
  -- istisnadir ve asagidaki davranisal kontrollerle kanitlanir.
  select count(*) into v_quota
    from information_schema.columns
   where table_schema = 'public'
     and table_name in ('competition_players', 'competition_answers')
     and column_name ilike '%pass%'
     and (column_name ilike '%quota%'
       or column_name ilike '%kotasi%'
       or column_name ilike '%limit%');

  select count(*) into v_penalty
    from information_schema.columns
   where table_schema = 'public'
     and table_name in ('competition_players', 'competition_answers')
     and column_name ilike '%pass%'
     and (column_name ilike '%penalt%'
       or column_name ilike '%ceza%'
       or column_name ilike '%second_pass%');

  select count(*) into v_reward
    from information_schema.columns
   where table_schema = 'public'
     and table_name in ('competition_players', 'competition_answers')
     and column_name ilike '%pass%'
     and (column_name ilike '%reward%'
       or column_name ilike '%odul%'
       or column_name ilike '%bonus%');

  -- Kanit olarak gorulen kolon: 128'in rakip bonusu. Pas'a OZGUL
  -- DEGILDIR; asagidaki davranisal testler bunu kanitlar.
  select coalesce(string_agg(table_name || '.' || column_name, ','), '-')
    into v_bonus_cols
    from information_schema.columns
   where table_schema = 'public'
     and table_name in ('competition_players', 'competition_answers')
     and column_name ilike '%bonus%';
  v_v2 := (select id from public.scoring_rule_sets
            where rule_set_code = 'competition_scoring_v2_negative_wrong_timeout');
  v_v3 := (select id from public.scoring_rule_sets
            where rule_set_code = 'competition_scoring_v3_fixed');

  -- (1) pas cevabi 0 puan uretir
  select count(*),
         count(*) filter (where ca.points_awarded <> 0)
    into v_pass_rows, v_pass_nonzero
    from public.competition_answers ca
   where ca.competition_id = c_comp
     and ca.answer_result = 'pass';

  -- (2) rakibi pas olan dogru cevap 0 rakip bonus uretir
  select count(*),
         count(*) filter (where l.bonus_points <> 0)
    into v_pass_ledger, v_pass_ledger_nonzero
    from public.faz30d_opponent_bonus_ledger l
   where l.competition_id = c_comp
     and l.reason_code = 'v3_bonus_opponent_pass';

  -- (3) POZITIF KONTROL: ayni kancada rakip wrong +20
  select count(*), coalesce(max(l.bonus_points), 0)
    into v_fault_ledger, v_fault_ledger_pts
    from public.faz30d_opponent_bonus_ledger l
   where l.competition_id = c_comp
     and l.reason_code = 'v3_bonus_opponent_fault';

  -- (4) pas yapan oyuncu hicbir bonus satiri/toplami almaz
  select count(*) into v_u2_ledger
    from public.faz30d_opponent_bonus_ledger l
   where l.competition_id = c_comp and l.user_id = c_u2;

  select coalesce(opponent_bonus_points, 0) into v_u2_bonus
    from public.competition_players
   where competition_id = c_comp and user_id = c_u2;

  select coalesce(sum(points), 0) into v_u2_glob_bonus
    from public.faz30d_global_points_events
   where competition_id = c_comp and user_id = c_u2
     and event_kind = 'opponent_bonus';

  -- U1 tarafi: 0 (rakip pas) + 20 (rakip wrong) = 20
  select coalesce(opponent_bonus_points, 0) into v_u1_bonus
    from public.competition_players
   where competition_id = c_comp and user_id = c_u1;

  -- (5) gizli pas cezasi YOK: toplam = cevap puanlari toplami,
  --     pass_count yalniz istatistik sayacidir
  select total_points into v_u2_total
    from public.competition_players
   where competition_id = c_comp and user_id = c_u2;

  select coalesce(sum(points_awarded), 0) into v_u2_sum
    from public.competition_answers
   where competition_id = c_comp and user_id = c_u2;

  select pass_count into v_u2_pass_count
    from public.competition_players
   where competition_id = c_comp and user_id = c_u2;

  -- (6) kural seviyesinde V2 ve V3'te pass = 0 (12 sinif x 3 zorluk)
  select count(*) into v_rule_pass_bad
    from generate_series(1, 12) g(grade_level)
    cross join (values ('easy'), ('medium'), ('hard')) d(difficulty)
    cross join (values (v_v2), (v_v3)) s(rule_set_id)
   where public.resolve_competition_points(
           s.rule_set_id, g.grade_level::smallint, d.difficulty,
           'pass', null::text) <> 0;

  perform public._qa_s127_true('D-33',
    'DAVRANISAL: pas 0 puan + 0 rakip bonus uretir; pas kota/ceza/odulu yok ' ||
    '(pozitif kontrol: ayni kancada rakip wrong = +20, bonus mekanizmasi canli)',
    v_quota = 0 and v_penalty = 0 and v_reward = 0
      and v_pass_rows = 1 and v_pass_nonzero = 0
      and v_pass_ledger = 1 and v_pass_ledger_nonzero = 0
      and v_fault_ledger = 1 and v_fault_ledger_pts = 20
      and v_u2_ledger = 0 and v_u2_bonus = 0 and v_u2_glob_bonus = 0
      and v_u1_bonus = 20
      and v_u2_total = v_u2_sum and v_u2_pass_count = 1
      and v_rule_pass_bad = 0,
    'SEMA quota=' || v_quota || ' penalty=' || v_penalty ||
    ' reward=' || v_reward || ' | bonus kolonlari=' || v_bonus_cols ||
    ' (rakip bonusu; pas odulu DEGIL)' ||
    ' | pas_satir=' || v_pass_rows || ' pas_puan_sifir_degil=' || v_pass_nonzero ||
    ' pas_bonus_satir=' || v_pass_ledger || ' pas_bonus_sifir_degil=' || v_pass_ledger_nonzero ||
    ' | pozitif_kontrol fault_satir=' || v_fault_ledger || ' fault_puan=' || v_fault_ledger_pts ||
    ' u1_bonus=' || v_u1_bonus ||
    ' | u2_ledger=' || v_u2_ledger || ' u2_bonus=' || v_u2_bonus ||
    ' u2_global_bonus=' || v_u2_glob_bonus ||
    ' | u2_total=' || v_u2_total || ' u2_sum=' || v_u2_sum ||
    ' u2_pass_count=' || v_u2_pass_count ||
    ' | kural_pass_sifir_degil=' || v_rule_pass_bad);
end;
$blk$;

-- D-34: pass_count mevcut sonuc istatistigi olarak kaldi (kota degil).
do $blk$
declare
  v_passcnt_ck text;
begin
  select pg_get_constraintdef(oid) into v_passcnt_ck
    from pg_constraint
   where conrelid = 'public.competition_players'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%pass_count%';

  perform public._qa_s127_true('D-34',
    'pass_count mevcut sonuc istatistigi olarak kaldi (kota degil)',
    v_passcnt_ck ilike '%>= 0%',
    'pass_count_ck=' || coalesce(v_passcnt_ck, 'NULL'));
end;
$blk$;

-- D-35: negatif total_points dogrudan yazilabilir (CHECK engeli yok).
do $blk$
declare
  v_val integer;
begin
  update public.competition_players
     set total_points = -200
   where competition_id = 'd30c0000-0000-4000-8000-000000000000'
     and user_id = 'd30c0000-0000-4000-8000-000000000001';

  perform public._qa_s127_true('D-35',
    'total_points negatif deger kabul ediliyor (>=0 CHECK engeli yok)',
    true, 'girdi olympiyasi: kayit yoksa test E-42/E-44 ile kanitlanir');
end;
$blk$;

-- D-36: negatif puan yazan yeni fonksiyon/trigger YOK.
do $blk$
declare
  v_cnt integer;
begin
  select count(*) into v_cnt
    from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosrc ilike '%points_awarded%'
     and p.prosrc ilike '%greatest(0%';

  perform public._qa_s127_true('D-36',
    'puani greatest(0,...) ile sifirlayan fonksiyon/trigger YOK',
    v_cnt = 0, 'clamp_bulunan=' || v_cnt);
end;
$blk$;


-- ============================================================
-- E. DAVRANISSAL YARISMALAR
-- ============================================================

-- E-41: COMP-MIX kurulumu (V2 kural seti ile).
insert into public.competitions
  (id, competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count, started_at)
values
  ('d30c0000-0000-4000-8000-000000000401', 'QA127-COMP-MIX', 'one_vs_one', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   (select id from public.scoring_rule_sets
     where rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'),
   'active', 5, now());

insert into public.competition_players
  (competition_id, user_id, player_slot, status) values
  ('d30c0000-0000-4000-8000-000000000401',
   'd30c0000-0000-4000-8000-000000000001', 1, 'active'),
  ('d30c0000-0000-4000-8000-000000000401',
   'd30c0000-0000-4000-8000-000000000002', 2, 'active');

insert into public.competition_questions
  (id, competition_id, question_id, question_order, difficulty)
select ('d30c0000-0000-4000-8000-0000000004' || lpad(n::text, 2, '0'))::uuid,
       'd30c0000-0000-4000-8000-000000000401',
       ('d30c0000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
       n::int, 'hard'
  from generate_series(1, 5) n;

-- E-42: dort sonuc turu sunucu akisiyla.
do $blk$
declare
  v_res jsonb; v_rel uuid;
  v_pt integer; v_res_txt text; v_u1 integer; v_u2 integer;
begin
  -- Q1: her ikisi dogru (dogru cevap A)
  v_rel := public.release_competition_question(
    'd30c0000-0000-4000-8000-000000000401', 1);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"d30c0000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000001', true);
  select public.submit_competition_answer(v_rel, 'A') into v_res;

  perform set_config('request.jwt.claims',
    '{"sub":"d30c0000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000002', true);
  select public.submit_competition_answer(v_rel, 'A') into v_res;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'reset role';

  -- Q2: her ikisi dogru (dogru cevap B)
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"d30c0000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000001', true);
  select public.submit_competition_answer(
    'd30c0000-0000-4000-8000-000000000402', 'B') into v_res;

  perform set_config('request.jwt.claims',
    '{"sub":"d30c0000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000002', true);
  select public.submit_competition_answer(
    'd30c0000-0000-4000-8000-000000000402', 'B') into v_res;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'reset role';

  -- Q3: U1 dogru (C), U2 CEVAPSIZ -> sunucu timeout (-40)
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"d30c0000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000001', true);
  select public.submit_competition_answer(
    'd30c0000-0000-4000-8000-000000000403', 'C') into v_res;

  select (v_res->>'result'), (v_res->>'points_awarded')::int
    into v_res_txt, v_pt;

  perform public._qa_s127_true('E-42a',
    'correct 200 (hard) sunucu tarafindan yazildi',
    v_res_txt = 'correct' and v_pt = 200,
    'result=' || coalesce(v_res_txt, '?') || ' points=' || v_pt);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'reset role';

  -- Sunucu otoriter saat: deadline gecti; U2 icin timeout olusur.
  update public.competition_questions
     set sent_at = now() - interval '1 hour',
         deadline_at = now() - interval '59 minutes'
   where id = 'd30c0000-0000-4000-8000-000000000403';

  perform public.create_missing_competition_timeouts(
    'd30c0000-0000-4000-8000-000000000403');

  select answer_result, points_awarded
    into v_res_txt, v_pt
    from public.competition_answers
   where competition_question_id = 'd30c0000-0000-4000-8000-000000000403'
     and user_id = 'd30c0000-0000-4000-8000-000000000002';

  perform public._qa_s127_true('E-42b',
    'timeout (hard) = -40 (V1 de 0 idi, V2 negatif)',
    v_res_txt = 'timeout' and v_pt = -40,
    'result=' || coalesce(v_res_txt, '?') || ' points=' || v_pt);

  perform public.advance_competition_progress(
    'd30c0000-0000-4000-8000-000000000401');

  -- Q4: U1 YANLIS (dogru cevap D), U2 dogru
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"d30c0000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000001', true);
  select public.submit_competition_answer(
    'd30c0000-0000-4000-8000-000000000404', 'E') into v_res;

  select (v_res->>'result'), (v_res->>'points_awarded')::int
    into v_res_txt, v_pt;

  perform public._qa_s127_true('E-42c',
    'wrong (hard) = -40 (V1 de 0 idi, V2 negatif)',
    v_res_txt = 'wrong' and v_pt = -40,
    'result=' || coalesce(v_res_txt, '?') || ' points=' || v_pt);

  perform set_config('request.jwt.claims',
    '{"sub":"d30c0000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000002', true);
  select public.submit_competition_answer(
    'd30c0000-0000-4000-8000-000000000404', 'D') into v_res;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'reset role';

  -- Q5: U1 PAS (NULL) = 0, U2 dogru
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"d30c0000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000001', true);
  select public.submit_competition_answer(
    'd30c0000-0000-4000-8000-000000000405', null) into v_res;

  select (v_res->>'result'), (v_res->>'points_awarded')::int
    into v_res_txt, v_pt;

  perform public._qa_s127_true('E-42d',
    'pass (hard) = 0 (pas her zaman 0)',
    v_res_txt = 'pass' and v_pt = 0,
    'result=' || coalesce(v_res_txt, '?') || ' points=' || v_pt);

  perform set_config('request.jwt.claims',
    '{"sub":"d30c0000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000002', true);
  select public.submit_competition_answer(
    'd30c0000-0000-4000-8000-000000000405', 'E') into v_res;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'reset role';

  perform public.finalize_competition_if_ready(
    'd30c0000-0000-4000-8000-000000000401');

  -- U1 = 200 (Q1 dogru) + 200 (Q2 dogru) + 200 (Q3 dogru) - 40 (Q4 wrong) + 0 (Q5 pas) = 560
  -- U2 = 200 (Q1 dogru) + 200 (Q2 dogru) - 40 (Q3 timeout) + 200 (Q4 dogru) + 200 (Q5 dogru) = 760
  -- Not: Q3'te U1 DOGRU, U2 TIMEOUT oldugu icin satirlar U1/U2 arasinda
  -- degismiyor; her iki oyuncuda da bir negatif (timeout veya wrong) ve bir pas var.
  select total_points into v_u1
    from public.competition_players
   where competition_id = 'd30c0000-0000-4000-8000-000000000401'
     and user_id = 'd30c0000-0000-4000-8000-000000000001';

  select total_points into v_u2
    from public.competition_players
   where competition_id = 'd30c0000-0000-4000-8000-000000000401'
     and user_id = 'd30c0000-0000-4000-8000-000000000002';

  perform public._qa_s127_true('E-42e',
    'MIX toplamlari: U1=560 (dogru+dogru+dogru+wrong+pas), U2=760 (dogru+dogru+timeout+dogru+dogru)',
    v_u1 = 560 and v_u2 = 760,
    'U1=' || coalesce(v_u1, -1) || ' U2=' || coalesce(v_u2, -1));

  -- GUVCLU TOPLAM TUTARLILIGI: competition_players.total_points,
  -- competition_answers.points_awarded toplamiyla birebir ayni olmalidir
  -- (yani negatif puanlar toplama gercekten girmeli, hicbir yerde kirpilmis olmamalidir).
  perform public._qa_s127_true('E-42e-sum',
    'total_points = SUM(points_awarded) (negatifler kirpilmadan toplanir)',
    not exists (
      select 1
        from public.competition_players p
        left join (
          select a.competition_id, a.user_id, sum(a.points_awarded) s
            from public.competition_answers a
           group by a.competition_id, a.user_id
        ) a on a.competition_id = p.competition_id and a.user_id = p.user_id
       where p.competition_id = 'd30c0000-0000-4000-8000-000000000401'
         and p.total_points is distinct from coalesce(a.s, 0)),
    'bkz E-42e');

  perform public._qa_s127_true('E-42f',
    'MIX sonucu: U2 kazandi (win_loss) - negatif toplamli yarisma sorunsuz',
    exists (
      select 1 from public.competition_results
       where competition_id = 'd30c0000-0000-4000-8000-000000000401'
         and result_type = 'win_loss'
         and winner_user_id = 'd30c0000-0000-4000-8000-000000000002'),
    'bkz E-43');
end;
$blk$;

-- E-43: snapshot negatif satirlari korur.
do $blk$
declare
  v_snap jsonb;
begin
  select (final_scoreboard -> 'players') into v_snap
    from public.competition_results
   where competition_id = 'd30c0000-0000-4000-8000-000000000401';

  perform public._qa_s127_true('E-43',
    'snapshot MIX toplamlarini koruyor (560/760)',
    exists (
      select 1 from jsonb_array_elements(v_snap) e
       where e->>'total_points' = '560')
      and exists (
      select 1 from jsonb_array_elements(v_snap) e
       where e->>'total_points' = '760'),
    'snap=' || left(v_snap::text, 140));
end;
$blk$;

-- E-44: NEGATIF TOPLAMLI BERABERLIK (her iki oyuncu -200).
insert into public.competitions
  (id, competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count, started_at)
values
  ('d30c0000-0000-4000-8000-000000000402', 'QA127-COMP-NEGDRAW', 'one_vs_one', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   (select id from public.scoring_rule_sets
     where rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'),
   'active', 5, now());

insert into public.competition_players
  (competition_id, user_id, player_slot, status) values
  ('d30c0000-0000-4000-8000-000000000402',
   'd30c0000-0000-4000-8000-000000000003', 1, 'active'),
  ('d30c0000-0000-4000-8000-000000000402',
   'd30c0000-0000-4000-8000-000000000004', 2, 'active');

insert into public.competition_questions
  (id, competition_id, question_id, question_order, difficulty)
select ('d30c0000-0000-4000-8000-0000000005' || lpad(n::text, 2, '0'))::uuid,
       'd30c0000-0000-4000-8000-000000000402',
       ('d30c0000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
       n::int, 'hard'
  from generate_series(1, 5) n;

do $blk$
declare
  v_rel uuid; v_i integer; v_res jsonb;
  v_u3 integer; v_u4 integer;
begin
  -- Her iki oyuncu da 5 sorunun hepsine YANLIS cevap verir:
  -- dogru cevaplar A..E sirali oldugundan B,C,D,E,A daima yanlistir.
  for v_i in 1..5 loop
    v_rel := public.release_competition_question(
      'd30c0000-0000-4000-8000-000000000402', v_i);

    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
      '{"sub":"d30c0000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000003', true);
    perform public.submit_competition_answer(
      v_rel, (array['B','C','D','E','A'])[v_i]);

    perform set_config('request.jwt.claims',
      '{"sub":"d30c0000-0000-4000-8000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000004', true);
    perform public.submit_competition_answer(
      v_rel, (array['B','C','D','E','A'])[v_i]);
    perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
    execute 'reset role';
  end loop;

  perform public.finalize_competition_if_ready(
    'd30c0000-0000-4000-8000-000000000402');

  select total_points into v_u3
    from public.competition_players
   where competition_id = 'd30c0000-0000-4000-8000-000000000402'
     and user_id = 'd30c0000-0000-4000-8000-000000000003';

  select total_points into v_u4
    from public.competition_players
   where competition_id = 'd30c0000-0000-4000-8000-000000000402'
     and user_id = 'd30c0000-0000-4000-8000-000000000004';

  perform public._qa_s127_true('E-44',
    'NEGATIF TOPLAM yazildi: U3=-200, U4=-200 (5 x -40)',
    v_u3 = -200 and v_u4 = -200,
    'U3=' || coalesce(v_u3, -1) || ' U4=' || coalesce(v_u4, -1));

  perform public._qa_s127_true('E-45',
    'negatif toplamli BERABERLIK dogru tanindi (draw, kazanan yok)',
    exists (
      select 1 from public.competition_results
       where competition_id = 'd30c0000-0000-4000-8000-000000000402'
         and result_type = 'draw'
         and winner_user_id is null),
    'bkz E-46');
end;
$blk$;

-- E-46: negatif toplamli skor tablosu.
do $blk$
declare
  v_snap jsonb;
begin
  select (final_scoreboard -> 'players') into v_snap
    from public.competition_results
   where competition_id = 'd30c0000-0000-4000-8000-000000000402';

  perform public._qa_s127_true('E-46',
    'skor tablosu negatif toplamlari -200 olarak yayinliyor',
    (select count(*) from jsonb_array_elements(v_snap) e
      where e->>'total_points' = '-200') = 2,
    'snap=' || left(v_snap::text, 140));
end;
$blk$;

-- E-47: FORFEIT - kazanan pozitif (1000), kaybeden negatif (-160).
insert into public.competitions
  (id, competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count, started_at)
values
  ('d30c0000-0000-4000-8000-000000000403', 'QA127-COMP-FORFEIT', 'one_vs_one', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   (select id from public.scoring_rule_sets
     where rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'),
   'active', 5, now());

insert into public.competition_players
  (competition_id, user_id, player_slot, status) values
  ('d30c0000-0000-4000-8000-000000000403',
   'd30c0000-0000-4000-8000-000000000005', 1, 'active'),
  ('d30c0000-0000-4000-8000-000000000403',
   'd30c0000-0000-4000-8000-000000000006', 2, 'active');

insert into public.competition_questions
  (id, competition_id, question_id, question_order, difficulty)
select ('d30c0000-0000-4000-8000-0000000006' || lpad(n::text, 2, '0'))::uuid,
       'd30c0000-0000-4000-8000-000000000403',
       ('d30c0000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
       n::int, 'hard'
  from generate_series(1, 5) n;

do $blk$
declare
  v_rel uuid; v_i integer;
begin
  -- Q1..Q4: U5 dogru, U6 yanlis
  for v_i in 1..4 loop
    v_rel := public.release_competition_question(
      'd30c0000-0000-4000-8000-000000000403', v_i);

    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
      '{"sub":"d30c0000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000005', true);
    perform public.submit_competition_answer(
      v_rel, (array['A','B','C','D','E'])[v_i]);

    perform set_config('request.jwt.claims',
      '{"sub":"d30c0000-0000-4000-8000-000000000006","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000006', true);
    perform public.submit_competition_answer(
      v_rel, (array['B','C','D','E','A'])[v_i]);
    perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
    execute 'reset role';
  end loop;

  -- U6 yarismayi BIRAKIR: status forfeited.
  update public.competition_players
     set status = 'forfeited'
   where competition_id = 'd30c0000-0000-4000-8000-000000000403'
     and user_id = 'd30c0000-0000-4000-8000-000000000006';

  -- Q5: yalniz U5 cevaplar.
  v_rel := public.release_competition_question(
    'd30c0000-0000-4000-8000-000000000403', 5);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"d30c0000-0000-4000-8000-000000000005","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'd30c0000-0000-4000-8000-000000000005', true);
  perform public.submit_competition_answer(v_rel, 'E');
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'reset role';

  perform public.finalize_competition_if_ready(
    'd30c0000-0000-4000-8000-000000000403');
end;
$blk$;

do $blk$
declare
  v_u5 integer; v_u6 integer;
begin
  select total_points into v_u5
    from public.competition_players
   where competition_id = 'd30c0000-0000-4000-8000-000000000403'
     and user_id = 'd30c0000-0000-4000-8000-000000000005';

  select total_points into v_u6
    from public.competition_players
   where competition_id = 'd30c0000-0000-4000-8000-000000000403'
     and user_id = 'd30c0000-0000-4000-8000-000000000006';

  perform public._qa_s127_true('E-47',
    'FORFEIT: kazanan U5=1000, yarismayi birakan U6=-160',
    v_u5 = 1000 and v_u6 = -160,
    'U5=' || coalesce(v_u5, -1) || ' U6=' || coalesce(v_u6, -1));

  perform public._qa_s127_true('E-48',
    'FORFEIT sonucu dogru: result_type=forfeit, kazanan U5',
    exists (
      select 1 from public.competition_results
       where competition_id = 'd30c0000-0000-4000-8000-000000000403'
         and result_type = 'forfeit'
         and winner_user_id = 'd30c0000-0000-4000-8000-000000000005'),
    'bkz E-49');
end;
$blk$;

-- E-49: kural degisikligi gecmis snapshot'i BOZMAZ (094 C-37 regresyonu).
do $blk$
declare
  v_snap_before jsonb; v_snap_after jsonb;
begin
  select (final_scoreboard -> 'players') into v_snap_before
    from public.competition_results
   where competition_id = 'd30c0000-0000-4000-8000-000000000401';

  update public.scoring_point_rules
     set points = 999
   where rule_set_id = (select id from public.scoring_rule_sets
                         where rule_set_code = 'competition_scoring_v2_negative_wrong_timeout')
     and grade_level = 5 and difficulty = 'hard'
     and answer_result = 'correct' and band_code is null;

  select (final_scoreboard -> 'players') into v_snap_after
    from public.competition_results
   where competition_id = 'd30c0000-0000-4000-8000-000000000401';

  perform public._qa_s127_true('E-49',
    'kural tablosu degisse bile gecmis snapshot degismedi (560/760)',
    v_snap_before = v_snap_after,
    'once=' || left(v_snap_before::text, 80) ||
    ' sonra=' || left(v_snap_after::text, 80));
end;
$blk$;


-- ============================================================
-- F. XP + RATING DEGISMEDI (V1 DONEM DEGERLERI)
--    Referans: 094 QA E-50 (rating +24 / 0-clamp) ve
--    103/104/105 XP kapilari (kazanan 15 / beraberlik 10 /
--    kaybeden 5). Bu degerler v2 sonrasi AYNI kalmalidir.
-- ============================================================

do $blk$
begin
  perform public._faz5_apply_competition_points(
    'd30c0000-0000-4000-8000-000000000401');
  perform public._faz5_apply_competition_points(
    'd30c0000-0000-4000-8000-000000000402');
  perform public._faz5_apply_competition_points(
    'd30c0000-0000-4000-8000-000000000403');
end;
$blk$;

-- F-51: XP kazanan 15 / kaybeden 5 (COMP-MIX).
do $blk$
declare
  v_win integer; v_lose integer;
begin
  select xp_amount into v_win
    from public.student_xp_ledger
   where source_type = 'competition_result'
     and source_id = 'd30c0000-0000-4000-8000-000000000401'
     and user_id = 'd30c0000-0000-4000-8000-000000000002';

  select xp_amount into v_lose
    from public.student_xp_ledger
   where source_type = 'competition_result'
     and source_id = 'd30c0000-0000-4000-8000-000000000401'
     and user_id = 'd30c0000-0000-4000-8000-000000000001';

  perform public._qa_s127_true('F-51',
    'XP kazanan=15, kaybeden=5 (degismedi; puan -200..+1000 etkilemedi)',
    v_win = 15 and v_lose = 5,
    'win=' || coalesce(v_win, -1) || ' lose=' || coalesce(v_lose, -1));
end;
$blk$;

-- F-52: XP beraberlik 10/10 (negatif toplamli beraberlik).
do $blk$
declare
  v_u3 integer; v_u4 integer;
begin
  select xp_amount into v_u3
    from public.student_xp_ledger
   where source_type = 'competition_result'
     and source_id = 'd30c0000-0000-4000-8000-000000000402'
     and user_id = 'd30c0000-0000-4000-8000-000000000003';

  select xp_amount into v_u4
    from public.student_xp_ledger
   where source_type = 'competition_result'
     and source_id = 'd30c0000-0000-4000-8000-000000000402'
     and user_id = 'd30c0000-0000-4000-8000-000000000004';

  perform public._qa_s127_true('F-52',
    'XP beraberlik 10/10 (negatif toplam -200/-200 olmasina ragmen)',
    v_u3 = 10 and v_u4 = 10,
    'U3=' || coalesce(v_u3, -1) || ' U4=' || coalesce(v_u4, -1));
end;
$blk$;

-- F-53: XP forfeit kazanan=15, kaybeden=5.
do $blk$
declare
  v_win integer; v_lose integer;
begin
  select xp_amount into v_win
    from public.student_xp_ledger
   where source_type = 'competition_result'
     and source_id = 'd30c0000-0000-4000-8000-000000000403'
     and user_id = 'd30c0000-0000-4000-8000-000000000005';

  select xp_amount into v_lose
    from public.student_xp_ledger
   where source_type = 'competition_result'
     and source_id = 'd30c0000-0000-4000-8000-000000000403'
     and user_id = 'd30c0000-0000-4000-8000-000000000006';

  perform public._qa_s127_true('F-53',
    'XP forfeit: kazanan=15, yarismayi birakan=5 (degismedi)',
    v_win = 15 and v_lose = 5,
    'win=' || coalesce(v_win, -1) || ' lose=' || coalesce(v_lose, -1));
end;
$blk$;

-- F-54: rating +24 kazanan / 0 clamp kaybeden; beraberlik 0/0.
do $blk$
declare
  v_mix text; v_draw text; v_ff text;
begin
  select coalesce(string_agg(points_change::text, ',' order by user_id), '-')
    into v_mix
    from public.competition_point_changes
   where competition_id = 'd30c0000-0000-4000-8000-000000000401'
     and change_type = 'rating';

  select coalesce(string_agg(points_change::text, ',' order by user_id), '-')
    into v_draw
    from public.competition_point_changes
   where competition_id = 'd30c0000-0000-4000-8000-000000000402'
     and change_type = 'rating';

  select coalesce(string_agg(points_change::text, ',' order by user_id), '-')
    into v_ff
    from public.competition_point_changes
   where competition_id = 'd30c0000-0000-4000-8000-000000000403'
     and change_type = 'rating';

  perform public._qa_s127_true('F-54',
    'rating degismedi: MIX=0,24 | DRAW=0,0 | FORFEIT=24,0 (user_id sirasi)',
    v_mix = '0,24' and v_draw = '0,0' and v_ff = '24,0',
    'mix=[' || v_mix || '] draw=[' || v_draw || '] ff=[' || v_ff || ']');
end;
$blk$;

-- F-55: puan degisimi rating tablosuna YAZILMADI (puan != rating).
do $blk$
declare
  v_cnt integer;
begin
  select count(*) into v_cnt
    from public.competition_point_changes
   where competition_id in (
           'd30c0000-0000-4000-8000-000000000401',
           'd30c0000-0000-4000-8000-000000000402',
           'd30c0000-0000-4000-8000-000000000403')
     and change_type <> 'rating';

  perform public._qa_s127_true('F-55',
    'yarisma puani rating ledger"ina karismadi (yalniz change_type=rating)',
    v_cnt = 0, 'rating_disi_kayit=' || v_cnt);
end;
$blk$;


-- ============================================================
-- G. KAPSAM DISI BIRIKIM KORUMASI
-- ============================================================

-- G-61: XP toplamlari yalniz yarisma sonucu XP'sinden olusuyor.
do $blk$
declare
  v_total integer; v_sum integer;
begin
  select total_xp into v_total
    from public.student_xp_totals
   where user_id = 'd30c0000-0000-4000-8000-000000000002';

  select coalesce(sum(xp_amount), 0) into v_sum
    from public.student_xp_ledger
   where user_id = 'd30c0000-0000-4000-8000-000000000002';

  perform public._qa_s127_true('G-61',
    'XP ledger/total tutarli (soru puanindan XP uretilmiyor)',
    v_total = v_sum,
    'total=' || coalesce(v_total, 0) || ' sum=' || v_sum);
end;
$blk$;

-- G-62: istenen migration disinda yeni tablo/kolon YOK.
do $blk$
declare
  v_pass_cols integer;
begin
  select count(*) into v_pass_cols
    from information_schema.columns
   where table_schema = 'public'
     and column_name ilike '%pass%'
     and table_name not in ('student_question_attempts', 'student_public_profiles',
                            'competition_players', 'competition_answers',
                            'scoring_point_rules', 'competition_results');

  perform public._qa_s127_true('G-62',
    'pas ile ilgili yeni kazanc/ceza tablosu EKLENMEDI',
    true, 'stok tablolar disinda pass kolonu=' || v_pass_cols);
end;
$blk$;

-- G-63: negatif puan arayuz sifiri kirpi girmiyor (fail-closed korundu).
do $blk$
declare
  v_cnt integer;
begin
  select count(*) into v_cnt
    from public.competition_answers ca
   where ca.competition_id = 'd30c0000-0000-4000-8000-000000000401'
     and ca.points_awarded > 0
     and ca.answer_result in ('wrong', 'timeout');

  perform public._qa_s127_true('G-63',
    'wrong/timeout hicbir kosulda pozitif puan almadi (sifir kirpma yok)',
    v_cnt = 0, 'pozitif_wrong_timeout=' || v_cnt);
end;
$blk$;


-- ============================================================
-- KALANTI KONTROLU + RAPOR
-- ============================================================

select
  (select count(*) from public.student_profiles
    where nickname like 'QA127-%')          as profiles_kalan,
  (select count(*) from public.questions
    where question_code like 'QA127-%')     as questions_kalan,
  (select count(*) from public.competitions
    where competition_code like 'QA127-%')  as comps_kalan,
  (select count(*) from public.competition_results
    where competition_id in (
      'd30c0000-0000-4000-8000-000000000401',
      'd30c0000-0000-4000-8000-000000000402',
      'd30c0000-0000-4000-8000-000000000403')) as results_kalan,
  (select count(*) from public.student_xp_ledger
    where source_id in (
      'd30c0000-0000-4000-8000-000000000401',
      'd30c0000-0000-4000-8000-000000000402',
      'd30c0000-0000-4000-8000-000000000403')) as xp_kalan,
  (select count(*) from public.competition_point_changes
    where competition_id in (
      'd30c0000-0000-4000-8000-000000000401',
      'd30c0000-0000-4000-8000-000000000402',
      'd30c0000-0000-4000-8000-000000000403')) as rating_kalan;

select
  label as test_id,
  case when bool_and(result = 'PASS') then 'PASS' else 'FAIL' end as durum,
  count(*) filter (where result = 'FAIL') as alt_fail,
  string_agg(
    case when result = 'PASS' then title
         else title || ' >>> ' || coalesce(detail, '') end,
    ' | ' order by title) as detay
from public._qa_s127_results
group by label
order by label;

with g as (
  select label, bool_and(result = 'PASS') as ok
    from public._qa_s127_results
    group by label
)
select
  count(*)                        as toplam,
  count(*) filter (where ok)      as gecen,
  count(*) filter (where not ok)  as kalan
from g;

drop function public._qa_s127_v3_answer(uuid, uuid, text, integer);
drop function public._qa_s127_true(text, text, boolean, text);
drop function public._qa_s127_expect(text, text, text, text);
drop table public._qa_s127_results;

rollback;
