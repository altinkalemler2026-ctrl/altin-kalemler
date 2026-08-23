-- ============================================================
-- scripts/qa_faz3_local_validation.sql
-- Altin Kalemler - Migration Faz 3 Temel QA suite (070)
--
-- Kapsam:
--   T-S        : yetki sinirlari - anon/authenticated denials,
--                sahte-sonuç kapisi (ingest EXECUTE revoke)
--   T-A        : antrenman secimi -> training exposure olusumu
--   T-B        : dogruluk YALNIZ DB'de hesaplanir (correct_answer),
--                istemci sonuc gonderemez (p_result yok)
--   T-C        : idempotency - ayni client_key tek attempt + tek metrik,
--                DB seviyesinde partial unique index savunmasi
--   T-D        : exposure olmadan cevap YOK + cross-user izolasyonu
--   T-E        : pass/timeout/blank eylemleri + metrik yansimasi
--   T-F        : guvenlik - minimal yanit (allowlist), sure clamp,
--                aktif olmayan/cevapsiz soru fail-closed
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_faz3_local_validation.sql supabase_db_yarisma-programi:/tmp/
--   docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -f /tmp/qa_faz3_local_validation.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
--
-- NOT (070 devir teslimi): ingest_student_attempt artik authenticated'a
-- KAPALIDIR. Bu suite RPC cagrilari postgres roluyle ama JWT claim'leri
-- ile yapar; auth.uid() claim'den okunur, davranis aynidir.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR (faz2 deseniyle ayni)
-- ============================================================

create table public._qa_faz3_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_faz3_results
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
      insert into public._qa_faz3_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_faz3_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_faz3_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_faz3_results
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
  insert into public._qa_faz3_results
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
-- Sorularin correct_answer degerleri bilinir (grading testlerinin temeli):
--   Q3-01='C'  Q3-02='A'  Q3-03='B'  Q3-04='D'  Q3-05='E'
-- ============================================================

insert into auth.users (id, email) values
  ('99999999-9999-9999-8888-999999999901', 'qa3-user-a@test.local'),
  ('99999999-9999-9999-8888-999999999902', 'qa3-user-b@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('99999999-9999-9999-8888-999999999901', 12, 'QA3-NICK-A'),
  ('99999999-9999-9999-8888-999999999902', 12, 'QA3-NICK-B');

insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('88888888-8888-8888-7777-888888888801', 'QA3-Y-2099', 'MEB-QA3', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('77777777-7777-7777-6666-777777777701', 'QA3-SCHED', 'QA3 Profil',
   '88888888-8888-8888-7777-888888888801', true, true);

insert into public.academic_weeks (academic_year, week, starts_at, ends_at) values
  ('QA3-Y-2099', 5, current_date - 3, current_date + 4),
  ('QA3-Y-2099', 6, current_date + 4, current_date + 11);

insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('66666666-6666-6666-5555-000000000001',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   12, 'QA3 Islenmis Konu', 'qa3-islenmis',
   '88888888-8888-8888-7777-888888888801');

insert into public.subtopics (id, topic_id, name, slug) values
  ('55555555-5555-5555-4444-000000000001',
   '66666666-6666-6666-5555-000000000001',
   'QA3 Alt Konu', 'qa3-alt-konu');

insert into public.curriculum_outcomes
  (id, curriculum_version_id, grade_level, subject_id, outcome_text) values
  ('44444444-4444-4444-3333-000000000001',
   '88888888-8888-8888-7777-888888888801', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   'QA3 kazanım metni');

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, start_week, end_week) values
  ('77777777-7777-7777-6666-777777777701', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '66666666-6666-6666-5555-000000000001', 1, 3);

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, outcome_id, start_week) values
  ('77777777-7777-7777-6666-777777777701', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '44444444-4444-4444-3333-000000000001', 2);

