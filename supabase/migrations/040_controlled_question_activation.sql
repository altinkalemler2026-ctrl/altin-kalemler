-- 040_controlled_question_activation.sql
-- Altın Kalemler
--
-- Kontrollü soru aktivasyonu / öğrenciye yayın kapısı.
--
-- AMAÇ:
-- questions tablosuna aktarılmış bir soru,
-- ayrıca insan tarafından yayınlanmadan öğrenciye görünmez.
--
-- Güvenlik ilkeleri:
--
-- 1. AI kendi kendine aktivasyon yapamaz.
-- 2. Gerçek authenticated admin gerekir.
-- 3. Soru approval_status = approved olmalıdır.
-- 4. AI staging'den geldiyse nihai insan promotion kaydı olmalıdır.
-- 5. Görsel gerekiyorsa geçerli/aktif görsel olmalıdır.
-- 6. Müfredat bilgisi olan AI sorusunda approved mapping olmalıdır.
-- 7. Restricted lisanslı içerik aktifleştirilemez.
-- 8. commercial_use_allowed = true ise commercial clearance approved olmalıdır.
-- 9. Aktivasyon/deaktivasyon audit kaydı tutulur.
--
-- Bu migration AI API çağırmaz.

BEGIN;


-- =========================================================
-- 1. QUESTION PUBLICATION AUDIT
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_publication_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  question_id uuid NOT NULL
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  staging_question_id uuid
    REFERENCES public.ai_question_staging(id)
    ON DELETE SET NULL,

  action text NOT NULL
    CHECK (
      action IN (
        'activate',
        'deactivate'
      )
    ),

  previous_is_active boolean NOT NULL,

  new_is_active boolean NOT NULL,

  reason text,

  performed_by uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE RESTRICT,

  performed_at timestamptz NOT NULL DEFAULT now(),

  checks_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);


CREATE INDEX IF NOT EXISTS
idx_question_publication_events_question
ON public.question_publication_events(
  question_id,
  performed_at DESC
);


CREATE INDEX IF NOT EXISTS
idx_question_publication_events_user
ON public.question_publication_events(
  performed_by,
  performed_at DESC
);


ALTER TABLE public.question_publication_events
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 2. PUBLICATION CHECK FUNCTION
--
-- Sadece kontrol yapar.
-- Soruyu aktif etmez.
-- =========================================================

