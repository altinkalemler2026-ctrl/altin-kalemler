-- 034_curriculum_fit_verification.sql
-- Altın Kalemler
--
-- AI-generated staging questions için:
-- - sınıf uygunluğu
-- - ders uygunluğu
-- - konu uygunluğu
-- - alt konu uygunluğu
-- - kazanım uygunluğu
-- - ön koşul ihlali
--
-- doğrulama kapısı.
--
-- İki bağımsız reviewer sonucu desteklenir.
--
-- PASS bile production yayını anlamına gelmez.
-- Diğer kalite/telif/süre kapıları devam eder.
--
-- Bu migration AI API çağrısı yapmaz.

BEGIN;


-- =========================================================
-- 1. CURRICULUM FIT VERIFICATION RUN
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_curriculum_fit_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  staging_question_id uuid NOT NULL
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  ai_job_id uuid
    REFERENCES public.ai_jobs(id)
    ON DELETE SET NULL,

  -- Beklenen hedeflerin snapshot'ı
  expected_curriculum_version_id uuid
    REFERENCES public.curriculum_versions(id)
    ON DELETE SET NULL,

  expected_grade_level smallint NOT NULL
    CHECK (expected_grade_level BETWEEN 1 AND 12),

  expected_subject_id uuid NOT NULL
    REFERENCES public.subjects(id)
    ON DELETE RESTRICT,

  expected_topic_id uuid
    REFERENCES public.topics(id)
    ON DELETE SET NULL,

  expected_subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE SET NULL,

  expected_outcome_id uuid
    REFERENCES public.curriculum_outcomes(id)
    ON DELETE SET NULL,

  status text NOT NULL DEFAULT 'waiting_reviewer_1'
    CHECK (
      status IN (
        'waiting_reviewer_1',
        'waiting_reviewer_2',
        'verified',
        'reviewer_disagreement',
        'grade_mismatch',
        'subject_mismatch',
        'topic_mismatch',
        'subtopic_mismatch',
        'outcome_mismatch',
        'prerequisite_violation',
        'low_confidence',
        'needs_human_review',
        'rejected'
      )
    ),

  minimum_confidence numeric(5,4)
    NOT NULL DEFAULT 0.90
    CHECK (
      minimum_confidence >= 0
      AND minimum_confidence <= 1
    ),

  human_review_required boolean NOT NULL DEFAULT false,

  human_decision text
    CHECK (
      human_decision IS NULL
      OR human_decision IN (
        'approve',
        'correct_classification',
        'reject_question'
      )
    ),

  human_reviewed_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  human_reviewed_at timestamptz,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (staging_question_id),

  CHECK (
    human_decision IS NULL
    OR (
      human_reviewed_by IS NOT NULL
      AND human_reviewed_at IS NOT NULL
    )
  )
);


ALTER TABLE public.ai_curriculum_fit_runs
ENABLE ROW LEVEL SECURITY;


CREATE INDEX IF NOT EXISTS
idx_ai_curriculum_fit_runs_status
ON public.ai_curriculum_fit_runs(
  status,
  created_at DESC
);


CREATE INDEX IF NOT EXISTS
idx_ai_curriculum_fit_runs_question
ON public.ai_curriculum_fit_runs(
  staging_question_id
);


DROP TRIGGER IF EXISTS
trigger_ai_curriculum_fit_runs_updated_at
ON public.ai_curriculum_fit_runs;


