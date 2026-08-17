-- 021_secure_competition_scoring.sql
-- Altın Kalemler
--
-- Güvenli yarışma cevap gönderme ve skor hesaplama motoru.
--
-- Öğrenci:
-- - süre göndermez
-- - puan göndermez
-- - doğru/yanlış göndermez
-- - sadece seçtiği cevabı gönderir
--
-- Süre ve puan server tarafında hesaplanır.


-- =========================================================
-- 1. YARIŞMAYA KATILIMCI MI?
--
-- SECURITY DEFINER kullanarak competition_players üzerinde
-- recursive RLS sorununu engeller.
-- =========================================================

CREATE OR REPLACE FUNCTION public.is_competition_participant(
  p_competition_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.competition_players cp
    WHERE cp.competition_id = p_competition_id
      AND cp.user_id = p_user_id
  );
$$;

REVOKE ALL
ON FUNCTION public.is_competition_participant(uuid, uuid)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.is_competition_participant(uuid, uuid)
TO authenticated;


-- =========================================================
-- 2. 019'DAKİ competition_players SELECT POLICY'SİNİ
-- GÜVENLİ HALE GETİR
-- =========================================================

DROP POLICY IF EXISTS "players read own competitions"
ON public.competition_players;

DROP POLICY IF EXISTS "competition participants read players"
ON public.competition_players;

CREATE POLICY "competition participants read players"
ON public.competition_players
FOR SELECT
TO authenticated
USING (
  public.is_competition_participant(
    competition_id,
    auth.uid()
  )
);


-- =========================================================
-- 3. YARIŞMALARI SADECE KATILIMCILAR GÖREBİLSİN
-- =========================================================

DROP POLICY IF EXISTS "competition participants read competitions"
ON public.competitions;

CREATE POLICY "competition participants read competitions"
ON public.competitions
FOR SELECT
TO authenticated
USING (
  public.is_competition_participant(
    id,
    auth.uid()
  )
);


