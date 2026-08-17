-- 016_leagues_and_seasons.sql
-- Altın Kalemler esnek lig, yükselme/düşme ve sezon kuralları.

-- =========================================================
-- 1. LİG TANIMLARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.leagues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  league_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  sort_order integer NOT NULL DEFAULT 0,

  min_points integer NOT NULL DEFAULT 0
    CHECK (min_points >= 0),

  max_points integer
    CHECK (
      max_points IS NULL
      OR max_points >= 0
    ),

  league_type text NOT NULL DEFAULT 'standard'
    CHECK (
      league_type IN (
        'standard',
        'subject',
        'tournament',
        'special',
        'seasonal',
        'custom'
      )
    ),

  icon_key text,

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    max_points IS NULL
    OR max_points >= min_points
  )
);

CREATE INDEX IF NOT EXISTS idx_leagues_sort
ON public.leagues(sort_order);

ALTER TABLE public.leagues
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read active leagues"
ON public.leagues
FOR SELECT
TO authenticated
USING (is_active = true);

DROP TRIGGER IF EXISTS trigger_leagues_set_updated_at
ON public.leagues;

CREATE TRIGGER trigger_leagues_set_updated_at
BEFORE UPDATE ON public.leagues
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. LİG KURAL SETLERİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.league_rule_sets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  rule_set_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  rule_type text NOT NULL DEFAULT 'points'
    CHECK (
      rule_type IN (
        'points',
        'rank',
        'percentage',
        'mixed',
        'custom'
      )
    ),

  applies_to_scope text NOT NULL DEFAULT 'general'
    CHECK (
      applies_to_scope IN (
        'general',
        'subject',
        'grade',
        'tournament',
        'custom'
      )
    ),

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.league_rule_sets
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read active league rule sets"
ON public.league_rule_sets
FOR SELECT
TO authenticated
USING (is_active = true);

DROP TRIGGER IF EXISTS trigger_league_rule_sets_set_updated_at
ON public.league_rule_sets;

CREATE TRIGGER trigger_league_rule_sets_set_updated_at
BEFORE UPDATE ON public.league_rule_sets
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. LİG GEÇİŞ KURALLARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.league_transition_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  from_league_id uuid
    REFERENCES public.leagues(id)
    ON DELETE CASCADE,

  to_league_id uuid
    REFERENCES public.leagues(id)
    ON DELETE CASCADE,

  rule_set_id uuid
    REFERENCES public.league_rule_sets(id)
    ON DELETE SET NULL,

  transition_type text NOT NULL
    CHECK (
      transition_type IN (
        'promotion',
        'demotion',
        'placement',
        'reset',
        'special'
      )
    ),

  min_points integer
    CHECK (
      min_points IS NULL
      OR min_points >= 0
    ),

  max_points integer
    CHECK (
      max_points IS NULL
      OR max_points >= 0
    ),

  min_rank integer
    CHECK (
      min_rank IS NULL
      OR min_rank > 0
    ),

  max_rank integer
    CHECK (
      max_rank IS NULL
      OR max_rank > 0
    ),

  min_percentile numeric(5,2)
    CHECK (
      min_percentile IS NULL
      OR (
        min_percentile >= 0
        AND min_percentile <= 100
      )
    ),

  max_percentile numeric(5,2)
    CHECK (
      max_percentile IS NULL
      OR (
        max_percentile >= 0
        AND max_percentile <= 100
      )
    ),

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    from_league_id IS NULL
    OR to_league_id IS NULL
    OR from_league_id <> to_league_id
  )
);

CREATE INDEX IF NOT EXISTS idx_league_transition_from
ON public.league_transition_rules(from_league_id);

CREATE INDEX IF NOT EXISTS idx_league_transition_to
ON public.league_transition_rules(to_league_id);

ALTER TABLE public.league_transition_rules
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read active league transitions"
ON public.league_transition_rules
FOR SELECT
TO authenticated
USING (is_active = true);


-- =========================================================
-- 4. ÖĞRENCİ LİG ÜYELİKLERİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.student_league_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  league_id uuid NOT NULL
    REFERENCES public.leagues(id)
    ON DELETE CASCADE,

  season_id uuid
    REFERENCES public.leaderboard_seasons(id)
    ON DELETE SET NULL,

  subject_id uuid
    REFERENCES public.subjects(id)
    ON DELETE SET NULL,

  membership_scope text NOT NULL DEFAULT 'general'
    CHECK (
      membership_scope IN (
        'general',
        'subject',
        'tournament',
        'special',
        'custom'
      )
    ),

  points_at_entry integer NOT NULL DEFAULT 0
    CHECK (points_at_entry >= 0),

  current_points integer NOT NULL DEFAULT 0
    CHECK (current_points >= 0),

  entered_at timestamptz NOT NULL DEFAULT now(),
  exited_at timestamptz,

  is_current boolean NOT NULL DEFAULT true,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_student_league_memberships_user
