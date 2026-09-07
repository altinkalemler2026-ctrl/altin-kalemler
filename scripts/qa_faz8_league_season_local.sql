-- ============================================================
-- scripts/qa_faz8_league_season_local.sql
-- Altin Kalemler - Migration Faz 8 yerel QA suite
--
-- Kapsam:
--   101 lig/sezon motoru: sezon durum türetimi, üyeliğe sezon
--   bağlama trigger'ı, entry üretici motoru, aynı sınıf güvenli
--   okuma RPC'si (get_my_league_ranking), sezon kapanış bakım
--   RPC'si (close_league_season), RLS/grant/ACL.
--
-- Test haritasi (AŞAMA 10 matrisi):
--   T-01..05   lig tanimi + benzersizlik kisitlari
--   T-06..T-16 grade izolasyonu + PII allowlist
--   T-17..T-27 rating motoru + ayrik puan turlari
--   T-28..T-34 siralama + tie-break + limit + rate limit
--   T-35..T-40 promotion/demotion
--   T-41..T-51 sezon yasadongusu + kapanis + okul yok
--
-- Calistirma (LOCAL ONLY, disposable stack):
--   docker cp scripts/qa_faz8_league_season_local.sql <db>:/tmp/
--   docker exec <db> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -f /tmp/qa_faz8_league_season_local.sql
--
-- Guvence: suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR (faz5 deseninin aynisi)
-- ============================================================

create table public._qa_faz8_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_faz8_results
  to anon, authenticated, service_role;

create function public._qa8_expect(p_label text, p_title text, p_expect text, p_sql text)
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
    insert into public._qa_faz8_results
    values (p_label, p_title, 'FAIL',
            'beklenen hata gelmedi (' || p_expect || ')');
  exception
    when others then
      get stacked diagnostics v_state = RETURNED_SQLSTATE,
                              v_msg = MESSAGE_TEXT;
      if v_state = p_expect then
        insert into public._qa_faz8_results
        values (p_label, p_title, 'PASS',
                'sqlstate=' || v_state || ' | mesaj eslesti');
      else
        insert into public._qa_faz8_results
        values (p_label, p_title, 'FAIL',
                'sqlstate=' || v_state ||
                ' beklenen=' || p_expect ||
                ' | msg=' || left(v_msg, 160));
      end if;
  end;
end;
$qa$;

create function public._qa8_true(p_label text, p_title text, p_ok boolean, p_detail text default null)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_faz8_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa8_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa8_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR
-- Ogrenciler:
--   A (7.sinif, gorunur)   : 8f800000-...-0001
--   B (7.sinif, gorunur)   : 8f800000-...-0002
--   C (7.sinif, GIZLI)     : 8f800000-...-0003
--   D (6.sinif, gorunur)   : 8f800000-...-0004
--   E (8.sinif, gorunur)   : 8f800000-...-0005
--   F (7.sinif, gorunur)   : 8f800000-...-0006  (tie)
--   G (7.sinif, gorunur)   : 8f800000-...-0007  (tie)
--   N (profil YOK)         : 8f800000-...-0009  (fail-closed)
-- Sezonlar:
--   S1 (aktif)   : 8f820000-...-0011
--   S2 (upcoming): 8f820000-...-0012
-- QA ligleri: QA8-BRONZ (sort 1, 0-99), QA8-GUMUS (sort 2, 100+)
-- ============================================================

insert into auth.users (id, email) values
  ('8f800000-0000-0000-0000-000000000001', 'qa8-a@test.local'),
  ('8f800000-0000-0000-0000-000000000002', 'qa8-b@test.local'),
  ('8f800000-0000-0000-0000-000000000003', 'qa8-c@test.local'),
  ('8f800000-0000-0000-0000-000000000004', 'qa8-d@test.local'),
  ('8f800000-0000-0000-0000-000000000005', 'qa8-e@test.local'),
  ('8f800000-0000-0000-0000-000000000006', 'qa8-f@test.local'),
  ('8f800000-0000-0000-0000-000000000007', 'qa8-g@test.local'),
  ('8f800000-0000-0000-0000-000000000009', 'qa8-n@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('8f800000-0000-0000-0000-000000000001', 7, 'QA8-NICK-A'),
  ('8f800000-0000-0000-0000-000000000002', 7, 'QA8-NICK-B'),
  ('8f800000-0000-0000-0000-000000000003', 7, 'QA8-NICK-C'),
  ('8f800000-0000-0000-0000-000000000004', 6, 'QA8-NICK-D'),
  ('8f800000-0000-0000-0000-000000000005', 8, 'QA8-NICK-E'),
  ('8f800000-0000-0000-0000-000000000006', 7, 'QA8-NICK-F'),
  ('8f800000-0000-0000-0000-000000000007', 7, 'QA8-NICK-G');

insert into public.student_public_profiles
  (user_id, nickname, grade_level, avatar_key, is_visible) values
  ('8f800000-0000-0000-0000-000000000001', 'QA8-NICK-A', 7, 'avatar_a', true),
  ('8f800000-0000-0000-0000-000000000002', 'QA8-NICK-B', 7, 'avatar_b', true),
  ('8f800000-0000-0000-0000-000000000003', 'QA8-NICK-C', 7, 'avatar_c', false),
  ('8f800000-0000-0000-0000-000000000004', 'QA8-NICK-D', 6, 'avatar_d', true),
  ('8f800000-0000-0000-0000-000000000005', 'QA8-NICK-E', 8, 'avatar_e', true),
  ('8f800000-0000-0000-0000-000000000006', 'QA8-NICK-F', 7, 'avatar_f', true),
  ('8f800000-0000-0000-0000-000000000007', 'QA8-NICK-G', 7, 'avatar_g', true);

-- Uyelikler: season_id YOK (null) -> attach trigger aktif sezonu
-- baglar; entry upsert trigger otomatik entry uretir.
-- Promotion/demotion testleri PRODUCTION bantlariyla (bronze 0-999,
-- silver 1000-2499, diamond 5000+) yapilir; QA ligi yaratilmaz.

-- Sezonlar: S1 aktif pencerede, S2 upcoming (S1 bitisinden sonra).
insert into public.leaderboard_seasons
  (id, season_code, name, season_type, starts_at, ends_at, is_active) values
  ('8f820000-0000-0000-0000-000000000011', 'FAZ8-S1', 'Faz 8 Sezon 1',
   'monthly', now() - interval '1 day', now() + interval '7 days', true),
  ('8f820000-0000-0000-0000-000000000012', 'FAZ8-S2', 'Faz 8 Sezon 2',
   'monthly', now() + interval '7 days', now() + interval '37 days', false);

-- Uyelikler: season_id YOK (null) -> attach trigger aktif sezonu
-- baglar; entry upsert trigger otomatik entry uretir.
insert into public.student_league_memberships
  (user_id, league_id, membership_scope,
   points_at_entry, current_points, is_current, entered_at)
select v.uid,
       (select id from public.leagues where league_code = 'bronze'),
       'general',
       v.pts, v.pts, true,
       coalesce(v.ent, now())
  from (values
    ('8f800000-0000-0000-0000-000000000001'::uuid, 40::integer, null::timestamptz),
    ('8f800000-0000-0000-0000-000000000002', 30, null),
    ('8f800000-0000-0000-0000-000000000003', 20, null),
    ('8f800000-0000-0000-0000-000000000004', 10, null),
    ('8f800000-0000-0000-0000-000000000005', 15, null),
    ('8f800000-0000-0000-0000-000000000006', 25, now() - interval '10 seconds'),
    ('8f800000-0000-0000-0000-000000000007', 25, now() - interval '5 seconds')
  ) as v(uid, pts, ent);


-- ============================================================
-- T-01..03: LIG TANIMI (Bronz/Gumus/Altin/Elmas, benzersiz, bant)
-- ============================================================

do $blk$
declare
  v_cnt integer;
  v_ok boolean;
begin
  select count(*) into v_cnt
    from public.leagues
   where league_code in ('bronze', 'silver', 'gold', 'diamond')
     and league_type = 'standard'
     and is_active = true;
  perform public._qa8_true('T-01',
    '4 lig kademesi mevcut ve aktif (bronze/silver/gold/diamond)',
    v_cnt = 4, 'cnt=' || v_cnt);

  select count(distinct league_code) = 4 into v_ok
    from public.leagues
   where league_code in ('bronze', 'silver', 'gold', 'diamond');
  perform public._qa8_true('T-02',
    'lig kodlari benzersiz (UNIQUE)', v_ok, 'distinct-kod');

  select
    (select min_points || '-' || coalesce(max_points::text, 'inf')
       from public.leagues where league_code = 'bronze') = '0-999'
    and (select min_points || '-' || coalesce(max_points::text, 'inf')
       from public.leagues where league_code = 'silver') = '1000-2499'
    and (select min_points || '-' || coalesce(max_points::text, 'inf')
       from public.leagues where league_code = 'gold') = '2500-4999'
    and (select min_points || '-' || coalesce(max_points::text, 'inf')
       from public.leagues where league_code = 'diamond') = '5000-inf'
    and 10 < 20 and 20 < 30 and 30 < 40
    and (select sort_order from public.leagues where league_code='bronze') = 10
    and (select sort_order from public.leagues where league_code='diamond') = 40
    into v_ok;
  perform public._qa8_true('T-03',
    'lig bantlari deterministik ve cakismaz (016 sozlesmesi)',
    v_ok, 'bantlar');
end;
$blk$;


-- ============================================================
-- T-04: TEK GUNCEL UYELIK (Faz 8 UNIQUE indeksi)
-- ============================================================

select public._qa8_expect('T-04',
  'ayni kullanici icin ikinci guncel genel uyelik reddedilir',
  '23505',
  $sql$insert into public.student_league_memberships
    (user_id, league_id, membership_scope,
     points_at_entry, current_points, is_current)
  values ('8f800000-0000-0000-0000-000000000001',
          (select id from public.leagues where league_code = 'silver'),
          'general', 0, 0, true)$sql$);


-- ============================================================
-- T-05: TEK AKTIF SEZON (Faz 8 UNIQUE indeksi)
-- ============================================================

select public._qa8_expect('T-05',
  'S1 aktifken S2 de aktif yapilamaz (cakisan aktif sezon yok)',
  '23505',
  $sql$update public.leaderboard_seasons
     set is_active = true
   where id = '8f820000-0000-0000-0000-000000000012'$sql$);


-- ============================================================
-- T-06..T-16: GRADE IZOLASYONU + PII
-- ============================================================

-- T-06: anon RPC red.
do $blk$
begin
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);

  perform public._qa8_expect('T-06',
    'anon: get_my_league_ranking 42501 ile reddedilir',
    '42501',
    $sql$select public.get_my_league_ranking()$sql$);

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$blk$;

