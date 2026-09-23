-- ============================================================
-- scripts/qa_fizik_seed_intake_local.sql
-- Altin Kalemler - Migration 125 (Fizik TYMM 2026 outcome seed)
-- yerel disposable QA suite.
--
-- Kapsam:
--   F-01..F-03 : seed dogruluk (curriculum_versions + 22 FIZ.* outcome,
--                dagilim 9/10/11/12 = 6/5/8/3, 124 cozumleme sorgusu
--                tek eslesme, is_default korunumu)
--   F-04       : seed idempotency (ON CONFLICT DO NOTHING -> 0 yeni satir)
--   F-05       : yetkili Fizik intake happy-path (4 onemli FIZ.* kodu,
--                9/10/11/12) -> spec+staging atomik zinciri kurulur
--   F-06       : fail-closed: seed'de olmayan FIZ.9.1.3 -> outcome_not_found
--   F-07       : fail-closed: sinif uyusmazligi FIZ.9.1.1@10
--   F-08       : ACL kapisi: service_role/admin kabul; izinsiz P0001
--   F-09       : DTO ic yapi sizdirmaz + otomatik yayin yasagi
--   F-10       : regression: MAT.9.1.1 intake 125 sonrasi da cozulur
--
-- Calistirma (disposable DB, migration 001-125 uygulanmis):
--   docker cp scripts/qa_fizik_seed_intake_local.sql <db>:/tmp/
--   docker exec <db> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -A -t -f /tmp/qa_fizik_seed_intake_local.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti/kayit kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOLARI + YARDIMCILAR
-- ============================================================

create table public._qa_fizik_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_fizik_results
  to anon, authenticated, service_role;

create table public._qa_fizik_submits (
  key      text primary key,
  result   jsonb,
  is_err   boolean not null default false,
  sqlstate text,
  err_msg  text,
  created_at timestamptz not null default now()
);

grant select, insert, update, delete
  on public._qa_fizik_submits
  to anon, authenticated, service_role;