-- Sorular (correct_answer dahil).
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer)
values
  ('33333333-3333-3333-7777-000000000031', 'Q3-01', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'C'),
  ('33333333-3333-3333-7777-000000000032', 'Q3-02', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'acik_uclu', 'A'),
  ('33333333-3333-3333-7777-000000000033', 'Q3-03', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'hard', 'comprehension', 'dogru_yanlis', 'B'),
  ('33333333-3333-3333-7777-000000000034', 'Q3-04', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'D'),
  ('33333333-3333-3333-7777-000000000035', 'Q3-05', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'medium', 'application', 'bosluk_doldurma', 'E'),
  -- Fail-closed testleri icin secim havuzuna GIRMEYEN sorular:
  ('33333333-3333-3333-7777-000000000036', 'Q3-06', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', false,
   'easy', 'learning', 'coktan_secmeli', 'A'),
  ('33333333-3333-3333-7777-000000000037', 'Q3-07', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', null);

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, subtopic_id, review_status)
select ('33333333-3333-3333-7777-0000000000' || n)::uuid,
       '88888888-8888-8888-7777-888888888801',
       '66666666-6666-6666-5555-000000000001',
       '55555555-5555-5555-4444-000000000001', 'approved'
  from unnest(array['31','32','33','34','35']) n;

insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id) values
  ('22222222-2222-2222-1111-00000000000a', 'QA3-V-PRACTICE',
   'QA3 Antrenman Kasasi', 'practice', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, practice_eligible)
select '22222222-2222-2222-1111-00000000000a',
       ('33333333-3333-3333-7777-0000000000' || n)::uuid, 'active', true
  from unnest(array['31','32','33','34','35']) n;


-- ============================================================
-- SABITLER
-- ============================================================

-- client_key havuzu (idempotency testlerinde tekrar kullanilir)
--   key01..key09 = aaaaaaaa-aaaa-aaaa-aaaa-00000000000N


-- ============================================================
-- T-S: YETKI SINIRLARI
-- ============================================================

do $blk$
begin
  perform public._qa_true('T-S1',
    'anon: submit_training_attempt EXECUTE yetkisi yok',
    not has_function_privilege('anon',
      'public.submit_training_attempt(uuid,text,text,integer,uuid)', 'EXECUTE'),
    null);

  perform public._qa_true('T-S2',
    'authenticated: submit_training_attempt EXECUTE izni var',
    has_function_privilege('authenticated',
      'public.submit_training_attempt(uuid,text,text,integer,uuid)', 'EXECUTE'),
    null);

  perform public._qa_true('T-S3',
    'SAHTE-SONUC KAPISI: authenticated artik ingest_student_attempt cagiramaz',
    not has_function_privilege('authenticated',
      'public.ingest_student_attempt(uuid,text,text,integer,uuid,jsonb)', 'EXECUTE'),
    null);
end;
$blk$;

