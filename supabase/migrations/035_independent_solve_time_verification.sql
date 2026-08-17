-- 035_independent_solve_time_verification.sql
-- Altın Kalemler
--
-- AI tarafından üretilen her soru için bağımsız,
-- soru-bazlı çözüm süresi doğrulama kapısı.
--
-- Süre yalnız "zorluk" veya "sınıf" üzerinden hesaplanmaz.
-- Her soru ayrı değerlendirilir:
--
-- okuma
-- + muhakeme
-- + görsel/grafik/tablo inceleme
-- + işlem/hesaplama
-- + diğer
-- = toplam çözüm süresi
--
-- İki bağımsız reviewer kullanılır.
-- Reviewer'lar birbirinin sonucunu bilmeden çalışmalıdır.
--
-- PASS sonucu bile production yayını anlamına gelmez.
-- Bu migration gerçek AI API çağrısı yapmaz.

BEGIN;


-- =========================================================
-- 1. ÇÖZÜM SÜRESİ DOĞRULAMA RUN
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_solve_time_verification_runs (
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

  -- Üretici AI'nin ilk tahmini.
  producer_estimated_total_seconds numeric(10,2)
    CHECK (
      producer_estimated_total_seconds IS NULL
      OR producer_estimated_total_seconds > 0
    ),

  -- Generation spec hedef aralığı.
  requested_min_seconds numeric(10,2)
    CHECK (
      requested_min_seconds IS NULL
      OR requested_min_seconds > 0
    ),

  requested_max_seconds numeric(10,2)
    CHECK (
      requested_max_seconds IS NULL
      OR requested_max_seconds > 0
    ),

  -- İki reviewer tamamlandıktan sonra hesaplanan
  -- consensus değerleri.
  consensus_reading_seconds numeric(10,2)
    CHECK (
      consensus_reading_seconds IS NULL
      OR consensus_reading_seconds >= 0
    ),

  consensus_reasoning_seconds numeric(10,2)
    CHECK (
      consensus_reasoning_seconds IS NULL
      OR consensus_reasoning_seconds >= 0
    ),

  consensus_visual_seconds numeric(10,2)
    CHECK (
      consensus_visual_seconds IS NULL
      OR consensus_visual_seconds >= 0
    ),

  consensus_calculation_seconds numeric(10,2)
    CHECK (
      consensus_calculation_seconds IS NULL
      OR consensus_calculation_seconds >= 0
    ),

  consensus_other_seconds numeric(10,2)
    CHECK (
      consensus_other_seconds IS NULL
      OR consensus_other_seconds >= 0
    ),

  consensus_total_seconds numeric(10,2)
    CHECK (
      consensus_total_seconds IS NULL
      OR consensus_total_seconds > 0
    ),

  recommended_race_limit_seconds numeric(10,2)
    CHECK (
      recommended_race_limit_seconds IS NULL
      OR recommended_race_limit_seconds > 0
    ),

  -- Reviewer'ların toplam tahminleri arasındaki fark.
  reviewer_difference_seconds numeric(10,2)
    CHECK (
      reviewer_difference_seconds IS NULL
      OR reviewer_difference_seconds >= 0
    ),

  reviewer_difference_percent numeric(7,2)
    CHECK (
      reviewer_difference_percent IS NULL
      OR reviewer_difference_percent >= 0
    ),

  -- Producer tahmini ile consensus arasındaki fark.
  producer_difference_seconds numeric(10,2)
    CHECK (
      producer_difference_seconds IS NULL
      OR producer_difference_seconds >= 0
    ),

  producer_difference_percent numeric(7,2)
    CHECK (
      producer_difference_percent IS NULL
      OR producer_difference_percent >= 0
    ),

  status text NOT NULL DEFAULT 'waiting_reviewer_1'
    CHECK (
      status IN (
        'waiting_reviewer_1',
        'waiting_reviewer_2',
        'verified',
        'reviewer_disagreement',
        'producer_mismatch',
        'outside_requested_range',
        'low_confidence',
        'needs_human_review',
        'rejected'
      )
    ),

  -- Reviewer confidence eşiği.
  minimum_confidence numeric(5,4)
    NOT NULL DEFAULT 0.90
    CHECK (
      minimum_confidence BETWEEN 0 AND 1
    ),

  -- İki reviewer arasındaki kabul edilebilir
  -- maksimum yüzde fark.
  max_reviewer_difference_percent numeric(7,2)
    NOT NULL DEFAULT 25
    CHECK (
      max_reviewer_difference_percent >= 0
      AND max_reviewer_difference_percent <= 500
    ),

  -- Producer tahmini ile reviewer consensus arasındaki
  -- kabul edilebilir maksimum fark.
  max_producer_difference_percent numeric(7,2)
    NOT NULL DEFAULT 35
    CHECK (
      max_producer_difference_percent >= 0
      AND max_producer_difference_percent <= 500
    ),

  human_review_required boolean NOT NULL DEFAULT false,

  human_decision text
    CHECK (
      human_decision IS NULL
      OR human_decision IN (
        'approve_consensus',
        'override_time',
        'reject_question'
      )
    ),

  human_total_seconds numeric(10,2)
    CHECK (
      human_total_seconds IS NULL
      OR human_total_seconds > 0
    ),

  human_race_limit_seconds numeric(10,2)
    CHECK (
      human_race_limit_seconds IS NULL
      OR human_race_limit_seconds > 0
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
    requested_min_seconds IS NULL
    OR requested_max_seconds IS NULL
    OR requested_min_seconds <= requested_max_seconds
  ),

  CHECK (
    human_decision IS NULL
    OR (
      human_reviewed_by IS NOT NULL
      AND human_reviewed_at IS NOT NULL
    )
  ),

  CHECK (
    human_decision <> 'override_time'
    OR human_total_seconds IS NOT NULL
  )
);


