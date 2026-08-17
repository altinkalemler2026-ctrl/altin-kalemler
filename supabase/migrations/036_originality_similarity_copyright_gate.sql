-- 036_originality_similarity_copyright_gate.sql
-- Altın Kalemler
--
-- AI soru fabrikası:
-- - özgünlük doğrulaması
-- - metin benzerliği
-- - semantik benzerlik
-- - yapısal benzerlik
-- - kavram benzerliği
-- - çözüm yolu benzerliği
-- - telif risk yönlendirmesi
--
-- ÖNEMLİ:
-- Bu sistem hukuki karar vermez.
-- Eşikler yalnız teknik risk yönlendirme eşikleridir.
--
-- Bir soru bu kapıdan geçse bile:
-- commercial_use_allowed = false kalır.
--
-- Ticari kullanım ayrıca:
-- ownership + license + copyright + human/commercial gate
-- kontrollerinden geçmelidir.
--
-- AI doğrudan production'a yayın yapamaz.

BEGIN;


-- =========================================================
-- 1. ORIGINALITY / COPYRIGHT VERIFICATION RUN
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_originality_verification_runs (
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

        'low_originality',
        'high_similarity',
        'possible_duplicate',
        'copyright_risk',
        'reviewer_disagreement',
        'low_confidence',

        'needs_human_review',
        'blocked',
        'rejected'
      )
    ),

  -- Teknik kalite eşiği.
  -- Hukuki eşik değildir.
  minimum_originality_score numeric(5,4)
    NOT NULL DEFAULT 0.90
    CHECK (
      minimum_originality_score BETWEEN 0 AND 1
    ),

  -- Bu değerin üzeri incelemeye gönderilir.
  maximum_similarity_score numeric(5,4)
    NOT NULL DEFAULT 0.80
    CHECK (
      maximum_similarity_score BETWEEN 0 AND 1
    ),

  -- Çok yüksek benzerlik.
  -- Otomatik ticari izin vermez;
  -- insan incelemesine yönlendirir.
  critical_similarity_score numeric(5,4)
    NOT NULL DEFAULT 0.92
    CHECK (
      critical_similarity_score BETWEEN 0 AND 1
    ),

  minimum_confidence numeric(5,4)
    NOT NULL DEFAULT 0.90
    CHECK (
      minimum_confidence BETWEEN 0 AND 1
    ),

  consensus_originality_score numeric(5,4)
    CHECK (
      consensus_originality_score IS NULL
      OR consensus_originality_score BETWEEN 0 AND 1
    ),

  highest_detected_similarity_score numeric(5,4)
    CHECK (
      highest_detected_similarity_score IS NULL
      OR highest_detected_similarity_score BETWEEN 0 AND 1
    ),

  highest_similarity_type text
    CHECK (
      highest_similarity_type IS NULL
      OR highest_similarity_type IN (
        'exact',
        'text',
        'semantic',
        'structure',
        'concept',
        'solution_path'
      )
    ),

  copyright_risk_level text NOT NULL DEFAULT 'unknown'
    CHECK (
      copyright_risk_level IN (
        'unknown',
        'low',
        'medium',
        'high',
        'blocked'
      )
    ),

  human_review_required boolean NOT NULL DEFAULT false,

  human_decision text
    CHECK (
      human_decision IS NULL
      OR human_decision IN (
        'approve_originality',
        'keep_for_noncommercial_review',
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
    maximum_similarity_score
    <= critical_similarity_score
  ),

  CHECK (
    human_decision IS NULL
    OR (
      human_reviewed_by IS NOT NULL
      AND human_reviewed_at IS NOT NULL
    )
  )
);


CREATE INDEX IF NOT EXISTS
idx_ai_originality_runs_status
ON public.ai_originality_verification_runs(
  status,
  created_at DESC
);


CREATE INDEX IF NOT EXISTS
idx_ai_originality_runs_staging
ON public.ai_originality_verification_runs(
  staging_question_id
);


ALTER TABLE public.ai_originality_verification_runs
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS
trigger_ai_originality_runs_updated_at
ON public.ai_originality_verification_runs;