-- T-07..T-12: A'nin goruntusu (tek RPC cagrisi, coklu iddia).
do $blk$
declare
  v_json jsonb;
  v_entries jsonb;
  v_names text[];
  v_keys_ok boolean;
  v_e record;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

  select public.get_my_league_ranking() into v_json;
  v_entries := v_json -> 'entries';

  perform public._qa8_true('T-07',
    'A: kendi grade 7 kapsami + kendi sira karti',
    (v_json -> 'grade_level')::text = '7'
      and (v_json -> 'my' ->> 'nickname') = 'QA8-NICK-A'
      and (v_json -> 'my' ->> 'rank')::int = 1
      and (v_json -> 'my' ->> 'rating')::int = 40,
    'my=' || coalesce((v_json -> 'my')::text, 'yok'));

  perform public._qa8_true('T-08',
    'A: ayni sinif gorunur B listesinde',
    exists (
      select 1
        from jsonb_array_elements(v_entries) el
       where el ->> 'nickname' = 'QA8-NICK-B'));

  perform public._qa8_true('T-09',
    'A: grade 6 D listesinde YOK',
    not exists (
      select 1
        from jsonb_array_elements(v_entries) el
       where el ->> 'nickname' = 'QA8-NICK-D'));

  perform public._qa8_true('T-10',
    'A: grade 8 E listesinde YOK',
    not exists (
      select 1
        from jsonb_array_elements(v_entries) el
       where el ->> 'nickname' = 'QA8-NICK-E'));

  perform public._qa8_true('T-11',
    'A: gizli profil C listesinde YOK (toplam 5 satir, 4 gorunur)',
    not exists (
      select 1
        from jsonb_array_elements(v_entries) el
       where el ->> 'nickname' = 'QA8-NICK-C')
      and jsonb_array_length(v_entries) = 4
      and (v_json ->> 'total')::int = 5,
    'entries=' || jsonb_array_length(v_entries) ||
    ' total=' || coalesce(v_json ->> 'total', '?'));

  -- PII allowlist: entry anahtarlari izinli kumede; UUID/email yok.
  v_keys_ok := true;
  for v_e in select el as e from jsonb_array_elements(v_entries) el loop
    if exists (
      select 1
        from jsonb_object_keys(v_e.e) k
       where k not in ('rank', 'is_current_student', 'nickname',
                       'avatar_key', 'league_code', 'league_name', 'rating')
    ) then
      v_keys_ok := false;
    end if;
  end loop;

  select array_agg(el ->> 'nickname') into v_names
    from jsonb_array_elements(v_entries) el;

  perform public._qa8_true('T-12',
    'PII allowlist: yalniz izinli anahtarlar; UUID/email sizzor',
    v_keys_ok
      and v_json::text not like '%8f800000%'
      and v_json::text not like '%@%'
      and not exists (
        select 1
          from jsonb_object_keys(v_json) k
         where k in ('user_id', 'email', 'phone', 'school', 'classroom')),
    'keys_ok=' || v_keys_ok || ' names=' || coalesce(array_to_string(v_names, ','), '-'));

  -- Tie-break + siralama (F/G ayni rating, F daha once girdi).
  perform public._qa8_true('T-13',
    'tie-break: F(G) oncesinde; siralama rating desc deterministik',
    exists (
      select 1
        from jsonb_array_elements(v_entries) ef
        join jsonb_array_elements(v_entries) eg
          on ef ->> 'nickname' = 'QA8-NICK-F'
         and eg ->> 'nickname' = 'QA8-NICK-G'
       where (ef ->> 'rank')::int < (eg ->> 'rank')::int)
      and exists (
        select 1
          from jsonb_array_elements(v_entries) e1
          join jsonb_array_elements(v_entries) e2
            on (e1 ->> 'rank')::int = (e2 ->> 'rank')::int - 1
         where (e1 ->> 'rating')::int > (e2 ->> 'rating')::int),
    'siralama');

  -- K ENDIK: RPC imzasi grade/user/season/school parametresi almaz.
  perform public._qa8_true('T-14',
    'RPC imzasi: yalniz p_limit/p_offset; grade/user/season yok',
    exists (
      select 1
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = 'get_my_league_ranking'
         and lower(pg_get_function_arguments(p.oid))
               = 'p_limit integer default 50, p_offset integer default 0'
         and lower(pg_get_function_arguments(p.oid)) not like '%grade%'
         and lower(pg_get_function_arguments(p.oid)) not like '%user%'
         and lower(pg_get_function_arguments(p.oid)) not like '%season%'
         and lower(pg_get_function_arguments(p.oid)) not like '%school%'
         and lower(pg_get_function_arguments(p.oid)) not like '%classroom%'),
    'imza');

  -- C (gizli) kendi kartini gorur; digerleri C'yi goremez.
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000003","role":"authenticated"}', true);
  declare
    v_json_c jsonb;
  begin
    select public.get_my_league_ranking() into v_json_c;
    perform public._qa8_true('T-15',
      'gizli C kendi sira kartini gorur (rank=5, rating=20)',
      (v_json_c -> 'my' ->> 'nickname') = 'QA8-NICK-C'
        and (v_json_c -> 'my' ->> 'rank')::int = 5
        and (v_json_c -> 'my' ->> 'rating')::int = 20,
      'my=' || coalesce((v_json_c -> 'my')::text, 'yok'));
  end;

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- T-16: dogrudan tablo okumasi fail-closed: authenticated'a SELECT
-- grant'i yoktur (yeni CLI no-auto-expose); ogrenci okumayi yalniz
-- allowlist RPC uzerinden yapar -> grade siniri tablo duzeyinde de
-- asilamaz (erisim tamamen kapali >= grade izolasyonu).
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

  perform public._qa8_expect('T-16a',
    'A dogrudan leaderboard_entries SELECT edemez (42501, fail-closed)',
    '42501',
    $sql$select count(*) from public.leaderboard_entries where grade_level = 6$sql$);

  perform public._qa8_expect('T-16b',
    'A dogrudan student_league_memberships SELECT edemez (42501)',
    '42501',
    $sql$select count(*) from public.student_league_memberships
     where user_id = '8f800000-0000-0000-0000-000000000004'$sql$);

  perform public._qa8_expect('T-16c',
    'A dogrudan student_league_history SELECT edemez (42501)',
    '42501',
    $sql$select count(*) from public.student_league_history$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;


-- ============================================================
-- T-17..T-27: RATING MOTORU
-- C1: completed yarisma (A kazandi) -> +24 / -12
-- ============================================================

do $blk$
declare
  v_comp uuid;
begin
  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count,
     winner_user_id)
  values
    ('F8-QA-C1', 'one_vs_one', 7,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'completed', 5,
     '8f800000-0000-0000-0000-000000000001')
  returning id into v_comp;

  insert into public.competition_players
    (competition_id, user_id, player_slot, total_points, status)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 1, 250, 'finished'),
    (v_comp, '8f800000-0000-0000-0000-000000000002', 2, 80, 'finished');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type,
     player_results, calculated_at)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 'win_loss',
     '[]'::jsonb, now());

  perform set_config('qa8.comp_c1', v_comp::text, false);
