-- ============================================================
-- scripts/qa_faz10b_public_privilege_hardening_local.sql
-- Altin Kalemler - Faz 10B QA (108: public tablo ayrica
-- sertlestirmesi + RPC-only lig okumasi + avatar rate limit)
--
-- Kapsam:
--   T-01..T-11 : TRUNCATE/REFERENCES/TRIGGER yasaği (gercek rol
--                baglami + JWT claims), service_role/postgres yolu
--   T-12..T-18 : RPC-only lig tablolari + get_my_league_ranking
--                allowlist DTO + grade izolasyonu + PII sentineli
--   T-19       : gelecek tablo default ayricalik korumasi
--   T-20       : migration 108 idempotent yeniden uygulama
--   T-21..T-22 : profil/avatar RPC sagligi + deger ayriligi
--   D-01       : pg_default_acl invariant (postgres, public, tablolar)
--   RL-01..07  : avatar rate limit 10/60 davranissal sozlesmesi
--   SD-01..    : SECURITY DEFINER denetimleri (introspection)
--
-- Guvence: tek transaction, sonunda ROLLBACK, kalinti yok.
-- CI uyumlu ozet: son satir "toplam|gecen|kalan" (kalan=0);
-- ayrica "PASS=|FAIL=|SKIP=" satiri acikca uretilir.
-- ============================================================

\set ON_ERROR_STOP on

begin;

create table public._qa10b_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL', 'SKIP')),
  detail text
);

create function public._qa10b_expect(p_label text, p_title text, p_expect text, p_sql text)
returns void language plpgsql security invoker as $qa$
declare v_state text; v_msg text;
begin
  begin
    execute p_sql;
    if p_expect = '' then
      insert into public._qa10b_results values (p_label, p_title, 'PASS', 'uygulandi');
    else
      insert into public._qa10b_results values (p_label, p_title, 'FAIL',
        'hata beklenmisti ama uygulandi; beklenen=' || p_expect);
    end if;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if p_expect <> '' and v_state = p_expect then
      insert into public._qa10b_results values (p_label, p_title, 'PASS',
        'sqlstate=' || v_state);
    else
      insert into public._qa10b_results values (p_label, p_title, 'FAIL',
        'sqlstate=' || v_state || ' beklenen=' || coalesce(nullif(p_expect,''),'-') ||
        ' | ' || left(v_msg, 160));
    end if;
  end;
end;
$qa$;

create function public._qa10b_true(p_label text, p_title text, p_ok boolean, p_detail text default null)
returns void language plpgsql security invoker as $qa$
begin
  insert into public._qa10b_results
  values (p_label, p_title, case when p_ok then 'PASS' else 'FAIL' end, p_detail);
end;
$qa$;

grant select, insert, update, delete on public._qa10b_results to anon, authenticated, service_role;
grant execute on function public._qa10b_expect(text,text,text,text) to anon, authenticated, service_role;
grant execute on function public._qa10b_true(text,text,boolean,text) to anon, authenticated, service_role;

