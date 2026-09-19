-- ============================================================
-- qa_faz20_candidate_batch_operation_status_local.sql
-- Altın Kalemler - SQL QA Faz 20 (yerel/disposable, rollback'li)
--
-- Kapsam (121_faz20_candidate_batch_operation_status.sql):
--   1. get_candidate_question_batch_operation_status ACL/owner/
--      search_path/ozet
--   2. anon / claimsiz erisim reddedilir (42501: "Kimlik dogrulamasi gerekli.")
--   3. authenticated yetki GIRMEDEN reddedilir (42501 yetki msj)
--   4. authenticated + ai.manage yetkisi ile islem durumu OK
--   5. authenticated + questions.approve yetkisi ile islem durumu OK
--   6. mevcut paket OK: batch + phase + gates + provider + retry
--   7. allowlist temiz: ham error_data / raw_payload / api_key sizmaz;
--      retry.supported=false + reason_key sabittir
--   8. olmayan paket -> P0002 "Aday paketi bulunamadi."
--   9. null id -> 22023 "p_batch_id zorunludur."
--  10. anon/public EXECUTE YOK, authenticated+service_role EXECUTE VAR
--  11. owner=supabase_admin, SECURITY DEFINER, STABLE, search_path=""
--
-- CI UYUMU: detay satirlari once, SON satir yalniz "toplam|gecen|kalan"
-- (kalan=0). Tüm değişiklikler rollback ile geri alınır.
--
-- KOSU: disposable klon (001-121) uzerinde; DOGRULANDI (10/10 PASS,
-- 2026-09-19). Kullanici onayiyla yalniz izole disposable DB'de calisir;
-- ana stack/hosted uzerinde calistirilmaz.
-- ============================================================

begin;

-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR
-- ============================================================

create table public._qa_f20_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_f20_results
  to anon, authenticated, service_role;

create function public._qa_f20_expect(
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
      insert into public._qa_f20_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_f20_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_f20_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_f20_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa_f20_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_f20_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa_f20_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_f20_true(text, text, boolean, text)
  to anon, authenticated, service_role;

-- Auth simulasyon yardimcilari.
--
-- Supabase image 17.6.x auth sözleşmesi:
--   auth.uid()  -> request.jwt.claim.sub
--   auth.role() -> request.jwt.claim.role
-- (auth.uid/role fonksiyonlari bu iki GUC'u okur; yalniz
--  request.jwt.claims ayarlamak yetmez.) Burada üçü de set edilir;
--  claimsiz cagrilar (T-01) hicbir claim GUC'u set etmedigi icin
--  auth.uid() null kalir ve 42501 "Kimlik dogrulamasi gerekli." uyar.
create function public._qa_f20_as_role(p_role text, p_claims text, p_code text)
returns text
language plpgsql
security invoker
as $qa$
declare
  v_out text;
  v_claims jsonb;
begin
  v_claims := coalesce(nullif(p_claims, '')::jsonb, '{}'::jsonb);
  execute format('set local role %I', p_role);
  perform set_config('request.jwt.claims', p_claims, true);
  perform set_config('request.jwt.claim.sub', coalesce(v_claims->>'sub', ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_claims->>'role', ''), true);
  execute p_code into v_out;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  execute 'reset role';
  return coalesce(v_out, '');
end;
$qa$;

grant execute
  on function public._qa_f20_as_role(text, text, text)
  to anon, authenticated, service_role;

-- Yetkili admin kullanicilari (deterministik QA uuid'leri).
-- auth.users onay kolonu bu disposable image sekmesinde 'confirmed_at'
-- olarak gelir (email_confirmed_at bu image'ta yok; migration'larda
-- da gecmez). Insert bu sekemaya uyarlandi.
insert into auth.users
  (id, aud, role, email, encrypted_password, confirmed_at,
   raw_user_meta_data, created_at, updated_at)
values
  ('99999999-9999-9999-9999-000000000111', 'authenticated', 'authenticated',
   'qa-faz20-admin-a@e2e.test', '', now(),
   '{"nickname":"QA_Faz20_Admin_A"}'::jsonb, now(), now()),
  ('99999999-9999-9999-9999-000000000222', 'authenticated', 'authenticated',
   'qa-faz20-admin-b@e2e.test', '', now(),
   '{"nickname":"QA_Faz20_Admin_B"}'::jsonb, now(), now())
on conflict (id) do nothing;

insert into public.admin_user_roles (user_id, role_id, assigned_by, assigned_at)
select '99999999-9999-9999-9999-000000000111', r.id, '99999999-9999-9999-9999-000000000111', now()
  from public.admin_roles r
 where r.role_code = 'super_admin';

insert into public.admin_user_roles (user_id, role_id, assigned_by, assigned_at)
select '99999999-9999-9999-9999-000000000222', r.id, '99999999-9999-9999-9999-000000000222', now()
  from public.admin_roles r
 where r.role_code = 'question_reviewer';

-- ============================================================
-- TESTLER
-- ============================================================

do $blk$
declare
  v_json jsonb;
  v_ok   boolean;
  v_id   uuid := '7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3'::uuid;
begin

  -- T-01: claimsiz (jwt yok) -> 42501 "Kimlik dogrulamasi gerekli."
  perform public._qa_f20_expect(
    'T-01',
    'claimsiz erisim reddedilir (42501)',
    '42501',
    'select public.get_candidate_question_batch_operation_status(null::uuid)');

  -- T-02: authenticated yetki GIRMEDEN -> 42501 yetki msj
  perform public._qa_f20_expect(
    'T-02',
    'authenticated yetkisiz reddedilir (42501)',
    '42501',
    'select public._qa_f20_as_role(''authenticated'',
      ''{"sub":"99999999-9999-9999-9999-000000000333","role":"authenticated"}'',
      ''select public.get_candidate_question_batch_operation_status(NULL::uuid)::text'')');

  -- T-03: authenticated + super_admin (ai.manage) -> islem durumu OK
  v_json := public._qa_f20_as_role('authenticated',
    '{"sub":"99999999-9999-9999-9999-000000000111","role":"authenticated"}',
    format('select public.get_candidate_question_batch_operation_status(%L)::text', v_id));
  if v_json is not null and v_json::text <> '' then
    v_json := v_json::jsonb;
  else
    v_json := null::jsonb;
  end if;

  v_ok := v_json is not null
      and (v_json->'batch') is not null
      and (v_json->'phase') is not null
      and (v_json->'phase'->'candidate_counts') is not null
      and (v_json->'gates') is not null
      and (v_json->'provider') is not null
      and (v_json->'retry') is not null
      and (v_json->'gates'->'answer_verification') is not null;

  perform public._qa_f20_true('T-03a', 'ai.manage islem durumu: batch/phase/gates/provider/retry',
    v_ok, 'json=' || left(coalesce(v_json::text, 'NULL'), 160));

  -- T-03b: retry.supported=false + reason_key sabit
  v_ok := v_json->'retry'->>'supported' = 'false'
      and v_json->'retry'->>'reason_key' = 'gate_retry_not_supported';
  perform public._qa_f20_true('T-03b', 'retry.supported=false + gate_retry_not_supported',
    v_ok, '');

  -- T-03c: allowlist temiz (ham error_data/raw_payload/api_key yok; waiting_* gecerli)
  v_ok := not (v_json::text like '%raw_payload%')
      and not (lower(v_json::text) like '%api_key%')
      and not (v_json::text like '%validation_errors%')
      and v_json::text like '%waiting_solver_1%'
      and v_json::text like '%waiting_reviewer_1%'
      and v_json->'provider'->>'has_batch_error_data' in ('true', 'false');
  perform public._qa_f20_true('T-03c', 'allowlist temiz + waiting_* alanlari mevcut',
    v_ok, '');

  -- T-04: authenticated + question_reviewer (questions.approve) -> OK
  v_json := public._qa_f20_as_role('authenticated',
    '{"sub":"99999999-9999-9999-9999-000000000222","role":"authenticated"}',
    format('select public.get_candidate_question_batch_operation_status(%L)::text', v_id));
  perform public._qa_f20_true('T-04', 'authenticated + question_reviewer (questions.approve) OK',
    v_json is not null and (v_json::jsonb->'batch') is not null,
    'json=' || left(coalesce(v_json::text, 'NULL'), 120));

  -- T-05: olmayan paket -> P0002
  perform public._qa_f20_expect(
    'T-05',
    'olmayan paket P0002 (Aday paketi bulunamadi.)',
    'P0002',
    format('select public._qa_f20_as_role(''authenticated'',
      %L, %L)',
      '{"sub":"99999999-9999-9999-9999-000000000111","role":"authenticated"}',
      'select public.get_candidate_question_batch_operation_status(''aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa''::uuid)::text'));

  -- T-06: null id -> 22023 (yetkili kullaniciyla)
  perform public._qa_f20_expect(
    'T-06',
    'null id 22023 (p_batch_id zorunludur.)',
    '22023',
    'select public._qa_f20_as_role(''authenticated'',
      ''{"sub":"99999999-9999-9999-9999-000000000111","role":"authenticated"}'',
      ''select public.get_candidate_question_batch_operation_status(null::uuid)::text'')');

  -- T-07: ACL matrisi
  v_ok := not has_function_privilege('anon', 'public.get_candidate_question_batch_operation_status(uuid)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.get_candidate_question_batch_operation_status(uuid)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.get_candidate_question_batch_operation_status(uuid)', 'EXECUTE');
  perform public._qa_f20_true('T-07', 'EXECUTE matrisi: anon yok, authenticated+service_role var',
    v_ok, '');

  -- T-08: owner/security ozellikleri
  select case
           when p.proowner = 'supabase_admin'::regrole and
                p.prosecdef and
                coalesce(p.provolatile, '') = 's' and
                p.proconfig = array['search_path=""']::text[]
           then true else false end
    into v_ok
    from pg_proc p
   where p.proname = 'get_candidate_question_batch_operation_status'
     and p.pronamespace = 'public'::regnamespace;

  perform public._qa_f20_true('T-08', 'owner=supabase_admin, SECURITY DEFINER, STABLE, search_path=""',
    v_ok, '');

end;
$blk$;

-- ============================================================
-- OZET (CI uyumlu: detay once, son satir toplam|gecen|kalan)
-- ============================================================

reset role;

select label || '|PASS|' || title from public._qa_f20_results where result = 'PASS';
select label || '|FAIL|' || coalesce(detail, title) from public._qa_f20_results where result = 'FAIL';

select count(*)
       || '|' || count(*) filter (where result = 'PASS')
       || '|' || count(*) filter (where result = 'FAIL')
  from public._qa_f20_results;

drop function public._qa_f20_as_role(text, text, text);
drop function public._qa_f20_true(text, text, boolean, text);
drop function public._qa_f20_expect(text, text, text, text);
drop table public._qa_f20_results;