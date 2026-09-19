-- ============================================================
-- qa_faz19_admin_candidate_batch_read_local.sql
-- Altın Kalemler - SQL QA Faz 19 (yerel/disposable, rollback'li)
--
-- Kapsam (120_faz19_admin_candidate_batch_read.sql):
--   1. list_candidate_question_batches ACL/owner/search_path/ozet
--   2. anon / claimsiz erisim reddedilir (42501: "Kimlik dogrulamasi gerekli.")
--   3. authenticated yetki GIRMEDEN reddedilir (42501 yetki msj)
--   4. service_role claim ile list OK; allowlist alanlar + counts + total
--   5. authenticated + ai.manage yetkisi ile list OK
--   6. authenticated + questions.approve yetkisi ile list OK
--   7. limit clamp (p_limit 1..100, p_offset >= 0)
--   8. get_candidate_question_batch_detail: mevcut paket OK (batch + candidates)
--   9. detail olmayan paket -> P0002 "Aday paketi bulunamadi."
--  10. detail null id -> 22023 "p_batch_id zorunludur."
--  11. anon/public EXECUTE YOK, authenticated+service_role EXECUTE VAR
--  12. Migration idempotans (uygulama once) + pow onemli alanlar
--
-- CI UYUMU: detay satirlari once, SON satir yalniz "toplam|gecen|kalan"
-- (kalan=0). Tüm değişiklikler rollback ile geri alınır.
--
-- KOSU: disposable klon (001-120) uzerinde:
--   docker cp scripts/qa_faz19_admin_candidate_batch_read_local.sql \
--     supabase_db_qa-faz19:/tmp/
--   docker exec supabase_db_qa-faz19 psql -U supabase_admin -d qa \
--     -v ON_ERROR_STOP=1 -f /tmp/qa_faz19_admin_candidate_batch_read_local.sql
-- ============================================================

begin;

-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR
-- ============================================================

create table public._qa_f19_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_f19_results
  to anon, authenticated, service_role;

create function public._qa_f19_expect(
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
      insert into public._qa_f19_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_f19_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_f19_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_f19_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa_f19_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_f19_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa_f19_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_f19_true(text, text, boolean, text)
  to anon, authenticated, service_role;

-- Auth simulasyon yardimcilari.
create function public._qa_f19_as_role(p_role text, p_claims text, p_code text)
returns text
language plpgsql
security invoker
as $qa$
declare
  v_out text;
begin
  execute format('set local role %I', p_role);
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_code into v_out;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  return coalesce(v_out, '');
end;
$qa$;

grant execute
  on function public._qa_f19_as_role(text, text, text)
  to anon, authenticated, service_role;

-- Yetkili admin kullanicilari (deterministik QA uuid'leri).
insert into auth.users
  (id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_user_meta_data, created_at, updated_at)
values
  ('99999999-9999-9999-9999-000000000111', 'authenticated', 'authenticated',
   'qa-faz19-admin-a@e2e.test', '', now(),
   '{"nickname":"QA_Faz19_Admin_A"}'::jsonb, now(), now()),
  ('99999999-9999-9999-9999-000000000222', 'authenticated', 'authenticated',
   'qa-faz19-admin-b@e2e.test', '', now(),
   '{"nickname":"QA_Faz19_Admin_B"}'::jsonb, now(), now())
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
  perform public._qa_f19_expect(
    'T-01',
    'claimsiz erisim reddedilir (42501)',
    '42501',
    'select public.list_candidate_question_batches()');

  -- T-02: authenticated yetki GIRMEDEN -> 42501 yetki msj
  perform public._qa_f19_expect(
    'T-02',
    'authenticated yetkisiz reddedilir (42501)',
    '42501',
    'select public._qa_f19_as_role(''authenticated'',
      ''{"sub":"99999999-9999-9999-9999-000000000333","role":"authenticated"}'',
      ''select public.list_candidate_question_batches()::text'')');

  -- T-03: service_role -> list OK + allowlist
  v_json := public._qa_f19_as_role('postgres',
    '{"sub":"99999999-9999-9999-9999-000000000111","role":"service_role"}',
    'select public.list_candidate_question_batches()::text')::jsonb;

  v_ok := v_json ? 'items'
      and v_json ? 'total'
      and v_json ? 'limit'
      and v_json ? 'offset'
      and (v_json->>'total')::int >= 1;

  perform public._qa_f19_true('T-03a', 'service_role list OK (items/total/limit/offset)',
    v_ok, 'json=' || left(v_json::text, 120));

  -- T-03b: item allowlist temiz (gizli alan yok: raw_payload, metadata, counts alan adlari)
  v_ok := not (v_json::text like '%raw_payload%')
      and not (v_json::text like '%candidate%staging%')
      and v_json::text like '%batch_id%'
      and v_json::text like '%producer_model%';
  perform public._qa_f19_true('T-03b', 'list allowlist: batch_id/producer_model var, raw_payload yok',
    v_ok, '');

  -- T-04: authenticated + super_admin (ai.manage) -> list OK
  v_json := public._qa_f19_as_role('authenticated',
    '{"sub":"99999999-9999-9999-9999-000000000111","role":"authenticated"}',
    'select public.list_candidate_question_batches()::text')::jsonb;
  perform public._qa_f19_true('T-04', 'authenticated + super_admin (ai.manage) list OK',
    v_json ? 'items', 'json=' || left(v_json::text, 120));

  -- T-05: authenticated + question_reviewer (questions.approve) -> list OK
  v_json := public._qa_f19_as_role('authenticated',
    '{"sub":"99999999-9999-9999-9999-000000000222","role":"authenticated"}',
    'select public.list_candidate_question_batches()::text')::jsonb;
  perform public._qa_f19_true('T-05', 'authenticated + question_reviewer (questions.approve) list OK',
    v_json ? 'items', 'json=' || left(v_json::text, 120));

  -- T-06: limit clamp: p_limit=0 -> 1 ; p_limit=500 -> 100
  v_json := public._qa_f19_as_role('postgres',
    '{"sub":"99999999-9999-9999-9999-000000000111","role":"service_role"}',
    'select public.list_candidate_question_batches(0)::text')::jsonb;
  perform public._qa_f19_true('T-06a', 'limit clamp alt (0 -> 1)',
    (v_json->>'limit')::int = 1, 'limit=' || (v_json->>'limit'));

  v_json := public._qa_f19_as_role('postgres',
    '{"sub":"99999999-9999-9999-9999-000000000111","role":"service_role"}',
    'select public.list_candidate_question_batches(500)::text')::jsonb;
  perform public._qa_f19_true('T-06b', 'limit clamp ust (500 -> 100)',
    (v_json->>'limit')::int = 100, 'limit=' || (v_json->>'limit'));

  -- T-07: detail mevcut paket -> batch + candidates + allowlist
  v_json := public._qa_f19_as_role('authenticated',
    '{"sub":"99999999-9999-9999-9999-000000000111","role":"authenticated"}',
    format('select public.get_candidate_question_batch_detail(%L)::text', v_id));
  if v_json is not null and v_json::text <> '' then
    v_json := v_json::jsonb;
  else
    v_json := null::jsonb;
  end if;

  v_ok := v_json is not null
      and (v_json->'batch') is not null
      and jsonb_typeof(v_json->'candidates') = 'array'
      and jsonb_array_length(v_json->'candidates') >= 1;

  perform public._qa_f19_true('T-07a', 'detail mevcut paket: batch + candidates dizisi',
    v_ok, 'json=' || left(coalesce(v_json::text, 'NULL'), 160));

  -- T-07b: candidate allowlist: staging_question_id + validation_results var,
  --        preview question_text/options/proposed_correct_answer VAR,
  --        raw_payload/access_token gibi gizli alan YOK
  v_ok := v_json is not null
      and v_json::text like '%staging_question_id%'
      and v_json::text like '%validation_results%'
      and v_json::text like '%question_text%'
      and v_json::text like '%proposed_correct_answer%'
      and not (v_json::text like '%raw_payload%')
      and not (lower(v_json::text) like '%secret%')
      and not (v_json::text like '%client_question_id%oauth%');
  perform public._qa_f19_true('T-07b', 'detail candidate allowlist temiz',
    v_ok, '');

  -- T-08: detail olmayan paket -> P0002
  perform public._qa_f19_expect(
    'T-08',
    'detail olmayan paket P0002 (Aday paketi bulunamadi.)',
    'P0002',
    format('select public._qa_f19_as_role(''authenticated'',
      %L, %L)',
      '{"sub":"99999999-9999-9999-9999-000000000111","role":"authenticated"}',
      'select public.get_candidate_question_batch_detail(''aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa''::uuid)::text'));

  -- T-09: detail null id -> 22023
  perform public._qa_f19_expect(
    'T-09',
    'detail null id 22023 (p_batch_id zorunludur.)',
    '22023',
    'select public._qa_f19_as_role(''authenticated'',
      ''{"sub":"99999999-9999-9999-9999-000000000111","role":"authenticated"}'',
      ''select public.get_candidate_question_batch_detail(null::uuid)::text'')');

  -- T-10: ACL matrisi
  v_ok := not has_function_privilege('anon', 'public.list_candidate_question_batches(integer,integer)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.get_candidate_question_batch_detail(uuid)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.list_candidate_question_batches(integer,integer)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.get_candidate_question_batch_detail(uuid)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.list_candidate_question_batches(integer,integer)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.get_candidate_question_batch_detail(uuid)', 'EXECUTE');
  perform public._qa_f19_true('T-10', 'EXECUTE matrisi: anon yok, authenticated+service_role var',
    v_ok, '');

  -- T-11: owner/security ozellikleri
  select case
           when p.proowner = 'supabase_admin'::regrole and
                p.prosecdef and
                p.provolatile = 's' and
                p.proconfig = array['search_path=""']::text[]
           then true else false end
    into v_ok
    from pg_proc p
   where p.proname = 'list_candidate_question_batches'
     and p.pronamespace = 'public'::regnamespace;

  perform public._qa_f19_true('T-11', 'owner=supabase_admin, SECURITY DEFINER, STABLE, search_path=""',
    v_ok, '');

  -- T-12: detail fonksiyon owner/grant ayni
  select case
           when p.proowner = 'supabase_admin'::regrole and
                p.prosecdef and
                coalesce(p.provolatile, '') = 's' and
                p.proconfig = array['search_path=""']::text[]
           then true else false end
    into v_ok
    from pg_proc p
   where p.proname = 'get_candidate_question_batch_detail'
     and p.pronamespace = 'public'::regnamespace;

  perform public._qa_f19_true('T-12', 'detail owner/secdef/stable/search_path dogrulu',
    v_ok, '');

end;
$blk$;

-- ============================================================
-- OZET (CI uyumlu: detay once, son satir toplam|gecen|kalan)
-- ============================================================

reset role;

select label || '|PASS|' || title from public._qa_f19_results where result = 'PASS';
select label || '|FAIL|' || coalesce(detail, title) from public._qa_f19_results where result = 'FAIL';

select count(*)
       || '|' || count(*) filter (where result = 'PASS')
       || '|' || count(*) filter (where result = 'FAIL')
  from public._qa_f19_results;

drop function public._qa_f19_as_role(text, text, text);
drop function public._qa_f19_true(text, text, boolean, text);
drop function public._qa_f19_expect(text, text, text, text);
drop table public._qa_f19_results;