CREATE INDEX IF NOT EXISTS
idx_ai_solve_time_runs_status
ON public.ai_solve_time_verification_runs(
  status,
  created_at DESC
);


CREATE INDEX IF NOT EXISTS
idx_ai_solve_time_runs_staging
ON public.ai_solve_time_verification_runs(
  staging_question_id
);


ALTER TABLE public.ai_solve_time_verification_runs
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS
trigger_ai_solve_time_verification_runs_updated_at
ON public.ai_solve_time_verification_runs;


CREATE TRIGGER
trigger_ai_solve_time_verification_runs_updated_at
BEFORE UPDATE
ON public.ai_solve_time_verification_runs
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. BAĞIMSIZ REVIEWER SONUÇLARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_solve_time_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  verification_run_id uuid NOT NULL
    REFERENCES public.ai_solve_time_verification_runs(id)
    ON DELETE CASCADE,

  reviewer_number smallint NOT NULL
    CHECK (reviewer_number IN (1, 2)),

  -- -------------------------------------------------------
  -- Sürenin bileşenleri
  -- -------------------------------------------------------

  reading_seconds numeric(10,2) NOT NULL DEFAULT 0
    CHECK (reading_seconds >= 0),

  reasoning_seconds numeric(10,2) NOT NULL DEFAULT 0
    CHECK (reasoning_seconds >= 0),

  visual_analysis_seconds numeric(10,2) NOT NULL DEFAULT 0
    CHECK (visual_analysis_seconds >= 0),

  calculation_seconds numeric(10,2) NOT NULL DEFAULT 0
    CHECK (calculation_seconds >= 0),

  other_seconds numeric(10,2) NOT NULL DEFAULT 0
    CHECK (other_seconds >= 0),

  total_seconds numeric(10,2) NOT NULL
    CHECK (total_seconds > 0),

  recommended_race_limit_seconds numeric(10,2) NOT NULL
    CHECK (recommended_race_limit_seconds > 0),

  -- -------------------------------------------------------
  -- Soru özellikleri
  -- -------------------------------------------------------

  text_length_estimate integer
    CHECK (
      text_length_estimate IS NULL
      OR text_length_estimate >= 0
    ),

  option_reading_load numeric(6,2)
    CHECK (
      option_reading_load IS NULL
      OR option_reading_load >= 0
    ),

  reasoning_step_count integer
    CHECK (
      reasoning_step_count IS NULL
      OR reasoning_step_count >= 0
    ),

  calculation_step_count integer
    CHECK (
      calculation_step_count IS NULL
      OR calculation_step_count >= 0
    ),

  formula_count integer
    CHECK (
      formula_count IS NULL
      OR formula_count >= 0
    ),

  visual_count integer
    CHECK (
      visual_count IS NULL
      OR visual_count >= 0
    ),

  graph_count integer
    CHECK (
      graph_count IS NULL
      OR graph_count >= 0
    ),

  table_count integer
    CHECK (
      table_count IS NULL
      OR table_count >= 0
    ),

  diagram_count integer
    CHECK (
      diagram_count IS NULL
      OR diagram_count >= 0
    ),

  -- -------------------------------------------------------
  -- Yük sınıfları
  -- -------------------------------------------------------

  reading_load text
    CHECK (
      reading_load IS NULL
      OR reading_load IN (
        'very_low',
        'low',
        'medium',
        'high',
        'very_high'
      )
    ),

  reasoning_load text
    CHECK (
      reasoning_load IS NULL
      OR reasoning_load IN (
        'very_low',
        'low',
        'medium',
        'high',
        'very_high'
      )
    ),

  calculation_load text
    CHECK (
      calculation_load IS NULL
      OR calculation_load IN (
        'none',
        'very_low',
        'low',
        'medium',
        'high',
        'very_high'
      )
    ),

  visual_load text
    CHECK (
      visual_load IS NULL
      OR visual_load IN (
        'none',
        'very_low',
        'low',
        'medium',
        'high',
        'very_high'
      )
    ),

  confidence_score numeric(5,4) NOT NULL
    CHECK (
      confidence_score BETWEEN 0 AND 1
    ),

  provider_name text,
  model_name text,
  prompt_version text,

  review_summary text,

  calculation_details jsonb NOT NULL DEFAULT '{}'::jsonb,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    verification_run_id,
    reviewer_number
  ),

  -- Bileşenler toplamı ile verilen total arasında
  -- en fazla 1 saniyelik yuvarlama farkına izin ver.
  CHECK (
    abs(
      total_seconds
      -
      (
        reading_seconds
        + reasoning_seconds
        + visual_analysis_seconds
        + calculation_seconds
        + other_seconds
      )
    ) <= 1
  )
);


