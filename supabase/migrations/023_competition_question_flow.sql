-- 023_competition_question_flow.sql
-- Altın Kalemler
--
-- Server-authoritative yarışma soru akışı.
--
-- - Her yarışmada 1-5 soru
-- - İki oyuncu hazır olmadan yarışma başlamaz
-- - İlk soru server tarafından açılır
-- - sent_at / deadline_at server tarafından belirlenir
-- - Soruya özel onaylı çözüm süresi profili kullanılır
-- - Profil yoksa güvenli fallback süre uygulanır
-- - İki oyuncu da cevaplayınca sıradaki soru açılır
-- - Süre dolarsa cevap vermeyen oyuncu timeout olur
-- - Son soru tamamlanınca yarışma kapanır


-- =========================================================
-- 1. COMPETITION_QUESTIONS TABLOSUNA
-- SÜRE SNAPSHOT ALANLARI
-- =========================================================

ALTER TABLE public.competition_questions
ADD COLUMN IF NOT EXISTS time_limit_seconds integer
CHECK (
  time_limit_seconds IS NULL
  OR time_limit_seconds > 0
);


ALTER TABLE public.competition_questions
ADD COLUMN IF NOT EXISTS solve_time_profile_id uuid
REFERENCES public.question_solve_time_profiles(id)
ON DELETE SET NULL;


ALTER TABLE public.competition_questions
ADD COLUMN IF NOT EXISTS timing_source text
CHECK (
  timing_source IS NULL
  OR timing_source IN (
    'question_profile',
    'question_configuration',
    'competition_configuration',
    'default'
  )
);


ALTER TABLE public.competition_questions
ADD COLUMN IF NOT EXISTS released_at timestamptz;


ALTER TABLE public.competition_questions
ADD COLUMN IF NOT EXISTS completed_at timestamptz;


-- =========================================================
-- 2. YARIŞMA AKIŞ DURUMU
-- =========================================================

ALTER TABLE public.competitions
ADD COLUMN IF NOT EXISTS current_question_order integer
CHECK (
  current_question_order IS NULL
  OR current_question_order BETWEEN 1 AND 5
);


ALTER TABLE public.competitions
ADD COLUMN IF NOT EXISTS current_question_id uuid
REFERENCES public.competition_questions(id)
ON DELETE SET NULL;


-- =========================================================
-- 3. SORUYA UYGUN SÜREYİ SERVER BELİRLESİN
--
-- Öncelik:
--
-- 1. Onaylanmış question_solve_time_profile
-- 2. competition_questions.configuration
-- 3. competitions.configuration
-- 4. 90 saniye varsayılan
--
-- Sonuç ayrıca minimum/maksimum güvenlik sınırından geçer.
-- =========================================================