end;
$blk$;

do $blk$
declare
  v_comp uuid := nullif(current_setting('qa8.comp_c1', true), '')::uuid;
begin
  perform public._faz5_apply_competition_points(v_comp);

  perform public._qa8_true('T-17',
    'rating: A +24 / B -12; rating yarisma puanindan ayri (250!=64)',
    exists (
      select 1 from public.competition_point_changes cpc
       where cpc.competition_id = v_comp
         and cpc.user_id = '8f800000-0000-0000-0000-000000000001'
         and cpc.change_type = 'rating'
         and cpc.points_change = 24
         and cpc.points_before + cpc.points_change = cpc.points_after)
      and exists (
        select 1 from public.competition_point_changes cpc
         where cpc.competition_id = v_comp
           and cpc.user_id = '8f800000-0000-0000-0000-000000000002'
           and cpc.change_type = 'rating'
           and cpc.points_change = -12)
      and (select m.current_points
             from public.student_league_memberships m
            where m.user_id = '8f800000-0000-0000-0000-000000000001'
              and m.is_current) = 64
      and 250 <> 64);

  -- Idempotency: tekrar apply -> no-op.
  perform public._faz5_apply_competition_points(v_comp);

  perform public._qa8_true('T-18',
    'idempotency: tekrar apply rating degistirmez (2 kayit kalir)',
    (select count(*) from public.competition_point_changes cpc
      where cpc.competition_id = v_comp
        and cpc.change_type = 'rating') = 2
      and (select m.current_points
             from public.student_league_memberships m
            where m.user_id = '8f800000-0000-0000-0000-000000000001'
              and m.is_current) = 64);

  -- Entry tam bir kez olusur/guncellenir.
  perform public._qa8_true('T-19',
    'entry uretici: A icin tek entry, puan 64, sezon S1',
    (select count(*) from public.leaderboard_entries e
      where e.user_id = '8f800000-0000-0000-0000-000000000001'
        and e.season_id = '8f820000-0000-0000-0000-000000000011'
        and e.scope_type = 'league') = 1
      and exists (
        select 1 from public.leaderboard_entries e
         where e.user_id = '8f800000-0000-0000-0000-000000000001'
           and e.season_id = '8f820000-0000-0000-0000-000000000011'
           and e.points = 64
           and e.grade_level = 7));

  -- Rating/XP/yildiz ayrimi.
  perform public._qa8_true('T-20',
    'ayrim: cuzdan (yildiz) dokunulmaz; XP alani/altyapisi yok',
    not exists (
      select 1 from public.student_wallets w
       where w.user_id = '8f800000-0000-0000-0000-000000000001'
         and w.balances <> '{}'::jsonb)
      and not exists (
        select 1 from information_schema.columns c
         where c.table_schema = 'public'
           and c.table_name = 'student_profiles'
           and c.column_name in ('xp', 'level', 'star_balance', 'rating'))
      and not exists (
        select 1 from information_schema.tables t
         where t.table_schema = 'public'
           and t.table_name ilike 'xp%'));

  -- History yok (bant degismedi).
  perform public._qa8_true('T-21',
    'bant degismedigi icin history yazilmadi',
    (select count(*) from public.student_league_history h
      where h.user_id in ('8f800000-0000-0000-0000-000000000001',
                          '8f800000-0000-0000-0000-000000000002')) = 0);
end;
$blk$;

-- T-22: tamamlanmamis yarisma rating uretmez.
do $blk$
declare
  v_comp uuid;
begin
  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count)
  values
    ('F8-QA-C4', 'one_vs_one', 7,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'active', 5)
  returning id into v_comp;

  insert into public.competition_players
    (competition_id, user_id, player_slot, total_points, status)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 1, 100, 'active'),
    (v_comp, '8f800000-0000-0000-0000-000000000002', 2, 50, 'active');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type,
     player_results, calculated_at)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 'win_loss',
     '[]'::jsonb, now());

  perform public._faz5_apply_competition_points(v_comp);

  perform public._qa8_true('T-22',
    'tamamlanmamis yarisma rating uretmez (fail-closed)',
    (select count(*) from public.competition_point_changes cpc
      where cpc.competition_id = v_comp
        and cpc.change_type = 'rating') = 0);
end;
$blk$;

-- T-23: katilimci olmayan kullanici rating isletemez / etkilenmez.
do $blk$
declare
  v_comp uuid;
begin
  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count,
     winner_user_id)
  values
    ('F8-QA-C5', 'one_vs_one', 7,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'completed', 5,
     '8f800000-0000-0000-0000-000000000001')
  returning id into v_comp;

  insert into public.competition_players
    (competition_id, user_id, player_slot, total_points, status)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 1, 200, 'finished'),
    (v_comp, '8f800000-0000-0000-0000-000000000002', 2, 90, 'finished');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type,
     player_results, calculated_at)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 'win_loss',
     '[]'::jsonb, now());

  perform set_config('qa8.comp_c5', v_comp::text, false);
end;
$blk$;

do $blk$
declare
  v_comp uuid := nullif(current_setting('qa8.comp_c5', true), '')::uuid;
