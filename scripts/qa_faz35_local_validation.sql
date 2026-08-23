-- ============================================================
-- scripts/qa_faz35_local_validation.sql
-- Altin Kalemler - Migration Faz 3.5 yerel QA suite
--
-- Kapsam (academic_weeks yonetimi, 073):
--   T-01..03 : anon -> tum takvim RPC'leri EXECUTE-denied
--   T-04..05 : rol/izni olmayan authenticated ogrenci -> in-func red
--   T-06..07 : yanlis yetkili admin (copyright_reviewer) -> in-func red
--   T-08..09 : calendar.manage admin okuma + upsert OK
--   T-10     : ayni yil cakismasi RED (mesaj dogrulamali)
--   T-11     : farkli yil cakismasi RED (Faz 3.5 kurali)
--   T-12..13 : baslamis/gecmis hafta guncelleme + silme RED
--   T-14     : attempt referansli gelecek hafta silme RED
--   T-15     : gelecek + referanssiz hafta silme OK
--   T-16     : gecersiz girdi (hafta 99) RED
--   T-17..18 : takvim -> donem cozumleyici zinciri; takvim bosken
--              Training fail-closed (P0001 akademik donem bulunamadi)
--   T-19     : 074 DB backstop - RPC'yi bypass eden dogrudan INSERT
--              dahi farkli yilla cakisan aralikta 23P01 alir
--   T-20     : 074 global EXCLUDE constraint'in varligi dogrulanir
--
-- Calistirma (LOCAL ONLY):
--   docker cp scripts/qa_faz35_local_validation.sql supabase_db_yarisma-programi:/tmp/
--   docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -f /tmp/qa_faz35_local_validation.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR
-- ============================================================

create table public._qa_faz35_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_faz35_results
  to anon, authenticated, service_role;

create function public._qa35_expect(p_label text, p_title text, p_expect text, p_sql text)
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
      insert into public._qa_faz35_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_faz35_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_faz35_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | ' || left(v_msg, 160));
    else
      insert into public._qa_faz35_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || coalesce(nullif(p_expect, ''), '-') ||
              ' | ' || left(v_msg, 200));
    end if;
  end;
end;
$qa$;

create function public._qa35_expect_msg(
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
    insert into public._qa_faz35_results
    values (p_label, p_title, 'FAIL',
            'hata beklenmisti ama uygulandi');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if v_state = p_state and upper(v_msg) like upper(p_msg_pattern) then
      insert into public._qa_faz35_results
      values (p_label, p_title, 'PASS',
              'sqlstate=' || v_state || ' | mesaj eslesti');
    else
      insert into public._qa_faz35_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state ||
              ' beklenen=' || p_state ||
              ' | msg=' || left(v_msg, 160));
    end if;
  end;
end;
$qa$;

create function public._qa35_true(p_label text, p_title text, p_ok boolean, p_detail text default null)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_faz35_results
  values (p_label, p_title,
          case when p_ok then 'PASS' else 'FAIL' end,
          p_detail);
end;
$qa$;

grant execute
  on function public._qa35_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa35_expect_msg(text, text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa35_true(text, text, boolean, text)
  to anon, authenticated, service_role;

create function public._qa35_as(p_uid uuid)
returns void
language plpgsql
security invoker
as $qa$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
end;
$qa$;


-- ============================================================
-- FIXTURE'LAR (rollback ile silinecek)
-- subject: 045 seed matematik (430903f3-...)
-- ============================================================

insert into auth.users (id, email) values
  ('99999999-9999-9999-9999-999999999911', 'qa-cal-admin@test.local'),
  ('99999999-9999-9999-9999-999999999912', 'qa-cal-wrong@test.local'),
  ('99999999-9999-9999-9999-999999999913', 'qa-cal-student@test.local');

insert into public.admin_user_roles (user_id, role_id)
select '99999999-9999-9999-9999-999999999911', ar.id
  from public.admin_roles ar
 where ar.role_code = 'content_admin';

insert into public.admin_user_roles (user_id, role_id)
select '99999999-9999-9999-9999-999999999912', ar.id
  from public.admin_roles ar
 where ar.role_code = 'copyright_reviewer';

-- QA-CAL-2099: w1 BUGUNU KAPSAYAN (baslamis), w20/w21 gelecek.
insert into public.academic_weeks (academic_year, week, starts_at, ends_at) values
  ('QA-CAL-2099', 1, current_date - 2, current_date + 5),
  ('QA-CAL-2099', 20, current_date + 50, current_date + 57),
  ('QA-CAL-2099', 21, current_date + 57, current_date + 64);

insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active)
values
  ('33333333-3333-3333-3333-000000000911', 'QCAL-01', 12,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true);

