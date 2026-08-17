-- 032_ai_worker_staging_ingestion.sql
-- Altın Kalemler
--
-- AI Worker -> Raw Output -> Deterministic Validation
-- -> ai_question_staging güvenli ingestion sözleşmesi.
--
-- Bu migration:
--
-- 1. AI worker çıktısını ham haliyle saklar.
-- 2. Zorunlu JSON yapısını kontrol eder.
-- 3. Soru sayısını kontrol eder.
-- 4. Her sorunun metin/seçenek/cevap yapısını doğrular.
-- 5. Sınıf/ders/spec/job/dispatch eşleşmesini doğrular.
-- 6. Bozuk soruları staging'e sokmaz.
-- 7. Geçerli soruları yalnız ai_question_staging'e yazar.
-- 8. Deterministic validation kayıtlarını oluşturur.
-- 9. Eksik üretim varsa retry ihtiyacını hesaplar.
-- 10. Production'a otomatik yayın YAPMAZ.
--
-- Herhangi bir ücretli AI API çağrısı içermez.

BEGIN;


-- =========================================================
-- 1. AI WORKER HAM ÇIKTILARI
--
-- AI sağlayıcısından gelen cevap ilk olarak buraya gelir.
-- Böylece:
--
-- - ham cevap kaybolmaz
-- - parse hataları incelenebilir
-- - provider/model/prompt sürümü izlenebilir
-- - staging'e neyin girdiği denetlenebilir
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_worker_outputs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  ai_job_id uuid NOT NULL
    REFERENCES public.ai_jobs(id)
    ON DELETE CASCADE,

  generation_spec_id uuid
    REFERENCES public.ai_generation_specs(id)
    ON DELETE SET NULL,

  competition_generation_request_id uuid
    REFERENCES public.competition_ai_generation_requests(id)
    ON DELETE SET NULL,

  competition_factory_dispatch_id uuid
    REFERENCES public.competition_ai_factory_dispatches(id)
    ON DELETE SET NULL,

  -- -------------------------------------------------------
  -- Worker / provider bilgisi
  -- -------------------------------------------------------

  provider_name text,

  model_name text,

  prompt_version text,

  worker_version text,

  -- -------------------------------------------------------
  -- Ham payload
  -- -------------------------------------------------------

  raw_output jsonb NOT NULL,

  -- -------------------------------------------------------
  -- Parse / validation
  -- -------------------------------------------------------

  status text NOT NULL DEFAULT 'received'
    CHECK (
      status IN (
        'received',
        'validating',
        'validated',
        'partially_valid',
        'rejected',
        'ingested',
        'failed'
      )
    ),

  requested_question_count integer
    CHECK (
      requested_question_count IS NULL
      OR requested_question_count > 0
    ),

  received_question_count integer NOT NULL DEFAULT 0
    CHECK (received_question_count >= 0),

  valid_question_count integer NOT NULL DEFAULT 0
    CHECK (valid_question_count >= 0),

  invalid_question_count integer NOT NULL DEFAULT 0
    CHECK (invalid_question_count >= 0),

  inserted_question_count integer NOT NULL DEFAULT 0
    CHECK (inserted_question_count >= 0),

  duplicate_question_count integer NOT NULL DEFAULT 0
    CHECK (duplicate_question_count >= 0),

  remaining_question_count integer NOT NULL DEFAULT 0
    CHECK (remaining_question_count >= 0),

  retry_required boolean NOT NULL DEFAULT false,

  validation_summary jsonb NOT NULL DEFAULT '{}'::jsonb,

  error_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  received_at timestamptz NOT NULL DEFAULT now(),

  validated_at timestamptz,

  ingested_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),

  updated_at timestamptz NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS
idx_ai_worker_outputs_job
ON public.ai_worker_outputs(
  ai_job_id,
  created_at DESC
);


CREATE INDEX IF NOT EXISTS
idx_ai_worker_outputs_dispatch
ON public.ai_worker_outputs(
  competition_factory_dispatch_id,
  created_at DESC
);


CREATE INDEX IF NOT EXISTS
idx_ai_worker_outputs_status
ON public.ai_worker_outputs(
  status,
  created_at DESC
);


ALTER TABLE public.ai_worker_outputs
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS
trigger_ai_worker_outputs_updated_at
ON public.ai_worker_outputs;


CREATE TRIGGER
trigger_ai_worker_outputs_updated_at
BEFORE UPDATE
ON public.ai_worker_outputs
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. TEK TEK ADAY SORU DOĞRULAMA SONUÇLARI
--
-- Bir worker output içindeki her candidate için ayrı kayıt.
-- Bozuk soru staging'e girmese bile neden reddedildiği kalır.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_worker_candidate_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  worker_output_id uuid NOT NULL
    REFERENCES public.ai_worker_outputs(id)
    ON DELETE CASCADE,

  candidate_index integer NOT NULL
    CHECK (candidate_index >= 0),

  candidate_key text,

  raw_candidate jsonb NOT NULL,

  validation_status text NOT NULL DEFAULT 'pending'
    CHECK (
      validation_status IN (
        'pending',
        'valid',
        'invalid',
        'duplicate',
        'inserted',
        'failed'
      )
    ),

  validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,

  validation_warnings jsonb NOT NULL DEFAULT '[]'::jsonb,

  staging_question_id uuid
    REFERENCES public.ai_question_staging(id)
    ON DELETE SET NULL,

  created_at timestamptz NOT NULL DEFAULT now(),

  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    worker_output_id,
    candidate_index
  )
);


CREATE INDEX IF NOT EXISTS
idx_ai_worker_candidate_results_output
ON public.ai_worker_candidate_results(
  worker_output_id,
  validation_status
);


CREATE INDEX IF NOT EXISTS
idx_ai_worker_candidate_results_staging
ON public.ai_worker_candidate_results(
  staging_question_id
);


ALTER TABLE public.ai_worker_candidate_results
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS
trigger_ai_worker_candidate_results_updated_at
ON public.ai_worker_candidate_results;