CREATE OR REPLACE FUNCTION private.check_question_activation_readiness(
  p_question_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_question public.questions%ROWTYPE;

  v_staging public.ai_question_staging%ROWTYPE;

  v_has_staging boolean := false;
  v_has_final_human_approval boolean := false;

  v_has_approved_curriculum_mapping boolean := false;

  v_has_required_visual_asset boolean := false;

  v_commercial_clearance_status text;

  v_blockers jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;

  v_can_activate boolean := true;
BEGIN

  -- =======================================================
  -- QUESTION
  -- =======================================================

  SELECT *
  INTO v_question
  FROM public.questions q
  WHERE q.id = p_question_id;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Question not found.';
  END IF;


  -- =======================================================
  -- BASIC QUESTION CHECKS
  -- =======================================================

  IF v_question.approval_status <> 'approved' THEN

    v_can_activate := false;

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'question_not_approved',

             'message',
             'Question approval status must be approved.'
           )
         );

  END IF;


  IF NULLIF(
       btrim(v_question.question_text),
       ''
     ) IS NULL
  THEN

    v_can_activate := false;

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'missing_question_text',

             'message',
             'Question text is missing.'
           )
         );

  END IF;


  IF NULLIF(
       btrim(v_question.option_a),
       ''
     ) IS NULL
     OR
     NULLIF(
       btrim(v_question.option_b),
       ''
     ) IS NULL
     OR
     NULLIF(
       btrim(v_question.option_c),
       ''
     ) IS NULL
     OR
     NULLIF(
       btrim(v_question.option_d),
       ''
     ) IS NULL
  THEN

    v_can_activate := false;

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'missing_required_options',

             'message',
             'Options A, B, C and D are required.'
           )
         );

  END IF;


  IF v_question.correct_answer
     NOT IN (
       'A',
       'B',
       'C',
       'D',
       'E'
     )
  THEN

    v_can_activate := false;

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'invalid_correct_answer',

             'message',
             'Valid correct answer is required.'
           )
         );

  END IF;


  IF v_question.grade_level IS NULL
     OR
     v_question.grade_level NOT BETWEEN 1 AND 12
  THEN

    v_can_activate := false;

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'invalid_grade',

             'message',
             'Valid grade level is required.'
           )
         );

  END IF;


  IF v_question.subject_id IS NULL THEN

    v_can_activate := false;

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'missing_subject',

             'message',
             'Subject is required.'
           )
         );

  END IF;


  -- =======================================================
  -- LICENSE
  -- =======================================================

  IF v_question.license_status = 'restricted' THEN

    v_can_activate := false;

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'restricted_license',

             'message',
             'Restricted-license question cannot be activated.'
           )
         );

  END IF;


  IF v_question.ownership_status = 'third_party'
     AND v_question.license_status <> 'approved'
  THEN

    v_can_activate := false;

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'third_party_license_not_approved',

             'message',
             'Third-party content requires approved license before activation.'
           )
         );

  END IF;


  IF v_question.ownership_status = 'unknown' THEN

    v_warnings :=
      v_warnings
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'ownership_unknown',

             'message',
             'Question ownership status is unknown.'
           )
         );

  END IF;


  -- =======================================================
  -- AI STAGING ORIGIN
  -- =======================================================

  SELECT *
  INTO v_staging
  FROM public.ai_question_staging s
  WHERE s.final_question_id =
        p_question_id
  ORDER BY s.updated_at DESC
  LIMIT 1;


  IF FOUND THEN

    v_has_staging := true;


    -- AI/staging sorusu promoted olmak zorunda.

    IF v_staging.staging_status <>
       'promoted'
    THEN

      v_can_activate := false;

      v_blockers :=
        v_blockers
        || jsonb_build_array(
             jsonb_build_object(
               'code',
               'staging_not_promoted',

               'message',
               'Staging question must be promoted before activation.'
             )
           );

    END IF;


    -- 039 final human approval kaydı.

    SELECT EXISTS (
      SELECT 1
      FROM public.ai_question_final_reviews fr
      WHERE fr.staging_question_id =
            v_staging.id

        AND fr.promoted_question_id =
            p_question_id

        AND fr.decision =
            'approve'
    )
    INTO v_has_final_human_approval;


    IF NOT v_has_final_human_approval THEN

      v_can_activate := false;

      v_blockers :=
        v_blockers
        || jsonb_build_array(
             jsonb_build_object(
               'code',
               'missing_final_human_approval',

               'message',
               'Final human approval record is required.'
             )
           );

    END IF;


    -- =====================================================
    -- CURRICULUM MAPPING
    --
    -- Staging'de curriculum/topic varsa production'da
    -- approved mapping bulunmalı.
    -- =====================================================

    IF v_staging.proposed_curriculum_version_id IS NOT NULL
       OR v_staging.proposed_topic_id IS NOT NULL
    THEN

      SELECT EXISTS (
        SELECT 1
        FROM public.question_curriculum_mappings qm
        WHERE qm.question_id =
              p_question_id

          AND qm.review_status =
              'approved'
      )
      INTO v_has_approved_curriculum_mapping;


      IF NOT v_has_approved_curriculum_mapping THEN

        v_can_activate := false;

        v_blockers :=
          v_blockers
          || jsonb_build_array(
               jsonb_build_object(
                 'code',
                 'approved_curriculum_mapping_missing',

                 'message',
                 'Approved curriculum mapping is required.'
               )
             );

      END IF;

    ELSE

      v_warnings :=
        v_warnings
        || jsonb_build_array(
             jsonb_build_object(
               'code',
               'curriculum_mapping_not_provided',

               'message',
               'No curriculum mapping was provided for this staging question.'
             )
           );

    END IF;


    -- =====================================================
    -- AI READINESS
    --
    -- Promotion yapıldıktan sonra 038 zaten
    -- already_promoted olabilir.
    -- Bu yüzden 039 final approve kaydı esas kanıttır.
    -- =====================================================

    IF NOT EXISTS (
      SELECT 1
      FROM public.ai_question_readiness_runs rr
      WHERE rr.staging_question_id =
            v_staging.id

        AND rr.readiness_score =
            1.0000
    )
    THEN

      v_can_activate := false;

      v_blockers :=
        v_blockers
        || jsonb_build_array(
             jsonb_build_object(
               'code',
               'full_ai_readiness_missing',

               'message',
               'A full AI readiness score is required.'
             )
           );

    END IF;

  END IF;


  -- =======================================================
  -- VISUAL ASSET CHECK
  -- =======================================================

  IF v_question.has_visual = true THEN

    SELECT EXISTS (
      SELECT 1
      FROM public.question_assets qa
      WHERE qa.question_id =
            p_question_id

        AND qa.validation_status =
            'valid'

        AND qa.is_active =
            true
    )
    INTO v_has_required_visual_asset;


    IF NOT v_has_required_visual_asset THEN

      v_can_activate := false;

      v_blockers :=
        v_blockers
        || jsonb_build_array(
             jsonb_build_object(
               'code',
               'valid_visual_asset_missing',

               'message',
               'Question requires a valid and active visual asset.'
             )
           );

    END IF;

  ELSE

    v_has_required_visual_asset := true;

  END IF;


  -- =======================================================
  -- COMMERCIAL CLEARANCE
  --
  -- commercial_use_allowed FALSE olan normal eğitim
  -- aktivasyonu için commercial clearance zorunlu değildir.
  --
  -- Fakat soru commercial_use_allowed TRUE ise clearance
  -- mutlaka approved olmalıdır.
  -- =======================================================

  SELECT c.clearance_status
  INTO v_commercial_clearance_status
  FROM public.commercial_question_clearance c
  WHERE c.question_id =
        p_question_id

     OR (
       v_has_staging = true
       AND c.staging_question_id =
           v_staging.id
     )
  ORDER BY c.updated_at DESC,
           c.created_at DESC
  LIMIT 1;


  IF v_question.commercial_use_allowed = true
     AND COALESCE(
           v_commercial_clearance_status,
           ''
         ) <> 'approved'
  THEN

    v_can_activate := false;

    v_blockers :=
      v_blockers
      || jsonb_build_array(
           jsonb_build_object(
             'code',
             'commercial_clearance_missing',

             'message',
             'Commercially enabled question requires approved commercial clearance.'
           )
         );

  END IF;


  -- =======================================================
  -- RESULT
  -- =======================================================

  RETURN jsonb_build_object(
    'question_id',
    p_question_id,

    'question_code',
    v_question.question_code,

    'current_is_active',
    v_question.is_active,

    'can_activate',
    v_can_activate,

    'checks',
    jsonb_build_object(
      'approval_status',
      v_question.approval_status,

      'license_status',
      v_question.license_status,

      'ownership_status',
      v_question.ownership_status,

      'has_staging_origin',
      v_has_staging,

      'final_human_approval',
      v_has_final_human_approval,

      'approved_curriculum_mapping',
      v_has_approved_curriculum_mapping,

      'required_visual_asset_ready',
      v_has_required_visual_asset,

      'commercial_use_allowed',
      v_question.commercial_use_allowed,

      'commercial_clearance_status',
      COALESCE(
        v_commercial_clearance_status,
        'not_started'
      )
    ),

    'blocking_reasons',
    v_blockers,

    'warnings',
    v_warnings
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.check_question_activation_readiness(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.check_question_activation_readiness(uuid)
TO authenticated;


-- =========================================================
-- 3. PUBLIC READINESS CHECK
-- =========================================================

CREATE OR REPLACE FUNCTION public.check_question_activation_readiness(
  p_question_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
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


  RETURN private.check_question_activation_readiness(
    p_question_id
  );

END;
$$;


REVOKE ALL
ON FUNCTION public.check_question_activation_readiness(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.check_question_activation_readiness(uuid)
TO authenticated;


-- =========================================================
-- 4. ACTIVATE QUESTION
-- =========================================================

CREATE OR REPLACE FUNCTION private.activate_question_for_students(
  p_question_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;

  v_question public.questions%ROWTYPE;

  v_staging_id uuid;

  v_check jsonb;

  v_can_activate boolean;

  v_event_id uuid;
BEGIN

  -- Gerçek kullanıcı gerekir.
  -- Service role üzerinden otomatik publication yok.

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


  SELECT *
  INTO v_question
  FROM public.questions q
  WHERE q.id = p_question_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Question not found.';
  END IF;


  IF v_question.is_active = true THEN

    RETURN jsonb_build_object(
      'status',
      'already_active',

      'question_id',
      v_question.id,

      'question_code',
      v_question.question_code,

      'is_active',
      true
    );

  END IF;


  -- Aktivasyon öncesi bütün deterministic kontroller.

  v_check :=
    private.check_question_activation_readiness(
      p_question_id
    );


  v_can_activate :=
    COALESCE(
      (v_check ->> 'can_activate')::boolean,
      false
    );


  IF NOT v_can_activate THEN

    RAISE EXCEPTION
      'Question cannot be activated. Activation readiness checks failed: %',
      v_check -> 'blocking_reasons';

  END IF;


  SELECT s.id
  INTO v_staging_id
  FROM public.ai_question_staging s
  WHERE s.final_question_id =
        p_question_id
  ORDER BY s.updated_at DESC
  LIMIT 1;


  -- =======================================================
  -- ACTIVATE
  -- =======================================================

  UPDATE public.questions
  SET
    is_active = true

  WHERE id = p_question_id;


  -- =======================================================
  -- AUDIT
  -- =======================================================

  INSERT INTO public.question_publication_events (
    question_id,

    staging_question_id,

    action,

    previous_is_active,
    new_is_active,

    reason,

    performed_by,

    checks_snapshot,

    metadata
  )
  VALUES (
    p_question_id,

    v_staging_id,

    'activate',

    false,
    true,

    NULLIF(
      btrim(p_reason),
      ''
    ),

    v_user_id,

    v_check,

    jsonb_build_object(
      'student_visible',
      true,

      'automatic_publication',
      false,

      'human_publication_action',
      true
    )
  )
  RETURNING id
  INTO v_event_id;


  RETURN jsonb_build_object(
    'status',
    'activated',

    'publication_event_id',
    v_event_id,

    'question_id',
    p_question_id,

    'question_code',
    v_question.question_code,

    'approval_status',
    v_question.approval_status,

    'is_active',
    true,

    'student_visible',
    true,

    'automatic_publication',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.activate_question_for_students(
  uuid,
  text
)
FROM PUBLIC, anon, service_role;


GRANT EXECUTE
ON FUNCTION private.activate_question_for_students(
  uuid,
  text
)
TO authenticated;


-- =========================================================
-- 5. PUBLIC ACTIVATE RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.activate_question_for_students(
  p_question_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.activate_question_for_students(
    p_question_id,
    p_reason
  );
$$;


REVOKE ALL
ON FUNCTION public.activate_question_for_students(
  uuid,
  text
)
FROM PUBLIC, anon, service_role;


GRANT EXECUTE
ON FUNCTION public.activate_question_for_students(
  uuid,
  text
)
TO authenticated;


-- =========================================================
-- 6. DEACTIVATE QUESTION
--
-- Acil hata/telif/kalite durumlarında öğrenci erişimini
-- derhal kapatabiliriz.
-- =========================================================

CREATE OR REPLACE FUNCTION private.deactivate_question_for_students(
  p_question_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;

  v_question public.questions%ROWTYPE;

  v_staging_id uuid;

  v_event_id uuid;
BEGIN

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


  IF NULLIF(
       btrim(p_reason),
       ''
     ) IS NULL
  THEN

    RAISE EXCEPTION
      'Deactivation reason is required.';

  END IF;


  SELECT *
  INTO v_question
  FROM public.questions q
  WHERE q.id = p_question_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Question not found.';
  END IF;


  IF v_question.is_active = false THEN

    RETURN jsonb_build_object(
      'status',
      'already_inactive',

      'question_id',
      v_question.id,

      'question_code',
      v_question.question_code,

      'is_active',
      false
    );

  END IF;


  SELECT s.id
  INTO v_staging_id
  FROM public.ai_question_staging s
  WHERE s.final_question_id =
        p_question_id
  ORDER BY s.updated_at DESC
  LIMIT 1;


  UPDATE public.questions
  SET
    is_active = false

  WHERE id = p_question_id;


  INSERT INTO public.question_publication_events (
    question_id,
    staging_question_id,

    action,

    previous_is_active,
    new_is_active,

    reason,

    performed_by,

    checks_snapshot,

    metadata
  )
  VALUES (
    p_question_id,
    v_staging_id,

    'deactivate',

    true,
    false,

    btrim(p_reason),

    v_user_id,

    jsonb_build_object(
      'approval_status',
      v_question.approval_status
    ),

    jsonb_build_object(
      'student_visible',
      false,

      'human_publication_action',
      true
    )
  )
  RETURNING id
  INTO v_event_id;


  RETURN jsonb_build_object(
    'status',
    'deactivated',

    'publication_event_id',
    v_event_id,

    'question_id',
    p_question_id,

    'question_code',
    v_question.question_code,

    'is_active',
    false,

    'student_visible',
    false
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.deactivate_question_for_students(
  uuid,
  text
)
FROM PUBLIC, anon, service_role;


GRANT EXECUTE
ON FUNCTION private.deactivate_question_for_students(
  uuid,
  text
)
TO authenticated;


-- =========================================================
-- 7. PUBLIC DEACTIVATE RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.deactivate_question_for_students(
  p_question_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.deactivate_question_for_students(
    p_question_id,
    p_reason
  );
$$;


REVOKE ALL
ON FUNCTION public.deactivate_question_for_students(
  uuid,
  text
)
FROM PUBLIC, anon, service_role;


GRANT EXECUTE
ON FUNCTION public.deactivate_question_for_students(
  uuid,
  text
)
TO authenticated;


-- =========================================================
-- 8. PUBLICATION REPORT
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_question_publication_report(
  p_question_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_question public.questions%ROWTYPE;
  v_check jsonb;
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


  SELECT *
  INTO v_question
  FROM public.questions q
  WHERE q.id = p_question_id;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Question not found.';
  END IF;


  v_check :=
    private.check_question_activation_readiness(
      p_question_id
    );


  RETURN jsonb_build_object(
    'question_id',
    v_question.id,

    'question_code',
    v_question.question_code,

    'approval_status',
    v_question.approval_status,

    'is_active',
    v_question.is_active,

    'student_visible',
    (
      v_question.approval_status = 'approved'
      AND
      v_question.is_active = true
    ),

    'activation_readiness',
    v_check,

    'publication_events',
    (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'event_id',
            e.id,

            'action',
            e.action,

            'previous_is_active',
            e.previous_is_active,

            'new_is_active',
            e.new_is_active,

            'reason',
            e.reason,

            'performed_by',
            e.performed_by,

            'performed_at',
            e.performed_at
          )
          ORDER BY e.performed_at DESC
        ),

        '[]'::jsonb
      )

      FROM public.question_publication_events e

      WHERE e.question_id =
            p_question_id
    )
  );

END;
$$;


REVOKE ALL
ON FUNCTION public.get_question_publication_report(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_question_publication_report(uuid)
TO authenticated;


-- =========================================================
-- 9. RLS
-- =========================================================

DROP POLICY IF EXISTS
"admins read question publication events"
ON public.question_publication_events;


CREATE POLICY
"admins read question publication events"
ON public.question_publication_events
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


-- Publication event yazımı doğrudan yapılmaz.
-- Yalnız kontrollü SECURITY DEFINER RPC üzerinden yapılır.


-- =========================================================
-- 10. SECURITY INVOKER OVERVIEW
-- =========================================================

CREATE OR REPLACE VIEW public.question_publication_overview
WITH (security_invoker = true)
AS

SELECT
  q.id AS question_id,

  q.question_code,

  q.grade_level,
  q.subject_id,

  q.approval_status,
  q.is_active,

  (
    q.approval_status = 'approved'
    AND
    q.is_active = true
  ) AS student_visible,

  q.ownership_status,
  q.license_status,
  q.commercial_use_allowed,

  q.updated_at

FROM public.questions q;


REVOKE ALL
ON public.question_publication_overview
FROM PUBLIC, anon;


GRANT SELECT
ON public.question_publication_overview
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