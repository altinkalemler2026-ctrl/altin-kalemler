-- ============================================================
-- scripts/qa_faz9_gamification_local.sql
-- Altin Kalemler - Migration Faz 9 yerel QA suite
--
-- Kapsam:
--   103 oyunlastirma cekirdegi: seviye formulu, XP ledger
--   (append-only + idempotency), gunluk 500 soru kotası
--   (Europe/Istanbul), seri motoru (current/longest, gecikmis
--   olay deterministik yeniden hesap), rozet katalogu + tek
--   seferlik idempotent grant, RLS/grant/ACL.
--   104 baglanti: ingest_student_attempt XP/seri/rozet, select
--   RPC'lerinde gunluk kota, _faz5_apply_competition_points
--   yarisma XP/aktivite.
--   105 result guard: cancelled/disputed yarismalar aktivite/
--   streak/yarisma rozeti uretmez (Faz 9b).
--
-- Test haritasi:
--   T-01..T-03  seviye formulu ve esikler
--   T-10..T-19  training XP + append-only + ogrenci yazim engelleri
--   T-30..T-39  gunluk kota (Europe/Istanbul, atomik, kota-doldu)
--   T-40..T-44  seri motoru (idempotency, gecikmis olay, longest)
--   T-50..T-55  yarisma XP + rating ayrikligi + gunluk etkinlik
--   T-60..T-67  rozetler (idempotent grant, katalog, RLS)
--   T-70..T-74  profil RPC (otoriter toplam, ayri DTO alanlari)
--   T-75..T-79  Faz 9b: result guard, duplicate attempt XP,
--               streak_7, paralel kota (dblink), rewards.manage
--               idempotency
--
-- ON KOSULLAR (disposable stack, LOCAL ONLY):
--   - Migration'lar 101/102 dahil uygulanmis + 103/104 uygulanmis.
--   - local-faz7-e2e-fixture.sql uygulanmis olmasi TERCİH edilir
--     (mufredat/takvim scaffolding'i); suite eksik temel kayitlari
--     (akademik hafta, varsayilan takvim profili) idempotent
--     tamamlar.
--
-- Calistirma:
--   docker cp scripts/qa_faz9_gamification_local.sql <db>:/tmp/
--   docker exec <db> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -f /tmp/qa_faz9_gamification_local.sql
--
-- Guvence: suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR (faz8 deseninin aynisi)
-- ============================================================

create table public._qa_faz9_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

create function public._qa9_expect(p_label text, p_title text, p_expect text, p_sql text)
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
    insert into public._qa_faz9_results
    values (p_label, p_title, 'FAIL',
            'beklenen hata gelmedi (' || p_expect || ')');
  exception
    when others then
      get stacked diagnostics v_state = RETURNED_SQLSTATE,
                              v_msg = MESSAGE_TEXT;
      if v_state = p_expect then
        insert into public._qa_faz9_results
        values (p_label, p_title, 'PASS',
                'sqlstate=' || v_state || ' | mesaj eslesti');
      else
        insert into public._qa_faz9_results
        values (p_label, p_title, 'FAIL',
                'sqlstate=' || v_state ||
                ' beklenen=' || p_expect ||
                ' | msg=' || left(v_msg, 160));
      end if;
  end;
end;
$qa$;

create function public._qa9_true(p_label text, p_title text, p_ok boolean, p_detail text default null)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_faz9_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

-- Yeni CLI "no-auto-expose" bootstrap'inda yardimci tablo/fonksiyonlara
-- dogustan grant verilmedigi icin (faz8/faz10 deseniyle ayni)
-- calistirilabilirlik grant'leri. Test beklentileri degismez.
grant select, insert, update, delete
  on public._qa_faz9_results
  to anon, authenticated, service_role;
grant execute
  on function public._qa9_expect(text, text, text, text)
  to anon, authenticated, service_role;
grant execute
  on function public._qa9_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR (deterministik sahte veriler)
--   A: 9f900000-...-0001 (12.sinif; XP/seri/rozet ana aktor)
--   B: 9f900000-...-0002 (12.sinif; yarisma rakibi)
--   W: 9f900000-...-0003 (12.sinif; wins_10)
--   Q: 9f900000-...-0004 (12.sinif; kota testleri)
-- Sorular: 9f910000-...-0001 easy / 0002 medium / 0003 hard
-- ============================================================

insert into auth.users (id, email) values
  ('9f900000-0000-0000-0000-000000000001', 'qa9-a@test.local'),
  ('9f900000-0000-0000-0000-000000000002', 'qa9-b@test.local'),
  ('9f900000-0000-0000-0000-000000000003', 'qa9-w@test.local'),
  ('9f900000-0000-0000-0000-000000000004', 'qa9-q@test.local'),
  ('9f900000-0000-0000-0000-000000000005', 'qa9-u@test.local'),
  ('9f900000-0000-0000-0000-000000000006', 'qa9-v@test.local'),
  ('9f900000-0000-0000-0000-000000000007', 'qa9-s@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('9f900000-0000-0000-0000-000000000001', 12, 'QA9-NICK-A'),
  ('9f900000-0000-0000-0000-000000000002', 12, 'QA9-NICK-B'),
  ('9f900000-0000-0000-0000-000000000003', 12, 'QA9-NICK-W'),
  ('9f900000-0000-0000-0000-000000000004', 12, 'QA9-NICK-Q'),
  ('9f900000-0000-0000-0000-000000000005', 12, 'QA9-NICK-U'),
  ('9f900000-0000-0000-0000-000000000006', 12, 'QA9-NICK-V'),
  ('9f900000-0000-0000-0000-000000000007', 12, 'QA9-NICK-S');

insert into public.student_public_profiles
  (user_id, nickname, grade_level, avatar_key, is_visible) values
  ('9f900000-0000-0000-0000-000000000001', 'QA9-NICK-A', 12, 'avatar_qa9_a', true),
  ('9f900000-0000-0000-0000-000000000002', 'QA9-NICK-B', 12, 'avatar_qa9_b', true),
  ('9f900000-0000-0000-0000-000000000003', 'QA9-NICK-W', 12, 'avatar_qa9_w', true),
  ('9f900000-0000-0000-0000-000000000004', 'QA9-NICK-Q', 12, 'avatar_qa9_q', true),
  ('9f900000-0000-0000-0000-000000000005', 'QA9-NICK-U', 12, 'avatar_qa9_u', true),
  ('9f900000-0000-0000-0000-000000000006', 'QA9-NICK-V', 12, 'avatar_qa9_v', true),
  ('9f900000-0000-0000-0000-000000000007', 'QA9-NICK-S', 12, 'avatar_qa9_s', true);

insert into public.subjects (id, name, slug, sort_order, is_active)
values ('9f905000-0000-0000-0000-000000000001', 'QA9 Matematik',
        'qa9-matematik', 990, true);

insert into public.questions
  (id, question_code, grade_level, subject_id, question_text,
   correct_answer, difficulty, is_active, approval_status)
values
  ('9f910000-0000-0000-0000-000000000001', 'QA9-Q-EASY',   12,
   '9f905000-0000-0000-0000-000000000001', 'QA9 kolay soru',  'A', 'easy',   true, 'approved'),
  ('9f910000-0000-0000-0000-000000000002', 'QA9-Q-MEDIUM', 12,
   '9f905000-0000-0000-0000-000000000001', 'QA9 orta soru',   'A', 'medium', true, 'approved'),
  ('9f910000-0000-0000-0000-000000000003', 'QA9-Q-HARD',   12,
   '9f905000-0000-0000-0000-000000000001', 'QA9 zor soru',    'A', 'hard',   true, 'approved');

-- Akademik hafta fallback: bugunu kapsayan hafta yoksa ekle.
do $blk$
begin
  if not exists (
    select 1
      from public.academic_weeks w
     where (current_timestamp at time zone 'utc')::date >= w.starts_at
       and (current_timestamp at time zone 'utc')::date < w.ends_at
  ) then
    insert into public.academic_weeks
      (academic_year, week, starts_at, ends_at)
    values ('QA9-YIL', 1,
            (current_timestamp at time zone 'utc')::date,
            (current_timestamp at time zone 'utc')::date + 1);
  end if;
end;
$blk$;

-- Mufredat scaffolding fallback: varsayilan aktif takvim profili
-- yoksa (QA9 surumuyle) ekle; _faz2_student_context cozulebilsin.
do $blk$
declare
  v_version uuid;
begin
  if not exists (
    select 1
      from public.curriculum_schedule_profiles
     where is_default = true and is_active = true
  ) then
    insert into public.curriculum_versions
      (id, academic_year, framework, is_active)
    values ('9f915000-0000-0000-0000-000000000001',
            '2098-2099-QA9', 'MEB-QA9', true)
    on conflict (academic_year, framework) do nothing
    returning id into v_version;

    if v_version is null then
      select id into v_version
        from public.curriculum_versions
       where framework = 'MEB-QA9';
    end if;

    insert into public.curriculum_schedule_profiles
      (id, code, name, curriculum_version_id,
       is_default, is_active)
    values ('9f916000-0000-0000-0000-000000000001',
            'QA9-DEFAULT', 'QA9 varsayilan takvim profili',
            v_version, true, true)
    on conflict (code) do nothing;
  end if;
end;
$blk$;

-- Yarisma puan kural seti fallback.
insert into public.scoring_rule_sets
  (id, rule_set_code, name, version, is_active)
values ('9f917000-0000-0000-0000-000000000001', 'qa9_scoring',
        'QA9 puan kural seti', 'v1', true)
on conflict (rule_set_code) do nothing;

-- Lig uyelikleri (rating floor testi icin POZITIF puanlarla):
-- A=40, B=30 (bronze bandi). Faz 8 +24/-12 sozlesmesinin
-- gozlemlenebilmesi icin sifirdan buyuk bakiye gerekir.
insert into public.student_league_memberships
  (user_id, league_id, membership_scope,
   points_at_entry, current_points, is_current)
values
  ('9f900000-0000-0000-0000-000000000001',
   (select id from public.leagues where league_code = 'bronze'),
   'general', 40, 40, true),
  ('9f900000-0000-0000-0000-000000000002',
   (select id from public.leagues where league_code = 'bronze'),
   'general', 30, 30, true);


-- ============================================================
-- BOLUM A: SEVIYE FORMULU (500 x (seviye-1)^2, max 50)
-- ============================================================

do $blk$
declare
  v_ok boolean;
begin
  select
    public.faz9_required_total_xp(1)  = 0
    and public.faz9_required_total_xp(2)  = 500
    and public.faz9_required_total_xp(3)  = 2000
    and public.faz9_required_total_xp(50) = 1200500
    into v_ok;
  perform public._qa9_true('T-01',
    'gerekli toplam XP = 500*(seviye-1)^2 (1,2,3,50)',
    v_ok, 'formul');

  select
    public.faz9_level_from_total_xp(0) = 1
    and public.faz9_level_from_total_xp(499) = 1
    and public.faz9_level_from_total_xp(500) = 2
    and public.faz9_level_from_total_xp(1999) = 2
    and public.faz9_level_from_total_xp(2000) = 3
    and public.faz9_level_from_total_xp(1200499) = 49
    and public.faz9_level_from_total_xp(1200500) = 50
    into v_ok;
  perform public._qa9_true('T-02',
    'seviye esikleri deterministik (1/500/2000/1200500 sinirlari)',
    v_ok, 'esikler');

  select public.faz9_level_from_total_xp(999999999) = 50 into v_ok;
  perform public._qa9_true('T-03',
    'V1 maksimum seviye 50 (ustXP seviyeyi 50''de sabitler)',
    v_ok, 'max=50');
end;
$blk$;


-- ============================================================
-- BOLUM B: TRAINING XP (ingest baglantisi, idempotency, append-only)
-- Cagri auth.uid() ile: claims + superuser (070 ile authenticated
-- EXECUTE kapali; QA superuser olarak otoriter cagri yapar).
-- ============================================================

do $blk$
declare
  v_res jsonb;
  v_xp smallint;
  v_rows integer;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"9f900000-0000-0000-0000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    '9f900000-0000-0000-0000-000000000001', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- Kolay dogru → +2 XP, ilk gecerli etkinlik (seri + first_step +
  -- first_correct rozetleri).
  v_res := public.ingest_student_attempt(
    '9f910000-0000-0000-0000-000000000001', 'training', 'correct',
    12000, null,
    jsonb_build_object('client_key', '9f990000-0000-0000-0000-000000000001'));

  select xp_amount into v_xp
    from public.student_xp_ledger
   where user_id = '9f900000-0000-0000-0000-000000000001';
  perform public._qa9_true('T-10',
    'kolay dogru +2 XP ledger''a yazildi',
    v_xp = 2, 'xp=' || coalesce(v_xp::text, 'yok'));

  -- Orta dogru +3, zor dogru +5.
  perform public.ingest_student_attempt(
    '9f910000-0000-0000-0000-000000000002', 'training', 'correct',
    15000, null,
    jsonb_build_object('client_key', '9f990000-0000-0000-0000-000000000002'));
  perform public.ingest_student_attempt(
    '9f910000-0000-0000-0000-000000000003', 'training', 'correct',
    18000, null,
    jsonb_build_object('client_key', '9f990000-0000-0000-0000-000000000003'));

  select total_xp into v_xp
    from public.student_xp_totals
   where user_id = '9f900000-0000-0000-0000-000000000001';
  perform public._qa9_true('T-11',
    'toplam XP = 2+3+5 = 10 (totals islemsel guncel)',
    v_xp = 10, 'total=' || coalesce(v_xp::text, 'yok'));

  -- Yanlis: 0 XP — ledger kaydi YOK.
  perform public.ingest_student_attempt(
    '9f910000-0000-0000-0000-000000000001', 'training', 'wrong',
    9000, null,
    jsonb_build_object('client_key', '9f990000-0000-0000-0000-000000000004'));

  select count(*) into v_rows
    from public.student_xp_ledger
   where user_id = '9f900000-0000-0000-0000-000000000001';
  perform public._qa9_true('T-12',
    'yanlis cevap 0 XP: ledger kaydi uretmez',
    v_rows = 3, 'ledger=' || v_rows);

  -- Pas/timeout: hem XP yok hem gunluk etkinlik OLUSTURMAZ.
  perform public.ingest_student_attempt(
    '9f910000-0000-0000-0000-000000000001', 'training', 'pass',
    null, null,
    jsonb_build_object('client_key', '9f990000-0000-0000-0000-000000000005'));

  select count(*) into v_rows
    from public.student_daily_activity
   where user_id = '9f900000-0000-0000-0000-000000000001';
  perform public._qa9_true('T-13',
    'pas/timeout gunluk etkinlik OLUSTURMAZ (yalniz correct/wrong)',
    v_rows = 1, 'aktivite=' || v_rows);

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end;
$blk$;

-- T-14: append-only savunma (UPDATE/DELETE her rol icin engelli).
select public._qa9_expect('T-14',
  'XP ledger UPDATE engellenir (append-only trigger)',
  'P0001',
  $sql$update public.student_xp_ledger
      set xp_amount = 99
    where user_id = '9f900000-0000-0000-0000-000000000001'$sql$);

select public._qa9_expect('T-15',
  'XP ledger DELETE engellenir (append-only trigger)',
  'P0001',
  $sql$delete from public.student_xp_ledger
    where user_id = '9f900000-0000-0000-0000-000000000001'$sql$);

-- T-16/T-17: ogrenci dogrudan yazamaz (RLS + grant yok).
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"9f900000-0000-0000-0000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    '9f900000-0000-0000-0000-000000000001', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  perform public._qa9_expect('T-16',
    'ogrenci XP ledger''a INSERT edemez',
    '42501',
    $sql$insert into public.student_xp_ledger
      (user_id, source_type, source_id, xp_amount)
    values ('9f900000-0000-0000-0000-000000000001',
            'training_attempt',
            '9f910000-0000-0000-0000-000000000001', 500)$sql$);

  perform public._qa9_expect('T-17',
    'ogrenci toplam XP''sini yazamaz/guncelleyemez',
    '42501',
    $sql$insert into public.student_xp_totals
      (user_id, total_xp)
    values ('9f900000-0000-0000-0000-000000000001', 999999)$sql$);

  perform public._qa9_expect('T-18',
    'ogrenci serisini dogrudan yazamaz',
    '42501',
    $sql$insert into public.student_streaks
      (user_id, current_streak, longest_streak)
    values ('9f900000-0000-0000-0000-000000000001', 999, 999)$sql$);

  perform public._qa9_expect('T-19',
    'ogrenci kendine rozet veremez',
    '42501',
    $sql$insert into public.student_badges
      (user_id, badge_code)
    values ('9f900000-0000-0000-0000-000000000001', 'wins_10')$sql$);

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end;
$blk$;


