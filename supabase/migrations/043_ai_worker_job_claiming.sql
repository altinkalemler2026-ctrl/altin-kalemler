-- 043_ai_worker_job_claiming.sql
-- Altın Kalemler
--
-- AI worker queue claim / lease altyapısı.
--
-- Amaç:
-- - Aynı queued AI job'ın iki worker tarafından aynı anda alınmasını engellemek.
-- - Worker'a benzersiz claim token vermek.
-- - Uzun süren işlerde heartbeat ile lease yenilemek.
-- - Worker hatalarında kontrollü retry yapmak.
-- - Lease süresi dolan işleri güvenli biçimde yeniden kuyruğa almak.
--
-- Güvenlik:
-- - Bu migration AI provider çağrısı yapmaz.
-- - Production'a soru yayınlamaz.
-- - Public worker RPC'leri yalnızca service_role tarafından çağrılabilir.
-- - AI çıktıları hâlâ 032 ingestion zinciri üzerinden staging'e gider.

BEGIN;

-- =========================================================
-- AI JOB WORKER CLAIM FIELDS
-- =========================================================

ALTER TABLE public.ai_jobs
  ADD COLUMN IF NOT EXISTS claimed_by text;

ALTER TABLE public.ai_jobs
  ADD COLUMN IF NOT EXISTS claim_token uuid;

ALTER TABLE public.ai_jobs
  ADD COLUMN IF NOT EXISTS claimed_at timestamptz;

ALTER TABLE public.ai_jobs
  ADD COLUMN IF NOT EXISTS lease_expires_at timestamptz;

ALTER TABLE public.ai_jobs
  ADD COLUMN IF NOT EXISTS heartbeat_at timestamptz;


-- =========================================================
-- INDEXES
-- =========================================================

CREATE INDEX IF NOT EXISTS idx_ai_jobs_worker_queue
ON public.ai_jobs (
  status,
  job_type,
  created_at
)
WHERE status = 'queued';


CREATE INDEX IF NOT EXISTS idx_ai_jobs_worker_lease
ON public.ai_jobs (
  lease_expires_at
)
WHERE status = 'processing'
  AND claim_token IS NOT NULL;


CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_jobs_active_claim_token
ON public.ai_jobs (claim_token)
WHERE claim_token IS NOT NULL;


-- =========================================================
-- PRIVATE: CLAIM NEXT QUESTION GENERATION JOB
-- =========================================================

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

  v_worker_name text;

  v_claim_token uuid;

  v_now timestamptz;

  v_lease_expires_at timestamptz;
