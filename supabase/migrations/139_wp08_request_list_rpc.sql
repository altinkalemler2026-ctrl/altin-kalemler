-- ============================================================
-- 139_wp08_request_list_rpc.sql
-- Altın Kalemler — WP-08: üretim talepleri salt-okunur liste RPC
--
-- Dar ek: /admin/uretim-talepleri ekranı için tek salt-okunur
-- fonksiyon. Yazma yolu yok; SECURITY DEFINER + iç izin kontrolü
-- (ai.manage VEYA questions.approve). Her talep için talep + dispatch
-- + iş + (varsa) paket bağlantı durumları tek satırda döner; UI
-- katmanı sınıflandırmayı classify_ai_production_status ile yapar.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.list_question_generation_requests(
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  request_id uuid,
  request_status text,
  requested_quantity integer,
  generated_count integer,
  producer_type text,
  dispatch_mode text,
  dispatch_id uuid,
  dispatch_status text,
  dispatch_requested integer,
  dispatch_inserted integer,
  dispatch_invalid integer,
  dispatch_duplicate integer,
  ai_job_id uuid,
  ai_job_status text,
  ai_job_attempts integer,
  ai_job_error_code text,
  batch_id uuid,
  batch_count integer,
  last_error_message text,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT private.current_user_has_admin_permission('ai.manage')
     AND NOT private.current_user_has_admin_permission('questions.approve')
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  RETURN QUERY
  WITH latest_dispatch AS (
    SELECT DISTINCT ON (d.generation_request_id)
      d.generation_request_id, d.id, d.status, d.requested_quantity,
      d.inserted_quantity, d.invalid_quantity, d.duplicate_quantity, d.error_message
    FROM public.ai_question_generation_dispatches d
    ORDER BY d.generation_request_id, d.created_at DESC
  ),
  latest_job AS (
    SELECT DISTINCT ON (j.generation_request_id)
      j.generation_request_id, j.id, j.status, j.attempt_count, j.error_code
    FROM public.ai_jobs j
    WHERE j.job_type = 'question_generation'
      AND j.generation_request_id IS NOT NULL
    ORDER BY j.generation_request_id, j.created_at DESC
  ),
  batch_counts AS (
    SELECT b.generation_request_id, count(*) AS batch_count
    FROM public.candidate_question_batches b
    WHERE b.generation_request_id IS NOT NULL
    GROUP BY b.generation_request_id
  )
  SELECT
    r.id,
    r.request_status,
    r.requested_question_count,
    COALESCE(r.generated_candidate_count, 0),
    r.producer_type,
    r.dispatch_mode,
    d.id,
    d.status,
    d.requested_quantity,
    d.inserted_quantity,
    d.invalid_quantity,
    d.duplicate_quantity,
    j.id,
    j.status,
    j.attempt_count,
    j.error_code,
    bc.generation_request_id,
    COALESCE(bc.batch_count, 0)::integer,
    d.error_message,
    r.created_at,
    r.updated_at
  FROM public.question_generation_requests r
  LEFT JOIN latest_dispatch d ON d.generation_request_id = r.id
  LEFT JOIN latest_job j ON j.generation_request_id = r.id
  LEFT JOIN batch_counts bc ON bc.generation_request_id = r.id
  ORDER BY r.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)::int;
END;
$$;

REVOKE ALL ON FUNCTION public.list_question_generation_requests(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_question_generation_requests(integer) TO authenticated;

COMMIT;
