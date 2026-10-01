-- 130_faz35b_review_actions_m1_m4.sql
-- Altın Kalemler
--
-- Faz 35A denetimiyle tespit edilen M1-M4 gerçek açıklarının
-- güvenli onarımı. Append-only: 038/039/089/007 DEĞİŞTİRİLMEZ,
-- yalnız CREATE OR REPLACE ile yeni gövde tanımlanır.
--
-- Kapsam ve dayanak (docs/reports/faz35a-admin-aday-karar-akisi-sozlesme-denetimi.md):
--
--   M1  public.validate_question_promotion() trigger'ı
--       question_promotion_requests tablosundadır (0 satır, ölü kod).
--       review_and_promote_ai_question doğrudan questions'a yazdığı
--       için o kapıları ATLAR. Sonuç: yüksek/bloklanmış telif riskli ya da
--       başka bir doğrulayıcıdan 'fail' almış aday promote edilebilir.
--       -> Kontroller DOĞRU KAYNAKTA (5 doğrulama tablosu + telif +
--          validation sonuçları) ve promote ile AYNI TRANSACTION'da
--          uygulanır.
--
--   M2  request_changes dalında idempotency koruması yoktu; tekrar
--       tıklama yeni ai_question_final_reviews + ai_validation_results
--       satırı üretiyordu.
--       -> Bekleyen değişiklik talebi tekrar gelirse mevcut sonuç
--          döndürülür, yeni denetim satırı yazılmaz.
--
--   M3  Karar fonksiyonu admin_audit_log'a yazmıyordu (089'da yalnız
--       admin_question_edit / admin_question_requalify yazıyor).
--       Admin panelinin denetim ekranı karar geçmişini göremiyordu.
--       -> Üç karar da aktörlü, before/after'lı, aynı transaction'da
--          yazılır.
--
--   M4  (a) evaluate_ai_question_readiness her çağrıda
--          ai_validation_results'a korumasız bir satır INSERT ediyordu;
--          review fonksiyonu her karar öncesi onu çağırdığı için tek
--          approve çağrısı iki satır üretiyordu.
--          -> (staging_question_id, deterministic, overall) için
--             UPDATE-then-INSERT (idempotent).
--       (b) Batch sayaçları intake anında bir kez hesaplanıyor ve
--          karardan SONRA karar durumunu yansıtmıyordu.
--          -> Sayaçların ANLAMI DEĞİŞTİRİLMEZ (inserted_items =
--             "staging'e alındı" gerçeğidir ve karardan sonra da
--             doğrudur). Uydurma sayaç/status yazılmaz: status CHECK'i
--             'promoted' içermez. Bunun yerine karar gerçeği
--             ai_question_staging.staging_status'tan hesaplanıp
--             validation_summary -> 'human_final_review' altına
--             AYRI bir ad alanında yazılır (mevcut anahtarlar korunur).
--
-- Güvenlik:
-- - Hiçbir yeni PUBLIC fonksiyon eklenmez; iki yeni fonksiyon da
--   private şemadadır ve PUBLIC/anon/service_role'dan REVOKE edilir.
-- - public.review_and_promote_ai_question imzası DEĞİŞMEZ; bu
--   nedenle public şema tipleri (src/lib/supabase/types.ts) değişmez.
-- - Otomatik yayın yok: promote hâlâ is_active=false bırakır.
-- - Mevcut 038/039 grant'ları korunur.

BEGIN;


-- =========================================================
-- 1. M1 YARDIMCI: PROMOTE BLOKLAYICI TESPİTİ
--    Doğru kaynaktan okur, readiness özetine güvenmez.
-- =========================================================

