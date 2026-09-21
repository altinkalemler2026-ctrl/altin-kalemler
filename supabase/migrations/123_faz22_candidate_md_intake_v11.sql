-- 123_faz22_candidate_md_intake_v11.sql
-- Altın Kalemler
--
-- Markdown aday soru paketi v1.1 intake'ı.
--
-- Prior: 117 (candidate batch intake), 118 (external producer / generation
-- spec), 120 (admin read). Bu migration v1.0 register'ın KATI üst kümesi
-- olan private.register_candidate_md_batch(p_payload jsonb) fonksiyonunu
-- ekler ve aynı candidate_question_batches tablosuna yazar.
--
-- Dikkat:
--  * Yalnız v1.1 sözleşmesi kabul edilir (beş seçenek A-E zorunlu, çözüm
--    zorunlu, durum yalnız needs_review/pending, publication_allowed=false
--    ve is_active=false kalıcı, birden fazla kazanım kodu bloklanır).
--  * Ders adı (subject_ref) subjects.is_active kanonik eşleşmesiyle çözülür;
--    hard-code uuid yoktur. Çözülemeyen/çoklu eşleşen aday reddedilir.
--  * GERÇEK evren duplicate kontrolü sunucuda zorunlu: public.questions
--    (approval_status <> 'rejected') ve public.ai_question_staging
--    (staging_status <> 'rejected'); normalize anahtar
--    lower(btrim(question_text)). Eşleşen aday staging'e YAZILMAZ,
--    'duplicate' işaretlenir.
--  * Paket-dışı içerik yalnız SAYI olarak (out_of_package_count + tür
--    özeti) metadata/preflight'a geçer; içerik asla taşınmaz.
--  * validation_summary.preflight nesnesi admin DTO'nun allowlist'iyle
--    okunur.
--
-- Idempotent: CREATE OR REPLACE; tekrar uygulama hata vermez.

BEGIN;


-- =========================================================
-- 1. İNTAKE RPC (PRIVATE)
-- =========================================================

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
    -- EVREN (GERÇEK) DUPLICATE KONTROLÜ — sunucu zorunlu
    -- Normalize anahtar: lower(btrim(question_text)).
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

    INSERT INTO public.ai_question_staging (
      staging_source,
      grade_level,
      subject_id,
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
      v_grade_level,
      v_subject_id,
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
        'candidate_md_v11', jsonb_build_object(
          'schema_version', '1.1',
          'publication_allowed', false,
          'is_active', false,
          'review_required', v_review_required
        ),
        'solution', COALESCE(v_solution, '{}'::jsonb),
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


-- =========================================================
-- 2. PUBLIC RPC
-- =========================================================
-- PostgREST (schemas = [public, graphql_public]) yalnız public şemayı
-- açar; facade'ın .rpc("register_candidate_md_batch") çağrısı için
-- 117 deseniyle aynı SECURITY INVOKER sarmalayıcı gerekir. Asıl kapı
-- (service_role/admin yetkileri) private fonksiyonda uygulanır.

CREATE OR REPLACE FUNCTION public.register_candidate_md_batch(
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.register_candidate_md_batch(p_payload);
$$;


REVOKE ALL
ON FUNCTION public.register_candidate_md_batch(jsonb)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.register_candidate_md_batch(jsonb)
TO authenticated, service_role;


COMMIT;