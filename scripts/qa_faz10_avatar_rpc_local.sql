-- ============================================================
-- scripts/qa_faz10_avatar_rpc_local.sql
-- Altin Kalemler - Faz 10 QA (107: avatar secimi + nickname sync)
--
-- A: Profil okuma/yazma sinirlari (001 RLS + 093 kolon-ayricaligi)
-- B: select_own_avatar guvenlik matrisi (katalog, kilitli/pasif,
--    sahte kod, dis URL, baskasinin avatarı, idempotentlik)
-- C: Yan etkisizlik (XP/rating/yildiz/grade degismez) + sync trigger
-- D: Rate limit
--
-- Guvence: tek transaction, sonunda ROLLBACK, kalinti yok.
-- CI uyumlu ozet: son satir "toplam|gecen|kalan" (kalan=0).
-- ============================================================

\set ON_ERROR_STOP on

begin;

create table public._qa_d107_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

create function public._qa_d107_expect(p_label text, p_title text, p_expect text, p_sql text)
returns void language plpgsql security invoker as $qa$
declare v_state text; v_msg text;
begin
  begin
    execute p_sql;
    if p_expect = '' then
      insert into public._qa_d107_results values (p_label, p_title, 'PASS', 'uygulandi');
    else
      insert into public._qa_d107_results values (p_label, p_title, 'FAIL',
        'hata beklenmisti ama uygulandi; beklenen=' || p_expect);
    end if;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_d107_results values (p_label, p_title, 'PASS',
        'sqlstate=' || v_state);
    else
      insert into public._qa_d107_results values (p_label, p_title, 'FAIL',
        'sqlstate=' || v_state || ' beklenen=' || coalesce(nullif(p_expect,''),'-') ||
        ' | ' || left(v_msg, 160));
    end if;
  end;
end;
$qa$;

create function public._qa_d107_true(p_label text, p_title text, p_ok boolean, p_detail text default null)
returns void language plpgsql security invoker as $qa$
begin
  insert into public._qa_d107_results
  values (p_label, p_title, case when p_ok then 'PASS' else 'FAIL' end, p_detail);
end;
$qa$;

grant select, insert, update, delete on public._qa_d107_results to anon, authenticated, service_role;
grant execute on function public._qa_d107_expect(text,text,text,text) to anon, authenticated, service_role;
grant execute on function public._qa_d107_true(text,text,boolean,text) to anon, authenticated, service_role;

