-- 117_faz14a_candidate_question_batch.sql
-- Altın Kalemler
--
-- Dış üreticilerden/farklı AI modellerinden gelen soruların
-- ai_question_staging alanına aday olarak alınması için candidate
-- question batch intake + C-1 toplu denetim altyapısı.
--
-- Bu migration:
--
-- 1. candidate_question_batches tablosu (ai_worker_outputs
--    deseni, ai_job/factory dispatch bağımlılıkları YOK).
-- 2. candidate_batch_candidate_results tablosu (per-candidate
--    audit kayıtları).
-- 3. Deterministik paket + soru doğrulama fonksiyonu.
-- 4. register_candidate_question_batch RPC:
--    - Deterministik yapı doğrulaması
--    - Duplicate guardian相同 normalized question_text
--    - ai_question_staging INSERT
--    - ai_validation_results deterministic audit
--    - review_queue可疑 insert
--    - Otomatik publication YAPMAZ.
-- 5. get_candidate_question_batch_contract() sözleşmesi.
-- 6. RLS + GRANT/REVOKE.
--
-- Idempotent: tekrar uygulama hata vermez.

BEGIN;


-- =========================================================
-- 1. CANDIDATE QUESTION BATCHES
--
-- ai_worker_outputs ile aynı desen; ancak AI job /
-- competition factory dispatch bağımlılıkları YOKTUR.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.candidate_question_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  batch_key text NOT NULL UNIQUE,

  schema_version text NOT NULL DEFAULT '1.0'
    CHECK (schema_version = '1.0'),

  origin text NOT NULL
    CHECK (origin IN ('curriculum_original')),

  producer_id text NOT NULL,

  producer_model text,

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

  total_items integer NOT NULL DEFAULT 0
    CHECK (total_items >= 0),

  valid_items integer NOT NULL DEFAULT 0
    CHECK (valid_items >= 0),

  invalid_items integer NOT NULL DEFAULT 0
    CHECK (invalid_items >= 0),

  inserted_items integer NOT NULL DEFAULT 0
    CHECK (inserted_items >= 0),

  duplicate_items integer NOT NULL DEFAULT 0
    CHECK (duplicate_items >= 0),

  validation_summary jsonb NOT NULL DEFAULT '{}'::jsonb,

  error_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  raw_payload jsonb NOT NULL,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS idx_candidate_question_batches_status
ON public.candidate_question_batches(status, created_at DESC);


CREATE INDEX IF NOT EXISTS idx_candidate_question_batches_producer
ON public.candidate_question_batches(producer_id, created_at DESC);


ALTER TABLE public.candidate_question_batches
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS trigger_candidate_question_batches_updated_at
ON public.candidate_question_batches;


CREATE TRIGGER trigger_candidate_question_batches_updated_at
BEFORE UPDATE ON public.candidate_question_batches
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. PER-CANDIDATE RESULTS
-- =========================================================

CREATE TABLE IF NOT EXISTS public.candidate_batch_candidate_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  batch_id uuid NOT NULL
    REFERENCES public.candidate_question_batches(id)
    ON DELETE CASCADE,

  candidate_index integer NOT NULL
    CHECK (candidate_index >= 0),

  client_question_id text,

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

  UNIQUE (batch_id, candidate_index)
);


CREATE INDEX IF NOT EXISTS idx_candidate_batch_results_batch
ON public.candidate_batch_candidate_results(batch_id, validation_status);


CREATE INDEX IF NOT EXISTS idx_candidate_batch_results_staging
ON public.candidate_batch_candidate_results(staging_question_id);


ALTER TABLE public.candidate_batch_candidate_results
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS trigger_candidate_batch_candidate_results_updated_at
ON public.candidate_batch_candidate_results;


CREATE TRIGGER trigger_candidate_batch_candidate_results_updated_at
BEFORE UPDATE ON public.candidate_batch_candidate_results
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. DETERMİSTİK SORU DOĞRULAYICI
-- =========================================================

