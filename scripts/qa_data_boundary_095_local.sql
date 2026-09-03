-- ============================================================
-- scripts/qa_data_boundary_095_local.sql
-- Altin Kalemler - Migration 095 QA (veri siniri + odul guvenligi)
-- A: public profil sinif-izolasyonu | B: loadout + equip RPC
-- C: odul/envanter dogrudan yazim reddi | D: PII | E: regresyon
-- Guvence: tek transaction, sonunda ROLLBACK, kalinti yok.
-- ============================================================

\set ON_ERROR_STOP on

begin;

create table public._qa_d95_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete on public._qa_d95_results to anon, authenticated, service_role;

create function public._qa_d95_expect(p_label text, p_title text, p_expect text, p_sql text)
returns void language plpgsql security invoker as $qa$
declare v_state text; v_msg text;
begin
  begin
    execute p_sql;
    if p_expect = '' then
      insert into public._qa_d95_results values (p_label, p_title, 'PASS', 'uygulandi');
    else
      insert into public._qa_d95_results values (p_label, p_title, 'FAIL',
        'hata beklenmisti ama uygulandi; beklenen=' || p_expect);
    end if;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_d95_results values (p_label, p_title, 'PASS',
        'sqlstate=' || v_state);
    else
      insert into public._qa_d95_results values (p_label, p_title, 'FAIL',
        'sqlstate=' || v_state || ' beklenen=' || coalesce(nullif(p_expect,''),'-') ||
        ' | ' || left(v_msg, 160));
    end if;
  end;
end;
$qa$;

create function public._qa_d95_true(p_label text, p_title text, p_ok boolean, p_detail text default null)
returns void language plpgsql security invoker as $qa$
begin
  insert into public._qa_d95_results
  values (p_label, p_title, case when p_ok then 'PASS' else 'FAIL' end, p_detail);
end;
$qa$;

grant execute on function public._qa_d95_expect(text,text,text,text) to anon, authenticated, service_role;
grant execute on function public._qa_d95_true(text,text,boolean,text) to anon, authenticated, service_role;

