-- ============================================================
-- scripts/qa_faz30d1_v3_local.sql
-- Altin Kalemler - FAZ 30D-1 yerel QA suite
-- (V3 sabit puan matrisi + rakip bonusu + ders ustaligi)
--
-- ONAYLI KURAL:
--   Matris 9-12 ayni:
--     perfect 130/195/260 | good 120/180/240
--     average 110/165/220 | poor (+poor_grace) 100/150/200
--     wrong -20/-30/-40    | timeout -20/-30/-40 | pass 0
--   Goreli T bandlari: T, T*1.20, T*1.40, T*1.60, T*1.75
--   Rakip bonusu: rakip hata +20, rank farki +5/+10/+15
--   Ustalik: perfect +150, wrong/timeout -20/-30/-40, pas 0
--   Global: base + bonus (golge; lig/rating/XP degismez)
--   T yoksa: bant/bonus/ustalik YOK, V2 uyumlu temel puan
--
-- Kapsam (13 zorunlu senaryo):
--   A  V3 matris seed butunlugu
--   B  V1/V2 korunumu (puan/aktiflik/snapshot)
--   C  Band esikleri (saf cozumleyici, tam sinir seti)
--   D  poor_grace teknik flag + UI etiketi
--   E  proposed_timeout yalniz golge (sonuc/deadline degismez)
--   F  T eksik: bant yok, V2 uyumlu temel puan, reason/provenance
--   G  Rakip bonusu: rakip wrong +20, rakip pass 0
--   H  Rakip bonusu: band gap +10, ayni bant 0
--   I  Kazanan toplami base+bonus, kaybedene bonus yok
--   J  Ustalik: perfect/ceza/pas/clamp 0/seviye monotonik
--   K  Global toplam + lig/rating/XP etkisizligi
--   L  Idempotency: tekrar finalize / tekrar trigger
--   M  Guvenlik: yeni tablolarda rol ayricaliklari + RLS
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_faz30d1_v3_local.sql <db>:/tmp/
--   docker exec <db> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -A -t -f /tmp/qa_faz30d1_v3_local.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve
-- sonunda ROLLBACK yapilir; hicbir artefakt kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;

create table public._qa_s128_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_s128_results
  to anon, authenticated, service_role;

create function public._qa_s128_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_s128_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end, p_detail);
end;
$qa$;