CREATE OR REPLACE FUNCTION private.validate_candidate_question_batch_candidate(
  p_candidate jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
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
  v_origin text;

  v_option_values text[];
  v_option_count integer;
  v_unique_option_count integer;

  v_solution jsonb;
  v_steps jsonb;
BEGIN

  IF p_candidate IS NULL
     OR jsonb_typeof(p_candidate) <> 'object' THEN

    RETURN jsonb_build_object(
      'valid', false,
      'errors', jsonb_build_array('candidate_must_be_json_object'),
      'warnings', '[]'::jsonb
    );

  END IF;


  -- =======================================================
  -- QUESTION TEXT
  -- =======================================================

  v_question_text := btrim(COALESCE(p_candidate ->> 'question_text', ''));

  IF length(v_question_text) < 10 THEN
    v_errors := v_errors || jsonb_build_array('question_text_missing_or_too_short');
  END IF;


  -- =======================================================
  -- OPTIONS
  -- =======================================================

  v_options := p_candidate -> 'options';

  IF v_options IS NULL
     OR jsonb_typeof(v_options) <> 'object' THEN

    v_errors := v_errors || jsonb_build_array('options_must_be_object');

  ELSE

    v_a := btrim(COALESCE(v_options ->> 'A', ''));
    v_b := btrim(COALESCE(v_options ->> 'B', ''));
    v_c := btrim(COALESCE(v_options ->> 'C', ''));
    v_d := btrim(COALESCE(v_options ->> 'D', ''));
    v_e := btrim(COALESCE(v_options ->> 'E', ''));

    IF v_a = '' THEN v_errors := v_errors || jsonb_build_array('option_A_missing'); END IF;
    IF v_b = '' THEN v_errors := v_errors || jsonb_build_array('option_B_missing'); END IF;
    IF v_c = '' THEN v_errors := v_errors || jsonb_build_array('option_C_missing'); END IF;
    IF v_d = '' THEN v_errors := v_errors || jsonb_build_array('option_D_missing'); END IF;

    v_option_values := ARRAY[
      NULLIF(lower(v_a), ''),
      NULLIF(lower(v_b), ''),
      NULLIF(lower(v_c), ''),
      NULLIF(lower(v_d), ''),
      NULLIF(lower(v_e), '')
    ];

    SELECT COUNT(*), COUNT(DISTINCT x)
    INTO v_option_count, v_unique_option_count
    FROM unnest(v_option_values) AS t(x)
    WHERE x IS NOT NULL;

    IF v_option_count <> v_unique_option_count THEN
      v_errors := v_errors || jsonb_build_array('duplicate_option_text_detected');
    END IF;

  END IF;


  -- =======================================================
  -- CORRECT ANSWER
  -- =======================================================

  v_correct_answer := upper(btrim(COALESCE(p_candidate ->> 'correct_answer', '')));

  IF v_correct_answer NOT IN ('A', 'B', 'C', 'D', 'E') THEN
    v_errors := v_errors || jsonb_build_array('correct_answer_invalid');
  END IF;

  IF v_correct_answer = 'E' AND COALESCE(v_e, '') = '' THEN
    v_errors := v_errors || jsonb_build_array('correct_answer_points_to_missing_option_E');
  END IF;


  -- =======================================================
  -- DIFFICULTY
  -- =======================================================

  v_difficulty := lower(btrim(COALESCE(p_candidate ->> 'difficulty', '')));

  IF v_difficulty <> ''
     AND v_difficulty NOT IN ('easy', 'medium', 'hard') THEN
    v_errors := v_errors || jsonb_build_array('difficulty_invalid');
  END IF;


  -- =======================================================
  -- COGNITIVE TYPE
  -- =======================================================

  v_cognitive := lower(btrim(COALESCE(p_candidate ->> 'cognitive_type', '')));

  IF v_cognitive <> ''
     AND v_cognitive NOT IN ('learning', 'comprehension', 'application') THEN
    v_errors := v_errors || jsonb_build_array('cognitive_type_invalid');
  END IF;


  -- =======================================================
  -- SOLVE TIME
  -- =======================================================

  BEGIN
    IF p_candidate ? 'estimated_solve_time_seconds'
       AND p_candidate ->> 'estimated_solve_time_seconds' IS NOT NULL THEN
      v_solve_time := (p_candidate ->> 'estimated_solve_time_seconds')::integer;
    ELSE
      v_solve_time := NULL;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      v_solve_time := NULL;
      v_errors := v_errors || jsonb_build_array('estimated_solve_time_seconds_invalid');
  END;

  IF v_solve_time IS NOT NULL AND v_solve_time <= 0 THEN
    v_errors := v_errors || jsonb_build_array('estimated_solve_time_seconds_must_be_positive');
  END IF;


  -- =======================================================
  -- SOLUTION (opsiyonel ama varsa kontroller)
  -- =======================================================

  IF p_candidate ? 'solution' THEN
    v_solution := p_candidate -> 'solution';

    IF v_solution IS NULL
       OR jsonb_typeof(v_solution) <> 'object' THEN
      v_errors := v_errors || jsonb_build_array('solution_must_be_object');
    ELSE
      IF btrim(COALESCE(v_solution ->> 'method', '')) = '' THEN
        v_errors := v_errors || jsonb_build_array('solution_method_empty');
      END IF;

      v_steps := v_solution -> 'steps';

      IF v_steps IS NULL
         OR jsonb_typeof(v_steps) <> 'array'
         OR jsonb_array_length(v_steps) = 0 THEN
        v_errors := v_errors || jsonb_build_array('solution_steps_empty');
      END IF;

      IF btrim(COALESCE(v_solution ->> 'result', '')) = '' THEN
        v_errors := v_errors || jsonb_build_array('solution_result_empty');
      END IF;

      IF btrim(COALESCE(v_solution ->> 'correctAnswerJustification', '')) = '' THEN
        v_errors := v_errors || jsonb_build_array('solution_justification_empty');
      END IF;
    END IF;
  END IF;


  -- =======================================================
  -- GRADE LEVEL
  -- =======================================================

  BEGIN
    IF p_candidate ? 'grade_level' THEN
      DECLARE
        v_grade integer;
      BEGIN
        v_grade := (p_candidate ->> 'grade_level')::integer;
        IF v_grade < 1 OR v_grade > 12 THEN
          v_errors := v_errors || jsonb_build_array('grade_level_out_of_range');
        END IF;
      END;
    ELSE
      v_errors := v_errors || jsonb_build_array('grade_level_missing');
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_array('grade_level_invalid');
  END;


  -- =======================================================
  -- SUBJECT ID (UUID format)
  -- =======================================================

  IF NOT (p_candidate ? 'subject_id')
     OR btrim(COALESCE(p_candidate ->> 'subject_id', '')) = '' THEN
    v_errors := v_errors || jsonb_build_array('subject_id_missing');
  ELSIF NOT (p_candidate ->> 'subject_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
    v_errors := v_errors || jsonb_build_array('subject_id_not_uuid');
  END IF;


  -- =======================================================
  -- OUTCOME CODE
  -- =======================================================

  IF NOT (p_candidate ? 'outcome_code')
     OR btrim(COALESCE(p_candidate ->> 'outcome_code', '')) = '' THEN
    v_errors := v_errors || jsonb_build_array('outcome_code_missing');
  ELSIF NOT (p_candidate ->> 'outcome_code' ~ '^[A-Za-z0-9._-]+$') THEN
    v_errors := v_errors || jsonb_build_array('outcome_code_invalid_format');
  END IF;


  -- =======================================================
  -- ORIGIN CHECK (forbidden fields)
  -- =======================================================

  IF p_candidate ? 'source_question_text'
     OR p_candidate ? 'pdf_reference'
     OR p_candidate ? 'crop_reference'
     OR p_candidate ? 'image_data'
     OR p_candidate ? 'image_url'
     OR p_candidate ? 'source_page_number'
     OR p_candidate ? 'source_test_code'
     OR p_candidate ? 'source_question_code'
     OR p_candidate ? 'derived_from_question_id'
     OR p_candidate ? 'derived_from_source_id'
  THEN
    v_errors := v_errors || jsonb_build_array('forbidden_source_derived_fields_present');
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
ON FUNCTION private.validate_candidate_question_batch_candidate(jsonb)
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 4. PAKET DOĞRULAMA + YERLEŞTİRME (PRIVATE)
-- =========================================================

CREATE OR REPLACE FUNCTION private.register_candidate_question_batch(
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_batch_id uuid;
  v_batch_key text;
  v_producer_id text;
  v_producer_model text;
  v_origin text;
  v_question jsonb;
  v_candidate_index integer := 0;
  v_client_question_id text;

  v_received_count integer := 0;
  v_valid_count integer := 0;
  v_invalid_count integer := 0;
  v_inserted_count integer := 0;
  v_duplicate_count integer := 0;

  v_staging_id uuid;
  v_question_text text;
  v_options jsonb;
  v_correct_answer text;
  v_difficulty text;
  v_cognitive text;
  v_solve_time integer;
  v_grade_level integer;
  v_subject_id uuid;
  v_outcome_code text;
  v_solution jsonb;

  v_validation jsonb;
  v_errors jsonb;
  v_warnings jsonb;

  v_final_status text;

  v_staging_ids jsonb := '[]'::jsonb;

  -- Duplicate guard: aynı batch_key tekrar geldiyse idempotent dön
  v_existing_batch public.candidate_question_batches%ROWTYPE;
BEGIN

  -- =======================================================
  -- Caller
  -- =======================================================

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR
       private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Candidate batch intake requires AI or admin permission.';
  END IF;


  -- =======================================================
  -- ROOT VALIDATION
  -- =======================================================

  IF p_payload IS NULL
     OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'Payload must be a JSON object.';
  END IF;

  IF p_payload ->> 'schema_version' IS DISTINCT FROM '1.0' THEN
    RAISE EXCEPTION 'Unsupported schema version.';
  END IF;

  IF p_payload ->> 'origin' IS DISTINCT FROM 'curriculum_original' THEN
    RAISE EXCEPTION 'Origin must be curriculum_original.';
  END IF;

  IF p_payload->'producer' IS NULL
     OR jsonb_typeof(p_payload->'producer') <> 'object'
     OR btrim(COALESCE(p_payload->'producer' ->> 'id', '')) = '' THEN
    RAISE EXCEPTION 'Producer id is required.';
  END IF;

  IF NOT (p_payload ? 'questions')
     OR jsonb_typeof(p_payload -> 'questions') <> 'array'
     OR jsonb_array_length(p_payload -> 'questions') = 0 THEN
    RAISE EXCEPTION 'Questions array must be non-empty.';
  END IF;


  -- =======================================================
  -- PRODUCER + BATCH KEY
  -- =======================================================

  v_producer_id := btrim(p_payload->'producer' ->> 'id');
  v_producer_model := NULLIF(btrim(COALESCE(p_payload->'producer' ->> 'model', '')), '');
  v_origin := p_payload ->> 'origin';

  v_batch_key := v_producer_id || ':' || encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex');

  -- Idempotent: Aynı batch_key varsa mevcut sonucu dön
  SELECT * INTO v_existing_batch
  FROM public.candidate_question_batches b
  WHERE b.batch_key = v_batch_key;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'batch_id', v_existing_batch.id,
      'status', 'already_received',
      'staging_ids',
        (
          SELECT COALESCE(jsonb_agg(r.staging_question_id), '[]'::jsonb)
          FROM public.candidate_batch_candidate_results r
          WHERE r.batch_id = v_existing_batch.id
            AND r.validation_status = 'inserted'
        ),
      'total_items', v_existing_batch.total_items,
      'valid_items', v_existing_batch.valid_items,
      'invalid_items', v_existing_batch.invalid_items,
      'inserted_items', v_existing_batch.inserted_items,
      'duplicate_items', v_existing_batch.duplicate_items
    );
  END IF;


  -- =======================================================
  -- BATCH KAYDI
  -- =======================================================

  INSERT INTO public.candidate_question_batches (
    batch_key,
    schema_version,
    origin,
    producer_id,
    producer_model,
    status,
    total_items,
    raw_payload
  )
  VALUES (
    v_batch_key,
    '1.0',
    v_origin,
    v_producer_id,
    v_producer_model,
    'validating',
    jsonb_array_length(p_payload -> 'questions'),
    p_payload
  )
  RETURNING id INTO v_batch_id;


  -- =======================================================
  -- HER CANDIDATE
  -- =======================================================

  FOR v_question IN
    SELECT value
    FROM jsonb_array_elements(p_payload -> 'questions')
  LOOP

    v_received_count := v_received_count + 1;
    v_client_question_id := NULLIF(btrim(COALESCE(v_question ->> 'client_question_id', '')), '');

    v_validation := private.validate_candidate_question_batch_candidate(v_question);
    v_errors := COALESCE(v_validation -> 'errors', '[]'::jsonb);
    v_warnings := COALESCE(v_validation -> 'warnings', '[]'::jsonb);

    -- Candidate audit kaydı
    INSERT INTO public.candidate_batch_candidate_results (
      batch_id,
      candidate_index,
      client_question_id,
      validation_status,
      validation_errors,
      validation_warnings
    )
    VALUES (
      v_batch_id,
      v_candidate_index,
      v_client_question_id,
      CASE WHEN (v_validation ->> 'valid')::boolean THEN 'valid' ELSE 'invalid' END,
      v_errors,
      v_warnings
    );

    -- Invalid → staging insert yok
    IF NOT (v_validation ->> 'valid')::boolean THEN
      v_invalid_count := v_invalid_count + 1;
      v_candidate_index := v_candidate_index + 1;
      CONTINUE;
    END IF;

    v_valid_count := v_valid_count + 1;

    -- =====================================================
    -- NORMALIZE
    -- =====================================================

    v_question_text := btrim(v_question ->> 'question_text');
    v_options := v_question -> 'options';
    v_correct_answer := upper(btrim(v_question ->> 'correct_answer'));

    v_difficulty := NULLIF(lower(btrim(COALESCE(v_question ->> 'difficulty', ''))), '');
    v_cognitive := NULLIF(lower(btrim(COALESCE(v_question ->> 'cognitive_type', ''))), '');

    BEGIN
      v_solve_time := NULLIF(v_question ->> 'estimated_solve_time_seconds', '')::integer;
    EXCEPTION WHEN OTHERS THEN
      v_solve_time := NULL;
    END;

    BEGIN
      v_grade_level := (v_question ->> 'grade_level')::integer;
    EXCEPTION WHEN OTHERS THEN
      v_grade_level := NULL;
    END;

    BEGIN
      v_subject_id := (v_question ->> 'subject_id')::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_subject_id := NULL;
    END;

    v_outcome_code := NULLIF(btrim(COALESCE(v_question ->> 'outcome_code', '')), '');
    v_solution := v_question -> 'solution';


    -- =====================================================
    -- LOCAL DUPLICATE GUARD
    -- =====================================================

    IF EXISTS (
      SELECT 1
      FROM public.candidate_batch_candidate_results r
      JOIN public.ai_question_staging s ON s.id = r.staging_question_id
      WHERE r.batch_id = v_batch_id
        AND r.validation_status = 'inserted'
        AND lower(btrim(COALESCE(s.question_text, ''))) = lower(btrim(v_question_text))
    )
    THEN
      v_duplicate_count := v_duplicate_count + 1;

      UPDATE public.candidate_batch_candidate_results
      SET
        validation_status = 'duplicate',
        validation_warnings = validation_warnings || jsonb_build_array('duplicate_normalized_question_text')
      WHERE batch_id = v_batch_id
        AND candidate_index = v_candidate_index;

      v_candidate_index := v_candidate_index + 1;
      CONTINUE;
    END IF;


    -- =====================================================
    -- STAGING INSERT
    -- =====================================================

    INSERT INTO public.ai_question_staging (
      staging_source,
      grade_level,
      subject_id,
      question_text,
      option_a,
      option_b,
      option_c,
      option_d,
      option_e,
      proposed_correct_answer,
      proposed_difficulty,
      proposed_cognitive_type,
      proposed_solve_time_seconds,
      ownership_status,
      license_status,
      commercial_use_allowed,
      copyright_risk_level,
      staging_status,
      metadata
    )
    VALUES (
      'manual_candidate',
      v_grade_level,
      v_subject_id,
      v_question_text,
      NULLIF(btrim(v_options ->> 'A'), ''),
      NULLIF(btrim(v_options ->> 'B'), ''),
      NULLIF(btrim(v_options ->> 'C'), ''),
      NULLIF(btrim(v_options ->> 'D'), ''),
      NULLIF(btrim(v_options ->> 'E'), ''),
      v_correct_answer,
      v_difficulty,
      v_cognitive,
      v_solve_time,
      'ai_original',
      'pending',
      false,
      'unknown',
      'validating',
      jsonb_build_object(
        'candidate_batch_id', v_batch_id,
        'client_question_id', v_client_question_id,
        'producer_id', v_producer_id,
        'producer_model', v_producer_model,
        'origin', v_origin,
        'solution', COALESCE(v_solution, '{}'::jsonb),
        'deterministic_ingestion_passed', true,
        'automatic_publication_allowed', false,
        'final_readiness_status', 'pending'
      )
    )
    RETURNING id INTO v_staging_id;


    -- =====================================================
    -- CANDIDATE RESULT UPDATE
    -- =====================================================

    UPDATE public.candidate_batch_candidate_results
    SET
      validation_status = 'inserted',
      staging_question_id = v_staging_id
    WHERE batch_id = v_batch_id
      AND candidate_index = v_candidate_index;


    -- =====================================================
    -- DETERMINISTIC STRUCTURE VALIDATION
    -- =====================================================

    INSERT INTO public.ai_validation_results (
      staging_question_id,
      validator_type,
      validation_type,
      result,
      summary,
      details
    )
    VALUES (
      v_staging_id,
      'deterministic',
      'structure',
      'pass',
      'Candidate passed deterministic intake structure validation.',
      jsonb_build_object(
        'batch_id', v_batch_id,
        'candidate_index', v_candidate_index,
        'warnings', v_warnings
      )
    );


    -- =====================================================
    -- DETERMINISTIC ANSWER FORMAT VALIDATION
    -- =====================================================

    INSERT INTO public.ai_validation_results (
      staging_question_id,
      validator_type,
      validation_type,
      result,
      summary,
      details
    )
    VALUES (
      v_staging_id,
      'deterministic',
      'answer',
      'pass',
      'Correct-answer field points to an existing option.',
      jsonb_build_object(
        'proposed_correct_answer', v_correct_answer,
        'important', 'This does not prove the academic correctness of the answer. Independent solving is still required.'
      )
    );


    -- =====================================================
    -- REVIEW QUEUE (şüpheli/eksik)
    --
    -- solution.steps boşsa veya grade level yoksa
    -- inceleme kuyruğuna ekle (fail-closed).
    -- =====================================================

    IF v_solution IS NULL
       OR NOT (v_solution ? 'steps')
       OR jsonb_array_length(COALESCE(v_solution -> 'steps', '[]'::jsonb)) = 0
       OR v_grade_level IS NULL
       OR v_subject_id IS NULL
    THEN
      INSERT INTO public.review_queue (
        entity_type,
        entity_id,
        reason_code,
        reason_details,
        priority,
        status
      )
      VALUES (
        'staging_question',
        v_staging_id,
        'candidate_batch_intake_incomplete',
        jsonb_build_object(
          'batch_id', v_batch_id,
          'candidate_index', v_candidate_index,
          'missing_solution_steps',
          v_solution IS NULL OR NOT (v_solution ? 'steps')
            OR jsonb_array_length(COALESCE(v_solution -> 'steps', '[]'::jsonb)) = 0,
          'missing_grade_level', v_grade_level IS NULL,
          'missing_subject_id', v_subject_id IS NULL
        ),
        'normal',
        'open'
      );

      -- staging status: review_queue yönlendirmesi
      UPDATE public.ai_question_staging
      SET staging_status = 'needs_review',
          metadata = metadata || jsonb_build_object(
            'final_readiness_status', 'needs_review',
            'needs_review_reason', 'candidate_batch_intake_incomplete'
          )
      WHERE id = v_staging_id;

    ELSE
      -- Tüm deterministik kontroller geçti
      UPDATE public.ai_question_staging
      SET metadata = metadata || jsonb_build_object(
        'final_readiness_status', 'pending',
        'candidate_batch_deterministic_checks_passed', true
      )
      WHERE id = v_staging_id;
    END IF;


    -- staging_ids listesine ekle
    v_staging_ids := v_staging_ids || to_jsonb(v_staging_id);

    v_inserted_count := v_inserted_count + 1;
    v_candidate_index := v_candidate_index + 1;

  END LOOP;


  -- =======================================================
  -- BATCH STATUS
  -- =======================================================

  IF v_inserted_count = 0 AND v_invalid_count > 0 THEN
    v_final_status := 'rejected';
  ELSIF v_invalid_count > 0 OR v_duplicate_count > 0 THEN
    v_final_status := 'partially_valid';
  ELSE
    v_final_status := 'ingested';
  END IF;


  UPDATE public.candidate_question_batches
  SET
    status = v_final_status,
    valid_items = v_valid_count,
    invalid_items = v_invalid_count,
    inserted_items = v_inserted_count,
    duplicate_items = v_duplicate_count,
    validation_summary = jsonb_build_object(
      'received', v_received_count,
      'valid', v_valid_count,
      'invalid', v_invalid_count,
      'inserted', v_inserted_count,
      'duplicates', v_duplicate_count
    )
  WHERE id = v_batch_id;


  -- =======================================================
  -- RESULT
  -- =======================================================

  RETURN jsonb_build_object(
    'batch_id', v_batch_id,
    'batch_key', v_batch_key,
    'status', v_final_status,
    'staging_ids', v_staging_ids,
    'total_items', v_received_count,
    'valid_items', v_valid_count,
    'invalid_items', v_invalid_count,
    'inserted_items', v_inserted_count,
    'duplicate_items', v_duplicate_count,
    'automatic_publication_allowed', false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.register_candidate_question_batch(jsonb)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.register_candidate_question_batch(jsonb)
TO authenticated, service_role;


-- =========================================================
-- 5. PUBLIC RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.register_candidate_question_batch(
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.register_candidate_question_batch(p_payload);
$$;


REVOKE ALL
ON FUNCTION public.register_candidate_question_batch(jsonb)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.register_candidate_question_batch(jsonb)
TO authenticated, service_role;


-- =========================================================
-- 6. SÖZLEŞME
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_candidate_question_batch_contract()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'schema_version', '1.0',
    'origin', jsonb_build_object(
      'allowed', jsonb_build_array('curriculum_original'),
      'description', 'Only curriculum-original content is accepted. PDF-derived or source-rewritten questions are forbidden.'
    ),
    'producer', jsonb_build_object(
      'required', jsonb_build_array('id'),
      'id_type', 'text',
      'model_optional', true
    ),
    'question', jsonb_build_object(
      'required', jsonb_build_array(
        'grade_level', 'subject_id', 'outcome_code', 'question_text', 'options', 'correct_answer'
      ),
      'grade_level', jsonb_build_object(
        'type', 'integer',
        'min', 1,
        'max', 12
      ),
      'subject_id', jsonb_build_object(
        'type', 'uuid'
      ),
      'outcome_code', jsonb_build_object(
        'type', 'string',
        'pattern', '^[A-Za-z0-9._-]+$'
      ),
      'question_text', jsonb_build_object(
        'type', 'string',
        'minimum_length', 10
      ),
      'options', jsonb_build_object(
        'type', 'object',
        'required_keys', jsonb_build_array('A', 'B', 'C', 'D'),
        'optional_keys', jsonb_build_array('E')
      ),
      'correct_answer', jsonb_build_object(
        'type', 'text',
        'allowed', jsonb_build_array('A', 'B', 'C', 'D', 'E')
      ),
      'difficulty', jsonb_build_object(
        'type', 'text',
        'allowed', jsonb_build_array('easy', 'medium', 'hard'),
        'optional', true
      ),
      'cognitive_type', jsonb_build_object(
        'type', 'text',
        'allowed', jsonb_build_array('learning', 'comprehension', 'application'),
        'optional', true
      ),
      'estimated_solve_time_seconds', jsonb_build_object(
        'type', 'positive_integer',
        'optional', true
      ),
      'solution', jsonb_build_object(
        'type', 'object',
        'optional', true,
        'fields', jsonb_build_object(
          'method', 'text',
          'steps', 'non_empty_array',
          'result', 'text',
          'correctAnswerJustification', 'text'
        )
      )
    ),
    'forbidden_fields', jsonb_build_array(
      'source_question_text', 'pdf_reference', 'crop_reference',
      'image_data', 'image_url', 'source_page_number', 'source_test_code',
      'source_question_code', 'derived_from_question_id', 'derived_from_source_id'
    ),
    'important_rules', jsonb_build_array(
      'Each question must be original.',
      'Existing source questions may not be rewritten by merely changing wording, names or numbers.',
      'The correct answer must be independently solvable.',
      'Question grade and curriculum fit must be reviewed.',
      'Question-specific solve-time analysis is required.',
      'Candidates may only enter staging.',
      'Automatic production publication is forbidden.',
      'Suspicious or incomplete candidates are routed to review_queue.'
    )
  );
$$;


REVOKE EXECUTE
ON FUNCTION public.get_candidate_question_batch_contract()
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_candidate_question_batch_contract()
TO authenticated, service_role;


-- =========================================================
-- 7. RLS — admin manage + service_role
-- =========================================================

DROP POLICY IF EXISTS "admins manage candidate question batches"
ON public.candidate_question_batches;


CREATE POLICY "admins manage candidate question batches"
ON public.candidate_question_batches
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('ai.manage')
  OR
  public.current_user_has_admin_permission('questions.approve')
)
WITH CHECK (
  public.current_user_has_admin_permission('ai.manage')
  OR
  public.current_user_has_admin_permission('questions.approve')
);


DROP POLICY IF EXISTS "admins manage candidate batch candidate results"
ON public.candidate_batch_candidate_results;


CREATE POLICY "admins manage candidate batch candidate results"
ON public.candidate_batch_candidate_results
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('ai.manage')
  OR
  public.current_user_has_admin_permission('questions.approve')
)
WITH CHECK (
  public.current_user_has_admin_permission('ai.manage')
  OR
  public.current_user_has_admin_permission('questions.approve')
);


GRANT SELECT, INSERT, UPDATE
ON public.candidate_question_batches
TO service_role;


GRANT SELECT, INSERT, UPDATE
ON public.candidate_batch_candidate_results
TO service_role;


-- =========================================================
-- 8. PRIVATE DEFAULT SECURITY
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
