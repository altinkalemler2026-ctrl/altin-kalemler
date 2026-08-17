-- 022_competition_scoreboard.sql
-- Altın Kalemler
--
-- Yarışma sonunda:
-- - maksimum 5 soru
-- - soru soru yarışmacı performansı
-- - doğru / yanlış / pas / timeout
-- - çözüm süresi
-- - hız seviyesi
-- - soru puanı
-- - yarışma toplam puanı
-- - lig / sıralama puanı kazanma-kaybetme
-- - yarışma sonu değiştirilemez snapshot
--
-- Öğrenci bu detayları yalnızca yarışma bittikten sonra görür.


-- =========================================================
-- 1. YARIŞMADA MAKSİMUM 5 SORU
-- =========================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'competitions_question_count_between_1_and_5'
      AND conrelid = 'public.competitions'::regclass
  ) THEN

    ALTER TABLE public.competitions
    ADD CONSTRAINT competitions_question_count_between_1_and_5
    CHECK (
      question_count BETWEEN 1 AND 5
    )
    NOT VALID;

  END IF;
END;
$$;


ALTER TABLE public.competitions
VALIDATE CONSTRAINT competitions_question_count_between_1_and_5;


-- =========================================================
-- 2. GERÇEK EKLENEN SORU SAYISI DA 5'İ GEÇEMEZ
--
-- competitions.question_count = 3 iken
-- 4. soru da eklenemez.
-- =========================================================

CREATE OR REPLACE FUNCTION public.validate_competition_question_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_declared_question_count integer;
  v_existing_question_count integer;
BEGIN

  SELECT c.question_count
  INTO v_declared_question_count
  FROM public.competitions c
  WHERE c.id = NEW.competition_id;

  IF v_declared_question_count IS NULL THEN
    RAISE EXCEPTION 'Competition not found.';
  END IF;

  IF v_declared_question_count > 5 THEN
    RAISE EXCEPTION
      'A competition cannot contain more than 5 questions.';
  END IF;

  SELECT COUNT(*)
  INTO v_existing_question_count
  FROM public.competition_questions cq
  WHERE cq.competition_id = NEW.competition_id
    AND (
      TG_OP <> 'UPDATE'
      OR cq.id <> NEW.id
    );

  IF v_existing_question_count + 1
     > v_declared_question_count THEN

    RAISE EXCEPTION
      'Competition question limit exceeded. Expected maximum: %',
      v_declared_question_count;

  END IF;

  RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS
trigger_validate_competition_question_limit
ON public.competition_questions;

CREATE TRIGGER
trigger_validate_competition_question_limit
BEFORE INSERT OR UPDATE
ON public.competition_questions
FOR EACH ROW
EXECUTE FUNCTION public.validate_competition_question_limit();


-- =========================================================
-- 3. CEVABA HIZ SEVİYESİ ADI SNAPSHOT'I
--
-- time_band_code zaten tutuluyor.
-- Burada "Mükemmel", "İyi", "Orta" gibi görünen adı da
-- yarışma anındaki haliyle saklıyoruz.
-- =========================================================

ALTER TABLE public.competition_answers
ADD COLUMN IF NOT EXISTS time_band_name text;


CREATE OR REPLACE FUNCTION public.snapshot_competition_answer_band_name()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_question_id uuid;
  v_rule_set_id uuid;
  v_grade_level smallint;
  v_difficulty text;
  v_band_name text;
BEGIN

  IF NEW.time_band_code IS NULL THEN
    RETURN NEW;
  END IF;


  SELECT
    cq.question_id,
    cq.difficulty,
    c.scoring_rule_set_id,
    c.grade_level

  INTO
    v_question_id,
    v_difficulty,
    v_rule_set_id,
    v_grade_level

  FROM public.competition_questions cq

  JOIN public.competitions c
    ON c.id = cq.competition_id

  WHERE cq.id = NEW.competition_question_id;


  -- -------------------------------------------------------
  -- Önce soru-bazlı özel süre bandı.
  -- -------------------------------------------------------

  SELECT qstb.band_name
  INTO v_band_name

  FROM public.question_scoring_time_bands qstb

  JOIN public.question_solve_time_profiles qstp
    ON qstp.id = qstb.solve_time_profile_id

  WHERE qstb.question_id = v_question_id
    AND qstb.scoring_rule_set_id = v_rule_set_id
    AND qstb.band_code = NEW.time_band_code
    AND qstb.is_active = true

    AND qstp.question_id = v_question_id
    AND qstp.is_current = true
    AND qstp.is_approved_for_scoring = true

  ORDER BY qstb.sort_order
  LIMIT 1;


  -- -------------------------------------------------------
  -- Özel bant yoksa sınıf/zorluk genel bandı.
  -- -------------------------------------------------------

  IF v_band_name IS NULL THEN

    SELECT stb.band_name
    INTO v_band_name

    FROM public.scoring_time_bands stb

    WHERE stb.rule_set_id = v_rule_set_id
      AND stb.grade_level = v_grade_level
      AND stb.difficulty = v_difficulty
      AND stb.band_code = NEW.time_band_code
      AND stb.is_active = true

    ORDER BY stb.sort_order
    LIMIT 1;

  END IF;


  NEW.time_band_name :=
    COALESCE(
      v_band_name,
      NEW.time_band_code
    );

  RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS
trigger_snapshot_competition_answer_band_name
ON public.competition_answers;

CREATE TRIGGER
trigger_snapshot_competition_answer_band_name
BEFORE INSERT
ON public.competition_answers
FOR EACH ROW
EXECUTE FUNCTION public.snapshot_competition_answer_band_name();