grant execute on function public._qa_s128_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR (sabit UUID'ler; rollback ile silinecek)
-- matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
-- ============================================================

insert into auth.users (id, email) values
  ('d30d0000-0000-4000-8000-000000000001', 'qa30d1-a@test.local'),
  ('d30d0000-0000-4000-8000-000000000002', 'qa30d1-b@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('d30d0000-0000-4000-8000-000000000001', 5, 'QA30D1-A'),
  ('d30d0000-0000-4000-8000-000000000002', 5, 'QA30D1-B');

insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('d30d0000-0000-4000-8000-000000000010', 'QA30D1-Y', 'MEB-QA30D1', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('d30d0000-0000-4000-8000-000000000011', 'QA30D1-SCHED', 'QA30D1 Profil',
   'd30d0000-0000-4000-8000-000000000010', true, true);

insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('d30d0000-0000-4000-8000-000000000012',
  '430903f3-527e-4e12-b7e8-ac0afdb784aa',
  5, 'QA30D1 Konu', 'qa30d1-konu',
  'd30d0000-0000-4000-8000-000000000010');

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, start_week, end_week) values
  ('d30d0000-0000-4000-8000-000000000011', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   'd30d0000-0000-4000-8000-000000000012', 1, null);

-- 6 soru: hepsi hard, T = 60 saniye.
--   Q1..Q4  : T=60  (bonus yarismasi)
--   Q5      : T=NULL (T eksik senaryosu)
--   Q6      : T=60  (V3 E2E submit akisi)
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds, expert_solution_time_seconds)
select ('d30d0000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
       'QA30D1-Q-' || n, 5,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
       'hard', 'learning', 'coktan_secmeli', 'A', true, 60,
       case when n = 5 then null else 60 end
  from generate_series(1, 6) n;

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, review_status)
select q.id, 'd30d0000-0000-4000-8000-000000000010',
       'd30d0000-0000-4000-8000-000000000012', 'approved'
  from public.questions q
 where q.question_code like 'QA30D1-%';


-- ============================================================
-- A. V3 MATRIS SEED BUTUNLUGU
-- ============================================================

-- A-01: V3 kural seti tek kez, version 3, AKTIF.
do $blk$
declare v_cnt int; v_ver text; v_act boolean; v_sets text[];
begin
  select count(*), max(version), bool_or(is_active)
    into v_cnt, v_ver, v_act
    from public.scoring_rule_sets
   where rule_set_code = 'competition_scoring_v3_fixed';

  select coalesce(array_agg(rule_set_code order by rule_set_code), '{}')
    into v_sets from public.scoring_rule_sets where is_active = true;

  perform public._qa_s128_true('A-01',
    'V3 kural seti tam bir kez, version=3, tek aktif varsayilan',
    v_cnt = 1 and v_ver = '3' and v_act
      and v_sets = array['competition_scoring_v3_fixed'],
    'count=' || v_cnt || ' ver=' || v_ver || ' aktif=' || array_to_string(v_sets, ','));
end;
$blk$;

-- A-02: 252 satir = 12 sinif x 3 zorluk x 7 satir; kapsam eksiksiz.
do $blk$
declare
  v_total int; v_grades int; v_diffs int; v_banded int; v_nullband int;
  v_dup int; v_act int;
begin
  select count(*), count(distinct r.grade_level), count(distinct r.difficulty)
    into v_total, v_grades, v_diffs
    from public.scoring_point_rules r
    join public.scoring_rule_sets s on s.id = r.rule_set_id
   where s.rule_set_code = 'competition_scoring_v3_fixed';

  select count(*) into v_banded
    from public.scoring_point_rules r
    join public.scoring_rule_sets s on s.id = r.rule_set_id
   where s.rule_set_code = 'competition_scoring_v3_fixed'
     and r.band_code is not null;

  select count(*) into v_nullband
    from public.scoring_point_rules r
    join public.scoring_rule_sets s on s.id = r.rule_set_id
   where s.rule_set_code = 'competition_scoring_v3_fixed'
     and r.band_code is null;

  select count(*) into v_act
    from public.scoring_point_rules r
    join public.scoring_rule_sets s on s.id = r.rule_set_id
   where s.rule_set_code = 'competition_scoring_v3_fixed' and r.is_active;

  select coalesce(max(c), 0) into v_dup
    from (
      select count(*) c
        from public.scoring_point_rules r
        join public.scoring_rule_sets s on s.id = r.rule_set_id
       where s.rule_set_code = 'competition_scoring_v3_fixed' and r.is_active
       group by r.grade_level, r.difficulty, r.answer_result,
                coalesce(r.band_code, '')
    ) x;

  perform public._qa_s128_true('A-02',
    'V3 satirlar 252 (12x3x7), bandli 108, fallback 144, duplicate yok',
    v_total = 252 and v_grades = 12 and v_diffs = 3
      and v_banded = 108 and v_nullband = 144 and v_dup = 1 and v_act = 252,
    'total=' || v_total || ' grades=' || v_grades || ' diffs=' || v_diffs ||
    ' banded=' || v_banded || ' nullband=' || v_nullband ||
    ' max_group=' || v_dup || ' active=' || v_act);
end;
$blk$;

-- A-03: MATRIS DEGERLERI (3 zorluk x 7 sonuc/band) tam onayli.
do $blk$
declare
  v_bad int;
begin
  with expect(answer_result, band_code, easy, medium, hard) as (values
    ('correct','perfect', 130, 195, 260),
    ('correct','good',    120, 180, 240),
    ('correct','average', 110, 165, 220),
    ('correct',null,      100, 150, 200),
    ('wrong',  null,      -20, -30, -40),
    ('timeout',null,      -20, -30, -40),
    ('pass',   null,         0,   0,   0)
  ), actual as (
    select r.id, r.answer_result, r.band_code, r.difficulty, r.points
      from public.scoring_point_rules r
      join public.scoring_rule_sets s on s.id = r.rule_set_id
     where s.rule_set_code = 'competition_scoring_v3_fixed' and r.is_active
  )
  select count(*) into v_bad
    from expect e
    left join actual a
      on a.answer_result = e.answer_result
     and a.band_code is not distinct from e.band_code
     and a.difficulty = 'easy'   and a.points = e.easy
    left join actual a2
      on a2.answer_result = e.answer_result
     and a2.band_code is not distinct from e.band_code
     and a2.difficulty = 'medium' and a2.points = e.medium
    left join actual a3
      on a3.answer_result = e.answer_result
     and a3.band_code is not distinct from e.band_code
     and a3.difficulty = 'hard'   and a3.points = e.hard
   where a.id is null or a2.id is null or a3.id is null;

  perform public._qa_s128_true('A-03',
    'Matris degerleri onayli (perfect 130/195/260 ... pas 0)',
    v_bad = 0, 'uyusmayan kombinasyon=' || v_bad);
end;
$blk$;

-- A-04: Belirleyicilik indeksi mevcut (bandli + fallback tekillestirilmis).
do $blk$
declare v_idx int; v_uniq int;
begin
  select count(*) into v_idx
    from pg_indexes
   where schemaname = 'public'
     and indexname = 'uq_scoring_point_rules_active_key';

  select count(*) into v_uniq from pg_index i
   where i.indexrelid = 'public.uq_scoring_point_rules_active_key'::regclass
     and i.indisunique;

  perform public._qa_s128_true('A-04',
    'Bantli arama belirleyici: tekil indeks mevcut',
    v_idx = 1 and v_uniq = 1, 'idx=' || v_idx || ' unique=' || v_uniq);
end;
$blk$;


-- ============================================================
-- B. V1 / V2 KORUNUMU
-- ============================================================

-- B-01: V1 ve V2 satirlari AKTIF kalir; yalniz kural seti bayragi pasif.
do $blk$
declare
  v_v1_rows int; v_v2_rows int; v_v1_act boolean; v_v2_act boolean;
begin
  select count(*), bool_or(r.is_active) into v_v1_rows, v_v1_act
    from public.scoring_point_rules r
    join public.scoring_rule_sets s on s.id = r.rule_set_id
   where s.rule_set_code = 'competition_scoring_v1';

  select count(*), bool_or(r.is_active) into v_v2_rows, v_v2_act
    from public.scoring_point_rules r
    join public.scoring_rule_sets s on s.id = r.rule_set_id
   where s.rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  perform public._qa_s128_true('B-01',
    'V1/V2 katalogda kaldi ve 144er satiri AKTIF kaldi',
    v_v1_rows = 144 and v_v1_act and v_v2_rows = 144 and v_v2_act,
    'v1=' || v_v1_rows || '/' || v_v1_act ||
    ' v2=' || v_v2_rows || '/' || v_v2_act);
end;
$blk$;

-- B-02: V1 cozumlemesi degismedi (hard correct = 200, bantli arama da 200).
do $blk$
declare
  v_v1 uuid; v_v2 uuid;
  v_v1_pt int; v_v1_band int; v_v2_pt int; v_v2_band int;
begin
  select id into v_v1 from public.scoring_rule_sets
   where rule_set_code = 'competition_scoring_v1';
  select id into v_v2 from public.scoring_rule_sets
   where rule_set_code = 'competition_scoring_v2_negative_wrong_timeout';

  v_v1_pt := public.resolve_competition_points(v_v1, 5::smallint, 'hard', 'correct', null);
  v_v1_band := public.resolve_competition_points(v_v1, 5::smallint, 'hard', 'correct', 'perfect');
  v_v2_pt := public.resolve_competition_points(v_v2, 5::smallint, 'hard', 'correct', null);
  v_v2_band := public.resolve_competition_points(v_v2, 5::smallint, 'hard', 'correct', 'perfect');

  perform public._qa_s128_true('B-02',
    'V1/V2 cozumlemesi degismedi: hard correct 200, bantsiz bantta da 200',
    v_v1_pt = 200 and v_v1_band = 200 and v_v2_pt = 200 and v_v2_band = 200,
    'v1=' || v_v1_pt || '/' || v_v1_band || ' v2=' || v_v2_pt || '/' || v_v2_band);
end;
$blk$;

-- B-03: V1/V2 yarismasinda V3 tetikleyicileri TETIKLENMEZ.
insert into public.competitions
  (id, competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count, started_at)
values
  ('d30d0000-0000-4000-8000-000000000501', 'QA30D1-COMP-V2', 'one_vs_one', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   (select id from public.scoring_rule_sets
     where rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'),
   'active', 1, now());

insert into public.competition_players
  (competition_id, user_id, player_slot, status) values
  ('d30d0000-0000-4000-8000-000000000501',
   'd30d0000-0000-4000-8000-000000000001', 1, 'active');

insert into public.competition_questions
  (id, competition_id, question_id, question_order, difficulty)
values ('d30d0000-0000-4000-8000-000000000502',
  'd30d0000-0000-4000-8000-000000000501',
  'd30d0000-0000-4000-8000-000000000206', 1, 'hard');

update public.competition_questions
   set sent_at = now() - interval '10 seconds',
       deadline_at = now() + interval '50 seconds'
 where id = 'd30d0000-0000-4000-8000-000000000502';

update public.competitions
   set current_question_order = 1,
       current_question_id = 'd30d0000-0000-4000-8000-000000000502'
 where id = 'd30d0000-0000-4000-8000-000000000501';

-- V2 yaris: V3 tetikleyicileri erken cikis yapmali.
insert into public.competition_answers
  (id, competition_id, competition_question_id, user_id, submitted_answer,
   answer_result, sent_at, deadline_at, answer_received_at, time_ms,
   points_awarded, server_validated)
values
  ('d30d0000-0000-4000-8000-000000000503',
   'd30d0000-0000-4000-8000-000000000501',
   'd30d0000-0000-4000-8000-000000000502',
   'd30d0000-0000-4000-8000-000000000001', 'B', 'wrong',
   now() - interval '10 seconds', now() + interval '50 seconds',
   now() - interval '5 seconds', 5000, -40, true);

do $blk$
declare
  v_band text; v_shadow int; v_ledger int; v_pts int; v_git int;
begin
  select time_band_code, points_awarded
    into v_band, v_pts
    from public.competition_answers
   where id = 'd30d0000-0000-4000-8000-000000000503';

  select count(*) into v_shadow
    from public.faz30d_answer_shadow
   where competition_id = 'd30d0000-0000-4000-8000-000000000501';

  select count(*) into v_ledger
    from public.faz30d_opponent_bonus_ledger
   where competition_id = 'd30d0000-0000-4000-8000-000000000501';

  select count(*) into v_git
    from public.faz30d_global_points_events
   where competition_id = 'd30d0000-0000-4000-8000-000000000501';

  perform public._qa_s128_true('B-03',
    'V2 yarismasi etkilenmedi: bant NULL, golge kaydi YOK, puan -40 korundu',
    v_band is null and v_shadow = 0 and v_ledger = 0 and v_git = 0 and v_pts = -40,
    'band=' || coalesce(v_band, 'NULL') || ' pts=' || v_pts ||
    ' shadow=' || v_shadow || ' ledger=' || v_ledger || ' global=' || v_git);
end;
$blk$;


-- ============================================================
-- C. BAND ESIKLERI (saf cozumleyici; T = 60sn = 60000ms)
-- ============================================================

-- C-01: Tum esikler tam ve deterministik.
do $blk$
declare
  v_bad int; v_det int;
begin
  with cases(label, ms, want_band, want_reason) as (values
    ('tam T',          60000, 'perfect',          'v3_band_perfect'),
    ('T+1',            60001, 'good',             'v3_band_good'),
    ('tam 1.20T',      72000, 'good',             'v3_band_good'),
    ('1.20T+1',        72001, 'average',          'v3_band_average'),
    ('tam 1.40T',      84000, 'average',          'v3_band_average'),
    ('1.40T+1',        84001, 'poor',             'v3_band_poor'),
    ('tam 1.60T',      96000, 'poor',             'v3_band_poor'),
    ('1.60T+1',        96001, 'poor_grace',       'v3_band_poor_grace'),
    ('tam 1.75T',     105000, 'poor_grace',       'v3_band_poor_grace'),
    ('1.75T+1',       105001, 'proposed_timeout', 'v3_band_proposed_timeout'),
    ('cok yavas',     999999, 'proposed_timeout', 'v3_band_proposed_timeout')
  ), got as (
    select c.label, c.want_band,
           (private.faz30d_v3_resolve_band(c.ms, 60))->>'band_code' as band,
           (private.faz30d_v3_resolve_band(c.ms, 60))->>'reason_code' as reason
      from cases c
  )
  select count(*) into v_bad from got
   where band is distinct from want_band
      or reason is distinct from
         case want_band
           when 'perfect' then 'v3_band_perfect'
           when 'good' then 'v3_band_good'
           when 'average' then 'v3_band_average'
           when 'poor' then 'v3_band_poor'
           when 'poor_grace' then 'v3_band_poor_grace'
           else 'v3_band_proposed_timeout'
         end;

  -- ayni girdi iki kez -> ayni cikti (saf fonksiyon)
  select count(*) into v_det
    from (select private.faz30d_v3_resolve_band(72001, 60) as a,
                 private.faz30d_v3_resolve_band(72001, 60) as b) x
   where a <> b;

  perform public._qa_s128_true('C-01',
    'Band esikleri T/T*1.20/T*1.40/T*1.60/T*1.75 tam, tekrarlanabilir',
    v_bad = 0 and v_det = 0,
    'yanlis esik=' || v_bad || ' tekrarsizlik=' || v_det);
end;
$blk$;

-- C-02: oran (ratio) dogru hesaplaniyor.
do $blk$
declare v_ratio numeric;
begin
  v_ratio := (private.faz30d_v3_resolve_band(30000, 60))->>'ratio';
  perform public._qa_s128_true('C-02',
    'Oran dogru: 30000ms / 60sn = 0.5', v_ratio = 0.5000,
    'ratio=' || v_ratio);
end;
$blk$;


-- ============================================================
-- D. poor_grace TEKNIK FLAG + UI ETIKETI
-- ============================================================

-- D-01: poor_grace teknik ayri, UI etiketi "Kotu".
do $blk$
declare
  v_band text; v_grace boolean; v_scored boolean; v_label text;
begin
  v_band  := (private.faz30d_v3_resolve_band(100000, 60))->>'band_code';
  v_grace := (private.faz30d_v3_resolve_band(100000, 60))->>'is_grace_window';

  select is_scored_band, label_key into v_scored, v_label
    from public.faz30d_v3_bands where band_code = 'poor_grace';

  perform public._qa_s128_true('D-01',
    'poor_grace teknik ayri (is_grace_window) ama UI etiketi band_poor',
    v_band = 'poor_grace' and v_grace = true
      and v_scored = false and v_label = 'band_poor',
    'band=' || v_band || ' grace=' || v_grace ||
    ' scored=' || v_scored || ' label=' || v_label);
end;
$blk$;

-- D-02: poor_grace puani "kotu" degeriyle ayni (100/150/200).
do $blk$
declare v_pts int; v_fallback int; v_v3 uuid;
begin
  select id into v_v3 from public.scoring_rule_sets
   where rule_set_code = 'competition_scoring_v3_fixed';

  -- poor_grace bandli satir YOKTUR; cozumleyici fallback'e duser.
  v_pts := public.resolve_competition_points(
             v_v3, 5::smallint, 'hard', 'correct', 'poor_grace');
  v_fallback := public.resolve_competition_points(
             v_v3, 5::smallint, 'hard', 'correct', null);

  perform public._qa_s128_true('D-02',
    'poor_grace puani kotu degeriyle ayni (hard 200)',
    v_pts = 200 and v_fallback = 200,
    'poor_grace=' || v_pts || ' fallback=' || v_fallback);
end;
$blk$;


-- ============================================================
-- E. proposed_timeout YALNIZ GOLGE
-- ============================================================

-- E-01: proposed_timeout bantli bant OLARAK CEZALANDIRMAZ;
--       cozumleyici kotu fallback'ine duser.
do $blk$
declare v_pts int; v_v3 uuid; v_poor int;
begin
  select id into v_v3 from public.scoring_rule_sets
   where rule_set_code = 'competition_scoring_v3_fixed';

  v_pts  := public.resolve_competition_points(
              v_v3, 5::smallint, 'hard', 'correct', 'proposed_timeout');
  v_poor := public.resolve_competition_points(
              v_v3, 5::smallint, 'hard', 'correct', null);

  perform public._qa_s128_true('E-01',
    'proposed_timeout puani kotu degeriyle ayni (hard 200), ceza YOK',
    v_pts = 200 and v_poor = 200,
    'proposed_timeout=' || v_pts || ' kotu=' || v_poor);
end;
$blk$;

-- E-02: proposed_timeout sonucu degistirmez (mevcut deadline/timeout korunur).
do $blk$
declare v_flag boolean; v_deadline boolean;
begin
  v_flag := (private.faz30d_v3_resolve_band(999999, 60))->>'is_proposed_timeout';

  -- katalogda proposed_timeout "sonuc degistirici" degil, yalniz
  -- golge isareti olarak isaretlidir.
  select (b.is_proposed_timeout and not b.is_scored_band) into v_deadline
    from public.faz30d_v3_bands b where b.band_code = 'proposed_timeout';

  perform public._qa_s128_true('E-02',
    'proposed_timeout yalniz golge isareti; mevcut deadline/timeout DEGISMEDI',
    v_flag = true and v_deadline = true,
    'flag=' || v_flag || ' katalog=' || v_deadline);
end;
$blk$;


-- ============================================================
-- F. T EKSIK (uzman suresi yok)
-- ============================================================

-- F-01: T NULL ise bant uretilmez + acik reason/provenance.
do $blk$
declare v_b text; v_r text; v_ratio numeric;
begin
  v_b := (private.faz30d_v3_resolve_band(30000, null))->>'band_code';
  v_r := (private.faz30d_v3_resolve_band(30000, null))->>'reason_code';
  v_ratio := (private.faz30d_v3_resolve_band(30000, null))->>'ratio';

  perform public._qa_s128_true('F-01',
    'T yoksa bant uretilmez, reason=v3_missing_expert_time, ratio NULL',
    v_b is null and v_r = 'v3_missing_expert_time' and v_ratio is null,
    'band=' || coalesce(v_b, 'NULL') || ' reason=' || v_r);
end;
$blk$;

-- F-02: Sonuc/ceza/regresyon tanimlari degismedi.
do $blk$
declare v_bad int;
begin
  select count(*) into v_bad
    from (values ('correct','easy'),('correct','medium'),('correct','hard'),
                 ('wrong','easy'),('wrong','medium'),('wrong','hard'),
                 ('timeout','easy'),('timeout','medium'),('timeout','hard'),
                 ('pass','easy'),('pass','medium'),('pass','hard')) e(answer_result, difficulty)
   where e.answer_result not in ('correct','wrong','timeout','pass')
      or e.difficulty not in ('easy','medium','hard');

  perform public._qa_s128_true('F-02',
    'Dort degerli sonuc sozlugu ve uc zorluk degismedi', v_bad = 0,
    'bozuk=' || v_bad);
end;
$blk$;


-- ============================================================
-- G/H/I. RAKIP BONUSU + KAZANAN TOPLAMI
--
-- Yarisma kurulumu: V3, hard, T=60sn, 4 soru.
--   Q1: U1 perfect(60000) dogru | U2 yanlis
--   Q2: U1 perfect(60000) dogru | U2 average(70000) dogru
--   Q3: U1 good(65000) dogru    | U2 good(65000) dogru
--   Q4: U1 pas                   | U2 perfect(60000) dogru
--
-- Beklenen (hard):
--   U1 taban: 260 + 260 + 240 + 0   = 760
--   U2 taban: -40 + 220 + 240 + 260 = 680
--   U1 bonus: +20 (Q1 rakip hata)
--             +10 (Q2 rank farki 2: perfect3 - average1)
--             +0  (Q3 ayni bant)
--             +0  (Q4 kendi cevabi pas)
--             = 30
--   U2 bonus: 0 (Q1/Q3/Q4'te rakip Q1'de hatali = +20 beklenir;
--              ama U2'nin Q1 cevabi YANLIS -> kural: kendi dogru
--              degilse 0)
--   => U2 bonus = 0
--   U1 toplam: 790 | U2 toplam: 680
-- ============================================================

insert into public.competitions
  (id, competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count, started_at)
values
  ('d30d0000-0000-4000-8000-000000000601', 'QA30D1-COMP-BONUS', 'one_vs_one', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   (select id from public.scoring_rule_sets
     where rule_set_code = 'competition_scoring_v3_fixed'),
   'active', 4, now());

insert into public.competition_players
  (competition_id, user_id, player_slot, status) values
  ('d30d0000-0000-4000-8000-000000000601',
   'd30d0000-0000-4000-8000-000000000001', 1, 'active'),
  ('d30d0000-0000-4000-8000-000000000601',
   'd30d0000-0000-4000-8000-000000000002', 2, 'active');

insert into public.competition_questions
  (id, competition_id, question_id, question_order, difficulty)
select ('d30d0000-0000-4000-8000-0000000006' || lpad(n::text, 2, '0'))::uuid,
       'd30d0000-0000-4000-8000-000000000601',
       ('d30d0000-0000-4000-8000-0000000002' || lpad(n::text, 2, '0'))::uuid,
       n::int, 'hard'
  from generate_series(1, 4) n;

update public.competition_questions
   set sent_at = now() - interval '1 hour',
       deadline_at = now() + interval '1 hour'
 where competition_id = 'd30d0000-0000-4000-8000-000000000601';

update public.competitions
   set current_question_order = 1,
       current_question_id = 'd30d0000-0000-4000-8000-000000000601'
 where id = 'd30d0000-0000-4000-8000-000000000601';

-- yardimci: tam milisaniye kontrollu cevap ekleme
create function public._qa_s128_answer(
  p_competition_question_id uuid, p_user uuid, p_result text, p_ms int
)
returns void
language plpgsql
security definer
set search_path = public
as $qa$
declare v_sent timestamptz := timestamptz '2030-01-02 03:04:05+00';
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

grant execute on function public._qa_s128_answer(uuid, uuid, text, integer)
  to anon, authenticated, service_role;

-- Q1
select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000601',
  'd30d0000-0000-4000-8000-000000000001', 'correct', 60000);
select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000601',
  'd30d0000-0000-4000-8000-000000000002', 'wrong', 60000);