insert into public.student_question_attempts
  (id, user_id, question_id, subject_id, attempt_context, result,
   attempt_number, time_ms, academic_year, week, answered_at, metadata)
values
  ('44444444-4444-4444-4444-000000000911',
   '99999999-9999-9999-9999-999999999913',
   '33333333-3333-3333-3333-000000000911',
   '430903f3-527e-4e12-b7e8-ac0afdb784aa',
   'training', 'correct', 1, 5000,
   'QA-CAL-2099', 20, now(), '{}'::jsonb);


-- ============================================================
-- TESTLER
-- ============================================================

-- ---- ANON ---------------------------------------------------
set local role anon;
select set_config('request.jwt.claims', '', true);

select public._qa35_expect('T-01',
  'anon: list_years EXECUTE-denied',
  '42501',
  $sql$select * from public.academic_calendar_list_years()$sql$);

select public._qa35_expect('T-02',
  'anon: upsert EXECUTE-denied',
  '42501',
  $sql$select public.academic_calendar_upsert_week('QA-CAL-2099', 30, current_date + 100, current_date + 107)$sql$);

select public._qa35_expect('T-03',
  'anon: delete EXECUTE-denied',
  '42501',
  $sql$select public.academic_calendar_delete_week('QA-CAL-2099', 20)$sql$);

reset role;
select set_config('request.jwt.claims', '', true);


-- ---- OGRENCI (rolu/izni yok) ---------------------------------
select public._qa35_as('99999999-9999-9999-9999-999999999913');

select public._qa35_expect_msg('T-04',
  'ogrenci: list_weeks yetki reddi (in-func)',
  $sql$select * from public.academic_calendar_list_weeks('QA-CAL-2099')$sql$,
  '42501', '%calendar.manage yetkisi%');

select public._qa35_expect_msg('T-05',
  'ogrenci: upsert yetki reddi (in-func)',
  $sql$select public.academic_calendar_upsert_week('QA-CAL-2099', 31, current_date + 110, current_date + 117)$sql$,
  '42501', '%calendar.manage yetkisi%');

reset role;
select set_config('request.jwt.claims', '', true);


-- ---- YANLIS YETKILI ADMIN (copyright_reviewer) ---------------
select public._qa35_as('99999999-9999-9999-9999-999999999912');

select public._qa35_expect_msg('T-06',
  'yanlis yetkili admin: list_years red',
  $sql$select * from public.academic_calendar_list_years()$sql$,
  '42501', '%calendar.manage yetkisi%');

select public._qa35_expect_msg('T-07',
  'yanlis yetkili admin: upsert red',
  $sql$select public.academic_calendar_upsert_week('QA-CAL-2099', 32, current_date + 120, current_date + 127)$sql$,
  '42501', '%calendar.manage yetkisi%');

reset role;
select set_config('request.jwt.claims', '', true);


-- ---- calendar.manage ADMIN ----------------------------------
select public._qa35_as('99999999-9999-9999-9999-999999999911');

