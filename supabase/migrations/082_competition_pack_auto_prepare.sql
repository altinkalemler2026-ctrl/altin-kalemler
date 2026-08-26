-- ============================================================
-- 082_competition_pack_auto_prepare.sql
-- Altin Kalemler - Competition Pack Auto-Prepare
--
-- Purpose:
-- When the second user joins and triggers a match,
-- prepare_competition_pack is called atomically within the
-- same transaction. This eliminates the gap where the client
-- had to call prepare_competition_pack separately.
--
-- Security:
-- - prepare_competition_pack authenticated EXECUTE revoked
--   (no longer needed — called internally by join_matchmaking_queue)
-- - service_role EXECUTE preserved for admin use
-- - join_matchmaking_queue SECURITY DEFINER calls pack internally
-- - Pack failure rolls back entire match (atomic)
--
-- Migration type: FORWARD ONLY
-- ============================================================

BEGIN;

-- ============================================================
-- 1. UPDATE join_matchmaking_queue — add pack auto-prepare
--
-- Exact source from local DB (post-080 hardening), with only
-- the PERFORM prepare_competition_pack(v_comp_id) added after
-- competition_players insert and before queue status update.
-- ============================================================

CREATE OR REPLACE FUNCTION public.join_matchmaking_queue(p_subject_id uuid)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
AS $function$
declare
  v_user      uuid;
  v_grade     smallint;
  v_subject   uuid;
  v_queue_id  uuid;
  r_partner   public.matchmaking_queue%rowtype;
  v_rule_set  uuid;
  v_comp_id   uuid;
  v_comp_code text;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  -- FAZ4: kuyruk yazimi korumasi.
  perform public._faz4_consume_rate_limit('queue_join', 10, 300);

  if p_subject_id is null then
    raise exception 'Ders zorunludur.' using errcode = '22004';
  end if;

  select s.id into v_subject
    from public.subjects s
   where s.id = p_subject_id
     and s.is_active = true;

  if v_subject is null then
    raise exception 'Ders bulunamadi veya pasif.'
      using errcode = 'P0001';
  end if;

  select sp.grade_level into v_grade
    from public.student_profiles sp
   where sp.id = v_user;

  if v_grade is null then
    raise exception 'Ogrenci profili bulunamadi; kuyruğa girilemez.'
      using errcode = 'P0001';
  end if;

  -- Zaten bekliyor mu? (idempotent yeniden deneme noktasi)
  select mq.id into v_queue_id
    from public.matchmaking_queue mq
   where mq.user_id = v_user
     and mq.status = 'waiting'
   order by mq.joined_at desc
   limit 1;

  if v_queue_id is null then
    insert into public.matchmaking_queue
      (user_id, grade_level, subject_id, queue_type,
       status, preferences, expires_at)
    values
      (v_user, v_grade, v_subject, 'standard',
       'waiting', '{}'::jsonb, now() + interval '15 minutes')
    returning id into v_queue_id;
  else
    -- Eslesmeden once kendi satirimizi kilitle.
    perform 1
      from public.matchmaking_queue mq
     where mq.id = v_queue_id
       and mq.status = 'waiting'
       for update;

    if not found then
      select mq.id into v_queue_id
        from public.matchmaking_queue mq
       where mq.user_id = v_user
         and mq.status = 'waiting'
       order by mq.joined_at desc
       limit 1;
    end if;
  end if;

  if v_queue_id is null then
    select mq.id into v_queue_id
      from public.matchmaking_queue mq
     where mq.user_id = v_user
     order by mq.joined_at desc
     limit 1;
  end if;

  -- Eslesme serilestirme: ayni (grade,subject) kovasinda tek islem.
  perform pg_advisory_xact_lock(
    hashtextextended('faz5mm:' || v_grade::text || ':' || v_subject::text, 0)
  );

  select * into r_partner
    from public.matchmaking_queue mq2
   where mq2.id is distinct from v_queue_id
     and mq2.status = 'waiting'
     and mq2.grade_level = v_grade
     and mq2.subject_id = v_subject
     and mq2.user_id <> v_user
     and (mq2.expires_at is null or mq2.expires_at > now())
   order by mq2.joined_at asc
   limit 1;

  if r_partner.id is null then
    return jsonb_build_object(
      'status', 'waiting',
      'queue_id', v_queue_id,
      'grade_level', v_grade,
      'subject_id', v_subject
    );
  end if;

  -- Partner satirini kilitle (READ COMMITTED altinda taze deger).
  select * into r_partner
    from public.matchmaking_queue mq2
   where mq2.id = r_partner.id
     and mq2.status = 'waiting'
     for update;

  if r_partner.id is null then
    return jsonb_build_object(
      'status', 'waiting',
      'queue_id', v_queue_id,
      'grade_level', v_grade,
      'subject_id', v_subject
    );
  end if;

  -- Yarisma kurulumu (question_count = 5, MVP #8).
  select srs.id into v_rule_set
    from public.scoring_rule_sets srs
   where srs.is_active = true
   order by (srs.rule_set_code = 'faz5_default') desc,
            srs.created_at asc
   limit 1;

  if v_rule_set is null then
    raise exception 'Aktif puanlama kural seti yok; yarisma kurulamaz.'
      using errcode = 'P0001';
  end if;

  v_comp_code :=
    'F5-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count)
  values
    (v_comp_code, 'one_vs_one', v_grade,
     v_subject, v_rule_set, 'waiting', 5)
  returning id into v_comp_id;

  insert into public.competition_players
    (competition_id, user_id, player_slot)
  values
    (v_comp_id, r_partner.user_id, 1),
    (v_comp_id, v_user, 2);

  -- ========================================================
  -- AUTO-PREPARE: Pack hazirlik ayni transaction icinde.
  -- Basarisizsa tum match rollback olur (atomik).
  -- ========================================================
  perform public.prepare_competition_pack(v_comp_id);

  update public.matchmaking_queue mq
     set status = 'matched',
         matched_at = now()
   where mq.id in (r_partner.id, v_queue_id);

  return jsonb_build_object(
    'status', 'matched',
    'queue_id', v_queue_id,
    'competition_id', v_comp_id,
    'competition_code', v_comp_code,
    'grade_level', v_grade,
    'subject_id', v_subject
  );
end;
$function$;

-- ============================================================
-- 2. REVOKE authenticated EXECUTE on prepare_competition_pack
--
-- No longer needed — called internally by join_matchmaking_queue
-- (SECURITY DEFINER, owner = postgres). This prevents direct
-- client calls and tightens least-privilege.
-- ============================================================

REVOKE EXECUTE
  ON FUNCTION public.prepare_competition_pack(uuid)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.prepare_competition_pack(uuid)
  TO service_role;

COMMIT;