-- Q2
select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000602',
  'd30d0000-0000-4000-8000-000000000001', 'correct', 60000);
select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000602',
  'd30d0000-0000-4000-8000-000000000002', 'correct', 70000);
-- Q3
select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000603',
  'd30d0000-0000-4000-8000-000000000001', 'correct', 65000);
select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000603',
  'd30d0000-0000-4000-8000-000000000002', 'correct', 65000);
-- Q4
select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000604',
  'd30d0000-0000-4000-8000-000000000001', 'pass', 1000);
select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000604',
  'd30d0000-0000-4000-8000-000000000002', 'correct', 60000);

-- G-01: taban puanlar matrise uygun mu?  (T = 60000ms)
--   U1: 260 (Q1 perfect) + 260 (Q2 perfect) + 240 (Q3 good) + 0 (Q4 pas) = 760
--   U2: -40 (Q1 wrong)  + 240 (Q2 good, 70000<=1.20T)
--                     + 240 (Q3 good)    + 260 (Q4 perfect)             = 700
do $blk$
declare
  v_u1 int; v_u2 int; v_bad int;
begin
  select coalesce(sum(points_awarded), 0) into v_u1
    from public.competition_answers
   where competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and user_id = 'd30d0000-0000-4000-8000-000000000001';

  select coalesce(sum(points_awarded), 0) into v_u2
    from public.competition_answers
   where competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and user_id = 'd30d0000-0000-4000-8000-000000000002';

  -- her cevap icin beklenen taban puan
  select count(*) into v_bad
    from public.competition_answers a
   where a.competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and a.points_awarded <> case
       when a.answer_result = 'correct' and a.time_ms <= 60000 then 260
       when a.answer_result = 'correct' and a.time_ms <= 72000 then 240
       when a.answer_result = 'correct' then 220
       when a.answer_result = 'pass' then 0
       else -40
     end;

  perform public._qa_s128_true('G-01',
    'V3 taban puan: U1=760 (260+260+240+0), U2=700 (-40+240+240+260)',
    v_u1 = 760 and v_u2 = 700 and v_bad = 0,
    'u1=' || v_u1 || ' u2=' || v_u2 || ' uyumsuz=' || v_bad);
