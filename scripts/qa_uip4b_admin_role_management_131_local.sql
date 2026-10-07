-- ============================================================
-- scripts/qa_uip4b_admin_role_management_131_local.sql
-- Altın Kalemler — Migration 131 (UI-P4B) yerel QA suite
--
-- Kapsam: UI-P4A'da kanıtlanan G1/G3/G4/G5 açıklarının
-- append-only kapanışının saldırı-odaklı sözleşme kanıtı.
--
--   DML kapama        T-01..T-09 : anon/authenticated/super-admin
--                                 ham INSERT/UPDATE/DELETE → RED
--   RPC yetki kapısı  T-10..T-14 : anon/öğrenci/non-super → RED
--   Self-scope        T-15..T-16 : süper-admin kendine → RED
--   Kategorik yasak   T-17..T-18 : super_admin hedef rol → RED
--                                 (son-admin koruması dahil)
--   Başarı + audit    T-20..T-23 : atama → TEK audit; replay →
--                                 idempotent, audit çoğalmaz
--   Revoke + audit    T-24..T-26 : kaldırma → TEK audit; replay
--   Parametre dağar   T-27..T-30 : uydurma rol / olmayan hedef /
--                                 inactive rol → RED, DB değişmez
--   UI-P2A koruması   T-31..T-33 : mevcut izin zinciri bozulmaz
--   Grant invarıant   T-34..T-36 : anon/PUBLIC EXECUTE sızıntısı yok
--
-- Çalıştırma (disposable DB, migration 001-131 uygulanmış):
--   docker cp scripts/qa_uip4b_admin_role_management_131_local.sql <db>:/tmp/
--   docker exec <db> psql -U supabase_admin -d postgres \
--          -v ON_ERROR_STOP=1 -f /tmp/qa_uip4b_admin_role_management_131_local.sql
--
-- Güvence: tüm suite TEK TRANSACTION içinde çalışır ve sonunda
-- ROLLBACK yapılır; hiçbir test artefaktı kalıcı olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUÇ TABLOSU + YARDIMCILAR (qa_faz35_130 kanonik deseni)
-- ============================================================

create table public._qa_uip4b_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_uip4b_results
  to anon, authenticated, service_role;

