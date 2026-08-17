-- 033_independent_answer_verification.sql
-- Altın Kalemler
--
-- AI tarafından üretilen sorular için bağımsız cevap
-- doğrulama kapısı.
--
-- Amaç:
-- - Üretici AI'nin verdiği cevaba tek başına güvenmemek.
-- - En az iki bağımsız çözücü sonucunu saklamak.
-- - Önerilen cevap ile bağımsız çözücüleri karşılaştırmak.
-- - Uyuşmazlıkta otomatik onay vermemek.
-- - Sonucu ai_validation_results tablosuna kaydetmek.
--
-- Bu migration production'a otomatik soru yayınlamaz.
-- Gerçek AI API çağrısı yapmaz.

BEGIN;


-- =========================================================
-- 1. BAĞIMSIZ CEVAP DOĞRULAMA ÇALIŞMALARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_answer_verification_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  staging_question_id uuid NOT NULL
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  ai_job_id uuid
    REFERENCES public.ai_jobs(id)
    ON DELETE SET NULL,

  -- -------------------------------------------------------
  -- Staging'deki üretici AI cevabının snapshot'ı
  -- -------------------------------------------------------

  proposed_answer text NOT NULL
    CHECK (
      proposed_answer IN (
        'A',
        'B',
        'C',
        'D',
        'E'
      )
    ),

  -- -------------------------------------------------------
  -- Birinci bağımsız çözücü
  -- -------------------------------------------------------

  solver_1_answer text
    CHECK (
      solver_1_answer IS NULL
      OR solver_1_answer IN (
        'A',
        'B',
        'C',
        'D',
        'E'
      )
    ),

  solver_1_confidence numeric(5,4)
    CHECK (
      solver_1_confidence IS NULL
      OR (
        solver_1_confidence >= 0
        AND solver_1_confidence <= 1
      )
    ),

  solver_1_provider text,
  solver_1_model text,
  solver_1_prompt_version text,

  solver_1_reasoning_summary text,

  solver_1_result jsonb NOT NULL DEFAULT '{}'::jsonb,

  solver_1_completed_at timestamptz,

  -- -------------------------------------------------------
  -- İkinci bağımsız çözücü
  -- -------------------------------------------------------

  solver_2_answer text
    CHECK (
      solver_2_answer IS NULL
      OR solver_2_answer IN (
        'A',
        'B',
        'C',
        'D',
        'E'
      )
    ),

  solver_2_confidence numeric(5,4)
    CHECK (
      solver_2_confidence IS NULL
      OR (
        solver_2_confidence >= 0
        AND solver_2_confidence <= 1
      )
    ),

  solver_2_provider text,
  solver_2_model text,
  solver_2_prompt_version text,

  solver_2_reasoning_summary text,

  solver_2_result jsonb NOT NULL DEFAULT '{}'::jsonb,

  solver_2_completed_at timestamptz,

  -- -------------------------------------------------------
  -- Konsensüs
  -- -------------------------------------------------------

  consensus_answer text
    CHECK (
      consensus_answer IS NULL
      OR consensus_answer IN (
        'A',
        'B',
        'C',
        'D',
        'E'
      )
    ),

  consensus_status text NOT NULL DEFAULT 'pending'
    CHECK (
      consensus_status IN (
        'pending',
        'waiting_solver_1',
        'waiting_solver_2',
        'verified',
        'answer_mismatch',
        'solver_disagreement',
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

  -- -------------------------------------------------------
  -- İnsan incelemesi
  -- -------------------------------------------------------

  human_review_required boolean NOT NULL DEFAULT false,

  human_final_answer text
    CHECK (
      human_final_answer IS NULL
      OR human_final_answer IN (
        'A',
        'B',
        'C',
        'D',
        'E'
      )
    ),

  human_decision text
    CHECK (
      human_decision IS NULL
      OR human_decision IN (
        'approve',
        'correct_answer_changed',
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
    OR human_reviewed_by IS NOT NULL
  ),

  CHECK (
    human_decision IS NULL
    OR human_reviewed_at IS NOT NULL
  )
);


CREATE INDEX IF NOT EXISTS
idx_ai_answer_verification_status
ON public.ai_answer_verification_runs(
  consensus_status,
  created_at DESC
);


CREATE INDEX IF NOT EXISTS
idx_ai_answer_verification_question
ON public.ai_answer_verification_runs(
  staging_question_id
);


ALTER TABLE public.ai_answer_verification_runs
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS
trigger_ai_answer_verification_updated_at
ON public.ai_answer_verification_runs;


CREATE TRIGGER
trigger_ai_answer_verification_updated_at
BEFORE UPDATE
ON public.ai_answer_verification_runs
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. VERIFICATION RUN BAŞLAT
--
-- AI çağrısı yapmaz.
-- Sadece staging sorusunu doğrulama kuyruğuna hazırlar.
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


  IF v_question.staging_source <> 'ai_generated' THEN

    RAISE EXCEPTION
      'Independent answer verification is intended for AI generated staging questions.';

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


CREATE OR REPLACE FUNCTION public.start_answer_verification(
  p_staging_question_id uuid,
  p_minimum_confidence numeric DEFAULT 0.90
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.start_answer_verification(
    p_staging_question_id,
    p_minimum_confidence
  );
$$;


REVOKE ALL
ON FUNCTION public.start_answer_verification(uuid, numeric)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.start_answer_verification(uuid, numeric)
TO authenticated, service_role;


-- =========================================================
-- 3. BAĞIMSIZ ÇÖZÜCÜ SONUCU GÖNDER
--
-- p_solver_number yalnız 1 veya 2.
--
-- İki çözücü birbirinin sonucunu bilmeden çalışmalıdır.
-- Bu fonksiyon sadece sonuç kaydeder.
-- =========================================================

CREATE OR REPLACE FUNCTION private.submit_answer_solver_result(
  p_verification_run_id uuid,
  p_solver_number integer,
  p_answer text,
  p_confidence numeric,
  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,
  p_reasoning_summary text DEFAULT NULL,
  p_result jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run public.ai_answer_verification_runs%ROWTYPE;

  v_answer text;

  v_status text;

  v_consensus_answer text;

  v_human_review boolean := false;

  v_validation_result text;
BEGIN

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT private.current_user_has_admin_permission(
       'ai.manage'
     )
  THEN

    RAISE EXCEPTION
      'AI worker or AI management permission required.';

  END IF;


  IF p_solver_number NOT IN (1, 2) THEN

    RAISE EXCEPTION
      'Solver number must be 1 or 2.';

  END IF;


  v_answer :=
    upper(
      btrim(
        COALESCE(
          p_answer,
          ''
        )
      )
    );


  IF v_answer NOT IN (
    'A',
    'B',
    'C',
    'D',
    'E'
  ) THEN

    RAISE EXCEPTION
      'Solver answer must be A, B, C, D or E.';

  END IF;


  IF p_confidence IS NULL
     OR p_confidence < 0
     OR p_confidence > 1 THEN

    RAISE EXCEPTION
      'Solver confidence must be between 0 and 1.';

  END IF;


  SELECT *
  INTO v_run

  FROM public.ai_answer_verification_runs r

  WHERE r.id = p_verification_run_id

  FOR UPDATE;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Answer verification run not found.';

  END IF;


  IF v_run.consensus_status IN (
    'verified',
    'rejected'
  ) THEN

    RAISE EXCEPTION
      'Answer verification run is already finalized.';

  END IF;


  -- =======================================================
  -- SOLVER 1
  -- =======================================================

  IF p_solver_number = 1 THEN

    IF v_run.solver_1_completed_at IS NOT NULL THEN

      RAISE EXCEPTION
        'Solver 1 result already exists.';

    END IF;


    UPDATE public.ai_answer_verification_runs
    SET
      solver_1_answer =
        v_answer,

      solver_1_confidence =
        p_confidence,

      solver_1_provider =
        NULLIF(
          btrim(p_provider_name),
          ''
        ),

      solver_1_model =
        NULLIF(
          btrim(p_model_name),
          ''
        ),

      solver_1_prompt_version =
        NULLIF(
          btrim(p_prompt_version),
          ''
        ),

      solver_1_reasoning_summary =
        NULLIF(
          btrim(p_reasoning_summary),
          ''
        ),

      solver_1_result =
        COALESCE(
          p_result,
          '{}'::jsonb
        ),

      solver_1_completed_at =
        clock_timestamp(),

      consensus_status =
        'waiting_solver_2'

    WHERE id =
      p_verification_run_id;


    RETURN jsonb_build_object(
      'verification_run_id',
      p_verification_run_id,

      'solver',
      1,

      'result',
      'stored',

      'next',
      'waiting_solver_2'
    );

  END IF;


  -- =======================================================
  -- SOLVER 2
  -- =======================================================

  IF v_run.solver_1_completed_at IS NULL THEN

    RAISE EXCEPTION
      'Solver 1 must finish before solver 2 result can be finalized.';

  END IF;


  IF v_run.solver_2_completed_at IS NOT NULL THEN

    RAISE EXCEPTION
      'Solver 2 result already exists.';

  END IF;


  UPDATE public.ai_answer_verification_runs
  SET
    solver_2_answer =
      v_answer,

    solver_2_confidence =
      p_confidence,

    solver_2_provider =
      NULLIF(
        btrim(p_provider_name),
        ''
      ),

    solver_2_model =
      NULLIF(
        btrim(p_model_name),
        ''
      ),

    solver_2_prompt_version =
      NULLIF(
        btrim(p_prompt_version),
        ''
      ),

    solver_2_reasoning_summary =
      NULLIF(
        btrim(p_reasoning_summary),
        ''
      ),

    solver_2_result =
      COALESCE(
        p_result,
        '{}'::jsonb
      ),

    solver_2_completed_at =
      clock_timestamp()

  WHERE id =
    p_verification_run_id;


  -- Güncel satırı tekrar al.

  SELECT *
  INTO v_run

  FROM public.ai_answer_verification_runs r

  WHERE r.id =
    p_verification_run_id

  FOR UPDATE;


  -- =======================================================
  -- KONSENSÜS MOTORU
  -- =======================================================

  IF v_run.solver_1_confidence
       < v_run.minimum_confidence
     OR
     v_run.solver_2_confidence
       < v_run.minimum_confidence
  THEN

    v_status :=
      'low_confidence';

    v_human_review :=
      true;

    v_validation_result :=
      'warning';


  ELSIF v_run.solver_1_answer
        <> v_run.solver_2_answer
  THEN

    v_status :=
      'solver_disagreement';

    v_human_review :=
      true;

    v_validation_result :=
      'fail';


  ELSIF v_run.solver_1_answer
        <> v_run.proposed_answer
  THEN

    -- İki bağımsız AI aynı cevabı bulmuş,
    -- fakat üretici AI farklı cevap vermiş.

    v_status :=
      'answer_mismatch';

    v_consensus_answer :=
      v_run.solver_1_answer;

    v_human_review :=
      true;

    v_validation_result :=
      'fail';


  ELSE

    -- Üçü de aynı:
    -- producer + solver1 + solver2

    v_status :=
      'verified';

    v_consensus_answer :=
      v_run.proposed_answer;

    v_human_review :=
      false;

    v_validation_result :=
      'pass';

  END IF;


  UPDATE public.ai_answer_verification_runs
  SET
    consensus_answer =
      v_consensus_answer,

    consensus_status =
      v_status,

    human_review_required =
      v_human_review

  WHERE id =
    p_verification_run_id;


  -- =======================================================
  -- AI VALIDATION RESULT
  --
  -- Bu kayıt akademik cevap doğrulama kapısının sonucudur.
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

    'answer',

    v_validation_result,

    LEAST(
      v_run.solver_1_confidence,
      v_run.solver_2_confidence
    ),

    CASE v_status

      WHEN 'verified'
        THEN
          'Two independent solvers agreed with the proposed answer.'

      WHEN 'solver_disagreement'
        THEN
          'Independent solvers returned different answers.'

      WHEN 'answer_mismatch'
        THEN
          'Independent solvers agreed with each other but not with the proposed answer.'

      WHEN 'low_confidence'
        THEN
          'At least one independent solver did not reach the required confidence.'

      ELSE
        'Independent answer verification requires review.'

    END,

    jsonb_build_object(
      'verification_run_id',
      v_run.id,

      'proposed_answer',
      v_run.proposed_answer,

      'solver_1_answer',
      v_run.solver_1_answer,

      'solver_1_confidence',
      v_run.solver_1_confidence,

      'solver_2_answer',
      v_run.solver_2_answer,

      'solver_2_confidence',
      v_run.solver_2_confidence,

      'consensus_answer',
      v_consensus_answer,

      'consensus_status',
      v_status,

      'human_review_required',
      v_human_review,

      'automatic_publication_allowed',
      false
    )
  );


  -- =======================================================
  -- STAGING DURUMU
  --
  -- Answer verification PASS olsa bile APPROVED yapılmaz.
  -- Diğer kalite kapıları hâlâ çalışmalıdır.
  -- =======================================================

  UPDATE public.ai_question_staging
  SET
    staging_status =
      CASE
        WHEN v_status = 'verified'
          THEN 'validating'
        ELSE 'needs_review'
      END,

    answer_confidence =
      CASE
        WHEN v_status = 'verified'
        THEN
          LEAST(
            v_run.solver_1_confidence,
            v_run.solver_2_confidence
          )
        ELSE answer_confidence
      END,

    metadata =
      metadata
      || jsonb_build_object(
           'answer_verification_status',
           v_status,

           'answer_consensus',
           v_consensus_answer,

           'human_answer_review_required',
           v_human_review
         )

  WHERE id =
    v_run.staging_question_id;


  RETURN jsonb_build_object(
    'verification_run_id',
    v_run.id,

    'proposed_answer',
    v_run.proposed_answer,

    'solver_1_answer',
    v_run.solver_1_answer,

    'solver_2_answer',
    v_run.solver_2_answer,

    'consensus_answer',
    v_consensus_answer,

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
ON FUNCTION private.submit_answer_solver_result(
  uuid,
  integer,
  text,
  numeric,
  text,
  text,
  text,
  text,
  jsonb
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.submit_answer_solver_result(
  uuid,
  integer,
  text,
  numeric,
  text,
  text,
  text,
  text,
  jsonb
)
TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.submit_answer_solver_result(
  p_verification_run_id uuid,
  p_solver_number integer,
  p_answer text,
  p_confidence numeric,
  p_provider_name text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_prompt_version text DEFAULT NULL,
  p_reasoning_summary text DEFAULT NULL,
  p_result jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.submit_answer_solver_result(
    p_verification_run_id,
    p_solver_number,
    p_answer,
    p_confidence,
    p_provider_name,
    p_model_name,
    p_prompt_version,
    p_reasoning_summary,
    p_result
  );
$$;


REVOKE ALL
ON FUNCTION public.submit_answer_solver_result(
  uuid,
  integer,
  text,
  numeric,
  text,
  text,
  text,
  text,
  jsonb
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.submit_answer_solver_result(
  uuid,
  integer,
  text,
  numeric,
  text,
  text,
  text,
  text,
  jsonb
)
TO authenticated, service_role;


-- =========================================================
-- 4. İNSAN CEVAP İNCELEMESİ
--
-- Sadece uyuşmazlık / düşük güven gibi durumlarda.
-- =========================================================

CREATE OR REPLACE FUNCTION private.review_answer_verification(
  p_verification_run_id uuid,
  p_decision text,
  p_final_answer text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;

  v_run public.ai_answer_verification_runs%ROWTYPE;

  v_final_answer text;
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
  ) THEN

    RAISE EXCEPTION
      'Question approval permission required.';

  END IF;


  IF p_decision NOT IN (
    'approve',
    'correct_answer_changed',
    'reject_question'
  ) THEN

    RAISE EXCEPTION
      'Invalid human answer review decision.';

  END IF;


  SELECT *
  INTO v_run

  FROM public.ai_answer_verification_runs r

  WHERE r.id =
    p_verification_run_id

  FOR UPDATE;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Answer verification run not found.';

  END IF;


  v_final_answer :=
    upper(
      btrim(
        COALESCE(
          p_final_answer,
          ''
        )
      )
    );


  IF p_decision IN (
    'approve',
    'correct_answer_changed'
  )
  THEN

    IF v_final_answer = '' THEN

      v_final_answer :=
        COALESCE(
          v_run.consensus_answer,
          v_run.proposed_answer
        );

    END IF;


    IF v_final_answer NOT IN (
      'A',
      'B',
      'C',
      'D',
      'E'
    ) THEN

      RAISE EXCEPTION
        'Final answer must be A, B, C, D or E.';

    END IF;

  ELSE

    v_final_answer := NULL;

  END IF;


  UPDATE public.ai_answer_verification_runs
  SET
    human_review_required =
      false,

    human_final_answer =
      v_final_answer,

    human_decision =
      p_decision,

    human_reviewed_by =
      v_user_id,

    human_reviewed_at =
      clock_timestamp(),

    consensus_answer =
      CASE
        WHEN p_decision IN (
          'approve',
          'correct_answer_changed'
        )
        THEN v_final_answer
        ELSE consensus_answer
      END,

    consensus_status =
      CASE
        WHEN p_decision IN (
          'approve',
          'correct_answer_changed'
        )
          THEN 'verified'

        ELSE 'rejected'
      END

  WHERE id =
    p_verification_run_id;


  IF p_decision = 'reject_question' THEN

    UPDATE public.ai_question_staging
    SET
      staging_status =
        'rejected',

      metadata =
        metadata
        || jsonb_build_object(
             'answer_review_decision',
             'reject_question'
           )

    WHERE id =
      v_run.staging_question_id;


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
      'answer',
      'fail',
      v_user_id,
      'Question rejected during human answer verification.',
      jsonb_build_object(
        'verification_run_id',
        v_run.id
      )
    );

  ELSE

    UPDATE public.ai_question_staging
    SET
      proposed_correct_answer =
        v_final_answer,

      staging_status =
        'validating',

      metadata =
        metadata
        || jsonb_build_object(
             'answer_review_decision',
             p_decision,

             'human_verified_answer',
             v_final_answer
           )

    WHERE id =
      v_run.staging_question_id;


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
      'answer',
      'pass',
      v_user_id,
      'Human reviewer finalized the question answer.',
      jsonb_build_object(
        'verification_run_id',
        v_run.id,

        'final_answer',
        v_final_answer,

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

    'final_answer',
    v_final_answer,

    'production_publication',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.review_answer_verification(
  uuid,
  text,
  text
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.review_answer_verification(
  uuid,
  text,
  text
)
TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.review_answer_verification(
  p_verification_run_id uuid,
  p_decision text,
  p_final_answer text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.review_answer_verification(
    p_verification_run_id,
    p_decision,
    p_final_answer
  );
$$;


REVOKE ALL
ON FUNCTION public.review_answer_verification(
  uuid,
  text,
  text
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.review_answer_verification(
  uuid,
  text,
  text
)
TO authenticated, service_role;


-- =========================================================
-- 5. CEVAP DOĞRULAMA RAPORU
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_answer_verification_report(
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

    'staging_question_id',
    r.staging_question_id,

    'proposed_answer',
    r.proposed_answer,

    'solver_1',
    jsonb_build_object(
      'answer',
      r.solver_1_answer,

      'confidence',
      r.solver_1_confidence,

      'provider',
      r.solver_1_provider,

      'model',
      r.solver_1_model,

      'completed_at',
      r.solver_1_completed_at
    ),

    'solver_2',
    jsonb_build_object(
      'answer',
      r.solver_2_answer,

      'confidence',
      r.solver_2_confidence,

      'provider',
      r.solver_2_provider,

      'model',
      r.solver_2_model,

      'completed_at',
      r.solver_2_completed_at
    ),

    'consensus_answer',
    r.consensus_answer,

    'consensus_status',
    r.consensus_status,

    'minimum_confidence',
    r.minimum_confidence,

    'human_review_required',
    r.human_review_required,

    'human_final_answer',
    r.human_final_answer,

    'human_decision',
    r.human_decision,

    'human_reviewed_at',
    r.human_reviewed_at,

    'automatic_publication_allowed',
    false
  )

  INTO v_result

  FROM public.ai_answer_verification_runs r

  WHERE r.staging_question_id =
    p_staging_question_id;


  IF v_result IS NULL THEN

    RETURN jsonb_build_object(
      'status',
      'answer_verification_not_started',

      'staging_question_id',
      p_staging_question_id
    );

  END IF;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_answer_verification_report(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_answer_verification_report(uuid)
TO authenticated, service_role;


-- =========================================================
-- 6. ADMIN RLS
-- =========================================================

DROP POLICY IF EXISTS
"admins manage answer verification runs"
ON public.ai_answer_verification_runs;


CREATE POLICY
"admins manage answer verification runs"
ON public.ai_answer_verification_runs
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
-- 7. ADMIN VIEW
-- =========================================================

CREATE OR REPLACE VIEW public.ai_answer_verification_overview
WITH (security_invoker = true)
AS

SELECT
  r.id AS verification_run_id,

  r.staging_question_id,

  r.ai_job_id,

  r.proposed_answer,

  r.solver_1_answer,
  r.solver_1_confidence,

  r.solver_2_answer,
  r.solver_2_confidence,

  r.consensus_answer,
  r.consensus_status,

  r.minimum_confidence,

  r.human_review_required,

  r.human_final_answer,
  r.human_decision,

  r.created_at,
  r.updated_at

FROM public.ai_answer_verification_runs r;


REVOKE ALL
ON public.ai_answer_verification_overview
FROM PUBLIC;


REVOKE ALL
ON public.ai_answer_verification_overview
FROM anon;


GRANT SELECT
ON public.ai_answer_verification_overview
TO authenticated;


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