-- ============================================================
-- BOLUM C: GUNLUK 500 SORU KOTASI (Europe/Istanbul)
-- ============================================================

do $blk$
declare
  v_ok boolean;
begin
  select
    public._faz9_local_day('2026-09-07T21:30:00Z'::timestamptz)
      = date '2026-09-08'
    and public._faz9_local_day('2026-09-08T20:59:59Z'::timestamptz)
      = date '2026-09-08'
    and public._faz9_local_day('2026-09-08T21:00:00Z'::timestamptz)
      = date '2026-09-09'
    into v_ok;
  perform public._qa9_true('T-30',
    'gun siniri Europe/Istanbul (sabit UTC+3, DST yok)',
    v_ok, 'sinir degerleri');
end;
$blk$;

do $blk$
declare
  v_left  integer;
  v_left2 integer;
begin
  -- Ilk kilit 500 hak verir.
  v_left := public._faz9_lock_daily_counter(
    '9f900000-0000-0000-0000-000000000004',
    public._faz9_local_day(now()));

  perform public._qa9_true('T-31',
    'temiz gun icin kalan hak 500',
    v_left = 500, 'kalan=' || v_left);

  -- 490 teslim.
  perform public._faz9_consume_daily_quota(
    '9f900000-0000-0000-0000-000000000004',
    public._faz9_local_day(now()), 490);

  -- Ikinci kilit ayni islemde satiri yeniden kilitler.
  v_left2 := public._faz9_lock_daily_counter(
    '9f900000-0000-0000-0000-000000000004',
    public._faz9_local_day(now()));

  perform public._qa9_true('T-32',
    'kilit + tuketim atomik: 490 teslimden sonra 10 hak kalir',
    v_left2 = 10, 'kalan=' || v_left2);

  -- Kalan 10'u asmak reddedilir (P0001).
  perform public._qa9_expect('T-33',
    'gunluk 500 ustune tuketim reddedilir',
    'P0001',
    $sql$select public._faz9_consume_daily_quota(
      '9f900000-0000-0000-0000-000000000004',
      public._faz9_local_day(now()), 11)$sql$);

  -- CHECK backstop: dogrudan 501 yazilamaz (23514).
  perform public._qa9_expect('T-34',
    'CHECK backstop: sayac 500''u asamaz (gunluk 10''da)',
    '23514',
    $sql$update public.student_daily_question_counters
       set questions_used = 501
     where user_id = '9f900000-0000-0000-0000-000000000004'$sql$);

  -- Kalan 10 hakki teslim edilir: sayaç 500'e ulasir.
  perform public._faz9_consume_daily_quota(
    '9f900000-0000-0000-0000-000000000004',
    public._faz9_local_day(now()), 10);

  -- 500 dolu iken 1 hak daha reddedilir.
  perform public._qa9_expect('T-35',
    'es zamanli tuketimler 500''u asamaz: dolu sayacta 1 hak da reddedilir',
    'P0001',
    $sql$select public._faz9_consume_daily_quota(
      '9f900000-0000-0000-0000-000000000004',
      public._faz9_local_day(now()), 1)$sql$);
