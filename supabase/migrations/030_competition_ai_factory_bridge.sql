-- 030_competition_ai_factory_bridge.sql
-- Altın Kalemler
--
-- Yarışma soru havuzu ihtiyaç analizini
-- AI Question Factory akışına bağlayan güvenli köprü.
--
-- Temel güvenlik:
-- - Havuz açığı AI'yi otomatik başlatmaz.
-- - İnsan onayı zorunludur.
-- - Production'a doğrudan yazma yoktur.
-- - AI çıktısı staging'e gitmelidir.
-- - Sınıf / konu / kazanım / süre / özgünlük / telif
--   gereksinimleri snapshot olarak korunur.
-- - Talep, generation spec, AI job ve staging soruları
--   birbirine izlenebilir şekilde bağlanır.

BEGIN;


-- =========================================================
-- 1. FACTORY DISPATCH TABLOSU
--
-- competition_ai_generation_requests ile gerçek
-- AI Question Factory arasındaki güvenli köprü.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competition_ai_factory_dispatches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  dispatch_code text NOT NULL UNIQUE,

  competition_generation_request_id uuid NOT NULL
    REFERENCES public.competition_ai_generation_requests(id)
    ON DELETE CASCADE,

  profile_id uuid NOT NULL
    REFERENCES public.competition_pool_profiles(id)
    ON DELETE CASCADE,

  analysis_run_id uuid
    REFERENCES public.competition_pool_analysis_runs(id)
    ON DELETE SET NULL,

  gap_item_id uuid
    REFERENCES public.competition_pool_gap_items(id)
    ON DELETE SET NULL,

  -- -------------------------------------------------------
  -- İstenen soru adedi
  -- -------------------------------------------------------

  requested_question_count integer NOT NULL
    CHECK (requested_question_count > 0),

  -- -------------------------------------------------------
  -- AI Factory bağlantıları
  -- Bunlar factory kayıtları oluşturuldukça doldurulur.
  -- -------------------------------------------------------

  generation_spec_id uuid
    REFERENCES public.ai_generation_specs(id)
    ON DELETE SET NULL,

  ai_job_id uuid
    REFERENCES public.ai_jobs(id)
    ON DELETE SET NULL,

  -- -------------------------------------------------------
  -- Requirement snapshot
  --
  -- Talep oluşturulduktan sonra profile değişse bile
  -- bu üretimin şartları değişmez.
  -- -------------------------------------------------------

  generation_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  curriculum_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  solve_time_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  quality_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  diversity_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  copyright_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  review_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- -------------------------------------------------------
  -- Dispatch durumu
  -- -------------------------------------------------------

  status text NOT NULL DEFAULT 'prepared'
    CHECK (
      status IN (
        'prepared',
        'ready_for_factory',
        'spec_created',
        'job_created',
        'generating',
        'staging',
        'reviewing',
        'partially_completed',
        'completed',
        'blocked',
        'failed',
        'cancelled'
      )
    ),

  -- -------------------------------------------------------
  -- Sonuç sayaçları
  -- -------------------------------------------------------

  generated_count integer NOT NULL DEFAULT 0
    CHECK (generated_count >= 0),

  staging_count integer NOT NULL DEFAULT 0
    CHECK (staging_count >= 0),

  approved_count integer NOT NULL DEFAULT 0
    CHECK (approved_count >= 0),

  rejected_count integer NOT NULL DEFAULT 0
    CHECK (rejected_count >= 0),

  copyright_blocked_count integer NOT NULL DEFAULT 0
    CHECK (copyright_blocked_count >= 0),

  solve_time_rejected_count integer NOT NULL DEFAULT 0
    CHECK (solve_time_rejected_count >= 0),

  curriculum_rejected_count integer NOT NULL DEFAULT 0
    CHECK (curriculum_rejected_count >= 0),

  -- -------------------------------------------------------
  -- İnsan onayı snapshot
  -- -------------------------------------------------------

  human_approved boolean NOT NULL DEFAULT false,

  approved_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  approved_at timestamptz,

  -- -------------------------------------------------------
  -- Güvenlik
  -- -------------------------------------------------------

  production_promotion_allowed boolean
    NOT NULL DEFAULT false,

  automatic_publication_allowed boolean
    NOT NULL DEFAULT false,

  error_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (competition_generation_request_id),

  CHECK (
    human_approved = false
    OR (
      approved_by IS NOT NULL
      AND approved_at IS NOT NULL
    )
  ),

  CHECK (
    automatic_publication_allowed = false
  )
);


