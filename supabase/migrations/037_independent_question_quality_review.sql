-- 037_independent_question_quality_review.sql
-- Altın Kalemler
--
-- Bağımsız genel soru kalite kontrolü:
-- - dil ve anlatım
-- - bilimsel/akademik doğruluk
-- - belirsizlik
-- - seçenek kalitesi
-- - tek doğru cevap mantığı
-- - sınıf seviyesine uygun dil
-- - zorluk uygunluğu
-- - bilişsel seviye
-- - soru tipi
--
-- İki bağımsız reviewer gerekir.
-- Bu migration AI API çağırmaz.
-- PASS sonucu production yayını değildir.

BEGIN;


-- =========================================================
-- 1. QUALITY VERIFICATION RUN
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_question_quality_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  staging_question_id uuid NOT NULL
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  ai_job_id uuid
    REFERENCES public.ai_jobs(id)
    ON DELETE SET NULL,

  generation_spec_id uuid
    REFERENCES public.ai_generation_specs(id)
    ON DELETE SET NULL,

  status text NOT NULL DEFAULT 'waiting_reviewer_1'
    CHECK (
      status IN (
        'waiting_reviewer_1',
        'waiting_reviewer_2',
        'verified',
        'low_confidence',
        'reviewer_disagreement',
        'language_problem',
        'scientific_problem',
        'ambiguity_problem',
        'option_quality_problem',
        'difficulty_mismatch',
        'cognitive_mismatch',
        'question_type_mismatch',
        'needs_human_review',
        'rejected'
      )
    ),

  minimum_confidence numeric(5,4)
    NOT NULL DEFAULT 0.90
    CHECK (
      minimum_confidence BETWEEN 0 AND 1
    ),

  minimum_quality_score numeric(5,4)
    NOT NULL DEFAULT 0.85
    CHECK (
      minimum_quality_score BETWEEN 0 AND 1
    ),

  consensus_quality_score numeric(5,4)
    CHECK (
      consensus_quality_score IS NULL
      OR consensus_quality_score BETWEEN 0 AND 1
    ),

  human_review_required boolean NOT NULL DEFAULT false,

  human_decision text
    CHECK (
      human_decision IS NULL
      OR human_decision IN (
        'approve',
        'approve_after_correction',
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


CREATE INDEX IF NOT EXISTS
idx_ai_question_quality_runs_status
ON public.ai_question_quality_runs(
  status,
  created_at DESC
);


ALTER TABLE public.ai_question_quality_runs
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS
trigger_ai_question_quality_runs_updated_at
ON public.ai_question_quality_runs;


CREATE TRIGGER
trigger_ai_question_quality_runs_updated_at
BEFORE UPDATE
ON public.ai_question_quality_runs
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. REVIEWER SONUÇLARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_question_quality_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  quality_run_id uuid NOT NULL
    REFERENCES public.ai_question_quality_runs(id)
    ON DELETE CASCADE,

  reviewer_number smallint NOT NULL
    CHECK (reviewer_number IN (1, 2)),

  -- -------------------------------------------------------
  -- Kalite skorları
  -- -------------------------------------------------------

  language_score numeric(5,4) NOT NULL
    CHECK (language_score BETWEEN 0 AND 1),

  scientific_accuracy_score numeric(5,4) NOT NULL
    CHECK (scientific_accuracy_score BETWEEN 0 AND 1),

  clarity_score numeric(5,4) NOT NULL
    CHECK (clarity_score BETWEEN 0 AND 1),

  option_quality_score numeric(5,4) NOT NULL
    CHECK (option_quality_score BETWEEN 0 AND 1),

  age_grade_language_score numeric(5,4) NOT NULL
    CHECK (age_grade_language_score BETWEEN 0 AND 1),

  overall_quality_score numeric(5,4) NOT NULL
    CHECK (overall_quality_score BETWEEN 0 AND 1),

  -- -------------------------------------------------------
  -- Kritik bayraklar
  -- -------------------------------------------------------

  ambiguous_wording boolean NOT NULL DEFAULT false,

  multiple_correct_answer_risk boolean NOT NULL DEFAULT false,

  no_correct_answer_risk boolean NOT NULL DEFAULT false,

  misleading_option_risk boolean NOT NULL DEFAULT false,

  scientific_error_detected boolean NOT NULL DEFAULT false,

  factual_error_detected boolean NOT NULL DEFAULT false,

  grammar_problem_detected boolean NOT NULL DEFAULT false,

  age_inappropriate_language boolean NOT NULL DEFAULT false,

  missing_information_detected boolean NOT NULL DEFAULT false,

  unnecessary_information_problem boolean NOT NULL DEFAULT false,

  -- -------------------------------------------------------
  -- Reviewer sınıflandırması
  -- -------------------------------------------------------

  suggested_difficulty text
    CHECK (
      suggested_difficulty IS NULL
      OR suggested_difficulty IN (
        'easy',
        'medium',
        'hard'
      )
    ),

  suggested_cognitive_type text
    CHECK (
      suggested_cognitive_type IS NULL
      OR suggested_cognitive_type IN (
        'learning',
        'comprehension',
        'application'
      )
    ),

  suggested_primary_question_type text,

  difficulty_fit_score numeric(5,4)
    CHECK (
      difficulty_fit_score IS NULL
      OR difficulty_fit_score BETWEEN 0 AND 1
    ),

  cognitive_fit_score numeric(5,4)
    CHECK (
      cognitive_fit_score IS NULL
      OR cognitive_fit_score BETWEEN 0 AND 1
    ),

  question_type_fit_score numeric(5,4)
    CHECK (
      question_type_fit_score IS NULL
      OR question_type_fit_score BETWEEN 0 AND 1
    ),

  confidence_score numeric(5,4) NOT NULL
    CHECK (
      confidence_score BETWEEN 0 AND 1
    ),

  provider_name text,
  model_name text,
  prompt_version text,

  review_summary text,

  problems jsonb NOT NULL DEFAULT '[]'::jsonb,
  suggestions jsonb NOT NULL DEFAULT '[]'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    quality_run_id,
    reviewer_number
  )
);