do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-8888-999999999901","role":"authenticated"}', true);

  perform public._qa_expect('T-S4',
    'calisma zamaninda da 42501: authenticated ingest cagrisi',
    '42501',
    $sql$select public.ingest_student_attempt(
      '33333333-3333-3333-7777-000000000031',
      'training', 'correct', 1000)$sql$);

  perform public._qa_expect('T-S5',
    'istemci attempts tablosuna dogrudan INSERT yapamaz',
    '42501',
    $sql$insert into public.student_question_attempts
        (user_id, question_id, subject_id, attempt_context, result,
         attempt_number, time_ms, academic_year, week, metadata)
        values
        ('99999999-9999-9999-8888-999999999901',
         '33333333-3333-3333-7777-000000000031',
         '430903f3-527e-4e12-b7e8-ac0afdb784aa',
         'training', 'correct', 1, 1000, 'QA3-Y-2099', 5, '{}'::jsonb)$sql$);

  perform public._qa_expect('T-S6',
    'istemci exposures tablosuna dogrudan INSERT yapamaz',
    '42501',
    $sql$insert into public.student_question_exposures
        (user_id, question_id, attempt_context)
        values
        ('99999999-9999-9999-8888-999999999901',
         '33333333-3333-3333-7777-000000000031', 'training')$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-A: SECIM -> EXPOSURE
-- ============================================================

do $blk$
declare
  v_res jsonb;
  v_cnt integer;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-8888-999999999901","role":"authenticated"}', true);

  select public.select_training_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa', 5)
    into v_res;

  perform public._qa_true('T-A1',
    'UA secimi: 5 yeni soru, haftalik sayac 5',
    (v_res->>'new_count') = '5'
      and (v_res->'weekly'->>'new_questions_used') = '5',
    'payload=' || left(v_res::text, 200));

  select count(*) into v_cnt
    from public.student_question_exposures
   where user_id = '99999999-9999-9999-8888-999999999901'
     and attempt_context = 'training';

  perform public._qa_true('T-A2',
    'UA icin 5 training exposure kaydi olustu',
    v_cnt = 5,
    'count=' || v_cnt);

  perform set_config('request.jwt.claims', '', true);
end;
$blk$;


-- ============================================================
-- T-B: DOGRULUK YALNIZ DB'DE HESAPLANIR
-- ============================================================

do $blk$
declare
  v_q31 uuid := '33333333-3333-3333-7777-000000000031';
  v_q32 uuid := '33333333-3333-3333-7777-000000000032';
  v_q33 uuid := '33333333-3333-3333-7777-000000000033';
  v_r   jsonb;
  r     record;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-8888-999999999901","role":"authenticated"}', true);

  -- Q3-01 correct='C'; istemci 'A' der -> DB 'wrong' der.
  select public.submit_training_attempt(v_q31, 'A', null, 45000,
           'aaaaaaaa-aaaa-aaaa-aaaa-000000000001')
    into v_r;

  perform public._qa_true('T-B1',
    'DB-side grading: yanlis sik -> result=wrong',
    (v_r->>'result') = 'wrong'
      and (v_r->>'duplicate') = 'false'
      and (v_r->>'attempt_number') = '1',
    'resp=' || left(v_r::text, 160));

  -- Q3-02 correct='A'; istemci 'A' der -> 'correct'.
  select public.submit_training_attempt(v_q32, 'A', null, 20000,
           'aaaaaaaa-aaaa-aaaa-aaaa-000000000002')
    into v_r;

  perform public._qa_true('T-B2',
    'DB-side grading: dogru sik -> result=correct',
    (v_r->>'result') = 'correct'
      and (v_r->>'duplicate') = 'false',
    'resp=' || left(v_r::text, 160));

  -- Buyuk/kucuk harf esnekligi: 'b' -> Q3-03 correct='B' -> correct.
  select public.submit_training_attempt(v_q33, 'b', null, 15000,
           'aaaaaaaa-aaaa-aaaa-aaaa-000000000003')
    into v_r;

  perform public._qa_true('T-B3',
    'harf normalizasyonu: b -> correct',
    (v_r->>'result') = 'correct',
    'resp=' || left(v_r::text, 160));

  perform set_config('request.jwt.claims', '', true);

  -- Metrikler: toplam 3, correct 2, wrong 1, pass_timeout 0.
  select * into r
    from public.student_dimension_metrics
   where user_id = '99999999-9999-9999-8888-999999999901'
     and metric_scope = 'subject'
     and scope_key = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_true('T-B4',
    'metrikler dogru birikir (tot=3, c=2, w=1, pt=0)',
    r.total_attempts = 3
      and r.correct_count = 2
      and r.wrong_count = 1
      and r.pass_timeout_count = 0,
    format('tot=%s c=%s w=%s pt=%s',
      r.total_attempts, r.correct_count, r.wrong_count, r.pass_timeout_count));
end;
$blk$;

do $blk$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-8888-999999999901","role":"authenticated"}', true);

  perform public._qa_expect('T-B5',
    'istemci sonuc BILDIREMEZ: p_result parametresi mevcut degil',
    '42883',
    $sql$select public.submit_training_attempt(
      '33333333-3333-3333-7777-000000000031',
      p_choice => 'A', p_result => 'correct',
      p_client_key => 'aaaaaaaa-aaaa-aaaa-aaaa-000000000099')$sql$);

  perform public._qa_expect('T-B6',
    'gecersiz sik reddedilir',
    'P0001',
    $sql$select public.submit_training_attempt(
      '33333333-3333-3333-7777-000000000031',
      'F', null, 1000,
      'aaaaaaaa-aaaa-aaaa-aaaa-000000000098')$sql$);

  perform public._qa_expect('T-B7',
    'secim + eylem birlikte gönderilemez',
    'P0001',
    $sql$select public.submit_training_attempt(
      '33333333-3333-3333-7777-000000000032',
      'A', 'pass', 1000,
      'aaaaaaaa-aaaa-aaaa-aaaa-000000000097')$sql$);

  perform set_config('request.jwt.claims', '', true);
end;
$blk$;


-- ============================================================
-- T-C: IDEMPOTENCY
-- ============================================================

do $blk$
declare
  v_q31 uuid := '33333333-3333-3333-7777-000000000031';
  v_first jsonb;
  v_again jsonb;
  v_cnt   integer;
  r       record;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-8888-999999999901","role":"authenticated"}', true);

  -- key01 ilk cevapta 'wrong' oldu (T-B1). AYNI anahtarla bu kez
  -- 'dogru olacak' sik gönderiliyor: sonuç DEGISMEMELI.
  select public.submit_training_attempt(v_q31, 'C', null, 99999,
           'aaaaaaaa-aaaa-aaaa-aaaa-000000000001')
    into v_again;

  perform public._qa_true('T-C1',
    'ayni key: duplicate=true, orijinal sonuc korunur',
    (v_again->>'duplicate') = 'true'
      and (v_again->>'result') = 'wrong'
      and (v_again->>'attempt_number') = '1',
    'resp=' || left(v_again::text, 160));

  select count(*) into v_cnt
    from public.student_question_attempts
   where user_id = '99999999-9999-9999-8888-999999999901'
     and question_id = v_q31;

  perform public._qa_true('T-C2',
    'ayni key ikinci attempt URETMEZ',
    v_cnt = 1,
    'attempts=' || v_cnt);

  perform set_config('request.jwt.claims', '', true);

  select * into r
    from public.student_dimension_metrics
   where user_id = '99999999-9999-9999-8888-999999999901'
     and metric_scope = 'subject'
     and scope_key = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_true('T-C3',
    'metrik cift artmamistir (hala tot=3)',
    r.total_attempts = 3,
    'tot=' || r.total_attempts);

  -- DB seviyesi savunma: pre-check'i atlayip dogrudan ayni key ile
  -- INSERT -> partial unique index 23505 vermeli.
  begin
    insert into public.student_question_attempts
      (user_id, question_id, subject_id, attempt_context, result,
       attempt_number, time_ms, academic_year, week, metadata)
    values
      ('99999999-9999-9999-8888-999999999901', v_q31,
       '430903f3-527e-4e12-b7e8-ac0afdb784aa',
       'training', 'correct', 99, 1000, 'QA3-Y-2099', 5,
       jsonb_build_object('client_key', 'aaaaaaaa-aaaa-aaaa-aaaa-000000000001'));

    perform public._qa_true('T-C4',
      'partial unique index ayni key ikinci satira IZIN VERMEZ',
      false,
      'INSERT beklenmedik sekilde basarili');
  exception
    when unique_violation then
      perform public._qa_true('T-C4',
        'partial unique index ayni key ikinci satira IZIN VERMEZ',
        true,
        '23505 unique_violation');
  end;
end;
$blk$;


-- ============================================================
-- T-D: EXPOSURE KAPISI + CROSS-USER
-- ============================================================

do $blk$
declare
  v_res jsonb;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-8888-999999999902","role":"authenticated"}', true);

  -- UB hicbir training sorusu gormedi.
  perform public._qa_expect('T-D1',
    'exposure yoksa cevap yazilamaz (cross-user)',
    'P0001',
    $sql$select public.submit_training_attempt(
      '33333333-3333-3333-7777-000000000031',
      'A', null, 5000,
      'aaaaaaaa-aaaa-aaaa-aaaa-000000000010')$sql$);

  -- UB kendi secimini yapar; sonra soruyu SADECE kendisi cevaplayabilir.
  select public.select_training_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa', 5)
    into v_res;

  perform public._qa_true('T-D2',
    'UB secimi bagimsiz (5 yeni)',
    (v_res->>'new_count') = '5',
    'payload=' || left(v_res::text, 120));

  perform set_config('request.jwt.claims', '', true);
end;
$blk$;

do $blk$
declare
  v_res jsonb;
  r     record;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-8888-999999999902","role":"authenticated"}', true);

  select public.submit_training_attempt(
           '33333333-3333-3333-7777-000000000034', 'D', null, 25000,
           'aaaaaaaa-aaaa-aaaa-aaaa-000000000011')
    into v_res;

  perform public._qa_true('T-D3',
    'kendi exposure''u olan soruya cevap yazar, result=DB''den',
    (v_res->>'result') = 'correct',
    'resp=' || left(v_res::text, 160));

  perform set_config('request.jwt.claims', '', true);

  select * into r
    from public.student_question_attempts
   where metadata ->> 'client_key' = 'aaaaaaaa-aaaa-aaaa-aaaa-000000000011'
     and user_id = '99999999-9999-9999-8888-999999999902';

  perform public._qa_true('T-D4',
    'user_id her zaman auth.uid()''den gelir (UB''ye ait)',
    r.user_id = '99999999-9999-9999-8888-999999999902',
    'owner=' || coalesce(r.user_id::text, '?'));
end;
$blk$;


-- ============================================================
-- T-E: EYLEMLER (pass / timeout / blank)
-- ============================================================

do $blk$
declare
  v_r jsonb;
  r   record;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-8888-999999999901","role":"authenticated"}', true);

  select public.submit_training_attempt(
           '33333333-3333-3333-7777-000000000035', null, 'pass', 8000,
           'aaaaaaaa-aaaa-aaaa-aaaa-000000000004')
    into v_r;
  perform public._qa_true('T-E1', 'pass eylemi -> result=pass',
    (v_r->>'result') = 'pass', 'resp=' || left(v_r::text, 120));

  select public.submit_training_attempt(
           '33333333-3333-3333-7777-000000000035', null, 'timeout', 60000,
           'aaaaaaaa-aaaa-aaaa-aaaa-000000000005')
    into v_r;
  perform public._qa_true('T-E2', 'timeout eylemi -> result=timeout',
    (v_r->>'result') = 'timeout', 'resp=' || left(v_r::text, 120));

  select public.submit_training_attempt(
           '33333333-3333-3333-7777-000000000035', null, 'blank', 0,
           'aaaaaaaa-aaaa-aaaa-aaaa-000000000006')
    into v_r;
  perform public._qa_true('T-E3', 'blank eylemi -> result=blank',
    (v_r->>'result') = 'blank', 'resp=' || left(v_r::text, 120));

  perform public._qa_expect('T-E4',
    'gecersiz eylem reddedilir',
    'P0001',
    $sql$select public.submit_training_attempt(
      '33333333-3333-3333-7777-000000000035',
      null, 'skip', 1000,
      'aaaaaaaa-aaaa-aaaa-aaaa-000000000096')$sql$);

  perform set_config('request.jwt.claims', '', true);

  select * into r
    from public.student_dimension_metrics
   where user_id = '99999999-9999-9999-8888-999999999901'
     and metric_scope = 'subject'
     and scope_key = '430903f3-527e-4e12-b7e8-ac0afdb784aa';

  perform public._qa_true('T-E5',
    'pass+timeout metrike yansir (pt=2, tot=6)',
    r.pass_timeout_count = 2 and r.total_attempts = 6,
    format('tot=%s pt=%s', r.total_attempts, r.pass_timeout_count));
end;
$blk$;


-- ============================================================
-- T-F: GUVENLIK DETAYLARI
-- ============================================================

do $blk$
declare
  v_r jsonb;
  v_keys text[];
  v_k  text;
  v_ok boolean;
  v_time integer;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-8888-999999999901","role":"authenticated"}', true);

  -- Minimal yanit sözlesmesi: yalniz izinli anahtarlar.
  select public.submit_training_attempt(
           '33333333-3333-3333-7777-000000000035', 'E', null, 12000,
           'aaaaaaaa-aaaa-aaaa-aaaa-000000000007')
    into v_r;

  v_keys := array(select jsonb_object_keys(v_r));
  v_ok := true;
  foreach v_k in array v_keys loop
    if v_k not in ('attempt_id', 'attempt_number', 'result', 'duplicate') then
      v_ok := false;
    end if;
  end loop;

  perform public._qa_true('T-F1',
    'yanit ALLOWLIST: yalniz 4 anahtar',
    v_ok and array_length(v_keys, 1) = 4,
    'keys=' || array_to_string(v_keys, ','));

  perform public._qa_true('T-F2',
    'yanitta correct_answer/cozum SIZMAZ',
    not (v_r ? 'correct_answer')
      and not (v_r ? 'solution')
      and position('correct_answer' in v_r::text) = 0,
    'resp=' || left(v_r::text, 160));

  -- Sure clamp: negatif -> 0.
  select public.submit_training_attempt(
           '33333333-3333-3333-7777-000000000034', 'D', null, -500,
           'aaaaaaaa-aaaa-aaaa-aaaa-000000000008')
    into v_r;

  perform set_config('request.jwt.claims', '', true);

  select a.time_ms into v_time
    from public.student_question_attempts a
   where a.metadata ->> 'client_key' = 'aaaaaaaa-aaaa-aaaa-aaaa-000000000008'
     and a.user_id = '99999999-9999-9999-8888-999999999901';

  perform public._qa_true('T-F3',
    'negatif sure 0''a clamp''lenir',
    v_time = 0,
    'time_ms=' || coalesce(v_time::text, '?'));

  -- Fail-closed: aktif olmayan soru (stale exposure ile dahi).
  insert into public.student_question_exposures
    (user_id, question_id, attempt_context)
  values
    ('99999999-9999-9999-8888-999999999901',
     '33333333-3333-3333-7777-000000000036', 'training'),
    ('99999999-9999-9999-8888-999999999901',
     '33333333-3333-3333-7777-000000000037', 'training');

  perform set_config('request.jwt.claims',
    '{"sub":"99999999-9999-9999-8888-999999999901","role":"authenticated"}', true);

  perform public._qa_expect('T-F4',
    'aktif olmayan soru puanlanamaz (fail-closed)',
    'P0001',
    $sql$select public.submit_training_attempt(
      '33333333-3333-3333-7777-000000000036',
      'A', null, 1000,
      'aaaaaaaa-aaaa-aaaa-aaaa-000000000095')$sql$);

  perform public._qa_expect('T-F5',
    'cevap anahtari olmayan soru puanlanamaz (fail-closed)',
    'P0001',
    $sql$select public.submit_training_attempt(
      '33333333-3333-3333-7777-000000000037',
      'A', null, 1000,
      'aaaaaaaa-aaaa-aaaa-aaaa-000000000094')$sql$);

  perform public._qa_expect('T-F6',
    'client_key zorunlu',
    '22004',
    $sql$select public.submit_training_attempt(
      '33333333-3333-3333-7777-000000000034',
      'D', null, 1000, null)$sql$);

  perform set_config('request.jwt.claims', '', true);
end;
$blk$;


-- ============================================================
-- RAPOR + TEMIZLIK + ROLLBACK
-- ============================================================

\echo ''
\echo '===== QA FAZ 3 SONUCLAR ====='
select label, title, result, coalesce(detail, '') as detail
  from public._qa_faz3_results
 order by label;

do $blk$
declare
  v_pass integer;
  v_fail integer;
begin
  select count(*) filter (where result = 'PASS'),
         count(*) filter (where result = 'FAIL')
    into v_pass, v_fail
    from public._qa_faz3_results;

  raise notice 'QA FAZ 3: % PASS / % FAIL', v_pass, v_fail;

  if v_fail > 0 then
    raise exception 'QA FAZ 3 BASARISIZ: % test kaldi', v_fail
      using errcode = 'P0001';
  end if;

  raise notice 'QA FAZ 3 TAMAM: kalan=0';
end;
$blk$;

rollback;