-- =========================================================
-- 4. YARIŞMA / LİG / SIRALAMA PUAN DEĞİŞİMLERİ
--
-- Bu puan, soru içindeki points_awarded ile aynı şey değildir.
--
-- Örneğin:
-- yarışma içi skor = 365
-- lig puanı değişimi = +24
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competition_point_changes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  competition_id uuid NOT NULL
    REFERENCES public.competitions(id)
    ON DELETE CASCADE,

  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  change_type text NOT NULL DEFAULT 'rating'
    CHECK (
      change_type IN (
        'rating',
        'league_points',
        'ranking_points',
        'season_points',
        'wallet_points',
        'custom'
      )
    ),

  points_before integer,

  points_change integer NOT NULL DEFAULT 0,

  points_after integer,

  reason_code text,

  rule_reference jsonb NOT NULL DEFAULT '{}'::jsonb,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    points_before IS NULL
    OR points_after IS NULL
    OR points_after = points_before + points_change
  ),

  UNIQUE (
    competition_id,
    user_id,
    change_type
  )
);

CREATE INDEX IF NOT EXISTS
idx_competition_point_changes_user
ON public.competition_point_changes(
  user_id,
  created_at DESC
);

CREATE INDEX IF NOT EXISTS
idx_competition_point_changes_competition
ON public.competition_point_changes(
  competition_id
);

ALTER TABLE public.competition_point_changes
ENABLE ROW LEVEL SECURITY;


DROP POLICY IF EXISTS
"student reads own competition point changes"
ON public.competition_point_changes;

CREATE POLICY
"student reads own competition point changes"
ON public.competition_point_changes
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
);


-- =========================================================
-- 5. competition_results TABLOSUNU GENİŞLET
--
-- Yarışma bitişindeki ayrıntılar immutable snapshot olarak
-- saklanabilecek.
-- =========================================================

ALTER TABLE public.competition_results
ADD COLUMN IF NOT EXISTS question_results jsonb
NOT NULL DEFAULT '[]'::jsonb;


ALTER TABLE public.competition_results
ADD COLUMN IF NOT EXISTS point_changes jsonb
NOT NULL DEFAULT '[]'::jsonb;


ALTER TABLE public.competition_results
ADD COLUMN IF NOT EXISTS final_scoreboard jsonb
NOT NULL DEFAULT '{}'::jsonb;


-- =========================================================
-- 6. GELİŞMİŞ YARIŞMA BİTİRME FONKSİYONU
--
-- 021'deki fonksiyonu geliştiriyoruz.
-- Yarışma sonu soru soru snapshot üretir.
-- =========================================================

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

END;
$$;


-- =========================================================
-- 7. YARIŞMA SONU SKOR TABLOSU RPC
--
-- Öğrenci yalnızca katıldığı ve TAMAMLANMIŞ yarışmayı
-- ayrıntılı görebilir.
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_competition_scoreboard(
  p_competition_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;

  v_status text;
  v_result jsonb;
BEGIN

  v_user_id := auth.uid();


  IF v_user_id IS NULL THEN
    RAISE EXCEPTION
      'Authentication required.';
  END IF;


  -- -------------------------------------------------------
  -- Katılımcı mı?
  -- -------------------------------------------------------

  IF NOT public.is_competition_participant(
    p_competition_id,
    v_user_id
  ) THEN

    RAISE EXCEPTION
      'You are not a participant in this competition.';

  END IF;


  -- -------------------------------------------------------
  -- Yarışma bitti mi?
  -- -------------------------------------------------------

  SELECT c.status
  INTO v_status

  FROM public.competitions c

  WHERE c.id = p_competition_id;


  IF v_status IS NULL THEN
    RAISE EXCEPTION
      'Competition not found.';
  END IF;


  IF v_status <> 'completed' THEN

    RAISE EXCEPTION
      'Detailed scoreboard is available after the competition ends.';

  END IF;


  -- -------------------------------------------------------
  -- Snapshot sonucu.
  -- -------------------------------------------------------

  SELECT jsonb_build_object(

    'competition_id',
    c.id,

    'competition_code',
    c.competition_code,

    'competition_type',
    c.competition_type,

    'grade_level',
    c.grade_level,

    'subject_id',
    c.subject_id,

    'question_count',
    c.question_count,

    'winner_user_id',
    cr.winner_user_id,

    'result_type',
    cr.result_type,

    'players',
    cr.player_results,

    'questions',
    cr.question_results,

    'point_changes',
    cr.point_changes,

    'started_at',
    c.server_started_at,

    'completed_at',
    c.server_completed_at

  )

  INTO v_result

  FROM public.competitions c

  JOIN public.competition_results cr
    ON cr.competition_id = c.id

  WHERE c.id = p_competition_id;


  RETURN v_result;

END;
$$;


REVOKE ALL
ON FUNCTION public.get_competition_scoreboard(uuid)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.get_competition_scoreboard(uuid)
TO authenticated;


-- =========================================================
-- 8. ÖĞRENCİ competition_results TABLOSUNDAN DA SADECE
-- KATILDIĞI YARIŞMAYI OKUYABİLİR
-- =========================================================

DROP POLICY IF EXISTS
"competition participants read results"
ON public.competition_results;

CREATE POLICY
"competition participants read results"
ON public.competition_results
FOR SELECT
TO authenticated
USING (
  public.is_competition_participant(
    competition_id,
    auth.uid()
  )
);


-- =========================================================
-- 9. PUAN DEĞİŞİKLİĞİNİ DOĞRUDAN ÖĞRENCİ YAZAMAZ
--
-- INSERT / UPDATE policy özellikle oluşturmuyoruz.
-- Bu kayıtları ileride server-side puan motoru oluşturacak.
-- =========================================================