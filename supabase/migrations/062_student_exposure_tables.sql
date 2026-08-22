-- ============================================================
-- 059_04_student_exposure_tables.sql
-- Altın Kalemler - Migration 059 Faz 1
--
-- Öğrenci görme (exposure) kayıtları.
--
-- 059 kuralları:
--   - student/question exposure kayıtları indeksli olmalı.
--   - student/pack exposure kayıtları indeksli olmalı.
--   - İki öğrenci yarışırken öncelikle ikisinin de hiç görmediği ortak
--     5 soruluk kasa seçilmeli.
--   - Tamamen ortak çözülmemiş kasa yoksa ikisinin de görmediği yeterli
--     soru bulunan uygun kasa değerlendirilmeli.
--
-- Exposure kaydı yeniden sormayı ENGELLEMEZ; yalnız "yeni soru" ve
-- "ortak görülmemiş kasa" tanımını besler. Geçmiş yanlış/boş/tekrar
-- erişimi ayrıca attempts tablosundan devam eder.
--
-- Paket kavramının taşıyıcısı question_vaults (048) olmaya devam eder;
-- bu tablolar yalnız görme kaydı tutar.
-- ============================================================

begin;


-- ============================================================
-- 1. STUDENT_QUESTION_EXPOSURES
--
-- PK (user_id, question_id, context) anti-join sorgularının anahtarıdır.
-- idx_question: "iki öğrencinin ortak görmediği soru" sayımı için ters yön.
-- ============================================================

create table if not exists public.student_question_exposures (
  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  question_id uuid not null
    references public.questions(id)
    on delete cascade,

  attempt_context text not null
    check (
      attempt_context in (
        'practice',
        'competition',
        'one_v_one',
        'training',
        'exam'
      )
    ),

  first_exposed_at timestamptz not null default now(),

  primary key (user_id, question_id, attempt_context)
);

comment on table public.student_question_exposures is
  'Ogrencinin bir soruyu hangi baglamda gordugunun tekil kaydi. Ortak gorulmemis soru/kasa seciminin temel verisi.';

create index if not exists idx_student_question_exposures_question
  on public.student_question_exposures(question_id);


-- ============================================================
-- 2. STUDENT_PACK_EXPOSURES
--
-- fully_solved: kasanın tüm sorularının çözüldüğü anlamına gelir.
-- "Tamamen ortak çözülmemiş kasa yoksa..." fallback kontrolünde kullanılır.
-- ============================================================

create table if not exists public.student_pack_exposures (
  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  vault_id uuid not null
    references public.question_vaults(id)
    on delete cascade,

  -- Paketler yalnız yarışma bağlamlarında kullanılır.
  attempt_context text not null
    check (
      attempt_context in (
        'competition',
        'one_v_one'
      )
    ),

  fully_solved boolean not null default false,

  first_exposed_at timestamptz not null default now(),

  last_solved_at timestamptz,

  primary key (user_id, vault_id, attempt_context),

  constraint student_pack_exposures_solved_consistency
    check (
      fully_solved = false
      or last_solved_at is not null
    )
);

comment on table public.student_pack_exposures is
  'Ogrencinin bir 5''lik paket kasayi gorme/cozme durumu. Ortak gorulmemis paket seciminde anti-join ana verisi.';

create index if not exists idx_student_pack_exposures_vault
  on public.student_pack_exposures(vault_id);

create index if not exists idx_student_pack_exposures_vault_unsolved
  on public.student_pack_exposures(vault_id)
  where fully_solved = false;


-- ============================================================
-- 3. RLS
--
-- Öğrenci yalnız kendi exposure kayıtlarını okuyabilir.
-- Yazma politikası YOKTUR; Phase 2 seçim/senkron RPC'leri yazar.
-- ============================================================

alter table public.student_question_exposures
  enable row level security;

alter table public.student_pack_exposures
  enable row level security;

drop policy if exists student_reads_own_question_exposures
  on public.student_question_exposures;

create policy student_reads_own_question_exposures
on public.student_question_exposures
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists student_reads_own_pack_exposures
  on public.student_pack_exposures;

create policy student_reads_own_pack_exposures
on public.student_pack_exposures
for select
to authenticated
using (user_id = auth.uid());


-- ============================================================
-- 4. PRIVILEGES
-- ============================================================

-- Tam revoke deseni (059_01 / 057 ile ayni): authenticated uzerinde
-- TRUNCATE / REFERENCES / TRIGGER kalintisi birakmaz.
revoke all
  on table public.student_question_exposures
  from anon, authenticated;

revoke all
  on table public.student_pack_exposures
  from anon, authenticated;

grant select
  on public.student_question_exposures
  to authenticated;

grant select
  on public.student_pack_exposures
  to authenticated;

grant select, insert, update, delete
  on public.student_question_exposures
  to service_role;

grant select, insert, update, delete
  on public.student_pack_exposures
  to service_role;


commit;