-- ============ FIXTURE ============
insert into auth.users (id, email) values
  ('95000000-0000-0000-0000-000000000091', 'qa95-user-a@test.local'),
  ('95000000-0000-0000-0000-000000000092', 'qa95-user-b@test.local'),
  ('95000000-0000-0000-0000-000000000093', 'qa95-user-c@test.local'),
  ('95000000-0000-0000-0000-000000000094', 'qa95-user-d@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('95000000-0000-0000-0000-000000000091', 5, 'QA95-NICK-A'),
  ('95000000-0000-0000-0000-000000000092', 5, 'QA95-NICK-B'),
  ('95000000-0000-0000-0000-000000000093', 6, 'QA95-NICK-C'),
  ('95000000-0000-0000-0000-000000000094', 5, 'QA95-NICK-D');

insert into public.student_public_profiles
  (user_id, nickname, grade_level, is_visible, total_points) values
  ('95000000-0000-0000-0000-000000000091', 'QA95-NICK-A', 5, false, 10),
  ('95000000-0000-0000-0000-000000000092', 'QA95-NICK-B', 5, true,  20),
  ('95000000-0000-0000-0000-000000000093', 'QA95-NICK-C', 6, true,  30),
  ('95000000-0000-0000-0000-000000000094', 'QA95-NICK-D', 5, false, 40);

insert into public.characters
  (id, character_code, name, sort_order, rarity, unlock_type, unlock_value, is_active) values
  ('95950000-0000-0000-0000-0000000000c1', 'qa95-ch1', 'QA95 K1', 10, 'common', 'default', 0, true),
  ('95950000-0000-0000-0000-0000000000c2', 'qa95-ch2', 'QA95 K2', 20, 'rare', 'stars', 100, true),
  ('95950000-0000-0000-0000-0000000000c3', 'qa95-ch3', 'QA95 K3', 30, 'epic', 'stars', 200, false);

insert into public.cosmetic_items
  (id, item_code, name, item_type, rarity, unlock_type, unlock_value, is_active) values
  ('95950000-0000-0000-0000-0000000000a1', 'qa95-hat1', 'QA95 S1', 'hat', 'common', 'free', 0, true),
  ('95950000-0000-0000-0000-0000000000a2', 'qa95-hat2', 'QA95 S2', 'hat', 'rare', 'stars', 50, true),
  ('95950000-0000-0000-0000-0000000000a3', 'qa95-fr1', 'QA95 F1', 'frame', 'common', 'free', 0, true),
  ('95950000-0000-0000-0000-0000000000a4', 'qa95-hatp', 'QA95 SP', 'hat', 'epic', 'stars', 99, false);

insert into public.student_characters (user_id, character_id, unlock_source) values
  ('95000000-0000-0000-0000-000000000091', '95950000-0000-0000-0000-0000000000c1', 'qa'),
  ('95000000-0000-0000-0000-000000000091', '95950000-0000-0000-0000-0000000000c3', 'qa'),
  ('95000000-0000-0000-0000-000000000092', '95950000-0000-0000-0000-0000000000c2', 'qa');

insert into public.student_cosmetics (user_id, cosmetic_item_id, unlock_source) values
  ('95000000-0000-0000-0000-000000000091', '95950000-0000-0000-0000-0000000000a1', 'qa'),
  ('95000000-0000-0000-0000-000000000091', '95950000-0000-0000-0000-0000000000a3', 'qa'),
  ('95000000-0000-0000-0000-000000000091', '95950000-0000-0000-0000-0000000000a4', 'qa');

insert into public.student_wallets (user_id, points, stars)
values ('95000000-0000-0000-0000-000000000091', 50, 5);

insert into public.student_league_memberships
  (user_id, league_id, membership_scope, points_at_entry, current_points, is_current)
select '95000000-0000-0000-0000-000000000091', l.id, 'general', 0, 24, true
  from public.leagues l where l.league_code = 'bronze';

insert into public.leaderboard_seasons
  (id, season_code, name, season_type, starts_at, ends_at, is_active)
values ('95950000-0000-0000-0000-0000000000e1', 'QA95-SEZON', 'QA95 Sezon',
        'monthly', current_date - 1, current_date + 30, true);

insert into public.leaderboard_entries
  (season_id, leaderboard_definition_id, user_id, grade_level, points, rank_position)
values
  ('95950000-0000-0000-0000-0000000000e1',
   (select id from public.leaderboard_definitions where leaderboard_code = 'monthly_general'),
   '95000000-0000-0000-0000-000000000091', 5, 100, 1),
  ('95950000-0000-0000-0000-0000000000e1',
   (select id from public.leaderboard_definitions where leaderboard_code = 'monthly_general'),
   '95000000-0000-0000-0000-000000000093', 6, 200, 1);

-- Antrenman regresyon fiksasyonu
insert into public.curriculum_versions (id, academic_year, framework, is_active)
values ('95959595-9595-9595-9595-959595950001', 'QA95-Y', 'MEB-QA95', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active)
values ('95959595-9595-9595-9595-959595950002', 'QA95-SCHED', 'QA95 Profil',
        '95959595-9595-9595-9595-959595950001', true, true);

insert into public.academic_weeks (academic_year, week, starts_at, ends_at)
values ('QA95-Y', 5, current_date - 3, current_date + 4);

insert into public.topics
  (id, subject_id, grade_level, name, slug, curriculum_version_id)
values ('95959595-9595-9595-9595-959595950010',
        '430903f3-527e-4e12-b7e8-ac0afdb784aa', 5, 'QA95 Konu', 'qa95-konu',
        '95959595-9595-9595-9595-959595950001');

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, start_week)
values ('95959595-9595-9595-9595-959595950002', 5,
        '430903f3-527e-4e12-b7e8-ac0afdb784aa',
        '95959595-9595-9595-9595-959595950010', 1);

insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type, correct_answer,
   commercial_use_allowed, estimated_solve_time_seconds)
values ('95959595-9595-9595-9595-959595951001', 'QA95-P1', 5,
        '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
        'easy', 'learning', 'coktan_secmeli', 'A', true, 45);

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, review_status)
values ('95959595-9595-9595-9595-959595951001',
        '95959595-9595-9595-9595-959595950001',
        '95959595-9595-9595-9595-959595950010', 'approved');

insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id)
values ('95959595-9595-9595-9595-959595952001', 'QA95-V-P', 'QA95 Antrenman',
        'practice', 5, '430903f3-527e-4e12-b7e8-ac0afdb784aa');

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, practice_eligible)
values ('95959595-9595-9595-9595-959595952001',
        '95959595-9595-9595-9595-959595951001', 'active', true);

-- ============ A. PUBLIC PROFIL SINIF-IZOLASYONU ============
do $blk$
declare
  v_cnt integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  select count(*) into v_cnt from public.student_public_profiles
   where user_id = '95000000-0000-0000-0000-000000000092';
  perform public._qa_d95_true('A-01',
    'A(5), ayni siniftan gorunur B profilini okur', v_cnt = 1, 'cnt=' || v_cnt);

  select count(*) into v_cnt from public.student_public_profiles
   where user_id = '95000000-0000-0000-0000-000000000093';
  perform public._qa_d95_true('A-02',
    'A(5), farkli siniftaki C profilini OKUYAMAZ (0 satir)', v_cnt = 0, 'cnt=' || v_cnt);

  select count(*) into v_cnt from public.student_public_profiles
   where user_id = '95000000-0000-0000-0000-000000000094';
  perform public._qa_d95_true('A-03',
    'A(5), ayni siniftan gorunmez D profilini okuyamaz', v_cnt = 0, 'cnt=' || v_cnt);

  select count(*) into v_cnt from public.student_public_profiles
   where user_id = '95000000-0000-0000-0000-000000000091';
  perform public._qa_d95_true('A-04',
    'A kendi gorunmez profilini okur (self)', v_cnt = 1, 'cnt=' || v_cnt);

  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000092","role":"authenticated"}', true);
  select count(*) into v_cnt from public.student_public_profiles
   where user_id = '95000000-0000-0000-0000-000000000091';
  perform public._qa_d95_true('A-05',
    'B(5), gorunmez A profilini okuyamaz', v_cnt = 0, 'cnt=' || v_cnt);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

do $blk$
declare
  v_cnt integer;
begin
  select count(*) into v_cnt from pg_policies
   where schemaname = 'public' and tablename = 'student_public_profiles'
     and policyname = 'admin read all public profiles';
  perform public._qa_d95_true('A-06',
    '088 admin okuma politikasi yerinde', v_cnt = 1, 'cnt=' || v_cnt);

  execute 'set local role service_role';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000091","role":"service_role"}', true);
  select count(*) into v_cnt from public.student_public_profiles;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  perform public._qa_d95_true('A-07',
    'service_role tum profilleri okur', v_cnt = 4, 'cnt=' || v_cnt);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000093","role":"authenticated"}', true);
  select count(*) into v_cnt from public.student_public_profiles
   where user_id = '95000000-0000-0000-0000-000000000091';
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  perform public._qa_d95_true('A-08',
    'C(6), A(5) profilini okuyamaz (ters yon)', v_cnt = 0, 'cnt=' || v_cnt);
end;
$blk$;

