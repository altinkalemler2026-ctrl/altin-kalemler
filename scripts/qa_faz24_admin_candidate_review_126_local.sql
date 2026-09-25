-- ============================================================
-- scripts/qa_faz24_admin_candidate_review_126_local.sql
-- Altin Kalemler - Migration 126 yerel QA suite
-- (admin candidate-review veri sozlesmesi uzantisi)
--
-- 126 kapsami:
--   1. get_candidate_question_batch_detail(uuid) CREATE OR REPLACE:
--      preview'a subject_name (subjects JOIN), outcome_code ve
--      low_confidence (staging metadata) eklerir. Ust katman:
--      subject_name=text, outcome_code=text,
--      low_confidence=boolean (metadata anahtari yoksa NULL).
--   2. private.register_candidate_md_batch(jsonb): kok zarftaki
--      opsiyonel `low_confidence_candidates` (client_question_id
--      dizisi) okunur; her staging'in metadata'sina `low_confidence`
--      boolean yazilir (eslesme yoksa false). Eski kayitlar anahtari
--      TASIMAZ; RPC bu durumda NULL doner.
--
-- Test matrisi:
--   T-01  register happy-path (service_role) + low_confidence_candidates
--         -> ingested, 2 inserted, staging metadata true/false
--   T-02  detail ayni batch (service_role): subject_name=Matematik,
--         outcome_code, low_confidence true/false, solution object
--   T-03  detail allowlist: raw_payload/metadata top-level sizdirmaz,
--         yalniz yeni alanlar var
--   T-04  legacy staging (metadata'da low_confidence anahtari yok)
--         -> detail low_confidence=null ("kayit yok")
--   T-05  zarf sessizce eksik/bozuk (null yerine false) -> false
--   T-06  ACL: anon EXECUTE yok, authenticated/service_role var
--         (hem detail hem register); anon cagri 42501
--   T-07  ACL: authenticated yetkisiz 42501; super_admin OK;
--         question_reviewer (questions.approve) OK
--   T-08  idempotent: ayni payload yeniden -> already_received,
--         yeni staging/batch YOK (124 regresyonu)
--   T-09  migration yeniden uygulama (suitten once yapilir) sorunsuz
--
-- CI UYUMU: detay satirlari once, SON satir yalniz "toplam|gecen|kalan"
-- (kalan=0). Tum degisiklikler rollback ile geri alinir.
--
-- KOSU (disposable, 001-126 uygulanmis; 126 dosyasi da 2 kez):
--   docker cp scripts/qa_faz24_admin_candidate_review_126_local.sql <db>:/tmp/
--   docker exec <db> psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -A -t -f /tmp/qa_faz24_admin_candidate_review_126_local.sql
-- ============================================================

\set ON_ERROR_STOP on

begin;

-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR
-- ============================================================

create table public._qa_f24_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_f24_results
  to anon, authenticated, service_role;

create table public._qa_f24_submits (
  key      text primary key,
  result   jsonb,
  is_err   boolean not null default false,
  sqlstate text,
  err_msg  text,
  created_at timestamptz not null default now()
);

grant select, insert, update, delete
  on public._qa_f24_submits
  to anon, authenticated, service_role;

create function public._qa_f24_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_f24_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa_f24_true(text, text, boolean, text)
  to anon, authenticated, service_role;

-- role + jwt simülasyonuyla kod calistirir, ciktiyi doner.
create function public._qa_f24_as_role(p_role text, p_claims text, p_code text)
returns text
language plpgsql
security invoker
as $qa$
declare
  v_out text;
begin
  execute format('set local role %I', p_role);
  perform set_config('request.jwt.claims', p_claims, true);
  -- auth.uid()/auth.role() request.jwt.claim.sub/.role GUC'larini okur
  if p_claims is not null and p_claims <> '' then
    perform set_config('request.jwt.claim.sub',
      coalesce((p_claims::jsonb ->> 'sub'), ''), true);
    perform set_config('request.jwt.claim.role',
      coalesce((p_claims::jsonb ->> 'role'), ''), true);
  end if;
  execute p_code into v_out;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  execute 'reset role';
  return coalesce(v_out, '');
end;
$qa$;

grant execute
  on function public._qa_f24_as_role(text, text, text)
  to anon, authenticated, service_role;

-- bilesik cagri matrisi executor'u (detail), hata yakalar.
create function public._qa_f24_role_try(p_role text, p_claims text, p_code text)
returns jsonb
language plpgsql
security invoker
as $qa$
declare
  v_out text;
  v_state text;
  v_msg   text;
begin
  begin
    v_out := public._qa_f24_as_role(p_role, p_claims, p_code);
    return jsonb_build_object('ok', true, 'out', v_out);
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return jsonb_build_object('ok', false, 'sqlstate', v_state, 'msg', left(v_msg, 160));
  end;
end;
$qa$;

grant execute
  on function public._qa_f24_role_try(text, text, text)
  to anon, authenticated, service_role;

-- register (private) cagrisi: role+claims ile, sonucu/hata durumunu saklar.
create function public._qa_f24_reg(
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

  insert into public._qa_f24_submits
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
  on function public._qa_f24_reg(text, jsonb, text, jsonb)
  to anon, authenticated, service_role;

-- Beklenen hata asserti (sqlstate + mesaj icerigi) — register submit'i icin.
create function public._qa_f24_expect(
  p_label text, p_title text, p_key text, p_state text, p_msg_like text default ''
)
returns void
language plpgsql
security invoker
as $qa$
declare
  v_row public._qa_f24_submits%rowtype;
begin
  select * into v_row from public._qa_f24_submits where key = p_key;

  if v_row.key is null then
    insert into public._qa_f24_results
    values (p_label, p_title, 'FAIL', 'key bulunamadi: ' || p_key);
    return;
  end if;

  insert into public._qa_f24_results
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
  on function public._qa_f24_expect(text, text, text, text, text)
  to anon, authenticated, service_role;

-- ============================================================
-- PAYLOAD KURUCULAR (v1.1 md; 124 sozlesmesiyle uyumlu)
-- ============================================================

create function public._qa_f24_candidate(
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
        'A', 'QA24 secenek A', 'B', 'QA24 secenek B',
        'C', 'QA24 secenek C', 'D', 'QA24 secenek D',
        'E', 'QA24 secenek E'),
      'solution', jsonb_build_object(
        'method', 'Gercek yontem anlatilir.',
        'steps', jsonb_build_array(
          'Adim 1: verilenler yazilir.',
          'Adim 2: islem yapilir.'),
        'result', 'A secenegi dogrudur.',
        'correctAnswerJustification', 'A secenegindeki deger dogrulanir.',
        'commonMistakes', jsonb_build_array('Yaygin hata belirlenir.'))
    ) || p_extra
$qa$;

create function public._qa_f24_package(
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
      'producer', jsonb_build_object('id', 'qa24-producer-1', 'model', 'qa24-parser-v1'),
      'publication_allowed', false,
      'is_active', false,
      'validation_requested_status', 'needs_review',
      'metadata', jsonb_build_object(
        'out_of_package_count', 0,
        'out_of_package_kinds', jsonb_build_array())
    ) || p_extra || jsonb_build_object('questions', p_questions)
$qa$;

grant execute
  on function public._qa_f24_candidate(text, text, jsonb)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_f24_package(jsonb, jsonb)
  to anon, authenticated, service_role;

-- ============================================================
-- FIXTURE'LAR (sabit QA uuid'leri; rollback ile silinecek)
--   ADMIN : super_admin (ai.manage + questions.approve)
--   REVRW : question_reviewer (questions.approve)
--   ORDIN : izinsiz kullanici
--   MAT.5.1 aktif (intake cozum hedefi) / MAT.5.2 pasif
--   Matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
--   TYMM 2026: a1000000-0000-4000-8000-0000000000c1 (111 seed)
-- ============================================================

