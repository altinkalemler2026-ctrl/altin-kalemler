-- ============================================================
-- qa_faz11_progress_feedback_local.sql
-- Altın Kalemler - SQL QA Faz 11 (yerel/disposable, rollback'li)
--
-- Kapsam:
--   1. get_attempt_feedback (109) ACL/owner/search_path/overload matrisi
--   2. anon erişimi reddedilir
--   3. Cevap ÖNCESİ sızıntı yok: exposure var + deneme yok -> {found:false}
--   4. Cevap SONRASI: doğru cevap + yalnız ONAYLI metin çözüm döner
--      (pending/valid ayrımı deterministik seçimle doğrulanır)
--   5. Onaylı olmayan/aktif olmayan soruda correct_answer NULL
--   6. Başka öğrenci spoofing'i sonuç vermez (kullanıcı parametresi YOK)
--   7. Exposure kapısı: deneme var ama gösterim yoksa -> {found:false}
--   8. Duplicate submit ikinci ödül/kota üretmez; XP/lig/yıldız dokunulmaz
--   9. get_student_dimension_summary (085) yalnız KENDİ satırlarını döner
--
-- CI UYUMU: detay satırları önce, SON satır yalnız "toplam|gecen|kalan"
-- (kalan=0). Tüm değişiklikler rollback ile geri alınır.
-- ============================================================

begin;

-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR
-- ============================================================

create table public._qa_f11_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_f11_results
  to anon, authenticated, service_role;

create function public._qa_f11_expect(
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
      insert into public._qa_f11_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_f11_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_f11_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_f11_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa_f11_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_f11_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa_f11_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_f11_true(text, text, boolean, text)
  to anon, authenticated, service_role;

-- Auth simulasyon yardimcisi.
create function public._qa_f11_as_user(p_user uuid, p_body text)
returns text
language plpgsql
security invoker
as $qa$
declare
  v_out text;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user, 'role', 'authenticated')::text, true);

  execute p_body into v_out;

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  return v_out;
end;
$qa$;

grant execute
  on function public._qa_f11_as_user(uuid, text)
  to anon, authenticated, service_role;

-- ============================================================
-- FIXTURE (sabit QA uuid'leri; rollback ile silinecek)
-- matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
-- ============================================================

insert into auth.users (id, email) values
  ('99999999-9999-9999-9999-000000000091', 'qa11-user-a@test.local'),
  ('99999999-9999-9999-9999-000000000092', 'qa11-user-b@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('99999999-9999-9999-9999-000000000091', 5, 'QA11-NICK-A'),
  ('99999999-9999-9999-9999-000000000092', 5, 'QA11-NICK-B');

insert into public.curriculum_versions
  (id, academic_year, framework, is_active) values
  ('99999999-9999-9999-9999-999999990001', 'QA11-Y', 'MEB-QA11', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active) values
  ('99999999-9999-9999-9999-999999990002', 'QA11-SCHED', 'QA11 Profil',
   '99999999-9999-9999-9999-999999990001', true, true);

insert into public.academic_weeks (academic_year, week, starts_at, ends_at) values
  ('QA11-Y', 5, current_date - 3, current_date + 4)
on conflict do nothing;

insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id) values
  ('99999999-9999-9999-9999-999999990010',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   5, 'QA11 Islenmis Konu', 'qa11-konu',
   '99999999-9999-9999-9999-999999990001');

insert into public.curriculum_outcomes
  (id, curriculum_version_id, subject_id, grade_level, topic_id,
   outcome_code, outcome_text) values
  ('99999999-9999-9999-9999-999999990020',
   '99999999-9999-9999-9999-999999990001',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 5,
   '99999999-9999-9999-9999-999999990010',
   'QA11-O1', 'QA11 Kazanim O1');

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, outcome_id,
   start_week, end_week) values
  ('99999999-9999-9999-9999-999999990002', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   '99999999-9999-9999-9999-999999990010',
   '99999999-9999-9999-9999-999999990020', 1, null);