CREATE TRIGGER
trigger_ai_worker_candidate_results_updated_at
BEFORE UPDATE
ON public.ai_worker_candidate_results
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. WORKER PAYLOAD SÖZLEŞMESİ
--
-- Beklenen ana yapı:
--
-- {
--   "schema_version": "1.0",
--   "questions": [
--     {
--       "client_question_id": "...",
--       "question_text": "...",
--       "options": {
--         "A": "...",
--         "B": "...",
--         "C": "...",
--         "D": "...",
--         "E": "..."
--       },
--       "correct_answer": "A",
--       "difficulty": "medium",
--       "cognitive_type": "application",
--       "primary_question_type": "...",
--       "is_new_generation": true,
--       "estimated_solve_time_seconds": 75,
--       "has_visual": false,
--       "solution": {...},
--       "analysis": {...},
--       "metadata": {...}
--     }
--   ]
-- }
--
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_ai_question_worker_contract()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(

    'schema_version',
    '1.0',

    'root',
    jsonb_build_object(
      'required',
      jsonb_build_array(
        'schema_version',
        'questions'
      ),

      'schema_version',
      '1.0',

      'questions_type',
      'array'
    ),

    'question',
    jsonb_build_object(

      'required',
      jsonb_build_array(
        'question_text',
        'options',
        'correct_answer'
      ),

      'question_text',
      jsonb_build_object(
        'type',
        'string',
        'minimum_non_whitespace_length',
        10
      ),

      'options',
      jsonb_build_object(
        'type',
        'object',

        'required_keys',
        jsonb_build_array(
          'A',
          'B',
          'C',
          'D'
        ),

        'optional_keys',
        jsonb_build_array(
          'E'
        )
      ),

      'correct_answer',
      jsonb_build_object(
        'allowed',
        jsonb_build_array(
          'A',
          'B',
          'C',
          'D',
          'E'
        )
      ),

      'difficulty',
      jsonb_build_object(
        'allowed',
        jsonb_build_array(
          'easy',
          'medium',
          'hard'
        )
      ),

      'cognitive_type',
      jsonb_build_object(
        'allowed',
        jsonb_build_array(
          'learning',
          'comprehension',
          'application'
        )
      ),

      'estimated_solve_time_seconds',
      jsonb_build_object(
        'type',
        'positive_integer'
      ),

      'important_rules',
      jsonb_build_array(

        'Each question must be original.',

        'Existing source questions may not be rewritten by merely changing wording, names or numbers.',

        'The correct answer must be independently solvable.',

        'Question grade and curriculum fit must be reviewed.',

        'Question-specific solve-time analysis is required.',

        'Generated questions may only enter staging.',

        'Automatic production publication is forbidden.'
      )
    )
  );
$$;


REVOKE EXECUTE
ON FUNCTION public.get_ai_question_worker_contract()
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_ai_question_worker_contract()
TO authenticated, service_role;


-- =========================================================
-- 4. INTERNAL:
-- TEK CANDIDATE DETERMINISTIC VALIDATOR
--
-- AI'nin "bu soru doğru" demesine güvenmeden önce
-- yapısal kontroller.
-- =========================================================