CREATE INDEX IF NOT EXISTS
idx_competition_factory_dispatch_status
ON public.competition_ai_factory_dispatches(
  status,
  created_at DESC
);


CREATE INDEX IF NOT EXISTS
idx_competition_factory_dispatch_spec
ON public.competition_ai_factory_dispatches(
  generation_spec_id
);


CREATE INDEX IF NOT EXISTS
idx_competition_factory_dispatch_job
ON public.competition_ai_factory_dispatches(
  ai_job_id
);


ALTER TABLE public.competition_ai_factory_dispatches
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS
trigger_competition_ai_factory_dispatch_updated_at
ON public.competition_ai_factory_dispatches;


CREATE TRIGGER
trigger_competition_ai_factory_dispatch_updated_at
BEFORE UPDATE
ON public.competition_ai_factory_dispatches
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. AI GENERATION SPEC'E KAYNAK TALEBİ BAĞLA
-- =========================================================

ALTER TABLE public.ai_generation_specs
ADD COLUMN IF NOT EXISTS
competition_generation_request_id uuid
REFERENCES public.competition_ai_generation_requests(id)
ON DELETE SET NULL;


ALTER TABLE public.ai_generation_specs
ADD COLUMN IF NOT EXISTS
competition_factory_dispatch_id uuid
REFERENCES public.competition_ai_factory_dispatches(id)
ON DELETE SET NULL;


CREATE INDEX IF NOT EXISTS
idx_ai_generation_specs_competition_request
ON public.ai_generation_specs(
  competition_generation_request_id
);


CREATE INDEX IF NOT EXISTS
idx_ai_generation_specs_dispatch
ON public.ai_generation_specs(
  competition_factory_dispatch_id
);


-- =========================================================
-- 3. AI JOB'A DISPATCH BAĞLA
-- =========================================================

ALTER TABLE public.ai_jobs
ADD COLUMN IF NOT EXISTS
competition_generation_request_id uuid
REFERENCES public.competition_ai_generation_requests(id)
ON DELETE SET NULL;


ALTER TABLE public.ai_jobs
ADD COLUMN IF NOT EXISTS
competition_factory_dispatch_id uuid
REFERENCES public.competition_ai_factory_dispatches(id)
ON DELETE SET NULL;


CREATE INDEX IF NOT EXISTS
idx_ai_jobs_competition_request
ON public.ai_jobs(
  competition_generation_request_id
);


CREATE INDEX IF NOT EXISTS
idx_ai_jobs_dispatch
ON public.ai_jobs(
  competition_factory_dispatch_id
);


-- =========================================================
-- 4. STAGING SORULARINI DISPATCH'E BAĞLA
--
-- Üretilen her sorunun hangi havuz açığını kapatmak için
-- üretildiği izlenebilir.
-- =========================================================

ALTER TABLE public.ai_question_staging
ADD COLUMN IF NOT EXISTS
competition_generation_request_id uuid
REFERENCES public.competition_ai_generation_requests(id)
ON DELETE SET NULL;


ALTER TABLE public.ai_question_staging
ADD COLUMN IF NOT EXISTS
competition_factory_dispatch_id uuid
REFERENCES public.competition_ai_factory_dispatches(id)
ON DELETE SET NULL;


CREATE INDEX IF NOT EXISTS
idx_ai_question_staging_competition_request
ON public.ai_question_staging(
  competition_generation_request_id
);


CREATE INDEX IF NOT EXISTS
idx_ai_question_staging_dispatch
ON public.ai_question_staging(
  competition_factory_dispatch_id
);


-- =========================================================
-- 5. DISPATCH OLUŞTURMA KORUMASI
--
-- İnsan onayı olmadan factory'ye geçiş yapılamaz.
-- =========================================================

CREATE OR REPLACE FUNCTION public.validate_competition_factory_dispatch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_request_approved boolean;
  v_request_status text;
