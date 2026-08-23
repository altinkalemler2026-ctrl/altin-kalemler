-- ============================================================
-- 073_academic_weeks_admin_management.sql
-- Altın Kalemler - Faz 3.5: Akademik takvim yönetimi (ADDITIVE)
--
-- Kurallar:
--   - academic_weeks tablosunun RLS/ACL modeli DEĞİŞMEZ:
--     RLS açık + policy yok; anon/authenticated privilege YOK;
--     istemci tabloya doğrudan asla erişemez.
--   - Yönetim yalnızca SECURITY DEFINER RPC'ler üzerinden.
--   - HER RPC (okuma dahil) fonksiyon içinde calendar.manage
--     kontrolü yapar; yetkisiz çağrı exception ile reddedilir.
--   - search_path = '' ; tüm adlar tam nitelikli.
--   - EXECUTE public/anon'dan alınır; yalnız authenticated'a verilir.
--   - Farklı akademik yıllar ARASINDA tarih çakışması da reddedilir
--     (aynı yıl çakışması zaten 067 GiST EXCLUDE ile engelli).
--   - starts_at <= current_date olan (başlamış/geçmiş) hafta
--     değiştirilemez ve silinemez.
--   - student_question_attempts referansı olan hafta silinemez;
--     yalnız gelecekteki ve referanssız hafta silinebilir.
--   - Hata mesajları ASCII Türkçe (istemci desen eşleşmesi için).
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. YENİ YETKİ KODU + ROL BAĞLAMA (idempotent)
--    super_admin: tüm yetkiler; content_admin: içerik/takvim sahibi.
-- ------------------------------------------------------------

insert into public.admin_permissions (
  permission_code,
  name,
  description
)
values (
  'calendar.manage',
  'Akademik Takvimi Yönet',
  'Akademik yıl/hafta takvimini görüntüler, ekler, günceller ve siler.'
)
on conflict (permission_code) do update
set
  name = excluded.name,
  description = excluded.description;

insert into public.admin_role_permissions (
  role_id,
  permission_id
)
select
  ar.id,
  ap.id
from public.admin_roles ar
cross join public.admin_permissions ap
where ar.role_code in ('super_admin', 'content_admin')
  and ar.is_active = true
  and ap.permission_code = 'calendar.manage'
on conflict do nothing;


-- ------------------------------------------------------------
-- 2. YETKİ HELPER'I (047 deseni; search_path='')
-- ------------------------------------------------------------

create or replace function public.academic_calendar_has_permission(
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.admin_user_roles aur
      join public.admin_roles ar
        on ar.id = aur.role_id
       and ar.is_active = true
      join public.admin_role_permissions arp
        on arp.role_id = ar.id
      join public.admin_permissions ap
        on ap.id = arp.permission_id
     where aur.user_id = auth.uid()
       and ap.permission_code = p_permission_code
  );
$$;


-- ------------------------------------------------------------
-- 3. OKUMA RPC'LERİ (yetki zorunlu)
-- ------------------------------------------------------------