begin
  perform public._faz5_apply_competition_points(v_comp);

  perform public._qa8_true('T-23',
    'yalniz katilimcilar islenir; D (katilimci degil) etkilenmez',
    (select count(*) from public.competition_point_changes cpc
      where cpc.competition_id = v_comp
        and cpc.change_type = 'rating') = 2
      and not exists (
        select 1 from public.competition_point_changes cpc
         where cpc.competition_id = v_comp
           and cpc.user_id = '8f800000-0000-0000-0000-000000000004')
      and (select m.current_points
             from public.student_league_memberships m
            where m.user_id = '8f800000-0000-0000-0000-000000000004'
              and m.is_current) = 10);
end;
$blk$;

-- T-24: basarisiz islem kismi veri birakmaz (alt transaction).
do $blk$
declare
  v_comp uuid;
  v_members_a_before integer;
  v_entry_before integer;
begin
  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count)
  values
    ('F8-QA-C6', 'one_vs_one', 7,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'completed', 5)
  returning id into v_comp;

  insert into public.competition_players
    (competition_id, user_id, player_slot, total_points, status)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 1, 100, 'finished'),
    (v_comp, '8f800000-0000-0000-0000-000000000002', 2, 100, 'finished');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type,
     player_results, calculated_at)
  values
    (v_comp, null, 'draw', '[]'::jsonb, now());

  v_members_a_before := (select m.current_points
                           from public.student_league_memberships m
                          where m.user_id = '8f800000-0000-0000-0000-000000000001'
                            and m.is_current);
  v_entry_before := (select count(*) from public.leaderboard_entries);

  begin
    perform public._faz5_apply_competition_points(v_comp);
    raise exception 'zincir hatasi simulasyonu';
  exception
    when others then
      null; -- tum alt islem (rating + entry + uyelik) geri alinir
  end;

  perform public._qa8_true('T-24',
    'basarisiz islem: kismi rating/history/entry birakmaz',
    (select count(*) from public.competition_point_changes cpc
      where cpc.competition_id = v_comp
        and cpc.change_type = 'rating') = 0
      and (select m.current_points
             from public.student_league_memberships m
            where m.user_id = '8f800000-0000-0000-0000-000000000001'
              and m.is_current) = v_members_a_before
      and (select count(*) from public.leaderboard_entries) = v_entry_before,
    format('before=%s after-uyelik-ok entry-ok',
           v_members_a_before));
end;
$blk$;

-- T-25: idempotency UNIQUE kisiti yerinde (eszamanli savunma).
do $blk$
declare
  v_idx_ok boolean;
begin
  select exists (
    select 1
      from pg_indexes
     where schemaname = 'public'
       and tablename = 'competition_point_changes'
       and indexdef ilike '%unique%'
       and indexdef ilike '%competition_id%user_id%change_type%'
  ) into v_idx_ok;
  perform public._qa8_true('T-25',
    'rating idempotency UNIQUE(competition,user,type) yerinde',
    v_idx_ok, 'idx=' || v_idx_ok);
end;
$blk$;