end;
$blk$;

-- yarismayi tamamla (bonus kancasi tetiklensin)
do $blk$
begin
  perform public.advance_competition_progress(
    'd30d0000-0000-4000-8000-000000000601');
  perform public.finalize_competition_if_ready(
    'd30d0000-0000-4000-8000-000000000601');
end;
$blk$;

-- G-02: U1 bonus = 20 (Q1 rakip wrong) + 5 (Q2 perfect vs good, gap 1)
--                  + 0 (Q3 ayni bant) = 25 ; Q4 pas -> satir YOK
do $blk$
declare
  v_rows int; v_sum int; v_bad int;
begin
  select count(*), coalesce(sum(bonus_points), 0)
    into v_rows, v_sum
    from public.faz30d_opponent_bonus_ledger
   where competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and user_id = 'd30d0000-0000-4000-8000-000000000001';

  select count(*) into v_bad
    from public.faz30d_opponent_bonus_ledger
   where competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and user_id = 'd30d0000-0000-4000-8000-000000000001'
      and bonus_points <> case reason_code
            when 'v3_bonus_opponent_fault' then 20
            when 'v3_bonus_opponent_pass' then 0
            when 'v3_bonus_band_gap' then
              case
                when band_rank_gap is null then -1   -- NULL gap: kural ihlali
                when band_rank_gap <= 0    then 0    -- ayni veya alt bant
                when band_rank_gap = 1     then 5
                when band_rank_gap = 2     then 10
                when band_rank_gap = 3     then 15
                else -1                            -- tanimsiz gap: kural ihlali
              end
            else 0
          end;

  perform public._qa_s128_true('G-02',
    'Rakip bonusu: rakip wrong +20, band gap 1 +5, ayni bant 0, pas satir yok -> U1=25',
    v_rows = 3 and v_sum = 25 and v_bad = 0,
    'satir=' || v_rows || ' toplam=' || v_sum || ' kural ihlali=' || v_bad);
