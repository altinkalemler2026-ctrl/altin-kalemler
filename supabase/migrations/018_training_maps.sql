-- 018_training_maps.sql
-- Altın Kalemler Antrenman Sahası / ilerleme haritası altyapısı.

-- =========================================================
-- 1. ANTRENMAN HARİTALARI
-- Ders, sınıf ve müfredat bazlı haritalar.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.training_maps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  map_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  curriculum_version_id uuid
    REFERENCES public.curriculum_versions(id)
    ON DELETE SET NULL,

  grade_level smallint
    CHECK (
      grade_level IS NULL
      OR grade_level BETWEEN 1 AND 12
    ),

  subject_id uuid
    REFERENCES public.subjects(id)
    ON DELETE SET NULL,

  map_type text NOT NULL DEFAULT 'subject'
    CHECK (
      map_type IN (
        'subject',
        'topic',
        'mixed',
        'exam_prep',
        'special_event',
        'custom'
      )
    ),

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  visual_settings jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_training_maps_lookup
ON public.training_maps(
  curriculum_version_id,
  grade_level,
  subject_id
);

ALTER TABLE public.training_maps
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students read active training maps"
ON public.training_maps
FOR SELECT
TO authenticated
USING (is_active = true);

DROP TRIGGER IF EXISTS trigger_training_maps_set_updated_at
ON public.training_maps;

CREATE TRIGGER trigger_training_maps_set_updated_at
BEFORE UPDATE ON public.training_maps
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. ANTRENMAN SEVİYELERİ
-- Haritadaki düğümler.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.training_levels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  training_map_id uuid NOT NULL
    REFERENCES public.training_maps(id)
    ON DELETE CASCADE,

  level_code text NOT NULL,

  name text NOT NULL,
  description text,

  sort_order integer NOT NULL DEFAULT 0,

  level_type text NOT NULL DEFAULT 'normal'
    CHECK (
      level_type IN (
        'normal',
        'challenge',
        'boss',
        'mixed_review',
        'checkpoint',
        'bonus',
        'special',
        'custom'
      )
    ),

  topic_id uuid
    REFERENCES public.topics(id)
    ON DELETE SET NULL,

  subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE SET NULL,

  outcome_id uuid
    REFERENCES public.curriculum_outcomes(id)
    ON DELETE SET NULL,

  difficulty text
    CHECK (
      difficulty IS NULL
      OR difficulty IN (
        'easy',
        'medium',
        'hard',
        'mixed'
      )
    ),

  question_count integer NOT NULL DEFAULT 10
    CHECK (question_count > 0),

  passing_accuracy numeric(5,2) NOT NULL DEFAULT 60
    CHECK (
      passing_accuracy >= 0
      AND passing_accuracy <= 100
    ),

  max_stars smallint NOT NULL DEFAULT 3
    CHECK (
      max_stars BETWEEN 1 AND 5
    ),

  replay_allowed boolean NOT NULL DEFAULT true,

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  visual_settings jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (training_map_id, level_code)
);

CREATE INDEX IF NOT EXISTS idx_training_levels_map
ON public.training_levels(
  training_map_id,
  sort_order
);

CREATE INDEX IF NOT EXISTS idx_training_levels_curriculum
ON public.training_levels(
  topic_id,
  subtopic_id,
  outcome_id
);

ALTER TABLE public.training_levels
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students read active training levels"
ON public.training_levels
FOR SELECT
TO authenticated
USING (is_active = true);

DROP TRIGGER IF EXISTS trigger_training_levels_set_updated_at
ON public.training_levels;

CREATE TRIGGER trigger_training_levels_set_updated_at
BEFORE UPDATE ON public.training_levels
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. SEVİYE BAĞLANTILARI / YOLLAR
-- Harita doğrusal olmak zorunda değil.
-- Dallanma, alternatif yol ve bonus yol olabilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.training_level_connections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  from_level_id uuid NOT NULL
    REFERENCES public.training_levels(id)
    ON DELETE CASCADE,

  to_level_id uuid NOT NULL
    REFERENCES public.training_levels(id)
    ON DELETE CASCADE,

  connection_type text NOT NULL DEFAULT 'normal'
    CHECK (
      connection_type IN (
        'normal',
        'required',
        'optional',
        'bonus',
        'challenge',
        'shortcut',
        'custom'
      )
    ),

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (from_level_id <> to_level_id),

  UNIQUE (from_level_id, to_level_id)
);