CREATE OR REPLACE FUNCTION private.ai_question_promotion_blockers(
  p_staging_question_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_answer_status       text;
  v_curriculum_status   text;
  v_solve_time_status   text;
  v_originality_status  text;
  v_quality_status      text;

  v_missing_gates jsonb := '[]'::jsonb;
  v_blockers      jsonb := '[]'::jsonb;

  v_failing_validation  boolean := false;
  v_dangerous_copyright boolean := false;
BEGIN

  -- 038 ile BIREBIR ayni "en son kosu" siralamasi.
  SELECT r.consensus_status
  INTO v_answer_status
  FROM public.ai_answer_verification_runs r
  WHERE r.staging_question_id = p_staging_question_id
  ORDER BY r.updated_at DESC NULLS LAST, r.created_at DESC
  LIMIT 1;

  SELECT r.status
  INTO v_curriculum_status
  FROM public.ai_curriculum_fit_runs r
  WHERE r.staging_question_id = p_staging_question_id
  ORDER BY r.updated_at DESC, r.created_at DESC
  LIMIT 1;

  SELECT r.status
  INTO v_solve_time_status
  FROM public.ai_solve_time_verification_runs r
  WHERE r.staging_question_id = p_staging_question_id
  ORDER BY r.updated_at DESC, r.created_at DESC
  LIMIT 1;

  SELECT r.status
  INTO v_originality_status
  FROM public.ai_originality_verification_runs r
  WHERE r.staging_question_id = p_staging_question_id
  ORDER BY r.updated_at DESC, r.created_at DESC
  LIMIT 1;

  SELECT r.status
  INTO v_quality_status
  FROM public.ai_question_quality_runs r
  WHERE r.staging_question_id = p_staging_question_id
  ORDER BY r.updated_at DESC, r.created_at DESC
  LIMIT 1;

  -- -------------------------------------------------------
  -- Zorunlu dogrulama kapilari
  -- -------------------------------------------------------

  IF v_answer_status IS DISTINCT FROM 'verified' THEN
    v_missing_gates :=
      v_missing_gates || jsonb_build_array('answer_verification');
    v_blockers :=
      v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'missing_verification_gate',
          'gate', 'answer_verification',
          'status', COALESCE(v_answer_status, 'not_started'),
          'message',
            'Mandatory AI verification gate has not passed: answer_verification.'
        )
      );
  END IF;

  IF v_curriculum_status IS DISTINCT FROM 'verified' THEN
    v_missing_gates :=
      v_missing_gates || jsonb_build_array('curriculum_fit');
    v_blockers :=
      v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'missing_verification_gate',
          'gate', 'curriculum_fit',
          'status', COALESCE(v_curriculum_status, 'not_started'),
          'message',
            'Mandatory AI verification gate has not passed: curriculum_fit.'
        )
      );
  END IF;

  IF v_solve_time_status IS DISTINCT FROM 'verified' THEN
    v_missing_gates :=
      v_missing_gates || jsonb_build_array('solve_time_verification');
    v_blockers :=
      v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'missing_verification_gate',
          'gate', 'solve_time_verification',
          'status', COALESCE(v_solve_time_status, 'not_started'),
          'message',
            'Mandatory AI verification gate has not passed: solve_time_verification.'
        )
      );
  END IF;

  IF v_originality_status IS DISTINCT FROM 'verified' THEN
    v_missing_gates :=
      v_missing_gates || jsonb_build_array('originality_verification');
    v_blockers :=
      v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'missing_verification_gate',
          'gate', 'originality_verification',
          'status', COALESCE(v_originality_status, 'not_started'),
          'message',
            'Mandatory AI verification gate has not passed: originality_verification.'
        )
      );
  END IF;

  IF v_quality_status IS DISTINCT FROM 'verified' THEN
    v_missing_gates :=
      v_missing_gates || jsonb_build_array('question_quality');
    v_blockers :=
      v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'missing_verification_gate',
          'gate', 'question_quality',
          'status', COALESCE(v_quality_status, 'not_started'),
          'message',
            'Mandatory AI verification gate has not passed: question_quality.'
        )
      );
  END IF;

  -- -------------------------------------------------------
  -- FAIL dogrulama sonucu var mi?
  -- 040'in trigger'indaki kontrolun promote yolundaki karsiligi.
  -- -------------------------------------------------------

  SELECT EXISTS (
    SELECT 1
    FROM public.ai_validation_results v
    WHERE v.staging_question_id = p_staging_question_id
      AND v.result = 'fail'
  )
  INTO v_failing_validation;

  IF v_failing_validation THEN
    v_blockers :=
      v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'failing_validation_result',
          'message',
            'Question cannot be promoted: a failing validation result exists.'
        )
      );
  END IF;

  -- -------------------------------------------------------
  -- Yuksek / bloklanmis telif-ozgunluk riski var mi?
  -- risk_level CHECK: unknown|low|medium|high|blocked
  -- -------------------------------------------------------

  SELECT EXISTS (
    SELECT 1
    FROM public.copyright_reviews c
    WHERE c.staging_question_id = p_staging_question_id
      AND c.risk_level IN ('high', 'blocked')
  )
  INTO v_dangerous_copyright;

  IF v_dangerous_copyright THEN
    v_blockers :=
      v_blockers || jsonb_build_array(
        jsonb_build_object(
          'code', 'dangerous_copyright_risk',
          'message',
            'Question cannot be promoted: high or blocked copyright/originality risk exists.'
        )
      );
  END IF;

  RETURN jsonb_build_object(
    'staging_question_id', p_staging_question_id,
    'missing_verification_gates', v_missing_gates,
    'failing_validation_exists', v_failing_validation,
    'dangerous_copyright_exists', v_dangerous_copyright,
    'can_promote', v_blockers = '[]'::jsonb,
    'blocking_reasons', v_blockers
  );

