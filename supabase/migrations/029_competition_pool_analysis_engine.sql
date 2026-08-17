-- 029_competition_pool_analysis_engine.sql
-- Altın Kalemler
--
-- Deterministik yarışma soru havuzu analiz motoru.
--
-- 028'de tanımlanan profile göre gerçek soru havuzunu tarar.
--
-- Analiz:
-- - sınıf
-- - ders
-- - konu / alt konu / kazanım
-- - zorluk
-- - soru tipi
-- - bilişsel seviye
-- - yeni nesil
-- - görsel / grafik / tablo / diyagram
-- - okuma / muhakeme / işlem yükü
-- - soru bazlı çözüm süresi
-- - onay / aktiflik
-- - scoring-ready durumu
-- - son kullanım sıklığı
-- - aşırı kullanılan sorular
-- - telif riski
--
-- Eksik varsa AI üretim talebi "planned" oluşturulur.
-- AI hiçbir şekilde doğrudan production'a soru yayınlayamaz.

BEGIN;


-- =========================================================
-- 1. INTERNAL: ADMIN YETKİ KONTROLÜ
-- =========================================================

CREATE OR REPLACE FUNCTION private.require_pool_analysis_permission()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION
      'Authentication required.';
  END IF;


  IF NOT (
    private.current_user_has_admin_permission(
      'questions.edit'
    )
    OR
    private.current_user_has_admin_permission(
      'ai.manage'
    )
    OR
    private.current_user_has_admin_permission(
      'questions.approve'
    )
  ) THEN

    RAISE EXCEPTION
      'You do not have permission to run competition pool analysis.';

  END IF;

END;
$$;


REVOKE ALL
ON FUNCTION private.require_pool_analysis_permission()
FROM PUBLIC, anon, authenticated;


GRANT EXECUTE
ON FUNCTION private.require_pool_analysis_permission()
TO service_role;


-- =========================================================
-- 2. INTERNAL:
-- SORUNUN APPROVED + ACTIVE OLDUĞUNU BELİRLE
--
-- questions tablosunda zaman içerisinde alan isimleri
-- değişebilirse diye to_jsonb üzerinden güvenli fallback
-- kullanıyoruz.
-- =========================================================