create function public._qa_fizik_true(
  p_label text, p_title text, p_ok boolean, p_detail text
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_fizik_results
  values (p_label, p_title, case when p_ok then 'PASS' else 'FAIL' end,
          coalesce(p_detail, ''));
end;
$qa$;

grant execute
  on function public._qa_fizik_true(text, text, boolean, text)
  to anon, authenticated, service_role;

create function public._qa_fizik_reg(
  p_key text, p_payload jsonb, p_role text, p_claims jsonb
)
returns void
language plpgsql
security invoker
as $qa$
declare
  v_res   jsonb;
  v_state text;
  v_msg   text;
begin
  execute format('set local role %I', p_role);
  perform set_config('request.jwt.claims', coalesce(p_claims::text, '{}'), true);
  perform set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
  if p_claims is not null and p_claims ? 'sub' then
    perform set_config('request.jwt.claim.sub', p_claims ->> 'sub', true);
  end if;

  begin
    execute 'select private.register_candidate_md_batch($1)::text' using p_payload
      into v_msg;
    v_res := v_msg::jsonb;
    v_state := 'OK';
  exception when others then
    v_res := null;
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;

  insert into public._qa_fizik_submits
    (key, result, is_err, sqlstate, err_msg)
  values
    (p_key, v_res, v_state <> 'OK',
     case when v_state = 'OK' then null else v_state end,
     case when v_state = 'OK' then null else v_msg end);

  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end;
$qa$;

grant execute
  on function public._qa_fizik_reg(text, jsonb, text, jsonb)
  to anon, authenticated, service_role;

create function public._qa_fizik_res(p_key text)
returns text
language sql
security invoker
as $qa$
  select result ->> 'status' from public._qa_fizik_submits where key = p_key
$qa$;

grant execute
  on function public._qa_fizik_res(text)
  to anon, authenticated, service_role;

create function public._qa_fizik_has_err(p_key text, p_code text)
returns boolean
language sql
security invoker
as $qa$
  select exists (
    select 1
      from public._qa_fizik_submits s
      join public.candidate_question_batches b
        on b.batch_key = s.result ->> 'batch_key'
      join public.candidate_batch_candidate_results r
        on r.batch_id = b.id
     where s.key = p_key
       and (r.validation_errors ? p_code)
       and r.validation_status in ('invalid', 'duplicate')
  );
$qa$;

grant execute
  on function public._qa_fizik_has_err(text, text)
  to anon, authenticated, service_role;

create function public._qa_fizik_expect(
  p_label text, p_title text, p_key text, p_state text, p_msg_like text default ''
)
returns void
language plpgsql
security invoker
as $qa$
declare
  v_row public._qa_fizik_submits%rowtype;
begin
  select * into v_row from public._qa_fizik_submits where key = p_key;

  if v_row.key is null then
    insert into public._qa_fizik_results
    values (p_label, p_title, 'FAIL', 'key bulunamadi: ' || p_key);
    return;
  end if;

  insert into public._qa_fizik_results
  values (
    p_label, p_title,
    case
      when v_row.is_err
       and v_row.sqlstate = p_state
       and (p_msg_like = '' or position(p_msg_like in coalesce(v_row.err_msg, '')) > 0)
      then 'PASS'
      else 'FAIL'
    end,
    'state=' || coalesce(v_row.sqlstate, 'OK')
    || ' msg=' || left(coalesce(v_row.err_msg, 'OK'), 160)
    || ' beklenen_state=' || p_state
    || case when p_msg_like <> '' then ' beklenen_msg=' || p_msg_like else '' end
  );
end;
$qa$;

grant execute
  on function public._qa_fizik_expect(text, text, text, text, text)
  to anon, authenticated, service_role;


-- ============================================================
-- PAYLOAD KURUCULAR (Fizik)
-- ============================================================

create function public._qa_fizik_candidate(
  p_client text, p_text text, p_subject text, p_grade integer, p_code text
)
returns jsonb
language sql
immutable
security invoker
as $qa$
  select jsonb_build_object(
      'client_question_id', p_client,
      'question_text', p_text,
      'subject_ref', p_subject,
      'grade_level', p_grade,
      'outcome_code', p_code,
      'difficulty', 'easy',
      'cognitive_type', 'learning',
      'estimated_solve_time_seconds', 60,
      'correct_answer', 'A',
      'options', jsonb_build_object(
        'A', 'QA Fizik secenek A', 'B', 'QA Fizik secenek B',
        'C', 'QA Fizik secenek C', 'D', 'QA Fizik secenek D',
        'E', 'QA Fizik secenek E'),
      'solution', jsonb_build_object(
        'method', 'Bilinen yontem kullanilir.',
        'steps', jsonb_build_array(
          'Adim 1: verilenler yazilir.',
          'Adim 2: islem yapilir ve sonuc bulunur.'),
        'result', 'Dogrulayici sonuc A secenegidir.',
        'correctAnswerJustification', 'A secenegindeki deger dogrudur.',
        'commonMistakes', jsonb_build_array('Yaygin hata isaret karisikligidir.'))
    )
$qa$;

create function public._qa_fizik_package(
  p_questions jsonb
)
returns jsonb
language sql
immutable
security invoker
as $qa$
  select jsonb_build_object(
      'schema_version', '1.1',
      'origin', 'curriculum_original',
      'producer', jsonb_build_object('id', 'qa-fiz-p01', 'model', 'qa-fiz-parser-v1'),
      'publication_allowed', false,
      'is_active', false,
      'validation_requested_status', 'needs_review',
      'metadata', jsonb_build_object(
        'out_of_package_count', 0,
        'out_of_package_kinds', jsonb_build_array()),
      'questions', p_questions
    )
$qa$;

grant execute
  on function public._qa_fizik_candidate(text, text, text, integer, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_fizik_package(jsonb)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE: yetkili / izinsiz QA kullanicilari
-- ============================================================

insert into auth.users
  (id, aud, role, email, encrypted_password, confirmed_at,
   raw_user_meta_data, created_at, updated_at)
values
  ('99770000-0000-0000-0000-000000000911', 'authenticated', 'authenticated',
   'qafiz-admin@e2e.test', '', now(),
   '{"nickname":"QAFiz_Admin"}'::jsonb, now(), now()),
  ('99770000-0000-0000-0000-000000000912', 'authenticated', 'authenticated',
   'qafiz-ordin@e2e.test', '', now(),
   '{"nickname":"QAFiz_Ordin"}'::jsonb, now(), now())
on conflict (id) do nothing;

insert into public.admin_user_roles (user_id, role_id, assigned_by, assigned_at)
select '99770000-0000-0000-0000-000000000911', r.id,
       '99770000-0000-0000-0000-000000000911', now()
  from public.admin_roles r
 where r.role_code = 'super_admin'
on conflict do nothing;


-- ============================================================
-- F-01: curriculum_versions — Fizik surumu + Math default korunumu
-- ============================================================

do $blk$
begin
  perform public._qa_fizik_true('F-01a',
    'tymm_2026_fizik satiri var, aktif, default degil',
    exists (
      select 1 from public.curriculum_versions
      where id = 'a1000000-0000-4000-8000-0000000000c3'
        and framework = 'tymm_2026_fizik'
        and academic_year = '2026-2027'
        and is_active = true
        and is_default = false),
    'cv count=' || (select count(*)::text from public.curriculum_versions
                    where framework = 'tymm_2026_fizik'));

  perform public._qa_fizik_true('F-01b',
    'Math tymm_2026 default korundu (tek default)',
    (select count(*) from public.curriculum_versions
      where academic_year = '2026-2027' and is_default = true and is_active = true) = 1
    and exists (
      select 1 from public.curriculum_versions
      where id = 'a1000000-0000-4000-8000-0000000000c1'
        and is_default = true and is_active = true),
    'default sayisi=' || (select count(*)::text from public.curriculum_versions
                          where academic_year = '2026-2027' and is_default = true));
end $blk$;


-- ============================================================
-- F-02: seed — 22 FIZ.* outcome, dagilim, aktiflik, null topic
-- ============================================================

do $blk$
declare
  v_total integer;
  v_grade9 integer;
  v_grade10 integer;
  v_grade11 integer;
  v_grade12 integer;
begin
  v_total := 0; v_grade9 := 0; v_grade10 := 0; v_grade11 := 0; v_grade12 := 0;

  select count(*),
         count(*) filter (where grade_level = 9),
         count(*) filter (where grade_level = 10),
         count(*) filter (where grade_level = 11),
         count(*) filter (where grade_level = 12)
    into v_total, v_grade9, v_grade10, v_grade11, v_grade12
   from public.curriculum_outcomes
  where curriculum_version_id = 'a1000000-0000-4000-8000-0000000000c3';

  perform public._qa_fizik_true('F-02a',
    'toplam 22 outcome + dagilim 9/10/11/12 = 6/5/8/3',
    v_total = 22 and v_grade9 = 6 and v_grade10 = 5 and v_grade11 = 8 and v_grade12 = 3,
    'toplam=' || v_total
    || ' g9=' || v_grade9 || ' g10=' || v_grade10
    || ' g11=' || v_grade11 || ' g12=' || v_grade12);

  perform public._qa_fizik_true('F-02b',
    'subject=Fizik, hepsi aktif, topic/subtopic NULL, kod kalibi gecerli, metin dolu',
    (select count(*) from public.curriculum_outcomes
      where curriculum_version_id = 'a1000000-0000-4000-8000-0000000000c3'
        and subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3'
        and is_active = true
        and topic_id is null
        and subtopic_id is null
        and outcome_code ~ '^FIZ\.(9|10|11|12)\.[0-9]+\.[0-9]+$'
        and length(btrim(outcome_text)) > 10
        and source_reference like 'TYMM 2026 Fizik%') = 22,
    'uyum=' || (select count(*)::text from public.curriculum_outcomes
       where curriculum_version_id = 'a1000000-0000-4000-8000-0000000000c3'
         and is_active = true and topic_id is null and subtopic_id is null));
end $blk$;


-- ============================================================
-- F-03: 22 kodun tamami 124 cozumleme sorgusuyla tek eslesmeli
-- ============================================================

do $blk$
declare
  v_unresolved integer := 0;
  v_multi integer := 0;
  v_row record;
begin
  for v_row in
    select outcome_code, grade_level, subject_id
      from public.curriculum_outcomes
     where curriculum_version_id = 'a1000000-0000-4000-8000-0000000000c3'
  loop
    if not exists (
      select 1
        from public.curriculum_outcomes o
        join public.curriculum_versions cv on cv.id = o.curriculum_version_id
       where o.outcome_code = v_row.outcome_code
         and o.subject_id = v_row.subject_id
         and o.grade_level = v_row.grade_level
         and o.is_active
       limit 1
    ) then
      v_unresolved := v_unresolved + 1;
    end if;

    if (select count(*)
          from public.curriculum_outcomes o
          join public.curriculum_versions cv on cv.id = o.curriculum_version_id
         where o.outcome_code = v_row.outcome_code
           and o.subject_id = v_row.subject_id
           and o.grade_level = v_row.grade_level
           and o.is_active) <> 1 then
      v_multi := v_multi + 1;
    end if;
  end loop;

  perform public._qa_fizik_true('F-03',
    'her FIZ.* (code,subject,grade) 124 sorgusuyla tek satira cozulur',
    v_unresolved = 0 and v_multi = 0,
    'cozulemeyen=' || v_unresolved || ' coklu=' || v_multi);
end $blk$;


-- ============================================================
-- F-04: seed idempotency (ON CONFLICT DO NOTHING -> 0 yeni satir)
-- ============================================================

do $blk$
declare
  v_cv_before integer;
  v_cv_after integer;
  v_out_before integer;
  v_out_after integer;
begin
  select count(*) into v_cv_before from public.curriculum_versions
   where framework = 'tymm_2026_fizik';
  select count(*) into v_out_before from public.curriculum_outcomes
   where curriculum_version_id = 'a1000000-0000-4000-8000-0000000000c3';

  insert into public.curriculum_versions
    (id, academic_year, framework, source_name, source_url, published_at,
     is_active, is_default, created_at, updated_at)
  values
    ('a1000000-0000-4000-8000-0000000000c3', '2026-2027', 'tymm_2026_fizik',
     'Türkiye Yüzyılı Maarif Modeli Fizik Dersi (9, 10, 11 ve 12. Sınıflar) Öğretim Programı (2026)',
     'https://mufredat.meb.gov.tr/Dosyalar/2026518151437471-fizikd%C3%B6p.pdf',
     '2026-05-18', true, false, now(), now())
  on conflict (id) do nothing;

  insert into public.curriculum_outcomes
    (id, curriculum_version_id, grade_level, subject_id, topic_id, subtopic_id,
     outcome_code, outcome_text, sort_order, source_reference, is_active, created_at, updated_at)
  values
    ('a9090000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c3', 9,
     '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL,
     'FIZ.9.1.1', 'Fizik biliminin tanımına yönelik tümevarımsal akıl yürütebilme', 1,
     'TYMM 2026 Fizik Öğretim Programı, s.15', true, now(), now())
  on conflict (id) do nothing;

  select count(*) into v_cv_after from public.curriculum_versions
   where framework = 'tymm_2026_fizik';
  select count(*) into v_out_after from public.curriculum_outcomes
   where curriculum_version_id = 'a1000000-0000-4000-8000-0000000000c3';

  perform public._qa_fizik_true('F-04',
    'seed yeniden uygulamasi 0 yeni satir ekler (idempotent)',
    v_cv_before = v_cv_after and v_out_before = v_out_after
      and v_cv_before = 1 and v_out_before = 22,
    'cv ' || v_cv_before || '->' || v_cv_after
    || ' out ' || v_out_before || '->' || v_out_after);
end $blk$;


-- ============================================================
-- F-05: yetkili Fizik intake happy-path (9/10/11/12)
-- ============================================================

do $blk$
declare
  v_q9  jsonb := public._qa_fizik_candidate(
    'fiz-g9-1', 'QA Fizik G9 birinci soru metni: fizik bilimi tumevarim.', 'Fizik', 9, 'FIZ.9.1.1');
  v_q10 jsonb := public._qa_fizik_candidate(
    'fiz-g10-1', 'QA Fizik G10 soru metni: paralel esdeger direnc hesabi.', 'Fizik', 10, 'FIZ.10.3.4');
  v_q11 jsonb := public._qa_fizik_candidate(
    'fiz-g11-1', 'QA Fizik G11 soru metni: duzgun cembersel hareket degiskenleri.', 'Fizik', 11, 'FIZ.11.1.10');
  v_q12 jsonb := public._qa_fizik_candidate(
    'fiz-g12-1', 'QA Fizik G12 soru metni: acisal momentumun korunumu kosulu.', 'Fizik', 12, 'FIZ.12.1.6');
  v_pkg jsonb := public._qa_fizik_package(jsonb_build_array(v_q9, v_q10, v_q11, v_q12));
  v_res jsonb;
  v_bid uuid;
begin
  perform public._qa_fizik_reg('F-05', v_pkg, 'service_role', null);
  select result into v_res from public._qa_fizik_submits where key = 'F-05';
  v_bid := (v_res ->> 'batch_id')::uuid;

  perform public._qa_fizik_true('F-05a',
    'status=ingested, 4 inserted, 0 invalid/dup',
    (v_res->>'status') = 'ingested'
    and (v_res->>'inserted_items')::int = 4
    and (v_res->>'invalid_items')::int = 0
    and (v_res->>'duplicate_items')::int = 0
    and jsonb_array_length(v_res -> 'staging_ids') = 4,
    'status=' || coalesce(v_res->>'status', '<null>')
    || ' ok=' || coalesce(v_res->>'inserted_items', '<null>'));

  perform public._qa_fizik_true('F-05b',
    '4 staging satiri (Fizik, ...c3 versiyon, spec bagli)',
    (select count(*) = 4
       from public.ai_question_staging s
      where s.staging_source = 'external_producer'
        and s.subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3'
        and s.proposed_curriculum_version_id = 'a1000000-0000-4000-8000-0000000000c3'
        and s.generation_spec_id is not null
        and s.staging_status = 'validating'),
    'staging=' || (select count(*)::text from public.ai_question_staging
                   where subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3'));

  perform public._qa_fizik_true('F-05c',
    'outcome kodu -> seed outcome id atomik baglandi (required_outcome_id)',
    (select count(distinct (s.metadata ->> 'required_outcome_id'))
       from public.ai_question_staging s
      where s.subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3') = 4
    and not exists (
      select 1 from public.ai_question_staging s
      where s.subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3'
        and (s.metadata ->> 'required_outcome_id')::uuid not in (
          select id from public.curriculum_outcomes
           where curriculum_version_id = 'a1000000-0000-4000-8000-0000000000c3')),
    'distinct outcome=' || (select count(distinct (s.metadata ->> 'required_outcome_id'))::text
                             from public.ai_question_staging s
                            where s.subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3'));

  perform public._qa_fizik_true('F-05d',
    'ai_generation_specs: 4 adet ready, desired_count=1, outcome_id bagli',
    (select count(*) = 4
       from public.ai_generation_specs g
       join public.ai_question_staging s on s.generation_spec_id = g.id
      where s.subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3'
        and g.status = 'ready'
        and g.desired_count = 1
        and g.outcome_id is not null
        and g.curriculum_version_id = 'a1000000-0000-4000-8000-0000000000c3'),
    'spec=' || (select count(*)::text from public.ai_generation_specs g
                join public.ai_question_staging s on s.generation_spec_id = g.id
               where s.subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3'));

  perform public._qa_fizik_true('F-05e',
    '8 deterministic validation (2/aday) + 4 inserted audit',
    (select count(*) = 8
       from public.ai_validation_results v
       join public.ai_question_staging s on s.id = v.staging_question_id
      where s.subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3'
        and v.validator_type = 'deterministic'
        and v.result = 'pass')
    and (select count(*) = 4
          from public.candidate_batch_candidate_results r
         where r.batch_id = v_bid and r.validation_status = 'inserted'),
    'validation=' || (select count(*)::text from public.ai_validation_results v
                       join public.ai_question_staging s on s.id = v.staging_question_id
                      where s.subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3'));

  perform public._qa_fizik_true('F-05f',
    'batch ingested + preflight ozeti (adapter v1.1, skandal yok)',
    (select b.status = 'ingested'
        and (b.validation_summary -> 'preflight' ->> 'adapter') = 'v1.1_markdown'
        and (b.validation_summary -> 'preflight' ->> 'publication_allowed')::boolean = false
        and (b.validation_summary -> 'preflight' ->> 'is_active')::boolean = false
        and (b.validation_summary -> 'preflight' ->> 'review_required')::boolean = true
       from public.candidate_question_batches b where b.id = v_bid),
    'batch=' || coalesce(v_res->>'status', '<null>'));
end $blk$;


-- ============================================================
-- F-06: fail-closed — seed'de olmayan FIZ.9.1.3
-- ============================================================

do $blk$
begin
  perform public._qa_fizik_reg('F-06',
    public._qa_fizik_package(jsonb_build_array(
      public._qa_fizik_candidate('fiz-g9-3', 'QA Fizik seedde olmayan kod soru metni burada.',
        'Fizik', 9, 'FIZ.9.1.3'))),
    'service_role', null);

  perform public._qa_fizik_true('F-06',
    'FIZ.9.1.3 (seed disi) -> rejected + outcome_not_found + staging YOK',
    public._qa_fizik_res('F-06') = 'rejected'
    and public._qa_fizik_has_err('F-06', 'outcome_not_found')
    and not exists (select 1 from public.ai_question_staging
                    where metadata ->> 'client_question_id' = 'fiz-g9-3'),
    'durum=' || public._qa_fizik_res('F-06'));
end $blk$;


-- ============================================================
-- F-07: fail-closed — sinif uyusmazligi FIZ.9.1.1 @ 10
-- ============================================================

do $blk$
begin
  perform public._qa_fizik_reg('F-07',
    public._qa_fizik_package(jsonb_build_array(
      public._qa_fizik_candidate('fiz-g10-11', 'QA Fizik sinif uyusmazligi soru metni burada.',
        'Fizik', 10, 'FIZ.9.1.1'))),
    'service_role', null);

  perform public._qa_fizik_true('F-07',
    'FIZ.9.1.1 @ grade 10 -> outcome_not_found + staging YOK',
    public._qa_fizik_res('F-07') = 'rejected'
    and public._qa_fizik_has_err('F-07', 'outcome_not_found')
    and not exists (select 1 from public.ai_question_staging
                    where metadata ->> 'client_question_id' = 'fiz-g10-11'),
    'durum=' || public._qa_fizik_res('F-07'));
end $blk$;


-- ============================================================
-- F-08: ACL kapisi (service_role / admin / izinsiz)
-- ============================================================

do $blk$
declare
  v_admin jsonb := jsonb_build_object(
    'sub', '99770000-0000-0000-0000-000000000911',
    'role', 'authenticated');
  v_ordin jsonb := jsonb_build_object(
    'sub', '99770000-0000-0000-0000-000000000912',
    'role', 'authenticated');
  v_pkg jsonb := public._qa_fizik_package(jsonb_build_array(
    public._qa_fizik_candidate('fiz-acl1', 'QA Fizik ACL kapsaminda gecerli soru metni burada.',
      'Fizik', 9, 'FIZ.9.1.2')));
begin
  perform public._qa_fizik_reg('F-08a', v_pkg, 'service_role', null);
  perform public._qa_fizik_true('F-08a', 'service_role -> kabul',
    public._qa_fizik_res('F-08a') = 'ingested',
    'durum=' || public._qa_fizik_res('F-08a'));

  perform public._qa_fizik_reg('F-08b', v_pkg, 'authenticated', v_admin);
  perform public._qa_fizik_true('F-08b', 'admin (ai.manage/questions.approve) -> kabul',
    public._qa_fizik_res('F-08b') = 'already_received'
    or public._qa_fizik_res('F-08b') = 'ingested',
    'durum=' || public._qa_fizik_res('F-08b'));

  perform public._qa_fizik_reg('F-08c', v_pkg, 'authenticated', v_ordin);
  perform public._qa_fizik_expect('F-08c', 'izinsiz kullanici -> P0001 kapisi',
    'F-08c', 'P0001', 'requires AI or admin permission');
end $blk$;


-- ============================================================
-- F-09: DTO ic yapi sizdirma + otomatik yayin yasagi
-- ============================================================

do $blk$
declare
  v_res jsonb;
begin
  select result into v_res from public._qa_fizik_submits where key = 'F-05';

  perform public._qa_fizik_true('F-09',
    'yanit anahtarlari ic yapi sizdirmaz, automatic_publication_allowed=false',
    not (v_res ? 'spec_id')
    and not (v_res ? 'generation_spec_id')
    and not (v_res ? 'required_outcome_id')
    and (v_res ->> 'automatic_publication_allowed')::boolean = false,
    'keys=' || (select string_agg(k, ',') from jsonb_object_keys(v_res) k));
end $blk$;


-- ============================================================
-- F-10: regression — MAT.9.1.1 125 sonrasi da cozulur
-- ============================================================

do $blk$
declare
  v_c jsonb := jsonb_build_object(
    'client_question_id', 'fiz-reg-mat1',
    'question_text', 'QA Fizik turu regression icin matematik soru metni buradadir.',
    'subject_id', '430903f3-527e-4e12-b7e8-ac0afdb784aa',
    'grade_level', 9,
    'outcome_code', 'MAT.9.1.1',
    'difficulty', 'easy',
    'cognitive_type', 'learning',
    'estimated_solve_time_seconds', 60,
    'correct_answer', 'A',
    'options', jsonb_build_object(
      'A', 'QA reg sec A', 'B', 'QA reg sec B', 'C', 'QA reg sec C',
      'D', 'QA reg sec D', 'E', 'QA reg sec E'),
    'solution', jsonb_build_object(
      'method', 'Bilindik cozum yontemi uygulanir.',
      'steps', jsonb_build_array('Adim bir: verilenler duzenlenir.', 'Adim iki: sonuc bulunur.'),
      'result', 'Sonuc A secenegidir.',
      'correctAnswerJustification', 'A secenegi dogrudur.',
      'commonMistakes', jsonb_build_array('Yaygin hata birakinilir.')));
  v_pkg jsonb := jsonb_build_object(
    'schema_version', '1.1',
    'origin', 'curriculum_original',
    'producer', jsonb_build_object('id', 'qa-fiz-reg', 'model', 'qa-reg-parser'),
    'publication_allowed', false,
    'is_active', false,
    'validation_requested_status', 'needs_review',
    'metadata', jsonb_build_object('out_of_package_count', 0,
                                   'out_of_package_kinds', jsonb_build_array()),
    'questions', jsonb_build_array(v_c));
begin
  perform public._qa_fizik_reg('F-10', v_pkg, 'service_role', null);
  perform public._qa_fizik_true('F-10',
    'MAT.9.1.1 intake 125 sonrasi da ingested (Math zarar gormedi)',
    public._qa_fizik_res('F-10') = 'ingested',
    'durum=' || public._qa_fizik_res('F-10'));
end $blk$;


-- ============================================================
-- OZET + ROLLBACK (kalici kayit yok)
-- ============================================================

select label || ' | ' || title || ' | ' || result || ' | ' || coalesce(detail, '')
  from public._qa_fizik_results
 order by label;

select 'TOPLAM|' || count(*) || '|' || count(*) filter (where result = 'PASS')
       || '|' || count(*) filter (where result = 'FAIL')
  from public._qa_fizik_results;

rollback;