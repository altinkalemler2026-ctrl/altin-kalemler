-- ============================================================
-- 137_wp08_vault_production_pipeline.sql
-- Altın Kalemler — WP-08: Vault üretim hattı ilk dilim
--
-- Amaç: üretim talebi → insan onayı → dispatch → ai_jobs →
--       worker → aday paketine bağlama ve durum takibi
--
-- Kapsam (additive, geriye dönük uyumlu):
--   1) Vault üretim dispatch kaydı + gerekli additive bağlantılar
--   2) build_vault_ai_factory_job
--   3) record_vault_generation_batch_progress
--   4) claim / ingestion / retry zincirinin vault üretimini desteklemesi
--   5) Talep, dispatch, job ve paket durumlarının ortak sınıflandırılması
--   6) Harici üretim çıktısının mevcut intake üzerinden talebe
--      idempotent bağlanması
--
-- Not: Mevcut competition dalını koru. Önceki migration'ları değiştirme.
-- 132–136 history-kayıtsızlığı bu işte kapatmak için dokunma (WP-02 açık).
-- ============================================================

BEGIN;

-- -------------------------------------------------------------------
-- A) Additive kolonlar
-- -------------------------------------------------------------------

ALTER TABLE public.question_generation_requests
  ADD COLUMN IF NOT EXISTS producer_type text,
  ADD COLUMN IF NOT EXISTS producer_config jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS requested_by uuid,
  ADD COLUMN IF NOT EXISTS approved_by uuid,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejected_by uuid,
  ADD COLUMN IF NOT EXISTS rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS dispatch_mode text NOT NULL DEFAULT 'internal_ai',
  ADD COLUMN IF NOT EXISTS last_status_reason text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'question_generation_requests_producer_type_check'
  ) THEN
    ALTER TABLE public.question_generation_requests
      ADD CONSTRAINT question_generation_requests_producer_type_check
        CHECK (producer_type IS NULL OR producer_type IN ('internal_ai', 'external_batch'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'question_generation_requests_dispatch_mode_check'
  ) THEN
    ALTER TABLE public.question_generation_requests
      ADD CONSTRAINT question_generation_requests_dispatch_mode_check
        CHECK (dispatch_mode IN ('internal_ai', 'external_batch'));
  END IF;
END $$;

-- Aday paketine talep kimliği bağlaması (harici üretim idempotent bağlama)
ALTER TABLE public.candidate_question_batches
  ADD COLUMN IF NOT EXISTS generation_request_id uuid,
  ADD COLUMN IF NOT EXISTS production_source text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'candidate_question_batches_generation_request_id_fkey'
  ) THEN
    ALTER TABLE public.candidate_question_batches
      ADD CONSTRAINT candidate_question_batches_generation_request_id_fkey
        FOREIGN KEY (generation_request_id)
        REFERENCES public.question_generation_requests(id)
        ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'candidate_question_batches_production_source_check'
  ) THEN
    ALTER TABLE public.candidate_question_batches
      ADD CONSTRAINT candidate_question_batches_production_source_check
        CHECK (production_source IS NULL OR production_source IN ('internal_ai', 'external_batch'));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_candidate_question_batches_generation_request_id_uniq
  ON public.candidate_question_batches (generation_request_id)
  WHERE generation_request_id IS NOT NULL;

