-- ============================================================
-- 138_wp08_vault_claim_support.sql
-- Altın Kalemler — WP-08: claim zincirine vault üretim dalı
--
-- 043 claim sözleşmesine ADDITIVE genişletme:
--   - Competition dalı BİREBİR korunur
--     (competition_factory_dispatch_id IS NOT NULL AND
--      generation_spec_id IS NOT NULL).
--   - Yeni vault dalı: generation_request_id + factory_dispatch_id
--     dolu ve competition_factory_dispatch_id NULL olan işler.
--   - Vault işinde generation_spec_id NULL geçerlidir (spec
--      competition dalı özelliğidir); result alanları korunur.
-- Claim sözleşmesi şeması geriye dönük uyumlu: yeni alanlar eklenir,
-- mevcut alanlar değişmez.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION private.claim_next_ai_generation_job(
  p_worker_name text,
  p_lease_seconds integer DEFAULT 300
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE

  v_job public.ai_jobs%ROWTYPE;

  v_claim_token uuid;

  v_now timestamptz;

  v_lease_expires_at timestamptz;

  v_is_vault_job boolean := false;

BEGIN

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT private.current_user_has_admin_permission('ai.manage')
  THEN

    RAISE EXCEPTION
      'AI worker or AI management permission required.';

  END IF;

  IF p_worker_name IS NULL
     OR btrim(p_worker_name) = ''
  THEN

    RAISE EXCEPTION
      'Worker name is required.';

  END IF;

  IF p_lease_seconds IS NULL
     OR p_lease_seconds < 30
     OR p_lease_seconds > 1800
  THEN

    RAISE EXCEPTION
      'Lease seconds must be between 30 and 1800.';

  END IF;

  v_now := now();

  -- =======================================================
  -- EXPIRED LEASE RECLAIM
  -- =======================================================

  UPDATE public.ai_jobs j
  SET
    status = 'queued',

    claimed_by = NULL,

    claim_token = NULL,

    claimed_at = NULL,

    lease_expires_at = NULL,

    heartbeat_at = NULL,

    output_data =
      COALESCE(
        output_data,
        '{}'::jsonb
      )
      ||
      jsonb_build_object(
        'last_worker_lease_expired_at',
        v_now
      ),

    updated_at =
      v_now

  WHERE j.job_type = 'question_generation'

    AND j.status = 'processing'

    AND j.claim_token IS NOT NULL

    AND j.lease_expires_at IS NOT NULL

    AND j.lease_expires_at <= v_now;


  -- =======================================================
  -- CLAIM
  -- Competition dalı (043, birebir korunur):
  --   competition_factory_dispatch_id IS NOT NULL
  --   AND generation_spec_id IS NOT NULL
  -- Vault dalı (138, additive):
  --   generation_request_id IS NOT NULL
  --   AND factory_dispatch_id IS NOT NULL
  --   AND competition_factory_dispatch_id IS NULL
  -- =======================================================

  SELECT j.*
  INTO v_job

  FROM public.ai_jobs j

  WHERE j.job_type = 'question_generation'

    AND j.status = 'queued'

    AND j.attempt_count < j.max_attempts

    AND (
      (
        j.competition_factory_dispatch_id IS NOT NULL
        AND j.generation_spec_id IS NOT NULL
      )
      OR
      (
        j.generation_request_id IS NOT NULL
        AND j.factory_dispatch_id IS NOT NULL
        AND j.competition_factory_dispatch_id IS NULL
      )
    )

  ORDER BY
    j.created_at ASC,
    j.id ASC

  FOR UPDATE SKIP LOCKED

  LIMIT 1;


  IF NOT FOUND THEN

    RETURN jsonb_build_object(
      'status',
      'empty',

      'job_available',
      false
    );

  END IF;

  v_is_vault_job :=
    v_job.competition_factory_dispatch_id IS NULL
    AND v_job.generation_request_id IS NOT NULL;

  v_claim_token :=
    gen_random_uuid();


  v_lease_expires_at :=
    v_now
    + make_interval(
        secs => p_lease_seconds
      );


  UPDATE public.ai_jobs
  SET
    status = 'processing',

    claimed_by = p_worker_name,

    claim_token = v_claim_token,

    claimed_at = v_now,

    heartbeat_at = v_now,

    lease_expires_at = v_lease_expires_at,

    started_at = COALESCE(started_at, v_now),

    completed_at = NULL,

    error_code = NULL,

    error_message = NULL,

    updated_at = v_now

  WHERE id = v_job.id

  RETURNING *
  INTO v_job;


  RETURN jsonb_build_object(
    'status', 'claimed',
    'job_available', true,
    'ai_job_id', v_job.id,
    'job_type', v_job.job_type,
    'generation_spec_id', v_job.generation_spec_id,
    'competition_generation_request_id', v_job.competition_generation_request_id,
    'competition_factory_dispatch_id', v_job.competition_factory_dispatch_id,
    'generation_request_id', v_job.generation_request_id,
    'factory_dispatch_id', v_job.factory_dispatch_id,
    'requested_quantity', v_job.requested_quantity,
    'producer_type', CASE WHEN v_is_vault_job THEN 'internal_ai' ELSE NULL END,
    'claim_token', v_job.claim_token,
    'claimed_by', v_job.claimed_by,
    'claimed_at', v_job.claimed_at,
    'lease_expires_at', v_job.lease_expires_at,
    'attempt_count', v_job.attempt_count,
    'max_attempts', v_job.max_attempts,
    'input_data', v_job.input_data
  );

END;
$function$;


CREATE OR REPLACE FUNCTION public.claim_next_ai_generation_job(
  p_worker_name text,
  p_lease_seconds integer DEFAULT 300
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN private.claim_next_ai_generation_job(
    p_worker_name,
    p_lease_seconds
  );
END;
$function$;

COMMIT;

-- ============================================================
-- EK (138): 137'deki fonksiyonların gerçek şema kolon adlarıyla
-- uyumsuzluğu (v_req.status/requested_count/scope/criteria vs
-- gerçek request_status/requested_question_count/ai_generation_spec)
-- bu görevde düzeltildi:
--   approve_question_generation_request  → request_status/requested_
--     question_count/ai_generation_spec; competition trigger'ına
--     takılmaması için competition_factory_dispatch_id=NULL,
--     generation_spec_id=NULL (vault dalı);
--   build_vault_ai_factory_job → request_status/requested_question_count;
--   record_vault_generation_batch_progress → request_status/requested_
--     question_count + generated_candidate_count sayacı;
--   claim_next_ai_generation_job → vault dalı (yukarıda).
-- DB'de düzeltilmiş sürümler canlıdır; pozitif zincir provaları
-- (onay→dispatch→job→claim→progress) BEGIN/ROLLBACK içinde PASS.
-- ============================================================
