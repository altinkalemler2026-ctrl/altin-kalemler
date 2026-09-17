-- 118_faz15c_external_candidate_generation_spec_binding.sql
-- Faz 15C: Harici aday paketini mevcut AI denetim sözleşmesine bağla.
--
-- Sorun (Faz 15B): curriculum_original harici üretici adayları
-- staging_source='manual_candidate' ile giriyor ve generation_spec
-- bağı taşımıyordu. Bu yüzden:
--   * 033 start_answer_verification   → "intended for AI generated";
--   * 034 start_curriculum_fit_verification → "Generation spec is required";
--   * 035 start_solve_time_verification    → "Generation spec is required".
--
-- Çözüm (append-only; eski migration değiştirilmez):
--   1. ai_question_staging.staging_source allowlist'ine 'external_producer' ekle
--      (harici üretici kaynaklı aday, sahte 'manuel' etiketi taşımaz).
--   2. Harici adaylar için mevcut ai_generation_specs şemasına uygun bir
--      üretim şartnamesi oluştur (desired_count=1, grade/subject/outcome,
--      difficulty, cognitive, solve-time, provenance constraints, status='ready')
--      ve staging satırına generation_spec_id bağla.
--   3. Intake artık staging_source='external_producer' yazar; producer/origin
--      provenance bilgisi metadata'da ve spec.constraints içinde korunur.
--   4. private.start_answer_verification sözleşmesi 'external_producer' adayları
--      da kabul eder (033 ile aynı govde, yalnız kaynak kontrolü genişletildi).
--   5. Gate'ler yalnız denetim run'ı başlatır; otomatik promotion asla yapılmaz.
--
-- Uyum: Bu migration 117'nin private.register_candidate_question_batch
-- fonksiyonunu CREATE OR REPLACE ile yeniden tanımlar; davranış korunur,
-- yalnız spec bağı + doğru staging_source eklenir.

BEGIN;

-- =========================================================
-- 1. STAGING SOURCE ALLOWLIST
-- =========================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'ai_question_staging'
      AND c.conname = 'ai_question_staging_staging_source_check'
  ) THEN
    ALTER TABLE public.ai_question_staging
      DROP CONSTRAINT ai_question_staging_staging_source_check;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'ai_question_staging'
      AND c.conname = 'ai_question_staging_staging_source_check'
  ) THEN
    ALTER TABLE public.ai_question_staging
      ADD CONSTRAINT ai_question_staging_staging_source_check
      CHECK (
        staging_source IN (
          'pdf_extracted',
          'excel_import',
          'pdf_excel_matched',
          'ai_generated',
          'manual_candidate',
          'external_producer'
        )
      );
  END IF;
END $$;

-- =========================================================
-- 2. ANSWER VERIFICATION KAPISINI GENİŞLET (033 eşdeğeri)
--    Harici üretici adayları da bağımsız cevap doğrulamasına girebilir.
--    Kaynak kontrolü dışında 033 davranışı AYNEN korunur.
-- =========================================================