-- ============ FIXTURE ============
-- Ogrenciler (grade: A/B/C=7, D=6, E=8, F/G=9):
--   A gorunur, B gorunur, C GIZLI, F/G rate-limit adanaylari.
-- F ve G grade 9'dadir: A'nin grade-7 lig gorunumunu hicbir
-- senaryoda kirletmezler (avatar/RL testleri izole kalir).
insert into auth.users (id, email) values
  ('7b100000-0000-0000-0000-0000000000a1', 'qa10b-a@test.local'),
  ('7b100000-0000-0000-0000-0000000000b1', 'qa10b-b@test.local'),
  ('7b100000-0000-0000-0000-0000000000c1', 'qa10b-c@test.local'),
  ('7b100000-0000-0000-0000-0000000000d1', 'qa10b-d@test.local'),
  ('7b100000-0000-0000-0000-0000000000e1', 'qa10b-e@test.local'),
  ('7b100000-0000-0000-0000-0000000000f1', 'qa10b-f@test.local'),
  ('7b100000-0000-0000-0000-0000000000f2', 'qa10b-g@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('7b100000-0000-0000-0000-0000000000a1', 7, 'QA10B-NICK-A'),
  ('7b100000-0000-0000-0000-0000000000b1', 7, 'QA10B-NICK-B'),
  ('7b100000-0000-0000-0000-0000000000c1', 7, 'QA10B-NICK-C'),
  ('7b100000-0000-0000-0000-0000000000d1', 6, 'QA10B-NICK-D'),
  ('7b100000-0000-0000-0000-0000000000e1', 8, 'QA10B-NICK-E'),
  ('7b100000-0000-0000-0000-0000000000f1', 9, 'QA10B-NICK-F'),
  ('7b100000-0000-0000-0000-0000000000f2', 9, 'QA10B-NICK-G');

insert into public.student_public_profiles
  (user_id, nickname, grade_level, avatar_key, is_visible) values
  ('7b100000-0000-0000-0000-0000000000a1', 'QA10B-NICK-A', 7, 'qa10b-av-a', true),
  ('7b100000-0000-0000-0000-0000000000b1', 'QA10B-NICK-B', 7, 'qa10b-av-b', true),
  ('7b100000-0000-0000-0000-0000000000c1', 'QA10B-NICK-C', 7, 'qa10b-av-c', false),
  ('7b100000-0000-0000-0000-0000000000d1', 'QA10B-NICK-D', 6, 'qa10b-av-d', true),
  ('7b100000-0000-0000-0000-0000000000e1', 'QA10B-NICK-E', 8, 'qa10b-av-e', true);

insert into public.student_wallets (user_id, points, stars) values
  ('7b100000-0000-0000-0000-0000000000a1', 50, 5),
  ('7b100000-0000-0000-0000-0000000000f1', 42, 7);

-- Sezon: tek aktif S1; uyelikler season_id NULL -> attach trigger
-- aktif sezonu baglar, entry upsert trigger entry uretir (Faz 8 deseni).
insert into public.leaderboard_seasons
  (id, season_code, name, season_type, starts_at, ends_at, is_active) values
  ('7b120000-0000-0000-0000-0000000000a1', 'FAZ10B-S1', 'Faz 10B Sezon 1',
   'monthly', now() - interval '1 day', now() + interval '7 days', true);

insert into public.student_league_memberships
  (user_id, league_id, membership_scope,
   points_at_entry, current_points, is_current, entered_at)
select v.uid,
       (select id from public.leagues where league_code = 'bronze'),
       'general', v.pts, v.pts, true, now()
  from (values
    ('7b100000-0000-0000-0000-0000000000a1'::uuid, 40::integer),
    ('7b100000-0000-0000-0000-0000000000b1', 30),
    ('7b100000-0000-0000-0000-0000000000c1', 20),
    ('7b100000-0000-0000-0000-0000000000d1', 10),
    ('7b100000-0000-0000-0000-0000000000e1', 15),
    ('7b100000-0000-0000-0000-0000000000f1', 33),
    ('7b100000-0000-0000-0000-0000000000f2', 21)
  ) as v(uid, pts);

insert into public.characters
  (id, character_code, name, sort_order, rarity, unlock_type, unlock_value, is_active) values
  ('7b110000-0000-0000-0000-0000000000c1', 'qa10b-ch1', 'QA10B K1', 10, 'common', 'default', 0, true),
  ('7b110000-0000-0000-0000-0000000000c2', 'qa10b-ch2', 'QA10B K2', 20, 'common', 'default', 0, true);

-- ============ P. YETKI MATRISI (108 sonrasi statik envanter) ============
do $blk$
declare
  v_cnt integer;
begin
  select count(*) into v_cnt
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p')
     and has_table_privilege('authenticated', c.oid, 'TRUNCATE');
  perform public._qa10b_true('T-04',
    'authenticated icin hicbir public tabloda TRUNCATE ayrica yok',
    v_cnt = 0, 'cnt=' || v_cnt);

  select count(*) into v_cnt
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p')
     and has_table_privilege('anon', c.oid, 'TRUNCATE');
  perform public._qa10b_true('T-05',
    'anon icin hicbir public tabloda TRUNCATE ayrica yok',
    v_cnt = 0, 'cnt=' || v_cnt);

  select count(*) into v_cnt
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p')
     and has_table_privilege('authenticated', c.oid, 'REFERENCES');
  perform public._qa10b_true('T-06',
    'authenticated icin public tablolarda REFERENCES ayrica yok',
    v_cnt = 0, 'cnt=' || v_cnt);

  select count(*) into v_cnt
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p')
     and has_table_privilege('anon', c.oid, 'REFERENCES');
  perform public._qa10b_true('T-07',
    'anon icin public tablolarda REFERENCES ayrica yok',
    v_cnt = 0, 'cnt=' || v_cnt);

  select count(*) into v_cnt
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p')
     and has_table_privilege('authenticated', c.oid, 'TRIGGER');
  perform public._qa10b_true('T-08',
    'authenticated icin public tablolarda TRIGGER ayrica yok',
    v_cnt = 0, 'cnt=' || v_cnt);

  select count(*) into v_cnt
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p')
     and has_table_privilege('anon', c.oid, 'TRIGGER');
  perform public._qa10b_true('T-09',
    'anon icin public tablolarda TRIGGER ayrica yok',
    v_cnt = 0, 'cnt=' || v_cnt);

  -- Tablo sayisi saglik kontrolu: envanter bos/yanlis semada degil.
  select count(*) into v_cnt
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p');
  perform public._qa10b_true('T-04b',
    'public tablo envanteri gercek (sayim > 100)',
    v_cnt > 100, 'cnt=' || v_cnt);
end;
$blk$;

-- D-01: pg_default_acl invariant (task 5 kaniti):
-- postgres rolunun public semasindaki tablo default ACL'sinde
-- authenticated/anon icin TRUNCATE/REFERENCES/TRIGGER tipi YOK.
do $blk$
declare v_cnt integer;
begin
  select count(*) into v_cnt
    from pg_default_acl d,
         aclexplode(d.defaclacl) a
   where d.defaclrole = 'postgres'::regrole
     and d.defaclnamespace = 'public'::regnamespace
     and d.defaclobjtype = 'r'
     and a.grantee in ('authenticated'::regrole, 'anon'::regrole)
     and a.privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER');
  perform public._qa10b_true('D-01',
    'pg_default_acl: postgres/public tablolarinda tehlikeli default ayrica yok',
    v_cnt = 0, 'cnt=' || v_cnt);
end;
$blk$;

-- ============ T. DAVRANISSAL TRUNCATE TESTLERI ============
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"7b100000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

  perform public._qa10b_expect('T-01',
    'authenticated student_public_profiles TRUNCATE edemez (42501)',
    '42501',
    $sql$truncate public.student_public_profiles$sql$);

  perform public._qa10b_expect('T-02',
    'authenticated leaderboard_entries TRUNCATE ... CASCADE edemez (42501)',
    '42501',
    $sql$truncate public.leaderboard_entries CASCADE$sql$);

  perform public._qa10b_expect('T-01b',
    'authenticated student_loadouts TRUNCATE edemez (42501)',
    '42501',
    $sql$truncate public.student_loadouts$sql$);

  perform public._qa10b_expect('T-01c',
    'authenticated student_wallets TRUNCATE edemez (42501)',
    '42501',
    $sql$truncate public.student_wallets$sql$);

  perform public._qa10b_expect('T-01d',
    'authenticated student_league_memberships TRUNCATE edemez (42501)',
    '42501',
    $sql$truncate public.student_league_memberships$sql$);

  perform public._qa10b_expect('T-01e',
    'authenticated student_league_history TRUNCATE edemez (42501)',
    '42501',
    $sql$truncate public.student_league_history$sql$);

  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);

  perform public._qa10b_expect('T-03',
    'anon student_wallets TRUNCATE edemez (42501)',
    '42501',
    $sql$truncate public.student_wallets$sql$);
