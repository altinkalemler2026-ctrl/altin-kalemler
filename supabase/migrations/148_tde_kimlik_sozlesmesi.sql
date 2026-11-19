-- ============================================================================
-- 148 — TDE KİMLİK SÖZLEŞMESİ (S1 + S3 eşlik dilimi)
-- ============================================================================
-- DURUM: HAZIRLIK — BU MIGRATION ONAY ALINMADAN KOŞULMAZ (2026-10-28).
--
-- Amaç: TDE çatı kodları (TDE1.1 vb., resmî yapı gereği temalar arası
-- tekrar eder) intake/bulk-gate zincirinde KEYFİ (LIMIT 1 / first-seen)
-- kazanım satırına sessizce bağlanamasın.
--
-- Kapsam:
--   A) GUARD: çatı-deseni satırlarda (sürüm, sınıf, tema, kod) mükerrer
--      varsa fail-closed dur (raporlu).
--   B) S1: partial UNIQUE indeks — yalnız çatı deseni kodlarında
--      (curriculum_version_id, grade_level, topic_id, outcome_code)
--      benzersizlik. 5 ders üç-basamaklı kodları desene uymaz → etkisiz.
--   C) private.resolve_intake_outcome: tek çözümleme noktası.
--      Çatı kodu + tema bağlamı yoksa 0 satır (fail-closed);
--      0 veya 2+ eşleşmede 0 satır (fail-closed). Çatı olmayan kodda
--      mevcut davranış birebir (ORDER BY cv.is_default DESC, created_at
--      DESC LIMIT 1).
--   D) private.register_candidate_md_batch (132 gövdesi üzerine) ve
--      private.register_candidate_question_batch (118 gövdesi üzerine):
--      opsiyonel payload.topic_id (UUID) tema bağlamı; çatı kodunda
--      bağlam yoksa 'outcome_tema_baglami_zorunlu' ile AÇIK red;
--      çözümleme helper üzerinden. Çatı olmayan kodlarda davranış
--      DEĞİŞMEZ (132: fail-closed outcome_not_found; 118: mevcut akış).
--   E) get_canonical_outcome_codes: çıktıya 'grade_level' alanı EKLENİR
--      (additif; mevcut tüketiciler etkilenmez) — bulk-gate kapsam
--      çözümlemesi için.
--   F) Yetki düzeltmesi: 132'deki DROP+CREATE sonrası
--      private.register_candidate_md_batch üzerinde PUBLIC EXECUTE
--      varsayılanı kalmıştı; REVOKE/GRANT ile eski sözleşmeye döner.
--
-- Gösterim (S3): türetilmiş etiket (TDE1.1@9-T3) HİÇBİR tabloya
-- yazılmaz; yalnız uygulama katmanında anlık üretilir
-- (src/lib/curriculum/outcome-display.ts).
--
-- Geri dönüş: DROP INDEX IF EXISTS uq_curriculum_outcomes_cati_kod;
-- (data-only, tek adım). Fonksiyonlar için 132/118 tanımlarına dönüş.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- A) GUARD — çatı-deseni satırlarda (sürüm, sınıf, tema, kod) mükerrerlik
-- ----------------------------------------------------------------------------
DO $guard$
DECLARE
  v_mukerrer integer;
BEGIN
  SELECT count(*) INTO v_mukerrer FROM (
    SELECT 1
    FROM public.curriculum_outcomes
    WHERE outcome_code ~ '^[A-Z]{2,4}[0-9]+\.[0-9]+$'
      AND topic_id IS NOT NULL
    GROUP BY curriculum_version_id, grade_level, topic_id, outcome_code
    HAVING count(*) > 1
  ) x;
  IF v_mukerrer > 0 THEN
    RAISE EXCEPTION
      'GUARD_148: çatı-deseni satırlarda % adet mükerrer (sürüm,sınıf,tema,kod) üçlüsü var — indeks kurulamaz, fail-closed dur.',
      v_mukerrer;
  END IF;
END
$guard$;

