-- ============================================================
-- scripts/qa_candidate_md_intake_123_local.sql
-- Altin Kalemler - Migration 123-124 yerel QA suite
-- (Markdown v1.1 aday soru paketi intake'i + Faz 22 kurikulum/outcome +
--  generation spec baglantisi — migration 124)
--
-- 124 kapsami: her gecerli candidate-md staging yaziminda outcome_code ->
-- curriculum_outcomes (fail-closed 'outcome_not_found') -> ai_generation_specs
-- (desired_count=1, status='ready') -> staging baglantisi. Seed (111/112)
-- yalniz 9-12. sinif kazanim yukledigi icin QA, MAT.5.1 (aktif) + MAT.5.2
-- (pasif) kazanimlarini kendi transaction'inda sabitler.
--
-- Calistirma (disposable DB, migration 001-124 uygulanmis):
--   docker cp scripts/qa_candidate_md_intake_123_local.sql <db>:/tmp/
--   docker exec <db> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -A -t -f /tmp/qa_candidate_md_intake_123_local.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti/kayit kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC + GONDERIM TABLOLARI
-- ============================================================

create table public._qa_q123_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_q123_results
  to anon, authenticated, service_role;

create table public._qa_q123_submits (
  key      text primary key,
  result   jsonb,
  is_err   boolean not null default false,
  sqlstate text,
  err_msg  text,
  created_at timestamptz not null default now()
);

grant select, insert, update, delete
  on public._qa_q123_submits
  to anon, authenticated, service_role;


-- ============================================================
-- YARDIMCILAR
-- ============================================================