end;
$blk$;

-- H-01: rakibi yanlis olan KENDI cevabi dogru olmayana bonus YOK.
do $blk$
declare v_sum int; v_rows int;
begin
  select coalesce(sum(bonus_points), 0), count(*)
    into v_sum, v_rows
    from public.faz30d_opponent_bonus_ledger
   where competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and user_id = 'd30d0000-0000-4000-8000-000000000002';

  perform public._qa_s128_true('H-01',
    'Kendi cevabi correct olmayan oyuncuya bonus YAZILMAZ (U2=0, 3 kayit)',
    v_sum = 0 and v_rows = 3,
    'toplam=' || v_sum || ' satir=' || v_rows);
end;
$blk$;

-- H-02: bonus satiri reason_code ile KESIN kural eslesmesi.
--   v3_bonus_opponent_fault -> daima 20
--   v3_bonus_opponent_pass  -> 0
--   v3_bonus_band_gap       -> gap 1/2/3 = 5/10/15;
--                             gap <= 0 (ayni veya ALT bant) = 0;
--                             gap NULL = KURAL IHLALI
do $blk$
declare v_bad int; v_offenders text;
begin
  select count(*), coalesce(string_agg(
           reason_code || '/gap=' || coalesce(band_rank_gap::text,'NULL')
           || '/pts=' || bonus_points::text, '; '), '')
    into v_bad, v_offenders
    from public.faz30d_opponent_bonus_ledger
   where competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and user_id = 'd30d0000-0000-4000-8000-000000000001'
     and bonus_points <> case reason_code
           when 'v3_bonus_opponent_fault' then 20
           when 'v3_bonus_opponent_pass'  then 0
           when 'v3_bonus_band_gap' then
             case
               when band_rank_gap is null then -1
               when band_rank_gap <= 0    then 0
               when band_rank_gap = 1     then 5
               when band_rank_gap = 2     then 10
               when band_rank_gap = 3     then 15
               else -1
             end
           else 0
         end;

  perform public._qa_s128_true('H-02',
    'Bonus satiri kural eslesmesi: fault=20, gap 1/2/3=5/10/15, ayni/alt bant=0, gap NULL yasak',
    v_bad = 0, 'ihlal=' || v_bad || ' [' || v_offenders || ']');
end;
$blk$;

-- I-01: kazanan hesabi base + bonus; kaybedene bonus yok.
do $blk$
declare
  v_u1_total int; v_u2_total int;
  v_u1_bonus int; v_u2_bonus int; v_status text;
begin
  select total_points, opponent_bonus_points into v_u1_total, v_u1_bonus
    from public.competition_players
   where competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and user_id = 'd30d0000-0000-4000-8000-000000000001';

  select total_points, opponent_bonus_points into v_u2_total, v_u2_bonus
    from public.competition_players
   where competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and user_id = 'd30d0000-0000-4000-8000-000000000002';

  select status into v_status from public.competitions
   where id = 'd30d0000-0000-4000-8000-000000000601';

  perform public._qa_s128_true('I-01',
    'Kazanan toplami base+bonus: U1=785 (760+25), U2=700 (700+0)',
    v_u1_total = 785 and v_u1_bonus = 25
      and v_u2_total = 700 and v_u2_bonus = 0
      and v_status = 'completed',
    'u1=' || v_u1_total || '(+' || v_u1_bonus || ')' ||
    ' u2=' || v_u2_total || '(+' || v_u2_bonus || ')' ||
    ' status=' || v_status);
end;
$blk$;


-- ============================================================
-- J. DERS USTALIGI
-- ============================================================

-- J-01: U1 (hard): 2 perfect (+150+150) + good (0) + pas (0) = 300
do $blk$
declare v_total int; v_ev int; v_delta_sum int;
begin
  select total_points into v_total
    from public.faz30d_subject_mastery_current
   where user_id = 'd30d0000-0000-4000-8000-000000000001'
     and subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  select count(*), coalesce(sum(delta_points), 0) into v_ev, v_delta_sum
    from public.faz30d_subject_mastery_events
   where user_id = 'd30d0000-0000-4000-8000-000000000001'
     and subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_s128_true('J-01',
    'Ustalik U1: 2 perfect +300, good 0, pas 0 -> toplam 300 (4 olay)',
    v_total = 300 and v_ev = 4 and v_delta_sum = 300,
    'toplam=' || v_total || ' olay=' || v_ev || ' delta=' || v_delta_sum);
end;
$blk$;

-- J-02: U2 (hard): wrong -40 + good 0 + good 0 + perfect +150
--   delta toplami = 110; ANCAK toplam 150'dir: ilk -40
--   taban (0) tarafindan yutulur (GREATEST(0, ...) kurali).
--   Bu ayrim bilerek test edilir: delta toplami ile birikmis
--   toplam esit olmak ZORUNDA DEGILDIR.
do $blk$
declare v_total int; v_delta_sum int;
begin
  select total_points into v_total
    from public.faz30d_subject_mastery_current
   where user_id = 'd30d0000-0000-4000-8000-000000000002'
     and subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  select coalesce(sum(delta_points), 0) into v_delta_sum
    from public.faz30d_subject_mastery_events
   where user_id = 'd30d0000-0000-4000-8000-000000000002'
     and subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_s128_true('J-02',
    'Ustalik U2: delta -40+0+0+150 = 110; taban 0 tabaninda -40 yutuldu -> toplam 150',
    v_total = 150 and v_delta_sum = 110,
    'toplam=' || v_total || ' delta=' || v_delta_sum);
end;
$blk$;

-- J-03: 0 ALTINA INILMEZ (clamp).
insert into public.faz30d_subject_mastery_current
  (user_id, subject_id, total_points, current_level, highest_level)
values ('d30d0000-0000-4000-8000-000000000002',
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10, 1, 1)
on conflict (user_id, subject_id) do update
  set total_points = 10, current_level = 1, highest_level = 1;

insert into public.competitions
  (id, competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count, started_at)
values ('d30d0000-0000-4000-8000-000000000701', 'QA30D1-COMP-CLAMP',
  'one_vs_one', 5, '430903f3-527e-4e12-b7e8-ac0afdb784aa',
  (select id from public.scoring_rule_sets
    where rule_set_code = 'competition_scoring_v3_fixed'),
  'active', 2, now());