BEGIN

  SELECT
    r.human_approval_received,
    r.status

  INTO
    v_request_approved,
    v_request_status

  FROM public.competition_ai_generation_requests r

  WHERE r.id =
    NEW.competition_generation_request_id;


  IF v_request_approved IS NULL THEN

    RAISE EXCEPTION
      'Competition AI generation request not found.';

  END IF;


  IF NEW.status IN (
    'ready_for_factory',
    'spec_created',
    'job_created',
    'generating',
    'staging',
    'reviewing',
    'partially_completed',
    'completed'
  )
  AND (
    v_request_approved = false
    OR NEW.human_approved = false
  )
  THEN

    RAISE EXCEPTION
      'Human approval is required before AI Factory dispatch.';

  END IF;


  -- -------------------------------------------------------
  -- AI hiçbir zaman automatic publication açamaz.
  -- -------------------------------------------------------

  IF NEW.automatic_publication_allowed = true THEN

    RAISE EXCEPTION
      'Automatic publication of AI generated questions is forbidden.';

  END IF;


  IF NEW.production_promotion_allowed = true
     AND NEW.status NOT IN (
       'reviewing',
       'partially_completed',
       'completed'
     )
  THEN

    RAISE EXCEPTION
      'Production promotion cannot be enabled before review.';

  END IF;


  RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS
trigger_validate_competition_factory_dispatch
ON public.competition_ai_factory_dispatches;


CREATE TRIGGER
trigger_validate_competition_factory_dispatch
BEFORE INSERT OR UPDATE
ON public.competition_ai_factory_dispatches
FOR EACH ROW
EXECUTE FUNCTION public.validate_competition_factory_dispatch();


REVOKE EXECUTE
ON FUNCTION public.validate_competition_factory_dispatch()
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 6. ADMIN ONAYI + DISPATCH HAZIRLAMA
--
-- Bu fonksiyon:
-- - request'i kontrol eder
-- - insan onayını kaydeder
-- - requirement snapshot oluşturur
-- - dispatch yaratır
--
-- AI job henüz başlamaz.
-- =========================================================