-- Koşulsuz dogruluk asserti.
create function public._qa_q123_true(
  p_label text, p_title text, p_ok boolean, p_detail text
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_q123_results
  values (p_label, p_title, case when p_ok then 'PASS' else 'FAIL' end,
          coalesce(p_detail, ''));
end;
$qa$;

grant execute
  on function public._qa_q123_true(text, text, boolean, text)
  to anon, authenticated, service_role;

-- register cagrisi: role + jwt claims kurulumu ile calistirir,
-- sonucu/hata durumunu _qa_q123_submits'e yazar.
create function public._qa_q123_reg(
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

  insert into public._qa_q123_submits
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
  on function public._qa_q123_reg(text, jsonb, text, jsonb)
  to anon, authenticated, service_role;

-- Beklenen hata asserti (sqlstate + mesaj icerigi).
create function public._qa_q123_expect(
  p_label text, p_title text, p_key text, p_state text, p_msg_like text default ''
)
returns void
language plpgsql
security invoker
as $qa$
declare
  v_row public._qa_q123_submits%rowtype;
begin
  select * into v_row from public._qa_q123_submits where key = p_key;

  if v_row.key is null then
    insert into public._qa_q123_results
    values (p_label, p_title, 'FAIL', 'key bulunamadi: ' || p_key);
    return;
  end if;

  insert into public._qa_q123_results
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
  on function public._qa_q123_expect(text, text, text, text, text)
  to anon, authenticated, service_role;

-- ============================================================
-- PAYLOAD KURUCULAR
-- ============================================================

create function public._qa_q123_candidate(
  p_client text, p_text text, p_extra jsonb default '{}'::jsonb
)
returns jsonb
language sql
immutable
security invoker
as $qa$
  select jsonb_build_object(
      'client_question_id', p_client,
      'question_text', p_text,
      'subject_ref', 'Matematik',
      'grade_level', 5,
      'outcome_code', 'MAT.5.1',
      'difficulty', 'easy',
      'cognitive_type', 'learning',
      'estimated_solve_time_seconds', 60,
      'correct_answer', 'A',
      'options', jsonb_build_object(
        'A', 'QA md secenek A', 'B', 'QA md secenek B',
        'C', 'QA md secenek C', 'D', 'QA md secenek D',
        'E', 'QA md secenek E'),
      'solution', jsonb_build_object(
        'method', 'Esitlikten yararlanilir.',
        'steps', jsonb_build_array(
          'Adim 1: verilenler yazilir.',
          'Adim 2: islem yapilir.'),
        'result', 'Dogrulayici sonuc A secenegidir.',
        'correctAnswerJustification', 'A secenegindeki deger dogrudur.',
        'commonMistakes', jsonb_build_array('Yaygin hata isaret karisikligidir.'))
    ) || p_extra
$qa$;

create function public._qa_q123_package(
  p_questions jsonb, p_extra jsonb default '{}'::jsonb
)
returns jsonb
language sql
immutable
security invoker
as $qa$
  select jsonb_build_object(
      'schema_version', '1.1',
      'origin', 'curriculum_original',
      'producer', jsonb_build_object('id', 'qa-md-producer-1', 'model', 'qa-md-parser-v1'),
      'publication_allowed', false,
      'is_active', false,
      'validation_requested_status', 'needs_review',
      'metadata', jsonb_build_object(
        'out_of_package_count', 2,
        'out_of_package_kinds', jsonb_build_array('topic_not_supported', 'grade_out_of_scope'))
    ) || p_extra || jsonb_build_object('questions', p_questions)
$qa$;

grant execute
  on function public._qa_q123_candidate(text, text, jsonb)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_q123_package(jsonb, jsonb)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR (sabit QA uuid'leri; rollback ile silinecek)
--   ADMIN : super_admin (ai.manage + questions.approve)
--   ORDIN : izinsiz kullanici
--   matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
-- ============================================================

insert into auth.users
  (id, aud, role, email, encrypted_password, confirmed_at,
   raw_user_meta_data, created_at, updated_at)
values
  ('99770000-0000-0000-0000-000000000901', 'authenticated', 'authenticated',
   'qa123-admin@e2e.test', '', now(),
   '{"nickname":"QA123_Admin"}'::jsonb, now(), now()),
  ('99770000-0000-0000-0000-000000000902', 'authenticated', 'authenticated',
   'qa123-ordin@e2e.test', '', now(),
   '{"nickname":"QA123_Ordin"}'::jsonb, now(), now())
on conflict (id) do nothing;

insert into public.admin_user_roles (user_id, role_id, assigned_by, assigned_at)
select '99770000-0000-0000-0000-000000000901', r.id,
       '99770000-0000-0000-0000-000000000901', now()
  from public.admin_roles r
 where r.role_code = 'super_admin'
on conflict do nothing;


-- ============================================================
-- FIXTURE: QA kazanimlari (Faz 22)
--   MAT.5.1 : aktif (happy-path intake'lerin cozum hedefi)
--   MAT.5.2 : pasif (fail-closed testi — cozulmemeli)
--   Matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
--   TYMM 2026  : a1000000-0000-4000-8000-0000000000c1 (111 seed)
-- ============================================================

insert into public.curriculum_outcomes (
  id, curriculum_version_id, grade_level, subject_id, topic_id, subtopic_id,
  outcome_code, outcome_text, sort_order, source_reference, is_active, created_at, updated_at
)
values
  ('99770000-0000-0000-0000-000000000b01',
   'a1000000-0000-4000-8000-0000000000c1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', NULL, NULL,
   'MAT.5.1', 'QA124 kazanimi: dogal sayilarla dort islem.', 1,
   'QA fixture', true, now(), now()),
  ('99770000-0000-0000-0000-000000000b02',
   'a1000000-0000-4000-8000-0000000000c1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', NULL, NULL,
   'MAT.5.2', 'QA124 pasif kazanimi.', 2,
   'QA fixture', false, now(), now())
on conflict (id) do nothing;


-- ============================================================
-- T-01: Gecerli v1.1 paket -> 117-118 hatti, staging'e yazilir
-- ============================================================

do $blk$
declare
  v_key text;
  v_bid uuid;
  v_res jsonb;
  v_c1 jsonb := public._qa_q123_candidate(
    't01-c1', 'QA123 gecerli birinci soru metnidir buradadir.');
  v_c2 jsonb := public._qa_q123_candidate(
    't01-c2', 'QA123 gecerli ikinci soru metnidir buradadir.');
  v_pkg jsonb := public._qa_q123_package(jsonb_build_array(v_c1, v_c2));
begin
  perform public._qa_q123_reg('T-01', v_pkg, 'service_role', null);

  select result into v_res from public._qa_q123_submits where key = 'T-01';

  perform public._qa_q123_true('T-01a', 'status=ingested, 2 inserted, dup yok',
    (v_res->>'status') = 'ingested'
    and (v_res->>'inserted_items')::int = 2
    and (v_res->>'invalid_items')::int = 0
    and (v_res->>'duplicate_items')::int = 0
    and jsonb_array_length(v_res -> 'staging_ids') = 2,
    'status=' || coalesce(v_res->>'status', '<null>')
    || ' ok=' || coalesce(v_res->>'ok', '<null>'));

  v_bid := (v_res ->> 'batch_id')::uuid;

  perform public._qa_q123_true('T-01b', 'batch satiri ingested/v1.0/curriculum_original',
    exists (
      select 1 from public.candidate_question_batches b
      where b.id = v_bid
        and b.status = 'ingested'
        and b.schema_version = '1.0'
        and b.origin = 'curriculum_original'
        and b.total_items = 2
        and b.inserted_items = 2),
    'batch bulundu mu=' || exists(select 1 from public.candidate_question_batches b where b.id = v_bid));

  perform public._qa_q123_true('T-01c', '2 staging satiri external_producer + guvenli alanlar',
    (select count(*) = 2
       from public.ai_question_staging s
      where s.staging_source = 'external_producer'
        and s.staging_status = 'validating'
        and s.ownership_status = 'ai_original'
        and s.license_status = 'pending'
        and s.commercial_use_allowed = false
        and s.copyright_risk_level = 'unknown'
        and s.grade_level = 5
        and s.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa'
        and (s.metadata -> 'candidate_md_v11' ->> 'publication_allowed')::boolean = false
        and (s.metadata -> 'candidate_md_v11' ->> 'is_active')::boolean = false
        and (s.metadata -> 'candidate_md_v11' ->> 'review_required')::boolean = true
        and s.metadata ->> 'final_readiness_status' = 'pending'
        and (s.metadata ->> 'deterministic_ingestion_passed')::boolean = true
        and (s.metadata ->> 'automatic_publication_allowed')::boolean = false
        and s.metadata -> 'solution' is not null
        and s.metadata ->> 'outcome_code' = 'MAT.5.1'),
    'staging: ' || (select count(*)::text from public.ai_question_staging));

  perform public._qa_q123_true('T-01d', 'subject kanonik cozumu (Matematik uuid)',
    exists (
      select 1 from public.ai_question_staging s
      where s.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa'),
    'subject=' || (select string_agg(distinct subject_id::text, ',')
                     from public.ai_question_staging where subject_id is not null)::text);

  perform public._qa_q123_true('T-01e', 'her staging 2 adet deterministic validation (structure+answer)',
    (select count(*) = 4
       from public.ai_validation_results v
       join public.ai_question_staging s on s.id = v.staging_question_id
      where s.staging_source = 'external_producer'
        and v.validator_type = 'deterministic'
        and v.result = 'pass'
        and v.validation_type in ('structure', 'answer')),
    'validation_result adedi=' ||
    (select count(*)::text from public.ai_validation_results v
      where v.validation_type in ('structure','answer')));

  perform public._qa_q123_true('T-01f', 'per-candidate audit satirlari (inserted)',
    (select count(*) = 2
       from public.candidate_batch_candidate_results r
      where r.batch_id = v_bid and r.validation_status = 'inserted'),
    'audit adedi=' ||
    (select count(*)::text from public.candidate_batch_candidate_results r
      where r.batch_id = v_bid));

  perform public._qa_q123_true('T-01g', 'preflight ozeti + oop sayaci',
    (select (b.validation_summary -> 'preflight' ->> 'adapter') = 'v1.1_markdown'
        and (b.validation_summary -> 'preflight' ->> 'schema_version') = '1.1'
        and (b.validation_summary -> 'preflight' ->> 'root_valid')::boolean = true
        and (b.validation_summary -> 'preflight' ->> 'out_of_package_count')::int = 2
        and jsonb_array_length(b.validation_summary -> 'preflight' -> 'out_of_package_kinds') = 2
        and (b.validation_summary -> 'preflight' ->> 'publication_allowed')::boolean = false
        and (b.validation_summary -> 'preflight' ->> 'is_active')::boolean = false
       from public.candidate_question_batches b where b.id = v_bid),
    (select (b.validation_summary -> 'preflight' ->> 'out_of_package_count')::text
       from public.candidate_question_batches b where b.id = v_bid));
end $blk$;


-- ============================================================
-- T-02: Kok dogrulama (P0001 + dogru mesaj)
-- ============================================================

do $blk$
declare
  v_valid jsonb := public._qa_q123_candidate(
    't02-c1', 'QA123 kok dogrulama gecerli soru metni buradadir.');
begin
  perform public._qa_q123_reg('T-02a', null::jsonb, 'service_role', null);
  perform public._qa_q123_expect('T-02a', 'null payload red',
    'T-02a', 'P0001', 'Payload must be a JSON object.');

  perform public._qa_q123_reg('T-02b',
    '[]'::jsonb, 'service_role', null);
  perform public._qa_q123_expect('T-02b', 'array payload red',
    'T-02b', 'P0001', 'Payload must be a JSON object.');

  perform public._qa_q123_reg('T-02c',
    public._qa_q123_package(jsonb_build_array(v_valid), jsonb_build_object('schema_version', '1.0')),
    'service_role', null);
  perform public._qa_q123_expect('T-02c', 'schema_version 1.0 red',
    'T-02c', 'P0001', 'Unsupported schema version');

  perform public._qa_q123_reg('T-02d',
    public._qa_q123_package(jsonb_build_array(v_valid), jsonb_build_object('origin', 'ai_generated')),
    'service_role', null);
  perform public._qa_q123_expect('T-02d', 'origin ai_generated red',
    'T-02d', 'P0001', 'Origin must be curriculum_original.');

  perform public._qa_q123_reg('T-02e',
    public._qa_q123_package(jsonb_build_array(v_valid), jsonb_build_object('producer', '{}'::jsonb)),
    'service_role', null);
  perform public._qa_q123_expect('T-02e', 'producer bos red',
    'T-02e', 'P0001', 'Producer id is required.');

  perform public._qa_q123_reg('T-02f',
    public._qa_q123_package(jsonb_build_array(v_valid), jsonb_build_object('publication_allowed', true)),
    'service_role', null);
  perform public._qa_q123_expect('T-02f', 'publication_allowed=true red',
    'T-02f', 'P0001', 'MD candidate packages can never be publishable.');

  perform public._qa_q123_reg('T-02g',
    public._qa_q123_package(jsonb_build_array(v_valid), jsonb_build_object('is_active', true)),
    'service_role', null);
  perform public._qa_q123_expect('T-02g', 'is_active=true red',
    'T-02g', 'P0001', 'MD candidate packages can never be publishable.');

  perform public._qa_q123_reg('T-02h',
    public._qa_q123_package(jsonb_build_array(v_valid), jsonb_build_object('validation_requested_status', 'approved')),
    'service_role', null);
  perform public._qa_q123_expect('T-02h', 'paket durumu approved red',
    'T-02h', 'P0001', 'status cannot be publishable/approved.');

  perform public._qa_q123_reg('T-02i',
    public._qa_q123_package('[]'::jsonb),
    'service_role', null);
  perform public._qa_q123_expect('T-02i', 'bos questions red',
    'T-02i', 'P0001', 'Questions array must be non-empty.');
end $blk$;


-- ============================================================
-- T-03: Idempotency (aynı batch_key -> already_received)
-- ============================================================

do $blk$
declare
  v_c1 jsonb := public._qa_q123_candidate(
    't03-c1', 'QA123 idempotency ayni soru metni bundan once de girildi.');
  v_pkg jsonb := public._qa_q123_package(jsonb_build_array(v_c1));
  v_first jsonb;
begin
  perform public._qa_q123_reg('T-03a', v_pkg, 'service_role', null);
  perform public._qa_q123_reg('T-03b', v_pkg, 'service_role', null);

  select result into v_first from public._qa_q123_submits where key = 'T-03a';

  perform public._qa_q123_true('T-03a', 'ilk gonderim ingested',
    (v_first->>'status') = 'ingested' and (v_first->>'inserted_items')::int = 1,
    'status=' || coalesce(v_first->>'status', '<null>'));

  perform public._qa_q123_true('T-03b', 'tekrar already_received + ayni staging',
    (select (result->>'status') = 'already_received'
        and (result->>'staging_ids')::jsonb
            = (select coalesce(jsonb_agg(r.staging_question_id), '[]'::jsonb)
                 from public.candidate_batch_candidate_results r
                where r.batch_id = (v_first->>'batch_id')::uuid
                  and r.validation_status = 'inserted')
       from public._qa_q123_submits where key = 'T-03b'),
    (select result->>'status' from public._qa_q123_submits where key = 'T-03b'));

  perform public._qa_q123_true('T-03c', 'yeni batch/staging satiri yok',
    (select count(*) = 1 from public.candidate_question_batches
      where batch_key = coalesce((select result->>'batch_key' from public._qa_q123_submits where key = 'T-03a'), ''))
    and (select count(*) = 1
          from public.ai_question_staging s
         where s.metadata ->> 'client_question_id' = 't03-c1'),
    'staging sayisi=' || (select count(*)::text from public.ai_question_staging s
                           where s.metadata ->> 'client_question_id' = 't03-c1'));
end $blk$;


-- ============================================================
-- Aday hata-kodu yardimcisi
-- ============================================================

create function public._qa_q123_has_err(p_key text, p_code text)
returns boolean
language sql
security invoker
as $qa$
  select exists (
    select 1
      from public._qa_q123_submits s
      join public.candidate_question_batches b
        on b.batch_key = s.result ->> 'batch_key'
      join public.candidate_batch_candidate_results r
        on r.batch_id = b.id
     where s.key = p_key
       and (r.validation_errors ? p_code)
and r.validation_status in ('invalid', 'duplicate')
  );
$qa$;

create function public._qa_q123_res(p_key text)
returns text
language sql
security invoker
as $qa$
  select result ->> 'status' from public._qa_q123_submits where key = p_key
$qa$;

grant execute
  on function public._qa_q123_has_err(text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_q123_res(text)
  to anon, authenticated, service_role;


-- ============================================================
-- T-04: Secenekler (A-E zorunlu + benzersiz)
-- ============================================================

do $blk$
declare
  v_ok jsonb := public._qa_q123_candidate('t04-c1', 'QA123 secenek testi gecerli soru metni.');
  v_opt_bad jsonb := jsonb_build_object(
    'A', 'QA sec A', 'B', 'QA sec B', 'C', 'QA sec C', 'D', 'QA sec D',
    'E', '');
  v_opt_dup jsonb := jsonb_build_object(
    'A', 'QA ayni secenek', 'B', 'QA ayni secenek',
    'C', 'QA sec C', 'D', 'QA sec D', 'E', 'QA sec E');
begin
  perform public._qa_q123_reg('T-04a',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t04-ca', 'QA123 options json olmayan kandir.', jsonb_build_object('options', jsonb_build_array(1))))),
    'service_role', null);
  perform public._qa_q123_true('T-04a', 'options obje degil -> invalid + rejected',
    public._qa_q123_res('T-04a') = 'rejected'
    and public._qa_q123_has_err('T-04a', 'options_bir_json_object_olmali'),
    'durum=' || public._qa_q123_res('T-04a'));

  perform public._qa_q123_reg('T-04b',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t04-cb', 'QA123 E secenegi eksik soru metni.', jsonb_build_object('options', v_opt_bad)))),
    'service_role', null);
  perform public._qa_q123_true('T-04b', 'E secenegi bos -> option_E_eksik',
    public._qa_q123_has_err('T-04b', 'option_E_eksik'),
    'durum=' || public._qa_q123_res('T-04b'));

  perform public._qa_q123_reg('T-04c',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t04-cc', 'QA123 tekrar eden secenek soru metni.', jsonb_build_object('options', v_opt_dup)))),
    'service_role', null);
  perform public._qa_q123_true('T-04c', 'tekrar eden secenek -> ayni_secenek...',
    public._qa_q123_has_err('T-04c', 'ayni_secenek_metni_tekrar_eden_bulundu'),
    'durum=' || public._qa_q123_res('T-04c'));
end $blk$;


-- ============================================================
-- T-05: correct_answer (harf araligi + bos secenek)
-- ============================================================

do $blk$
declare
  v_opt4 jsonb := jsonb_build_object(
    'A', 'QA sec A', 'B', 'QA sec B', 'C', 'QA sec C', 'D', 'QA sec D',
    'E', 'QA sec E');
begin
  perform public._qa_q123_reg('T-05a',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t05-ca', 'QA123 gecersiz harf dogru cevap soru metni.',
        jsonb_build_object('correct_answer', 'F', 'options', v_opt4)))),
    'service_role', null);
  perform public._qa_q123_true('T-05a', 'correct_answer F -> harf araligi hatasi',
    public._qa_q123_has_err('T-05a', 'correct_answer_A_E_arasi_olmali'),
    'durum=' || public._qa_q123_res('T-05a'));

  perform public._qa_q123_reg('T-05b',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t05-cb', 'QA123 bos secenek dogru cevap soru metni.',
        jsonb_build_object('correct_answer', 'C',
          'options', jsonb_build_object(
            'A', 'QA sec A', 'B', 'QA sec B', 'C', '', 'D', 'QA sec D', 'E', 'QA sec E'))))),
    'service_role', null);
  perform public._qa_q123_true('T-05b', 'correct_answer bos secenegi gosteriyor -> hatasi',
    public._qa_q123_has_err('T-05b', 'correct_answer_bos_secenek'),
    'durum=' || public._qa_q123_res('T-05b'));