create or replace function public.academic_calendar_list_years()
returns table (
  academic_year text,
  week_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.academic_calendar_has_permission('calendar.manage') then
    raise exception 'Akademik takvimi goruntulemek icin calendar.manage yetkisi gerekli.'
      using errcode = '42501';
  end if;

  return query
    select w.academic_year,
           count(*)::bigint as week_count
      from public.academic_weeks w
     group by w.academic_year
     order by w.academic_year desc;
end;
$$;


create or replace function public.academic_calendar_list_weeks(
  p_year text
)
returns table (
  academic_year text,
  week integer,
  starts_at date,
  ends_at date,
  is_started boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_year text;
begin
  if not public.academic_calendar_has_permission('calendar.manage') then
    raise exception 'Akademik takvimi goruntulemek icin calendar.manage yetkisi gerekli.'
      using errcode = '42501';
  end if;

  v_year := btrim(coalesce(p_year, ''));
  if v_year = '' then
    raise exception 'Akademik yil bilgisi bos olamaz.'
      using errcode = 'P0001';
  end if;

  return query
    select w.academic_year,
           w.week,
           w.starts_at,
           w.ends_at,
           (w.starts_at <= current_date) as is_started
      from public.academic_weeks w
     where w.academic_year = v_year
     order by w.starts_at, w.week;
end;
$$;


-- ------------------------------------------------------------
-- 4. MUTASYON RPC'LERİ
--
-- upsert:
--   - mevcut hafta başlamışsa (starts_at <= current_date) her
--     güncelleme reddedilir (067 satırı korunur).
--   - aynı yıl içinde başka haftaya çakışma RED (GiST son savunma).
--   - FARKLI yıl takvimiyle çakışma da RED (Faz 3.5 kuralı).
-- delete:
--   - bulunamayan / başlamış / attempt referanslı hafta red;
--     yalnız gelecek + referanssız hafta silinir.
-- ------------------------------------------------------------

create or replace function public.academic_calendar_upsert_week(
  p_year text,
  p_week integer,
  p_starts_at date,
  p_ends_at date
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_year     text;
  v_existing public.academic_weeks%rowtype;
begin
  if not public.academic_calendar_has_permission('calendar.manage') then
    raise exception 'Akademik takvimi duzenlemek icin calendar.manage yetkisi gerekli.'
      using errcode = '42501';
  end if;

  v_year := btrim(coalesce(p_year, ''));
  if v_year = '' or length(v_year) > 100 then
    raise exception 'Akademik yil bilgisi gecersiz.'
      using errcode = 'P0001';
  end if;

  if p_week is null or p_week < 0 or p_week > 52 then
    raise exception 'Hafta numarasi 0 ile 52 arasinda olmali.'
      using errcode = 'P0001';
  end if;

  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception 'Bitis tarihi baslangic tarihinden sonra olmali.'
      using errcode = 'P0001';
  end if;

  select * into v_existing
    from public.academic_weeks w
   where w.academic_year = v_year
     and w.week = p_week;

  if found and v_existing.starts_at <= current_date then
    raise exception 'Baslamis veya gecmis akademik hafta degistirilemez.'
      using errcode = 'P0001';
  end if;

  -- Aynı yıl: kendi dışındaki haftalarla çakışma (GiST'in ön mesajı).
  if exists (
    select 1
      from public.academic_weeks w
     where w.academic_year = v_year
       and w.week <> p_week
       and daterange(w.starts_at, w.ends_at, '[)')
           && daterange(p_starts_at, p_ends_at, '[)')
  ) then
    raise exception 'Ayni akademik yilda mevcut bir haftayla cakisiyor.'
      using errcode = 'P0001';
  end if;

  -- Farklı yıl: Faz 3.5 kuralı gereği kesin red.
  if exists (
    select 1
      from public.academic_weeks w
     where w.academic_year <> v_year
       and daterange(w.starts_at, w.ends_at, '[)')
           && daterange(p_starts_at, p_ends_at, '[)')
  ) then
    raise exception 'Farkli bir akademik yilin takvimiyle cakisiyor.'
      using errcode = 'P0001';
  end if;

  insert into public.academic_weeks
    (academic_year, week, starts_at, ends_at)
  values
    (v_year, p_week, p_starts_at, p_ends_at)
  on conflict (academic_year, week) do update
    set starts_at = excluded.starts_at,
        ends_at   = excluded.ends_at;
end;
$$;


create or replace function public.academic_calendar_delete_week(
  p_year text,
  p_week integer
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_year     text;
  v_existing public.academic_weeks%rowtype;
begin
  if not public.academic_calendar_has_permission('calendar.manage') then
    raise exception 'Akademik takvimi duzenlemek icin calendar.manage yetkisi gerekli.'
      using errcode = '42501';
  end if;

  v_year := btrim(coalesce(p_year, ''));
  if v_year = '' then
    raise exception 'Akademik yil bilgisi gecersiz.'
      using errcode = 'P0001';
  end if;

  select * into v_existing
    from public.academic_weeks w
   where w.academic_year = v_year
     and w.week = p_week;

  if not found then
    raise exception 'Silinecek akademik hafta bulunamadi.'
      using errcode = 'P0001';
  end if;

  if v_existing.starts_at <= current_date then
    raise exception 'Baslamis veya gecmis akademik hafta silinemez.'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
      from public.student_question_attempts a
     where a.academic_year = v_year
       and a.week = p_week
  ) then
    raise exception 'Bu hafta ogrenci deneme kayitlari tarafindan referans aliniyor; silinemez.'
      using errcode = 'P0001';
  end if;

  delete from public.academic_weeks w
   where w.academic_year = v_year
     and w.week = p_week;
end;
$$;


-- ------------------------------------------------------------
-- 5. EXECUTE MATRİSİ: PUBLIC/anon revoked → yalnız authenticated
-- ------------------------------------------------------------

revoke execute
on function public.academic_calendar_has_permission(text)
from public, anon, authenticated;
grant execute
on function public.academic_calendar_has_permission(text)
to authenticated;

revoke execute
on function public.academic_calendar_list_years()
from public, anon, authenticated;
grant execute
on function public.academic_calendar_list_years()
to authenticated;

revoke execute
on function public.academic_calendar_list_weeks(text)
from public, anon, authenticated;
grant execute
on function public.academic_calendar_list_weeks(text)
to authenticated;

revoke execute
on function public.academic_calendar_upsert_week(text, integer, date, date)
from public, anon, authenticated;
grant execute
on function public.academic_calendar_upsert_week(text, integer, date, date)
to authenticated;

revoke execute
on function public.academic_calendar_delete_week(text, integer)
from public, anon, authenticated;
grant execute
on function public.academic_calendar_delete_week(text, integer)
to authenticated;


commit;
