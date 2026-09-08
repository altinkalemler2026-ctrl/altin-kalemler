-- ============================================================
-- 103_faz9_gamification_core.sql
-- Altın Kalemler - Migration Faz 9 (103): XP, kişisel seviye,
-- günlük kota, seri ve rozet çekirdeği.
--
-- ÜRÜN KARARLARI (kullanıcı onaylı, 8 Eylül 2026):
--   1. Dört ekonomi ayrıdır: yarışma puanı (094 otoriter), lig
--      rating (+24/-12/0, 078/102 otoriter), XP ve yıldız (017).
--      XP, yarışma puanıyla, rating ile veya yıldızla birleştirilmez;
--      ayrı tablo/kolon/DTO alanlarıdır.
--   2. XP kaynakları (yalnız sunucu-otoriter):
--      - Antrenman + hedefli tekrar (attempt_context='training'),
--        YALNIZ 'correct' sonucu: easy=2, medium=3, hard=5 XP.
--        wrong/blank/pass/timeout = 0 XP (ledger kaydı YOK).
--      - Tamamlanmış yarışma: kazanan +15, beraberlik +10 (her iki
--        oyuncu), kaybeden +5. İptal/tamamlanmamış = 0 (results
--        satırı yoksa XP yok). Yarışmadaki soru puanları XP'ye
--        DÖNÜŞTÜRÜLMEZ.
--   3. Günlük XP üst sınırı YOKTUR; günlük soru kotası 500'dür
--      (antrenman + hedefli tekrar, tekrar + yeni dahil; yarışma
--      hariç). Gün sınırı Europe/Istanbul (sabit UTC+3, DST yok).
--      Mevcut haftalık 500 YENİ soru zinciri (063/068) AYNEN korunur.
--   4. Seviye formülü: gerekli toplam XP = 500 * (seviye-1)^2;
--      başlangıç seviyesi 1, V1 maksimum 50. Seviye istemciden
--      KABUL EDİLMEZ; toplam XP'den sunucuda hesaplanır.
--   5. Seri: günü oluşturan etkinlik = sunucu tarafından kabul
--      edilmiş training correct/wrong cevabı VEYA tamamlanmış
--      yarışma. Europe/Istanbul takvim günü. Aynı gün ek etkinlik
--      seriyi değiştirmez; dün ise +1; en az bir tam gün kaçtıysa
--      1'e döner. Grace period YOK. longest_streak geriye düşmez.
--      Gecikmiş olaylar daily activity kaydından deterministik
--      yeniden hesaplanır. İstemciden tarih kabul edilmez.
--   6. Rozetler: tek seferlik, UNIQUE(user_id, badge_code),
--      XP/yıldız vermez, yarışma puanını/rating'i değiştirmez,
--      yalnız sunucu idempotent grant yapar, koşullar otoriter DB
--      kayıtlarına dayanır. Katalog admin yönetimlidir
--      ('rewards.manage'), öğrenci yazamaz.
--   7. Idempotency: her soru denemesi en fazla bir XP olayı
--      (UNIQUE source), aynı yarışma sonucu öğrenci başına en fazla
--      bir XP olayı; duplicate submit/finalize ikinci üretmez.
--      XP ledger APPEND-ONLY (trigger ile UPDATE/DELETE engellenir).
--      Öğrenci XP/seviye/seri/rozet/kota'ya doğrudan yazamaz.
--
-- DESTEK DESENLERİ (mevcut zincirle uyumlu):
--   - Sayaç tablosu + CHECK backstop: 063 deseni.
--   - Kilit + tüketim fonksiyonları: 068 _faz2_lock/consume deseni.
--   - Tam revoke + selective grant: 059/070 deseni.
--   - Admin RLS: public.current_user_has_admin_permission (087).
-- ============================================================

begin;


-- ============================================================
-- 1. YARDIMCI: Europe/Istanbul TAKVİM GÜNÜ
--
-- Türkiye 2016'dan beri DST kullanmaz (sabit UTC+3); takvim günü
-- dönüşümü deterministiktir. Olay zamanı ÇAĞIRANdan alınır
-- (attempt answered_at / yarışma completion time); istemci tarih
-- gönderemez.
-- ============================================================