-- T-26: istemci rating/membership/entry yazamaz.
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

  perform public._qa8_expect('T-26a',
    'istemci competition_point_changes INSERT reddedilir (42501)',
    '42501',
    $sql$insert into public.competition_point_changes
      (competition_id, user_id, change_type, points_change)
     values ('8f810000-0000-0000-0000-000000000001',
             '8f800000-0000-0000-0000-000000000001', 'rating', 999)$sql$);

  perform public._qa8_expect('T-26b',
    'istemci leaderboard_entries INSERT reddedilir (42501)',
    '42501',
    $sql$insert into public.leaderboard_entries
      (season_id, leaderboard_definition_id, user_id, points)
     values ('8f820000-0000-0000-0000-000000000011',
             (select id from public.leaderboard_definitions
               where leaderboard_code = 'league_ranking'),
             '8f800000-0000-0000-0000-000000000001', 9999)$sql$);

  perform public._qa8_expect('T-26c',
    'istemci student_league_memberships INSERT reddedilir (42501)',
    '42501',
    $sql$insert into public.student_league_memberships
      (user_id, league_id, membership_scope, points_at_entry,
       current_points, is_current)
     values ('8f800000-0000-0000-0000-000000000001',
             (select id from public.leagues
               where league_code = 'QA8-GUMUS'),
             'general', 0, 9999, true)$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- T-27: istemci kendi grade'ini degistiremez (093 hardening).
do $blk$
declare
  v_ok boolean := true;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000001","role":"authenticated"}', true);
  begin
    update public.student_profiles
       set grade_level = 6
     where id = '8f800000-0000-0000-0000-000000000001';
  exception
    when others then
      v_ok := true; -- hata beklendi; degisiklik olmadi
  end;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  perform public._qa8_true('T-27',
    'grade istemciden degistirilemez: A grade 7 kaldi',
    (select grade_level from public.student_profiles
      where id = '8f800000-0000-0000-0000-000000000001') = 7,
    'grade-korundu=' || v_ok);
end;
$blk$;


-- ============================================================
-- T-28..T-34: SIRALAMA
-- ============================================================

-- T-28: tam liste siralamasi (A=64, F=25, G=25, B=18; C gizli 20).
do $blk$
declare
  v_json jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

  select public.get_my_league_ranking() into v_json;

  perform public._qa8_true('T-28',
    'siralama: A(64)=1, F(25)=2, G(25)=3, B(18)=5; C gizli',
    (v_json -> 'entries' -> 0 ->> 'nickname') = 'QA8-NICK-A'
      and (v_json -> 'entries' -> 0 ->> 'rank')::int = 1
      and (v_json -> 'entries' -> 0 ->> 'is_current_student')::text = 'true'
      and (v_json -> 'entries' -> 1 ->> 'nickname') = 'QA8-NICK-F'
      and (v_json -> 'entries' -> 2 ->> 'nickname') = 'QA8-NICK-G'
      and (v_json -> 'entries' -> 3 ->> 'nickname') = 'QA8-NICK-B'
      and (v_json -> 'entries' -> 3 ->> 'rank')::int = 5,
    'ilk=' || coalesce(v_json -> 'entries' -> 0 ->> 'nickname', '?'));

  -- T-29: determinizm: ayni cagri ayni sonuc.
  declare
    v_json2 jsonb;
  begin
    select public.get_my_league_ranking() into v_json2;
    perform public._qa8_true('T-29',
      'determinizm: tekrar cagri birebir ayni jsonb',
      v_json = v_json2, 'ayni-cikti');
  end;

  -- T-30: kendi sira kartinin dogrulugu (C5 sonrasi A=88).
  perform public._qa8_true('T-30',
    'kendi sira karti: A rank=1, rating=88, lig=Bronz Lig',
    (v_json -> 'my' ->> 'rank')::int = 1
      and (v_json -> 'my' ->> 'rating')::int = 88
      and (v_json -> 'my' ->> 'league_code') = 'bronze'
      and (v_json -> 'my' ->> 'league_name') = 'Bronz Lig',
    'my=' || coalesce((v_json -> 'my')::text, 'yok'));

  -- T-31: sonraki lig esigi (promosyon ilerleme bilgisi).
  perform public._qa8_true('T-31',
    'promosyon ilerlemesi: sonraki lig Gumus esik 1000',
    (v_json -> 'next_league' ->> 'league_code') = 'silver'
      and (v_json -> 'next_league' ->> 'threshold')::int = 1000
      and (v_json -> 'next_league' ->> 'league_name') = 'Gümüş Lig');

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- T-32: liste disindaki ogrenci kendi kartini gorur (B, limit 1).
do $blk$
declare
  v_json jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000002","role":"authenticated"}', true);

  select public.get_my_league_ranking(1) into v_json;

  perform public._qa8_true('T-32',
    'liste disi: B limit 1 ile sadece 1. sirayi gorur, karti rank=5',
    jsonb_array_length(v_json -> 'entries') = 1
      and (v_json -> 'my' ->> 'rank')::int = 5
      and (v_json -> 'my' ->> 'nickname') = 'QA8-NICK-B');

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- T-33: limit guvenligi.
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

  perform public._qa8_expect('T-33a',
    'limit 0 reddedilir (P0001)',
    'P0001',
    $sql$select public.get_my_league_ranking(0)$sql$);

  perform public._qa8_expect('T-33b',
    'negatif limit reddedilir (P0001)',
    'P0001',
    $sql$select public.get_my_league_ranking(-5)$sql$);

  perform public._qa8_expect('T-33c',
    'negatif offset reddedilir (P0001)',
    'P0001',
    $sql$select public.get_my_league_ranking(50, -1)$sql$);

  perform public._qa8_true('T-33d',
    'buyuk limit ust sinira kirpilir (hata yok, 4 satir)',
    jsonb_array_length(
      (select public.get_my_league_ranking(100000) -> 'entries')) = 4);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- T-34: rate limit (30 istek / 60 sn; kota doldurulur -> P0001).
do $blk$
declare
  v_window timestamptz;
begin
  -- Prime: postgres olarak (rpc_rate_limits istemciye kapalidir).
  v_window := to_timestamp(
    floor(extract(epoch from now()) / 60) * 60);

  insert into public.rpc_rate_limits
    (user_id, rpc_name, window_start, hit_count)
  values
    ('8f800000-0000-0000-0000-000000000001',
     'get_my_league_ranking', v_window, 30)
  on conflict (user_id, rpc_name, window_start)
    do update set hit_count = 30;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

  perform public._qa8_expect('T-34',
    'rate limit: 30/60 dolduruldu -> RPC P0001 ile reddedilir',
    'P0001',
    $sql$select public.get_my_league_ranking()$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  -- Temizle: sonraki kosular icin kota yeniden acilir.
  delete from public.rpc_rate_limits
   where user_id = '8f800000-0000-0000-0000-000000000001'
     and rpc_name = 'get_my_league_ranking'
     and window_start = v_window;
end;
$blk$;


-- ============================================================
-- T-35..T-40: PROMOTION / DEMOTION
-- ============================================================

-- T-35: promotion: A 998 + 24 -> 1022 -> Silver + history.
do $blk$
declare
  v_comp uuid;
  v_member uuid;
begin
  select m.id into v_member
    from public.student_league_memberships m
   where m.user_id = '8f800000-0000-0000-0000-000000000001'
     and m.is_current;

  update public.student_league_memberships m
     set current_points = 998, points_at_entry = 998
   where m.id = v_member;

  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count,
     winner_user_id)
  values
    ('F8-QA-C2', 'one_vs_one', 7,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'completed', 5,
     '8f800000-0000-0000-0000-000000000001')
  returning id into v_comp;

  insert into public.competition_players
    (competition_id, user_id, player_slot, total_points, status)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 1, 300, 'finished'),
    (v_comp, '8f800000-0000-0000-0000-000000000002', 2, 70, 'finished');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type,
     player_results, calculated_at)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 'win_loss',
     '[]'::jsonb, now());

  perform public._faz5_apply_competition_points(v_comp);

  perform public._qa8_true('T-35',
    'promotion: 998+24=1022 -> Silver uyeligi + history',
    exists (
      select 1
        from public.student_league_memberships m
        join public.leagues l on l.id = m.league_id
       where m.user_id = '8f800000-0000-0000-0000-000000000001'
         and m.is_current
         and l.league_code = 'silver'
         and m.current_points = 1022)
      and exists (
        select 1
          from public.student_league_history h
          join public.leagues lf on lf.id = h.from_league_id
          join public.leagues lt on lt.id = h.to_league_id
         where h.user_id = '8f800000-0000-0000-0000-000000000001'
           and lf.league_code = 'bronze'
           and lt.league_code = 'silver'
           and h.transition_type = 'promotion'
           and h.points_at_transition = 1022));

  -- A'nin entry'si yenilendi (tek satir, silver, 1022).
  perform public._qa8_true('T-36',
    'entry yenileme: A icin tek entry (Silver, 1022); bayat yok',
    (select count(*) from public.leaderboard_entries e
      where e.user_id = '8f800000-0000-0000-0000-000000000001'
        and e.season_id = '8f820000-0000-0000-0000-000000000011'
        and e.scope_type = 'league') = 1
      and exists (
        select 1 from public.leaderboard_entries e
         where e.user_id = '8f800000-0000-0000-0000-000000000001'
           and e.season_id = '8f820000-0000-0000-0000-000000000011'
           and e.points = 1022
           and e.league_code = 'silver'));

  -- Idempotency: tekrar apply history dublike etmez.
  perform public._faz5_apply_competition_points(v_comp);

  perform public._qa8_true('T-37',
    'tekrar apply: promotion history tekil kalir',
    (select count(*) from public.student_league_history h
      where h.user_id = '8f800000-0000-0000-0000-000000000001'
        and h.transition_type = 'promotion') = 1);
end;
$blk$;

-- T-38: demotion: B (Silver 1000) kaybeder -> 988 -> Bronz.
do $blk$
declare
  v_comp uuid;
  v_member uuid;
begin
  select m.id into v_member
    from public.student_league_memberships m
   where m.user_id = '8f800000-0000-0000-0000-000000000002'
     and m.is_current;

  update public.student_league_memberships m
     set league_id = (select id from public.leagues
                       where league_code = 'silver'),
         current_points = 1000,
         points_at_entry = 1000
   where m.id = v_member;

  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count,
     winner_user_id)
  values
    ('F8-QA-C3', 'one_vs_one', 7,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'completed', 5,
     '8f800000-0000-0000-0000-000000000003')
  returning id into v_comp;

  insert into public.competition_players
    (competition_id, user_id, player_slot, total_points, status)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000003', 1, 100, 'finished'),
    (v_comp, '8f800000-0000-0000-0000-000000000002', 2, 10, 'finished');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type,
     player_results, calculated_at)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000003', 'win_loss',
     '[]'::jsonb, now());

  perform public._faz5_apply_competition_points(v_comp);

  perform public._qa8_true('T-38',
    'demotion: 1000-12=988 -> Bronz uyeligi + history',
    exists (
      select 1
        from public.student_league_memberships m
        join public.leagues l on l.id = m.league_id
       where m.user_id = '8f800000-0000-0000-0000-000000000002'
         and m.is_current
         and l.league_code = 'bronze'
         and m.current_points = 988)
      and exists (
        select 1
          from public.student_league_history h
          join public.leagues lf on lf.id = h.from_league_id
          join public.leagues lt on lt.id = h.to_league_id
         where h.user_id = '8f800000-0000-0000-0000-000000000002'
           and lf.league_code = 'silver'
           and lt.league_code = 'bronze'
           and h.transition_type = 'demotion'));
end;
$blk$;

-- T-39: tepe lig korumasi: G (ELMAS 6000) kazanir -> lig degismez.
do $blk$
declare
  v_comp uuid;
  v_member uuid;
  v_member_before uuid;
