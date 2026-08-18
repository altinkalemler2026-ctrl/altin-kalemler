-- 039_human_final_question_promotion.sql
-- Altın Kalemler
--
-- Nihai insan onayı ve kontrollü staging -> questions aktarımı.
--
-- Güvenlik:
-- - AI bu fonksiyonu tek başına kullanamaz.
-- - Gerçek authenticated admin gerekir.
-- - 038 readiness = ready_for_human_review olmalıdır.
-- - Promotion sonrası soru is_active = false kalır.
-- - Öğrenciye otomatik yayın yapılmaz.
-- - Ticari kullanım otomatik açılmaz.

BEGIN;


-- =========================================================
-- 1. HUMAN FINAL REVIEW AUDIT
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_question_final_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  staging_question_id uuid NOT NULL
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  readiness_run_id uuid
    REFERENCES public.ai_question_readiness_runs(id)
    ON DELETE SET NULL,

  decision text NOT NULL
    CHECK (
      decision IN (
        'approve',
        'request_changes',
        'reject'
      )
    ),

  review_notes text,

  reviewed_by uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE RESTRICT,

  reviewed_at timestamptz NOT NULL DEFAULT now(),

  promoted_question_id uuid
    REFERENCES public.questions(id)
    ON DELETE SET NULL,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);


CREATE INDEX IF NOT EXISTS
idx_ai_question_final_reviews_staging
ON public.ai_question_final_reviews(
  staging_question_id,
  reviewed_at DESC
);


CREATE INDEX IF NOT EXISTS
idx_ai_question_final_reviews_reviewer
ON public.ai_question_final_reviews(
  reviewed_by,
  reviewed_at DESC
);


ALTER TABLE public.ai_question_final_reviews
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 2. HUMAN FINAL DECISION
-- =========================================================