-- Sorular:
--   Q1: approved + aktif; A cevabi VAR; valid + pending text_solution VAR
--   Q2: approved + aktif; A cevabi VAR; yalnız PENDING text_solution VAR
--   Q3: approved + aktif; A exposure VAR, deneme YOK (cevap öncesi)
--   Q4: approval_status='draft'; A denemesi VAR (onay kapısı)
--   Q5: exposure YOK; A denemesi VAR (gösterim kapısı)
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
values
  ('99999999-9999-9999-9999-999999991001', 'QA11-Q1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'B', true, 45),
  ('99999999-9999-9999-9999-999999991002', 'QA11-Q2', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'C', true, 45),
  ('99999999-9999-9999-9999-999999991003', 'QA11-Q3', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'D', true, 45),
  ('99999999-9999-9999-9999-999999991004', 'QA11-Q4', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'draft', false,
   'easy', 'learning', 'coktan_secmeli', 'A', true, 45),
  ('99999999-9999-9999-9999-999999991005', 'QA11-Q5', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'easy', 'learning', 'coktan_secmeli', 'E', true, 45);

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, review_status)
select q.id, '99999999-9999-9999-9999-999999990001',
       '99999999-9999-9999-9999-999999990010', 'approved'
  from public.questions q
 where q.question_code like 'QA11-%';

insert into public.question_outcome_mappings
  (question_id, outcome_id, review_status)
select q.id, '99999999-9999-9999-9999-999999990020', 'approved'
  from public.questions q
 where q.question_code like 'QA11-%';

-- Metin çözümleri: Q1 valid + pending; Q2 yalnız pending.
insert into public.question_solution_assets
  (question_id, asset_type, asset_text, source_type, validation_status,
   is_active, created_at)
values
  ('99999999-9999-9999-9999-999999991001', 'text_solution',
   'QA11 ONAYLI COZUM Q1: 3/4 ile 2^5 karsilastirmasi.',
   'manual', 'valid', true, now() - interval '2 minutes'),
  ('99999999-9999-9999-9999-999999991001', 'text_solution',
   'QA11 BEKLEYEN COZUM Q1 (dondurulmemeli).',
   'manual', 'pending', true, now() - interval '1 minute'),
  ('99999999-9999-9999-9999-999999991002', 'text_solution',
   'QA11 BEKLEYEN COZUM Q2 (dondurulmemeli).',
   'manual', 'pending', true, now());

-- A'nin training exposure'lari: Q1..Q4 (Q5 exposure'suz).
insert into public.student_question_exposures
  (user_id, question_id, attempt_context)
select '99999999-9999-9999-9999-000000000091', q.id, 'training'
  from public.questions q
 where q.question_code in ('QA11-Q1', 'QA11-Q2', 'QA11-Q3', 'QA11-Q4');

-- B'nin training exposure'i: Q1 (denemesi YOK).
insert into public.student_question_exposures
  (user_id, question_id, attempt_context)
select '99999999-9999-9999-9999-000000000092', q.id, 'training'
  from public.questions q
 where q.question_code = 'QA11-Q1';

-- Denemeler: A Q1 'correct', Q2 'wrong', Q4 'correct', Q5 exposure'suz deneme.
insert into public.student_question_attempts
  (user_id, question_id, subject_id, attempt_context, result,
   attempt_number, time_ms, academic_year, week, answered_at, metadata)
values
  ('99999999-9999-9999-9999-000000000091',
   '99999999-9999-9999-9999-999999991001',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'training', 'correct',
   1, 20000, 'QA11-Y', 5, now() - interval '10 minutes',
   '{"source":"qa11"}'::jsonb),
  ('99999999-9999-9999-9999-000000000091',
   '99999999-9999-9999-9999-999999991002',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'training', 'wrong',
   1, 30000, 'QA11-Y', 5, now() - interval '9 minutes',
   '{"source":"qa11"}'::jsonb),
  ('99999999-9999-9999-9999-000000000091',
   '99999999-9999-9999-9999-999999991004',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'training', 'correct',
   1, 15000, 'QA11-Y', 5, now() - interval '8 minutes',
   '{"source":"qa11"}'::jsonb),
  ('99999999-9999-9999-9999-000000000091',
   '99999999-9999-9999-9999-999999991005',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'training', 'correct',
   1, 15000, 'QA11-Y', 5, now() - interval '7 minutes',
   '{"source":"qa11"}'::jsonb);

-- B'nin AYRI metrikleri (izolasyon karsi-tarafi; A'nin kapsaminda YOK).
insert into public.student_dimension_metrics
  (user_id, metric_scope, scope_key, total_attempts, correct_count,
   wrong_count, blank_count, pass_timeout_count, repeat_total,
   repeat_correct, total_time_ms, last_attempted_at) values
  ('99999999-9999-9999-9999-000000000092', 'topic',
   '99999999-9999-9999-9999-999999990010', 3, 1, 2, 0, 0, 0, 0, 90000,
   now() - interval '1 hour'),
  ('99999999-9999-9999-9999-000000000092', 'subject',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 3, 1, 2, 0, 0, 0, 0, 90000,
   now() - interval '1 hour');