END;
$function$;


REVOKE ALL
  ON FUNCTION private.ai_question_promotion_blockers(uuid)
  FROM PUBLIC, anon, service_role;

GRANT EXECUTE
  ON FUNCTION private.ai_question_promotion_blockers(uuid)
  TO authenticated;


-- =========================================================
-- 2. M4b YARDIMCI: BATCH KARAR ÖZETİ SENKRONU
--
--    DİKKAT: candidate_question_batches.total_items / valid_items /
--    invalid_items / inserted_items / duplicate_items birer INTAKE
--    gerçeğidir (117/118/123/124/126 hepsinde tek seferlik hesaplanır)
--    ve karardan sonra da doğrudur. Bu migration sayaçlara DOKUNMAZ.
--
--    status CHECK'i 'promoted' icermedigi icin yeni bir status
--    de UYDURULMAZ.
--
--    Karar gercegi tek kaynaktan (ai_question_staging.staging_status)
--    hesaplanip validation_summary -> 'human_final_review' altina
--    yazilir; mevcut anahtarlar (received/valid/invalid/inserted/
--    duplicates/preflight) korunur.
-- =========================================================

CREATE OR REPLACE FUNCTION private.sync_candidate_batch_review_summary(
  p_staging_question_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_batch_id   uuid;
  v_batch_ids  uuid[];
  v_total      integer;
  v_promoted   integer;
  v_rejected   integer;
  v_pending    integer;
  v_undecided  integer;
  v_row_count  integer;
  v_counter_total integer;
BEGIN

  SELECT COALESCE(array_agg(DISTINCT r.batch_id), '{}'::uuid[])
  INTO v_batch_ids
  FROM public.candidate_batch_candidate_results r
  WHERE r.staging_question_id = p_staging_question_id;

  IF COALESCE(array_length(v_batch_ids, 1), 0) = 0 THEN
    RETURN;
  END IF;

  FOREACH v_batch_id IN ARRAY v_batch_ids LOOP

    -- Karar dagilimi: TEK kaynak ai_question_staging.staging_status
    SELECT
      count(*),
      count(*) FILTER (WHERE s.staging_status = 'promoted'),
      count(*) FILTER (WHERE s.staging_status = 'rejected'),
      count(*) FILTER (WHERE s.staging_status = 'needs_review'),
      count(*) FILTER (
        WHERE s.staging_status IS NULL
           OR s.staging_status NOT IN ('promoted', 'rejected', 'needs_review')
      )
    INTO v_total, v_promoted, v_rejected, v_pending, v_undecided
    FROM public.candidate_batch_candidate_results r
    LEFT JOIN public.ai_question_staging s
           ON s.id = r.staging_question_id
    WHERE r.batch_id = v_batch_id;

    SELECT count(*)
    INTO v_row_count
    FROM public.candidate_batch_candidate_results
    WHERE batch_id = v_batch_id;

    SELECT b.total_items
    INTO v_counter_total
    FROM public.candidate_question_batches b
    WHERE b.id = v_batch_id;

    -- Sayaçlara YAZILMAZ; yalnizca intake gercegiyle satir sayisi
    -- tutarli mi diye GOZLENIR (uydurma yok, olcum var).
    UPDATE public.candidate_question_batches b
    SET
      validation_summary =
        COALESCE(b.validation_summary, '{}'::jsonb)
        || jsonb_build_object(
            'human_final_review', jsonb_build_object(
              'total_candidates', v_total,
              'promoted', v_promoted,
              'rejected', v_rejected,
              'changes_requested_pending', v_pending,
              'undecided', v_undecided,
              'source', 'ai_question_staging.staging_status',
              'intake_total_items', v_counter_total,
              'intake_counters_match_rows',
                (v_counter_total IS NOT DISTINCT FROM v_row_count)
            )
          ),

      metadata =
        COALESCE(b.metadata, '{}'::jsonb)
        || jsonb_build_object(
            'human_final_review', jsonb_build_object(
              'synced_at', clock_timestamp(),
              'source', 'faz35b_migration_130'
            )
          )
    WHERE b.id = v_batch_id;

  END LOOP;

END;
$function$;


REVOKE ALL
  ON FUNCTION private.sync_candidate_batch_review_summary(uuid)
  FROM PUBLIC, anon, service_role;

GRANT EXECUTE
  ON FUNCTION private.sync_candidate_batch_review_summary(uuid)
  TO authenticated;


-- =========================================================
-- 3. M4a: evaluate_ai_question_readiness IDEMPOTENT
--
--    Yalnizca son "overall validation result" yazimi degisir:
--    korumasiz INSERT -> UPDATE-then-INSERT.
--    readiness_runs upsert'i, staging metadata'si, review_queue
--    ekleme korumasi ve donus payload'i DEGISMEZ.
--
--    Not: bilincli olarak UNIQUE INDEX EKLENMEZ. Legacy veride
--    (deterministic, overall) tekrari varsa index eklemek migration
--    zincirini kirardi; UPDATE-then-INSERT ayni idempotency'yi
--    index gerektirmeden verir.
-- =========================================================

CREATE OR REPLACE FUNCTION private.evaluate_ai_question_readiness(
  p_staging_question_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
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
  -- Bunun READINESS ile ayni sey olmadigini ozellikle
  -- ayiriyoruz.
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
  -- OVERALL VALIDATION RESULT  (M4a: IDEMPOTENT)
  --
  -- 038'de bu INSERT korumasizdi; her cagri yeni satir uretiyordu
  -- ve review_and_promote_ai_question her karar oncesi bu fonksiyonu
  -- cagirdigi icin tek approve cagrisi IKI satir olusturuyordu.
  -- Artik (staging_question_id, deterministic, overall) anahtari
  -- UPDATE edilir; yoksa INSERT edilir.
  -- =======================================================

  UPDATE public.ai_validation_results
  SET
    ai_job_id =
      v_question.ai_job_id,

    result =
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

    score =
      v_readiness_score,

    summary =
      'Final deterministic AI question readiness evaluation completed.',

    details =
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
      ),

    created_at =
      clock_timestamp()

  WHERE staging_question_id =
        p_staging_question_id
    AND validator_type =
          'deterministic'
    AND validation_type =
          'overall';


  IF NOT FOUND THEN

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

  END IF;


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
$function$;


REVOKE ALL
  ON FUNCTION private.evaluate_ai_question_readiness(uuid)
  FROM PUBLIC, anon, service_role;

GRANT EXECUTE
  ON FUNCTION private.evaluate_ai_question_readiness(uuid)
  TO authenticated;


-- =========================================================
-- 4. M1 + M2 + M3 + M4b:
--    private.review_and_promote_ai_question
--
--    039'daki gövde korunur; şu değişiklikler yapılır:
--      M1  approve dalına, HİÇBİR yazma yapılmadan önce
--          private.ai_question_promotion_blockers() kapısı.
--      M2  request_changes dalının başına bekleyen talep koruması.
--      M3  üç karara da admin_audit_log INSERT'i.
--      M4b her kararın sonunda private.sync_candidate_batch_review_summary().
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
AS $function$
DECLARE
  v_user_id uuid;

  v_staging public.ai_question_staging%ROWTYPE;
  v_readiness public.ai_question_readiness_runs%ROWTYPE;

  v_question_id uuid;
  v_question_code text;

  v_review_id uuid;
  v_audit_id uuid;

  -- M1
  v_blockers jsonb;

  -- M2
  v_latest_review public.ai_question_final_reviews%ROWTYPE;

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
  -- REQUEST CHANGES  (M2: idempotent)
  -- =======================================================

  IF p_decision = 'request_changes' THEN

    -- M2
    -- Bekleyen bir değişiklik talebi zaten varsa (en son karar
    -- request_changes VE staging hâlâ needs_review) aynı isteğin
    -- tekrarıdır: yeni denetim satırı yazılmaz, mevcut sonuç
    -- döndürülür.
    SELECT *
    INTO v_latest_review
    FROM public.ai_question_final_reviews fr
    WHERE fr.staging_question_id = v_staging.id
    ORDER BY fr.reviewed_at DESC, fr.id DESC
    LIMIT 1;

    IF v_latest_review.id IS NOT NULL
       AND v_latest_review.decision = 'request_changes'
       AND v_staging.staging_status = 'needs_review'
    THEN

      RETURN jsonb_build_object(
        'status',
        'changes_requested',

        'final_review_id',
        v_latest_review.id,

        'staging_question_id',
        v_staging.id,

        'production_publication',
        false,

        'idempotent_replay',
        true
      );

    END IF;


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


    -- M3
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
      'staging_question.request_changes',
      'staging_question',
      v_staging.id,

      jsonb_build_object(
        'staging_status', v_staging.staging_status,
        'automatic_publication_allowed', false
      ),

      jsonb_build_object(
        'decision', 'request_changes',
        'final_review_id', v_review_id,
        'readiness_run_id', v_readiness.id,
        'readiness_status', v_readiness.readiness_status,
        'readiness_score', v_readiness.readiness_score,
        'review_notes', NULLIF(btrim(p_review_notes), ''),
        'staging_status', 'needs_review',
        'question_id', v_staging.final_question_id,
        'is_active', false,
        'student_visible', false,
        'production_publication', false,
        'automatic_publication_allowed', false
      )
    )
    RETURNING id
    INTO v_audit_id;


    -- M4b
    PERFORM private.sync_candidate_batch_review_summary(
      v_staging.id
    );


    RETURN jsonb_build_object(
      'status',
      'changes_requested',

      'final_review_id',
      v_review_id,

      'audit_id',
      v_audit_id,

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


    -- M3
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
      'staging_question.reject',
      'staging_question',
      v_staging.id,

      jsonb_build_object(
        'staging_status', v_staging.staging_status,
        'commercial_use_allowed', v_staging.commercial_use_allowed,
        'automatic_publication_allowed', false
      ),

      jsonb_build_object(
        'decision', 'reject',
        'final_review_id', v_review_id,
        'readiness_run_id', v_readiness.id,
        'readiness_status', v_readiness.readiness_status,
        'readiness_score', v_readiness.readiness_score,
        'review_notes', NULLIF(btrim(p_review_notes), ''),
        'staging_status', 'rejected',
        'commercial_use_allowed', false,
        'question_id', v_staging.final_question_id,
        'is_active', false,
        'student_visible', false,
        'production_publication', false,
        'automatic_publication_allowed', false
      )
    )
    RETURNING id
    INTO v_audit_id;


    -- M4b
    PERFORM private.sync_candidate_batch_review_summary(
      v_staging.id
    );


    RETURN jsonb_build_object(
      'status',
      'rejected',

      'final_review_id',
      v_review_id,

      'audit_id',
      v_audit_id,

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
  -- M1: PROMOTION BLOKLAYICI KAPISI
  --
  -- 040'taki public.validate_question_promotion trigger'i
  -- question_promotion_requests tablosundadır ve bu fonksiyon
  -- questions'a doğrudan yazdığı için o kapılar burada
  -- UYGULANMAMAZDI. Eksik zorunlu doğrulama, fail doğrulama
  -- sonucu ve high/blocked telif-ozgunluk riski kontrolleri
  -- DOĞRU KAYNAKTAN ve promote ile AYNI TRANSACTION'da,
  -- HİÇBİR YAZMA YAPILMADAN ÖNCE burada uygulanır.
  --
  -- Fail-closed: herhangi bir bloklayıcı varsa hiçbir tablo
  -- yazılmadan hata fırlatılır.
  -- =======================================================

  v_blockers :=
    private.ai_question_promotion_blockers(
      p_staging_question_id
    );


  IF NOT COALESCE((v_blockers ->> 'can_promote')::boolean, false) THEN

    RAISE EXCEPTION
      'Question cannot be promoted: blocking promotion gates failed: %',
      v_blockers -> 'blocking_reasons';

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
  -- M3: ADMIN DENETİM KAYDI (atomik, aktörlü)
  -- =======================================================

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
    'staging_question.approve',
    'staging_question',
    v_staging.id,

    jsonb_build_object(
      'staging_status', v_staging.staging_status,
      'final_question_id', v_staging.final_question_id,
      'automatic_publication_allowed', false
    ),

    jsonb_build_object(
      'decision', 'approve',
      'final_review_id', v_review_id,
      'readiness_run_id', v_readiness.id,
      'readiness_status', v_readiness.readiness_status,
      'readiness_score', v_readiness.readiness_score,
      'review_notes', NULLIF(btrim(p_review_notes), ''),
      'question_id', v_question_id,
      'question_code', v_question_code,
      'staging_status', 'promoted',
      'approval_status', 'approved',
      'is_active', false,
      'student_visible', false,
      'commercial_use_allowed', v_commercial_allowed,
      'production_publication', false,
      'automatic_publication_allowed', false
    )
  )
  RETURNING id
  INTO v_audit_id;


  -- =======================================================
  -- M4b: BATCH KARAR ÖZETİ SENKRONU
  -- =======================================================

  PERFORM private.sync_candidate_batch_review_summary(
    v_staging.id
  );


  -- =======================================================
  -- RESULT
  -- =======================================================

  RETURN jsonb_build_object(
    'status',
    'promoted',

    'final_review_id',
    v_review_id,

    'audit_id',
    v_audit_id,

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
$function$;


-- 039'daki grant modeli birebir korunur.
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
-- 5. KORUMA İNVARİYANTAYLA
--
--    Yeni PUBLIC yüzey açılmadığı ve private şema kapalı kaldığı
--    doğrulanır. Bu migration'ın güvenlik iddiası bu iki
--    invaryantın bozulmamasına dayanır.
-- =========================================================

DO $$
DECLARE
  v_leak text;
BEGIN

  -- grantee = 0 -> PUBLIC; 'PUBLIC' bir ROL olmadigi icin
  -- has_function_privilege ile sorgulanamaz, proacl acilmalidir.
  SELECT string_agg(
           format('%I.%I', n.nspname, p.proname),
           ', '
         )
  INTO v_leak
  FROM pg_proc p
  JOIN pg_namespace n
    ON n.oid = p.pronamespace
  WHERE p.proname IN (
    'ai_question_promotion_blockers',
    'sync_candidate_batch_review_summary',
    'review_and_promote_ai_question',
    'evaluate_ai_question_readiness'
  )
  AND (
    has_function_privilege('anon', p.oid, 'EXECUTE')
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.aclexplode(p.proacl) a
      WHERE a.grantee = 0
        AND a.privilege_type = 'EXECUTE'
    )
  );

  IF v_leak IS NOT NULL THEN
    RAISE EXCEPTION
      '130: private yüzey sızdı, rollback gerekir: %', v_leak;
  END IF;

END;
$$;


COMMIT;