-- ----------------------------------------------------------------------------
-- B) S1 — bileşik benzersizlik (yalnız çatı deseni)
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_curriculum_outcomes_cati_kod
  ON public.curriculum_outcomes (curriculum_version_id, grade_level, topic_id, outcome_code)
  WHERE outcome_code ~ '^[A-Z]{2,4}[0-9]+\.[0-9]+$'
    AND topic_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- C) TEK çözümleme noktası
--    Dönüş: 0 satır = çözülemedi (çağıran fail-closed reddeder);
--    1 satır = kesin kimlik. Kapsamsız çatı kodu ASLA çözülmez.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.resolve_intake_outcome(
  p_outcome_code text,
  p_subject_id uuid,
  p_grade_level integer,
  p_scope_topic_id uuid DEFAULT NULL
)
RETURNS TABLE (
  outcome_id uuid,
  curriculum_version_id uuid,
  topic_id uuid,
  subtopic_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $body$
DECLARE
  v_cati boolean;
  v_eslesen integer;
BEGIN
  IF p_outcome_code IS NULL OR p_subject_id IS NULL OR p_grade_level IS NULL THEN
    RETURN;
  END IF;

  v_cati := (p_outcome_code ~ '^[A-Z]{2,4}[0-9]+\.[0-9]+$');

  IF v_cati THEN
    -- Çatı kodu: tema bağlamı ZORUNLU (fail-closed).
    IF p_scope_topic_id IS NULL THEN
      RETURN;
    END IF;

    SELECT count(*) INTO v_eslesen
    FROM public.curriculum_outcomes o
    JOIN public.curriculum_versions cv ON cv.id = o.curriculum_version_id
    WHERE o.outcome_code = p_outcome_code
      AND o.subject_id = p_subject_id
      AND o.grade_level = p_grade_level
      AND o.topic_id = p_scope_topic_id
      AND o.is_active;

    IF v_eslesen <> 1 THEN
      -- 0 = kapsam dışı / bulunamadı; 2+ = belirsiz → ikisinde de YOK.
      RETURN;
    END IF;

    RETURN QUERY
      SELECT o.id, o.curriculum_version_id, o.topic_id, o.subtopic_id
      FROM public.curriculum_outcomes o
      JOIN public.curriculum_versions cv ON cv.id = o.curriculum_version_id
      WHERE o.outcome_code = p_outcome_code
        AND o.subject_id = p_subject_id
        AND o.grade_level = p_grade_level
        AND o.topic_id = p_scope_topic_id
        AND o.is_active
      ORDER BY cv.is_default DESC, o.created_at DESC
      LIMIT 1;
    RETURN;
  END IF;

  -- Çatı olmayan kod (5 ders + legacy): MEVCUT davranış birebir korunur.
  RETURN QUERY
    SELECT o.id, o.curriculum_version_id, o.topic_id, o.subtopic_id
    FROM public.curriculum_outcomes o
    JOIN public.curriculum_versions cv ON cv.id = o.curriculum_version_id
    WHERE o.outcome_code = p_outcome_code
      AND o.subject_id = p_subject_id
      AND o.grade_level = p_grade_level
      AND o.is_active
    ORDER BY cv.is_default DESC, o.created_at DESC
    LIMIT 1;
END;
$body$;

REVOKE ALL
ON FUNCTION private.resolve_intake_outcome(text, uuid, integer, uuid)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION private.resolve_intake_outcome(text, uuid, integer, uuid)
TO service_role;

-- ----------------------------------------------------------------------------
-- D1) private.register_candidate_md_batch — 132 gövdesi + tema bağlamı
--     (pg_get_functiondef kaynağından üretildi; tek fark: 3 dar değişiklik)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.register_candidate_md_batch(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $body$
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
  -- TDE kimlik sözleşmesi (148): opsiyonel tema bağlamı (topic_id).
  v_topic_id_raw text;
  v_scope_topic_id uuid;
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
    -- TEMA BAĞLAMI (TDE kimlik sözleşmesi, 148)
    -- Çatı kodu (TDE1.1 vb.) resmî yapı gereği birden fazla temada
    -- tekrar eder; tema bağlamı payload'daki opsiyonel topic_id
    -- (UUID) ile taşınır. Çatı kodunda bağlam ZORUNLUDUR.
    -- -----------------------------------------------------

    v_topic_id_raw := NULLIF(btrim(COALESCE(v_question ->> 'topic_id', '')), '');
    v_scope_topic_id := NULL;

    IF v_topic_id_raw IS NOT NULL THEN
      IF NOT (v_topic_id_raw ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
        v_errors := v_errors || jsonb_build_array('topic_id_gecerli_bir_uuid_olmali');
        v_is_valid := false;
      ELSE
        v_scope_topic_id := v_topic_id_raw::uuid;
      END IF;
    END IF;

    IF v_outcome_code IS NOT NULL
       AND v_outcome_code ~ '^[A-Z]{2,4}[0-9]+\.[0-9]+$'
       AND v_scope_topic_id IS NULL THEN
      v_errors := v_errors || jsonb_build_array('outcome_tema_baglami_zorunlu');
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

      -- TDE kimlik sözleşmesi (148): çözümleme private.resolve_intake_outcome
      -- üzerinden yapılır. Çatı kodunda tema bağlamı ZORUNLU; belirsiz
      -- eşleşmede satır DÖNMEZ (fail-closed). 5 ders kodlarında mevcut
      -- tekil çözümleme davranışı korunur.
      SELECT r.outcome_id, r.curriculum_version_id, r.topic_id, r.subtopic_id
        INTO v_outcome_id, v_curriculum_version_id, v_topic_id, v_subtopic_id
      FROM private.resolve_intake_outcome(
        v_outcome_code, v_subject_id, v_grade_level, v_scope_topic_id
      ) r;

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
      NULLIF(v_difficulty, ''),
      NULLIF(v_cognitive, ''),
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
$body$;



-- ----------------------------------------------------------------------------
-- D2) private.register_candidate_question_batch — 118 gövdesi + tema bağlamı
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.register_candidate_question_batch(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $body$
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
  v_subject_id uuid;
  v_outcome_code text;
  -- TDE kimlik sözleşmesi (148): opsiyonel tema bağlamı (topic_id).
  v_topic_id_raw text;
  v_scope_topic_id uuid;
  v_solution jsonb;

  v_validation jsonb;
  v_errors jsonb;
  v_warnings jsonb;

  v_final_status text;

  v_staging_ids jsonb := '[]'::jsonb;

  v_outcome_id uuid;
  v_curriculum_version_id uuid;
  v_topic_id uuid;
  v_subtopic_id uuid;
  v_spec_id uuid;

  v_existing_batch public.candidate_question_batches%ROWTYPE;
BEGIN

  -- =======================================================
  -- Caller
  -- =======================================================

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR
       private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Candidate batch intake requires AI or admin permission.';
  END IF;


  -- =======================================================
  -- ROOT VALIDATION
  -- =======================================================

  IF p_payload IS NULL
     OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'Payload must be a JSON object.';
  END IF;

  IF p_payload ->> 'schema_version' IS DISTINCT FROM '1.0' THEN
    RAISE EXCEPTION 'Unsupported schema version.';
  END IF;

  IF p_payload ->> 'origin' IS DISTINCT FROM 'curriculum_original' THEN
    RAISE EXCEPTION 'Origin must be curriculum_original.';
  END IF;

  IF p_payload->'producer' IS NULL
     OR jsonb_typeof(p_payload->'producer') <> 'object'
     OR btrim(COALESCE(p_payload->'producer' ->> 'id', '')) = '' THEN
    RAISE EXCEPTION 'Producer id is required.';
  END IF;

  IF NOT (p_payload ? 'questions')
     OR jsonb_typeof(p_payload -> 'questions') <> 'array'
     OR jsonb_array_length(p_payload -> 'questions') = 0 THEN
    RAISE EXCEPTION 'Questions array must be non-empty.';
  END IF;


  -- =======================================================
  -- PRODUCER + BATCH KEY
  -- =======================================================

  v_producer_id := btrim(p_payload->'producer' ->> 'id');
  v_producer_model := NULLIF(btrim(COALESCE(p_payload->'producer' ->> 'model', '')), '');
  v_origin := p_payload ->> 'origin';

  v_batch_key := v_producer_id || ':' || encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex');

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
      'duplicate_items', v_existing_batch.duplicate_items
    );
  END IF;


  -- =======================================================
  -- BATCH KAYDI
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


  -- =======================================================
  -- HER CANDIDATE
  -- =======================================================

  FOR v_question IN
    SELECT value
    FROM jsonb_array_elements(p_payload -> 'questions')
  LOOP

    v_received_count := v_received_count + 1;
    v_client_question_id := NULLIF(btrim(COALESCE(v_question ->> 'client_question_id', '')), '');

    v_validation := private.validate_candidate_question_batch_candidate(v_question);
    v_errors := COALESCE(v_validation -> 'errors', '[]'::jsonb);
    v_warnings := COALESCE(v_validation -> 'warnings', '[]'::jsonb);

    INSERT INTO public.candidate_batch_candidate_results (
      batch_id,
      candidate_index,
      client_question_id,
      validation_status,
      validation_errors,
      validation_warnings
    )
    VALUES (
      v_batch_id,
      v_candidate_index,
      v_client_question_id,
      CASE WHEN (v_validation ->> 'valid')::boolean THEN 'valid' ELSE 'invalid' END,
      v_errors,
      v_warnings
    );

    IF NOT (v_validation ->> 'valid')::boolean THEN
      v_invalid_count := v_invalid_count + 1;
      v_candidate_index := v_candidate_index + 1;
      CONTINUE;
    END IF;

    v_valid_count := v_valid_count + 1;

    v_question_text := btrim(v_question ->> 'question_text');
    v_options := v_question -> 'options';
    v_correct_answer := upper(btrim(v_question ->> 'correct_answer'));

    v_difficulty := NULLIF(lower(btrim(COALESCE(v_question ->> 'difficulty', ''))), '');
    v_cognitive := NULLIF(lower(btrim(COALESCE(v_question ->> 'cognitive_type', ''))), '');

    BEGIN
      v_solve_time := NULLIF(v_question ->> 'estimated_solve_time_seconds', '')::integer;
    EXCEPTION WHEN OTHERS THEN
      v_solve_time := NULL;
    END;

    BEGIN
      v_grade_level := (v_question ->> 'grade_level')::integer;
    EXCEPTION WHEN OTHERS THEN
      v_grade_level := NULL;
    END;

    BEGIN
      v_subject_id := (v_question ->> 'subject_id')::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_subject_id := NULL;
    END;

    v_outcome_code := NULLIF(btrim(COALESCE(v_question ->> 'outcome_code', '')), '');
    v_solution := v_question -> 'solution';

    -- TEMA BAĞLAMI (TDE kimlik sözleşmesi, 148): opsiyonel topic_id.
    -- Geçersiz UUID bağlamı YOK SAYILIR (v1.0 gövdesinde hata biriktirme
    -- aşaması zaten geçilmiştir); çatı kodunda çözümleme aşamasında
    -- fail-closed reddedilir. (v1.1 gövdesinde geçersiz UUID açık
    -- 'topic_id_gecerli_bir_uuid_olmali' hatasıdır — bilinçli asimetri.)
    v_scope_topic_id := NULL;
    v_topic_id_raw := NULLIF(btrim(COALESCE(v_question ->> 'topic_id', '')), '');
    IF v_topic_id_raw IS NOT NULL THEN
      BEGIN
        v_scope_topic_id := v_topic_id_raw::uuid;
      EXCEPTION WHEN OTHERS THEN
        v_scope_topic_id := NULL;
      END;
    END IF;


    -- =====================================================
    -- LOCAL DUPLICATE GUARD
    -- =====================================================

    IF EXISTS (
      SELECT 1
      FROM public.candidate_batch_candidate_results r
      JOIN public.ai_question_staging s ON s.id = r.staging_question_id
      WHERE r.batch_id = v_batch_id
        AND r.validation_status = 'inserted'
        AND lower(btrim(COALESCE(s.question_text, ''))) = lower(btrim(v_question_text))
    )
    THEN
      v_duplicate_count := v_duplicate_count + 1;

      UPDATE public.candidate_batch_candidate_results
      SET
        validation_status = 'duplicate',
        validation_warnings = validation_warnings || jsonb_build_array('duplicate_normalized_question_text')
      WHERE batch_id = v_batch_id
        AND candidate_index = v_candidate_index;

      v_candidate_index := v_candidate_index + 1;
      CONTINUE;
    END IF;


    -- =====================================================
    -- OUTCOME + GENERATION SPEC (Faz 15C)
    --
    -- Aktif (veya is_default) müfredata göre kazanım UUID'sini
    -- çöz; her harici aday için mevcut ai_generation_specs
    -- sözleşmesine uygun bir kayıt oluştur (desired_count=1).
    -- Provenance (origin, producer, batch, client_question_id)
    -- spec.constraints içinde korunur. Status='ready' yalnızca
    -- gate'lerin beklediği geçerli spec sözleşmesidir; otomatik
    -- yayın bayrağı hiçbir yerde verilmez.
    -- =====================================================

    SELECT r.outcome_id, r.curriculum_version_id, r.topic_id, r.subtopic_id
      INTO v_outcome_id, v_curriculum_version_id, v_topic_id, v_subtopic_id
    FROM private.resolve_intake_outcome(
      v_outcome_code, v_subject_id, v_grade_level, v_scope_topic_id
    ) r;

    IF NOT FOUND
       AND v_outcome_code ~ '^[A-Z]{2,4}[0-9]+\.[0-9]+$' THEN
      -- TDE kimlik sözleşmesi (148): çatı kodu tema bağlamı olmadan
      -- çözülemez; sessiz NULL spec/staging yazımı YASAKTIR.
      UPDATE public.candidate_batch_candidate_results
      SET
        validation_status = 'invalid',
        validation_errors = validation_errors || jsonb_build_array(
          CASE
            WHEN v_scope_topic_id IS NULL THEN 'outcome_tema_baglami_zorunlu'
            ELSE 'outcome_not_found'
          END
        )
      WHERE batch_id = v_batch_id
        AND candidate_index = v_candidate_index;

      v_valid_count := v_valid_count - 1;
      v_invalid_count := v_invalid_count + 1;
      v_candidate_index := v_candidate_index + 1;
      CONTINUE;
    END IF;

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


    -- =====================================================
    -- STAGING INSERT
    -- =====================================================

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
      NULLIF(btrim(v_options ->> 'A'), ''),
      NULLIF(btrim(v_options ->> 'B'), ''),
      NULLIF(btrim(v_options ->> 'C'), ''),
      NULLIF(btrim(v_options ->> 'D'), ''),
      NULLIF(btrim(v_options ->> 'E'), ''),
      v_correct_answer,
      v_difficulty,
      v_cognitive,
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
        'solution', COALESCE(v_solution, '{}'::jsonb),
        'deterministic_ingestion_passed', true,
        'automatic_publication_allowed', false,
        'final_readiness_status', 'pending'
      )
    )
    RETURNING id INTO v_staging_id;


    -- =====================================================
    -- CANDIDATE RESULT UPDATE
    -- =====================================================

    UPDATE public.candidate_batch_candidate_results
    SET
      validation_status = 'inserted',
      staging_question_id = v_staging_id
    WHERE batch_id = v_batch_id
      AND candidate_index = v_candidate_index;


    -- =====================================================
    -- DETERMINISTIC STRUCTURE VALIDATION
    -- =====================================================

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
      'Candidate passed deterministic intake structure validation.',
      jsonb_build_object(
        'batch_id', v_batch_id,
        'candidate_index', v_candidate_index,
        'warnings', v_warnings
      )
    );


    -- =====================================================
    -- DETERMINISTIC ANSWER FORMAT VALIDATION
    -- =====================================================

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


    -- =====================================================
    -- REVIEW QUEUE (şüpheli/eksik)
    -- =====================================================

    IF v_solution IS NULL
       OR NOT (v_solution ? 'steps')
       OR jsonb_array_length(COALESCE(v_solution -> 'steps', '[]'::jsonb)) = 0
       OR v_grade_level IS NULL
       OR v_subject_id IS NULL
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
        v_staging_id,
        'candidate_batch_intake_incomplete',
        jsonb_build_object(
          'batch_id', v_batch_id,
          'candidate_index', v_candidate_index,
          'missing_solution_steps',
          v_solution IS NULL OR NOT (v_solution ? 'steps')
            OR jsonb_array_length(COALESCE(v_solution -> 'steps', '[]'::jsonb)) = 0,
          'missing_grade_level', v_grade_level IS NULL,
          'missing_subject_id', v_subject_id IS NULL
        ),
        'normal',
        'open'
      );

      UPDATE public.ai_question_staging
      SET staging_status = 'needs_review',
          metadata = metadata || jsonb_build_object(
            'final_readiness_status', 'needs_review',
            'needs_review_reason', 'candidate_batch_intake_incomplete'
          )
      WHERE id = v_staging_id;

    ELSE
      UPDATE public.ai_question_staging
      SET metadata = metadata || jsonb_build_object(
        'final_readiness_status', 'pending',
        'candidate_batch_deterministic_checks_passed', true
      )
      WHERE id = v_staging_id;
    END IF;


    v_staging_ids := v_staging_ids || to_jsonb(v_staging_id);
    v_inserted_count := v_inserted_count + 1;
    v_candidate_index := v_candidate_index + 1;

  END LOOP;


  -- =======================================================
  -- BATCH STATUS
  -- =======================================================

  IF v_inserted_count = 0 AND v_invalid_count > 0 THEN
    v_final_status := 'rejected';
  ELSIF v_invalid_count > 0 OR v_duplicate_count > 0 THEN
    v_final_status := 'partially_valid';
  ELSE
    v_final_status := 'ingested';
  END IF;


  UPDATE public.candidate_question_batches
  SET
    status = v_final_status,
    valid_items = v_valid_count,
    invalid_items = v_invalid_count,
    inserted_items = v_inserted_count,
    duplicate_items = v_duplicate_count,
    validation_summary = jsonb_build_object(
      'received', v_received_count,
      'valid', v_valid_count,
      'invalid', v_invalid_count,
      'inserted', v_inserted_count,
      'duplicates', v_duplicate_count
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
    'automatic_publication_allowed', false
  );