CREATE OR REPLACE FUNCTION private.validate_ai_question_candidate(
  p_candidate jsonb,
  p_spec_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_spec public.ai_generation_specs%ROWTYPE;

  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;

  v_question_text text;

  v_options jsonb;

  v_a text;
  v_b text;
  v_c text;
  v_d text;
  v_e text;

  v_correct_answer text;

  v_difficulty text;

  v_cognitive text;

  v_solve_time integer;

  v_option_values text[];
  v_option_count integer;
  v_unique_option_count integer;
BEGIN

  IF p_candidate IS NULL
     OR jsonb_typeof(p_candidate) <> 'object' THEN

    RETURN jsonb_build_object(
      'valid',
      false,

      'errors',
      jsonb_build_array(
        'candidate_must_be_json_object'
      ),

      'warnings',
      '[]'::jsonb
    );

  END IF;


  SELECT *
  INTO v_spec

  FROM public.ai_generation_specs s

  WHERE s.id = p_spec_id;


  IF NOT FOUND THEN

    RETURN jsonb_build_object(
      'valid',
      false,

      'errors',
      jsonb_build_array(
        'generation_spec_not_found'
      ),

      'warnings',
      '[]'::jsonb
    );

  END IF;


  -- =======================================================
  -- QUESTION TEXT
  -- =======================================================

  v_question_text :=
    btrim(
      COALESCE(
        p_candidate ->> 'question_text',
        ''
      )
    );


  IF length(v_question_text) < 10 THEN

    v_errors :=
      v_errors
      || jsonb_build_array(
           'question_text_missing_or_too_short'
         );

  END IF;


  -- =======================================================
  -- OPTIONS
  -- =======================================================

  v_options :=
    p_candidate -> 'options';


  IF v_options IS NULL
     OR jsonb_typeof(v_options) <> 'object' THEN

    v_errors :=
      v_errors
      || jsonb_build_array(
           'options_must_be_object'
         );

  ELSE

    v_a := btrim(COALESCE(v_options ->> 'A', ''));
    v_b := btrim(COALESCE(v_options ->> 'B', ''));
    v_c := btrim(COALESCE(v_options ->> 'C', ''));
    v_d := btrim(COALESCE(v_options ->> 'D', ''));
    v_e := btrim(COALESCE(v_options ->> 'E', ''));


    IF v_a = '' THEN
      v_errors :=
        v_errors || jsonb_build_array('option_A_missing');
    END IF;


    IF v_b = '' THEN
      v_errors :=
        v_errors || jsonb_build_array('option_B_missing');
    END IF;


    IF v_c = '' THEN
      v_errors :=
        v_errors || jsonb_build_array('option_C_missing');
    END IF;


    IF v_d = '' THEN
      v_errors :=
        v_errors || jsonb_build_array('option_D_missing');
    END IF;


    -- -----------------------------------------------------
    -- Aynı seçeneklerin tekrarını engelle.
    -- -----------------------------------------------------

    v_option_values :=
      ARRAY[
        NULLIF(lower(v_a), ''),
        NULLIF(lower(v_b), ''),
        NULLIF(lower(v_c), ''),
        NULLIF(lower(v_d), ''),
        NULLIF(lower(v_e), '')
      ];


    SELECT
      COUNT(*),
      COUNT(DISTINCT x)

    INTO
      v_option_count,
      v_unique_option_count

    FROM unnest(v_option_values) AS t(x)

    WHERE x IS NOT NULL;


    IF v_option_count <> v_unique_option_count THEN

      v_errors :=
        v_errors
        || jsonb_build_array(
             'duplicate_option_text_detected'
           );

    END IF;

  END IF;


  -- =======================================================
  -- CORRECT ANSWER
  -- =======================================================

  v_correct_answer :=
    upper(
      btrim(
        COALESCE(
          p_candidate ->> 'correct_answer',
          ''
        )
      )
    );


  IF v_correct_answer NOT IN (
    'A',
    'B',
    'C',
    'D',
    'E'
  ) THEN

    v_errors :=
      v_errors
      || jsonb_build_array(
           'correct_answer_invalid'
         );

  END IF;


  IF v_correct_answer = 'E'
     AND COALESCE(v_e, '') = '' THEN

    v_errors :=
      v_errors
      || jsonb_build_array(
           'correct_answer_points_to_missing_option_E'
         );

  END IF;


  -- =======================================================
  -- DIFFICULTY
  -- =======================================================

  v_difficulty :=
    lower(
      btrim(
        COALESCE(
          p_candidate ->> 'difficulty',
          ''
        )
      )
    );


  IF v_difficulty <> ''
     AND v_difficulty NOT IN (
       'easy',
       'medium',
       'hard'
     ) THEN

    v_errors :=
      v_errors
      || jsonb_build_array(
           'difficulty_invalid'
         );

  END IF;


  IF v_spec.difficulty IS NOT NULL
     AND v_difficulty <> ''
     AND v_difficulty <> v_spec.difficulty THEN

    v_warnings :=
      v_warnings
      || jsonb_build_array(
           'difficulty_differs_from_generation_spec'
         );

  END IF;


  -- =======================================================
  -- COGNITIVE TYPE
  -- =======================================================

  v_cognitive :=
    lower(
      btrim(
        COALESCE(
          p_candidate ->> 'cognitive_type',
          ''
        )
      )
    );


  IF v_cognitive <> ''
     AND v_cognitive NOT IN (
       'learning',
       'comprehension',
       'application'
     ) THEN

    v_errors :=
      v_errors
      || jsonb_build_array(
           'cognitive_type_invalid'
         );

  END IF;


  IF v_spec.cognitive_type IS NOT NULL
     AND v_cognitive <> ''
     AND v_cognitive <> v_spec.cognitive_type THEN

    v_warnings :=
      v_warnings
      || jsonb_build_array(
           'cognitive_type_differs_from_generation_spec'
         );

  END IF;


  -- =======================================================
  -- SOLVE TIME
  -- =======================================================

  BEGIN

    IF p_candidate ? 'estimated_solve_time_seconds'
       AND p_candidate ->> 'estimated_solve_time_seconds'
           IS NOT NULL THEN

      v_solve_time :=
        (p_candidate ->> 'estimated_solve_time_seconds')::integer;

    ELSE

      v_solve_time := NULL;

    END IF;

  EXCEPTION
    WHEN invalid_text_representation
      OR numeric_value_out_of_range THEN

      v_solve_time := NULL;

      v_errors :=
        v_errors
        || jsonb_build_array(
             'estimated_solve_time_seconds_invalid'
           );

  END;


  IF v_solve_time IS NOT NULL
     AND v_solve_time <= 0 THEN

    v_errors :=
      v_errors
      || jsonb_build_array(
           'estimated_solve_time_seconds_must_be_positive'
         );

  END IF;


  IF v_spec.min_solve_time_seconds IS NOT NULL
     AND v_solve_time IS NOT NULL
     AND v_solve_time < v_spec.min_solve_time_seconds THEN

    v_warnings :=
      v_warnings
      || jsonb_build_array(
           'estimated_solve_time_below_requested_range'
         );

  END IF;


  IF v_spec.max_solve_time_seconds IS NOT NULL
     AND v_solve_time IS NOT NULL
     AND v_solve_time > v_spec.max_solve_time_seconds THEN

    v_warnings :=
      v_warnings
      || jsonb_build_array(
           'estimated_solve_time_above_requested_range'
         );

  END IF;


  -- =======================================================
  -- SOLUTION / ANALYSIS WARNINGS
  --
  -- Bunları henüz hard fail yapmıyoruz.
  -- Sonraki AI doğrulama katmanları bağımsız kontrol edecek.
  -- =======================================================

  IF NOT (p_candidate ? 'solution') THEN

    v_warnings :=
      v_warnings
      || jsonb_build_array(
           'solution_not_provided'
         );

  END IF;


  IF NOT (p_candidate ? 'analysis') THEN

    v_warnings :=
      v_warnings
      || jsonb_build_array(
           'question_analysis_not_provided'
         );

  END IF;


  -- =======================================================
  -- RESULT
  -- =======================================================

  RETURN jsonb_build_object(

    'valid',
    jsonb_array_length(v_errors) = 0,

    'errors',
    v_errors,

    'warnings',
    v_warnings
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.validate_ai_question_candidate(jsonb, uuid)
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 5. WORKER OUTPUT REGISTER
--
-- Worker ham sonucu önce buraya teslim eder.
--
-- Bu işlem henüz staging insert yapmaz.
-- =========================================================

CREATE OR REPLACE FUNCTION private.register_ai_worker_output(
  p_ai_job_id uuid,
  p_raw_output jsonb,
  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,
  p_worker_version text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_job public.ai_jobs%ROWTYPE;

  v_dispatch public.competition_ai_factory_dispatches%ROWTYPE;

  v_output_id uuid;

  v_received_count integer := 0;
BEGIN

  -- =======================================================
  -- Caller:
  -- service_role veya yetkili admin
  -- =======================================================

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission(
         'ai.manage'
       )
       OR
       private.current_user_has_admin_permission(
         'questions.approve'
       )
     )
  THEN

    RAISE EXCEPTION
      'AI worker or AI management permission required.';

  END IF;


  SELECT *
  INTO v_job

  FROM public.ai_jobs j

  WHERE j.id = p_ai_job_id

  FOR UPDATE;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'AI job not found.';

  END IF;


  IF v_job.job_type <> 'question_generation' THEN

    RAISE EXCEPTION
      'Only question_generation jobs can use this ingestion endpoint.';

  END IF;


  IF v_job.competition_factory_dispatch_id IS NULL THEN

    RAISE EXCEPTION
      'AI job is not connected to a competition factory dispatch.';

  END IF;


  SELECT *
  INTO v_dispatch

  FROM public.competition_ai_factory_dispatches d

  WHERE d.id =
    v_job.competition_factory_dispatch_id;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Competition AI factory dispatch not found.';

  END IF;


  IF v_dispatch.human_approved = false THEN

    RAISE EXCEPTION
      'Factory dispatch has not been human approved.';

  END IF;


  IF v_dispatch.automatic_publication_allowed = true THEN

    RAISE EXCEPTION
      'Automatic publication is forbidden.';

  END IF;


  IF v_job.status NOT IN (
    'queued',
    'processing'
  ) THEN

    RAISE EXCEPTION
      'AI job cannot receive worker output in status: %',
      v_job.status;

  END IF;


  -- =======================================================
  -- ROOT JSON
  -- =======================================================

  IF p_raw_output IS NULL
     OR jsonb_typeof(p_raw_output) <> 'object' THEN

    RAISE EXCEPTION
      'AI worker output must be a JSON object.';

  END IF;


  IF p_raw_output ->> 'schema_version'
     IS DISTINCT FROM '1.0' THEN

    RAISE EXCEPTION
      'Unsupported AI worker output schema version.';

  END IF;


  IF NOT (p_raw_output ? 'questions')
     OR jsonb_typeof(
          p_raw_output -> 'questions'
        ) <> 'array'
  THEN

    RAISE EXCEPTION
      'AI worker output must contain a questions array.';

  END IF;


  v_received_count :=
    jsonb_array_length(
      p_raw_output -> 'questions'
    );


  -- =======================================================
  -- WORKER OUTPUT KAYDI
  -- =======================================================

  INSERT INTO public.ai_worker_outputs (
    ai_job_id,

    generation_spec_id,

    competition_generation_request_id,

    competition_factory_dispatch_id,

    provider_name,

    model_name,

    prompt_version,

    worker_version,

    raw_output,

    status,

    requested_question_count,

    received_question_count,

    metadata
  )

  VALUES (
    v_job.id,

    v_job.generation_spec_id,

    v_job.competition_generation_request_id,

    v_job.competition_factory_dispatch_id,

    NULLIF(btrim(p_provider_name), ''),

    NULLIF(btrim(p_model_name), ''),

    NULLIF(btrim(p_prompt_version), ''),

    NULLIF(btrim(p_worker_version), ''),

    p_raw_output,

    'received',

    v_dispatch.requested_question_count,

    v_received_count,

    jsonb_build_object(
      'registered_at',
      clock_timestamp(),

      'automatic_publication_allowed',
      false
    )
  )

  RETURNING id
  INTO v_output_id;


  -- Job worker tarafından işleniyor kabul edilir.

  UPDATE public.ai_jobs
  SET
    status = 'processing',

    started_at =
      COALESCE(
        started_at,
        clock_timestamp()
      )

  WHERE id = v_job.id;


  UPDATE public.competition_ai_factory_dispatches
  SET
    status = 'generating'

  WHERE id = v_dispatch.id;


  UPDATE public.competition_ai_generation_requests
  SET
    status = 'generating'

  WHERE id =
    v_dispatch.competition_generation_request_id;


  RETURN v_output_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.register_ai_worker_output(
  uuid,
  jsonb,
  text,
  text,
  text,
  text
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.register_ai_worker_output(
  uuid,
  jsonb,
  text,
  text,
  text,
  text
)
TO authenticated, service_role;


-- =========================================================
-- 6. PUBLIC WORKER OUTPUT REGISTER RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.register_ai_worker_output(
  p_ai_job_id uuid,
  p_raw_output jsonb,
  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,
  p_worker_version text DEFAULT NULL
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.register_ai_worker_output(
    p_ai_job_id,
    p_raw_output,
    p_provider_name,
    p_model_name,
    p_prompt_version,
    p_worker_version
  );
$$;


REVOKE ALL
ON FUNCTION public.register_ai_worker_output(
  uuid,
  jsonb,
  text,
  text,
  text,
  text
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.register_ai_worker_output(
  uuid,
  jsonb,
  text,
  text,
  text,
  text
)
TO authenticated, service_role;


-- =========================================================
-- 7. OUTPUT VALIDATION + STAGING INGESTION
-- =========================================================

CREATE OR REPLACE FUNCTION private.ingest_ai_worker_output(
  p_worker_output_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_output public.ai_worker_outputs%ROWTYPE;

  v_job public.ai_jobs%ROWTYPE;

  v_spec public.ai_generation_specs%ROWTYPE;

  v_dispatch public.competition_ai_factory_dispatches%ROWTYPE;

  v_candidate jsonb;

  v_validation jsonb;

  v_candidate_index integer := 0;

  v_candidate_key text;

  v_errors jsonb;

  v_warnings jsonb;

  v_question_text text;

  v_options jsonb;

  v_correct_answer text;

  v_difficulty text;

  v_cognitive text;

  v_primary_type text;

  v_is_new_generation boolean;

  v_has_visual boolean;

  v_solve_time integer;

  v_staging_id uuid;

  v_received_count integer := 0;

  v_valid_count integer := 0;

  v_invalid_count integer := 0;

  v_inserted_count integer := 0;

  v_duplicate_count integer := 0;

  v_existing_generated_count integer := 0;

  v_total_after_ingestion integer := 0;

  v_remaining integer := 0;

  v_retry_required boolean := false;

  v_final_output_status text;

  v_job_status text;
BEGIN

  -- =======================================================
  -- Caller
  -- =======================================================

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission(
         'ai.manage'
       )
       OR
       private.current_user_has_admin_permission(
         'questions.approve'
       )
     )
  THEN

    RAISE EXCEPTION
      'AI worker or AI management permission required.';

  END IF;


  -- =======================================================
  -- OUTPUT LOCK
  -- =======================================================

  SELECT *
  INTO v_output

  FROM public.ai_worker_outputs o

  WHERE o.id = p_worker_output_id

  FOR UPDATE;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'AI worker output not found.';

  END IF;


  IF v_output.status = 'ingested' THEN

    RETURN jsonb_build_object(
      'status',
      'already_ingested',

      'worker_output_id',
      v_output.id,

      'inserted_question_count',
      v_output.inserted_question_count,

      'remaining_question_count',
      v_output.remaining_question_count,

      'retry_required',
      v_output.retry_required
    );

  END IF;


  IF v_output.status IN (
    'failed',
    'rejected'
  ) THEN

    RAISE EXCEPTION
      'Rejected or failed worker output cannot be ingested.';

  END IF;


  UPDATE public.ai_worker_outputs
  SET status = 'validating'
  WHERE id = v_output.id;


  -- =======================================================
  -- JOB
  -- =======================================================

  SELECT *
  INTO v_job

  FROM public.ai_jobs j

  WHERE j.id = v_output.ai_job_id

  FOR UPDATE;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'AI job not found.';

  END IF;


  IF v_job.job_type <> 'question_generation' THEN

    RAISE EXCEPTION
      'Worker output job is not question_generation.';

  END IF;


  -- =======================================================
  -- SPEC
  -- =======================================================

  SELECT *
  INTO v_spec

  FROM public.ai_generation_specs s

  WHERE s.id =
    v_output.generation_spec_id;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'AI generation spec not found.';

  END IF;


  -- =======================================================
  -- DISPATCH
  -- =======================================================

  SELECT *
  INTO v_dispatch

  FROM public.competition_ai_factory_dispatches d

  WHERE d.id =
    v_output.competition_factory_dispatch_id

  FOR UPDATE;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Competition factory dispatch not found.';

  END IF;


  IF v_dispatch.human_approved = false THEN

    RAISE EXCEPTION
      'Factory dispatch is not human approved.';

  END IF;


  IF v_dispatch.automatic_publication_allowed = true THEN

    RAISE EXCEPTION
      'Automatic publication is forbidden.';

  END IF;


  IF v_dispatch.generation_spec_id
     IS DISTINCT FROM v_spec.id THEN

    RAISE EXCEPTION
      'Worker output generation spec does not match dispatch.';

  END IF;


  IF v_dispatch.ai_job_id
     IS DISTINCT FROM v_job.id THEN

    RAISE EXCEPTION
      'Worker output AI job does not match dispatch.';

  END IF;


  -- =======================================================
  -- PAYLOAD ROOT
  -- =======================================================

  IF jsonb_typeof(v_output.raw_output) <> 'object'
     OR v_output.raw_output ->> 'schema_version'
        IS DISTINCT FROM '1.0'
     OR jsonb_typeof(
          v_output.raw_output -> 'questions'
        ) <> 'array'
  THEN

    UPDATE public.ai_worker_outputs
    SET
      status = 'rejected',

      error_data =
        jsonb_build_object(
          'reason',
          'invalid_root_payload'
        ),

      validated_at =
        clock_timestamp()

    WHERE id = v_output.id;


    RAISE EXCEPTION
      'Invalid AI worker payload root structure.';

  END IF;


  v_received_count :=
    jsonb_array_length(
      v_output.raw_output -> 'questions'
    );


  -- =======================================================
  -- MEVCUT STAGING SAYISI
  --
  -- Aynı dispatch için önceki worker cevapları olabilir.
  -- =======================================================

  SELECT COUNT(*)
  INTO v_existing_generated_count

  FROM public.ai_question_staging s

  WHERE s.competition_factory_dispatch_id =
        v_dispatch.id

    AND s.staging_status <> 'rejected';


  -- =======================================================
  -- HER CANDIDATE
  -- =======================================================

  FOR v_candidate IN

    SELECT value

    FROM jsonb_array_elements(
      v_output.raw_output -> 'questions'
    )

  LOOP

    v_candidate_key :=
      NULLIF(
        btrim(
          COALESCE(
            v_candidate ->> 'client_question_id',
            ''
          )
        ),
        ''
      );


    v_validation :=
      private.validate_ai_question_candidate(
        v_candidate,
        v_spec.id
      );


    v_errors :=
      COALESCE(
        v_validation -> 'errors',
        '[]'::jsonb
      );


    v_warnings :=
      COALESCE(
        v_validation -> 'warnings',
        '[]'::jsonb
      );


    -- -----------------------------------------------------
    -- Candidate audit kaydı.
    -- -----------------------------------------------------

    INSERT INTO public.ai_worker_candidate_results (
      worker_output_id,

      candidate_index,

      candidate_key,

      raw_candidate,

      validation_status,

      validation_errors,

      validation_warnings
    )

    VALUES (
      v_output.id,

      v_candidate_index,

      v_candidate_key,

      v_candidate,

      CASE
        WHEN (v_validation ->> 'valid')::boolean
          THEN 'valid'
        ELSE 'invalid'
      END,

      v_errors,

      v_warnings
    )

    ON CONFLICT (
      worker_output_id,
      candidate_index
    )

    DO UPDATE SET
      candidate_key =
        EXCLUDED.candidate_key,

      raw_candidate =
        EXCLUDED.raw_candidate,

      validation_status =
        EXCLUDED.validation_status,

      validation_errors =
        EXCLUDED.validation_errors,

      validation_warnings =
        EXCLUDED.validation_warnings;


    -- -----------------------------------------------------
    -- Invalid -> staging yok.
    -- -----------------------------------------------------

    IF NOT (v_validation ->> 'valid')::boolean THEN

      v_invalid_count :=
        v_invalid_count + 1;

      v_candidate_index :=
        v_candidate_index + 1;

      CONTINUE;

    END IF;


    v_valid_count :=
      v_valid_count + 1;


    -- =====================================================
    -- NORMALIZE
    -- =====================================================

    v_question_text :=
      btrim(
        v_candidate ->> 'question_text'
      );


    v_options :=
      v_candidate -> 'options';


    v_correct_answer :=
      upper(
        btrim(
          v_candidate ->> 'correct_answer'
        )
      );


    v_difficulty :=
      NULLIF(
        lower(
          btrim(
            COALESCE(
              v_candidate ->> 'difficulty',
              ''
            )
          )
        ),
        ''
      );


    v_cognitive :=
      NULLIF(
        lower(
          btrim(
            COALESCE(
              v_candidate ->> 'cognitive_type',
              ''
            )
          )
        ),
        ''
      );


    v_primary_type :=
      NULLIF(
        btrim(
          COALESCE(
            v_candidate ->> 'primary_question_type',
            ''
          )
        ),
        ''
      );


    BEGIN

      v_is_new_generation :=
        CASE
          WHEN lower(
            COALESCE(
              v_candidate ->> 'is_new_generation',
              ''
            )
          ) IN (
            'true',
            't',
            '1',
            'yes'
          )
          THEN true

          WHEN lower(
            COALESCE(
              v_candidate ->> 'is_new_generation',
              ''
            )
          ) IN (
            'false',
            'f',
            '0',
            'no'
          )
          THEN false

          ELSE
            COALESCE(
              v_spec.is_new_generation,
              true
            )
        END;

    EXCEPTION
      WHEN OTHERS THEN

        v_is_new_generation :=
          COALESCE(
            v_spec.is_new_generation,
            true
          );

    END;


    v_has_visual :=
      lower(
        COALESCE(
          v_candidate ->> 'has_visual',
          'false'
        )
      ) IN (
        'true',
        't',
        '1',
        'yes'
      );


    BEGIN

      v_solve_time :=
        NULLIF(
          v_candidate
            ->> 'estimated_solve_time_seconds',
          ''
        )::integer;

    EXCEPTION
      WHEN OTHERS THEN
        v_solve_time := NULL;

    END;


    -- =====================================================
    -- LOCAL DUPLICATE GUARD
    --
    -- Bu telif/semantic similarity kontrolü DEĞİL.
    -- Sadece aynı normalized soru metninin aynı dispatch'e
    -- iki kez staging insert edilmesini engeller.
    -- =====================================================

    IF EXISTS (
      SELECT 1

      FROM public.ai_question_staging s

      WHERE s.competition_factory_dispatch_id =
            v_dispatch.id

        AND lower(
              btrim(
                COALESCE(
                  s.question_text,
                  ''
                )
              )
            )
            =
            lower(
              btrim(v_question_text)
            )

        AND s.staging_status <> 'rejected'
    )
    THEN

      v_duplicate_count :=
        v_duplicate_count + 1;


      UPDATE public.ai_worker_candidate_results
      SET
        validation_status = 'duplicate',

        validation_warnings =
          validation_warnings
          || jsonb_build_array(
               'exact_normalized_question_text_already_exists_in_dispatch'
             )

      WHERE worker_output_id =
            v_output.id

        AND candidate_index =
            v_candidate_index;


      v_candidate_index :=
        v_candidate_index + 1;

      CONTINUE;

    END IF;


    -- =====================================================
    -- STAGING INSERT
    --
    -- ÖNEMLİ:
    -- commercial_use_allowed = false
    -- ownership = ai_original
    -- fakat telif/özgünlük review yapılmadan ticari izin yok.
    -- =====================================================

    INSERT INTO public.ai_question_staging (
      staging_source,

      ai_job_id,

      generation_spec_id,

      grade_level,

      subject_id,

      proposed_curriculum_version_id,

      proposed_topic_id,

      proposed_subtopic_id,

      question_text,

      option_a,

      option_b,

      option_c,

      option_d,

      option_e,

      proposed_correct_answer,

      proposed_difficulty,

      proposed_cognitive_type,

      proposed_primary_question_type,

      proposed_secondary_question_type,

      proposed_is_new_generation,

      proposed_has_visual,

      proposed_solve_time_seconds,

      ownership_status,

      license_status,

      commercial_use_allowed,

      copyright_risk_level,

      staging_status,

      metadata,

      competition_generation_request_id,

      competition_factory_dispatch_id
    )

    VALUES (
      'ai_generated',

      v_job.id,

      v_spec.id,

      v_spec.grade_level,

      v_spec.subject_id,

      v_spec.curriculum_version_id,

      v_spec.topic_id,

      v_spec.subtopic_id,

      v_question_text,

      NULLIF(
        btrim(v_options ->> 'A'),
        ''
      ),

      NULLIF(
        btrim(v_options ->> 'B'),
        ''
      ),

      NULLIF(
        btrim(v_options ->> 'C'),
        ''
      ),

      NULLIF(
        btrim(v_options ->> 'D'),
        ''
      ),

      NULLIF(
        btrim(v_options ->> 'E'),
        ''
      ),

      v_correct_answer,

      v_difficulty,

      v_cognitive,

      COALESCE(
        v_primary_type,
        v_spec.primary_question_type
      ),

      NULL,

      v_is_new_generation,

      v_has_visual,

      v_solve_time,

      'ai_original',

      'pending',

      false,

      'unknown',

      'validating',

      jsonb_build_object(

        'worker_output_id',
        v_output.id,

        'worker_candidate_index',
        v_candidate_index,

        'worker_candidate_key',
        v_candidate_key,

        'solution',
        COALESCE(
          v_candidate -> 'solution',
          '{}'::jsonb
        ),

        'analysis',
        COALESCE(
          v_candidate -> 'analysis',
          '{}'::jsonb
        ),

        'candidate_metadata',
        COALESCE(
          v_candidate -> 'metadata',
          '{}'::jsonb
        ),

        'required_outcome_id',
        v_dispatch.curriculum_requirements
          ->> 'outcome_id',

        'deterministic_ingestion_passed',
        true,

        'automatic_publication_allowed',
        false
      ),

      v_dispatch.competition_generation_request_id,

      v_dispatch.id
    )

    RETURNING id
    INTO v_staging_id;


    -- =====================================================
    -- AUDIT CANDIDATE RESULT
    -- =====================================================

    UPDATE public.ai_worker_candidate_results
    SET
      validation_status =
        'inserted',

      staging_question_id =
        v_staging_id

    WHERE worker_output_id =
          v_output.id

      AND candidate_index =
          v_candidate_index;


    -- =====================================================
    -- DETERMINISTIC STRUCTURE VALIDATION
    -- =====================================================

    INSERT INTO public.ai_validation_results (
      staging_question_id,

      ai_job_id,

      validator_type,

      validation_type,

      result,

      summary,

      details
    )

    VALUES (
      v_staging_id,

      v_job.id,

      'deterministic',

      'structure',

      'pass',

      'AI worker candidate passed deterministic ingestion structure validation.',

      jsonb_build_object(
        'worker_output_id',
        v_output.id,

        'candidate_index',
        v_candidate_index,

        'warnings',
        v_warnings
      )
    );


    -- =====================================================
    -- DETERMINISTIC ANSWER FORMAT VALIDATION
    --
    -- Bu matematiksel/doğruluk doğrulaması değildir.
    -- Sadece cevap formatı ve seçeneğin mevcut olmasıdır.
    -- =====================================================

    INSERT INTO public.ai_validation_results (
      staging_question_id,

      ai_job_id,

      validator_type,

      validation_type,

      result,

      summary,

      details
    )

    VALUES (
      v_staging_id,

      v_job.id,

      'deterministic',

      'answer',

      'pass',

      'Correct-answer field points to an existing option.',

      jsonb_build_object(
        'proposed_correct_answer',
        v_correct_answer,

        'important',
        'This does not prove the academic correctness of the answer. Independent solving is still required.'
      )
    );


    v_inserted_count :=
      v_inserted_count + 1;


    v_candidate_index :=
      v_candidate_index + 1;

  END LOOP;


  -- =======================================================
  -- TOPLAM DURUM
  -- =======================================================

  v_total_after_ingestion :=
    v_existing_generated_count
    + v_inserted_count;


  v_remaining :=
    GREATEST(
      0,

      v_dispatch.requested_question_count
      - v_total_after_ingestion
    );


  v_retry_required :=
    v_remaining > 0;


  -- =======================================================
  -- OUTPUT STATUS
  -- =======================================================

  IF v_inserted_count = 0
     AND v_invalid_count > 0 THEN

    v_final_output_status :=
      'rejected';

  ELSIF v_invalid_count > 0
        OR v_duplicate_count > 0 THEN

    v_final_output_status :=
      'partially_valid';

  ELSE

    v_final_output_status :=
      'ingested';

  END IF;


  -- =======================================================
  -- JOB STATUS
  --
  -- Burada "completed" AI generation worker işinin aday
  -- üretimini tamamladığı anlamına gelir.
  -- Soruların production onayı anlamına GELMEZ.
  -- =======================================================

  IF v_retry_required THEN

    IF v_job.attempt_count + 1
       < v_job.max_attempts THEN

      v_job_status :=
        'queued';

    ELSE

      v_job_status :=
        'completed_with_warnings';

    END IF;

  ELSE

    v_job_status :=
      'completed';

  END IF;


  -- =======================================================
  -- WORKER OUTPUT UPDATE
  -- =======================================================

  UPDATE public.ai_worker_outputs
  SET
    status =
      v_final_output_status,

    received_question_count =
      v_received_count,

    valid_question_count =
      v_valid_count,

    invalid_question_count =
      v_invalid_count,

    inserted_question_count =
      v_inserted_count,

    duplicate_question_count =
      v_duplicate_count,

    remaining_question_count =
      v_remaining,

    retry_required =
      v_retry_required,

    validation_summary =
      jsonb_build_object(

        'received',
        v_received_count,

        'valid',
        v_valid_count,

        'invalid',
        v_invalid_count,

        'inserted',
        v_inserted_count,

        'duplicates',
        v_duplicate_count,

        'existing_before_this_output',
        v_existing_generated_count,

        'total_after_ingestion',
        v_total_after_ingestion,

        'requested',
        v_dispatch.requested_question_count,

        'remaining',
        v_remaining
      ),

    validated_at =
      clock_timestamp(),

    ingested_at =
      CASE
        WHEN v_inserted_count > 0
        THEN clock_timestamp()
        ELSE NULL
      END

  WHERE id = v_output.id;


  -- =======================================================
  -- JOB UPDATE
  -- =======================================================

  UPDATE public.ai_jobs
  SET
    status =
      v_job_status,

    attempt_count =
      attempt_count + 1,

    completed_at =
      CASE
        WHEN v_job_status IN (
          'completed',
          'completed_with_warnings'
        )
        THEN clock_timestamp()
        ELSE NULL
      END,

    output_data =
      jsonb_build_object(

        'last_worker_output_id',
        v_output.id,

        'requested_question_count',
        v_dispatch.requested_question_count,

        'received_question_count',
        v_received_count,

        'inserted_question_count',
        v_inserted_count,

        'total_staging_count',
        v_total_after_ingestion,

        'remaining_question_count',
        v_remaining,

        'retry_required',
        v_retry_required,

        'production_publication',
        false
      )

  WHERE id = v_job.id;


  -- =======================================================
  -- DISPATCH COUNTERS
  -- =======================================================

  UPDATE public.competition_ai_factory_dispatches
  SET
    generated_count =
      v_total_after_ingestion,

    staging_count =
      (
        SELECT COUNT(*)

        FROM public.ai_question_staging s

        WHERE s.competition_factory_dispatch_id =
              v_dispatch.id
      ),

    status =
      CASE
        WHEN v_total_after_ingestion >=
             requested_question_count
          THEN 'reviewing'

        WHEN v_total_after_ingestion > 0
          THEN 'partially_completed'

        ELSE 'job_created'
      END,

    metadata =
      metadata
      || jsonb_build_object(

           'latest_worker_output_id',
           v_output.id,

           'remaining_generation_count',
           v_remaining,

           'retry_required',
           v_retry_required
         )

  WHERE id = v_dispatch.id;


  -- =======================================================
  -- REQUEST COUNTERS
  -- =======================================================

  UPDATE public.competition_ai_generation_requests
  SET
    generated_count =
      v_total_after_ingestion,

    staging_count =
      (
        SELECT COUNT(*)

        FROM public.ai_question_staging s

        WHERE s.competition_factory_dispatch_id =
              v_dispatch.id
      ),

    status =
      CASE
        WHEN v_total_after_ingestion >=
             requested_question_count
          THEN 'reviewing'

        WHEN v_total_after_ingestion > 0
          THEN 'partially_completed'

        ELSE status
      END,

    metadata =
      metadata
      || jsonb_build_object(

           'latest_worker_output_id',
           v_output.id,

           'remaining_generation_count',
           v_remaining,

           'retry_required',
           v_retry_required
         )

  WHERE id =
    v_dispatch.competition_generation_request_id;


  -- =======================================================
  -- RESULT
  -- =======================================================

  RETURN jsonb_build_object(

    'worker_output_id',
    v_output.id,

    'ai_job_id',
    v_job.id,

    'dispatch_id',
    v_dispatch.id,

    'received_question_count',
    v_received_count,

    'valid_question_count',
    v_valid_count,

    'invalid_question_count',
    v_invalid_count,

    'inserted_question_count',
    v_inserted_count,

    'duplicate_question_count',
    v_duplicate_count,

    'total_staging_count',
    v_total_after_ingestion,

    'requested_question_count',
    v_dispatch.requested_question_count,

    'remaining_question_count',
    v_remaining,

    'retry_required',
    v_retry_required,

    'job_status',
    v_job_status,

    'production_publication',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.ingest_ai_worker_output(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.ingest_ai_worker_output(uuid)
TO authenticated, service_role;


-- =========================================================
-- 8. PUBLIC INGEST RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.ingest_ai_worker_output(
  p_worker_output_id uuid
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.ingest_ai_worker_output(
    p_worker_output_id
  );
$$;


REVOKE ALL
ON FUNCTION public.ingest_ai_worker_output(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.ingest_ai_worker_output(uuid)
TO authenticated, service_role;


-- =========================================================
-- 9. RETRY GEREKSİNİM RAPORU
--
-- Worker'a tekrar kaç soru üretmesi gerektiğini söyler.
--
-- Bu fonksiyon AI çağırmaz.
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_ai_generation_retry_requirement(
  p_ai_job_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_result jsonb;
BEGIN

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       public.current_user_has_admin_permission(
         'ai.manage'
       )
       OR
       public.current_user_has_admin_permission(
         'questions.approve'
       )
     )
  THEN

    RAISE EXCEPTION
      'AI worker or admin permission required.';

  END IF;


  SELECT jsonb_build_object(

    'ai_job_id',
    j.id,

    'job_status',
    j.status,

    'attempt_count',
    j.attempt_count,

    'max_attempts',
    j.max_attempts,

    'dispatch_id',
    d.id,

    'requested_question_count',
    d.requested_question_count,

    'current_generated_count',
    (
      SELECT COUNT(*)

      FROM public.ai_question_staging s

      WHERE s.competition_factory_dispatch_id =
            d.id

        AND s.staging_status <> 'rejected'
    ),

    'remaining_question_count',
    GREATEST(
      0,

      d.requested_question_count
      -
      (
        SELECT COUNT(*)

        FROM public.ai_question_staging s

        WHERE s.competition_factory_dispatch_id =
              d.id

          AND s.staging_status <> 'rejected'
      )
    ),

    'retry_allowed',
    (
      j.attempt_count < j.max_attempts

      AND

      d.requested_question_count
      >
      (
        SELECT COUNT(*)

        FROM public.ai_question_staging s

        WHERE s.competition_factory_dispatch_id =
              d.id

          AND s.staging_status <> 'rejected'
      )
    ),

    'important',
    'Retry may generate only the missing quantity. Existing accepted staging questions must not be regenerated.',

    'automatic_publication_allowed',
    false
  )

  INTO v_result

  FROM public.ai_jobs j

  JOIN public.competition_ai_factory_dispatches d
    ON d.id =
       j.competition_factory_dispatch_id

  WHERE j.id =
    p_ai_job_id

    AND j.job_type =
        'question_generation';


  IF v_result IS NULL THEN

    RAISE EXCEPTION
      'Competition question-generation AI job not found.';

  END IF;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_ai_generation_retry_requirement(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_ai_generation_retry_requirement(uuid)
TO authenticated, service_role;


-- =========================================================
-- 10. OUTPUT DETAY RAPORU
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_ai_worker_output_report(
  p_worker_output_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_result jsonb;
BEGIN

  IF NOT (
    public.current_user_has_admin_permission(
      'ai.manage'
    )
    OR
    public.current_user_has_admin_permission(
      'questions.approve'
    )
    OR
    public.current_user_has_admin_permission(
      'questions.edit'
    )
  ) THEN

    RAISE EXCEPTION
      'Admin permission required.';

  END IF;


  SELECT jsonb_build_object(

    'worker_output',
    jsonb_build_object(

      'id',
      o.id,

      'ai_job_id',
      o.ai_job_id,

      'status',
      o.status,

      'provider_name',
      o.provider_name,

      'model_name',
      o.model_name,

      'prompt_version',
      o.prompt_version,

      'worker_version',
      o.worker_version,

      'requested_question_count',
      o.requested_question_count,

      'received_question_count',
      o.received_question_count,

      'valid_question_count',
      o.valid_question_count,

      'invalid_question_count',
      o.invalid_question_count,

      'inserted_question_count',
      o.inserted_question_count,

      'duplicate_question_count',
      o.duplicate_question_count,

      'remaining_question_count',
      o.remaining_question_count,

      'retry_required',
      o.retry_required,

      'validation_summary',
      o.validation_summary,

      'received_at',
      o.received_at,

      'validated_at',
      o.validated_at,

      'ingested_at',
      o.ingested_at
    ),

    'candidates',
    (
      SELECT COALESCE(
        jsonb_agg(

          jsonb_build_object(

            'candidate_index',
            c.candidate_index,

            'candidate_key',
            c.candidate_key,

            'validation_status',
            c.validation_status,

            'validation_errors',
            c.validation_errors,

            'validation_warnings',
            c.validation_warnings,

            'staging_question_id',
            c.staging_question_id
          )

          ORDER BY c.candidate_index
        ),

        '[]'::jsonb
      )

      FROM public.ai_worker_candidate_results c

      WHERE c.worker_output_id =
            o.id
    )

  )

  INTO v_result

  FROM public.ai_worker_outputs o

  WHERE o.id =
    p_worker_output_id;


  IF v_result IS NULL THEN

    RAISE EXCEPTION
      'AI worker output not found.';

  END IF;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_ai_worker_output_report(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_ai_worker_output_report(uuid)
TO authenticated, service_role;


-- =========================================================
-- 11. ADMIN RLS
-- =========================================================

DROP POLICY IF EXISTS
"admins manage ai worker outputs"
ON public.ai_worker_outputs;


CREATE POLICY
"admins manage ai worker outputs"
ON public.ai_worker_outputs
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission(
    'ai.manage'
  )
  OR
  public.current_user_has_admin_permission(
    'questions.approve'
  )
)
WITH CHECK (
  public.current_user_has_admin_permission(
    'ai.manage'
  )
  OR
  public.current_user_has_admin_permission(
    'questions.approve'
  )
);


DROP POLICY IF EXISTS
"admins manage ai worker candidate results"
ON public.ai_worker_candidate_results;


CREATE POLICY
"admins manage ai worker candidate results"
ON public.ai_worker_candidate_results
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission(
    'ai.manage'
  )
  OR
  public.current_user_has_admin_permission(
    'questions.approve'
  )
)
WITH CHECK (
  public.current_user_has_admin_permission(
    'ai.manage'
  )
  OR
  public.current_user_has_admin_permission(
    'questions.approve'
  )
);


-- =========================================================
-- 12. SERVICE ROLE
--
-- Backend worker gerektiğinde doğrudan tablo işlemleri için
-- service_role kullanabilir.
--
-- Secret/service-role key ASLA browser/client içine konmaz.
-- =========================================================

GRANT SELECT, INSERT, UPDATE
ON public.ai_worker_outputs
TO service_role;


GRANT SELECT, INSERT, UPDATE
ON public.ai_worker_candidate_results
TO service_role;


-- =========================================================
-- 13. ADMIN OVERVIEW
-- =========================================================

CREATE OR REPLACE VIEW public.ai_worker_output_overview
WITH (security_invoker = true)
AS

SELECT
  o.id AS worker_output_id,

  o.ai_job_id,

  o.generation_spec_id,

  o.competition_generation_request_id,

  o.competition_factory_dispatch_id,

  o.provider_name,

  o.model_name,

  o.prompt_version,

  o.worker_version,

  o.status,

  o.requested_question_count,

  o.received_question_count,

  o.valid_question_count,

  o.invalid_question_count,

  o.inserted_question_count,

  o.duplicate_question_count,

  o.remaining_question_count,

  o.retry_required,

  o.received_at,

  o.validated_at,

  o.ingested_at

FROM public.ai_worker_outputs o;


REVOKE ALL
ON public.ai_worker_output_overview
FROM PUBLIC;


REVOKE ALL
ON public.ai_worker_output_overview
FROM anon;


GRANT SELECT
ON public.ai_worker_output_overview
TO authenticated;


-- =========================================================
-- 14. PRIVATE DEFAULT SECURITY
-- =========================================================

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA private
REVOKE EXECUTE ON FUNCTIONS
FROM PUBLIC;


ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA private
REVOKE EXECUTE ON FUNCTIONS
FROM anon;


COMMIT;