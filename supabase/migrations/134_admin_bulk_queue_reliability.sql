-- ============================================================
-- 134_admin_bulk_queue_reliability.sql
-- Altın Kalemler — WP-10: BÜYÜK KOŞU ÖNCESİ KUYRUK GÜVENİLİRLİĞİ
--
-- Kapsam (günlük kararı bozmadan, kapı sözleşmesini GEVŞETMEDEN):
--   1) Müfredat kapısı için kanonik kazanım kaydı artık konu/alt-konu
--      bağını da döndürür: worker, gözden geçirenin seçtiği kazanımın
--      DOĞRULANMIŞ DB satırındaki topic_id/subtopic_id değerini gönderir
--      (eski davranışta NULL gönderiliyordu → sistematik topic_mismatch).
--   2) Lease/lock kurtarma: süresi dolmuş 'running' görev yalnız
--      deneme hakkı bitmemişse yeniden alınabilir (attempt sayacı devam
--      eder; üst sınır 3 korunur); deneme hakkı bitmiş ve lease'i
--      süresi geçmiş görev açıkça 'failed' olur (kalıcı 'running' kalmaz).
--   3) Koşu (run) durumu: tüm görevler bittiğinde kısmen/tamamı başarılıysa
--      'completed', BÜTÜN görevler başarısızsa 'failed' yazılır; koşu
--      çıktısı tamamlanan/başarısız/atlanan görev sayacını verir.
--   4) SQL düzeyinde model beyaz listesi: start RPC YALNIZ izinli modeli
--      kabul eder (TS katmanına ek sunucu garantisi; yeni model AÇILMAZ).
--
-- Not: Bu migration YALNIZ fonksiyon tanımlarını değiştirir; tablo
-- şeması, RLS ve mevcut kayıtlar korunur. db reset YOK.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1) KANONİK KAZANIM KAYDI — konu/alt-konu bağını ekle
--    (worker: seçilen kazanımın DB'deki doğrulanmış konu/alt-konu
--     değerini müfredat gönderimine taşır; UYDURMA yok.)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_canonical_outcome_codes(
  p_curriculum_version_id uuid,
  p_subject_id uuid,
  p_min_grade integer DEFAULT 9,
  p_max_grade integer DEFAULT 12
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'code', o.outcome_code,
        'text', o.outcome_text,
        'topic_id', o.topic_id,
        'subtopic_id', o.subtopic_id
      )
      ORDER BY o.grade_level, o.outcome_code
    ),
    '[]'::jsonb
  )
  FROM public.curriculum_outcomes o
  WHERE o.is_active = true
    AND (p_curriculum_version_id IS NULL OR o.curriculum_version_id = p_curriculum_version_id)
    AND (p_subject_id IS NULL OR o.subject_id = p_subject_id)
    AND o.grade_level BETWEEN COALESCE(p_min_grade, 9) AND COALESCE(p_max_grade, 12);
$$;


REVOKE ALL
  ON FUNCTION public.get_canonical_outcome_codes(uuid, uuid, integer, integer)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.get_canonical_outcome_codes(uuid, uuid, integer, integer)
  TO service_role;


