-- ============================================================
-- 140_wp08_137_sozlesme_duzeltmeleri.sql
-- Altın Kalemler — WP-02 uzlaştırma: 137 sözleşme düzeltmelerinin
-- kalıcı dosya temsili
--
-- AMAÇ: 137'deki fonksiyonlar yerel DB'de gerçek şema kolon
-- adlarıyla (request_status, requested_question_count,
-- ai_generation_spec) düzeltilmişti; bu düzeltmeler geçici kanıt
-- dosyalarındaydı. Bu migration, DB'deki güncel ve çalışan tanımları
-- KALICI dosyaya taşır (tarihî 137 dosyası DEĞİŞTİRİLMEDİ).
--
-- Kanıt kaynağı: canlı DB pg_get_functiondef çıktısı (25 Ekim 2026),
-- reality-checker tur3 (ses_e8ca8aca3ffeWQB1WDCnu3WNOd) bizzat
-- yeniden koşumla doğruladı. Pozitif zincir provası PASS.
--
-- Bu dosya uygulandığında DB'deki tanımlar ZATEN aynıdır
-- (idempotent CREATE OR REPLACE); yalnız dosya-DB uzlaştırmasını
-- tamamlar. History kaydı için ayrıca kullanıcı onaylı repair
-- işlemi gerekir (WP-02 planı).
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.approve_question_generation_request(p_request_id uuid, p_dispatch_mode text DEFAULT 'internal_ai'::text, p_producer_type text DEFAULT 'internal_ai'::text, p_producer_config jsonb DEFAULT '{}'::jsonb, p_requested_quantity integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_req public.question_generation_requests%ROWTYPE;
  v_dispatch_id uuid;
  v_job_id uuid;
  v_qty integer;
  v_now timestamptz := now();
  v_actor uuid;
  v_scope jsonb;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  v_actor := auth.uid();

  SELECT *
  INTO v_req
  FROM public.question_generation_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Talep bulunamadi.';
  END IF;

  IF v_req.request_status <> 'pending_approval' THEN
    RAISE EXCEPTION 'Yalniz pending_approval durumundaki talep onaylanabilir.';
  END IF;

  IF p_dispatch_mode NOT IN ('internal_ai', 'external_batch') THEN
    RAISE EXCEPTION 'Gecersiz dispatch_mode.';
  END IF;
  IF p_producer_type NOT IN ('internal_ai', 'external_batch') THEN
    RAISE EXCEPTION 'Gecersiz producer_type.';
  END IF;

  v_qty := COALESCE(p_requested_quantity, v_req.requested_question_count);
  IF v_qty IS NULL OR v_qty <= 0 THEN
    RAISE EXCEPTION 'Gecerli bir talep miktari gerekli.';
  END IF;

  UPDATE public.question_generation_requests
  SET request_status = 'approved',
      approved_by = v_actor,
      approved_at = v_now,
      dispatch_mode = p_dispatch_mode,
      producer_type = p_producer_type,
      producer_config = COALESCE(p_producer_config, '{}'::jsonb),
      updated_at = v_now
  WHERE id = p_request_id;

  v_scope := COALESCE(v_req.ai_generation_spec, '{}'::jsonb);

  SELECT id INTO v_dispatch_id
  FROM public.ai_question_generation_dispatches
  WHERE generation_request_id = p_request_id
    AND status IN ('created', 'dispatched', 'processing')
  LIMIT 1;

  IF v_dispatch_id IS NULL THEN
    INSERT INTO public.ai_question_generation_dispatches (
      generation_request_id, vault_id, status, requested_quantity,
      dispatched_by, dispatched_at, producer_type, producer_config, input_snapshot
    ) VALUES (
      p_request_id, v_req.vault_id, 'dispatched', v_qty,
      v_actor, v_now, p_producer_type, COALESCE(p_producer_config, '{}'::jsonb),
      jsonb_build_object(
        'request_id', p_request_id,
        'vault_id', v_req.vault_id,
        'requested_question_count', v_req.requested_question_count,
        'scope', v_scope
      )
    )
    RETURNING id INTO v_dispatch_id;
  ELSE
    UPDATE public.ai_question_generation_dispatches
    SET status = 'dispatched',
        dispatched_by = COALESCE(dispatched_by, v_actor),
        dispatched_at = COALESCE(dispatched_at, v_now),
        requested_quantity = GREATEST(requested_quantity, v_qty),
        producer_type = p_producer_type,
        producer_config = COALESCE(p_producer_config, '{}'::jsonb),
        updated_at = v_now
    WHERE id = v_dispatch_id;
  END IF;

  IF p_dispatch_mode = 'internal_ai' THEN
    SELECT id INTO v_job_id
    FROM public.ai_jobs
    WHERE generation_request_id = p_request_id
      AND status IN ('queued', 'processing')
    LIMIT 1;

    IF v_job_id IS NULL THEN
      INSERT INTO public.ai_jobs (
        job_type, generation_spec_id, competition_generation_request_id,
        competition_factory_dispatch_id, generation_request_id, factory_dispatch_id,
        requested_quantity, producer_type, producer_config,
        status, attempt_count, max_attempts, input_data
      ) VALUES (
        'question_generation', NULL, NULL,
        NULL, p_request_id, v_dispatch_id,
        v_qty, p_producer_type, COALESCE(p_producer_config, '{}'::jsonb),
        'queued', 0, 3,
        jsonb_build_object(
          'source', 'vault_factory',
          'generation_request_id', p_request_id,
          'vault_id', v_req.vault_id,
          'factory_dispatch_id', v_dispatch_id,
          'requested_quantity', v_qty
        )
      )
      RETURNING id INTO v_job_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', p_request_id,
    'status', 'approved',
    'dispatch_mode', p_dispatch_mode,
    'producer_type', p_producer_type,
    'dispatch_id', v_dispatch_id,
    'ai_job_id', v_job_id,
    'requested_quantity', v_qty
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.build_vault_ai_factory_job(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_req public.question_generation_requests%ROWTYPE;
  v_dispatch_id uuid;
  v_job_id uuid;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT private.current_user_has_admin_permission('ai.manage')
  THEN
    RAISE EXCEPTION 'AI management permission required.';
  END IF;

  SELECT *
  INTO v_req
  FROM public.question_generation_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Talep bulunamadi.';
  END IF;

  IF v_req.request_status <> 'approved' THEN
    RAISE EXCEPTION 'build_vault_ai_factory_job yalniz approved talep icin cagrilabilir.';
  END IF;

  IF v_req.dispatch_mode = 'external_batch' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'mode', 'external_batch',
      'note', 'Dahili ai_jobs olusturulmadi; harici uretim yolu kullanilir.'
    );
  END IF;

  SELECT id INTO v_dispatch_id
  FROM public.ai_question_generation_dispatches
  WHERE generation_request_id = p_request_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_dispatch_id IS NULL THEN
    INSERT INTO public.ai_question_generation_dispatches (
      generation_request_id,
      vault_id,
      status,
      requested_quantity,
      producer_type,
      input_snapshot
    ) VALUES (
      p_request_id,
      v_req.vault_id,
      'dispatched',
      COALESCE(v_req.requested_question_count, 0),
      COALESCE(v_req.producer_type, 'internal_ai'),
      jsonb_build_object('source', 'build_vault_ai_factory_job')
    )
    RETURNING id INTO v_dispatch_id;
  END IF;

  SELECT id INTO v_job_id
  FROM public.ai_jobs
  WHERE generation_request_id = p_request_id
    AND status IN ('queued', 'processing')
  LIMIT 1;

  IF v_job_id IS NULL THEN
    INSERT INTO public.ai_jobs (
      job_type,
      generation_spec_id,
      competition_factory_dispatch_id,
      generation_request_id,
      factory_dispatch_id,
      requested_quantity,
      producer_type,
      producer_config,
      status,
      attempt_count,
      max_attempts,
      input_data
    ) VALUES (
      'question_generation',
      NULL,
      NULL,
      p_request_id,
      v_dispatch_id,
      COALESCE(v_req.requested_question_count, 0),
      COALESCE(v_req.producer_type, 'internal_ai'),
      COALESCE(v_req.producer_config, '{}'::jsonb),
      'queued',
      0,
      3,
      jsonb_build_object(
        'source', 'build_vault_ai_factory_job',
        'generation_request_id', p_request_id,
        'vault_id', v_req.vault_id,
        'factory_dispatch_id', v_dispatch_id
      )
    )
    RETURNING id INTO v_job_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', p_request_id,
    'dispatch_id', v_dispatch_id,
    'ai_job_id', v_job_id,
    'status', 'queued'
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.record_vault_generation_batch_progress(p_generation_request_id uuid, p_batch_id uuid, p_received integer DEFAULT 0, p_valid integer DEFAULT 0, p_invalid integer DEFAULT 0, p_inserted integer DEFAULT 0, p_duplicate integer DEFAULT 0, p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_dispatch_id uuid;
  v_req public.question_generation_requests%ROWTYPE;
  v_now timestamptz := now();
  v_ins_total integer;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT private.current_user_has_admin_permission('ai.manage')
  THEN
    RAISE EXCEPTION 'AI worker or AI management permission required.';
  END IF;

  SELECT *
  INTO v_req
  FROM public.question_generation_requests
  WHERE id = p_generation_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Talep bulunamadi.';
  END IF;

  SELECT id INTO v_dispatch_id
  FROM public.ai_question_generation_dispatches
  WHERE generation_request_id = p_generation_request_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_dispatch_id IS NOT NULL THEN
    UPDATE public.ai_question_generation_dispatches
    SET processed_quantity = COALESCE(processed_quantity, 0) + COALESCE(p_received, 0),
        inserted_quantity  = COALESCE(inserted_quantity, 0)  + COALESCE(p_inserted, 0),
        invalid_quantity   = COALESCE(invalid_quantity, 0)   + COALESCE(p_invalid, 0),
        duplicate_quantity = COALESCE(duplicate_quantity, 0) + COALESCE(p_duplicate, 0),
        status = COALESCE(p_status, status),
        updated_at = v_now
    WHERE id = v_dispatch_id;
  END IF;

  IF p_batch_id IS NOT NULL THEN
    UPDATE public.candidate_question_batches
    SET generation_request_id = COALESCE(generation_request_id, p_generation_request_id)
    WHERE id = p_batch_id
      AND (generation_request_id IS NULL OR generation_request_id = p_generation_request_id);
  END IF;

  IF v_dispatch_id IS NOT NULL THEN
    SELECT inserted_quantity INTO v_ins_total
    FROM public.ai_question_generation_dispatches
    WHERE id = v_dispatch_id;

    UPDATE public.question_generation_requests
    SET request_status = CASE
          WHEN COALESCE(v_ins_total, 0) >= COALESCE(v_req.requested_question_count, 0)
            THEN 'reviewing'
          ELSE request_status
        END,
        generated_candidate_count = COALESCE(generated_candidate_count, 0) + COALESCE(p_inserted, 0),
        updated_at = v_now
    WHERE id = p_generation_request_id
      AND request_status IN ('approved', 'generating');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'generation_request_id', p_generation_request_id,
    'batch_id', p_batch_id,
    'dispatch_id', v_dispatch_id
  );
END;
$function$
;


COMMIT;