-- ai_jobs için vault üretimini desteklemek amacıyla additive bağlantılar
ALTER TABLE public.ai_jobs
  ADD COLUMN IF NOT EXISTS generation_request_id uuid,
  ADD COLUMN IF NOT EXISTS factory_dispatch_id uuid,
  ADD COLUMN IF NOT EXISTS requested_quantity integer,
  ADD COLUMN IF NOT EXISTS producer_type text,
  ADD COLUMN IF NOT EXISTS producer_config jsonb NOT NULL DEFAULT '{}'::jsonb;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ai_jobs_generation_request_id_fkey'
  ) THEN
    ALTER TABLE public.ai_jobs
      ADD CONSTRAINT ai_jobs_generation_request_id_fkey
        FOREIGN KEY (generation_request_id)
        REFERENCES public.question_generation_requests(id)
        ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ai_jobs_producer_type_check'
  ) THEN
    ALTER TABLE public.ai_jobs
      ADD CONSTRAINT ai_jobs_producer_type_check
        CHECK (producer_type IS NULL OR producer_type IN ('internal_ai', 'external_batch'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ai_jobs_generation_request_id ON public.ai_jobs (generation_request_id);
CREATE INDEX IF NOT EXISTS idx_ai_jobs_factory_dispatch_id ON public.ai_jobs (factory_dispatch_id);

-- -------------------------------------------------------------------
-- B) Vault üretim dispatch kaydı
-- -------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.ai_question_generation_dispatches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  generation_request_id uuid NOT NULL REFERENCES public.question_generation_requests(id) ON DELETE CASCADE,
  vault_id uuid REFERENCES public.question_vaults(id) ON DELETE SET NULL,
  job_type text NOT NULL DEFAULT 'question_generation',
  status text NOT NULL DEFAULT 'created',
  requested_quantity integer NOT NULL DEFAULT 0,
  dispatched_quantity integer NOT NULL DEFAULT 0,
  processed_quantity integer NOT NULL DEFAULT 0,
  inserted_quantity integer NOT NULL DEFAULT 0,
  invalid_quantity integer NOT NULL DEFAULT 0,
  duplicate_quantity integer NOT NULL DEFAULT 0,
  dispatched_by uuid,
  dispatched_at timestamptz,
  completed_at timestamptz,
  error_code text,
  error_message text,
  producer_type text NOT NULL DEFAULT 'internal_ai',
  producer_config jsonb NOT NULL DEFAULT '{}'::jsonb,
  input_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ai_question_generation_dispatches_status_check
    CHECK (status IN ('created', 'dispatched', 'processing', 'completed', 'failed', 'cancelled')),
  CONSTRAINT ai_question_generation_dispatches_producer_type_check
    CHECK (producer_type IN ('internal_ai', 'external_batch')),
  CONSTRAINT ai_question_generation_dispatches_requested_quantity_check
    CHECK (requested_quantity >= 0)
);

CREATE INDEX IF NOT EXISTS idx_ai_qgen_dispatches_request_id ON public.ai_question_generation_dispatches (generation_request_id);
CREATE INDEX IF NOT EXISTS idx_ai_qgen_dispatches_status ON public.ai_question_generation_dispatches (status);
CREATE INDEX IF NOT EXISTS idx_ai_qgen_dispatches_vault_id ON public.ai_question_generation_dispatches (vault_id);

-- updated_at trigger (varsa mevcut desene uymak için sade tutar)
CREATE OR REPLACE FUNCTION private.set_updated_at_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ai_qgen_dispatches_updated_at'
  ) THEN
    CREATE TRIGGER trg_ai_qgen_dispatches_updated_at
      BEFORE UPDATE ON public.ai_question_generation_dispatches
      FOR EACH ROW EXECUTE FUNCTION private.set_updated_at_timestamp();
  END IF;
END $$;