end $blk$;


-- ============================================================
-- T-06: outcome_code, additional, grade, difficulty, solve_time
-- ============================================================

do $blk$
begin
  perform public._qa_q123_reg('T-06a',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t06-ca', 'QA123 outcome eksik olan soru metni burada.',
        jsonb_build_object('outcome_code', ' ')))),
    'service_role', null);
  perform public._qa_q123_true('T-06a', 'bos outcome_code -> outcome_code_bos_olamaz',
    public._qa_q123_has_err('T-06a', 'outcome_code_bos_olamaz'),
    'durum=' || public._qa_q123_res('T-06a'));

  perform public._qa_q123_reg('T-06b',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t06-cb', 'QA123 gecersiz kazanim kalibi soru metni.',
        jsonb_build_object('outcome_code', 'MAT..!!')))),
    'service_role', null);
  perform public._qa_q123_true('T-06b', 'gecersiz kazanim formati -> outcome_code_formati_gecersiz',
    public._qa_q123_has_err('T-06b', 'outcome_code_formati_gecersiz'),
    'durum=' || public._qa_q123_res('T-06b'));

  perform public._qa_q123_reg('T-06c',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t06-cc', 'QA123 cok kazanimli soru metni buradadir.',
        jsonb_build_object('additional_outcome_codes', jsonb_build_array('MAT.5.2'))))),
    'service_role', null);
  perform public._qa_q123_true('T-06c', 'ek kazanim kodu -> birden_fazla_kazanim_kodu',
    public._qa_q123_has_err('T-06c', 'birden_fazla_kazanim_kodu'),
    'durum=' || public._qa_q123_res('T-06c'));

  perform public._qa_q123_reg('T-06d',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t06-cd', 'QA123 sinif disi not soru metni buradadir.',
        jsonb_build_object('grade_level', 13)))),
    'service_role', null);
  perform public._qa_q123_true('T-06d', 'grade 13 -> grade_level_1_12_olmali',
    public._qa_q123_has_err('T-06d', 'grade_level_1_12_olmali'),
    'durum=' || public._qa_q123_res('T-06d'));

  perform public._qa_q123_reg('T-06e',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t06-ce', 'QA123 gecersiz zorluk etiketi olan soru metni.',
        jsonb_build_object('difficulty', 'impossible')))),
    'service_role', null);
  perform public._qa_q123_true('T-06e', 'gecersiz zorluk -> difficulty_easy_medium_hard_olmali',
    public._qa_q123_has_err('T-06e', 'difficulty_easy_medium_hard_olmali'),
    'durum=' || public._qa_q123_res('T-06e'));

  perform public._qa_q123_reg('T-06f',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t06-cf', 'QA123 negatif sureli gecerli soru metnidir.',
        jsonb_build_object('estimated_solve_time_seconds', -5)))),
    'service_role', null);
  perform public._qa_q123_true('T-06f', 'negatif sure -> estimated_solve_time... hatasi',
    public._qa_q123_has_err('T-06f', 'estimated_solve_time_seconds_pozitif_tamsayi_olmali'),
    'durum=' || public._qa_q123_res('T-06f'));