insert into auth.users
  (id, aud, role, email, encrypted_password, confirmed_at,
   raw_user_meta_data, created_at, updated_at)
values
  ('99770000-0000-0000-0000-000000000a01', 'authenticated', 'authenticated',
   'qa24-admin@e2e.test', '', now(),
   '{"nickname":"QA24_Admin"}'::jsonb, now(), now()),
  ('99770000-0000-0000-0000-000000000a02', 'authenticated', 'authenticated',
   'qa24-reviewer@e2e.test', '', now(),
   '{"nickname":"QA24_Reviewer"}'::jsonb, now(), now()),
  ('99770000-0000-0000-0000-000000000a03', 'authenticated', 'authenticated',
   'qa24-ordin@e2e.test', '', now(),
   '{"nickname":"QA24_Ordin"}'::jsonb, now(), now())
on conflict (id) do nothing;

insert into public.admin_user_roles (user_id, role_id, assigned_by, assigned_at)
select '99770000-0000-0000-0000-000000000a01', r.id,
       '99770000-0000-0000-0000-000000000a01', now()
  from public.admin_roles r
 where r.role_code = 'super_admin'
on conflict do nothing;

insert into public.admin_user_roles (user_id, role_id, assigned_by, assigned_at)
select '99770000-0000-0000-0000-000000000a02', r.id,
       '99770000-0000-0000-0000-000000000a02', now()
  from public.admin_roles r
 where r.role_code = 'question_reviewer'
