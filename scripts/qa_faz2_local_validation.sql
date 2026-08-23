-- ============================================================
-- scripts/qa_faz2_local_validation.sql
-- Altin Kalemler - Migration Faz 2 yerel QA suite
--
-- Kapsam:
--   T-01       : anon RPC EXECUTE denials (067/068/069)
--   T-02       : antrenman secimi - mufredat kapisi + show-time atomik
--                exposure/sayac + payload ALLOWLIST (F-5)
--   T-02e      : esleme review_status onay kapisi (F-4)
--   T-03       : tekrar sorular sayac tuketmez (karar #2)
--   T-04       : 500 siniri - kapasite dolunca yeni akis durur,
--                501. yeni soru imkansiz (CHECK son savunma)
--   T-05       : cross-student izolasyon + istemci dogrudan DML denials
--   T-06/T-07  : ingest_student_attempt - attempt no, sure, 7 kapsam,
--                metrik anahtari normalizasyonu (069, karar #3/#5)
--   T-08       : ortak gorulmemis paket onceligi A/B + cift secim kilidi
--   T-08g/h/i  : faz2_pack.question_ids metadata + snapshot kaynak
--                sabitleme trigger'i (F-1)
--   T-09       : snapshot degistirilemezligi triggerlari (karar #4/#6)
--   T-10       : 065 paket uye limiti Faz 2 ile birlikte yasasin
--   T-11       : akademik donem yoksa FAIL-CLOSED (karar #1)
--   T-12       : get_my_weekly_usage dogru dondurur
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_faz2_local_validation.sql supabase_db_yarisma-programi:/tmp/
--   docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -f /tmp/qa_faz2_local_validation.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR
-- ============================================================

create table public._qa_faz2_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_faz2_results
  to anon, authenticated, service_role;

create function public._qa_expect(p_label text, p_title text, p_expect text, p_sql text)
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
      insert into public._qa_faz2_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_faz2_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_faz2_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_faz2_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa_true(p_label text, p_title text, p_ok boolean, p_detail text default null)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_faz2_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR (sabit QA uuid'leri; rollback ile silinecek)
-- matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
-- ============================================================

insert into auth.users (id, email) values
  ('99999999-9999-9999-9999-999999999901', 'qa2-user-a@test.local'),
  ('99999999-9999-9999-9999-999999999902', 'qa2-user-b@test.local');

insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('88888888-8888-8888-8888-888888888801', 'QA-Y-2099', 'MEB-QA2', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('77777777-7777-7777-7777-777777777701', 'QA2-SCHED', 'QA2 Profil',
   '88888888-8888-8888-8888-888888888801', true, true);

insert into public.student_profiles (id, grade_level, nickname) values
  ('99999999-9999-9999-9999-999999999901', 12, 'QA2-NICK-A'),
  ('99999999-9999-9999-9999-999999999902', 12, 'QA2-NICK-B');

-- Akademik takvim: bugunu kapsayan hafta 5 (+ sonraki hafta 6).
insert into public.academic_weeks (academic_year, week, starts_at, ends_at) values
  ('QA-Y-2099', 5, current_date - 3, current_date + 4),
  ('QA-Y-2099', 6, current_date + 4, current_date + 11);

-- Konular / alt konu / kazanım.
insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('66666666-6666-6666-6666-000000000001', '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   12, 'QA2 Islenmis Konu', 'qa2-islenmis',
   '88888888-8888-8888-8888-888888888801'),
  ('66666666-6666-6666-6666-000000000002', '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   12, 'QA2 Gelecek Konu', 'qa2-gelecek',
   '88888888-8888-8888-8888-888888888801');

insert into public.subtopics (id, topic_id, name, slug) values
  ('55555555-5555-5555-5555-000000000001',
   '66666666-6666-6666-6666-000000000001',
   'QA2 Alt Konu', 'qa2-alt-konu');

insert into public.curriculum_outcomes
  (id, curriculum_version_id, grade_level, subject_id, outcome_text) values
  ('44444444-4444-4444-4444-000000000001',
   '88888888-8888-8888-8888-888888888801', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   'QA2 kazanım metni');

-- Schedule items:
--   T_ALLOWED: start 1 (islenmis), end_week 3 < guncel hafta 5 ->
--              antrenman ERISIMI acik kalmali (end_week kapataz).
--   T_FUTURE : start 6 -> henuz sorulamaz.
insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, start_week, end_week) values
  ('77777777-7777-7777-7777-777777777701', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '66666666-6666-6666-6666-000000000001', 1, 3),
  ('77777777-7777-7777-7777-777777777701', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '66666666-6666-6666-6666-000000000002', 6, null);

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, outcome_id, start_week) values
  ('77777777-7777-7777-7777-777777777701', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '44444444-4444-4444-4444-000000000001', 2);

-- Sorular: NN -> 01..17.
--   01..05 : islenmis konu / kazanım kapsaminda
--   06     : gelecek konuda (BLOKLU)
--   07     : eslemesiz (BLOKLU)
--   08..10 : islenmis konuda
--   11     : question_type serbest metin (normalizasyon)
--   12     : question_type NULL (tanimsiz)
--   13..16 : islenmis konuda (kapasite testi rezervi)
--   17     : konu eslemesi PENDING -> F-4 onay kapisi testi
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type)
values
  ('33333333-3333-3333-3333-000000000001', 'Q2-01', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli'),
  ('33333333-3333-3333-3333-000000000002', 'Q2-02', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'acik_uclu'),
  ('33333333-3333-3333-3333-000000000003', 'Q2-03', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'hard', 'comprehension', 'dogru_yanlis'),
  ('33333333-3333-3333-3333-000000000004', 'Q2-04', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli'),
  ('33333333-3333-3333-3333-000000000005', 'Q2-05', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'bosluk_doldurma'),
  ('33333333-3333-3333-3333-000000000006', 'Q2-06', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli'),
  ('33333333-3333-3333-3333-000000000007', 'Q2-07', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli'),
  ('33333333-3333-3333-3333-000000000008', 'Q2-08', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'hard', 'comprehension', 'eslestirme'),
  ('33333333-3333-3333-3333-000000000009', 'Q2-09', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'coktan_secmeli'),
  ('33333333-3333-3333-3333-000000000010', 'Q2-10', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'klassik'),
  ('33333333-3333-3333-3333-000000000011', 'Q2-11', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', '  ÖZEL Tip!!  '),
  ('33333333-3333-3333-3333-000000000012', 'Q2-12', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', null, null),
  ('33333333-3333-3333-3333-000000000013', 'Q2-13', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli'),
  ('33333333-3333-3333-3333-000000000014', 'Q2-14', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'hard', 'comprehension', 'acik_uclu'),
  ('33333333-3333-3333-3333-000000000015', 'Q2-15', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'dogru_yanlis'),
  ('33333333-3333-3333-3333-000000000016', 'Q2-16', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli'),
  ('33333333-3333-3333-3333-000000000017', 'Q2-17', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli');

-- Müfredat eşlemeleri (sürüm V1).
insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, subtopic_id, review_status) values
  ('33333333-3333-3333-3333-000000000001',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001',
   '55555555-5555-5555-5555-000000000001', 'approved'),
  ('33333333-3333-3333-3333-000000000002',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001', null, 'approved'),
  ('33333333-3333-3333-3333-000000000003',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001', null, 'approved'),
  ('33333333-3333-3333-3333-000000000004',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001', null, 'approved'),
  ('33333333-3333-3333-3333-000000000006',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000002', null, 'approved'),
  ('33333333-3333-3333-3333-000000000008',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001', null, 'approved'),
  ('33333333-3333-3333-3333-000000000009',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001', null, 'approved'),
  ('33333333-3333-3333-3333-000000000010',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001', null, 'approved'),
  ('33333333-3333-3333-3333-000000000013',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001', null, 'approved'),
  ('33333333-3333-3333-3333-000000000014',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001', null, 'approved'),
  ('33333333-3333-3333-3333-000000000015',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001', null, 'approved'),
  ('33333333-3333-3333-3333-000000000016',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001', null, 'approved'),
  -- F-4: Q17 eslemesi ONAY BEKLIYOR -> secim aday havuzuna GIREMEZ.
  ('33333333-3333-3333-3333-000000000017',
   '88888888-8888-8888-8888-888888888801',
   '66666666-6666-6666-6666-000000000001', null, 'pending');

-- Kazanım eşlemesi: Q5 yalniz outcome ile sorulabilir.
insert into public.question_outcome_mappings
  (question_id, outcome_id, review_status) values
  ('33333333-3333-3333-3333-000000000001',
   '44444444-4444-4444-4444-000000000001', 'approved'),
  ('33333333-3333-3333-3333-000000000005',
   '44444444-4444-4444-4444-000000000001', 'approved');

-- Pratik (antrenman) kasasi: Q1..Q10 uyeli (13..16 T-04 oncesi eklenir).
-- Q17 de uyedir; esleme pending oldugu surece secilemez (F-4).
insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('22222222-2222-2222-2222-00000000000a', 'QA2-V-PRACTICE',
   'QA2 Antrenman Kasasi', 'practice', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, practice_eligible)
select '22222222-2222-2222-2222-00000000000a',
       ('33333333-3333-3333-3333-0000000000' || n)::uuid, 'active', true
  from unnest(array['01','02','03','04','05','06','07','08','09','10','17']) n;

-- Paket kasaları: VA (bakir), VB (sadece UA gorecek), VC (her ikisi de).
insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('22222222-2222-2222-2222-00000000000b', 'QA2-V-PACK-A',
   'QA2 Paket A', 'one_v_one', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa'),
  ('22222222-2222-2222-2222-00000000000c', 'QA2-V-PACK-B',
   'QA2 Paket B', 'one_v_one', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa'),
  ('22222222-2222-2222-2222-00000000000d', 'QA2-V-PACK-C',
   'QA2 Paket C', 'one_v_one', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active, difficulty)
select ('33333333-3333-3333-3333-10000000000' || n)::uuid,
       'Q2-PA-' || n, 12,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true, 'easy'
  from unnest(array['1','2','3','4','5']) n;

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, competition_eligible, one_v_one_eligible)
select '22222222-2222-2222-2222-00000000000b',
       ('33333333-3333-3333-3333-10000000000' || n)::uuid, 'active', true, true
  from unnest(array['1','2','3','4','5']) n;

insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active, difficulty)
select ('33333333-3333-3333-3333-11000000000' || n)::uuid,
       'Q2-PB-' || n, 12,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true, 'easy'
  from unnest(array['1','2','3','4','5']) n;

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, competition_eligible, one_v_one_eligible)
select '22222222-2222-2222-2222-00000000000c',
       ('33333333-3333-3333-3333-11000000000' || n)::uuid, 'active', true, true
  from unnest(array['1','2','3','4','5']) n;

insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active, difficulty)
select ('33333333-3333-3333-3333-12000000000' || n)::uuid,
       'Q2-PC-' || n, 12,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true, 'easy'
  from unnest(array['1','2','3','4','5']) n;

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, competition_eligible, one_v_one_eligible)
select '22222222-2222-2222-2222-00000000000d',
       ('33333333-3333-3333-3333-12000000000' || n)::uuid, 'active', true, true
  from unnest(array['1','2','3','4','5']) n;

-- VC (Paket C): her iki oyuncunun pack exposure'u var (A bloklu)
-- VE sorularinin hepsi ikisinde de exposure'lu (B bloklu).
insert into public.student_pack_exposures
  (user_id, vault_id, attempt_context) values
  ('99999999-9999-9999-9999-999999999901',
   '22222222-2222-2222-2222-00000000000d', 'one_v_one'),
  ('99999999-9999-9999-9999-999999999902',
   '22222222-2222-2222-2222-00000000000d', 'one_v_one');

insert into public.student_question_exposures
  (user_id, question_id, attempt_context)
select u.id, q.id, 'competition'
  from (values
    ('99999999-9999-9999-9999-999999999901'::uuid),
    ('99999999-9999-9999-9999-999999999902'::uuid)
  ) u(id)
  cross join unnest(array[
    '33333333-3333-3333-3333-120000000001',
    '33333333-3333-3333-3333-120000000002',
    '33333333-3333-3333-3333-120000000003',
    '33333333-3333-3333-3333-120000000004',
    '33333333-3333-3333-3333-120000000005'
  ]::uuid[]) q(id);

-- VB: sadece UA'nin pack exposure'u var (A bloklu; B yoluna dusurur).
insert into public.student_pack_exposures
  (user_id, vault_id, attempt_context) values
  ('99999999-9999-9999-9999-999999999901',
   '22222222-2222-2222-2222-00000000000c', 'one_v_one');

-- Yarisma altyapisi.
insert into public.scoring_rule_sets
  (id, rule_set_code, name, version) values
  ('10101010-1010-1010-1010-101010101010',
   'QA2-RS', 'QA2 Skor Seti', '1');

insert into public.competitions
  (id, competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count) values
  ('11111111-1111-1111-1111-000000000001', 'QA2-C-1', 'one_vs_one', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '10101010-1010-1010-1010-101010101010', 'waiting', 5),
  ('11111111-1111-1111-1111-000000000002', 'QA2-C-2', 'one_vs_one', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '10101010-1010-1010-1010-101010101010', 'waiting', 5),
  ('11111111-1111-1111-1111-000000000003', 'QA2-C-3', 'one_vs_one', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '10101010-1010-1010-1010-101010101010', 'waiting', 5),
  ('11111111-1111-1111-1111-000000000004', 'QA2-C-4', 'one_vs_one', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '10101010-1010-1010-1010-101010101010', 'created', 5);

insert into public.competition_players
  (competition_id, user_id, player_slot)
select u.cid, u.uid, u.slot
  from (values
    ('11111111-1111-1111-1111-000000000001'::uuid,
     '99999999-9999-9999-9999-999999999901'::uuid, 1),
    ('11111111-1111-1111-1111-000000000001'::uuid,
     '99999999-9999-9999-9999-999999999902'::uuid, 2),
    ('11111111-1111-1111-1111-000000000002'::uuid,
     '99999999-9999-9999-9999-999999999901'::uuid, 1),
    ('11111111-1111-1111-1111-000000000002'::uuid,
     '99999999-9999-9999-9999-999999999902'::uuid, 2),
    ('11111111-1111-1111-1111-000000000003'::uuid,
     '99999999-9999-9999-9999-999999999901'::uuid, 1),
    ('11111111-1111-1111-1111-000000000003'::uuid,
     '99999999-9999-9999-9999-999999999902'::uuid, 2)
  ) as u(cid, uid, slot);


-- ============================================================
-- T-01: ANON RPC EXECUTE DENIALS
-- ============================================================

do $blk$
begin
  execute 'set local role anon';

  perform public._qa_expect('T-01a',
    'anon: select_training_questions EXECUTE yetkisi yok',
    '42501',
    $sql$select public.select_training_questions(
      '430903f3-527e-4e12-b7e8-ac0afdb784aa', 5)$sql$);

  perform public._qa_expect('T-01b',
    'anon: prepare_competition_pack EXECUTE yetkisi yok',
    '42501',
    $sql$select public.prepare_competition_pack(
      '11111111-1111-1111-1111-000000000001')$sql$);

  perform public._qa_expect('T-01c',
    'anon: ingest_student_attempt EXECUTE yetkisi yok',
    '42501',
    $sql$select public.ingest_student_attempt(
      '33333333-3333-3333-3333-000000000001', 'training', 'correct')$sql$);

  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-02: ANTRENMAN SEÇİMİ (mufredat kapisi + atomik show-time)
-- Beklenen yeni sorular (havuzun tamami = 8):
--   Q1..Q5, Q8, Q9, Q10
--   (Q6/Q7 konu kapisi; Q17 esleme PENDING -> F-4 onay kapisi)
-- ============================================================

do $blk$
declare
  v_res      jsonb;
  v_used     integer;
  v_ids      jsonb;
  v_dirty    integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999901","role":"authenticated"}', true);

  v_res := public.select_training_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_true('T-02a',
    'secim: new_count=8 ve Q6/Q7/Q17 payload icinde degil (Q17: esleme pending)',
    (v_res->>'new_count') = '8'
      and not exists (
        select 1
          from jsonb_array_elements(v_res->'questions') el
         where el->>'question_code' in ('Q2-06', 'Q2-07', 'Q2-17')
      ),
    'new_count=' || coalesce(v_res->>'new_count', '?') ||
    ' soru_adedi=' || jsonb_array_length(coalesce(v_res->'questions', '[]'::jsonb))
  );

  -- F-5: allowlist. Her payload elemaninin anahtar kumesi TAM olarak
  -- izinli listeden olusmali; fazladan/eklenmemis hicbir alan yok.
  select count(*) into v_dirty
    from jsonb_array_elements(v_res->'questions') el
   where exists (
           select 1
             from jsonb_object_keys(el) k
            where k not in (
              'id', 'question_code', 'grade_level', 'subject_id',
              'question_text',
              'option_a', 'option_b', 'option_c', 'option_d', 'option_e',
              'difficulty', 'has_visual', 'estimated_solve_time_seconds'
            )
         )
      or not el ? 'question_text';

  perform public._qa_true('T-02b',
    'payload tam allowlist (izinli 13 alan disina cikmaz)',
    v_dirty = 0,
    'allowlist_disi_eleman=' || v_dirty);

  select c.new_questions_used into v_used
    from public.student_weekly_counters c
   where c.user_id = '99999999-9999-9999-9999-999999999901'
     and c.academic_year = 'QA-Y-2099' and c.week = 5
     and c.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_true('T-02c',
    'show-time atomik: 8 yeni soru -> sayac tam 8',
    v_used = 8,
    'sayac=' || coalesce(v_used, -1));

  select count(*) into v_dirty
    from public.student_question_exposures e
   where e.user_id = '99999999-9999-9999-9999-999999999901'
     and e.attempt_context = 'training';

  perform public._qa_true('T-02d',
    'show-time atomik: training exposure satiri = sayac',
    v_dirty = 8,
    'exposure=' || v_dirty);
end;
$blk$;


-- ============================================================
-- T-02e: F-4 ONAY KAPISI - esleme pending iken secilmeyen Q17,
-- esleme 'approved' yapilinca TEK yeni soru olarak gelir.
-- UA sayaci 8 -> 9, training exposure da 9 olur.
-- ============================================================

do $blk$
declare
  v_res      jsonb;
  v_used     integer;
  v_exposure integer;
begin
  update public.question_curriculum_mappings
     set review_status = 'approved'
   where question_id = '33333333-3333-3333-3333-000000000017'
     and curriculum_version_id = '88888888-8888-8888-8888-888888888801';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999901","role":"authenticated"}', true);

  v_res := public.select_training_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_true('T-02e-a',
    'esleme onaylandi: Q17 artik secilir (new_count=1)',
    (v_res->>'new_count') = '1'
      and exists (
        select 1
          from jsonb_array_elements(v_res->'questions') el
         where el->>'question_code' = 'Q2-17'
      ),
    'new_count=' || coalesce(v_res->>'new_count', '?'));

  select c.new_questions_used into v_used
    from public.student_weekly_counters c
   where c.user_id = '99999999-9999-9999-9999-999999999901'
     and c.academic_year = 'QA-Y-2099' and c.week = 5
     and c.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  select count(*) into v_exposure
    from public.student_question_exposures e
   where e.user_id = '99999999-9999-9999-9999-999999999901'
     and e.attempt_context = 'training';

  perform public._qa_true('T-02e-b',
    'sayac ve exposure 9''a cikti',
    v_used = 9 and v_exposure = 9,
    'sayac=' || coalesce(v_used, -1) || ' exposure=' || v_exposure);
end;
$blk$;


-- ============================================================
-- T-03: TEKRAR SORULAR SAYAC TUKETMEZ
-- ============================================================

do $blk$
declare
  v_res  jsonb;
  v_used integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999901","role":"authenticated"}', true);

  v_res := public.select_training_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select c.new_questions_used into v_used
    from public.student_weekly_counters c
   where c.user_id = '99999999-9999-9999-9999-999999999901'
     and c.academic_year = 'QA-Y-2099' and c.week = 5
     and c.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_true('T-03',
    'tekrar secim: repeat=9 new=0 sayac degismez (9)',
    (v_res->>'repeat_count') = '9'
      and (v_res->>'new_count') = '0'
      and v_used = 9,
    'repeat=' || coalesce(v_res->>'repeat_count', '?') ||
    ' new=' || coalesce(v_res->>'new_count', '?') ||
    ' sayac=' || coalesce(v_used, -1));
end;
$blk$;


-- Kapasite testi icin ek taze sorular havuza girer (13..16).
insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, practice_eligible)
select '22222222-2222-2222-2222-00000000000a',
       ('33333333-3333-3333-3333-0000000000' || n)::uuid, 'active', true
  from unnest(array['13','14','15','16']) n;


-- ============================================================
-- T-04: 500 SINIRI
--   a) kullanilan=498 yapilir -> kapasite 2 -> id asc ilk 2 yeni
--      (Q13,Q14) gelir, sayac 500 olur.
--   b) tekrar secim -> new=0, sayac 500 kalir.
--   c) dogrudan 501 update -> CHECK (23514).
-- ============================================================

update public.student_weekly_counters
   set new_questions_used = 498
 where user_id = '99999999-9999-9999-9999-999999999901'
   and academic_year = 'QA-Y-2099' and week = 5
   and subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

do $blk$
declare
  v_res  jsonb;
  v_used integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999901","role":"authenticated"}', true);

  v_res := public.select_training_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10);

  perform public._qa_true('T-04a',
    'kapasite 2: yalniz Q13 ve Q14 yeni olarak gelir',
    (v_res->>'new_count') = '2'
      and exists (
        select 1 from jsonb_array_elements(v_res->'questions') el
         where el->>'question_code' = 'Q2-13')
      and exists (
        select 1 from jsonb_array_elements(v_res->'questions') el
         where el->>'question_code' = 'Q2-14'),
    'new_count=' || coalesce(v_res->>'new_count', '?'));

  v_res := public.select_training_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select c.new_questions_used into v_used
    from public.student_weekly_counters c
   where c.user_id = '99999999-9999-9999-9999-999999999901'
     and c.academic_year = 'QA-Y-2099' and c.week = 5
     and c.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_true('T-04b',
    '500 dolulukta yeni akis durur: new=0 ve sayac=500',
    (v_res->>'new_count') = '0' and v_used = 500,
    'new=' || coalesce(v_res->>'new_count', '?') || ' sayac=' || v_used);
end;
$blk$;

select public._qa_expect('T-04c',
  'son savunma: sayaci 501''e cikarma CHECK ile reddedilir',
  '23514',
  $sql$update public.student_weekly_counters
      set new_questions_used = 501
    where user_id = '99999999-9999-9999-9999-999999999901'
      and academic_year = 'QA-Y-2099' and week = 5
      and subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa'$sql$);


-- ============================================================
-- T-05: CROSS-STUDENT IZOLASYON + ISTEMCI DML DENIALS
-- ============================================================

do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999902","role":"authenticated"}', true);

  perform public._qa_expect('T-05a',
    'istemci exposures tablosuna INSERT edemez',
    '42501',
    $sql$insert into public.student_question_exposures
        (user_id, question_id, attempt_context)
        values ('99999999-9999-9999-9999-999999999901',
                '33333333-3333-3333-3333-000000000002', 'training')$sql$);

  perform public._qa_expect('T-05b',
    'istemci dimension_metrics guncelleyemez',
    '42501',
    $sql$update public.student_dimension_metrics
        set total_attempts = total_attempts + 100$sql$);

  perform public._qa_expect('T-05c',
    'istemci weekly_counters guncelleyemez',
    '42501',
    $sql$update public.student_weekly_counters
        set new_questions_used = 0$sql$);

  perform public._qa_expect('T-05d',
    'istemci attempts silemez',
    '42501',
    $sql$delete from public.student_question_attempts$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-06: INGEST - attempt no / sure / 7 kapsam
-- ============================================================

do $blk$
declare
  v_r1 jsonb;
  v_r2 jsonb;
  r    record;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999901","role":"authenticated"}', true);

  v_r1 := public.ingest_student_attempt(
    '33333333-3333-3333-3333-000000000001',
    'training', 'correct', 45000);

  v_r2 := public.ingest_student_attempt(
    '33333333-3333-3333-3333-000000000001',
    'training', 'wrong', 30000);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_true('T-06a',
    'attempt_number sirali artar (1,2)',
    (v_r1->>'attempt_number') = '1'
      and (v_r2->>'attempt_number') = '2',
    'n1=' || coalesce(v_r1->>'attempt_number', '?') ||
    ' n2=' || coalesce(v_r2->>'attempt_number', '?'));

  perform public._qa_true('T-06b',
    'ilk denemede 7 metrik kapsami guncellenir',
    (v_r1->>'metrics_updated') = '7',
    'scopes=' || coalesce(v_r1->>'metrics_updated', '?') ||
    ' liste=' || coalesce(v_r1->>'metric_scopes'::text, '?'));

  select * into r
    from public.student_dimension_metrics
   where user_id = '99999999-9999-9999-9999-999999999901'
     and metric_scope = 'subject'
     and scope_key = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_true('T-06c',
    'subject metriği: total=2 correct=1 wrong=1 repeat_total=1 repeat_correct=0 time=75000',
    r.total_attempts = 2
      and r.correct_count = 1
      and r.wrong_count = 1
      and r.repeat_total = 1
      and r.repeat_correct = 0
      and r.total_time_ms = 75000,
    format('total=%s c=%s w=%s rt=%s rc=%s t=%s',
           r.total_attempts, r.correct_count, r.wrong_count,
           r.repeat_total, r.repeat_correct, r.total_time_ms));

  select count(*) into r from public.student_dimension_metrics
   where user_id = '99999999-9999-9999-9999-999999999901';

  perform public._qa_true('T-06d',
    'metrik satir sayisi: subject+difficulty+cognitive+qtype+topic+subtopic+outcome = 7',
    r.count = 7,
    'satir=' || r.count);
end;
$blk$;


-- ============================================================
-- T-07: METRIK ANAHTARI NORMALIZASYONU (karar #5)
-- ============================================================

do $blk$
declare
  v_norm1 text;
  v_norm2 text;
  v_cnt1  integer;
  v_cnt2  integer;
begin
  select public._faz2_normalize_metric_key('  ÖZEL Tip!!  ') into v_norm1;
  select public._faz2_normalize_metric_key(null) into v_norm2;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999901","role":"authenticated"}', true);

  perform public.ingest_student_attempt(
    '33333333-3333-3333-3333-000000000011',
    'training', 'blank', 1000);

  perform public.ingest_student_attempt(
    '33333333-3333-3333-3333-000000000012',
    'training', 'timeout', 2000);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select count(*) into v_cnt1
    from public.student_dimension_metrics
   where metric_scope = 'question_type'
     and scope_key = v_norm1
     and user_id = '99999999-9999-9999-9999-999999999901';

  select count(*) into v_cnt2
    from public.student_dimension_metrics
   where metric_scope = 'question_type'
     and scope_key = v_norm2
     and user_id = '99999999-9999-9999-9999-999999999901';

  perform public._qa_true('T-07',
    'serbest metin normalize edilir; bos deger tanimsiz olur',
    v_norm1 = 'zel_tip' and v_cnt1 = 1
      and v_norm2 = 'tanimsiz' and v_cnt2 = 1,
    'norm1=' || coalesce(v_norm1, '?') || ' kayit=' || v_cnt1 ||
    ' norm2=' || coalesce(v_norm2, '?') || ' kayit=' || v_cnt2);
end;
$blk$;


-- ============================================================
-- T-08: PAKET ONCELIĞI A/B + ÇİFT SEÇİM KİLİDİ
-- ============================================================

do $blk$
declare
  v_pack   jsonb;
  v_pe     integer;
  v_qe     integer;
  v_pa_ub  integer;
  v_pb_ub  integer;
  v_ua_exp integer;
  v_bused  integer;
begin
  -- UA'nin haftalik sayaci 500'de; clamp yolu da burada test edilir.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999901","role":"authenticated"}', true);

  v_pack := public.prepare_competition_pack(
    '11111111-1111-1111-1111-000000000001');

  perform public._qa_true('T-08a',
    'K1: bakir paket VA oncelik A ile secilir',
    v_pack->>'vault_id' = '22222222-2222-2222-2222-00000000000b'
      and v_pack->>'priority' = 'A',
    'vault=' || coalesce(v_pack->>'vault_id', '?') ||
    ' prio=' || coalesce(v_pack->>'priority', '?'));

  perform public._qa_expect('T-08d',
    'K1 ikinci cagri reddedilir (paket zaten secildi)',
    'P0001',
    $sql$select public.prepare_competition_pack(
      '11111111-1111-1111-1111-000000000001')$sql$);

  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999902","role":"authenticated"}', true);

  -- K2: A yolu bloklu (UA-VB pack exposure); B yolu: VB sorulari
  -- hicbir oyuncuda gorulmemis -> oncelik B ile VB secilir.
  v_pack := public.prepare_competition_pack(
    '11111111-1111-1111-1111-000000000002');

  perform public._qa_true('T-08b',
    'K2: VB oncelik B ile secilir',
    v_pack->>'vault_id' = '22222222-2222-2222-2222-00000000000c'
      and v_pack->>'priority' = 'B',
    'vault=' || coalesce(v_pack->>'vault_id', '?') ||
    ' prio=' || coalesce(v_pack->>'priority', '?'));

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  -- Pack exposure her iki oyuncuya yazildi mi (VA icin)?
  select count(*) into v_pe
    from public.student_pack_exposures
   where vault_id = '22222222-2222-2222-2222-00000000000b'
     and attempt_context = 'one_v_one';

  -- Question exposure dagilimi (clamp semantigi): T-04 UA sayacini
  --   500'e cikardigi icin UA paket sorularinda exposure ALMAZ (clamp).
  --   UB: K1'de PA 5, K2'de PB 5 -> toplam 10 satir.
  select count(*) into v_qe
    from public.student_question_exposures
   where attempt_context = 'one_v_one';

  select count(*) into v_pa_ub
    from public.student_question_exposures
   where attempt_context = 'one_v_one'
     and user_id = '99999999-9999-9999-9999-999999999902'
     and question_id::text like '33333333-3333-3333-3333-10%';

  select count(*) into v_pb_ub
    from public.student_question_exposures
   where attempt_context = 'one_v_one'
     and user_id = '99999999-9999-9999-9999-999999999902'
     and question_id::text like '33333333-3333-3333-3333-11%';

  select count(*) into v_ua_exp
    from public.student_question_exposures
   where attempt_context = 'one_v_one'
     and user_id = '99999999-9999-9999-9999-999999999901';

  perform public._qa_true('T-08c',
    'paket yazimlari: pack=2; UB PA+PB=5+5; UA clamp ile 0',
    v_pe = 2 and v_qe = 10 and v_pa_ub = 5
      and v_pb_ub = 5 and v_ua_exp = 0,
    'pack=' || v_pe || ' total=' || v_qe ||
    ' pa_ub=' || v_pa_ub || ' pb_ub=' || v_pb_ub ||
    ' ua=' || v_ua_exp);

  -- UB icin show-time sayaci: K1'de 5 + K2'de 5 yeni soru.
  select c.new_questions_used into v_bused
    from public.student_weekly_counters c
   where c.user_id = '99999999-9999-9999-9999-999999999902'
     and c.academic_year = 'QA-Y-2099' and c.week = 5
     and c.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_true('T-08e',
    'UB sayaci 10 yeni soru tuketti (K1+K2)',
    v_bused = 10,
    'ub_sayac=' || coalesce(v_bused, -1));

  -- K3: butun paketler bloklu -> fail-closed.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999901","role":"authenticated"}', true);

  perform public._qa_expect('T-08f',
    'K3: uygun ortak gorulmemis paket yok -> P0001',
    'P0001',
    $sql$select public.prepare_competition_pack(
      '11111111-1111-1111-1111-000000000003')$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-08g/h/i: F-1 PAKET LISTESI + SNAPSHOT KAYNAK SABITLEME
--   g) prepare_competition_pack kesin soru listesini
--      configuration.faz2_pack.question_ids'e yazar (5 eleman, VA).
--   h) listede OLMAYAN soru K1'e snapshot olarak GIREMEZ (P0001).
--   i) listeden bir soru yazilabilir (yasal yazici yolu acik).
-- ============================================================

do $blk$
declare
  v_cfg jsonb;
  v_cnt integer;
begin
  select c.configuration -> 'faz2_pack' into v_cfg
    from public.competitions c
   where c.id = '11111111-1111-1111-1111-000000000001';

  perform public._qa_true('T-08g',
    'faz2_pack metadata: 5 elemanli kesin question_ids listesi (VA)',
    v_cfg->>'vault_id' = '22222222-2222-2222-2222-00000000000b'
      and jsonb_typeof(coalesce(v_cfg->'question_ids', 'null'::jsonb)) = 'array'
      and jsonb_array_length(v_cfg->'question_ids') = 5
      and not exists (
        select 1
          from jsonb_array_elements_text(v_cfg->'question_ids') qid
         where qid::uuid not in (
           select m.question_id
             from public.question_vault_memberships m
            where m.vault_id = '22222222-2222-2222-2222-00000000000b'
              and m.membership_status = 'active'
         )
      ),
    'eleman=' ||
      coalesce(jsonb_array_length(v_cfg->'question_ids'), -1));

  perform public._qa_expect('T-08h',
    'paket listesinde olmayan soru snapshot''a giremez (F-1)',
    'P0001',
    $sql$insert into public.competition_questions
        (competition_id, question_id, question_order, difficulty)
        values ('11111111-1111-1111-1111-000000000001',
                '33333333-3333-3333-3333-000000000009',
                91, 'easy')$sql$);

  begin
    insert into public.competition_questions
      (competition_id, question_id, question_order, difficulty)
    values ('11111111-1111-1111-1111-000000000001',
            '33333333-3333-3333-3333-100000000001', 92, 'easy');

    select count(*) into v_cnt
      from public.competition_questions
     where competition_id = '11111111-1111-1111-1111-000000000001';

    perform public._qa_true('T-08i',
      'listeden soru snapshot''a yazilabilir (yasal yol acik)',
      v_cnt = 1,
      'satir=' || v_cnt);

    delete from public.competition_questions
     where competition_id = '11111111-1111-1111-1111-000000000001'
       and question_id = '33333333-3333-3333-3333-100000000001';
  exception when others then
    perform public._qa_true('T-08i',
      'listeden soru snapshot''a yazilabilir (yasal yol acik)',
      false, SQLERRM);
  end;
end;
$blk$;


-- ============================================================
-- T-09: SNAPSHOT DEGISTIRILEMEZLIGI (karar #4)
-- ============================================================

do $blk$
begin
  insert into public.competition_questions
    (competition_id, question_id, question_order, difficulty)
  select '11111111-1111-1111-1111-000000000004',
         ('33333333-3333-3333-3333-10000000000' || n)::uuid,
         n::smallint + 10, 'easy'
    from unnest(array['1','2','3','4','5']) n;

  perform public._qa_expect('T-09a',
    'snapshot question_id degisikligi engellenir',
    'P0001',
    $sql$update public.competition_questions
        set question_id = '33333333-3333-3333-3333-000000000009'
      where competition_id = '11111111-1111-1111-1111-000000000004'
        and question_order = 11$sql$);

  update public.competitions
     set status = 'active'
   where id = '11111111-1111-1111-1111-000000000004';

  perform public._qa_expect('T-09b',
    'aktif yarismadan snapshot sorusu silinemez',
    'P0001',
    $sql$delete from public.competition_questions
      where competition_id = '11111111-1111-1111-1111-000000000004'
        and question_order = 11$sql$);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999901","role":"authenticated"}', true);

  perform public._qa_expect('T-09c',
    'snapshot''u olan yarismaya prepare_competition_pack giremez',
    'P0001',
    $sql$select public.prepare_competition_pack(
      '11111111-1111-1111-1111-000000000004')$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  begin
    update public.competition_questions
       set sent_at = now()
     where competition_id = '11111111-1111-1111-1111-000000000004'
       and question_order = 11;

    perform public._qa_true('T-09d',
      'release akisi icin sent_at guncellemesi serbest',
      true, null);
  exception when others then
    perform public._qa_true('T-09d',
      'release akisi icin sent_at guncellemesi serbest',
      false, 'sent_at guncellemesi engellendi');
  end;
end;
$blk$;


-- ============================================================
-- T-10: 065 PAKET LIMITI FAZ 2 ILE YASAYA DEVAM
-- ============================================================

select public._qa_expect('T-10',
  'VA (5 aktif uye) 6. uye kabul etmez (065 tetikleyicisi)',
  'P0001',
  $sql$insert into public.question_vault_memberships
      (vault_id, question_id, membership_status,
       competition_eligible, one_v_one_eligible)
      values ('22222222-2222-2222-2222-00000000000b',
              '33333333-3333-3333-3333-000000000009',
              'active', true, true)$sql$);


-- ============================================================
-- T-12: HAFTALIK KULLANIM GORUNTUSU (dönem silmeden ÖNCE)
-- ============================================================

do $blk$
declare
  v_usage jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999901","role":"authenticated"}', true);

  v_usage := public.get_my_weekly_usage();

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa_true('T-12',
    'kullanim goruntusu: yil/hafta/ders/500 dogru',
    v_usage->>'academic_year' = 'QA-Y-2099'
      and v_usage->>'week' = '5'
      and (v_usage->'subjects'->0->>'new_questions_used') = '500'
      and (v_usage->'subjects'->0->>'limit') = '500',
    v_usage::text);
end;
$blk$;


-- ============================================================
-- T-11: AKADEMIK DONEM YOKSA FAIL-CLOSED (karar #1)
-- ============================================================

delete from public.academic_weeks where academic_year = 'QA-Y-2099';

do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-9999-999999999901","role":"authenticated"}', true);

  perform public._qa_expect('T-11a',
    'donem yok: secim fail-closed',
    'P0001',
    $sql$select public.select_training_questions(
      '430903f3-527e-4e12-b7e8-ac0afdb784aa', 5)$sql$);

  perform public._qa_expect('T-11b',
    'donem yok: ingest fail-closed',
    'P0001',
    $sql$select public.ingest_student_attempt(
      '33333333-3333-3333-3333-000000000002',
      'training', 'correct', 5000)$sql$);

  perform public._qa_expect('T-11c',
    'donem yok: usage goruntusu fail-closed',
    'P0001',
    $sql$select public.get_my_weekly_usage()$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- TEMIZLIK (suite ici; ayrica final ROLLBACK her seyi geri alir)
-- ============================================================

-- Snapshot korumasini gecmek icin once statuleri pasif duruma al.
update public.competitions
   set status = 'cancelled'
 where id::text like '11111111-1111-1111-1111-%';

delete from public.competition_questions
 where competition_id::text like '11111111-1111-1111-1111-%';

delete from public.competition_players
 where competition_id::text like '11111111-1111-1111-1111-%';

delete from public.competitions
 where id::text like '11111111-1111-1111-1111-%';

delete from public.scoring_rule_sets where rule_set_code = 'QA2-RS';

delete from public.student_question_attempts
 where user_id in ('99999999-9999-9999-9999-999999999901',
                   '99999999-9999-9999-9999-999999999902');

delete from public.student_dimension_metrics
 where user_id in ('99999999-9999-9999-9999-999999999901',
                   '99999999-9999-9999-9999-999999999902');

delete from public.student_question_exposures
 where user_id in ('99999999-9999-9999-9999-999999999901',
                   '99999999-9999-9999-9999-999999999902');

delete from public.student_pack_exposures
 where user_id in ('99999999-9999-9999-9999-999999999901',
                   '99999999-9999-9999-9999-999999999902');

delete from public.student_weekly_counters
 where academic_year like 'QA-%';

delete from public.question_vault_memberships m
using public.question_vaults v
where m.vault_id = v.id and v.vault_code like 'QA2-V-%';

delete from public.question_vaults where vault_code like 'QA2-V-%';

delete from public.question_outcome_mappings
 where question_id::text like '33333333-3333-3333-3333-%';

delete from public.question_curriculum_mappings
 where question_id::text like '33333333-3333-3333-3333-%';

delete from public.questions
 where question_code like 'Q2-%';

delete from public.curriculum_schedule_items
 where schedule_profile_id = '77777777-7777-7777-7777-777777777701';

delete from public.curriculum_schedule_profiles
 where code = 'QA2-SCHED';

delete from public.curriculum_outcomes
 where outcome_text like 'QA2 %';

delete from public.subtopics where slug = 'qa2-alt-konu';

delete from public.topics where slug like 'qa2-%';

delete from public.academic_weeks where academic_year like 'QA-%';

delete from public.curriculum_versions
 where academic_year like 'QA-%';

delete from public.student_profiles
 where nickname like 'QA2-NICK-%';

delete from auth.users where email like '%@test.local';


-- ============================================================
-- TEMIZLIK DOGRULAMASI (suite ici, rollback oncesi durum)
-- ============================================================

select
  (select count(*) from auth.users
    where email like '%@test.local')                                          as users_kalan,
  (select count(*) from public.questions
    where question_code like 'Q2-%')                                          as questions_kalan,
  (select count(*) from public.question_vaults
    where vault_code like 'QA2-V-%')                                          as vaults_kalan,
  (select count(*) from public.student_weekly_counters
    where academic_year like 'QA-%')                                          as counters_kalan,
  (select count(*) from public.student_question_exposures
    where user_id::text like '99999999%')                                      as qexpo_kalan,
  (select count(*) from public.student_pack_exposures
    where user_id::text like '99999999%')                                      as pexpo_kalan,
  (select count(*) from public.student_question_attempts
    where user_id::text like '99999999%')                                      as attempts_kalan,
  (select count(*) from public.student_dimension_metrics
    where user_id::text like '99999999%')                                      as metrics_kalan,
  (select count(*) from public.academic_weeks
    where academic_year like 'QA-%')                                          as weeks_kalan,
  (select count(*) from public.competitions
    where competition_code like 'QA2-C-%')                                    as comps_kalan;


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
from public._qa_faz2_results
group by label
order by label;

with g as (
  select label, bool_and(result = 'PASS') as ok
  from public._qa_faz2_results
  group by label
)
select
  count(*)                        as toplam_test,
  count(*) filter (where ok)      as gecen,
  count(*) filter (where not ok)  as kalan
from g;


drop function public._qa_true(text, text, boolean, text);
drop function public._qa_expect(text, text, text, text);
drop table public._qa_faz2_results;

rollback;