-- =========================================================
-- 4. DOĞRU CEVABI GÜVENLİ ŞEKİLDE OKUYAN INTERNAL FUNCTION
--
-- questions tablosundaki alan adı zaman içinde değişirse
-- farklı muhtemel kolon adlarını JSON üzerinden kontrol eder.
--
-- Bu fonksiyon öğrenciye açık değildir.
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_internal_correct_answer(
  p_question_id uuid
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_question jsonb;
  v_answer text;
BEGIN

  SELECT to_jsonb(q)
  INTO v_question
  FROM public.questions q
  WHERE q.id = p_question_id;

  IF v_question IS NULL THEN
    RAISE EXCEPTION 'Question not found.';
  END IF;

  v_answer :=
    COALESCE(
      v_question ->> 'correct_answer',
      v_question ->> 'correct_option',
      v_question ->> 'correct_choice',
      v_question ->> 'answer'
    );

  IF v_answer IS NULL OR btrim(v_answer) = '' THEN
    RAISE EXCEPTION
      'Correct answer is not configured for this question.';
  END IF;

  RETURN upper(btrim(v_answer));

END;
$$;

REVOKE ALL
ON FUNCTION public.get_internal_correct_answer(uuid)
FROM PUBLIC;


-- =========================================================
-- 5. SORUYA ÖZEL SÜRE BANDINI BUL
--
-- Öncelik:
-- 1. question_scoring_time_bands
-- 2. scoring_time_bands
--
-- Soruya özel profil varsa onu kullanır.
-- =========================================================

CREATE OR REPLACE FUNCTION public.resolve_competition_time_band(
  p_question_id uuid,
  p_rule_set_id uuid,
  p_grade_level smallint,
  p_difficulty text,
  p_time_ms integer
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_band_code text;
BEGIN

  -- -------------------------------------------------------
  -- Önce soru-bazlı süre bandı.
  -- Yalnızca scoring için onaylanmış current profil.
  -- -------------------------------------------------------

  SELECT qstb.band_code
  INTO v_band_code

  FROM public.question_scoring_time_bands qstb

  JOIN public.question_solve_time_profiles qstp
    ON qstp.id = qstb.solve_time_profile_id

  WHERE qstb.question_id = p_question_id
    AND qstb.scoring_rule_set_id = p_rule_set_id
    AND qstb.is_active = true

    AND qstp.question_id = p_question_id
    AND qstp.is_current = true
    AND qstp.is_approved_for_scoring = true

    AND p_time_ms >= qstb.min_time_ms

    AND (
      qstb.max_time_ms IS NULL
      OR p_time_ms < qstb.max_time_ms
    )

  ORDER BY qstb.sort_order ASC
  LIMIT 1;


  IF v_band_code IS NOT NULL THEN
    RETURN v_band_code;
  END IF;


  -- -------------------------------------------------------
  -- Soru-bazlı bant yoksa genel sınıf/zorluk bandı.
  -- -------------------------------------------------------

  SELECT stb.band_code
  INTO v_band_code

  FROM public.scoring_time_bands stb

  WHERE stb.rule_set_id = p_rule_set_id
    AND stb.grade_level = p_grade_level
    AND stb.difficulty = p_difficulty
    AND stb.is_active = true

    AND (
      stb.min_time_ms IS NULL
      OR p_time_ms >= stb.min_time_ms
    )

    AND (
      stb.max_time_ms IS NULL
      OR p_time_ms < stb.max_time_ms
    )

  ORDER BY stb.sort_order ASC
  LIMIT 1;


  RETURN v_band_code;

END;
$$;

REVOKE ALL
ON FUNCTION public.resolve_competition_time_band(
  uuid,
  uuid,
  smallint,
  text,
  integer
)
FROM PUBLIC;


-- =========================================================
-- 6. PUANI SERVER TARAFINDA BUL
--
-- Önce band_code'lu kural aranır.
-- Bulunamazsa band_code IS NULL fallback kuralı kullanılır.
-- =========================================================

CREATE OR REPLACE FUNCTION public.resolve_competition_points(
  p_rule_set_id uuid,
  p_grade_level smallint,
  p_difficulty text,
  p_answer_result text,
  p_band_code text
)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_points integer;
BEGIN

  -- -------------------------------------------------------
  -- Önce süre bandına özel puan.
  -- -------------------------------------------------------

  IF p_band_code IS NOT NULL THEN

    SELECT spr.points
    INTO v_points

    FROM public.scoring_point_rules spr

    WHERE spr.rule_set_id = p_rule_set_id
      AND spr.grade_level = p_grade_level
      AND spr.difficulty = p_difficulty
      AND spr.answer_result = p_answer_result
      AND spr.band_code = p_band_code
      AND spr.is_active = true

    ORDER BY spr.created_at DESC
    LIMIT 1;

  END IF;


  -- -------------------------------------------------------
  -- Band özel kural bulunamazsa genel sonuç puanı.
  -- -------------------------------------------------------

  IF v_points IS NULL THEN

    SELECT spr.points
    INTO v_points

    FROM public.scoring_point_rules spr

    WHERE spr.rule_set_id = p_rule_set_id
      AND spr.grade_level = p_grade_level
      AND spr.difficulty = p_difficulty
      AND spr.answer_result = p_answer_result
      AND spr.band_code IS NULL
      AND spr.is_active = true

    ORDER BY spr.created_at DESC
    LIMIT 1;

  END IF;


  RETURN COALESCE(v_points, 0);

END;
$$;

REVOKE ALL
ON FUNCTION public.resolve_competition_points(
  uuid,
  smallint,
  text,
  text,
  text
)
FROM PUBLIC;


-- =========================================================
-- 7. OYUNCUNUN TOPLAM SKORUNU YENİDEN HESAPLA
--
-- Client'ın toplam puana müdahalesini önlemek için
-- competition_answers üzerinden tekrar hesaplanır.
-- =========================================================

CREATE OR REPLACE FUNCTION public.recalculate_competition_player_score(
  p_competition_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_points integer;
  v_correct integer;
  v_wrong integer;
  v_pass integer;
  v_timeout integer;
BEGIN

  SELECT
    COALESCE(SUM(ca.points_awarded), 0),

    COUNT(*) FILTER (
      WHERE ca.answer_result = 'correct'
    ),

    COUNT(*) FILTER (
      WHERE ca.answer_result = 'wrong'
    ),

    COUNT(*) FILTER (
      WHERE ca.answer_result = 'pass'
    ),

    COUNT(*) FILTER (
      WHERE ca.answer_result = 'timeout'
    )

  INTO
    v_total_points,
    v_correct,
    v_wrong,
    v_pass,
    v_timeout

  FROM public.competition_answers ca

  WHERE ca.competition_id = p_competition_id
    AND ca.user_id = p_user_id;


  UPDATE public.competition_players
  SET
    total_points = COALESCE(v_total_points, 0),
    correct_count = COALESCE(v_correct, 0),
    wrong_count = COALESCE(v_wrong, 0),
    pass_count = COALESCE(v_pass, 0),
    timeout_count = COALESCE(v_timeout, 0)

  WHERE competition_id = p_competition_id
    AND user_id = p_user_id;

END;
$$;

REVOKE ALL
ON FUNCTION public.recalculate_competition_player_score(
  uuid,
  uuid
)
FROM PUBLIC;


-- =========================================================
-- 8. YARIŞMAYI GEREKİRSE BİTİR
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
BEGIN

  SELECT COUNT(*)
  INTO v_question_count
  FROM public.competition_questions cq
  WHERE cq.competition_id = p_competition_id;


  SELECT COUNT(*)
  INTO v_player_count
  FROM public.competition_players cp
  WHERE cp.competition_id = p_competition_id;


  -- -------------------------------------------------------
  -- Tüm soruları cevaplayan oyuncuları finished yap.
  -- -------------------------------------------------------

  UPDATE public.competition_players cp
  SET
    status = 'finished',
    finished_at = COALESCE(cp.finished_at, now())

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


  IF v_player_count < 2
     OR v_finished_players < v_player_count THEN
    RETURN;
  END IF;


  -- -------------------------------------------------------
  -- İlk iki skoru bul.
  -- -------------------------------------------------------

  SELECT
    MAX(total_points)
  INTO v_top_score
  FROM public.competition_players
  WHERE competition_id = p_competition_id;


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
  -- Kazanan / beraberlik.
  -- -------------------------------------------------------

  IF v_second_score IS NOT NULL
     AND v_top_score = v_second_score THEN

    v_winner_user_id := NULL;
    v_result_type := 'draw';

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


  -- -------------------------------------------------------
  -- Competition kaydını kapat.
  -- -------------------------------------------------------

  UPDATE public.competitions
  SET
    status = 'completed',
    winner_user_id = v_winner_user_id,
    completed_at = COALESCE(completed_at, now()),
    server_completed_at = COALESCE(
      server_completed_at,
      now()
    )

  WHERE id = p_competition_id
    AND status <> 'completed';


  -- -------------------------------------------------------
  -- Sonuç snapshot'ı.
  -- Geçmiş yarışmanın sonucu daha sonra kural değişse bile
  -- korunur.
  -- -------------------------------------------------------

  INSERT INTO public.competition_results (
    competition_id,
    winner_user_id,
    result_type,
    player_results,
    scoring_snapshot,
    calculated_at
  )

  SELECT
    p_competition_id,

    v_winner_user_id,

    v_result_type,

    (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'user_id', cp.user_id,
            'player_slot', cp.player_slot,
            'total_points', cp.total_points,
            'correct_count', cp.correct_count,
            'wrong_count', cp.wrong_count,
            'pass_count', cp.pass_count,
            'timeout_count', cp.timeout_count
          )
          ORDER BY cp.player_slot
        ),
        '[]'::jsonb
      )

      FROM public.competition_players cp
      WHERE cp.competition_id = p_competition_id
    ),

    (
      SELECT jsonb_build_object(
        'rule_set_id', c.scoring_rule_set_id,
        'grade_level', c.grade_level,
        'question_count', c.question_count
      )

      FROM public.competitions c
      WHERE c.id = p_competition_id
    ),

    now()

  ON CONFLICT (competition_id)
  DO UPDATE SET
    winner_user_id = EXCLUDED.winner_user_id,
    result_type = EXCLUDED.result_type,
    player_results = EXCLUDED.player_results,
    scoring_snapshot = EXCLUDED.scoring_snapshot,
    calculated_at = EXCLUDED.calculated_at;

