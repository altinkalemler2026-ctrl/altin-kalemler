-- 015_student_leaderboards.sql
-- Altın Kalemler esnek öğrenci public profil ve leaderboard altyapısı.

-- =========================================================
-- 1. LEADERBOARD SEZONLARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.leaderboard_seasons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  season_code text NOT NULL UNIQUE,
  name text NOT NULL,

  season_type text NOT NULL DEFAULT 'monthly'
    CHECK (
      season_type IN (
        'daily',
        'weekly',
        'monthly',
        'yearly',
        'special',
        'tournament'
      )
    ),

  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,

  is_active boolean NOT NULL DEFAULT false,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (ends_at > starts_at)
);

ALTER TABLE public.leaderboard_seasons
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read leaderboard seasons"
ON public.leaderboard_seasons
FOR SELECT
TO authenticated
USING (true);

DROP TRIGGER IF EXISTS trigger_leaderboard_seasons_set_updated_at
ON public.leaderboard_seasons;

CREATE TRIGGER trigger_leaderboard_seasons_set_updated_at
BEFORE UPDATE ON public.leaderboard_seasons
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. LEADERBOARD TANIMLARI
-- Yeni sıralama türleri tablo değiştirmeden eklenebilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.leaderboard_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  leaderboard_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  scope_type text NOT NULL
    CHECK (
      scope_type IN (
        'general',
        'grade',
        'subject',
        'topic',
        'subtopic',
        'league',
        'team',
        'friends',
        'school',
        'city',
        'special_event',
        'tournament',
        'custom'
      )
    ),

  ranking_metric text NOT NULL DEFAULT 'points',

  sort_direction text NOT NULL DEFAULT 'desc'
    CHECK (
      sort_direction IN ('asc', 'desc')
    ),

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.leaderboard_definitions
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read leaderboard definitions"
ON public.leaderboard_definitions
FOR SELECT
TO authenticated
USING (is_active = true);

DROP TRIGGER IF EXISTS trigger_leaderboard_definitions_set_updated_at
ON public.leaderboard_definitions;

