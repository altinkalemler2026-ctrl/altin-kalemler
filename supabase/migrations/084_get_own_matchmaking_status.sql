-- 084: Read-only matchmaking status RPC.
--
-- Polling icin kullanilir: kullanici beklerken her 3 saniyede bu
-- RPC cagrilir. INSERT/UPDATE/DELETE yapmaz, rate-limit tuketmez.
-- Rakip PII dondurmez; competition_id/code yalnizca participant icin doner.

CREATE OR REPLACE FUNCTION public.get_own_matchmaking_status(p_subject_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_user uuid;
  v_queue_row record;
  v_comp_row record;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'kimlik dogrulamasi gerekli'
      USING ERRCODE = '42501';
  END IF;

  IF p_subject_id IS NULL THEN
    RAISE EXCEPTION 'subject_id bos olamaz';
  END IF;

  -- Validate subject exists and is active
  IF NOT EXISTS (
    SELECT 1 FROM public.subjects
    WHERE id = p_subject_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'ders bulunamadi veya pasif';
  END IF;

  -- Find the user's most recent non-expired/non-cancelled queue row for this subject.
  -- If the most recent row is expired or cancelled, treat as not_queued.
  SELECT id, status, matched_at
  INTO v_queue_row
  FROM public.matchmaking_queue
  WHERE user_id = v_user
    AND subject_id = p_subject_id
    AND status IN ('waiting', 'matched')
    AND (expires_at IS NULL OR expires_at > now())
  ORDER BY joined_at DESC
  LIMIT 1;

  IF v_queue_row IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'not_queued',
      'competition_id', null,
      'competition_code', null
    );
  END IF;

  IF v_queue_row.status = 'waiting' THEN
    RETURN jsonb_build_object(
      'status', 'waiting',
      'competition_id', null,
      'competition_code', null
    );
  END IF;

  -- status = 'matched' — check if user is a participant
  SELECT c.id AS competition_id, c.competition_code
  INTO v_comp_row
  FROM public.competitions c
  INNER JOIN public.competition_players cp
    ON cp.competition_id = c.id
  WHERE cp.user_id = v_user
    AND c.status IN ('waiting', 'active')
  ORDER BY c.created_at DESC
  LIMIT 1;

  IF v_comp_row IS NULL THEN
    -- matched but no competition found — transitional state
    RETURN jsonb_build_object(
      'status', 'waiting',
      'competition_id', null,
      'competition_code', null
    );
  END IF;

  RETURN jsonb_build_object(
    'status', 'matched',
    'competition_id', v_comp_row.competition_id,
    'competition_code', v_comp_row.competition_code
  );
END;
$$;

-- Security: revoke all, then grant only to authenticated and service_role
REVOKE ALL ON FUNCTION public.get_own_matchmaking_status(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_own_matchmaking_status(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_own_matchmaking_status(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_own_matchmaking_status(uuid) TO service_role;