on conflict do nothing;

insert into public.curriculum_outcomes (
  id, curriculum_version_id, grade_level, subject_id, topic_id, subtopic_id,
  outcome_code, outcome_text, sort_order, source_reference, is_active, created_at, updated_at
)
values
  ('99770000-0000-0000-0000-000000000c01',
   'a1000000-0000-4000-8000-0000000000c1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', NULL, NULL,
   'MAT.5.1', 'QA24 kazanimi: dogal sayilarla dort islem.', 1,
   'QA fixture', true, now(), now()),
  ('99770000-0000-0000-0000-000000000c02',
   'a1000000-0000-4000-8000-0000000000c1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', NULL, NULL,
   'MAT.5.2', 'QA24 pasif kazanimi.', 2,
   'QA fixture', false, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- T-01: register happy-path + low_confidence_candidates
-- ============================================================

do $blk$
declare
  v_res jsonb;
  v_bid uuid;
  v_c1 jsonb := public._qa_f24_candidate(
    'f24-c1', 'QA24 gecerli birinci soru metni surada yazilidir.');
  v_c2 jsonb := public._qa_f24_candidate(
    'f24-c2', 'QA24 gecerli ikinci soru metni surada yazilidir.');
  v_pkg jsonb := public._qa_f24_package(
    jsonb_build_array(v_c1, v_c2),
    jsonb_build_object('low_confidence_candidates', jsonb_build_array('f24-c1')));
begin
  perform public._qa_f24_reg('T-01', v_pkg, 'service_role', null);

  select result into v_res from public._qa_f24_submits where key = 'T-01';

  perform public._qa_f24_true('T-01a', 'ingested, 2 inserted, dup yok',
    (v_res->>'status') = 'ingested'
    and (v_res->>'inserted_items')::int = 2
    and (v_res->>'invalid_items')::int = 0
    and (v_res->>'duplicate_items')::int = 0
    and jsonb_array_length(v_res -> 'staging_ids') = 2,
    'status=' || coalesce(v_res->>'status', '<null>'));

  v_bid := (v_res ->> 'batch_id')::uuid;

  perform public._qa_f24_true('T-01b', 'low_confidence true (f24-c1) / false (f24-c2) yazildi',
    exists (
      select 1 from public.ai_question_staging s
      where s.id = (v_res -> 'staging_ids' ->> 0)::uuid
        and (s.metadata -> 'low_confidence')::boolean = true
        and s.metadata ->> 'client_question_id' = 'f24-c1')
    and exists (
      select 1 from public.ai_question_staging s
      where s.id = (v_res -> 'staging_ids' ->> 1)::uuid
        and (s.metadata -> 'low_confidence')::boolean = false
        and s.metadata ->> 'client_question_id' = 'f24-c2'),
    'metadata kontrolu staging_ids uzerinden');

  -- batch keyini testin geri kalaninda kullanmak icin sakla
  perform set_config('qa24.batch_id', v_bid::text, true);
end $blk$;

-- ============================================================
-- T-02 / T-03: detail RPC — yeni alanlar + allowlist
-- ============================================================

do $blk$
declare
  v_bid  uuid;
  v_json jsonb;
  v_row  public.AI_QUESTION_STAGING%ROWTYPE;
  v_prev jsonb;
begin
  v_bid := (current_setting('qa24.batch_id', true))::uuid;

  v_json := public._qa_f24_as_role('postgres',
    '{"sub":"99770000-0000-0000-0000-000000000a01","role":"service_role"}',
    format('select public.get_candidate_question_batch_detail(%L)::text', v_bid) ||
    '')::jsonb;

  perform public._qa_f24_true('T-02a',
    'batch bilgisi intact + 2 aday',
    (v_json -> 'batch' ->> 'batch_id')::uuid = v_bid
    and jsonb_array_length(v_json -> 'candidates') = 2,
    'candidates=' || jsonb_array_length(v_json -> 'candidates'));

  -- ilk aday (f24-c1): subject_name/outcome_code/low_confidence=true/solution
  v_prev := v_json -> 'candidates' -> 0 -> 'preview';

  perform public._qa_f24_true('T-02b',
    'preview yeni alanlar: subject_name=Matematik, outcome_code=MAT.5.1, low_confidence=true',
    v_prev is not null
    and v_prev ->> 'subject_name' = 'Matematik'
    and v_prev ->> 'outcome_code' = 'MAT.5.1'
    and (v_prev -> 'low_confidence')::boolean = true
    and (v_prev ->> 'staging_status') = 'validating',
    'subject_name=' || coalesce(v_prev->>'subject_name', '<null>')
    || ' outcome_code=' || coalesce(v_prev->>'outcome_code', '<null>')
    || ' low_confidence=' || coalesce(v_prev->>'low_confidence', '<null>'));

  perform public._qa_f24_true('T-02c',
    'solution object allowlist alanlariyla taşinir (method/steps/result)',
    v_prev -> 'solution' -> 'method' = '"Gercek yontem anlatilir."'
    and v_prev -> 'solution' ? 'steps'
    and v_prev -> 'solution' ->> 'result' = 'A secenegi dogrudur.',
    'solution=' || left(coalesce((v_prev->>'solution'), '<null>'), 160));

  -- ikinci aday (f24-c2): low_confidence=false
  v_prev := v_json -> 'candidates' -> 1 -> 'preview';
  perform public._qa_f24_true('T-02d',
    'eslesmeyen aday low_confidence=false (boolean yazildi)',
    (v_prev -> 'low_confidence')::boolean = false,
    'low_confidence=' || coalesce(v_prev->>'low_confidence', '<null>'));

  -- allowlist: ham/kapali alan adlari top-level sizdirilmaz
  perform public._qa_f24_true('T-03',
    'allowlist: raw_payload/metadata/forecast gibi kapali alanlar sizdirilmaz',
    not (v_json::text like '%raw_payload%')
    and not (v_json::text like '%generation_spec_id%')
    and not (v_json::text like '%deterministic_ingestion_passed%')
    and not (v_json::text like '%required_outcome_id%'),
    '');
end $blk$;

-- ============================================================
-- T-04: legacy staging (metadata'da low_confidence anahtari yok)
--        -> detail low_confidence=null ("kayit yok")
-- ============================================================

do $blk$
declare
  v_bid uuid;
  v_json jsonb;
  v_sid  uuid;
begin
  v_bid := (current_setting('qa24.batch_id', true))::uuid;

  -- fixture'in c1 staging satirindan anahtari kaldir (legacy simule)
  select s.id into v_sid
    from public.ai_question_staging s
   where s.metadata ->> 'client_question_id' = 'f24-c1'
   limit 1;

  update public.ai_question_staging
     set metadata = metadata - 'low_confidence'
   where id = v_sid;

  v_json := public._qa_f24_as_role('postgres',
    '{"sub":"99770000-0000-0000-0000-000000000a01","role":"service_role"}',
    format('select public.get_candidate_question_batch_detail(%L)::text', v_bid))::jsonb;

  perform public._qa_f24_true('T-04',
    'anahtar yoksa low_confidence=NULL (kayit yok), subject_name/outcome_code hala dolu',
    (v_json -> 'candidates' -> 0 -> 'preview' -> 'low_confidence')::text = 'null'
    and v_json -> 'candidates' -> 0 -> 'preview' ->> 'subject_name' = 'Matematik'
    and v_json -> 'candidates' -> 0 -> 'preview' ->> 'outcome_code' = 'MAT.5.1',
    'low_confidence=' || coalesce(v_json->'candidates'->0->'preview'->>'low_confidence', '<null>'));
end $blk$;

-- ============================================================
-- T-05: zarf eksikken (low_confidence_candidates yok) -> false
-- ============================================================

do $blk$
declare
  v_c1 jsonb := public._qa_f24_candidate(
    'f24-n1', 'QA24 zarfsiz paketin ilk soru metni yazilmistir.');
  v_c2 jsonb := public._qa_f24_candidate(
    'f24-n2', 'QA24 zarfsiz paketin ikinci soru metni yazilmistir.');
  v_pkg jsonb := public._qa_f24_package(jsonb_build_array(v_c1, v_c2));
  v_res jsonb;
  v_sid uuid;
begin
  perform public._qa_f24_reg('T-05', v_pkg, 'service_role', null);
  select result into v_res from public._qa_f24_submits where key = 'T-05';

  perform public._qa_f24_true('T-05a', 'zarf yokken ingested/2 inserted',
    (v_res->>'status') = 'ingested' and (v_res->>'inserted_items')::int = 2,
    'status=' || coalesce(v_res->>'status', '<null>'));

  select s.id into v_sid
    from public.ai_question_staging s
   where s.metadata ->> 'client_question_id' = 'f24-n1'
   limit 1;

  perform public._qa_f24_true('T-05b',
    'zarf yokken her staging low_confidence=false (boolean, null degil)',
    (select (s.metadata -> 'low_confidence')::boolean = false
       from public.ai_question_staging s where s.id = v_sid)
    and not exists (
      select 1 from public.ai_question_staging s
      where s.metadata ->> 'client_question_id' like 'f24-n%'
        and (s.metadata -> 'low_confidence') is null),
    'low_confidence yoksa null mu kalior');
end $blk$;

-- ============================================================
-- T-06: ACL — grant matrisi + anon cagri fail-closed
-- ============================================================

do $blk$
begin
  perform public._qa_f24_true('T-06a',
    'detail: anon EXECUTE yok, authenticated/service_role var',
    not has_function_privilege('anon',
       'public.get_candidate_question_batch_detail(uuid)', 'EXECUTE')
    and has_function_privilege('authenticated',
       'public.get_candidate_question_batch_detail(uuid)', 'EXECUTE')
    and has_function_privilege('service_role',
       'public.get_candidate_question_batch_detail(uuid)', 'EXECUTE'),
    '');

  perform public._qa_f24_true('T-06b',
    'register: anon EXECUTE yok, authenticated/service_role var',
    not has_function_privilege('anon',
       'private.register_candidate_md_batch(jsonb)', 'EXECUTE')
    and has_function_privilege('authenticated',
       'private.register_candidate_md_batch(jsonb)', 'EXECUTE')
    and has_function_privilege('service_role',
       'private.register_candidate_md_batch(jsonb)', 'EXECUTE'),
    '');

  perform public._qa_f24_true('T-06c',
    'claimsiz detail cagrisi 42501 (Kimlik dogrulamasi gerekli)',
    (public._qa_f24_role_try('anon',
       '', 'select public.get_candidate_question_batch_detail(''00000000-0000-0000-0000-000000000000'')::text') -> 'ok') = 'false'
    and public._qa_f24_role_try('anon',
       '', 'select public.get_candidate_question_batch_detail(''00000000-0000-0000-0000-000000000000'')::text') ->> 'sqlstate' = '42501',
    '');
end $blk$;

-- ============================================================
-- T-07: ACL — yetkili okuma (super_admin / question_reviewer)
-- ============================================================

do $blk$
declare
  v_bid uuid;
  v_super jsonb;
  v_revw  jsonb;
begin
  v_bid := (current_setting('qa24.batch_id', true))::uuid;

  v_super := public._qa_f24_role_try('authenticated',
    '{"sub":"99770000-0000-0000-0000-000000000a01","role":"authenticated"}',
    format('select public.get_candidate_question_batch_detail(%L)::text', v_bid));
  v_revw := public._qa_f24_role_try('authenticated',
    '{"sub":"99770000-0000-0000-0000-000000000a02","role":"authenticated"}',
    format('select public.get_candidate_question_batch_detail(%L)::text', v_bid));

  perform public._qa_f24_true('T-07a',
    'super_admin (ai.manage) detail OK + yeni alanlar',
    (v_super -> 'ok')::boolean
    and v_super ->> 'out' like '%subject_name%'
    and v_super ->> 'out' like '%outcome_code%',
    'len=' || length(coalesce(v_super->>'out', '')));

  perform public._qa_f24_true('T-07b',
    'question_reviewer (questions.approve) detail OK',
    (v_revw -> 'ok')::boolean
    and v_revw ->> 'out' like '%low_confidence%',
    'len=' || length(coalesce(v_revw->>'out', '')));

  perform public._qa_f24_true('T-07c',
    'izinsiz authenticated 42501 (fail-closed)',
    (public._qa_f24_role_try('authenticated',
       '{"sub":"99770000-0000-0000-0000-000000000a03","role":"authenticated"}',
       format('select public.get_candidate_question_batch_detail(%L)::text', v_bid)) ->> 'sqlstate') = '42501',
    '');
end $blk$;

-- ============================================================
-- T-08: idempotent yeniden gonderim (124 regresyonu)
-- ============================================================

do $blk$
declare
  v_c1 jsonb := public._qa_f24_candidate(
    'f24-c1', 'QA24 gecerli birinci soru metni surada yazilidir.');
  v_c2 jsonb := public._qa_f24_candidate(
    'f24-c2', 'QA24 gecerli ikinci soru metni surada yazilidir.');
  v_pkg jsonb := public._qa_f24_package(
    jsonb_build_array(v_c1, v_c2),
    jsonb_build_object('low_confidence_candidates', jsonb_build_array('f24-c1')));
  v_res jsonb;
begin
  perform public._qa_f24_reg('T-08', v_pkg, 'service_role', null);
  select result into v_res from public._qa_f24_submits where key = 'T-08';

  perform public._qa_f24_true('T-08',
    'ayni payload yeniden -> already_received, total intact',
    (v_res->>'status') = 'already_received'
    and (v_res->>'inserted_items')::int = 2,
    'status=' || coalesce(v_res->>'status', '<null>'));
end $blk$;

-- ============================================================
-- OZET + ROLLBACK (kalici kayit yok)
-- ============================================================

select label || ' | ' || title || ' | ' || result || ' | ' || coalesce(detail, '')
  from public._qa_f24_results
 order by label;

select 'TOPLAM|' || count(*) || '|' || count(*) filter (where result = 'PASS')
       || '|' || count(*) filter (where result = 'FAIL')
  from public._qa_f24_results;

rollback;