create function public._qa_uip4b_expect(
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
      insert into public._qa_uip4b_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_uip4b_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_uip4b_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_uip4b_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa_uip4b_expect_msg(
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
    insert into public._qa_uip4b_results
    values (p_label, p_title, 'FAIL', 'hata beklenmisti ama uygulandi');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if v_state = p_state and upper(v_msg) like upper(p_msg_pattern) then
      insert into public._qa_uip4b_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | mesaj eslesti');
    else
      insert into public._qa_uip4b_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state || ' beklenen=' || p_state ||
              ' | msg=' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa_uip4b_true(
  p_label text, p_title text, p_ok boolean, p_detail text default null
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_uip4b_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

create function public._qa_uip4b_as(p_uid uuid)
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

create function public._qa_uip4b_clear_claims()
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
  on function public._qa_uip4b_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_uip4b_clear_claims()
  to anon, authenticated, service_role;

grant execute
  on function public._qa_uip4b_expect_msg(text, text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_uip4b_true(text, text, boolean, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_uip4b_as(uuid)
  to anon, authenticated, service_role;


-- ============================================================
-- SABİTLER (suite'e özgü UUID uzayı; qa_f35b b35... uzayından ayrık)
-- ============================================================

create or replace function public._qa_uip4b_consts()
returns jsonb language sql as $qa$
select jsonb_build_object(
  'super_uid',     '4b130000-0000-0000-0000-000000000001'::uuid,
  'reviewer_uid',  '4b130000-0000-0000-0000-000000000002'::uuid,
  'student_uid',   '4b130000-0000-0000-0000-000000000003'::uuid,
  'target_uid',    '4b130000-0000-0000-0000-000000000004'::uuid,
  'target2_uid',   '4b130000-0000-0000-0000-000000000005'::uuid,
  'super2_uid',    '4b130000-0000-0000-0000-000000000006'::uuid,
  'ghost_uid',     '4b130000-0000-0000-0000-0000000000ff'::uuid
);
$qa$;


-- ============================================================
-- FİXTURE (rollback ile silinecek)
--   super:    super_admin ataması (disposable'da güvenli test süper-admin'i)
--   reviewer: question_reviewer (users.manage YOK; UI-P2A izinleri var)
--   student:  admin rolü yok
--   target:   rolesiz gerçek auth kullanıcısı (atama/revoke hedefi)
--   target2:  rolesiz gerçek auth kullanıcısı (parametre hedefi)
-- ============================================================

insert into auth.users (id, email) values
  ('4b130000-0000-0000-0000-000000000001', 'qa-4b-super@test.local'),
  ('4b130000-0000-0000-0000-000000000002', 'qa-4b-reviewer@test.local'),
  ('4b130000-0000-0000-0000-000000000003', 'qa-4b-ogrenci@test.local'),
  ('4b130000-0000-0000-0000-000000000004', 'qa-4b-target@test.local'),
  ('4b130000-0000-0000-0000-000000000005', 'qa-4b-target2@test.local');

insert into public.admin_user_roles (user_id, role_id)
select '4b130000-0000-0000-0000-000000000001'::uuid,
       (select id from public.admin_roles where role_code = 'super_admin');

insert into public.admin_user_roles (user_id, role_id)
select '4b130000-0000-0000-0000-000000000002'::uuid,
       (select id from public.admin_roles where role_code = 'question_reviewer');


-- ============================================================
-- DML YÜZEYİ: HAM POSTGREST YAZIMLARI REDDEDİLİR
-- (131'den ÖNCE bu yüzden G1/G2 saldırısı mümkündü)
-- ============================================================

do $t$
declare
  v_priv_ok boolean;
begin
  -- T-01: GRANT katmanı — authenticated INSERT/UPDATE/DELETE kapalı
  select has_table_privilege('authenticated', 'public.admin_user_roles', 'INSERT')
      or has_table_privilege('authenticated', 'public.admin_user_roles', 'UPDATE')
      or has_table_privilege('authenticated', 'public.admin_user_roles', 'DELETE')
    into v_priv_ok;

  perform public._qa_uip4b_true('T-01',
    'DML: authenticated admin_user_roles INSERT/UPDATE/DELETE ayricaligi KAPALI',
    v_priv_ok is false,
    'has_table_privilege ölçümü');

  -- T-02: GRANT katmanı — anon INSERT/UPDATE/DELETE kapalı
  select has_table_privilege('anon', 'public.admin_user_roles', 'INSERT')
      or has_table_privilege('anon', 'public.admin_user_roles', 'UPDATE')
      or has_table_privilege('anon', 'public.admin_user_roles', 'DELETE')
    into v_priv_ok;

  perform public._qa_uip4b_true('T-02',
    'DML: anon admin_user_roles INSERT/UPDATE/DELETE ayricaligi KAPALI',
    v_priv_ok is false,
    'has_table_privilege ölçümü');

  -- T-03: GRANT katmanı — admin_role_permissions DML kapalı
  select has_table_privilege('authenticated', 'public.admin_role_permissions', 'INSERT')
      or has_table_privilege('authenticated', 'public.admin_role_permissions', 'DELETE')
    into v_priv_ok;

  perform public._qa_uip4b_true('T-03',
    'DML: authenticated admin_role_permissions INSERT/DELETE ayricaligi KAPALI',
    v_priv_ok is false,
    'has_table_privilege ölçümü');

  -- T-04: SELECT korunur (own-roles sözleşmesi)
  perform public._qa_uip4b_true('T-04',
    'DML: authenticated SELECT ayricaligi KORUNUR (RLS ile satır görünümü)',
    has_table_privilege('authenticated', 'public.admin_user_roles', 'SELECT')
      and has_table_privilege('authenticated', 'public.admin_roles', 'SELECT'),
    null);

  -- T-05: FOR ALL politikaları gerçekten gitti; yalnız own-roles SELECT kaldı
  perform public._qa_uip4b_true('T-05',
    'DML: admin_user_roles üzerinde TEK politika kaldı (own-roles SELECT)',
    (select count(*) from pg_policies
      where schemaname='public' and tablename='admin_user_roles') = 1
      and (select count(*) from pg_policies
            where schemaname='public' and tablename='admin_user_roles'
              and cmd in ('ALL', 'INSERT', 'UPDATE', 'DELETE')) = 0,
    (select string_agg(policyname || ':' || cmd, ',') from pg_policies
      where schemaname='public' and tablename='admin_user_roles'));

end;
$t$;

-- T-06: öğrenci bağlamında ham INSERT → reddedilir
select public._qa_uip4b_as((public._qa_uip4b_consts() ->> 'student_uid')::uuid);

select public._qa_uip4b_expect('T-06',
  'DML: öğrenci bağlamında admin_user_roles ham INSERT → RED',
  '42501',
  $sql$insert into public.admin_user_roles (user_id, role_id)
           values ('4b130000-0000-0000-0000-000000000004'::uuid,
                   (select id from public.admin_roles
                     where role_code='content_admin'))$sql$);

reset role;
select public._qa_uip4b_clear_claims();

-- T-07: super-admin bağlamında bile ham INSERT → reddedilir
-- (G1 kapandıktan sonra EN YETKİLİ admin dahi REST'ten yazamaz)
select public._qa_uip4b_as((public._qa_uip4b_consts() ->> 'super_uid')::uuid);

select public._qa_uip4b_expect('T-07',
  'DML: super-admin bağlamında bile ham INSERT → RED (yazım yalnız RPC)',
  '42501',
  $sql$insert into public.admin_user_roles (user_id, role_id)
           values ('4b130000-0000-0000-0000-000000000004'::uuid,
                   (select id from public.admin_roles
                     where role_code='content_admin'))$sql$);

reset role;
select public._qa_uip4b_clear_claims();

-- T-08: ham UPDATE → reddedilir (öğrenci bağlamı)
select public._qa_uip4b_as((public._qa_uip4b_consts() ->> 'student_uid')::uuid);

select public._qa_uip4b_expect('T-08',
  'DML: ham UPDATE admin_user_roles → RED',
  '42501',
  $sql$update public.admin_user_roles set role_id = role_id$sql$);

reset role;
select public._qa_uip4b_clear_claims();

-- T-09: ham DELETE → reddedilir (öğrenci bağlamı)
select public._qa_uip4b_as((public._qa_uip4b_consts() ->> 'student_uid')::uuid);

select public._qa_uip4b_expect('T-09',
  'DML: ham DELETE admin_user_roles → RED',
  '42501',
  $sql$delete from public.admin_user_roles$sql$);

reset role;
select public._qa_uip4b_clear_claims();


-- ============================================================
-- RPC YETKİ KAPISI
-- ============================================================

-- T-10: anon RPC → EXECUTE yok (PUBLIC/anon revoke)
set local role anon;
select public._qa_uip4b_clear_claims();

select public._qa_uip4b_expect('T-10',
  'RPC: anon assign_admin_role EXECUTE-denied',
  '42501',
  $sql$select public.assign_admin_role(
         '4b130000-0000-0000-0000-000000000004'::uuid, 'content_admin')$sql$);

reset role;
select public._qa_uip4b_clear_claims();

-- T-11: anon revoke RPC → EXECUTE yok
set local role anon;
select public._qa_uip4b_clear_claims();

select public._qa_uip4b_expect('T-11',
  'RPC: anon revoke_admin_role EXECUTE-denied',
  '42501',
  $sql$select public.revoke_admin_role(
         '4b130000-0000-0000-0000-000000000002'::uuid, 'question_reviewer')$sql$);

reset role;
select public._qa_uip4b_clear_claims();

-- T-12: öğrenci RPC → P0001 (super admin gerekir)
select public._qa_uip4b_as((public._qa_uip4b_consts() ->> 'student_uid')::uuid);

select public._qa_uip4b_expect_msg('T-12',
  'RPC: admin rolü olmayan öğrenci rol atayamaz',
  $sql$select public.assign_admin_role(
         '4b130000-0000-0000-0000-000000000004'::uuid, 'content_admin')$sql$,
  'P0001', '%requires super admin%');

reset role;
select public._qa_uip4b_clear_claims();

-- T-13: question_reviewer (süper olmayan admin) → RED
select public._qa_uip4b_as((public._qa_uip4b_consts() ->> 'reviewer_uid')::uuid);

select public._qa_uip4b_expect_msg('T-13',
  'RPC: question_reviewer (süper olmayan admin) rol atayamaz',
  $sql$select public.assign_admin_role(
         '4b130000-0000-0000-0000-000000000004'::uuid, 'content_admin')$sql$,
  'P0001', '%requires super admin%');

reset role;
select public._qa_uip4b_clear_claims();

-- T-14: süper olmayan aktörün revoke'u da RED
select public._qa_uip4b_as((public._qa_uip4b_consts() ->> 'reviewer_uid')::uuid);

select public._qa_uip4b_expect_msg('T-14',
  'RPC: question_reviewer rol kaldıramaz',
  $sql$select public.revoke_admin_role(
         '4b130000-0000-0000-0000-000000000004'::uuid, 'content_admin')$sql$,
  'P0001', '%requires super admin%');

reset role;
select public._qa_uip4b_clear_claims();


-- ============================================================
-- SELF-SCOPE + KATEGORİK YASAK
-- ============================================================

do $t$
begin
  perform public._qa_uip4b_as('4b130000-0000-0000-0000-000000000001'::uuid);

  -- T-15: süper-admin KENDİNE operasyonel rol atayamaz
  perform public._qa_uip4b_expect_msg('T-15',
    'Self: süper-admin kendine content_admin ATAYAMAZ',
    $sql$select public.assign_admin_role(
           '4b130000-0000-0000-0000-000000000001'::uuid, 'content_admin')$sql$,
    'P0001', '%cannot change their own admin roles%');

  -- T-16: süper-admin kendi süper-admin rolünü KALDIRAMAZ (self-scope)
  perform public._qa_uip4b_expect_msg('T-16',
    'Self: süper-admin kendi rolünü kaldıramaz',
    $sql$select public.revoke_admin_role(
           '4b130000-0000-0000-0000-000000000001'::uuid, 'super_admin')$sql$,
    'P0001', '%cannot change their own admin roles%');

  -- T-17: süper-admin BAŞKASINA super_admin ATAYAMAZ (kategorik yasak)
  perform public._qa_uip4b_expect_msg('T-17',
    'Kategorik: süper-admin başkasına super_admin ATAYAMAZ',
    $sql$select public.assign_admin_role(
           '4b130000-0000-0000-0000-000000000004'::uuid, 'super_admin')$sql$,
    'P0001', '%super admin role cannot be assigned%');

end;
$t$;

reset role;
select public._qa_uip4b_clear_claims();

-- T-18: İKİ süper-admin varken bile, diğer süper-adminin super_admin
-- rolü RPC yoluyla kaldırılamaz (kategorik yasak; son-admin koruması
-- sayaç-tabanlı korumadan güçlüdür — son süper-admin her koşulda
-- kaldırılamaz).
do $t$
declare
  v_res jsonb;
  v_err text;
begin
  -- süper-admin #2 fixture
  insert into auth.users (id, email) values
    ('4b130000-0000-0000-0000-000000000006', 'qa-4b-super2@test.local');
  insert into public.admin_user_roles (user_id, role_id)
  select '4b130000-0000-0000-0000-000000000006'::uuid,
         (select id from public.admin_roles where role_code = 'super_admin');

  perform public._qa_uip4b_as('4b130000-0000-0000-0000-000000000001'::uuid);

  begin
    v_res := public.revoke_admin_role(
      '4b130000-0000-0000-0000-000000000006'::uuid, 'super_admin');

    perform public._qa_uip4b_true('T-18',
      'Kategorik: iki süper-admin varken bile super_admin kaldırılamaz',
      false, 'reddedilmedi — G3 kategorik yasak sızıntı: ' || v_res::text);

  exception when others then
    get stacked diagnostics v_err = message_text;
    perform public._qa_uip4b_true('T-18',
      'Kategorik: iki süper-admin varken bile super_admin kaldırılamaz',
      upper(v_err) like upper('%super admin role cannot be%'),
      'mesaj=' || left(v_err, 160));
  end;
end;
$t$;

reset role;
select public._qa_uip4b_clear_claims();


-- ============================================================
-- BAŞARI + AUDIT + IDEMPOTENCY
-- ============================================================

do $t$
declare
  v_res  jsonb;
begin
  perform public._qa_uip4b_as('4b130000-0000-0000-0000-000000000001'::uuid);

  -- T-20: atama → 'assigned' + audit_id döner
  v_res := public.assign_admin_role(
    '4b130000-0000-0000-0000-000000000004'::uuid, 'content_admin');

  perform public._qa_uip4b_true('T-20',
    'Başarı: content_admin ataması assigned döner + audit_id üretir',
    v_res ->> 'status' = 'assigned'
      and v_res ->> 'audit_id' is not null
      and v_res ->> 'role_code' = 'content_admin'
      and v_res ->> 'target_user_id' = '4b130000-0000-0000-0000-000000000004',
    v_res::text);

  -- T-21: replay → already_assigned, audit_id NULL
  v_res := public.assign_admin_role(
    '4b130000-0000-0000-0000-000000000004'::uuid, 'content_admin');

  perform public._qa_uip4b_true('T-21',
    'İdepotent: aynı atama replay → already_assigned, YENİ audit ÜRETMEZ',
    v_res ->> 'status' = 'already_assigned'
      and v_res ->> 'audit_id' is null,
    v_res::text);

end;
$t$;

reset role;
select public._qa_uip4b_clear_claims();

-- T-22 + T-23: süperuser turu (RLS) — audit içeriği + tekillik
do $t$
declare
  v_cnt integer;
  v_aud public.admin_audit_log%ROWTYPE;
begin
  select count(*) into v_cnt
    from public.admin_audit_log
   where entity_id = '4b130000-0000-0000-0000-000000000004'::uuid
     and action_code = 'admin_user_role.assign';

  perform public._qa_uip4b_true('T-22',
    'Audit: atama TEK audit satırı üretti (replay çoğaltmadı)',
    v_cnt = 1,
    format('assign_audit=%s', v_cnt));

  select * into v_aud
    from public.admin_audit_log
   where entity_id = '4b130000-0000-0000-0000-000000000004'::uuid
     and action_code = 'admin_user_role.assign';

  perform public._qa_uip4b_true('T-23',
    'Audit: aktör + hedef + before/after + zaman tam',
    v_aud.actor_user_id = '4b130000-0000-0000-0000-000000000001'::uuid
      and v_aud.entity_type = 'admin_user_role'
      and v_aud.before_data -> 'role_codes' = '[]'::jsonb
      and v_aud.after_data ->> 'added_role' = 'content_admin'
      and v_aud.after_data -> 'role_codes' ? 'content_admin'
      and v_aud.performed_at is not null,
    v_aud.after_data::text);
end;
$t$;


-- ============================================================
-- REVOKE + AUDIT
-- ============================================================

do $t$
declare
  v_res jsonb;
begin
  perform public._qa_uip4b_as('4b130000-0000-0000-0000-000000000001'::uuid);

  -- T-24: kaldırma → 'revoked' + audit_id
  v_res := public.revoke_admin_role(
    '4b130000-0000-0000-0000-000000000004'::uuid, 'content_admin');

  perform public._qa_uip4b_true('T-24',
    'Revoke: content_admin kaldırma revoked döner + audit_id üretir',
    v_res ->> 'status' = 'revoked'
      and v_res ->> 'audit_id' is not null,
    v_res::text);

  -- T-25: replay → already_revoked, audit YOK
  v_res := public.revoke_admin_role(
    '4b130000-0000-0000-0000-000000000004'::uuid, 'content_admin');

  perform public._qa_uip4b_true('T-25',
    'İdepotent: aynı kaldırma replay → already_revoked, YENİ audit ÜRETMEZ',
    v_res ->> 'status' = 'already_revoked'
      and v_res ->> 'audit_id' is null,
    v_res::text);

end;
$t$;

reset role;
select public._qa_uip4b_clear_claims();

do $t$
declare
  v_assign integer;
  v_revoke integer;
begin
  select count(*) into v_revoke
    from public.admin_audit_log
   where entity_id = '4b130000-0000-0000-0000-000000000004'::uuid
     and action_code = 'admin_user_role.revoke';

  select count(*) into v_assign
    from public.admin_audit_log
   where entity_id = '4b130000-0000-0000-0000-000000000004'::uuid
     and action_code = 'admin_user_role.assign';

  perform public._qa_uip4b_true('T-26',
    'Audit: revoke TEK satır + hedefin ataması gerçekten kalktı',
    v_revoke = 1
      and v_assign = 1
      and not exists (
        select 1 from public.admin_user_roles
         where user_id = '4b130000-0000-0000-0000-000000000004'::uuid),
    format('assign=%s revoke=%s', v_assign, v_revoke));
end;
$t$;


-- ============================================================
-- PARAMETRE / VERİ DAĞARCIĞI (DB değişmez)
-- ============================================================

do $t$
declare
  v_aud_before integer;
begin
  select count(*) into v_aud_before from public.admin_audit_log;

  -- inactive rol fixture'ı (süperuser bağlamında; T-30 sonrası zaten
  -- ROLLBACK var)
  update public.admin_roles
     set is_active = false
   where role_code = 'copyright_reviewer';

  perform public._qa_uip4b_as('4b130000-0000-0000-0000-000000000001'::uuid);

  -- T-27: uydurma rol kodu → RED
  perform public._qa_uip4b_expect_msg('T-27',
    'Dağarcık: uydurma rol kodu REDDEDİLİR',
    $sql$select public.assign_admin_role(
           '4b130000-0000-0000-0000-000000000005'::uuid, 'god_mode')$sql$,
    'P0001', '%Invalid admin role code%');

  -- T-28: olmayan hedef → RED
  perform public._qa_uip4b_expect_msg('T-28',
    'Dağarcık: auth.users''ta olmayan hedef REDDEDİLİR',
    $sql$select public.assign_admin_role(
           '4b130000-0000-0000-0000-0000000000ff'::uuid, 'content_admin')$sql$,
    'P0001', '%Target user not found%');

  -- T-29: inactive (is_active=false) rol → RED
  perform public._qa_uip4b_expect_msg('T-29',
    'Dağarcık: inactive rol REDDEDİLİR',
    $sql$select public.assign_admin_role(
           '4b130000-0000-0000-0000-000000000005'::uuid,
           'copyright_reviewer')$sql$,
    'P0001', '%Invalid admin role code%');

  reset role;
  perform public._qa_uip4b_clear_claims();

  -- T-30: bu reddedilen çağrılar hiçbir atama/audit ÜRETMEZ
  perform public._qa_uip4b_true('T-30',
    'Fail-closed: reddedilen çağrılar DB''yi değiştirmedi (audit/atama yok)',
    (select count(*) from public.admin_audit_log) = v_aud_before
      and not exists (select 1 from public.admin_user_roles
                       where user_id = '4b130000-0000-0000-0000-000000000005'::uuid),
    format('audit=%s→%s', v_aud_before,
           (select count(*) from public.admin_audit_log)));
end;
$t$;


-- ============================================================
-- UI-P2A / MEVCUT İZİN ZİNCİRİ KORUNUR
-- ============================================================

do $t$
begin
  -- T-31: question_reviewer'ın UI-P2A izinleri bozulmadı
  perform public._qa_uip4b_as('4b130000-0000-0000-0000-000000000002'::uuid);

  perform public._qa_uip4b_true('T-31',
    'UI-P2A: question_reviewer questions.approve + view izinleri KORUNDU',
    private.current_user_has_admin_permission('questions.approve') is true
      and private.current_user_has_admin_permission('questions.view') is true
      and private.current_user_has_admin_permission('users.manage') is false,
    null);

  reset role;
  perform public._qa_uip4b_clear_claims();

  -- T-32: süper-admin bypass davranışı korundu
  perform public._qa_uip4b_as('4b130000-0000-0000-0000-000000000001'::uuid);

  perform public._qa_uip4b_true('T-32',
    'UI-P2A: süper-admin bypass (tüm izinler) KORUNDU',
    private.current_user_has_admin_permission('audit.view') is true
      and private.current_user_has_admin_permission('users.manage') is true
      and private.is_current_user_super_admin() is true,
    null);

  reset role;
  perform public._qa_uip4b_clear_claims();

  -- T-33: has_admin_permission (SECURITY DEFINER) bozulmadı
  perform public._qa_uip4b_true('T-33',
    'UI-P2A: has_admin_permission hedef-rol join''i KORUNDU',
    private.has_admin_permission(
      '4b130000-0000-0000-0000-000000000002'::uuid, 'questions.approve') is true
      and private.has_admin_permission(
      '4b130000-0000-0000-0000-000000000002'::uuid, 'users.manage') is false,
    null);
end;
$t$;


-- ============================================================
-- GRANT İNVARİYANTLARI (T-34..T-36)
-- ============================================================

do $t$
declare
  v_leak text;
begin
  -- T-34: anon EXECUTE YOK
  select string_agg(p.proname, ',') into v_leak
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where p.proname in ('assign_admin_role', 'revoke_admin_role')
     and has_function_privilege('anon', p.oid, 'EXECUTE');

  perform public._qa_uip4b_true('T-34',
    'Grant: yeni RPC''lerde anon EXECUTE YOK',
    v_leak is null, coalesce('sizan=' || v_leak, 'sizan=yok'));

  -- T-35: PUBLIC EXECUTE YOK
  select string_agg(p.proname, ',') into v_leak
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where p.proname in ('assign_admin_role', 'revoke_admin_role')
     and exists (
       select 1 from pg_catalog.aclexplode(p.proacl) a
        where a.grantee = 0 and a.privilege_type = 'EXECUTE'
     );

  perform public._qa_uip4b_true('T-35',
    'Grant: yeni RPC''lerde PUBLIC EXECUTE YOK',
    v_leak is null, coalesce('sizan=' || v_leak, 'sizan=yok'));

  -- T-36: authenticated EXECUTE VAR (gelecekteki UI'nin yolu)
  select string_agg(p.proname, ',') into v_leak
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('assign_admin_role', 'revoke_admin_role')
     and NOT has_function_privilege('authenticated', p.oid, 'EXECUTE');

  perform public._qa_uip4b_true('T-36',
    'Grant: authenticated EXECUTE KORUNDU (public sarmalayıcıda)',
    v_leak is null, coalesce('eksik=' || v_leak, 'eksik=yok'));
end;
$t$;


-- ============================================================
-- SONUÇ RAPORU
-- ============================================================

select
  label                                                        as test_id,
  case when bool_and(result = 'PASS') then 'PASS' else 'FAIL' end as durum,
  count(*) filter (where result = 'FAIL')                      as alt_fail,
  string_agg(
    case when result = 'PASS' then title
         else title || ' >>> ' || coalesce(detail, '') end,
    ' | ' order by title)                                      as detay
from public._qa_uip4b_results
group by label
order by label;

-- CI run_suite 'summary' turu icin tek satirlik ozet.
select 'OZET: ' || count(*) filter (where result = 'PASS') || ' PASS / '
            || count(*) filter (where result <> 'PASS') || ' FAIL'
  from public._qa_uip4b_results;

rollback;
