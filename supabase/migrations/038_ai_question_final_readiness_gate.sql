-- 038_ai_question_final_readiness_gate.sql
-- Altın Kalemler
--
-- AI soru üretim zincirindeki ana kalite kapılarını
-- tek bir nihai "readiness" kararında birleştirir.
--
-- Kontrol edilen ana aşamalar:
--
-- 033 bağımsız cevap doğrulama
-- 034 müfredat / sınıf / konu / ön koşul
-- 035 soru bazlı çözüm süresi
-- 036 özgünlük / benzerlik / telif riski
-- 037 genel soru kalitesi
--
-- ÖNEMLİ:
-- READY sonucu production yayını değildir.
-- READY sonucu yalnızca:
--
-- "Bu aday soru artık insanın nihai onay ekranına
-- gönderilebilir."
--
-- anlamına gelir.
--
-- AI doğrudan questions tablosuna yayın yapmaz.

BEGIN;


-- =========================================================
-- 1. FINAL READINESS RUN
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_question_readiness_runs (
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

  -- -------------------------------------------------------
  -- Ana kalite kapıları
  -- -------------------------------------------------------

  answer_verification_passed boolean NOT NULL DEFAULT false,

  curriculum_fit_passed boolean NOT NULL DEFAULT false,

  solve_time_verification_passed boolean NOT NULL DEFAULT false,

  originality_verification_passed boolean NOT NULL DEFAULT false,

  question_quality_passed boolean NOT NULL DEFAULT false,

  -- -------------------------------------------------------
  -- Kaydedilen durum snapshot'ları
  -- -------------------------------------------------------

  answer_status text,

  curriculum_status text,

  solve_time_status text,

  originality_status text,

  quality_status text,

  -- -------------------------------------------------------
  -- Ticari kullanım ayrı tutulur.
  --
  -- Soru kalite açısından hazır olabilir fakat ticari
  -- kullanım için ayrıca hak/lisans/telif clearance gerekir.
  -- -------------------------------------------------------

  commercial_clearance_status text,

  commercial_ready boolean NOT NULL DEFAULT false,

  -- -------------------------------------------------------
  -- Nihai readiness
  -- -------------------------------------------------------

  readiness_status text NOT NULL DEFAULT 'not_ready'
    CHECK (
      readiness_status IN (
        'not_ready',
        'ready_for_human_review',
        'human_review_required',
        'blocked',
        'rejected',
        'already_promoted'
      )
    ),

  blocking_reasons jsonb NOT NULL DEFAULT '[]'::jsonb,

  warnings jsonb NOT NULL DEFAULT '[]'::jsonb,

  readiness_score numeric(5,4)
    CHECK (
      readiness_score IS NULL
      OR readiness_score BETWEEN 0 AND 1
    ),

  evaluated_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  evaluated_at timestamptz NOT NULL DEFAULT now(),

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (staging_question_id)
);


CREATE INDEX IF NOT EXISTS
idx_ai_question_readiness_status
ON public.ai_question_readiness_runs(
  readiness_status,
  evaluated_at DESC
);


CREATE INDEX IF NOT EXISTS
idx_ai_question_readiness_staging
ON public.ai_question_readiness_runs(
  staging_question_id
);


ALTER TABLE public.ai_question_readiness_runs
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS
trigger_ai_question_readiness_runs_updated_at
ON public.ai_question_readiness_runs;


CREATE TRIGGER
trigger_ai_question_readiness_runs_updated_at
BEFORE UPDATE
ON public.ai_question_readiness_runs
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. FINAL READINESS DEĞERLENDİRME
-- =========================================================

