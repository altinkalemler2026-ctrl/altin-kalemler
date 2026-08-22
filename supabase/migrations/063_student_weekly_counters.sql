-- ============================================================
-- 059_05_student_weekly_counters.sql
-- Altın Kalemler - Migration 059 Faz 1
--
-- Haftalık hızlı yeni soru sayacı.
--
-- 059 kuralları:
--   - Öğrenci başına ders/hafta yeni soru üst sınırı 500.
--   - Haftalık 500 sınırı için her istekte COUNT(*) yapılmamalı.
--   - Öğrenci + eğitim yılı + hafta + ders bazında hızlı sayaç/özet tutulmalı.
--   - Öğrenci 500. yeni soruya ulaştığında o ders için o haftaki yeni soru
--     akışı durmalıdır.
--
-- Sayaç YALNIZ YENİ (daha önce hiç görülmemiş) sorularda artar; artım
-- mantığı Phase 2'deki tek noktadan atomik fonksiyonda uygulanır.
-- CHECK <= 500 veritabanı düzeyinde son savunmadır.
-- ============================================================

begin;


-- ============================================================
-- 1. STUDENT_WEEKLY_COUNTERS
-- ============================================================

create table if not exists public.student_weekly_counters (
  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  academic_year text not null,

  week integer not null
    check (week >= 0),

  subject_id uuid not null
    references public.subjects(id)
    on delete restrict,

  -- O hafta o derste tüketilen YENİ benzersiz soru sayısı.
  -- Üst sınır 059 kuralı gereği 500'dür.
  new_questions_used integer not null default 0
    check (
      new_questions_used >= 0
      and new_questions_used <= 500
    ),

  updated_at timestamptz not null default now(),

  primary key (user_id, academic_year, week, subject_id),

  constraint student_weekly_counters_week_range
    check (week between 0 and 52)
);

comment on table public.student_weekly_counters is
  'Ogrenci + egitim yili + hafta + ders bazinda hizli yeni soru sayaci. 500 ust sinirinin COUNT(*''siz) kontrolu icin.';

drop trigger if exists trigger_student_weekly_counters_set_updated_at
  on public.student_weekly_counters;

create trigger trigger_student_weekly_counters_set_updated_at
before update on public.student_weekly_counters
for each row
execute function public.set_updated_at();


-- ============================================================
-- 2. RLS
-- ============================================================

alter table public.student_weekly_counters
  enable row level security;

drop policy if exists student_reads_own_weekly_counters
  on public.student_weekly_counters;

create policy student_reads_own_weekly_counters
on public.student_weekly_counters
for select
to authenticated
using (user_id = auth.uid());


-- ============================================================
-- 3. PRIVILEGES
-- ============================================================

-- Tam revoke deseni (059_01 / 057 ile ayni): authenticated uzerinde
-- TRUNCATE / REFERENCES / TRIGGER kalintisi birakmaz.
revoke all
  on table public.student_weekly_counters
  from anon, authenticated;

grant select
  on public.student_weekly_counters
  to authenticated;

grant select, insert, update, delete
  on public.student_weekly_counters
  to service_role;


commit;