-- ============ B. LOADOUT + EQUIP RPC ============
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  perform public._qa_d95_expect('B-01',
    'dogrudan INSERT loadout reddedilir (42501)', '42501',
    $sql$insert into public.student_loadouts (user_id, character_id)
      values ('95000000-0000-0000-0000-000000000091', null)$sql$);

  perform public._qa_d95_expect('B-02',
    'dogrudan UPDATE loadout reddedilir (42501)', '42501',
    $sql$update public.student_loadouts set character_id = null
      where user_id = '95000000-0000-0000-0000-000000000091'$sql$);

  perform public._qa_d95_expect('B-03',
    'dogrudan DELETE loadout reddedilir (42501)', '42501',
    $sql$delete from public.student_loadouts
      where user_id = '95000000-0000-0000-0000-000000000091'$sql$);

  perform public._qa_d95_expect('B-04',
    'RPC: sahipsiz karakter kusanma reddedilir (P0001)', 'P0001',
    $sql$select public.equip_student_character(
      '95950000-0000-0000-0000-0000000000c2'::uuid)$sql$);

  perform public._qa_d95_expect('B-05',
    'RPC: sahip olunan PASIF karakter kusanma reddedilir (P0001)', 'P0001',
    $sql$select public.equip_student_character(
      '95950000-0000-0000-0000-0000000000c3'::uuid)$sql$);

  perform public._qa_d95_expect('B-08',
    'RPC: sahipsiz kozmetik kusanma reddedilir (P0001)', 'P0001',
    $sql$select public.equip_student_cosmetic(
      '95950000-0000-0000-0000-0000000000a2'::uuid, true)$sql$);

  perform public._qa_d95_expect('B-11',
    'RPC: pasif kozmetik kusanma reddedilir (P0001)', 'P0001',
    $sql$select public.equip_student_cosmetic(
      '95950000-0000-0000-0000-0000000000a4'::uuid, true)$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- Sahipli kusanmalar + izolasyon.
do $blk$
declare
  v_res jsonb; v_char uuid; v_items jsonb; v_cnt integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  select public.equip_student_character(
    '95950000-0000-0000-0000-0000000000c1'::uuid) into v_res;
  perform public._qa_d95_true('B-06',
    'RPC: sahipli aktif karakter kusanir', v_res->>'equipped' = 'character');

  select l.character_id into v_char
    from public.student_loadouts l
   where l.user_id = '95000000-0000-0000-0000-000000000091';
  perform public._qa_d95_true('B-07',
    'loadout.character_id kusanilan karakter oldu (upsert)',
    v_char = '95950000-0000-0000-0000-0000000000c1');

  select public.equip_student_cosmetic(
    '95950000-0000-0000-0000-0000000000a1'::uuid, true) into v_res;
  perform public._qa_d95_true('B-09',
    'RPC: sahipli kozmetik kusanir (hat)',
    v_res->>'item_type' = 'hat'
      and v_res->'equipped_items'->>'hat' = '95950000-0000-0000-0000-0000000000a1');

  select public.equip_student_cosmetic(
    '95950000-0000-0000-0000-0000000000a3'::uuid, true) into v_res;
  select equipped_items into v_items
    from public.student_loadouts
   where user_id = '95000000-0000-0000-0000-000000000091';
  perform public._qa_d95_true('B-10',
    'farkli tip ekleme: hat + frame birlikte',
    v_items->>'hat' = '95950000-0000-0000-0000-0000000000a1'
      and v_items->>'frame' = '95950000-0000-0000-0000-0000000000a3');

  select public.unequip_student_character() into v_res;
  select character_id into v_char
    from public.student_loadouts
   where user_id = '95000000-0000-0000-0000-000000000091';
  perform public._qa_d95_true('B-13',
    'RPC: karakter cikarma -> character_id null', v_char is null);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  perform public._qa_d95_expect('B-14',
    'anon: equip RPC EXECUTE reddedilir (42501)', '42501',
    $sql$select public.equip_student_character(
      '95950000-0000-0000-0000-0000000000c1'::uuid)$sql$);
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  -- B(5): sahipsiz kozmetigi kusanamaz; sahipsiz karakteri de kusanamaz.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000092","role":"authenticated"}', true);

  perform public._qa_d95_expect('B-08b',
    'RPC: B sahipsiz kozmetigi kusanamaz (P0001)', 'P0001',
    $sql$select public.equip_student_cosmetic(
      '95950000-0000-0000-0000-0000000000a2'::uuid, true)$sql$);

  select public.equip_student_character(
    '95950000-0000-0000-0000-0000000000c2'::uuid) into v_res;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';

  select count(*) into v_cnt
    from public.student_loadouts
   where user_id = '95000000-0000-0000-0000-000000000092'
     and character_id = '95950000-0000-0000-0000-0000000000c2';
  perform public._qa_d95_true('B-15',
    'B kendi karakterini kusanir; U1 loadoutundan bagimsiz',
    v_cnt = 1);

  select count(*) into v_cnt
    from public.student_loadouts
   where user_id = '95000000-0000-0000-0000-000000000091';
  perform public._qa_d95_true('B-17',
    'U1 loadout satiri tek ve yerinde', v_cnt = 1);
end;
$blk$;

-- Kozmetik cikarma (unequip) ayri blok: U1 hat cikarir.
do $blk$
declare
  v_res jsonb; v_items jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  select public.equip_student_cosmetic(
    '95950000-0000-0000-0000-0000000000a1'::uuid, false) into v_res;

  select equipped_items into v_items
    from public.student_loadouts
   where user_id = '95000000-0000-0000-0000-000000000091';

  perform public._qa_d95_true('B-12',
    'RPC: kozmetik cikarma -> hat anahtari silinir, frame kalir',
    v_items ? 'frame' and not v_items ? 'hat',
    'items=' || coalesce(v_items::text, '?'));

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- ============ C. DOGRUDAN YAZIM REDDI ============
do $blk$
declare
  v_cnt integer;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  perform public._qa_d95_expect('C-01',
    'cuzdan INSERT reddedilir (42501)', '42501',
    $sql$insert into public.student_wallets (user_id, points) values
      ('95000000-0000-0000-0000-000000000091', 999)$sql$);

  perform public._qa_d95_expect('C-02',
    'reward_transactions INSERT reddedilir (42501)', '42501',
    $sql$insert into public.reward_transactions
      (user_id, reward_type, source_type) values
      ('95000000-0000-0000-0000-000000000091', 'points', 'special')$sql$);

  perform public._qa_d95_expect('C-03',
    'student_characters INSERT reddedilir (42501)', '42501',
    $sql$insert into public.student_characters
      (user_id, character_id) values
      ('95000000-0000-0000-0000-000000000091',
       '95950000-0000-0000-0000-0000000000c2')$sql$);

  perform public._qa_d95_expect('C-04',
    'student_cosmetics INSERT reddedilir (42501)', '42501',
    $sql$insert into public.student_cosmetics
      (user_id, cosmetic_item_id) values
      ('95000000-0000-0000-0000-000000000091',
       '95950000-0000-0000-0000-0000000000a2')$sql$);

  perform public._qa_d95_expect('C-05',
    'leaderboard_entries INSERT reddedilir (42501)', '42501',
    $sql$insert into public.leaderboard_entries
      (season_id, leaderboard_definition_id, user_id, grade_level, points)
     values ('95950000-0000-0000-0000-0000000000e1',
       (select id from public.leaderboard_definitions
         where leaderboard_code = 'monthly_general'),
       '95000000-0000-0000-0000-000000000091', 5, 99999)$sql$);

  perform public._qa_d95_expect('C-06',
    'student_league_memberships INSERT reddedilir (42501)', '42501',
    $sql$insert into public.student_league_memberships
      (user_id, league_id, membership_scope) values
      ('95000000-0000-0000-0000-000000000091',
       (select id from public.leagues where league_code = 'diamond'),
       'general')$sql$);

  begin
    update public.student_wallets set points = 999
     where user_id = '95000000-0000-0000-0000-000000000091';
    get diagnostics v_cnt = row_count;
    perform public._qa_d95_true('C-07',
      'cuzdan UPDATE: ogrenci puan degistiremez (0 satir veya 42501)',
      v_cnt = 0
        and (select points from public.student_wallets
              where user_id = '95000000-0000-0000-0000-000000000091') = 50,
      'rows=' || v_cnt);
  exception
    when insufficient_privilege then
      perform public._qa_d95_true('C-07',
        'cuzdan UPDATE yetkisi yok (42501)', true, 'sqlstate=42501');
  end;

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- C-09: visibility settings own-write hala calisir.
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  perform public._qa_d95_expect('C-09',
    'gorunurluk tercihleri own-write calisir (regresyon)', '',
    $sql$insert into public.student_visibility_settings
      (user_id, show_streak) values
      ('95000000-0000-0000-0000-000000000091', true)
     on conflict (user_id) do update set show_streak = true$sql$);

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

-- ============ D. PII MINIMIZASYONU ============
do $blk$
declare
  v_bad integer; v_cols text[];
begin
  select coalesce(array_agg(column_name), '{}') into v_cols
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'student_public_profiles';

  perform public._qa_d95_true('D-01',
    'public profil kolonlari PII icermez (email/phone/real name/school yok)',
    not (v_cols && array['email','phone','real_name','first_name','last_name','school_name'])
      and v_cols @> array['nickname','grade_level','avatar_key'],
    'cols=' || array_to_string(v_cols, ','));

  select count(*) into v_bad
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'leaderboard_entries'
     and column_name in ('email','phone','real_name','nickname','school_name');
  perform public._qa_d95_true('D-02',
    'leaderboard_entries kolonlari PII icermez',
    v_bad = 0, 'bad=' || v_bad);
end;
$blk$;

-- ============ E. REGRESYON ============
do $blk$
declare
  v_res jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000091","role":"authenticated"}', true);

  perform public._qa_d95_expect('E-01',
    '093 regresyon: ogrenci grade_level degistiremiyor (42501)', '42501',
    $sql$update public.student_profiles set grade_level = 6
      where id = '95000000-0000-0000-0000-000000000091'$sql$);

  select public.select_training_questions(
    '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10) into v_res;
  perform public._qa_d95_true('E-03',
    'antrenman secimi calisiyor (QA95-P1 doner)',
    exists (select 1 from jsonb_array_elements(v_res->'questions') el
             where el->>'question_code' = 'QA95-P1'),
    'res=' || left(coalesce(v_res::text,'?'), 80));

  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
end;
$blk$;

do $blk$
declare
  v_pt integer; v_cnt integer; v_res jsonb;
begin
  -- E-02: 094 tek aktif V1 set + hard correct 200.
  select public.resolve_competition_points(
    (select id from public.scoring_rule_sets
      where rule_set_code = 'competition_scoring_v1'),
    5::smallint, 'hard'::text, 'correct'::text, null::text) into v_pt;
  perform public._qa_d95_true('E-02',
    '094 regresyon: V1 hard correct = 200', v_pt = 200, 'pt=' || v_pt);

  -- E-04: leaderboard same-grade okuma (015).
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select count(*) into v_cnt
    from public.leaderboard_entries
   where season_id = '95950000-0000-0000-0000-0000000000e1'
     and user_id in ('95000000-0000-0000-0000-000000000091',
                     '95000000-0000-0000-0000-000000000093');
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  perform public._qa_d95_true('E-04',
    'leaderboard: A yalniz kendi sinifindaki kaydi gorur (1/2)',
    v_cnt = 1, 'cnt=' || v_cnt);

  -- E-05: student_profiles own-read.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select count(*) into v_cnt from public.student_profiles
   where id = '95000000-0000-0000-0000-000000000091';
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  perform public._qa_d95_true('E-05',
    'ogrenci kendi profilini okur', v_cnt = 1);

  -- E-06: lig uyeligi own-read.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"95000000-0000-0000-0000-000000000091","role":"authenticated"}', true);
  select count(*) into v_cnt from public.student_league_memberships
   where user_id = '95000000-0000-0000-0000-000000000091'
     and is_current = true;
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  perform public._qa_d95_true('E-06',
    'lig uyeligi own-read calisir', v_cnt = 1);
end;
$blk$;

-- ============ KALANTI + RAPOR ============
select
  (select count(*) from public.student_profiles
    where nickname like 'QA95-%') as profiles_kalan,
  (select count(*) from public.student_loadouts
    where user_id::text like '95000000%') as loadouts_kalan;

select
  label as test_id,
  case when bool_and(result = 'PASS') then 'PASS' else 'FAIL' end as durum,
  count(*) filter (where result = 'FAIL') as alt_fail,
  string_agg(
    case when result = 'PASS' then title
         else title || ' >>> ' || coalesce(detail, '') end,
    ' | ' order by title) as detay
from public._qa_d95_results
group by label
order by label;

with g as (
  select label, bool_and(result = 'PASS') as ok
  from public._qa_d95_results
  group by label
)
select
  count(*) as toplam,
  count(*) filter (where ok) as gecen,
  count(*) filter (where not ok) as kalan
from g;

drop function public._qa_d95_true(text, text, boolean, text);
drop function public._qa_d95_expect(text, text, text, text);
drop table public._qa_d95_results;

rollback;