CREATE TRIGGER
trigger_ai_originality_runs_updated_at
BEFORE UPDATE
ON public.ai_originality_verification_runs
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. BAĞIMSIZ ORIGINALITY REVIEWER SONUÇLARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_originality_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  verification_run_id uuid NOT NULL
    REFERENCES public.ai_originality_verification_runs(id)
    ON DELETE CASCADE,

  reviewer_number smallint NOT NULL
    CHECK (
      reviewer_number IN (1, 2)
    ),

  originality_score numeric(5,4) NOT NULL
    CHECK (
      originality_score BETWEEN 0 AND 1
    ),

  -- En yüksek benzerlik skorları.
  exact_similarity_score numeric(5,4)
    CHECK (
      exact_similarity_score IS NULL
      OR exact_similarity_score BETWEEN 0 AND 1
    ),

  text_similarity_score numeric(5,4)
    CHECK (
      text_similarity_score IS NULL
      OR text_similarity_score BETWEEN 0 AND 1
    ),

  semantic_similarity_score numeric(5,4)
    CHECK (
      semantic_similarity_score IS NULL
      OR semantic_similarity_score BETWEEN 0 AND 1
    ),

  structural_similarity_score numeric(5,4)
    CHECK (
      structural_similarity_score IS NULL
      OR structural_similarity_score BETWEEN 0 AND 1
    ),

  concept_similarity_score numeric(5,4)
    CHECK (
      concept_similarity_score IS NULL
      OR concept_similarity_score BETWEEN 0 AND 1
    ),

  solution_path_similarity_score numeric(5,4)
    CHECK (
      solution_path_similarity_score IS NULL
      OR solution_path_similarity_score BETWEEN 0 AND 1
    ),

  -- Reviewer'ın gördüğü en yüksek benzerlik.
  highest_similarity_score numeric(5,4) NOT NULL
    CHECK (
      highest_similarity_score BETWEEN 0 AND 1
    ),

  highest_similarity_type text
    CHECK (
      highest_similarity_type IS NULL
      OR highest_similarity_type IN (
        'exact',
        'text',
        'semantic',
        'structure',
        'concept',
        'solution_path'
      )
    ),

  -- En çok benzeyen kayıt.
  matched_question_id uuid
    REFERENCES public.questions(id)
    ON DELETE SET NULL,

  matched_staging_id uuid
    REFERENCES public.ai_question_staging(id)
    ON DELETE SET NULL,

  matched_source_id uuid
    REFERENCES public.question_sources(id)
    ON DELETE SET NULL,

  -- Sadece kelime / sayı değiştirilmiş mi?
  superficial_rewrite_detected boolean NOT NULL DEFAULT false,

  -- Aynı soru iskeleti korunuyor mu?
  template_copy_detected boolean NOT NULL DEFAULT false,

  -- Çözüm yolu olağandışı ölçüde aynı mı?
  solution_path_copy_risk boolean NOT NULL DEFAULT false,

  copyright_risk_level text NOT NULL DEFAULT 'unknown'
    CHECK (
      copyright_risk_level IN (
        'unknown',
        'low',
        'medium',
        'high',
        'blocked'
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

  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    verification_run_id,
    reviewer_number
  ),

  CHECK (
    NOT (
      matched_question_id IS NOT NULL
      AND matched_staging_id IS NOT NULL
    )
  )
);


CREATE INDEX IF NOT EXISTS
idx_ai_originality_reviews_run
ON public.ai_originality_reviews(
  verification_run_id,
  reviewer_number
);


ALTER TABLE public.ai_originality_reviews
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 3. VERIFICATION BAŞLAT
-- =========================================================