BEGIN

  -- -------------------------------------------------------
  -- Caller
  -- -------------------------------------------------------

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT private.current_user_has_admin_permission(
       'ai.manage'
     )
  THEN

    RAISE EXCEPTION
      'AI worker or AI management permission required.';

  END IF;


  -- -------------------------------------------------------
  -- Worker name
  -- -------------------------------------------------------

  v_worker_name :=
    NULLIF(
      btrim(
        COALESCE(
          p_worker_name,
          ''
        )
      ),
      ''
    );


  IF v_worker_name IS NULL THEN

    RAISE EXCEPTION
      'Worker name is required.';

  END IF;


  IF char_length(v_worker_name) > 200 THEN

    RAISE EXCEPTION
      'Worker name is too long.';

  END IF;


  -- -------------------------------------------------------
  -- Lease duration
  -- 30 sn - 30 dk
  -- -------------------------------------------------------

  IF p_lease_seconds IS NULL
     OR p_lease_seconds < 30
     OR p_lease_seconds > 1800
  THEN

    RAISE EXCEPTION
      'Lease seconds must be between 30 and 1800.';

  END IF;


  v_now :=
    clock_timestamp();


  -- =======================================================
  -- EXPIRED LEASE RECOVERY
  --
  -- Worker claim etmiş fakat lease süresi içinde işi
  -- tamamlayamamışsa bu execution başarısız attempt sayılır.
  --
  -- Daha attempt hakkı varsa queued.
  -- Hak bittiyse failed.
  -- =======================================================

  UPDATE public.ai_jobs
  SET
    attempt_count =
      attempt_count + 1,

    status =
      CASE
        WHEN attempt_count + 1 >= max_attempts
          THEN 'failed'
        ELSE 'queued'
      END,

    error_code =
      'worker_lease_expired',

    error_message =
      'AI worker lease expired before the job was completed.',

    completed_at =
      CASE
        WHEN attempt_count + 1 >= max_attempts
          THEN v_now
        ELSE NULL
      END,

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

  WHERE job_type = 'question_generation'

    AND status = 'processing'

    AND claim_token IS NOT NULL

    AND lease_expires_at IS NOT NULL

    AND lease_expires_at <= v_now;


  -- =======================================================
  -- CLAIM
  --
  -- FOR UPDATE SKIP LOCKED:
  -- Aynı anda çalışan worker'ların aynı job'ı almasını
  -- engeller.
  -- =======================================================

  SELECT j.*
  INTO v_job

  FROM public.ai_jobs j

  WHERE j.job_type = 'question_generation'

    AND j.status = 'queued'

    AND j.attempt_count < j.max_attempts

    AND j.competition_factory_dispatch_id IS NOT NULL

    AND j.generation_spec_id IS NOT NULL

  ORDER BY
    j.created_at ASC,
    j.id ASC

  FOR UPDATE SKIP LOCKED

  LIMIT 1;


  -- -------------------------------------------------------
  -- Queue boş
  -- -------------------------------------------------------

  IF NOT FOUND THEN

    RETURN jsonb_build_object(
      'status',
      'empty',

      'job_available',
      false
    );

  END IF;


  v_claim_token :=
    gen_random_uuid();


  v_lease_expires_at :=
    v_now
    + make_interval(
        secs => p_lease_seconds
      );


  -- =======================================================
  -- JOB -> PROCESSING
  -- =======================================================

  UPDATE public.ai_jobs
  SET
    status =
      'processing',

    claimed_by =
      v_worker_name,

    claim_token =
      v_claim_token,

    claimed_at =
      v_now,

    heartbeat_at =
      v_now,

    lease_expires_at =
      v_lease_expires_at,

    started_at =
      COALESCE(
        started_at,
        v_now
      ),

    completed_at =
      NULL,

    error_code =
      NULL,

    error_message =
      NULL,

    updated_at =
      v_now

  WHERE id = v_job.id

  RETURNING *
  INTO v_job;


  -- =======================================================
  -- RESULT
  -- =======================================================

  RETURN jsonb_build_object(

    'status',
    'claimed',

    'job_available',
    true,

    'ai_job_id',
    v_job.id,

    'job_type',
    v_job.job_type,

    'generation_spec_id',
    v_job.generation_spec_id,

    'competition_generation_request_id',
    v_job.competition_generation_request_id,

    'competition_factory_dispatch_id',
    v_job.competition_factory_dispatch_id,

    'claim_token',
    v_job.claim_token,

    'claimed_by',
    v_job.claimed_by,

    'claimed_at',
    v_job.claimed_at,

    'lease_expires_at',
    v_job.lease_expires_at,

    'attempt_count',
    v_job.attempt_count,

    'max_attempts',
    v_job.max_attempts,

    'input_data',
    v_job.input_data

  );

END;
$function$;


-- =========================================================
-- PRIVATE: HEARTBEAT / LEASE RENEW
-- =========================================================

