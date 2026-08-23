-- ============================================================
-- 074_academic_weeks_cross_year_db_backstop.sql
-- Altin Kalemler - Faz 3.5 R-1 duzeltmesi:
-- yillar arasi tarih cakismasi icin DB seviyesinde backstop.
--
-- Kok sorun:
--   067 EXCLUDE constraint'i "academic_year with =" icerdigi icin
--   yalniz AYNI yil icindeki cakismayi engeller. Farkli yillar
--   arasi kural 073 upsert RPC'sindeki on-kontrolle uygulanir;
--   iki ESZAMANLI admin cagrisi bu kontrolu birlikte gecebilir.
--
-- Cozum (ADDITIVE):
--   1. Yil ayirt etmeyen GLOBAL GiST EXCLUDE constraint:
--      daterange(starts_at, ends_at, '[)') && -> 23P01.
--      - 067 ayni-yil kurali SOKULMEZ; bu constraint onu kapsayan
--        daha sikir savunmadir (ayni yil da dahil hepsi engellenir).
--      - Tablo/RSL/ACL modeli degismez; istemci yazma yetkisi hala yok.
--      - Eszamanlilik: exclusion index, ikinci yazani bekletir; ilk
--        islem commit olursa ikincisi 23P01 alir (unique gibi).
--      - btree_gist gerekmez (skalar kolon icermez; 067'de zaten var).
--   2. upsert RPC guncellenir: INSERT adimi exclusion_violation
--      yakalayip ASCII Turkce P0001'e cevirir; yarish penceresinde
--      bile istemci ham Ingilizce mesaj yerine kurli mesaj gorur.
--
-- Hata sozlesmesi (ASCII): yeni mesaj
--   'Tarih araligi mevcut bir akademik haftayla cakisiyor; eszamanli guncelleme algilandi.' (P0001)
-- Istemci deseni: /eszamanli guncelleme algilandi/i ve
--   /exclusion constraint/i -> concurrentOverlap mesaji.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. GLOBAL (yillardan bagimsiz) cakisma backstop'u
-- ------------------------------------------------------------

alter table public.academic_weeks
  add constraint academic_weeks_no_cross_year_overlap
  exclude using gist (
    daterange(starts_at, ends_at, '[)') with &&
  );

comment on constraint academic_weeks_no_cross_year_overlap
  on public.academic_weeks is
  'Faz 3.5 R-1: farkli akademik yillarin takvimleri de ust uste binemez; 067 ayni-yil kuralinin global kapsam savunmasi.';

-- ------------------------------------------------------------
-- 2. upsert RPC: eszamanlilik yarishi icin 23P01 yakalama
--    (gövde dışındaki her şey 073 ile aynıdır)
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

  -- Farklı yıl: hızlı yol ön-kontrolü (073 kuralı). Yarış penceresi
  -- kalırsa aşağıdaki exception bloğu 074 global EXCLUDE'a düşer.
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

  begin
    insert into public.academic_weeks
      (academic_year, week, starts_at, ends_at)
    values
      (v_year, p_week, p_starts_at, p_ends_at)
    on conflict (academic_year, week) do update
      set starts_at = excluded.starts_at,
          ends_at   = excluded.ends_at;
  exception
    when exclusion_violation then
      -- 074 backstop'u: eşzamanlı yazışma penceresinde buraya düşer.
      raise exception 'Tarih araligi mevcut bir akademik haftayla cakisiyor; eszamanli guncelleme algilandi.'
        using errcode = 'P0001';
  end;
end;
$$;

-- CREATE OR REPLACE yetkileri silmez; matris bilinçli olarak
-- yeniden teyit edilir (drift guard).
revoke execute
on function public.academic_calendar_upsert_week(text, integer, date, date)
from public, anon, authenticated;
grant execute
on function public.academic_calendar_upsert_week(text, integer, date, date)
to authenticated;


commit;