create or replace function public._faz9_local_day(
  p_event_time timestamptz default now()
)
returns date
language sql
immutable
strict
set search_path = ''
as $$
  select (p_event_time at time zone 'Europe/Istanbul')::date;
$$;

revoke execute
on function public._faz9_local_day(timestamptz)
from public, anon, authenticated;


-- ============================================================
-- 2. GÜNLÜK SORU KOTASI SAYACI (500/gün)
-- ============================================================

create table if not exists public.student_daily_question_counters (
  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  quota_day date not null,

  -- O gün teslim edilen toplam antrenman+hedefli tekrar sorusu
  -- (yeni + tekrar). CHECK son savunmadır.
  questions_used integer not null default 0
    check (
      questions_used >= 0
      and questions_used <= 500
    ),

  updated_at timestamptz not null default now(),

  primary key (user_id, quota_day)
);

comment on table public.student_daily_question_counters is
  'Gunluk 500 soru kotasi sayaci (antrenman + hedefli tekrar, yarisma haric). Gun siniri Europe/Istanbul. Sunucu-otoriter; istemci yazamaz.';

drop trigger if exists trigger_student_daily_question_counters_set_updated_at
  on public.student_daily_question_counters;

create trigger trigger_student_daily_question_counters_set_updated_at
before update on public.student_daily_question_counters
for each row
execute function public.set_updated_at();

alter table public.student_daily_question_counters
  enable row level security;

drop policy if exists student_reads_own_daily_question_counters
  on public.student_daily_question_counters;

create policy student_reads_own_daily_question_counters
on public.student_daily_question_counters
for select
to authenticated
using (user_id = auth.uid());

revoke all
  on table public.student_daily_question_counters
  from anon, authenticated;

grant select
  on public.student_daily_question_counters
  to authenticated;

grant select, insert, update, delete
  on public.student_daily_question_counters
  to service_role;