CREATE OR REPLACE FUNCTION public.resolve_competition_question_time_limit(
  p_competition_question_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_question_id uuid;
  v_competition_id uuid;

  v_question_configuration jsonb;
  v_competition_configuration jsonb;

  v_profile_id uuid;

  v_profile_recommended numeric;
  v_profile_estimated numeric;

  v_time_limit integer;
  v_timing_source text;

  v_minimum_time integer;
  v_maximum_time integer;
BEGIN

  SELECT
    cq.question_id,
    cq.competition_id,
    cq.configuration,
    c.configuration

  INTO
    v_question_id,
    v_competition_id,
    v_question_configuration,
    v_competition_configuration

  FROM public.competition_questions cq

  JOIN public.competitions c
    ON c.id = cq.competition_id

  WHERE cq.id = p_competition_question_id;


  IF v_question_id IS NULL THEN
    RAISE EXCEPTION
      'Competition question not found.';
  END IF;


  -- -------------------------------------------------------
  -- Güvenlik sınırları
  --
  -- Yarışmaya göre ileride admin panelinden değişebilir.
  -- Default:
  -- minimum 10 sn
  -- maksimum 300 sn
  -- -------------------------------------------------------

  v_minimum_time :=
    COALESCE(
      NULLIF(
        v_competition_configuration
          ->> 'minimum_question_time_seconds',
        ''
      )::integer,
      10
    );


  v_maximum_time :=
    COALESCE(
      NULLIF(
        v_competition_configuration
          ->> 'maximum_question_time_seconds',
        ''
      )::integer,
      300
    );


  IF v_minimum_time < 1 THEN
    v_minimum_time := 1;
  END IF;


  IF v_maximum_time < v_minimum_time THEN
    v_maximum_time := v_minimum_time;
  END IF;


  -- -------------------------------------------------------
  -- 1. SORUYA ÖZEL ONAYLI SÜRE PROFİLİ
  -- -------------------------------------------------------

  SELECT
    p.id,
    p.recommended_time_limit_seconds,
    p.estimated_total_time_seconds

  INTO
    v_profile_id,
    v_profile_recommended,
    v_profile_estimated

  FROM public.question_solve_time_profiles p

  WHERE p.question_id = v_question_id
    AND p.is_current = true
    AND p.is_approved_for_scoring = true
    AND p.review_status IN (
      'human_reviewed',
      'approved'
    )

  ORDER BY p.analysis_version DESC
  LIMIT 1;


  IF v_profile_id IS NOT NULL THEN

    v_time_limit :=
      CEIL(
        COALESCE(
          v_profile_recommended,
          v_profile_estimated
        )
      )::integer;

    v_timing_source := 'question_profile';

  END IF;


  -- -------------------------------------------------------
  -- 2. YARIŞMA SORUSUNA ÖZEL MANUEL SÜRE
  -- -------------------------------------------------------

  IF v_time_limit IS NULL THEN

    v_time_limit :=
      NULLIF(
        v_question_configuration
          ->> 'time_limit_seconds',
        ''
      )::integer;

    IF v_time_limit IS NOT NULL THEN
      v_timing_source := 'question_configuration';
    END IF;

  END IF;


  -- -------------------------------------------------------
  -- 3. YARIŞMA GENEL SÜRESİ
  -- -------------------------------------------------------

  IF v_time_limit IS NULL THEN

    v_time_limit :=
      NULLIF(
        v_competition_configuration
          ->> 'default_question_time_seconds',
        ''
      )::integer;

    IF v_time_limit IS NOT NULL THEN
      v_timing_source := 'competition_configuration';
    END IF;

  END IF;


  -- -------------------------------------------------------
  -- 4. SON FALLBACK
  -- -------------------------------------------------------

  IF v_time_limit IS NULL THEN

    v_time_limit := 90;
    v_timing_source := 'default';

  END IF;


  -- -------------------------------------------------------
  -- Güvenlik sınırına al
  -- -------------------------------------------------------

  v_time_limit :=
    GREATEST(
      v_minimum_time,
      LEAST(
        v_time_limit,
        v_maximum_time
      )
    );


  RETURN jsonb_build_object(
    'time_limit_seconds',
    v_time_limit,

    'timing_source',
    v_timing_source,

    'solve_time_profile_id',
    v_profile_id,

    'minimum_time_seconds',
    v_minimum_time,

    'maximum_time_seconds',
    v_maximum_time
  );

END;
$$;


REVOKE ALL
ON FUNCTION public.resolve_competition_question_time_limit(uuid)
FROM PUBLIC;


-- =========================================================
-- 4. BİR SORUYU SERVER TARAFINDAN AÇ
--
-- Bu internal fonksiyondur.
-- Öğrenci doğrudan çalıştıramaz.
-- =========================================================

CREATE OR REPLACE FUNCTION public.release_competition_question(
  p_competition_id uuid,
  p_question_order integer
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_question_id uuid;
  v_now timestamptz;

  v_timing jsonb;

  v_time_limit integer;
  v_timing_source text;
  v_profile_id uuid;
BEGIN

  IF p_question_order < 1
     OR p_question_order > 5 THEN

    RAISE EXCEPTION
      'Question order must be between 1 and 5.';

  END IF;


  -- -------------------------------------------------------
  -- Yarışma satırını kilitle.
  -- -------------------------------------------------------

  PERFORM 1

  FROM public.competitions c

  WHERE c.id = p_competition_id

  FOR UPDATE;


  -- -------------------------------------------------------
  -- İstenen sıradaki soru.
  -- -------------------------------------------------------

  SELECT cq.id
  INTO v_question_id

  FROM public.competition_questions cq

  WHERE cq.competition_id = p_competition_id
    AND cq.question_order = p_question_order;


  IF v_question_id IS NULL THEN

    RAISE EXCEPTION
      'Competition question not found for order %.',

      p_question_order;

  END IF;


  -- -------------------------------------------------------
  -- Daha önce açıldıysa tekrar timer başlatma.
  -- -------------------------------------------------------

  IF EXISTS (
    SELECT 1

    FROM public.competition_questions cq

    WHERE cq.id = v_question_id
      AND cq.sent_at IS NOT NULL
  ) THEN

    RETURN v_question_id;

  END IF;


  -- -------------------------------------------------------
  -- Süreyi çöz.
  -- -------------------------------------------------------

  v_timing :=
    public.resolve_competition_question_time_limit(
      v_question_id
    );


  v_time_limit :=
    (v_timing ->> 'time_limit_seconds')::integer;


  v_timing_source :=
    v_timing ->> 'timing_source';


  IF (
    v_timing ->> 'solve_time_profile_id'
  ) IS NOT NULL THEN

    v_profile_id :=
      (
        v_timing ->> 'solve_time_profile_id'
      )::uuid;

  END IF;


  -- -------------------------------------------------------
  -- Server başlangıç zamanı.
  -- -------------------------------------------------------

  v_now := clock_timestamp();


  UPDATE public.competition_questions
  SET
    time_limit_seconds = v_time_limit,

    solve_time_profile_id = v_profile_id,

    timing_source = v_timing_source,

    sent_at = v_now,

    released_at = v_now,

    deadline_at =
      v_now
      + make_interval(
          secs => v_time_limit
        )

  WHERE id = v_question_id
    AND sent_at IS NULL;


  UPDATE public.competitions
  SET
    current_question_order = p_question_order,
    current_question_id = v_question_id,

    status = 'active',

    server_started_at =
      COALESCE(
        server_started_at,
        v_now
      ),

    started_at =
      COALESCE(
        started_at,
        v_now
      )

  WHERE id = p_competition_id;


  RETURN v_question_id;

END;
$$;


REVOKE ALL
ON FUNCTION public.release_competition_question(
  uuid,
  integer
)
FROM PUBLIC;


-- =========================================================
-- 5. OYUNCU HAZIR OL RPC
--
-- Öğrenci sadece kendisini hazır yapabilir.
--
-- İki oyuncu da hazır olduğunda:
-- yarışma otomatik başlar ve ilk soru açılır.
-- =========================================================

CREATE OR REPLACE FUNCTION public.set_competition_player_ready(
  p_competition_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;

  v_player_count integer;
  v_ready_count integer;

  v_question_count integer;
  v_declared_question_count integer;

  v_first_question_id uuid;

  v_status text;
BEGIN

  v_user_id := auth.uid();


  IF v_user_id IS NULL THEN
    RAISE EXCEPTION
      'Authentication required.';
  END IF;


  -- -------------------------------------------------------
  -- Yarışma satırını kilitle.
  -- -------------------------------------------------------

  SELECT c.status,
         c.question_count

  INTO
    v_status,
    v_declared_question_count

  FROM public.competitions c

  WHERE c.id = p_competition_id

  FOR UPDATE;


  IF v_status IS NULL THEN
    RAISE EXCEPTION
      'Competition not found.';
  END IF;


  IF v_status IN (
    'completed',
    'cancelled',
    'abandoned'
  ) THEN

    RAISE EXCEPTION
      'Competition cannot be started.';

  END IF;


  -- -------------------------------------------------------
  -- Gerçek katılımcı mı?
  -- -------------------------------------------------------

  IF NOT public.is_competition_participant(
    p_competition_id,
    v_user_id
  ) THEN

    RAISE EXCEPTION
      'You are not a participant in this competition.';

  END IF;


  -- -------------------------------------------------------
  -- Kendisini ready yap.
  -- -------------------------------------------------------

  UPDATE public.competition_players
  SET
    status = 'ready',
    ready_at = COALESCE(
      ready_at,
      clock_timestamp()
    )

  WHERE competition_id = p_competition_id
    AND user_id = v_user_id

    AND status IN (
      'joined',
      'ready'
    );


  -- -------------------------------------------------------
  -- Tam olarak iki yarışmacı olmalı.
  -- -------------------------------------------------------

  SELECT COUNT(*)
  INTO v_player_count

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id;


  IF v_player_count <> 2 THEN

    RETURN jsonb_build_object(
      'status',
      'waiting_for_players',

      'player_count',
      v_player_count,

      'ready_count',
      0
    );

  END IF;


  -- -------------------------------------------------------
  -- Soru sayısı 1-5 ve ilan edilen sayıyla aynı olmalı.
  -- -------------------------------------------------------

  SELECT COUNT(*)
  INTO v_question_count

  FROM public.competition_questions cq

  WHERE cq.competition_id = p_competition_id;


  IF v_declared_question_count NOT BETWEEN 1 AND 5 THEN

    RAISE EXCEPTION
      'Competition question count must be between 1 and 5.';

  END IF;


  IF v_question_count <> v_declared_question_count THEN

    RAISE EXCEPTION
      'Competition questions are not ready. Expected %, found %.',
      v_declared_question_count,
      v_question_count;

  END IF;


  -- -------------------------------------------------------
  -- Sıra numaraları 1..N eksiksiz olmalı.
  -- -------------------------------------------------------

  IF EXISTS (
    SELECT gs.question_order

    FROM generate_series(
      1,
      v_declared_question_count
    ) AS gs(question_order)

    WHERE NOT EXISTS (
      SELECT 1

      FROM public.competition_questions cq

      WHERE cq.competition_id =
            p_competition_id

        AND cq.question_order =
            gs.question_order
    )
  ) THEN

    RAISE EXCEPTION
      'Competition question order is incomplete.';

  END IF;


  SELECT COUNT(*)
  INTO v_ready_count

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id
    AND cp.status = 'ready';


  -- -------------------------------------------------------
  -- İki oyuncu hazırsa ilk soruyu aç.
  -- -------------------------------------------------------

  IF v_ready_count = 2 THEN

    UPDATE public.competition_players
    SET status = 'active'

    WHERE competition_id = p_competition_id
      AND status = 'ready';


    UPDATE public.competitions
    SET status = 'active'

    WHERE id = p_competition_id;


    v_first_question_id :=
      public.release_competition_question(
        p_competition_id,
        1
      );


    RETURN jsonb_build_object(
      'status',
      'started',

      'ready_count',
      2,

      'current_question_id',
      v_first_question_id,

      'current_question_order',
      1
    );

  END IF;


  RETURN jsonb_build_object(
    'status',
    'waiting_for_opponent',

    'ready_count',
    v_ready_count,

    'player_count',
    v_player_count
  );

END;
$$;


REVOKE ALL
ON FUNCTION public.set_competition_player_ready(uuid)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.set_competition_player_ready(uuid)
TO authenticated;


-- =========================================================
-- 6. EKSİK CEVAPLARI TIMEOUT OLARAK KAYDET
--
-- Deadline geçtiyse ve oyuncu cevap vermediyse
-- server otomatik timeout oluşturur.
-- =========================================================

CREATE OR REPLACE FUNCTION public.create_missing_competition_timeouts(
  p_competition_question_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_competition_id uuid;
  v_question_id uuid;

  v_sent_at timestamptz;
  v_deadline_at timestamptz;

  v_grade_level smallint;
  v_rule_set_id uuid;
  v_difficulty text;

  v_time_ms integer;

  v_band_code text;
  v_points integer;

  v_player record;

  v_inserted integer := 0;
BEGIN

  SELECT
    cq.competition_id,
    cq.question_id,
    cq.sent_at,
    cq.deadline_at,
    cq.difficulty,

    c.grade_level,
    c.scoring_rule_set_id

  INTO
    v_competition_id,
    v_question_id,
    v_sent_at,
    v_deadline_at,
    v_difficulty,

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


  IF v_sent_at IS NULL
     OR v_deadline_at IS NULL THEN

    RETURN 0;

  END IF;


  -- Deadline henüz geçmediyse timeout üretme.
  IF clock_timestamp() <= v_deadline_at THEN
    RETURN 0;
  END IF;


  v_time_ms :=
    GREATEST(
      0,

      FLOOR(
        EXTRACT(
          EPOCH FROM (
            v_deadline_at - v_sent_at
          )
        ) * 1000
      )::integer
    );


  v_band_code :=
    public.resolve_competition_time_band(
      v_question_id,
      v_rule_set_id,
      v_grade_level,
      v_difficulty,
      v_time_ms
    );


  v_points :=
    public.resolve_competition_points(
      v_rule_set_id,
      v_grade_level,
      v_difficulty,
      'timeout',
      v_band_code
    );


  FOR v_player IN

    SELECT cp.user_id

    FROM public.competition_players cp

    WHERE cp.competition_id = v_competition_id
      AND cp.status <> 'forfeited'

  LOOP

    IF NOT EXISTS (
      SELECT 1

      FROM public.competition_answers ca

      WHERE ca.competition_question_id =
            p_competition_question_id

        AND ca.user_id =
            v_player.user_id
    ) THEN

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
        v_player.user_id,

        NULL,
        'timeout',

        v_sent_at,
        v_deadline_at,
        v_deadline_at,

        v_time_ms,
        v_band_code,

        v_points,

        true,

        jsonb_build_object(
          'validation_source',
          'server_timeout',

          'question_id',
          v_question_id,

          'scoring_rule_set_id',
          v_rule_set_id
        )
      )

      ON CONFLICT (
        competition_question_id,
        user_id
      )
      DO NOTHING;


      IF FOUND THEN
        v_inserted := v_inserted + 1;
      END IF;

    END IF;

  END LOOP;


  RETURN v_inserted;

END;
$$;


REVOKE ALL
ON FUNCTION public.create_missing_competition_timeouts(uuid)
FROM PUBLIC;


-- =========================================================
-- 7. YARIŞMAYI İLERLET
--
-- Kurallar:
--
-- - İki oyuncu da mevcut soruyu cevapladıysa:
--     sonraki soru açılır.
--
-- - Deadline geçtiyse:
--     eksik cevaplar timeout olur,
--     sonra sonraki soru açılır.
--
-- - Son soru tamamlandıysa:
--     yarışma sonuçlandırılır.
-- =========================================================

CREATE OR REPLACE FUNCTION public.advance_competition_progress(
  p_competition_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;

  v_question_count integer;
  v_current_order integer;
  v_current_question_id uuid;

  v_deadline_at timestamptz;

  v_active_player_count integer;
  v_answer_count integer;

  v_next_question_id uuid;

  v_player record;
BEGIN

  -- -------------------------------------------------------
  -- Yarışma satırını kilitle.
  -- -------------------------------------------------------

  SELECT
    c.status,
    c.question_count,
    c.current_question_order,
    c.current_question_id

  INTO
    v_status,
    v_question_count,
    v_current_order,
    v_current_question_id

  FROM public.competitions c

  WHERE c.id = p_competition_id

  FOR UPDATE;


  IF v_status IS NULL THEN
    RAISE EXCEPTION
      'Competition not found.';
  END IF;


  IF v_status = 'completed' THEN

    RETURN jsonb_build_object(
      'status',
      'completed'
    );

  END IF;


  IF v_status <> 'active' THEN

    RETURN jsonb_build_object(
      'status',
      v_status
    );

  END IF;


  IF v_current_question_id IS NULL THEN

    RAISE EXCEPTION
      'Competition does not have an active question.';

  END IF;


  SELECT cq.deadline_at
  INTO v_deadline_at

  FROM public.competition_questions cq

  WHERE cq.id = v_current_question_id;


  -- -------------------------------------------------------
  -- Deadline geçtiyse eksik cevapları timeout yap.
  -- -------------------------------------------------------

  IF v_deadline_at IS NOT NULL
     AND clock_timestamp() > v_deadline_at THEN

    PERFORM
      public.create_missing_competition_timeouts(
        v_current_question_id
      );

  END IF;


  -- -------------------------------------------------------
  -- Aktif/normal oyuncu sayısı.
  -- -------------------------------------------------------

  SELECT COUNT(*)
  INTO v_active_player_count

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id
    AND cp.status <> 'forfeited';


  -- -------------------------------------------------------
  -- Bu soruya cevap sayısı.
  -- -------------------------------------------------------

  SELECT COUNT(*)
  INTO v_answer_count

  FROM public.competition_answers ca

  WHERE ca.competition_question_id =
        v_current_question_id;


  -- -------------------------------------------------------
  -- Herkes henüz bitirmediyse bekle.
  -- -------------------------------------------------------

  IF v_answer_count < v_active_player_count
     AND (
       v_deadline_at IS NULL
       OR clock_timestamp() <= v_deadline_at
     ) THEN

    RETURN jsonb_build_object(
      'status',
      'waiting_for_answers',

      'current_question_id',
      v_current_question_id,

      'current_question_order',
      v_current_order,

      'answer_count',
      v_answer_count,

      'player_count',
      v_active_player_count,

      'deadline_at',
      v_deadline_at
    );

  END IF;


  -- -------------------------------------------------------
  -- Mevcut soruyu tamamlandı işaretle.
  -- -------------------------------------------------------

  UPDATE public.competition_questions
  SET completed_at = COALESCE(
    completed_at,
    clock_timestamp()
  )

  WHERE id = v_current_question_id;


  -- -------------------------------------------------------
  -- Oyuncu skorlarını cevaplardan yeniden oluştur.
  -- -------------------------------------------------------

  FOR v_player IN

    SELECT cp.user_id

    FROM public.competition_players cp

    WHERE cp.competition_id = p_competition_id

  LOOP

    PERFORM
      public.recalculate_competition_player_score(
        p_competition_id,
        v_player.user_id
      );

  END LOOP;


  -- -------------------------------------------------------
  -- SON SORUYSA yarışmayı bitir.
  -- -------------------------------------------------------

  IF v_current_order >= v_question_count THEN

    PERFORM
      public.finalize_competition_if_ready(
        p_competition_id
      );


    RETURN jsonb_build_object(
      'status',
      'completed',

      'last_question_order',
      v_current_order
    );

  END IF;


  -- -------------------------------------------------------
  -- Sıradaki soruyu aç.
  -- -------------------------------------------------------

  v_next_question_id :=
    public.release_competition_question(
      p_competition_id,
      v_current_order + 1
    );


  RETURN jsonb_build_object(
    'status',
    'next_question',

    'current_question_id',
    v_next_question_id,

    'current_question_order',
    v_current_order + 1
  );

END;
$$;


REVOKE ALL
ON FUNCTION public.advance_competition_progress(uuid)
FROM PUBLIC;


-- =========================================================
-- 8. CLIENT SENKRONİZASYON RPC
--
-- Telefon sadece "yarışmanın güncel durumunu getir" der.
--
-- Bu fonksiyon:
-- - deadline geçmiş mi kontrol eder
-- - timeout üretir
-- - gerekirse sonraki soruyu açar
-- - güvenli güncel durumu döndürür
-- =========================================================

CREATE OR REPLACE FUNCTION public.sync_competition_state(
  p_competition_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;

  v_progress jsonb;

  v_status text;

  v_current_question_id uuid;
  v_current_question_order integer;

  v_sent_at timestamptz;
  v_deadline_at timestamptz;
  v_time_limit_seconds integer;

  v_has_answered boolean;

  v_my_points integer;
  v_opponent_points integer;
BEGIN

  v_user_id := auth.uid();


  IF v_user_id IS NULL THEN
    RAISE EXCEPTION
      'Authentication required.';
  END IF;


  IF NOT public.is_competition_participant(
    p_competition_id,
    v_user_id
  ) THEN

    RAISE EXCEPTION
      'You are not a participant in this competition.';

  END IF;


  -- -------------------------------------------------------
  -- Önce server state'i ilerlet.
  -- -------------------------------------------------------

  v_progress :=
    public.advance_competition_progress(
      p_competition_id
    );


  SELECT
    c.status,
    c.current_question_id,
    c.current_question_order

  INTO
    v_status,
    v_current_question_id,
    v_current_question_order

  FROM public.competitions c

  WHERE c.id = p_competition_id;


  -- -------------------------------------------------------
  -- Yarışma bitti.
  -- -------------------------------------------------------

  IF v_status = 'completed' THEN

    RETURN jsonb_build_object(
      'status',
      'completed',

      'scoreboard_available',
      true
    );

  END IF;


  -- -------------------------------------------------------
  -- Güncel soru zamanı.
  -- -------------------------------------------------------

  IF v_current_question_id IS NOT NULL THEN

    SELECT
      cq.sent_at,
      cq.deadline_at,
      cq.time_limit_seconds

    INTO
      v_sent_at,
      v_deadline_at,
      v_time_limit_seconds

    FROM public.competition_questions cq

    WHERE cq.id = v_current_question_id;


    SELECT EXISTS (
      SELECT 1

      FROM public.competition_answers ca

      WHERE ca.competition_question_id =
            v_current_question_id

        AND ca.user_id =
            v_user_id
    )

    INTO v_has_answered;

  END IF;


  -- -------------------------------------------------------
  -- Kendi anlık toplam skoru.
  -- -------------------------------------------------------

  SELECT cp.total_points
  INTO v_my_points

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id
    AND cp.user_id = v_user_id;


  -- -------------------------------------------------------
  -- Rakip anlık toplam skoru.
  --
  -- Bu ileride ürün kararına göre yarışma sırasında
  -- gizlenebilir. Şimdilik altyapı destekliyor.
  -- -------------------------------------------------------

  SELECT cp.total_points
  INTO v_opponent_points

  FROM public.competition_players cp

  WHERE cp.competition_id = p_competition_id
    AND cp.user_id <> v_user_id

  LIMIT 1;


  RETURN jsonb_build_object(
    'status',
    v_status,

    'progress',
    v_progress,

    'current_question_id',
    v_current_question_id,

    'current_question_order',
    v_current_question_order,

    'sent_at',
    v_sent_at,

    'deadline_at',
    v_deadline_at,

    'time_limit_seconds',
    v_time_limit_seconds,

    'has_answered_current_question',
    COALESCE(
      v_has_answered,
      false
    ),

    'my_current_score',
    COALESCE(
      v_my_points,
      0
    ),

    'opponent_current_score',
    COALESCE(
      v_opponent_points,
      0
    )
  );

END;
$$;


REVOKE ALL
ON FUNCTION public.sync_competition_state(uuid)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.sync_competition_state(uuid)
TO authenticated;


-- =========================================================
-- 9. 021'DEKİ SUBMIT FONKSİYONUNDAN SONRA
-- OTOMATİK İLERLEME TRIGGER'I
--
-- Cevap geldikten sonra yarışma akışı kontrol edilir.
--
-- Timeout toplu ekleme sırasında recursive trigger
-- oluşmasını pg_trigger_depth() ile engelliyoruz.
-- =========================================================

CREATE OR REPLACE FUNCTION public.after_competition_answer_progress()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

  -- Nested trigger içindeysek tekrar ilerletme.
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;


  -- -------------------------------------------------------
  -- Önce cevap veren oyuncunun skorunu yenile.
  -- Böylece son sorudaki puan yarışma sonucuna doğru girer.
  -- -------------------------------------------------------

  PERFORM public.recalculate_competition_player_score(
    NEW.competition_id,
    NEW.user_id
  );


  -- -------------------------------------------------------
  -- Sonra yarışmayı ilerlet.
  -- -------------------------------------------------------

  PERFORM public.advance_competition_progress(
    NEW.competition_id
  );


  RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS
trigger_after_competition_answer_progress
ON public.competition_answers;


CREATE TRIGGER
trigger_after_competition_answer_progress
AFTER INSERT
ON public.competition_answers
FOR EACH ROW
EXECUTE FUNCTION public.after_competition_answer_progress();


-- =========================================================
-- 10. GÜNCEL SORU PAYLOAD RPC
--
-- Client competition_question_id bilmek zorunda kalmadan
-- güncel soruyu güvenli biçimde alabilir.
--
-- Doğru cevap yine dönmez.
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_current_competition_question()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;

  v_competition_id uuid;
  v_question_id uuid;

  v_status text;

  v_payload jsonb;
BEGIN

  v_user_id := auth.uid();


  IF v_user_id IS NULL THEN
    RAISE EXCEPTION
      'Authentication required.';
  END IF;


  -- -------------------------------------------------------
  -- Kullanıcının aktif yarışması.
  -- Aynı anda tek aktif 1v1 varsayımı.
  -- -------------------------------------------------------

  SELECT
    c.id,
    c.current_question_id,
    c.status

  INTO
    v_competition_id,
    v_question_id,
    v_status

  FROM public.competitions c

  JOIN public.competition_players cp
    ON cp.competition_id = c.id

  WHERE cp.user_id = v_user_id

    AND c.status IN (
      'ready',
      'active'
    )

  ORDER BY c.created_at DESC

  LIMIT 1;


  IF v_competition_id IS NULL THEN

    RETURN jsonb_build_object(
      'status',
      'no_active_competition'
    );

  END IF;


  -- Server durumunu güncelle.
  PERFORM public.sync_competition_state(
    v_competition_id
  );


  SELECT
    c.current_question_id,
    c.status

  INTO
    v_question_id,
    v_status

  FROM public.competitions c

  WHERE c.id = v_competition_id;


  IF v_status = 'completed' THEN

    RETURN jsonb_build_object(
      'status',
      'completed',

      'competition_id',
      v_competition_id,

      'scoreboard_available',
      true
    );

  END IF;


  IF v_question_id IS NULL THEN

    RETURN jsonb_build_object(
      'status',
      v_status,

      'competition_id',
      v_competition_id,

      'question_available',
      false
    );

  END IF;


  v_payload :=
    public.get_competition_question_payload(
      v_question_id
    );


  RETURN jsonb_build_object(
    'status',
    v_status,

    'competition_id',
    v_competition_id,

    'question_available',
    true,

    'payload',
    v_payload
  );

END;
$$;


REVOKE ALL
ON FUNCTION public.get_current_competition_question()
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.get_current_competition_question()
TO authenticated;


-- =========================================================
-- 11. ADMIN POLİTİKALARI
-- =========================================================

DROP POLICY IF EXISTS
"admins manage competitions"
ON public.competitions;

CREATE POLICY
"admins manage competitions"
ON public.competitions
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission(
    'competitions.manage'
  )
  OR
  public.current_user_has_admin_permission(
    'questions.edit'
  )
)
WITH CHECK (
  public.current_user_has_admin_permission(
    'competitions.manage'
  )
  OR
  public.current_user_has_admin_permission(
    'questions.edit'
  )
);


DROP POLICY IF EXISTS
"admins manage competition questions"
ON public.competition_questions;

CREATE POLICY
"admins manage competition questions"
ON public.competition_questions
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission(
    'competitions.manage'
  )
  OR
  public.current_user_has_admin_permission(
    'questions.edit'
  )
)
WITH CHECK (
  public.current_user_has_admin_permission(
    'competitions.manage'
  )
  OR
  public.current_user_has_admin_permission(
    'questions.edit'
  )
);