CREATE TRIGGER
trigger_ai_curriculum_fit_runs_updated_at
BEFORE UPDATE
ON public.ai_curriculum_fit_runs
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. REVIEWER SONUÇLARI
--
-- Her reviewer diğerinden bağımsız değerlendirme yapar.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_curriculum_fit_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  verification_run_id uuid NOT NULL
    REFERENCES public.ai_curriculum_fit_runs(id)
    ON DELETE CASCADE,

  reviewer_number smallint NOT NULL
    CHECK (reviewer_number IN (1, 2)),

  -- -------------------------------------------------------
  -- Reviewer'ın önerdiği sınıflandırma
  -- -------------------------------------------------------

  suggested_grade_level smallint
    CHECK (
      suggested_grade_level IS NULL
      OR suggested_grade_level BETWEEN 1 AND 12
    ),

  suggested_subject_id uuid
    REFERENCES public.subjects(id)
    ON DELETE SET NULL,

  suggested_topic_id uuid
    REFERENCES public.topics(id)
    ON DELETE SET NULL,

  suggested_subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE SET NULL,

  suggested_outcome_id uuid
    REFERENCES public.curriculum_outcomes(id)
    ON DELETE SET NULL,

  -- -------------------------------------------------------
  -- Uygunluk puanları
  -- -------------------------------------------------------

  grade_fit_score numeric(5,4)
    CHECK (
      grade_fit_score IS NULL
      OR grade_fit_score BETWEEN 0 AND 1
    ),

  subject_fit_score numeric(5,4)
    CHECK (
      subject_fit_score IS NULL
      OR subject_fit_score BETWEEN 0 AND 1
    ),

  topic_fit_score numeric(5,4)
    CHECK (
      topic_fit_score IS NULL
      OR topic_fit_score BETWEEN 0 AND 1
    ),

  subtopic_fit_score numeric(5,4)
    CHECK (
      subtopic_fit_score IS NULL
      OR subtopic_fit_score BETWEEN 0 AND 1
    ),

  outcome_fit_score numeric(5,4)
    CHECK (
      outcome_fit_score IS NULL
      OR outcome_fit_score BETWEEN 0 AND 1
    ),

  -- -------------------------------------------------------
  -- Drift / prerequisite
  -- -------------------------------------------------------

  grade_drift_detected boolean NOT NULL DEFAULT false,
  topic_drift_detected boolean NOT NULL DEFAULT false,
  subtopic_drift_detected boolean NOT NULL DEFAULT false,
  outcome_drift_detected boolean NOT NULL DEFAULT false,

  prerequisite_violation boolean NOT NULL DEFAULT false,

  prerequisite_details jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- Örneğin:
  -- soru 6. sınıf etiketi taşıyor fakat çözüm için
  -- 8. sınıfta öğretilen bilgi gerekiyor.
  required_prior_knowledge jsonb NOT NULL DEFAULT '[]'::jsonb,

  confidence_score numeric(5,4) NOT NULL
    CHECK (
      confidence_score >= 0
      AND confidence_score <= 1
    ),

  provider_name text,
  model_name text,
  prompt_version text,

  review_summary text,

  details jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    verification_run_id,
    reviewer_number
  )
);


ALTER TABLE public.ai_curriculum_fit_reviews
ENABLE ROW LEVEL SECURITY;


CREATE INDEX IF NOT EXISTS
idx_ai_curriculum_fit_reviews_run
ON public.ai_curriculum_fit_reviews(
  verification_run_id,
  reviewer_number
);


-- =========================================================
-- 3. VERIFICATION BAŞLAT
-- =========================================================

CREATE OR REPLACE FUNCTION private.start_curriculum_fit_verification(
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
  v_spec public.ai_generation_specs%ROWTYPE;
  v_expected_outcome_id uuid;
  v_run_id uuid;
BEGIN

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR
       private.current_user_has_admin_permission('questions.approve')
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


  IF v_question.staging_status IN (
    'rejected',
    'promoted'
  ) THEN
    RAISE EXCEPTION
      'Question cannot enter curriculum verification.';
  END IF;


  IF v_question.generation_spec_id IS NULL THEN
    RAISE EXCEPTION
      'Generation spec is required.';
  END IF;


  SELECT *
  INTO v_spec
  FROM public.ai_generation_specs s
  WHERE s.id = v_question.generation_spec_id;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Generation spec not found.';
  END IF;


  -- 032'de expected outcome metadata içine snapshot olarak
  -- taşınmış olabilir.
  BEGIN
    v_expected_outcome_id :=
      NULLIF(
        v_question.metadata ->> 'required_outcome_id',
        ''
      )::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      v_expected_outcome_id := NULL;
  END;


  INSERT INTO public.ai_curriculum_fit_runs (
    staging_question_id,
    ai_job_id,

    expected_curriculum_version_id,
    expected_grade_level,
    expected_subject_id,
    expected_topic_id,
    expected_subtopic_id,
    expected_outcome_id,

    status,
    minimum_confidence,

    metadata
  )
  VALUES (
    v_question.id,
    v_question.ai_job_id,

    v_spec.curriculum_version_id,
    v_spec.grade_level,
    v_spec.subject_id,
    v_spec.topic_id,
    v_spec.subtopic_id,
    v_expected_outcome_id,

    'waiting_reviewer_1',
    p_minimum_confidence,

    jsonb_build_object(
      'automatic_publication_allowed',
      false,
      'independent_reviewers_required',
      2
    )
  )
  ON CONFLICT (staging_question_id)
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
           'curriculum_fit_run_id',
           v_run_id,
           'curriculum_fit_required',
           true
         )

  WHERE id = p_staging_question_id;


  RETURN v_run_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.start_curriculum_fit_verification(uuid, numeric)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.start_curriculum_fit_verification(uuid, numeric)
TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.start_curriculum_fit_verification(
  p_staging_question_id uuid,
  p_minimum_confidence numeric DEFAULT 0.90
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.start_curriculum_fit_verification(
    p_staging_question_id,
    p_minimum_confidence
  );
$$;


REVOKE ALL
ON FUNCTION public.start_curriculum_fit_verification(uuid, numeric)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.start_curriculum_fit_verification(uuid, numeric)
TO authenticated, service_role;


-- =========================================================
-- 4. REVIEWER SONUCU GÖNDER
-- =========================================================

CREATE OR REPLACE FUNCTION private.submit_curriculum_fit_review(
  p_verification_run_id uuid,

  p_reviewer_number integer,

  p_suggested_grade_level smallint,
  p_suggested_subject_id uuid,
  p_suggested_topic_id uuid DEFAULT NULL,
  p_suggested_subtopic_id uuid DEFAULT NULL,
  p_suggested_outcome_id uuid DEFAULT NULL,

  p_grade_fit_score numeric DEFAULT NULL,
  p_subject_fit_score numeric DEFAULT NULL,
  p_topic_fit_score numeric DEFAULT NULL,
  p_subtopic_fit_score numeric DEFAULT NULL,
  p_outcome_fit_score numeric DEFAULT NULL,

  p_prerequisite_violation boolean DEFAULT false,
  p_prerequisite_details jsonb DEFAULT '{}'::jsonb,
  p_required_prior_knowledge jsonb DEFAULT '[]'::jsonb,

  p_confidence_score numeric DEFAULT 0,

  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,
  p_review_summary text DEFAULT NULL,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run public.ai_curriculum_fit_runs%ROWTYPE;

  v_grade_drift boolean;
  v_topic_drift boolean;
  v_subtopic_drift boolean;
  v_outcome_drift boolean;

  v_review_1 public.ai_curriculum_fit_reviews%ROWTYPE;
  v_review_2 public.ai_curriculum_fit_reviews%ROWTYPE;

  v_status text;
  v_validation_result text;
  v_human_review boolean := false;
BEGIN

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT private.current_user_has_admin_permission(
       'ai.manage'
     )
  THEN
    RAISE EXCEPTION
      'AI worker or AI management permission required.';
  END IF;


  IF p_reviewer_number NOT IN (1, 2) THEN
    RAISE EXCEPTION
      'Reviewer number must be 1 or 2.';
  END IF;


  IF p_confidence_score < 0
     OR p_confidence_score > 1 THEN
    RAISE EXCEPTION
      'Confidence score must be between 0 and 1.';
  END IF;


  SELECT *
  INTO v_run
  FROM public.ai_curriculum_fit_runs r
  WHERE r.id = p_verification_run_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Curriculum verification run not found.';
  END IF;


  IF v_run.status IN (
    'verified',
    'rejected'
  ) THEN
    RAISE EXCEPTION
      'Curriculum verification is already finalized.';
  END IF;


  IF p_reviewer_number = 2
     AND NOT EXISTS (
       SELECT 1
       FROM public.ai_curriculum_fit_reviews cr
       WHERE cr.verification_run_id =
             p_verification_run_id
         AND cr.reviewer_number = 1
     )
  THEN
    RAISE EXCEPTION
      'Reviewer 1 must complete first.';
  END IF;


  v_grade_drift :=
    p_suggested_grade_level IS DISTINCT FROM
    v_run.expected_grade_level;


  v_topic_drift :=
    v_run.expected_topic_id IS NOT NULL
    AND p_suggested_topic_id IS DISTINCT FROM
        v_run.expected_topic_id;


  v_subtopic_drift :=
    v_run.expected_subtopic_id IS NOT NULL
    AND p_suggested_subtopic_id IS DISTINCT FROM
        v_run.expected_subtopic_id;


  v_outcome_drift :=
    v_run.expected_outcome_id IS NOT NULL
    AND p_suggested_outcome_id IS DISTINCT FROM
        v_run.expected_outcome_id;


  INSERT INTO public.ai_curriculum_fit_reviews (
    verification_run_id,
    reviewer_number,

    suggested_grade_level,
    suggested_subject_id,
    suggested_topic_id,
    suggested_subtopic_id,
    suggested_outcome_id,

    grade_fit_score,
    subject_fit_score,
    topic_fit_score,
    subtopic_fit_score,
    outcome_fit_score,

    grade_drift_detected,
    topic_drift_detected,
    subtopic_drift_detected,
    outcome_drift_detected,

    prerequisite_violation,
    prerequisite_details,
    required_prior_knowledge,

    confidence_score,

    provider_name,
    model_name,
    prompt_version,
    review_summary,
    details
  )
  VALUES (
    p_verification_run_id,
    p_reviewer_number,

    p_suggested_grade_level,
    p_suggested_subject_id,
    p_suggested_topic_id,
    p_suggested_subtopic_id,
    p_suggested_outcome_id,

    p_grade_fit_score,
    p_subject_fit_score,
    p_topic_fit_score,
    p_subtopic_fit_score,
    p_outcome_fit_score,

    v_grade_drift,
    v_topic_drift,
    v_subtopic_drift,
    v_outcome_drift,

    COALESCE(p_prerequisite_violation, false),

    COALESCE(
      p_prerequisite_details,
      '{}'::jsonb
    ),

    COALESCE(
      p_required_prior_knowledge,
      '[]'::jsonb
    ),

    p_confidence_score,

    NULLIF(btrim(p_provider_name), ''),
    NULLIF(btrim(p_model_name), ''),
    NULLIF(btrim(p_prompt_version), ''),
    NULLIF(btrim(p_review_summary), ''),

    COALESCE(
      p_details,
      '{}'::jsonb
    )
  );


  IF p_reviewer_number = 1 THEN

    UPDATE public.ai_curriculum_fit_runs
    SET status = 'waiting_reviewer_2'
    WHERE id = p_verification_run_id;


    RETURN jsonb_build_object(
      'verification_run_id',
      p_verification_run_id,

      'reviewer',
      1,

      'status',
      'stored',

      'next',
      'waiting_reviewer_2'
    );

  END IF;


  -- =======================================================
  -- İKİ REVIEWER'I AL
  -- =======================================================

  SELECT *
  INTO v_review_1
  FROM public.ai_curriculum_fit_reviews r
  WHERE r.verification_run_id =
        p_verification_run_id
    AND r.reviewer_number = 1;


  SELECT *
  INTO v_review_2
  FROM public.ai_curriculum_fit_reviews r
  WHERE r.verification_run_id =
        p_verification_run_id
    AND r.reviewer_number = 2;


  -- =======================================================
  -- KONSENSÜS
  -- =======================================================

  IF v_review_1.confidence_score <
       v_run.minimum_confidence
     OR
     v_review_2.confidence_score <
       v_run.minimum_confidence
  THEN

    v_status := 'low_confidence';
    v_validation_result := 'warning';
    v_human_review := true;


  ELSIF v_review_1.suggested_grade_level
        IS DISTINCT FROM
        v_review_2.suggested_grade_level

     OR v_review_1.suggested_subject_id
        IS DISTINCT FROM
        v_review_2.suggested_subject_id

     OR v_review_1.suggested_topic_id
        IS DISTINCT FROM
        v_review_2.suggested_topic_id

     OR v_review_1.suggested_subtopic_id
        IS DISTINCT FROM
        v_review_2.suggested_subtopic_id

     OR v_review_1.suggested_outcome_id
        IS DISTINCT FROM
        v_review_2.suggested_outcome_id
  THEN

    v_status := 'reviewer_disagreement';
    v_validation_result := 'warning';
    v_human_review := true;


  ELSIF v_review_1.prerequisite_violation
        OR v_review_2.prerequisite_violation
  THEN

    v_status := 'prerequisite_violation';
    v_validation_result := 'fail';
    v_human_review := true;


  ELSIF v_review_1.suggested_grade_level
        IS DISTINCT FROM
        v_run.expected_grade_level
  THEN

    v_status := 'grade_mismatch';
    v_validation_result := 'fail';
    v_human_review := true;


  ELSIF v_review_1.suggested_subject_id
        IS DISTINCT FROM
        v_run.expected_subject_id
  THEN

    v_status := 'subject_mismatch';
    v_validation_result := 'fail';
    v_human_review := true;


  ELSIF v_run.expected_topic_id IS NOT NULL
        AND v_review_1.suggested_topic_id
            IS DISTINCT FROM
            v_run.expected_topic_id
  THEN

    v_status := 'topic_mismatch';
    v_validation_result := 'fail';
    v_human_review := true;


  ELSIF v_run.expected_subtopic_id IS NOT NULL
        AND v_review_1.suggested_subtopic_id
            IS DISTINCT FROM
            v_run.expected_subtopic_id
  THEN

    v_status := 'subtopic_mismatch';
    v_validation_result := 'fail';
    v_human_review := true;


  ELSIF v_run.expected_outcome_id IS NOT NULL
        AND v_review_1.suggested_outcome_id
            IS DISTINCT FROM
            v_run.expected_outcome_id
  THEN

    v_status := 'outcome_mismatch';
    v_validation_result := 'fail';
    v_human_review := true;


  ELSE

    v_status := 'verified';
    v_validation_result := 'pass';
    v_human_review := false;

  END IF;


  UPDATE public.ai_curriculum_fit_runs
  SET
    status = v_status,
    human_review_required = v_human_review

  WHERE id = p_verification_run_id;


  -- =======================================================
  -- VALIDATION RESULTS
  -- =======================================================

  INSERT INTO public.ai_validation_results (
    staging_question_id,
    ai_job_id,
    validator_type,
    validation_type,
    result,
    score,
    summary,
    details
  )
  VALUES (
    v_run.staging_question_id,
    v_run.ai_job_id,

    'ai',
    'grade_appropriateness',

    CASE
      WHEN v_status = 'verified'
        THEN 'pass'

      WHEN v_status = 'grade_mismatch'
        THEN 'fail'

      ELSE 'warning'
    END,

    LEAST(
      COALESCE(v_review_1.grade_fit_score, 1),
      COALESCE(v_review_2.grade_fit_score, 1)
    ),

    'Independent grade appropriateness review completed.',

    jsonb_build_object(
      'verification_run_id',
      v_run.id,

      'expected_grade',
      v_run.expected_grade_level,

      'reviewer_1_grade',
      v_review_1.suggested_grade_level,

      'reviewer_2_grade',
      v_review_2.suggested_grade_level,

      'status',
      v_status
    )
  );


  INSERT INTO public.ai_validation_results (
    staging_question_id,
    ai_job_id,
    validator_type,
    validation_type,
    result,
    score,
    summary,
    details
  )
  VALUES (
    v_run.staging_question_id,
    v_run.ai_job_id,

    'ai',
    'topic_coherence',

    CASE
      WHEN v_status = 'verified'
        THEN 'pass'

      WHEN v_status IN (
        'subject_mismatch',
        'topic_mismatch',
        'subtopic_mismatch',
        'outcome_mismatch'
      )
        THEN 'fail'

      ELSE 'warning'
    END,

    LEAST(
      COALESCE(v_review_1.topic_fit_score, 1),
      COALESCE(v_review_2.topic_fit_score, 1)
    ),

    'Independent topic and curriculum coherence review completed.',

    jsonb_build_object(
      'verification_run_id',
      v_run.id,

      'expected_topic_id',
      v_run.expected_topic_id,

      'expected_subtopic_id',
      v_run.expected_subtopic_id,

      'expected_outcome_id',
      v_run.expected_outcome_id,

      'reviewer_1_topic_id',
      v_review_1.suggested_topic_id,

      'reviewer_2_topic_id',
      v_review_2.suggested_topic_id,

      'status',
      v_status
    )
  );


  INSERT INTO public.ai_validation_results (
    staging_question_id,
    ai_job_id,
    validator_type,
    validation_type,
    result,
    score,
    summary,
    details
  )
  VALUES (
    v_run.staging_question_id,
    v_run.ai_job_id,

    'ai',
    'prerequisite_check',

    CASE
      WHEN v_review_1.prerequisite_violation
           OR v_review_2.prerequisite_violation
        THEN 'fail'

      WHEN v_status = 'low_confidence'
           OR v_status = 'reviewer_disagreement'
        THEN 'warning'

      ELSE 'pass'
    END,

    LEAST(
      v_review_1.confidence_score,
      v_review_2.confidence_score
    ),

    'Independent prerequisite review completed.',

    jsonb_build_object(
      'verification_run_id',
      v_run.id,

      'reviewer_1_violation',
      v_review_1.prerequisite_violation,

      'reviewer_2_violation',
      v_review_2.prerequisite_violation,

      'reviewer_1_required_prior_knowledge',
      v_review_1.required_prior_knowledge,

      'reviewer_2_required_prior_knowledge',
      v_review_2.required_prior_knowledge,

      'status',
      v_status
    )
  );


  -- Genel curriculum sonucu da tutulur.

  INSERT INTO public.ai_validation_results (
    staging_question_id,
    ai_job_id,
    validator_type,
    validation_type,
    result,
    score,
    summary,
    details
  )
  VALUES (
    v_run.staging_question_id,
    v_run.ai_job_id,

    'ai',
    'curriculum',

    v_validation_result,

    LEAST(
      v_review_1.confidence_score,
      v_review_2.confidence_score
    ),

    'Two-reviewer curriculum fit verification completed.',

    jsonb_build_object(
      'verification_run_id',
      v_run.id,
      'status',
      v_status,
      'human_review_required',
      v_human_review,
      'automatic_publication_allowed',
      false
    )
  );


  -- =======================================================
  -- STAGING
  --
  -- VERIFIED olsa dahi approved YAPMIYORUZ.
  -- =======================================================

  UPDATE public.ai_question_staging
  SET
    staging_status =
      CASE
        WHEN v_status = 'verified'
          THEN 'validating'
        ELSE 'needs_review'
      END,

    classification_confidence =
      CASE
        WHEN v_status = 'verified'
        THEN LEAST(
          v_review_1.confidence_score,
          v_review_2.confidence_score
        )
        ELSE classification_confidence
      END,

    metadata =
      metadata
      || jsonb_build_object(
           'curriculum_fit_status',
           v_status,

           'grade_fit_score',
           LEAST(
             COALESCE(v_review_1.grade_fit_score, 1),
             COALESCE(v_review_2.grade_fit_score, 1)
           ),

           'topic_fit_score',
           LEAST(
             COALESCE(v_review_1.topic_fit_score, 1),
             COALESCE(v_review_2.topic_fit_score, 1)
           ),

           'subtopic_fit_score',
           LEAST(
             COALESCE(v_review_1.subtopic_fit_score, 1),
             COALESCE(v_review_2.subtopic_fit_score, 1)
           ),

           'outcome_fit_score',
           LEAST(
             COALESCE(v_review_1.outcome_fit_score, 1),
             COALESCE(v_review_2.outcome_fit_score, 1)
           ),

           'prerequisite_violation',
           (
             v_review_1.prerequisite_violation
             OR
             v_review_2.prerequisite_violation
           ),

           'human_curriculum_review_required',
           v_human_review
         )

  WHERE id = v_run.staging_question_id;


  RETURN jsonb_build_object(
    'verification_run_id',
    v_run.id,

    'status',
    v_status,

    'human_review_required',
    v_human_review,

    'production_publication',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.submit_curriculum_fit_review(
  uuid,
  integer,
  smallint,
  uuid,
  uuid,
  uuid,
  uuid,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  boolean,
  jsonb,
  jsonb,
  numeric,
  text,
  text,
  text,
  text,
  jsonb
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.submit_curriculum_fit_review(
  uuid,
  integer,
  smallint,
  uuid,
  uuid,
  uuid,
  uuid,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  boolean,
  jsonb,
  jsonb,
  numeric,
  text,
  text,
  text,
  text,
  jsonb
)
TO authenticated, service_role;


-- =========================================================
-- 5. PUBLIC REVIEW RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.submit_curriculum_fit_review(
  p_verification_run_id uuid,

  p_reviewer_number integer,

  p_suggested_grade_level smallint,
  p_suggested_subject_id uuid,
  p_suggested_topic_id uuid DEFAULT NULL,
  p_suggested_subtopic_id uuid DEFAULT NULL,
  p_suggested_outcome_id uuid DEFAULT NULL,

  p_grade_fit_score numeric DEFAULT NULL,
  p_subject_fit_score numeric DEFAULT NULL,
  p_topic_fit_score numeric DEFAULT NULL,
  p_subtopic_fit_score numeric DEFAULT NULL,
  p_outcome_fit_score numeric DEFAULT NULL,

  p_prerequisite_violation boolean DEFAULT false,
  p_prerequisite_details jsonb DEFAULT '{}'::jsonb,
  p_required_prior_knowledge jsonb DEFAULT '[]'::jsonb,

  p_confidence_score numeric DEFAULT 0,

  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,
  p_review_summary text DEFAULT NULL,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.submit_curriculum_fit_review(
    p_verification_run_id,

    p_reviewer_number,

    p_suggested_grade_level,
    p_suggested_subject_id,
    p_suggested_topic_id,
    p_suggested_subtopic_id,
    p_suggested_outcome_id,

    p_grade_fit_score,
    p_subject_fit_score,
    p_topic_fit_score,
    p_subtopic_fit_score,
    p_outcome_fit_score,

    p_prerequisite_violation,
    p_prerequisite_details,
    p_required_prior_knowledge,

    p_confidence_score,

    p_provider_name,
    p_model_name,
    p_prompt_version,
    p_review_summary,
    p_details
  );
$$;


REVOKE ALL
ON FUNCTION public.submit_curriculum_fit_review(
  uuid,
  integer,
  smallint,
  uuid,
  uuid,
  uuid,
  uuid,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  boolean,
  jsonb,
  jsonb,
  numeric,
  text,
  text,
  text,
  text,
  jsonb
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.submit_curriculum_fit_review(
  uuid,
  integer,
  smallint,
  uuid,
  uuid,
  uuid,
  uuid,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  boolean,
  jsonb,
  jsonb,
  numeric,
  text,
  text,
  text,
  text,
  jsonb
)
TO authenticated, service_role;


-- =========================================================
-- 6. İNSAN MÜFREDAT KARARI
-- =========================================================

CREATE OR REPLACE FUNCTION private.review_curriculum_fit(
  p_verification_run_id uuid,
  p_decision text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_run public.ai_curriculum_fit_runs%ROWTYPE;
BEGIN

  v_user_id := auth.uid();


  IF v_user_id IS NULL THEN
    RAISE EXCEPTION
      'Authentication required.';
  END IF;


  IF NOT (
    private.current_user_has_admin_permission(
      'questions.approve'
    )
    OR
    private.current_user_has_admin_permission(
      'ai.manage'
    )
  ) THEN
    RAISE EXCEPTION
      'Question approval permission required.';
  END IF;


  IF p_decision NOT IN (
    'approve',
    'correct_classification',
    'reject_question'
  ) THEN
    RAISE EXCEPTION
      'Invalid human curriculum review decision.';
  END IF;


  SELECT *
  INTO v_run
  FROM public.ai_curriculum_fit_runs r
  WHERE r.id = p_verification_run_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Curriculum verification run not found.';
  END IF;


  UPDATE public.ai_curriculum_fit_runs
  SET
    human_review_required = false,

    human_decision =
      p_decision,

    human_reviewed_by =
      v_user_id,

    human_reviewed_at =
      clock_timestamp(),

    status =
      CASE
        WHEN p_decision IN (
          'approve',
          'correct_classification'
        )
        THEN 'verified'

        ELSE 'rejected'
      END

  WHERE id = p_verification_run_id;


  IF p_decision = 'reject_question' THEN

    UPDATE public.ai_question_staging
    SET
      staging_status = 'rejected',

      metadata =
        metadata
        || jsonb_build_object(
             'curriculum_human_decision',
             p_decision
           )

    WHERE id = v_run.staging_question_id;


    INSERT INTO public.ai_validation_results (
      staging_question_id,
      ai_job_id,
      validator_type,
      validation_type,
      result,
      reviewed_by,
      summary,
      details
    )
    VALUES (
      v_run.staging_question_id,
      v_run.ai_job_id,
      'human',
      'curriculum',
      'fail',
      v_user_id,
      'Question rejected during human curriculum review.',
      jsonb_build_object(
        'verification_run_id',
        v_run.id
      )
    );

  ELSE

    UPDATE public.ai_question_staging
    SET
      staging_status = 'validating',

      metadata =
        metadata
        || jsonb_build_object(
             'curriculum_human_decision',
             p_decision,
             'curriculum_human_verified',
             true
           )

    WHERE id = v_run.staging_question_id;


    INSERT INTO public.ai_validation_results (
      staging_question_id,
      ai_job_id,
      validator_type,
      validation_type,
      result,
      reviewed_by,
      summary,
      details
    )
    VALUES (
      v_run.staging_question_id,
      v_run.ai_job_id,
      'human',
      'curriculum',
      'pass',
      v_user_id,
      'Human reviewer accepted curriculum fit.',
      jsonb_build_object(
        'verification_run_id',
        v_run.id,
        'decision',
        p_decision
      )
    );

  END IF;


  RETURN jsonb_build_object(
    'verification_run_id',
    v_run.id,

    'decision',
    p_decision,

    'production_publication',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.review_curriculum_fit(uuid, text)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.review_curriculum_fit(uuid, text)
TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.review_curriculum_fit(
  p_verification_run_id uuid,
  p_decision text
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.review_curriculum_fit(
    p_verification_run_id,
    p_decision
  );
$$;


REVOKE ALL
ON FUNCTION public.review_curriculum_fit(uuid, text)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.review_curriculum_fit(uuid, text)
TO authenticated, service_role;


-- =========================================================
-- 7. RAPOR
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_curriculum_fit_report(
  p_staging_question_id uuid
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
      'questions.edit'
    )
    OR
    public.current_user_has_admin_permission(
      'questions.approve'
    )
    OR
    public.current_user_has_admin_permission(
      'ai.manage'
    )
  ) THEN
    RAISE EXCEPTION
      'Admin permission required.';
  END IF;


  SELECT jsonb_build_object(

    'verification_run_id',
    r.id,

    'staging_question_id',
    r.staging_question_id,

    'expected',
    jsonb_build_object(
      'curriculum_version_id',
      r.expected_curriculum_version_id,

      'grade_level',
      r.expected_grade_level,

      'subject_id',
      r.expected_subject_id,

      'topic_id',
      r.expected_topic_id,

      'subtopic_id',
      r.expected_subtopic_id,

      'outcome_id',
      r.expected_outcome_id
    ),

    'status',
    r.status,

    'minimum_confidence',
    r.minimum_confidence,

    'human_review_required',
    r.human_review_required,

    'human_decision',
    r.human_decision,

    'reviews',
    (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'reviewer_number',
            cr.reviewer_number,

            'grade_level',
            cr.suggested_grade_level,

            'subject_id',
            cr.suggested_subject_id,

            'topic_id',
            cr.suggested_topic_id,

            'subtopic_id',
            cr.suggested_subtopic_id,

            'outcome_id',
            cr.suggested_outcome_id,

            'grade_fit_score',
            cr.grade_fit_score,

            'topic_fit_score',
            cr.topic_fit_score,

            'subtopic_fit_score',
            cr.subtopic_fit_score,

            'outcome_fit_score',
            cr.outcome_fit_score,

            'prerequisite_violation',
            cr.prerequisite_violation,

            'required_prior_knowledge',
            cr.required_prior_knowledge,

            'confidence_score',
            cr.confidence_score
          )
          ORDER BY cr.reviewer_number
        ),
        '[]'::jsonb
      )

      FROM public.ai_curriculum_fit_reviews cr

      WHERE cr.verification_run_id = r.id
    ),

    'automatic_publication_allowed',
    false

  )
  INTO v_result

  FROM public.ai_curriculum_fit_runs r

  WHERE r.staging_question_id =
        p_staging_question_id;


  IF v_result IS NULL THEN

    RETURN jsonb_build_object(
      'status',
      'curriculum_verification_not_started',

      'staging_question_id',
      p_staging_question_id
    );

  END IF;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_curriculum_fit_report(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_curriculum_fit_report(uuid)
TO authenticated, service_role;


-- =========================================================
-- 8. RLS
-- =========================================================

DROP POLICY IF EXISTS
"admins manage curriculum fit runs"
ON public.ai_curriculum_fit_runs;


CREATE POLICY
"admins manage curriculum fit runs"
ON public.ai_curriculum_fit_runs
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
"admins manage curriculum fit reviews"
ON public.ai_curriculum_fit_reviews;


CREATE POLICY
"admins manage curriculum fit reviews"
ON public.ai_curriculum_fit_reviews
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
-- 9. OVERVIEW
-- =========================================================

CREATE OR REPLACE VIEW public.ai_curriculum_fit_overview
WITH (security_invoker = true)
AS

SELECT
  r.id AS verification_run_id,

  r.staging_question_id,

  r.expected_grade_level,
  r.expected_subject_id,
  r.expected_topic_id,
  r.expected_subtopic_id,
  r.expected_outcome_id,

  r.status,

  r.minimum_confidence,

  r.human_review_required,

  r.human_decision,

  r.created_at,
  r.updated_at

FROM public.ai_curriculum_fit_runs r;


REVOKE ALL
ON public.ai_curriculum_fit_overview
FROM PUBLIC;


REVOKE ALL
ON public.ai_curriculum_fit_overview
FROM anon;


GRANT SELECT
ON public.ai_curriculum_fit_overview
TO authenticated;


-- =========================================================
-- 10. PRIVATE DEFAULT SECURITY
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