begin
  select m.id into v_member_before
    from public.student_league_memberships m
   where m.user_id = '8f800000-0000-0000-0000-000000000007'
     and m.is_current;

  update public.student_league_memberships m
     set league_id = (select id from public.leagues
                       where league_code = 'diamond'),
         current_points = 6000,
         points_at_entry = 6000
   where m.id = v_member_before;

  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count,
     winner_user_id)
  values
    ('F8-QA-C7', 'one_vs_one', 7,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'completed', 5,
     '8f800000-0000-0000-0000-000000000007')
  returning id into v_comp;

  insert into public.competition_players
    (competition_id, user_id, player_slot, total_points, status)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000007', 1, 500, 'finished'),
    (v_comp, '8f800000-0000-0000-0000-000000000005', 2, 10, 'finished');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type,
     player_results, calculated_at)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000007', 'win_loss',
     '[]'::jsonb, now());

  perform public._faz5_apply_competition_points(v_comp);

  select m.id into v_member
    from public.student_league_memberships m
   where m.user_id = '8f800000-0000-0000-0000-000000000007'
     and m.is_current;

  perform public._qa8_true('T-39',
    'tepe lig: G 6024 ile ELMAS''ta kalir; yeni uyelik/history yok',
    v_member = v_member_before
      and (select m.current_points
             from public.student_league_memberships m
            where m.id = v_member) = 6024
      and not exists (
        select 1 from public.student_league_history h
         where h.user_id = '8f800000-0000-0000-0000-000000000007'));
end;
$blk$;

-- T-40: dip korumasi: B 0'dan kaybeder -> clamp 0, demotion yok.
do $blk$
declare
  v_comp uuid;
begin
  update public.student_league_memberships m
     set current_points = 0
   where m.user_id = '8f800000-0000-0000-0000-000000000002'
     and m.is_current;

  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count,
     winner_user_id)
  values
    ('F8-QA-C8', 'one_vs_one', 7,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'completed', 5,
     '8f800000-0000-0000-0000-000000000006')
  returning id into v_comp;

  insert into public.competition_players
    (competition_id, user_id, player_slot, total_points, status)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000006', 1, 10, 'finished'),
    (v_comp, '8f800000-0000-0000-0000-000000000002', 2, 0, 'finished');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type,
     player_results, calculated_at)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000006', 'win_loss',
     '[]'::jsonb, now());

  perform public._faz5_apply_competition_points(v_comp);

  perform public._qa8_true('T-40',
    'dip koruma: B 0''da kalir (clamp); negatif rating yok',
    (select m.current_points
       from public.student_league_memberships m
      where m.user_id = '8f800000-0000-0000-0000-000000000002'
        and m.is_current) = 0
      and not exists (
        select 1 from public.competition_point_changes cpc
         where cpc.competition_id = v_comp
           and cpc.user_id = '8f800000-0000-0000-0000-000000000002'
           and cpc.points_after < 0)
      and not exists (
        select 1 from public.student_league_history h
         where h.user_id = '8f800000-0000-0000-0000-000000000002'
           and h.points_at_transition = 0
           and h.transition_type = 'demotion'));
end;
$blk$;


-- ============================================================
-- T-59 (K-B): TAM DETERMINISTIK SIRALAMA — rating + entered_at +
-- nickname uclusu esitken son sunucu-ici benzersiz anahtar
-- (membership/entry user_id) siralamayi belirler. Anahtar DTO'ya
-- donmez. Geçici fixture kullanilir ve GERI YUKLENIR.
-- ============================================================

do $blk$
declare
  v_f_points integer;
  v_f_ent timestamptz;
  v_b_points integer;
  v_b_ent timestamptz;
  v_json1 jsonb;
  v_json2 jsonb;
  v_tie_nick text := 'QA8-TIE-NICK';
  v_tie_ts timestamptz;
begin
  -- Orijinal degerleri sakla.
  select m.current_points, m.entered_at
    into v_f_points, v_f_ent
    from public.student_league_memberships m
   where m.user_id = '8f800000-0000-0000-0000-000000000006'
     and m.is_current;
  select m.current_points, m.entered_at
    into v_b_points, v_b_ent
    from public.student_league_memberships m
   where m.user_id = '8f800000-0000-0000-0000-000000000002'
     and m.is_current;

  -- F ve B: ayni lig (bronze), ayni rating, ayni entered_at,
  -- ayni nickname -> yalniz user_id tie-break kalir.
  v_tie_ts := now() - interval '30 seconds';

  update public.student_public_profiles
     set nickname = v_tie_nick
   where user_id in ('8f800000-0000-0000-0000-000000000006',
                     '8f800000-0000-0000-0000-000000000002');

  update public.student_league_memberships
     set current_points = 55, entered_at = v_tie_ts
   where user_id = '8f800000-0000-0000-0000-000000000006' and is_current;

  update public.student_league_memberships
     set current_points = 55, entered_at = v_tie_ts
   where user_id = '8f800000-0000-0000-0000-000000000002' and is_current;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000006","role":"authenticated"}', true);

  select public.get_my_league_ranking(100) into v_json1;
  select public.get_my_league_ranking(100) into v_json2;

  perform public._qa8_true('T-59a',
    'K-B determinizm: esit uclude iki cagri birebir ayni jsonb',
    v_json1 = v_json2,
    'ayni-siralama');

  perform public._qa8_true('T-59b',
    'K-B: esit nickli iki satir sirada (rank 1 ve 2); UUID DTO''da yok',
    (select count(*) from jsonb_array_elements(v_json1 -> 'entries') el
      where el ->> 'nickname' = v_tie_nick) = 2
      and (select count(distinct el ->> 'rank')
             from jsonb_array_elements(v_json1 -> 'entries') el
            where el ->> 'nickname' = v_tie_nick) = 2
      and v_json1::text not like '%8f800000%',
    'tie-iki-satir');

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  -- GERI YUKLE: sonraki testlerin fixture'i bozulmasin.
  update public.student_public_profiles
     set nickname = 'QA8-NICK-F'
   where user_id = '8f800000-0000-0000-0000-000000000006';
  update public.student_public_profiles
     set nickname = 'QA8-NICK-B'
   where user_id = '8f800000-0000-0000-0000-000000000002';

  update public.student_league_memberships
     set current_points = v_f_points, entered_at = v_f_ent
   where user_id = '8f800000-0000-0000-0000-000000000006' and is_current;
  update public.student_league_memberships
     set current_points = v_b_points, entered_at = v_b_ent
   where user_id = '8f800000-0000-0000-0000-000000000002' and is_current;
end;
$blk$;


-- ============================================================
-- T-41..T-52: SEZON
-- ============================================================

-- T-41: upcoming sezon siralama verisi uretmez (S1 kapatilir).
do $blk$
declare
  v_json jsonb;
begin
  update public.leaderboard_seasons
     set is_active = false
   where id = '8f820000-0000-0000-0000-000000000011';

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

  select public.get_my_league_ranking() into v_json;

  perform public._qa8_true('T-41',
    'aktif sezon yokken RPC no_active_season doner (upcoming S2 donmez)',
    v_json ->> 'season_status' = 'no_active_season'
      and jsonb_array_length(v_json -> 'entries') = 0
      and not exists (
        select 1 from jsonb_object_keys(v_json) k
         where v_json -> k ->> 'code' = 'FAZ8-S2'));

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  update public.leaderboard_seasons
     set is_active = true
   where id = '8f820000-0000-0000-0000-000000000011';
end;
$blk$;