-- ------------------------------------------------------------
-- 2) MODEL BEYAZ LİSTESİ (tek doğruluk kaynağı SQL'de)
--    Yeni sağlayıcı/model AÇILMAZ; yalnız mevcut izinli ücretli model.
--    Not: aday gövdesi yalnız tanımlı ücretli modele gönderilir.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.bulk_allowed_models()
RETURNS text[]
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT ARRAY['opencode-go/glm-5.3-flash']::text[];
$$;


REVOKE ALL
  ON FUNCTION private.bulk_allowed_models()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION private.bulk_allowed_models()
  TO service_role;


-- ------------------------------------------------------------
-- 3) PLAN (salt-okunur) — 133 imzası ve davranışı korunur.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.plan_bulk_gate_control(
  p_batch_id uuid,
  p_scope text,
  p_candidate_ids uuid[] DEFAULT ARRAY[]::uuid[],
  p_gates text[] DEFAULT ARRAY[]::text[],
  p_group_filter text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan jsonb;
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

  IF EXISTS (
    SELECT 1 FROM unnest(COALESCE(p_gates, ARRAY[]::text[])) g(g)
    WHERE g.g NOT IN ('answer', 'curriculum', 'quality')
  ) THEN
    RAISE EXCEPTION 'Unsupported gate for bulk control.';
  END IF;

  v_plan := private.bulk_gate_plan(
    p_batch_id,
    p_scope,
    p_candidate_ids,
    p_gates,
    p_group_filter
  );

  RETURN v_plan;
END;
$$;


REVOKE ALL
  ON FUNCTION public.plan_bulk_gate_control(uuid, text, uuid[], text[], text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.plan_bulk_gate_control(uuid, text, uuid[], text[], text)
  TO authenticated, service_role;


-- ------------------------------------------------------------
-- 4) BAŞLAT — 133 davranışı + MODEL BEYAZ LİSTESİ (sunucu garantisi).
--    İmza değişmedi: iki adımlı onay akışı (önizleme + başlat) aynı.
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
-- 5) GÖREV AL (lease) — süresi dolmuş 'running' görevler de
--    kurtarılır (FOR UPDATE SKIP LOCKED; attempt sayacı devam eder).
--    Mükerrer sonuç yok: aynı görev satırı tekrar çalışır, ikinci
--    kopya oluşturulmaz.
--    Deneme hakkı bitmiş (attempt_count >= 3) ve lease'i süresi geçmiş
--    görev kurtarılamaz: açıkça 'failed' olur; kalıcı 'running' BULUNMAZ.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_bulk_gate_tasks(
  p_worker_id text,
  p_limit integer DEFAULT 1,
  p_lease_seconds integer DEFAULT 300
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_task record;
  v_ctx record;
  v_model text;
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required.';
  END IF;

  -- 5.0) Lease'i süresi geçmiş ve deneme hakkı bitmiş görev kalıcı
  --      'running' OLAMAZ: teknik hata olarak kapatılır (sonraki koşumda
  --      yeniden deneme yolu 'retry_failed_bulk_gate_tasks' ile açıktır).
  UPDATE public.admin_bulk_gate_tasks t
  SET
    status = 'failed',
    error_code = COALESCE(t.error_code, 'lease_expiration_exhausted'),
    error_message = COALESCE(t.error_message,
      'Lease expired after the maximum 3 controlled attempts; task was not left running.'),
    completed_at = now(),
    claimed_by = NULL,
    lease_expires_at = NULL
  FROM public.admin_bulk_gate_runs r
  WHERE r.id = t.bulk_run_id
    AND t.status = 'running'
    AND t.attempt_count >= 3
    AND t.lease_expires_at IS NOT NULL
    AND t.lease_expires_at < now();

  -- 5.1) Yeni iş veya süresi dolmuş (hakkı bitmemiş) iş alımı.
  FOR v_task IN
    WITH candidates AS (
      SELECT t.id
      FROM public.admin_bulk_gate_tasks t
      JOIN public.admin_bulk_gate_runs r
        ON r.id = t.bulk_run_id
      WHERE (
              t.status = 'pending'
              OR (
                t.status = 'running'
                AND t.attempt_count < 3
                AND t.lease_expires_at IS NOT NULL
                AND t.lease_expires_at < now()
              )
            )
        AND r.stop_requested = false
      ORDER BY t.created_at ASC, t.id ASC
      FOR UPDATE OF t SKIP LOCKED
      LIMIT GREATEST(COALESCE(p_limit, 1), 1)
    )
    UPDATE public.admin_bulk_gate_tasks t
    SET
      status = 'running',
      claimed_by = p_worker_id,
      lease_expires_at = now()
        + make_interval(secs => GREATEST(COALESCE(p_lease_seconds, 300), 30)),
      started_at = COALESCE(t.started_at, now()),
      attempt_count = t.attempt_count + 1
    FROM candidates c
    WHERE t.id = c.id
    RETURNING
      t.id,
      t.bulk_run_id,
      t.staging_question_id,
      t.candidate_position,
      t.gate_key,
      t.gate_role,
      t.attempt_count,
      t.gate_run_id,
      t.content_snapshot
  LOOP
    SELECT r.model
    INTO v_model
    FROM public.admin_bulk_gate_runs r
    WHERE r.id = v_task.bulk_run_id;

    SELECT
      COALESCE(
        NULLIF(s.metadata ->> 'client_question_id', ''),
        s.metadata ->> 'client_question_id'
      ) AS client_question_id,
      sub.name AS subject_name,
      s.question_text,
      s.option_a, s.option_b, s.option_c, s.option_d, s.option_e,
      s.proposed_correct_answer,
      s.grade_level,
      s.subject_id,
      s.proposed_topic_id,
      s.proposed_subtopic_id,
      s.proposed_solve_time_seconds,
      s.proposed_curriculum_version_id,
      s.metadata ->> 'outcome_code' AS outcome_code
    INTO v_ctx
    FROM public.ai_question_staging s
    LEFT JOIN public.subjects sub
      ON sub.id = s.subject_id
    WHERE s.id = v_task.staging_question_id;

    v_items := v_items || jsonb_build_object(
      'task_id', v_task.id,
      'bulk_run_id', v_task.bulk_run_id,
      'staging_question_id', v_task.staging_question_id,
      'candidate_position', v_task.candidate_position,
      'gate_key', v_task.gate_key,
      'gate_role', v_task.gate_role,
      'attempt_count', v_task.attempt_count,
      'gate_run_id', v_task.gate_run_id,
      'content_snapshot', v_task.content_snapshot,
      'current_snapshot', jsonb_build_object(
        'question_text', v_ctx.question_text,
        'option_a', v_ctx.option_a,
        'option_b', v_ctx.option_b,
        'option_c', v_ctx.option_c,
        'option_d', v_ctx.option_d,
        'option_e', v_ctx.option_e,
        'proposed_correct_answer', v_ctx.proposed_correct_answer,
        'grade_level', v_ctx.grade_level,
        'subject_id', v_ctx.subject_id,
        'topic_id', v_ctx.proposed_topic_id,
        'subtopic_id', v_ctx.proposed_subtopic_id,
        'solve_time_seconds', v_ctx.proposed_solve_time_seconds,
        'curriculum_version_id', v_ctx.proposed_curriculum_version_id
      ),
      'model', v_model,
      'blind_context', jsonb_build_object(
        'clientQuestionId', v_ctx.client_question_id,
        'subjectName', COALESCE(v_ctx.subject_name, 'Matematik'),
        'questionText', v_ctx.question_text,
        'options', jsonb_build_object(
          'A', v_ctx.option_a,
          'B', v_ctx.option_b,
          'C', v_ctx.option_c,
          'D', v_ctx.option_d,
          'E', v_ctx.option_e
        ),
        'gradeLevel', v_ctx.grade_level,
        'subjectId', v_ctx.subject_id,
        'topicId', v_ctx.proposed_topic_id,
        'subtopicId', v_ctx.proposed_subtopic_id,
        'curriculumVersionId', v_ctx.proposed_curriculum_version_id,
        'outcomeCode', v_ctx.outcome_code
      )
    );
  END LOOP;

  RETURN jsonb_build_object(
    'claimed_count', jsonb_array_length(v_items),
    'tasks', v_items
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.claim_bulk_gate_tasks(text, integer, integer)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.claim_bulk_gate_tasks(text, integer, integer)
  TO service_role;


-- ------------------------------------------------------------
-- 6) GÖREV TAMAMLA — zincir adımı (reviewer_1→reviewer_2) KORUNUR;
--    koşu bitişinde gerçek bitiş durumu + sayaçlar:
--      * kısmen/tamamı başarılı koşu → 'completed'
--      * BÜTÜN görevler başarısız → 'failed'
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
-- 7) YENİDEN KUYAĞA AL (hata geri çekilmesi) — 133 davranışı korunur.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.requeue_bulk_gate_task(
  p_task_id uuid,
  p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_attempt integer;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required.';
  END IF;

  UPDATE public.admin_bulk_gate_tasks
  SET
    status = 'pending',
    error_code = p_error_code,
    error_message = p_error_message,
    completed_at = NULL,
    claimed_by = NULL,
    lease_expires_at = NULL
  WHERE id = p_task_id
  RETURNING attempt_count INTO v_attempt;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bulk task not found.';
  END IF;

  RETURN jsonb_build_object(
    'task_id', p_task_id,
    'status', 'pending',
    'attempt_count', v_attempt
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.requeue_bulk_gate_task(uuid, text, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.requeue_bulk_gate_task(uuid, text, text)
  TO service_role;


-- ------------------------------------------------------------
-- 8) DURUM + SONUÇ LİSTESİ (salt-okunur) — 133 çıktısına EK olarak
--    her koşuya kendi görev sayaçları ilave edilir (koşu bazlı
--    izlenebilirlik; "yeniden dene" doğru koşuyu hedefler).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_bulk_gate_control_status(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_runs jsonb;
  v_tasks jsonb;
  v_counts jsonb;
  v_rows jsonb;
  v_items jsonb := '[]'::jsonb;
  v_row jsonb;
  v_group text;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.created_at DESC), '[]'::jsonb)
  INTO v_runs
  FROM (
    SELECT
      r.id,
      r.scope,
      r.filter_spec,
      r.gates,
      r.model,
      r.status,
      r.stop_requested,
      r.planned_candidate_count,
      r.planned_task_count,
      r.planned_model_call_count,
      r.cost_estimate_status,
      r.cost_estimate_minor_units,
      r.cost_currency,
      r.created_by,
      r.created_at,
      r.started_at,
      r.stopped_at,
      (-- Koşu bazlı görev sayaçları
        SELECT jsonb_build_object(
          'pending', count(*) FILTER (WHERE t.status = 'pending'),
          'running', count(*) FILTER (WHERE t.status = 'running'),
          'completed', count(*) FILTER (WHERE t.status = 'completed'),
          'failed', count(*) FILTER (WHERE t.status = 'failed'),
          'skipped', count(*) FILTER (WHERE t.status = 'skipped')
        )
        FROM public.admin_bulk_gate_tasks t
        WHERE t.bulk_run_id = r.id
      ) AS run_task_counts
    FROM public.admin_bulk_gate_runs r
    WHERE r.batch_id = p_batch_id
    ORDER BY r.created_at DESC
    LIMIT 5
  ) x;

  SELECT coalesce(jsonb_agg(x ORDER BY x.created_at DESC), '[]'::jsonb)
  INTO v_tasks
  FROM (
    SELECT
      t.id,
      t.bulk_run_id,
      t.staging_question_id,
      t.candidate_position,
      t.gate_key,
      t.gate_role,
      t.status,
      t.attempt_count,
      t.gate_run_id,
      t.error_code,
      t.error_message,
      t.created_at,
      t.started_at,
      t.completed_at
    FROM public.admin_bulk_gate_tasks t
    JOIN public.admin_bulk_gate_runs r
      ON r.id = t.bulk_run_id
    WHERE r.batch_id = p_batch_id
    ORDER BY t.created_at DESC
    LIMIT 500
  ) x;

  SELECT jsonb_build_object(
    'pending', count(*) FILTER (WHERE t.status = 'pending'),
    'running', count(*) FILTER (WHERE t.status = 'running'),
    'completed', count(*) FILTER (WHERE t.status = 'completed'),
    'failed', count(*) FILTER (WHERE t.status = 'failed'),
    'skipped', count(*) FILTER (WHERE t.status = 'skipped')
  )
  INTO v_counts
  FROM public.admin_bulk_gate_tasks t
  JOIN public.admin_bulk_gate_runs r
    ON r.id = t.bulk_run_id
  WHERE r.batch_id = p_batch_id;

  v_rows := private.bulk_gate_candidate_rows(p_batch_id);

  FOR v_row IN SELECT value FROM jsonb_array_elements(v_rows) AS t(value)
  LOOP
    v_group := private.bulk_gate_classify(v_row);
    v_items := v_items || jsonb_build_object(
      'staging_question_id', v_row -> 'staging_question_id',
      'candidate_position', v_row -> 'candidate_position',
      'client_question_id', v_row -> 'client_question_id',
      'staging_status', v_row -> 'staging_status',
      'grade_level', v_row -> 'grade_level',
      'subject_name', v_row -> 'subject_name',
      'topic_name', v_row -> 'topic_name',
      'subtopic_name', v_row -> 'subtopic_name',
      'outcome_code', v_row -> 'outcome_code',
      'question_text', v_row -> 'question_text',
      'options', v_row -> 'options',
      'gates', v_row -> 'gates',
      'readiness', v_row -> 'readiness',
      'bulk', v_row -> 'bulk',
      'group', v_group
    );
  END LOOP;

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'runs', v_runs,
    'tasks', v_tasks,
    'task_counts', v_counts,
    'candidates', v_items
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.get_bulk_gate_control_status(uuid)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.get_bulk_gate_control_status(uuid)
  TO authenticated, service_role;


COMMIT;
