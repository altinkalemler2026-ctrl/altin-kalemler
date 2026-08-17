-- 031_competition_ai_job_builder.sql
-- Altın Kalemler
--
-- Competition Pool Demand -> AI Question Factory
-- gerçek Generation Spec + AI Job oluşturma motoru.
--
-- Akış:
--
-- competition_ai_generation_requests
--            ↓
-- human approval
--            ↓
-- competition_ai_factory_dispatches
--            ↓
-- ai_generation_specs
--            ↓
-- ai_jobs (question_generation)
--            ↓
-- ai_question_staging
--
-- Güvenlik:
-- - İnsan onayı olmadan job oluşturulamaz.
-- - Aynı dispatch için ikinci spec/job oluşturulamaz.
-- - Competition job yalnız kendi spec/request/dispatch'iyle çalışır.
-- - Staging kayıtlarının job/spec/request ilişkisi doğrulanır.
-- - Production'a otomatik yayın yapılmaz.
-- - Bu migration herhangi bir ücretli AI sağlayıcısını çağırmaz.

BEGIN;


-- =========================================================
-- 1. AYNI SPEC / JOB'IN BİRDEN FAZLA DISPATCH'E
-- BAĞLANMASINI ENGELLE
-- =========================================================

CREATE UNIQUE INDEX IF NOT EXISTS
uq_competition_factory_dispatch_generation_spec
ON public.competition_ai_factory_dispatches(
  generation_spec_id
)
WHERE generation_spec_id IS NOT NULL;


CREATE UNIQUE INDEX IF NOT EXISTS
uq_competition_factory_dispatch_ai_job
ON public.competition_ai_factory_dispatches(
  ai_job_id
)
WHERE ai_job_id IS NOT NULL;


-- =========================================================
-- 2. COMPETITION AI JOB GÜVENLİK KAPISI
--
-- Competition dispatch'e bağlı bir AI job:
--
-- - onaylı request'ten gelmeli
-- - onaylı dispatch'e bağlı olmalı
-- - doğru generation spec'i kullanmalı
-- =========================================================

CREATE OR REPLACE FUNCTION public.validate_competition_ai_job()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_dispatch record;
  v_request record;
BEGIN

  -- Competition factory ile ilgisi olmayan AI job'lara
  -- müdahale etme.
  IF NEW.competition_factory_dispatch_id IS NULL THEN
    RETURN NEW;
  END IF;


  SELECT
    d.id,
    d.competition_generation_request_id,
    d.generation_spec_id,
    d.human_approved,
    d.automatic_publication_allowed,
    d.status

  INTO v_dispatch

  FROM public.competition_ai_factory_dispatches d

  WHERE d.id =
    NEW.competition_factory_dispatch_id;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Competition AI factory dispatch not found.';

  END IF;


  SELECT
    r.id,
    r.human_approval_required,
    r.human_approval_received,
    r.status

  INTO v_request

  FROM public.competition_ai_generation_requests r

  WHERE r.id =
    v_dispatch.competition_generation_request_id;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Competition AI generation request not found.';

  END IF;


  -- -------------------------------------------------------
  -- Request eşleşmesi
  -- -------------------------------------------------------

  IF NEW.competition_generation_request_id IS NULL THEN

    NEW.competition_generation_request_id :=
      v_dispatch.competition_generation_request_id;

  END IF;


  IF NEW.competition_generation_request_id
     <> v_dispatch.competition_generation_request_id THEN

    RAISE EXCEPTION
      'AI job generation request does not match factory dispatch.';

  END IF;


  -- -------------------------------------------------------
  -- Generation Spec eşleşmesi
  -- -------------------------------------------------------

  IF v_dispatch.generation_spec_id IS NULL THEN

    RAISE EXCEPTION
      'Factory dispatch does not have a generation spec.';

  END IF;


  IF NEW.generation_spec_id IS NULL THEN

    NEW.generation_spec_id :=
      v_dispatch.generation_spec_id;

  END IF;


  IF NEW.generation_spec_id
     <> v_dispatch.generation_spec_id THEN

    RAISE EXCEPTION
      'AI job generation spec does not match factory dispatch.';

  END IF;


  -- -------------------------------------------------------
  -- İnsan onayı
  -- -------------------------------------------------------

  IF NEW.status IN (
    'queued',
    'processing',
    'completed',
    'completed_with_warnings'
  )
  THEN

    IF v_dispatch.human_approved = false THEN

      RAISE EXCEPTION
        'Factory dispatch requires human approval.';

    END IF;


    IF v_request.human_approval_required = true
       AND v_request.human_approval_received = false THEN

      RAISE EXCEPTION
        'Generation request requires human approval.';

    END IF;

  END IF;


  -- -------------------------------------------------------
  -- Otomatik yayın kesinlikle yasak.
  -- -------------------------------------------------------

  IF v_dispatch.automatic_publication_allowed = true THEN

    RAISE EXCEPTION
      'Automatic publication of AI generated questions is forbidden.';

  END IF;


  RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS
trigger_validate_competition_ai_job
ON public.ai_jobs;


CREATE TRIGGER
trigger_validate_competition_ai_job
BEFORE INSERT OR UPDATE
ON public.ai_jobs
FOR EACH ROW
EXECUTE FUNCTION public.validate_competition_ai_job();


REVOKE EXECUTE
ON FUNCTION public.validate_competition_ai_job()
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 3. STAGING BAĞLANTI KORUMASINI GÜÇLENDİR
--
-- 030'daki fonksiyonu geliştiriyoruz.
--
-- Artık kontrol edilenler:
--
-- request
-- dispatch
-- generation_spec
-- ai_job
-- =========================================================

CREATE OR REPLACE FUNCTION public.validate_competition_staging_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_dispatch record;
BEGIN

  IF NEW.competition_factory_dispatch_id IS NULL THEN
    RETURN NEW;
  END IF;


  SELECT
    d.competition_generation_request_id,
    d.generation_spec_id,
    d.ai_job_id,
    d.human_approved,
    d.automatic_publication_allowed

  INTO v_dispatch

  FROM public.competition_ai_factory_dispatches d

  WHERE d.id =
    NEW.competition_factory_dispatch_id;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Competition AI factory dispatch not found.';

  END IF;


  IF v_dispatch.human_approved = false THEN

    RAISE EXCEPTION
      'Competition AI factory dispatch has not been approved.';

  END IF;


  IF v_dispatch.automatic_publication_allowed = true THEN

    RAISE EXCEPTION
      'Automatic publication is forbidden.';

  END IF;


  -- -------------------------------------------------------
  -- Request
  -- -------------------------------------------------------

  IF NEW.competition_generation_request_id IS NULL THEN

    NEW.competition_generation_request_id :=
      v_dispatch.competition_generation_request_id;

  END IF;


  IF NEW.competition_generation_request_id
     <> v_dispatch.competition_generation_request_id THEN

    RAISE EXCEPTION
      'Staging request does not match factory dispatch.';

  END IF;


  -- -------------------------------------------------------
  -- Generation Spec
  -- -------------------------------------------------------

  IF v_dispatch.generation_spec_id IS NULL THEN

    RAISE EXCEPTION
      'Factory dispatch does not have a generation spec.';

  END IF;


  IF NEW.generation_spec_id IS NULL THEN

    NEW.generation_spec_id :=
      v_dispatch.generation_spec_id;

  END IF;


  IF NEW.generation_spec_id
     <> v_dispatch.generation_spec_id THEN

    RAISE EXCEPTION
      'Staging generation spec does not match factory dispatch.';

  END IF;


  -- -------------------------------------------------------
  -- AI Job
  -- -------------------------------------------------------

  IF v_dispatch.ai_job_id IS NULL THEN

    RAISE EXCEPTION
      'Factory dispatch does not have an AI job.';

  END IF;


  IF NEW.ai_job_id IS NULL THEN

    NEW.ai_job_id :=
      v_dispatch.ai_job_id;

  END IF;


  IF NEW.ai_job_id
     <> v_dispatch.ai_job_id THEN

    RAISE EXCEPTION
      'Staging AI job does not match factory dispatch.';

  END IF;


  -- Competition Factory tarafından üretilen soru
  -- mutlaka ai_generated olmalı.

  IF NEW.staging_source <> 'ai_generated' THEN

    RAISE EXCEPTION
      'Competition factory staging source must be ai_generated.';

  END IF;


  RETURN NEW;

END;
$$;