select public._qa35_true('T-08',
  'admin: yil ozeti + hafta listesi dogru',
  (select count(*) = 3
     from public.academic_calendar_list_weeks('QA-CAL-2099')
    where week in (1, 20, 21))
  and (select count(*) = 1
         from public.academic_calendar_list_years()
        where academic_year = 'QA-CAL-2099'
          and week_count = 3),
  'list_years week_count=3, list_weeks 1/20/21');

select public._qa35_expect('T-09a',
  'admin: gelecek hafta 22 upsert OK',
  '',
  $sql$select public.academic_calendar_upsert_week('QA-CAL-2099', 22, current_date + 64, current_date + 71)$sql$);

select public._qa35_true('T-09b',
  'admin: hafta 22 listede',
  (select count(*) = 1
     from public.academic_calendar_list_weeks('QA-CAL-2099')
    where week = 22
      and starts_at = current_date + 64),
  null);

-- AYNI YIL cakisma: w23 araligi w20/w21 ile kesisiyor.
select public._qa35_expect_msg('T-10',
  'ayni yil cakismasi RED',
  $sql$select public.academic_calendar_upsert_week('QA-CAL-2099', 23, current_date + 52, current_date + 60)$sql$,
  'P0001', '%Ayni akademik yilda mevcut bir haftayla cakisiyor%');

-- FARKLI YIL cakisma: QA-CAL-2100 takvimi A yilinin w20'siyle kesisiyor.
select public._qa35_expect_msg('T-11',
  'farkli yil cakismasi RED',
  $sql$select public.academic_calendar_upsert_week('QA-CAL-2100', 5, current_date + 51, current_date + 58)$sql$,
  'P0001', '%Farkli bir akademik yilin takvimiyle cakisiyor%');

-- Farkli yil + cakismayan tarih serbest.
select public._qa35_expect('T-11b',
  'farkli yil cakismayan tarih OK',
  '',
  $sql$select public.academic_calendar_upsert_week('QA-CAL-2100', 5, current_date + 200, current_date + 207)$sql$);

-- BASLAMIS hafta (w1, starts_at <= bugun) guncelleme RED.
select public._qa35_expect_msg('T-12',
  'baslamis hafta guncelleme RED',
  $sql$select public.academic_calendar_upsert_week('QA-CAL-2099', 1, current_date - 2, current_date + 6)$sql$,
  'P0001', '%Baslamis veya gecmis akademik hafta degistirilemez%');

-- BASLAMIS hafta silme RED.
select public._qa35_expect_msg('T-13',
  'baslamis hafta silme RED',
  $sql$select public.academic_calendar_delete_week('QA-CAL-2099', 1)$sql$,
  'P0001', '%Baslamis veya gecmis akademik hafta silinemez%');

-- ATTEMPT REFERANSLI gelecek hafta (w20) silme RED.
select public._qa35_expect_msg('T-14',
  'attempt referansli hafta silme RED',
  $sql$select public.academic_calendar_delete_week('QA-CAL-2099', 20)$sql$,
  'P0001', '%referans aliniyor%');

-- Gelecek + referanssiz hafta (w21) silme OK.
select public._qa35_expect('T-15a',
  'gelecek referanssiz hafta silme OK',
  '',
  $sql$select public.academic_calendar_delete_week('QA-CAL-2099', 21)$sql$);

-- Gecersiz girdi: hafta 99.
select public._qa35_expect_msg('T-16',
  'hafta numarasi 99 RED',
  $sql$select public.academic_calendar_upsert_week('QA-CAL-2099', 99, current_date + 300, current_date + 307)$sql$,
  'P0001', '%arasinda olmali%');

reset role;
select set_config('request.jwt.claims', '', true);

-- Silme dogrulamasi dogrudan tablodan okunur: postgres rolu gerekir
-- (academic_weeks istemciye kapali kalir).
select public._qa35_true('T-15b',
  'hafta 21 gercekten silindi',
  not exists (
    select 1
      from public.academic_weeks
     where academic_year = 'QA-CAL-2099'
       and week = 21
  ),
  null);