end;
$blk$;

-- T-36: istemci sayac/tarih/kullanici degistiremez.
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"9f900000-0000-0000-0000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    '9f900000-0000-0000-0000-000000000004', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  perform public._qa9_expect('T-36',
    'istemci gunluk sayac satirini guncelleyemez',
    '42501',
    $sql$update public.student_daily_question_counters
       set questions_used = 0
     where user_id = '9f900000-0000-0000-0000-000000000004'$sql$);

  perform public._qa9_expect('T-37',
    'istemci gunluk sayac satiri EKLEYEMEZ',
    '42501',
    $sql$insert into public.student_daily_question_counters
      (user_id, quota_day, questions_used)
    values ('9f900000-0000-0000-0000-000000000004',
            date '2020-01-01', 0)$sql$);

  perform public._qa9_expect('T-38',
    'istemci kota yardimci fonksiyonlarini CAGIRAMAZ (execute yok)',
    '42501',
    $sql$select public._faz9_lock_daily_counter(
      '9f900000-0000-0000-0000-000000000004',
      public._faz9_local_day(now()))$sql$);

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end;
$blk$;

-- T-39: kota dolunca teslim YOK (gunluk_kota_doldu).
do $blk$
declare
  v_json jsonb;
begin
  -- Q sayaci 500/500 dolu (T-35 sonrasi); teslim YOK beklenir.
  perform set_config('request.jwt.claims',
    '{"sub":"9f900000-0000-0000-0000-000000000004","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    '9f900000-0000-0000-0000-000000000004', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  v_json := public.select_training_questions(
    '9f905000-0000-0000-0000-000000000001', 10);

  perform public._qa9_true('T-39',
    'kota dolunca select: reason=gunluk_kota_doldu, bos liste',
    v_json ->> 'reason' = 'gunluk_kota_doldu'
      and jsonb_array_length(v_json -> 'questions') = 0
      and (v_json -> 'daily' ->> 'remaining')::int = 0,
    'reason=' || coalesce(v_json ->> 'reason', 'yok') ||
    ' | remaining=' || coalesce(v_json -> 'daily' ->> 'remaining', '?'));

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end;
$blk$;


-- ============================================================
-- BOLUM D: SERI MOTORU (current/longest, idempotency, gecikmis)
-- ============================================================

