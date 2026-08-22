-- ============================================================
-- 059_06_student_dimension_metrics.sql
-- Altın Kalemler - Migration 059 Faz 1
--
-- Deterministik öğrenci analiz metrikleri (özet katmanı).
--
-- 059 kuralları:
--   - Öğrenci çözüm geçmişi ders / konu / alt konu / kazanım / zorluk /
--     bilişsel düzey / soru tipi boyutlarında analiz edilebilmeli.
--   - Doğru, yanlış, boş, çözüm süresi, tekrar performansı.
--   - AI öğrenci tavsiyesini ham veriden kafasına göre oluşturmamalı;
--     önce deterministic/analitik metrikler hesaplanmalı.
--
-- Tek kompakt tablo; soru başına satır TUTMAZ.
-- scope_key: metric_scope'a göre uuid::text ('subject' için subjects.id)
-- veya değer etiketi ('difficulty' için 'easy'|'medium'|'hard' vb.).
-- Güncelleme Phase 2'deki senkron mantığıyla atomik yapılır.
-- ============================================================

begin;


-- ============================================================
-- 1. STUDENT_DIMENSION_METRICS
-- ============================================================

create table if not exists public.student_dimension_metrics (
  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  metric_scope text not null
    check (
      metric_scope in (
        'subject',
        'topic',
        'subtopic',
        'outcome',
        'difficulty',
        'cognitive_type',
        'question_type'
      )
    ),

  -- subject/topic/subtopic/outcome icin ilgili tablonun uuid'si;
  -- difficulty/cognitive_type/question_type icin deger etiketi.
  scope_key text not null,

  total_attempts integer not null default 0
    check (total_attempts >= 0),

  correct_count integer not null default 0
    check (correct_count >= 0),

  wrong_count integer not null default 0
    check (wrong_count >= 0),

  blank_count integer not null default 0
    check (blank_count >= 0),

  pass_timeout_count integer not null default 0
    check (pass_timeout_count >= 0),

  -- Tekrar performansı: attempt_number > 1 olan denemeler.
  repeat_total integer not null default 0
    check (repeat_total >= 0),

  repeat_correct integer not null default 0
    check (repeat_correct >= 0),

  total_time_ms bigint not null default 0
    check (total_time_ms >= 0),

  last_attempted_at timestamptz,

  updated_at timestamptz not null default now(),

  primary key (user_id, metric_scope, scope_key),

  constraint student_dimension_metrics_result_sum
    check (
      correct_count
      + wrong_count
      + blank_count
      + pass_timeout_count
      <= total_attempts
    ),

  constraint student_dimension_metrics_repeat_within_total
    check (repeat_total <= total_attempts)
);

comment on table public.student_dimension_metrics is
  'Deterministik ogrenci analiz ozeti. AI tavsiyesi bu hazir metriklerden uretilir; ham veriden keyfi hesap yapilmaz.';

create index if not exists idx_student_dimension_metrics_scope
  on public.student_dimension_metrics(metric_scope, scope_key);

drop trigger if exists trigger_student_dimension_metrics_set_updated_at
  on public.student_dimension_metrics;

create trigger trigger_student_dimension_metrics_set_updated_at
before update on public.student_dimension_metrics
for each row
execute function public.set_updated_at();


-- ============================================================
-- 2. RLS
-- ============================================================

alter table public.student_dimension_metrics
  enable row level security;

drop policy if exists student_reads_own_dimension_metrics
  on public.student_dimension_metrics;

create policy student_reads_own_dimension_metrics
on public.student_dimension_metrics
for select
to authenticated
using (user_id = auth.uid());


-- ============================================================
-- 3. PRIVILEGES
-- ============================================================

-- Tam revoke deseni (059_01 / 057 ile ayni): authenticated uzerinde
-- TRUNCATE / REFERENCES / TRIGGER kalintisi birakmaz.
revoke all
  on table public.student_dimension_metrics
  from anon, authenticated;

grant select
  on public.student_dimension_metrics
  to authenticated;

grant select, insert, update, delete
  on public.student_dimension_metrics
  to service_role;


commit;