end;
$blk$;

-- ============ S. SERVICE_ROLE / POSTGRES YOLU ============
do $blk$
declare v_ok boolean;
begin
  execute 'reset role';

  -- T-19/T-11: gelecek tablo probe'u (postgres olusturur).
  create table public._qa10b_future_probe (id integer);

  -- Gelecek tablo tehlikeli default ayrica ALMAZ (T-19 statik kisim).
  perform public._qa10b_true('T-19',
    'yeni olusturulan tablo tehlikeli default ayrica almaz',
    not has_table_privilege('authenticated', 'public._qa10b_future_probe', 'TRUNCATE')
    and not has_table_privilege('anon', 'public._qa10b_future_probe', 'TRUNCATE')
    and not has_table_privilege('authenticated', 'public._qa10b_future_probe', 'REFERENCES')
    and not has_table_privilege('anon', 'public._qa10b_future_probe', 'REFERENCES')
    and not has_table_privilege('authenticated', 'public._qa10b_future_probe', 'TRIGGER')
    and not has_table_privilege('anon', 'public._qa10b_future_probe', 'TRIGGER'),
    'future-probe');

  -- T-10: service_role bakim yolu saglam (TRUNCATE + SELECT).
  execute 'set local role service_role';
  perform set_config('request.jwt.claims', '', true);
  v_ok := false;
  begin
    truncate public._qa10b_future_probe;
    v_ok := true;
  exception when others then
    v_ok := false;
  end;
  perform public._qa10b_true('T-10',
    'service_role bakim islemi (TRUNCATE) yapabiliyor',
    v_ok, 'svc_truncate=' || v_ok);

  -- T-19 (davranissal): authenticated gelecek tabloyu TRUNCATE edemez.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"7b100000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
  perform public._qa10b_expect('T-19b',
    'authenticated gelecek tabloyu TRUNCATE edemez (42501, default ACL sert)',
    '42501',
    $sql$truncate public._qa10b_future_probe$sql$);

  execute 'reset role';
  drop table public._qa10b_future_probe;

  -- T-11: postgres migration yolu saglam (create + alter + drop).
  begin
    create table public._qa10b_mig_probe (id integer primary key);
    alter table public._qa10b_mig_probe add column note text;
    drop table public._qa10b_mig_probe;
    v_ok := true;
  exception when others then
    v_ok := false;
  end;
  perform public._qa10b_true('T-11',
    'postgres migration/bakim yolu bozulmadi',
    v_ok, 'ddl=' || v_ok);

  -- Faz 10B'nin kismi erisimleri KORUNDUGUNUN kaniti (asiri-revoke yok):
  perform public._qa10b_true('T-11b',
    'authenticated bilincli SELECT erisimleri korundu (profiles + pp + loadouts + characters)',
    has_table_privilege('authenticated', 'public.student_profiles', 'SELECT')
    and has_table_privilege('authenticated', 'public.student_public_profiles', 'SELECT')
    and has_table_privilege('authenticated', 'public.student_loadouts', 'SELECT')
    and has_table_privilege('authenticated', 'public.characters', 'SELECT'),
    'korunan-select');

  perform public._qa10b_true('T-11c',
    'service_role bakim yolu saglam (explicit SELECT + lig tablosu TRUNCATE)',
    has_table_privilege('service_role', 'public.league_season_close_results', 'SELECT')
    and has_table_privilege('service_role', 'public.leaderboard_entries', 'TRUNCATE'),
    'svc-yol');
