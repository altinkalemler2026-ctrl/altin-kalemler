-- ============================================================
-- 059_03_student_question_attempts.sql
-- Altın Kalemler - Migration 059 Faz 1
--
-- Soru bazlı çözüm olay kaydı (fact tablosu).
--
-- 059 kuralları:
--   - Öğrenci analizi: ders, konu, alt konu, kazanım, zorluk,
--     bilişsel düzey, soru tipi boyutlarında analiz.
--   - Doğru / yanlış / BOŞ ayrımı.
--   - Çözüm süresi ve tekrar performansı.
--   - Geçmiş yanlış, boş ve tekrar sorularının analizi/erişimi devam eder.
--
-- Neden yeni tablo:
--   - training_attempts (018) seviye-bazlı toplamsal kayıttır; soru
--     bazlı pratik/antrenman geçmişi tutmaz.
--   - competition_answers (019) yarışma bağlamına özgüdür.
--
-- Bu tabloya istemci doğrudan yazamaz; Phase 2'deki korumalı RPC
-- (SECURITY DEFINER + auth.uid() sahiplik kontrolü) ve service_role yazar.
-- AI bu tablodan hiçbir üretim/onay akışı başlatamaz.
-- ============================================================

begin;


-- ============================================================
-- 1. STUDENT_QUESTION_ATTEMPTS
-- ============================================================

create table if not exists public.student_question_attempts (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  question_id uuid not null
    references public.questions(id)
    on delete restrict,

  -- Analizin "ders" boyutu için denormalize referans.
  subject_id uuid not null
    references public.subjects(id)
    on delete restrict,

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

  result text not null
    check (
      result in (
        'correct',
        'wrong',
        'blank',
        'pass',
        'timeout'
      )
    ),

  -- Tekrar performansı: aynı sorunun kaçıncı çözümü.
  attempt_number integer not null
    check (attempt_number >= 1),

  time_ms integer
    check (time_ms is null or time_ms >= 0),

  academic_year text not null,

  week integer
    check (week is null or week >= 0),

  answered_at timestamptz not null default now(),

  -- Kaynağındaki satıra serbest referans (competition_answers /
  -- training_attempts vb.). FK zorunlu değil; çapraz bağlam izlenebilirliği içindir.
  source_answer_id uuid,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now()
);

comment on table public.student_question_attempts is
  'Soru bazli ogrenci cozum olaylari. Dogru/yanlis/bos ayrimi, sure ve tekrar performansi analizinin ham fact verisi.';

create index if not exists idx_student_question_attempts_user_time
  on public.student_question_attempts(user_id, answered_at desc);

create index if not exists idx_student_question_attempts_question
  on public.student_question_attempts(question_id);

create index if not exists idx_student_question_attempts_week_subject
  on public.student_question_attempts(academic_year, week, subject_id);


-- ============================================================
-- 2. RLS
--
-- Öğrenci yalnız kendi kayıtlarını okuyabilir.
-- Yazma politikası YOKTUR: insert/update/delete client'a kapalıdır;
-- Phase 2 RPC (security definer) ve service_role yazar.
-- ============================================================

alter table public.student_question_attempts
  enable row level security;

drop policy if exists student_reads_own_question_attempts
  on public.student_question_attempts;

create policy student_reads_own_question_attempts
on public.student_question_attempts
for select
to authenticated
using (user_id = auth.uid());


-- ============================================================
-- 3. PRIVILEGES
-- ============================================================

-- Tam revoke deseni (059_01 / 057 ile ayni): authenticated uzerinde
-- TRUNCATE / REFERENCES / TRIGGER kalintisi birakmaz. TRUNCATE RLS'den
-- etkilenmedigi icin tam revocation zorunludur.
revoke all
  on table public.student_question_attempts
  from anon, authenticated;

grant select
  on public.student_question_attempts
  to authenticated;

grant select, insert, update, delete
  on public.student_question_attempts
  to service_role;


commit;