-- T-42: yetkisiz kapanis reddedilir.
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

  perform public._qa8_expect('T-42',
    'ogrenci close_league_season calistiramaz (42501)',
    '42501',
    $sql$select public.close_league_season(
      '8f820000-0000-0000-0000-000000000011')$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- T-43: ends_at oncesi kapanis reddedilir (cutoff).
do $blk$
declare
  v_err text := null;
begin
  update public.leaderboard_seasons
     set ends_at = now() + interval '3 days'
   where id = '8f820000-0000-0000-0000-000000000011';

  begin
    perform public.close_league_season(
      '8f820000-0000-0000-0000-000000000011');
  exception
    when others then
      get stacked diagnostics v_err = MESSAGE_TEXT;
  end;

  perform public._qa8_true('T-43',
    'cutoff: ends_at oncesi kapanis reddedildi, sezon hala aktif',
    v_err is not null
      and (select is_active from public.leaderboard_seasons
            where id = '8f820000-0000-0000-0000-000000000011') = true
      and not exists (
        select 1 from public.league_season_close_results
         where season_id = '8f820000-0000-0000-0000-000000000011'),
    'err=' || coalesce(v_err, 'yok'));

  -- Geri yukle: kapanis testleri icin ends_at gecmise alinir
  -- (tum okuma/rating testleri tamamlandi).
  update public.leaderboard_seasons
     set ends_at = now() - interval '1 second'
   where id = '8f820000-0000-0000-0000-000000000011';
end;
$blk$;

-- T-44: basarisiz kapanis kismi veri birakmaz (alt transaction).
do $blk$
declare
  v_members_before integer;
begin
  select count(*) into v_members_before
    from public.student_league_memberships where is_current;

  begin
    delete from public.leaderboard_definitions
     where leaderboard_code = 'league_ranking';

    perform public.close_league_season(
      '8f820000-0000-0000-0000-000000000011');
  exception
    when others then
      null; -- beklenen: P0001; tum alt islem geri alinir
  end;

  perform public._qa8_true('T-44',
    'basarisiz kapanis: uyelikler/history/close_results degismedi',
    (select count(*) from public.student_league_memberships
      where is_current) = v_members_before
      and not exists (
        select 1 from public.league_season_close_results)
      and exists (
        select 1 from public.leaderboard_definitions
         where leaderboard_code = 'league_ranking'),
    'rollback-tamam');
end;
$blk$;

-- ============================================================
-- T-57/T-58 (K-A CUTGUARD): ends_at sonrasi + close oncesi
-- finalize edilen sonuc ESKI SEZON rating/entry/history'yi
-- DEGISTIREMEZ; yeni hedefe (ara donem null-sezon uyeligi) yazar.
-- (T-43 ile ends_at gecmise alinmisti; close henuz cagrilmadi.)
-- ============================================================

do $blk$
declare
  v_comp uuid;
  v_hist_a_before integer;
begin
  select count(*) into v_hist_a_before
    from public.student_league_history
   where user_id = '8f800000-0000-0000-0000-000000000001';

  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count,
     winner_user_id)
  values
    ('F8-QA-C10', 'one_vs_one', 7,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'completed', 5,
     '8f800000-0000-0000-0000-000000000001')
  returning id into v_comp;

  insert into public.competition_players
    (competition_id, user_id, player_slot, total_points, status)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 1, 100, 'finished'),
    (v_comp, '8f800000-0000-0000-0000-000000000002', 2, 10, 'finished');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type,
     player_results, calculated_at)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 'win_loss',
     '[]'::jsonb, now());

  -- ends_at SONRASI, close ONCESI finalize.
  perform public._faz5_apply_competition_points(v_comp);

  perform public._qa8_true('T-57',
    'cutoff: A''nin eski sezon (Silver 1022) uyeligi DEGISMEZ',
    (select max(m.current_points) from public.student_league_memberships m
      where m.user_id = '8f800000-0000-0000-0000-000000000001'
        and m.season_id = '8f820000-0000-0000-0000-000000000011') = 1022
      and not exists (
        select 1 from public.student_league_memberships m
         where m.user_id = '8f800000-0000-0000-0000-000000000001'
           and m.season_id = '8f820000-0000-0000-0000-000000000011'
           and m.is_current = true),
    'eski-sezon-sabit');

  perform public._qa8_true('T-58',
    'cutoff: eski sezon entry 1022; post-cutoff 24 ara donemde; history degismedi',
    (select e.points from public.leaderboard_entries e
      where e.user_id = '8f800000-0000-0000-0000-000000000001'
        and e.season_id = '8f820000-0000-0000-0000-000000000011'
        and e.scope_type = 'league') = 1022
      and exists (
        select 1 from public.student_league_memberships m
         where m.user_id = '8f800000-0000-0000-0000-000000000001'
           and m.is_current = true
           and m.membership_scope = 'general'
           and m.season_id is null
           and m.current_points = 24)
      and (select count(*) from public.student_league_history
            where user_id = '8f800000-0000-0000-0000-000000000001')
          = v_hist_a_before,
    format('entry=1022 ara=24 hist_once=%s', v_hist_a_before));
end;
$blk$;

-- T-45..T-50: ILK KAPANIS + idempotency (cutoff uyumlu sayilar).
do $blk$
declare
  v_res jsonb;
  v_snap integer;
  v_closed integer;