-- 2a. Kotayı KİLİTLE ve kalan hakkı döndür (068 lock deseni).
create or replace function public._faz9_lock_daily_counter(
  p_user uuid,
  p_day  date
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_used integer;
begin
  insert into public.student_daily_question_counters
    (user_id, quota_day)
  values
    (p_user, p_day)
  on conflict (user_id, quota_day) do nothing;

  select c.questions_used
    into v_used
    from public.student_daily_question_counters c
   where c.user_id = p_user
     and c.quota_day = p_day
   for update;

  return 500 - coalesce(v_used, 0);
end;
$$;

-- 2b. Teslim edilen soru kadar kota tüket (eşzamanlılık: çağıran
--     aynı işlemde satır kilidini tutar; toplam 500'ü aşamaz;
--     CHECK backstop).
create or replace function public._faz9_consume_daily_quota(
  p_user  uuid,
  p_day   date,
  p_count integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_count is null or p_count <= 0 then
    return;
  end if;

  update public.student_daily_question_counters c
     set questions_used = c.questions_used + p_count,
         updated_at     = now()
   where c.user_id = p_user
     and c.quota_day = p_day
     and c.questions_used + p_count <= 500;

  if not found then
    raise exception 'Gunluk 500 soru siniri asilamaz.'
      using errcode = 'P0001';
  end if;
end;
$$;

revoke execute
on function public._faz9_lock_daily_counter(uuid, date)
from public, anon, authenticated;

revoke execute
on function public._faz9_consume_daily_quota(uuid, date, integer)
from public, anon, authenticated;


-- ============================================================
-- 3. GÜNLÜK AKTİVİTE VE SERİ
-- ============================================================

create table if not exists public.student_daily_activity (
  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  activity_day date not null,

  -- O güne ilk etkinliği üreten otoriter olay zamanı.
  first_event_at timestamptz not null default now(),

  created_at timestamptz not null default now(),

  primary key (user_id, activity_day)
);

comment on table public.student_daily_activity is
  'Gunluk ogrenme etkinligi kaydi (kabul edilmis training correct/wrong cevabi veya tamamlanmis yarisma). Seri bu kayitlardan deterministik hesaplanir.';

alter table public.student_daily_activity
  enable row level security;

drop policy if exists student_reads_own_daily_activity
  on public.student_daily_activity;

create policy student_reads_own_daily_activity
on public.student_daily_activity
for select
to authenticated
using (user_id = auth.uid());

revoke all
  on table public.student_daily_activity
  from anon, authenticated;

grant select
  on public.student_daily_activity
  to authenticated;

grant select, insert, update, delete
  on public.student_daily_activity
  to service_role;


create table if not exists public.student_streaks (
  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  current_streak integer not null default 0
    check (current_streak >= 0),

  longest_streak integer not null default 0
    check (longest_streak >= 0),

  last_activity_day date,

  updated_at timestamptz not null default now(),

  primary key (user_id)
);

comment on table public.student_streaks is
  'Ogrenci gunluk serisi. current_streak Europe/Istanbul gunune gore; longest_streak geriye dusmez. Yazim yalniz sunucu-ici fonksiyondan.';

drop trigger if exists trigger_student_streaks_set_updated_at
  on public.student_streaks;

create trigger trigger_student_streaks_set_updated_at
before update on public.student_streaks
for each row
execute function public.set_updated_at();

alter table public.student_streaks
  enable row level security;

drop policy if exists student_reads_own_streak
  on public.student_streaks;

create policy student_reads_own_streak
on public.student_streaks
for select
to authenticated
using (user_id = auth.uid());

revoke all
  on table public.student_streaks
  from anon, authenticated;

grant select
  on public.student_streaks
  to authenticated;

grant select, insert, update, delete
  on public.student_streaks
  to service_role;


-- 3a. Seri güncelleme: idempotent, gecikmiş olayda deterministik
--     yeniden hesap, longest korumalı.
create or replace function public._faz9_record_daily_activity(
  p_user       uuid,
  p_event_time timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day       date;
  v_current   integer;
  v_longest   integer;
  v_last      date;
  v_new       integer;
begin
  v_day := public._faz9_local_day(p_event_time);

  -- Seri güncellemeleri öğrenci başına serileşir (eşzamanlı
  -- attempt/finalize yarışına karşı).
  perform pg_advisory_xact_lock(
    hashtextextended(p_user::text || ':faz9_streak', 0)
  );

  -- Aynı gün ikinci etkinlik seriyi DEĞİŞTİRMEZ (idempotency).
  insert into public.student_daily_activity
    (user_id, activity_day, first_event_at)
  values
    (p_user, v_day, p_event_time)
  on conflict (user_id, activity_day) do nothing;

  if not found then
    return;
  end if;

  select s.current_streak, s.longest_streak, s.last_activity_day
    into v_current, v_longest, v_last
    from public.student_streaks s
   where s.user_id = p_user
   for update;

  if not found then
    v_current := 0;
    v_longest := 0;
    v_last    := null;
  end if;

  if v_last is null then
    v_new := 1;
  elsif v_day = v_last then
    -- Aynı gün (teoriik; yukarıdaki conflict no-op zaten döner).
    v_new := v_current;
  elsif v_day = v_last + 1 then
    v_new := v_current + 1;
  elsif v_day > v_last + 1 then
    -- En az bir tam gün kaçtı: sıfırla.
    v_new := 1;
  else
    -- GECİKMİŞ olay (p_day < v_last): daily activity kayıtlarından
    -- deterministik yeniden hesap. Bugün (yerel) veya öncesi BÜTÜN
    -- günler üzerinden, bugüne bitişik koşu hesaplanır; gecikmiş
    -- olay mevcut seriyi BÜYÜTEBİLİR ama kısaltamaz.
    select coalesce(r.run_len, 0)
      into v_new
      from (
        select isl, count(*) as run_len, max(d.activity_day) as run_end
          from (
            select d.activity_day,
                   d.activity_day
                     - (row_number() over (order by d.activity_day))::int as isl
              from public.student_daily_activity d
             where d.user_id = p_user
               and d.activity_day <= public._faz9_local_day(now())
          ) d
         group by isl
         order by run_end desc
         limit 1
      ) r;

    v_new := greatest(v_new, 1);
  end if;

  insert into public.student_streaks
    (user_id, current_streak, longest_streak, last_activity_day)
  values
    (p_user, v_new, greatest(v_longest, v_new),
     case when v_last is null then v_day else greatest(v_last, v_day) end)
  on conflict (user_id) do update
    set current_streak    = excluded.current_streak,
        longest_streak    = greatest(public.student_streaks.longest_streak,
                                     excluded.longest_streak),
        last_activity_day = excluded.last_activity_day,
        updated_at        = now();
end;
$$;

revoke execute
on function public._faz9_record_daily_activity(uuid, timestamptz)
from public, anon, authenticated;


-- ============================================================
-- 4. XP LEDGER (append-only) VE TOPLAM XP
-- ============================================================

create table if not exists public.student_xp_ledger (
  id bigint generated always as identity primary key,

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  source_type text not null
    check (source_type in ('training_attempt', 'competition_result')),

  source_id uuid not null,

  xp_amount smallint not null
    check (xp_amount > 0 and xp_amount <= 15),

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  -- Idempotency: bir deneme/yarışma sonucu öğrenci başına en fazla
  -- bir XP olayı üretir.
  constraint student_xp_ledger_unique_event
    unique (source_type, source_id, user_id)
);

comment on table public.student_xp_ledger is
  'Append-only XP olay kaydi. Kaynaklar: training_attempt (easy=2/medium=3/hard=5, yalniz correct) ve competition_result (kazanan 15/beraberlik 10/kaybeden 5). Ogrenci yazamaz; UPDATE/DELETE trigger ile engellenir.';

create index if not exists idx_student_xp_ledger_user_time
  on public.student_xp_ledger(user_id, created_at desc);


-- Append-only savunma: UPDATE/DELETE her rol için engellenir
-- (service_role dahil); ledger yalnız INSERT ile büyür.
create or replace function public.guard_student_xp_ledger_append_only()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'XP ledger append-only dir; guncelleme ve silme yasaktir.'
    using errcode = 'P0001';
end;
$$;

drop trigger if exists trg_student_xp_ledger_append_only
  on public.student_xp_ledger;

create trigger trg_student_xp_ledger_append_only
before update or delete on public.student_xp_ledger
for each row
execute function public.guard_student_xp_ledger_append_only();

revoke execute
on function public.guard_student_xp_ledger_append_only()
from public, anon, authenticated;


alter table public.student_xp_ledger
  enable row level security;

drop policy if exists student_reads_own_xp_ledger
  on public.student_xp_ledger;

create policy student_reads_own_xp_ledger
on public.student_xp_ledger
for select
to authenticated
using (user_id = auth.uid());

revoke all
  on table public.student_xp_ledger
  from anon, authenticated;

grant select
  on public.student_xp_ledger
  to authenticated;

grant select, insert
  on public.student_xp_ledger
  to service_role;

grant usage
  on sequence public.student_xp_ledger_id_seq
  to service_role;


create table if not exists public.student_xp_totals (
  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  -- İşlemsel önbellek; otoriter değer ledger toplamıdır.
  total_xp integer not null default 0
    check (total_xp >= 0),

  updated_at timestamptz not null default now(),

  primary key (user_id)
);

comment on table public.student_xp_totals is
  'Toplam XP onbellegi. Otoriter kaynak student_xp_ledger toplamidir; seviye bu toplamdan sunucuda hesaplanir (istemciden kabul edilmez).';

drop trigger if exists trigger_student_xp_totals_set_updated_at
  on public.student_xp_totals;

create trigger trigger_student_xp_totals_set_updated_at
before update on public.student_xp_totals
for each row
execute function public.set_updated_at();

alter table public.student_xp_totals
  enable row level security;

drop policy if exists student_reads_own_xp_totals
  on public.student_xp_totals;

create policy student_reads_own_xp_totals
on public.student_xp_totals
for select
to authenticated
using (user_id = auth.uid());

revoke all
  on table public.student_xp_totals
  from anon, authenticated;

grant select
  on public.student_xp_totals
  to authenticated;

grant select, insert, update
  on public.student_xp_totals
  to service_role;


-- 4a. Training XP grant (yalnız correct; difficulty sorudan).
create or replace function public._faz9_grant_training_xp(
  p_user       uuid,
  p_attempt_id uuid,
  p_difficulty text,
  p_event_time timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_xp smallint;
begin
  v_xp := case p_difficulty
            when 'easy'   then 2
            when 'medium' then 3
            when 'hard'   then 5
            else 0
          end;

  if v_xp <= 0 then
    return;
  end if;

  insert into public.student_xp_ledger
    (user_id, source_type, source_id, xp_amount, metadata)
  values
    (p_user, 'training_attempt', p_attempt_id, v_xp,
     jsonb_build_object(
       'difficulty', p_difficulty,
       'attempt_context', 'training',
       'event_time', p_event_time
     ))
  on conflict (source_type, source_id, user_id) do nothing;

  if found then
    insert into public.student_xp_totals
      (user_id, total_xp)
    values
      (p_user, v_xp)
    on conflict (user_id) do update
      set total_xp  = public.student_xp_totals.total_xp + excluded.total_xp,
          updated_at = now();
  end if;
end;
$$;


-- 4b. Yarışma XP grant (kazanan 15 / beraberlik 10 / kaybeden 5).
create or replace function public._faz9_grant_competition_xp(
  p_user           uuid,
  p_competition_id uuid,
  p_amount         smallint,
  p_result_type    text,
  p_event_time     timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_amount is null or p_amount <= 0 then
    return;
  end if;

  insert into public.student_xp_ledger
    (user_id, source_type, source_id, xp_amount, metadata)
  values
    (p_user, 'competition_result', p_competition_id, p_amount,
     jsonb_build_object(
       'result_type', p_result_type,
       'event_time', p_event_time
     ))
  on conflict (source_type, source_id, user_id) do nothing;

  if found then
    insert into public.student_xp_totals
      (user_id, total_xp)
    values
      (p_user, p_amount)
    on conflict (user_id) do update
      set total_xp  = public.student_xp_totals.total_xp + excluded.total_xp,
          updated_at = now();
  end if;
end;
$$;

revoke execute
on function public._faz9_grant_training_xp(uuid, uuid, text, timestamptz)
from public, anon, authenticated;

revoke execute
on function public._faz9_grant_competition_xp(uuid, uuid, smallint, text, timestamptz)
from public, anon, authenticated;


-- ============================================================
-- 5. SEVİYE FORMÜLÜ: gerekli toplam XP = 500 * (seviye-1)^2
-- ============================================================

create or replace function public.faz9_required_total_xp(
  p_level integer
)
returns bigint
language sql
immutable
strict
set search_path = ''
as $$
  select 500::bigint * (p_level::bigint - 1) * (p_level::bigint - 1);
$$;

create or replace function public.faz9_level_from_total_xp(
  p_total_xp bigint
)
returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select least(50, floor(sqrt(p_total_xp::numeric / 500))::integer + 1);
$$;

revoke execute
on function public.faz9_required_total_xp(integer)
from public, anon, authenticated;

revoke execute
on function public.faz9_level_from_total_xp(bigint)
from public, anon, authenticated;


-- ============================================================
-- 6. ROZET KATALOĞU VE GRANT
-- ============================================================

create table if not exists public.badge_definitions (
  badge_code text primary key,

  name text not null,

  description text not null default '',

  is_active boolean not null default true,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);

comment on table public.badge_definitions is
  'Rozet katalogu. Admin (rewards.manage) yonetir; ogrenci yalniz okur. V1 rozetleri XP veya yildiz vermez.';

drop trigger if exists trigger_badge_definitions_set_updated_at
  on public.badge_definitions;

create trigger trigger_badge_definitions_set_updated_at
before update on public.badge_definitions
for each row
execute function public.set_updated_at();

alter table public.badge_definitions
  enable row level security;

drop policy if exists badge_definitions_all_read
  on public.badge_definitions;

create policy badge_definitions_all_read
on public.badge_definitions
for select
to authenticated
using (true);

drop policy if exists badge_definitions_admin_write
  on public.badge_definitions;

create policy badge_definitions_admin_write
on public.badge_definitions
for all
to authenticated
using (
  public.current_user_has_admin_permission('rewards.manage')
)
with check (
  public.current_user_has_admin_permission('rewards.manage')
);

revoke all
  on table public.badge_definitions
  from anon, authenticated;

grant select, insert, update, delete
  on public.badge_definitions
  to authenticated;

grant select, insert, update, delete
  on public.badge_definitions
  to service_role;


-- 6a. V1 rozet kataloğu (idempotent seed).
insert into public.badge_definitions
  (badge_code, name, description)
values
  ('first_step', 'İlk Adım',
   'İlk geçerli öğrenme etkinliğini tamamladın.'),
  ('first_correct', 'İlk Doğru',
   'İlk doğru cevabını verdin.'),
  ('streak_3', 'Üç Gün Üst Üste',
   'Çalışma serini 3 güne ulaştırdın.'),
  ('streak_7', 'Bir Haftalık Seri',
   'Çalışma serini 7 güne ulaştırdın.'),
  ('correct_50', '50 Doğru',
   'Toplam 50 doğru cevaba ulaştın.'),
  ('first_competition', 'İlk Yarışmam',
   'İlk yarışmanı tamamladın.'),
  ('wins_10', '10 Zafer',
   '10 yarışma kazandın.')
on conflict (badge_code) do update
  set name        = excluded.name,
      description = excluded.description,
      updated_at  = now();


-- 6b. 'rewards.manage' admin yetkisi + super_admin bağlantısı
--     (013/092 kataloğu deseni; idempotent).
insert into public.admin_permissions
  (permission_code, name, description)
values
  ('rewards.manage',
   'Ödülleri Yönet',
   'Rozet kataloğunu yönetebilir.')
on conflict (permission_code) do update
  set name        = excluded.name,
      description = excluded.description;

insert into public.admin_role_permissions
  (role_id, permission_id)
select ar.id, ap.id
  from public.admin_roles ar
 cross join public.admin_permissions ap
 where ar.role_code = 'super_admin'
   and ap.permission_code = 'rewards.manage'
on conflict do nothing;


create table if not exists public.student_badges (
  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  badge_code text not null
    references public.badge_definitions(badge_code)
    on delete restrict,

  granted_at timestamptz not null default now(),

  -- Grant'i üreten otoriter olay referansı (audit).
  source_ref jsonb not null default '{}'::jsonb,

  primary key (user_id, badge_code)
);

comment on table public.student_badges is
  'Tek seferlik rozet grant kaydi. Yalniz sunucu-ici idempotent fonksiyon yazar; ogrenci kendisine rozet veremez.';

create index if not exists idx_student_badges_user
  on public.student_badges(user_id, granted_at desc);

alter table public.student_badges
  enable row level security;

drop policy if exists student_reads_own_badges
  on public.student_badges;

create policy student_reads_own_badges
on public.student_badges
for select
to authenticated
using (user_id = auth.uid());

revoke all
  on table public.student_badges
  from anon, authenticated;

grant select
  on public.student_badges
  to authenticated;

grant select, insert, update, delete
  on public.student_badges
  to service_role;


-- 6c. Idempotent rozet değerlendirme: koşullar YALNIZ otoriter
--     DB kayıtlarından; her rozet yalnız bir kez.
create or replace function public._faz9_evaluate_badges(
  p_user uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- first_step: ilk geçerli öğrenme etkinliği (daily activity).
  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, 'first_step',
         jsonb_build_object('basis', 'daily_activity')
    where exists (
      select 1
        from public.student_daily_activity a
       where a.user_id = p_user
    )
  on conflict (user_id, badge_code) do nothing;

  -- first_correct + correct_50: otoriter attempt fact tablosu.
  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, 'first_correct',
         jsonb_build_object('basis', 'attempts')
    where exists (
      select 1
        from public.student_question_attempts t
       where t.user_id = p_user
         and t.result = 'correct'
    )
  on conflict (user_id, badge_code) do nothing;

  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, 'correct_50',
         jsonb_build_object('basis', 'attempts',
                            'correct_count', v_count)
    from (
      select count(*) as v_count
        from public.student_question_attempts t
       where t.user_id = p_user
         and t.result = 'correct'
    ) c
   where c.v_count >= 50
  on conflict (user_id, badge_code) do nothing;

  -- streak_3 / streak_7: sunucudaki seri kaydı.
  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, b.code, jsonb_build_object('basis', 'streak',
                                            'current_streak', s.current_streak)
    from public.student_streaks s
   cross join (values ('streak_3', 3), ('streak_7', 7)) b(code, threshold)
   where s.user_id = p_user
     and s.current_streak >= b.threshold
  on conflict (user_id, badge_code) do nothing;

  -- first_competition: tamamlanmış yarışma katılımı.
  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, 'first_competition',
         jsonb_build_object('basis', 'competitions')
    where exists (
      select 1
        from public.competition_players cp
        join public.competitions c on c.id = cp.competition_id
       where cp.user_id = p_user
         and c.status = 'completed'
    )
  on conflict (user_id, badge_code) do nothing;

  -- wins_10: kesinleşmiş galibiyet (tamamlanmış yarışma sonucu).
  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, 'wins_10',
         jsonb_build_object('basis', 'competition_results',
                            'win_count', v_wins)
    from (
      select count(*) as v_wins
        from public.competition_results cr
       where cr.winner_user_id = p_user
         and exists (
           select 1
             from public.competitions c
            where c.id = cr.competition_id
              and c.status = 'completed'
         )
    ) w
   where w.v_wins >= 10
  on conflict (user_id, badge_code) do nothing;
end;
$$;

revoke execute
on function public._faz9_evaluate_badges(uuid)
from public, anon, authenticated;


-- ============================================================
-- 7. ÖĞRENCİ OKUMA RPC: YALNIZ GERÇEK DEĞERLER
--
-- DTO alanları AYRIDIR: xp, streak, daily_quota, badges ayrı
-- anahtarlar; yarışma puanı, lig rating ve yıldız burada YOKTUR
-- (kendi tablolarından/DTO'larından okunur).
-- ============================================================

create or replace function public.get_own_gamification_profile()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user     uuid;
  v_total    bigint;
  v_level    integer;
  v_next_req bigint;
  v_day      date;
  v_used     integer;
  r_streak   public.student_streaks%rowtype;
  v_badges   jsonb;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  select coalesce(t.total_xp, 0)
    into v_total
    from public.student_xp_totals t
   where t.user_id = v_user;

  v_level := public.faz9_level_from_total_xp(coalesce(v_total, 0));

  if v_level < 50 then
    v_next_req := public.faz9_required_total_xp(v_level + 1);
  else
    v_next_req := null;
  end if;

  select * into r_streak
    from public.student_streaks s
   where s.user_id = v_user;

  v_day := public._faz9_local_day(now());

  select c.questions_used
    into v_used
    from public.student_daily_question_counters c
   where c.user_id = v_user
     and c.quota_day = v_day;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'badge_code', b.badge_code,
        'name', d.name,
        'granted_at', b.granted_at
      )
      order by b.granted_at, b.badge_code
    ),
    '[]'::jsonb
  )
    into v_badges
    from public.student_badges b
    join public.badge_definitions d
      on d.badge_code = b.badge_code
   where b.user_id = v_user
     and d.is_active;

  return jsonb_build_object(
    'xp', jsonb_build_object(
      'total', coalesce(v_total, 0),
      'level', v_level,
      'max_level', 50,
      'next_level_required_total_xp', v_next_req,
      'xp_to_next_level',
        case when v_next_req is null
             then null
             else v_next_req - coalesce(v_total, 0)
        end
    ),
    'streak', jsonb_build_object(
      'current', coalesce(r_streak.current_streak, 0),
      'longest', coalesce(r_streak.longest_streak, 0),
      'last_activity_day', r_streak.last_activity_day
    ),
    'daily_quota', jsonb_build_object(
      'day', v_day,
      'questions_used', coalesce(v_used, 0),
      'limit', 500,
      'remaining', 500 - coalesce(v_used, 0)
    ),
    'badges', v_badges
  );
end;
$$;

revoke execute
on function public.get_own_gamification_profile()
from public, anon, authenticated;

grant execute
on function public.get_own_gamification_profile()
to authenticated;


commit;
