-- ============================================================
-- scripts/qa_faz35_review_actions_130_local.sql
-- Altın Kalemler — Migration 130 (Faz 35B) yerel QA suite
--
-- Kapsam: Faz 35A denetiminde tespit edilen M1-M4 açıklarının
-- append-only onarımının sözleşme kanıtı.
--
--   M1  private.ai_question_promotion_blockers()
--       T-01..T-07 : bloklayıcı tespiti (eksik kapı / fail sonuç /
--                    high|blocked telif / fail-closed birleşimi)
--       T-08..T-09 : approve gerçekten reddediyor ve questions'a
--                    HİÇBİR şey yazmıyor
--
--   M2  request_changes idempotency
--       T-10..T-12 : ilk çağrı yazıyor, tekrar YENİ satır ÜRETMİYOR
--
--   M3  admin_audit_log
--       T-13..T-18 : approve/reject/request_changes tam ve TEKİL
--                    audit; atomiklik; already_promoted tekrarı
--
--   M4  readiness idempotency + batch karar görünürlüğü
--       T-19..T-21 : (staging, deterministic, overall) TEKİL
--       T-22..T-26 : intake sayaçları DEĞİŞMİYOR; karar özeti
--                    ayrı alanda; uydurma status YAZILMIYOR
--
--   Yetki
--       T-27..T-31 : anon/PUBLIC yüzey kapalı; yetkisiz rol ve
--                    öğrenci reddi; geçersiz karar reddi
--
-- Çalıştırma (disposable DB, migration 001-130 uygulanmış):
--   docker cp scripts/qa_faz35_review_actions_130_local.sql <db>:/tmp/
--   docker exec <db> psql -U <admin> -d postgres \
--          -v ON_ERROR_STOP=1 -f /tmp/qa_faz35_review_actions_130_local.sql
--
-- Güvence: tüm suite TEK TRANSACTION içinde çalışır ve sonunda
-- ROLLBACK yapılır; hiçbir test artefaktı kalıcı olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUÇ TABLOSU + YARDIMCILAR
-- ============================================================

create table public._qa_f35b_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_f35b_results
  to anon, authenticated, service_role;

