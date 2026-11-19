-- ============================================================
-- 135_admin_bulk_gate_integrity.sql
-- Altın Kalemler — WP-10: BÜYÜK KOŞU ÖNCESİ BÜTÜNLÜK DÜZELTMELERİ
--
-- Kapsam (migration 134 sonrası; kapı sözleşmesi GEVŞETİLMEDEN):
--   1) Yarış koruması: aynı (aday, kapı, rol) için bekleyen/çalışan
--      görevi olan ikinci kopya kısmi unique index ile ENGELLENİR
--      (önceki koruma yalnız plan anındaki EXISTS kontrolüydü — iki
--      eşzamanlı başlatma arasında TOCTOU penceresi vardı).
--   2) `start_bulk_gate_control`: görev ekleme unique ihlalini
--      aday-bazlı hataya çevirir (bütün koşum iptal olmaz;
--      'duplicate_pending_task' hatası listelenir — fail-closed).
--   3) `complete_bulk_gate_task`: zincir adımı eklemesi unique
--      ihlaline karşı savunmalıdır (ihlalde zincir adımı açılmaz;
--      görev tamamlandı kaydı korunur).
--   4) `bulk_gate_classify`: deneme hakkı dolmuş görevler
--      ('skipped' — yalnız retry tükendiğinde üretilir) artık
--      'technical_error' grubuna DÜŞER (önceki davranış: gruptan
--      çıkıp başka gruba karışıyordu — izlenebilirlik hatası).
--   5) `set_bulk_gate_control_stop`: devam et (resume) durumunu
--      görev sayaçlarından türetir; tamamlanmış/başarısız koşum
--      yanlışlıkla 'running' gösterilmez (önceki davranış: durdurulmuş
--      koşum koşulsuz 'running' yapılıyordu).
--
-- Not: Yalnız fonksiyon tanımları + bir index; tablo şeması, RLS ve
-- mevcut kayıtlar korunur. db reset YOK.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1) YARIŞ KORUMASI — kısmi unique index
--    (Aynı aday/kapı/rol için aynı anda birden fazla bekleyen/
--     çalışan görev OLAMAZ; farklı koşumlarda bile.)
-- ------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS
  uq_admin_bulk_gate_tasks_pending_running
  ON public.admin_bulk_gate_tasks (staging_question_id, gate_key, gate_role)
  WHERE status IN ('pending', 'running');