END;
$body$;



-- ----------------------------------------------------------------------------
-- E) get_canonical_outcome_codes — çıktıya grade_level eklenir (additif)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_canonical_outcome_codes(
  p_curriculum_version_id uuid,
  p_subject_id uuid,
  p_min_grade integer DEFAULT 9,
  p_max_grade integer DEFAULT 12
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $body$
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'code', o.outcome_code,
        'text', o.outcome_text,
        'topic_id', o.topic_id,
        'subtopic_id', o.subtopic_id,
        'grade_level', o.grade_level
      )
      ORDER BY o.grade_level, o.outcome_code
    ),
    '[]'::jsonb
  )
  FROM public.curriculum_outcomes o
  WHERE o.is_active = true
    AND (p_curriculum_version_id IS NULL OR o.curriculum_version_id = p_curriculum_version_id)
    AND (p_subject_id IS NULL OR o.subject_id = p_subject_id)
    AND o.grade_level BETWEEN COALESCE(p_min_grade, 9) AND COALESCE(p_max_grade, 12);
$body$;

-- ----------------------------------------------------------------------------
-- F) Yetki sözleşmesi (DROP/CREATE sonrası PUBLIC varsayılanını kapatır)
-- ----------------------------------------------------------------------------
REVOKE ALL
ON FUNCTION private.register_candidate_md_batch(jsonb)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION private.register_candidate_md_batch(jsonb)
TO authenticated, service_role;

