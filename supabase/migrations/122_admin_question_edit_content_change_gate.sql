-- ============================================================
-- 122_admin_question_edit_content_change_gate.sql
-- Phase P0 — İŞLEYEN SORUDA DEĞİŞİKLİK KAPISI
--
-- AMAÇ:
-- Yayındaki/aktif (veya onaylı ancak henüz yayınlanmamış) bir
-- sorunun İÇERİĞİ (question_text, option_a..e, correct_answer,
-- has_visual) gerçekten değişirse soru OTOMATİK pasife alınır ve
-- approval_status 'needs_review' yapılır. Böylece soru aktif
-- kalıp denetim zincirini atlayamaz ve ESKİ onay, değiştirilmiş
-- soruyu yeniden yayımlayamaz (040 readiness question_not_approved).
--
-- EK: admin_question_requalify RPC — 'needs_review'deki soruyu
-- yalnızca yeniden onaya ('approved') getirir; is_active=false'te KALIR
-- (öğrenciye otomatik açılmaz; yayın için 040 activate ayrı ve insan
-- adımıdır). İzin: questions.approve. Audit: admin_audit_log'a
-- 'question.requalify' yazar (aynı transaction, atomik).
--
-- TASARIM KARARI (tetikleyici alan seti):
--   TETİKLEYİCİ  : question_text, option_a..e, correct_answer, has_visual
--                   -> öğrencinin gördüğü soru içeriği + görsel içerik.
--   TETİKLEMEYEN : difficulty, cognitive_type, quality_level,
--                   primary/secondary_question_type,
--                   estimated_solve_time_seconds, is_new_generation
--                   -> metadata; öğrenciye sunulan içeriği değiştirmez.
--
-- No-op tespiti: tetikleyici alanların hiçbiri DEĞİŞMEDİYSE kapı
-- tetiklenmez, soru pasife alınmaz (aynı değerlerle kaydetme gereksiz
-- denetim başlatmaz).
--
-- Önceki cevaplar/denemeler ve audit geçmişi DEĞİŞTİRİLMEZ: yalnızca
-- approval_status/is_active güncellenir ve yeni audit/event satırları
-- EKLENİR (append-only).
-- ============================================================

BEGIN;


-- ============================================================
-- 1. admin_question_edit — İÇERİK DEĞİŞİKLİĞİ KAPISI
--    (089 signature birebir korunur; davranış additive genişler)
-- ============================================================

