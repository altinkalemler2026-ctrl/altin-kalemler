-- ============================================================
-- 126_faz24_admin_candidate_review_low_confidence.sql
-- Altın Kalemler — Faz 24: Admin candidate-review veri sözleşmesi
-- uzantısı (append-only).
--
-- Kapsam:
--   1. get_candidate_question_batch_detail(uuid) CREATE OR REPLACE:
--      preview alanına subject_name (subjects JOIN), outcome_code ve
--      low_confidence (staging metadata) eklenir. 120 davranışı birebir
--      korunur; ACL (revoke anon/public, grant authenticated/service_role)
--      ve fail-closed kapı aynıdır. Yalnız okuma: DML veri değiştirmez.
--   2. private.register_candidate_md_batch(jsonb) CREATE OR REPLACE:
--      124 davranışı birebir korunur; yalnız yeni paket kök zarfındaki
--      opsiyonel `low_confidence_candidates` (client_question_id dizisi)
--      okunur ve her adayın staging metadata'sına `low_confidence`
--      boolean'ı saklanır. Zarf yoksa / eşleşme yoksa false yazılır; eski
--      kayıtlar bu anahtarı TAŞIMAZ (RPC null döner → "kayıt yok").
--      Mevcut Fizik batch'ine geriye dönük veri/backfill YOKTUR.
--
-- Ürün kararı: low_confidence yalnız admin/öğretmen candidate-review
-- yüzeyindedir; öğrenci API'sine asla taşınmaz.
--
-- Idempotent: CREATE OR REPLACE; tekrar uygulama hata vermez. 120/128/121/
-- 123/124/125 dosyalarına geri dokunulmaz, yeni dosya ekli zincirdir.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. DETAIL RPC — subject_name + outcome_code + low_confidence
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_candidate_question_batch_detail(
  p_batch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid;
  v_batch public.candidate_question_batches%ROWTYPE;
  v_candidates jsonb := '[]'::jsonb;
  v_candidate jsonb;
  v_preview jsonb;
  v_validation jsonb;
  v_review_entries jsonb;
  v_answer jsonb;
  v_curriculum jsonb;
  v_solve jsonb;
  v_originality jsonb;
  v_quality jsonb;
  v_readiness jsonb;
  v_final_review jsonb;
  r record;
BEGIN
  v_uid := auth.uid();

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Kimlik dogrulamasi gerekli.'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       public.current_user_has_admin_permission('ai.manage')
       OR public.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Aday paket detayi icin ai.manage veya questions.approve yetkisi gerekli.'
      USING ERRCODE = '42501';
  END IF;

  IF p_batch_id IS NULL THEN
    RAISE EXCEPTION 'p_batch_id zorunludur.'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
    INTO v_batch
  FROM public.candidate_question_batches b
  WHERE b.id = p_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aday paketi bulunamadi.'
      USING ERRCODE = 'P0002';
  END IF;

  FOR r IN
    SELECT
      cr.candidate_index,
      cr.client_question_id,
      cr.validation_status,
      cr.validation_errors,
      cr.validation_warnings,
      cr.staging_question_id,
      s.staging_status,
      s.ownership_status,
      s.license_status,
      s.commercial_use_allowed,
      s.copyright_risk_level,
      s.question_text,
      s.option_a,
      s.option_b,
      s.option_c,
      s.option_d,
      s.option_e,
      s.proposed_correct_answer,
      s.proposed_difficulty,
      s.proposed_cognitive_type,
      s.proposed_solve_time_seconds,
      s.grade_level,
      s.subject_id,
      sub.name AS subject_name,
      s.proposed_curriculum_version_id,
      s.proposed_topic_id,
      s.proposed_subtopic_id,
      s.metadata
    FROM public.candidate_batch_candidate_results cr
    LEFT JOIN public.ai_question_staging s
      ON s.id = cr.staging_question_id
    LEFT JOIN public.subjects sub
      ON sub.id = s.subject_id
    WHERE cr.batch_id = p_batch_id
    ORDER BY cr.candidate_index ASC
  LOOP

    IF r.staging_question_id IS NULL THEN
      v_preview := NULL;
      v_validation := '[]'::jsonb;
      v_review_entries := '[]'::jsonb;
      v_answer := NULL;
      v_curriculum := NULL;
      v_solve := NULL;
      v_originality := NULL;
      v_quality := NULL;
      v_readiness := NULL;
      v_final_review := NULL;
    ELSE
      v_preview := jsonb_build_object(
        'staging_status', r.staging_status,
        'question_text', r.question_text,
        'options', jsonb_build_object(
          'A', r.option_a,
          'B', r.option_b,
          'C', r.option_c,
          'D', r.option_d,
          'E', r.option_e
        ),
        'proposed_correct_answer', r.proposed_correct_answer,
        'proposed_difficulty', r.proposed_difficulty,
        'proposed_cognitive_type', r.proposed_cognitive_type,
        'proposed_solve_time_seconds', r.proposed_solve_time_seconds,
        'grade_level', r.grade_level,
        'subject_id', r.subject_id,
        'subject_name', r.subject_name,
        'outcome_code', r.metadata ->> 'outcome_code',
        'low_confidence',
          CASE
            WHEN r.metadata ? 'low_confidence'
            THEN (r.metadata -> 'low_confidence')::boolean
            ELSE NULL
          END,
        'proposed_curriculum_version_id', r.proposed_curriculum_version_id,
        'proposed_topic_id', r.proposed_topic_id,
        'proposed_subtopic_id', r.proposed_subtopic_id,
        'ownership_status', r.ownership_status,
        'license_status', r.license_status,
        'commercial_use_allowed', r.commercial_use_allowed,
        'copyright_risk_level', r.copyright_risk_level,
        'solution', r.metadata -> 'solution'
      );

      v_validation := (
        SELECT COALESCE(jsonb_agg(j ORDER BY vv.created_at ASC), '[]'::jsonb)
        FROM (
          SELECT jsonb_build_object(
            'validator_type', vr.validator_type,
            'validation_type', vr.validation_type,
            'result', vr.result,
            'score', vr.score,
            'summary', vr.summary,
            'provider_name', vr.provider_name,
            'model_name', vr.model_name,
            'prompt_version', vr.prompt_version,
            'created_at', vr.created_at
          ) AS j,
          vr.created_at
          FROM public.ai_validation_results vr
          WHERE vr.staging_question_id = r.staging_question_id
        ) vv
      );

      v_review_entries := (
        SELECT COALESCE(jsonb_agg(j ORDER BY rv.created_at ASC), '[]'::jsonb)
        FROM (
          SELECT jsonb_build_object(
            'reason_code', rq.reason_code,
            'reason_details', rq.reason_details,
            'priority', rq.priority,
            'status', rq.status,
            'created_at', rq.created_at
          ) AS j,
          rq.created_at
          FROM public.review_queue rq
          WHERE rq.entity_type = 'staging_question'
            AND rq.entity_id = r.staging_question_id
        ) rv
      );

      v_answer := (
        SELECT jsonb_build_object(
          'consensus_status', a.consensus_status,
          'consensus_answer', a.consensus_answer,
          'minimum_confidence', a.minimum_confidence,
          'solver_1_answer', a.solver_1_answer,
          'solver_1_confidence', a.solver_1_confidence,
          'solver_2_answer', a.solver_2_answer,
          'solver_2_confidence', a.solver_2_confidence,
          'human_decision', a.human_decision,
          'human_reviewed_by', a.human_reviewed_by,
          'human_reviewed_at', a.human_reviewed_at,
          'updated_at', a.updated_at
        )
        FROM public.ai_answer_verification_runs a
        WHERE a.staging_question_id = r.staging_question_id
        ORDER BY a.created_at DESC
        LIMIT 1
      );

      v_curriculum := (
        SELECT jsonb_build_object(
          'status', c.status,
          'expected_grade_level', c.expected_grade_level,
          'expected_subject_id', c.expected_subject_id,
          'expected_topic_id', c.expected_topic_id,
          'expected_subtopic_id', c.expected_subtopic_id,
          'expected_outcome_id', c.expected_outcome_id,
          'minimum_confidence', c.minimum_confidence,
          'human_decision', c.human_decision,
          'human_reviewed_by', c.human_reviewed_by,
          'human_reviewed_at', c.human_reviewed_at,
          'updated_at', c.updated_at
        )
        FROM public.ai_curriculum_fit_runs c
        WHERE c.staging_question_id = r.staging_question_id
        ORDER BY c.created_at DESC
        LIMIT 1
      );

      v_solve := (
        SELECT jsonb_build_object(
          'status', s.status,
          'producer_estimated_total_seconds', s.producer_estimated_total_seconds,
          'requested_min_seconds', s.requested_min_seconds,
          'requested_max_seconds', s.requested_max_seconds,
          'consensus_total_seconds', s.consensus_total_seconds,
          'recommended_race_limit_seconds', s.recommended_race_limit_seconds,
          'minimum_confidence', s.minimum_confidence,
          'human_decision', s.human_decision,
          'human_total_seconds', s.human_total_seconds,
          'human_reviewed_by', s.human_reviewed_by,
          'human_reviewed_at', s.human_reviewed_at,
          'updated_at', s.updated_at
        )
        FROM public.ai_solve_time_verification_runs s
        WHERE s.staging_question_id = r.staging_question_id
        ORDER BY s.created_at DESC
        LIMIT 1
      );

      v_originality := (
        SELECT jsonb_build_object(
          'status', o.status,
          'minimum_originality_score', o.minimum_originality_score,
          'maximum_similarity_score', o.maximum_similarity_score,
          'critical_similarity_score', o.critical_similarity_score,
          'consensus_originality_score', o.consensus_originality_score,
          'highest_detected_similarity_score', o.highest_detected_similarity_score,
          'highest_similarity_type', o.highest_similarity_type,
          'copyright_risk_level', o.copyright_risk_level,
          'human_decision', o.human_decision,
          'human_reviewed_by', o.human_reviewed_by,
          'human_reviewed_at', o.human_reviewed_at,
          'updated_at', o.updated_at
        )
        FROM public.ai_originality_verification_runs o
        WHERE o.staging_question_id = r.staging_question_id
        ORDER BY o.created_at DESC
        LIMIT 1
      );

      v_quality := (
        SELECT jsonb_build_object(
          'status', q.status,
          'minimum_confidence', q.minimum_confidence,
          'minimum_quality_score', q.minimum_quality_score,
          'consensus_quality_score', q.consensus_quality_score,
          'human_decision', q.human_decision,
          'human_reviewed_by', q.human_reviewed_by,
          'human_reviewed_at', q.human_reviewed_at,
          'updated_at', q.updated_at
        )
        FROM public.ai_question_quality_runs q
        WHERE q.staging_question_id = r.staging_question_id
        ORDER BY q.created_at DESC
        LIMIT 1
      );

      v_readiness := (
        SELECT jsonb_build_object(
          'readiness_status', rd.readiness_status,
          'readiness_score', rd.readiness_score,
          'blocking_reasons', rd.blocking_reasons,
          'warnings', rd.warnings,
          'answer_verification_passed', rd.answer_verification_passed,
          'curriculum_fit_passed', rd.curriculum_fit_passed,
          'solve_time_verification_passed', rd.solve_time_verification_passed,
          'originality_verification_passed', rd.originality_verification_passed,
          'question_quality_passed', rd.question_quality_passed,
          'commercial_clearance_status', rd.commercial_clearance_status,
          'commercial_ready', rd.commercial_ready,
          'evaluated_at', rd.evaluated_at,
          'updated_at', rd.updated_at
        )
        FROM public.ai_question_readiness_runs rd
        WHERE rd.staging_question_id = r.staging_question_id
        ORDER BY rd.created_at DESC
        LIMIT 1
      );

      v_final_review := (
        SELECT jsonb_build_object(
          'decision', fr.decision,
          'review_notes', fr.review_notes,
          'reviewed_by', fr.reviewed_by,
          'reviewed_at', fr.reviewed_at,
          'promoted_question_id', fr.promoted_question_id
        )
        FROM public.ai_question_final_reviews fr
        WHERE fr.staging_question_id = r.staging_question_id
        ORDER BY fr.reviewed_at DESC
        LIMIT 1
      );
    END IF;

    v_candidate := jsonb_build_object(
      'candidate_index', r.candidate_index,
      'client_question_id', r.client_question_id,
      'validation_status', r.validation_status,
      'validation_errors', r.validation_errors,
      'validation_warnings', r.validation_warnings,
      'staging_question_id', r.staging_question_id,
      'preview', v_preview,
      'validation_results', v_validation,
      'review_queue', v_review_entries,
      'gates', jsonb_build_object(
        'answer_verification', v_answer,
        'curriculum_fit', v_curriculum,
        'solve_time_verification', v_solve,
        'originality_verification', v_originality,
        'question_quality', v_quality,
        'readiness', v_readiness,
        'final_review', v_final_review
      )
    );

    v_candidates := v_candidates || v_candidate;
  END LOOP;

  RETURN jsonb_build_object(
    'batch', jsonb_build_object(
      'batch_id', v_batch.id,
      'batch_key', v_batch.batch_key,
      'schema_version', v_batch.schema_version,
      'origin', v_batch.origin,
      'producer_id', v_batch.producer_id,
      'producer_model', v_batch.producer_model,
      'status', v_batch.status,
      'counts', jsonb_build_object(
        'total_items', v_batch.total_items,
        'valid_items', v_batch.valid_items,
        'invalid_items', v_batch.invalid_items,
        'inserted_items', v_batch.inserted_items,
        'duplicate_items', v_batch.duplicate_items
      ),
      'validation_summary', v_batch.validation_summary,
      'created_at', v_batch.created_at,
      'updated_at', v_batch.updated_at
    ),
    'candidates', v_candidates
  );
END;
$$;


REVOKE ALL
ON FUNCTION public.get_candidate_question_batch_detail(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.get_candidate_question_batch_detail(uuid)
TO authenticated, service_role;


-- ============================================================
-- 2. REGISTER — low_confidence saklama (124 davranışı + yeni zarf okuma)
--    Değişiklikler yalnız: declare,
--    loop-içi v_low_confidence hesabı, staging metadata alanı.
-- ============================================================

CREATE OR REPLACE FUNCTION private.register_candidate_md_batch(
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_batch_id uuid;
  v_batch_key text;
  v_producer_id text;
  v_producer_model text;
  v_origin text;
  v_question jsonb;

  v_candidate_index integer := 0;
  v_client_question_id text;

  v_received_count integer := 0;
  v_valid_count integer := 0;
  v_invalid_count integer := 0;
  v_inserted_count integer := 0;
  v_duplicate_count integer := 0;

  v_staging_id uuid;
  v_question_text text;
  v_options jsonb;
  v_correct_answer text;
  v_difficulty text;
  v_cognitive text;
  v_solve_time integer;
  v_grade_level integer;
  v_subject_id_raw text;
  v_subject_name text;
  v_subject_id uuid;
  v_subject_match_count integer := 0;
  v_outcome_code text;
  v_solution jsonb;
  v_req_status text;
  v_package_status text;

  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_is_valid boolean := true;
  v_is_duplicate boolean := false;

  v_option_a text;
  v_option_b text;
  v_option_c text;
  v_option_d text;
  v_option_e text;
  v_option_values text[];
  v_option_count integer;
  v_unique_option_count integer;
  v_cm_item jsonb;

  v_final_status text;
  v_staging_ids jsonb := '[]'::jsonb;

  v_oop integer := 0;
  v_kinds jsonb := '[]'::jsonb;
  v_review_required boolean := true;
  v_any_needs_review boolean := false;

  v_outcome_id uuid;
  v_curriculum_version_id uuid;
  v_topic_id uuid;
  v_subtopic_id uuid;
  v_spec_id uuid;
  v_low_confidence boolean := false;

  v_existing_batch public.candidate_question_batches%ROWTYPE;
BEGIN

  -- =======================================================
  -- CALLER
  -- =======================================================

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR
       private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Candidate MD batch intake requires AI or admin permission.';
  END IF;

  -- =======================================================
  -- ROOT VALIDATION (v1.1)
  -- =======================================================

  IF p_payload IS NULL
     OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'Payload must be a JSON object.';
  END IF;

  IF p_payload ->> 'schema_version' IS DISTINCT FROM '1.1' THEN
    RAISE EXCEPTION 'Unsupported schema version (1.1 required).';
  END IF;

  IF p_payload ->> 'origin' IS DISTINCT FROM 'curriculum_original' THEN
    RAISE EXCEPTION 'Origin must be curriculum_original.';
  END IF;

  IF p_payload->'producer' IS NULL
     OR jsonb_typeof(p_payload->'producer') <> 'object'
     OR btrim(COALESCE(p_payload->'producer' ->> 'id', '')) = '' THEN
    RAISE EXCEPTION 'Producer id is required.';
  END IF;

  -- Kalıcı yayın yasağı değişmezleri paket düzeyinde de dayatılır.
  IF p_payload->'publication_allowed' = 'true'::jsonb
     OR p_payload->'is_active' = 'true'::jsonb THEN
    RAISE EXCEPTION 'MD candidate packages can never be publishable.';
  END IF;

  v_package_status := lower(btrim(COALESCE(p_payload ->> 'validation_requested_status', 'needs_review')));

  IF v_package_status NOT IN ('needs_review', 'pending') THEN
    RAISE EXCEPTION 'Candidate MD package status cannot be publishable/approved.';
  END IF;

  IF NOT (p_payload ? 'questions')
     OR jsonb_typeof(p_payload -> 'questions') <> 'array'
     OR jsonb_array_length(p_payload -> 'questions') = 0 THEN
    RAISE EXCEPTION 'Questions array must be non-empty.';
  END IF;


  -- =======================================================
  -- PRODUCER + BATCH KEY (idempotent)
  -- =======================================================

  v_producer_id := btrim(p_payload->'producer' ->> 'id');
  v_producer_model := NULLIF(btrim(COALESCE(p_payload->'producer' ->> 'model', '')), '');
  v_origin := p_payload ->> 'origin';

  v_batch_key := v_producer_id || ':md:' || encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex');

  SELECT * INTO v_existing_batch
  FROM public.candidate_question_batches b
  WHERE b.batch_key = v_batch_key;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'batch_id', v_existing_batch.id,
      'status', 'already_received',
      'staging_ids',
        (
          SELECT COALESCE(jsonb_agg(r.staging_question_id), '[]'::jsonb)
          FROM public.candidate_batch_candidate_results r
          WHERE r.batch_id = v_existing_batch.id
            AND r.validation_status = 'inserted'
        ),
      'total_items', v_existing_batch.total_items,
      'valid_items', v_existing_batch.valid_items,
      'invalid_items', v_existing_batch.invalid_items,
      'inserted_items', v_existing_batch.inserted_items,
      'duplicate_items', v_existing_batch.duplicate_items,
      'validation_summary', v_existing_batch.validation_summary
    );
  END IF;


  -- =======================================================
  -- PAKET-DIŞI İÇERİK ÖZETİ (yalnız sayaç)
  -- =======================================================

  BEGIN
    v_oop := COALESCE((p_payload->'metadata' ->> 'out_of_package_count')::integer, 0);
  EXCEPTION
    WHEN OTHERS THEN
      v_oop := 0;
  END;

  IF p_payload->'metadata' -> 'out_of_package_kinds' IS NOT NULL
     AND jsonb_typeof(p_payload->'metadata' -> 'out_of_package_kinds') = 'array' THEN
    v_kinds := p_payload->'metadata' -> 'out_of_package_kinds';
  END IF;


  -- =======================================================
  -- BATCH KAYDI (origin + kamu sütunları v1.0 CHECK'leriyle uyumlu)
  -- =======================================================

  INSERT INTO public.candidate_question_batches (
    batch_key,
    schema_version,
    origin,
    producer_id,
    producer_model,
    status,
    total_items,
    raw_payload
  )
  VALUES (
    v_batch_key,
    '1.0',
    v_origin,
    v_producer_id,
    v_producer_model,
    'validating',
    jsonb_array_length(p_payload -> 'questions'),
    p_payload
  )
  RETURNING id INTO v_batch_id;

  v_received_count := jsonb_array_length(p_payload -> 'questions');


  -- =======================================================
  -- HER CANDIDATE
  -- =======================================================

  FOR v_question IN
    SELECT value
    FROM jsonb_array_elements(p_payload -> 'questions')
  LOOP

    v_candidate_index := v_candidate_index + 1;
    v_client_question_id := NULLIF(btrim(COALESCE(v_question ->> 'client_question_id', '')), '');
    v_errors := '[]'::jsonb;
    v_warnings := '[]'::jsonb;
    v_is_valid := true;
    v_is_duplicate := false;
    v_staging_id := NULL;
    v_subject_id := NULL;
    v_low_confidence := false;

    -- ------------------------------------------------
    -- LOW-CONFIDENCE İŞARETİ (Faz 24)
    -- Kök zarf low_confidence_candidates (client_question_id dizisi).
    -- Zarf yok/bozuk → yalnız false. Eşleşme yoksa false.
    -- ------------------------------------------------

    IF v_client_question_id IS NOT NULL
       AND p_payload->'low_confidence_candidates' IS NOT NULL
       AND jsonb_typeof(p_payload->'low_confidence_candidates') = 'array'
       AND EXISTS (
         SELECT 1
         FROM jsonb_array_elements_text(p_payload->'low_confidence_candidates') AS lc(qid)
         WHERE lc.qid = v_client_question_id
       )
    THEN
      v_low_confidence := true;
    END IF;

    -- -----------------------------------------------------
    -- SORU METNİ
    -- -----------------------------------------------------

    v_question_text := btrim(COALESCE(v_question ->> 'question_text', ''));

    IF length(v_question_text) < 10 THEN
      v_errors := v_errors || jsonb_build_array('question_text_en_az_10_karakter_olmali');
      v_is_valid := false;
    END IF;

    -- -----------------------------------------------------
    -- SEÇENEKLER (A-E zorunlu + benzersiz)
    -- -----------------------------------------------------

    v_options := v_question -> 'options';

    IF v_options IS NULL
       OR jsonb_typeof(v_options) <> 'object' THEN
      v_errors := v_errors || jsonb_build_array('options_bir_json_object_olmali');
      v_is_valid := false;
    ELSE

      v_option_a := btrim(COALESCE(v_options ->> 'A', ''));
      v_option_b := btrim(COALESCE(v_options ->> 'B', ''));
      v_option_c := btrim(COALESCE(v_options ->> 'C', ''));
      v_option_d := btrim(COALESCE(v_options ->> 'D', ''));
      v_option_e := btrim(COALESCE(v_options ->> 'E', ''));

      IF v_option_a = '' THEN v_errors := v_errors || jsonb_build_array('option_A_eksik'); v_is_valid := false; END IF;
      IF v_option_b = '' THEN v_errors := v_errors || jsonb_build_array('option_B_eksik'); v_is_valid := false; END IF;
      IF v_option_c = '' THEN v_errors := v_errors || jsonb_build_array('option_C_eksik'); v_is_valid := false; END IF;
      IF v_option_d = '' THEN v_errors := v_errors || jsonb_build_array('option_D_eksik'); v_is_valid := false; END IF;
      IF v_option_e = '' THEN v_errors := v_errors || jsonb_build_array('option_E_eksik'); v_is_valid := false; END IF;

      v_option_values := ARRAY[
        NULLIF(lower(v_option_a), ''),
        NULLIF(lower(v_option_b), ''),
        NULLIF(lower(v_option_c), ''),
        NULLIF(lower(v_option_d), ''),
        NULLIF(lower(v_option_e), '')
      ];

      SELECT COUNT(*), COUNT(DISTINCT x)
      INTO v_option_count, v_unique_option_count
      FROM unnest(v_option_values) AS t(x)
      WHERE x IS NOT NULL;

      IF v_option_count <> v_unique_option_count THEN
        v_errors := v_errors || jsonb_build_array('ayni_secenek_metni_tekrar_eden_bulundu');
        v_is_valid := false;
      END IF;

    END IF;

    -- -----------------------------------------------------
    -- DOĞRU CEVAP
    -- -----------------------------------------------------

    v_correct_answer := upper(btrim(COALESCE(v_question ->> 'correct_answer', '')));

    IF v_correct_answer NOT IN ('A', 'B', 'C', 'D', 'E') THEN
      v_errors := v_errors || jsonb_build_array('correct_answer_A_E_arasi_olmali');
      v_is_valid := false;
    ELSIF btrim(COALESCE(v_options ->> v_correct_answer, '')) = '' THEN
      v_errors := v_errors || jsonb_build_array('correct_answer_bos_secenek');
      v_is_valid := false;
    END IF;

    -- -----------------------------------------------------
    -- ZORLUK / BİLİŞSEL / SÜRE (opsiyonel kısıtlar)
    -- -----------------------------------------------------

    v_difficulty := lower(btrim(COALESCE(v_question ->> 'difficulty', '')));

    IF v_difficulty <> ''
       AND v_difficulty NOT IN ('easy', 'medium', 'hard') THEN
      v_errors := v_errors || jsonb_build_array('difficulty_easy_medium_hard_olmali');
      v_is_valid := false;
    END IF;

    v_cognitive := lower(btrim(COALESCE(v_question ->> 'cognitive_type', '')));

    IF v_cognitive <> ''
       AND v_cognitive NOT IN ('learning', 'comprehension', 'application') THEN
      v_errors := v_errors || jsonb_build_array('cognitive_type_learning_comprehension_application_olmali');
      v_is_valid := false;
    END IF;

    BEGIN
      IF v_question ? 'estimated_solve_time_seconds'
         AND v_question ->> 'estimated_solve_time_seconds' IS NOT NULL THEN
        v_solve_time := (v_question ->> 'estimated_solve_time_seconds')::integer;
      ELSE
        v_solve_time := NULL;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        v_solve_time := NULL;
    END;

    IF v_solve_time IS NOT NULL AND v_solve_time <= 0 THEN
      v_errors := v_errors || jsonb_build_array('estimated_solve_time_seconds_pozitif_tamsayi_olmali');
      v_is_valid := false;
    END IF;

    -- -----------------------------------------------------
    -- SINIF SEVİYESİ
    -- -----------------------------------------------------

    BEGIN
      IF v_question ? 'grade_level' THEN
        v_grade_level := (v_question ->> 'grade_level')::integer;
      ELSE
        v_grade_level := NULL;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        v_grade_level := NULL;
    END;

    IF v_grade_level IS NULL OR v_grade_level < 1 OR v_grade_level > 12 THEN
      v_errors := v_errors || jsonb_build_array('grade_level_1_12_olmali');
      v_is_valid := false;
    END IF;

    -- -----------------------------------------------------
    -- KAZANIM KODU (tek kazanım; çok kod otomatik seçilmez)
    -- -----------------------------------------------------

    v_outcome_code := NULLIF(btrim(COALESCE(v_question ->> 'outcome_code', '')), '');

    IF v_outcome_code IS NULL THEN
      v_errors := v_errors || jsonb_build_array('outcome_code_bos_olamaz');
      v_is_valid := false;
    ELSIF NOT (v_outcome_code ~ '^[A-Za-z0-9._-]+$') THEN
      v_errors := v_errors || jsonb_build_array('outcome_code_formati_gecersiz');
      v_is_valid := false;
    END IF;

    IF v_question -> 'additional_outcome_codes' IS NOT NULL
       AND jsonb_typeof(v_question -> 'additional_outcome_codes') = 'array'
       AND jsonb_array_length(v_question -> 'additional_outcome_codes') > 0 THEN
      v_errors := v_errors || jsonb_build_array('birden_fazla_kazanim_kodu');
      v_is_valid := false;
    END IF;

    -- -----------------------------------------------------
    -- ADAY DURUMU (yalnız needs_review/pending)
    -- -----------------------------------------------------

    v_req_status := lower(btrim(COALESCE(v_question ->> 'validation_requested_status', '')));

    IF v_req_status <> ''
       AND v_req_status NOT IN ('needs_review', 'pending') THEN
      v_errors := v_errors || jsonb_build_array('candidate_durum_not_importable');
      v_is_valid := false;
    END IF;

    IF v_req_status = 'needs_review' THEN
      v_any_needs_review := true;
    END IF;

    -- -----------------------------------------------------
    -- ÇÖZÜM (v1.1'de zorunlu: yöntem + en az iki adım + sonuç +
    -- gerekçe + çeldirici gerekçesi)
    -- -----------------------------------------------------

    v_solution := v_question -> 'solution';

    IF v_solution IS NULL OR jsonb_typeof(v_solution) <> 'object' THEN
      v_errors := v_errors || jsonb_build_array('solution_zorunlu');
      v_is_valid := false;
    ELSE

      IF btrim(COALESCE(v_solution ->> 'method', '')) = '' THEN
        v_errors := v_errors || jsonb_build_array('solution_method_eksik');
        v_is_valid := false;
      END IF;

      IF NOT (v_solution ? 'steps')
         OR jsonb_typeof(v_solution -> 'steps') <> 'array'
         OR jsonb_array_length(v_solution -> 'steps') < 2 THEN
        v_errors := v_errors || jsonb_build_array('solution_en_az_iki_adim_olmali');
        v_is_valid := false;
      END IF;

      IF btrim(COALESCE(v_solution ->> 'result', '')) = '' THEN
        v_errors := v_errors || jsonb_build_array('solution_result_eksik');
        v_is_valid := false;
      END IF;

      IF btrim(COALESCE(v_solution ->> 'correctAnswerJustification', '')) = '' THEN
        v_errors := v_errors || jsonb_build_array('solution_justification_eksik');
        v_is_valid := false;
      END IF;

      IF NOT (v_solution ? 'commonMistakes')
         OR jsonb_typeof(v_solution -> 'commonMistakes') <> 'array'
         OR jsonb_array_length(v_solution -> 'commonMistakes') = 0 THEN
        v_errors := v_errors || jsonb_build_array('solution_common_mistakes_eksik');
        v_is_valid := false;
      ELSE
        FOR v_cm_item IN
          SELECT value
          FROM jsonb_array_elements(v_solution -> 'commonMistakes')
        LOOP
          IF jsonb_typeof(v_cm_item) <> 'string'
             OR btrim(COALESCE(v_cm_item #>> '{}', '')) = '' THEN
            v_errors := v_errors || jsonb_build_array('solution_common_mistakes_eksik');
            v_is_valid := false;
            EXIT;
          END IF;
        END LOOP;
      END IF;

    END IF;

    -- -----------------------------------------------------
    -- DERS ÇÖZÜMLEME (kanonik subjects eşleşmesi)
    -- UUID varsa yalnız format doğrulanır (v1.0 ile tutarlı).
    -- Ad varsa subjects.is_active üzerinden kesin (tek) eşleşme aranır.
    -- -----------------------------------------------------

    v_subject_id_raw := NULLIF(btrim(COALESCE(v_question ->> 'subject_id', '')), '');
    v_subject_name := NULLIF(btrim(COALESCE(v_question ->> 'subject_ref', '')), '');

    IF v_subject_id_raw IS NOT NULL THEN
      IF NOT (v_subject_id_raw ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
        v_errors := v_errors || jsonb_build_array('subject_id_gecerli_bir_uuid_olmali');
        v_is_valid := false;
      ELSE
        v_subject_id := v_subject_id_raw::uuid;
      END IF;
    ELSIF v_subject_name IS NOT NULL THEN

      SELECT count(*)
      INTO v_subject_match_count
      FROM public.subjects s
      WHERE s.is_active = true
        AND lower(btrim(s.name)) = lower(btrim(v_subject_name));

      IF v_subject_match_count = 1 THEN

        SELECT s.id
        INTO v_subject_id
        FROM public.subjects s
        WHERE s.is_active = true
          AND lower(btrim(s.name)) = lower(btrim(v_subject_name))
        LIMIT 1;

      ELSIF v_subject_match_count = 0 THEN
        v_errors := v_errors || jsonb_build_array('subject_not_found');
        v_is_valid := false;
      ELSE
        v_errors := v_errors || jsonb_build_array('subject_ambiguous');
        v_is_valid := false;
      END IF;

    ELSE
      v_errors := v_errors || jsonb_build_array('subject_id_veya_subject_ref_zorunlu');
      v_is_valid := false;
    END IF;

    -- -----------------------------------------------------
    -- KAZANIM → MÜFREDAT ÇÖZÜMÜ (Faz 118 zinciri; fail-closed)
    -- -----------------------------------------------------

    IF v_is_valid THEN

      SELECT o.id, o.curriculum_version_id, o.topic_id, o.subtopic_id
        INTO v_outcome_id, v_curriculum_version_id, v_topic_id, v_subtopic_id
      FROM public.curriculum_outcomes o
      JOIN public.curriculum_versions cv ON cv.id = o.curriculum_version_id
      WHERE o.outcome_code = v_outcome_code
        AND o.subject_id = v_subject_id
        AND o.grade_level = v_grade_level
        AND o.is_active
      ORDER BY cv.is_default DESC, o.created_at DESC
      LIMIT 1;

      IF NOT FOUND THEN
        v_errors := v_errors || jsonb_build_array('outcome_not_found');
        v_is_valid := false;
      END IF;

    END IF;

    -- -----------------------------------------------------
    -- EVREN (GERÇEK) DUPLICATE KONTROLÜ — sunucu zorunlu
    -- -----------------------------------------------------

    IF v_is_valid THEN
      v_is_duplicate := EXISTS (
        SELECT 1
        FROM public.questions q
        WHERE q.approval_status IS DISTINCT FROM 'rejected'
          AND lower(btrim(coalesce(q.question_text, ''))) = lower(btrim(v_question_text))
      )
      OR EXISTS (
        SELECT 1
        FROM public.ai_question_staging s
        WHERE s.staging_status IS DISTINCT FROM 'rejected'
          AND lower(btrim(coalesce(s.question_text, ''))) = lower(btrim(v_question_text))
      )
      OR EXISTS (
        SELECT 1
        FROM public.candidate_batch_candidate_results r
        JOIN public.ai_question_staging s ON s.id = r.staging_question_id
        WHERE r.batch_id = v_batch_id
          AND r.validation_status = 'inserted'
          AND lower(btrim(coalesce(s.question_text, ''))) = lower(btrim(v_question_text))
      )
      OR (
        v_client_question_id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.candidate_batch_candidate_results r
          WHERE r.batch_id = v_batch_id
            AND r.validation_status = 'inserted'
            AND lower(coalesce(r.client_question_id, '')) = lower(v_client_question_id)
        )
      );
    END IF;

    IF v_is_duplicate THEN
      v_duplicate_count := v_duplicate_count + 1;
      v_errors := v_errors || jsonb_build_array('existing_universe_duplicate_question_text');
      v_is_valid := false;
    END IF;

    -- -----------------------------------------------------
    -- CANDIDATE AUDIT KAYDI
    -- -----------------------------------------------------

    IF v_is_valid THEN
      v_valid_count := v_valid_count + 1;
    ELSE
      v_invalid_count := v_invalid_count + 1;
    END IF;

    INSERT INTO public.candidate_batch_candidate_results (
      batch_id,
      candidate_index,
      client_question_id,
      validation_status,
      validation_errors,
      validation_warnings,
      staging_question_id
    )
    VALUES (
      v_batch_id,
      v_candidate_index,
      v_client_question_id,
      CASE
        WHEN NOT v_is_valid AND NOT v_is_duplicate THEN 'invalid'
        WHEN NOT v_is_valid AND v_is_duplicate THEN 'duplicate'
        ELSE 'inserted'
      END,
      v_errors,
      v_warnings,
      v_staging_id
    );

    -- -----------------------------------------------------
    -- SADECE GEÇERLİ ADAYLAR STAGING'E YAZILIR
    -- -----------------------------------------------------

    IF NOT v_is_valid THEN
      CONTINUE;
    END IF;

    -- -----------------------------------------------------
    -- GENERATION SPEC (Faz 118 bağı)
    -- -----------------------------------------------------

    INSERT INTO public.ai_generation_specs (
      curriculum_version_id,
      grade_level,
      subject_id,
      topic_id,
      subtopic_id,
      desired_count,
      difficulty,
      cognitive_type,
      min_solve_time_seconds,
      max_solve_time_seconds,
      constraints,
      status,
      outcome_id
    )
    VALUES (
      v_curriculum_version_id,
      v_grade_level,
      v_subject_id,
      v_topic_id,
      v_subtopic_id,
      1,
      v_difficulty,
      v_cognitive,
      v_solve_time,
      v_solve_time,
      jsonb_build_object(
        'origin', v_origin,
        'producer_id', v_producer_id,
        'producer_model', v_producer_model,
        'batch_id', v_batch_id,
        'client_question_id', v_client_question_id,
        'outcome_code', v_outcome_code,
        'source', 'external_producer'
      ),
      'ready',
      v_outcome_id
    )
    RETURNING id INTO v_spec_id;

    INSERT INTO public.ai_question_staging (
      staging_source,
      generation_spec_id,
      grade_level,
      subject_id,
      proposed_curriculum_version_id,
      proposed_topic_id,
      proposed_subtopic_id,
      question_text,
      option_a,
      option_b,
      option_c,
      option_d,
      option_e,
      proposed_correct_answer,
      proposed_difficulty,
      proposed_cognitive_type,
      proposed_solve_time_seconds,
      ownership_status,
      license_status,
      commercial_use_allowed,
      copyright_risk_level,
      staging_status,
      metadata
    )
    VALUES (
      'external_producer',
      v_spec_id,
      v_grade_level,
      v_subject_id,
      v_curriculum_version_id,
      v_topic_id,
      v_subtopic_id,
      v_question_text,
      NULLIF(v_option_a, ''),
      NULLIF(v_option_b, ''),
      NULLIF(v_option_c, ''),
      NULLIF(v_option_d, ''),
      NULLIF(v_option_e, ''),
      v_correct_answer,
      NULLIF(v_difficulty, ''),
      NULLIF(v_cognitive, ''),
      v_solve_time,
      'ai_original',
      'pending',
      false,
      'unknown',
      'validating',
      jsonb_build_object(
        'candidate_batch_id', v_batch_id,
        'client_question_id', v_client_question_id,
        'producer_id', v_producer_id,
        'producer_model', v_producer_model,
        'origin', v_origin,
        'outcome_code', v_outcome_code,
        'required_outcome_id', v_outcome_id,
        'generation_spec_id', v_spec_id,
        'curriculum_version_id', v_curriculum_version_id,
        'candidate_md_v11', jsonb_build_object(
          'schema_version', '1.1',
          'publication_allowed', false,
          'is_active', false,
          'review_required', v_review_required
        ),
        'solution', COALESCE(v_solution, '{}'::jsonb),
        'low_confidence', v_low_confidence,
        'deterministic_ingestion_passed', true,
        'automatic_publication_allowed', false,
        'final_readiness_status', 'pending'
      )
    )
    RETURNING id INTO v_staging_id;

    UPDATE public.candidate_batch_candidate_results
    SET
      validation_status = 'inserted',
      staging_question_id = v_staging_id
    WHERE batch_id = v_batch_id
      AND candidate_index = v_candidate_index;

    INSERT INTO public.ai_validation_results (
      staging_question_id,
      validator_type,
      validation_type,
      result,
      summary,
      details
    )
    VALUES (
      v_staging_id,
      'deterministic',
      'structure',
      'pass',
      'Candidate passed deterministic MD intake validation.',
      jsonb_build_object(
        'batch_id', v_batch_id,
        'candidate_index', v_candidate_index,
        'warnings', v_warnings
      )
    );

    INSERT INTO public.ai_validation_results (
      staging_question_id,
      validator_type,
      validation_type,
      result,
      summary,
      details
    )
    VALUES (
      v_staging_id,
      'deterministic',
      'answer',
      'pass',
      'Correct-answer field points to an existing option.',
      jsonb_build_object(
        'proposed_correct_answer', v_correct_answer,
        'important', 'This does not prove the academic correctness of the answer. Independent solving is still required.'
      )
    );

    v_staging_ids := v_staging_ids || to_jsonb(v_staging_id);
    v_inserted_count := v_inserted_count + 1;

  END LOOP;


  -- =======================================================
  -- FİNAL STATUS + PREFLIGHT ÖZETİ
  -- =======================================================

  IF v_inserted_count = 0 AND v_invalid_count > 0 THEN
    v_final_status := 'rejected';
  ELSIF v_invalid_count > 0 OR v_duplicate_count > 0 THEN
    v_final_status := 'partially_valid';
  ELSE
    v_final_status := 'ingested';
  END IF;

  v_review_required :=
    v_package_status = 'needs_review'
    OR v_any_needs_review
    OR v_invalid_count > 0
    OR v_duplicate_count > 0;

  UPDATE public.candidate_question_batches
  SET
    status = v_final_status,
    total_items = v_received_count,
    valid_items = v_valid_count,
    invalid_items = v_invalid_count,
    inserted_items = v_inserted_count,
    duplicate_items = v_duplicate_count,
    validation_summary = jsonb_build_object(
      'received', v_received_count,
      'valid', v_valid_count,
      'invalid', v_invalid_count,
      'inserted', v_inserted_count,
      'duplicates', v_duplicate_count,
      'preflight', jsonb_build_object(
        'adapter', 'v1.1_markdown',
        'schema_version', '1.1',
        'root_valid', true,
        'out_of_package_count', v_oop,
        'out_of_package_kinds', v_kinds,
        'review_required', v_review_required,
        'publication_allowed', false,
        'is_active', false
      )
    ),
    metadata = metadata || jsonb_build_object(
      'candidate_md_v11', jsonb_build_object(
        'schema_version', '1.1',
        'subject_ref', NULLIF(btrim(COALESCE(p_payload ->> 'subject_ref', '')), ''),
        'validation_requested_status', NULLIF(v_package_status, ''),
        'out_of_package_count', v_oop,
        'out_of_package_kinds', v_kinds,
        'review_required', v_review_required,
        'publication_allowed', false,
        'is_active', false
      )
    )
  WHERE id = v_batch_id;


  -- =======================================================
  -- RESULT
  -- =======================================================

  RETURN jsonb_build_object(
    'batch_id', v_batch_id,
    'batch_key', v_batch_key,
    'status', v_final_status,
    'staging_ids', v_staging_ids,
    'total_items', v_received_count,
    'valid_items', v_valid_count,
    'invalid_items', v_invalid_count,
    'inserted_items', v_inserted_count,
    'duplicate_items', v_duplicate_count,
    'automatic_publication_allowed', false,
    'validation_summary', jsonb_build_object(
      'preflight', jsonb_build_object(
        'adapter', 'v1.1_markdown',
        'schema_version', '1.1',
        'root_valid', true,
        'out_of_package_count', v_oop,
        'out_of_package_kinds', v_kinds,
        'review_required', v_review_required,
        'publication_allowed', false,
        'is_active', false
      )
    )
  );

END;
$$;


REVOKE ALL
ON FUNCTION private.register_candidate_md_batch(jsonb)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION private.register_candidate_md_batch(jsonb)
TO authenticated, service_role;


COMMIT;