CREATE OR REPLACE FUNCTION private.question_is_approved_active(
  p_question jsonb
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_approved boolean := false;
  v_active boolean := false;

  v_approval_text text;
  v_active_text text;
BEGIN

  v_approval_text :=
    lower(
      COALESCE(
        p_question ->> 'approval_status',
        p_question ->> 'status',
        p_question ->> 'is_approved',
        p_question ->> 'approved',
        ''
      )
    );


  v_active_text :=
    lower(
      COALESCE(
        p_question ->> 'is_active',
        p_question ->> 'active',
        ''
      )
    );


  v_approved :=
    v_approval_text IN (
      'approved',
      'true',
      't',
      '1',
      'yes'
    );


  v_active :=
    v_active_text IN (
      'active',
      'true',
      't',
      '1',
      'yes'
    );


  RETURN v_approved AND v_active;

END;
$$;


REVOKE ALL
ON FUNCTION private.question_is_approved_active(jsonb)
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 3. INTERNAL:
-- SORU / PROFILE EŞLEŞMESİ
--
-- Curriculum mapping varsa onu da kontrol eder.
-- =========================================================

CREATE OR REPLACE FUNCTION private.question_matches_competition_profile(
  p_question_id uuid,
  p_profile_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_q jsonb;
  v_p public.competition_pool_profiles%ROWTYPE;

  v_grade text;
  v_subject text;

  v_difficulty text;
  v_question_type text;
  v_cognitive text;

  v_new_generation text;

  v_time_profile public.question_solve_time_profiles%ROWTYPE;

  v_curriculum_match boolean := true;
BEGIN

  SELECT to_jsonb(q)
  INTO v_q
  FROM public.questions q
  WHERE q.id = p_question_id;


  IF v_q IS NULL THEN
    RETURN false;
  END IF;


  SELECT *
  INTO v_p
  FROM public.competition_pool_profiles p
  WHERE p.id = p_profile_id
    AND p.is_active = true;


  IF NOT FOUND THEN
    RETURN false;
  END IF;


  -- -------------------------------------------------------
  -- Sınıf
  -- -------------------------------------------------------

  v_grade :=
    COALESCE(
      v_q ->> 'grade_level',
      v_q ->> 'grade'
    );


  IF v_grade IS NULL
     OR v_grade <> v_p.grade_level::text THEN
    RETURN false;
  END IF;


  -- -------------------------------------------------------
  -- Ders
  -- -------------------------------------------------------

  v_subject :=
    v_q ->> 'subject_id';


  IF v_subject IS NULL
     OR v_subject <> v_p.subject_id::text THEN
    RETURN false;
  END IF;


  -- -------------------------------------------------------
  -- Zorluk
  -- -------------------------------------------------------

  IF v_p.difficulty IS NOT NULL
     AND v_p.difficulty <> 'mixed' THEN

    v_difficulty :=
      lower(
        COALESCE(
          v_q ->> 'difficulty',
          v_q ->> 'difficulty_level',
          ''
        )
      );


    IF v_difficulty <> lower(v_p.difficulty) THEN
      RETURN false;
    END IF;

  END IF;


  -- -------------------------------------------------------
  -- Soru tipi
  -- -------------------------------------------------------

  IF v_p.question_type IS NOT NULL THEN

    v_question_type :=
      lower(
        COALESCE(
          v_q ->> 'question_type',
          v_q ->> 'type',
          ''
        )
      );


    IF v_question_type <> lower(v_p.question_type) THEN
      RETURN false;
    END IF;

  END IF;


  -- -------------------------------------------------------
  -- Bilişsel seviye
  -- -------------------------------------------------------

  IF v_p.cognitive_level IS NOT NULL THEN

    v_cognitive :=
      lower(
        COALESCE(
          v_q ->> 'cognitive_level',
          v_q ->> 'cognitive_type',
          ''
        )
      );


    IF v_cognitive <> lower(v_p.cognitive_level) THEN
      RETURN false;
    END IF;

  END IF;


  -- -------------------------------------------------------
  -- Yeni nesil
  -- -------------------------------------------------------

  IF v_p.new_generation_required IS NOT NULL THEN

    v_new_generation :=
      lower(
        COALESCE(
          v_q ->> 'is_new_generation',
          v_q ->> 'new_generation',
          'false'
        )
      );


    IF v_p.new_generation_required = true
       AND v_new_generation NOT IN (
         'true',
         't',
         '1',
         'yes'
       ) THEN

      RETURN false;

    END IF;


    IF v_p.new_generation_required = false
       AND v_new_generation IN (
         'true',
         't',
         '1',
         'yes'
       ) THEN

      RETURN false;

    END IF;

  END IF;


  -- =======================================================
  -- CURRICULUM EŞLEŞMESİ
  --
  -- Önce question json içindeki id'lere bakar.
  -- Yetmezse question_curriculum_mappings tablosuna bakar.
  -- =======================================================

  IF v_p.topic_id IS NOT NULL
     OR v_p.subtopic_id IS NOT NULL
     OR v_p.outcome_id IS NOT NULL
  THEN

    v_curriculum_match := false;


    -- -----------------------------------------------------
    -- Questions tablosunda doğrudan taxonomy varsa.
    -- -----------------------------------------------------

    IF (
      v_p.topic_id IS NULL
      OR v_q ->> 'topic_id' = v_p.topic_id::text
    )
    AND (
      v_p.subtopic_id IS NULL
      OR v_q ->> 'subtopic_id' = v_p.subtopic_id::text
    )
    AND (
      v_p.outcome_id IS NULL
      OR v_q ->> 'outcome_id' = v_p.outcome_id::text
    )
    THEN

      v_curriculum_match := true;

    END IF;


    -- -----------------------------------------------------
    -- Mapping tablosu fallback.
    -- -----------------------------------------------------

    IF v_curriculum_match = false THEN

      SELECT EXISTS (
        SELECT 1

        FROM public.question_curriculum_mappings m

        WHERE m.question_id = p_question_id

          AND (
            v_p.topic_id IS NULL
            OR to_jsonb(m) ->> 'topic_id'
               = v_p.topic_id::text
          )

          AND (
            v_p.subtopic_id IS NULL
            OR to_jsonb(m) ->> 'subtopic_id'
               = v_p.subtopic_id::text
          )

          AND (
            v_p.outcome_id IS NULL
            OR to_jsonb(m) ->> 'outcome_id'
               = v_p.outcome_id::text
          )
      )

      INTO v_curriculum_match;

    END IF;


    IF v_curriculum_match = false THEN
      RETURN false;
    END IF;

  END IF;


  -- =======================================================
  -- SÜRE PROFİLİ / YÜKLER
  --
  -- Profile bu alanlardan herhangi birini istiyorsa
  -- current solve-time profili zorunludur.
  -- =======================================================

  IF v_p.min_solve_time_seconds IS NOT NULL
     OR v_p.max_solve_time_seconds IS NOT NULL
     OR v_p.reading_load IS NOT NULL
     OR v_p.reasoning_load IS NOT NULL
     OR v_p.calculation_load IS NOT NULL
     OR v_p.visual_load IS NOT NULL
     OR v_p.requires_visual IS NOT NULL
     OR v_p.requires_graph IS NOT NULL
     OR v_p.requires_table IS NOT NULL
     OR v_p.requires_diagram IS NOT NULL
  THEN

    SELECT *
    INTO v_time_profile

    FROM public.question_solve_time_profiles stp

    WHERE stp.question_id = p_question_id
      AND stp.is_current = true

    ORDER BY stp.analysis_version DESC
    LIMIT 1;


    IF NOT FOUND THEN
      RETURN false;
    END IF;


    -- -----------------------------------------------------
    -- Çözüm süresi
    -- -----------------------------------------------------

    IF v_p.min_solve_time_seconds IS NOT NULL
       AND v_time_profile.estimated_total_time_seconds
           < v_p.min_solve_time_seconds THEN

      RETURN false;

    END IF;


    IF v_p.max_solve_time_seconds IS NOT NULL
       AND v_time_profile.estimated_total_time_seconds
           > v_p.max_solve_time_seconds THEN

      RETURN false;

    END IF;


    -- -----------------------------------------------------
    -- Yükler
    -- -----------------------------------------------------

    IF v_p.reading_load IS NOT NULL
       AND v_time_profile.reading_load
           IS DISTINCT FROM v_p.reading_load THEN

      RETURN false;

    END IF;


    IF v_p.reasoning_load IS NOT NULL
       AND v_time_profile.reasoning_load
           IS DISTINCT FROM v_p.reasoning_load THEN

      RETURN false;

    END IF;


    IF v_p.calculation_load IS NOT NULL
       AND v_time_profile.calculation_load
           IS DISTINCT FROM v_p.calculation_load THEN

      RETURN false;

    END IF;


    IF v_p.visual_load IS NOT NULL
       AND v_time_profile.visual_load
           IS DISTINCT FROM v_p.visual_load THEN

      RETURN false;

    END IF;


    -- -----------------------------------------------------
    -- Görsel özellikler
    -- -----------------------------------------------------

    IF v_p.requires_visual = true
       AND v_time_profile.visual_count <= 0
    THEN
      RETURN false;
    END IF;


    IF v_p.requires_graph = true
       AND v_time_profile.graph_count <= 0
    THEN
      RETURN false;
    END IF;


    IF v_p.requires_table = true
       AND v_time_profile.table_count <= 0
    THEN
      RETURN false;
    END IF;


    IF v_p.requires_diagram = true
       AND v_time_profile.diagram_count <= 0
    THEN
      RETURN false;
    END IF;

  END IF;


  RETURN true;

END;
$$;


REVOKE ALL
ON FUNCTION private.question_matches_competition_profile(uuid, uuid)
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 4. INTERNAL:
-- COPYRIGHT BLOCK KONTROLÜ
--
-- Review tablolarının farklı sürümleriyle uyumlu olması için
-- JSON üzerinden risk/status kontrolleri yapıyoruz.
-- =========================================================

CREATE OR REPLACE FUNCTION private.question_has_copyright_block(
  p_question_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_blocked boolean := false;
BEGIN

  -- -------------------------------------------------------
  -- Commercial clearance
  -- -------------------------------------------------------

  SELECT EXISTS (
    SELECT 1

    FROM public.commercial_question_clearance c

    WHERE
      to_jsonb(c) ->> 'question_id'
        = p_question_id::text

      AND (
        lower(
          COALESCE(
            to_jsonb(c) ->> 'status',
            to_jsonb(c) ->> 'decision',
            ''
          )
        ) IN (
          'blocked',
          'rejected',
          'failed',
          'denied'
        )

        OR lower(
          COALESCE(
            to_jsonb(c) ->> 'commercially_cleared',
            to_jsonb(c) ->> 'is_cleared',
            ''
          )
        ) IN (
          'false',
          'f',
          '0',
          'no'
        )
      )
  )
  INTO v_blocked;


  IF v_blocked THEN
    RETURN true;
  END IF;


  -- -------------------------------------------------------
  -- Copyright reviews
  -- -------------------------------------------------------

  SELECT EXISTS (
    SELECT 1

    FROM public.copyright_reviews cr

    WHERE
      to_jsonb(cr) ->> 'question_id'
        = p_question_id::text

      AND lower(
        COALESCE(
          to_jsonb(cr) ->> 'status',
          to_jsonb(cr) ->> 'decision',
          to_jsonb(cr) ->> 'risk_level',
          ''
        )
      ) IN (
        'blocked',
        'rejected',
        'high',
        'critical',
        'high_risk'
      )
  )
  INTO v_blocked;


  RETURN COALESCE(v_blocked, false);

END;
$$;


REVOKE ALL
ON FUNCTION private.question_has_copyright_block(uuid)
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 5. INTERNAL:
-- TEK PROFİLİN TAM ANALİZİ
-- =========================================================

CREATE OR REPLACE FUNCTION private.analyze_competition_pool_profile(
  p_analysis_run_id uuid,
  p_profile_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_profile public.competition_pool_profiles%ROWTYPE;

  v_question record;

  v_total integer := 0;
  v_approved integer := 0;
  v_time_profile integer := 0;
  v_scoring_ready integer := 0;

  v_overused integer := 0;
  v_diversity_rejected integer := 0;
  v_quality_rejected integer := 0;
  v_copyright_blocked integer := 0;

  v_usable integer := 0;

  v_usage_count integer;

  v_has_current_time boolean;
  v_is_scoring_ready boolean;
  v_is_copyright_blocked boolean;

  v_gap jsonb;

  v_buffer_target integer;
  v_missing integer;
  v_status text;
  v_urgency numeric;

  v_gap_item_id uuid;

  v_generation_recommendation jsonb;

  v_request_code text;
BEGIN

  SELECT *
  INTO v_profile
  FROM public.competition_pool_profiles p
  WHERE p.id = p_profile_id
    AND p.is_active = true;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Competition pool profile not found.';
  END IF;


  -- =======================================================
  -- SORU HAVUZUNU TARA
  -- =======================================================

  FOR v_question IN

    SELECT
      q.id,
      to_jsonb(q) AS question_json

    FROM public.questions q

  LOOP

    -- -----------------------------------------------------
    -- Profile eşleşiyor mu?
    -- -----------------------------------------------------

    IF NOT private.question_matches_competition_profile(
      v_question.id,
      p_profile_id
    ) THEN

      CONTINUE;

    END IF;


    v_total := v_total + 1;


    -- -----------------------------------------------------
    -- Approved + active
    -- -----------------------------------------------------

    IF NOT private.question_is_approved_active(
      v_question.question_json
    ) THEN

      CONTINUE;

    END IF;


    v_approved := v_approved + 1;


    -- -----------------------------------------------------
    -- Current solve time profile
    -- -----------------------------------------------------

    SELECT EXISTS (
      SELECT 1

      FROM public.question_solve_time_profiles stp

      WHERE stp.question_id = v_question.id
        AND stp.is_current = true
    )

    INTO v_has_current_time;


    IF v_has_current_time THEN
      v_time_profile := v_time_profile + 1;
    END IF;


    -- -----------------------------------------------------
    -- Scoring ready
    --
    -- Onaylı current profile +
    -- aktif question-specific scoring band.
    -- -----------------------------------------------------

    SELECT EXISTS (
      SELECT 1

      FROM public.question_solve_time_profiles stp

      WHERE stp.question_id = v_question.id
        AND stp.is_current = true
        AND stp.is_approved_for_scoring = true

        AND EXISTS (
          SELECT 1

          FROM public.question_scoring_time_bands stb

          WHERE stb.question_id = v_question.id
            AND stb.solve_time_profile_id = stp.id
            AND stb.is_active = true
        )
    )

    INTO v_is_scoring_ready;


    IF v_is_scoring_ready THEN
      v_scoring_ready := v_scoring_ready + 1;
    END IF;


    -- -----------------------------------------------------
    -- Copyright block
    -- -----------------------------------------------------

    v_is_copyright_blocked :=
      private.question_has_copyright_block(
        v_question.id
      );


    IF v_is_copyright_blocked THEN

      v_copyright_blocked :=
        v_copyright_blocked + 1;

      CONTINUE;

    END IF;


    -- -----------------------------------------------------
    -- Son N gündeki kullanım.
    --
    -- competition_questions.created_at üzerinden gerçek
    -- deterministic kullanım sayılır.
    -- -----------------------------------------------------

    SELECT COUNT(*)
    INTO v_usage_count

    FROM public.competition_questions cq

    WHERE cq.question_id = v_question.id

      AND cq.created_at >=
        now()
        - make_interval(
            days => v_profile.usage_window_days
          );


    IF v_usage_count >
       v_profile.max_uses_per_window THEN

      v_overused :=
        v_overused + 1;

      CONTINUE;

    END IF;


    -- -----------------------------------------------------
    -- Yarışma için kullanılabilir kabul edilmesi için
    -- scoring-ready olması zorunlu.
    -- -----------------------------------------------------

    IF NOT v_is_scoring_ready THEN
      CONTINUE;
    END IF;


    -- -----------------------------------------------------
    -- Şimdilik deterministic diversity/quality sayaçları
    -- 0 kalabilir.
    --
    -- İleride similarity cluster ve Question Health Score
    -- ile bunları ayrıca dolduracağız.
    -- -----------------------------------------------------


    v_usable := v_usable + 1;

  END LOOP;


  -- =======================================================
  -- GAP HESABI
  -- =======================================================

  v_gap :=
    public.calculate_competition_pool_gap_status(
      v_usable,
      v_profile.target_question_count,
      v_profile.minimum_safe_count,
      v_profile.preferred_buffer_percent
    );


  v_buffer_target :=
    (v_gap ->> 'buffer_target_count')::integer;


  v_missing :=
    (v_gap ->> 'missing_question_count')::integer;


  v_status :=
    v_gap ->> 'gap_status';


  v_urgency :=
    (v_gap ->> 'urgency_score')::numeric;


  -- =======================================================
  -- GAP ITEM
  -- =======================================================

  INSERT INTO public.competition_pool_gap_items (
    analysis_run_id,
    profile_id,

    total_matching_questions,
    approved_active_questions,
    questions_with_time_profile,
    scoring_ready_questions,

    overused_questions,
    diversity_rejected_questions,
    quality_rejected_questions,
    copyright_blocked_questions,

    usable_question_count,

    target_question_count,
    buffer_target_count,
    missing_question_count,

    gap_status,
    urgency_score,

    usage_analysis,
    diversity_analysis,
    time_profile_analysis,
    quality_analysis,
    copyright_analysis,

    recommendation,

    calculated_at
  )

  VALUES (
    p_analysis_run_id,
    p_profile_id,

    v_total,
    v_approved,
    v_time_profile,
    v_scoring_ready,

    v_overused,
    v_diversity_rejected,
    v_quality_rejected,
    v_copyright_blocked,

    v_usable,

    v_profile.target_question_count,
    v_buffer_target,
    v_missing,

    v_status,
    v_urgency,

    jsonb_build_object(
      'window_days',
      v_profile.usage_window_days,

      'max_uses_per_window',
      v_profile.max_uses_per_window,

      'overused_question_count',
      v_overused
    ),

    jsonb_build_object(
      'status',
      'foundation_ready',

      'note',
      'Similarity-cluster diversity scoring will be added in a later analysis layer.'
    ),

    jsonb_build_object(
      'questions_with_time_profile',
      v_time_profile,

      'scoring_ready_questions',
      v_scoring_ready
    ),

    jsonb_build_object(
      'deterministic_quality_rejected',
      v_quality_rejected
    ),

    jsonb_build_object(
      'copyright_blocked_questions',
      v_copyright_blocked
    ),

    jsonb_build_object(
      'action',
      CASE
        WHEN v_missing > 0
          THEN 'generate_more_questions'
        ELSE 'no_generation_required'
      END,

      'requested_new_questions',
      v_missing
    ),

    now()
  )

  ON CONFLICT (
    analysis_run_id,
    profile_id
  )

  DO UPDATE SET

    total_matching_questions =
      EXCLUDED.total_matching_questions,

    approved_active_questions =
      EXCLUDED.approved_active_questions,

    questions_with_time_profile =
      EXCLUDED.questions_with_time_profile,

    scoring_ready_questions =
      EXCLUDED.scoring_ready_questions,

    overused_questions =
      EXCLUDED.overused_questions,

    diversity_rejected_questions =
      EXCLUDED.diversity_rejected_questions,

    quality_rejected_questions =
      EXCLUDED.quality_rejected_questions,

    copyright_blocked_questions =
      EXCLUDED.copyright_blocked_questions,

    usable_question_count =
      EXCLUDED.usable_question_count,

    target_question_count =
      EXCLUDED.target_question_count,

    buffer_target_count =
      EXCLUDED.buffer_target_count,

    missing_question_count =
      EXCLUDED.missing_question_count,

    gap_status =
      EXCLUDED.gap_status,

    urgency_score =
      EXCLUDED.urgency_score,

    usage_analysis =
      EXCLUDED.usage_analysis,

    diversity_analysis =
      EXCLUDED.diversity_analysis,

    time_profile_analysis =
      EXCLUDED.time_profile_analysis,

    quality_analysis =
      EXCLUDED.quality_analysis,

    copyright_analysis =
      EXCLUDED.copyright_analysis,

    recommendation =
      EXCLUDED.recommendation,

    calculated_at =
      EXCLUDED.calculated_at

  RETURNING id
  INTO v_gap_item_id;


  -- =======================================================
  -- AI GENERATION PLAN
  --
  -- Eksik varsa sadece PLANNED kayıt oluştur.
  -- AI job otomatik başlatılmaz.
  -- =======================================================

  IF v_missing > 0 THEN

    v_generation_recommendation :=
      public.build_competition_generation_recommendation(
        v_gap_item_id
      );


    -- Aynı gap item için açık talep varsa tekrar üretme.
    IF NOT EXISTS (
      SELECT 1

      FROM public.competition_ai_generation_requests r

      WHERE r.gap_item_id = v_gap_item_id

        AND r.status IN (
          'planned',
          'approved',
          'queued',
          'generating',
          'reviewing',
          'partially_completed'
        )
    ) THEN

      v_request_code :=
        'CPGR-'
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


      INSERT INTO public.competition_ai_generation_requests (
        request_code,

        analysis_run_id,
        gap_item_id,
        profile_id,

        requested_question_count,

        generation_requirements,

        quality_requirements,

        solve_time_requirements,

        diversity_requirements,

        copyright_requirements,

        status,

        human_approval_required,
        human_approval_received,

        metadata
      )

      VALUES (
        v_request_code,

        p_analysis_run_id,
        v_gap_item_id,
        p_profile_id,

        v_missing,

        v_generation_recommendation,

        jsonb_build_object(
          'answer_validation_required',
          true,

          'grade_fit_required',
          true,

          'topic_fit_required',
          true,

          'subtopic_fit_required',
          true,

          'outcome_fit_required',
          true,

          'prerequisite_check_required',
          true,

          'independent_ai_review_required',
          true,

          'human_approval_required',
          true
        ),

        jsonb_build_object(
          'minimum_seconds',
          v_profile.min_solve_time_seconds,

          'maximum_seconds',
          v_profile.max_solve_time_seconds,

          'reading_load',
          v_profile.reading_load,

          'reasoning_load',
          v_profile.reasoning_load,

          'calculation_load',
          v_profile.calculation_load,

          'visual_load',
          v_profile.visual_load,

          'question_specific_solve_time_analysis_required',
          true,

          'independent_solve_time_review_required',
          true
        ),

        jsonb_build_object(
          'avoid_near_duplicates',
          true,

          'semantic_similarity_review_required',
          true,

          'structural_similarity_review_required',
          true,

          'solution_path_similarity_review_required',
          true,

          'profile_rules',
          v_profile.diversity_rules
        ),

        jsonb_build_object(
          'originality_review_required',
          true,

          'copyright_review_required',
          true,

          'commercial_clearance_required',
          true,

          'third_party_rewrite_not_allowed',
          true
        ),

        'planned',

        true,
        false,

        jsonb_build_object(
          'created_by',
          'deterministic_competition_pool_analysis',

          'urgency_score',
          v_urgency,

          'gap_status',
          v_status
        )
      );

    END IF;

  END IF;


  RETURN v_gap_item_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.analyze_competition_pool_profile(
  uuid,
  uuid
)
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 6. INTERNAL:
-- TAM ANALİZ ÇALIŞTIR
-- =========================================================

CREATE OR REPLACE FUNCTION private.run_competition_pool_analysis(
  p_run_type text DEFAULT 'full',
  p_grade_level smallint DEFAULT NULL,
  p_subject_id uuid DEFAULT NULL,
  p_profile_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_run_id uuid;
  v_run_code text;

  v_profile record;

  v_profile_count integer := 0;

  v_total_missing integer := 0;
  v_critical integer := 0;
  v_empty integer := 0;
  v_healthy integer := 0;
BEGIN

  PERFORM private.require_pool_analysis_permission();


  IF p_grade_level IS NOT NULL
     AND p_grade_level NOT BETWEEN 1 AND 12 THEN

    RAISE EXCEPTION
      'Grade level must be between 1 and 12.';

  END IF;


  v_run_code :=
    'CPAR-'
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


  INSERT INTO public.competition_pool_analysis_runs (
    run_code,

    run_type,

    status,

    requested_grade_level,

    requested_subject_id,

    requested_profile_id,

    started_at,

    created_by
  )

  VALUES (
    v_run_code,

    p_run_type,

    'running',

    p_grade_level,

    p_subject_id,

    p_profile_id,

    clock_timestamp(),

    auth.uid()
  )

  RETURNING id
  INTO v_run_id;


  BEGIN

    FOR v_profile IN

      SELECT p.id

      FROM public.competition_pool_profiles p

      WHERE p.is_active = true

        AND (
          p_grade_level IS NULL
          OR p.grade_level = p_grade_level
        )

        AND (
          p_subject_id IS NULL
          OR p.subject_id = p_subject_id
        )

        AND (
          p_profile_id IS NULL
          OR p.id = p_profile_id
        )

      ORDER BY
        p.priority DESC,
        p.grade_level,
        p.subject_id,
        p.profile_code

    LOOP

      PERFORM
        private.analyze_competition_pool_profile(
          v_run_id,
          v_profile.id
        );


      v_profile_count :=
        v_profile_count + 1;

    END LOOP;


    -- -----------------------------------------------------
    -- Run summary
    -- -----------------------------------------------------

    SELECT
      COALESCE(
        SUM(g.missing_question_count),
        0
      ),

      COUNT(*) FILTER (
        WHERE g.gap_status = 'critical'
      ),

      COUNT(*) FILTER (
        WHERE g.gap_status = 'empty'
      ),

      COUNT(*) FILTER (
        WHERE g.gap_status = 'healthy'
      )

    INTO
      v_total_missing,
      v_critical,
      v_empty,
      v_healthy

    FROM public.competition_pool_gap_items g

    WHERE g.analysis_run_id = v_run_id;


    UPDATE public.competition_pool_analysis_runs
    SET
      status = 'completed',

      completed_at =
        clock_timestamp(),

      summary =
        jsonb_build_object(
          'analyzed_profile_count',
          v_profile_count,

          'total_missing_questions',
          v_total_missing,

          'critical_profiles',
          v_critical,

          'empty_profiles',
          v_empty,

          'healthy_profiles',
          v_healthy
        )

    WHERE id = v_run_id;


  EXCEPTION
    WHEN OTHERS THEN

      UPDATE public.competition_pool_analysis_runs
      SET
        status = 'failed',

        completed_at =
          clock_timestamp(),

        error_data =
          jsonb_build_object(
            'sqlstate',
            SQLSTATE,

            'message',
            SQLERRM
          )

      WHERE id = v_run_id;


      RAISE;

  END;


  RETURN v_run_id;

END;
$$;


REVOKE ALL
ON FUNCTION private.run_competition_pool_analysis(
  text,
  smallint,
  uuid,
  uuid
)
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 7. PUBLIC ADMIN RPC
--
-- SECURITY INVOKER wrapper.
-- Güçlü implementation private şemada.
-- =========================================================

CREATE OR REPLACE FUNCTION public.run_competition_pool_analysis(
  p_run_type text DEFAULT 'full',
  p_grade_level smallint DEFAULT NULL,
  p_subject_id uuid DEFAULT NULL,
  p_profile_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.run_competition_pool_analysis(
    p_run_type,
    p_grade_level,
    p_subject_id,
    p_profile_id
  );
$$;


REVOKE ALL
ON FUNCTION public.run_competition_pool_analysis(
  text,
  smallint,
  uuid,
  uuid
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.run_competition_pool_analysis(
  text,
  smallint,
  uuid,
  uuid
)
TO authenticated, service_role;


-- Public wrapper'ın private implementation'a erişebilmesi
-- gerekir. private şema Data API'de exposed değildir.

GRANT EXECUTE
ON FUNCTION private.run_competition_pool_analysis(
  text,
  smallint,
  uuid,
  uuid
)
TO authenticated, service_role;


GRANT USAGE
ON SCHEMA private
TO authenticated, service_role;


-- =========================================================
-- 8. SON ANALİZ RAPORUNU OKUMA RPC
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_latest_competition_pool_report()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_run_id uuid;
  v_result jsonb;
BEGIN

  IF NOT (
    public.current_user_has_admin_permission(
      'questions.edit'
    )
    OR
    public.current_user_has_admin_permission(
      'ai.manage'
    )
    OR
    public.current_user_has_admin_permission(
      'questions.approve'
    )
  ) THEN

    RAISE EXCEPTION
      'Admin permission required.';

  END IF;


  SELECT r.id
  INTO v_run_id

  FROM public.competition_pool_analysis_runs r

  WHERE r.status = 'completed'

  ORDER BY r.completed_at DESC

  LIMIT 1;


  IF v_run_id IS NULL THEN

    RETURN jsonb_build_object(
      'status',
      'no_completed_analysis'
    );

  END IF;


  SELECT jsonb_build_object(

    'analysis_run',
    (
      SELECT to_jsonb(r)

      FROM public.competition_pool_analysis_runs r

      WHERE r.id = v_run_id
    ),

    'profiles',
    (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'profile_code',
            p.profile_code,

            'profile_name',
            p.name,

            'grade_level',
            p.grade_level,

            'subject_id',
            p.subject_id,

            'topic_id',
            p.topic_id,

            'subtopic_id',
            p.subtopic_id,

            'outcome_id',
            p.outcome_id,

            'difficulty',
            p.difficulty,

            'usable_question_count',
            g.usable_question_count,

            'target_question_count',
            g.target_question_count,

            'buffer_target_count',
            g.buffer_target_count,

            'missing_question_count',
            g.missing_question_count,

            'gap_status',
            g.gap_status,

            'urgency_score',
            g.urgency_score,

            'overused_questions',
            g.overused_questions,

            'copyright_blocked_questions',
            g.copyright_blocked_questions,

            'scoring_ready_questions',
            g.scoring_ready_questions
          )

          ORDER BY
            g.urgency_score DESC,
            p.grade_level,
            p.profile_code
        ),
        '[]'::jsonb
      )

      FROM public.competition_pool_gap_items g

      JOIN public.competition_pool_profiles p
        ON p.id = g.profile_id

      WHERE g.analysis_run_id = v_run_id
    )

  )

  INTO v_result;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_latest_competition_pool_report()
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_latest_competition_pool_report()
TO authenticated, service_role;


-- =========================================================
-- 9. PRIVATE DEFAULT SECURITY
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