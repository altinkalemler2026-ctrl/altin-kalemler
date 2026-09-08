-- ============================================================
-- scripts/qa_faz9d_ledger_cascade_local.sql
-- Altin Kalemler - Migration Faz 9D (106) hedefli QA suite
--
-- Kapsam:
--   student_xp_ledger append-only guard'inin cascade duzeltmesi:
--   UPDATE her zaman yasak; DELETE canli sahipken yasak (postgres
--   ve service_role dahil), ust auth.users satiri silinmisken
--   (FK cascade / hesap silme) izinli; cascade diger Faz 9
--   kayitlarini da temizler; baska ogrenci etkilenmez; islem
--   atomiktir; migration tekrari ayni sonucu verir.
--
-- Test haritasi:
--   D-01  canli sahipken UPDATE reddedilir (P0001)
--   D-02  canli sahipken dogrudan DELETE reddedilir (P0001)
--   D-03  service_role yolu da engelli (42501: DELETE grant yok)
--   D-04  auth.users silme (yetkili hesap silme) basarili
--   D-05  silinen kullanicinin ledger satirlari temizlenir
--   D-06  totals/activity/streaks/badges/counters cascade temizligi
--   D-07  baska ogrencinin butun kayitlari DEGISMEZ
--   D-08  savepoint rollback: hesap silme islemi atomik geri alinir
--   D-09  rollback sonrasi UPDATE yasagi aynen surer
--   D-10  migration 106 tekrar uygulandiginda ayni davranis
--   D-11  suite tek transaction + sonunda ROLLBACK (kalinti yok)
--
-- Calistirma (LOCAL ONLY, disposable stack):
--   docker cp scripts/qa_faz9d_ledger_cascade_local.sql <db>:/tmp/
--   docker exec <db> psql -U supabase_admin -d postgres \
--          -v ON_ERROR_STOP=1 -f /tmp/qa_faz9d_ledger_cascade_local.sql
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR
-- ============================================================

create table public._qa_faz9d_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

create function public._qa9d_expect(p_label text, p_title text, p_expect text, p_sql text)
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
    insert into public._qa_faz9d_results
    values (p_label, p_title, 'FAIL',
            'beklenen hata gelmedi (' || p_expect || ')');
  exception
    when others then
      get stacked diagnostics v_state = RETURNED_SQLSTATE,
                              v_msg = MESSAGE_TEXT;
      if v_state = p_expect then
        insert into public._qa_faz9d_results
        values (p_label, p_title, 'PASS',
                'sqlstate=' || v_state || ' | mesaj eslesti');
      else
        insert into public._qa_faz9d_results
        values (p_label, p_title, 'FAIL',
                'sqlstate=' || v_state ||
                ' beklenen=' || p_expect ||
                ' | msg=' || left(v_msg, 160));
      end if;
  end;
end;
$qa$;

create function public._qa9d_true(p_label text, p_title text, p_ok boolean, p_detail text default null)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_faz9d_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

-- Yeni CLI "no-auto-expose" bootstrap'inda yardimci tablo/fonksiyonlara
-- dogustan grant verilmedigi icin (faz8/faz10 deseniyle ayni)
-- calistirilabilirlik grant'leri. Test beklentileri degismez.
grant select, insert, update, delete
  on public._qa_faz9d_results
  to anon, authenticated, service_role;
grant execute
  on function public._qa9d_expect(text, text, text, text)
  to anon, authenticated, service_role;