end $blk$;


-- ============================================================
-- T-07: Aday durumu (yalnizca needs_review/pending)
-- ============================================================

do $blk$
begin
  perform public._qa_q123_reg('T-07a',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t07-ca', 'QA123 approved durumlu aday soru metni burada.',
        jsonb_build_object('validation_requested_status', 'approved')))),
    'service_role', null);
  perform public._qa_q123_true('T-07a', 'aday approved -> candidate_durum_not_importable',
    public._qa_q123_has_err('T-07a', 'candidate_durum_not_importable')
    and public._qa_q123_res('T-07a') = 'rejected',
    'durum=' || public._qa_q123_res('T-07a'));
end $blk$;


-- ============================================================
-- T-08: Cozum (v1.1 zorunlu alanlar)
-- ============================================================

do $blk$
declare
  v_sol_short jsonb := jsonb_build_object(
    'method', 'Yontem var.',
    'steps', jsonb_build_array('Tek adim'),
    'result', 'Sonuc var.',
    'correctAnswerJustification', 'Gerekce var.',
    'commonMistakes', jsonb_build_array('Yaygin hata var.'));
  v_sol_no_cm jsonb := jsonb_build_object(
    'method', 'Yontem var.',
    'steps', jsonb_build_array('Adim bir.', 'Adim iki.'),
    'result', 'Sonuc var.',
    'correctAnswerJustification', 'Gerekce var.',
    'commonMistakes', jsonb_build_array(''));
begin
  perform public._qa_q123_reg('T-08a',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t08-ca', 'QA123 cozumu olmayan soru metni buradadir.',
        jsonb_build_object('solution', 'null'::jsonb)))),
    'service_role', null);
  perform public._qa_q123_true('T-08a', 'cozum bos -> solution_zorunlu',
    public._qa_q123_has_err('T-08a', 'solution_zorunlu'),
    'durum=' || public._qa_q123_res('T-08a'));

  perform public._qa_q123_reg('T-08b',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t08-cb', 'QA123 yontemsiz cozum iceren soru metni.',
        jsonb_build_object('solution', jsonb_build_object(
          'steps', jsonb_build_array('Adim bir.', 'Adim iki.'),
          'result', 'Sonuc var.',
          'correctAnswerJustification', 'Gerekce var.',
          'commonMistakes', jsonb_build_array('Yaygin hata var.')))))),
    'service_role', null);
  perform public._qa_q123_true('T-08b', 'cozum yontemsiz -> solution_method_eksik',
    public._qa_q123_has_err('T-08b', 'solution_method_eksik'),
    'durum=' || public._qa_q123_res('T-08b'));

  perform public._qa_q123_reg('T-08c',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t08-cc', 'QA123 tek adimli cozum iceren soru metni.',
        jsonb_build_object('solution', v_sol_short)))),
    'service_role', null);
  perform public._qa_q123_true('T-08c', 'tek adim -> solution_en_az_iki_adim_olmali',
    public._qa_q123_has_err('T-08c', 'solution_en_az_iki_adim_olmali'),
    'durum=' || public._qa_q123_res('T-08c'));

  perform public._qa_q123_reg('T-08d',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t08-cd', 'QA123 sonucu eksik cozum olan soru metni.',
        jsonb_build_object('solution', jsonb_build_object(
          'method', 'Yontem var.',
          'steps', jsonb_build_array('Adim bir.', 'Adim iki.'),
          'correctAnswerJustification', 'Gerekce var.',
          'commonMistakes', jsonb_build_array('Yaygin hata var.')))))),
    'service_role', null);
  perform public._qa_q123_true('T-08d', 'cozum sonucsuz -> solution_result_eksik',
    public._qa_q123_has_err('T-08d', 'solution_result_eksik'),
    'durum=' || public._qa_q123_res('T-08d'));

  perform public._qa_q123_reg('T-08e',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t08-ce', 'QA123 gerekcesiz cozum iceren soru metni.',
        jsonb_build_object('solution', jsonb_build_object(
          'method', 'Yontem var.',
          'steps', jsonb_build_array('Adim bir.', 'Adim iki.'),
          'result', 'Sonuc var.',
          'commonMistakes', jsonb_build_array('Yaygin hata var.')))))),
    'service_role', null);
  perform public._qa_q123_true('T-08e', 'cozum gerekcesiz -> solution_justification_eksik',
    public._qa_q123_has_err('T-08e', 'solution_justification_eksik'),
    'durum=' || public._qa_q123_res('T-08e'));

  perform public._qa_q123_reg('T-08f',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t08-cf', 'QA123 celdirici gerekcesi olmayan soru metni.',
        jsonb_build_object('solution', v_sol_no_cm)))),
    'service_role', null);
  perform public._qa_q123_true('T-08f', 'celdirici gerekcesi bos -> solution_common_mistakes_eksik',
    public._qa_q123_has_err('T-08f', 'solution_common_mistakes_eksik'),
    'durum=' || public._qa_q123_res('T-08f'));
end $blk$;


-- ============================================================
-- T-09: Ders cozumleme (kanonik subjects tek/eslesme kurallari)
-- ============================================================

insert into public.subjects (id, name, slug, sort_order, is_active)
values
  ('99770000-0000-0000-0000-000000000a10', 'QA Kapali Ders', 'qa-kapali-ders', 90, false),
  ('99770000-0000-0000-0000-000000000a11', 'QA Coklu Ders', 'qa-coklu-ders-1', 91, true),
  ('99770000-0000-0000-0000-000000000a12', 'qa coklu ders', 'qa-coklu-ders-2', 92, true)
on conflict (id) do nothing;

