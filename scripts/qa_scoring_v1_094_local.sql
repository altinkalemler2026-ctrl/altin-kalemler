-- ============================================================
-- scripts/qa_scoring_v1_094_local.sql
-- Altin Kalemler - Migration 094 yerel QA suite
-- (Yarisma puanlama sozlesmesi V1)
--
-- Kapsam:
--   A-01..A-10 : seed/katalog (tek set, idempotency, kapsam,
--                negatif yok, ust sinir)
--   B-11..B-24 : puan cozumleyici (fallback matrisi, bilinmeyen
--                bant davranisi, sinif paritesi)
--   C-25..C-38 : davranissal yarisma (sunucu degerlendirme,
--                timeout, duplicate, finalize, snapshot,
--                rating idempotency)
--   D-39..D-45 : yetki matrisi
--   E-46..E-50 : regresyon (093, havuz ayrigi, <=5, matchmaking,
--                lig rating +24/-12)
--
-- NOT: Onayli sure bandi seed'i olmadigi icin V1 fallback
-- matrisi gecerlidir: correct easy=100/medium=150/hard=200,
-- diger sonuclar 0. Bilinmeyen/NULL bant fallback'e doner.
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_scoring_v1_094_local.sql <db>:/tmp/
--   docker exec <db> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -A -t -f /tmp/qa_scoring_v1_094_local.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;

create table public._qa_s94_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_s94_results
  to anon, authenticated, service_role;