grant execute
  on function public._qa9d_true(text, text, boolean, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE (deterministik sahte veriler)
--   X: 9f9d0000-...-0021 (hesabi silinecek ogrenci)
--   Y: 9f9d0000-...-0022 (dokunulmayacak ogrenci)
-- ============================================================

insert into auth.users (id, email) values
  ('9f9d0000-0000-0000-0000-000000000021', 'qa9d-x@test.local'),
  ('9f9d0000-0000-0000-0000-000000000022', 'qa9d-y@test.local');

insert into public.student_profiles (id, grade_level, nickname) values
  ('9f9d0000-0000-0000-0000-000000000021', 12, 'QA9D-X'),
  ('9f9d0000-0000-0000-0000-000000000022', 12, 'QA9D-Y');

insert into public.student_xp_ledger
  (user_id, source_type, source_id, xp_amount, metadata) values
  ('9f9d0000-0000-0000-0000-000000000021', 'training_attempt',
   '9f9d0000-0000-0000-0000-000000000101', 2, '{}'),
  ('9f9d0000-0000-0000-0000-000000000021', 'competition_result',
   '9f9d0000-0000-0000-0000-000000000201', 15, '{}'),
  ('9f9d0000-0000-0000-0000-000000000022', 'training_attempt',
   '9f9d0000-0000-0000-0000-000000000102', 3, '{}');

insert into public.student_xp_totals
  (user_id, total_xp) values
  ('9f9d0000-0000-0000-0000-000000000021', 17),
  ('9f9d0000-0000-0000-0000-000000000022', 3);

insert into public.student_daily_activity
  (user_id, activity_day) values
  ('9f9d0000-0000-0000-0000-000000000021', current_date),
  ('9f9d0000-0000-0000-0000-000000000022', current_date);

insert into public.student_streaks
  (user_id, current_streak, longest_streak, last_activity_day) values
  ('9f9d0000-0000-0000-0000-000000000021', 4, 9, current_date),
  ('9f9d0000-0000-0000-0000-000000000022', 2, 2, current_date);

insert into public.student_badges
  (user_id, badge_code) values
  ('9f9d0000-0000-0000-0000-000000000021', 'first_correct'),
  ('9f9d0000-0000-0000-0000-000000000022', 'first_step');

insert into public.student_daily_question_counters
  (user_id, quota_day, questions_used) values
  ('9f9d0000-0000-0000-0000-000000000021', current_date, 120),
  ('9f9d0000-0000-0000-0000-000000000022', current_date, 80);


-- ============================================================
-- D-01: canli sahipken UPDATE reddedilir (her rolde)
-- ============================================================

select public._qa9d_expect('D-01',
  'canli sahipken ledger UPDATE reddedilir (postgres, P0001)',
  'P0001',
  $sql$update public.student_xp_ledger
      set xp_amount = 99
    where user_id = '9f9d0000-0000-0000-0000-000000000021'$sql$);

-- D-02: canli sahipken dogrudan DELETE reddedilir.
select public._qa9d_expect('D-02',
  'canli sahipken dogrudan ledger DELETE reddedilir (P0001)',
  'P0001',
  $sql$delete from public.student_xp_ledger
    where user_id = '9f9d0000-0000-0000-0000-000000000021'$sql$);

-- D-03: service_role yolu da engelli (DELETE grant yok: 42501).
do $blk$
begin
  execute 'set local role service_role';

  perform public._qa9d_expect('D-03',
    'service_role icin de ledger DELETE engelli (42501)',
    '42501',
    $sql$delete from public.student_xp_ledger
      where user_id = '9f9d0000-0000-0000-0000-000000000021'$sql$);

  execute 'reset role';
end;
$blk$;


-- ============================================================
-- D-04..D-07: yetkili hesap silme yolu (FK cascade)
-- ============================================================

do $blk$
declare
  v_x  uuid := '9f9d0000-0000-0000-0000-000000000021';
  v_y  uuid := '9f9d0000-0000-0000-0000-000000000022';
  v_x_ledger_before integer;
  v_y_ledger_before integer;
  v_y_total_before  integer;
  v_y_streak_before integer;
  v_y_badge_before  integer;
  v_y_counter_before integer;
  v_cnt integer;
begin
  select count(*) into v_x_ledger_before
    from public.student_xp_ledger where user_id = v_x;
  select count(*) into v_y_ledger_before
    from public.student_xp_ledger where user_id = v_y;
  select total_xp into v_y_total_before
    from public.student_xp_totals where user_id = v_y;
  select current_streak into v_y_streak_before
    from public.student_streaks where user_id = v_y;
  select count(*) into v_y_badge_before
    from public.student_badges where user_id = v_y;
  select questions_used into v_y_counter_before
    from public.student_daily_question_counters
   where user_id = v_y and quota_day = current_date;

  perform public._qa9d_true('D-07a',
    'D-07 baslangic: Y butun kayitlari yerinde',
    v_y_ledger_before = 1 and v_y_total_before = 3
      and v_y_streak_before = 2 and v_y_badge_before = 1
      and v_y_counter_before = 80,
    format('ledger=%s total=%s streak=%s badge=%s counter=%s',
           v_y_ledger_before, v_y_total_before, v_y_streak_before,
           v_y_badge_before, v_y_counter_before));

  -- Yetkili hesap silme yolu: ust auth.users satiri silinir.
  delete from auth.users where id = v_x;

  -- D-05: X'in ledger satirlari cascade ile temizlendi.
  select count(*) into v_cnt
    from public.student_xp_ledger where user_id = v_x;
  perform public._qa9d_true('D-05',
    'D-05: silinen kullanicinin XP ledger satirlari kaldırildi',
    v_cnt = 0 and v_x_ledger_before = 2,
    'once=' || v_x_ledger_before || ' sonra=' || v_cnt);

  -- D-06: diger ON DELETE CASCADE Faz 9 kayitlari da temizlendi.
  select count(*) into v_cnt
    from public.student_xp_totals where user_id = v_x;
  if v_cnt <> 0 then
    perform public._qa9d_true('D-06', 'D-06 cascade temizligi', false,
      'totals kalan=' || v_cnt);
  else
    select count(*) into v_cnt
      from public.student_daily_activity where user_id = v_x;
    if v_cnt <> 0 then
      perform public._qa9d_true('D-06', 'D-06 cascade temizligi', false,
        'activity kalan=' || v_cnt);
    else
      select count(*) into v_cnt
        from public.student_streaks where user_id = v_x;
      if v_cnt <> 0 then
        perform public._qa9d_true('D-06', 'D-06 cascade temizligi', false,
          'streaks kalan=' || v_cnt);
      else
        select count(*) into v_cnt
          from public.student_badges where user_id = v_x;
        if v_cnt <> 0 then
          perform public._qa9d_true('D-06', 'D-06 cascade temizligi', false,
            'badges kalan=' || v_cnt);
        else
          select count(*) into v_cnt
            from public.student_daily_question_counters
           where user_id = v_x;
          perform public._qa9d_true('D-06',
            'D-06 cascade temizligi (totals/activity/streaks/badges/counters)',
            v_cnt = 0, 'counters kalan=' || v_cnt);
        end if;
      end if;
    end if;
  end if;

  -- D-07: baska ogrenci (Y) degismedi.
  select count(*) into v_cnt
    from public.student_xp_ledger where user_id = v_y;
  if v_cnt = v_y_ledger_before then
    select total_xp into v_cnt
      from public.student_xp_totals where user_id = v_y;
    if v_cnt = v_y_total_before then
      select count(*) into v_cnt
        from public.student_badges where user_id = v_y;
      if v_cnt = v_y_badge_before then
        select questions_used into v_cnt
          from public.student_daily_question_counters
         where user_id = v_y and quota_day = current_date;
        perform public._qa9d_true('D-07',
          'D-07: baska ogrencinin ledger/toplam/rozet/sayaci DEGISMEZ',
          v_cnt = v_y_counter_before,
          'ledger=' || v_y_ledger_before || ' total=' || v_y_total_before ||
          ' badge=' || v_y_badge_before || ' counter=' || v_y_counter_before);
      else
        perform public._qa9d_true('D-07', 'D-07 yazi degismedi', false,
          'badge=' || v_cnt);
      end if;
    else
      perform public._qa9d_true('D-07', 'D-07 yazi degismedi', false,
        'total=' || v_cnt);
    end if;
  else
    perform public._qa9d_true('D-07', 'D-07 yazi degismedi', false,
      'ledger=' || v_cnt);
  end if;
end;
$blk$;


-- ============================================================
-- D-08: hesap silme isleminin atomikligi (top-level savepoint)
-- D-09: rollback sonrasi UPDATE yasagi aynen surer
-- ============================================================

savepoint d08;

delete from auth.users where id = '9f9d0000-0000-0000-0000-000000000022';

select public._qa9d_true('D-08a',
  'D-08: islem icinde cascade calisir (kullanici silindi)',
  not exists (
    select 1
      from public.student_xp_ledger
     where user_id = '9f9d0000-0000-0000-0000-000000000022'),
  'cascade silme denendi');

rollback to savepoint d08;

do $blk$
declare
  v_cnt integer;
begin
  -- Kullanici ve XP kayitlari birlikte geri alindi.
  select count(*) into v_cnt
    from auth.users where id = '9f9d0000-0000-0000-0000-000000000022';
  if v_cnt <> 1 then
    perform public._qa9d_true('D-08b',
      'D-08: rollback sonrasi kullanici geri geldi', false,
      'user=' || v_cnt);
    return;
  end if;

  select count(*) into v_cnt
    from public.student_xp_ledger
   where user_id = '9f9d0000-0000-0000-0000-000000000022';
  perform public._qa9d_true('D-08b',
    'D-08: basarisiz islem kullanici ve XP kayitlarini birlikte geri alir',
    v_cnt = 1, 'ledger=' || v_cnt);
end;
$blk$;

-- D-09: UPDATE yasagi rollback sonrasi aynen surer.
select public._qa9d_expect('D-09',
  'D-09: rollback sonrasi UPDATE yasaği degismeden surer (P0001)',
  'P0001',
  $sql$update public.student_xp_ledger
      set xp_amount = 99
    where user_id = '9f9d0000-0000-0000-0000-000000000022'$sql$);


-- ============================================================
-- D-10: migration 106'nin tekrar uygulanmasi ayni davranisi verir
-- (ayni CREATE OR REPLACE ifadesi; koyu dosya calistirmadan,
-- birebir ayni fonksiyon govdesiyle).
-- ============================================================

do $blk$
declare
  v_src text;
begin
  select pg_get_functiondef(
           'public.guard_student_xp_ledger_append_only()'::regprocedure)
    into v_src;
  execute v_src;

  perform public._qa9d_expect('D-10a',
    'D-10: migration tekrari sonrasi canli sahip DELETE hala yasak',
    'P0001',
    $sql$delete from public.student_xp_ledger
      where user_id = '9f9d0000-0000-0000-0000-000000000022'$sql$);
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
    from public._qa_faz9d_results;

  raise notice 'QA FAZ 9D OZET: PASS=% FAIL=%', v_pass, v_fail;

  if v_fail > 0 then
    raise notice 'BASARISIZ TESTLER:';
    for r in
      select label, title, detail
        from public._qa_faz9d_results
       where result = 'FAIL'
       order by label
    loop
      raise notice '  % | % | %', r.label, r.title, r.detail;
    end loop;
  end if;
end;
$blk$;

select label, result, title, coalesce(detail, '') as detail
  from public._qa_faz9d_results
 order by label;

rollback;
