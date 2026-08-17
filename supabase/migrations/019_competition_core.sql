-- 019_competition_core.sql
-- Altın Kalemler 1v1 yarışma çekirdeği.

-- =========================================================
-- 1. PUANLAMA KURAL SETLERİ
-- Geçmiş yarışmalar eski kurallarla korunabilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.scoring_rule_sets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  rule_set_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  version text NOT NULL,

  is_active boolean NOT NULL DEFAULT true,

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.scoring_rule_sets
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_scoring_rule_sets_updated_at
ON public.scoring_rule_sets;

CREATE TRIGGER trigger_scoring_rule_sets_updated_at
BEFORE UPDATE ON public.scoring_rule_sets
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. SÜRE BANTLARI
-- Sınıf + zorluk + sonuç bandı.
-- Örn: mükemmel / iyi / orta / kötü / çözemedi / pas
-- =========================================================

CREATE TABLE IF NOT EXISTS public.scoring_time_bands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  rule_set_id uuid NOT NULL
    REFERENCES public.scoring_rule_sets(id)
    ON DELETE CASCADE,

  grade_level smallint NOT NULL
    CHECK (grade_level BETWEEN 1 AND 12),

  difficulty text NOT NULL
    CHECK (
      difficulty IN (
        'easy',
        'medium',
        'hard'
      )
    ),

  band_code text NOT NULL,

  band_name text NOT NULL,

  min_time_ms integer
    CHECK (
      min_time_ms IS NULL
      OR min_time_ms >= 0
    ),

  max_time_ms integer
    CHECK (
      max_time_ms IS NULL
      OR max_time_ms >= 0
    ),

  sort_order integer NOT NULL DEFAULT 0,

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    min_time_ms IS NULL
    OR max_time_ms IS NULL
    OR min_time_ms < max_time_ms
  ),

  UNIQUE (
    rule_set_id,
    grade_level,
    difficulty,
    band_code
  )
);

CREATE INDEX IF NOT EXISTS idx_scoring_time_bands_lookup
ON public.scoring_time_bands(
  rule_set_id,
  grade_level,
  difficulty,
  sort_order
);

ALTER TABLE public.scoring_time_bands
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 3. PUAN KURALLARI
-- Doğru / yanlış / pas + süre bandına göre puan.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.scoring_point_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  rule_set_id uuid NOT NULL
    REFERENCES public.scoring_rule_sets(id)
    ON DELETE CASCADE,

  grade_level smallint NOT NULL
    CHECK (grade_level BETWEEN 1 AND 12),

  difficulty text NOT NULL
    CHECK (
      difficulty IN (
        'easy',
        'medium',
        'hard'
      )
    ),

  answer_result text NOT NULL
    CHECK (
      answer_result IN (
        'correct',
        'wrong',
        'pass',
        'timeout'
      )
    ),

  band_code text,

  points integer NOT NULL DEFAULT 0,

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_scoring_point_rules_lookup
ON public.scoring_point_rules(
  rule_set_id,
  grade_level,
  difficulty,
  answer_result,
  band_code
);

ALTER TABLE public.scoring_point_rules
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 4. EŞLEŞTİRME KUYRUĞU
-- =========================================================

CREATE TABLE IF NOT EXISTS public.matchmaking_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  grade_level smallint NOT NULL
    CHECK (grade_level BETWEEN 1 AND 12),

  subject_id uuid
    REFERENCES public.subjects(id)
    ON DELETE SET NULL,

  league_id uuid
    REFERENCES public.leagues(id)
    ON DELETE SET NULL,

  queue_type text NOT NULL DEFAULT 'standard'
    CHECK (
      queue_type IN (
        'standard',
        'subject',
        'league',
        'ranked',
        'friendly',
        'tournament',
        'custom'
      )
    ),

  status text NOT NULL DEFAULT 'waiting'
    CHECK (
      status IN (
        'waiting',
        'matched',
        'cancelled',
        'expired'
      )
    ),

  preferences jsonb NOT NULL DEFAULT '{}'::jsonb,

  joined_at timestamptz NOT NULL DEFAULT now(),
  matched_at timestamptz,
  expires_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_matchmaking_waiting