CREATE OR REPLACE FUNCTION private.review_and_promote_ai_question(
  p_staging_question_id uuid,
  p_decision text,
  p_review_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;

  v_staging public.ai_question_staging%ROWTYPE;
  v_readiness public.ai_question_readiness_runs%ROWTYPE;

  v_question_id uuid;
  v_question_code text;

  v_review_id uuid;

  v_commercial_allowed boolean := false;
BEGIN

  -- =======================================================
  -- HUMAN AUTHENTICATION ONLY
  -- =======================================================

  v_user_id := auth.uid();


  IF v_user_id IS NULL THEN
    RAISE EXCEPTION
      'Human authentication required.';
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
    'approve',
    'request_changes',
    'reject'
  )
  THEN
    RAISE EXCEPTION
      'Invalid final review decision.';
  END IF;


  -- =======================================================
  -- STAGING QUESTION
  -- =======================================================

  SELECT *
  INTO v_staging
  FROM public.ai_question_staging s
  WHERE s.id = p_staging_question_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Staging question not found.';
  END IF;


  IF v_staging.staging_status = 'promoted' THEN

    RETURN jsonb_build_object(
      'status',
      'already_promoted',

      'staging_question_id',
      v_staging.id,

      'question_id',
      v_staging.final_question_id
    );

  END IF;


  IF v_staging.staging_status = 'rejected' THEN
    RAISE EXCEPTION
      'Rejected staging question cannot be promoted.';
  END IF;


  -- =======================================================
  -- READINESS'I YENİDEN HESAPLA
  --
  -- Eski/stale bir readiness sonucuna güvenmiyoruz.
  -- =======================================================

  PERFORM private.evaluate_ai_question_readiness(
    p_staging_question_id
  );


  SELECT *
  INTO v_readiness
  FROM public.ai_question_readiness_runs r
  WHERE r.staging_question_id =
        p_staging_question_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Final readiness evaluation not found.';
  END IF;


  -- =======================================================
  -- REQUEST CHANGES
  -- =======================================================

  IF p_decision = 'request_changes' THEN

    INSERT INTO public.ai_question_final_reviews (
      staging_question_id,
      readiness_run_id,
      decision,
      review_notes,
      reviewed_by,
      metadata
    )
    VALUES (
      v_staging.id,
      v_readiness.id,
      'request_changes',
      NULLIF(btrim(p_review_notes), ''),
      v_user_id,

      jsonb_build_object(
        'readiness_status',
        v_readiness.readiness_status,
        'readiness_score',
        v_readiness.readiness_score
      )
    )
    RETURNING id
    INTO v_review_id;


    UPDATE public.ai_question_staging
    SET
      staging_status = 'needs_review',

      metadata =
        metadata
        || jsonb_build_object(
             'human_final_review_status',
             'request_changes',

             'human_final_review_id',
             v_review_id,

             'automatic_publication_allowed',
             false
           )

    WHERE id = v_staging.id;


    RETURN jsonb_build_object(
      'status',
      'changes_requested',

      'final_review_id',
      v_review_id,

      'staging_question_id',
      v_staging.id,

      'production_publication',
      false
    );

  END IF;


  -- =======================================================
  -- REJECT
  -- =======================================================

  IF p_decision = 'reject' THEN

    INSERT INTO public.ai_question_final_reviews (
      staging_question_id,
      readiness_run_id,
      decision,
      review_notes,
      reviewed_by,
      metadata
    )
    VALUES (
      v_staging.id,
      v_readiness.id,
      'reject',
      NULLIF(btrim(p_review_notes), ''),
      v_user_id,

      jsonb_build_object(
        'readiness_status',
        v_readiness.readiness_status,
        'readiness_score',
        v_readiness.readiness_score
      )
    )
    RETURNING id
    INTO v_review_id;


    UPDATE public.ai_question_staging
    SET
      staging_status = 'rejected',

      commercial_use_allowed = false,

      metadata =
        metadata
        || jsonb_build_object(
             'human_final_review_status',
             'rejected',

             'human_final_review_id',
             v_review_id,

             'automatic_publication_allowed',
             false
           )

    WHERE id = v_staging.id;


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
      v_staging.id,
      v_staging.ai_job_id,

      'human',
      'overall',

      'fail',

      v_user_id,

      'Question rejected during final human review.',

      jsonb_build_object(
        'final_review_id',
        v_review_id,

        'readiness_run_id',
        v_readiness.id
      )
    );


    RETURN jsonb_build_object(
      'status',
      'rejected',

      'final_review_id',
      v_review_id,

      'staging_question_id',
      v_staging.id,

      'production_publication',
      false
    );

  END IF;


  -- =======================================================
  -- APPROVE İÇİN READINESS ZORUNLULUĞU
  -- =======================================================

  IF v_readiness.readiness_status <>
     'ready_for_human_review'
  THEN
    RAISE EXCEPTION
      'Question is not ready for final human approval. Current readiness status: %',
      v_readiness.readiness_status;
  END IF;


  IF v_readiness.readiness_score IS DISTINCT FROM 1.0000 THEN
    RAISE EXCEPTION
      'All mandatory AI quality gates must pass before promotion.';
  END IF;


  -- =======================================================
  -- SON DETERMINISTIC İÇERİK KONTROLLERİ
  -- =======================================================

  IF v_staging.grade_level IS NULL THEN
    RAISE EXCEPTION
      'Grade level is required.';
  END IF;


  IF v_staging.subject_id IS NULL THEN
    RAISE EXCEPTION
      'Subject is required.';
  END IF;


  IF NULLIF(
       btrim(v_staging.question_text),
       ''
     ) IS NULL
  THEN
    RAISE EXCEPTION
      'Question text is required.';
  END IF;


  IF v_staging.proposed_correct_answer
     NOT IN ('A', 'B', 'C', 'D', 'E')
  THEN
    RAISE EXCEPTION
      'A valid correct answer is required.';
  END IF;


  IF NULLIF(btrim(v_staging.option_a), '') IS NULL
     OR NULLIF(btrim(v_staging.option_b), '') IS NULL
     OR NULLIF(btrim(v_staging.option_c), '') IS NULL
     OR NULLIF(btrim(v_staging.option_d), '') IS NULL
  THEN
    RAISE EXCEPTION
      'At least options A, B, C and D are required.';
  END IF;


  -- =======================================================
  -- QUESTION CODE
  -- =======================================================

  IF NULLIF(
       btrim(v_staging.proposed_question_code),
       ''
     ) IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.questions q
       WHERE q.question_code =
             btrim(v_staging.proposed_question_code)
     )
  THEN

    v_question_code :=
      btrim(v_staging.proposed_question_code);

  ELSE

    -- UUID tabanlı deterministik ve benzersiz kod.
    v_question_code :=
      'AK-AI-'
      ||
      upper(
        replace(
          v_staging.id::text,
          '-',
          ''
        )
      );

  END IF;


  IF EXISTS (
    SELECT 1
    FROM public.questions q
    WHERE q.question_code =
          v_question_code
  )
  THEN
    RAISE EXCEPTION
      'Generated question code already exists.';
  END IF;


  -- =======================================================
  -- COMMERCIAL USE
  --
  -- Readiness ticari kullanım değildir.
  -- Yalnız clearance gerçekten approved ise aktarılır.
  -- =======================================================

  v_commercial_allowed :=
    (
      v_readiness.commercial_ready = true
      AND
      v_staging.commercial_use_allowed = true
    );


  -- =======================================================
  -- QUESTIONS TABLOSUNA PROMOTION
  --
  -- ÖNEMLİ:
  -- approval_status = approved
  -- is_active = false
  --
  -- Böylece soru bankasında bulunur fakat öğrenciye
  -- otomatik yayınlanmaz.
  -- =======================================================

  INSERT INTO public.questions (
    question_code,

    legacy_question_key,
    exam_track,

    grade_level,
    subject_id,

    legacy_taxonomy_id,

    question_text,

    option_a,
    option_b,
    option_c,
    option_d,
    option_e,

    correct_answer,

    difficulty,
    cognitive_type,
    quality_level,

    primary_question_type,
    secondary_question_type,

    is_new_generation,
    has_visual,

    estimated_solve_time_seconds,

    approval_status,
    is_active,

    ownership_status,
    license_status,

    commercial_use_allowed
  )
  VALUES (
    v_question_code,

    v_staging.legacy_question_key,
    v_staging.exam_track,

    v_staging.grade_level,
    v_staging.subject_id,

    v_staging.legacy_taxonomy_id,

    v_staging.question_text,

    v_staging.option_a,
    v_staging.option_b,
    v_staging.option_c,
    v_staging.option_d,
    v_staging.option_e,

    v_staging.proposed_correct_answer,

    v_staging.proposed_difficulty,
    v_staging.proposed_cognitive_type,
    v_staging.proposed_quality_level,

    v_staging.proposed_primary_question_type,
    v_staging.proposed_secondary_question_type,

    COALESCE(
      v_staging.proposed_is_new_generation,
      false
    ),

    COALESCE(
      v_staging.proposed_has_visual,
      false
    ),

    v_staging.proposed_solve_time_seconds,

    'approved',

    -- Kritik:
    -- İnsan approve etti diye öğrenciye hemen açma.
    false,

    CASE
      WHEN v_staging.staging_source = 'ai_generated'
           AND v_staging.ownership_status = 'unknown'
        THEN 'ai_original'

      ELSE v_staging.ownership_status
    END,

    v_staging.license_status,

    v_commercial_allowed
  )
  RETURNING id
  INTO v_question_id;


  -- =======================================================
  -- SOURCE LOCATION
  -- =======================================================

  IF v_staging.source_id IS NOT NULL THEN

    INSERT INTO public.question_source_locations (
      question_id,
      source_id,

      page_number,
      test_number,
      test_code,
      question_number,

      source_question_code,

      extraction_confidence
    )
    VALUES (
      v_question_id,
      v_staging.source_id,

      v_staging.source_page_number,
      v_staging.source_test_number,
      v_staging.source_test_code,
      v_staging.source_question_number,

      v_staging.proposed_question_code,

      v_staging.extraction_confidence
    )
    ON CONFLICT (
      question_id,
      source_id
    )
    DO NOTHING;

  END IF;


  -- =======================================================
  -- CURRICULUM MAPPING
  -- =======================================================

  IF v_staging.proposed_curriculum_version_id IS NOT NULL
     AND v_staging.proposed_topic_id IS NOT NULL
  THEN

    INSERT INTO public.question_curriculum_mappings (
      question_id,

      curriculum_version_id,

      topic_id,
      subtopic_id,

      mapping_source,

      confidence_score,

      review_status,

      reviewed_by,
      reviewed_at
    )
    VALUES (
      v_question_id,

      v_staging.proposed_curriculum_version_id,

      v_staging.proposed_topic_id,
      v_staging.proposed_subtopic_id,

      'ai',

      v_staging.classification_confidence,

      'approved',

      v_user_id,
      clock_timestamp()
    )
    ON CONFLICT DO NOTHING;

  END IF;


  -- =======================================================
  -- HUMAN REVIEW AUDIT
  -- =======================================================

  INSERT INTO public.ai_question_final_reviews (
    staging_question_id,
    readiness_run_id,

    decision,
    review_notes,

    reviewed_by,

    promoted_question_id,

    metadata
  )
  VALUES (
    v_staging.id,
    v_readiness.id,

    'approve',
    NULLIF(btrim(p_review_notes), ''),

    v_user_id,

    v_question_id,

    jsonb_build_object(
      'question_code',
      v_question_code,

      'is_active',
      false,

      'commercial_use_allowed',
      v_commercial_allowed,

      'readiness_score',
      v_readiness.readiness_score,

      'automatic_publication_allowed',
      false
    )
  )
  RETURNING id
  INTO v_review_id;


  -- =======================================================
  -- STAGING -> PROMOTED
  -- =======================================================

  UPDATE public.ai_question_staging
  SET
    staging_status = 'promoted',

    final_question_id =
      v_question_id,

    metadata =
      metadata
      || jsonb_build_object(
           'human_final_review_status',
           'approved',

           'human_final_review_id',
           v_review_id,

           'promoted_question_id',
           v_question_id,

           'promoted_question_code',
           v_question_code,

           'promoted_at',
           clock_timestamp(),

           'student_visible',
           false,

           'automatic_publication_allowed',
           false
         )

  WHERE id = v_staging.id;


  -- =======================================================
  -- REVIEW QUEUE KAPAT
  -- =======================================================

  UPDATE public.review_queue
  SET
    status = 'approved',

    decision_notes =
      COALESCE(
        NULLIF(btrim(p_review_notes), ''),
        'Final human approval completed.'
      ),

    resolved_at =
      clock_timestamp()

  WHERE entity_type =
        'staging_question'

    AND entity_id =
        v_staging.id

    AND reason_code =
        'final_ai_question_approval'

    AND status IN (
      'open',
      'assigned'
    );


  -- =======================================================
  -- HUMAN VALIDATION AUDIT
  -- =======================================================

  INSERT INTO public.ai_validation_results (
    staging_question_id,
    ai_job_id,

    validator_type,
    validation_type,

    result,
    score,

    reviewed_by,

    summary,
    details
  )
  VALUES (
    v_staging.id,
    v_staging.ai_job_id,

    'human',
    'overall',

    'pass',
    1.0000,

    v_user_id,

    'Final human approval completed and question promoted to the question bank.',

    jsonb_build_object(
      'final_review_id',
      v_review_id,

      'readiness_run_id',
      v_readiness.id,

      'question_id',
      v_question_id,

      'question_code',
      v_question_code,

      'question_is_active',
      false,

      'student_visible',
      false,

      'commercial_use_allowed',
      v_commercial_allowed,

      'automatic_publication_allowed',
      false
    )
  );


  -- =======================================================
  -- RESULT
  -- =======================================================

  RETURN jsonb_build_object(
    'status',
    'promoted',

    'final_review_id',
    v_review_id,

    'staging_question_id',
    v_staging.id,

    'question_id',
    v_question_id,

    'question_code',
    v_question_code,

    'approval_status',
    'approved',

    'is_active',
    false,

    'student_visible',
    false,

    'commercial_use_allowed',
    v_commercial_allowed,

    'automatic_publication_allowed',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.review_and_promote_ai_question(
  uuid,
  text,
  text
)
FROM PUBLIC, anon, service_role;


GRANT EXECUTE
ON FUNCTION private.review_and_promote_ai_question(
  uuid,
  text,
  text
)
TO authenticated;


-- =========================================================
-- 3. PUBLIC HUMAN RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.review_and_promote_ai_question(
  p_staging_question_id uuid,
  p_decision text,
  p_review_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.review_and_promote_ai_question(
    p_staging_question_id,
    p_decision,
    p_review_notes
  );
$$;


REVOKE ALL
ON FUNCTION public.review_and_promote_ai_question(
  uuid,
  text,
  text
)
FROM PUBLIC, anon, service_role;


GRANT EXECUTE
ON FUNCTION public.review_and_promote_ai_question(
  uuid,
  text,
  text
)
TO authenticated;


-- =========================================================
-- 4. FINAL REVIEW REPORT
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_ai_question_final_review_report(
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
    'staging_question_id',
    s.id,

    'staging_status',
    s.staging_status,

    'final_question_id',
    s.final_question_id,

    'readiness',
    (
      SELECT jsonb_build_object(
        'readiness_run_id',
        r.id,

        'status',
        r.readiness_status,

        'score',
        r.readiness_score,

        'commercial_ready',
        r.commercial_ready
      )
      FROM public.ai_question_readiness_runs r
      WHERE r.staging_question_id = s.id
      LIMIT 1
    ),

    'final_reviews',
    (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'review_id',
            fr.id,

            'decision',
            fr.decision,

            'notes',
            fr.review_notes,

            'reviewed_by',
            fr.reviewed_by,

            'reviewed_at',
            fr.reviewed_at,

            'promoted_question_id',
            fr.promoted_question_id
          )
          ORDER BY fr.reviewed_at DESC
        ),
        '[]'::jsonb
      )

      FROM public.ai_question_final_reviews fr

      WHERE fr.staging_question_id =
            s.id
    ),

    'automatic_publication_allowed',
    false
  )
  INTO v_result

  FROM public.ai_question_staging s

  WHERE s.id =
        p_staging_question_id;


  IF v_result IS NULL THEN
    RAISE EXCEPTION
      'Staging question not found.';
  END IF;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_ai_question_final_review_report(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_ai_question_final_review_report(uuid)
TO authenticated, service_role;


-- =========================================================
-- 5. RLS
-- =========================================================

DROP POLICY IF EXISTS
"admins read final question reviews"
ON public.ai_question_final_reviews;


CREATE POLICY
"admins read final question reviews"
ON public.ai_question_final_reviews
FOR SELECT
TO authenticated
USING (
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
);


-- Yazma normal tablo erişimiyle yapılmaz.
-- Sadece kontrollü RPC üzerinden yapılır.


-- =========================================================
-- 6. SECURITY INVOKER OVERVIEW
-- =========================================================

CREATE OR REPLACE VIEW public.ai_question_final_review_overview
WITH (security_invoker = true)
AS

SELECT
  fr.id AS final_review_id,

  fr.staging_question_id,

  fr.readiness_run_id,

  fr.decision,

  fr.reviewed_by,
  fr.reviewed_at,

  fr.promoted_question_id

FROM public.ai_question_final_reviews fr;


REVOKE ALL
ON public.ai_question_final_review_overview
FROM PUBLIC, anon;


GRANT SELECT
ON public.ai_question_final_review_overview
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