CREATE OR REPLACE FUNCTION private.evaluate_ai_question_readiness(
  p_staging_question_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;

  v_question public.ai_question_staging%ROWTYPE;

  v_answer_status text;
  v_curriculum_status text;
  v_solve_time_status text;
  v_originality_status text;
  v_quality_status text;

  v_answer_pass boolean := false;
  v_curriculum_pass boolean := false;
  v_solve_time_pass boolean := false;
  v_originality_pass boolean := false;
  v_quality_pass boolean := false;

  v_commercial_clearance_status text;
  v_commercial_ready boolean := false;

  v_blockers jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;

  v_readiness_status text;
  v_readiness_score numeric(5,4);

  v_pass_count integer := 0;

  v_run_id uuid;
BEGIN

  v_user_id := auth.uid();


  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission(
         'ai.manage'
       )
       OR
       private.current_user_has_admin_permission(
         'questions.approve'
       )
       OR
       private.current_user_has_admin_permission(
         'questions.edit'
       )
     )
  THEN
    RAISE EXCEPTION
      'AI management or question permission required.';
  END IF;


  -- =======================================================
  -- STAGING QUESTION
  -- =======================================================

  SELECT *
  INTO v_question
  FROM public.ai_question_staging s
  WHERE s.id = p_staging_question_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Staging question not found.';
  END IF;


  -- =======================================================
  -- REJECTED / PROMOTED KISA YOL
  -- =======================================================

  IF v_question.staging_status = 'rejected' THEN

    v_readiness_status := 'rejected';

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'staging_rejected',

             'message',
             'Staging question is rejected.'
           )
         );


  ELSIF v_question.staging_status = 'promoted' THEN

    v_readiness_status := 'already_promoted';

    v_warnings :=
      v_warnings
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'already_promoted',

             'message',
             'Question has already been promoted.'
           )
         );

  END IF;


  -- =======================================================
  -- 033 ANSWER VERIFICATION
  -- =======================================================

  SELECT r.consensus_status
  INTO v_answer_status
  FROM public.ai_answer_verification_runs r
  WHERE r.staging_question_id =
        p_staging_question_id
  ORDER BY r.updated_at DESC NULLS LAST,
           r.created_at DESC
  LIMIT 1;


  IF v_answer_status = 'verified' THEN

    v_answer_pass := true;

  ELSE

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'answer_verification_not_passed',

             'status',
             COALESCE(
               v_answer_status,
               'not_started'
             ),

             'message',
             'Independent answer verification has not passed.'
           )
         );

  END IF;


  -- =======================================================
  -- 034 CURRICULUM FIT
  -- =======================================================

  SELECT r.status
  INTO v_curriculum_status
  FROM public.ai_curriculum_fit_runs r
  WHERE r.staging_question_id =
        p_staging_question_id
  ORDER BY r.updated_at DESC,
           r.created_at DESC
  LIMIT 1;


  IF v_curriculum_status = 'verified' THEN

    v_curriculum_pass := true;

  ELSE

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'curriculum_fit_not_passed',

             'status',
             COALESCE(
               v_curriculum_status,
               'not_started'
             ),

             'message',
             'Curriculum fit verification has not passed.'
           )
         );

  END IF;


  -- =======================================================
  -- 035 SOLVE TIME
  -- =======================================================

  SELECT r.status
  INTO v_solve_time_status
  FROM public.ai_solve_time_verification_runs r
  WHERE r.staging_question_id =
        p_staging_question_id
  ORDER BY r.updated_at DESC,
           r.created_at DESC
  LIMIT 1;


  IF v_solve_time_status = 'verified' THEN

    v_solve_time_pass := true;

  ELSE

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'solve_time_verification_not_passed',

             'status',
             COALESCE(
               v_solve_time_status,
               'not_started'
             ),

             'message',
             'Question-specific solve-time verification has not passed.'
           )
         );

  END IF;


  -- =======================================================
  -- 036 ORIGINALITY / SIMILARITY
  -- =======================================================

  SELECT r.status
  INTO v_originality_status
  FROM public.ai_originality_verification_runs r
  WHERE r.staging_question_id =
        p_staging_question_id
  ORDER BY r.updated_at DESC,
           r.created_at DESC
  LIMIT 1;


  IF v_originality_status = 'verified' THEN

    v_originality_pass := true;

  ELSE

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'originality_verification_not_passed',

             'status',
             COALESCE(
               v_originality_status,
               'not_started'
             ),

             'message',
             'Originality and similarity verification has not passed.'
           )
         );

  END IF;


  -- =======================================================
  -- 037 QUESTION QUALITY
  -- =======================================================

  SELECT r.status
  INTO v_quality_status
  FROM public.ai_question_quality_runs r
  WHERE r.staging_question_id =
        p_staging_question_id
  ORDER BY r.updated_at DESC,
           r.created_at DESC
  LIMIT 1;


  IF v_quality_status = 'verified' THEN

    v_quality_pass := true;

  ELSE

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'question_quality_not_passed',

             'status',
             COALESCE(
               v_quality_status,
               'not_started'
             ),

             'message',
             'Independent question quality review has not passed.'
           )
         );

  END IF;


  -- =======================================================
  -- PASS COUNT / READINESS SCORE
  -- =======================================================

  v_pass_count :=
      CASE WHEN v_answer_pass THEN 1 ELSE 0 END
    + CASE WHEN v_curriculum_pass THEN 1 ELSE 0 END
    + CASE WHEN v_solve_time_pass THEN 1 ELSE 0 END
    + CASE WHEN v_originality_pass THEN 1 ELSE 0 END
    + CASE WHEN v_quality_pass THEN 1 ELSE 0 END;


  v_readiness_score :=
    ROUND(
      v_pass_count::numeric / 5,
      4
    );


  -- =======================================================
  -- COMMERCIAL CLEARANCE
  --
  -- Bunun READINESS ile aynı şey olmadığını özellikle
  -- ayırıyoruz.
  -- =======================================================

  SELECT c.clearance_status
  INTO v_commercial_clearance_status
  FROM public.commercial_question_clearance c
  WHERE c.staging_question_id =
        p_staging_question_id
  ORDER BY c.updated_at DESC,
           c.created_at DESC
  LIMIT 1;


  IF v_commercial_clearance_status = 'approved'
     AND v_question.commercial_use_allowed = true
  THEN

    v_commercial_ready := true;

  ELSE

    v_commercial_ready := false;

    v_warnings :=
      v_warnings
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'not_commercially_cleared',

             'clearance_status',
             COALESCE(
               v_commercial_clearance_status,
               'not_started'
             ),

             'message',
             'Question is not commercially cleared yet.'
           )
         );

  END IF;


  -- =======================================================
  -- FINAL STATUS
  -- =======================================================

  IF v_question.staging_status = 'rejected' THEN

    v_readiness_status :=
      'rejected';


  ELSIF v_question.staging_status = 'promoted' THEN

    v_readiness_status :=
      'already_promoted';


  ELSIF v_originality_status IN (
    'blocked',
    'rejected'
  )
  OR v_quality_status = 'rejected'
  OR v_curriculum_status = 'rejected'
  OR v_solve_time_status = 'rejected'
  THEN

    v_readiness_status :=
      'blocked';


  ELSIF v_answer_pass
        AND v_curriculum_pass
        AND v_solve_time_pass
        AND v_originality_pass
        AND v_quality_pass
  THEN

    v_readiness_status :=
      'ready_for_human_review';


  ELSE

    v_readiness_status :=
      'human_review_required';

  END IF;


  -- =======================================================
  -- READINESS RUN UPSERT
  -- =======================================================

  INSERT INTO public.ai_question_readiness_runs (
    staging_question_id,
    ai_job_id,
    generation_spec_id,

    answer_verification_passed,
    curriculum_fit_passed,
    solve_time_verification_passed,
    originality_verification_passed,
    question_quality_passed,

    answer_status,
    curriculum_status,
    solve_time_status,
    originality_status,
    quality_status,

    commercial_clearance_status,
    commercial_ready,

    readiness_status,

    blocking_reasons,
    warnings,

    readiness_score,

    evaluated_by,
    evaluated_at,

    metadata
  )
  VALUES (
    v_question.id,
    v_question.ai_job_id,
    v_question.generation_spec_id,

    v_answer_pass,
    v_curriculum_pass,
    v_solve_time_pass,
    v_originality_pass,
    v_quality_pass,

    v_answer_status,
    v_curriculum_status,
    v_solve_time_status,
    v_originality_status,
    v_quality_status,

    v_commercial_clearance_status,
    v_commercial_ready,

    v_readiness_status,

    v_blockers,
    v_warnings,

    v_readiness_score,

    v_user_id,
    clock_timestamp(),

    jsonb_build_object(
      'automatic_publication_allowed',
      false,

      'human_final_approval_required',
      true,

      'commercial_clearance_separate',
      true
    )
  )

  ON CONFLICT (staging_question_id)
  DO UPDATE SET

    ai_job_id =
      EXCLUDED.ai_job_id,

    generation_spec_id =
      EXCLUDED.generation_spec_id,

    answer_verification_passed =
      EXCLUDED.answer_verification_passed,

    curriculum_fit_passed =
      EXCLUDED.curriculum_fit_passed,

    solve_time_verification_passed =
      EXCLUDED.solve_time_verification_passed,

    originality_verification_passed =
      EXCLUDED.originality_verification_passed,

    question_quality_passed =
      EXCLUDED.question_quality_passed,

    answer_status =
      EXCLUDED.answer_status,

    curriculum_status =
      EXCLUDED.curriculum_status,

    solve_time_status =
      EXCLUDED.solve_time_status,

    originality_status =
      EXCLUDED.originality_status,

    quality_status =
      EXCLUDED.quality_status,

    commercial_clearance_status =
      EXCLUDED.commercial_clearance_status,

    commercial_ready =
      EXCLUDED.commercial_ready,

    readiness_status =
      EXCLUDED.readiness_status,

    blocking_reasons =
      EXCLUDED.blocking_reasons,

    warnings =
      EXCLUDED.warnings,

    readiness_score =
      EXCLUDED.readiness_score,

    evaluated_by =
      EXCLUDED.evaluated_by,

    evaluated_at =
      EXCLUDED.evaluated_at,

    metadata =
      EXCLUDED.metadata

  RETURNING id
  INTO v_run_id;


  -- =======================================================
  -- STAGING METADATA
  -- =======================================================

  UPDATE public.ai_question_staging
  SET
    staging_status =
      CASE
        WHEN v_readiness_status =
             'ready_for_human_review'
          THEN 'needs_review'

        WHEN v_readiness_status IN (
          'blocked',
          'rejected'
        )
          THEN 'needs_review'

        ELSE staging_status
      END,

    metadata =
      metadata
      || jsonb_build_object(
           'final_readiness_run_id',
           v_run_id,

           'final_readiness_status',
           v_readiness_status,

           'final_readiness_score',
           v_readiness_score,

           'human_final_approval_required',
           true,

           'commercial_ready',
           v_commercial_ready,

           'automatic_publication_allowed',
           false
         )

  WHERE id =
        p_staging_question_id;


  -- =======================================================
  -- REVIEW QUEUE
  -- =======================================================

  IF v_readiness_status =
     'ready_for_human_review'
  THEN

    IF NOT EXISTS (
      SELECT 1
      FROM public.review_queue rq
      WHERE rq.entity_type =
            'staging_question'
        AND rq.entity_id =
            p_staging_question_id
        AND rq.reason_code =
            'final_ai_question_approval'
        AND rq.status IN (
          'open',
          'assigned'
        )
    )
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
        p_staging_question_id,

        'final_ai_question_approval',

        jsonb_build_object(
          'readiness_run_id',
          v_run_id,

          'readiness_score',
          v_readiness_score,

          'commercial_ready',
          v_commercial_ready,

          'human_final_approval_required',
          true
        ),

        'high',

        'open'
      );

    END IF;


  ELSIF v_readiness_status IN (
    'blocked',
    'human_review_required'
  )
  THEN

    IF NOT EXISTS (
      SELECT 1
      FROM public.review_queue rq
      WHERE rq.entity_type =
            'staging_question'
        AND rq.entity_id =
            p_staging_question_id
        AND rq.reason_code =
            'ai_readiness_blocker'
        AND rq.status IN (
          'open',
          'assigned'
        )
    )
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
        p_staging_question_id,

        'ai_readiness_blocker',

        jsonb_build_object(
          'readiness_run_id',
          v_run_id,

          'readiness_status',
          v_readiness_status,

          'blocking_reasons',
          v_blockers,

          'warnings',
          v_warnings
        ),

        CASE
          WHEN v_readiness_status = 'blocked'
            THEN 'critical'
          ELSE 'high'
        END,

        'open'
      );

    END IF;

  END IF;


  -- =======================================================
  -- OVERALL VALIDATION RESULT
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
    p_staging_question_id,
    v_question.ai_job_id,

    'deterministic',
    'overall',

    CASE
      WHEN v_readiness_status =
           'ready_for_human_review'
        THEN 'pass'

      WHEN v_readiness_status IN (
        'blocked',
        'rejected'
      )
        THEN 'fail'

      ELSE 'warning'
    END,

    v_readiness_score,

    'Final deterministic AI question readiness evaluation completed.',

    jsonb_build_object(
      'readiness_run_id',
      v_run_id,

      'readiness_status',
      v_readiness_status,

      'answer_status',
      v_answer_status,

      'curriculum_status',
      v_curriculum_status,

      'solve_time_status',
      v_solve_time_status,

      'originality_status',
      v_originality_status,

      'quality_status',
      v_quality_status,

      'commercial_ready',
      v_commercial_ready,

      'blocking_reasons',
      v_blockers,

      'warnings',
      v_warnings,

      'automatic_publication_allowed',
      false,

      'human_final_approval_required',
      true
    )
  );


  RETURN jsonb_build_object(
    'readiness_run_id',
    v_run_id,

    'staging_question_id',
    p_staging_question_id,

    'readiness_status',
    v_readiness_status,

    'readiness_score',
    v_readiness_score,

    'gates',
    jsonb_build_object(
      'answer_verification',
      jsonb_build_object(
        'passed',
        v_answer_pass,
        'status',
        COALESCE(
          v_answer_status,
          'not_started'
        )
      ),

      'curriculum_fit',
      jsonb_build_object(
        'passed',
        v_curriculum_pass,
        'status',
        COALESCE(
          v_curriculum_status,
          'not_started'
        )
      ),

      'solve_time',
      jsonb_build_object(
        'passed',
        v_solve_time_pass,
        'status',
        COALESCE(
          v_solve_time_status,
          'not_started'
        )
      ),

      'originality',
      jsonb_build_object(
        'passed',
        v_originality_pass,
        'status',
        COALESCE(
          v_originality_status,
          'not_started'
        )
      ),

      'quality',
      jsonb_build_object(
        'passed',
        v_quality_pass,
        'status',
        COALESCE(
          v_quality_status,
          'not_started'
        )
      )
    ),

    'blocking_reasons',
    v_blockers,

    'warnings',
    v_warnings,

    'commercial_ready',
    v_commercial_ready,

    'human_final_approval_required',
    true,

    'automatic_publication_allowed',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.evaluate_ai_question_readiness(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.evaluate_ai_question_readiness(uuid)
TO authenticated, service_role;


-- =========================================================
-- 3. PUBLIC RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.evaluate_ai_question_readiness(
  p_staging_question_id uuid
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.evaluate_ai_question_readiness(
    p_staging_question_id
  );
$$;


REVOKE ALL
ON FUNCTION public.evaluate_ai_question_readiness(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.evaluate_ai_question_readiness(uuid)
TO authenticated, service_role;


-- =========================================================
-- 4. READINESS REPORT
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_ai_question_readiness_report(
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
    'readiness_run_id',
    r.id,

    'staging_question_id',
    r.staging_question_id,

    'readiness_status',
    r.readiness_status,

    'readiness_score',
    r.readiness_score,

    'gates',
    jsonb_build_object(
      'answer',
      jsonb_build_object(
        'passed',
        r.answer_verification_passed,
        'status',
        r.answer_status
      ),

      'curriculum',
      jsonb_build_object(
        'passed',
        r.curriculum_fit_passed,
        'status',
        r.curriculum_status
      ),

      'solve_time',
      jsonb_build_object(
        'passed',
        r.solve_time_verification_passed,
        'status',
        r.solve_time_status
      ),

      'originality',
      jsonb_build_object(
        'passed',
        r.originality_verification_passed,
        'status',
        r.originality_status
      ),

      'quality',
      jsonb_build_object(
        'passed',
        r.question_quality_passed,
        'status',
        r.quality_status
      )
    ),

    'blocking_reasons',
    r.blocking_reasons,

    'warnings',
    r.warnings,

    'commercial_clearance_status',
    r.commercial_clearance_status,

    'commercial_ready',
    r.commercial_ready,

    'evaluated_at',
    r.evaluated_at,

    'human_final_approval_required',
    true,

    'automatic_publication_allowed',
    false
  )
  INTO v_result

  FROM public.ai_question_readiness_runs r

  WHERE r.staging_question_id =
        p_staging_question_id;


  IF v_result IS NULL THEN

    RETURN jsonb_build_object(
      'status',
      'readiness_not_evaluated',

      'staging_question_id',
      p_staging_question_id
    );

  END IF;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_ai_question_readiness_report(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_ai_question_readiness_report(uuid)
TO authenticated, service_role;


-- =========================================================
-- 5. RLS
-- =========================================================

DROP POLICY IF EXISTS
"admins manage ai question readiness"
ON public.ai_question_readiness_runs;


CREATE POLICY
"admins manage ai question readiness"
ON public.ai_question_readiness_runs
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
-- 6. OVERVIEW
-- =========================================================

CREATE OR REPLACE VIEW public.ai_question_readiness_overview
WITH (security_invoker = true)
AS

SELECT
  r.id AS readiness_run_id,

  r.staging_question_id,
  r.ai_job_id,

  r.answer_verification_passed,
  r.curriculum_fit_passed,
  r.solve_time_verification_passed,
  r.originality_verification_passed,
  r.question_quality_passed,

  r.readiness_score,
  r.readiness_status,

  r.commercial_ready,

  r.blocking_reasons,
  r.warnings,

  r.evaluated_at,
  r.updated_at

FROM public.ai_question_readiness_runs r;


REVOKE ALL
ON public.ai_question_readiness_overview
FROM PUBLIC, anon;


GRANT SELECT
ON public.ai_question_readiness_overview
TO authenticated;


-- =========================================================
-- 7. PRIVATE DEFAULT SECURITY
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