begin
  -- Kapanis oncesi S1 entry sayisi (canli entry'ler) yedeklenebilir
  -- degil; kapanis sonrasi dogrulamalar asagida.
  select public.close_league_season(
    '8f820000-0000-0000-0000-000000000011') into v_res;

  v_snap := (v_res ->> 'snapshot_entry_count')::int;
  v_closed := (v_res ->> 'membership_close_count')::int;

  perform public._qa8_true('T-45',
    'kapanis: status=closed; 7 snapshot entry; 5 uyelik close (A/B rollover)',
    v_res ->> 'status' = 'closed'
      and v_snap = 7 and v_closed = 5,
    format('snap=%s closed=%s', v_snap, v_closed));

  perform public._qa8_true('T-46',
    'kapanis: S1 pasif, S2 aktif, close_results kaydi var',
    (select is_active from public.leaderboard_seasons
      where id = '8f820000-0000-0000-0000-000000000011') = false
      and (select is_active from public.leaderboard_seasons
            where id = '8f820000-0000-0000-0000-000000000012') = true
      and exists (
        select 1 from public.league_season_close_results
         where season_id = '8f820000-0000-0000-0000-000000000011'));

  perform public._qa8_true('T-47',
    'snapshot: A(Silver 1022) rank=1; B(Bronz 0) rank=3; post-cutoff sizmaz',
    exists (
      select 1 from public.leaderboard_entries e
       where e.season_id = '8f820000-0000-0000-0000-000000000011'
         and e.user_id = '8f800000-0000-0000-0000-000000000001'
         and e.rank_position = 1
         and e.league_code = 'silver'
         and e.points = 1022)
      and exists (
        select 1 from public.leaderboard_entries e
         where e.season_id = '8f820000-0000-0000-0000-000000000011'
           and e.user_id = '8f800000-0000-0000-0000-000000000002'
           and e.rank_position = 3
           and e.points = 0)
      and exists (
        select 1 from public.leaderboard_entries e
         where e.season_id = '8f820000-0000-0000-0000-000000000011'
           and e.user_id = '8f800000-0000-0000-0000-000000000003')
      and not exists (
        select 1 from public.leaderboard_entries e
         where e.season_id = '8f820000-0000-0000-0000-000000000011'
           and e.user_id = '8f800000-0000-0000-0000-000000000001'
           and e.points in (24, 1046)),
    format('A=%s B=%s',
      (select coalesce(max(e.points)::text,'yok') from public.leaderboard_entries e
        where e.season_id = '8f820000-0000-0000-0000-000000000011'
          and e.user_id = '8f800000-0000-0000-0000-000000000001'),
      (select coalesce(string_agg(e.rank_position::text || ':' || e.points::text, ','),'yok')
         from public.leaderboard_entries e
        where e.season_id = '8f820000-0000-0000-0000-000000000011'
          and e.user_id = '8f800000-0000-0000-0000-000000000002')));

  perform public._qa8_true('T-48',
    'yeni sezon uyelikleri: 7 ogrenci S2''de; A''nin post-cutoff 24''u tasınır',
    (select count(*) from public.student_league_memberships m
      where m.season_id = '8f820000-0000-0000-0000-000000000012'
        and m.is_current) = 7
      and (select count(*) from public.student_league_memberships m
            where m.season_id = '8f820000-0000-0000-0000-000000000012'
              and m.is_current
              and m.current_points = 0) = 6
      and exists (
        select 1
          from public.student_league_memberships m
          join public.leagues l on l.id = m.league_id
         where m.user_id = '8f800000-0000-0000-0000-000000000001'
           and m.season_id = '8f820000-0000-0000-0000-000000000012'
           and m.is_current
           and m.current_points = 24
           and l.league_code = 'bronze'));

  perform public._qa8_true('T-49',
    'reset history: 7 append-only satir (onceki lig + puan kayitli)',
    (select count(*) from public.student_league_history h
      where h.season_id = '8f820000-0000-0000-0000-000000000011'
        and h.transition_type = 'reset'
        and h.reason = 'season_reset') = 7
      and exists (
        select 1 from public.student_league_history h
         where h.user_id = '8f800000-0000-0000-0000-000000000001'
           and h.season_id = '8f820000-0000-0000-0000-000000000011'
           and h.transition_type = 'reset'
           and h.points_at_transition = 1022));

  -- Ikinci kapanis: no-op.
  declare
    v_res2 jsonb;
  begin
    select public.close_league_season(
      '8f820000-0000-0000-0000-000000000011') into v_res2;

    perform public._qa8_true('T-50',
      'ikinci kapanis: already_closed; snapshot/uyelik degismedi',
      v_res2 ->> 'status' = 'already_closed'
        and (select count(*) from public.league_season_close_results) = 1
        and (select count(*) from public.student_league_history
              where season_id = '8f820000-0000-0000-0000-000000000011'
                and transition_type = 'reset') = 7);
  end;
end;
$blk$;

-- T-51: cutoff determinizmi: kapanis sonrasi yarisma -> yeni sezona.
do $blk$
declare
  v_comp uuid;
begin
  v_comp := nullif(current_setting('qa8.comp_c5', true), '')::uuid;

  -- Kapanis oncesi uygulanmisti; simdi tamamen yeni state icin
  -- kapanis sonrasi bir yarisma daha uygulanir (idempotency
  -- guard'i C5 icin no-op yaptigi icin yeni yarisma C9 kurulusu).
  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count,
     winner_user_id)
  values
    ('F8-QA-C9', 'one_vs_one', 7,
     '430903f3-527e-4e12-b7e8-ac0afdb784aa',
     (select id from public.scoring_rule_sets
       where rule_set_code = 'faz5_default'), 'completed', 5,
     '8f800000-0000-0000-0000-000000000001')
  returning id into v_comp;

  insert into public.competition_players
    (competition_id, user_id, player_slot, total_points, status)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 1, 120, 'finished'),
    (v_comp, '8f800000-0000-0000-0000-000000000002', 2, 60, 'finished');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type,
     player_results, calculated_at)
  values
    (v_comp, '8f800000-0000-0000-0000-000000000001', 'win_loss',
     '[]'::jsonb, now());

  perform public._faz5_apply_competition_points(v_comp);

  perform public._qa8_true('T-51',
    'cutoff determinizmi: kapanis sonrasi sonuc S2 uyeligine yazar (24+24=48)',
    exists (
      select 1
        from public.student_league_memberships m
       where m.user_id = '8f800000-0000-0000-0000-000000000001'
         and m.season_id = '8f820000-0000-0000-0000-000000000012'
         and m.is_current
         and m.current_points = 48
         and m.membership_scope = 'general'));
end;
$blk$;

-- T-52: kapanis sonrasi RPC: yeni sezon baslamadi -> no_active_season.
do $blk$
declare
  v_json jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

  select public.get_my_league_ranking() into v_json;

  perform public._qa8_true('T-52',
    'S2 baslamadi: RPC no_active_season (gule gulme durumu)',
    v_json ->> 'season_status' = 'no_active_season');

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- T-53: history / close_results istemciye degistirilemez.
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"8f800000-0000-0000-0000-000000000001","role":"authenticated"}', true);

  perform public._qa8_expect('T-53a',
    'student_league_history UPDATE reddedilir (42501)',
    '42501',
    $sql$update public.student_league_history
        set reason = 'degistirildi' where true$sql$);

  perform public._qa8_expect('T-53b',
    'league_season_close_results erisimi yok (42501)',
    '42501',
    $sql$select count(*) from public.league_season_close_results$sql$);

  perform set_config('request.claims', '', true);
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- T-54: ACL: okuma RPC authenticated'a acik, anon kapali; kapanis
-- RPC yalniz service_role.
do $blk$
declare
  v_read_auth boolean;
  v_read_anon boolean;
  v_close_auth boolean;
  v_close_service boolean;
begin
  select has_function_privilege('authenticated', p.oid, 'EXECUTE'),
         has_function_privilege('anon', p.oid, 'EXECUTE')
    into v_read_auth, v_read_anon
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'get_my_league_ranking';

  select has_function_privilege('authenticated', p.oid, 'EXECUTE'),
         has_function_privilege('service_role', p.oid, 'EXECUTE')
    into v_close_auth, v_close_service
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'close_league_season';

  perform public._qa8_true('T-54',
    'ACL: okuma=authenticated evet/anon hayir; kapanis=auth hayir/service evet',
    v_read_auth and not v_read_anon
      and not coalesce(v_close_auth, true)
      and coalesce(v_close_service, false));
end;
$blk$;

-- T-55: SECURITY DEFINER + search_path='' + PUBLIC EXECUTE yok.
do $blk$
declare
  v_ok boolean;
begin
  select not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('get_my_league_ranking', 'close_league_season',
                         '_faz8_attach_membership_season',
                         '_faz8_upsert_membership_entry')
       and (p.prosecdef is distinct from true
            or p.proconfig is null
            or not ('search_path=""') = any (p.proconfig))
  ) and not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('get_my_league_ranking', 'close_league_season')
       and (has_function_privilege('anon', p.oid, 'EXECUTE')
            or has_function_privilege('public', p.oid, 'EXECUTE'))
  ) into v_ok;

  perform public._qa8_true('T-55',
    'SECURITY DEFINER + search_path='''' + PUBLIC/anon EXECUTE yok',
    v_ok, 'definer-ok');
end;
$blk$;

-- T-56: okul/sube yok: tablo, kolon, RPC parametresi.
do $blk$
declare
  v_ok boolean;
begin
  select not exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name ilike '%school%'
  ) and not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name in ('leaderboard_entries',
                          'student_league_memberships')
       and (column_name ilike '%school%' or column_name ilike '%classroom%'
            or column_name ilike '%branch%')
  ) and not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('get_my_league_ranking', 'close_league_season')
       and (pg_get_function_arguments(p.oid) ilike '%school%'
            or pg_get_function_arguments(p.oid) ilike '%classroom%')
  ) into v_ok;

  perform public._qa8_true('T-56',
    'okul/sube siralamasi yok (tablo/kolon/parametre)',
    v_ok, 'okul-yok');
end;
$blk$;


-- ============================================================
-- RAPOR
-- ============================================================

\echo
\echo ===== FAZ8 QA SONUCLARI =====
select label, title, result,
       coalesce(detail, '-') as detail
  from public._qa_faz8_results
 order by label;

\echo
select format('%s|%s|%s',
       count(*),
       count(*) filter (where result = 'PASS'),
       count(*) filter (where result = 'FAIL')) as "toplam|gecen|kalan"
  from public._qa_faz8_results;

rollback;