-- ------------------------------------------------------------
-- 2) BAŞLAT — görev ekleme unique ihlali aday-bazlı hataya çevrilir
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_bulk_gate_control(
  p_batch_id uuid,
  p_scope text,
  p_candidate_ids uuid[] DEFAULT ARRAY[]::uuid[],
  p_gates text[] DEFAULT ARRAY[]::text[],
  p_group_filter text DEFAULT NULL,
  p_model text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan jsonb;
  v_task jsonb;
  v_run_id uuid;
  v_bulk_run_id uuid;
  v_created integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_staging uuid;
  v_gate text;
  v_role text;
  v_need_start boolean;
  v_gate_run_id uuid;
  v_snapshot jsonb;
  v_position integer;
  v_start_error text;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  IF p_scope NOT IN ('selection', 'filter') THEN
    RAISE EXCEPTION 'Invalid bulk scope.';
  END IF;

  IF COALESCE(btrim(p_model), '') = '' THEN
    RAISE EXCEPTION 'Model identifier is required.';
  END IF;

  -- MODEL BEYAZ LİSTESİ (sunucu garantisi; TS katmanına ek)
  IF NOT (p_model = ANY(private.bulk_allowed_models())) THEN
    RAISE EXCEPTION 'Bulk model is not allowed.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM unnest(COALESCE(p_gates, ARRAY[]::text[])) g(g)
    WHERE g.g NOT IN ('answer', 'curriculum', 'quality')
  ) THEN
    RAISE EXCEPTION 'Unsupported gate for bulk control.';
  END IF;

  IF p_scope = 'selection'
     AND COALESCE(array_length(p_candidate_ids, 1), 0) = 0
  THEN
    RAISE EXCEPTION 'No candidate selected.';
  END IF;

  -- Plan sunucuda yeniden hesaplanır (istemci listesi güvenilmez).
  v_plan := private.bulk_gate_plan(
    p_batch_id,
    p_scope,
    p_candidate_ids,
    p_gates,
    p_group_filter
  );

  INSERT INTO public.admin_bulk_gate_runs (
    batch_id,
    scope,
    filter_spec,
    gates,
    model,
    status,
    planned_candidate_count,
    planned_task_count,
    planned_model_call_count,
    cost_estimate_status,
    cost_estimate_minor_units,
    cost_currency,
    created_by
  )
  VALUES (
    p_batch_id,
    p_scope,
    jsonb_build_object('group', p_group_filter),
    COALESCE(p_gates, ARRAY[]::text[]),
    p_model,
    'planned',
    (v_plan ->> 'selected_candidate_count')::integer,
    jsonb_array_length(v_plan -> 'tasks'),
    (v_plan ->> 'planned_model_calls')::integer,
    'unavailable',
    NULL,
    NULL,
    auth.uid()
  )
  RETURNING id INTO v_bulk_run_id;

  FOR v_task IN SELECT value FROM jsonb_array_elements(v_plan -> 'tasks') AS t(value)
  LOOP
    v_staging := (v_task ->> 'staging_question_id')::uuid;
    v_gate := v_task ->> 'gate_key';
    v_role := v_task ->> 'gate_role';
    v_need_start := COALESCE((v_task ->> 'need_start')::boolean, false);
    v_gate_run_id := (v_task ->> 'gate_run_id')::uuid;
    v_snapshot := v_task -> 'content_snapshot';
    v_position := (v_task ->> 'candidate_position')::integer;

    -- Kapı çalıştırma kaydı yoksa oluştur (mevcut start RPC'ler üzerinden;
    --   guard ve kapı sözleşmesi AYNEN korunur).
    IF v_need_start THEN
      BEGIN
        IF v_gate = 'answer' THEN
          v_gate_run_id := private.start_answer_verification(v_staging, 0.90);
        ELSIF v_gate = 'curriculum' THEN
          v_gate_run_id := private.start_curriculum_fit_verification(v_staging, 0.90);
        ELSIF v_gate = 'quality' THEN
          v_gate_run_id := private.start_question_quality_review(v_staging, 0.90, 0.85);
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_start_error := SQLERRM;
        v_gate_run_id := NULL;
      END;
    END IF;

    IF v_start_error IS NOT NULL THEN
      v_errors := v_errors || jsonb_build_object(
        'staging_question_id', v_staging,
        'candidate_position', v_position,
        'gate_key', v_gate,
        'gate_role', v_role,
        'error_code', 'gate_start_failed',
        'error_message', v_start_error
      );
      v_start_error := NULL;
      CONTINUE;
    END IF;

    IF v_gate_run_id IS NULL THEN
      v_errors := v_errors || jsonb_build_object(
        'staging_question_id', v_staging,
        'candidate_position', v_position,
        'gate_key', v_gate,
        'gate_role', v_role,
        'error_code', 'gate_run_missing',
        'error_message', 'Gate run could not be opened.'
      );
      CONTINUE;
    END IF;

    -- Görev ekleme: plan-INSERT yarış penceresine karşı kısmi unique
    -- index ile korunur; ihlal bütün koşumu DEĞİL, yalnız o görevi
    -- düşürür (fail-closed; mükerrer çalışma oluşmaz).
    BEGIN
      INSERT INTO public.admin_bulk_gate_tasks (
        bulk_run_id,
        staging_question_id,
        candidate_position,
        gate_key,
        gate_role,
        status,
        gate_run_id,
        content_snapshot
      )
      VALUES (
        v_bulk_run_id,
        v_staging,
        v_position,
        v_gate,
        v_role,
        'pending',
        v_gate_run_id,
        v_snapshot
      )
      ON CONFLICT (bulk_run_id, staging_question_id, gate_key, gate_role)
      DO NOTHING;

      IF FOUND THEN
        v_created := v_created + 1;
      END IF;
    EXCEPTION
      WHEN unique_violation THEN
        v_errors := v_errors || jsonb_build_object(
          'staging_question_id', v_staging,
          'candidate_position', v_position,
          'gate_key', v_gate,
          'gate_role', v_role,
          'error_code', 'duplicate_pending_task',
          'error_message', 'Aynı (aday, kapı, rol) için bekleyen/çalışan görev zaten var; ikinci kopya oluşturulmadı.'
        );
    END;
  END LOOP;

  UPDATE public.admin_bulk_gate_runs
  SET
    planned_task_count = v_created,
    planned_model_call_count = v_created,
    status = CASE WHEN v_created = 0 THEN 'completed' ELSE 'planned' END
  WHERE id = v_bulk_run_id;

  RETURN jsonb_build_object(
    'bulk_run_id', v_bulk_run_id,
    'created_task_count', v_created,
    'selected_candidate_count', (v_plan ->> 'selected_candidate_count')::integer,
    'skipped', v_plan -> 'skipped',
    'human_queue', v_plan -> 'human_queue',
    'errors', v_errors,
    'planned_model_calls', v_created,
    'cost_estimate_status', 'unavailable',
    'cost_estimate_minor_units', NULL,
    'cost_currency', NULL,
    'model', p_model
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.start_bulk_gate_control(uuid, text, uuid[], text[], text, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.start_bulk_gate_control(uuid, text, uuid[], text[], text, text)
  TO authenticated, service_role;


-- ------------------------------------------------------------
-- 3) GÖREV TAMAMLA — zincir adımı unique ihlaline savunmalı
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_bulk_gate_task(
  p_task_id uuid,
  p_status text,
  p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_task record;
  v_next_status text;
  v_next_created boolean := false;
  v_next_role text;
  v_remaining integer := 0;
  v_run_stopped boolean := false;
  v_completed integer := 0;
  v_failed integer := 0;
  v_skipped integer := 0;
  v_run_status text;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required.';
  END IF;

  IF p_status NOT IN ('completed', 'failed', 'skipped') THEN
    RAISE EXCEPTION 'Invalid task status.';
  END IF;

  SELECT *
  INTO v_task
  FROM public.admin_bulk_gate_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bulk task not found.';
  END IF;

  UPDATE public.admin_bulk_gate_tasks
  SET
    status = p_status,
    error_code = p_error_code,
    error_message = p_error_message,
    completed_at = CASE
      WHEN p_status = 'pending' THEN NULL
      ELSE now()
    END,
    claimed_by = NULL,
    lease_expires_at = NULL
  WHERE id = p_task_id;

  -- Zincir: kapı sıradaki adımı bekliyorsa yeni görev açılır.
  IF p_status = 'completed' THEN
    v_next_role := NULL;

    IF v_task.gate_key = 'answer' THEN
      SELECT consensus_status
      INTO v_next_status
      FROM public.ai_answer_verification_runs
      WHERE id = v_task.gate_run_id;

      IF v_next_status = 'waiting_solver_2' THEN
        v_next_role := 'solver_2';
      END IF;
    ELSE
      IF v_task.gate_key = 'curriculum' THEN
        SELECT status
        INTO v_next_status
        FROM public.ai_curriculum_fit_runs
        WHERE id = v_task.gate_run_id;
      ELSIF v_task.gate_key = 'quality' THEN
        SELECT status
        INTO v_next_status
        FROM public.ai_question_quality_runs
        WHERE id = v_task.gate_run_id;
      END IF;

      IF v_next_status = 'waiting_reviewer_2' THEN
        v_next_role := 'reviewer_2';
      END IF;
    END IF;

    IF v_next_role IS NOT NULL THEN
      BEGIN
        INSERT INTO public.admin_bulk_gate_tasks (
          bulk_run_id,
          staging_question_id,
          candidate_position,
          gate_key,
          gate_role,
          status,
          gate_run_id,
          content_snapshot
        )
        VALUES (
          v_task.bulk_run_id,
          v_task.staging_question_id,
          v_task.candidate_position,
          v_task.gate_key,
          v_next_role,
          'pending',
          v_task.gate_run_id,
          v_task.content_snapshot
        )
        ON CONFLICT (bulk_run_id, staging_question_id, gate_key, gate_role)
        DO NOTHING;

        v_next_created := FOUND;
      EXCEPTION
        WHEN unique_violation THEN
          -- Başka bir koşumun bekleyen/çalışan görevi aynı (aday,
          -- kapı, rol) çiftini tutuyor; zincir adımı AÇILMAZ
          -- (mükerrer çalışma oluşmaz; görev tamamlandı kalır).
          v_next_created := false;
      END;
    END IF;
  END IF;

  -- Koşu sayaçları (KOŞU bazlı; tek doğruluk kaynağı DB).
  SELECT
    count(*) FILTER (WHERE t.status IN ('pending', 'running')),
    count(*) FILTER (WHERE t.status = 'completed'),
    count(*) FILTER (WHERE t.status = 'failed'),
    count(*) FILTER (WHERE t.status = 'skipped'),
    COALESCE(bool_or(r.stop_requested), false)
  INTO
    v_remaining,
    v_completed,
    v_failed,
    v_skipped,
    v_run_stopped
  FROM public.admin_bulk_gate_tasks t
  JOIN public.admin_bulk_gate_runs r
    ON r.id = t.bulk_run_id
  WHERE t.bulk_run_id = v_task.bulk_run_id;

  -- Koşu sonu: tüm işler bittiğinde BÜTÜN görevler başarısızsa koşu
  -- 'failed' olur (dürüst izlenebilirlik; kısmi başarı 'completed').
  v_run_status := CASE
    WHEN v_run_stopped THEN 'stopped'
    WHEN v_remaining > 0 THEN 'running'
    WHEN v_completed = 0 AND (v_failed > 0) THEN 'failed'
    ELSE 'completed'
  END;

  UPDATE public.admin_bulk_gate_runs
  SET
    status = v_run_status,
    started_at = COALESCE(started_at, now())
  WHERE id = v_task.bulk_run_id;

  RETURN jsonb_build_object(
    'task_id', p_task_id,
    'status', p_status,
    'next_task_created', v_next_created,
    'remaining_task_count', v_remaining,
    'completed_task_count', v_completed,
    'failed_task_count', v_failed,
    'skipped_task_count', v_skipped,
    'run_stopped', v_run_stopped,
    'run_status', v_run_status
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.complete_bulk_gate_task(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.complete_bulk_gate_task(uuid, text, text, text)
  TO service_role;


-- ------------------------------------------------------------
-- 4) GRUP SINIFLANDIRMA — 'skipped' (deneme hakkı dolmuş) görevler
--    teknik hata grubuna döner (izlenebilirlik; gruptan kaybolmaz).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.bulk_gate_classify(p_row jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_gates jsonb;
  v_bulk jsonb;
  v_readiness jsonb;
BEGIN
  v_gates := COALESCE(p_row -> 'gates', '{}'::jsonb);
  v_bulk := COALESCE(p_row -> 'bulk', '{}'::jsonb);
  v_readiness := COALESCE(p_row -> 'readiness', '{}'::jsonb);

  -- 1) Teknik hata (başarısız VEYA deneme hakkı dolmuş 'skipped')
  IF COALESCE((v_bulk ->> 'failed')::integer, 0) > 0
     OR COALESCE((v_bulk ->> 'skipped')::integer, 0) > 0
  THEN
    RETURN 'technical_error';
  END IF;

  -- 2) Karar kapanmış
  IF (p_row ->> 'staging_status') IN ('rejected', 'promoted') THEN
    RETURN 'closed';
  END IF;

  -- 3) Çalışıyor
  IF COALESCE((v_bulk ->> 'running')::integer, 0) > 0 THEN
    RETURN 'running';
  END IF;

  -- 4) Düzeltme / uyuşmazlık
  IF (v_gates -> 'answer' ->> 'status') IN (
        'answer_mismatch', 'solver_disagreement', 'rejected'
      )
     OR (v_gates -> 'curriculum' ->> 'status') IN (
        'grade_mismatch', 'subject_mismatch', 'topic_mismatch',
        'subtopic_mismatch', 'outcome_mismatch', 'prerequisite_violation',
        'reviewer_disagreement', 'rejected'
      )
     OR (v_gates -> 'quality' ->> 'status') IN (
        'language_problem', 'scientific_problem', 'ambiguity_problem',
        'option_quality_problem', 'difficulty_mismatch', 'cognitive_mismatch',
        'question_type_mismatch', 'reviewer_disagreement', 'rejected'
      )
     OR (v_gates -> 'solve_time' ->> 'status') IN (
        'producer_mismatch', 'outside_requested_range',
        'reviewer_disagreement', 'rejected'
      )
     OR (v_gates -> 'originality' ->> 'status') IN (
        'low_originality', 'high_similarity', 'possible_duplicate',
        'copyright_risk', 'blocked', 'reviewer_disagreement', 'rejected'
      )
     OR (v_readiness ->> 'status') IN ('blocked', 'rejected')
  THEN
    RETURN 'needs_fix';
  END IF;

  -- 5) Eksik otomatik kontrol var
  IF (v_gates -> 'answer' ->> 'status') IS NULL
     OR (v_gates -> 'curriculum' ->> 'status') IS NULL
     OR (v_gates -> 'quality' ->> 'status') IS NULL
     OR COALESCE((v_bulk ->> 'pending')::integer, 0) > 0
  THEN
    RETURN 'waiting';
  END IF;

  -- 6) İnsan incelemesi / ölçümü bekliyor
  IF (v_gates -> 'answer' ->> 'status') IN ('needs_human_review', 'low_confidence')
     OR (v_gates -> 'curriculum' ->> 'status') IN ('needs_human_review', 'low_confidence')
     OR (v_gates -> 'quality' ->> 'status') IN ('needs_human_review', 'low_confidence')
     OR (v_gates -> 'solve_time' ->> 'status') IS NULL
     OR (v_gates -> 'originality' ->> 'status') IS NULL
     OR (v_gates -> 'solve_time' ->> 'status') IN (
          'needs_human_review', 'low_confidence',
          'waiting_reviewer_1', 'waiting_reviewer_2'
        )
     OR (v_gates -> 'originality' ->> 'status') IN (
          'needs_human_review', 'low_confidence',
          'waiting_reviewer_1', 'waiting_reviewer_2'
        )
  THEN
    RETURN 'human_pending';
  END IF;

  -- 7) Nihai insan onayı bekliyor
  IF (v_readiness ->> 'status') = 'ready_for_human_review'
     AND COALESCE((v_readiness ->> 'score')::numeric, 0) = 1
  THEN
    RETURN 'ready_for_approval';
  END IF;

  RETURN 'human_pending';