REVOKE ALL
ON FUNCTION private.register_candidate_question_batch(jsonb)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION private.register_candidate_question_batch(jsonb)
TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- DOĞRULAMA (salt-okunur; idempotent)
-- ----------------------------------------------------------------------------
DO $verify$
DECLARE
  v_src_md text;
  v_src_q text;
  v_src_helper text;
  v_cati_dup integer;
  v_index_def text;
BEGIN
  SELECT p.prosrc INTO v_src_md
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.proname = 'register_candidate_md_batch' AND n.nspname = 'private'
    AND p.pronargs = 1;

  SELECT p.prosrc INTO v_src_q
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.proname = 'register_candidate_question_batch' AND n.nspname = 'private'
    AND p.pronargs = 1;

  SELECT p.prosrc INTO v_src_helper
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.proname = 'resolve_intake_outcome' AND n.nspname = 'private'
    AND p.pronargs = 4;

  IF v_src_md IS NULL OR v_src_q IS NULL OR v_src_helper IS NULL THEN
    RAISE EXCEPTION 'Dogrulama basarisiz: 148 fonksiyonlarindan biri yok';
  END IF;

  -- Gövde imzaları yorumla değil ÇAĞRI ile kanıtlanır.
  IF position('FROM private.resolve_intake_outcome(' in v_src_md) = 0
     OR position('jsonb_build_array(''outcome_tema_baglami_zorunlu'')' in v_src_md) = 0 THEN
    RAISE EXCEPTION 'Dogrulama basarisiz: register_candidate_md_batch 148 duzenlemesi yok';
  END IF;

  IF position('FROM private.resolve_intake_outcome(' in v_src_q) = 0
     OR position('WHEN v_scope_topic_id IS NULL THEN ''outcome_tema_baglami_zorunlu''' in v_src_q) = 0 THEN
    RAISE EXCEPTION 'Dogrulama basarisiz: register_candidate_question_batch 148 duzenlemesi yok';
  END IF;

  IF position('outcome_tema_baglami_zorunlu' in v_src_helper) <> 0 THEN
    RAISE EXCEPTION 'Dogrulama basarisiz: helper hata kodu icermemeli (fail-closed satir dondurmeli)';
  END IF;

  -- İndeks VARLIĞI + TANIMI (yalnız adı değil; UNIQUE + kolon sırası + partial)
  SELECT indexdef INTO v_index_def
  FROM pg_indexes
  WHERE schemaname = 'public' AND indexname = 'uq_curriculum_outcomes_cati_kod';

  IF v_index_def IS NULL
     OR v_index_def NOT LIKE 'CREATE UNIQUE%'
     OR position('(curriculum_version_id, grade_level, topic_id, outcome_code)' in v_index_def) = 0
     OR position('topic_id IS NOT NULL' in v_index_def) = 0 THEN
    RAISE EXCEPTION 'Dogrulama basarisiz: uq_curriculum_outcomes_cati_kod tanimi beklenmedik: %', coalesce(v_index_def, '<yok>');
  END IF;

  SELECT count(*) INTO v_cati_dup FROM (
    SELECT 1
    FROM public.curriculum_outcomes
    WHERE outcome_code ~ '^[A-Z]{2,4}[0-9]+\.[0-9]+$'
      AND topic_id IS NOT NULL
    GROUP BY curriculum_version_id, grade_level, topic_id, outcome_code
    HAVING count(*) > 1
  ) x;
  IF v_cati_dup <> 0 THEN
    RAISE EXCEPTION 'Dogrulama basarisiz: cati-deseni mukerrerlik % adet', v_cati_dup;
  END IF;