CREATE OR REPLACE FUNCTION private.start_originality_verification(
  p_staging_question_id uuid,
  p_minimum_originality_score numeric DEFAULT 0.90,
  p_maximum_similarity_score numeric DEFAULT 0.80,
  p_critical_similarity_score numeric DEFAULT 0.92,
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
       private.current_user_has_admin_permission('ai.manage')
       OR
       private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION
      'AI management or question approval permission required.';
  END IF;


  IF p_minimum_originality_score < 0
     OR p_minimum_originality_score > 1
     OR p_maximum_similarity_score < 0
     OR p_maximum_similarity_score > 1
     OR p_critical_similarity_score < 0
     OR p_critical_similarity_score > 1
     OR p_minimum_confidence < 0
     OR p_minimum_confidence > 1
  THEN
    RAISE EXCEPTION
      'Scores must be between 0 and 1.';
  END IF;


  IF p_maximum_similarity_score >
     p_critical_similarity_score
  THEN
    RAISE EXCEPTION
      'Maximum similarity threshold cannot exceed critical threshold.';
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
      'Question cannot enter originality verification.';
  END IF;


  INSERT INTO public.ai_originality_verification_runs (
    staging_question_id,
    ai_job_id,
    generation_spec_id,

    status,

    minimum_originality_score,
    maximum_similarity_score,
    critical_similarity_score,
    minimum_confidence,

    copyright_risk_level,

    metadata
  )
  VALUES (
    v_question.id,
    v_question.ai_job_id,
    v_question.generation_spec_id,

    'waiting_reviewer_1',

    p_minimum_originality_score,
    p_maximum_similarity_score,
    p_critical_similarity_score,
    p_minimum_confidence,

    'unknown',

    jsonb_build_object(
      'independent_reviewers_required',
      2,

      'legal_determination',
      false,

      'commercial_use_allowed',
      false,

      'automatic_publication_allowed',
      false,

      'thresholds_are_technical_risk_thresholds',
      true
    )
  )

  ON CONFLICT (staging_question_id)
  DO UPDATE SET
    minimum_originality_score =
      EXCLUDED.minimum_originality_score,

    maximum_similarity_score =
      EXCLUDED.maximum_similarity_score,

    critical_similarity_score =
      EXCLUDED.critical_similarity_score,

    minimum_confidence =
      EXCLUDED.minimum_confidence

  RETURNING id
  INTO v_run_id;


  -- Ticari kullanım bu aşamada açıkça kapalıdır.

  UPDATE public.ai_question_staging
  SET
    staging_status = 'validating',

    commercial_use_allowed = false,

    metadata =
      metadata
      || jsonb_build_object(
           'originality_verification_run_id',
           v_run_id,

           'originality_verification_required',
           true,

           'copyright_review_required',
           true,

           'commercial_clearance_required',
           true,

           'commercial_use_allowed',
           false
         )

  WHERE id = p_staging_question_id;


  RETURN v_run_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.start_originality_verification(
  uuid,
  numeric,
  numeric,
  numeric,
  numeric
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.start_originality_verification(
  uuid,
  numeric,
  numeric,
  numeric,
  numeric
)
TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.start_originality_verification(
  p_staging_question_id uuid,
  p_minimum_originality_score numeric DEFAULT 0.90,
  p_maximum_similarity_score numeric DEFAULT 0.80,
  p_critical_similarity_score numeric DEFAULT 0.92,
  p_minimum_confidence numeric DEFAULT 0.90
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.start_originality_verification(
    p_staging_question_id,
    p_minimum_originality_score,
    p_maximum_similarity_score,
    p_critical_similarity_score,
    p_minimum_confidence
  );
$$;


REVOKE ALL
ON FUNCTION public.start_originality_verification(
  uuid,
  numeric,
  numeric,
  numeric,
  numeric
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.start_originality_verification(
  uuid,
  numeric,
  numeric,
  numeric,
  numeric
)
TO authenticated, service_role;


-- =========================================================
-- 4. REVIEWER SONUCU
-- =========================================================

CREATE OR REPLACE FUNCTION private.submit_originality_review(
  p_verification_run_id uuid,
  p_reviewer_number integer,

  p_originality_score numeric,

  p_exact_similarity_score numeric,
  p_text_similarity_score numeric,
  p_semantic_similarity_score numeric,
  p_structural_similarity_score numeric,
  p_concept_similarity_score numeric,
  p_solution_path_similarity_score numeric,

  p_highest_similarity_type text,

  p_matched_question_id uuid DEFAULT NULL,
  p_matched_staging_id uuid DEFAULT NULL,
  p_matched_source_id uuid DEFAULT NULL,

  p_superficial_rewrite_detected boolean DEFAULT false,
  p_template_copy_detected boolean DEFAULT false,
  p_solution_path_copy_risk boolean DEFAULT false,

  p_copyright_risk_level text DEFAULT 'unknown',

  p_confidence_score numeric DEFAULT 0,

  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,

  p_review_summary text DEFAULT NULL,

  p_evidence jsonb DEFAULT '{}'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run public.ai_originality_verification_runs%ROWTYPE;

  v_r1 public.ai_originality_reviews%ROWTYPE;
  v_r2 public.ai_originality_reviews%ROWTYPE;

  v_highest numeric;
  v_consensus_originality numeric;
  v_consensus_highest numeric;

  v_highest_type text;

  v_status text;
  v_risk text;
  v_human_review boolean;

  v_match_question uuid;
  v_match_staging uuid;

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


  IF p_originality_score < 0
     OR p_originality_score > 1
     OR p_confidence_score < 0
     OR p_confidence_score > 1
  THEN
    RAISE EXCEPTION
      'Originality and confidence scores must be between 0 and 1.';
  END IF;


  IF p_highest_similarity_type IS NOT NULL
     AND p_highest_similarity_type NOT IN (
       'exact',
       'text',
       'semantic',
       'structure',
       'concept',
       'solution_path'
     )
  THEN
    RAISE EXCEPTION
      'Invalid similarity type.';
  END IF;


  IF p_copyright_risk_level NOT IN (
    'unknown',
    'low',
    'medium',
    'high',
    'blocked'
  ) THEN
    RAISE EXCEPTION
      'Invalid copyright risk level.';
  END IF;


  IF p_matched_question_id IS NOT NULL
     AND p_matched_staging_id IS NOT NULL
  THEN
    RAISE EXCEPTION
      'Match may reference either question or staging question, not both.';
  END IF;


  SELECT *
  INTO v_run
  FROM public.ai_originality_verification_runs r
  WHERE r.id = p_verification_run_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Originality verification run not found.';
  END IF;


  IF v_run.status IN (
    'verified',
    'rejected'
  ) THEN
    RAISE EXCEPTION
      'Originality verification is already finalized.';
  END IF;


  IF p_reviewer_number = 2
     AND NOT EXISTS (
       SELECT 1
       FROM public.ai_originality_reviews r
       WHERE r.verification_run_id =
             p_verification_run_id
         AND r.reviewer_number = 1
     )
  THEN
    RAISE EXCEPTION
      'Reviewer 1 must complete first.';
  END IF;


  -- Reviewer'ın bildirdiği skorları kullanarak en yüksek
  -- benzerliği veritabanında da tekrar hesaplıyoruz.

  v_highest :=
    GREATEST(
      COALESCE(p_exact_similarity_score, 0),
      COALESCE(p_text_similarity_score, 0),
      COALESCE(p_semantic_similarity_score, 0),
      COALESCE(p_structural_similarity_score, 0),
      COALESCE(p_concept_similarity_score, 0),
      COALESCE(p_solution_path_similarity_score, 0)
    );


  -- Tip yoksa en yüksek skora göre belirle.

  IF p_highest_similarity_type IS NULL THEN

    v_highest_type :=
      CASE v_highest
        WHEN COALESCE(p_exact_similarity_score, 0)
          THEN 'exact'

        WHEN COALESCE(p_text_similarity_score, 0)
          THEN 'text'

        WHEN COALESCE(p_semantic_similarity_score, 0)
          THEN 'semantic'

        WHEN COALESCE(p_structural_similarity_score, 0)
          THEN 'structure'

        WHEN COALESCE(p_concept_similarity_score, 0)
          THEN 'concept'

        ELSE 'solution_path'
      END;

  ELSE

    v_highest_type :=
      p_highest_similarity_type;

  END IF;


  INSERT INTO public.ai_originality_reviews (
    verification_run_id,
    reviewer_number,

    originality_score,

    exact_similarity_score,
    text_similarity_score,
    semantic_similarity_score,
    structural_similarity_score,
    concept_similarity_score,
    solution_path_similarity_score,

    highest_similarity_score,
    highest_similarity_type,

    matched_question_id,
    matched_staging_id,
    matched_source_id,

    superficial_rewrite_detected,
    template_copy_detected,
    solution_path_copy_risk,

    copyright_risk_level,

    confidence_score,

    provider_name,
    model_name,
    prompt_version,

    review_summary,

    evidence,
    metadata
  )
  VALUES (
    p_verification_run_id,
    p_reviewer_number,

    p_originality_score,

    p_exact_similarity_score,
    p_text_similarity_score,
    p_semantic_similarity_score,
    p_structural_similarity_score,
    p_concept_similarity_score,
    p_solution_path_similarity_score,

    v_highest,
    v_highest_type,

    p_matched_question_id,
    p_matched_staging_id,
    p_matched_source_id,

    COALESCE(
      p_superficial_rewrite_detected,
      false
    ),

    COALESCE(
      p_template_copy_detected,
      false
    ),

    COALESCE(
      p_solution_path_copy_risk,
      false
    ),

    p_copyright_risk_level,

    p_confidence_score,

    NULLIF(btrim(p_provider_name), ''),
    NULLIF(btrim(p_model_name), ''),
    NULLIF(btrim(p_prompt_version), ''),

    NULLIF(btrim(p_review_summary), ''),

    COALESCE(
      p_evidence,
      '{}'::jsonb
    ),

    COALESCE(
      p_metadata,
      '{}'::jsonb
    )
  );


  -- =======================================================
  -- EXISTING SIMILARITY MATCH TABLOSUNA KAYDET
  -- =======================================================

  IF (
    p_matched_question_id IS NOT NULL
    OR p_matched_staging_id IS NOT NULL
  )
  AND v_highest > 0
  THEN

    INSERT INTO public.question_similarity_matches (
      candidate_staging_id,

      matched_question_id,
      matched_staging_id,

      similarity_type,
      similarity_score,

      copyright_risk,

      review_status,

      details
    )
    VALUES (
      v_run.staging_question_id,

      p_matched_question_id,
      p_matched_staging_id,

      v_highest_type,
      v_highest,

      (
        p_copyright_risk_level IN (
          'high',
          'blocked'
        )
        OR
        COALESCE(
          p_superficial_rewrite_detected,
          false
        )
        OR
        COALESCE(
          p_template_copy_detected,
          false
        )
        OR
        COALESCE(
          p_solution_path_copy_risk,
          false
        )
      ),

      CASE
        WHEN v_highest >=
             v_run.critical_similarity_score
          THEN 'copyright_risk'

        WHEN v_highest >
             v_run.maximum_similarity_score
          THEN 'needs_review'

        ELSE 'acceptable'
      END,

      jsonb_build_object(
        'verification_run_id',
        v_run.id,

        'reviewer_number',
        p_reviewer_number,

        'superficial_rewrite_detected',
        COALESCE(
          p_superficial_rewrite_detected,
          false
        ),

        'template_copy_detected',
        COALESCE(
          p_template_copy_detected,
          false
        ),

        'solution_path_copy_risk',
        COALESCE(
          p_solution_path_copy_risk,
          false
        ),

        'copyright_risk_level',
        p_copyright_risk_level
      )
    );

  END IF;


  -- Reviewer 1 tamamlandı.

  IF p_reviewer_number = 1 THEN

    UPDATE public.ai_originality_verification_runs
    SET
      status = 'waiting_reviewer_2'

    WHERE id = p_verification_run_id;


    RETURN jsonb_build_object(
      'verification_run_id',
      p_verification_run_id,

      'reviewer',
      1,

      'originality_score',
      p_originality_score,

      'highest_similarity_score',
      v_highest,

      'status',
      'stored',

      'next',
      'waiting_reviewer_2'
    );

  END IF;


  -- =======================================================
  -- İKİ REVIEWER
  -- =======================================================

  SELECT *
  INTO v_r1
  FROM public.ai_originality_reviews r
  WHERE r.verification_run_id =
        p_verification_run_id
    AND r.reviewer_number = 1;


  SELECT *
  INTO v_r2
  FROM public.ai_originality_reviews r
  WHERE r.verification_run_id =
        p_verification_run_id
    AND r.reviewer_number = 2;


  v_consensus_originality :=
    ROUND(
      (
        v_r1.originality_score
        + v_r2.originality_score
      ) / 2,
      4
    );


  v_consensus_highest :=
    GREATEST(
      v_r1.highest_similarity_score,
      v_r2.highest_similarity_score
    );


  IF v_r1.highest_similarity_score >=
     v_r2.highest_similarity_score
  THEN

    v_highest_type :=
      v_r1.highest_similarity_type;

    v_match_question :=
      v_r1.matched_question_id;

    v_match_staging :=
      v_r1.matched_staging_id;

  ELSE

    v_highest_type :=
      v_r2.highest_similarity_type;

    v_match_question :=
      v_r2.matched_question_id;

    v_match_staging :=
      v_r2.matched_staging_id;

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

    v_status :=
      'low_confidence';

    v_risk :=
      'unknown';

    v_human_review :=
      true;


  ELSIF v_r1.copyright_risk_level = 'blocked'
        OR
        v_r2.copyright_risk_level = 'blocked'
  THEN

    v_status :=
      'blocked';

    v_risk :=
      'blocked';

    v_human_review :=
      true;


  ELSIF v_consensus_highest >=
        v_run.critical_similarity_score
  THEN

    v_status :=
      'possible_duplicate';

    v_risk :=
      'high';

    v_human_review :=
      true;


  ELSIF v_r1.superficial_rewrite_detected
        OR v_r2.superficial_rewrite_detected
        OR v_r1.template_copy_detected
        OR v_r2.template_copy_detected
        OR v_r1.solution_path_copy_risk
        OR v_r2.solution_path_copy_risk
  THEN

    v_status :=
      'copyright_risk';

    v_risk :=
      'high';

    v_human_review :=
      true;


  ELSIF v_consensus_highest >
        v_run.maximum_similarity_score
  THEN

    v_status :=
      'high_similarity';

    v_risk :=
      'medium';

    v_human_review :=
      true;


  ELSIF v_consensus_originality <
        v_run.minimum_originality_score
  THEN

    v_status :=
      'low_originality';

    v_risk :=
      'medium';

    v_human_review :=
      true;


  ELSIF ABS(
          v_r1.originality_score
          - v_r2.originality_score
        ) > 0.15
  THEN

    v_status :=
      'reviewer_disagreement';

    v_risk :=
      'unknown';

    v_human_review :=
      true;


  ELSIF v_r1.copyright_risk_level IN (
          'medium',
          'high'
        )
        OR
        v_r2.copyright_risk_level IN (
          'medium',
          'high'
        )
  THEN

    v_status :=
      'copyright_risk';

    v_risk :=
      CASE
        WHEN v_r1.copyright_risk_level = 'high'
          OR v_r2.copyright_risk_level = 'high'
        THEN 'high'
        ELSE 'medium'
      END;

    v_human_review :=
      true;


  ELSE

    v_status :=
      'verified';

    -- Özgünlük kontrolü geçti.
    -- Ancak kaynak hakkı/lisans kontrolü tamamlanmadığı
    -- için bunu hukuki "copyright safe" anlamında
    -- kullanmıyoruz.

    v_risk :=
      'unknown';

    v_human_review :=
      false;

  END IF;


  UPDATE public.ai_originality_verification_runs
  SET
    status =
      v_status,

    consensus_originality_score =
      v_consensus_originality,

    highest_detected_similarity_score =
      v_consensus_highest,

    highest_similarity_type =
      v_highest_type,

    copyright_risk_level =
      v_risk,

    human_review_required =
      v_human_review,

    metadata =
      metadata
      || jsonb_build_object(
           'reviewer_1_originality',
           v_r1.originality_score,

           'reviewer_2_originality',
           v_r2.originality_score,

           'reviewer_1_highest_similarity',
           v_r1.highest_similarity_score,

           'reviewer_2_highest_similarity',
           v_r2.highest_similarity_score,

           'matched_question_id',
           v_match_question,

           'matched_staging_id',
           v_match_staging,

           'legal_determination',
           false,

           'commercial_use_allowed',
           false,

           'automatic_publication_allowed',
           false
         )

  WHERE id = p_verification_run_id;


  -- =======================================================
  -- COPYRIGHT REVIEW AUDIT KAYDI
  -- =======================================================

  INSERT INTO public.copyright_reviews (
    staging_question_id,
    source_id,

    review_type,

    risk_level,

    originality_score,

    commercial_use_recommendation,

    evidence,

    reviewer_type,

    notes
  )
  VALUES (
    v_run.staging_question_id,

    COALESCE(
      v_r1.matched_source_id,
      v_r2.matched_source_id
    ),

    'originality',

    v_risk,

    v_consensus_originality,

    CASE
      WHEN v_status = 'verified'
      THEN 'human_review_required'

      WHEN v_status IN (
        'blocked',
        'possible_duplicate',
        'copyright_risk'
      )
      THEN 'do_not_allow'

      ELSE 'human_review_required'
    END,

    jsonb_build_object(
      'verification_run_id',
      v_run.id,

      'highest_similarity_score',
      v_consensus_highest,

      'highest_similarity_type',
      v_highest_type,

      'reviewer_1',
      jsonb_build_object(
        'originality',
        v_r1.originality_score,

        'copyright_risk',
        v_r1.copyright_risk_level,

        'superficial_rewrite',
        v_r1.superficial_rewrite_detected,

        'template_copy',
        v_r1.template_copy_detected,

        'solution_path_copy_risk',
        v_r1.solution_path_copy_risk
      ),

      'reviewer_2',
      jsonb_build_object(
        'originality',
        v_r2.originality_score,

        'copyright_risk',
        v_r2.copyright_risk_level,

        'superficial_rewrite',
        v_r2.superficial_rewrite_detected,

        'template_copy',
        v_r2.template_copy_detected,

        'solution_path_copy_risk',
        v_r2.solution_path_copy_risk
      ),

      'legal_determination',
      false,

      'thresholds_are_technical_only',
      true
    ),

    'ai',

    'Independent originality/similarity risk review.'
  );


  -- =======================================================
  -- AI VALIDATION RESULTS
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
    'originality',

    CASE
      WHEN v_status = 'verified'
        THEN 'pass'

      WHEN v_status IN (
        'blocked',
        'possible_duplicate',
        'copyright_risk'
      )
        THEN 'fail'

      ELSE 'warning'
    END,

    v_consensus_originality,

    'Independent originality verification completed.',

    jsonb_build_object(
      'verification_run_id',
      v_run.id,

      'status',
      v_status,

      'minimum_required',
      v_run.minimum_originality_score,

      'legal_determination',
      false
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
    'similarity',

    CASE
      WHEN v_status = 'verified'
        THEN 'pass'

      WHEN v_status IN (
        'blocked',
        'possible_duplicate',
        'copyright_risk'
      )
        THEN 'fail'

      ELSE 'warning'
    END,

    -- Similarity düşük olması iyi olduğu için burada
    -- kalite skoru olarak 1 - similarity kullanıyoruz.
    GREATEST(
      0,
      1 - v_consensus_highest
    ),

    'Multi-dimensional similarity verification completed.',

    jsonb_build_object(
      'verification_run_id',
      v_run.id,

      'highest_similarity_score',
      v_consensus_highest,

      'highest_similarity_type',
      v_highest_type,

      'technical_review_threshold',
      v_run.maximum_similarity_score,

      'critical_review_threshold',
      v_run.critical_similarity_score,

      'legal_determination',
      false
    )
  );


  -- =======================================================
  -- STAGING
  -- =======================================================

  UPDATE public.ai_question_staging
  SET
    originality_score =
      v_consensus_originality,

    copyright_risk_level =
      CASE
        WHEN v_risk IN (
          'medium',
          'high',
          'blocked'
        )
        THEN v_risk

        -- VERIFIED olması telif hukukunun geçtiği
        -- anlamına gelmediği için unknown kalabilir.
        ELSE copyright_risk_level
      END,

    commercial_use_allowed =
      false,

    staging_status =
      CASE
        WHEN v_status = 'verified'
        THEN 'validating'

        ELSE 'needs_review'
      END,

    metadata =
      metadata
      || jsonb_build_object(
           'originality_verification_status',
           v_status,

           'consensus_originality_score',
           v_consensus_originality,

           'highest_similarity_score',
           v_consensus_highest,

           'highest_similarity_type',
           v_highest_type,

           'copyright_risk_level_from_originality_gate',
           v_risk,

           'human_originality_review_required',
           v_human_review,

           'commercial_use_allowed',
           false,

           'commercial_clearance_required',
           true,

           'legal_determination',
           false,

           'automatic_publication_allowed',
           false
         )

  WHERE id = v_run.staging_question_id;


  RETURN jsonb_build_object(
    'verification_run_id',
    v_run.id,

    'status',
    v_status,

    'originality_score',
    v_consensus_originality,

    'highest_similarity_score',
    v_consensus_highest,

    'highest_similarity_type',
    v_highest_type,

    'copyright_risk_level',
    v_risk,

    'human_review_required',
    v_human_review,

    'commercial_use_allowed',
    false,

    'legal_determination',
    false,

    'production_publication',
    false
  );

END;
$$;


-- =========================================================
-- 5. PRIVATE FUNCTION PERMISSIONS
-- =========================================================

REVOKE ALL
ON FUNCTION private.submit_originality_review(
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

  uuid,
  uuid,
  uuid,

  boolean,
  boolean,
  boolean,

  text,

  numeric,

  text,
  text,
  text,

  text,

  jsonb,
  jsonb
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.submit_originality_review(
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

  uuid,
  uuid,
  uuid,

  boolean,
  boolean,
  boolean,

  text,

  numeric,

  text,
  text,
  text,

  text,

  jsonb,
  jsonb
)
TO authenticated, service_role;


-- =========================================================
-- 6. PUBLIC REVIEW RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.submit_originality_review(
  p_verification_run_id uuid,
  p_reviewer_number integer,

  p_originality_score numeric,

  p_exact_similarity_score numeric,
  p_text_similarity_score numeric,
  p_semantic_similarity_score numeric,
  p_structural_similarity_score numeric,
  p_concept_similarity_score numeric,
  p_solution_path_similarity_score numeric,

  p_highest_similarity_type text,

  p_matched_question_id uuid DEFAULT NULL,
  p_matched_staging_id uuid DEFAULT NULL,
  p_matched_source_id uuid DEFAULT NULL,

  p_superficial_rewrite_detected boolean DEFAULT false,
  p_template_copy_detected boolean DEFAULT false,
  p_solution_path_copy_risk boolean DEFAULT false,

  p_copyright_risk_level text DEFAULT 'unknown',

  p_confidence_score numeric DEFAULT 0,

  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,

  p_review_summary text DEFAULT NULL,

  p_evidence jsonb DEFAULT '{}'::jsonb,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.submit_originality_review(
    p_verification_run_id,
    p_reviewer_number,

    p_originality_score,

    p_exact_similarity_score,
    p_text_similarity_score,
    p_semantic_similarity_score,
    p_structural_similarity_score,
    p_concept_similarity_score,
    p_solution_path_similarity_score,

    p_highest_similarity_type,

    p_matched_question_id,
    p_matched_staging_id,
    p_matched_source_id,

    p_superficial_rewrite_detected,
    p_template_copy_detected,
    p_solution_path_copy_risk,

    p_copyright_risk_level,

    p_confidence_score,

    p_provider_name,
    p_model_name,
    p_prompt_version,

    p_review_summary,

    p_evidence,
    p_metadata
  );
$$;


REVOKE ALL
ON FUNCTION public.submit_originality_review(
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

  uuid,
  uuid,
  uuid,

  boolean,
  boolean,
  boolean,

  text,

  numeric,

  text,
  text,
  text,

  text,

  jsonb,
  jsonb
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.submit_originality_review(
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

  uuid,
  uuid,
  uuid,

  boolean,
  boolean,
  boolean,

  text,

  numeric,

  text,
  text,
  text,

  text,

  jsonb,
  jsonb
)
TO authenticated, service_role;


-- =========================================================
-- 7. HUMAN REVIEW
-- =========================================================

CREATE OR REPLACE FUNCTION private.review_originality_verification(
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
  v_run public.ai_originality_verification_runs%ROWTYPE;
BEGIN

  v_user_id :=
    auth.uid();


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
  )
  THEN
    RAISE EXCEPTION
      'Question approval permission required.';
  END IF;


  IF p_decision NOT IN (
    'approve_originality',
    'keep_for_noncommercial_review',
    'reject_question'
  )
  THEN
    RAISE EXCEPTION
      'Invalid originality review decision.';
  END IF;


  SELECT *
  INTO v_run
  FROM public.ai_originality_verification_runs r
  WHERE r.id = p_verification_run_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Originality verification run not found.';
  END IF;


  UPDATE public.ai_originality_verification_runs
  SET
    human_review_required =
      false,

    human_decision =
      p_decision,

    human_reviewed_by =
      v_user_id,

    human_reviewed_at =
      clock_timestamp(),

    status =
      CASE
        WHEN p_decision IN (
          'approve_originality',
          'keep_for_noncommercial_review'
        )
        THEN 'verified'

        ELSE 'rejected'
      END,

    metadata =
      metadata
      || jsonb_build_object(
           'human_originality_review',
           true,

           'human_decision',
           p_decision,

           'commercial_use_allowed',
           false,

           'legal_determination',
           false
         )

  WHERE id = p_verification_run_id;


  IF p_decision = 'reject_question' THEN

    UPDATE public.ai_question_staging
    SET
      staging_status =
        'rejected',

      commercial_use_allowed =
        false,

      metadata =
        metadata
        || jsonb_build_object(
             'originality_human_decision',
             'reject_question',

             'commercial_use_allowed',
             false
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
      'originality',

      'fail',

      v_user_id,

      'Question rejected during originality review.',

      jsonb_build_object(
        'verification_run_id',
        v_run.id,

        'commercial_use_allowed',
        false
      )
    );


  ELSE

    UPDATE public.ai_question_staging
    SET
      staging_status =
        'validating',

      -- İnsan originality review'da kabul etse bile
      -- ticari izin burada VERİLMEZ.
      commercial_use_allowed =
        false,

      metadata =
        metadata
        || jsonb_build_object(
             'originality_human_decision',
             p_decision,

             'originality_human_verified',
             true,

             'commercial_use_allowed',
             false,

             'commercial_clearance_required',
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
      'originality',

      'pass',

      v_user_id,

      'Human reviewer accepted originality risk review.',

      jsonb_build_object(
        'verification_run_id',
        v_run.id,

        'decision',
        p_decision,

        'commercial_use_allowed',
        false,

        'legal_determination',
        false
      )
    );

  END IF;


  RETURN jsonb_build_object(
    'verification_run_id',
    v_run.id,

    'decision',
    p_decision,

    'commercial_use_allowed',
    false,

    'commercial_clearance_required',
    true,

    'legal_determination',
    false,

    'production_publication',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.review_originality_verification(
  uuid,
  text
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.review_originality_verification(
  uuid,
  text
)
TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.review_originality_verification(
  p_verification_run_id uuid,
  p_decision text
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.review_originality_verification(
    p_verification_run_id,
    p_decision
  );
$$;


REVOKE ALL
ON FUNCTION public.review_originality_verification(
  uuid,
  text
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.review_originality_verification(
  uuid,
  text
)
TO authenticated, service_role;


-- =========================================================
-- 8. REPORT RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_originality_verification_report(
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
  )
  THEN
    RAISE EXCEPTION
      'Admin permission required.';
  END IF;


  SELECT jsonb_build_object(

    'verification_run_id',
    r.id,

    'staging_question_id',
    r.staging_question_id,

    'status',
    r.status,

    'technical_thresholds',
    jsonb_build_object(
      'minimum_originality_score',
      r.minimum_originality_score,

      'maximum_similarity_score',
      r.maximum_similarity_score,

      'critical_similarity_score',
      r.critical_similarity_score,

      'minimum_confidence',
      r.minimum_confidence,

      'legal_thresholds',
      false
    ),

    'consensus_originality_score',
    r.consensus_originality_score,

    'highest_detected_similarity_score',
    r.highest_detected_similarity_score,

    'highest_similarity_type',
    r.highest_similarity_type,

    'copyright_risk_level',
    r.copyright_risk_level,

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
            rr.reviewer_number,

            'originality_score',
            rr.originality_score,

            'exact_similarity',
            rr.exact_similarity_score,

            'text_similarity',
            rr.text_similarity_score,

            'semantic_similarity',
            rr.semantic_similarity_score,

            'structural_similarity',
            rr.structural_similarity_score,

            'concept_similarity',
            rr.concept_similarity_score,

            'solution_path_similarity',
            rr.solution_path_similarity_score,

            'highest_similarity_score',
            rr.highest_similarity_score,

            'highest_similarity_type',
            rr.highest_similarity_type,

            'superficial_rewrite_detected',
            rr.superficial_rewrite_detected,

            'template_copy_detected',
            rr.template_copy_detected,

            'solution_path_copy_risk',
            rr.solution_path_copy_risk,

            'copyright_risk_level',
            rr.copyright_risk_level,

            'confidence_score',
            rr.confidence_score,

            'provider',
            rr.provider_name,

            'model',
            rr.model_name
          )
          ORDER BY rr.reviewer_number
        ),
        '[]'::jsonb
      )

      FROM public.ai_originality_reviews rr

      WHERE rr.verification_run_id =
            r.id
    ),

    'commercial_use_allowed',
    false,

    'commercial_clearance_required',
    true,

    'legal_determination',
    false,

    'automatic_publication_allowed',
    false

  )
  INTO v_result

  FROM public.ai_originality_verification_runs r

  WHERE r.staging_question_id =
        p_staging_question_id;


  IF v_result IS NULL THEN

    RETURN jsonb_build_object(
      'status',
      'originality_verification_not_started',

      'staging_question_id',
      p_staging_question_id
    );

  END IF;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_originality_verification_report(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_originality_verification_report(uuid)
TO authenticated, service_role;


-- =========================================================
-- 9. ADMIN RLS
-- =========================================================

DROP POLICY IF EXISTS
"admins manage originality verification runs"
ON public.ai_originality_verification_runs;


CREATE POLICY
"admins manage originality verification runs"
ON public.ai_originality_verification_runs
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
"admins manage originality reviews"
ON public.ai_originality_reviews;


CREATE POLICY
"admins manage originality reviews"
ON public.ai_originality_reviews
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
-- 10. SECURITY INVOKER OVERVIEW
-- =========================================================

CREATE OR REPLACE VIEW public.ai_originality_verification_overview
WITH (security_invoker = true)
AS

SELECT
  r.id AS verification_run_id,

  r.staging_question_id,
  r.ai_job_id,

  r.status,

  r.consensus_originality_score,

  r.highest_detected_similarity_score,
  r.highest_similarity_type,

  r.copyright_risk_level,

  r.human_review_required,
  r.human_decision,

  false::boolean AS commercial_use_allowed,

  r.created_at,
  r.updated_at

FROM public.ai_originality_verification_runs r;


REVOKE ALL
ON public.ai_originality_verification_overview
FROM PUBLIC;


REVOKE ALL
ON public.ai_originality_verification_overview
FROM anon;


GRANT SELECT
ON public.ai_originality_verification_overview
TO authenticated;


-- =========================================================
-- 11. PRIVATE DEFAULT SECURITY
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