END;
$$;


REVOKE ALL
  ON FUNCTION private.bulk_gate_classify(jsonb)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION private.bulk_gate_classify(jsonb)
  TO service_role;


-- ------------------------------------------------------------
-- 5) DURDUR / DEVAM ET — devam durumunu görev sayaçlarından türet
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_bulk_gate_control_stop(
  p_bulk_run_id uuid,
  p_stop boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row record;
  v_remaining integer := 0;
  v_completed integer := 0;
  v_failed integer := 0;
  v_skipped integer := 0;
  v_new_status text;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  SELECT status, stop_requested
  INTO v_row
  FROM public.admin_bulk_gate_runs
  WHERE id = p_bulk_run_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bulk run not found.';
  END IF;

  IF p_stop THEN
    v_new_status := 'stopped';
  ELSIF COALESCE(v_row.stop_requested, false) THEN
    -- DEVAM: gerçek durum görev sayaçlarından türetilir.
    -- (Koşum sayacı kuralları complete_bulk_gate_task ile AYNI:
    --  iş kalmadıysa tümü başarısızsa 'failed', aksi 'completed'.)
    SELECT
      count(*) FILTER (WHERE t.status IN ('pending', 'running')),
      count(*) FILTER (WHERE t.status = 'completed'),
      count(*) FILTER (WHERE t.status = 'failed'),
      count(*) FILTER (WHERE t.status = 'skipped')
    INTO v_remaining, v_completed, v_failed, v_skipped
    FROM public.admin_bulk_gate_tasks t
    WHERE t.bulk_run_id = p_bulk_run_id;

    v_new_status := CASE
      WHEN v_remaining > 0 THEN 'running'
      WHEN v_completed = 0 AND (v_failed > 0) THEN 'failed'
      ELSE 'completed'
    END;
  ELSE
    v_new_status := v_row.status;
  END IF;

  UPDATE public.admin_bulk_gate_runs
  SET
    stop_requested = p_stop,
    status = v_new_status,
    stopped_at = CASE WHEN p_stop THEN now() ELSE NULL END
  WHERE id = p_bulk_run_id
  RETURNING
    id, scope, status, stop_requested, model,
    planned_candidate_count, planned_task_count, planned_model_call_count,
    cost_estimate_status, created_at, started_at, stopped_at
  INTO v_row;

  RETURN jsonb_build_object(
    'bulk_run_id', v_row.id,
    'status', v_row.status,
    'stop_requested', v_row.stop_requested,
    'planned_task_count', v_row.planned_task_count,
    'planned_model_call_count', v_row.planned_model_call_count,
    'cost_estimate_status', v_row.cost_estimate_status,
    'model', v_row.model
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.set_bulk_gate_control_stop(uuid, boolean)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.set_bulk_gate_control_stop(uuid, boolean)
  TO authenticated, service_role;


COMMIT;
