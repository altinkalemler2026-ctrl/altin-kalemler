-- ============================================================
-- 154_bulk_gate_run_cancel.sql — AK-BULK-CANCEL-154A TASLAK (UYGULANMAMIŞTIR)
--
-- Amaç (AK-BULK-QV-COMPLETE-01 §2 / AK-QUESTION-PIPELINE-UX-01 §3.1):
--   Durdurulmuş ('stopped', stop_requested=true) bir toplu denetim koşusunun
--   HENÜZ BAŞLAMAMIŞ (pending) görevlerini tek atomik işlemde terminal
--   'skipped' + error_code='run_cancelled' durumuna çekmek; böylece
--   uq_admin_bulk_gate_tasks_pending_running (135) kısmi unique index'inin
--   (staging_question_id, gate_key, gate_role) yarısındaki pending kilidini
--   çözmek. Böylece aynı adaylar için YENİ bir koşu (ör. EVREN) planlanabilir.
--
-- Şema DEĞİŞİKLİĞİ YOKTUR (en küçük çözüm):
--   * admin_bulk_gate_tasks.status CHECK zaten 'skipped' içerir (133:98-99);
--     'skipped', 135 kısmi unique index predikatı DIŞINDADIR → kilit çözülür.
--   * runs CHECK'e 'cancelled' EKLENMEZ; koşu 'stopped' kalır, iptal bilgisi
--     görev satırlarında + admin_audit_log'da tutulur (geçmiş silinmez).
--
-- Güvenlik sözleşmesi (fail-closed):
--   G1) Yetki: service_role VEYA ai.manage VEYA questions.approve
--       (start/stop/retry ile BİREBİR aynı guard; yetki genişletilmez).
--   G2) Yalnız açıkça hedeflenen ve DURMUŞ koşu: run FOR UPDATE kilitlenir;
--       stop_requested=false VEYA status<>'stopped' → istisna. planned/
--       running/completed/failed koşular iptal EDİLEMEZ (resume için zaten
--       set_bulk_gate_control_stop(false) vardır).
--   G3) Aktif iş koruması: koşuda status='running' görev VEYA taze
--       lease_expires_at (> now()) VEYA pending-olduğu-hâlde claimed_by
--       dolu görev varsa HİÇBİR satır değişmeden istisna (yarış yok).
--   G4) Yalnız pending görevler değişir; completed/failed/skipped dokunulmaz.
--       attempt_count, started_at, gate_run_id, content_snapshot, model
--       provenance'ı KORUNUR (silinmez); error_message önceki hatayı
--       taşıyarak genişletilir.
--   G5) İdempotent: ikinci çağrı 0 satır iptal eder, YENİ audit satırı
--       YAZMAZ, {"status":"already_cancelled"} döner.
--   G6) Audit: iptal gerçekleştiyse (v_cancelled>0) admin_audit_log'a
--       aktörlü TEK satır ('bulk_gate_run.cancel'); tekrar denemesinde
--       audit çoğalmaz.
--
-- DENEME SAYACI SÖZLEŞMESİ (Matematik aday #69 vakası — sessiz sıfırlama YOK):
--   Eski görev satırları attempt_count=2 (ör.) ile 'skipped' olarak KORUNUR.
--   start_bulk_gate_control YENİ görev oluştururken aynı (aday, kapı, rol)
--   için 'run_cancelled' ile iptal edilmiş görevlerin max attempt_count'unu
--   yeni göreve TAŞIR (2 ile sınırlı → en az 1 taze deneme kalır, 3 değil).
--   Böylece transport hatasıyla yanmış denemeler yeni koşuda sessizce
--   yeniden tam hakka dönüşmez; 134 claim Sözleşmesi (attempt<3 penceresi)
--   taşınmış sayaçla da doğru çalışır.
--
-- Bu dosya yalnız TASLAK + disposable QA provası içindir.
-- Canlıya kullanıcı onayı ve tek onay paketi olmadan uygulanmaz.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1) İPTAL — cancel_bulk_gate_run
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_bulk_gate_run(
  p_bulk_run_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run record;
  v_active integer := 0;
  v_cancelled integer := 0;
  v_completed integer := 0;
  v_failed integer := 0;
  v_skipped_other integer := 0;
  v_carry_candidates jsonb := '[]'::jsonb;
  v_audit_id uuid;
BEGIN
  -- G1) Yetki (start/stop/retry ile birebir)
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  -- G2) Yalnız açıkça hedeflenmiş, durmuş koşu
  SELECT r.status, r.stop_requested, r.batch_id, r.model, r.gates
  INTO v_run
  FROM public.admin_bulk_gate_runs r
  WHERE r.id = p_bulk_run_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bulk run not found.';
  END IF;

  IF NOT COALESCE(v_run.stop_requested, false)
     OR v_run.status <> 'stopped'
  THEN
    RAISE EXCEPTION
      'Only an explicitly stopped bulk run can be cancelled. Current status: %',
      v_run.status;
  END IF;

  -- G3) Aktif iş / taze kiralama koruması (fail-closed, atomik ön kontrol)
  SELECT count(DISTINCT t.id)
  INTO v_active
  FROM public.admin_bulk_gate_tasks t
  WHERE t.bulk_run_id = p_bulk_run_id
    AND (t.status = 'running'
         OR t.lease_expires_at > now()
         OR (t.status = 'pending' AND t.claimed_by IS NOT NULL));

  IF v_active > 0 THEN
    RAISE EXCEPTION
      'Bulk run has % active or leased task(s); cancel is blocked (fail-closed).',
      v_active;
  END IF;

  -- Deneme taşıma kanıtı: iptal edilecek pending görevler arasındaki
  -- önceki deneme izleri (audit çıktısına yazılır; satır silinmez).
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'staging_question_id', t.staging_question_id,
    'gate_key', t.gate_key,
    'gate_role', t.gate_role,
    'prior_attempt_count', t.attempt_count
  ) ORDER BY t.candidate_position, t.gate_key), '[]'::jsonb)
  INTO v_carry_candidates
  FROM public.admin_bulk_gate_tasks t
  WHERE t.bulk_run_id = p_bulk_run_id
    AND t.status = 'pending'
    AND t.attempt_count > 0;

  -- G4) Yalnız pending görevler terminal 'skipped' olur; geçmiş korunur
  UPDATE public.admin_bulk_gate_tasks t
  SET
    status = 'skipped',
    error_code = 'run_cancelled',
    error_message =
      trim(both ' | ' from
        coalesce(t.error_message, '')
        || CASE WHEN t.error_code IS NOT NULL
                THEN ' | prior_error_code=' || t.error_code
                ELSE '' END
        || CASE WHEN t.attempt_count > 0
                THEN ' | prior_attempts=' || t.attempt_count::text
                ELSE '' END
        || ' | run_cancelled'
        || coalesce(' (' || btrim(p_reason) || ')', '')
      ),
    completed_at = now(),
    claimed_by = NULL,
    lease_expires_at = NULL
  WHERE t.bulk_run_id = p_bulk_run_id
    AND t.status = 'pending';

  GET DIAGNOSTICS v_cancelled = ROW_COUNT;

  -- G5) İdempotent tekrar: 0 iptal → audit YOK, durum bildirimi yeterli
  IF v_cancelled = 0 THEN
    SELECT
      count(*) FILTER (WHERE status = 'completed'),
      count(*) FILTER (WHERE status = 'failed'),
      count(*) FILTER (WHERE status = 'skipped'
                       AND error_code IS DISTINCT FROM 'run_cancelled')
    INTO v_completed, v_failed, v_skipped_other
    FROM public.admin_bulk_gate_tasks
    WHERE bulk_run_id = p_bulk_run_id;

    RETURN jsonb_build_object(
      'status', 'already_cancelled',
      'bulk_run_id', p_bulk_run_id,
      'cancelled_task_count', 0,
      'completed_task_count', v_completed,
      'failed_task_count', v_failed,
      'other_skipped_task_count', v_skipped_other,
      'run_status', v_run.status
    );
  END IF;

  SELECT
    count(*) FILTER (WHERE status = 'completed'),
    count(*) FILTER (WHERE status = 'failed'),
    count(*) FILTER (WHERE status = 'skipped'
                     AND error_code IS DISTINCT FROM 'run_cancelled')
  INTO v_completed, v_failed, v_skipped_other
  FROM public.admin_bulk_gate_tasks
  WHERE bulk_run_id = p_bulk_run_id;

  -- G6) Audit — yalnız gerçek iptalde, aktörlü, tek satır
  INSERT INTO public.admin_audit_log (
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    before_data,
    after_data
  )
  VALUES (
    auth.uid(),
    'bulk_gate_run.cancel',
    'admin_bulk_gate_run',
    p_bulk_run_id,
    jsonb_build_object(
      'run_status', v_run.status,
      'stop_requested', v_run.stop_requested,
      'batch_id', v_run.batch_id,
      'model', v_run.model
    ),
    jsonb_build_object(
      'cancelled_task_count', v_cancelled,
      'preserved_completed_task_count', v_completed,
      'preserved_failed_task_count', v_failed,
      'other_skipped_task_count', v_skipped_other,
      'tasks_with_prior_attempts', v_carry_candidates,
      'reason', NULLIF(btrim(coalesce(p_reason, '')), ''),
      'run_status_after', v_run.status
    )
  )
  RETURNING id INTO v_audit_id;

  RETURN jsonb_build_object(
    'status', 'cancelled',
    'bulk_run_id', p_bulk_run_id,
    'cancelled_task_count', v_cancelled,
    'preserved_completed_task_count', v_completed,
    'preserved_failed_task_count', v_failed,
    'other_skipped_task_count', v_skipped_other,
    'tasks_with_prior_attempts', v_carry_candidates,
    'audit_id', v_audit_id,
    'run_status', v_run.status
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.cancel_bulk_gate_run(uuid, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.cancel_bulk_gate_run(uuid, text)
  TO authenticated, service_role;


-- ------------------------------------------------------------
-- 2) BAŞLAT — 135 gövdesi KORUNUR; TEK delta: DENEME TAŞIMA (G7).
--    'run_cancelled' ile iptal edilmiş eski görevlerin max attempt_count'u
--    yeni göreve taşınır (2 ile sınırlı). Sessiz tam hak yeniden verme YOK.
--    Bu, 135'teki gövdenin birebir kopyası + attempt_count alanıdır.
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
  v_carry_attempts integer;
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
    v_gate := (v_task ->> 'gate_key');
    v_role := (v_task ->> 'gate_role');
    v_need_start := COALESCE((v_task ->> 'need_start')::boolean, false);
    v_gate_run_id := (v_task ->> 'gate_run_id')::uuid;
    v_snapshot := v_task -> 'content_snapshot';
    v_position := (v_task ->> 'candidate_position')::integer;

    -- DENEME TAŞIMA (G7): aynı (aday, kapı, rol) için 'run_cancelled'
    -- terminal olmuş görevlerin en yüksek attempt_count'u yeni göreve
    -- taşınır; 2 ile sınırlanır (yeni görev en az 1 taze deneme alır,
    -- asla 3 tam hak değil). Geçmiş satırlar olduğu gibi kalır.
    SELECT LEAST(coalesce(max(c.attempt_count), 0), 2)
    INTO v_carry_attempts
    FROM public.admin_bulk_gate_tasks c
    WHERE c.staging_question_id = v_staging
      AND c.gate_key = v_gate
      AND c.gate_role = v_role
      AND c.status = 'skipped'
      AND c.error_code = 'run_cancelled';

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
        attempt_count,
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
        v_carry_attempts,
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

COMMIT;