CREATE INDEX IF NOT EXISTS idx_training_connections_from
ON public.training_level_connections(from_level_id);

CREATE INDEX IF NOT EXISTS idx_training_connections_to
ON public.training_level_connections(to_level_id);

ALTER TABLE public.training_level_connections
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students read training connections"
ON public.training_level_connections
FOR SELECT
TO authenticated
USING (true);


-- =========================================================
-- 4. SEVİYE AÇILMA KOŞULLARI
-- İleride farklı şartlar eklenebilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.training_unlock_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  level_id uuid NOT NULL
    REFERENCES public.training_levels(id)
    ON DELETE CASCADE,

  rule_type text NOT NULL
    CHECK (
      rule_type IN (
        'previous_level_complete',
        'minimum_stars',
        'minimum_points',
        'minimum_accuracy',
        'league',
        'achievement',
        'date_range',
        'manual',
        'custom'
      )
    ),

  required_level_id uuid
    REFERENCES public.training_levels(id)
    ON DELETE CASCADE,

  required_value numeric,

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_required boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    required_level_id IS NULL
    OR required_level_id <> level_id
  )
);

CREATE INDEX IF NOT EXISTS idx_training_unlock_rules_level
ON public.training_unlock_rules(level_id);

ALTER TABLE public.training_unlock_rules
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students read active unlock rules"
ON public.training_unlock_rules
FOR SELECT
TO authenticated
USING (is_active = true);


-- =========================================================
-- 5. YILDIZ KURALLARI
-- Örneğin:
-- %60 = 1 yıldız
-- %80 = 2 yıldız
-- %95 = 3 yıldız
-- =========================================================

CREATE TABLE IF NOT EXISTS public.training_star_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  level_id uuid
    REFERENCES public.training_levels(id)
    ON DELETE CASCADE,

  training_map_id uuid
    REFERENCES public.training_maps(id)
    ON DELETE CASCADE,

  star_count smallint NOT NULL
    CHECK (
      star_count BETWEEN 1 AND 5
    ),

  minimum_accuracy numeric(5,2)
    CHECK (
      minimum_accuracy IS NULL
      OR (
        minimum_accuracy >= 0
        AND minimum_accuracy <= 100
      )
    ),

  maximum_time_seconds integer
    CHECK (
      maximum_time_seconds IS NULL
      OR maximum_time_seconds > 0
    ),

  minimum_correct integer
    CHECK (
      minimum_correct IS NULL
      OR minimum_correct >= 0
    ),

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    level_id IS NOT NULL
    OR training_map_id IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS idx_training_star_rules_level
ON public.training_star_rules(level_id);

ALTER TABLE public.training_star_rules
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students read active star rules"
ON public.training_star_rules
FOR SELECT
TO authenticated
USING (is_active = true);


-- =========================================================
-- 6. ÖĞRENCİ HARİTA İLERLEMESİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.student_training_progress (
  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  training_map_id uuid NOT NULL
    REFERENCES public.training_maps(id)
    ON DELETE CASCADE,

  total_stars integer NOT NULL DEFAULT 0
    CHECK (total_stars >= 0),

  completed_levels integer NOT NULL DEFAULT 0
    CHECK (completed_levels >= 0),

  progress_percent numeric(5,2) NOT NULL DEFAULT 0
    CHECK (
      progress_percent >= 0
      AND progress_percent <= 100
    ),

  current_level_id uuid
    REFERENCES public.training_levels(id)
    ON DELETE SET NULL,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (user_id, training_map_id)
);

ALTER TABLE public.student_training_progress
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own training progress"
ON public.student_training_progress
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

DROP TRIGGER IF EXISTS trigger_student_training_progress_set_updated_at
ON public.student_training_progress;

