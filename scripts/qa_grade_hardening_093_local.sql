-- ============================================================
-- scripts/qa_grade_hardening_093_local.sql
-- Altin Kalemler - Migration 093 yerel QA suite
-- (Ogrenci sÄ±nÄ±f deÄŸiÅŸikliÄŸi gÃ¼venlik sertleÅŸtirmesi)
--
-- Kapsam:
--   T-00 : yetki matrisi (tablo/kolon ayrÄ±calÄ±klarÄ±)
--   T-01 : ogrenci KENDI nickname alanini guncelleyebilir
--   T-02 : ogrenci KENDI grade_level degerini DEGISTIREMEZ (42501)
--   T-03 : nickname + grade_level AYNI UPDATE'te -> butunlukle
--          reddedilir; nickname de degismez (atomiklik)
--   T-04 : ogrenci BASKA kullanÄ±cÄ±nÄ±n profilini guncelleyemez
--          (RLS: 0 satir; diger profil degisme)
--   T-05 : anon kullanici guncelleme yapamaz (42501)
--   T-06 : service_role yonetim yolu calisir (grade_level guncellemesi)
--   T-07 : basarisiz denemelerden sonra eski sinif KORUNUR
--   T-08 : _faz2_student_context guvenilir eski sinifi dondurur
--   T-09 : select_training_questions YALNIZ bu sinifin sorularini
--          getirir (farkli sinif sorusu kapsam disi)
--   T-10 : join_matchmaking_queue ayni-sinif kuralini korur
--          (farkli siniftaki ogrenci eslesmez)
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_grade_hardening_093_local.sql <db>:/tmp/
--   docker exec <db> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -A -t -f /tmp/qa_grade_hardening_093_local.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR
-- ============================================================

create table public._qa_g93_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_g93_results
  to anon, authenticated, service_role;