-- ============ FIXTURE ============
insert into auth.users (id, email) values
  ('97000000-0000-0000-0000-0000000000a1', 'qa107-user-a@test.local'),
  ('97000000-0000-0000-0000-0000000000a2', 'qa107-user-b@test.local'),
  ('97000000-0000-0000-0000-0000000000a3', 'qa107-user-c@test.local'),
  ('97000000-0000-0000-0000-0000000000a4', 'qa107-user-d@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('97000000-0000-0000-0000-0000000000a1', 7, 'QA107-NICK-A'),
  ('97000000-0000-0000-0000-0000000000a2', 7, 'QA107-NICK-B'),
  ('97000000-0000-0000-0000-0000000000a3', 6, 'QA107-NICK-C'),
  ('97000000-0000-0000-0000-0000000000a4', 8, 'QA107-NICK-D');

-- A'ya cuzdan ve lig uyeligi: avatar seciminin bunlara DOKUNMADIGINI
-- kanitlamak icin on degerler sabitlenir.
insert into public.student_wallets (user_id, points, stars)
values ('97000000-0000-0000-0000-0000000000a1', 50, 5);

insert into public.student_league_memberships
  (user_id, league_id, membership_scope, points_at_entry, current_points, is_current)
select '97000000-0000-0000-0000-0000000000a1', l.id, 'general', 0, 24, true
  from public.leagues l where l.league_code = 'bronze';

-- Katalog: default/aktif, stars-kilitli/aktif, default/pasif.
insert into public.characters
  (id, character_code, name, sort_order, rarity, unlock_type, unlock_value, is_active) values
  ('97100000-0000-0000-0000-0000000000c1', 'qa10-ch1', 'QA10 K1', 10, 'common', 'default', 0, true),
  ('97100000-0000-0000-0000-0000000000c2', 'qa10-ch2', 'QA10 K2', 20, 'rare', 'stars', 500, true),
  ('97100000-0000-0000-0000-0000000000c3', 'qa10-ch3', 'QA10 K3', 30, 'common', 'default', 0, false);

-- ============ A. PROFIL OKUMA/YAZMA SINIRLARI ============
do $blk$
declare
  v_cnt integer;
  v_nick text;
begin
  -- Anon kimlik: rol anon + jwt yok.
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);

  -- 001: anon'a student_profiles uzerinde SELECT ayrica yok;
  -- RLS + grant katmani birlikte fail-closed.
  perform public._qa_d107_expect('P-01',
    'Anon student_profiles satirlarini OKUYAMAZ (RLS+grant)', '42501',
    'select count(*) from public.student_profiles');

  -- Authenticated A kimligi.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"97000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

  select count(*) into v_cnt from public.student_profiles
   where id = '97000000-0000-0000-0000-0000000000a1';
  perform public._qa_d107_true('P-02',
    'A kendi profilini okur', v_cnt = 1, 'cnt=' || v_cnt);

  select count(*) into v_cnt from public.student_profiles
   where id = '97000000-0000-0000-0000-0000000000a2';
  perform public._qa_d107_true('P-03',
    'A baska ogrencinin profilini OKUYAMAZ', v_cnt = 0, 'cnt=' || v_cnt);

  -- 093 kolon-ayricaligi: yalniz nickname UPDATE acik.
  update public.student_profiles set nickname = 'QA107-NICK-A2'
   where id = '97000000-0000-0000-0000-0000000000a1';
  select nickname into v_nick from public.student_profiles
   where id = '97000000-0000-0000-0000-0000000000a1';
  perform public._qa_d107_true('P-04',
    'A kendi nickname''ini izinli yoldan gunceller',
    v_nick = 'QA107-NICK-A2', 'nick=' || v_nick);

  update public.student_profiles set nickname = 'QA107-HACK'
   where id = '97000000-0000-0000-0000-0000000000a2';
  get diagnostics v_cnt = row_count;

  -- RLS satir kapsami: A oturumunda B'nin satiri görünmez; guncelleme
  -- sessizce 0 satir etkilendi olmalidir.
  perform public._qa_d107_true('P-05a',
    'A''nin baskasinin satirina yazma denemesi 0 satir etkiler',
    v_cnt = 0, 'row_count=' || v_cnt);

  -- RLS ayrica A oturumundan B'nin nickname degerini de gizler;
  -- gercek degisim kontrolu postgres rolunde yapilir.
  execute 'reset role';
  select nickname into v_nick from public.student_profiles
   where id = '97000000-0000-0000-0000-0000000000a2';
  perform public._qa_d107_true('P-05b',
    'A baska ogrencinin nickname''ini DEGISTIREMEZ',
    v_nick = 'QA107-NICK-B', 'nick=' || coalesce(v_nick, 'NULL'));

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"97000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

  perform public._qa_d107_expect('P-06',
    'A grade_level UPDATE reddedilir (fail-closed)', '42501',
    'update public.student_profiles set grade_level = 5 where id = ''97000000-0000-0000-0000-0000000000a1''');

  perform public._qa_d107_expect('P-07',
    'nickname + grade ayni istekte BÜTÜNÜYLE reddedilir', '42501',
    'update public.student_profiles set nickname = ''QA107-XY'', grade_level = 5 where id = ''97000000-0000-0000-0000-0000000000a1''');

  select nickname into v_nick from public.student_profiles
   where id = '97000000-0000-0000-0000-0000000000a1';
  perform public._qa_d107_true('P-08',
    'Basarisiz guncelleme kismi degisiklik birakmaz',
    v_nick = 'QA107-NICK-A2', 'nick=' || v_nick);
end;
$blk$;

