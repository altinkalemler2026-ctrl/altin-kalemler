-- ============================================================
-- 067_academic_weeks_calendar.sql
-- Altın Kalemler - Migration Faz 2 (067)
--
-- Akademik dönem/hafta takvimi (deterministik referans tablo).
--
-- Faz 2 kararları:
--   - Akademik dönem/hafta icin academic_weeks referans tablosu.
--   - Deterministik: tarih/saat dilimi tahmini YAPILMAZ; guncel donem,
--     UTC tarihini academic_weeks araliklarina dusurerek bulunur.
--   - Gecerli akademik hafta bulunamazsa cagiran RPC fail-closed olur
--     (resolve_current_academic_period bos doner; _faz2_require_period
--     istisna firlatir - bkz. 068).
--
-- Tablo operasyonel referans verisidir:
--   - RLS acik + hicbir client policy'si yok -> istemci erisemez.
--   - anon/authenticated: yetki yok.
--   - service_role: tam yetki (takvim yukleme operasyonu).
--   - resolve_current_academic_period SECURITY DEFINER'dir ve yalnizca
--     sunucu tarafi RPC'ler tarafindan kullanilir; EXECUTE'u
--     PUBLIC/anon/authenticated'dan alinir (RPC yuzeyi acilmaz).
-- ============================================================

begin;

-- Tarih araligi cakismasini veritabani seviyesinde garanti etmek icin.
create extension if not exists btree_gist;

create table if not exists public.academic_weeks (
  academic_year text not null,

  week integer not null
    check (week between 0 and 52),

  -- INCLUSIVE baslangic tarihi (UTC takvim gunu).
  starts_at date not null,

  -- EXCLUSIVE bitis tarihi (UTC takvim gunu): gun >= ends_at ise hafta bitti.
  ends_at date not null,

  primary key (academic_year, week),

  constraint academic_weeks_range_order
    check (ends_at > starts_at),

  -- Aynı eğitim yılında haftalar çakışamaz / boşluk kuralları dışında
  -- üst üste binemez. Farklı eğitim yıllarının takvimleri bağımsızdır.
  constraint academic_weeks_no_overlap
    exclude using gist (
      academic_year with =,
      daterange(starts_at, ends_at, '[)') with &&
    )
);

comment on table public.academic_weeks is
  'Deterministik akademik hafta takvimi. Guncel donem, UTC tarihini starts_at <= gun < ends_at araligina dusuren tekil haftadir.';

create index if not exists idx_academic_weeks_dates
  on public.academic_weeks (starts_at, ends_at);


-- ------------------------------------------------------------
-- RLS + PRIVILEGES
-- ------------------------------------------------------------

alter table public.academic_weeks enable row level security;

revoke all on table public.academic_weeks from anon, authenticated;

grant select, insert, update, delete
  on public.academic_weeks
  to service_role;


-- ------------------------------------------------------------
-- GUNCEL DONEM COZUMLEYICI
--
-- Fail-closed sozlesmesi: uygun hafta yoksa bos sonuc doner;
-- cagiran (068 _faz2_require_period) istisnayla akisi keser.
-- Saat dilimi: yalnizca UTC takvim gunu kullanilir.
-- ------------------------------------------------------------

create or replace function public.resolve_current_academic_period()
returns table (
  academic_year text,
  week integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select w.academic_year, w.week
    from public.academic_weeks w
   where (current_timestamp at time zone 'utc')::date >= w.starts_at
     and (current_timestamp at time zone 'utc')::date < w.ends_at
   order by w.starts_at
   limit 1;
$$;

revoke execute
on function public.resolve_current_academic_period()
from public, anon, authenticated;


commit;