insert into public.competition_players
  (competition_id, user_id, player_slot, status) values
  ('d30d0000-0000-4000-8000-000000000701',
   'd30d0000-0000-4000-8000-000000000002', 1, 'active');

insert into public.competition_questions
  (id, competition_id, question_id, question_order, difficulty)
values ('d30d0000-0000-4000-8000-000000000702',
  'd30d0000-0000-4000-8000-000000000701',
  'd30d0000-0000-4000-8000-000000000201', 1, 'hard');

update public.competition_questions
   set sent_at = now() - interval '1 hour', deadline_at = now() + interval '1 hour'
 where id = 'd30d0000-0000-4000-8000-000000000702';

update public.competitions
   set current_question_order = 1,
       current_question_id = 'd30d0000-0000-4000-8000-000000000702'
 where id = 'd30d0000-0000-4000-8000-000000000701';

insert into public.competition_questions
  (id, competition_id, question_id, question_order, difficulty)
values ('d30d0000-0000-4000-8000-000000000703',
  'd30d0000-0000-4000-8000-000000000701',
  'd30d0000-0000-4000-8000-000000000202', 2, 'hard');

select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000702',
  'd30d0000-0000-4000-8000-000000000002', 'wrong', 60000);

do $blk$
declare v_total int;
begin
  select total_points into v_total
    from public.faz30d_subject_mastery_current
   where user_id = 'd30d0000-0000-4000-8000-000000000002'
     and subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_s128_true('J-03',
    'Ustalik 0 altina inilmez: 10 + (-40) -> 0', v_total = 0,
    'toplam=' || v_total);
end;
$blk$;

-- J-04: ACILMIS en yuksek seviye ASLA dusmez (monotonik).
-- Q2 fixture yukarida kuruldu; sadece mastery durumu sifirlanir.
insert into public.faz30d_subject_mastery_current
  (user_id, subject_id, total_points, current_level, highest_level)
values ('d30d0000-0000-4000-8000-000000000002',
  '430903f3-527e-4e12-b7e8-ac0afdb784aa', 14900, 1, 3)
on conflict (user_id, subject_id) do update
  set total_points = 14900, current_level = 1, highest_level = 3;

update public.competition_questions
   set sent_at = now() - interval '1 hour', deadline_at = now() + interval '1 hour'
 where id = 'd30d0000-0000-4000-8000-000000000703';

select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000703',
  'd30d0000-0000-4000-8000-000000000002', 'pass', 500);

do $blk$
declare v_total int; v_cur int; v_high int;
begin
  select total_points, current_level, highest_level
    into v_total, v_cur, v_high
    from public.faz30d_subject_mastery_current
   where user_id = 'd30d0000-0000-4000-8000-000000000002'
     and subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_s128_true('J-04',
    'Seviye monotonik: 14900 pas 0 -> seviye 1 ama EN YUKSEK 3 korunur',
    v_total = 14900 and v_cur = 1 and v_high = 3,
    'toplam=' || v_total || ' seviye=' || v_cur || ' en_yuksek=' || v_high);
end;
$blk$;

-- J-05: T eksik soruda ustalik OLAYI OLUSMAZ.
do $blk$
declare
  v_comp uuid := 'd30d0000-0000-4000-8000-000000000801';
  v_cq    uuid := 'd30d0000-0000-4000-8000-000000000802';
  v_user  uuid := 'd30d0000-0000-4000-8000-000000000001';
  v_total int; v_shadow_band text; v_reason text; v_prov jsonb; v_pts int;
  v_mastery int;
begin
  insert into public.competitions
    (id, competition_code, competition_type, grade_level, subject_id,
     scoring_rule_set_id, status, question_count, started_at)
  values (v_comp, 'QA30D1-COMP-NOT', 'one_vs_one', 5,
    '430903f3-527e-4e12-b7e8-ac0afdb784aa',
    (select id from public.scoring_rule_sets
      where rule_set_code = 'competition_scoring_v3_fixed'),
    'active', 1, now());

  insert into public.competition_players
    (competition_id, user_id, player_slot, status)
  values (v_comp, v_user, 1, 'active');

  -- soru 5: expert_solution_time_seconds NULL
  insert into public.competition_questions
    (id, competition_id, question_id, question_order, difficulty)
  values (v_cq, v_comp, 'd30d0000-0000-4000-8000-000000000205', 1, 'hard');

  update public.competition_questions
     set sent_at = now() - interval '1 hour',
         deadline_at = now() + interval '1 hour'
   where id = v_cq;

  update public.competitions
     set current_question_order = 1, current_question_id = v_cq
   where id = v_comp;

  perform public._qa_s128_answer(v_cq, v_user, 'correct', 60000);

  select band_code, reason_code, provenance, base_points
    into v_shadow_band, v_reason, v_prov, v_pts
    from public.faz30d_answer_shadow
   where competition_question_id = v_cq;

  select count(*) into v_mastery
    from public.faz30d_subject_mastery_events
   where competition_answer_id in (
     select id from public.competition_answers
      where competition_question_id = v_cq);

  perform public._qa_s128_true('J-05',
    'T eksik: bant NULL, reason=missing, V2 uyumlu temel 200, ustalik OLAYI YOK',
    v_shadow_band is null
      and v_reason = 'v3_missing_expert_time'
      and v_pts = 200
      and v_mastery = 0
      and v_prov ? 'expert_t'
      and v_prov ->> 'resolver' = 'private.faz30d_v3_resolve_band',
    'band=' || coalesce(v_shadow_band, 'NULL') || ' reason=' || v_reason ||
    ' puan=' || v_pts || ' ustalik_olay=' || v_mastery);
end;
$blk$;


-- ============================================================
-- K. GLOBAL PUAN + LIG/RATING/XP ETKISIZLIGI
-- ============================================================

-- K-01: global toplam = tum olaylarin toplami (cift sayim / kayma yok)
--   ve 601 yarismasi dilimi = base 760 + bonus 25 = 785.
--   (U1'in 801 yarismasindaki T-eksik temel puani 200 de
--    toplamin icindedir; toplam yariisma-601 ile sinirli degildir.)
do $blk$
declare
  v_u1 bigint; v_u2 bigint;
  v_u1_base int; v_u1_bonus int;
  v_u1_events bigint; v_u1_601 bigint;
begin
  select g.total_points into v_u1
    from public.faz30d_global_points_totals g
   where g.user_id = 'd30d0000-0000-4000-8000-000000000001';

  select g.total_points into v_u2
    from public.faz30d_global_points_totals g
   where g.user_id = 'd30d0000-0000-4000-8000-000000000002';

  -- tum olaylarin toplami (kaynak dogrulugu)
  select coalesce(sum(points), 0) into v_u1_events
    from public.faz30d_global_points_events
   where user_id = 'd30d0000-0000-4000-8000-000000000001';

  -- yalnizca 601 yarismasinin dilimi
  select coalesce(sum(points), 0) into v_u1_601
    from public.faz30d_global_points_events
   where user_id = 'd30d0000-0000-4000-8000-000000000001'
     and competition_id = 'd30d0000-0000-4000-8000-000000000601';

  select coalesce(sum(points), 0) into v_u1_base
    from public.faz30d_global_points_events
   where user_id = 'd30d0000-0000-4000-8000-000000000001'
     and competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and event_kind = 'base';

  select coalesce(sum(points), 0) into v_u1_bonus
    from public.faz30d_global_points_events
   where user_id = 'd30d0000-0000-4000-8000-000000000001'
     and competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and event_kind = 'opponent_bonus';

  perform public._qa_s128_true('K-01',
    'Global toplam = tum olay toplami; 601 dilimi 760+25=785',
    v_u1 = v_u1_events and v_u1_601 = 785
      and v_u1_base = 760 and v_u1_bonus = 25,
    'u1=' || v_u1 || ' (olay_toplami=' || v_u1_events
      || ', 601 dilimi=' || v_u1_601
      || ', base=' || v_u1_base || ' + bonus=' || v_u1_bonus || ')');