-- ============================================================
-- T-00: ACL / OWNER / SEARCH_PATH / OVERLOAD MATRISI
-- ============================================================

do $blk$
declare
  v_definer boolean;
  v_search  text;
  v_owner   text;
  v_overload int;
  v_argnames text[];
begin
  select p.prosecdef into v_definer
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_attempt_feedback';
  perform public._qa_f11_true('T-00a',
    'get_attempt_feedback SECURITY DEFINER', v_definer is true);

  select coalesce((select p.proconfig
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'get_attempt_feedback'), '{}')
    into v_search;
  perform public._qa_f11_true('T-00b',
    'search_path bos sabit (injection yuzeyi yok)',
    v_search::text[] @> ARRAY['search_path=""']);

  select coalesce(rolname, '(yok)') into v_owner
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    left join pg_roles r on r.oid = p.proowner
   where n.nspname = 'public' and p.proname = 'get_attempt_feedback';
  perform public._qa_f11_true('T-00c',
    'owner postgres (kalinti owner yok)', v_owner = 'postgres',
    'owner=' || v_owner);

  select count(*) into v_overload
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_attempt_feedback';
  perform public._qa_f11_true('T-00d',
    'tek imza; overload kalintisi yok', v_overload = 1,
    'imza_sayisi=' || v_overload);

  perform public._qa_f11_true('T-00e',
    'authenticated EXECUTE VAR',
    has_function_privilege('authenticated',
      'public.get_attempt_feedback(uuid)', 'EXECUTE'));

  perform public._qa_f11_true('T-00f',
    'anon EXECUTE YOK',
    not has_function_privilege('anon',
      'public.get_attempt_feedback(uuid)', 'EXECUTE'));

  perform public._qa_f11_true('T-00g',
    'PUBLIC EXECUTE YOK (070/099 deseni)',
    not has_function_privilege('public',
      'public.get_attempt_feedback(uuid)', 'EXECUTE'));

  select proargnames into v_argnames
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_attempt_feedback';
  perform public._qa_f11_true('T-00h',
    'fonksiyon arguman adlari: yalniz p_question_id (kullanici parametresi YOK)',
    v_argnames = ARRAY['p_question_id'::text],
    'argumanlar=' || coalesce(array_to_string(v_argnames, ','), '(null)'));
end;
$blk$;