do $blk$
declare
  -- Zaman-deterministik sabitleme: olaylar YEREL GUN ORTASINA (12:00)
  -- cemlenir. now()'un 22:00-24:00 bandindaki degerleri, '-1 gun +2
  -- saat' ofsetini gun sinirini asacak sekilde kaydirir ve ayni-gun
  -- ikinci etkinlik testi (T-41) kosma saatine bagli hale gelirdi.
  -- 12:00 cemlemesi butun ofset gunleri ayni yerel gunde tutar;
  -- test beklentileri degismez.
  v_u   uuid := '9f900000-0000-0000-0000-000000000002';
  v_now timestamptz := (
    (date_trunc('day', now() at time zone 'Europe/Istanbul') + interval '12 hours')
    at time zone 'Europe/Istanbul'
  );
  v_cur integer; v_long integer; v_last date;
begin
  -- Gun -1: ilk etkinlik.
  perform public._faz9_record_daily_activity(v_u, v_now - interval '1 day');
  select current_streak, longest_streak, last_activity_day
    into v_cur, v_long, v_last
    from public.student_streaks where user_id = v_u;
  perform public._qa9_true('T-40',
    'ilk etkinlik: seri 1',
    v_cur = 1 and v_long = 1 and v_last = public._faz9_local_day(v_now - interval '1 day'),
    'cur=' || v_cur || ' long=' || v_long);

  -- Aynı gün tekrar (aynı yerel günün ileri saati): seri DEGISMEZ.
  perform public._faz9_record_daily_activity(
    v_u, v_now - interval '1 day' + interval '2 hour');
  select current_streak into v_cur from public.student_streaks where user_id = v_u;
  perform public._qa9_true('T-41',
    'ayni gun ikinci etkinlik seriyi artirmaz',
    v_cur = 1, 'cur=' || v_cur);

  -- Bugun: +1.
  perform public._faz9_record_daily_activity(v_u, v_now);
  select current_streak, longest_streak into v_cur, v_long
    from public.student_streaks where user_id = v_u;
  perform public._qa9_true('T-42',
    'dunun etkinligi sonrasi bugun: seri 2',
    v_cur = 2 and v_long = 2, 'cur=' || v_cur);

  -- Gecikmis olay (gun -3): deterministik yeniden hesap. Gunler
  -- {-3, -1, 0} → bugune bitisik kosu 2; gecikmis olay seriyi
  -- KISALTMAZ (2 kalir), last_activity_day geri gitmez.
  perform public._faz9_record_daily_activity(v_u, v_now - interval '3 day');
  select current_streak, longest_streak, last_activity_day
    into v_cur, v_long, v_last
    from public.student_streaks where user_id = v_u;
  perform public._qa9_true('T-43',
    'gecikmis olay deterministik: seri kisalmaz, last geri gitmez',
    v_cur = 2 and v_long = 2
      and v_last = public._faz9_local_day(v_now),
    'cur=' || v_cur || ' last=' || v_last);

  -- Gecikmis olay kopruyu tamamlarsa seri UZAR: {-3,-2,-1,0} → 4.
  perform public._faz9_record_daily_activity(v_u, v_now - interval '2 day');
  select current_streak, longest_streak
    into v_cur, v_long
    from public.student_streaks where user_id = v_u;
  perform public._qa9_true('T-43b',
    'gecikmis olay koprü tamamlayinca seri 4''e uzar',
    v_cur = 4 and v_long = 4,
    'cur=' || v_cur || ' long=' || v_long);

  -- En az bir tam gun kacar: 3 gun sonra → 1'e doner.
  perform public._faz9_record_daily_activity(v_u, v_now + interval '3 day');
  select current_streak, longest_streak into v_cur, v_long
    from public.student_streaks where user_id = v_u;
  perform public._qa9_true('T-44',
    '1+ tam gun kacirma seriyi 1''e dusurur; longest korunur',
    v_cur = 1 and v_long = 4, 'cur=' || v_cur || ' long=' || v_long);
end;
$blk$;


-- ============================================================
-- BOLUM E: YARISMA XP (kazanan 15 / beraberlik 10 / kaybeden 5,
-- iptal 0; duplicate finalize ikinci uretmez; rating degismez)
-- ============================================================

-- Yarisma fixture'lari.
insert into public.competitions
  (id, competition_code, competition_type, grade_level, subject_id,
   scoring_rule_set_id, status, question_count,
   server_completed_at, completed_at)
values
  ('9f920000-0000-0000-0000-000000000001', 'QA9-C1-WIN', 'one_vs_one', 12,
   '9f905000-0000-0000-0000-000000000001',
   '9f917000-0000-0000-0000-000000000001', 'completed', 5,
   now(), now()),
  ('9f920000-0000-0000-0000-000000000002', 'QA9-C2-DRAW', 'one_vs_one', 12,
   '9f905000-0000-0000-0000-000000000001',
   '9f917000-0000-0000-0000-000000000001', 'completed', 5,
   now(), now()),
  ('9f920000-0000-0000-0000-000000000003', 'QA9-C3-CANCEL', 'one_vs_one', 12,
   '9f905000-0000-0000-0000-000000000001',
   '9f917000-0000-0000-0000-000000000001', 'completed', 5,
   now(), now());

insert into public.competition_players
  (competition_id, user_id, player_slot, status) values
  ('9f920000-0000-0000-0000-000000000001',
   '9f900000-0000-0000-0000-000000000001', 1, 'active'),
  ('9f920000-0000-0000-0000-000000000001',
   '9f900000-0000-0000-0000-000000000002', 2, 'active'),
  ('9f920000-0000-0000-0000-000000000002',
   '9f900000-0000-0000-0000-000000000001', 1, 'active'),
  ('9f920000-0000-0000-0000-000000000002',
   '9f900000-0000-0000-0000-000000000002', 2, 'active'),
  ('9f920000-0000-0000-0000-000000000003',
   '9f900000-0000-0000-0000-000000000001', 1, 'active'),
  ('9f920000-0000-0000-0000-000000000003',
   '9f900000-0000-0000-0000-000000000002', 2, 'active');

insert into public.competition_results
  (competition_id, winner_user_id, result_type) values
  ('9f920000-0000-0000-0000-000000000001',
   '9f900000-0000-0000-0000-000000000001', 'win_loss'),
  ('9f920000-0000-0000-0000-000000000002', null, 'draw'),
  ('9f920000-0000-0000-0000-000000000003', null, 'cancelled');

do $blk$
declare
  v_a_xp smallint; v_b_xp smallint; v_rows integer; v_rating integer;