do $blk$
begin
  perform public._qa_q123_reg('T-09a',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t09-ca', 'QA123 olmayan ders referansi soru metni burada.',
        jsonb_build_object('subject_ref', 'QA Boyle Bir Ders Yok')))),
    'service_role', null);
  perform public._qa_q123_true('T-09a', 'bilinmeyen ders -> subject_not_found',
    public._qa_q123_has_err('T-09a', 'subject_not_found'),
    'durum=' || public._qa_q123_res('T-09a'));

  perform public._qa_q123_reg('T-09b',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t09-cb', 'QA123 gecersiz uuidli ders olan soru metni.',
        jsonb_build_object('subject_id', 'not-a-uuid')))),
    'service_role', null);
  perform public._qa_q123_true('T-09b', 'gecersiz subject_id -> uuid formati hatasi',
    public._qa_q123_has_err('T-09b', 'subject_id_gecerli_bir_uuid_olmali'),
    'durum=' || public._qa_q123_res('T-09b'));

  perform public._qa_q123_reg('T-09c',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t09-cc', 'QA123 ders bilgisi olmayan soru metni burada.',
        jsonb_build_object('subject_ref', ' ', 'subject_id', ' ')))),
    'service_role', null);
  perform public._qa_q123_true('T-09c', 'ders alani yok -> subject_id_veya_subject_ref_zorunlu',
    public._qa_q123_has_err('T-09c', 'subject_id_veya_subject_ref_zorunlu'),
    'durum=' || public._qa_q123_res('T-09c'));

  perform public._qa_q123_reg('T-09d',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t09-cd', 'QA123 pasif dersle eslesen soru metni burada.',
        jsonb_build_object('subject_ref', 'QA Kapali Ders')))),
    'service_role', null);
  perform public._qa_q123_true('T-09d', 'is_active=false ders -> subject_not_found',
    public._qa_q123_has_err('T-09d', 'subject_not_found'),
    'durum=' || public._qa_q123_res('T-09d'));

  perform public._qa_q123_reg('T-09e',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t09-ce', 'QA123 coklu ders eslesmesi soru metnidir.',
        jsonb_build_object('subject_ref', 'QA Coklu Ders')))),
    'service_role', null);
  perform public._qa_q123_true('T-09e', 'coklu eslesme -> subject_ambiguous',
    public._qa_q123_has_err('T-09e', 'subject_ambiguous'),
    'durum=' || public._qa_q123_res('T-09e'));

  perform public._qa_q123_reg('T-09f',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t09-cf', 'QA123 subject_id ile gelen gecerli soru metni.',
        jsonb_build_object('subject_id', '430903f3-527e-4e12-b7e8-ac0afdb784aa')))),
    'service_role', null);
  perform public._qa_q123_true('T-09f', 'subject_id gecerli -> ingested',
    public._qa_q123_res('T-09f') = 'ingested',
    'durum=' || public._qa_q123_res('T-09f'));
end $blk$;


-- ============================================================
-- T-10: Evren (gercek) duplicate kontrolu + rejected muafiyeti
-- ============================================================

insert into public.ai_question_staging
  (staging_source, grade_level, subject_id, question_text,
   option_a, option_b, option_c, option_d, option_e,
   proposed_correct_answer, staging_status, ownership_status,
   license_status, commercial_use_allowed, copyright_risk_level)
values
  ('external_producer', 5, '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   'QA123 evren duplicate aday metni burada metin degeri.',
   'QA ev A', 'QA ev B', 'QA ev C', 'QA ev D', 'QA ev E',
   'A', 'validating', 'ai_original',
   'pending', false, 'unknown');

insert into public.ai_question_staging
  (staging_source, grade_level, subject_id, question_text,
   option_a, option_b, option_c, option_d, option_e,
   proposed_correct_answer, staging_status, ownership_status,
   license_status, commercial_use_allowed, copyright_risk_level)
values
  ('external_producer', 5, '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   'QA123 rejected evren metni burada yer almaktadir.',
   'QA rej A', 'QA rej B', 'QA rej C', 'QA rej D', 'QA rej E',
   'A', 'rejected', 'ai_original',
   'pending', false, 'unknown');

do $blk$
declare
  v_dup_text text := 'QA123 evren duplicate aday metni burada metin degeri.';
  v_rej_text text := 'QA123 rejected evren metni burada yer almaktadir.';
begin
  perform public._qa_q123_reg('T-10a',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t10-ca', v_dup_text))),
    'service_role', null);
  perform public._qa_q123_true('T-10a', 'evrende var -> duplicate + staging yok',
    (public._qa_q123_res('T-10a') = 'rejected'
     or public._qa_q123_res('T-10a') = 'partially_valid')
    and public._qa_q123_has_err('T-10a', 'existing_universe_duplicate_question_text')
    and (select count(*) = 1 from public.ai_question_staging
          where question_text = v_dup_text),
    'durum=' || public._qa_q123_res('T-10a')
    || ' staging sayisi=' || (select count(*)::text from public.ai_question_staging
                               where question_text = v_dup_text));

  perform public._qa_q123_reg('T-10b',
    public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t10-cb', v_rej_text))),
    'service_role', null);
  perform public._qa_q123_true('T-10b', 'rejected evren muaf -> ingested',
    public._qa_q123_res('T-10b') = 'ingested'
    and (select count(*) = 2 from public.ai_question_staging
          where question_text = v_rej_text),
    'durum=' || public._qa_q123_res('T-10b')
    || ' staging sayisi=' || (select count(*)::text from public.ai_question_staging
                               where question_text = v_rej_text));
end $blk$;


-- ============================================================
-- T-11: Paket ici duplicate (metin + client_question_id)
-- ============================================================

do $blk$
declare
  v_dup_txt text := 'QA123 paket ici tekrar eden soru metni burada yeralir.';
  v_pkg1 jsonb := public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t11-c1', v_dup_txt),
      public._qa_q123_candidate('t11-c2', v_dup_txt)));
  v_pkg2 jsonb := public._qa_q123_package(jsonb_build_array(
      public._qa_q123_candidate('t11-k1', 'QA123 ayni client id birinci soru metnidir.'),
      public._qa_q123_candidate('t11-k1', 'QA123 ayni client id ikinci soru metnidir.')));
begin
  perform public._qa_q123_reg('T-11a', v_pkg1, 'service_role', null);
  perform public._qa_q123_true('T-11a', 'paket ici ayni metin -> partially_valid 1+1 dup',
    (public._qa_q123_res('T-11a') = 'partially_valid')
    and (select (result ->> 'inserted_items')::int = 1
          and (result ->> 'duplicate_items')::int = 1
       from public._qa_q123_submits where key = 'T-11a'),
    'durum=' || public._qa_q123_res('T-11a'));

  perform public._qa_q123_reg('T-11b', v_pkg2, 'service_role', null);
  perform public._qa_q123_true('T-11b', 'paket ici ayni client id -> duplicate',
    (public._qa_q123_res('T-11b') = 'partially_valid')
    and (select (result ->> 'duplicate_items')::int = 1
       from public._qa_q123_submits where key = 'T-11b'),
    'durum=' || public._qa_q123_res('T-11b'));
end $blk$;


-- ============================================================
-- T-12: Guvenlik kapisi (service_role / admin / izinsiz kullanici)
-- ============================================================

do $blk$
declare
  v_admin jsonb := jsonb_build_object(
    'sub', '99770000-0000-0000-0000-000000000901',
    'role', 'authenticated');
  v_ordin jsonb := jsonb_build_object(
    'sub', '99770000-0000-0000-0000-000000000902',
    'role', 'authenticated');
  v_valid jsonb := public._qa_q123_candidate(
    't12-c1', 'QA123 guvenlik kapsami icin gecerli soru metni.');
  v_pkg jsonb := public._qa_q123_package(jsonb_build_array(v_valid));