CREATE INDEX IF NOT EXISTS
idx_ai_question_quality_reviews_run
ON public.ai_question_quality_reviews(
  quality_run_id,
  reviewer_number
);


ALTER TABLE public.ai_question_quality_reviews
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 3. QUALITY REVIEW BAŞLAT
-- =========================================================

CREATE OR REPLACE FUNCTION private.start_question_quality_review(
  p_staging_question_id uuid,
  p_minimum_confidence numeric DEFAULT 0.90,
  p_minimum_quality_score numeric DEFAULT 0.85
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
       private.current_user_has_admin_permission('ai.manage')
       OR
       private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION
      'AI management or question approval permission required.';
  END IF;


  IF p_minimum_confidence NOT BETWEEN 0 AND 1
     OR p_minimum_quality_score NOT BETWEEN 0 AND 1
  THEN
    RAISE EXCEPTION
      'Scores must be between 0 and 1.';
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
      'Question cannot enter quality review.';
  END IF;


  INSERT INTO public.ai_question_quality_runs (
    staging_question_id,
    ai_job_id,
    generation_spec_id,

    status,

    minimum_confidence,
    minimum_quality_score,

    metadata
  )
  VALUES (
    v_question.id,
    v_question.ai_job_id,
    v_question.generation_spec_id,

    'waiting_reviewer_1',

    p_minimum_confidence,
    p_minimum_quality_score,

    jsonb_build_object(
      'independent_reviewers_required',
      2,
      'automatic_publication_allowed',
      false
    )
  )

  ON CONFLICT (staging_question_id)
  DO UPDATE SET
    minimum_confidence =
      EXCLUDED.minimum_confidence,

    minimum_quality_score =
      EXCLUDED.minimum_quality_score

  RETURNING id
  INTO v_run_id;


  UPDATE public.ai_question_staging
  SET
    staging_status = 'validating',

    metadata =
      metadata
      || jsonb_build_object(
           'question_quality_run_id',
           v_run_id,
           'question_quality_review_required',
           true
         )

  WHERE id = p_staging_question_id;


  RETURN v_run_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.start_question_quality_review(
  uuid,
  numeric,
  numeric
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.start_question_quality_review(
  uuid,
  numeric,
  numeric
)
TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.start_question_quality_review(
  p_staging_question_id uuid,
  p_minimum_confidence numeric DEFAULT 0.90,
  p_minimum_quality_score numeric DEFAULT 0.85
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.start_question_quality_review(
    p_staging_question_id,
    p_minimum_confidence,
    p_minimum_quality_score
  );
$$;


REVOKE ALL
ON FUNCTION public.start_question_quality_review(
  uuid,
  numeric,
  numeric
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.start_question_quality_review(
  uuid,
  numeric,
  numeric
)
TO authenticated, service_role;


-- =========================================================
-- 4. REVIEWER SONUCU
-- =========================================================

CREATE OR REPLACE FUNCTION private.submit_question_quality_review(
  p_quality_run_id uuid,
  p_reviewer_number integer,

  p_language_score numeric,
  p_scientific_accuracy_score numeric,
  p_clarity_score numeric,
  p_option_quality_score numeric,
  p_age_grade_language_score numeric,
  p_overall_quality_score numeric,

  p_ambiguous_wording boolean DEFAULT false,
  p_multiple_correct_answer_risk boolean DEFAULT false,
  p_no_correct_answer_risk boolean DEFAULT false,
  p_misleading_option_risk boolean DEFAULT false,
  p_scientific_error_detected boolean DEFAULT false,
  p_factual_error_detected boolean DEFAULT false,
  p_grammar_problem_detected boolean DEFAULT false,
  p_age_inappropriate_language boolean DEFAULT false,
  p_missing_information_detected boolean DEFAULT false,
  p_unnecessary_information_problem boolean DEFAULT false,

  p_suggested_difficulty text DEFAULT NULL,
  p_suggested_cognitive_type text DEFAULT NULL,
  p_suggested_primary_question_type text DEFAULT NULL,

  p_difficulty_fit_score numeric DEFAULT NULL,
  p_cognitive_fit_score numeric DEFAULT NULL,
  p_question_type_fit_score numeric DEFAULT NULL,

  p_confidence_score numeric DEFAULT 0,

  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,

  p_review_summary text DEFAULT NULL,

  p_problems jsonb DEFAULT '[]'::jsonb,
  p_suggestions jsonb DEFAULT '[]'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run public.ai_question_quality_runs%ROWTYPE;
  v_question public.ai_question_staging%ROWTYPE;

  v_r1 public.ai_question_quality_reviews%ROWTYPE;
  v_r2 public.ai_question_quality_reviews%ROWTYPE;

  v_quality numeric;
  v_status text;
  v_human_review boolean;
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


  IF p_language_score NOT BETWEEN 0 AND 1
     OR p_scientific_accuracy_score NOT BETWEEN 0 AND 1
     OR p_clarity_score NOT BETWEEN 0 AND 1
     OR p_option_quality_score NOT BETWEEN 0 AND 1
     OR p_age_grade_language_score NOT BETWEEN 0 AND 1
     OR p_overall_quality_score NOT BETWEEN 0 AND 1
     OR p_confidence_score NOT BETWEEN 0 AND 1
  THEN
    RAISE EXCEPTION
      'Quality scores must be between 0 and 1.';
  END IF;


  SELECT *
  INTO v_run
  FROM public.ai_question_quality_runs r
  WHERE r.id = p_quality_run_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Quality review run not found.';
  END IF;


  SELECT *
  INTO v_question
  FROM public.ai_question_staging s
  WHERE s.id = v_run.staging_question_id;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Staging question not found.';
  END IF;


  IF v_run.status IN (
    'verified',
    'rejected'
  ) THEN
    RAISE EXCEPTION
      'Quality review is already finalized.';
  END IF;


  IF p_reviewer_number = 2
     AND NOT EXISTS (
       SELECT 1
       FROM public.ai_question_quality_reviews qr
       WHERE qr.quality_run_id = p_quality_run_id
         AND qr.reviewer_number = 1
     )
  THEN
    RAISE EXCEPTION
      'Reviewer 1 must complete first.';
  END IF;


  INSERT INTO public.ai_question_quality_reviews (
    quality_run_id,
    reviewer_number,

    language_score,
    scientific_accuracy_score,
    clarity_score,
    option_quality_score,
    age_grade_language_score,
    overall_quality_score,

    ambiguous_wording,
    multiple_correct_answer_risk,
    no_correct_answer_risk,
    misleading_option_risk,
    scientific_error_detected,
    factual_error_detected,
    grammar_problem_detected,
    age_inappropriate_language,
    missing_information_detected,
    unnecessary_information_problem,

    suggested_difficulty,
    suggested_cognitive_type,
    suggested_primary_question_type,

    difficulty_fit_score,
    cognitive_fit_score,
    question_type_fit_score,

    confidence_score,

    provider_name,
    model_name,
    prompt_version,

    review_summary,

    problems,
    suggestions,
    metadata
  )
  VALUES (
    p_quality_run_id,
    p_reviewer_number,

    p_language_score,
    p_scientific_accuracy_score,
    p_clarity_score,
    p_option_quality_score,
    p_age_grade_language_score,
    p_overall_quality_score,

    COALESCE(p_ambiguous_wording, false),
    COALESCE(p_multiple_correct_answer_risk, false),
    COALESCE(p_no_correct_answer_risk, false),
    COALESCE(p_misleading_option_risk, false),
    COALESCE(p_scientific_error_detected, false),
    COALESCE(p_factual_error_detected, false),
    COALESCE(p_grammar_problem_detected, false),
    COALESCE(p_age_inappropriate_language, false),
    COALESCE(p_missing_information_detected, false),
    COALESCE(p_unnecessary_information_problem, false),

    p_suggested_difficulty,
    p_suggested_cognitive_type,
    NULLIF(btrim(p_suggested_primary_question_type), ''),

    p_difficulty_fit_score,
    p_cognitive_fit_score,
    p_question_type_fit_score,

    p_confidence_score,

    NULLIF(btrim(p_provider_name), ''),
    NULLIF(btrim(p_model_name), ''),
    NULLIF(btrim(p_prompt_version), ''),

    NULLIF(btrim(p_review_summary), ''),

    COALESCE(p_problems, '[]'::jsonb),
    COALESCE(p_suggestions, '[]'::jsonb),
    COALESCE(p_metadata, '{}'::jsonb)
  );


  IF p_reviewer_number = 1 THEN

    UPDATE public.ai_question_quality_runs
    SET status = 'waiting_reviewer_2'
    WHERE id = p_quality_run_id;


    RETURN jsonb_build_object(
      'quality_run_id',
      p_quality_run_id,
      'reviewer',
      1,
      'status',
      'stored',
      'next',
      'waiting_reviewer_2'
    );

  END IF;


  SELECT *
  INTO v_r1
  FROM public.ai_question_quality_reviews r
  WHERE r.quality_run_id = p_quality_run_id
    AND r.reviewer_number = 1;


  SELECT *
  INTO v_r2
  FROM public.ai_question_quality_reviews r
  WHERE r.quality_run_id = p_quality_run_id
    AND r.reviewer_number = 2;


  v_quality :=
    ROUND(
      (
        v_r1.overall_quality_score
        +
        v_r2.overall_quality_score
      ) / 2,
      4
    );


  -- =======================================================
  -- KARAR MOTORU
  -- =======================================================

  IF v_r1.confidence_score < v_run.minimum_confidence
     OR v_r2.confidence_score < v_run.minimum_confidence
  THEN

    v_status := 'low_confidence';
    v_human_review := true;


  ELSIF v_r1.scientific_error_detected
        OR v_r2.scientific_error_detected
        OR v_r1.factual_error_detected
        OR v_r2.factual_error_detected
  THEN

    v_status := 'scientific_problem';
    v_human_review := true;


  ELSIF v_r1.multiple_correct_answer_risk
        OR v_r2.multiple_correct_answer_risk
        OR v_r1.no_correct_answer_risk
        OR v_r2.no_correct_answer_risk
  THEN

    v_status := 'ambiguity_problem';
    v_human_review := true;


  ELSIF v_r1.ambiguous_wording
        OR v_r2.ambiguous_wording
        OR v_r1.missing_information_detected
        OR v_r2.missing_information_detected
  THEN

    v_status := 'ambiguity_problem';
    v_human_review := true;


  ELSIF v_r1.language_score < v_run.minimum_quality_score
        OR v_r2.language_score < v_run.minimum_quality_score
        OR v_r1.age_inappropriate_language
        OR v_r2.age_inappropriate_language
  THEN

    v_status := 'language_problem';
    v_human_review := true;


  ELSIF v_r1.option_quality_score < v_run.minimum_quality_score
        OR v_r2.option_quality_score < v_run.minimum_quality_score
        OR v_r1.misleading_option_risk
        OR v_r2.misleading_option_risk
  THEN

    v_status := 'option_quality_problem';
    v_human_review := true;


  ELSIF v_quality < v_run.minimum_quality_score
  THEN

    v_status := 'needs_human_review';
    v_human_review := true;


  ELSIF v_r1.suggested_difficulty
        IS DISTINCT FROM
        v_r2.suggested_difficulty

        OR

        v_r1.suggested_cognitive_type
        IS DISTINCT FROM
        v_r2.suggested_cognitive_type
  THEN

    v_status := 'reviewer_disagreement';
    v_human_review := true;


  ELSIF v_question.proposed_difficulty IS NOT NULL
        AND v_r1.suggested_difficulty IS NOT NULL
        AND v_r1.suggested_difficulty
            IS DISTINCT FROM
            v_question.proposed_difficulty
  THEN

    v_status := 'difficulty_mismatch';
    v_human_review := true;


  ELSIF v_question.proposed_cognitive_type IS NOT NULL
        AND v_r1.suggested_cognitive_type IS NOT NULL
        AND v_r1.suggested_cognitive_type
            IS DISTINCT FROM
            v_question.proposed_cognitive_type
  THEN

    v_status := 'cognitive_mismatch';
    v_human_review := true;


  ELSIF v_question.proposed_primary_question_type IS NOT NULL
        AND v_r1.suggested_primary_question_type IS NOT NULL
        AND v_r1.suggested_primary_question_type
            IS DISTINCT FROM
            v_question.proposed_primary_question_type
  THEN

    v_status := 'question_type_mismatch';
    v_human_review := true;


  ELSE

    v_status := 'verified';
    v_human_review := false;

  END IF;


  UPDATE public.ai_question_quality_runs
  SET
    status = v_status,

    consensus_quality_score =
      v_quality,

    human_review_required =
      v_human_review,

    metadata =
      metadata
      || jsonb_build_object(
           'reviewer_1_quality_score',
           v_r1.overall_quality_score,

           'reviewer_2_quality_score',
           v_r2.overall_quality_score,

           'automatic_publication_allowed',
           false
         )

  WHERE id = p_quality_run_id;


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
    'language',

    CASE
      WHEN v_status = 'verified'
        THEN 'pass'
      WHEN v_status = 'language_problem'
        THEN 'fail'
      ELSE 'warning'
    END,

    LEAST(
      v_r1.language_score,
      v_r2.language_score
    ),

    'Independent language quality review completed.',

    jsonb_build_object(
      'quality_run_id',
      v_run.id,
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
    'scientific_accuracy',

    CASE
      WHEN v_status = 'scientific_problem'
        THEN 'fail'
      WHEN v_status = 'verified'
        THEN 'pass'
      ELSE 'warning'
    END,

    LEAST(
      v_r1.scientific_accuracy_score,
      v_r2.scientific_accuracy_score
    ),

    'Independent scientific/factual accuracy review completed.',

    jsonb_build_object(
      'quality_run_id',
      v_run.id,
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
    'difficulty',

    CASE
      WHEN v_status = 'difficulty_mismatch'
        THEN 'warning'
      WHEN v_status = 'verified'
        THEN 'pass'
      ELSE 'warning'
    END,

    LEAST(
      COALESCE(v_r1.difficulty_fit_score, 1),
      COALESCE(v_r2.difficulty_fit_score, 1)
    ),

    'Independent difficulty review completed.',

    jsonb_build_object(
      'quality_run_id',
      v_run.id,

      'producer_difficulty',
      v_question.proposed_difficulty,

      'reviewer_1_difficulty',
      v_r1.suggested_difficulty,

      'reviewer_2_difficulty',
      v_r2.suggested_difficulty
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
    'cognitive_level',

    CASE
      WHEN v_status = 'cognitive_mismatch'
        THEN 'warning'
      WHEN v_status = 'verified'
        THEN 'pass'
      ELSE 'warning'
    END,

    LEAST(
      COALESCE(v_r1.cognitive_fit_score, 1),
      COALESCE(v_r2.cognitive_fit_score, 1)
    ),

    'Independent cognitive-level review completed.',

    jsonb_build_object(
      'quality_run_id',
      v_run.id,

      'producer_cognitive_type',
      v_question.proposed_cognitive_type,

      'reviewer_1_cognitive_type',
      v_r1.suggested_cognitive_type,

      'reviewer_2_cognitive_type',
      v_r2.suggested_cognitive_type
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
    'question_type',

    CASE
      WHEN v_status = 'question_type_mismatch'
        THEN 'warning'
      WHEN v_status = 'verified'
        THEN 'pass'
      ELSE 'warning'
    END,

    LEAST(
      COALESCE(v_r1.question_type_fit_score, 1),
      COALESCE(v_r2.question_type_fit_score, 1)
    ),

    'Independent question-type review completed.',

    jsonb_build_object(
      'quality_run_id',
      v_run.id,

      'producer_question_type',
      v_question.proposed_primary_question_type,

      'reviewer_1_question_type',
      v_r1.suggested_primary_question_type,

      'reviewer_2_question_type',
      v_r2.suggested_primary_question_type
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
    'overall',

    CASE
      WHEN v_status = 'verified'
        THEN 'pass'

      WHEN v_status IN (
        'scientific_problem',
        'ambiguity_problem'
      )
        THEN 'fail'

      ELSE 'warning'
    END,

    v_quality,

    'Independent overall question quality review completed.',

    jsonb_build_object(
      'quality_run_id',
      v_run.id,

      'status',
      v_status,

      'human_review_required',
      v_human_review,

      'automatic_publication_allowed',
      false
    )
  );


  UPDATE public.ai_question_staging
  SET
    proposed_quality_level =
      CASE
        WHEN v_quality >= 0.90
          THEN 'high'

        WHEN v_quality >= 0.75
          THEN 'medium'

        ELSE 'low'
      END,

    staging_status =
      CASE
        WHEN v_status = 'verified'
          THEN 'validating'
        ELSE 'needs_review'
      END,

    metadata =
      metadata
      || jsonb_build_object(
           'question_quality_status',
           v_status,

           'question_quality_score',
           v_quality,

           'language_score',
           LEAST(
             v_r1.language_score,
             v_r2.language_score
           ),

           'scientific_accuracy_score',
           LEAST(
             v_r1.scientific_accuracy_score,
             v_r2.scientific_accuracy_score
           ),

           'clarity_score',
           LEAST(
             v_r1.clarity_score,
             v_r2.clarity_score
           ),

           'option_quality_score',
           LEAST(
             v_r1.option_quality_score,
             v_r2.option_quality_score
           ),

           'human_quality_review_required',
           v_human_review,

           'automatic_publication_allowed',
           false
         )

  WHERE id = v_run.staging_question_id;


  RETURN jsonb_build_object(
    'quality_run_id',
    v_run.id,

    'status',
    v_status,

    'quality_score',
    v_quality,

    'human_review_required',
    v_human_review,

    'production_publication',
    false
  );

END;
$$;


REVOKE ALL ON FUNCTION private.submit_question_quality_review(
  uuid,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  text,
  text,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb,
  jsonb
)
FROM PUBLIC, anon;


GRANT EXECUTE ON FUNCTION private.submit_question_quality_review(
  uuid,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  text,
  text,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb,
  jsonb
)
TO authenticated, service_role;


-- =========================================================
-- 5. PUBLIC RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.submit_question_quality_review(
  p_quality_run_id uuid,
  p_reviewer_number integer,

  p_language_score numeric,
  p_scientific_accuracy_score numeric,
  p_clarity_score numeric,
  p_option_quality_score numeric,
  p_age_grade_language_score numeric,
  p_overall_quality_score numeric,

  p_ambiguous_wording boolean DEFAULT false,
  p_multiple_correct_answer_risk boolean DEFAULT false,
  p_no_correct_answer_risk boolean DEFAULT false,
  p_misleading_option_risk boolean DEFAULT false,
  p_scientific_error_detected boolean DEFAULT false,
  p_factual_error_detected boolean DEFAULT false,
  p_grammar_problem_detected boolean DEFAULT false,
  p_age_inappropriate_language boolean DEFAULT false,
  p_missing_information_detected boolean DEFAULT false,
  p_unnecessary_information_problem boolean DEFAULT false,

  p_suggested_difficulty text DEFAULT NULL,
  p_suggested_cognitive_type text DEFAULT NULL,
  p_suggested_primary_question_type text DEFAULT NULL,

  p_difficulty_fit_score numeric DEFAULT NULL,
  p_cognitive_fit_score numeric DEFAULT NULL,
  p_question_type_fit_score numeric DEFAULT NULL,

  p_confidence_score numeric DEFAULT 0,

  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,

  p_review_summary text DEFAULT NULL,

  p_problems jsonb DEFAULT '[]'::jsonb,
  p_suggestions jsonb DEFAULT '[]'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.submit_question_quality_review(
    p_quality_run_id,
    p_reviewer_number,

    p_language_score,
    p_scientific_accuracy_score,
    p_clarity_score,
    p_option_quality_score,
    p_age_grade_language_score,
    p_overall_quality_score,

    p_ambiguous_wording,
    p_multiple_correct_answer_risk,
    p_no_correct_answer_risk,
    p_misleading_option_risk,
    p_scientific_error_detected,
    p_factual_error_detected,
    p_grammar_problem_detected,
    p_age_inappropriate_language,
    p_missing_information_detected,
    p_unnecessary_information_problem,

    p_suggested_difficulty,
    p_suggested_cognitive_type,
    p_suggested_primary_question_type,

    p_difficulty_fit_score,
    p_cognitive_fit_score,
    p_question_type_fit_score,

    p_confidence_score,

    p_provider_name,
    p_model_name,
    p_prompt_version,

    p_review_summary,

    p_problems,
    p_suggestions,
    p_metadata
  );
$$;


REVOKE ALL ON FUNCTION public.submit_question_quality_review(
  uuid,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  text,
  text,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb,
  jsonb
)
FROM PUBLIC, anon;


GRANT EXECUTE ON FUNCTION public.submit_question_quality_review(
  uuid,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  text,
  text,
  text,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb,
  jsonb
)
TO authenticated, service_role;


-- =========================================================
-- 6. HUMAN REVIEW
-- =========================================================

CREATE OR REPLACE FUNCTION private.review_question_quality(
  p_quality_run_id uuid,
  p_decision text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_run public.ai_question_quality_runs%ROWTYPE;
BEGIN

  v_user_id := auth.uid();


  IF v_user_id IS NULL THEN
    RAISE EXCEPTION
      'Authentication required.';
  END IF;


  IF NOT (
    private.current_user_has_admin_permission('questions.approve')
    OR
    private.current_user_has_admin_permission('ai.manage')
  )
  THEN
    RAISE EXCEPTION
      'Question approval permission required.';
  END IF;


  IF p_decision NOT IN (
    'approve',
    'approve_after_correction',
    'reject_question'
  )
  THEN
    RAISE EXCEPTION
      'Invalid quality review decision.';
  END IF;


  SELECT *
  INTO v_run
  FROM public.ai_question_quality_runs r
  WHERE r.id = p_quality_run_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Quality run not found.';
  END IF;


  UPDATE public.ai_question_quality_runs
  SET
    human_review_required = false,

    human_decision = p_decision,

    human_reviewed_by = v_user_id,

    human_reviewed_at = clock_timestamp(),

    status =
      CASE
        WHEN p_decision = 'reject_question'
          THEN 'rejected'
        ELSE 'verified'
      END

  WHERE id = p_quality_run_id;


  IF p_decision = 'reject_question' THEN

    UPDATE public.ai_question_staging
    SET
      staging_status = 'rejected',

      metadata =
        metadata
        || jsonb_build_object(
             'quality_human_decision',
             p_decision
           )

    WHERE id = v_run.staging_question_id;

  ELSE

    UPDATE public.ai_question_staging
    SET
      staging_status = 'validating',

      metadata =
        metadata
        || jsonb_build_object(
             'quality_human_decision',
             p_decision,

             'quality_human_verified',
             true
           )

    WHERE id = v_run.staging_question_id;

  END IF;


  RETURN jsonb_build_object(
    'quality_run_id',
    v_run.id,

    'decision',
    p_decision,

    'production_publication',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.review_question_quality(uuid, text)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.review_question_quality(uuid, text)
TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.review_question_quality(
  p_quality_run_id uuid,
  p_decision text
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.review_question_quality(
    p_quality_run_id,
    p_decision
  );
$$;


REVOKE ALL
ON FUNCTION public.review_question_quality(uuid, text)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.review_question_quality(uuid, text)
TO authenticated, service_role;


-- =========================================================
-- 7. REPORT
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_question_quality_report(
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
    public.current_user_has_admin_permission('questions.edit')
    OR
    public.current_user_has_admin_permission('questions.approve')
    OR
    public.current_user_has_admin_permission('ai.manage')
  )
  THEN
    RAISE EXCEPTION
      'Admin permission required.';
  END IF;


  SELECT jsonb_build_object(
    'quality_run_id',
    r.id,

    'staging_question_id',
    r.staging_question_id,

    'status',
    r.status,

    'minimum_confidence',
    r.minimum_confidence,

    'minimum_quality_score',
    r.minimum_quality_score,

    'consensus_quality_score',
    r.consensus_quality_score,

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
            qr.reviewer_number,

            'language_score',
            qr.language_score,

            'scientific_accuracy_score',
            qr.scientific_accuracy_score,

            'clarity_score',
            qr.clarity_score,

            'option_quality_score',
            qr.option_quality_score,

            'overall_quality_score',
            qr.overall_quality_score,

            'ambiguous_wording',
            qr.ambiguous_wording,

            'multiple_correct_answer_risk',
            qr.multiple_correct_answer_risk,

            'no_correct_answer_risk',
            qr.no_correct_answer_risk,

            'scientific_error_detected',
            qr.scientific_error_detected,

            'factual_error_detected',
            qr.factual_error_detected,

            'confidence_score',
            qr.confidence_score
          )
          ORDER BY qr.reviewer_number
        ),
        '[]'::jsonb
      )

      FROM public.ai_question_quality_reviews qr

      WHERE qr.quality_run_id = r.id
    ),

    'automatic_publication_allowed',
    false
  )
  INTO v_result

  FROM public.ai_question_quality_runs r

  WHERE r.staging_question_id =
        p_staging_question_id;


  IF v_result IS NULL THEN

    RETURN jsonb_build_object(
      'status',
      'quality_review_not_started',

      'staging_question_id',
      p_staging_question_id
    );

  END IF;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_question_quality_report(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_question_quality_report(uuid)
TO authenticated, service_role;


-- =========================================================
-- 8. RLS
-- =========================================================

DROP POLICY IF EXISTS
"admins manage question quality runs"
ON public.ai_question_quality_runs;


CREATE POLICY
"admins manage question quality runs"
ON public.ai_question_quality_runs
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


DROP POLICY IF EXISTS
"admins manage question quality reviews"
ON public.ai_question_quality_reviews;


CREATE POLICY
"admins manage question quality reviews"
ON public.ai_question_quality_reviews
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


-- =========================================================
-- 9. OVERVIEW
-- =========================================================

CREATE OR REPLACE VIEW public.ai_question_quality_overview
WITH (security_invoker = true)
AS

SELECT
  r.id AS quality_run_id,
  r.staging_question_id,
  r.ai_job_id,

  r.status,

  r.consensus_quality_score,

  r.human_review_required,
  r.human_decision,

  r.created_at,
  r.updated_at

FROM public.ai_question_quality_runs r;


REVOKE ALL
ON public.ai_question_quality_overview
FROM PUBLIC, anon;


GRANT SELECT
ON public.ai_question_quality_overview
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