CREATE TRIGGER trigger_leaderboard_definitions_set_updated_at
BEFORE UPDATE ON public.leaderboard_definitions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. GÜVENLİ PUBLIC ÖĞRENCİ PROFİLİ
-- Buraya e-posta, telefon, gerçek ad vb. konmaz.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.student_public_profiles (
  user_id uuid PRIMARY KEY
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  nickname text NOT NULL,

  grade_level smallint NOT NULL
    CHECK (grade_level BETWEEN 1 AND 12),

  avatar_key text,
  character_key text,
  league_code text,

  total_points integer NOT NULL DEFAULT 0
    CHECK (total_points >= 0),

  monthly_points integer NOT NULL DEFAULT 0
    CHECK (monthly_points >= 0),

  public_stats jsonb NOT NULL DEFAULT '{}'::jsonb,

  badges jsonb NOT NULL DEFAULT '[]'::jsonb,

  cosmetics jsonb NOT NULL DEFAULT '{}'::jsonb,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_visible boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.student_public_profiles
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read visible public profiles"
ON public.student_public_profiles
FOR SELECT
TO authenticated
USING (
  is_visible = true
  OR user_id = auth.uid()
);

-- Öğrenci bu tabloya doğrudan puan/istatistik yazamaz.
-- Güncellemeler server-side yapılacak.

DROP TRIGGER IF EXISTS trigger_student_public_profiles_set_updated_at
ON public.student_public_profiles;

CREATE TRIGGER trigger_student_public_profiles_set_updated_at
BEFORE UPDATE ON public.student_public_profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 4. GÖRÜNÜRLÜK AYARLARI
-- İleride yeni görünürlük anahtarları JSON'a eklenebilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.student_visibility_settings (
  user_id uuid PRIMARY KEY
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  profile_visibility text NOT NULL DEFAULT 'authenticated'
    CHECK (
      profile_visibility IN (
        'private',
        'same_grade',
        'same_league',
        'authenticated'
      )
    ),

  show_points boolean NOT NULL DEFAULT true,
  show_rank boolean NOT NULL DEFAULT true,
  show_accuracy boolean NOT NULL DEFAULT true,
  show_correct_count boolean NOT NULL DEFAULT true,
  show_competition_count boolean NOT NULL DEFAULT true,
  show_wins boolean NOT NULL DEFAULT true,
  show_streak boolean NOT NULL DEFAULT true,
  show_badges boolean NOT NULL DEFAULT true,
  show_league boolean NOT NULL DEFAULT true,

  additional_visibility jsonb NOT NULL DEFAULT '{}'::jsonb,

  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.student_visibility_settings
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own visibility settings"
ON public.student_visibility_settings
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "student updates own visibility settings"
ON public.student_visibility_settings
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY "student inserts own visibility settings"
ON public.student_visibility_settings
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP TRIGGER IF EXISTS trigger_student_visibility_settings_set_updated_at
ON public.student_visibility_settings;

CREATE TRIGGER trigger_student_visibility_settings_set_updated_at
BEFORE UPDATE ON public.student_visibility_settings
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 5. LEADERBOARD KAYITLARI
-- Scope sistemi sayesinde ileride farklı sıralamalar eklenebilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.leaderboard_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  season_id uuid NOT NULL
    REFERENCES public.leaderboard_seasons(id)
    ON DELETE CASCADE,

  leaderboard_definition_id uuid NOT NULL
    REFERENCES public.leaderboard_definitions(id)
    ON DELETE CASCADE,

  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  grade_level smallint
    CHECK (
      grade_level IS NULL
      OR grade_level BETWEEN 1 AND 12
    ),

  subject_id uuid
    REFERENCES public.subjects(id)
    ON DELETE SET NULL,

  topic_id uuid
    REFERENCES public.topics(id)
    ON DELETE SET NULL,

  subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE SET NULL,

  scope_type text NOT NULL DEFAULT 'general',

  scope_reference_id uuid,

  league_code text,

  points integer NOT NULL DEFAULT 0
    CHECK (points >= 0),

  rank_position integer
    CHECK (
      rank_position IS NULL
      OR rank_position > 0
    ),

  previous_rank_position integer
    CHECK (
      previous_rank_position IS NULL
      OR previous_rank_position > 0
    ),

  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_leaderboard_entries_lookup
ON public.leaderboard_entries(
  season_id,
  leaderboard_definition_id,
  grade_level,
  subject_id,
  league_code,
  points DESC
);

CREATE INDEX IF NOT EXISTS idx_leaderboard_entries_user
ON public.leaderboard_entries(user_id);

CREATE INDEX IF NOT EXISTS idx_leaderboard_entries_scope
ON public.leaderboard_entries(
  scope_type,
  scope_reference_id
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_leaderboard_entries_unique
ON public.leaderboard_entries(
  season_id,
  leaderboard_definition_id,
  user_id,
  scope_type,
  COALESCE(scope_reference_id, '00000000-0000-0000-0000-000000000000'::uuid)
);

ALTER TABLE public.leaderboard_entries
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 6. ÖĞRENCİ LEADERBOARD OKUMA KURALI
-- Kendi sınıfındaki detaylı sıralamayı görebilir.
-- =========================================================

CREATE POLICY "students read leaderboard entries"
ON public.leaderboard_entries
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR grade_level = (
    SELECT sp.grade_level
    FROM public.student_profiles sp
    WHERE sp.id = auth.uid()
  )
);

-- Öğrenci leaderboard_entry yazamaz.
-- Bunlar server-side yarışma motoru tarafından oluşturulacak.


-- =========================================================
-- 7. LEADERBOARD SNAPSHOT
-- Geçmiş sıralama değişimlerini saklamak için.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.leaderboard_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  leaderboard_entry_id uuid NOT NULL
    REFERENCES public.leaderboard_entries(id)
    ON DELETE CASCADE,

  rank_position integer
    CHECK (
      rank_position IS NULL
      OR rank_position > 0
    ),

  points integer NOT NULL DEFAULT 0
    CHECK (points >= 0),

  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,

  snapshot_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_leaderboard_snapshots_entry
ON public.leaderboard_snapshots(
  leaderboard_entry_id,
  snapshot_at DESC
);

ALTER TABLE public.leaderboard_snapshots
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students read own leaderboard snapshots"
ON public.leaderboard_snapshots
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.leaderboard_entries le
    WHERE le.id = leaderboard_entry_id
      AND le.user_id = auth.uid()
  )
);


-- =========================================================
-- 8. BAŞARI YÜZDESİ YARDIMCI FONKSİYONU
-- =========================================================

CREATE OR REPLACE FUNCTION public.calculate_accuracy(
  p_correct integer,
  p_answered integer
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_answered IS NULL
      OR p_answered <= 0
    THEN 0
    ELSE ROUND(
      (p_correct::numeric / p_answered::numeric) * 100,
      1
    )
  END;
$$;


-- =========================================================
-- 9. BAŞLANGIÇ LEADERBOARD TANIMLARI
-- İleride admin panelinden yenileri eklenebilir.
-- =========================================================

INSERT INTO public.leaderboard_definitions (
  leaderboard_code,
  name,
  description,
  scope_type,
  ranking_metric,
  sort_direction
)
VALUES
(
  'monthly_general',
  'Aylık Genel Sıralama',
  'Öğrencilerin aylık genel puan sıralaması.',
  'grade',
  'points',
  'desc'
),
(
  'monthly_subject',
  'Aylık Ders Sıralaması',
  'Sınıf ve ders bazında aylık sıralama.',
  'subject',
  'points',
  'desc'
),
(
  'league_ranking',
  'Lig Sıralaması',
  'Aynı ligde bulunan öğrencilerin sıralaması.',
  'league',
  'points',
  'desc'
)
ON CONFLICT (leaderboard_code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  scope_type = EXCLUDED.scope_type,
  ranking_metric = EXCLUDED.ranking_metric,
  sort_direction = EXCLUDED.sort_direction,
  is_active = true;