-- Trigger 030'da zaten oluşturuldu.
-- Tekrar güvenli şekilde tanımlıyoruz.

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
-- 4. FACTORY JOB BUILDER
--
-- Bir ready_for_factory dispatch'ten:
--
-- 1. ai_generation_specs
-- 2. ai_jobs
--
-- oluşturur.
--
-- Gerçek AI API çağrısı YAPMAZ.
-- =========================================================

CREATE OR REPLACE FUNCTION private.build_competition_ai_factory_job(
  p_dispatch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;

  v_dispatch public.competition_ai_factory_dispatches%ROWTYPE;
  v_request public.competition_ai_generation_requests%ROWTYPE;
  v_profile public.competition_pool_profiles%ROWTYPE;

  v_workflow_id uuid;

  v_spec_id uuid;
  v_job_id uuid;

  v_existing_spec_id uuid;
  v_existing_job_id uuid;

  v_spec_difficulty text;
  v_spec_cognitive text;

  v_min_time integer;
  v_max_time integer;

  v_constraints jsonb;

  v_generation_instructions text;
BEGIN

  v_user_id := auth.uid();


  IF v_user_id IS NULL THEN

    RAISE EXCEPTION
      'Authentication required.';

  END IF;


  -- =======================================================
  -- YETKİ
  -- =======================================================

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
      'AI management or question approval permission required.';

  END IF;


  -- =======================================================
  -- DISPATCH KİLİTLE
  -- =======================================================

  SELECT *
  INTO v_dispatch

  FROM public.competition_ai_factory_dispatches d

  WHERE d.id = p_dispatch_id

  FOR UPDATE;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Competition AI factory dispatch not found.';

  END IF;


  -- =======================================================
  -- DAHA ÖNCE OLUŞTURULMUŞSA MÜKERRER OLUŞTURMA
  -- =======================================================

  v_existing_spec_id :=
    v_dispatch.generation_spec_id;


  v_existing_job_id :=
    v_dispatch.ai_job_id;


  IF v_existing_spec_id IS NOT NULL
     AND v_existing_job_id IS NOT NULL THEN

    RETURN jsonb_build_object(
      'status',
      'already_created',

      'dispatch_id',
      p_dispatch_id,

      'generation_spec_id',
      v_existing_spec_id,

      'ai_job_id',
      v_existing_job_id
    );

  END IF;


  -- =======================================================
  -- DISPATCH DURUMU
  -- =======================================================

  IF v_dispatch.status NOT IN (
    'ready_for_factory',
    'spec_created'
  ) THEN

    RAISE EXCEPTION
      'Factory dispatch is not ready for job creation. Current status: %',
      v_dispatch.status;

  END IF;


  IF v_dispatch.human_approved = false THEN

    RAISE EXCEPTION
      'Factory dispatch requires human approval.';

  END IF;


  IF v_dispatch.automatic_publication_allowed = true THEN

    RAISE EXCEPTION
      'Automatic publication is forbidden.';

  END IF;


  IF v_dispatch.production_promotion_allowed = true THEN

    RAISE EXCEPTION
      'Production promotion cannot be enabled before AI review.';

  END IF;


  -- =======================================================
  -- REQUEST
  -- =======================================================

  SELECT *
  INTO v_request

  FROM public.competition_ai_generation_requests r

  WHERE r.id =
    v_dispatch.competition_generation_request_id;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Competition AI generation request not found.';

  END IF;


  IF v_request.human_approval_required = true
     AND v_request.human_approval_received = false THEN

    RAISE EXCEPTION
      'Generation request requires human approval.';

  END IF;


  IF v_request.status NOT IN (
    'approved',
    'queued'
  ) THEN

    RAISE EXCEPTION
      'Generation request is not approved for factory processing.';

  END IF;


  -- =======================================================
  -- PROFILE
  -- =======================================================

  SELECT *
  INTO v_profile

  FROM public.competition_pool_profiles p

  WHERE p.id =
    v_dispatch.profile_id;


  IF NOT FOUND THEN

    RAISE EXCEPTION
      'Competition pool profile not found.';

  END IF;


  -- =======================================================
  -- WORKFLOW
  --
  -- Önce tercih edilen workflow_code aranır.
  -- Bulunamazsa aktif question_generation workflow'una düşer.
  -- =======================================================

  SELECT w.id
  INTO v_workflow_id

  FROM public.ai_workflows w

  WHERE w.workflow_code = 'ai_question_generation'
    AND w.is_active = true

  LIMIT 1;


  IF v_workflow_id IS NULL THEN

    SELECT w.id
    INTO v_workflow_id

    FROM public.ai_workflows w

    WHERE w.workflow_type = 'question_generation'
      AND w.is_active = true

    ORDER BY w.created_at ASC

    LIMIT 1;

  END IF;


  IF v_workflow_id IS NULL THEN

    RAISE EXCEPTION
      'Active AI question generation workflow not found.';

  END IF;


  -- =======================================================
  -- DIFFICULTY
  --
  -- ai_generation_specs sadece:
  -- easy / medium / hard destekliyor.
  --
  -- mixed ise NULL bırakılır ve constraints içinde korunur.
  -- =======================================================

  IF v_profile.difficulty IN (
    'easy',
    'medium',
    'hard'
  ) THEN

    v_spec_difficulty :=
      v_profile.difficulty;

  ELSE

    v_spec_difficulty := NULL;

  END IF;


  -- =======================================================
  -- COGNITIVE TYPE
  --
  -- Eski ai_generation_specs enum'uyla uyumluysa doğrudan
  -- yazılır. Daha gelişmiş değer constraints içinde korunur.
  -- =======================================================

  IF lower(
       COALESCE(
         v_profile.cognitive_level,
         ''
       )
     ) IN (
       'learning',
       'comprehension',
       'application'
     )
  THEN

    v_spec_cognitive :=
      lower(v_profile.cognitive_level);

  ELSE

    v_spec_cognitive := NULL;

  END IF;


  -- =======================================================
  -- SÜRE
  -- =======================================================

  IF v_profile.min_solve_time_seconds IS NOT NULL
     AND v_profile.min_solve_time_seconds > 0 THEN

    v_min_time :=
      CEIL(
        v_profile.min_solve_time_seconds
      )::integer;

  ELSE

    v_min_time := NULL;

  END IF;


  IF v_profile.max_solve_time_seconds IS NOT NULL
     AND v_profile.max_solve_time_seconds > 0 THEN

    v_max_time :=
      CEIL(
        v_profile.max_solve_time_seconds
      )::integer;

  ELSE

    v_max_time := NULL;

  END IF;


  -- =======================================================
  -- CONSTRAINT SNAPSHOT
  -- =======================================================

  v_constraints :=
    jsonb_build_object(

      'origin',
      'competition_pool_demand',

      'competition_generation_request_id',
      v_request.id,

      'competition_factory_dispatch_id',
      v_dispatch.id,

      'competition_pool_profile_id',
      v_profile.id,

      'profile_code',
      v_profile.profile_code,

      'requested_question_count',
      v_dispatch.requested_question_count,

      'curriculum',
      v_dispatch.curriculum_requirements,

      'solve_time',
      v_dispatch.solve_time_requirements,

      'quality',
      v_dispatch.quality_requirements,

      'diversity',
      v_dispatch.diversity_requirements,

      'copyright',
      v_dispatch.copyright_requirements,

      'reviews',
      v_dispatch.review_requirements,

      'original_profile_cognitive_level',
      v_profile.cognitive_level,

      'original_profile_difficulty',
      v_profile.difficulty,

      'requires_visual',
      v_profile.requires_visual,

      'requires_graph',
      v_profile.requires_graph,

      'requires_table',
      v_profile.requires_table,

      'requires_diagram',
      v_profile.requires_diagram,

      'reading_load',
      v_profile.reading_load,

      'reasoning_load',
      v_profile.reasoning_load,

      'calculation_load',
      v_profile.calculation_load,

      'visual_load',
      v_profile.visual_load,

      'automatic_publication_allowed',
      false,

      'human_final_approval_required',
      true
    );


  -- =======================================================
  -- GENERATION INSTRUCTIONS
  -- =======================================================

  v_generation_instructions :=
    concat_ws(
      E'\n',

      'Altın Kalemler yarışma soru havuzu için özgün soru üret.',

      'Üretilecek soru adedi: '
        || v_dispatch.requested_question_count::text,

      'Sınıf: '
        || v_profile.grade_level::text,

      'Ders ID: '
        || v_profile.subject_id::text,

      CASE
        WHEN v_profile.topic_id IS NOT NULL
        THEN
          'Konu ID: '
          || v_profile.topic_id::text
      END,

      CASE
        WHEN v_profile.subtopic_id IS NOT NULL
        THEN
          'Alt konu ID: '
          || v_profile.subtopic_id::text
      END,

      CASE
        WHEN v_profile.outcome_id IS NOT NULL
        THEN
          'Kazanım ID: '
          || v_profile.outcome_id::text
      END,

      CASE
        WHEN v_profile.difficulty IS NOT NULL
        THEN
          'Zorluk: '
          || v_profile.difficulty
      END,

      CASE
        WHEN v_profile.question_type IS NOT NULL
        THEN
          'Soru tipi: '
          || v_profile.question_type
      END,

      CASE
        WHEN v_profile.cognitive_level IS NOT NULL
        THEN
          'Bilişsel seviye: '
          || v_profile.cognitive_level
      END,

      CASE
        WHEN v_min_time IS NOT NULL
             OR v_max_time IS NOT NULL
        THEN
          'Her soru için ayrı çözüm süresi profili oluşturulmalıdır.'
      END,

      'Her soru için cevap doğrulaması zorunludur.',

      'Sınıf, konu, alt konu, kazanım ve ön koşul uygunluğu bağımsız olarak denetlenmelidir.',

      'Her soru için okuma, muhakeme, görsel inceleme ve işlem süresi ayrı değerlendirilmelidir.',

      'Mevcut soruların metnini, sayılarını veya yapısını basitçe değiştirerek yeniden üretmek yasaktır.',

      'Metin, semantik, yapı ve çözüm yolu benzerliği kontrol edilmelidir.',

      'Telif ve özgünlük incelemesi zorunludur.',

      'İkinci bağımsız AI incelemesi zorunludur.',

      'AI çıktıları sadece staging alanına yazılmalıdır.',

      'Production soru bankasına otomatik yayın kesinlikle yasaktır.'
    );


  -- =======================================================
  -- GENERATION SPEC
  --
  -- Eğer 030'dan daha önce spec bağlandıysa onu kullan.
  -- =======================================================

  IF v_existing_spec_id IS NULL THEN

    INSERT INTO public.ai_generation_specs (
      curriculum_version_id,

      grade_level,

      subject_id,

      topic_id,

      subtopic_id,

      desired_count,

      difficulty,

      cognitive_type,

      primary_question_type,

      secondary_question_type,

      is_new_generation,

      min_solve_time_seconds,

      max_solve_time_seconds,

      generation_instructions,

      constraints,

      status,

      created_by,

      competition_generation_request_id,

      competition_factory_dispatch_id
    )

    VALUES (
      v_profile.curriculum_version_id,

      v_profile.grade_level,

      v_profile.subject_id,

      v_profile.topic_id,

      v_profile.subtopic_id,

      v_dispatch.requested_question_count,

      v_spec_difficulty,

      v_spec_cognitive,

      v_profile.question_type,

      NULL,

      v_profile.new_generation_required,

      v_min_time,

      v_max_time,

      v_generation_instructions,

      v_constraints,

      'ready',

      v_user_id,

      v_request.id,

      v_dispatch.id
    )

    RETURNING id
    INTO v_spec_id;


    UPDATE public.competition_ai_factory_dispatches
    SET
      generation_spec_id =
        v_spec_id,

      status =
        'spec_created'

    WHERE id = p_dispatch_id;


    UPDATE public.competition_ai_generation_requests
    SET
      generation_spec_id =
        v_spec_id

    WHERE id = v_request.id;

  ELSE

    v_spec_id :=
      v_existing_spec_id;

  END IF;


  -- =======================================================
  -- AI JOB
  --
  -- Henüz herhangi bir provider/model çağrısı yapılmaz.
  -- Job sadece kuyruğa hazırlanır.
  -- =======================================================

  IF v_existing_job_id IS NULL THEN

    INSERT INTO public.ai_jobs (
      workflow_id,

      job_type,

      status,

      generation_spec_id,

      input_data,

      attempt_count,

      max_attempts,

      competition_generation_request_id,

      competition_factory_dispatch_id
    )

    VALUES (
      v_workflow_id,

      'question_generation',

      'queued',

      v_spec_id,

      jsonb_build_object(

        'origin',
        'competition_pool_demand',

        'dispatch_id',
        v_dispatch.id,

        'dispatch_code',
        v_dispatch.dispatch_code,

        'generation_request_id',
        v_request.id,

        'request_code',
        v_request.request_code,

        'generation_spec_id',
        v_spec_id,

        'requested_question_count',
        v_dispatch.requested_question_count,

        'generation_requirements',
        v_dispatch.generation_requirements,

        'curriculum_requirements',
        v_dispatch.curriculum_requirements,

        'solve_time_requirements',
        v_dispatch.solve_time_requirements,

        'quality_requirements',
        v_dispatch.quality_requirements,

        'diversity_requirements',
        v_dispatch.diversity_requirements,

        'copyright_requirements',
        v_dispatch.copyright_requirements,

        'review_requirements',
        v_dispatch.review_requirements,

        'production_publication_allowed',
        false
      ),

      0,

      3,

      v_request.id,

      v_dispatch.id
    )

    RETURNING id
    INTO v_job_id;


    UPDATE public.competition_ai_factory_dispatches
    SET
      ai_job_id =
        v_job_id,

      status =
        'job_created'

    WHERE id = p_dispatch_id;


    UPDATE public.competition_ai_generation_requests
    SET
      ai_job_id =
        v_job_id,

      status =
        'queued'

    WHERE id = v_request.id;

  ELSE

    v_job_id :=
      v_existing_job_id;

  END IF;


  -- =======================================================
  -- SONUÇ
  -- =======================================================

  RETURN jsonb_build_object(

    'status',
    'job_created',

    'dispatch_id',
    p_dispatch_id,

    'generation_request_id',
    v_request.id,

    'generation_spec_id',
    v_spec_id,

    'ai_job_id',
    v_job_id,

    'requested_question_count',
    v_dispatch.requested_question_count,

    'automatic_publication',
    false,

    'next_stage',
    'AI worker may process the queued job and write candidates only to ai_question_staging.'
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.build_competition_ai_factory_job(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.build_competition_ai_factory_job(uuid)
TO authenticated, service_role;


-- =========================================================
-- 5. PUBLIC ADMIN RPC
--
-- Güçlü implementation private şemada.
-- =========================================================

CREATE OR REPLACE FUNCTION public.build_competition_ai_factory_job(
  p_dispatch_id uuid
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.build_competition_ai_factory_job(
    p_dispatch_id
  );
$$;


REVOKE ALL
ON FUNCTION public.build_competition_ai_factory_job(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.build_competition_ai_factory_job(uuid)
TO authenticated, service_role;


-- =========================================================
-- 6. JOB / DISPATCH DURUM RAPORU
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_competition_ai_factory_job_status(
  p_dispatch_id uuid
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
      'ai.manage'
    )
    OR
    public.current_user_has_admin_permission(
      'questions.approve'
    )
    OR
    public.current_user_has_admin_permission(
      'questions.edit'
    )
  ) THEN

    RAISE EXCEPTION
      'Admin permission required.';

  END IF;


  SELECT jsonb_build_object(

    'dispatch_id',
    d.id,

    'dispatch_code',
    d.dispatch_code,

    'dispatch_status',
    d.status,

    'requested_question_count',
    d.requested_question_count,

    'generation_spec_id',
    d.generation_spec_id,

    'generation_spec_status',
    s.status,

    'ai_job_id',
    d.ai_job_id,

    'ai_job_status',
    j.status,

    'attempt_count',
    j.attempt_count,

    'max_attempts',
    j.max_attempts,

    'generated_count',
    d.generated_count,

    'staging_count',
    d.staging_count,

    'approved_count',
    d.approved_count,

    'rejected_count',
    d.rejected_count,

    'copyright_blocked_count',
    d.copyright_blocked_count,

    'solve_time_rejected_count',
    d.solve_time_rejected_count,

    'curriculum_rejected_count',
    d.curriculum_rejected_count,

    'human_approved',
    d.human_approved,

    'automatic_publication_allowed',
    d.automatic_publication_allowed,

    'created_at',
    d.created_at,

    'updated_at',
    d.updated_at

  )

  INTO v_result

  FROM public.competition_ai_factory_dispatches d

  LEFT JOIN public.ai_generation_specs s
    ON s.id =
       d.generation_spec_id

  LEFT JOIN public.ai_jobs j
    ON j.id =
       d.ai_job_id

  WHERE d.id =
    p_dispatch_id;


  IF v_result IS NULL THEN

    RAISE EXCEPTION
      'Competition AI factory dispatch not found.';

  END IF;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_competition_ai_factory_job_status(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_competition_ai_factory_job_status(uuid)
TO authenticated, service_role;


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