END;
$$;

REVOKE ALL
ON FUNCTION public.finalize_competition_if_ready(uuid)
FROM PUBLIC;


-- =========================================================
-- 9. GÜVENLİ CEVAP GÖNDERME RPC
--
-- Client SADECE:
--
-- competition_question_id
-- submitted_answer
--
-- gönderir.
--
-- submitted_answer:
-- A / B / C / D / E
-- veya NULL = PAS
-- =========================================================

CREATE OR REPLACE FUNCTION public.submit_competition_answer(
  p_competition_question_id uuid,
  p_submitted_answer text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;

  v_competition_id uuid;
  v_question_id uuid;

  v_question_sent_at timestamptz;
  v_question_deadline_at timestamptz;

  v_competition_status text;
  v_grade_level smallint;
  v_rule_set_id uuid;

  v_difficulty text;

  v_correct_answer text;
  v_normalized_answer text;

  v_received_at timestamptz;
  v_time_ms integer;

  v_answer_result text;
  v_band_code text;
  v_points integer;

  v_answer_id uuid;
BEGIN

  -- -------------------------------------------------------
  -- Kullanıcı.
  -- -------------------------------------------------------

  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;


  -- -------------------------------------------------------
  -- Cevabı normalize et.
  -- NULL = pas
  -- -------------------------------------------------------

  IF p_submitted_answer IS NULL
     OR btrim(p_submitted_answer) = '' THEN

    v_normalized_answer := NULL;

  ELSE

    v_normalized_answer :=
      upper(btrim(p_submitted_answer));

    IF v_normalized_answer NOT IN (
      'A',
      'B',
      'C',
      'D',
      'E'
    ) THEN

      RAISE EXCEPTION
        'Invalid answer option.';

    END IF;

  END IF;


  -- -------------------------------------------------------
  -- Server zamanı.
  -- Client timestamp kullanılmaz.
  -- -------------------------------------------------------

  v_received_at := clock_timestamp();


  -- -------------------------------------------------------
  -- Yarışma sorusunu kilitle.
  -- -------------------------------------------------------

  SELECT
    cq.competition_id,
    cq.question_id,
    cq.sent_at,
    cq.deadline_at,
    cq.difficulty,

    c.status,
    c.grade_level,
    c.scoring_rule_set_id

  INTO
    v_competition_id,
    v_question_id,
    v_question_sent_at,
    v_question_deadline_at,
    v_difficulty,

    v_competition_status,
    v_grade_level,
    v_rule_set_id

  FROM public.competition_questions cq

  JOIN public.competitions c
    ON c.id = cq.competition_id

  WHERE cq.id = p_competition_question_id

  FOR UPDATE OF cq;


  IF v_competition_id IS NULL THEN
    RAISE EXCEPTION
      'Competition question not found.';
  END IF;


  -- -------------------------------------------------------
  -- Yarışmaya gerçekten katılıyor mu?
  -- -------------------------------------------------------

  IF NOT public.is_competition_participant(
    v_competition_id,
    v_user_id
  ) THEN

    RAISE EXCEPTION
      'You are not a participant in this competition.';

  END IF;


  -- -------------------------------------------------------
  -- Oyuncu forfeited ise cevap veremez.
  -- -------------------------------------------------------

  IF EXISTS (
    SELECT 1
    FROM public.competition_players cp

    WHERE cp.competition_id = v_competition_id
      AND cp.user_id = v_user_id
      AND cp.status = 'forfeited'
  ) THEN

    RAISE EXCEPTION
      'Player has forfeited this competition.';

  END IF;


  -- -------------------------------------------------------
  -- Yarışma aktif olmalı.
  -- -------------------------------------------------------

  IF v_competition_status <> 'active' THEN

    RAISE EXCEPTION
      'Competition is not active.';

  END IF;


  -- -------------------------------------------------------
  -- Sorunun başlangıç ve deadline bilgisi server tarafından
  -- atanmış olmalı.
  -- -------------------------------------------------------

  IF v_question_sent_at IS NULL
     OR v_question_deadline_at IS NULL THEN

    RAISE EXCEPTION
      'Question timing has not been initialized.';

  END IF;


  IF v_received_at < v_question_sent_at THEN

    RAISE EXCEPTION
      'Question has not started yet.';

  END IF;


  -- -------------------------------------------------------
  -- İkinci cevap engellenir.
  -- -------------------------------------------------------

  IF EXISTS (
    SELECT 1
    FROM public.competition_answers ca

    WHERE ca.competition_question_id =
          p_competition_question_id

      AND ca.user_id = v_user_id
  ) THEN

    RAISE EXCEPTION
      'Answer already submitted for this question.';

  END IF;


  -- -------------------------------------------------------
  -- Süre SERVER tarafından hesaplanır.
  --
  -- Deadline sonrası cevap gelirse süre deadline'da kesilir.
  -- -------------------------------------------------------

  v_time_ms :=
    GREATEST(
      0,

      FLOOR(
        EXTRACT(
          EPOCH FROM (
            LEAST(
              v_received_at,
              v_question_deadline_at
            )
            - v_question_sent_at
          )
        ) * 1000
      )::integer
    );


  -- -------------------------------------------------------
  -- Deadline geçtiyse TIMEOUT.
  -- -------------------------------------------------------

  IF v_received_at > v_question_deadline_at THEN

    v_answer_result := 'timeout';

  -- -------------------------------------------------------
  -- NULL cevap = PAS.
  -- -------------------------------------------------------

  ELSIF v_normalized_answer IS NULL THEN

    v_answer_result := 'pass';

  ELSE

    -- -----------------------------------------------------
    -- Doğru cevap client'a sorulmaz.
    -- Server içinden alınır.
    -- -----------------------------------------------------

    v_correct_answer :=
      public.get_internal_correct_answer(
        v_question_id
      );


    IF v_normalized_answer = v_correct_answer THEN

      v_answer_result := 'correct';

    ELSE

      v_answer_result := 'wrong';

    END IF;

  END IF;


  -- -------------------------------------------------------
  -- Soru-bazlı süre bandını çöz.
  --
  -- Timeout ve pas durumlarında da süre bandı bilgi amaçlı
  -- tutulabilir ancak puan kuralı result üzerinden belirlenir.
  -- -------------------------------------------------------

  v_band_code :=
    public.resolve_competition_time_band(
      v_question_id,
      v_rule_set_id,
      v_grade_level,
      v_difficulty,
      v_time_ms
    );


  -- -------------------------------------------------------
  -- Puan.
  -- -------------------------------------------------------

  v_points :=
    public.resolve_competition_points(
      v_rule_set_id,
      v_grade_level,
      v_difficulty,
      v_answer_result,
      v_band_code
    );


  -- -------------------------------------------------------
  -- Cevabı kaydet.
  -- sent_at/deadline_at competition_questions üzerinden gelir.
  -- -------------------------------------------------------

  INSERT INTO public.competition_answers (
    competition_id,
    competition_question_id,
    user_id,

    submitted_answer,
    answer_result,

    sent_at,
    deadline_at,
    answer_received_at,

    time_ms,
    time_band_code,

    points_awarded,

    server_validated,

    validation_data
  )

  VALUES (
    v_competition_id,
    p_competition_question_id,
    v_user_id,

    v_normalized_answer,
    v_answer_result,

    v_question_sent_at,
    v_question_deadline_at,
    v_received_at,

    v_time_ms,
    v_band_code,

    v_points,

    true,

    jsonb_build_object(
      'validation_source',
      'server',

      'scoring_rule_set_id',
      v_rule_set_id,

      'question_id',
      v_question_id,

      'used_question_specific_time_band',
      EXISTS (
        SELECT 1

        FROM public.question_scoring_time_bands qstb

        JOIN public.question_solve_time_profiles qstp
          ON qstp.id = qstb.solve_time_profile_id

        WHERE qstb.question_id = v_question_id
          AND qstb.scoring_rule_set_id = v_rule_set_id
          AND qstb.band_code = v_band_code
          AND qstb.is_active = true

          AND qstp.is_current = true
          AND qstp.is_approved_for_scoring = true
      ),

      'server_received_at',
      v_received_at
    )
  )

  RETURNING id
  INTO v_answer_id;


  -- -------------------------------------------------------
  -- Oyuncu toplamlarını cevaplardan yeniden hesapla.
  -- -------------------------------------------------------

  PERFORM public.recalculate_competition_player_score(
    v_competition_id,
    v_user_id
  );


  -- -------------------------------------------------------
  -- Yarışma tamamlandıysa bitir.
  -- -------------------------------------------------------

  PERFORM public.finalize_competition_if_ready(
    v_competition_id
  );


  -- -------------------------------------------------------
  -- Client'a güvenli sonuç.
  --
  -- Doğru cevabı burada özellikle dönmüyoruz.
  -- Yarışma sırasında rakip veya öğrenci doğru cevabı
  -- buradan öğrenemesin.
  -- -------------------------------------------------------

  RETURN jsonb_build_object(
    'answer_id',
    v_answer_id,

    'competition_id',
    v_competition_id,

    'result',
    v_answer_result,

    'time_ms',
    v_time_ms,

    'time_band',
    v_band_code,

    'points_awarded',
    v_points
  );


EXCEPTION

  WHEN unique_violation THEN

    RAISE EXCEPTION
      'Answer already submitted for this question.';

END;
$$;


REVOKE ALL
ON FUNCTION public.submit_competition_answer(
  uuid,
  text
)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.submit_competition_answer(
  uuid,
  text
)
TO authenticated;


-- =========================================================
-- 10. GÜVENLİ YARIŞMA SORUSU OKUMA RPC
--
-- questions tablosunun tamamını client'a göndermiyoruz.
-- Doğru cevap / çözüm / AI / admin alanları JSON'dan çıkarılır.
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_competition_question_payload(
  p_competition_question_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_competition_id uuid;

  v_question_json jsonb;

  v_question_order integer;
  v_sent_at timestamptz;
  v_deadline_at timestamptz;

  v_status text;
BEGIN

  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION
      'Authentication required.';
  END IF;


  SELECT
    cq.competition_id,
    cq.question_order,
    cq.sent_at,
    cq.deadline_at,
    c.status,

    to_jsonb(q)

  INTO
    v_competition_id,
    v_question_order,
    v_sent_at,
    v_deadline_at,
    v_status,
    v_question_json

  FROM public.competition_questions cq

  JOIN public.competitions c
    ON c.id = cq.competition_id

  JOIN public.questions q
    ON q.id = cq.question_id

  WHERE cq.id = p_competition_question_id;


  IF v_competition_id IS NULL THEN

    RAISE EXCEPTION
      'Competition question not found.';

  END IF;


  IF NOT public.is_competition_participant(
    v_competition_id,
    v_user_id
  ) THEN

    RAISE EXCEPTION
      'You are not a participant in this competition.';

  END IF;


  IF v_status NOT IN (
    'ready',
    'active'
  ) THEN

    RAISE EXCEPTION
      'Competition question is not available.';

  END IF;


  IF v_sent_at IS NULL THEN

    RAISE EXCEPTION
      'Question has not been released.';

  END IF;


  IF clock_timestamp() < v_sent_at THEN

    RAISE EXCEPTION
      'Question has not started yet.';

  END IF;


  -- -------------------------------------------------------
  -- Hassas alanları çıkar.
  --
  -- questions tablosunda ileride farklı isimler kullanılsa
  -- bile sık kullanılan cevap/çözüm/admin alanlarını temizler.
  -- -------------------------------------------------------

  v_question_json :=
    v_question_json
    - ARRAY[
        'correct_answer',
        'correct_option',
        'correct_choice',
        'answer',
        'answer_key',

        'solution',
        'solution_text',
        'solution_html',
        'solution_url',
        'solution_video_url',

        'explanation',
        'explanation_text',

        'approval_status',
        'approved_by',
        'approved_at',

        'ai_metadata',
        'review_metadata',

        'source_metadata',

        'created_by',
        'updated_by'
      ]::text[];


  RETURN jsonb_build_object(
    'competition_question_id',
    p_competition_question_id,

    'question_order',
    v_question_order,

    'sent_at',
    v_sent_at,

    'deadline_at',
    v_deadline_at,

    'question',
    v_question_json
  );

END;
$$;


REVOKE ALL
ON FUNCTION public.get_competition_question_payload(uuid)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.get_competition_question_payload(uuid)
TO authenticated;


-- =========================================================
-- 11. YARIŞMA SONUCUNU KATILIMCILAR OKUYABİLSİN
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
-- 12. competition_questions DOĞRUDAN CLIENT'A AÇILMAZ
--
-- Özellikle burada SELECT policy oluşturmuyoruz.
-- Öğrenci soruyu:
--
-- get_competition_question_payload()
--
-- üzerinden alacak.
-- =========================================================


-- =========================================================
-- 13. competition_answers DOĞRUDAN INSERT YAPILAMAZ
--
-- 019'daki SELECT policy kalır.
-- INSERT policy oluşturulmuyor.
--
-- Cevap sadece:
--
-- submit_competition_answer()
--
-- RPC'si ile gönderilir.
-- =========================================================