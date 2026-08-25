-- ============================================================
-- 078_faz5_league_rating_engine.sql
-- Altın Kalemler - Faz 5a
--
-- Yarisma sonu lig/rating puan motoru (MVP karar #2 ve #5):
--
--   - Rating SABIT TABLO ile uygulanir; Elo yok.
--     Tablo kaynagi: league_rule_sets satiri
--     'faz5_competition_rating' (configuration JSON):
--       win / loss / draw / forfeit_win / forfeit_loss
--     Satir yoksa veya pasifse gomulu varsayilanlar devrede:
--       win +24, loss -12, draw 0.
--   - Beraberlikte once bitiren kazanir kurali zaten
--     finalize icinde uygulanir (022); motor yalniz sonucu
--     okur, yeniden yorumlamaz.
--   - Puanlar student_league_memberships.current_points
--     uzerine yazilir; genel kapsam ('general') MVP'dir.
--   - Puan bandi degisirse (leagues.min/max_points) uyelik
--     kapatilir, yeni lige 'placement' uyeligi acilir ve
--     student_league_history'ye promotion/demotion yazilir.
--     Rank/percentile tabanli transition_rules MVP disidir.
--   - competition_point_changes('rating') kaydi UNIQUE
--     (competition_id,user_id,change_type) ile korunur;
--     tekrar finalize idempotentdir.
--
-- Cagri noktasi:
--   finalize_competition_if_ready 022 birebir yeniden
--   yazilir; SONUNA tek PERFORM ekleme yapilir. Fonksiyon
--   submit/akis RPC'leri (021/023) tarafindan cagrilmaya
--   devam eder; dogrudan istemci EXECUTE'u kapali kalir
--   (025 durumu korunur).
-- ============================================================

begin;


-- ============================================================
-- 1. SABIT RATING TABLOSU KAYDI (idempotent seed)
-- ============================================================

insert into public.league_rule_sets
  (rule_set_code, name, description, rule_type,
   applies_to_scope, configuration, is_active)
values
  ('faz5_competition_rating',
   'Faz 5 Yarışma Rating Tablosu',
   'Yarışma sonu sabit rating değişimi: win/loss/draw/forfeit.',
   'points',
   'general',
   jsonb_build_object(
     'win', 24,
     'loss', 12,
     'draw', 0,
     'forfeit_win', 24,
     'forfeit_loss', 12
   ),
   true)
on conflict (rule_set_code) do nothing;


-- ============================================================
-- 2. PUAN UYGULAYICI (yalnizca finalize cagirir)
--
-- Guvenlik:
--   - SECURITY DEFINER, search_path='' (tam niteleme).
--   - Dogrudan EXECUTE tum rollerden alinir (bolum 4).
-- ============================================================

create or replace function public._faz5_apply_competition_points(
  p_competition_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r_comp        public.competitions%rowtype;
  v_result_type text;
  v_winner      uuid;
  v_delta_map   jsonb;
  r_player      record;

  v_delta       integer;
  v_before      integer;
  v_after       integer;

  v_membership_id uuid;
  v_cur_league    uuid;
  v_cur_sort      integer;
  v_target        record;
begin
  select * into r_comp
    from public.competitions c
   where c.id = p_competition_id;

  if r_comp.id is null or r_comp.status <> 'completed' then
    return;
  end if;

  -- Idempotency hizli cikisi: bu yarisma icin rating yazildiysa dokunma.
  if exists (
       select 1
         from public.competition_point_changes cpc
        where cpc.competition_id = r_comp.id
          and cpc.change_type = 'rating'
     ) then
    return;
  end if;

  select cr.result_type, cr.winner_user_id
    into v_result_type, v_winner
    from public.competition_results cr
   where cr.competition_id = r_comp.id;

  if v_result_type is null then
    return;
  end if;

  select coalesce(srs.configuration, '{}'::jsonb) into v_delta_map
    from public.league_rule_sets srs
   where srs.rule_set_code = 'faz5_competition_rating'
     and srs.is_active = true
   limit 1;

  if v_delta_map is null then
    v_delta_map := jsonb_build_object(
      'win', 24, 'loss', 12, 'draw', 0,
      'forfeit_win', 24, 'forfeit_loss', 12
    );
  end if;

  for r_player in
    select cp.user_id, cp.status
      from public.competition_players cp
     where cp.competition_id = r_comp.id
     order by cp.user_id
  loop
    v_delta := case
      when v_result_type = 'draw'
        then coalesce((v_delta_map ->> 'draw')::integer, 0)
      when r_player.user_id = v_winner
        then case
               when r_player.status = 'active'
                 then coalesce((v_delta_map ->> 'win')::integer, 24)
               else coalesce((v_delta_map ->> 'forfeit_win')::integer, 24)
             end
      else
        case
          when r_player.status = 'forfeited'
            then -coalesce((v_delta_map ->> 'forfeit_loss')::integer, 12)
          else -coalesce((v_delta_map ->> 'loss')::integer, 12)
        end
    end;

    -- Mevcut genel-kapsam uyelik.
    select m.id, m.league_id, m.current_points
      into v_membership_id, v_cur_league, v_before
      from public.student_league_memberships m
     where m.user_id = r_player.user_id
       and m.is_current = true
       and m.membership_scope = 'general'
     order by m.entered_at desc
     limit 1;

    if v_membership_id is null then
      -- Ilk kez lig sistemine giris: en dusuk aktif lig.
      insert into public.student_league_memberships
        (user_id, league_id, membership_scope,
         points_at_entry, current_points, is_current)
      select r_player.user_id, l.id, 'general', 0, 0, true
        from public.leagues l
       where l.is_active = true
       order by l.sort_order asc, l.min_points asc
       limit 1
      returning id, league_id, current_points
        into v_membership_id, v_cur_league, v_before;

      if v_membership_id is null then
        -- Hic aktif lig tanimli degil: puan uygulama yok (fail-closed).
        return;
      end if;
    end if;

    v_after := greatest(v_before + v_delta, 0);

    update public.student_league_memberships m
       set current_points = v_after,
           updated_at = now()
     where m.id = v_membership_id;

    insert into public.competition_point_changes
      (competition_id, user_id, change_type,
       points_before, points_change, points_after,
       reason_code, rule_reference)
    values
      (r_comp.id, r_player.user_id, 'rating',
       v_before, v_after - v_before, v_after,
       'competition_' || v_result_type,
       jsonb_build_object(
         'rule_set_code', 'faz5_competition_rating',
         'result_type', v_result_type,
         'player_status', r_player.status
       ))
    on conflict (competition_id, user_id, change_type) do nothing;

    -- Lig bandi degisimi (promotion/demotion).
    select l.id, l.sort_order
      into v_target
      from public.leagues l
     where l.is_active = true
       and l.min_points <= v_after
       and (l.max_points is null or v_after <= l.max_points)
     order by l.sort_order asc, l.min_points asc
     limit 1;

    if v_target.id is not null
       and v_target.id is distinct from v_cur_league then

      select l.sort_order into v_cur_sort
        from public.leagues l
       where l.id = v_cur_league;

      update public.student_league_memberships m
         set is_current = false,
             exited_at = now(),
             updated_at = now()
       where m.id = v_membership_id;

      insert into public.student_league_memberships
        (user_id, league_id, membership_scope,
         points_at_entry, current_points, is_current)
      values
        (r_player.user_id, v_target.id, 'general',
         v_after, v_after, true);

      insert into public.student_league_history
        (user_id, from_league_id, to_league_id,
         transition_type, points_at_transition, reason)
      values
        (r_player.user_id, v_cur_league, v_target.id,
         case when coalesce(v_target.sort_order, 0)
                   > coalesce(v_cur_sort, 0)
              then 'promotion' else 'demotion' end,
         v_after,
         'competition_' || v_result_type);
    end if;
  end loop;
end;
$$;


-- ============================================================
-- 3. FINALIZE_COMPETITION_IF_READY(uuid)  [022 birebir + FAZ5]
-- ============================================================

CREATE OR REPLACE FUNCTION public.finalize_competition_if_ready(
  p_competition_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_question_count integer;
  v_player_count integer;
  v_finished_players integer;

  v_winner_user_id uuid;

  v_top_score integer;
  v_second_score integer;

  v_result_type text;

  v_question_results jsonb;
  v_player_results jsonb;
  v_point_changes jsonb;
  v_final_scoreboard jsonb;
  v_scoring_snapshot jsonb;
BEGIN

  -- -------------------------------------------------------
  -- Yarışmadaki soru sayısı.
  -- -------------------------------------------------------

  SELECT COUNT(*)
  INTO v_question_count

  FROM public.competition_questions cq

  WHERE cq.competition_id = p_competition_id;


  -- -------------------------------------------------------
  -- Oyuncu sayısı.
  -- -------------------------------------------------------

  SELECT COUNT(*)
  INTO v_player_count

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id;


  IF v_question_count = 0 THEN
    RETURN;
  END IF;


  -- -------------------------------------------------------
  -- Bütün sorulara cevap veren oyuncuyu finished yap.
  -- -------------------------------------------------------

  UPDATE public.competition_players cp
  SET
    status = 'finished',
    finished_at = COALESCE(
      cp.finished_at,
      now()
    )

  WHERE cp.competition_id = p_competition_id

    AND cp.status NOT IN (
      'finished',
      'forfeited'
    )

    AND (
      SELECT COUNT(*)

      FROM public.competition_answers ca

      WHERE ca.competition_id = p_competition_id
        AND ca.user_id = cp.user_id

    ) >= v_question_count;


  SELECT COUNT(*)
  INTO v_finished_players

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id
    AND cp.status IN (
      'finished',
      'forfeited'
    );


  -- -------------------------------------------------------
  -- İki yarışmacı da bitirmediyse sonuç oluşturma.
  -- -------------------------------------------------------

  IF v_player_count < 2
     OR v_finished_players < v_player_count THEN

    RETURN;

  END IF;


  -- -------------------------------------------------------
  -- En yüksek skor.
  -- -------------------------------------------------------

  SELECT MAX(cp.total_points)
  INTO v_top_score

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id;


  SELECT cp.total_points
  INTO v_second_score

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id

  ORDER BY
    cp.total_points DESC,
    cp.finished_at ASC NULLS LAST

  OFFSET 1
  LIMIT 1;


  -- -------------------------------------------------------
  -- Forfeit var mı?
  -- -------------------------------------------------------

  IF EXISTS (
    SELECT 1

    FROM public.competition_players cp

    WHERE cp.competition_id = p_competition_id
      AND cp.status = 'forfeited'
  ) THEN

    SELECT cp.user_id
    INTO v_winner_user_id

    FROM public.competition_players cp

    WHERE cp.competition_id = p_competition_id
      AND cp.status <> 'forfeited'

    ORDER BY cp.total_points DESC
    LIMIT 1;

    v_result_type := 'forfeit';


  -- -------------------------------------------------------
  -- Beraberlik.
  -- -------------------------------------------------------

  ELSIF v_second_score IS NOT NULL
        AND v_top_score = v_second_score THEN

    v_winner_user_id := NULL;
    v_result_type := 'draw';


  -- -------------------------------------------------------
  -- Normal galibiyet.
  -- -------------------------------------------------------

  ELSE

    SELECT cp.user_id
    INTO v_winner_user_id

    FROM public.competition_players cp

    WHERE cp.competition_id = p_competition_id

    ORDER BY
      cp.total_points DESC,
      cp.finished_at ASC NULLS LAST

    LIMIT 1;

    v_result_type := 'win_loss';

  END IF;


  -- =======================================================
  -- 6A. OYUNCU TOPLAM SONUÇLARI
  -- =======================================================

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'user_id', cp.user_id,
        'player_slot', cp.player_slot,

        'total_points', cp.total_points,

        'correct_count', cp.correct_count,
        'wrong_count', cp.wrong_count,
        'pass_count', cp.pass_count,
        'timeout_count', cp.timeout_count,

        'status', cp.status,

        'finished_at', cp.finished_at
      )
      ORDER BY cp.player_slot
    ),
    '[]'::jsonb
  )

  INTO v_player_results

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id;


  -- =======================================================
  -- 6B. SORU SORU DETAYLI SONUÇ
  --
  -- Her soru içinde iki yarışmacının:
  -- doğru/yanlış
  -- saniye
  -- hız seviyesi
  -- puanı
  -- =======================================================

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'competition_question_id',
        cq.id,

        'question_id',
        cq.question_id,

        'question_order',
        cq.question_order,

        'difficulty',
        cq.difficulty,

        'players',
        (
          SELECT COALESCE(
            jsonb_agg(
              jsonb_build_object(
                'user_id',
                cp.user_id,

                'player_slot',
                cp.player_slot,

                'submitted_answer',
                ca.submitted_answer,

                'answer_result',
                COALESCE(
                  ca.answer_result,
                  'timeout'
                ),

                'time_ms',
                ca.time_ms,

                'time_seconds',
                CASE
                  WHEN ca.time_ms IS NULL
                    THEN NULL

                  ELSE ROUND(
                    ca.time_ms::numeric / 1000,
                    2
                  )
                END,

                'speed_level_code',
                ca.time_band_code,

                'speed_level_name',
                COALESCE(
                  ca.time_band_name,
                  ca.time_band_code
                ),

                'points_awarded',
                COALESCE(
                  ca.points_awarded,
                  0
                )
              )
              ORDER BY cp.player_slot
            ),
            '[]'::jsonb
          )

          FROM public.competition_players cp

          LEFT JOIN public.competition_answers ca
            ON ca.competition_id = p_competition_id
           AND ca.competition_question_id = cq.id
           AND ca.user_id = cp.user_id

          WHERE cp.competition_id = p_competition_id
        )
      )
      ORDER BY cq.question_order
    ),
    '[]'::jsonb
  )

  INTO v_question_results

  FROM public.competition_questions cq

  WHERE cq.competition_id = p_competition_id;


  -- =======================================================
  -- 6C. LİG / SIRALAMA PUAN DEĞİŞİMLERİ
  -- =======================================================

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'user_id',
        cpc.user_id,

        'change_type',
        cpc.change_type,

        'points_before',
        cpc.points_before,

        'points_change',
        cpc.points_change,

        'points_after',
        cpc.points_after,

        'reason_code',
        cpc.reason_code
      )
      ORDER BY cpc.user_id
    ),
    '[]'::jsonb
  )

  INTO v_point_changes

  FROM public.competition_point_changes cpc

  WHERE cpc.competition_id = p_competition_id;


  -- =======================================================
  -- 6D. PUANLAMA SNAPSHOT'I
  -- =======================================================

  SELECT jsonb_build_object(
    'rule_set_id',
    c.scoring_rule_set_id,

    'grade_level',
    c.grade_level,

    'subject_id',
    c.subject_id,

    'question_count',
    c.question_count,

    'competition_type',
    c.competition_type
  )

  INTO v_scoring_snapshot

  FROM public.competitions c

  WHERE c.id = p_competition_id;


  -- =======================================================
  -- 6E. FİNAL SCOREBOARD
  -- =======================================================

  v_final_scoreboard :=
    jsonb_build_object(

      'winner_user_id',
      v_winner_user_id,

      'result_type',
      v_result_type,

      'players',
      v_player_results,

      'questions',
      v_question_results,

      'point_changes',
      v_point_changes
    );


  -- -------------------------------------------------------
  -- Competition tamamla.
  -- -------------------------------------------------------

  UPDATE public.competitions
  SET
    status = 'completed',

    winner_user_id = v_winner_user_id,

    completed_at = COALESCE(
      completed_at,
      now()
    ),

    server_completed_at = COALESCE(
      server_completed_at,
      now()
    )

  WHERE id = p_competition_id;


  -- -------------------------------------------------------
  -- Sonucu kaydet.
  -- -------------------------------------------------------

  INSERT INTO public.competition_results (
    competition_id,

    winner_user_id,

    result_type,

    player_results,

    question_results,

    point_changes,

    final_scoreboard,

    scoring_snapshot,

    calculated_at
  )

  VALUES (
    p_competition_id,

    v_winner_user_id,

    v_result_type,

    v_player_results,

    v_question_results,

    v_point_changes,

    v_final_scoreboard,

    v_scoring_snapshot,

    now()
  )

  ON CONFLICT (competition_id)
  DO UPDATE SET

    winner_user_id =
      EXCLUDED.winner_user_id,

    result_type =
      EXCLUDED.result_type,

    player_results =
      EXCLUDED.player_results,

    question_results =
      EXCLUDED.question_results,

    point_changes =
      EXCLUDED.point_changes,

    final_scoreboard =
      EXCLUDED.final_scoreboard,

    scoring_snapshot =
      EXCLUDED.scoring_snapshot,

    calculated_at =
      EXCLUDED.calculated_at;


  -- -------------------------------------------------------
  -- FAZ5: LIG/RATING PUAN MOTORU
  --
  -- Sonuc snapshot'i yazildiktan SONRA cagrilir; ayni
  -- transaction icinde hata olursa tum finalize geri alinir.
  -- Idempotency fonksiyonun kendi guard'iyla saglanir.
  -- -------------------------------------------------------

  PERFORM public._faz5_apply_competition_points(p_competition_id);

END;
$$;


-- ============================================================
-- 4. EXECUTE MATRISI
--
-- Iki fonksiyon da yalnizca sunucu-ici (RPC zinciri) cagrima
-- aciktir; 025 hardening durumu birebir korunur.
-- ============================================================

REVOKE EXECUTE
ON FUNCTION public.finalize_competition_if_ready(uuid)
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE
ON FUNCTION public._faz5_apply_competition_points(uuid)
FROM PUBLIC, anon, authenticated;


commit;


-- ============================================================
-- DOGRULAMA
-- ============================================================

select
  p.proname as function_name,
  p.prosecdef as is_security_definer,
  has_function_privilege('authenticated', p.oid, 'EXECUTE')
    as authenticated_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'finalize_competition_if_ready',
    '_faz5_apply_competition_points'
  )
order by p.proname;

select rule_set_code, configuration
from public.league_rule_sets
where rule_set_code = 'faz5_competition_rating';