CREATE OR REPLACE FUNCTION private.admin_question_edit(
  p_question_id uuid,
  p_question_text text DEFAULT NULL,
  p_option_a text DEFAULT NULL,
  p_option_b text DEFAULT NULL,
  p_option_c text DEFAULT NULL,
  p_option_d text DEFAULT NULL,
  p_option_e text DEFAULT NULL,
  p_correct_answer text DEFAULT NULL,
  p_difficulty text DEFAULT NULL,
  p_cognitive_type text DEFAULT NULL,
  p_quality_level text DEFAULT NULL,
  p_primary_question_type text DEFAULT NULL,
  p_secondary_question_type text DEFAULT NULL,
  p_estimated_solve_time_seconds integer DEFAULT NULL,
  p_is_new_generation boolean DEFAULT NULL,
  p_has_visual boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_question public.questions%ROWTYPE;
  v_before_data jsonb;
  v_after_data jsonb;
  v_next_question_text public.questions.question_text%TYPE;
  v_next_option_a public.questions.option_a%TYPE;
  v_next_option_b public.questions.option_b%TYPE;
  v_next_option_c public.questions.option_c%TYPE;
  v_next_option_d public.questions.option_d%TYPE;
  v_next_option_e public.questions.option_e%TYPE;
  v_next_correct_answer public.questions.correct_answer%TYPE;
  v_next_difficulty public.questions.difficulty%TYPE;
  v_next_cognitive_type public.questions.cognitive_type%TYPE;
  v_next_quality_level public.questions.quality_level%TYPE;
  v_next_primary public.questions.primary_question_type%TYPE;
  v_next_secondary public.questions.secondary_question_type%TYPE;
  v_next_solve integer;
  v_next_is_new_generation boolean;
  v_next_has_visual boolean;
  v_content_changed boolean := false;
  v_review_required boolean := false;
  v_was_active boolean;
  v_next_approval_status public.questions.approval_status%TYPE;
  v_next_is_active boolean;
  v_staging_id uuid;
  v_event_id uuid;
  v_audit_id uuid;
BEGIN

  -- Gerçek authenticated kullanıcı gerekir.
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  IF NOT private.current_user_has_admin_permission('questions.edit') THEN
    RAISE EXCEPTION 'Question edit permission required.'
      USING ERRCODE = '42501';
  END IF;

  -- Satırı kilitle + oku.
  SELECT *
  INTO v_question
  FROM public.questions q
  WHERE q.id = p_question_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Question not found.'
      USING ERRCODE = 'P0002';
  END IF;

  -- ======================================================
  -- GİRİŞ DOĞRULAMA (strict; DB CHECK kısıtları ile tutarlı)
  -- ======================================================
  IF p_difficulty IS NOT NULL
     AND p_difficulty NOT IN ('easy', 'medium', 'hard') THEN
    RAISE EXCEPTION 'Invalid difficulty.'
      USING ERRCODE = '22023';
  END IF;

  IF p_cognitive_type IS NOT NULL
     AND p_cognitive_type NOT IN ('learning', 'comprehension', 'application') THEN
    RAISE EXCEPTION 'Invalid cognitive type.'
      USING ERRCODE = '22023';
  END IF;

  IF p_quality_level IS NOT NULL
     AND p_quality_level NOT IN ('low', 'medium', 'high') THEN
    RAISE EXCEPTION 'Invalid quality level.'
      USING ERRCODE = '22023';
  END IF;

  IF p_correct_answer IS NOT NULL
     AND p_correct_answer NOT IN ('A', 'B', 'C', 'D', 'E') THEN
    RAISE EXCEPTION 'Invalid correct answer.'
      USING ERRCODE = '22023';
  END IF;

  IF p_estimated_solve_time_seconds IS NOT NULL
     AND p_estimated_solve_time_seconds <= 0 THEN
    RAISE EXCEPTION 'Solve time must be positive.'
      USING ERRCODE = '22023';
  END IF;

  -- ======================================================
  -- YENİ DEĞERLERİ HESAPLA (NULL => değiştirme, '' => NULL)
  -- ======================================================
  v_next_question_text := COALESCE(p_question_text, v_question.question_text);
  v_next_option_a := COALESCE(p_option_a, v_question.option_a);
  v_next_option_b := COALESCE(p_option_b, v_question.option_b);
  v_next_option_c := COALESCE(p_option_c, v_question.option_c);
  v_next_option_d := COALESCE(p_option_d, v_question.option_d);
  v_next_option_e := COALESCE(p_option_e, v_question.option_e);
  v_next_correct_answer := COALESCE(p_correct_answer, v_question.correct_answer);
  v_next_difficulty := COALESCE(p_difficulty, v_question.difficulty);
  v_next_cognitive_type := COALESCE(p_cognitive_type, v_question.cognitive_type);
  v_next_quality_level := COALESCE(p_quality_level, v_question.quality_level);
  v_next_primary := COALESCE(p_primary_question_type, v_question.primary_question_type);
  v_next_secondary := COALESCE(p_secondary_question_type, v_question.secondary_question_type);
  v_next_solve := COALESCE(p_estimated_solve_time_seconds, v_question.estimated_solve_time_seconds);
  v_next_is_new_generation := COALESCE(p_is_new_generation, v_question.is_new_generation);
  v_next_has_visual := COALESCE(p_has_visual, v_question.has_visual);

  -- Boş string => NULL temizleme (yalnız text alanları).
  IF p_question_text IS NOT NULL AND btrim(p_question_text) = '' THEN
    v_next_question_text := NULL;
  END IF;
  IF p_option_a IS NOT NULL AND btrim(p_option_a) = '' THEN v_next_option_a := NULL; END IF;
  IF p_option_b IS NOT NULL AND btrim(p_option_b) = '' THEN v_next_option_b := NULL; END IF;
  IF p_option_c IS NOT NULL AND btrim(p_option_c) = '' THEN v_next_option_c := NULL; END IF;
  IF p_option_d IS NOT NULL AND btrim(p_option_d) = '' THEN v_next_option_d := NULL; END IF;
  IF p_option_e IS NOT NULL AND btrim(p_option_e) = '' THEN v_next_option_e := NULL; END IF;
  IF p_primary_question_type IS NOT NULL AND btrim(p_primary_question_type) = '' THEN
    v_next_primary := NULL;
  END IF;
  IF p_secondary_question_type IS NOT NULL AND btrim(p_secondary_question_type) = '' THEN
    v_next_secondary := NULL;
  END IF;

  -- ======================================================
  -- İÇERİK DEĞİŞİKLİĞİ KAPISI
  --
  -- TETİKLEYİCİ alanlarda gerçek (null-safe) değişiklik var mı?
  -- No-op (aynı değerler) -> v_content_changed=false, kapı tetiklenmez.
  -- ======================================================
  v_content_changed := (
    v_next_question_text IS DISTINCT FROM v_question.question_text
    OR v_next_option_a IS DISTINCT FROM v_question.option_a
    OR v_next_option_b IS DISTINCT FROM v_question.option_b
    OR v_next_option_c IS DISTINCT FROM v_question.option_c
    OR v_next_option_d IS DISTINCT FROM v_question.option_d
    OR v_next_option_e IS DISTINCT FROM v_question.option_e
    OR v_next_correct_answer IS DISTINCT FROM v_question.correct_answer
    OR v_next_has_visual IS DISTINCT FROM v_question.has_visual
  );

  -- Onaylı bir sorunun içeriği değiştiyse yeniden denetim gerekir.
  v_review_required := (
    v_content_changed
    AND v_question.approval_status = 'approved'
  );

  v_was_active := v_question.is_active;

  IF v_review_required THEN
    v_next_approval_status := 'needs_review';
    v_next_is_active := false;
  ELSE
    v_next_approval_status := v_question.approval_status;
    v_next_is_active := v_question.is_active;
  END IF;

  -- before_data: düzenlenebilir allowlist alanları + yaşam döngüsü
  -- durumu (kapı geçişinin audit'te görünür olması için).
  v_before_data := jsonb_build_object(
    'question_text', v_question.question_text,
    'option_a', v_question.option_a,
    'option_b', v_question.option_b,
    'option_c', v_question.option_c,
    'option_d', v_question.option_d,
    'option_e', v_question.option_e,
    'correct_answer', v_question.correct_answer,
    'difficulty', v_question.difficulty,
    'cognitive_type', v_question.cognitive_type,
    'quality_level', v_question.quality_level,
    'primary_question_type', v_question.primary_question_type,
    'secondary_question_type', v_question.secondary_question_type,
    'estimated_solve_time_seconds', v_question.estimated_solve_time_seconds,
    'is_new_generation', v_question.is_new_generation,
    'has_visual', v_question.has_visual,
    'approval_status', v_question.approval_status,
    'is_active', v_question.is_active
  );

  -- ======================================================
  -- MUTATION (yalnız allowlist + kapı yaşam döngüsü alanları)
  -- ======================================================
  UPDATE public.questions
  SET
    question_text = v_next_question_text,
    option_a = v_next_option_a,
    option_b = v_next_option_b,
    option_c = v_next_option_c,
    option_d = v_next_option_d,
    option_e = v_next_option_e,
    correct_answer = v_next_correct_answer,
    difficulty = v_next_difficulty,
    cognitive_type = v_next_cognitive_type,
    quality_level = v_next_quality_level,
    primary_question_type = v_next_primary,
    secondary_question_type = v_next_secondary,
    estimated_solve_time_seconds = v_next_solve,
    is_new_generation = v_next_is_new_generation,
    has_visual = v_next_has_visual,
    approval_status = v_next_approval_status,
    is_active = v_next_is_active,
    updated_at = now()
  WHERE id = p_question_id;

  -- after_data: mutation sonrası allowlist + yaşam döngüsü durumu.
  v_after_data := jsonb_build_object(
    'question_text', v_next_question_text,
    'option_a', v_next_option_a,
    'option_b', v_next_option_b,
    'option_c', v_next_option_c,
    'option_d', v_next_option_d,
    'option_e', v_next_option_e,
    'correct_answer', v_next_correct_answer,
    'difficulty', v_next_difficulty,
    'cognitive_type', v_next_cognitive_type,
    'quality_level', v_next_quality_level,
    'primary_question_type', v_next_primary,
    'secondary_question_type', v_next_secondary,
    'estimated_solve_time_seconds', v_next_solve,
    'is_new_generation', v_next_is_new_generation,
    'has_visual', v_next_has_visual,
    'approval_status', v_next_approval_status,
    'is_active', v_next_is_active
  );

  -- ======================================================
  -- OTOMATİK PASİFE ALINMA — PUBLICATION EVENT
  --
  -- Kapı yalnızca SORU ÖĞRENCİYE GÖRÜNÜRKENDEN(Yayındayken)
  -- tetiklendiyse event yazılır; yayında olmayan onaylı soruda
  -- görünürlük değişmediği için publication event yazılmaz.
  -- (040 deactivate deseni; metadata automatic_content_change_gate.)
  -- ======================================================
  IF v_review_required AND v_was_active THEN

    SELECT s.id
    INTO v_staging_id
    FROM public.ai_question_staging s
    WHERE s.final_question_id = p_question_id
    ORDER BY s.updated_at DESC
    LIMIT 1;

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
      'Soru içeriği değişti; soru otomatik pasife alındı ve yeniden denetim gerekiyor.',
      v_user_id,
      jsonb_build_object(
        'approval_status',
        v_next_approval_status
      ),
      jsonb_build_object(
        'automatic_content_change_gate', true,
        'review_required', true
      )
    )
    RETURNING id
    INTO v_event_id;

  END IF;

  -- ======================================================
  -- ATOMIC AUDIT — aynı fonksiyon (aynı transaction).
  -- Audit INSERT başarısız olursa mutation da döner.
  -- ======================================================
  INSERT INTO public.admin_audit_log (
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    before_data,
    after_data
  )
  VALUES (
    v_user_id,
    'question.edit',
    'question',
    p_question_id,
    v_before_data,
    v_after_data
  )
  RETURNING id
  INTO v_audit_id;

  RETURN jsonb_build_object(
    'status', 'updated',
    'question_id', p_question_id,
    'audit_id', v_audit_id,
    'before_data', v_before_data,
    'after_data', v_after_data,
    'content_changed', v_content_changed,
    'review_required', v_review_required,
    'approval_status', v_next_approval_status,
    'is_active', v_next_is_active
  );

END;
$$;


-- ============================================================
-- 2. PUBLIC INVOKER SARMALAYICI (089 ile aynı)
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_question_edit(
  p_question_id uuid,
  p_question_text text DEFAULT NULL,
  p_option_a text DEFAULT NULL,
  p_option_b text DEFAULT NULL,
  p_option_c text DEFAULT NULL,
  p_option_d text DEFAULT NULL,
  p_option_e text DEFAULT NULL,
  p_correct_answer text DEFAULT NULL,
  p_difficulty text DEFAULT NULL,
  p_cognitive_type text DEFAULT NULL,
  p_quality_level text DEFAULT NULL,
  p_primary_question_type text DEFAULT NULL,
  p_secondary_question_type text DEFAULT NULL,
  p_estimated_solve_time_seconds integer DEFAULT NULL,
  p_is_new_generation boolean DEFAULT NULL,
  p_has_visual boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.admin_question_edit(
    p_question_id,
    p_question_text,
    p_option_a,
    p_option_b,
    p_option_c,
    p_option_d,
    p_option_e,
    p_correct_answer,
    p_difficulty,
    p_cognitive_type,
    p_quality_level,
    p_primary_question_type,
    p_secondary_question_type,
    p_estimated_solve_time_seconds,
    p_is_new_generation,
    p_has_visual
  );
$$;


-- ============================================================
-- 3. GÜVENLİ YENİDEN ONAY RPC: admin_question_requalify
--
--    'needs_review' -> 'approved' YALNIZCA.
--    is_active=FALSE KALIR (öğrenciye otomatik açılmaz; yayın için
--    040 activate ayrı ve insan adımıdır -> eski/kararsız onayın
--    değiştirilmiş soruyu kendiliğinden yayımlaması engellenir).
--    İzin: questions.approve. Audit: question.requalify (atomik).
-- ============================================================

CREATE OR REPLACE FUNCTION private.admin_question_requalify(
  p_question_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_question public.questions%ROWTYPE;
  v_before jsonb;
  v_after jsonb;
  v_audit_id uuid;
BEGIN

  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  IF NOT private.current_user_has_admin_permission('questions.approve') THEN
    RAISE EXCEPTION 'Question approval permission required.'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
  INTO v_question
  FROM public.questions q
  WHERE q.id = p_question_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Question not found.'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_question.approval_status = 'approved' THEN

    RETURN jsonb_build_object(
      'status', 'already_approved',
      'question_id', v_question.id,
      'question_code', v_question.question_code,
      'approval_status', 'approved',
      'is_active', v_question.is_active
    );

  END IF;

  IF v_question.approval_status <> 'needs_review' THEN
    RAISE EXCEPTION 'Question is not in re-review state.'
      USING ERRCODE = '22023';
  END IF;

  v_before := jsonb_build_object(
    'approval_status', v_question.approval_status,
    'is_active', v_question.is_active
  );

  UPDATE public.questions
  SET
    approval_status = 'approved',
    updated_at = now()
  WHERE id = p_question_id;

  v_after := jsonb_build_object(
    'approval_status', 'approved',
    'is_active', false
  );

  -- Atomik audit: mutation + audit aynı transaction.
  INSERT INTO public.admin_audit_log (
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    before_data,
    after_data
  )
  VALUES (
    v_user_id,
    'question.requalify',
    'question',
    p_question_id,
    v_before,
    v_after
  )
  RETURNING id
  INTO v_audit_id;

  RETURN jsonb_build_object(
    'status', 'requalified',
    'question_id', p_question_id,
    'question_code', v_question.question_code,
    'audit_id', v_audit_id,
    'approval_status', 'approved',
    'is_active', false
  );

END;
$$;


-- ============================================================
-- 4. PUBLIC INVOKER SARMALAYICI — admin_question_requalify
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_question_requalify(
  p_question_id uuid
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.admin_question_requalify(
    p_question_id
  );
$$;


-- ============================================================
-- 5. EXECUTE GRANT'LARI (canonical desen 040/089)
-- ============================================================

-- private SECURITY DEFINER: PUBLIC/anon'e kapalı; authenticated ve
-- service_role çağırabilir (public INVOKER sarmalayıcı rolüyle taşır).
REVOKE ALL
ON FUNCTION private.admin_question_edit(uuid, text, text, text, text, text,
                                        text, text, text, text, text, text,
                                        text, integer, boolean, boolean)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION private.admin_question_edit(uuid, text, text, text, text, text,
                                        text, text, text, text, text, text,
                                        text, integer, boolean, boolean)
FROM anon;

GRANT EXECUTE
ON FUNCTION private.admin_question_edit(uuid, text, text, text, text, text,
                                        text, text, text, text, text, text,
                                        text, integer, boolean, boolean)
TO authenticated;

GRANT EXECUTE
ON FUNCTION private.admin_question_edit(uuid, text, text, text, text, text,
                                        text, text, text, text, text, text,
                                        text, integer, boolean, boolean)
TO service_role;

REVOKE ALL
ON FUNCTION private.admin_question_requalify(uuid)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION private.admin_question_requalify(uuid)
FROM anon;

GRANT EXECUTE
ON FUNCTION private.admin_question_requalify(uuid)
TO authenticated;

GRANT EXECUTE
ON FUNCTION private.admin_question_requalify(uuid)
TO service_role;

-- public INVOKER sarmalayıcılar: authenticated admin'ler çağırır.
REVOKE ALL
ON FUNCTION public.admin_question_edit(uuid, text, text, text, text, text,
                                       text, text, text, text, text, text,
                                       text, integer, boolean, boolean)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.admin_question_edit(uuid, text, text, text, text, text,
                                       text, text, text, text, text, text,
                                       text, integer, boolean, boolean)
FROM anon;

GRANT EXECUTE
ON FUNCTION public.admin_question_edit(uuid, text, text, text, text, text,
                                       text, text, text, text, text, text,
                                       text, integer, boolean, boolean)
TO authenticated;

REVOKE ALL
ON FUNCTION public.admin_question_requalify(uuid)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.admin_question_requalify(uuid)
FROM anon;

GRANT EXECUTE
ON FUNCTION public.admin_question_requalify(uuid)
TO authenticated;


COMMIT;