begin
  perform public._qa_q123_reg('T-12a', v_pkg, 'service_role', null);
  perform public._qa_q123_true('T-12a', 'service_role -> kabul',
    public._qa_q123_res('T-12a') = 'ingested',
    'durum=' || public._qa_q123_res('T-12a'));

  perform public._qa_q123_reg('T-12b', v_pkg, 'authenticated', v_admin);
  perform public._qa_q123_true('T-12b', 'admin (ai.manage/questions.approve) -> kabul',
    public._qa_q123_res('T-12b') = 'already_received'
    or public._qa_q123_res('T-12b') = 'ingested',
    'durum=' || public._qa_q123_res('T-12b'));

  perform public._qa_q123_reg('T-12c', v_pkg, 'authenticated', v_ordin);
  perform public._qa_q123_expect('T-12c', 'izinsiz kullanici -> P0001 kapı',
    'T-12c', 'P0001', 'requires AI or admin permission');
end $blk$;


-- ============================================================
-- T-13: Final durumlar (rejected / partially_valid / ingested)
--       + review_required= hangi kosullarda false
-- ============================================================

do $blk$
declare
  v_bad jsonb := public._qa_q123_candidate(
    't13-cB', 'QA123 durumlar kapsaminda gecersiz secenekli soru.',
    jsonb_build_object('options', jsonb_build_object(
      'A', 'QA s A', 'B', 'QA s B', 'C', 'QA s C', 'D', 'QA s D')));
  v_ok jsonb := public._qa_q123_candidate(
    't13-cO', 'QA123 durumlar kapsaminda gecerli soru metni.');
  v_pkg_rej jsonb := public._qa_q123_package(jsonb_build_array(v_bad));
  v_pkg_mix jsonb := public._qa_q123_package(jsonb_build_array(v_bad, v_ok));
  v_pkg_pend jsonb := public._qa_q123_package(
    jsonb_build_array(
      public._qa_q123_candidate('t13-cP', 'QA123 pending paket icindeki gecerli soru metni.')),
    jsonb_build_object('validation_requested_status', 'pending'));
  v_pend_status text;
  v_pend_rev boolean;
begin
  perform public._qa_q123_reg('T-13a', v_pkg_rej, 'service_role', null);
  perform public._qa_q123_true('T-13a', 'tumu gecersiz -> rejected, inserted 0',
    public._qa_q123_res('T-13a') = 'rejected'
    and (select (result ->> 'inserted_items')::int = 0
            and (result ->> 'invalid_items')::int = 1
       from public._qa_q123_submits where key = 'T-13a'),
    'durum=' || public._qa_q123_res('T-13a'));

  perform public._qa_q123_reg('T-13b', v_pkg_mix, 'service_role', null);
  perform public._qa_q123_true('T-13b', 'karma -> partially_valid (1+1)',
    public._qa_q123_res('T-13b') = 'partially_valid'
    and (select (result ->> 'inserted_items')::int = 1
            and (result ->> 'invalid_items')::int = 1
       from public._qa_q123_submits where key = 'T-13b'),
    'durum=' || public._qa_q123_res('T-13b'));

  perform public._qa_q123_reg('T-13c', v_pkg_pend, 'service_role', null);
  select result ->> 'status',
         (result -> 'validation_summary' -> 'preflight' ->> 'review_required')::boolean
    into v_pend_status, v_pend_rev
   from public._qa_q123_submits where key = 'T-13c';
  perform public._qa_q123_true('T-13c', 'pending paket -> ingested + review_required=false',
    v_pend_status = 'ingested' and v_pend_rev = false,
    'status=' || coalesce(v_pend_status, '<null>')
    || ' review_required=' || coalesce(v_pend_rev::text, '<null>'));
end $blk$;


-- ============================================================
-- T-14: Deterministik sonuclar: her aday icin audit, yalniz
--       yazilan staging icin validation; sonuclar tutarli.
-- ============================================================

do $blk$
declare
  v_bad jsonb := public._qa_q123_candidate(
    't14-cB', 'QA123 determinizm icin gecersiz aday soru metni.',
    jsonb_build_object('correct_answer', 'X'));
  v_ok jsonb := public._qa_q123_candidate(
    't14-cO', 'QA123 determinizm icin gecerli soru metni budur.');
  v_pkg jsonb := public._qa_q123_package(jsonb_build_array(v_bad, v_ok));
  v_bid uuid;
begin
  perform public._qa_q123_reg('T-14', v_pkg, 'service_role', null);

  select (result ->> 'batch_id')::uuid into v_bid
    from public._qa_q123_submits where key = 'T-14';

  perform public._qa_q123_true('T-14a', '2 audit satiri (1 invalid + 1 inserted)',
    exists (
      select 1 from public.candidate_batch_candidate_results r
      where r.batch_id = v_bid and r.validation_status = 'invalid'
        and r.validation_errors ? 'correct_answer_A_E_arasi_olmali')
    and exists (
      select 1 from public.candidate_batch_candidate_results r
      where r.batch_id = v_bid and r.validation_status = 'inserted'
        and r.staging_question_id is not null),
    'audit satirlari=' || (select count(*)::text from public.candidate_batch_candidate_results
                            where batch_id = v_bid));

  perform public._qa_q123_true('T-14b', 'yalniz yazilan staging icin validation (2)',
    (select count(*) = 2
       from public.ai_validation_results v
       join public.candidate_batch_candidate_results r
         on r.staging_question_id = v.staging_question_id
      where r.batch_id = v_bid and r.validation_status = 'inserted'),
    'validation=' || (select count(*)::text
                       from public.ai_validation_results v
                       join public.candidate_batch_candidate_results r
                         on r.staging_question_id = v.staging_question_id
                      where r.batch_id = v_bid));
end $blk$;


-- ============================================================
-- T-15: PUBLIC RPC sarmalayicisi (PostgREST yolu)
-- ============================================================

do $blk$
declare
  v_admin jsonb := jsonb_build_object(
    'sub', '99770000-0000-0000-0000-000000000901',
    'role', 'authenticated');
  v_ordin jsonb := jsonb_build_object(
    'sub', '99770000-0000-0000-0000-000000000902',
    'role', 'authenticated');
  v_key_ok  text;
  v_key_ord text;
  v_key_anon text;
  v_state   text;
  v_msg     text;
  v_pkg jsonb := public._qa_q123_package(jsonb_build_array(
    public._qa_q123_candidate('t15-c1', 'QA123 public rpc ile gelen gecerli soru metni.')));
begin
  perform public._qa_q123_true('T-15a', 'public fonksiyon SECURITY INVOKER + EXECUTE kapsami',
    (select count(*) = 1
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'register_candidate_md_batch'
        and p.prosecdef = false
        and pg_get_function_identity_arguments(p.oid) = 'p_payload jsonb')
    and has_function_privilege('authenticated',
        'public.register_candidate_md_batch(jsonb)', 'EXECUTE')
    and has_function_privilege('service_role',
        'public.register_candidate_md_batch(jsonb)', 'EXECUTE')
    and not has_function_privilege('anon',
        'public.register_candidate_md_batch(jsonb)', 'EXECUTE'),
    'secdef=' || (select p.prosecdef::text from pg_proc p
                   join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'register_candidate_md_batch'));

  -- service_role icin public sarmayici
  execute 'set local role service_role';
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claims', '{}', true);
  begin
    execute 'select public.register_candidate_md_batch($1)::text' using v_pkg into v_msg;
    v_key_ok := 'ok';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform public._qa_q123_true('T-15b', 'public rpc service_role -> ingested',
    v_key_ok = 'ok' and (v_msg::jsonb ->> 'status') = 'ingested',
    'value=' || left(coalesce(v_msg, '<hata>'), 120));

  -- izinsiz kullanici icin public sarmayici -> kapı hatasi
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', v_ordin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_ordin ->> 'sub', true);
  begin
    execute 'select public.register_candidate_md_batch($1)::text' using v_pkg into v_msg;
    v_key_ord := 'ok';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    v_key_ord := v_state || ':' || v_msg;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform public._qa_q123_true('T-15c', 'public rpc izinsiz -> P0001 kapı',
    left(v_key_ord, 5) = 'P0001' and position('requires AI or admin permission' in v_key_ord) > 0,
    'value=' || left(v_key_ord, 120));

  -- anon -> EXECUTE yok (42501)
  execute 'set local role anon';
  begin
    execute 'select public.register_candidate_md_batch($1)::text' using v_pkg into v_msg;
    v_key_anon := 'ok';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    v_key_anon := v_state || ':' || v_msg;
  end;
  execute 'reset role';
  perform public._qa_q123_true('T-15d', 'public rpc anon -> 42501 (yetkisiz)',
    left(v_key_anon, 5) = '42501',
    'value=' || left(v_key_anon, 120));