create function public._qa35b_expect(
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
      insert into public._qa_f35b_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_f35b_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_f35b_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_f35b_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa35b_expect_msg(
  p_label text, p_title text, p_sql text,
  p_state text, p_msg_pattern text
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
    insert into public._qa_f35b_results
    values (p_label, p_title, 'FAIL', 'hata beklenmisti ama uygulandi');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if v_state = p_state and upper(v_msg) like upper(p_msg_pattern) then
      insert into public._qa_f35b_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | mesaj eslesti');
    else
      insert into public._qa_f35b_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state || ' beklenen=' || p_state ||
              ' | msg=' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa35b_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_f35b_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

-- Kimlik kurulumu: CI imajindaki auth.uid() ve auth.role() TEKIL (eski)
-- claim okur; bu yuzden qgate122 deseniyle COĞUL + TEKIL claim'ler birlikte
-- kurulur. Tekil claim'ler eklenmedigi zaman auth.uid() NULL doner ve
-- migration 130'un 'Human authentication required.' kapisi tetiklenir
-- (bkz. docs/reports/faz35e-ci-faz35b-sql-hatasi-kok-neden-teshisi.md).
create function public._qa35b_as(p_uid uuid)
returns void
language plpgsql
security invoker
as $qa$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end;
$qa$;

-- Kimlik temizleme: TEK noktada, uc claim birden. Suite'teki HER temizleme
-- noktasi bu yardimciyi cagirir; boylece kimlik T-31 (set local role anon)
-- dahil hicbir senaryoya sizamaz ve temizleme unutulamaz.
create function public._qa35b_clear_claims()
returns void
language plpgsql
security invoker
as $qa$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end;
$qa$;

grant execute
  on function public._qa35b_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa35b_clear_claims()
  to anon, authenticated, service_role;

grant execute
  on function public._qa35b_expect_msg(text, text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa35b_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- SABITLER
-- ============================================================

-- admin: question_reviewer -> questions.approve (izinli)
-- wrong: copyright_reviewer -> questions.approve YOK (izinsiz)
-- ogrenci: hicbir admin rolu yok
create or replace function public._qa35b_consts()
returns jsonb language sql as $qa$
select jsonb_build_object(
  'admin_uid',   'b3500000-0000-0000-0000-000000000001'::uuid,
  'wrong_uid',   'b3500000-0000-0000-0000-000000000002'::uuid,
  'student_uid', 'b3500000-0000-0000-0000-000000000003'::uuid,
  'subject_id',  '71191e01-220a-4682-9351-3d62631308d2'::uuid,
  'batch_id',    'b3500000-0000-0000-0000-000000000010'::uuid,
  'sid_ok',      'b3500000-0000-0000-0000-0000000000a1'::uuid,
  'sid_rc',      'b3500000-0000-0000-0000-0000000000a2'::uuid,
  'sid_failval', 'b3500000-0000-0000-0000-0000000000a3'::uuid,
  'sid_copy',    'b3500000-0000-0000-0000-0000000000a4'::uuid,
  'sid_rj',      'b3500000-0000-0000-0000-0000000000a5'::uuid,
  'sid_nogate',  'b3500000-0000-0000-0000-0000000000a6'::uuid,
  'sid_idem',    'b3500000-0000-0000-0000-0000000000a7'::uuid,
  'sid_atomic',  'b3500000-0000-0000-0000-0000000000a8'::uuid
);
$qa$;


-- ============================================================
-- FIXTURE YARDIMCISI
--
-- Bir staging adayı + 5 zorunlu doğrulama kapısının TAMAMI
-- 'verified' olarak kurar. Testler sonra tek tek bozar.
--
-- p_skip_quality: true ise question_quality kapısı HİÇ oluşturulmaz
--                (M1 "eksik kapı" senaryosu).
-- ============================================================

create or replace function public._qa35b_fixture(
  p_sid uuid, p_skip_quality boolean default false
)
returns void
language plpgsql
security invoker
as $qa$
declare
  v_sub uuid := public._qa35b_consts() ->> 'subject_id';
begin
  insert into public.ai_question_staging (
    id,
    staging_source,
    staging_status,
    grade_level,
    subject_id,
    question_text,
    option_a, option_b, option_c, option_d,
    proposed_correct_answer,
    proposed_difficulty,
    proposed_cognitive_type,
    proposed_quality_level,
    ownership_status,
    license_status,
    commercial_use_allowed,
    copyright_risk_level,
    metadata
  )
  values (
    p_sid,
    'ai_generated',
    'validating',
    12,
    v_sub,
    'QA Faz35B aday sorusu: ' || p_sid::text,
    'A1 secenek', 'B1 secenek', 'C1 secenek', 'D1 secenek',
    'A',
    'medium',
    'application',
    'medium',
    'unknown',
    'unknown',
    false,
    'low',
    '{}'::jsonb
  );

  -- 033 answer verification (consensus_status okunur)
  insert into public.ai_answer_verification_runs (
    staging_question_id, proposed_answer, consensus_status, created_at, updated_at
  )
  values (p_sid, 'A', 'verified', now(), now());

  -- 034 curriculum fit
  insert into public.ai_curriculum_fit_runs (
    staging_question_id, expected_grade_level, expected_subject_id,
    status, created_at, updated_at
  )
  values (p_sid, 12, v_sub, 'verified', now(), now());

  -- 035 solve time
  insert into public.ai_solve_time_verification_runs (
    staging_question_id, status, created_at, updated_at
  )
  values (p_sid, 'verified', now(), now());

  -- 036 originality
  insert into public.ai_originality_verification_runs (
    staging_question_id, status, created_at, updated_at
  )
  values (p_sid, 'verified', now(), now());

  -- 037 question quality
  if not p_skip_quality then
    insert into public.ai_question_quality_runs (
      staging_question_id, status, created_at, updated_at
    )
    values (p_sid, 'verified', now(), now());
  end if;
end;
$qa$;


-- ============================================================
-- FIXTURE'LAR (rollback ile silinecek)
-- ============================================================

insert into auth.users (id, email) values
  ('b3500000-0000-0000-0000-000000000001', 'qa-f35b-admin@test.local'),
  ('b3500000-0000-0000-0000-000000000002', 'qa-f35b-wrong@test.local'),
  ('b3500000-0000-0000-0000-000000000003', 'qa-f35b-ogrenci@test.local');

insert into public.admin_user_roles (user_id, role_id)
select u, (select id from public.admin_roles where role_code = 'question_reviewer')
from (values
  ('b3500000-0000-0000-0000-000000000001'::uuid)
) as x(u);

insert into public.admin_user_roles (user_id, role_id)
select u, (select id from public.admin_roles where role_code = 'copyright_reviewer')
from (values
  ('b3500000-0000-0000-0000-000000000002'::uuid)
) as x(u);

-- Temiz adaylar (candidate_results FK'si icin ONCE staging gerekir)
select public._qa35b_fixture((public._qa35b_consts() ->> 'sid_ok')::uuid);
select public._qa35b_fixture((public._qa35b_consts() ->> 'sid_rc')::uuid);
select public._qa35b_fixture((public._qa35b_consts() ->> 'sid_rj')::uuid);
select public._qa35b_fixture((public._qa35b_consts() ->> 'sid_idem')::uuid);
select public._qa35b_fixture((public._qa35b_consts() ->> 'sid_atomic')::uuid);

-- Batch: 2 aday, total_items satır sayısıyla birebir tutarlı.
-- Sayaçların anlamı DEĞİŞTİRİLMEZ: 130 bu blokta insert/update YAPMAZ.
insert into public.candidate_question_batches (
  id, batch_key, schema_version, origin, producer_id, producer_model,
  status,
  total_items, valid_items, invalid_items, inserted_items, duplicate_items,
  validation_summary, error_data, raw_payload, metadata
)
values (
  'b3500000-0000-0000-0000-000000000010',
  'QA-F35B-BATCH', '1.0', 'curriculum_original', 'qa_f35b_suite', 'deterministic',
  'ingested',
  2, 2, 0, 2, 0,
  '{"received":2,"valid":2,"invalid":0,"inserted":2,"duplicates":0}'::jsonb,
  '[]'::jsonb,
  '{"batch":"QA-F35B"}'::jsonb,
  '{}'::jsonb
);

insert into public.candidate_batch_candidate_results (
  batch_id, candidate_index, client_question_id, validation_status,
  validation_errors, validation_warnings, staging_question_id
)
values
  ('b3500000-0000-0000-0000-000000000010', 0, 'QA-C-0', 'inserted',
   '[]'::jsonb, '[]'::jsonb, 'b3500000-0000-0000-0000-0000000000a1'),
  ('b3500000-0000-0000-0000-000000000010', 1, 'QA-C-1', 'inserted',
   '[]'::jsonb, '[]'::jsonb, 'b3500000-0000-0000-0000-0000000000a2');

-- KARAR ÖNCESİ SNAPSHOT (M4b kanıtı).
-- 130'un intake sayaçlarına ve status'a DOKUNMADIĞI ancak
-- validation_summary/metadata'ya yazdığı bu anlık görüntüyle
-- sonradan birebir karşılaştırılır.
create table public._qa_f35b_batch_snap as
select
  (to_jsonb(b) - 'updated_at' - 'validation_summary' - 'metadata') as counters,
  b.status                                                      as status
from public.candidate_question_batches b
where b.id = 'b3500000-0000-0000-0000-000000000010';


-- M1: fail sonucu olan aday (5 kapı tam, AMA 'fail' validation)
select public._qa35b_fixture((public._qa35b_consts() ->> 'sid_failval')::uuid);
insert into public.ai_validation_results (
  staging_question_id, validator_type, validation_type, result, summary, details
)
values (
  'b3500000-0000-0000-0000-0000000000a3', 'ai', 'originality', 'fail',
  'QA: baska bir dogrulayicidan gelen FAIL sonucu',
  '{"qa":"failing_validation"}'::jsonb
);

-- M1: telif riski YÜKSEK olan aday
-- staging.copyright_risk_level='low' iken copyright_reviews'te 'high'
-- -> denetim DOĞRU KAYNAKTAN (copyright_reviews) okumak zorunda.
select public._qa35b_fixture((public._qa35b_consts() ->> 'sid_copy')::uuid);
insert into public.copyright_reviews (
  staging_question_id, review_type, risk_level,
  commercial_use_recommendation, evidence, reviewer_type
)
values (
  'b3500000-0000-0000-0000-0000000000a4', 'originality', 'high',
  'do_not_allow', '{"qa":"high_risk"}'::jsonb, 'ai'
);

-- M1: question_quality kapısı hiç oluşturulmamış aday
select public._qa35b_fixture((public._qa35b_consts() ->> 'sid_nogate')::uuid, true);


-- ============================================================
-- M1: BLOKLAYICI TESPİTİ (doğrudan yardımcı çağrısı)
-- ============================================================

do $t$
declare
  v jsonb;
begin
  -- T-01: 5 kapı tam + temiz telif -> promote edilebilir (kontrol)
  v := private.ai_question_promotion_blockers(
    (public._qa35b_consts() ->> 'sid_ok')::uuid);

  perform public._qa35b_true('T-01',
    'M1 kontrol: 5 kapı tam, fail yok, telif temiz -> can_promote=true',
    (v ->> 'can_promote')::boolean is true
      and v -> 'missing_verification_gates' = '[]'::jsonb
      and (v ->> 'failing_validation_exists')::boolean is false
      and (v ->> 'dangerous_copyright_exists')::boolean is false,
    v::text);

  -- T-02: question_quality kapısı eksik
  v := private.ai_question_promotion_blockers(
    (public._qa35b_consts() ->> 'sid_nogate')::uuid);

  perform public._qa35b_true('T-02',
    'M1: eksik question_quality kapisi -> can_promote=false',
    (v ->> 'can_promote')::boolean is false
      and v -> 'missing_verification_gates' ? 'question_quality'
      and exists (
        select 1 from jsonb_array_elements(v -> 'blocking_reasons') b
         where b ->> 'code' = 'missing_verification_gate'
           and b ->> 'gate' = 'question_quality'
           and b ->> 'status' = 'not_started'
      ),
    (v -> 'missing_verification_gates')::text);

  -- T-03: 'fail' doğrulama sonucu
  v := private.ai_question_promotion_blockers(
    (public._qa35b_consts() ->> 'sid_failval')::uuid);

  perform public._qa35b_true('T-03',
    'M1: herhangi bir dogrulayicidan fail sonucu -> can_promote=false',
    (v ->> 'can_promote')::boolean is false
      and (v ->> 'failing_validation_exists')::boolean is true
      and v -> 'missing_verification_gates' = '[]'::jsonb
      and exists (
        select 1 from jsonb_array_elements(v -> 'blocking_reasons') b
         where b ->> 'code' = 'failing_validation_result'
      ),
    (v -> 'blocking_reasons')::text);

  -- T-04: high telif riski
  v := private.ai_question_promotion_blockers(
    (public._qa35b_consts() ->> 'sid_copy')::uuid);

  perform public._qa35b_true('T-04',
    'M1: high telif riski (staging=low iken) -> can_promote=false',
    (v ->> 'can_promote')::boolean is false
      and (v ->> 'dangerous_copyright_exists')::boolean is true
      and exists (
        select 1 from jsonb_array_elements(v -> 'blocking_reasons') b
         where b ->> 'code' = 'dangerous_copyright_risk'
      ),
    (v -> 'blocking_reasons')::text);

  -- T-05: 'blocked' telif riski de aynı şekilde bloklar
  update public.copyright_reviews
     set risk_level = 'blocked'
   where staging_question_id = (public._qa35b_consts() ->> 'sid_copy')::uuid;

  v := private.ai_question_promotion_blockers(
    (public._qa35b_consts() ->> 'sid_copy')::uuid);

  perform public._qa35b_true('T-05',
    'M1: blocked telif riski de bloklar',
    (v ->> 'can_promote')::boolean is false
      and (v ->> 'dangerous_copyright_exists')::boolean is true,
    (v -> 'blocking_reasons')::text);

  -- T-06: fail-closed — eksik kapı + fail + telif birlikte
  update public.ai_question_staging
     set copyright_risk_level = 'high'
   where id = (public._qa35b_consts() ->> 'sid_nogate')::uuid;

  insert into public.ai_validation_results (
    staging_question_id, validator_type, validation_type, result, summary, details
  )
  values (
    'b3500000-0000-0000-0000-0000000000a6', 'ai', 'originality', 'fail',
    'QA: fail-closed birlik testi', '{"qa":"combined"}'::jsonb);

  insert into public.copyright_reviews (
    staging_question_id, review_type, risk_level,
    commercial_use_recommendation, evidence, reviewer_type
  )
  values (
    'b3500000-0000-0000-0000-0000000000a6', 'originality', 'blocked',
    'do_not_allow', '{"qa":"combined"}'::jsonb, 'ai');

  v := private.ai_question_promotion_blockers(
    (public._qa35b_consts() ->> 'sid_nogate')::uuid);

  perform public._qa35b_true('T-06',
    'M1: eksik kapı + fail + blocked telif birlikte -> 3 ayri bloklayici',
    (v ->> 'can_promote')::boolean is false
      and (select count(*) from jsonb_array_elements(v -> 'blocking_reasons')) = 3,
    (v -> 'blocking_reasons')::text);

  -- T-07: kapı "rejected" ise de 'verified' değil -> bloklar
  update public.ai_question_quality_runs
     set status = 'rejected'
   where staging_question_id = (public._qa35b_consts() ->> 'sid_idem')::uuid;

  v := private.ai_question_promotion_blockers(
    (public._qa35b_consts() ->> 'sid_idem')::uuid);

  perform public._qa35b_true('T-07',
    'M1: kapı rejected ise verified degildir -> can_promote=false',
    (v ->> 'can_promote')::boolean is false
      and exists (
        select 1 from jsonb_array_elements(v -> 'blocking_reasons') b
         where b ->> 'code' = 'missing_verification_gate'
           and b ->> 'gate' = 'question_quality'
           and b ->> 'status' = 'rejected'
      ),
    (v -> 'blocking_reasons')::text);

  -- T-07 sonrası temizle: bu aday M4 testlerinde kullanılacak
  update public.ai_question_quality_runs
     set status = 'verified'
   where staging_question_id = (public._qa35b_consts() ->> 'sid_idem')::uuid;

end;
$t$;


-- ============================================================
-- M1: APPROVE GERÇEKTEN REDDEDİYOR + questions'A YAZMIYOR
-- ============================================================

select public._qa35b_as((public._qa35b_consts() ->> 'admin_uid')::uuid);

-- T-08: fail sonuçlu aday -> reddedilir
select public._qa35b_expect_msg('T-08',
  'M1: fail dogrulama sonucu olan aday approve REDDEDILIR',
  $sql$select private.review_and_promote_ai_question(
          'b3500000-0000-0000-0000-0000000000a3', 'approve', 'M1 fail testi')$sql$,
  'P0001', '%blocking promotion gates failed%');

-- T-09: high telif riskli aday -> reddedilir
select public._qa35b_expect_msg('T-09',
  'M1: blocked telif riskli aday approve REDDEDILIR',
  $sql$select private.review_and_promote_ai_question(
          'b3500000-0000-0000-0000-0000000000a4', 'approve', 'M1 telif testi')$sql$,
  'P0001', '%blocking promotion gates failed%');

reset role;
select public._qa35b_clear_claims();

-- Bloke edilen iki aday için HİÇBİR yan etki olmamalı
select public._qa35b_true('T-08b',
  'M1: bloklanan adaylara questions/final_review/audit YAZILMADI',
  not exists (select 1 from public.questions
               where question_code like 'AK-AI-%'
                  or id in (select final_question_id
                              from public.ai_question_staging
                             where final_question_id is not null))
    and not exists (select 1 from public.ai_question_final_reviews
                     where staging_question_id in
                       ('b3500000-0000-0000-0000-0000000000a3',
                        'b3500000-0000-0000-0000-0000000000a4'))
    and not exists (select 1 from public.admin_audit_log
                     where entity_id in
                       ('b3500000-0000-0000-0000-0000000000a3',
                        'b3500000-0000-0000-0000-0000000000a4')),
  'fail-closed: hicbir tablo yazilmadi');


-- ============================================================
-- M3 + M4b: APPROVE (temiz aday) — AUDIT ve KATOMİKLİK
-- ============================================================

select public._qa35b_as((public._qa35b_consts() ->> 'admin_uid')::uuid);

do $t$
declare
  v_res jsonb;
  v_qid text;
begin
  -- T-13a: approve cagrisi audit_id donduruyor (yazma SECURITY DEFINER)
  v_res := private.review_and_promote_ai_question(
    (public._qa35b_consts() ->> 'sid_ok')::uuid, 'approve', 'M3 approve testi');

  v_qid := v_res ->> 'question_id';

  perform public._qa35b_true('T-13a',
    'M3: approve audit_id ve question_id dondurur (yazma SECURITY DEFINER ile gerceklesir)',
    v_res ->> 'status' = 'promoted'
      and v_res ->> 'audit_id' is not null
      and v_res ->> 'final_review_id' is not null
      and v_qid is not null
      and v_res ->> 'question_code' is not null
      and (v_res ->> 'is_active')::boolean is false
      and (v_res ->> 'student_visible')::boolean is false
      and (v_res ->> 'automatic_publication_allowed')::boolean is false,
    v_res::text);

  -- T-18: ikinci approve -> already_promoted
  v_res := private.review_and_promote_ai_question(
    (public._qa35b_consts() ->> 'sid_ok')::uuid, 'approve', 'M3 tekrar testi');

  perform public._qa35b_true('T-18a',
    'M3: promoted olmus adaya ikinci approve -> already_promoted (yeni karar URETILMEZ)',
    v_res ->> 'status' = 'already_promoted'
      and v_res ->> 'question_id' = v_qid
      and v_res ->> 'audit_id' is null
      and v_res ->> 'final_review_id' is null,
    v_res::text);

end;
$t$;

reset role;
select public._qa35b_clear_claims();

-- ---- Aşağıdaki T-13/T-14/T-18b/T-19a doğrulamaları SUPERUSER olarak
-- ---- yapılır: admin_audit_log / ai_question_final_reviews /
-- ---- questions tablolarında RLS ETKİNLİR ve authenticated rolü
-- ---- satır GÖREMEZ. Bu, beklenen ve doğru güvenlik davranışıdır
-- ---- (yazma SECURITY DEFINER; okuma ayrı yetkili yoldan).
do $t$
declare
  v_sid  uuid := (public._qa35b_consts() ->> 'sid_ok')::uuid;
  v_audit public.admin_audit_log%ROWTYPE;
  v_cnt  integer;
  v_qid  uuid;
begin
  select count(*) into v_cnt
    from public.admin_audit_log
   where entity_id = v_sid and action_code = 'staging_question.approve';
  select * into v_audit
    from public.admin_audit_log
   where entity_id = v_sid and action_code = 'staging_question.approve';

  perform public._qa35b_true('T-13',
    'M3: approve tam olarak 1 audit yazar (aktör + varlık + kod + before/after)',
    v_cnt = 1
      and v_audit.actor_user_id = (public._qa35b_consts() ->> 'admin_uid')::uuid
      and v_audit.entity_type = 'staging_question'
      and v_audit.entity_id = v_sid
      and v_audit.before_data is not null
      and v_audit.after_data is not null,
    format('adet=%s audit_id=%s actor=%s', v_cnt, v_audit.id,
           coalesce(v_audit.actor_user_id::text, '-')));

  select promoted_question_id into v_qid
    from public.ai_question_final_reviews
   where staging_question_id = v_sid and decision = 'approve';

  perform public._qa35b_true('T-14',
    'M3: approve audit after_data karar + yayin kapisi + review notu kaydeder',
    v_audit.after_data ->> 'decision' = 'approve'
      and v_audit.after_data ->> 'staging_status' = 'promoted'
      and (v_audit.after_data ->> 'is_active')::boolean is false
      and (v_audit.after_data ->> 'student_visible')::boolean is false
      and (v_audit.after_data ->> 'production_publication')::boolean is false
      and (v_audit.after_data ->> 'automatic_publication_allowed')::boolean is false
      and v_audit.after_data ->> 'question_id' = v_qid::text
      and v_audit.after_data ->> 'review_notes' = 'M3 approve testi'
      and v_audit.before_data ->> 'staging_status' = 'validating',
    v_audit.after_data::text);

  perform public._qa35b_true('T-18b',
    'M3: already_promoted tekrarinda YENI audit satiri YAZILMADI (hâlâ tekil)',
    (select count(*) from public.admin_audit_log
      where entity_id = v_sid and action_code = 'staging_question.approve') = 1
      and (select count(*) from public.ai_question_final_reviews
            where staging_question_id = v_sid) = 1,
    null);

  perform public._qa35b_true('T-19a',
    'promote sonrasi soru approved + is_active=false (otomatik yayin YOK)',
    exists (
      select 1 from public.questions q
       where q.id = v_qid
         and q.approval_status = 'approved'
         and q.is_active is false
    )
    and (select staging_status from public.ai_question_staging where id = v_sid)
        = 'promoted',
    null);

end;
$t$;


-- ============================================================
-- M2: REQUEST_CHANGES IDEMPOTENCY
-- ============================================================

select public._qa35b_as((public._qa35b_consts() ->> 'admin_uid')::uuid);

do $t$
declare
  v_rc_sid uuid := (public._qa35b_consts() ->> 'sid_rc')::uuid;
  v_first  jsonb;
  v_second jsonb;
  v_third  jsonb;
begin
  -- T-10a: ilk çağrı — karar + audit kimlikleri döner
  v_first := private.review_and_promote_ai_question(
    v_rc_sid, 'request_changes', 'Lutfen secenekleri duzelt');

  perform public._qa35b_true('T-10a',
    'M2: ilk request_changes karar + audit kimligi dondurur',
    v_first ->> 'status' = 'changes_requested'
      and v_first ->> 'final_review_id' is not null
      and v_first ->> 'audit_id' is not null
      and (v_first ->> 'production_publication')::boolean is false
      and v_first ->> 'idempotent_replay' is null,
    v_first::text);

  -- T-11a: ikinci çağrı -> idempotent_replay, AYNI karar kimliği
  v_second := private.review_and_promote_ai_question(
    v_rc_sid, 'request_changes', 'Lutfen secenekleri duzelt');

  perform public._qa35b_true('T-11a',
    'M2: tekrar ayni talep -> idempotent_replay=true ve AYNI final_review_id doner',
    v_second ->> 'status' = 'changes_requested'
      and (v_second ->> 'idempotent_replay')::boolean is true
      and v_second ->> 'final_review_id' = v_first ->> 'final_review_id'
      and v_second ->> 'audit_id' is null,
    v_second::text);

  -- T-12a: üçüncü çağrı da aynı kimliği döner
  v_third := private.review_and_promote_ai_question(
    v_rc_sid, 'request_changes', 'Lutfen secenekleri duzelt');

  perform public._qa35b_true('T-12a',
    'M2: ucuncu tekrar da ayni karari doner (idempotent zincir)',
    v_third ->> 'final_review_id' = v_first ->> 'final_review_id'
      and (v_third ->> 'idempotent_replay')::boolean is true,
    v_third::text);

end;
$t$;

reset role;
select public._qa35b_clear_claims();

-- ---- T-10b/T-11b/T-12b/T-16: SUPERUSER doğrulaması (RLS nedeniyle
-- ---- authenticated rolü bu tabloları GÖREMEZ).
do $t$
declare
  v_sid  uuid := (public._qa35b_consts() ->> 'sid_rc')::uuid;
  v_rc   integer;
  v_aud  integer;
  v_status text;
begin
  select count(*) into v_rc
    from public.ai_question_final_reviews where staging_question_id = v_sid;
  select count(*) into v_aud
    from public.admin_audit_log where entity_id = v_sid;
  select staging_status into v_status
    from public.ai_question_staging where id = v_sid;

  -- Üç kez tıklandı; yalnız BİR karar + BİR audit yazıldı
  perform public._qa35b_true('T-10b',
    'M2: 3 kez tıklamada TEK final_review + TEK audit yazildi',
    v_rc = 1 and v_aud = 1,
    format('final_reviews=%s audit_log=%s', v_rc, v_aud));

  perform public._qa35b_true('T-11b',
    'M2: tekrar YENI final_review veya audit satiri URETMEDI',
    v_rc = 1 and v_aud = 1,
    format('final_reviews=%s audit_log=%s', v_rc, v_aud));

  perform public._qa35b_true('T-12b',
    'M2: staging needs_review olarak kalir (karar degismedi)',
    v_status = 'needs_review'
      and exists (
        select 1 from public.ai_question_final_reviews
         where staging_question_id = v_sid and decision = 'request_changes'
      ),
    'staging_status=' || v_status);

  perform public._qa35b_true('T-16',
    'M3: request_changes tam olarak 1 audit + karar + not kaydi',
    (select count(*) from public.admin_audit_log
      where entity_id = v_sid
        and action_code = 'staging_question.request_changes') = 1
      and exists (
        select 1 from public.admin_audit_log l
         where l.entity_id = v_sid
           and l.after_data ->> 'decision' = 'request_changes'
           and l.after_data ->> 'staging_status' = 'needs_review'
           and l.after_data ->> 'review_notes' = 'Lutfen secenekleri duzelt'
           and l.actor_user_id = (public._qa35b_consts() ->> 'admin_uid')::uuid
      ),
    null);

end;
$t$;



-- ============================================================
-- M3: REJECT + ATOMİKLİK
-- ============================================================

select public._qa35b_as((public._qa35b_consts() ->> 'admin_uid')::uuid);

do $t$
declare
  v_rj_sid uuid := (public._qa35b_consts() ->> 'sid_rj')::uuid;
  v_res    jsonb;
begin
  -- T-15a: reject cagrisi
  v_res := private.review_and_promote_ai_question(
    v_rj_sid, 'reject', 'M3 reject testi');

  perform public._qa35b_true('T-15a',
    'M3: reject karar + audit kimligi dondurur (yayin kapisi kapali)',
    v_res ->> 'status' = 'rejected'
      and v_res ->> 'final_review_id' is not null
      and v_res ->> 'audit_id' is not null
      and (v_res ->> 'production_publication')::boolean is false,
    v_res::text);

end;
$t$;

-- T-15b doğrudan: rejected adaya approve reddedilmeli (P0001)
select public._qa35b_expect_msg('T-15b',
  'rejected adaya approve REDDEDILIR (terminal durum)',
  $sql$select private.review_and_promote_ai_question(
          'b3500000-0000-0000-0000-0000000000a5', 'approve', 'terminal test')$sql$,
  'P0001', '%Rejected staging question cannot be promoted%');

reset role;
select public._qa35b_clear_claims();

-- ---- T-15c: SUPERUSER doğrulaması (RLS)
do $t$
declare
  v_sid uuid := (public._qa35b_consts() ->> 'sid_rj')::uuid;
begin
  perform public._qa35b_true('T-15c',
    'M3: reject tam olarak 1 audit + karar kaydi + staging rejected',
    (select count(*) from public.admin_audit_log
      where entity_id = v_sid
        and action_code = 'staging_question.reject') = 1
      and exists (
        select 1 from public.admin_audit_log l
         where l.entity_id = v_sid
           and l.after_data ->> 'decision' = 'reject'
           and l.after_data ->> 'staging_status' = 'rejected'
           and (l.after_data ->> 'commercial_use_allowed')::boolean is false
           and l.after_data ->> 'review_notes' = 'M3 reject testi'
           and l.actor_user_id = (public._qa35b_consts() ->> 'admin_uid')::uuid
      )
      and (select staging_status from public.ai_question_staging
            where id = v_sid) = 'rejected'
      and (select commercial_use_allowed from public.ai_question_staging
            where id = v_sid) is false
      and (select count(*) from public.ai_question_final_reviews
            where staging_question_id = v_sid and decision = 'reject') = 1
      and (select count(*) from public.ai_validation_results
            where staging_question_id = v_sid
              and validator_type = 'human'
              and result = 'fail') = 1,
    null);

end;
$t$;



-- ============================================================
-- M3: ATOMİKLİK — zorlanan hata sonrası HİÇBİR ŞEY KALICI DEĞİL
--
-- review + audit + validation + batch özeti AYNI transaction'da
-- yazılır. Alt-blok (subtransaction) hata ile geri alınır;
-- hiçbir tablo yazılmış olmamalıdır.
--
-- NOT: role/claims KURULUMU alt-blok DIŞINDADIR; aksi halde
-- SET LOCAL de alt-blokla birlikte geri alınırdı.
-- ============================================================

select public._qa35b_as((public._qa35b_consts() ->> 'admin_uid')::uuid);

do $t$
declare
  v_sid  uuid := (public._qa35b_consts() ->> 'sid_atomic')::uuid;
  v_err  text;
begin
  begin
    perform private.review_and_promote_ai_question(
      v_sid, 'approve', 'M3 atomiklik testi');
    raise exception 'ZORLA_SONRAKI_HATA';
  exception when others then
    v_err := sqlerrm;
  end;

  perform set_config('qa35b.t17_forced_error', coalesce(v_err, ''), true);

end;
$t$;

reset role;
select public._qa35b_clear_claims();

-- ---- T-17: SUPERUSER doğrulaması (RLS)
-- Zorlanan hata authenticated bağlamında üretilir. Ancak
-- ai_question_final_reviews / admin_audit_log / ai_validation_results /
-- questions tablolarına authenticated SELECT verilmemesi bilinçli bir
-- güvenlik kararıdır. Bu nedenle geri alınma doğrulaması, T-15c ile aynı
-- kalıpta, reset role sonrası suite sahibi bağlamında yapılır.
do $t$
declare
  v_sid  uuid := (public._qa35b_consts() ->> 'sid_atomic')::uuid;
  v_err  text := nullif(current_setting('qa35b.t17_forced_error', true), '');
begin
  perform public._qa35b_true('T-17',
    'M3: zorlanan hata sonrasi review+audit+validation+questions HEPSI geri alindi',
    v_err = 'ZORLA_SONRAKI_HATA'
      and not exists (select 1 from public.ai_question_final_reviews
                       where staging_question_id = v_sid)
      and not exists (select 1 from public.admin_audit_log
                       where entity_id = v_sid)
      and not exists (select 1 from public.ai_validation_results
                       where staging_question_id = v_sid
                         and validator_type = 'human')
      and not exists (select 1 from public.questions
                       where question_code like 'AK-AI-%'
                         and id = (select final_question_id
                                     from public.ai_question_staging
                                    where id = v_sid))
      and (select staging_status from public.ai_question_staging
            where id = v_sid) <> 'promoted',
    'zorlanan hata=' || coalesce(v_err, '-'));

end;
$t$;


-- ============================================================
-- M4a: READINESS IDEMPOTENCY
-- ============================================================

select public._qa35b_as((public._qa35b_consts() ->> 'admin_uid')::uuid);

do $t$
declare
  v_sid      uuid := (public._qa35b_consts() ->> 'sid_idem')::uuid;
  v_runs_b   integer;
  v_det_b    integer;
  v_det_a    integer;
  v_runs_a   integer;
begin
  -- İlk çağrı: readiness run + deterministic/overall INSERT
  perform private.evaluate_ai_question_readiness(v_sid);

  select count(*) into v_runs_b from public.ai_question_readiness_runs
   where staging_question_id = v_sid;
  select count(*) into v_det_b from public.ai_validation_results
   where staging_question_id = v_sid
     and validator_type = 'deterministic'
     and validation_type = 'overall';

  -- İkinci ve üçüncü çağrı: UPDATE olmalı, INSERT DEĞİL
  perform private.evaluate_ai_question_readiness(v_sid);
  perform private.evaluate_ai_question_readiness(v_sid);

  select count(*) into v_runs_a from public.ai_question_readiness_runs
   where staging_question_id = v_sid;
  select count(*) into v_det_a from public.ai_validation_results
   where staging_question_id = v_sid
     and validator_type = 'deterministic'
     and validation_type = 'overall';

  perform public._qa35b_true('T-20',
    'M4a: evaluate 3 kez -> readiness_runs TEKIL kalir',
    v_runs_b = 1 and v_runs_a = 1,
    format('runs=%s->%s', v_runs_b, v_runs_a));

  perform public._qa35b_true('T-21',
    'M4a: evaluate 3 kez -> (deterministic,overall) validation TEKIL kalir'
      || ' [038 korumasiz INSERT idi; 039 her kararda cagriyordu]',
    v_det_b = 1 and v_det_a = 1,
    format('deterministic_overall=%s->%s', v_det_b, v_det_a));

end;
$t$;

reset role;
select public._qa35b_clear_claims();

-- T-22: promote tekrarı deterministic satırı çoğaltmaz
-- (approve, readiness'yi bir kez daha çağırır)
do $t$
declare
  v_det integer;
begin
  select count(*) into v_det
    from public.ai_validation_results
   where staging_question_id = (public._qa35b_consts() ->> 'sid_rj')::uuid
     and validator_type = 'deterministic'
     and validation_type = 'overall';

  perform public._qa35b_true('T-22',
    'M4a: reject sonrasi deterministic/overall yine tekil (human ayri)',
    v_det = 1,
    format('deterministic_overall=%s human=%s', v_det,
      (select count(*) from public.ai_validation_results
        where staging_question_id = (public._qa35b_consts() ->> 'sid_rj')::uuid
          and validator_type = 'human')));
end;
$t$;


-- ============================================================
-- M4b: BATCH ÖZETİ — SAYAÇLARIN ANLAMI DEĞİŞMEZ
-- ============================================================

do $t$
declare
  v_batch  uuid := (public._qa35b_consts() ->> 'batch_id')::uuid;
  v_snap   jsonb;
  v_status text;
  v_after  public.candidate_question_batches%ROWTYPE;
  v_sum    jsonb;
begin
  select counters, status into v_snap, v_status
    from public._qa_f35b_batch_snap;

  select * into v_after
    from public.candidate_question_batches b where b.id = v_batch;

  -- Sayaçlar intake gerçeğidir: karar ÖNCESİ ile karar SONRASI
  -- birebir aynıdır; yalnız validation_summary + metadata değişebilir.
  perform public._qa35b_true('T-23',
    'M4b: karar ONCESI/SONRASI intake sayaclari ve status BIREBIR degismedi',
    (to_jsonb(v_after) - 'updated_at' - 'validation_summary' - 'metadata')
        = v_snap
      and v_after.status = v_status
      and v_after.total_items = 2
      and v_after.valid_items = 2
      and v_after.invalid_items = 0
      and v_after.inserted_items = 2
      and v_after.duplicate_items = 0,
    format('total=%s valid=%s invalid=%s inserted=%s duplicate=%s status=%s',
      v_after.total_items, v_after.valid_items, v_after.invalid_items,
      v_after.inserted_items, v_after.duplicate_items, v_after.status));

  -- Karar özeti ayrı alanda, mevcut anahtarlar korunmuş
  v_sum := v_after.validation_summary -> 'human_final_review';

  perform public._qa35b_true('T-24',
    'M4b: karar ozeti validation_summary.human_final_review altinda dogru dagilim',
    v_sum is not null
      and (v_sum ->> 'promoted')::integer = 1
      and (v_sum ->> 'changes_requested_pending')::integer = 1
      and (v_sum ->> 'total_candidates')::integer = 2
      and (v_sum ->> 'undecided')::integer = 0
      and v_sum ->> 'source' = 'ai_question_staging.staging_status',
    coalesce(v_sum::text, '-'));

  -- Mevcut özet anahtarları korunur
  perform public._qa35b_true('T-25',
    'M4b: mevcut validation_summary anahtarlari KORUNUR (received/valid/inserted)',
    v_after.validation_summary ->> 'received' = '2'
      and v_after.validation_summary ->> 'valid' = '2'
      and v_after.validation_summary ->> 'inserted' = '2',
    v_after.validation_summary::text);

  -- Sayaç/satır tutarlılığı ölçülür, sayaç YAZILMAZ
  perform public._qa35b_true('T-26',
    'M4b: intake_total_items ve intake_counters_match_rows GOZLEM olarak yazilir',
    (v_sum ->> 'intake_total_items')::integer = 2
      and (v_sum ->> 'intake_counters_match_rows')::boolean is true,
    format('intake_total_items=%s match=%s',
      v_sum ->> 'intake_total_items', v_sum ->> 'intake_counters_match_rows'));

  -- metadata.human_final_review senkron damgasi
  perform public._qa35b_true('T-27',
    'M4b: metadata.human_final_review senkron damgasi yazildi',
    v_after.metadata -> 'human_final_review' ->> 'source' = 'faz35b_migration_130'
      and (v_after.metadata -> 'human_final_review' ->> 'synced_at') is not null,
    coalesce((v_after.metadata -> 'human_final_review')::text, '-'));

  -- UYDURMA status YAZILMAZ: status CHECK'inde 'promoted' yok
  perform public._qa35b_true('T-28',
    'M4b: uydurma status YAZILMADI (status=ingested kaldi, promoted diye bir status UYDURULMADI)',
    v_after.status = 'ingested'
      and v_after.status <> 'promoted'
      and not exists (
        select 1 from pg_constraint c
         where c.conrelid = 'public.candidate_question_batches'::regclass
           and c.contype = 'c'
           and pg_get_constraintdef(c.oid) ilike '%promoted%'
      ),
    'status=' || v_after.status);

end;
$t$;


-- ============================================================
-- YETKİ: YÜZEY KAPALI + YETKİSİZ ERİŞİM REDDEDİLİR
-- ============================================================

do $t$
declare
  v_leak text;
begin
  -- T-29: anon için EXECUTE YOK
  select string_agg(p.proname, ',') into v_leak
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname in ('ai_question_promotion_blockers',
                       'sync_candidate_batch_review_summary',
                       'review_and_promote_ai_question',
                       'evaluate_ai_question_readiness')
     and has_function_privilege('anon', p.oid, 'EXECUTE');

  perform public._qa35b_true('T-29',
    'Yetki: 130 fonksiyonlarinda anon EXECUTE YOK',
    v_leak is null, coalesce('sizan=' || v_leak, 'sizan=yok'));

  -- T-30: PUBLIC için EXECUTE YOK
  select string_agg(p.proname, ',') into v_leak
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname in ('ai_question_promotion_blockers',
                       'sync_candidate_batch_review_summary',
                       'review_and_promote_ai_question',
                       'evaluate_ai_question_readiness')
     and exists (
       select 1 from pg_catalog.aclexplode(p.proacl) a
        where a.grantee = 0 and a.privilege_type = 'EXECUTE'
     );

  perform public._qa35b_true('T-30',
    'Yetki: 130 fonksiyonlarinda PUBLIC EXECUTE YOK',
    v_leak is null, coalesce('sizan=' || v_leak, 'sizan=yok'));
end;
$t$;

-- T-31: anon çağrı -> EXECUTE-denied
set local role anon;
select public._qa35b_clear_claims();

select public._qa35b_expect('T-31',
  'Yetki: anon private.review_and_promote EXECUTE-denied',
  '42501',
  $sql$select private.review_and_promote_ai_question(
          'b3500000-0000-0000-0000-0000000000a1', 'approve', 'anon denemesi')$sql$);

reset role;
select public._qa35b_clear_claims();

-- T-32: öğrenci reddi
select public._qa35b_as((public._qa35b_consts() ->> 'student_uid')::uuid);

select public._qa35b_expect_msg('T-32',
  'Yetki: admin rolu olmayan ogrenci karar veremez',
  $sql$select private.review_and_promote_ai_question(
          'b3500000-0000-0000-0000-0000000000a1', 'approve', 'ogrenci denemesi')$sql$,
  'P0001', '%Question approval permission required%');

reset role;
select public._qa35b_clear_claims();

-- T-33: questions.approve yetkisi olmayan admin (copyright_reviewer)
select public._qa35b_as((public._qa35b_consts() ->> 'wrong_uid')::uuid);

select public._qa35b_expect_msg('T-33',
  'Yetki: questions.approve yetkisi olmayan admin karar veremez',
  $sql$select private.review_and_promote_ai_question(
          'b3500000-0000-0000-0000-0000000000a1', 'approve', 'yanlis rol denemesi')$sql$,
  'P0001', '%Question approval permission required%');

reset role;
select public._qa35b_clear_claims();

-- T-34: geçersiz karar
select public._qa35b_as((public._qa35b_consts() ->> 'admin_uid')::uuid);

select public._qa35b_expect_msg('T-34',
  'Yetki/sozlesme: gecersiz karar degeri REDDEDILIR',
  $sql$select private.review_and_promote_ai_question(
          'b3500000-0000-0000-0000-0000000000a1', 'publish_now', 'gecersiz karar')$sql$,
  'P0001', '%Invalid final review decision%');

reset role;
select public._qa35b_clear_claims();


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
from public._qa_f35b_results
group by label
order by label;

-- CI run_suite 'summary' turu icin tek satirlik ozet.
-- Bu satir kapilari gevsetmez; basarisizlik sayisini gorunur kilar.
select 'OZET: ' || count(*) filter (where result = 'PASS') || ' PASS / '
            || count(*) filter (where result <> 'PASS') || ' FAIL'
  from public._qa_f35b_results;

rollback;
