-- ============================================================================
-- rollback_165_drop.sql — YALNIZ QA: 165 nesnelerini TAMAMEN kaldirma
-- ============================================================================
-- rollback_165.sql arsiv moda gecirir (tablo/fonksiyonlar durur). Bu betik
-- GUARD_165'in "kalinti" kapilarini temizleyerek 165'in TEKRAR uygulanabilir
-- hale gelmesini dogrular (rollback → re-apply dongusu). QA disposable DB
-- icindir; canlıda calistirilmaz.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

DROP TRIGGER IF EXISTS trg_sqsq_comp_players ON public.competition_players;
DROP TRIGGER IF EXISTS trg_sqsq_comp_questions ON public.competition_questions;
DROP TRIGGER IF EXISTS trg_sqsq_comp_finalize ON public.competitions;
DROP FUNCTION IF EXISTS public.weekly_quota_status_per_subject();
DROP FUNCTION IF EXISTS public._q165_period();
DROP FUNCTION IF EXISTS public._q165_subject_of(uuid);
DROP FUNCTION IF EXISTS public._q165_lock(uuid,text,integer,uuid);
DROP FUNCTION IF EXISTS public._q165_reserve_competition(uuid,uuid);
DROP FUNCTION IF EXISTS public._q165_reserve_questions(uuid,uuid);
DROP FUNCTION IF EXISTS public._q165_trg_comp_players();
DROP FUNCTION IF EXISTS public._q165_trg_comp_questions();
DROP FUNCTION IF EXISTS public._q165_trg_comp_finalize();
DROP TRIGGER IF EXISTS trg_sqse_append_only ON public.student_week_subject_quota_events;
DROP FUNCTION IF EXISTS public._q165_trg_events_append_only();
DROP TABLE IF EXISTS public.student_week_subject_quota_events;
DROP TABLE IF EXISTS public.student_week_subject_question_ledger;
DROP TABLE IF EXISTS public.student_week_subject_quota;

-- rollback_165.sql calismissa bile history temizligi idempotent
DELETE FROM supabase_migrations.schema_migrations WHERE version = '165';

DO $ok$
BEGIN
  IF to_regclass('public.student_week_subject_quota') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_proc WHERE proname LIKE '_q165%'
                OR proname = 'weekly_quota_status_per_subject') THEN
    RAISE EXCEPTION 'DROP165: kalinti nesne var.';
  END IF;
  RAISE NOTICE 'DROP165 OK: 165 nesneleri tamamen kalkti (tekrar uygulama denenebilir)';
END $ok$;

COMMIT;