end $blk$;


-- ============================================================
-- T-16: Paket-dis ierik yalniz sayac; kalici yayin/islem yok
-- ============================================================

do $blk$
declare
  v_c1 jsonb := public._qa_q123_candidate(
    't16-c1', 'QA123 paket disi sayac testi icin gecerli soru metni.');
  v_pkg jsonb := public._qa_q123_package(jsonb_build_array(v_c1));
  v_bid uuid;
begin
  perform public._qa_q123_reg('T-16', v_pkg, 'service_role', null);
  select (result ->> 'batch_id')::uuid into v_bid
    from public._qa_q123_submits where key = 'T-16';

  perform public._qa_q123_true('T-16a', 'batch metadata oop sayac + tur ozeti korundu',
    (select (b.metadata -> 'candidate_md_v11' ->> 'out_of_package_count')::int = 2
        and jsonb_array_length(b.metadata -> 'candidate_md_v11' -> 'out_of_package_kinds') = 2
       from public.candidate_question_batches b where b.id = v_bid)
    and (select count(*) = 0
          from public.ai_question_staging s
         where s.staging_source = 'external_producer'
           and (s.metadata::text like '%topic_not_supported%'
                or s.metadata::text like '%grade_out_of_scope%')),
    'oop=' || (select (b.metadata -> 'candidate_md_v11' ->> 'out_of_package_count')::text
                from public.candidate_question_batches b where b.id = v_bid));

  perform public._qa_q123_true('T-16b', 'otomatik yayin/islem hicbir yerde true degil',
    (select count(*) = 0
       from public.ai_question_staging s
      where s.staging_source = 'external_producer'
        and (s.metadata -> 'candidate_md_v11' ->> 'publication_allowed')::boolean = true)
    and (select count(*) = 0
       from public.ai_question_staging s
      where s.staging_source = 'external_producer'
        and s.staging_status in ('ready', 'approved', 'promoted')),
    'yayinlanmis staging=' || (select count(*)::text from public.ai_question_staging s
                                where s.staging_source='external_producer'
                                  and s.staging_status in ('ready','approved','promoted'))::text);

  perform public._qa_q123_true('T-16c', 'hicbir external_producer staging promote edilmedi',
    (select count(*) = 0
       from public.ai_question_staging s
       join public.questions q on q.id = s.final_question_id
      where s.staging_source = 'external_producer')
    and (select count(*) = 0
       from public.questions q
      where q.approval_status = 'approved'
        and q.created_at >= (select min(created_at) - interval '1 second'
                                from public._qa_q123_submits)),
    'final_question_id=' || (select count(*)::text
                              from public.ai_question_staging s
                              where s.staging_source='external_producer'
                                and s.final_question_id is not null));
end $blk$;


-- ============================================================
-- T-17: Kazanim -> spec -> staging atomik baglantisi (migration 124)
-- ============================================================

do $blk$
declare
  v_pkg jsonb := public._qa_q123_package(jsonb_build_array(
    public._qa_q123_candidate('t17-c1', 'QA124 kurikulum bag kapsaminda gecerli soru metni burada.')));
  v_bid uuid;
  v_sid uuid;
  v_outcome_id uuid;
  v_ok boolean;
begin
  perform public._qa_q123_reg('T-17', v_pkg, 'service_role', null);

  select (result ->> 'batch_id')::uuid into v_bid
    from public._qa_q123_submits where key = 'T-17';
  select (result -> 'staging_ids' ->> 0)::uuid into v_sid
    from public._qa_q123_submits where key = 'T-17';
  select o.id into v_outcome_id
    from public.curriculum_outcomes o where o.outcome_code = 'MAT.5.1';

  select
      s.generation_spec_id is not null
      and s.proposed_curriculum_version_id = o2.curriculum_version_id
      and s.proposed_topic_id is not distinct from o2.topic_id
      and s.proposed_subtopic_id is not distinct from o2.subtopic_id
      and (s.metadata ->> 'required_outcome_id')::uuid = v_outcome_id
      and (s.metadata ->> 'generation_spec_id')::uuid = s.generation_spec_id
      and (s.metadata ->> 'curriculum_version_id')::uuid = o2.curriculum_version_id
      and (s.metadata ->> 'outcome_code') = 'MAT.5.1'
      and exists (select 1 from public.ai_generation_specs g
                  where g.id = s.generation_spec_id
                    and g.outcome_id = v_outcome_id)
    into v_ok
    from public.ai_question_staging s
    join public.curriculum_outcomes o2 on o2.id = v_outcome_id
   where s.id = v_sid
     and s.staging_source = 'external_producer';

  perform public._qa_q123_true('T-17', 'kazanim->spec->staging atomik zinciri kuruldu',
    v_ok,
    'ok=' || coalesce(v_ok::text, '<null>'));
end $blk$;


-- ============================================================
-- T-18: Faz 118 spec sozlesmesi (desired_count=1, status ready,
--       provenance constraints, otomatik yayin yok)
-- ============================================================

do $blk$
declare
  v_pkg jsonb := public._qa_q123_package(jsonb_build_array(
    public._qa_q123_candidate('t18-c1', 'QA124 spec sozlesmesi kapsaminda gecerli soru metni.')));
  v_bid uuid;
  v_ok boolean;
begin
  perform public._qa_q123_reg('T-18', v_pkg, 'service_role', null);

  select (result ->> 'batch_id')::uuid into v_bid
    from public._qa_q123_submits where key = 'T-18';

  select
      g.desired_count = 1
      and g.status = 'ready'
      and g.grade_level = 5
      and g.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa'
      and g.difficulty = 'easy'
      and g.cognitive_type = 'learning'
      and g.min_solve_time_seconds = 60
      and g.max_solve_time_seconds = 60
      and (g.constraints ->> 'source') = 'external_producer'
      and (g.constraints ->> 'batch_id') = v_bid::text
      and (g.constraints ->> 'producer_id') = 'qa-md-producer-1'
      and (g.constraints ->> 'outcome_code') = 'MAT.5.1'
      and exists (select 1 from public.ai_question_staging s
                  where s.generation_spec_id = g.id
                    and s.staging_status = 'validating')
    into v_ok
   from public.ai_generation_specs g
   where g.constraints ->> 'batch_id' = v_bid::text;

  perform public._qa_q123_true('T-18', 'Faz 118 spec sozlesmesi + provenance tek/ready',
    v_ok,
    'ok=' || coalesce(v_ok::text, '<null>'));
end $blk$;


-- ============================================================
-- T-19: Denetim kapilari (start_answer_verification +
--       start_curriculum_fit_verification) spec bagli adayda acilir
-- ============================================================

do $blk$
declare
  v_pkg jsonb := public._qa_q123_package(jsonb_build_array(
    public._qa_q123_candidate('t19-c1', 'QA124 denetim kapsaminda gecerli soru metni burada.')));
  v_staging_id uuid;
  v_answer_run uuid;
  v_fit_run uuid;
  v_ok_run text;
  v_outcome_id uuid;