begin
  perform public._faz5_apply_competition_points(
    '9f920000-0000-0000-0000-000000000001');

  select xp_amount into v_a_xp from public.student_xp_ledger
   where source_type = 'competition_result'
     and source_id = '9f920000-0000-0000-0000-000000000001'
     and user_id = '9f900000-0000-0000-0000-000000000001';
  select xp_amount into v_b_xp from public.student_xp_ledger
   where source_type = 'competition_result'
     and source_id = '9f920000-0000-0000-0000-000000000001'
     and user_id = '9f900000-0000-0000-0000-000000000002';

  perform public._qa9_true('T-50',
    'win_loss: kazanan +15, kaybeden +5',
    v_a_xp = 15 and v_b_xp = 5,
    'A=' || coalesce(v_a_xp::text, 'yok') ||
    ' B=' || coalesce(v_b_xp::text, 'yok'));

  -- Iptal edilen: 0 XP (ledger kaydi yok).
  select count(*) into v_rows
    from public.student_xp_ledger
   where source_id = '9f920000-0000-0000-0000-000000000003';
  perform public._qa9_true('T-51',
    'iptal edilen yarisma 0 XP (ledger kaydi uretmez)',
    v_rows = 0, 'ledger=' || v_rows);

  -- Duplicate finalize: rating erken donusu tum etkiyi keser.
  perform public._faz5_apply_competition_points(
    '9f920000-0000-0000-0000-000000000001');
  select count(*) into v_rows
    from public.student_xp_ledger
   where source_id = '9f920000-0000-0000-0000-000000000001';
  perform public._qa9_true('T-52',
    'duplicate finalize ikinci XP URETMEZ',
    v_rows = 2, 'ledger=' || v_rows);

  -- Rating sozlesmesi degismedi: A 40→64 (+24), B 30→18 (−12).
  select count(*) into v_rating
    from public.competition_point_changes
   where competition_id = '9f920000-0000-0000-0000-000000000001'
     and change_type = 'rating'
     and ((user_id = '9f900000-0000-0000-0000-000000000001'
           and points_change = 24)
          or (user_id = '9f900000-0000-0000-0000-000000000002'
              and points_change = -12));
  perform public._qa9_true('T-53',
    'lig rating +24/-12 aynen uygulandi (Faz 8 sozlesmesi)',
    v_rating = 2, 'rating=' || v_rating);

  -- Beraberlik: her iki oyuncu +10.
  perform public._faz5_apply_competition_points(
    '9f920000-0000-0000-0000-000000000002');
  select count(*) into v_rows
    from public.student_xp_ledger
   where source_id = '9f920000-0000-0000-0000-000000000002'
     and xp_amount = 10;
  perform public._qa9_true('T-54',
    'beraberlik: her iki oyuncu +10',
    v_rows = 2, 'ledger=' || v_rows);

  -- Yarisma sonucu gunluk etkinlik oldu (her iki oyuncu).
  select count(*) into v_rows
    from public.student_daily_activity
   where activity_day = public._faz9_local_day(now())
     and user_id in ('9f900000-0000-0000-0000-000000000001',
                     '9f900000-0000-0000-0000-000000000002');
  perform public._qa9_true('T-55',
    'tamamlanan yarisma gunluk etkinlik olusturur (her iki oyuncu)',
    v_rows = 2, 'aktivite=' || v_rows);
end;
$blk$;


-- ============================================================
-- BOLUM F: ROZETLER (tek seferlik, idempotent, otoriter kosullar)
-- ============================================================

do $blk$
declare
  v_u   uuid := '9f900000-0000-0000-0000-000000000003';
  v_cnt integer;
  v_ok  boolean;