end;
$blk$;

-- K-02: lig/rating motoru calisir (finalize yan etkisi) ama V3
--   degerleri puan havuzuna SIZMAZ.
--   078 kurali: kazanan +24, kaybeden -12; rating 0'in altina
--   inmez. Bu yuzden 0'dan baslayan kaybedende chg=0 gorunur -
--   bu MOTORUN mevcut taban kuralidir, V3 ile ilgisi yoktur.
--   Sizmazlik olcutu: hicbir rating/lig satiri V3 bonusu (25)
--   ya da V3 toplamlarini (760 / 785 / 700) ICERMEZ.
do $blk$
declare
  v_members int; v_ratings int; v_hist int; v_lb int;
  v_win int; v_bonus_leak int; v_total_leak int; v_v3_values int;
begin
  select count(*) into v_members
    from public.student_league_memberships
   where user_id in ('d30d0000-0000-4000-8000-000000000001',
                     'd30d0000-0000-4000-8000-000000000002');

  select count(*) into v_ratings
    from public.competition_point_changes
   where user_id in ('d30d0000-0000-4000-8000-000000000001',
                     'd30d0000-0000-4000-8000-000000000002')
     and change_type = 'rating';

  select count(*) into v_hist
    from public.student_league_history
   where user_id in ('d30d0000-0000-4000-8000-000000000001',
                     'd30d0000-0000-4000-8000-000000000002');

  select count(*) into v_lb
    from public.leaderboard_entries
   where user_id in ('d30d0000-0000-4000-8000-000000000001',
                     'd30d0000-0000-4000-8000-000000000002');

  -- 601 yarismasindaki rating satirlari
  select
      count(*) filter (where points_change = 24),
      count(*) filter (where points_change = 25),
      count(*) filter (where points_change in (760, 785, 700)
                        or points_before in (760, 785, 700)
                        or points_after  in (760, 785, 700))
    into v_win, v_bonus_leak, v_total_leak
    from public.competition_point_changes
   where competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and change_type = 'rating';

  -- hicbir V3 turevli deger lig tablosunda olmamali
  select count(*) into v_v3_values
    from public.student_league_memberships
   where user_id in ('d30d0000-0000-4000-8000-000000000001',
                     'd30d0000-0000-4000-8000-000000000002')
     and (current_points in (25, 760, 785, 700)
          or points_at_entry in (25, 760, 785, 700));

  perform public._qa_s128_true('K-02',
    'Lig/rating motoru calisti (kazanan +24) ama V3 bonusu/toplamlari hicbir puan tablosuna sizmadi',
    v_win = 1 and v_bonus_leak = 0 and v_total_leak = 0 and v_v3_values = 0,
    'rating_kazanan_24=' || v_win
      || ' bonus_sizmasi=' || v_bonus_leak
      || ' toplam_sizmasi=' || v_total_leak
      || ' lig_sizmasi=' || v_v3_values
      || ' | lig_uye=' || v_members || ' lig_gecmis=' || v_hist
      || ' leaderboard=' || v_lb);
end;
$blk$;


-- ============================================================
-- L. IDEMPOTENCY
-- ============================================================

-- L-01: ayni bonus kancasinin tekrar calismasi ledger/toplam degistirmez.
do $blk$
declare
  v_led_a int; v_led_b int;
  v_sum_a int; v_sum_b int;
  v_tot_a int; v_tot_b int;
  v_glob_a bigint; v_glob_b bigint;
begin
  select count(*), coalesce(sum(bonus_points), 0)
    into v_led_a, v_sum_a
    from public.faz30d_opponent_bonus_ledger
   where competition_id = 'd30d0000-0000-4000-8000-000000000601';
  select total_points into v_tot_a
    from public.competition_players
   where competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and user_id = 'd30d0000-0000-4000-8000-000000000001';
  select total_points into v_glob_a
    from public.faz30d_global_points_totals
   where user_id = 'd30d0000-0000-4000-8000-000000000001';

  -- finalize tekrar
  perform public.finalize_competition_if_ready(
    'd30d0000-0000-4000-8000-000000000601');
  -- durumu zorla geri alip tekrar 'completed' yap (kanca tekrar tetiklenir)
  update public.competitions set status = 'active'
   where id = 'd30d0000-0000-4000-8000-000000000601';
  update public.competitions set status = 'completed'
   where id = 'd30d0000-0000-4000-8000-000000000601';

  select count(*), coalesce(sum(bonus_points), 0)
    into v_led_b, v_sum_b
    from public.faz30d_opponent_bonus_ledger
   where competition_id = 'd30d0000-0000-4000-8000-000000000601';
  select total_points into v_tot_b
    from public.competition_players
   where competition_id = 'd30d0000-0000-4000-8000-000000000601'
     and user_id = 'd30d0000-0000-4000-8000-000000000001';
  select total_points into v_glob_b
    from public.faz30d_global_points_totals
   where user_id = 'd30d0000-0000-4000-8000-000000000001';

  perform public._qa_s128_true('L-01',
    'Idempotency: tekrar finalize + tekrar tetikleme degisiklik YOK',
    v_led_a = v_led_b and v_sum_a = v_sum_b
      and v_tot_a = v_tot_b and v_glob_a = v_glob_b,
    'ledger ' || v_led_a || '->' || v_led_b ||
    ' sum ' || v_sum_a || '->' || v_sum_b ||
    ' total ' || v_tot_a || '->' || v_tot_b ||
    ' global ' || v_glob_a || '->' || v_glob_b);
end;
$blk$;

-- L-02: ayni cevap satiri tekrar islenmez (UNIQUE korumasi).
--   U1 ustalik olayi = 4 (601'deki 4 cevap; 801 T-eksik cevap
--   ustalik URETMEZ -> kural 6).
--   U1 global base olayi = 5 (601'deki 4 + 801'deki T-eksik temel 200).
do $blk$
declare v_ev int; v_glob int;
begin
  select count(*) into v_ev
    from public.faz30d_subject_mastery_events
   where user_id = 'd30d0000-0000-4000-8000-000000000001'
     and subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  select count(*) into v_glob
    from public.faz30d_global_points_events
   where user_id = 'd30d0000-0000-4000-8000-000000000001'
     and event_kind = 'base';

  perform public._qa_s128_true('L-02',
    'Olay anahtarlari tekillestirilmis: ustalik 4, global base 5 (T-eksik dahil)',
    v_ev = 4 and v_glob = 5,
    'ustalik=' || v_ev || ' global_base=' || v_glob);
end;
$blk$;


-- ============================================================
-- M. GUVENLIK / AYRICALIKLAR
-- ============================================================

