-- 044_fix_ai_worker_report_service_role.sql
-- Altın Kalemler
--
-- AI worker output report fonksiyonunun server-side
-- service_role tarafından okunabilmesini sağlar.
--
-- Önceki davranış:
-- - Yalnızca admin permission kontrolü vardı.
-- - Server-side worker service_role ile ingestion yapabiliyor,
--   fakat rapor okuyamıyordu.
--
-- Yeni davranış:
-- - service_role erişebilir.
-- - ai.manage / questions.approve / questions.edit
--   yetkili adminler erişmeye devam eder.
-- - anon erişemez.
-- - Soru production'a yayınlanmaz; yalnızca raporlama düzeltmesidir.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_ai_worker_output_report(
  p_worker_output_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $function$
DECLARE
  v_result jsonb;
BEGIN

  -- =======================================================
  -- CALLER
  -- =======================================================

  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
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
     )
  THEN

    RAISE EXCEPTION
      'AI worker or admin permission required.';

  END IF;


  -- =======================================================
  -- REPORT
  -- =======================================================

  SELECT jsonb_build_object(

    'worker_output',
    jsonb_build_object(

      'id',
      o.id,

      'ai_job_id',
      o.ai_job_id,

      'status',
      o.status,

      'provider_name',
      o.provider_name,

      'model_name',
      o.model_name,

      'prompt_version',
      o.prompt_version,

      'worker_version',
      o.worker_version,

      'requested_question_count',
      o.requested_question_count,

      'received_question_count',
      o.received_question_count,

      'valid_question_count',
      o.valid_question_count,

      'invalid_question_count',
      o.invalid_question_count,

      'inserted_question_count',
      o.inserted_question_count,

      'duplicate_question_count',
      o.duplicate_question_count,

      'remaining_question_count',
      o.remaining_question_count,

      'retry_required',
      o.retry_required,

      'validation_summary',
      o.validation_summary,

      'received_at',
      o.received_at,

      'validated_at',
      o.validated_at,

      'ingested_at',
      o.ingested_at
    ),

    'candidates',
    (
      SELECT COALESCE(
        jsonb_agg(

          jsonb_build_object(

            'candidate_index',
            c.candidate_index,

            'candidate_key',
            c.candidate_key,

            'validation_status',
            c.validation_status,

            'validation_errors',
            c.validation_errors,

            'validation_warnings',
            c.validation_warnings,

            'staging_question_id',
            c.staging_question_id
          )

          ORDER BY c.candidate_index
        ),

        '[]'::jsonb
      )

      FROM public.ai_worker_candidate_results c

      WHERE c.worker_output_id =
            o.id
    )

  )

  INTO v_result

  FROM public.ai_worker_outputs o

  WHERE o.id =
        p_worker_output_id;


  IF v_result IS NULL THEN

    RAISE EXCEPTION
      'AI worker output not found.';

  END IF;


  RETURN v_result;

END;
$function$;


-- =========================================================
-- EXECUTE PERMISSIONS
-- =========================================================

REVOKE ALL
ON FUNCTION public.get_ai_worker_output_report(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_ai_worker_output_report(uuid)
TO authenticated;

GRANT EXECUTE
ON FUNCTION public.get_ai_worker_output_report(uuid)
TO service_role;


COMMENT ON FUNCTION public.get_ai_worker_output_report(uuid)
IS
'Returns an AI worker ingestion report for service-role workers or authorized admins.';


COMMIT;