create function public._qa_g93_expect(
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
      insert into public._qa_g93_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_g93_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_g93_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_g93_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa_g93_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_g93_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa_g93_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_g93_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR (sabit QA uuid'leri; rollback ile silinecek)
-- matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
--   A : 5. sinif  (hedef ogrenci)
--   B : 6. sinif  (izolasyon karsi-tarafi)
--   C : 5. sinif  (matchmaking es partneri)
-- ============================================================

insert into auth.users (id, email) values
  ('93000000-0000-0000-0000-000000000091', 'qa93-user-a@test.local'),
  ('93000000-0000-0000-0000-000000000092', 'qa93-user-b@test.local'),
  ('93000000-0000-0000-0000-000000000093', 'qa93-user-c@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('93000000-0000-0000-0000-000000000091', 5, 'QA93-NICK-A'),
  ('93000000-0000-0000-0000-000000000092', 6, 'QA93-NICK-B'),
  ('93000000-0000-0000-0000-000000000093', 5, 'QA93-NICK-C');

-- Akademik donem + mufredat (T-08/T-09 icin gerekli baglam).
insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('93939393-9393-9393-9393-939393930001', 'QA93-Y', 'MEB-QA93', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('93939393-9393-9393-9393-939393930002', 'QA93-SCHED', 'QA93 Profil',
   '93939393-9393-9393-9393-939393930001', true, true);

insert into public.academic_weeks (academic_year, week, starts_at, ends_at) values
  ('QA93-Y', 5, current_date - 3, current_date + 4);

-- 5. sinif islenmis konu.
insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('93939393-9393-9393-9393-939393930010',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   5, 'QA93 Islenmis Konu', 'qa93-islenmis',
   '93939393-9393-9393-9393-939393930001');

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, start_week, end_week) values
  ('93939393-9393-9393-9393-939393930002', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '93939393-9393-9393-9393-939393930010', 1, null);

-- Antrenman sorulari: 3x 5. sinif + 1x 6. sinif Tuzak.
-- Tuzak soru KASADA ve ONAYLI eslemededir; yalniz sinif filtresi
-- disarida birakabilir (T-09 bunu kanitlar).
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
values
  ('93939393-9393-9393-9393-939393931001', 'QA93-P1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45),
  ('93939393-9393-9393-9393-939393931002', 'QA93-P2', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'acik_uclu', 'B', true, 60),
  ('93939393-9393-9393-9393-939393931003', 'QA93-P3', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'hard', 'comprehension', 'dogru_yanlis', 'C', true, 75),
  ('93939393-9393-9393-9393-939393931099', 'QA93-G6', 6,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'D', true, 45);

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, review_status)
select q.id, '93939393-9393-9393-9393-939393930001',
       '93939393-9393-9393-9393-939393930010', 'approved'
  from public.questions q
 where q.question_code in ('QA93-P1', 'QA93-P2', 'QA93-P3', 'QA93-G6');

-- Pratik (antrenman) kasasi: 4 soru da uye.
insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('93939393-9393-9393-9393-939393932001', 'QA93-V-PRACTICE',
   'QA93 Antrenman Kasasi', 'practice', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, practice_eligible)
select '93939393-9393-9393-9393-939393932001', q.id, 'active', true
  from public.questions q
 where q.question_code in ('QA93-P1', 'QA93-P2', 'QA93-P3', 'QA93-G6');

-- one_v_one kasasi: 5 uygun soru (matchmaking eslesme sonrasi
-- paket hazirligi 082 icin).
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
select ('93939393-9393-9393-9393-93939393300' || n)::uuid,
       'QA93-C-' || n, 5,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
       'easy', 'learning', 'coktan_secmeli', 'A', true, 45
  from unnest(array['1','2','3','4','5']) n;

insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('93939393-9393-9393-9393-939393932002', 'QA93-V-1V1',
   'QA93 1v1 Kasasi', 'one_v_one', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, one_v_one_eligible)
select '93939393-9393-9393-9393-939393932002',
       ('93939393-9393-9393-9393-93939393300' || n)::uuid, 'active', true
  from unnest(array['1','2','3','4','5']) n;

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, review_status)
select ('93939393-9393-9393-9393-93939393300' || n)::uuid,
       '93939393-9393-9393-9393-939393930001',
       '93939393-9393-9393-9393-939393930010', 'approved'
  from unnest(array['1','2','3','4','5']) n;


-- ============================================================
-- T-00: YETKI MATRISI (093 sonrasi)
-- ============================================================

do $blk$
begin
  perform public._qa_g93_true('T-00a',
    'authenticated: student_profiles tablo-UPDATE YOK',
    not has_table_privilege('authenticated', 'public.student_profiles', 'UPDATE'));

  perform public._qa_g93_true('T-00b',
    'authenticated: nickname kolon-UPDATE VAR',
    has_column_privilege('authenticated', 'public.student_profiles', 'nickname', 'UPDATE'));

  perform public._qa_g93_true('T-00c',
    'authenticated: grade_level kolon-UPDATE YOK',
    not has_column_privilege('authenticated', 'public.student_profiles', 'grade_level', 'UPDATE'));

  perform public._qa_g93_true('T-00d',
    'anon: nickname kolon-UPDATE YOK',
    not has_column_privilege('anon', 'public.student_profiles', 'nickname', 'UPDATE'));

  perform public._qa_g93_true('T-00e',
    'anon: grade_level kolon-UPDATE YOK',
    not has_column_privilege('anon', 'public.student_profiles', 'grade_level', 'UPDATE'));

  perform public._qa_g93_true('T-00f',
    'service_role: tablo-UPDATE VAR (yonetim yolu)',
    has_table_privilege('service_role', 'public.student_profiles', 'UPDATE'));
end;
$blk$;


-- ============================================================
-- T-01: ogrenci KENDI izin verilen alanini (nickname) gunceller
-- ============================================================

do $blk$
declare
  v_count integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"93000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  update public.student_profiles
     set nickname = 'QA93-NICK-A-UPD'
   where id = '93000000-0000-0000-0000-000000000091';

  get diagnostics v_count = row_count;

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_g93_true('T-01',
    'ogrenci kendi nickname alanini guncelleyebiliyor',
    v_count = 1,
    'row_count=' || v_count);
end;
$blk$;


-- ============================================================
-- T-02: ogrenci KENDI grade_level degerini DEGISTIREMEZ
-- ============================================================

do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"93000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  perform public._qa_g93_expect('T-02',
    'ogrenci kendi grade_level degerini degistiremiyor (42501)',
    '42501',
    $sql$update public.student_profiles
        set grade_level = 6
      where id = '93000000-0000-0000-0000-000000000091'$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-03: nickname + grade_level AYNI UPDATE'te -> atomik red
--       (nickname de degismemeli)
-- ============================================================

do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"93000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  perform public._qa_g93_expect('T-03a',
    'nickname+grade_level ayni UPDATE: butunlukle reddedilir (42501)',
    '42501',
    $sql$update public.student_profiles
        set nickname = 'QA93-HACKED', grade_level = 6
      where id = '93000000-0000-0000-0000-000000000091'$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_g93_true('T-03b',
    'atomiklik: basarisiz ifadeden sonra nickname degismedi',
    (select nickname from public.student_profiles
      where id = '93000000-0000-0000-0000-000000000091') = 'QA93-NICK-A-UPD');
end;
$blk$;


-- ============================================================
-- T-04: ogrenci BASKA kullanÄ±cÄ±nÄ±n profilini guncelleyemez (RLS)
-- ============================================================

do $blk$
declare
  v_count integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"93000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  update public.student_profiles
     set nickname = 'QA93-HACKED-B'
   where id = '93000000-0000-0000-0000-000000000092';

  get diagnostics v_count = row_count;

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_g93_true('T-04a',
    'ogrenci baska kullanicinin satirini guncelleyemiyor (0 satir)',
    v_count = 0,
    'row_count=' || v_count);

  perform public._qa_g93_true('T-04b',
    'B nicknamesi degismedi',
    (select nickname from public.student_profiles
      where id = '93000000-0000-0000-0000-000000000092') = 'QA93-NICK-B');
end;
$blk$;


-- ============================================================
-- T-05: anon kullanici guncelleme yapamaz
-- ============================================================

do $blk$
begin
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);

  perform public._qa_g93_expect('T-05',
    'anon: student_profiles UPDATE reddedilir (42501)',
    '42501',
    $sql$update public.student_profiles
        set nickname = 'QA93-ANON'
      where id = '93000000-0000-0000-0000-000000000091'$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-06: service_role yonetim yolu calisiyor (grade guncellemesi)
-- ============================================================

do $blk$
begin
  execute 'set local role service_role';
  perform set_config('request.jwt.claims',
    '{"sub":"93000000-0000-0000-0000-000000000092","role":"service_role"}', true);

  perform public._qa_g93_expect('T-06a',
    'service_role: B grade_level guncellemesi basarili',
    '',
    $sql$update public.student_profiles
        set grade_level = 7
      where id = '93000000-0000-0000-0000-000000000092'$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_g93_true('T-06b',
    'B grade_level service_role ile 7 oldu',
    (select grade_level from public.student_profiles
      where id = '93000000-0000-0000-0000-000000000092') = 7);
end;
$blk$;


-- ============================================================
-- T-07: basarisiz denemelerden sonra A'nin eski sinifi KORUNUR
-- ============================================================

do $blk$
begin
  perform public._qa_g93_true('T-07',
    'A grade_level hala 5 (tum basarisiz denemeler sonrasi)',
    (select grade_level from public.student_profiles
      where id = '93000000-0000-0000-0000-000000000091') = 5);
end;
$blk$;


-- ============================================================
-- T-08: _faz2_student_context guvenilir eski sinifi dondurur
-- (071 geregi fonksiyon authenticated'a KAPALIDIR; sunucuici
-- RPC'lerinin kullandigi gibi owner rolunde, A'nin uid'si ile
-- cagrilir -> sinif yalniz profilden turetilir)
-- ============================================================

do $blk$
declare
  v_grade smallint;
begin
  select grade_level into v_grade
    from public._faz2_student_context(
      '93000000-0000-0000-0000-000000000091'::uuid)
   limit 1;

  perform public._qa_g93_true('T-08',
    'student_context guvenilir sinifi donduruyor (grade=5)',
    v_grade = 5,
    'grade=' || coalesce(v_grade::text, '?'));
end;
$blk$;


-- ============================================================
-- T-09: select_training_questions YALNIZ 5. sinif sorularini getirir
--       (QA93-G6 kasada ve eslemede olsa da DISARIDA kalir)
-- ============================================================

do $blk$
declare
  v_res   jsonb;
  v_codes text[];
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"93000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  v_res := public.select_training_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select coalesce(array_agg(el->>'question_code'), '{}')
    into v_codes
    from jsonb_array_elements(v_res->'questions') el;

  perform public._qa_g93_true('T-09',
    'antrenman secimi yalniz 5. sinif sorularini donduruyor',
    (v_res->>'new_count') = '3'
      and v_codes @> array['QA93-P1','QA93-P2','QA93-P3']
      and not ('QA93-G6' = any(v_codes)),
    'new_count=' || coalesce(v_res->>'new_count', '?') ||
    ' codes=' || array_to_string(v_codes, ','));
end;
$blk$;


-- ============================================================
-- T-10: matchmaking ayni-sinif kuralini koruyor
--   A(5) kuyruga girer -> waiting
--   B(6) ayni derse girer -> eslesmez, waiting kalir
--   C(5) girer -> A ile eslesir; yarisma grade_level=5
-- ============================================================

do $blk$
declare
  v_res_a  jsonb;
  v_res_b  jsonb;
  v_res_c  jsonb;
  v_comp   record;
  v_b_in   integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"93000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  v_res_a := public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa');

  perform set_config('request.jwt.claims',
    '{"sub":"93000000-0000-0000-0000-000000000092","role":"authenticated"}', true);
  v_res_b := public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa');

  perform set_config('request.jwt.claims',
    '{"sub":"93000000-0000-0000-0000-000000000093","role":"authenticated"}', true);
  v_res_c := public.join_matchmaking_queue(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa');

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select c.grade_level, c.id into v_comp
    from public.competitions c
   where c.competition_code like 'F5-%'
   order by c.created_at desc
   limit 1;

  select count(*) into v_b_in
    from public.competition_players cp
   where cp.user_id = '93000000-0000-0000-0000-000000000092'
     and cp.competition_id = v_comp.id;

  perform public._qa_g93_true('T-10a',
    'A(5) kuyruga girdi -> waiting',
    v_res_a ->> 'status' = 'waiting',
    'status=' || coalesce(v_res_a ->> 'status', '?'));

  perform public._qa_g93_true('T-10b',
    'B(6) farkli sinif -> eslesmedi, waiting',
    v_res_b ->> 'status' = 'waiting',
    'status=' || coalesce(v_res_b ->> 'status', '?'));

  perform public._qa_g93_true('T-10c',
    'C(5) A ile eslesti -> matched',
    v_res_c ->> 'status' = 'matched',
    'status=' || coalesce(v_res_c ->> 'status', '?'));

  perform public._qa_g93_true('T-10d',
    'eslesme yarismasinin sinifi 5 (guvenilir profilden)',
    v_comp.grade_level = 5,
    'grade=' || coalesce(v_comp.grade_level::text, '?'));

  perform public._qa_g93_true('T-10e',
    'B eslesme yarismasinin katilimcisi DEGIL',
    v_b_in = 0,
    'b_player_rows=' || v_b_in);
end;
$blk$;


-- ============================================================
-- KALANTI KONTROLU (rollback oncesi tespit)
-- ============================================================

select
  (select count(*) from public.student_profiles
    where nickname like 'QA93-%')       as profiles_kalan,
  (select count(*) from public.questions
    where question_code like 'QA93-%')  as questions_kalan,
  (select count(*) from public.question_vaults
    where vault_code like 'QA93-%')     as vaults_kalan,
  (select count(*) from public.matchmaking_queue
    where user_id::text like '93000000%') as queue_kalan;


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
from public._qa_g93_results
group by label
order by label;

with g as (
  select label, bool_and(result = 'PASS') as ok
  from public._qa_g93_results
  group by label
)
select
  count(*)                        as toplam,
  count(*) filter (where ok)      as gecen,
  count(*) filter (where not ok)  as kalan
from g;


drop function public._qa_g93_true(text, text, boolean, text);
drop function public._qa_g93_expect(text, text, text, text);
drop table public._qa_g93_results;

rollback;