ON public.matchmaking_queue(
  status,
  grade_level,
  subject_id,
  league_id,
  joined_at
);

ALTER TABLE public.matchmaking_queue
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own matchmaking queue"
ON public.matchmaking_queue
FOR SELECT
TO authenticated
USING (user_id = auth.uid());


-- =========================================================
-- 5. YARIŞMALAR
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  competition_code text NOT NULL UNIQUE,

  competition_type text NOT NULL DEFAULT 'one_vs_one'
    CHECK (
      competition_type IN (
        'one_vs_one',
        'friendly',
        'ranked',
        'league',
        'tournament',
        'special',
        'custom'
      )
    ),

  grade_level smallint NOT NULL
    CHECK (grade_level BETWEEN 1 AND 12),

  subject_id uuid
    REFERENCES public.subjects(id)
    ON DELETE SET NULL,

  scoring_rule_set_id uuid NOT NULL
    REFERENCES public.scoring_rule_sets(id)
    ON DELETE RESTRICT,

  status text NOT NULL DEFAULT 'created'
    CHECK (
      status IN (
        'created',
        'waiting',
        'ready',
        'active',
        'completed',
        'cancelled',
        'abandoned',
        'disputed'
      )
    ),

  question_count integer NOT NULL
    CHECK (question_count > 0),

  winner_user_id uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  started_at timestamptz,
  completed_at timestamptz,

  server_started_at timestamptz,
  server_completed_at timestamptz,

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_competitions_status
ON public.competitions(status);

CREATE INDEX IF NOT EXISTS idx_competitions_subject_grade
ON public.competitions(
  grade_level,
  subject_id
);

ALTER TABLE public.competitions
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_competitions_updated_at
ON public.competitions;

CREATE TRIGGER trigger_competitions_updated_at
BEFORE UPDATE ON public.competitions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 6. YARIŞMACILAR
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competition_players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  competition_id uuid NOT NULL
    REFERENCES public.competitions(id)
    ON DELETE CASCADE,

  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  player_slot smallint NOT NULL
    CHECK (player_slot IN (1, 2)),

  status text NOT NULL DEFAULT 'joined'
    CHECK (
      status IN (
        'joined',
        'ready',
        'active',
        'finished',
        'disconnected',
        'forfeited'
      )
    ),

  total_points integer NOT NULL DEFAULT 0,

  correct_count integer NOT NULL DEFAULT 0
    CHECK (correct_count >= 0),

  wrong_count integer NOT NULL DEFAULT 0
    CHECK (wrong_count >= 0),

  pass_count integer NOT NULL DEFAULT 0
    CHECK (pass_count >= 0),

  timeout_count integer NOT NULL DEFAULT 0
    CHECK (timeout_count >= 0),

  joined_at timestamptz NOT NULL DEFAULT now(),
  ready_at timestamptz,
  finished_at timestamptz,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  UNIQUE (competition_id, user_id),
  UNIQUE (competition_id, player_slot)
);

CREATE INDEX IF NOT EXISTS idx_competition_players_user
ON public.competition_players(user_id);

ALTER TABLE public.competition_players
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "players read own competitions"
ON public.competition_players
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.competition_players cp
    WHERE cp.competition_id = competition_id
      AND cp.user_id = auth.uid()
  )
);


-- =========================================================
-- 7. YARIŞMA SORULARI
-- İki öğrenciye aynı soru sırası.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competition_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  competition_id uuid NOT NULL
    REFERENCES public.competitions(id)
    ON DELETE CASCADE,

  question_id uuid NOT NULL
    REFERENCES public.questions(id)
    ON DELETE RESTRICT,

  question_order integer NOT NULL
    CHECK (question_order > 0),

  difficulty text NOT NULL
    CHECK (
      difficulty IN (
        'easy',
        'medium',
        'hard'
      )
    ),

  sent_at timestamptz,
  deadline_at timestamptz,

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (competition_id, question_order),
  UNIQUE (competition_id, question_id),

  CHECK (
    sent_at IS NULL
    OR deadline_at IS NULL
    OR deadline_at > sent_at
  )
);