CREATE OR REPLACE FUNCTION private.renew_ai_job_lease(
  p_ai_job_id uuid,
  p_claim_token uuid,
  p_lease_seconds integer DEFAULT 300
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_job public.ai_jobs%ROWTYPE;

  v_now timestamptz;

  v_new_expiry timestamptz;
BEGIN

  -- -------------------------------------------------------
  -- Caller
  -- -------------------------------------------------------

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT private.current_user_has_admin_permission(
       'ai.manage'
     )
  THEN

    RAISE EXCEPTION
      'AI worker or AI management permission required.';

  END IF;


  IF p_ai_job_id IS NULL
     OR p_claim_token IS NULL
  THEN

    RAISE EXCEPTION
      'AI job id and claim token are required.';

  END IF;


  IF p_lease_seconds IS NULL
     OR p_lease_seconds < 30
     OR p_lease_seconds > 1800
  THEN

    RAISE EXCEPTION
      'Lease seconds must be between 30 and 1800.';

  END IF;


  v_now :=
    clock_timestamp();


  SELECT *
  INTO v_job

  FROM public.ai_jobs j

  WHERE j.id = p_ai_job_id

  FOR UPDATE;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'AI job not found.';

  END IF;


  IF v_job.status <> 'processing' THEN

    RAISE EXCEPTION
      'AI job is not processing.';

  END IF;


  IF v_job.claim_token IS DISTINCT FROM p_claim_token THEN

    RAISE EXCEPTION
      'AI job claim token does not match.';

  END IF;


  IF v_job.lease_expires_at IS NULL
     OR v_job.lease_expires_at <= v_now
  THEN

    RAISE EXCEPTION
      'AI job lease has already expired.';

  END IF;


  v_new_expiry :=
    v_now
    + make_interval(
        secs => p_lease_seconds
      );


  UPDATE public.ai_jobs
  SET
    heartbeat_at =
      v_now,

    lease_expires_at =
      v_new_expiry,

    updated_at =
      v_now

  WHERE id = v_job.id;


  RETURN jsonb_build_object(

    'status',
    'renewed',

    'ai_job_id',
    v_job.id,

    'claim_token',
    p_claim_token,

    'heartbeat_at',
    v_now,

    'lease_expires_at',
    v_new_expiry

  );

END;
$function$;


-- =========================================================
-- PRIVATE: WORKER FAILURE
--
-- Provider/API/network/parsing gibi worker tarafındaki
-- başarısızlık burada kontrollü olarak job'a yazılır.
--
-- retryable=true ve attempt hakkı varsa tekrar queued.
-- Aksi halde failed.
-- =========================================================

CREATE OR REPLACE FUNCTION private.fail_ai_job_claim(
  p_ai_job_id uuid,
  p_claim_token uuid,
  p_error_code text,
  p_error_message text,
  p_retryable boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_job public.ai_jobs%ROWTYPE;

  v_now timestamptz;

  v_next_attempt integer;

  v_next_status text;

  v_retry_scheduled boolean;
BEGIN

  -- -------------------------------------------------------
  -- Caller
  -- -------------------------------------------------------

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT private.current_user_has_admin_permission(
       'ai.manage'
     )
  THEN

    RAISE EXCEPTION
      'AI worker or AI management permission required.';

  END IF;


  IF p_ai_job_id IS NULL
     OR p_claim_token IS NULL
  THEN

    RAISE EXCEPTION
      'AI job id and claim token are required.';

  END IF;


  v_now :=
    clock_timestamp();


  SELECT *
  INTO v_job

  FROM public.ai_jobs j

  WHERE j.id = p_ai_job_id

  FOR UPDATE;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'AI job not found.';

  END IF;


  IF v_job.status <> 'processing' THEN

    RAISE EXCEPTION
      'AI job is not processing.';

  END IF;


  IF v_job.claim_token IS DISTINCT FROM p_claim_token THEN

    RAISE EXCEPTION
      'AI job claim token does not match.';

  END IF;


  v_next_attempt :=
    v_job.attempt_count + 1;


  v_retry_scheduled :=
    COALESCE(
      p_retryable,
      true
    )
    AND v_next_attempt < v_job.max_attempts;


  IF v_retry_scheduled THEN

    v_next_status :=
      'queued';

  ELSE

    v_next_status :=
      'failed';

  END IF;


  UPDATE public.ai_jobs
  SET
    attempt_count =
      v_next_attempt,

    status =
      v_next_status,

    error_code =
      COALESCE(
        NULLIF(
          btrim(
            COALESCE(
              p_error_code,
              ''
            )
          ),
          ''
        ),
        'worker_failure'
      ),

    error_message =
      NULLIF(
        btrim(
          COALESCE(
            p_error_message,
            ''
          )
        ),
        ''
      ),

    completed_at =
      CASE
        WHEN v_next_status = 'failed'
          THEN v_now
        ELSE NULL
      END,

    claimed_by =
      NULL,

    claim_token =
      NULL,

    claimed_at =
      NULL,

    lease_expires_at =
      NULL,

    heartbeat_at =
      NULL,

    output_data =
      COALESCE(
        output_data,
        '{}'::jsonb
      )
      ||
      jsonb_build_object(
        'last_worker_failure',
        jsonb_build_object(
          'failed_at',
          v_now,

          'error_code',
          COALESCE(
            NULLIF(
              btrim(
                COALESCE(
                  p_error_code,
                  ''
                )
              ),
              ''
            ),
            'worker_failure'
          ),

          'error_message',
          NULLIF(
            btrim(
              COALESCE(
                p_error_message,
                ''
              )
            ),
            ''
          ),

          'retryable',
          COALESCE(
            p_retryable,
            true
          ),

          'attempt_number',
          v_next_attempt
        )
      ),

    updated_at =
      v_now

  WHERE id = v_job.id;


  RETURN jsonb_build_object(

    'status',
    v_next_status,

    'ai_job_id',
    v_job.id,

    'attempt_count',
    v_next_attempt,

    'max_attempts',
    v_job.max_attempts,

    'retry_scheduled',
    v_retry_scheduled

  );

END;
$function$;


-- =========================================================
-- PUBLIC WORKER WRAPPERS
--
-- Bunlar server-side worker içindir.
-- Browser / authenticated kullanıcıya açılmaz.
-- =========================================================

CREATE OR REPLACE FUNCTION public.claim_next_ai_generation_job(
  p_worker_name text,
  p_lease_seconds integer DEFAULT 300
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $function$

  SELECT private.claim_next_ai_generation_job(
    p_worker_name,
    p_lease_seconds
  );

$function$;


CREATE OR REPLACE FUNCTION public.renew_ai_job_lease(
  p_ai_job_id uuid,
  p_claim_token uuid,
  p_lease_seconds integer DEFAULT 300
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $function$

  SELECT private.renew_ai_job_lease(
    p_ai_job_id,
    p_claim_token,
    p_lease_seconds
  );

$function$;


CREATE OR REPLACE FUNCTION public.fail_ai_job_claim(
  p_ai_job_id uuid,
  p_claim_token uuid,
  p_error_code text,
  p_error_message text,
  p_retryable boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $function$

  SELECT private.fail_ai_job_claim(
    p_ai_job_id,
    p_claim_token,
    p_error_code,
    p_error_message,
    p_retryable
  );

$function$;


-- =========================================================
-- PERMISSIONS
-- =========================================================

REVOKE ALL
ON FUNCTION private.claim_next_ai_generation_job(
  text,
  integer
)
FROM PUBLIC;


REVOKE ALL
ON FUNCTION private.renew_ai_job_lease(
  uuid,
  uuid,
  integer
)
FROM PUBLIC;


REVOKE ALL
ON FUNCTION private.fail_ai_job_claim(
  uuid,
  uuid,
  text,
  text,
  boolean
)
FROM PUBLIC;


REVOKE ALL
ON FUNCTION public.claim_next_ai_generation_job(
  text,
  integer
)
FROM PUBLIC, anon, authenticated;


REVOKE ALL
ON FUNCTION public.renew_ai_job_lease(
  uuid,
  uuid,
  integer
)
FROM PUBLIC, anon, authenticated;


REVOKE ALL
ON FUNCTION public.fail_ai_job_claim(
  uuid,
  uuid,
  text,
  text,
  boolean
)
FROM PUBLIC, anon, authenticated;


GRANT EXECUTE
ON FUNCTION public.claim_next_ai_generation_job(
  text,
  integer
)
TO service_role;


GRANT EXECUTE
ON FUNCTION public.renew_ai_job_lease(
  uuid,
  uuid,
  integer
)
TO service_role;


GRANT EXECUTE
ON FUNCTION public.fail_ai_job_claim(
  uuid,
  uuid,
  text,
  text,
  boolean
)
TO service_role;


-- =========================================================
-- COMMENTS
-- =========================================================

COMMENT ON COLUMN public.ai_jobs.claimed_by
IS
'Server-side AI worker identifier that currently owns the job lease.';


COMMENT ON COLUMN public.ai_jobs.claim_token
IS
'Random lease token required for heartbeat and worker failure operations.';


COMMENT ON COLUMN public.ai_jobs.claimed_at
IS
'Timestamp when the current AI worker lease was acquired.';


COMMENT ON COLUMN public.ai_jobs.lease_expires_at
IS
'Timestamp after which an unfinished worker claim may be recovered.';


COMMENT ON COLUMN public.ai_jobs.heartbeat_at
IS
'Last successful worker lease heartbeat timestamp.';


COMMENT ON FUNCTION public.claim_next_ai_generation_job(
  text,
  integer
)
IS
'Claims one queued question_generation AI job for a server-side worker using FOR UPDATE SKIP LOCKED and a time-limited lease.';


COMMENT ON FUNCTION public.renew_ai_job_lease(
  uuid,
  uuid,
  integer
)
IS
'Renews the lease of a processing AI job when the supplied claim token matches.';


COMMENT ON FUNCTION public.fail_ai_job_claim(
  uuid,
  uuid,
  text,
  text,
  boolean
)
IS
'Records a claimed worker execution failure and either retries the AI job or marks it failed according to max_attempts.';


COMMIT;