-- ============ B+C. select_own_avatar GUVENLIK MATRISI ============
do $blk$
declare
  v_cnt integer;
  v_avatar text;
  v_grade smallint;
  v_stars integer;
  v_points integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"97000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

  -- V-01: A, default+aktif karakteri secer.
  perform public.select_own_avatar('qa10-ch1');
  select avatar_key into v_avatar from public.student_public_profiles
   where user_id = '97000000-0000-0000-0000-0000000000a1';
  perform public._qa_d107_true('V-01',
    'A default+aktif karakteri secer; pp.avatar_key set edilir',
    v_avatar = 'qa10-ch1', 'avatar_key=' || coalesce(v_avatar, 'NULL'));

  select count(*) into v_cnt from public.student_loadouts
   where user_id = '97000000-0000-0000-0000-0000000000a1'
     and character_id = '97100000-0000-0000-0000-0000000000c1';
  perform public._qa_d107_true('V-01b',
    'Loadout kendi satirina yazildi', v_cnt = 1, 'cnt=' || v_cnt);

  -- V-02: duplicate secim idempotent.
  perform public.select_own_avatar('qa10-ch1');
  select count(*) into v_cnt from public.student_loadouts
   where user_id = '97000000-0000-0000-0000-0000000000a1';
  select avatar_key into v_avatar from public.student_public_profiles
   where user_id = '97000000-0000-0000-0000-0000000000a1';
  perform public._qa_d107_true('V-02',
    'Duplicate secim guvenli ve idempotent',
    v_cnt = 1 and v_avatar = 'qa10-ch1',
    'loadout=' || v_cnt || ' avatar=' || coalesce(v_avatar, 'NULL'));

  -- V-03: kilitli (stars) karakter reddedilir (ekonomi yok).
  perform public._qa_d107_expect('V-03',
    'Kilitli (stars) karakter reddedilir', 'P0001',
    'select public.select_own_avatar(''qa10-ch2'')');

  -- V-04: pasif karakter reddedilir.
  perform public._qa_d107_expect('V-04',
    'Pasif karakter reddedilir', 'P0001',
    'select public.select_own_avatar(''qa10-ch3'')');

  -- V-05: bilinmeyen kod reddedilir.
  perform public._qa_d107_expect('V-05',
    'Bilinmeyen avatar kodu reddedilir', 'P0001',
    'select public.select_own_avatar(''qa10-yok'')');

  -- V-06: dis URL / dosya yolu kabul edilmez.
  perform public._qa_d107_expect('V-06',
    'Dis URL kabul edilmez', 'P0001',
    'select public.select_own_avatar(''https://evil.example/x.png'')');
  perform public._qa_d107_expect('V-06b',
    'Dosya yolu kabul edilmez', 'P0001',
    'select public.select_own_avatar(''../../etc/passwd'')');

  -- V-07: bos/NULL parametre reddedilir.
  perform public._qa_d107_expect('V-07',
    'Bos parametre reddedilir', 'P0001',
    'select public.select_own_avatar(''   '')');
  perform public._qa_d107_expect('V-07b',
    'NULL parametre reddedilir', 'P0001',
    'select public.select_own_avatar(null)');

  -- V-08: avatar secimi XP/rating/yildiz/grade DEGISTIRMEZ.
  select s.grade_level, w.stars, m.current_points
    into v_grade, v_stars, v_points
    from public.student_profiles s
    join public.student_wallets w on w.user_id = s.id
    join public.student_league_memberships m on m.user_id = s.id and m.is_current
   where s.id = '97000000-0000-0000-0000-0000000000a1';

  perform public.select_own_avatar('qa10-ch1');

  perform public._qa_d107_true('V-08',
    'Avatar secimi grade/yildiz/lig rating degistirmez',
    v_grade = 7 and v_stars = 5 and v_points = 24,
    'grade=' || coalesce(v_grade::text, 'NULL') ||
    ' stars=' || coalesce(v_stars::text, 'NULL') ||
    ' rating=' || coalesce(v_points::text, 'NULL'));

  -- V-09: B kendi avatarini secer; A'nin loadout'u DEGISMEZ.
  perform set_config('request.jwt.claims',
    '{"sub":"97000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);

  perform public.select_own_avatar('qa10-ch1');

  -- Loadout RLS: yalniz kendi satiri. B oturumundan A'nin kaydi
  -- gorunmez; gercek degismezlik kontrolu postgres rolunde.
  execute 'reset role';

  select count(*) into v_cnt from public.student_loadouts
   where user_id = '97000000-0000-0000-0000-0000000000a1'
     and character_id = '97100000-0000-0000-0000-0000000000c1';
  perform public._qa_d107_true('V-09',
    'B secimi yalniz B''ye yazar; A''nin avatar kaydi aynen kalir',
    v_cnt = 1, 'a_loadout_cnt=' || v_cnt);

  -- C-01: nickname sync trigger: A'nin nickname'i degisir ->
  -- pp.nickname taze olur (lig gosterimi).
  perform set_config('request.jwt.claims',
    '{"sub":"97000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

  update public.student_profiles set nickname = 'QA107-NICK-A3'
   where id = '97000000-0000-0000-0000-0000000000a1';

  select pp.nickname into v_avatar from public.student_public_profiles pp
   where pp.user_id = '97000000-0000-0000-0000-0000000000a1';
  perform public._qa_d107_true('C-01',
    'Nickname guncellenince pp.nickname senkronize edilir (lig)',
    v_avatar = 'QA107-NICK-A3', 'pp_nick=' || coalesce(v_avatar, 'NULL'));

  -- C-02: pp satiri OLMAYAN ogrencide nickname update pp URETMEZ
  -- (fail-closed; satir yalniz avatar secimiyle olusur).
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"97000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);

  update public.student_profiles set nickname = 'QA107-NICK-D2'
   where id = '97000000-0000-0000-0000-0000000000a4';

  select count(*) into v_cnt from public.student_public_profiles
   where user_id = '97000000-0000-0000-0000-0000000000a4';
  perform public._qa_d107_true('C-02',
    'pp satiri olmayan ogrencide nickname update pp URETMEZ',
    v_cnt = 0, 'cnt=' || v_cnt);

  -- C-03: Faz 9 profil RPC gercek ogrenci oturumunda calisir
  -- (103 bozuk EXECUTE zincirinin 107 ile duzeltilmesi). Hata
  -- gelirse expect helper FAIL loglar ve kosum surer.
  perform public._qa_d107_expect('C-03',
    'authenticated get_own_gamification_profile cagirabilir (hatasiz)',
    '',
    'select public.get_own_gamification_profile();');

  -- D-01: rate limit (10 istek/60 sn): B'nin bucket'i A testlerinde
  -- dolmadi; 10 kez gecersiz cagri tuketir (reddedilenler de sayilir
  -- cunku P0001 kural hatasi rate limit'ten SONRA gelir), 11.'si
  -- limit hatasi verir.
  declare
    v_attempts integer := 0;
    v_limited boolean := false;
    v_state text;
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
      '{"sub":"97000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);

    -- V-09'da B icin 1 cagri tuketildi; 9 tuketim daha (toplam 10).
    for i in 1..9 loop
      begin
        perform public.select_own_avatar('qa10-ch1');
      exception when others then
        -- beklenmeyen hata olsa bile sayaclama devam eder; detay
        -- ozet satirlarinda gorunur.
        null;
      end;
    end loop;

    begin
      perform public.select_own_avatar('qa10-ch1');
      v_limited := false;
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate;
      v_limited := true;
      v_attempts := v_attempts + 1;
    end;

    perform public._qa_d107_true('D-01',
      'Rate limit asiminda istek reddedilir (10/60)',
      v_limited, 'limited=' || v_limited);
  end;

  -- V-11: anon execute reddedilir.
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  perform public._qa_d107_expect('V-11',
    'Anon kimlik select_own_avatar CALISTIRAMAZ', '42501',
    'select public.select_own_avatar(''qa10-ch1'')');
end;
$blk$;

-- ============ OZET ============
reset role;

select 'TOPLAM=' || count(*)
       || '|' || 'GECEN=' || count(*) filter (where result = 'PASS')
       || '|' || 'KALAN=' || count(*) filter (where result = 'FAIL')
  from public._qa_d107_results;

select label || '|PASS|' || title from public._qa_d107_results where result = 'PASS';
select label || '|FAIL|' || coalesce(detail, title) from public._qa_d107_results where result = 'FAIL';

drop function public._qa_d107_expect(text,text,text,text);
drop function public._qa_d107_true(text,text,boolean,text);
drop table public._qa_d107_results;

rollback;