CREATE INDEX IF NOT EXISTS idx_competition_questions_order
ON public.competition_questions(
  competition_id,
  question_order
);

ALTER TABLE public.competition_questions
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 8. YARIŞMA CEVAPLARI
-- Süre client'tan değil server timestamp'lerinden hesaplanır.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competition_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  competition_id uuid NOT NULL
    REFERENCES public.competitions(id)
    ON DELETE CASCADE,

  competition_question_id uuid NOT NULL
    REFERENCES public.competition_questions(id)
    ON DELETE CASCADE,

  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  submitted_answer text
    CHECK (
      submitted_answer IS NULL
      OR submitted_answer IN (
        'A',
        'B',
        'C',
        'D',
        'E'
      )
    ),

  answer_result text NOT NULL
    CHECK (
      answer_result IN (
        'correct',
        'wrong',
        'pass',
        'timeout'
      )
    ),

  sent_at timestamptz NOT NULL,
  deadline_at timestamptz NOT NULL,

  answer_received_at timestamptz NOT NULL DEFAULT now(),

  time_ms integer NOT NULL
    CHECK (time_ms >= 0),

  time_band_code text,

  points_awarded integer NOT NULL DEFAULT 0,

  server_validated boolean NOT NULL DEFAULT false,

  validation_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    competition_question_id,
    user_id
  ),

  CHECK (deadline_at > sent_at),

  CHECK (
    time_ms =
    GREATEST(
      0,
      FLOOR(
        EXTRACT(
          EPOCH FROM (
            LEAST(answer_received_at, deadline_at) - sent_at
          )
        ) * 1000
      )::integer
    )
  )
);

CREATE INDEX IF NOT EXISTS idx_competition_answers_competition
ON public.competition_answers(competition_id);

CREATE INDEX IF NOT EXISTS idx_competition_answers_user
ON public.competition_answers(user_id);

ALTER TABLE public.competition_answers
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own competition answers"
ON public.competition_answers
FOR SELECT
TO authenticated
USING (user_id = auth.uid());


-- =========================================================
-- 9. BAĞLANTI KOPMA KAYITLARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competition_disconnects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  competition_id uuid NOT NULL
    REFERENCES public.competitions(id)
    ON DELETE CASCADE,

  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  disconnected_at timestamptz NOT NULL DEFAULT now(),
  reconnected_at timestamptz,

  disconnect_reason text,

  duration_ms integer
    CHECK (
      duration_ms IS NULL
      OR duration_ms >= 0
    ),

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  CHECK (
    reconnected_at IS NULL
    OR reconnected_at >= disconnected_at
  )
);

CREATE INDEX IF NOT EXISTS idx_competition_disconnects_lookup
ON public.competition_disconnects(
  competition_id,
  user_id,
  disconnected_at
);

ALTER TABLE public.competition_disconnects
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own disconnects"
ON public.competition_disconnects
FOR SELECT
TO authenticated
USING (user_id = auth.uid());


-- =========================================================
-- 10. YARIŞMA SONUÇ ÖZETİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competition_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  competition_id uuid NOT NULL UNIQUE
    REFERENCES public.competitions(id)
    ON DELETE CASCADE,

  winner_user_id uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  result_type text NOT NULL
    CHECK (
      result_type IN (
        'win_loss',
        'draw',
        'forfeit',
        'cancelled',
        'disputed'
      )
    ),

  player_results jsonb NOT NULL DEFAULT '{}'::jsonb,

  scoring_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,

  calculated_at timestamptz NOT NULL DEFAULT now(),

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.competition_results
ENABLE ROW LEVEL SECURITY;