create function public._qa_s94_expect(
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
      insert into public._qa_s94_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_s94_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_s94_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_s94_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa_s94_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_s94_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa_s94_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_s94_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR (sabit QA uuid'leri; rollback ile silinecek)
-- matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
--   U1 : 5. sinif (yarisma kazanani + antrenman kullanicisi)
--   U2 : 5. sinif (yarisma kaybedeni)
--   U3 : 6. sinif (matchmaking sinif-izolasyon karsi-tarafi)
-- ============================================================

insert into auth.users (id, email) values
  ('94000000-0000-0000-0000-000000000091', 'qa94-user-a@test.local'),
  ('94000000-0000-0000-0000-000000000092', 'qa94-user-b@test.local'),
  ('94000000-0000-0000-0000-000000000093', 'qa94-user-c@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('94000000-0000-0000-0000-000000000091', 5, 'QA94-NICK-A'),
  ('94000000-0000-0000-0000-000000000092', 5, 'QA94-NICK-B'),
  ('94000000-0000-0000-0000-000000000093', 6, 'QA94-NICK-C');

insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('94949494-9494-9494-9494-949494940001', 'QA94-Y', 'MEB-QA94', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('94949494-9494-9494-9494-949494940002', 'QA94-SCHED', 'QA94 Profil',
   '94949494-9494-9494-9494-949494940001', true, true);

insert into public.academic_weeks (academic_year, week, starts_at, ends_at) values
  ('QA94-Y', 5, current_date - 3, current_date + 4);

insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('94949494-9494-9494-9494-949494940010',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   5, 'QA94 Konu', 'qa94-konu',
   '94949494-9494-9494-9494-949494940001');

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, start_week, end_week) values
  ('94949494-9494-9494-9494-949494940002', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '94949494-9494-9494-9494-949494940010', 1, null);

-- 5 yarisma sorusu (hard, tek-yanitlik A..E) â€” 094 oncesi
-- kural olmadigi icin dogru cevaplarin puani 0 olurdu.
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
select ('94949494-9494-9494-9494-94949494100' || n)::uuid,
       'QA94-C-' || n, 5,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
       'hard', 'learning', 'coktan_secmeli',
       (array['A','B','C','D','E'])[n::int], true, 45
  from unnest(array['1','2','3','4','5']) n;

-- 1 antrenman sorusu (practice kasasi).
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
values
  ('94949494-9494-9494-9494-949494941101', 'QA94-P1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45);

-- Mufredat eslemeleri (hem yarisma hem antrenman sorusu icin).
insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, review_status)
select q.id, '94949494-9494-9494-9494-949494940001',
       '94949494-9494-9494-9494-949494940010', 'approved'
  from public.questions q
 where q.question_code like 'QA94-%';

-- Kasalar: 1v1 (5 soru) + practice (yalniz P1).
insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('94949494-9494-9494-9494-949494942001', 'QA94-V-1V1',
   'QA94 1v1 Kasasi', 'one_v_one', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa'),
  ('94949494-9494-9494-9494-949494942002', 'QA94-V-PRACTICE',
   'QA94 Antrenman Kasasi', 'practice', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, one_v_one_eligible, competition_eligible)
select '94949494-9494-9494-9494-949494942001',
       ('94949494-9494-9494-9494-94949494100' || n)::uuid, 'active', true, true
  from unnest(array['1','2','3','4','5']) n;

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, practice_eligible)
values ('94949494-9494-9494-9494-949494942002',
        '94949494-9494-9494-9494-949494941101', 'active', true);

-- Yarisma: dogrudan kurulmus aktif 1v1, 5 hard soru, V1 kural seti.
insert into public.competitions
  (id, competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count, started_at)
values
  ('94949494-9494-9494-9494-949494943001', 'QA94-COMP-1', 'one_vs_one', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   (select id from public.scoring_rule_sets
     where rule_set_code = 'competition_scoring_v1'),
   'active', 5, now());

insert into public.competition_players
  (competition_id, user_id, player_slot, status) values
  ('94949494-9494-9494-9494-949494943001',
   '94000000-0000-0000-0000-000000000091', 1, 'active'),
  ('94949494-9494-9494-9494-949494943001',
   '94000000-0000-0000-0000-000000000092', 2, 'active');

insert into public.competition_questions
  (id, competition_id, question_id, question_order, difficulty)
select
  ('94949494-9494-9494-9494-94949494400' || n)::uuid,
  '94949494-9494-9494-9494-949494943001',
  ('94949494-9494-9494-9494-94949494100' || n)::uuid,
  n::int, 'hard'
  from unnest(array['1','2','3','4','5']) n;


-- ############################################################
-- A. SEED VE KATALOG
-- ############################################################

-- A-01: V1 kural seti tam olarak bir kez, aktif ve versiyonlu.
do $blk$
declare
  v_cnt integer; v_active boolean; v_ver text;
begin
  select count(*), bool_or(is_active), max(version)
    into v_cnt, v_active, v_ver
    from public.scoring_rule_sets
   where rule_set_code = 'competition_scoring_v1';

  perform public._qa_s94_true('A-01',
    'V1 rule set tam bir kez, aktif, version=1',
    v_cnt = 1 and v_active and v_ver = '1',
    'count=' || v_cnt || ' active=' || v_active || ' ver=' || v_ver);
end;
$blk$;

-- A-02: tek aktif kural seti (faz5_default pasif).
do $blk$
declare
  v_active_sets text[];
begin
  select coalesce(array_agg(rule_set_code), '{}')
    into v_active_sets
    from public.scoring_rule_sets
   where is_active = true;

  perform public._qa_s94_true('A-02',
    'tek aktif kural seti: competition_scoring_v1',
    v_active_sets = array['competition_scoring_v1'],
    'sets=' || array_to_string(v_active_sets, ','));
end;
$blk$;

-- A-03/A-04/A-05/A-06/A-08: kapsam ve idempotency.
do $blk$
declare
  v_total integer; v_dup integer; v_grades integer;
  v_diffs integer; v_results integer; v_null_band integer;
begin
  select count(*) into v_total
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v1';

  select count(*) into v_dup
    from (
      select rule_set_id, grade_level, difficulty, answer_result,
             (band_code is null) as no_band, count(*) c
        from public.scoring_point_rules spr
        join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
       where srs.rule_set_code = 'competition_scoring_v1'
       group by 1,2,3,4,5
    ) x where c > 1;

  select count(distinct grade_level) into v_grades
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v1';

  select count(distinct difficulty) into v_diffs
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v1';

  select count(distinct answer_result) into v_results
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v1';

  select count(*) into v_null_band
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v1'
     and spr.band_code is null;

  perform public._qa_s94_true('A-03',
    'puan satirlari tam 144 (12 sinif x 3 zorluk x 4 sonuc)',
    v_total = 144, 'total=' || v_total);

  perform public._qa_s94_true('A-04',
    'grade 1-12 kapsami eksiksiz',
    v_grades = 12, 'grades=' || v_grades);

  perform public._qa_s94_true('A-05',
    'easy/medium/hard kapsamli',
    v_diffs = 3, 'diffs=' || v_diffs);

  perform public._qa_s94_true('A-06',
    'correct/wrong/pass/timeout kapsamli',
    v_results = 4, 'results=' || v_results);

  perform public._qa_s94_true('A-08',
    'tum satirlar NULL/fallback bantli (onayli bant yok)',
    v_null_band = 144, 'null_band=' || v_null_band);

  -- Idempotency: seed mantiginin aynisini tekrar calistir.
  insert into public.scoring_point_rules
    (rule_set_id, grade_level, difficulty, answer_result, band_code, points, is_active)
  select srs.id, g2.grade_level, d2.difficulty, r2.answer_result, NULL::text,
         case
           when r2.answer_result <> 'correct' then 0
           when d2.difficulty = 'easy'   then 100
           when d2.difficulty = 'medium' then 150
           when d2.difficulty = 'hard'   then 200
         end,
         true
  from public.scoring_rule_sets srs
  cross join (values (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) as g2(grade_level)
  cross join (values ('easy'),('medium'),('hard')) as d2(difficulty)
  cross join (values ('correct'),('wrong'),('pass'),('timeout')) as r2(answer_result)
  where srs.rule_set_code = 'competition_scoring_v1'
    and not exists (
      select 1 from public.scoring_point_rules e
       where e.rule_set_id = srs.id
         and e.grade_level = g2.grade_level
         and e.difficulty = d2.difficulty
         and e.answer_result = r2.answer_result
         and e.band_code is null
         and e.is_active = true
         and e.points = case
           when r2.answer_result <> 'correct' then 0
           when d2.difficulty = 'easy'   then 100
           when d2.difficulty = 'medium' then 150
           when d2.difficulty = 'hard'   then 200
         end);

  select count(*), max(x.c) into v_total, v_dup
    from (
      select count(*) c
        from public.scoring_point_rules spr
        join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
       where srs.rule_set_code = 'competition_scoring_v1'
       group by spr.grade_level, spr.difficulty, spr.answer_result,
                (spr.band_code is null)
    ) x;

  perform public._qa_s94_true('A-07',
    'tekrar seed mantigi duplicate uretmez (grup boyutlari=1, toplam 144)',
    v_total = 144 and coalesce(v_dup, 1) = 1,
    'total=' || v_total || ' max_group=' || coalesce(v_dup, 0));
end;
$blk$;

-- A-09/A-10: negatif yok; ust sinir.
do $blk$
declare
  v_min integer; v_max integer;
begin
  select min(spr.points), max(spr.points)
    into v_min, v_max
    from public.scoring_point_rules spr
    join public.scoring_rule_sets srs on srs.id = spr.rule_set_id
   where srs.rule_set_code = 'competition_scoring_v1';

  perform public._qa_s94_true('A-09',
    'negatif puan yok (min >= 0)',
    coalesce(v_min, 0) >= 0, 'min=' || coalesce(v_min, 0));

  perform public._qa_s94_true('A-10',
    'tek soru ust siniri: seed max=200 ve matris siniri 300 asilmaz',
    coalesce(v_max, 0) = 200 and coalesce(v_max, 0) <= 300,
    'max=' || coalesce(v_max, 0));
end;
$blk$;


-- ############################################################
-- B. PUAN COZUMLEYICI (fallback matrisi)
-- ############################################################

do $blk$
declare
  v_rs uuid;
begin
  v_rs := (select id from public.scoring_rule_sets
            where rule_set_code = 'competition_scoring_v1');

  perform public._qa_s94_true('B-11',
    'kolay-yavas(NULL) dogru = 100',
    public.resolve_competition_points(v_rs, 5::smallint, 'easy'::text, 'correct'::text, null::text) = 100);

  perform public._qa_s94_true('B-14',
    'orta-yavas(NULL) dogru = 150',
    public.resolve_competition_points(v_rs, 5::smallint, 'medium'::text, 'correct'::text, null::text) = 150);

  perform public._qa_s94_true('B-17',
    'zor-yavas(NULL) dogru = 200',
    public.resolve_competition_points(v_rs, 5::smallint, 'hard'::text, 'correct'::text, null::text) = 200);

  -- Normal/Hizli bantlar henuz seed EDILMEDI; bilinmeyen bant
  -- fallback'e doner (matristeki ayrilmis degerler bantlar
  -- onaylaninca devreye girer).
  perform public._qa_s94_true('B-12',
    'kolay bilinmeyen bant -> fallback 100 (bantli 120 ayrimli)',
    public.resolve_competition_points(v_rs, 5::smallint, 'easy'::text, 'correct'::text, 'qa94_hayali_normal'::text) = 100);

  perform public._qa_s94_true('B-15',
    'orta bilinmeyen bant -> fallback 150 (bantli 180 ayrimli)',
    public.resolve_competition_points(v_rs, 5::smallint, 'medium'::text, 'correct'::text, 'qa94_hayali_normal'::text) = 150);

  perform public._qa_s94_true('B-18',
    'zor bilinmeyen bant -> fallback 200 (bantli 240 ayrimli)',
    public.resolve_competition_points(v_rs, 5::smallint, 'hard'::text, 'correct'::text, 'qa94_hayali_normal'::text) = 200);

  perform public._qa_s94_true('B-13',
    'kolay hizli banti tanimsiz -> fallback 100 (150 ayrimli)',
    public.resolve_competition_points(v_rs, 5::smallint, 'easy'::text, 'correct'::text, 'qa94_hayali_normal'::text) = 100);

  perform public._qa_s94_true('B-16',
    'orta hizli banti tanimsiz -> fallback 150 (225 ayrimli)',
    public.resolve_competition_points(v_rs, 5::smallint, 'medium'::text, 'correct'::text, 'qa94_hayali_normal'::text) = 150);

  perform public._qa_s94_true('B-19',
    'zor hizli banti tanimsiz -> fallback 200 (300 ayrimli)',
    public.resolve_competition_points(v_rs, 5::smallint, 'hard'::text, 'correct'::text, 'qa94_hayali_normal'::text) = 200);

  -- B-20/21/22: wrong/pass/timeout tum zorluklarda 0.
  perform public._qa_s94_true('B-20',
    'wrong: tum zorluklarda 0',
    public.resolve_competition_points(v_rs, 5::smallint, 'easy'::text, 'wrong'::text, null::text) = 0
      and public.resolve_competition_points(v_rs, 5::smallint, 'medium'::text, 'wrong'::text, null::text) = 0
      and public.resolve_competition_points(v_rs, 5::smallint, 'hard'::text, 'wrong'::text, null::text) = 0);

  perform public._qa_s94_true('B-21',
    'pass: tum zorluklarda 0',
    public.resolve_competition_points(v_rs, 5::smallint, 'easy'::text, 'pass'::text, null::text) = 0
      and public.resolve_competition_points(v_rs, 5::smallint, 'medium'::text, 'pass'::text, null::text) = 0
      and public.resolve_competition_points(v_rs, 5::smallint, 'hard'::text, 'pass'::text, null::text) = 0);

  perform public._qa_s94_true('B-22',
    'timeout: tum zorluklarda 0',
    public.resolve_competition_points(v_rs, 5::smallint, 'easy'::text, 'timeout'::text, null::text) = 0
      and public.resolve_competition_points(v_rs, 5::smallint, 'medium'::text, 'timeout'::text, null::text) = 0
      and public.resolve_competition_points(v_rs, 5::smallint, 'hard'::text, 'timeout'::text, null::text) = 0);

  -- B-23: NULL bant fallback (expilkit).
  perform public._qa_s94_true('B-23',
    'NULL bant dogru cevap temel puana doner',
    public.resolve_competition_points(v_rs, 5::smallint, 'easy'::text, 'correct'::text, null::text) = 100
      and public.resolve_competition_points(v_rs, 5::smallint, 'medium'::text, 'correct'::text, null::text) = 150
      and public.resolve_competition_points(v_rs, 5::smallint, 'hard'::text, 'correct'::text, null::text) = 200);

  -- B-24: sinif 1,5,8,12 ayni puan.
  perform public._qa_s94_true('B-24',
    'sinif 1/5/8/12 ayni kural ayni puan',
    public.resolve_competition_points(v_rs, 1::smallint, 'hard'::text, 'correct'::text, null::text) = 200
      and public.resolve_competition_points(v_rs, 5::smallint, 'hard'::text, 'correct'::text, null::text) = 200
      and public.resolve_competition_points(v_rs, 8::smallint, 'hard'::text, 'correct'::text, null::text) = 200
      and public.resolve_competition_points(v_rs, 12::smallint, 'hard'::text, 'correct'::text, null::text) = 200
      and public.resolve_competition_points(v_rs, 1::smallint, 'easy'::text, 'correct'::text, null::text)
        = public.resolve_competition_points(v_rs, 12::smallint, 'easy'::text, 'correct'::text, null::text));
end;
$blk$;


-- ############################################################
-- C. DAVRANISSEL YARISMA
-- ############################################################

-- Gercek 023 akisi: release -> cevap -> advance -> finalize.
-- Sunucu zamanlamayi yonetir; istemci yalniz cevap gonderir.
do $blk$
declare
  v_res jsonb;
  v_rel uuid;
  v_status text;
begin
  -- C-25: soru 1'i sunucu akisiyla ac (server otoriter saat).
  v_rel := public.release_competition_question(
    '94949494-9494-9494-9494-949494943001', 1);

  perform public._qa_s94_true('C-25',
    'soru sunucuda acildi: sent_at/deadline server tarafindan atandi',
    v_rel = '94949494-9494-9494-9494-949494944001'
      and exists (
        select 1 from public.competition_questions
         where id = '94949494-9494-9494-9494-949494944001'
           and sent_at is not null
           and deadline_at is not null
           and deadline_at > sent_at));

  -- Soru 1: U1 dogru, U2 yanlis.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select public.submit_competition_answer(
    '94949494-9494-9494-9494-949494944001', 'A') into v_res;

  perform public._qa_s94_true('C-26',
    'sunucu dogru cevabi dogru degerlendirdi (correct, 200)',
    v_res->>'result' = 'correct' and (v_res->>'points_awarded')::int = 200,
    'result=' || coalesce(v_res->>'result', '?') ||
    ' points=' || coalesce(v_res->>'points_awarded', '?'));

  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000092","role":"authenticated"}', true);
  select public.submit_competition_answer(
    '94949494-9494-9494-9494-949494944001', 'B') into v_res;

  perform public._qa_s94_true('C-27',
    'sunucu yanlis cevabi yanlis degerlendirdi (wrong, 0)',
    v_res->>'result' = 'wrong' and (v_res->>'points_awarded')::int = 0,
    'result=' || coalesce(v_res->>'result', '?') ||
    ' points=' || coalesce(v_res->>'points_awarded', '?'));

  -- Soru 2: U1 dogru, U2 pas (NULL).
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select public.submit_competition_answer(
    '94949494-9494-9494-9494-949494944002', 'B') into v_res;

  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000092","role":"authenticated"}', true);
  select public.submit_competition_answer(
    '94949494-9494-9494-9494-949494944002', null) into v_res;

  perform public._qa_s94_true('C-26p',
    'pas cevap: result=pass, puan=0',
    v_res->>'result' = 'pass' and (v_res->>'points_awarded')::int = 0,
    'result=' || coalesce(v_res->>'result', '?'));

  -- Soru 3: U1 dogru; U2 cevapsiz kalir (asagida server timeout).
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select public.submit_competition_answer(
    '94949494-9494-9494-9494-949494944003', 'C') into v_res;

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  -- Server otoriter saat: deadline gecti; eksik cevap timeout.
  update public.competition_questions
     set sent_at = now() - interval '1 hour',
         deadline_at = now() - interval '59 minutes'
   where id = '94949494-9494-9494-9494-949494944003';

  perform public.create_missing_competition_timeouts(
    '94949494-9494-9494-9494-949494944003');

  perform public.advance_competition_progress(
    '94949494-9494-9494-9494-949494943001');

  -- Soru 4 ve 5: her iki oyuncu da dogru; son cevap finalize tetikler.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select public.submit_competition_answer(
    '94949494-9494-9494-9494-949494944004', 'D') into v_res;
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000092","role":"authenticated"}', true);
  select public.submit_competition_answer(
    '94949494-9494-9494-9494-949494944004', 'D') into v_res;
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select public.submit_competition_answer(
    '94949494-9494-9494-9494-949494944005', 'E') into v_res;
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000092","role":"authenticated"}', true);
  select public.submit_competition_answer(
    '94949494-9494-9494-9494-949494944005', 'E') into v_res;

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select status into v_status
    from public.competitions
   where id = '94949494-9494-9494-9494-949494943001';

  perform public._qa_s94_true('C-28',
    'son cevap sonrasi akis yarismayi tamamladi (finalize)',
    v_status = 'completed',
    'status=' || coalesce(v_status, '?'));
end;
$blk$;

-- C-29: server timeout satiri; bant yok -> time_band_code NULL.
do $blk$
declare
  v_result text; v_band text; v_points integer;
begin
  select answer_result, time_band_code, points_awarded
    into v_result, v_band, v_points
    from public.competition_answers
   where competition_question_id = '94949494-9494-9494-9494-949494944003'
     and user_id = '94000000-0000-0000-0000-000000000092';

  perform public._qa_s94_true('C-28t',
    'deadline sonrasi eksik cevap server tarafindan timeout oldu (puan 0)',
    v_result = 'timeout' and coalesce(v_points, -1) = 0,
    'result=' || coalesce(v_result, '?') ||
    ' points=' || coalesce(v_points, -1));

  perform public._qa_s94_true('C-29',
    'server bant cozumlemesi: onayli bant yok -> time_band_code NULL',
    v_band is null, 'band=' || coalesce(v_band, 'NULL'));
end;
$blk$;

-- C-31/32/33: toplam = cevap toplami; duplicate puan uretmez.
do $blk$
declare
  v_total integer; v_sum integer; v_cnt integer;
begin
  select cp.total_points,
         (select coalesce(sum(ca.points_awarded), 0)
            from public.competition_answers ca
           where ca.competition_id = cp.competition_id
             and ca.user_id = cp.user_id),
         (select count(*)
            from public.competition_answers ca
           where ca.competition_question_id =
                 '94949494-9494-9494-9494-949494944001'
             and ca.user_id = cp.user_id)
    into v_total, v_sum, v_cnt
    from public.competition_players cp
   where cp.competition_id = '94949494-9494-9494-9494-949494943001'
     and cp.user_id = '94000000-0000-0000-0000-000000000091';

  perform public._qa_s94_true('C-31',
    'total_points = cevap puanlari toplami (U1)',
    v_total = v_sum and v_total = 1000,
    'total=' || v_total || ' sum=' || v_sum);

  perform public._qa_s94_true('C-33',
    'ayni soru icin tek cevap garantisi',
    v_cnt = 1, 'answers=' || v_cnt);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  perform public._qa_s94_expect('C-32',
    'duplicate submission reddedildi (P0001), ikinci puan yok',
    'P0001',
    $sql$select public.submit_competition_answer(
      '94949494-9494-9494-9494-949494944001', 'A')$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select count(*) into v_cnt
    from public.competition_answers
   where competition_question_id = '94949494-9494-9494-9494-949494944001'
     and user_id = '94000000-0000-0000-0000-000000000091';

  perform public._qa_s94_true('C-32b',
    'duplicate sonrasi U1 cevap sayisi hala 1 (cift puan yok)',
    v_cnt = 1, 'answers=' || v_cnt);
end;
$blk$;

-- C-34: 5 hard dogru = 1000 (fallback); bantli matris devredeyken
-- ayni akis 1500 olur â€” belge/kalan rapor notu.
do $blk$
declare
  v_total integer;
begin
  select total_points into v_total
    from public.competition_players
   where competition_id = '94949494-9494-9494-9494-949494943001'
     and user_id = '94000000-0000-0000-0000-000000000091';

  perform public._qa_s94_true('C-34',
    'bes dogru zor cevap fallback toplami 1000 (bantli matrisle 1500)',
    v_total = 1000, 'total=' || coalesce(v_total, -1));
end;
$blk$;

-- Finalize: iki oyuncu tum sorulari cevapladi; sonuclari dosyala.
do $blk$
declare
  v_winner uuid; v_type text; v_u1 integer; v_u2 integer;
  v_snap jsonb; v_points integer; v_detail text;
begin
  -- U2'nin cevapsiz kalan sorusu yok; finalize hazir.
  perform public.finalize_competition_if_ready(
    '94949494-9494-9494-9494-949494943001');

  select winner_user_id, result_type
    into v_winner, v_type
    from public.competition_results
   where competition_id = '94949494-9494-9494-9494-949494943001';

  select total_points into v_u1
    from public.competition_players
   where competition_id = '94949494-9494-9494-9494-949494943001'
     and user_id = '94000000-0000-0000-0000-000000000091';

  select total_points into v_u2
    from public.competition_players
   where competition_id = '94949494-9494-9494-9494-949494943001'
     and user_id = '94000000-0000-0000-0000-000000000092';

  perform public._qa_s94_true('C-35',
    'wrong/pass/timeout U2 toplamini artirmadi (400) ve kazanan U1',
    v_winner = '94000000-0000-0000-0000-000000000091'
      and v_type = 'win_loss' and v_u2 = 400,
    'U1=' || v_u1 || ' U2=' || v_u2 || ' type=' || v_type);

  -- C-36: snapshot puanlama bilgisini korur.
  select (final_scoreboard -> 'players') into v_snap
    from public.competition_results
   where competition_id = '94949494-9494-9494-9494-949494943001';

  perform public._qa_s94_true('C-36',
    'snapshot oyuncu toplamlarini koruyor (1000/400)',
    (v_snap -> 0 ->> 'total_points') = '1000'
      and (v_snap -> 1 ->> 'total_points') = '400',
    'snap=' || left(v_snap::text, 120));

  -- C-37: kural tablosu sonradan degisse gecmis sonuc degismez.
  update public.scoring_point_rules
     set points = 999
   where rule_set_id = (select id from public.scoring_rule_sets
                         where rule_set_code = 'competition_scoring_v1')
     and grade_level = 5 and difficulty = 'hard'
     and answer_result = 'correct' and band_code is null;

  select (final_scoreboard -> 'players') into v_snap
    from public.competition_results
   where competition_id = '94949494-9494-9494-9494-949494943001';

  perform public._qa_s94_true('C-37',
    'kural degisikligi sonrasi gecmis snapshot degismedi (1000/400)',
    (v_snap -> 0 ->> 'total_points') = '1000'
      and (v_snap -> 1 ->> 'total_points') = '400',
    'snap=' || left(v_snap::text, 120));

  -- C-38: finalize/rating ikinci kez uygulanamaz.
  -- NOT: 078 rating motoru lig puanini 0 tabaninda sikistirir
  -- (greatest(before+delta, 0)). Ilk yarismasini kaybeden oyuncunun
  -- bakiyesi 0 oldugundan uygulanan degisim 0 olarak kaydedilir.
  perform public._faz5_apply_competition_points(
    '94949494-9494-9494-9494-949494943001');

  select count(*),
         coalesce(string_agg(points_change::text, ','), '-')
    into v_points, v_detail
    from public.competition_point_changes
   where competition_id = '94949494-9494-9494-9494-949494943001';

  perform public._qa_s94_true('C-38',
    'rating tek yazim: 2 kayit (+24 / 0-clamp), tekrar cagrim degisiklik yapmaz',
    v_points = 2 and v_detail = '24,0',
    'rows=' || v_points || ' deltas=' || v_detail);
end;
$blk$;


-- ############################################################
-- D. YETKI MATRISI
-- ############################################################

do $blk$
declare
  v_cnt integer;
  v_total integer;
begin
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);

  perform public._qa_s94_expect('D-39',
    'anon: scoring_point_rules INSERT reddedilir',
    '42501',
    $sql$insert into public.scoring_point_rules
      (rule_set_id, grade_level, difficulty, answer_result, points)
     values ('94949494-9494-9494-9494-949494943001', 1, 'easy', 'correct', 1)$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  perform public._qa_s94_expect('D-40',
    'ogrenci: scoring_point_rules INSERT reddedilir',
    '42501',
    $sql$insert into public.scoring_point_rules
      (rule_set_id, grade_level, difficulty, answer_result, points)
     values ('94949494-9494-9494-9494-949494943001', 1, 'easy', 'correct', 1)$sql$);

  -- D-41/D-42: puan kolonlari istemciye KAPALIDIR. Koruma iki
  -- katmanli olabilir: yetki yoksa 42501; yetki olsa bile RLS
  -- UPDATE politikasi olmadigindan 0 satir etkilener. Her iki
  -- ortamda da guvenlik ozelligi aynidir (puan degisemez).
  begin
    update public.competition_answers
       set points_awarded = 999
     where competition_id = '94949494-9494-9494-9494-949494943001'
       and user_id = '94000000-0000-0000-0000-000000000091';

    get diagnostics v_cnt = row_count;

    select total_points into v_total
      from public.competition_players
     where competition_id = '94949494-9494-9494-9494-949494943001'
       and user_id = '94000000-0000-0000-0000-000000000091';

    perform public._qa_s94_true('D-41',
      'ogrenci puan kolonunu degistiremiyor (0 satir; puan dokunulmadi)',
      v_cnt = 0 and v_total = 1000,
      'rows=' || v_cnt || ' total=' || coalesce(v_total, -1));
  exception
    when insufficient_privilege then
      perform public._qa_s94_true('D-41',
        'ogrenci puan kolonunu degistiremiyor (42501 yetki reddi)', true,
        'sqlstate=42501');
  end;

  begin
    update public.competition_players
       set total_points = 999
     where competition_id = '94949494-9494-9494-9494-949494943001'
       and user_id = '94000000-0000-0000-0000-000000000091';

    get diagnostics v_cnt = row_count;

    select total_points into v_total
      from public.competition_players
     where competition_id = '94949494-9494-9494-9494-949494943001'
       and user_id = '94000000-0000-0000-0000-000000000091';

    perform public._qa_s94_true('D-42',
      'ogrenci total_points degistiremiyor (0 satir; puan 1000 kaldi)',
      v_cnt = 0 and v_total = 1000,
      'rows=' || v_cnt || ' total=' || coalesce(v_total, -1));
  exception
    when insufficient_privilege then
      perform public._qa_s94_true('D-42',
        'ogrenci total_points degistiremiyor (42501 yetki reddi)', true,
        'sqlstate=42501');
  end;

  perform public._qa_s94_expect('D-43',
    'ogrenci: get_internal_correct_answer EXECUTE reddedilir',
    '42501',
    $sql$select public.get_internal_correct_answer(
      '94949494-9494-9494-9494-949494941001'::uuid)$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- D-44: yetkili RPC yolu calisir (C bloklarinda kanitlandi;
-- acik isaret: U1 cevabi sunucu tarafindan puanlandi).
do $blk$
declare
  v_ok boolean;
begin
  select exists (
    select 1 from public.competition_answers
     where competition_id = '94949494-9494-9494-9494-949494943001'
       and user_id = '94000000-0000-0000-0000-000000000091'
       and server_validated = true
       and points_awarded = 200
  ) into v_ok;

  perform public._qa_s94_true('D-44',
    'yetkili sunucu RPC puani server_validated olarak yazdi',
    v_ok);
end;
$blk$;

-- D-45: basarisiz islem kismi puan birakmaz (C-32b kapsam);
-- acik dogrulama: U1 toplami hala 1000.
do $blk$
declare
  v_total integer;
begin
  select total_points into v_total
    from public.competition_players
   where competition_id = '94949494-9494-9494-9494-949494943001'
     and user_id = '94000000-0000-0000-0000-000000000091';

  perform public._qa_s94_true('D-45',
    'basarisiz deneme sonrasi kismi puan yok (U1=1000)',
    v_total = 1000, 'total=' || coalesce(v_total, -1));
end;
$blk$;


-- ############################################################
-- E. REGRESYON
-- ############################################################

-- E-46: 093 sinif korumasi devam eder.
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  perform public._qa_s94_expect('E-46',
    '093 regresyon: ogrenci grade_level degistiremiyor (42501)',
    '42501',
    $sql$update public.student_profiles
        set grade_level = 6
      where id = '94000000-0000-0000-0000-000000000091'$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- E-47: training havuzu yarisma sorularini KULLANMAZ.
do $blk$
declare
  v_res jsonb;
  v_codes text[];
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  v_res := public.select_training_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select coalesce(array_agg(el->>'question_code'), '{}')
    into v_codes
    from jsonb_array_elements(v_res->'questions') el;

  perform public._qa_s94_true('E-47',
    'antrenman secimi yarisma (one_v_one) sorularini icermez',
    v_codes @> array['QA94-P1']
      and not exists (
        select 1 from unnest(v_codes) c
         where c like 'QA94-C-%'),
    'codes=' || array_to_string(v_codes, ','));
end;
$blk$;

-- E-48: <=5 soru kurali (CHECK) korunur.
do $blk$
begin
  perform public._qa_s94_expect('E-48',
    'question_count=6 reddedilir (CHECK 1..5)',
    '23514',
    $sql$insert into public.competitions
      (competition_code, competition_type, grade_level, subject_id,
       scoring_rule_set_id, status, question_count)
     values ('QA94-COMP-BAD', 'one_vs_one', 5,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa',
       (select id from public.scoring_rule_sets
         where rule_set_code = 'competition_scoring_v1'),
       'created', 6)$sql$);
end;
$blk$;

-- E-49: matchmaking ayni sinif icinde.
do $blk$
declare
  v_a jsonb; v_c jsonb; v_comp_count integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  v_a := public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa');

  perform set_config('request.jwt.claims',
    '{"sub":"94000000-0000-0000-0000-000000000093","role":"authenticated"}', true);
  v_c := public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa');

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select count(*) into v_comp_count
    from public.competitions
   where competition_code like 'F5-%';

  perform public._qa_s94_true('E-49',
    'matchmaking: U1(5) bekliyor; U3(6) eslesmedi',
    v_a ->> 'status' = 'waiting'
      and v_c ->> 'status' = 'waiting'
      and v_comp_count = 0,
    'A=' || coalesce(v_a ->> 'status', '?') ||
    ' C=' || coalesce(v_c ->> 'status', '?') ||
    ' comps=' || v_comp_count);
end;
$blk$;

-- E-50: lig rating sozlesmesi +24 / -12 (0 tabanli clamp ile).
--   Yarisma 1 (yukarida): U1 kazandi (+24; U2'nin bakiyesi 0
--   oldugu icin kayip degisimi clamp ile 0 uygulandi).
--   Yarisma 2: bu kez U2 kazanir; U1'in bakiyesi 24 -> -12
--   uygulanarak 12'ye dusmeli (clamp devreye girmez).
do $blk$
declare
  v_plus integer; v_minus integer; v_detail text;
  v_comp2 integer; v_rel uuid;
  v_res jsonb; v_u1_points integer; v_wrong text;
begin
  -- Ilk yarismanin rating kayitlari: U1 +24, U2 0 (clamp).
  select max(points_change) filter (where points_change > 0),
         max(points_change) filter (where points_change <= 0),
         coalesce(string_agg(points_change::text, ','), '-')
    into v_plus, v_minus, v_detail
    from public.competition_point_changes
   where competition_id = '94949494-9494-9494-9494-949494943001';

  perform public._qa_s94_true('E-50a',
    'yarisma 1: kazanan +24; kaybeden 0 bakiyeden clamp ile 0',
    v_plus = 24 and v_detail = '24,0',
    'plus=' || coalesce(v_plus, 0) || ' deltas=' || v_detail);

  -- Yarisma 2 kurulumu: ayni iki oyuncu, 5 hard soru.
  insert into public.competitions
    (id, competition_code, competition_type, grade_level, subject_id,
     scoring_rule_set_id, status, question_count, started_at)
  values
    ('94949494-9494-9494-9494-949494943002', 'QA94-COMP-2', 'one_vs_one', 5,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'competition_scoring_v1'),
     'active', 5, now());

  insert into public.competition_players
    (competition_id, user_id, player_slot, status) values
    ('94949494-9494-9494-9494-949494943002',
     '94000000-0000-0000-0000-000000000091', 1, 'active'),
    ('94949494-9494-9494-9494-949494943002',
     '94000000-0000-0000-0000-000000000092', 2, 'active');

  insert into public.competition_questions
    (id, competition_id, question_id, question_order, difficulty)
  select ('94949494-9494-9494-9494-94949494500' || n)::uuid,
         '94949494-9494-9494-9494-949494943002',
         ('94949494-9494-9494-9494-94949494100' || n)::uuid,
         n::int, 'hard'
    from unnest(array['1','2','3','4','5']) n;

  -- 5 soruyu sirayla ac; U1 yanlis, U2 dogru cevaplar.
  for v_comp2 in 1..5 loop
    v_rel := public.release_competition_question(
      '94949494-9494-9494-9494-949494943002', v_comp2);

    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
      '{"sub":"94000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
    -- U1 icin bilincsiz yanlis sik: dogru sikdan farkli ilk secenek.
    select case
             when correct_answer = 'A' then 'B'
             else 'A'
           end
      into v_wrong
      from public.questions
     where id = (select question_id from public.competition_questions
                  where id = v_rel);
    select public.submit_competition_answer(v_rel, v_wrong) into v_res;
    perform set_config('request.jwt.claims',
      '{"sub":"94000000-0000-0000-0000-000000000092","role":"authenticated"}', true);
    select public.submit_competition_answer(v_rel,
      (array['A','B','C','D','E'])[v_comp2]) into v_res;
    perform set_config('request.jwt.claims', '', true);
    execute 'reset role';
  end loop;

  -- Ikinci yarismanin rating kayitlari: U1 -12 (24->12), U2 +24.
  select max(points_change) filter (where points_change > 0),
         min(points_change) filter (where points_change < 0)
    into v_plus, v_minus
    from public.competition_point_changes
   where competition_id = '94949494-9494-9494-9494-949494943002';

  select current_points into v_u1_points
    from public.student_league_memberships
   where user_id = '94000000-0000-0000-0000-000000000091'
     and is_current = true;

  perform public._qa_s94_true('E-50b',
    'yarisma 2: kazanan +24; bakiyesi olan kaybeden -12 (24->12)',
    v_plus = 24 and v_minus = -12 and v_u1_points = 12,
    'plus=' || coalesce(v_plus, 0) || ' minus=' || coalesce(v_minus, 0) ||
    ' U1_rating=' || coalesce(v_u1_points, -1));
end;
$blk$;


-- ============================================================
-- KALANTI KONTROLU + RAPOR
-- ============================================================

select
  (select count(*) from public.student_profiles
    where nickname like 'QA94-%')        as profiles_kalan,
  (select count(*) from public.questions
    where question_code like 'QA94-%')   as questions_kalan,
  (select count(*) from public.competitions
    where competition_code like 'QA94-%') as comps_kalan,
  (select count(*) from public.matchmaking_queue
    where user_id::text like '94000000%') as queue_kalan;

select
  label as test_id,
  case when bool_and(result = 'PASS') then 'PASS' else 'FAIL' end as durum,
  count(*) filter (where result = 'FAIL') as alt_fail,
  string_agg(
    case when result = 'PASS' then title
         else title || ' >>> ' || coalesce(detail, '') end,
    ' | ' order by title) as detay
from public._qa_s94_results
group by label
order by label;

with g as (
  select label, bool_and(result = 'PASS') as ok
  from public._qa_s94_results
  group by label
)
select
  count(*)                        as toplam,
  count(*) filter (where ok)      as gecen,
  count(*) filter (where not ok)  as kalan
from g;

drop function public._qa_s94_true(text, text, boolean, text);
drop function public._qa_s94_expect(text, text, text, text);
drop table public._qa_s94_results;

rollback;