CREATE OR REPLACE FUNCTION private.start_answer_verification(
  p_staging_question_id uuid,
  p_minimum_confidence numeric DEFAULT 0.90
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_question public.ai_question_staging%ROWTYPE;
  v_run_id uuid;
BEGIN

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
      'AI management or question approval permission required.';

  END IF;


  IF p_minimum_confidence < 0
     OR p_minimum_confidence > 1 THEN

    RAISE EXCEPTION
      'Minimum confidence must be between 0 and 1.';

  END IF;


  SELECT *
  INTO v_question

  FROM public.ai_question_staging s

  WHERE s.id = p_staging_question_id

  FOR UPDATE;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Staging question not found.';

  END IF;


  IF v_question.staging_source NOT IN (
    'ai_generated',
    'external_producer'
  ) THEN

    RAISE EXCEPTION
      'Independent answer verification is intended for AI generated or external producer staging questions.';

  END IF;


  IF v_question.proposed_correct_answer IS NULL THEN

    RAISE EXCEPTION
      'Staging question does not have a proposed correct answer.';

  END IF;


  IF v_question.staging_status IN (
    'rejected',
    'promoted'
  ) THEN

    RAISE EXCEPTION
      'Question cannot enter answer verification in its current status.';

  END IF;


  INSERT INTO public.ai_answer_verification_runs (
    staging_question_id,

    ai_job_id,

    proposed_answer,

    minimum_confidence,

    consensus_status,

    metadata
  )

  VALUES (
    v_question.id,

    v_question.ai_job_id,

    v_question.proposed_correct_answer,

    p_minimum_confidence,

    'waiting_solver_1',

    jsonb_build_object(
      'automatic_publication_allowed',
      false,

      'independent_solvers_required',
      2
    )
  )

  ON CONFLICT (
    staging_question_id
  )

  DO UPDATE SET
    minimum_confidence =
      EXCLUDED.minimum_confidence

  RETURNING id
  INTO v_run_id;


  UPDATE public.ai_question_staging
  SET
    staging_status = 'validating',

    metadata =
      metadata
      || jsonb_build_object(
           'answer_verification_run_id',
           v_run_id,

           'independent_answer_verification_required',
           true
         )

  WHERE id = p_staging_question_id;


  RETURN v_run_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.start_answer_verification(uuid, numeric)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.start_answer_verification(uuid, numeric)
TO authenticated, service_role;


-- =========================================================
-- 3. INTAKE: HARİCİ ADAY İÇİN GENERATION SPEC BAĞI
--    117'nin private.register_candidate_question_batch fonksiyonunun
--    davranışını korur; her geçerli harici aday için mevcut şemaya uygun
--    bir ai_generation_specs kaydı oluşturur ve staging satırını bağlar.
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

  v_outcome_id uuid;
  v_curriculum_version_id uuid;
  v_topic_id uuid;
  v_subtopic_id uuid;
  v_spec_id uuid;

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

    IF NOT (v_validation ->> 'valid')::boolean THEN
      v_invalid_count := v_invalid_count + 1;
      v_candidate_index := v_candidate_index + 1;
      CONTINUE;
    END IF;

    v_valid_count := v_valid_count + 1;

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
    -- OUTCOME + GENERATION SPEC (Faz 15C)
    --
    -- Aktif (veya is_default) müfredata göre kazanım UUID'sini
    -- çöz; her harici aday için mevcut ai_generation_specs
    -- sözleşmesine uygun bir kayıt oluştur (desired_count=1).
    -- Provenance (origin, producer, batch, client_question_id)
    -- spec.constraints içinde korunur. Status='ready' yalnızca
    -- gate'lerin beklediği geçerli spec sözleşmesidir; otomatik
    -- yayın bayrağı hiçbir yerde verilmez.
    -- =====================================================

    SELECT o.id, o.curriculum_version_id, o.topic_id, o.subtopic_id
      INTO v_outcome_id, v_curriculum_version_id, v_topic_id, v_subtopic_id
    FROM public.curriculum_outcomes o
    JOIN public.curriculum_versions cv ON cv.id = o.curriculum_version_id
    WHERE o.outcome_code = v_outcome_code
      AND o.subject_id = v_subject_id
      AND o.grade_level = v_grade_level
      AND o.is_active
    ORDER BY cv.is_default DESC, o.created_at DESC
    LIMIT 1;

    INSERT INTO public.ai_generation_specs (
      curriculum_version_id,
      grade_level,
      subject_id,
      topic_id,
      subtopic_id,
      desired_count,
      difficulty,
      cognitive_type,
      min_solve_time_seconds,
      max_solve_time_seconds,
      constraints,
      status,
      outcome_id
    )
    VALUES (
      v_curriculum_version_id,
      v_grade_level,
      v_subject_id,
      v_topic_id,
      v_subtopic_id,
      1,
      v_difficulty,
      v_cognitive,
      v_solve_time,
      v_solve_time,
      jsonb_build_object(
        'origin', v_origin,
        'producer_id', v_producer_id,
        'producer_model', v_producer_model,
        'batch_id', v_batch_id,
        'client_question_id', v_client_question_id,
        'outcome_code', v_outcome_code,
        'source', 'external_producer'
      ),
      'ready',
      v_outcome_id
    )
    RETURNING id INTO v_spec_id;


    -- =====================================================
    -- STAGING INSERT
    -- =====================================================

    INSERT INTO public.ai_question_staging (
      staging_source,
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
      proposed_solve_time_seconds,
      ownership_status,
      license_status,
      commercial_use_allowed,
      copyright_risk_level,
      staging_status,
      metadata
    )
    VALUES (
      'external_producer',
      v_spec_id,
      v_grade_level,
      v_subject_id,
      v_curriculum_version_id,
      v_topic_id,
      v_subtopic_id,
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
        'outcome_code', v_outcome_code,
        'required_outcome_id', v_outcome_id,
        'generation_spec_id', v_spec_id,
        'curriculum_version_id', v_curriculum_version_id,
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

      UPDATE public.ai_question_staging
      SET staging_status = 'needs_review',
          metadata = metadata || jsonb_build_object(
            'final_readiness_status', 'needs_review',
            'needs_review_reason', 'candidate_batch_intake_incomplete'
          )
      WHERE id = v_staging_id;

    ELSE
      UPDATE public.ai_question_staging
      SET metadata = metadata || jsonb_build_object(
        'final_readiness_status', 'pending',
        'candidate_batch_deterministic_checks_passed', true
      )
      WHERE id = v_staging_id;
    END IF;


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


COMMIT;