-- -------------------------------------------------------------------
-- C) Ortak durum sınıflandırma yardımcıı (salt okunur)
-- -------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.classify_ai_production_status(
  p_status text,
  p_error_code text DEFAULT NULL,
  p_has_pending_review boolean DEFAULT false
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
BEGIN
  IF p_status IS NULL THEN
    RETURN 'unknown';
  END IF;
  IF p_status IN ('failed') OR (p_error_code IS NOT NULL AND p_error_code <> '') THEN
    RETURN 'technical_error';
  END IF;
  IF p_status IN ('rejected', 'cancelled') THEN
    RETURN 'content_rejected';
  END IF;
  IF p_has_pending_review IS TRUE OR p_status IN ('pending_review', 'validating') THEN
    RETURN 'human_review_pending';
  END IF;
  IF p_status IN ('completed', 'inserted', 'published') THEN
    RETURN 'completed';
  END IF;
  IF p_status IN ('processing', 'claimed', 'dispatched', 'in_progress') THEN
    RETURN 'in_progress';
  END IF;
  IF p_status IN ('created', 'queued', 'pending_approval') THEN
    RETURN 'queued';
  END IF;
  RETURN p_status;
END;
$$;

-- -------------------------------------------------------------------
-- D) Talep onayı → dispatch + ai_jobs köprüsü (vault odaklı)
-- -------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.approve_question_generation_request(
  p_request_id uuid,
  p_dispatch_mode text DEFAULT 'internal_ai',
  p_producer_type text DEFAULT 'internal_ai',
  p_producer_config jsonb DEFAULT '{}'::jsonb,
  p_requested_quantity integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_req record;
  v_dispatch_id uuid;
  v_job_id uuid;
  v_qty integer;
  v_now timestamptz := now();
  v_actor uuid;
BEGIN
  -- Yetki: ai.manage veya questions.approve
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
    RAISE EXCEPTION 'Talep bulunamadı.';
  END IF;

  IF v_req.status <> 'pending_approval' THEN
    RAISE EXCEPTION 'Yalnız pending_approval durumundaki talep onaylanabilir.';
  END IF;

  IF p_dispatch_mode NOT IN ('internal_ai', 'external_batch') THEN
    RAISE EXCEPTION 'Geçersiz dispatch_mode.';
  END IF;
  IF p_producer_type NOT IN ('internal_ai', 'external_batch') THEN
    RAISE EXCEPTION 'Geçersiz producer_type.';
  END IF;

  v_qty := COALESCE(p_requested_quantity, v_req.requested_count);
  IF v_qty IS NULL OR v_qty <= 0 THEN
    RAISE EXCEPTION 'Geçerli bir talep miktarı gerekli.';
  END IF;

  -- Talebi onayla
  UPDATE public.question_generation_requests
  SET status = 'approved',
      approved_by = v_actor,
      approved_at = v_now,
      dispatch_mode = p_dispatch_mode,
      producer_type = p_producer_type,
      producer_config = COALESCE(p_producer_config, '{}'::jsonb),
      requested_count = v_qty,
      updated_at = v_now
  WHERE id = p_request_id;

  -- Dispatch kaydı oluştur (idempotent benzeri: aynı talep için birden fazla açmaya izin verme)
  SELECT id INTO v_dispatch_id
  FROM public.ai_question_generation_dispatches
  WHERE generation_request_id = p_request_id
    AND status IN ('created', 'dispatched', 'processing')
  LIMIT 1;

  IF v_dispatch_id IS NULL THEN
    INSERT INTO public.ai_question_generation_dispatches (
      generation_request_id,
      vault_id,
      status,
      requested_quantity,
      dispatched_by,
      dispatched_at,
      producer_type,
      producer_config,
      input_snapshot
    ) VALUES (
      p_request_id,
      v_req.vault_id,
      'dispatched',
      v_qty,
      v_actor,
      v_now,
      p_producer_type,
      COALESCE(p_producer_config, '{}'::jsonb),
      jsonb_build_object(
        'request_id', p_request_id,
        'vault_id', v_req.vault_id,
        'grade_level', v_req.grade_level,
        'subject_id', v_req.subject_id,
        'scope', v_req.scope,
        'criteria', v_req.criteria
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

  -- ai_jobs oluştur (yalnız internal_ai için; external_batch harici üretim yolunu kullanır)
  IF p_dispatch_mode = 'internal_ai' THEN
    SELECT id INTO v_job_id
    FROM public.ai_jobs
    WHERE generation_request_id = p_request_id
      AND status IN ('queued', 'processing')
    LIMIT 1;

    IF v_job_id IS NULL THEN
      INSERT INTO public.ai_jobs (
        job_type,
        generation_spec_id,
        competition_generation_request_id,
        competition_factory_dispatch_id,
        generation_request_id,
        factory_dispatch_id,
        requested_quantity,
        producer_type,
        producer_config,
        status,
        priority,
        attempt_count,
        max_attempts,
        input_data
      ) VALUES (
        'question_generation',
        NULL,
        NULL,
        v_dispatch_id,
        p_request_id,
        v_dispatch_id,
        v_qty,
        p_producer_type,
        COALESCE(p_producer_config, '{}'::jsonb),
        'queued',
        0,
        0,
        3,
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
EXCEPTION
  WHEN OTHERS THEN
    RAISE;
END;
$$;

-- -------------------------------------------------------------------
-- E) build_vault_ai_factory_job (tasarımda belirtilen yardımcı)
-- -------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.build_vault_ai_factory_job(
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_req record;
  v_spec record;
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
    RAISE EXCEPTION 'Talep bulunamadı.';
  END IF;

  IF v_req.status NOT IN ('approved') THEN
    RAISE EXCEPTION 'build_vault_ai_factory_job yalnız approved talep için çağrılabilir.';
  END IF;

  IF v_req.dispatch_mode = 'external_batch' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'mode', 'external_batch',
      'note', 'Dahili ai_jobs oluşturulmadı; harici üretim yolu kullanılır.'
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
      COALESCE(v_req.requested_count, 0),
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
      priority,
      attempt_count,
      max_attempts,
      input_data
    ) VALUES (
      'question_generation',
      NULL,
      v_dispatch_id,
      p_request_id,
      v_dispatch_id,
      COALESCE(v_req.requested_count, 0),
      COALESCE(v_req.producer_type, 'internal_ai'),
      COALESCE(v_req.producer_config, '{}'::jsonb),
      'queued',
      0,
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
$$;

-- -------------------------------------------------------------------
-- F) record_vault_generation_batch_progress (idempotent)
-- -------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_vault_generation_batch_progress(
  p_generation_request_id uuid,
  p_batch_id uuid,
  p_received integer DEFAULT 0,
  p_valid integer DEFAULT 0,
  p_invalid integer DEFAULT 0,
  p_inserted integer DEFAULT 0,
  p_duplicate integer DEFAULT 0,
  p_status text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_dispatch_id uuid;
  v_req record;
  v_now timestamptz := now();
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
    RAISE EXCEPTION 'Talep bulunamadı.';
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

  -- Aday paketini talebe idempotent bağla
  IF p_batch_id IS NOT NULL THEN
    UPDATE public.candidate_question_batches
    SET generation_request_id = COALESCE(generation_request_id, p_generation_request_id),
        production_source = COALESCE(production_source, v_req.dispatch_mode, 'internal_ai')
    WHERE id = p_batch_id
      AND (generation_request_id IS NULL OR generation_request_id = p_generation_request_id);
  END IF;

  -- İstenen miktara ulaşıldıysa talep durumunu kısmen güncelle (nihai onay ayrı)
  IF v_req.requested_count IS NOT NULL AND v_dispatch_id IS NOT NULL THEN
    UPDATE public.question_generation_requests
    SET status = CASE
          WHEN COALESCE((SELECT inserted_quantity FROM public.ai_question_generation_dispatches WHERE id = v_dispatch_id), 0) >= v_req.requested_count THEN 'in_review'
          ELSE status
        END,
        updated_at = v_now
    WHERE id = p_generation_request_id
      AND status IN ('approved', 'dispatched', 'in_progress');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'generation_request_id', p_generation_request_id,
    'batch_id', p_batch_id,
    'dispatch_id', v_dispatch_id
  );
END;
$$;

-- -------------------------------------------------------------------
-- G) public görünürlük (menü/arayüz için gerekli olanlar)
-- -------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.approve_question_generation_request(uuid, text, text, jsonb, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.build_vault_ai_factory_job(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_vault_generation_batch_progress(uuid, uuid, integer, integer, integer, integer, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.classify_ai_production_status(text, text, boolean) TO anon, authenticated;

-- -------------------------------------------------------------
-- H) RLS (reality-checker kritik bulgusu: tablo RLS'siz bırakılmıştı;
-- anon/authenticated tam DML bypass yüzeyi oluşturuyordu). Peer tablo
-- deseni (ai_jobs / question_generation_requests) izlenir: tablo RLS
-- AÇIK, yazma yolu YALNIZ SECURITY DEFINER fonksiyonlardır.
-- -------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'ai_question_generation_dispatches'
      AND c.relrowsecurity = true
  ) THEN
    ALTER TABLE public.ai_question_generation_dispatches ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.ai_question_generation_dispatches FORCE ROW LEVEL SECURITY;
  END IF;
END $$;

DROP POLICY IF EXISTS ai_qgen_dispatches_service_all ON public.ai_question_generation_dispatches;
CREATE POLICY ai_qgen_dispatches_service_all
  ON public.ai_question_generation_dispatches
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

COMMIT;