CREATE INDEX IF NOT EXISTS
idx_ai_solve_time_reviews_run
ON public.ai_solve_time_reviews(
  verification_run_id,
  reviewer_number
);


ALTER TABLE public.ai_solve_time_reviews
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 3. VERIFICATION BAŞLAT
-- =========================================================

CREATE OR REPLACE FUNCTION private.start_solve_time_verification(
  p_staging_question_id uuid,
  p_minimum_confidence numeric DEFAULT 0.90,
  p_max_reviewer_difference_percent numeric DEFAULT 25,
  p_max_producer_difference_percent numeric DEFAULT 35
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_question public.ai_question_staging%ROWTYPE;
  v_spec public.ai_generation_specs%ROWTYPE;
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


  IF p_max_reviewer_difference_percent < 0
     OR p_max_producer_difference_percent < 0 THEN
    RAISE EXCEPTION
      'Difference thresholds cannot be negative.';
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
      'Question cannot enter solve-time verification.';
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


  INSERT INTO public.ai_solve_time_verification_runs (
    staging_question_id,
    ai_job_id,
    generation_spec_id,

    producer_estimated_total_seconds,

    requested_min_seconds,
    requested_max_seconds,

    minimum_confidence,
    max_reviewer_difference_percent,
    max_producer_difference_percent,

    status,

    metadata
  )
  VALUES (
    v_question.id,
    v_question.ai_job_id,
    v_question.generation_spec_id,

    v_question.proposed_solve_time_seconds,

    v_spec.min_solve_time_seconds,
    v_spec.max_solve_time_seconds,

    p_minimum_confidence,
    p_max_reviewer_difference_percent,
    p_max_producer_difference_percent,

    'waiting_reviewer_1',

    jsonb_build_object(
      'question_specific_timing',
      true,
      'independent_reviewers_required',
      2,
      'automatic_scoring_approval',
      false,
      'automatic_publication_allowed',
      false
    )
  )

  ON CONFLICT (staging_question_id)
  DO UPDATE SET
    minimum_confidence =
      EXCLUDED.minimum_confidence,

    max_reviewer_difference_percent =
      EXCLUDED.max_reviewer_difference_percent,

    max_producer_difference_percent =
      EXCLUDED.max_producer_difference_percent

  RETURNING id
  INTO v_run_id;


  UPDATE public.ai_question_staging
  SET
    staging_status = 'validating',

    metadata =
      metadata
      || jsonb_build_object(
           'solve_time_verification_run_id',
           v_run_id,
           'independent_solve_time_verification_required',
           true
         )

  WHERE id = p_staging_question_id;


  RETURN v_run_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.start_solve_time_verification(
  uuid,
  numeric,
  numeric,
  numeric
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.start_solve_time_verification(
  uuid,
  numeric,
  numeric,
  numeric
)
TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.start_solve_time_verification(
  p_staging_question_id uuid,
  p_minimum_confidence numeric DEFAULT 0.90,
  p_max_reviewer_difference_percent numeric DEFAULT 25,
  p_max_producer_difference_percent numeric DEFAULT 35
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.start_solve_time_verification(
    p_staging_question_id,
    p_minimum_confidence,
    p_max_reviewer_difference_percent,
    p_max_producer_difference_percent
  );
$$;


REVOKE ALL
ON FUNCTION public.start_solve_time_verification(
  uuid,
  numeric,
  numeric,
  numeric
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.start_solve_time_verification(
  uuid,
  numeric,
  numeric,
  numeric
)
TO authenticated, service_role;


-- =========================================================
-- 4. REVIEWER SONUCU GÖNDER
-- =========================================================

CREATE OR REPLACE FUNCTION private.submit_solve_time_review(
  p_verification_run_id uuid,
  p_reviewer_number integer,

  p_reading_seconds numeric,
  p_reasoning_seconds numeric,
  p_visual_analysis_seconds numeric,
  p_calculation_seconds numeric,
  p_other_seconds numeric,

  p_recommended_race_limit_seconds numeric,

  p_confidence_score numeric,

  p_reading_load text DEFAULT NULL,
  p_reasoning_load text DEFAULT NULL,
  p_calculation_load text DEFAULT NULL,
  p_visual_load text DEFAULT NULL,

  p_reasoning_step_count integer DEFAULT NULL,
  p_calculation_step_count integer DEFAULT NULL,
  p_formula_count integer DEFAULT NULL,
  p_visual_count integer DEFAULT NULL,
  p_graph_count integer DEFAULT NULL,
  p_table_count integer DEFAULT NULL,
  p_diagram_count integer DEFAULT NULL,

  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,

  p_review_summary text DEFAULT NULL,

  p_calculation_details jsonb DEFAULT '{}'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run public.ai_solve_time_verification_runs%ROWTYPE;

  v_total numeric(10,2);

  v_r1 public.ai_solve_time_reviews%ROWTYPE;
  v_r2 public.ai_solve_time_reviews%ROWTYPE;

  v_consensus_reading numeric;
  v_consensus_reasoning numeric;
  v_consensus_visual numeric;
  v_consensus_calculation numeric;
  v_consensus_other numeric;
  v_consensus_total numeric;
  v_consensus_race_limit numeric;

  v_reviewer_diff_seconds numeric;
  v_reviewer_diff_percent numeric;

  v_producer_diff_seconds numeric;
  v_producer_diff_percent numeric;

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


  IF p_confidence_score < 0
     OR p_confidence_score > 1 THEN
    RAISE EXCEPTION
      'Confidence score must be between 0 and 1.';
  END IF;


  IF COALESCE(p_reading_seconds, -1) < 0
     OR COALESCE(p_reasoning_seconds, -1) < 0
     OR COALESCE(p_visual_analysis_seconds, -1) < 0
     OR COALESCE(p_calculation_seconds, -1) < 0
     OR COALESCE(p_other_seconds, -1) < 0 THEN

    RAISE EXCEPTION
      'Solve-time components cannot be negative or null.';

  END IF;


  IF p_recommended_race_limit_seconds IS NULL
     OR p_recommended_race_limit_seconds <= 0 THEN

    RAISE EXCEPTION
      'Recommended race limit must be positive.';

  END IF;


  v_total :=
    p_reading_seconds
    + p_reasoning_seconds
    + p_visual_analysis_seconds
    + p_calculation_seconds
    + p_other_seconds;


  IF v_total <= 0 THEN
    RAISE EXCEPTION
      'Total solve time must be greater than zero.';
  END IF;


  SELECT *
  INTO v_run
  FROM public.ai_solve_time_verification_runs r
  WHERE r.id = p_verification_run_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Solve-time verification run not found.';
  END IF;


  IF v_run.status IN (
    'verified',
    'rejected'
  ) THEN
    RAISE EXCEPTION
      'Solve-time verification is already finalized.';
  END IF;


  IF p_reviewer_number = 2
     AND NOT EXISTS (
       SELECT 1
       FROM public.ai_solve_time_reviews sr
       WHERE sr.verification_run_id =
             p_verification_run_id
         AND sr.reviewer_number = 1
     )
  THEN
    RAISE EXCEPTION
      'Reviewer 1 must complete first.';
  END IF;


  INSERT INTO public.ai_solve_time_reviews (
    verification_run_id,
    reviewer_number,

    reading_seconds,
    reasoning_seconds,
    visual_analysis_seconds,
    calculation_seconds,
    other_seconds,

    total_seconds,

    recommended_race_limit_seconds,

    reasoning_step_count,
    calculation_step_count,
    formula_count,
    visual_count,
    graph_count,
    table_count,
    diagram_count,

    reading_load,
    reasoning_load,
    calculation_load,
    visual_load,

    confidence_score,

    provider_name,
    model_name,
    prompt_version,

    review_summary,
    calculation_details,
    metadata
  )
  VALUES (
    p_verification_run_id,
    p_reviewer_number,

    p_reading_seconds,
    p_reasoning_seconds,
    p_visual_analysis_seconds,
    p_calculation_seconds,
    p_other_seconds,

    v_total,

    p_recommended_race_limit_seconds,

    p_reasoning_step_count,
    p_calculation_step_count,
    p_formula_count,
    p_visual_count,
    p_graph_count,
    p_table_count,
    p_diagram_count,

    p_reading_load,
    p_reasoning_load,
    p_calculation_load,
    p_visual_load,

    p_confidence_score,

    NULLIF(btrim(p_provider_name), ''),
    NULLIF(btrim(p_model_name), ''),
    NULLIF(btrim(p_prompt_version), ''),

    NULLIF(btrim(p_review_summary), ''),

    COALESCE(
      p_calculation_details,
      '{}'::jsonb
    ),

    COALESCE(
      p_metadata,
      '{}'::jsonb
    )
  );


  -- Reviewer 1'den sonra bekle.

  IF p_reviewer_number = 1 THEN

    UPDATE public.ai_solve_time_verification_runs
    SET status = 'waiting_reviewer_2'
    WHERE id = p_verification_run_id;


    RETURN jsonb_build_object(
      'verification_run_id',
      p_verification_run_id,
      'reviewer',
      1,
      'estimated_total_seconds',
      v_total,
      'status',
      'stored',
      'next',
      'waiting_reviewer_2'
    );

  END IF;


  -- =======================================================
  -- İKİ REVIEWER SONUCU
  -- =======================================================

  SELECT *
  INTO v_r1
  FROM public.ai_solve_time_reviews r
  WHERE r.verification_run_id =
        p_verification_run_id
    AND r.reviewer_number = 1;


  SELECT *
  INTO v_r2
  FROM public.ai_solve_time_reviews r
  WHERE r.verification_run_id =
        p_verification_run_id
    AND r.reviewer_number = 2;


  -- Consensus: iki bağımsız tahminin ortalaması.
  -- Daha sonra gerçek öğrenci istatistikleriyle kalibre edilir.

  v_consensus_reading :=
    ROUND(
      (
        v_r1.reading_seconds
        + v_r2.reading_seconds
      ) / 2,
      2
    );


  v_consensus_reasoning :=
    ROUND(
      (
        v_r1.reasoning_seconds
        + v_r2.reasoning_seconds
      ) / 2,
      2
    );


  v_consensus_visual :=
    ROUND(
      (
        v_r1.visual_analysis_seconds
        + v_r2.visual_analysis_seconds
      ) / 2,
      2
    );


  v_consensus_calculation :=
    ROUND(
      (
        v_r1.calculation_seconds
        + v_r2.calculation_seconds
      ) / 2,
      2
    );


  v_consensus_other :=
    ROUND(
      (
        v_r1.other_seconds
        + v_r2.other_seconds
      ) / 2,
      2
    );


  v_consensus_total :=
    ROUND(
      (
        v_r1.total_seconds
        + v_r2.total_seconds
      ) / 2,
      2
    );


  v_consensus_race_limit :=
    ROUND(
      (
        v_r1.recommended_race_limit_seconds
        + v_r2.recommended_race_limit_seconds
      ) / 2,
      2
    );


  -- =======================================================
  -- REVIEWER FARKI
  -- =======================================================

  v_reviewer_diff_seconds :=
    ABS(
      v_r1.total_seconds
      - v_r2.total_seconds
    );


  v_reviewer_diff_percent :=
    CASE
      WHEN v_consensus_total > 0
      THEN
        ROUND(
          (
            v_reviewer_diff_seconds
            / v_consensus_total
          ) * 100,
          2
        )
      ELSE 0
    END;


  -- =======================================================
  -- PRODUCER FARKI
  -- =======================================================

  IF v_run.producer_estimated_total_seconds IS NOT NULL THEN

    v_producer_diff_seconds :=
      ABS(
        v_run.producer_estimated_total_seconds
        - v_consensus_total
      );


    v_producer_diff_percent :=
      CASE
        WHEN v_consensus_total > 0
        THEN
          ROUND(
            (
              v_producer_diff_seconds
              / v_consensus_total
            ) * 100,
            2
          )
        ELSE 0
      END;

  ELSE

    v_producer_diff_seconds := NULL;
    v_producer_diff_percent := NULL;

  END IF;


  -- =======================================================
  -- KARAR MOTORU
  -- =======================================================

  IF v_r1.confidence_score <
       v_run.minimum_confidence
     OR
     v_r2.confidence_score <
       v_run.minimum_confidence
  THEN

    v_status := 'low_confidence';
    v_human_review := true;


  ELSIF v_reviewer_diff_percent >
        v_run.max_reviewer_difference_percent
  THEN

    v_status := 'reviewer_disagreement';
    v_human_review := true;


  ELSIF v_producer_diff_percent IS NOT NULL
        AND v_producer_diff_percent >
            v_run.max_producer_difference_percent
  THEN

    v_status := 'producer_mismatch';
    v_human_review := true;


  ELSIF v_run.requested_min_seconds IS NOT NULL
        AND v_consensus_total <
            v_run.requested_min_seconds
  THEN

    v_status := 'outside_requested_range';
    v_human_review := true;


  ELSIF v_run.requested_max_seconds IS NOT NULL
        AND v_consensus_total >
            v_run.requested_max_seconds
  THEN

    v_status := 'outside_requested_range';
    v_human_review := true;


  ELSE

    v_status := 'verified';
    v_human_review := false;

  END IF;


  UPDATE public.ai_solve_time_verification_runs
  SET
    consensus_reading_seconds =
      v_consensus_reading,

    consensus_reasoning_seconds =
      v_consensus_reasoning,

    consensus_visual_seconds =
      v_consensus_visual,

    consensus_calculation_seconds =
      v_consensus_calculation,

    consensus_other_seconds =
      v_consensus_other,

    consensus_total_seconds =
      v_consensus_total,

    recommended_race_limit_seconds =
      v_consensus_race_limit,

    reviewer_difference_seconds =
      v_reviewer_diff_seconds,

    reviewer_difference_percent =
      v_reviewer_diff_percent,

    producer_difference_seconds =
      v_producer_diff_seconds,

    producer_difference_percent =
      v_producer_diff_percent,

    status =
      v_status,

    human_review_required =
      v_human_review,

    metadata =
      metadata
      || jsonb_build_object(
           'reviewer_1_total_seconds',
           v_r1.total_seconds,

           'reviewer_2_total_seconds',
           v_r2.total_seconds,

           'reviewer_1_confidence',
           v_r1.confidence_score,

           'reviewer_2_confidence',
           v_r2.confidence_score,

           'real_student_calibration_required_later',
           true,

           'approved_for_scoring',
           false
         )

  WHERE id = p_verification_run_id;


  -- =======================================================
  -- STAGING UPDATE
  --
  -- Verified bile olsa soru APPROVED olmaz.
  -- Ayrıca scoring için otomatik onay verilmez.
  -- =======================================================

  UPDATE public.ai_question_staging
  SET
    proposed_solve_time_seconds =
      CASE
        WHEN v_status = 'verified'
        THEN ROUND(v_consensus_total)::integer
        ELSE proposed_solve_time_seconds
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
           'solve_time_verification_status',
           v_status,

           'reading_seconds',
           v_consensus_reading,

           'reasoning_seconds',
           v_consensus_reasoning,

           'visual_analysis_seconds',
           v_consensus_visual,

           'calculation_seconds',
           v_consensus_calculation,

           'other_seconds',
           v_consensus_other,

           'verified_total_seconds',
           v_consensus_total,

           'recommended_race_limit_seconds',
           v_consensus_race_limit,

           'reviewer_difference_percent',
           v_reviewer_diff_percent,

           'producer_difference_percent',
           v_producer_diff_percent,

           'human_solve_time_review_required',
           v_human_review,

           'question_specific_time_verified',
           v_status = 'verified',

           'approved_for_scoring',
           false
         )

  WHERE id = v_run.staging_question_id;


  RETURN jsonb_build_object(
    'verification_run_id',
    v_run.id,

    'status',
    v_status,

    'producer_estimated_seconds',
    v_run.producer_estimated_total_seconds,

    'reviewer_1_total_seconds',
    v_r1.total_seconds,

    'reviewer_2_total_seconds',
    v_r2.total_seconds,

    'consensus_total_seconds',
    v_consensus_total,

    'recommended_race_limit_seconds',
    v_consensus_race_limit,

    'reviewer_difference_percent',
    v_reviewer_diff_percent,

    'producer_difference_percent',
    v_producer_diff_percent,

    'human_review_required',
    v_human_review,

    'approved_for_scoring',
    false,

    'production_publication',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.submit_solve_time_review(
  uuid,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  integer,
  integer,
  integer,
  integer,
  integer,
  integer,
  integer,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.submit_solve_time_review(
  uuid,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  integer,
  integer,
  integer,
  integer,
  integer,
  integer,
  integer,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb
)
TO authenticated, service_role;


-- =========================================================
-- 5. PUBLIC REVIEW RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.submit_solve_time_review(
  p_verification_run_id uuid,
  p_reviewer_number integer,

  p_reading_seconds numeric,
  p_reasoning_seconds numeric,
  p_visual_analysis_seconds numeric,
  p_calculation_seconds numeric,
  p_other_seconds numeric,

  p_recommended_race_limit_seconds numeric,

  p_confidence_score numeric,

  p_reading_load text DEFAULT NULL,
  p_reasoning_load text DEFAULT NULL,
  p_calculation_load text DEFAULT NULL,
  p_visual_load text DEFAULT NULL,

  p_reasoning_step_count integer DEFAULT NULL,
  p_calculation_step_count integer DEFAULT NULL,
  p_formula_count integer DEFAULT NULL,
  p_visual_count integer DEFAULT NULL,
  p_graph_count integer DEFAULT NULL,
  p_table_count integer DEFAULT NULL,
  p_diagram_count integer DEFAULT NULL,

  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,

  p_review_summary text DEFAULT NULL,

  p_calculation_details jsonb DEFAULT '{}'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.submit_solve_time_review(
    p_verification_run_id,
    p_reviewer_number,

    p_reading_seconds,
    p_reasoning_seconds,
    p_visual_analysis_seconds,
    p_calculation_seconds,
    p_other_seconds,

    p_recommended_race_limit_seconds,

    p_confidence_score,

    p_reading_load,
    p_reasoning_load,
    p_calculation_load,
    p_visual_load,

    p_reasoning_step_count,
    p_calculation_step_count,
    p_formula_count,
    p_visual_count,
    p_graph_count,
    p_table_count,
    p_diagram_count,

    p_provider_name,
    p_model_name,
    p_prompt_version,

    p_review_summary,

    p_calculation_details,
    p_metadata
  );
$$;


REVOKE ALL
ON FUNCTION public.submit_solve_time_review(
  uuid,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  integer,
  integer,
  integer,
  integer,
  integer,
  integer,
  integer,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.submit_solve_time_review(
  uuid,
  integer,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  text,
  text,
  text,
  text,
  integer,
  integer,
  integer,
  integer,
  integer,
  integer,
  integer,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb
)
TO authenticated, service_role;


-- =========================================================
-- 6. İNSAN SÜRE İNCELEMESİ
-- =========================================================

CREATE OR REPLACE FUNCTION private.review_solve_time_verification(
  p_verification_run_id uuid,
  p_decision text,
  p_total_seconds numeric DEFAULT NULL,
  p_race_limit_seconds numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_run public.ai_solve_time_verification_runs%ROWTYPE;
  v_final_total numeric;
  v_final_race_limit numeric;
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
    'approve_consensus',
    'override_time',
    'reject_question'
  ) THEN
    RAISE EXCEPTION
      'Invalid solve-time review decision.';
  END IF;


  SELECT *
  INTO v_run
  FROM public.ai_solve_time_verification_runs r
  WHERE r.id = p_verification_run_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Solve-time verification run not found.';
  END IF;


  IF p_decision = 'approve_consensus' THEN

    IF v_run.consensus_total_seconds IS NULL THEN
      RAISE EXCEPTION
        'Consensus solve time is not available.';
    END IF;


    v_final_total :=
      v_run.consensus_total_seconds;


    v_final_race_limit :=
      COALESCE(
        v_run.recommended_race_limit_seconds,
        v_run.consensus_total_seconds
      );


  ELSIF p_decision = 'override_time' THEN

    IF p_total_seconds IS NULL
       OR p_total_seconds <= 0 THEN

      RAISE EXCEPTION
        'A positive total solve time is required for override.';

    END IF;


    v_final_total :=
      p_total_seconds;


    v_final_race_limit :=
      COALESCE(
        NULLIF(p_race_limit_seconds, 0),
        p_total_seconds
      );


    IF v_final_race_limit <= 0 THEN
      RAISE EXCEPTION
        'Race limit must be positive.';
    END IF;


  ELSE

    v_final_total := NULL;
    v_final_race_limit := NULL;

  END IF;


  UPDATE public.ai_solve_time_verification_runs
  SET
    human_review_required = false,

    human_decision =
      p_decision,

    human_total_seconds =
      v_final_total,

    human_race_limit_seconds =
      v_final_race_limit,

    human_reviewed_by =
      v_user_id,

    human_reviewed_at =
      clock_timestamp(),

    status =
      CASE
        WHEN p_decision IN (
          'approve_consensus',
          'override_time'
        )
        THEN 'verified'
        ELSE 'rejected'
      END,

    metadata =
      metadata
      || jsonb_build_object(
           'human_verified',
           true,
           'human_decision',
           p_decision,
           'approved_for_scoring',
           false
         )

  WHERE id = p_verification_run_id;


  IF p_decision = 'reject_question' THEN

    UPDATE public.ai_question_staging
    SET
      staging_status = 'rejected',

      metadata =
        metadata
        || jsonb_build_object(
             'solve_time_human_decision',
             'reject_question'
           )

    WHERE id = v_run.staging_question_id;


  ELSE

    UPDATE public.ai_question_staging
    SET
      proposed_solve_time_seconds =
        ROUND(v_final_total)::integer,

      staging_status =
        'validating',

      metadata =
        metadata
        || jsonb_build_object(
             'solve_time_human_decision',
             p_decision,

             'human_verified_total_seconds',
             v_final_total,

             'human_verified_race_limit_seconds',
             v_final_race_limit,

             'question_specific_time_verified',
             true,

             'approved_for_scoring',
             false
           )

    WHERE id = v_run.staging_question_id;

  END IF;


  RETURN jsonb_build_object(
    'verification_run_id',
    v_run.id,

    'decision',
    p_decision,

    'final_total_seconds',
    v_final_total,

    'final_race_limit_seconds',
    v_final_race_limit,

    'approved_for_scoring',
    false,

    'production_publication',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.review_solve_time_verification(
  uuid,
  text,
  numeric,
  numeric
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.review_solve_time_verification(
  uuid,
  text,
  numeric,
  numeric
)
TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.review_solve_time_verification(
  p_verification_run_id uuid,
  p_decision text,
  p_total_seconds numeric DEFAULT NULL,
  p_race_limit_seconds numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.review_solve_time_verification(
    p_verification_run_id,
    p_decision,
    p_total_seconds,
    p_race_limit_seconds
  );
$$;


REVOKE ALL
ON FUNCTION public.review_solve_time_verification(
  uuid,
  text,
  numeric,
  numeric
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.review_solve_time_verification(
  uuid,
  text,
  numeric,
  numeric
)
TO authenticated, service_role;


-- =========================================================
-- 7. RAPOR
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_solve_time_verification_report(
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

    'producer_estimated_total_seconds',
    r.producer_estimated_total_seconds,

    'requested_range',
    jsonb_build_object(
      'minimum_seconds',
      r.requested_min_seconds,
      'maximum_seconds',
      r.requested_max_seconds
    ),

    'consensus',
    jsonb_build_object(
      'reading_seconds',
      r.consensus_reading_seconds,

      'reasoning_seconds',
      r.consensus_reasoning_seconds,

      'visual_seconds',
      r.consensus_visual_seconds,

      'calculation_seconds',
      r.consensus_calculation_seconds,

      'other_seconds',
      r.consensus_other_seconds,

      'total_seconds',
      r.consensus_total_seconds,

      'recommended_race_limit_seconds',
      r.recommended_race_limit_seconds
    ),

    'reviewer_difference_percent',
    r.reviewer_difference_percent,

    'producer_difference_percent',
    r.producer_difference_percent,

    'status',
    r.status,

    'minimum_confidence',
    r.minimum_confidence,

    'human_review_required',
    r.human_review_required,

    'human_decision',
    r.human_decision,

    'human_total_seconds',
    r.human_total_seconds,

    'human_race_limit_seconds',
    r.human_race_limit_seconds,

    'reviews',
    (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'reviewer_number',
            sr.reviewer_number,

            'reading_seconds',
            sr.reading_seconds,

            'reasoning_seconds',
            sr.reasoning_seconds,

            'visual_seconds',
            sr.visual_analysis_seconds,

            'calculation_seconds',
            sr.calculation_seconds,

            'other_seconds',
            sr.other_seconds,

            'total_seconds',
            sr.total_seconds,

            'recommended_race_limit_seconds',
            sr.recommended_race_limit_seconds,

            'reading_load',
            sr.reading_load,

            'reasoning_load',
            sr.reasoning_load,

            'calculation_load',
            sr.calculation_load,

            'visual_load',
            sr.visual_load,

            'reasoning_step_count',
            sr.reasoning_step_count,

            'calculation_step_count',
            sr.calculation_step_count,

            'confidence_score',
            sr.confidence_score,

            'provider',
            sr.provider_name,

            'model',
            sr.model_name
          )
          ORDER BY sr.reviewer_number
        ),

        '[]'::jsonb
      )

      FROM public.ai_solve_time_reviews sr

      WHERE sr.verification_run_id =
            r.id
    ),

    'real_student_calibration_required_later',
    true,

    'approved_for_scoring',
    false,

    'automatic_publication_allowed',
    false

  )
  INTO v_result

  FROM public.ai_solve_time_verification_runs r

  WHERE r.staging_question_id =
        p_staging_question_id;


  IF v_result IS NULL THEN

    RETURN jsonb_build_object(
      'status',
      'solve_time_verification_not_started',

      'staging_question_id',
      p_staging_question_id
    );

  END IF;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_solve_time_verification_report(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_solve_time_verification_report(uuid)
TO authenticated, service_role;


-- =========================================================
-- 8. ADMIN RLS
-- =========================================================

DROP POLICY IF EXISTS
"admins manage solve time verification runs"
ON public.ai_solve_time_verification_runs;


CREATE POLICY
"admins manage solve time verification runs"
ON public.ai_solve_time_verification_runs
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
"admins manage solve time reviews"
ON public.ai_solve_time_reviews;


CREATE POLICY
"admins manage solve time reviews"
ON public.ai_solve_time_reviews
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
-- 9. ADMIN OVERVIEW
-- =========================================================

CREATE OR REPLACE VIEW public.ai_solve_time_verification_overview
WITH (security_invoker = true)
AS

SELECT
  r.id AS verification_run_id,

  r.staging_question_id,

  r.ai_job_id,

  r.producer_estimated_total_seconds,

  r.consensus_reading_seconds,
  r.consensus_reasoning_seconds,
  r.consensus_visual_seconds,
  r.consensus_calculation_seconds,
  r.consensus_other_seconds,

  r.consensus_total_seconds,

  r.recommended_race_limit_seconds,

  r.reviewer_difference_percent,
  r.producer_difference_percent,

  r.status,

  r.human_review_required,
  r.human_decision,

  r.created_at,
  r.updated_at

FROM public.ai_solve_time_verification_runs r;


REVOKE ALL
ON public.ai_solve_time_verification_overview
FROM PUBLIC;


REVOKE ALL
ON public.ai_solve_time_verification_overview
FROM anon;


GRANT SELECT
ON public.ai_solve_time_verification_overview
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