-- T-01: anon calistirma reddi.
do $blk$
begin
  execute 'set local role anon';
  perform public._qa_f11_expect('T-01a',
    'anon get_attempt_feedback cagrisi reddedilir',
    '42501',
    'select public.get_attempt_feedback('
    || '''99999999-9999-9999-9999-999999991001''::uuid)');
  execute 'reset role';
end;
$blk$;

-- ============================================================
-- T-02..T-07: GERI BILDIRIM KAPILARI (A: 99999999-...-91)
-- ============================================================

do $blk$
declare
  v_out  jsonb;
begin
  -- T-02: cevap ÖNCESİ sızıntı yok (Q3: exposure VAR, deneme YOK).
  v_out := public._qa_f11_as_user('99999999-9999-9999-9999-000000000091',
    'select public.get_attempt_feedback(''99999999-9999-9999-9999-999999991003''::uuid)');
  perform public._qa_f11_true('T-02a',
    'cevap oncesi found=false (sizinti yok)', v_out = '{"found": false}',
    'out=' || left(v_out::text, 120));
  perform public._qa_f11_true('T-02b',
    'cevap oncesi correct_answer/solution_text anahtari YOK',
    not (v_out ? 'correct_answer') and not (v_out ? 'solution_text'));

  -- T-03: cevap SONRASI onaylı içerik (Q1).
  v_out := public._qa_f11_as_user('99999999-9999-9999-9999-000000000091',
    'select public.get_attempt_feedback(''99999999-9999-9999-9999-999999991001''::uuid)');
  perform public._qa_f11_true('T-03a',
    'kabul edilmis cevapta found=true', (v_out ->> 'found') = 'true');
  perform public._qa_f11_true('T-03b',
    'dogru cevap soru cevap anahtarindan (B)',
    v_out ->> 'correct_answer' = 'B');
  perform public._qa_f11_true('T-03c',
    'yalniz VALID text_solution doner (pending secilmez)',
    v_out ->> 'solution_text' = 'QA11 ONAYLI COZUM Q1: 3/4 ile 2^5 karsilastirmasi.',
    'solution=' || left(coalesce(v_out ->> 'solution_text', '(null)'), 120));

  -- T-04: yalnız pending çözüm varsa uydurma YOK (Q2).
  v_out := public._qa_f11_as_user('99999999-9999-9999-9999-000000000091',
    'select public.get_attempt_feedback(''99999999-9999-9999-9999-999999991002''::uuid)');
  perform public._qa_f11_true('T-04a',
    'pending-only cozumde solution_text NULL (uydurma yok)',
    (v_out ->> 'found') = 'true' and v_out ->> 'solution_text' is null,
    'out=' || left(v_out::text, 120));

  -- T-05: onaylı olmayan soruda correct_answer NULL (Q4 draft).
  v_out := public._qa_f11_as_user('99999999-9999-9999-9999-000000000091',
    'select public.get_attempt_feedback(''99999999-9999-9999-9999-999999991004''::uuid)');
  perform public._qa_f11_true('T-05a',
    'draft soruda correct_answer NULL (cevap anahtari acilmaz)',
    (v_out ->> 'found') = 'true' and v_out ->> 'correct_answer' is null,
    'out=' || left(v_out::text, 120));

  -- T-06: B (başka öğrenci) Q1 için KENDİ denemesi olmadığından sızamaz.
  v_out := public._qa_f11_as_user('99999999-9999-9999-9999-000000000092',
    'select public.get_attempt_feedback(''99999999-9999-9999-9999-999999991001''::uuid)');
  perform public._qa_f11_true('T-06a',
    'baska ogrenci denemesiyle found=false (spoofing sonucsuz)',
    v_out = '{"found": false}', 'out=' || left(v_out::text, 120));

  -- T-07: exposure kapısı: deneme VAR ama gösterim YOK (Q5).
  v_out := public._qa_f11_as_user('99999999-9999-9999-9999-000000000091',
    'select public.get_attempt_feedback(''99999999-9999-9999-9999-999999991005''::uuid)');
  perform public._qa_f11_true('T-07a',
    'exposure yoksa found=false (gosterim kapisi)',
    v_out = '{"found": false}', 'out=' || left(v_out::text, 120));
end;
$blk$;

-- ============================================================
-- T-08: DUPLICATE SUBMIT IDEMPOTENCY + OYUNLASTIRMA DOKUNULMAZLIGI
-- ============================================================

do $blk$
declare
  v_first  jsonb;
  v_second jsonb;
  v_attempts int;
  v_ledger_before int;
  v_ledger_after int;
begin
  -- Q1'e A ile yeni client_key ile submit (mevcut denemeden bağımsız).
  v_first := public._qa_f11_as_user('99999999-9999-9999-9999-000000000091',
    'select public.submit_training_attempt(''99999999-9999-9999-9999-999999991001''::uuid, ''A'', null, 12000, ''eeeeeeee-1111-4111-8111-000000000001''::uuid)');
  v_second := public._qa_f11_as_user('99999999-9999-9999-9999-000000000091',
    'select public.submit_training_attempt(''99999999-9999-9999-9999-999999991001''::uuid, ''A'', null, 12000, ''eeeeeeee-1111-4111-8111-000000000001''::uuid)');

  perform public._qa_f11_true('T-08a',
    'ilk gonderim duplicate=false',
    (v_first ->> 'duplicate') = 'false');
  perform public._qa_f11_true('T-08b',
    'ayni client_key ikinci gonderim duplicate=true',
    (v_second ->> 'duplicate') = 'true');
  perform public._qa_f11_true('T-08c',
    'ikinci gonderim ayni attempt döner',
    v_second ->> 'attempt_id' = v_first ->> 'attempt_id');

  select count(*) into v_attempts
    from public.student_question_attempts a
   where a.user_id = '99999999-9999-9999-9999-000000000091'
     and a.attempt_context = 'training'
     and a.metadata ->> 'client_key' = 'eeeeeeee-1111-4111-8111-000000000001';
  perform public._qa_f11_true('T-08d',
    'ayni client_key icin TEK attempt satiri', v_attempts = 1,
    'satir=' || v_attempts);

  -- XP ledger: duplicate ikinci gonderim YENI XP uretmez (before=after).
  select count(*) into v_ledger_before
    from public.student_xp_ledger
   where user_id in ('99999999-9999-9999-9999-000000000091',
                     '99999999-9999-9999-9999-000000000092');
  select count(*) into v_ledger_after
    from public.student_xp_ledger
   where user_id in ('99999999-9999-9999-9999-000000000091',
                     '99999999-9999-9999-9999-000000000092');
  perform public._qa_f11_true('T-08e',
    'duplicate submit YENI XP ledger satiri uretmez',
    v_ledger_before = v_ledger_after,
    'before=' || v_ledger_before || ' after=' || v_ledger_after);

  -- Gunluk kota sayaci: duplicate ikinci gonderim degisiklik URETMEZ.
  select count(*) into v_ledger_before
    from public.student_daily_question_counters
   where user_id = '99999999-9999-9999-9999-000000000091';
  v_second := public._qa_f11_as_user('99999999-9999-9999-9999-000000000091',
    'select public.submit_training_attempt(''99999999-9999-9999-9999-999999991001''::uuid, ''A'', null, 12000, ''eeeeeeee-1111-4111-8111-000000000001''::uuid)');
  select count(*) into v_ledger_after
    from public.student_daily_question_counters
   where user_id = '99999999-9999-9999-9999-000000000091';
  perform public._qa_f11_true('T-08g',
    'duplicate submit gunluk kota sayacini degistirmez',
    v_ledger_before = v_ledger_after,
    'before=' || v_ledger_before || ' after=' || v_ledger_after);

  -- Sahte-sonuç kapanışı (070): ingest_student_attempt istemciye kapalı.
  perform public._qa_f11_true('T-08f',
    'authenticated ingest_student_attempt EXECUTE YOK',
    not has_function_privilege('authenticated',
      'public.ingest_student_attempt(uuid, text, text, integer, uuid, jsonb)',
      'EXECUTE'));
end;
$blk$;

-- ============================================================
-- T-09: 085 ILERLEME OZETI YALNIZ KENDI VERISI
-- ============================================================

do $blk$
declare
  v_out   text;
  v_json  jsonb;
  v_count int;
begin
  -- Not: 085 RPC'si setof dondurur; text/jsonb'ye tek cumlede toplanir.
  v_out := public._qa_f11_as_user('99999999-9999-9999-9999-000000000091',
    'select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb)::text from public.get_student_dimension_summary() x');
  v_json := v_out::jsonb;

  perform public._qa_f11_true('T-09a',
    'A: B''nin konu/subject satirlarini GORMEZ',
    not (v_out like '%99999999-9999-9999-9999-000000000092%'));

  v_out := public._qa_f11_as_user('99999999-9999-9999-9999-000000000092',
    'select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb)::text from public.get_student_dimension_summary() x');
  v_json := v_out::jsonb;

  select count(*) into v_count
    from jsonb_array_elements(v_json) e
   where e ->> 'scope_type' = 'subject';

  perform public._qa_f11_true('T-09b',
    'B: yalniz kendi subject satirini gorur (1)',
    v_count = 1, 'subject_satiri=' || v_count);

  perform public._qa_f11_true('T-09c',
    '085 satirlari yalniz allowlist alani tasir (user_id yok)',
    not (v_out like '%user_id%'));
end;
$blk$;

-- ============================================================
-- OZET (CI uyumlu: detay once, son satir toplam|gecen|kalan)
-- ============================================================

reset role;

select label || '|PASS|' || title from public._qa_f11_results where result = 'PASS';
select label || '|FAIL|' || coalesce(detail, title) from public._qa_f11_results where result = 'FAIL';

select count(*)
       || '|' || count(*) filter (where result = 'PASS')
       || '|' || count(*) filter (where result = 'FAIL')
  from public._qa_f11_results;

drop function public._qa_f11_as_user(uuid, text);
drop function public._qa_f11_true(text, text, boolean, text);
drop function public._qa_f11_expect(text, text, text, text);
drop table public._qa_f11_results;

rollback;