begin
  perform public._qa_q123_reg('T-19', v_pkg, 'service_role', null);

  select r.staging_question_id into v_staging_id
    from public._qa_q123_submits s
    join public.candidate_question_batches b on b.batch_key = (s.result ->> 'batch_key')
    join public.candidate_batch_candidate_results r on r.batch_id = b.id
   where s.key = 'T-19'
     and r.validation_status = 'inserted';

  select o.id into v_outcome_id
    from public.curriculum_outcomes o where o.outcome_code = 'MAT.5.1';

  execute 'set local role service_role';
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claims', '{}', true);
  begin
    select private.start_answer_verification(v_staging_id) into v_answer_run;
    select private.start_curriculum_fit_verification(v_staging_id) into v_fit_run;
    v_ok_run := 'ok';
  exception when others then
    v_ok_run := sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  perform public._qa_q123_true('T-19', 'denetim kapilari spec bagli adayda sorunsuz acilir',
    v_ok_run = 'ok'
    and v_answer_run is not null
    and v_fit_run is not null
    and exists (select 1 from public.ai_answer_verification_runs r
                where r.staging_question_id = v_staging_id
                  and r.consensus_status = 'waiting_solver_1'
                  and (r.metadata ->> 'automatic_publication_allowed')::boolean = false)
    and exists (select 1 from public.ai_curriculum_fit_runs r
                where r.staging_question_id = v_staging_id
                  and r.status = 'waiting_reviewer_1'
                  and r.expected_outcome_id = v_outcome_id
                  and (r.metadata ->> 'automatic_publication_allowed')::boolean = false)
    and exists (select 1 from public.ai_question_staging s
                where s.id = v_staging_id
                  and s.metadata ? 'answer_verification_run_id'
                  and s.metadata ? 'curriculum_fit_run_id'),
    'ok=' || coalesce(v_ok_run, '<null>')
    || ' answer=' || coalesce(v_answer_run::text, '<null>')
    || ' fit=' || coalesce(v_fit_run::text, '<null>'));
end $blk$;


-- ============================================================
-- T-20: Fail-closed kazanimi (cozulemeyen/pasif) -> outcome_not_found,
--       yarim spec/staging/audit iliskisi birakmaz
-- ============================================================

do $blk$
declare
  v_pkg_a jsonb := public._qa_q123_package(jsonb_build_array(
    public._qa_q123_candidate('t20-ca', 'QA124 cozulemeyen kazanim icin gecerli soru metni.',
      jsonb_build_object('outcome_code', 'MAT.99.99'))));
  v_pkg_b jsonb := public._qa_q123_package(jsonb_build_array(
    public._qa_q123_candidate('t20-cb', 'QA124 pasif kazanim icin gecerli soru metni.',
      jsonb_build_object('outcome_code', 'MAT.5.2'))));
  v_bid_a uuid;
  v_bid_b uuid;
  v_no_spec boolean;
begin
  perform public._qa_q123_reg('T-20a', v_pkg_a, 'service_role', null);
  perform public._qa_q123_reg('T-20b', v_pkg_b, 'service_role', null);

  select (result ->> 'batch_id')::uuid into v_bid_a
    from public._qa_q123_submits where key = 'T-20a';
  select (result ->> 'batch_id')::uuid into v_bid_b
    from public._qa_q123_submits where key = 'T-20b';

  v_no_spec := not exists (
    select 1 from public.ai_generation_specs g
     where g.constraints ->> 'batch_id' in (v_bid_a::text, v_bid_b::text)
  );

  perform public._qa_q123_true('T-20', 'cozulemeyen/pasif kazanim fail-closed: outcome_not_found + yarim iliski yok',
    public._qa_q123_res('T-20a') = 'rejected'
    and public._qa_q123_res('T-20b') = 'rejected'
    and public._qa_q123_has_err('T-20a', 'outcome_not_found')
    and public._qa_q123_has_err('T-20b', 'outcome_not_found')
    and v_no_spec
    and not exists (select 1 from public.ai_question_staging s
                    where s.question_text like 'QA124 cozulemeyen%')
    and not exists (select 1 from public.ai_question_staging s
                    where s.question_text like 'QA124 pasif%'),
    'a=' || public._qa_q123_res('T-20a')
    || ' b=' || public._qa_q123_res('T-20b')
    || ' spec_yok=' || v_no_spec);
end $blk$;


-- ============================================================
-- T-21: v1.0 geriye uyumluluk + DTO ic yapi sizdirma + yayin yasagi
-- ============================================================

do $blk$
declare
  v_c jsonb := jsonb_build_object(
    'client_question_id', 't21-v10c1',
    'question_text', 'QA124 v10 geriye uyum icin gecerli soru metni buradadir.',
    'subject_id', '430903f3-527e-4e12-b7e8-ac0afdb784aa',
    'grade_level', 9,
    'outcome_code', 'MAT.9.1.1',
    'difficulty', 'easy',
    'cognitive_type', 'learning',
    'correct_answer', 'A',
    'options', jsonb_build_object(
      'A', 'QA v10 sec A', 'B', 'QA v10 sec B',
      'C', 'QA v10 sec C', 'D', 'QA v10 sec D', 'E', 'QA v10 sec E'));
  v_pkg jsonb := jsonb_build_object(
    'schema_version', '1.0',
    'origin', 'curriculum_original',
    'producer', jsonb_build_object('id', 'qa-v10-fz22', 'model', 'qa-v10-parser'),
    'questions', jsonb_build_array(v_c));
  v_res jsonb;
  v_state text;
  v_bid uuid;
  v_sid uuid;
  v_outcome_id uuid;
begin
  execute 'set local role service_role';
  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claims', '{}', true);
  begin
    execute 'select public.register_candidate_question_batch($1)::text' using v_pkg into v_res;
    v_state := 'OK';
  exception when others then
    v_state := sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  select o.id into v_outcome_id from public.curriculum_outcomes o
   where o.outcome_code = 'MAT.9.1.1'
     and o.subject_id = '430903f3-527e-4e12-b7e8-ac0afdb784aa'
   limit 1;

  v_bid := (v_res ->> 'batch_id')::uuid;
  v_sid := (v_res -> 'staging_ids' ->> 0)::uuid;

  perform public._qa_q123_true('T-21', 'v1.0 geriye uyum korunur: spec+zincir kurulur, DTO ic yapi sizdirmaz',
    v_state = 'OK'
    and (v_res ->> 'status') = 'ingested'
    and v_sid is not null
    and exists (select 1 from public.ai_question_staging s
                where s.id = v_sid
                  and s.staging_source = 'external_producer'
                  and s.generation_spec_id is not null
                  and s.proposed_curriculum_version_id is not null
                  and (s.metadata ->> 'required_outcome_id')::uuid = v_outcome_id)
    and exists (select 1 from public.ai_generation_specs g
                where g.id = (select generation_spec_id from public.ai_question_staging where id = v_sid)
                  and g.desired_count = 1
                  and g.status = 'ready'
                  and g.outcome_id = v_outcome_id
                  and g.constraints ->> 'batch_id' = v_bid::text
                  and g.constraints ->> 'source' = 'external_producer')
    and not (v_res ? 'spec_id')
    and not (v_res ? 'generation_spec_id')
    and not (v_res ? 'required_outcome_id')
    and (v_res ->> 'automatic_publication_allowed')::boolean = false,
    'v10 state=' || coalesce(v_state, '<null>')
    || ' status=' || coalesce(v_res ->> 'status', '<null>'));
end $blk$;


-- ============================================================
-- OZET + ROLLBACK (kalici kayit yok)
-- ============================================================

select label || ' | ' || title || ' | ' || result || ' | ' || coalesce(detail, '')
  from public._qa_q123_results
 order by label;

select 'TOPLAM|' || count(*) || '|' || count(*) filter (where result = 'PASS')
       || '|' || count(*) filter (where result = 'FAIL')
  from public._qa_q123_results;

rollback;