CREATE TRIGGER trigger_student_training_progress_set_updated_at
BEFORE UPDATE ON public.student_training_progress
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 7. ÖĞRENCİ SEVİYE İLERLEMESİ
-- Bir seviyeyi tekrar tekrar çözebilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.student_training_levels (
  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  level_id uuid NOT NULL
    REFERENCES public.training_levels(id)
    ON DELETE CASCADE,

  status text NOT NULL DEFAULT 'locked'
    CHECK (
      status IN (
        'locked',
        'unlocked',
        'in_progress',
        'completed',
        'mastered'
      )
    ),

  best_stars smallint NOT NULL DEFAULT 0
    CHECK (
      best_stars BETWEEN 0 AND 5
    ),

  best_accuracy numeric(5,2)
    CHECK (
      best_accuracy IS NULL
      OR (
        best_accuracy >= 0
        AND best_accuracy <= 100
      )
    ),

  best_time_seconds integer
    CHECK (
      best_time_seconds IS NULL
      OR best_time_seconds >= 0
    ),

  attempt_count integer NOT NULL DEFAULT 0
    CHECK (attempt_count >= 0),

  completed_count integer NOT NULL DEFAULT 0
    CHECK (completed_count >= 0),

  first_completed_at timestamptz,
  last_played_at timestamptz,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  updated_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (user_id, level_id)
);

ALTER TABLE public.student_training_levels
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own training levels"
ON public.student_training_levels
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

DROP TRIGGER IF EXISTS trigger_student_training_levels_set_updated_at
ON public.student_training_levels;

CREATE TRIGGER trigger_student_training_levels_set_updated_at
BEFORE UPDATE ON public.student_training_levels
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 8. ANTRENMAN DENEMELERİ
-- Her oynama ayrı kayıt.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.training_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  level_id uuid NOT NULL
    REFERENCES public.training_levels(id)
    ON DELETE CASCADE,

  attempt_number integer NOT NULL
    CHECK (attempt_number > 0),

  question_count integer NOT NULL DEFAULT 0
    CHECK (question_count >= 0),

  correct_count integer NOT NULL DEFAULT 0
    CHECK (correct_count >= 0),

  wrong_count integer NOT NULL DEFAULT 0
    CHECK (wrong_count >= 0),

  pass_count integer NOT NULL DEFAULT 0
    CHECK (pass_count >= 0),

  accuracy numeric(5,2)
    CHECK (
      accuracy IS NULL
      OR (
        accuracy >= 0
        AND accuracy <= 100
      )
    ),

  stars_earned smallint NOT NULL DEFAULT 0
    CHECK (
      stars_earned BETWEEN 0 AND 5
    ),

  total_time_seconds integer
    CHECK (
      total_time_seconds IS NULL
      OR total_time_seconds >= 0
    ),

  points_earned integer NOT NULL DEFAULT 0
    CHECK (points_earned >= 0),

  completed boolean NOT NULL DEFAULT false,

  result_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,

  CHECK (
    correct_count + wrong_count + pass_count <= question_count
  )
);

CREATE INDEX IF NOT EXISTS idx_training_attempts_user
ON public.training_attempts(
  user_id,
  started_at DESC
);

CREATE INDEX IF NOT EXISTS idx_training_attempts_level
ON public.training_attempts(level_id);

ALTER TABLE public.training_attempts
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own training attempts"
ON public.training_attempts
FOR SELECT
TO authenticated
USING (user_id = auth.uid());


-- =========================================================
-- 9. SEVİYE ÖDÜLLERİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.training_level_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  level_id uuid NOT NULL
    REFERENCES public.training_levels(id)
    ON DELETE CASCADE,

  trigger_type text NOT NULL DEFAULT 'complete'
    CHECK (
      trigger_type IN (
        'complete',
        'first_complete',
        'star_count',
        'perfect',
        'mastery',
        'custom'
      )
    ),

  trigger_value numeric,

  reward_type text NOT NULL
    CHECK (
      reward_type IN (
        'points',
        'stars',
        'badge',
        'cosmetic',
        'character',
        'title',
        'custom'
      )
    ),

  reward_value integer
    CHECK (
      reward_value IS NULL
      OR reward_value >= 0
    ),

  reward_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_repeatable boolean NOT NULL DEFAULT false,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.training_level_rewards
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students read active training rewards"
ON public.training_level_rewards
FOR SELECT
TO authenticated
USING (is_active = true);