end;
$blk$;

-- ============ L. RPC-ONLY LIG OKUMASI ============
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"7b100000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

  perform public._qa10b_expect('T-12',
    'authenticated leaderboard_entries dogrudan SELECT edemez (42501)',
    '42501',
    $sql$select count(*) from public.leaderboard_entries$sql$);

  perform public._qa10b_expect('T-13',
    'authenticated student_league_memberships dogrudan SELECT edemez (42501)',
    '42501',
    $sql$select count(*) from public.student_league_memberships$sql$);

  perform public._qa10b_expect('T-14',
    'authenticated student_league_history dogrudan SELECT edemez (42501)',
    '42501',
    $sql$select count(*) from public.student_league_history$sql$);
end;
$blk$;

-- T-15..T-18: allowlist RPC + grade izolasyonu + DTO/PII.
do $blk$
declare
  v_json_a jsonb;
  v_json_d jsonb;
  v_entries jsonb;
  v_keys jsonb;
  v_ok boolean;
  v_text text;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"7b100000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

  v_json_a := public.get_my_league_ranking();

  -- T-15: ayni sinif icin RPC calisir, sunucu sirasi korunur.
  v_entries := v_json_a -> 'entries';
  perform public._qa10b_true('T-15',
    'get_my_league_ranking ayni sinif icin calisir (A rank=1, rating=40)',
    (v_json_a ->> 'season_status') = 'active'
    and (v_json_a ->> 'grade_level')::int = 7
    and jsonb_array_length(v_entries) = 2
    and (v_entries -> 0 ->> 'nickname') = 'QA10B-NICK-A'
    and (v_entries -> 0 ->> 'rank')::int = 1
    and (v_entries -> 0 ->> 'rating')::int = 40
    and ((v_entries -> 0 ->> 'is_current_student')::boolean)
    and (v_entries -> 1 ->> 'nickname') = 'QA10B-NICK-B'
    and (v_json_a -> 'my' ->> 'rank')::int = 1
    and (v_json_a -> 'my' ->> 'rating')::int = 40,
    'status=' || coalesce(v_json_a ->> 'season_status', 'NULL') ||
    ' total=' || coalesce(v_json_a ->> 'total', 'NULL'));

  -- T-16: baska sinif ogrencileri gorunmez (D=6, E=8; C gizli).
  v_text := v_json_a::text;
  perform public._qa10b_true('T-16',
    'grade 7 ogrenci grade 6/8 ve gizli ogrencileri goremaz',
    v_text not like '%QA10B-NICK-D%'
    and v_text not like '%QA10B-NICK-E%'
    and v_text not like '%QA10B-NICK-C%',
    'entries-sadece-ayni-sinif-gorunur');

  -- D'nin kendi gorunumu: grade_level=6 ve yalniz kendisi.
  perform set_config('request.jwt.claims',
    '{"sub":"7b100000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
  v_json_d := public.get_my_league_ranking();
  perform public._qa10b_true('T-16b',
    'D kendi grade-6 gorunumunu gorur; A/B/C/D-disi yoktur',
    (v_json_d ->> 'grade_level')::int = 6
    and jsonb_array_length(v_json_d -> 'entries') = 1
    and (v_json_d -> 'entries' -> 0 ->> 'nickname') = 'QA10B-NICK-D',
    'd_grade=' || coalesce(v_json_d ->> 'grade_level', 'NULL'));

  -- T-17: DTO yalniz izinli alanlari icerir (allowlist).
  perform set_config('request.jwt.claims',
    '{"sub":"7b100000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
  v_json_a := public.get_my_league_ranking();
  v_entries := v_json_a -> 'entries';

  v_keys := (select jsonb_object_agg(k, true)
               from jsonb_object_keys(v_entries -> 0) as k);
  perform public._qa10b_true('T-17',
    'entry DTO yalniz izinli alanlari icerir (allowlist)',
    v_keys = '{"rank":true,"is_current_student":true,"nickname":true,"avatar_key":true,"league_code":true,"league_name":true,"rating":true}'::jsonb,
    'entry_keys=' || coalesce(v_keys::text, 'NULL'));

  v_keys := (select jsonb_object_agg(k, true) from jsonb_object_keys(v_json_a) as k);
  perform public._qa10b_true('T-17b',
    'kok DTO yalniz izinli alanlari icerir (allowlist)',
    v_keys = '{"season_status":true,"season":true,"grade_level":true,"my":true,"entries":true,"total":true,"next_league":true}'::jsonb,
    'root_keys=' || coalesce(v_keys::text, 'NULL'));

  if (v_json_a -> 'my') is not null then
    v_keys := (select jsonb_object_agg(k, true) from jsonb_object_keys(v_json_a -> 'my') as k);
    perform public._qa10b_true('T-17c',
      'my DTO yalniz izinli alanlari icerir (allowlist)',
      v_keys = '{"rank":true,"rating":true,"league_code":true,"league_name":true,"nickname":true,"avatar_key":true}'::jsonb,
      'my_keys=' || coalesce(v_keys::text, 'NULL'));
  else
    perform public._qa10b_true('T-17c', 'my DTO yalniz izinli alanlari icerir (allowlist)', false, 'my yok');
  end if;

  -- T-18: UUID / e-posta / PII / dahili metadata sizmasi yok.
  v_text := v_json_a::text;
  v_ok := v_text not like '%@test.local%'
          and v_text not like '%7b100000-%'
          and v_text not like '%7b120000-%'
          and v_text !~ '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
          and v_text not like '%"user_id"%'
          and v_text not like '%"email"%';
  perform public._qa10b_true('T-18',
    'DTO UUID/e-posta/PII/dahili metadata sizdirmiyor',
    v_ok, 'scan_temiz=' || v_ok);
end;
$blk$;

-- ============ A. PROFIL/AVATAR RPC SAGLIGI + DEGER AYRILIGI ============
do $blk$
declare
  v_json jsonb;
  v_stars integer;
  v_points integer;
  v_grade smallint;
  v_rating integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"7b100000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

  -- T-21: RPC'ler calisir.
  v_json := public.select_own_avatar('qa10b-ch1');
  perform public._qa10b_true('T-21',
    'select_own_avatar calisir ve sunucu DTO doner',
    (v_json ->> 'character_code') = 'qa10b-ch1'
    and (v_json ->> 'avatar_key') = 'qa10b-ch1',
    'code=' || coalesce(v_json ->> 'character_code', 'NULL'));

  v_json := public.get_own_gamification_profile();
  perform public._qa10b_true('T-21b',
    'get_own_gamification_profile calisir (allowlist DTO)',
    v_json ? 'xp' and v_json ? 'streak' and v_json ? 'daily_quota'
    and v_json ? 'badges'
    and (v_json -> 'daily_quota' ->> 'limit')::int = 500
    and (v_json -> 'xp' ->> 'total')::bigint = 0,
    'xp_total=' || coalesce(v_json -> 'xp' ->> 'total', 'NULL'));

  -- T-22: deger ayriligi: avatar secimi XP/rating/yarisma puani/yildiz
  -- dokunmaz. Degerler postgres baglaminda okunur (cuzdanda
  -- authenticated'a dogrudan SELECT bilincli erisim DEGILDIR;
  -- okuma yalniz sunucu RPC'leri ile).
  execute 'reset role';
  select w.stars, w.points, s.grade_level, m.current_points
    into v_stars, v_points, v_grade, v_rating
    from public.student_wallets w
    join public.student_profiles s on s.id = w.user_id
    join public.student_league_memberships m
      on m.user_id = s.id and m.is_current
   where w.user_id = '7b100000-0000-0000-0000-0000000000a1';

  perform public._qa10b_true('T-22',
    'avatar secimi yildiz/cuzdan/grade/lig-rating degistirmez',
    v_stars = 5 and v_points = 50 and v_grade = 7 and v_rating = 40,
    'stars=' || coalesce(v_stars::text,'NULL') || ' points=' || coalesce(v_points::text,'NULL')
    || ' grade=' || coalesce(v_grade::text,'NULL') || ' rating=' || coalesce(v_rating::text,'NULL'));
end;
$blk$;

-- ============ RL. AVATAR RATE LIMIT (10/60, ONAYLI KARAR) ============
do $blk$
declare
  v_fail integer;
  v_cnt integer;
  v_state text;
  v_ok boolean;
  v_stars integer;
  v_points integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"7b100000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);

  -- RL-01: ilk 10 gecerli istek izinli.
  v_fail := 0;
  for i in 1..10 loop
    begin
      perform public.select_own_avatar('qa10b-ch1');
    exception when others then
      v_fail := v_fail + 1;
    end;
  end loop;
  perform public._qa10b_true('RL-01',
    'ilk 10 gecerli avatar istegi izinli (10/60)',
    v_fail = 0, 'hata=' || v_fail);

  -- RL-02: 11. istek rate-limit ile reddedilir (gicerli kod ch2;
  -- katalog gecerli olsa da limit oncelidir).
  perform public._qa10b_expect('RL-02',
    '11. istek rate-limit ile reddedilir (P0001, 10/60)',
    'P0001',
    $sql$select public.select_own_avatar('qa10b-ch2')$sql$);

  -- RL-03: limit asimi avatar KISMEN degistirmez (ch2 yazilmadi).
  select count(*) into v_cnt
    from public.student_loadouts l
    join public.characters c on c.id = l.character_id
   where l.user_id = '7b100000-0000-0000-0000-0000000000f1'
     and c.character_code = 'qa10b-ch2';
  perform public._qa10b_true('RL-03',
    'limit asimi avatarini kismen degistirmez (ch2 yazilmadi)',
    v_cnt = 0, 'ch2_cnt=' || v_cnt);

  select count(*) into v_cnt
    from public.student_public_profiles pp
   where pp.user_id = '7b100000-0000-0000-0000-0000000000f1'
     and pp.avatar_key = 'qa10b-ch1';
  perform public._qa10b_true('RL-03b',
    'pp.avatar_key guncel secimde kaliyor (ch1)',
    v_cnt = 1, 'pp_ch1_cnt=' || v_cnt);

  -- RL-04: baska kullanici ayri sayaca sahiptir (G taze bucket).
  perform set_config('request.jwt.claims',
    '{"sub":"7b100000-0000-0000-0000-0000000000f2","role":"authenticated"}', true);
  perform public._qa10b_expect('RL-04',
    'baska kullanici ayri sayac: G''nin ilk istegi izinli',
    '',
    $sql$select public.select_own_avatar('qa10b-ch1')$sql$);

  -- RL-05: istemciden user_id ALINMAZ: RPC imzasi yalniz karakter kodu.
  execute 'reset role';
  select (p.proargnames = array['p_character_code'] and p.pronargs = 1)
    into v_ok
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'select_own_avatar';
  perform public._qa10b_true('RL-05',
    'select_own_avatar imzasi user_id/grade parametresi almaz',
    v_ok, 'imza=' || coalesce(v_ok::text, 'NULL'));

  -- anon kimlik calistiramaz (sahte kimlik yolu da kapali).
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  perform public._qa10b_expect('RL-05b',
    'anon kimlik select_own_avatar CALISTIRAMAZ (42501)',
    '42501',
    $sql$select public.select_own_avatar('qa10b-ch1')$sql$);

  -- RL-06: gunluk 500 soru kotasina etki yok (farkli tablo/sayaç).
  execute 'reset role';
  select count(*) into v_cnt
    from public.student_daily_question_counters
   where user_id = '7b100000-0000-0000-0000-0000000000f1';
  perform public._qa10b_true('RL-06',
    'gunluk 500 soru kotasina avatar/RL etkisi yok',
    v_cnt = 0, 'daily_cnt=' || v_cnt);

  select r.hit_count into v_cnt
    from public.rpc_rate_limits r
   where r.user_id = '7b100000-0000-0000-0000-0000000000f1'
     and r.rpc_name = 'select_own_avatar'
     and r.hit_count = 10
   limit 1;
  perform public._qa10b_true('RL-06b',
    'rate-limit sayaci kendi uzayinda (select_own_avatar, hit=10)',
    v_cnt = 10, 'hit=' || coalesce(v_cnt::text, 'NULL'));

  -- RL-07: RL denemeleri XP/yildiz URETMEZ (postgres baglaminda okuma).
  select w.stars, w.points into v_stars, v_points
    from public.student_wallets w
   where w.user_id = '7b100000-0000-0000-0000-0000000000f1';
  perform public._qa10b_true('RL-07',
    'RL denemeleri XP/yildiz uretmez (cuzdan sabit)',
    v_stars = 7 and v_points = 42,
    'stars=' || coalesce(v_stars::text,'NULL') || ' points=' || coalesce(v_points::text,'NULL'));

  select count(*) into v_cnt
    from public.student_xp_totals t
   where t.user_id = '7b100000-0000-0000-0000-0000000000f1';
  perform public._qa10b_true('RL-07b',
    'RL denemeleri XP kaydi uretmez',
    v_cnt = 0, 'xp_rows=' || v_cnt);
end;
$blk$;

-- ============ SD. SECURITY DEFINER DENETIMI ============
do $blk$
declare
  v_ok boolean;
  v_cnt integer;
begin
  execute 'reset role';

  -- SD-01: select_own_avatar
  select p.prosecdef
     and p.proowner = 'postgres'::regrole
     and p.proconfig is not null
     and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')
     and not has_function_privilege('anon', 'public.select_own_avatar(text)', 'EXECUTE')
     and has_function_privilege('authenticated', 'public.select_own_avatar(text)', 'EXECUTE')
    into v_ok
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'select_own_avatar';
  perform public._qa10b_true('SD-01',
    'select_own_avatar: DEFINER + postgres sahibi + search_path + anon/PUBLIC kapali + authenticated acik',
    v_ok, 'sd=' || coalesce(v_ok::text, 'NULL'));

  select count(*) into v_cnt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'select_own_avatar';
  perform public._qa10b_true('SD-01b',
    'select_own_avatar: overload kalintisi yok (tek tanim)',
    v_cnt = 1, 'overload_cnt=' || v_cnt);

  -- SD-02: get_own_gamification_profile
  select p.prosecdef
     and p.proowner = 'postgres'::regrole
     and p.proconfig is not null
     and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')
     and not has_function_privilege('anon', 'public.get_own_gamification_profile()', 'EXECUTE')
     and has_function_privilege('authenticated', 'public.get_own_gamification_profile()', 'EXECUTE')
    into v_ok
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_own_gamification_profile';
  perform public._qa10b_true('SD-02',
    'get_own_gamification_profile: DEFINER + sahibi + search_path + anon/PUBLIC kapali + authenticated acik',
    v_ok, 'sd=' || coalesce(v_ok::text, 'NULL'));

  select count(*) into v_cnt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_own_gamification_profile';
  perform public._qa10b_true('SD-02b',
    'get_own_gamification_profile: overload kalintisi yok',
    v_cnt = 1, 'overload_cnt=' || v_cnt);

  -- SD-03: get_my_league_ranking
  select p.prosecdef
     and p.proowner = 'postgres'::regrole
     and p.proconfig is not null
     and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')
     and not has_function_privilege('anon', 'public.get_my_league_ranking(integer,integer)', 'EXECUTE')
     and has_function_privilege('authenticated', 'public.get_my_league_ranking(integer,integer)', 'EXECUTE')
     and p.proargnames = array['p_limit', 'p_offset']
    into v_ok
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_my_league_ranking';
  perform public._qa10b_true('SD-03',
    'get_my_league_ranking: DEFINER + sahibi + search_path + anon kapali + authenticated acik + kimlik/grade parametreleri yok',
    v_ok, 'sd=' || coalesce(v_ok::text, 'NULL'));

  select count(*) into v_cnt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_my_league_ranking';
  perform public._qa10b_true('SD-03b',
    'get_my_league_ranking: overload kalintisi yok',
    v_cnt = 1, 'overload_cnt=' || v_cnt);

  -- SD-04: PUBLIC EXECUTE kapali (proacl NULL degil).
  select count(*) into v_cnt
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('select_own_avatar','get_own_gamification_profile','get_my_league_ranking')
     and p.proacl is null;
  perform public._qa10b_true('SD-04',
    'uc RPC icin PUBLIC (varsayilan) EXECUTE kapali',
    v_cnt = 0, 'null_acl_cnt=' || v_cnt);

  -- SD-05: dinamik SQL / EXECUTE kullanilan dosya denetimi kod
  -- incelemesindedir; burada RPC govdelerinin istemci parametresiyle
  -- baska kullanici/sinif SECEMEDIGINI davranissal kanitliyoruz:
  -- A'nin claims'i ile B'nin verisi (rank karti) gelmez.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"7b100000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
  declare v_json jsonb;
  begin
    v_json := public.get_my_league_ranking();
    perform public._qa10b_true('SD-05',
      'kimlik yalniz auth.uid(): B oturumunda my= B''ye ait',
      (v_json -> 'my' ->> 'nickname') = 'QA10B-NICK-B'
      and ((v_json -> 'my' ->> 'is_current_student') is null),
      'my_nick=' || coalesce(v_json -> 'my' ->> 'nickname', 'NULL'));
  exception when others then
    perform public._qa10b_true('SD-05',
      'kimlik yalniz auth.uid(): B oturumunda my= B''ye ait',
      false, 'rpc_hata: ' || sqlerrm);
  end;
end;
$blk$;

-- ============ I. MIGRATION 108 IDEMPOTENT YENIDEN UYGULAMA ============
do $blk$
DECLARE
  r record;
  v_dangerous integer;
  v_league_open integer;
BEGIN
  execute 'reset role';

  -- 108 govdesinin birebir yeniden calistirilmasi (idempotency kaniti).
  FOR r IN
    SELECT c.oid::regclass AS tbl
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relkind IN ('r', 'p')
  LOOP
    EXECUTE format(
      'REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE %s FROM authenticated',
      r.tbl);
    EXECUTE format(
      'REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE %s FROM anon',
      r.tbl);
  END LOOP;

  REVOKE SELECT ON public.leaderboard_entries FROM authenticated, anon;
  REVOKE SELECT ON public.student_league_memberships FROM authenticated, anon;
  REVOKE SELECT ON public.student_league_history FROM authenticated, anon;

  ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM authenticated, anon;

  SELECT count(*) INTO v_dangerous
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relkind IN ('r', 'p')
     AND (
           has_table_privilege('authenticated', c.oid, 'TRUNCATE')
        OR has_table_privilege('anon', c.oid, 'TRUNCATE')
        OR has_table_privilege('authenticated', c.oid, 'REFERENCES')
        OR has_table_privilege('anon', c.oid, 'REFERENCES')
        OR has_table_privilege('authenticated', c.oid, 'TRIGGER')
        OR has_table_privilege('anon', c.oid, 'TRIGGER')
         );

  SELECT count(*) INTO v_league_open
    FROM (VALUES
      ('public.leaderboard_entries'::regclass),
      ('public.student_league_memberships'::regclass),
      ('public.student_league_history'::regclass)
    ) AS t(oid)
   WHERE has_table_privilege('authenticated', t.oid, 'SELECT')
      OR has_table_privilege('anon', t.oid, 'SELECT');

  perform public._qa10b_true('T-20',
    'migration 108 yeniden uygulandi; ayni guvenlik sonucu korunuyor',
    v_dangerous = 0 and v_league_open = 0,
    'dangerous=' || v_dangerous || ' league_open=' || v_league_open);
END;
$blk$;

-- ============ OZET ============
reset role;

select 'PASS=' || count(*) filter (where result = 'PASS')
       || '|FAIL=' || count(*) filter (where result = 'FAIL')
       || '|SKIP=' || count(*) filter (where result = 'SKIP')
  from public._qa10b_results;

select 'TOPLAM=' || count(*)
       || '|' || 'GECEN=' || count(*) filter (where result = 'PASS')
       || '|' || 'KALAN=' || count(*) filter (where result = 'FAIL')
  from public._qa10b_results;

select label || '|PASS|' || title from public._qa10b_results where result = 'PASS';
select label || '|FAIL|' || coalesce(detail, title) from public._qa10b_results where result = 'FAIL';
select label || '|SKIP|' || coalesce(detail, title) from public._qa10b_results where result = 'SKIP';

drop function public._qa10b_expect(text,text,text,text);
drop function public._qa10b_true(text,text,boolean,text);
drop table public._qa10b_results;

rollback;