CREATE OR REPLACE FUNCTION private.approve_competition_ai_generation_request(
  p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;

  v_request public.competition_ai_generation_requests%ROWTYPE;
  v_profile public.competition_pool_profiles%ROWTYPE;

  v_dispatch_id uuid;
  v_dispatch_code text;

  v_existing_dispatch_id uuid;
BEGIN

  v_user_id := auth.uid();


  IF v_user_id IS NULL THEN

    RAISE EXCEPTION
      'Authentication required.';

  END IF;


  -- -------------------------------------------------------
  -- Yetki
  -- -------------------------------------------------------

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
      'Question approval or AI management permission required.';

  END IF;


  -- -------------------------------------------------------
  -- Request'i kilitle
  -- -------------------------------------------------------

  SELECT *
  INTO v_request

  FROM public.competition_ai_generation_requests r

  WHERE r.id = p_request_id

  FOR UPDATE;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Competition AI generation request not found.';

  END IF;


  IF v_request.status IN (
    'rejected',
    'cancelled',
    'failed'
  ) THEN

    RAISE EXCEPTION
      'This generation request cannot be approved.';

  END IF;


  -- -------------------------------------------------------
  -- Daha önce dispatch oluşturulduysa tekrar oluşturma.
  -- -------------------------------------------------------

  SELECT d.id
  INTO v_existing_dispatch_id

  FROM public.competition_ai_factory_dispatches d

  WHERE d.competition_generation_request_id =
        p_request_id;


  IF v_existing_dispatch_id IS NOT NULL THEN

    RETURN v_existing_dispatch_id;

  END IF;


  -- -------------------------------------------------------
  -- Profile
  -- -------------------------------------------------------

  SELECT *
  INTO v_profile

  FROM public.competition_pool_profiles p

  WHERE p.id = v_request.profile_id;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Competition pool profile not found.';

  END IF;


  -- -------------------------------------------------------
  -- İnsan onayı request'e kaydet
  -- -------------------------------------------------------

  UPDATE public.competition_ai_generation_requests
  SET
    human_approval_received = true,

    approved_by = v_user_id,

    approved_at = clock_timestamp(),

    status = 'approved'

  WHERE id = p_request_id;


  -- -------------------------------------------------------
  -- Dispatch code
  -- -------------------------------------------------------

  v_dispatch_code :=
    'CAFD-'
    || to_char(
         clock_timestamp(),
         'YYYYMMDDHH24MISSMS'
       )
    || '-'
    || substr(
         replace(
           gen_random_uuid()::text,
           '-',
           ''
         ),
         1,
         8
       );


  -- -------------------------------------------------------
  -- Dispatch oluştur.
  -- -------------------------------------------------------

  INSERT INTO public.competition_ai_factory_dispatches (
    dispatch_code,

    competition_generation_request_id,

    profile_id,

    analysis_run_id,

    gap_item_id,

    requested_question_count,

    generation_requirements,

    curriculum_requirements,

    solve_time_requirements,

    quality_requirements,

    diversity_requirements,

    copyright_requirements,

    review_requirements,

    status,

    human_approved,

    approved_by,

    approved_at,

    production_promotion_allowed,

    automatic_publication_allowed,

    metadata
  )

  VALUES (
    v_dispatch_code,

    p_request_id,

    v_request.profile_id,

    v_request.analysis_run_id,

    v_request.gap_item_id,

    v_request.requested_question_count,

    v_request.generation_requirements,

    jsonb_build_object(

      'curriculum_version_id',
      v_profile.curriculum_version_id,

      'grade_level',
      v_profile.grade_level,

      'subject_id',
      v_profile.subject_id,

      'topic_id',
      v_profile.topic_id,

      'subtopic_id',
      v_profile.subtopic_id,

      'outcome_id',
      v_profile.outcome_id,

      'grade_fit_validation_required',
      true,

      'topic_fit_validation_required',
      true,

      'subtopic_fit_validation_required',
      true,

      'outcome_fit_validation_required',
      true,

      'prerequisite_validation_required',
      true
    ),

    v_request.solve_time_requirements,

    v_request.quality_requirements,

    v_request.diversity_requirements,

    v_request.copyright_requirements,

    jsonb_build_object(

      'independent_answer_review_required',
      true,

      'independent_curriculum_review_required',
      true,

      'independent_solve_time_review_required',
      true,

      'originality_review_required',
      true,

      'copyright_review_required',
      true,

      'second_ai_review_required',
      true,

      'human_final_approval_required',
      true
    ),

    'ready_for_factory',

    true,

    v_user_id,

    clock_timestamp(),

    false,

    false,

    jsonb_build_object(
      'origin',
      'competition_pool_gap_analysis',

      'request_code',
      v_request.request_code,

      'profile_code',
      v_profile.profile_code
    )
  )

  RETURNING id
  INTO v_dispatch_id;


  RETURN v_dispatch_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.approve_competition_ai_generation_request(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.approve_competition_ai_generation_request(uuid)
TO authenticated, service_role;


-- =========================================================
-- 7. PUBLIC ADMIN RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.approve_competition_ai_generation_request(
  p_request_id uuid
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.approve_competition_ai_generation_request(
    p_request_id
  );
$$;


REVOKE ALL
ON FUNCTION public.approve_competition_ai_generation_request(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.approve_competition_ai_generation_request(uuid)
TO authenticated, service_role;


-- =========================================================
-- 8. FACTORY SPEC BAĞLAMA RPC
--
-- AI Generation Spec oluşturulduktan sonra dispatch'e
-- bağlamak için kullanılır.
--
-- Bu fonksiyon spec'in hangi competition request'ten
-- geldiğini de otomatik yazar.
-- =========================================================

CREATE OR REPLACE FUNCTION private.link_competition_generation_spec(
  p_dispatch_id uuid,
  p_generation_spec_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_request_id uuid;
BEGIN

  IF NOT (
    private.current_user_has_admin_permission(
      'ai.manage'
    )
    OR
    private.current_user_has_admin_permission(
      'questions.approve'
    )
  ) THEN

    RAISE EXCEPTION
      'AI management permission required.';

  END IF;


  SELECT d.competition_generation_request_id
  INTO v_request_id

  FROM public.competition_ai_factory_dispatches d

  WHERE d.id = p_dispatch_id

  FOR UPDATE;


  IF v_request_id IS NULL THEN

    RAISE EXCEPTION
      'Competition AI factory dispatch not found.';

  END IF;


  IF NOT EXISTS (
    SELECT 1

    FROM public.ai_generation_specs s

    WHERE s.id = p_generation_spec_id
  ) THEN

    RAISE EXCEPTION
      'AI generation spec not found.';

  END IF;


  UPDATE public.ai_generation_specs
  SET
    competition_generation_request_id =
      v_request_id,

    competition_factory_dispatch_id =
      p_dispatch_id

  WHERE id = p_generation_spec_id;


  UPDATE public.competition_ai_factory_dispatches
  SET
    generation_spec_id =
      p_generation_spec_id,

    status = 'spec_created'

  WHERE id = p_dispatch_id;


  UPDATE public.competition_ai_generation_requests
  SET
    generation_spec_id =
      p_generation_spec_id

  WHERE id = v_request_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.link_competition_generation_spec(uuid, uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.link_competition_generation_spec(uuid, uuid)
TO authenticated, service_role;


-- =========================================================
-- 9. FACTORY JOB BAĞLAMA RPC
-- =========================================================

CREATE OR REPLACE FUNCTION private.link_competition_ai_job(
  p_dispatch_id uuid,
  p_ai_job_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_request_id uuid;
  v_spec_id uuid;
BEGIN

  IF NOT private.current_user_has_admin_permission(
    'ai.manage'
  ) THEN

    RAISE EXCEPTION
      'AI management permission required.';

  END IF;


  SELECT
    d.competition_generation_request_id,
    d.generation_spec_id

  INTO
    v_request_id,
    v_spec_id

  FROM public.competition_ai_factory_dispatches d

  WHERE d.id = p_dispatch_id

  FOR UPDATE;


  IF v_request_id IS NULL THEN

    RAISE EXCEPTION
      'Competition AI factory dispatch not found.';

  END IF;


  IF v_spec_id IS NULL THEN

    RAISE EXCEPTION
      'Generation spec must be linked before AI job.';

  END IF;


  IF NOT EXISTS (
    SELECT 1

    FROM public.ai_jobs j

    WHERE j.id = p_ai_job_id
  ) THEN

    RAISE EXCEPTION
      'AI job not found.';

  END IF;


  UPDATE public.ai_jobs
  SET
    competition_generation_request_id =
      v_request_id,

    competition_factory_dispatch_id =
      p_dispatch_id

  WHERE id = p_ai_job_id;


  UPDATE public.competition_ai_factory_dispatches
  SET
    ai_job_id =
      p_ai_job_id,

    status = 'job_created'

  WHERE id = p_dispatch_id;


  UPDATE public.competition_ai_generation_requests
  SET
    ai_job_id =
      p_ai_job_id,

    status = 'queued'

  WHERE id = v_request_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.link_competition_ai_job(uuid, uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.link_competition_ai_job(uuid, uuid)
TO authenticated, service_role;


-- =========================================================
-- 10. STAGING KORUMASI
--
-- Competition dispatch'ten gelen staging sorusunun:
--
-- request
-- dispatch
-- generation spec
-- AI job
--
-- ilişkisi izlenebilir olmalı.
-- =========================================================

CREATE OR REPLACE FUNCTION public.validate_competition_staging_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_expected_request_id uuid;
BEGIN

  IF NEW.competition_factory_dispatch_id IS NULL THEN

    RETURN NEW;

  END IF;


  SELECT d.competition_generation_request_id
  INTO v_expected_request_id

  FROM public.competition_ai_factory_dispatches d

  WHERE d.id =
    NEW.competition_factory_dispatch_id;


  IF v_expected_request_id IS NULL THEN

    RAISE EXCEPTION
      'Competition AI factory dispatch not found.';

  END IF;


  IF NEW.competition_generation_request_id IS NULL THEN

    NEW.competition_generation_request_id :=
      v_expected_request_id;

  END IF;


  IF NEW.competition_generation_request_id
     <> v_expected_request_id THEN

    RAISE EXCEPTION
      'Staging question request does not match factory dispatch.';

  END IF;


  RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS
trigger_validate_competition_staging_link
ON public.ai_question_staging;


CREATE TRIGGER
trigger_validate_competition_staging_link
BEFORE INSERT OR UPDATE
ON public.ai_question_staging
FOR EACH ROW
EXECUTE FUNCTION public.validate_competition_staging_link();


REVOKE EXECUTE
ON FUNCTION public.validate_competition_staging_link()
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 11. DISPATCH SAYACINI SENKRONİZE ET
-- =========================================================

CREATE OR REPLACE FUNCTION private.refresh_competition_factory_dispatch_counts(
  p_dispatch_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_staging integer := 0;
  v_approved integer := 0;
  v_rejected integer := 0;
BEGIN

  SELECT COUNT(*)
  INTO v_staging

  FROM public.ai_question_staging s

  WHERE s.competition_factory_dispatch_id =
        p_dispatch_id;


  -- -------------------------------------------------------
  -- Staging status'larını JSON olarak okuyarak mevcut
  -- şemayla daha esnek çalış.
  -- -------------------------------------------------------

  SELECT COUNT(*)
  INTO v_approved

  FROM public.ai_question_staging s

  WHERE s.competition_factory_dispatch_id =
        p_dispatch_id

    AND lower(
      COALESCE(
        to_jsonb(s) ->> 'review_status',
        to_jsonb(s) ->> 'status',
        ''
      )
    ) IN (
      'approved',
      'accepted',
      'promoted'
    );


  SELECT COUNT(*)
  INTO v_rejected

  FROM public.ai_question_staging s

  WHERE s.competition_factory_dispatch_id =
        p_dispatch_id

    AND lower(
      COALESCE(
        to_jsonb(s) ->> 'review_status',
        to_jsonb(s) ->> 'status',
        ''
      )
    ) IN (
      'rejected',
      'blocked',
      'failed'
    );


  UPDATE public.competition_ai_factory_dispatches
  SET
    staging_count = v_staging,

    approved_count = v_approved,

    rejected_count = v_rejected,

    status =
      CASE

        WHEN v_staging = 0
          THEN status

        WHEN v_approved + v_rejected < v_staging
          THEN 'reviewing'

        WHEN v_approved >= requested_question_count
          THEN 'completed'

        WHEN v_approved > 0
          THEN 'partially_completed'

        ELSE 'reviewing'

      END

  WHERE id = p_dispatch_id;


  UPDATE public.competition_ai_generation_requests r
  SET
    staging_count = d.staging_count,

    approved_count = d.approved_count,

    rejected_count = d.rejected_count,

    status =
      CASE

        WHEN d.status = 'completed'
          THEN 'completed'

        WHEN d.status = 'partially_completed'
          THEN 'partially_completed'

        WHEN d.status = 'reviewing'
          THEN 'reviewing'

        ELSE r.status

      END

  FROM public.competition_ai_factory_dispatches d

  WHERE d.id = p_dispatch_id
    AND r.id =
      d.competition_generation_request_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.refresh_competition_factory_dispatch_counts(uuid)
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 12. STAGING DEĞİŞİNCE SAYACI YENİLE
-- =========================================================

CREATE OR REPLACE FUNCTION public.after_competition_staging_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_dispatch_id uuid;
BEGIN

  v_dispatch_id :=
    COALESCE(
      NEW.competition_factory_dispatch_id,
      OLD.competition_factory_dispatch_id
    );


  IF v_dispatch_id IS NOT NULL THEN

    PERFORM
      private.refresh_competition_factory_dispatch_counts(
        v_dispatch_id
      );

  END IF;


  RETURN COALESCE(NEW, OLD);

END;
$$;


DROP TRIGGER IF EXISTS
trigger_after_competition_staging_change
ON public.ai_question_staging;


CREATE TRIGGER
trigger_after_competition_staging_change
AFTER INSERT OR UPDATE OR DELETE
ON public.ai_question_staging
FOR EACH ROW
EXECUTE FUNCTION public.after_competition_staging_change();


REVOKE ALL
ON FUNCTION public.after_competition_staging_change()
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 13. ADMIN RLS
-- =========================================================

DROP POLICY IF EXISTS
"admins manage competition ai factory dispatches"
ON public.competition_ai_factory_dispatches;


CREATE POLICY
"admins manage competition ai factory dispatches"
ON public.competition_ai_factory_dispatches
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
-- 14. ADMIN OVERVIEW VIEW
-- =========================================================

CREATE OR REPLACE VIEW public.competition_ai_factory_overview
WITH (security_invoker = true)
AS

SELECT
  d.id AS dispatch_id,
  d.dispatch_code,

  r.id AS request_id,
  r.request_code,

  p.profile_code,
  p.name AS profile_name,

  p.grade_level,
  p.subject_id,
  p.topic_id,
  p.subtopic_id,
  p.outcome_id,

  d.requested_question_count,

  d.generated_count,
  d.staging_count,
  d.approved_count,
  d.rejected_count,

  d.copyright_blocked_count,
  d.solve_time_rejected_count,
  d.curriculum_rejected_count,

  d.status,

  d.generation_spec_id,
  d.ai_job_id,

  d.human_approved,
  d.approved_by,
  d.approved_at,

  d.created_at,
  d.updated_at

FROM public.competition_ai_factory_dispatches d

JOIN public.competition_ai_generation_requests r
  ON r.id =
     d.competition_generation_request_id

JOIN public.competition_pool_profiles p
  ON p.id = d.profile_id;


REVOKE ALL
ON public.competition_ai_factory_overview
FROM PUBLIC;

REVOKE ALL
ON public.competition_ai_factory_overview
FROM anon;

GRANT SELECT
ON public.competition_ai_factory_overview
TO authenticated;


-- =========================================================
-- 15. PRIVATE DEFAULT SECURITY
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