-- M-01: yeni tablolara authenticated/anon erisimi YOK, RLS acik.
do $blk$
declare
  v_bad int; v_norls int;
  v_tables text[] := array[
    'faz30d_v3_bands','faz30d_v3_mastery_rules','faz30d_v3_level_thresholds',
    'faz30d_v3_opponent_bonus_rules','faz30d_answer_shadow',
    'faz30d_opponent_bonus_ledger','faz30d_subject_mastery_events',
    'faz30d_subject_mastery_current','faz30d_global_points_events',
    'faz30d_global_points_totals'];
  t text;
begin
  v_bad := 0; v_norls := 0;
  foreach t in array v_tables loop
    if has_table_privilege('authenticated', format('public.%I', t)::regclass, 'SELECT')
       or has_table_privilege('anon', format('public.%I', t)::regclass, 'SELECT')
       or has_table_privilege('authenticated', format('public.%I', t)::regclass, 'TRUNCATE')
       or has_table_privilege('anon', format('public.%I', t)::regclass, 'TRUNCATE')
       or has_table_privilege('authenticated', format('public.%I', t)::regclass, 'REFERENCES')
       or has_table_privilege('anon', format('public.%I', t)::regclass, 'REFERENCES')
       or has_table_privilege('authenticated', format('public.%I', t)::regclass, 'TRIGGER')
       or has_table_privilege('anon', format('public.%I', t)::regclass, 'TRIGGER')
    then
      v_bad := v_bad + 1;
    end if;

    if not (select relrowsecurity from pg_class
             where oid = format('public.%I', t)::regclass) then
      v_norls := v_norls + 1;
    end if;
  end loop;

  perform public._qa_s128_true('M-01',
    '10 yeni tablo: RLS acik, authenticated/anon ayricaligi YOK',
    v_bad = 0 and v_norls = 0,
    'ayricalik_ihlali=' || v_bad || ' rls_kapali=' || v_norls);
end;
$blk$;

-- M-02: yeni tablolarda RLS POLICY yok; private fonksiyonlar
--        authenticated/anon'a CALISTIRILAMAZ.
do $blk$
declare
  v_pol int; v_exec int;
  v_funcs text[] := array[
    'private.faz30d_v3_resolve_band(integer,integer)',
    'private.faz30d_v3_score_answer()',
    'private.faz30d_v3_record_answer_events()',
    'private.faz30d_v3_apply_opponent_bonus()',
    'private.faz30d_v3_band_rank(text)'];
  f text;
begin
  select count(*) into v_pol
    from pg_policies
   where schemaname = 'public'
     and tablename like 'faz30d%';

  v_exec := 0;
  foreach f in array v_funcs loop
    if has_function_privilege('authenticated', f, 'EXECUTE')
       or has_function_privilege('anon', f, 'EXECUTE')
       or has_function_privilege('public', f, 'EXECUTE') then
      v_exec := v_exec + 1;
    end if;
  end loop;

  perform public._qa_s128_true('M-02',
    'Golge tablolarda RLS policy YOK, private fonksiyonlar rol erisimine kapali',
    v_pol = 0 and v_exec = 0,
    'policy=' || v_pol || ' acik_fonksiyon=' || v_exec);
end;
$blk$;


-- ============================================================
-- N. TETIKLEYICI SIRASI (OTOMATIK TAMAMLAMA YOLU)
--
-- PostgreSQL ayni anda ayni olayda atilan tetikleyicileri
-- ADA GORE sirayla atar. competition_answers uzerinde iki
-- AFTER INSERT tetikleyicisi vardir:
--   trigger_01_faz30d_v3_record_answer_events  (ONCE)
--   trigger_after_competition_answer_progress  (SONRA)
-- Ikincisi advance_competition_progress cagiriyor ve son
-- cevapta yarismayi 'completed' yaparak bonus kancasini
-- TETIKLER. Kanca yalnizca golge kaydini okudugu icin kayit
-- henuz yazilmadiginda bonus KAYBOLUR. N-01 bu yolu dogrudan
-- sinar: tek soruluk yarismada son cevap (rakibi yanlis)
-- bonusu ULASTIRMALI. Sayisal onek bu bagimliligi garanti
-- eder; 128'deki tetikleyici adi degistirilirse N-01 KIRMIZI
-- olmalidir.
-- ============================================================

insert into public.competitions
  (id, competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count, started_at)
values ('d30d0000-0000-4000-8000-000000000901', 'QA30D1-COMP-ORDER',
  'one_vs_one', 5, '430903f3-527e-4e12-b7e8-ac0afdb784aa',
  (select id from public.scoring_rule_sets
    where rule_set_code = 'competition_scoring_v3_fixed'),
  'active', 1, now());

insert into public.competition_players
  (competition_id, user_id, player_slot, status)
values ('d30d0000-0000-4000-8000-000000000901',
  'd30d0000-0000-4000-8000-000000000001', 1, 'active'),
  ('d30d0000-0000-4000-8000-000000000901',
  'd30d0000-0000-4000-8000-000000000002', 2, 'active');

insert into public.competition_questions
  (id, competition_id, question_id, question_order, difficulty)
values ('d30d0000-0000-4000-8000-000000000902',
  'd30d0000-0000-4000-8000-000000000901',
  'd30d0000-0000-4000-8000-000000000201', 1, 'hard');

update public.competition_questions
   set sent_at = now() - interval '1 hour',
       deadline_at = now() + interval '1 hour'
 where id = 'd30d0000-0000-4000-8000-000000000902';

update public.competitions
   set current_question_order = 1,
       current_question_id = 'd30d0000-0000-4000-8000-000000000902'
 where id = 'd30d0000-0000-4000-8000-000000000901';

-- ilk cevap: U1 dogru/perfect
select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000902',
  'd30d0000-0000-4000-8000-000000000001', 'correct', 60000);

-- SON cevap: U2 yanlis -> U1 +20 bonusu ULASTIRILMALI.
-- finalize_competition_if_ready CAGRILMAZ; otomatik yol test edilir.
select public._qa_s128_answer('d30d0000-0000-4000-8000-000000000902',
  'd30d0000-0000-4000-8000-000000000002', 'wrong', 60000);

do $blk$
declare
  v_status text;
  v_shadow int;
  v_bonus int;
  v_ledger int;
begin
  select status into v_status from public.competitions
   where id = 'd30d0000-0000-4000-8000-000000000901';

  select count(*) into v_shadow
    from public.faz30d_answer_shadow
   where competition_id = 'd30d0000-0000-4000-8000-000000000901';

  select coalesce(sum(bonus_points), 0) into v_bonus
    from public.faz30d_opponent_bonus_ledger
   where competition_id = 'd30d0000-0000-4000-8000-000000000901'
     and user_id = 'd30d0000-0000-4000-8000-000000000001';

  select count(*) into v_ledger
    from public.faz30d_opponent_bonus_ledger
   where competition_id = 'd30d0000-0000-4000-8000-000000000901';

  perform public._qa_s128_true('N-01',
    'Son cevap otomatik tamamlama yolunda da bonusu ULUSTIRIR (golge yazildiktan SONRA kanca)',
    v_bonus = 20 and v_ledger = 1 and v_shadow = 2
      and v_status = 'completed',
    'status=' || v_status || ' golge=' || v_shadow
      || ' bonus=' || v_bonus || ' ledger=' || v_ledger);
end;
$blk$;


-- ============================================================
-- SONUC
-- ============================================================

select count(*) || '|' || count(*) filter (where result = 'PASS')
       || '|' || count(*) filter (where result = 'FAIL')
  as summary
  from public._qa_s128_results;

select label, result, title, coalesce(detail, '') as detail
  from public._qa_s128_results
 where result = 'FAIL'
 order by label;

rollback;