-- T-20: 074 global EXCLUDE constraint yerinde mi?
select public._qa35_true('T-20',
  '074: global exclude constraint mevcut',
  exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.academic_weeks'::regclass
       and c.conname = 'academic_weeks_no_cross_year_overlap'
       and c.contype = 'x'
  ),
  null);

-- T-19 (074 DB backstop): RPC on-kontrolunu BYPASS eden dogrudan
-- INSERT dahi farkli yilla cakisan aralikta engellenir (23P01).
-- Eski dunyada bu INSERT basarili olurdu (067 yalniz ayni yili
-- kisitlardi) -> yarish penceresi artik DB seviyesinde kapali.
select public._qa35_expect('T-19',
  '074: db backstop - farkli yil cakisan dogrudan INSERT 23P01',
  '23P01',
  $sql$insert into public.academic_weeks
    (academic_year, week, starts_at, ends_at)
   values ('QA-CAL-2100', 6, current_date + 50, current_date + 57)$sql$);


-- ---- TAKVIM -> TRAINING FAIL-CLOSED ZINCIRI ------------------

-- T-17: bugunu kapsayan w1 oldugu surece cozumleyici onu dondurur.
do $blk$
declare
  v_year text;
  v_w    integer;
begin
  select academic_year, week into v_year, v_w
    from public._faz2_require_period();

  perform public._qa35_true('T-17',
    'takvim -> donem cozumleyici zinciri OK',
    v_year = 'QA-CAL-2099' and v_w = 1,
    format('year=%s week=%s', v_year, v_w));
end;
$blk$;

-- Takvimi bosalt: Training RPC'lerinin dayandigi tek kaynak.
delete from public.academic_weeks where academic_year like 'QA-CAL-%';

select public._qa35_expect_msg('T-18a',
  'takvim bos: require_period FAIL-CLOSED',
  $sql$select * from public._faz2_require_period()$sql$,
  'P0001', '%Gecerli akademik donem bulunamadi%');

select public._qa35_true('T-18b',
  'takvim bos: resolver bos doner (fail-closed sozlesmesi)',
  not exists (select 1 from public.resolve_current_academic_period()),
  null);


-- ============================================================
-- TEMIZLIK (suite ici dogrulama; final ROLLBACK her seyi geri alir)
-- ============================================================

delete from public.student_question_attempts
 where id = '44444444-4444-4444-4444-000000000911';

delete from public.questions where question_code = 'QCAL-01';

delete from public.admin_user_roles ur
using auth.users u
where ur.user_id = u.id
  and u.email like 'qa-cal-%@test.local';

delete from auth.users where email like 'qa-cal-%@test.local';


-- Temizlik dogrulamasi (rollback oncesi durum).
select
  (select count(*) from auth.users
    where email like 'qa-cal-%@test.local')                    as users_kalan,
  (select count(*) from public.student_question_attempts
    where id = '44444444-4444-4444-4444-000000000911')          as attempts_kalan,
  (select count(*) from public.questions
    where question_code = 'QCAL-01')                            as questions_kalan,
  (select count(*) from public.academic_weeks
    where academic_year like 'QA-CAL-%')                        as weeks_kalan;


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
from public._qa_faz35_results
group by label
order by label;

with g as (
  select label, bool_and(result = 'PASS') as ok
  from public._qa_faz35_results
  group by label
)
select
  count(*)                        as toplam_test,
  count(*) filter (where ok)      as gecen,
  count(*) filter (where not ok)  as kalan
from g;


drop function public._qa35_as(uuid);
drop function public._qa35_true(text, text, boolean, text);
drop function public._qa35_expect_msg(text, text, text, text, text);
drop function public._qa35_expect(text, text, text, text);
drop table public._qa_faz35_results;

rollback;