begin
  -- W icin 50 dogru cevap (otoriter fact tablosu) + gecerli ilk
  -- etkinlik (first_step gunluk aktiviteye dayanir).
  perform public._faz9_record_daily_activity(v_u, now());

  insert into public.student_question_attempts
    (user_id, question_id, subject_id, attempt_context, result,
     attempt_number, academic_year, answered_at)
  select v_u, '9f910000-0000-0000-0000-000000000001',
         '9f905000-0000-0000-0000-000000000001', 'training', 'correct',
         g, 'QA9-YIL', now()
    from generate_series(1, 50) g;

  perform public._faz9_evaluate_badges(v_u);

  select count(*) into v_cnt
    from public.student_badges
   where user_id = v_u
     and badge_code in ('first_step', 'first_correct', 'correct_50');
  perform public._qa9_true('T-60',
    'first_step + first_correct + correct_50 otomatik grant',
    v_cnt = 3, 'granted=' || v_cnt);

  -- Tekrar degerlendirme DUPLICATE uretmez.
  perform public._faz9_evaluate_badges(v_u);
  select count(*) into v_cnt
    from public.student_badges
   where user_id = v_u
     and badge_code in ('first_step', 'first_correct', 'correct_50');
  perform public._qa9_true('T-61',
    'idempotent grant: ikinci degerlendirme DUPLICATE uretmez',
    v_cnt = 3, 'granted=' || v_cnt);

  -- wins_10: 10 kesinlesmis galibiyet.
  insert into public.competitions
    (id, competition_code, competition_type, grade_level, subject_id,
     scoring_rule_set_id, status, question_count)
  select ('9f920000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid,
         'QA9-W' || g, 'one_vs_one', 12,
         '9f905000-0000-0000-0000-000000000001'::uuid,
         '9f917000-0000-0000-0000-000000000001'::uuid, 'completed', 5
    from generate_series(1, 10) g;

  insert into public.competition_players
    (competition_id, user_id, player_slot, status)
  select ('9f920000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid,
         v_u, 1, 'active'
    from generate_series(1, 10) g;

  insert into public.competition_results
    (competition_id, winner_user_id, result_type)
  select ('9f920000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid,
         v_u, 'win_loss'
    from generate_series(1, 10) g;

  perform public._faz9_evaluate_badges(v_u);

  select count(*) into v_cnt
    from public.student_badges
   where user_id = v_u and badge_code = 'wins_10';
  perform public._qa9_true('T-62',
    'wins_10: 10 kesinlesmis galibiyetten otomatik grant',
    v_cnt = 1, 'granted=' || v_cnt);

  -- first_competition: tamamlanmis yarisma katilimi.
  perform public._faz9_evaluate_badges('9f900000-0000-0000-0000-000000000001');
  select count(*) into v_cnt
    from public.student_badges
   where user_id = '9f900000-0000-0000-0000-000000000001'
     and badge_code = 'first_competition';
  perform public._qa9_true('T-63',
    'first_competition: ilk tamamlanmis yarismada grant',
    v_cnt = 1, 'granted=' || v_cnt);

  -- Seri rozetleri: A'nin serisi (Bolum D'de B=2; A ingesting'de
  -- 1 gunluk aktivite) 3 esigine ulasirsa.
  select s.current_streak >= 3 into v_ok
    from public.student_streaks s
   where s.user_id = '9f900000-0000-0000-0000-000000000002';
  if v_ok is null then v_ok := false; end if;

  if v_ok then
    select count(*) into v_cnt
      from public.student_badges
     where user_id = '9f900000-0000-0000-0000-000000000002'
       and badge_code = 'streak_3';
    perform public._qa9_true('T-64',
      'streak_3: seri 3''e ulastiginda grant',
      v_cnt = 1, 'granted=' || v_cnt);
  else
    -- B serisi 3'e ulasmadiysa: esik davranisini dogrudan dogrula.
    perform public._faz9_record_daily_activity(
      '9f900000-0000-0000-0000-000000000002',
      now() + interval '1 day');
    perform public._faz9_record_daily_activity(
      '9f900000-0000-0000-0000-000000000002',
      now() + interval '2 day');
    perform public._faz9_evaluate_badges(
      '9f900000-0000-0000-0000-000000000002');
    select count(*) into v_cnt
      from public.student_badges
     where user_id = '9f900000-0000-0000-0000-000000000002'
       and badge_code = 'streak_3';
    perform public._qa9_true('T-64',
      'streak_3: seri 3''e ulastiginda grant',
      v_cnt = 1, 'granted=' || v_cnt);
  end if;
end;
$blk$;

-- T-65: rozet katalogu admin yonetimlidir; ogrenci yazamaz.
do $blk$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"9f900000-0000-0000-0000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    '9f900000-0000-0000-0000-000000000001', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  perform public._qa9_expect('T-65',
    'ogrenci rozet kataloguna YAZAMAZ (rewards.manage admin)',
    '42501',
    $sql$insert into public.badge_definitions
      (badge_code, name) values ('qa9_hack', 'Hack')$sql$);

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end;
$blk$;

-- T-66: katalog seed'i tam ve okunabilir (7 V1 rozeti).
do $blk$
declare
  v_cnt integer;
  v_read integer;
begin
  select count(*) into v_cnt
    from public.badge_definitions
   where badge_code in ('first_step', 'first_correct', 'streak_3',
                        'streak_7', 'correct_50',
                        'first_competition', 'wins_10');
  perform public._qa9_true('T-66',
    'V1 rozet katalogu 7 rozetle seed edilmis',
    v_cnt = 7, 'cnt=' || v_cnt);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    '{"sub":"9f900000-0000-0000-0000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    '9f900000-0000-0000-0000-000000000001', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  select count(*) into v_read
    from public.badge_definitions;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  perform public._qa9_true('T-67',
    'ogrenci rozet katalogunu OKUYABILIR',
    v_read >= 7, 'read=' || v_read);
end;
$blk$;


-- ============================================================
-- BOLUM G: PROFIL RPC (yalniz gercek degerler; ayri DTO alanlari)
-- ============================================================

do $blk$
declare
  v_json jsonb;
  v_sum  integer;
  v_ok   boolean;
  v_bad  boolean := false;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"9f900000-0000-0000-0000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    '9f900000-0000-0000-0000-000000000001', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  v_json := public.get_own_gamification_profile();

  select coalesce(sum(xp_amount), 0) into v_sum
    from public.student_xp_ledger
   where user_id = '9f900000-0000-0000-0000-000000000001';

  perform public._qa9_true('T-70',
    'profil RPC toplam XP = ledger toplami (otoriter)',
    (v_json -> 'xp' ->> 'total')::int = v_sum,
    'dto=' || coalesce(v_json -> 'xp' ->> 'total', '?') ||
    ' sum=' || v_sum);

  perform public._qa9_true('T-71',
    'seviye sunucuda hesaplanir ve DTO''da ayridir',
    (v_json -> 'xp' ->> 'level')::int =
      public.faz9_level_from_total_xp(v_sum::bigint),
    'level=' || coalesce(v_json -> 'xp' ->> 'level', '?'));

  -- Yabanci ekonomi anahtarlari DTO'da YOK (ayri ekonomiler).
  v_bad := v_json ? 'stars' or v_json ? 'rating'
           or v_json ? 'competition_points' or v_json ? 'wallet'
           or (v_json -> 'xp') ? 'stars';
  perform public._qa9_true('T-72',
    'DTO yildiz/lig rating/yarisma puani ICERMEZ (ayri ekonomiler)',
    not v_bad,
    'keys=' || (select string_agg(k, ',') from jsonb_object_keys(v_json) k));

  perform public._qa9_true('T-73',
    'DTO bolumleri: xp, streak, daily_quota, badges (ayri anahtarlar)',
    v_json ? 'xp' and v_json ? 'streak' and v_json ? 'daily_quota'
      and v_json ? 'badges',
    'keys=' || (select string_agg(k, ',') from jsonb_object_keys(v_json) k));

  select (v_json -> 'daily_quota' ->> 'limit')::int = 500 into v_ok;
  perform public._qa9_true('T-74',
    'gunluk kota DTO: limit 500 ve Europe/Istanbul gunu',
    v_ok and (v_json -> 'daily_quota' ->> 'day') is not null,
    'daily=' || coalesce((v_json -> 'daily_quota')::text, 'yok'));

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end;
$blk$;


-- ============================================================
-- BOLUM H: FAZ 9B DAVRANISSEL TESTLER (T-75..T-79)
-- ============================================================

-- ------------------------------------------------------------
-- T-75: cancelled/disputed yarismalar XP, gunluk etkinlik,
-- current/longest streak, first_competition ve wins_10
-- rozetlerini DEGISTIRMEZ (105 guard).
-- ------------------------------------------------------------
do $blk$
declare
  v_u uuid := '9f900000-0000-0000-0000-000000000005';
  v_v uuid := '9f900000-0000-0000-0000-000000000006';
  v_cnt integer;
  v_act integer;
  v_stk integer;
begin
  insert into public.competitions
    (id, competition_code, competition_type, grade_level,
     scoring_rule_set_id, status, question_count,
     server_completed_at, completed_at)
  values
    ('9f920000-0000-0000-0000-000000000004', 'QA9-C4-CANCEL', 'one_vs_one', 12,
     '9f917000-0000-0000-0000-000000000001', 'completed', 5, now(), now()),
    ('9f920000-0000-0000-0000-000000000005', 'QA9-C5-DISPUTED', 'one_vs_one', 12,
     '9f917000-0000-0000-0000-000000000001', 'completed', 5, now(), now());

  insert into public.competition_players
    (competition_id, user_id, player_slot, status) values
    ('9f920000-0000-0000-0000-000000000004', v_u, 1, 'active'),
    ('9f920000-0000-0000-0000-000000000004', v_v, 2, 'active'),
    ('9f920000-0000-0000-0000-000000000005', v_u, 1, 'active'),
    ('9f920000-0000-0000-0000-000000000005', v_v, 2, 'active');

  insert into public.competition_results
    (competition_id, winner_user_id, result_type) values
    ('9f920000-0000-0000-0000-000000000004', null, 'cancelled'),
    ('9f920000-0000-0000-0000-000000000005', null, 'disputed');

  -- BASLANGIC: temiz durum.
  select count(*) into v_act
    from public.student_daily_activity
   where user_id in (v_u, v_v);
  select count(*) into v_stk
    from public.student_streaks
   where user_id in (v_u, v_v);
  perform public._qa9_true('T-75a',
    'T-75 baslangic: U/V icin aktivite ve seri YOK',
    v_act = 0 and v_stk = 0,
    'aktivite=' || v_act || ' seri=' || v_stk);

  perform public._faz5_apply_competition_points(
    '9f920000-0000-0000-0000-000000000004');
  perform public._faz5_apply_competition_points(
    '9f920000-0000-0000-0000-000000000005');

  -- XP: cancelled/disputed 0 (ledger kaydi yok).
  select count(*) into v_cnt
    from public.student_xp_ledger
   where source_id in ('9f920000-0000-0000-0000-000000000004',
                       '9f920000-0000-0000-0000-000000000005');
  perform public._qa9_true('T-75b',
    'T-75: cancelled/disputed 0 XP (ledger kaydi uretmez)',
    v_cnt = 0, 'ledger=' || v_cnt);

  -- Gunluk etkinlik + seri URETMEZ.
  select count(*) into v_act
    from public.student_daily_activity
   where user_id in (v_u, v_v);
  select count(*) into v_stk
    from public.student_streaks
   where user_id in (v_u, v_v);
  perform public._qa9_true('T-75c',
    'T-75: cancelled/disputed gunluk etkinlik ve streak URETMEZ',
    v_act = 0 and v_stk = 0,
    'aktivite=' || v_act || ' seri=' || v_stk);

  -- Rozetler: evaluate acikca cagrilsa bile yarisma rozetleri
  -- ve aktivite-bazli first_step VERILMEZ.
  perform public._faz9_evaluate_badges(v_u);
  perform public._faz9_evaluate_badges(v_v);
  select count(*) into v_cnt
    from public.student_badges
   where user_id in (v_u, v_v)
     and badge_code in ('first_competition', 'wins_10',
                        'first_step', 'streak_3');
  perform public._qa9_true('T-75e',
    'T-75: cancelled/disputed yarisma rozetlerini URETMEZ',
    v_cnt = 0, 'rozet=' || v_cnt);

  -- Duplicate apply (idempotency): hala sifir.
  perform public._faz5_apply_competition_points(
    '9f920000-0000-0000-0000-000000000004');
  perform public._faz5_apply_competition_points(
    '9f920000-0000-0000-0000-000000000005');
  select count(*) into v_act
    from public.student_daily_activity
   where user_id in (v_u, v_v);
  select count(*) into v_stk
    from public.student_streaks
   where user_id in (v_u, v_v);
  perform public._qa9_true('T-75f',
    'T-75: duplicate apply sonrasi hala aktivite/seri/rozet YOK',
    v_act = 0 and v_stk = 0,
    'aktivite=' || v_act || ' seri=' || v_stk);
end;
$blk$;

-- ------------------------------------------------------------
-- T-76: ayni antrenman attempt/cevap isleminin tekrari (ayni
-- client_key) yalniz BIR ledger kaydi ve TEK XP artisi uretir.
-- ------------------------------------------------------------
do $blk$
declare
  v_key uuid := '9f990000-0000-0000-0000-000000000011';
  v_res jsonb;
  v_total integer;
  v_total2 integer;
  v_rows integer;
begin
  insert into public.student_question_exposures
    (user_id, question_id, attempt_context)
  values ('9f900000-0000-0000-0000-000000000001',
          '9f910000-0000-0000-0000-000000000001', 'training');

  perform set_config('request.jwt.claims',
    '{"sub":"9f900000-0000-0000-0000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    '9f900000-0000-0000-0000-000000000001', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  select total_xp into v_total
    from public.student_xp_totals
   where user_id = '9f900000-0000-0000-0000-000000000001';

  v_res := public.submit_training_attempt(
    '9f910000-0000-0000-0000-000000000001', 'a', null, 5000, v_key);

  perform public._qa9_true('T-76a',
    'T-76: ilk submit correct + duplicate=false',
    v_res ->> 'result' = 'correct'
      and (v_res ->> 'duplicate')::boolean is false,
    'res=' || coalesce(v_res ->> 'result', '?') ||
    ' dup=' || coalesce(v_res ->> 'duplicate', '?'));

  select count(*) into v_rows
    from public.student_xp_ledger l
    join public.student_question_attempts a on a.id = l.source_id
   where l.source_type = 'training_attempt'
     and l.user_id = '9f900000-0000-0000-0000-000000000001'
     and a.user_id = '9f900000-0000-0000-0000-000000000001'
     and a.metadata ->> 'client_key' = v_key::text;
  perform public._qa9_true('T-76b',
    'T-76: ayni islem icin ledger tam 1 kayit',
    v_rows = 1, 'ledger=' || v_rows);

  select total_xp into v_total2
    from public.student_xp_totals
   where user_id = '9f900000-0000-0000-0000-000000000001';
  perform public._qa9_true('T-76c',
    'T-76: ilk submit toplam XP''ye +2 ekledi (kolay)',
    v_total2 = v_total + 2,
    'once=' || v_total || ' sonra=' || v_total2);

  -- Ayni client_key ile tekrar: duplicate, ek XP YOK.
  v_res := public.submit_training_attempt(
    '9f910000-0000-0000-0000-000000000001', 'a', null, 5000, v_key);

  perform public._qa9_true('T-76d',
    'T-76: tekrar submit duplicate=true',
    (v_res ->> 'duplicate')::boolean is true,
    'dup=' || coalesce(v_res ->> 'duplicate', '?'));

  select count(*) into v_rows
    from public.student_xp_ledger l
    join public.student_question_attempts a on a.id = l.source_id
   where l.source_type = 'training_attempt'
     and l.user_id = '9f900000-0000-0000-0000-000000000001'
     and a.user_id = '9f900000-0000-0000-0000-000000000001'
     and a.metadata ->> 'client_key' = v_key::text;
  select total_xp into v_total
    from public.student_xp_totals
   where user_id = '9f900000-0000-0000-0000-000000000001';
  perform public._qa9_true('T-76e',
    'T-76: tekrar submit ikinci XP URETMEZ (1 ledger, ayni toplam)',
    v_rows = 1 and v_total = v_total2,
    'ledger=' || v_rows || ' total=' || v_total);

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end;
$blk$;

-- ------------------------------------------------------------
-- T-77: 7 ardisik Europe/Istanbul gunu streak_7 rozetini TAM
-- BIR kez verir; ayni gun/tekrar cagri ikinci grant uretmez.
-- ------------------------------------------------------------
do $blk$
declare
  v_u   uuid := '9f900000-0000-0000-0000-000000000007';
  v_now timestamptz := now();
  v_cnt integer;
  v_cur integer;
begin
  perform public._faz9_record_daily_activity(v_u, v_now - interval '6 day');
  perform public._faz9_record_daily_activity(v_u, v_now - interval '5 day');
  perform public._faz9_record_daily_activity(v_u, v_now - interval '4 day');
  perform public._faz9_record_daily_activity(v_u, v_now - interval '3 day');
  perform public._faz9_record_daily_activity(v_u, v_now - interval '2 day');
  perform public._faz9_record_daily_activity(v_u, v_now - interval '1 day');
  perform public._faz9_record_daily_activity(v_u, v_now);

  select current_streak into v_cur
    from public.student_streaks where user_id = v_u;
  perform public._qa9_true('T-77a',
    'T-77: 7 ardisik gun → current=7',
    v_cur = 7, 'cur=' || v_cur);

  perform public._faz9_evaluate_badges(v_u);
  select count(*) into v_cnt
    from public.student_badges
   where user_id = v_u and badge_code = 'streak_7';
  perform public._qa9_true('T-77b',
    'T-77: streak_7 TAM 1 kez verildi',
    v_cnt = 1, 'rozet=' || v_cnt);

  -- Ayni gun ek etkinlik + tekrar degerlendirme: ikinci grant YOK.
  perform public._faz9_record_daily_activity(v_u, v_now + interval '2 hour');
  perform public._faz9_evaluate_badges(v_u);
  perform public._faz9_evaluate_badges(v_u);
  select count(*) into v_cnt
    from public.student_badges
   where user_id = v_u and badge_code = 'streak_7';
  perform public._qa9_true('T-77c',
    'T-77: ayni gun/tekrar cagri ikinci streak_7 URETMEZ',
    v_cnt = 1, 'rozet=' || v_cnt);
end;
$blk$;

-- ------------------------------------------------------------
-- T-78: 499 dolu sayacta PARALEL iki tuketim oturumu: en fazla
-- biri tuketir; final sayaç TAM 500; 501 imkansiz; ikinci
-- tuketici kontrollu kota hatasi alir.
--
-- Yontem: dblink ile ikinci GERCEK baglanti (paralel islem)
-- acilir; oturum-1 satiri FOR UPDATE ile kilitler, oturum-2
-- lock_timeout icinde ilerleyemez (55P03). Oturum-1 tuketip
-- commit eder; committed final = 500 dogrulanir.
-- ------------------------------------------------------------
do $blk$
declare
  v_r     uuid := '9f900000-0000-0000-0000-000000000008';
  v_day   date := public._faz9_local_day(now());
  v_used  integer;
  v_rem   integer;
begin
  create extension if not exists dblink;
  perform dblink_connect('qa78',
    'host=/var/run/postgresql port=5432 dbname=postgres user=supabase_admin');

  -- R kullanici + 499 dolu sayaç (COMMITTED; paralel oturumun
  -- gorunur olması icin).
  perform dblink_exec('qa78', 'begin');
  perform dblink_exec('qa78', format(
    'insert into auth.users (id, email) values (%L, %L) on conflict (id) do nothing',
    v_r, 'qa9-r78@test.local'));
  perform dblink_exec('qa78', format(
    'insert into public.student_daily_question_counters (user_id, quota_day, questions_used) values (%L, %L, 499) on conflict do nothing',
    v_r, v_day));
  perform dblink_exec('qa78', 'commit');

  -- Oturum-1: satiri kilitler ve TUTAR (islem acik).
  perform dblink_exec('qa78', 'begin');
  perform * from dblink('qa78', format(
    'select public._faz9_lock_daily_counter(%L::uuid, %L::date)',
    v_r, v_day)) as t(remaining int);

  -- Oturum-2 (ana): kilitli satirda 1.5 sn icinde ilerleyemez.
  set local lock_timeout = '1500ms';
  perform public._qa9_expect('T-78a',
    'T-78: kilitli sayacta paralel tuketici BEKLEMEK ZORUNDA (55P03)',
    '55P03',
    format($f$
      select public._faz9_lock_daily_counter('%s'::uuid, '%s'::date)
    $f$, v_r, v_day));

  -- Oturum-1: kalan 1 hakki tuketir (499 → 500) ve commit eder.
  perform * from dblink('qa78', format(
    'select public._faz9_consume_daily_quota(%L::uuid, %L::date, 1)::text',
    v_r, v_day)) as t(x text);
  perform dblink_exec('qa78', 'commit');

  -- Final sayaç TAM 500 (committed; ana oturumda lokal yazim yok
  -- — T-78a subtransaction rollback edildi).
  select questions_used into v_used
    from public.student_daily_question_counters
   where user_id = v_r and quota_day = v_day;
  perform public._qa9_true('T-78b',
    'T-78: paralel yarista final sayaç TAM 500, 501 DEGIL',
    v_used = 500, 'used=' || coalesce(v_used::text, 'yok'));

  -- 501 imkansiz: kontrollu P0001 (dolu sayacta 1 hak da reddedilir).
  perform public._qa9_expect('T-78c',
    'T-78: 500 dolu sayacta ek tuketim kontrollu P0001 ile reddedilir',
    'P0001',
    format($f$
      select * from dblink('qa78',
        'select public._faz9_consume_daily_quota(''%s''::uuid, ''%s''::date, 1)::text'
      ) as t(x text)
    $f$, v_r, v_day));

  -- Ikinci tuketici kalan 0 gorur → select kontrollu
  -- gunluk_kota_doldu yoluna girer (istisna degil).
  select t.remaining into v_rem
    from dblink('qa78', format(
      'select public._faz9_lock_daily_counter(%L::uuid, %L::date) as remaining',
      v_r, v_day)) as t(remaining int);
  perform public._qa9_true('T-78d',
    'T-78: ikinci tuketici kalan 0 gorur (kontrollu kota-doldu yolu)',
    v_rem = 0, 'kalan=' || coalesce(v_rem::text, 'yok'));

  -- Temizlik (committed): bu testin kendi kaynaklari.
  perform dblink_exec('qa78', 'begin');
  perform dblink_exec('qa78', format(
    'delete from public.student_daily_question_counters where user_id = %L', v_r));
  perform dblink_exec('qa78', format(
    'delete from auth.users where id = %L', v_r));
  perform dblink_exec('qa78', 'commit');
  perform dblink_disconnect('qa78');
end;
$blk$;

-- ------------------------------------------------------------
-- T-79: rewards.manage katalog/izin yolu tekrar calistirilinca
-- DUPLICATE kayit veya yetki genislemesi URETMEZ (migration
-- dosyasi koyu calistirilmaz; ayni idempotent ifadeler test edilir).
-- ------------------------------------------------------------
do $blk$
declare
  v_perm_cnt  integer;
  v_link_cnt  integer;
  v_other_cnt integer;
begin
  -- Migration 103'teki birebir idempotent ifadeler (1. tekrar).
  insert into public.admin_permissions
    (permission_code, name, description)
  values ('rewards.manage',
          'Ödülleri Yönet',
          'Rozet kataloğunu yönetebilir.')
  on conflict (permission_code) do update
    set name = excluded.name,
        description = excluded.description;

  insert into public.admin_role_permissions
    (role_id, permission_id)
  select ar.id, ap.id
    from public.admin_roles ar
   cross join public.admin_permissions ap
   where ar.role_code = 'super_admin'
     and ap.permission_code = 'rewards.manage'
  on conflict do nothing;

  -- 2. tekrar (aynı ifadeler).
  insert into public.admin_permissions
    (permission_code, name, description)
  values ('rewards.manage',
          'Ödülleri Yönet',
          'Rozet kataloğunu yönetebilir.')
  on conflict (permission_code) do update
    set name = excluded.name,
        description = excluded.description;

  insert into public.admin_role_permissions
    (role_id, permission_id)
  select ar.id, ap.id
    from public.admin_roles ar
   cross join public.admin_permissions ap
   where ar.role_code = 'super_admin'
     and ap.permission_code = 'rewards.manage'
  on conflict do nothing;

  select count(*) into v_perm_cnt
    from public.admin_permissions
   where permission_code = 'rewards.manage';
  perform public._qa9_true('T-79a',
    'T-79: tekrar uygulama DUPLICATE izin kaydi uretmez (tam 1)',
    v_perm_cnt = 1, 'izin=' || v_perm_cnt);

  select count(*) into v_link_cnt
    from public.admin_role_permissions rp
    join public.admin_roles ar on ar.id = rp.role_id
    join public.admin_permissions ap on ap.id = rp.permission_id
   where ar.role_code = 'super_admin'
     and ap.permission_code = 'rewards.manage';
  perform public._qa9_true('T-79b',
    'T-79: tekrar uygulama DUPLICATE super_admin baglantisi uretmez (tam 1)',
    v_link_cnt = 1, 'baglanti=' || v_link_cnt);

  -- Yetki genislemesi YOK: baska hicbir role baglanmamis.
  select count(*) into v_other_cnt
    from public.admin_role_permissions rp
    join public.admin_roles ar on ar.id = rp.role_id
    join public.admin_permissions ap on ap.id = rp.permission_id
   where ap.permission_code = 'rewards.manage'
     and ar.role_code <> 'super_admin';
  perform public._qa9_true('T-79c',
    'T-79: rewards.manage baska role SIÇMAZ (yetki genislemesi 0)',
    v_other_cnt = 0, 'diger=' || v_other_cnt);
end;
$blk$;


-- ============================================================
-- OZET + ROLLBACK
-- ============================================================

do $blk$
declare
  v_pass integer; v_fail integer;
  r record;
begin
  select count(*) filter (where result = 'PASS'),
         count(*) filter (where result = 'FAIL')
    into v_pass, v_fail
    from public._qa_faz9_results;

  raise notice 'QA FAZ 9 OZET: PASS=% FAIL=%', v_pass, v_fail;

  if v_fail > 0 then
    raise notice 'BASARISIZ TESTLER:';
    for r in
      select label, title, detail
        from public._qa_faz9_results
       where result = 'FAIL'
       order by label
    loop
      raise notice '  % | % | %', r.label, r.title, r.detail;
    end loop;
  end if;
end;
$blk$;

select label, result, title, coalesce(detail, '') as detail
  from public._qa_faz9_results
 order by label;

rollback;