END
$verify$;

-- ----------------------------------------------------------------------------
-- MIGRATION HISTORY — idempotent kayıt (146/147 deseni; psql koşumunda
-- statements=NULL; CLI koşan ortamda CLI'ın kendi kaydı varsa atlanır)
-- ----------------------------------------------------------------------------
insert into supabase_migrations.schema_migrations (version, name, statements)
select '148', '148_tde_kimlik_sozlesmesi', NULL
 where not exists (
   select 1 from supabase_migrations.schema_migrations where version = '148'
 );

COMMIT;

-- ============================================================================
-- UYGULAMA NOTU (onay sonrası):
--   docker cp 148_tde_kimlik_sozlesmesi.sql supabase_db_yarisma-programi:/tmp/
--   docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f /tmp/148_tde_kimlik_sozlesmesi.sql
--   (History kaydı yukarıdaki transaction İÇİNDE idempotent eklenir —
--    146/147 deseni; ayrı manuel adım gerekmez.)
--   Post-apply QA: 5 ders kod sayıları değişmez (MAT 24/69/90, FIZ 15/82/106,
--   KIM 12/92/93, BIY 8/89/75, COG 28/76/76); çatı-deseni satır 0 (TDE
--   yüklenene kadar); intake duman testi: çatı kodu + topicsiz payload →
--   'outcome_tema_baglami_zorunlu'.
-- ============================================================================