ON public.student_league_memberships(user_id);

CREATE INDEX IF NOT EXISTS idx_student_league_memberships_current
ON public.student_league_memberships(
  user_id,
  is_current
);

ALTER TABLE public.student_league_memberships
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own league memberships"
ON public.student_league_memberships
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
);


DROP TRIGGER IF EXISTS trigger_student_league_memberships_set_updated_at
ON public.student_league_memberships;

CREATE TRIGGER trigger_student_league_memberships_set_updated_at
BEFORE UPDATE ON public.student_league_memberships
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 5. LİG HAREKET GEÇMİŞİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.student_league_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  season_id uuid
    REFERENCES public.leaderboard_seasons(id)
    ON DELETE SET NULL,

  from_league_id uuid
    REFERENCES public.leagues(id)
    ON DELETE SET NULL,

  to_league_id uuid
    REFERENCES public.leagues(id)
    ON DELETE SET NULL,

  transition_type text NOT NULL
    CHECK (
      transition_type IN (
        'promotion',
        'demotion',
        'placement',
        'reset',
        'manual',
        'special'
      )
    ),

  points_at_transition integer
    CHECK (
      points_at_transition IS NULL
      OR points_at_transition >= 0
    ),

  rank_at_transition integer
    CHECK (
      rank_at_transition IS NULL
      OR rank_at_transition > 0
    ),

  reason text,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_student_league_history_user
ON public.student_league_history(
  user_id,
  created_at DESC
);

ALTER TABLE public.student_league_history
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own league history"
ON public.student_league_history
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
);


-- =========================================================
-- 6. LİG ÖDÜLLERİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.league_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  league_id uuid
    REFERENCES public.leagues(id)
    ON DELETE CASCADE,

  season_id uuid
    REFERENCES public.leaderboard_seasons(id)
    ON DELETE CASCADE,

  reward_type text NOT NULL
    CHECK (
      reward_type IN (
        'points',
        'stars',
        'badge',
        'cosmetic',
        'character_item',
        'title',
        'custom'
      )
    ),

  reward_code text,
  reward_value integer
    CHECK (
      reward_value IS NULL
      OR reward_value >= 0
    ),

  reward_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  condition_type text NOT NULL DEFAULT 'league_finish'
    CHECK (
      condition_type IN (
        'league_finish',
        'promotion',
        'top_rank',
        'streak',
        'special',
        'custom'
      )
    ),

  condition_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.league_rewards
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read active league rewards"
ON public.league_rewards
FOR SELECT
TO authenticated
USING (is_active = true);


-- =========================================================
-- 7. BAŞLANGIÇ LİGLERİ
-- Puanlar başlangıç değeridir; admin panelinden değiştirilebilir.
-- =========================================================

INSERT INTO public.leagues (
  league_code,
  name,
  sort_order,
  min_points,
  max_points,
  league_type
)
VALUES
(
  'bronze',
  'Bronz Lig',
  10,
  0,
  999,
  'standard'
),
(
  'silver',
  'Gümüş Lig',
  20,
  1000,
  2499,
  'standard'
),
(
  'gold',
  'Altın Lig',
  30,
  2500,
  4999,
  'standard'
),
(
  'diamond',
  'Elmas Lig',
  40,
  5000,
  NULL,
  'standard'
)
ON CONFLICT (league_code) DO UPDATE
SET
  name = EXCLUDED.name,
  sort_order = EXCLUDED.sort_order,
  min_points = EXCLUDED.min_points,
  max_points = EXCLUDED.max_points,
  league_type = EXCLUDED.league_type,
  is_active = true;


-- =========================================================
-- 8. BAŞLANGIÇ KURAL SETİ
-- =========================================================

INSERT INTO public.league_rule_sets (
  rule_set_code,
  name,
  description,
  rule_type,
  applies_to_scope,
  configuration
)
VALUES
(
  'standard_points',
  'Standart Puan Ligi',
  'Lig geçişlerini toplam puana göre hesaplayan başlangıç kural seti.',
  'points',
  'general',
  '{
    "season_reset_enabled": true,
    "allow_promotion": true,
    "allow_demotion": true,
    "manual_override_allowed": true
  }'::jsonb
)
ON CONFLICT (rule_set_code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  rule_type = EXCLUDED.rule_type,
  applies_to_scope = EXCLUDED.applies_to_scope,
  configuration = EXCLUDED.configuration,
  is_active = true;