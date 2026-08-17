-- 009_question_generation_rules.sql
-- Altın Kalemler soru üretim kuralları ve hedef matrisi.

-- =========================================================
-- 1. SINIF / KONU UYGUNLUK KURALLARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_generation_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  curriculum_version_id uuid
    REFERENCES public.curriculum_versions(id)
    ON DELETE CASCADE,

  grade_level smallint
    CHECK (
      grade_level IS NULL
      OR grade_level BETWEEN 1 AND 12
    ),

  subject_id uuid
    REFERENCES public.subjects(id)
    ON DELETE CASCADE,

  topic_id uuid
    REFERENCES public.topics(id)
    ON DELETE CASCADE,

  subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE CASCADE,

  rule_type text NOT NULL
    CHECK (
      rule_type IN (
        'grade_appropriateness',
        'topic_coherence',
        'prerequisite',
        'forbidden_concept',
        'allowed_concept',
        'language_level',
        'difficulty',
        'question_type',
        'solve_time',
        'generation_instruction'
      )
    ),

  rule_text text NOT NULL,

  severity text NOT NULL DEFAULT 'warning'
    CHECK (
      severity IN (
        'info',
        'warning',
        'blocking'
      )
    ),

  source_type text NOT NULL DEFAULT 'manual'
    CHECK (
      source_type IN (
        'manual',
        'curriculum',
        'rule_based',
        'ai_suggested'
      )
    ),

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_question_generation_rules_target
ON public.question_generation_rules(
  curriculum_version_id,
  grade_level,
  subject_id,
  topic_id,
  subtopic_id
);

CREATE INDEX IF NOT EXISTS idx_question_generation_rules_type
ON public.question_generation_rules(rule_type);

ALTER TABLE public.question_generation_rules
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_question_generation_rules_set_updated_at
ON public.question_generation_rules;

CREATE TRIGGER trigger_question_generation_rules_set_updated_at
BEFORE UPDATE ON public.question_generation_rules
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. KONU / ALT KONU ÖN KOŞUL İLİŞKİLERİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.curriculum_prerequisites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  curriculum_version_id uuid NOT NULL
    REFERENCES public.curriculum_versions(id)
    ON DELETE CASCADE,

  target_topic_id uuid
    REFERENCES public.topics(id)
    ON DELETE CASCADE,

  target_subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE CASCADE,

  prerequisite_topic_id uuid
    REFERENCES public.topics(id)
    ON DELETE CASCADE,

  prerequisite_subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE CASCADE,

  prerequisite_grade_level smallint
    CHECK (
      prerequisite_grade_level IS NULL
      OR prerequisite_grade_level BETWEEN 1 AND 12
    ),

  requirement_level text NOT NULL DEFAULT 'recommended'
    CHECK (
      requirement_level IN (
        'required',
        'recommended',
        'optional'
      )
    ),

  source_type text NOT NULL DEFAULT 'manual'
    CHECK (
      source_type IN (
        'manual',
        'curriculum',
        'rule_based',
        'ai_suggested'
      )
    ),

  confidence numeric(5,4)
    CHECK (
      confidence IS NULL
      OR (
        confidence >= 0
        AND confidence <= 1
      )
    ),

  review_status text NOT NULL DEFAULT 'pending'
    CHECK (
      review_status IN (
        'pending',
        'approved',
        'rejected',
        'needs_review'
      )
    ),

  notes text,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    target_topic_id IS NOT NULL
    OR target_subtopic_id IS NOT NULL
  ),

  CHECK (
    prerequisite_topic_id IS NOT NULL
    OR prerequisite_subtopic_id IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS idx_curriculum_prerequisites_target
ON public.curriculum_prerequisites(
  curriculum_version_id,
  target_topic_id,
  target_subtopic_id
);

ALTER TABLE public.curriculum_prerequisites
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_curriculum_prerequisites_set_updated_at
ON public.curriculum_prerequisites;

CREATE TRIGGER trigger_curriculum_prerequisites_set_updated_at
BEFORE UPDATE ON public.curriculum_prerequisites
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. SORU HAVUZU HEDEF MATRİSİ
-- Sınıf x ders x konu x alt konu x zorluk x bilişsel seviye
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_pool_targets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  curriculum_version_id uuid NOT NULL
    REFERENCES public.curriculum_versions(id)
    ON DELETE CASCADE,

  grade_level smallint NOT NULL
    CHECK (grade_level BETWEEN 1 AND 12),

  subject_id uuid NOT NULL
    REFERENCES public.subjects(id)
    ON DELETE CASCADE,

  topic_id uuid
    REFERENCES public.topics(id)
    ON DELETE CASCADE,

  subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE CASCADE,

  difficulty text
    CHECK (
      difficulty IS NULL
      OR difficulty IN (
        'easy',
        'medium',
        'hard'
      )
    ),

  cognitive_type text
    CHECK (
      cognitive_type IS NULL
      OR cognitive_type IN (
        'learning',
        'comprehension',
        'application'
      )
    ),

  primary_question_type text,

  target_count integer NOT NULL DEFAULT 0
    CHECK (target_count >= 0),

  minimum_count integer NOT NULL DEFAULT 0
    CHECK (minimum_count >= 0),

  maximum_count integer
    CHECK (
      maximum_count IS NULL
      OR maximum_count >= 0
    ),

  priority text NOT NULL DEFAULT 'normal'
    CHECK (
      priority IN (
        'low',
        'normal',
        'high',
        'critical'
      )
    ),

  allow_ai_generation boolean NOT NULL DEFAULT true,

  notes text,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    maximum_count IS NULL
    OR minimum_count <= maximum_count
  ),

  CHECK (
    target_count >= minimum_count
  )
);

CREATE INDEX IF NOT EXISTS idx_question_pool_targets_lookup
ON public.question_pool_targets(
  curriculum_version_id,
  grade_level,
  subject_id,
  topic_id,
  subtopic_id
);

CREATE INDEX IF NOT EXISTS idx_question_pool_targets_priority
ON public.question_pool_targets(priority);

ALTER TABLE public.question_pool_targets
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_question_pool_targets_set_updated_at
ON public.question_pool_targets;

CREATE TRIGGER trigger_question_pool_targets_set_updated_at
BEFORE UPDATE ON public.question_pool_targets
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 4. AI GAP ANALYSIS SONUÇLARI
-- Hangi alanda kaç soru eksik/fazla?
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_pool_gap_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  target_id uuid NOT NULL
    REFERENCES public.question_pool_targets(id)
    ON DELETE CASCADE,

  current_count integer NOT NULL DEFAULT 0
    CHECK (current_count >= 0),

  target_count integer NOT NULL DEFAULT 0
    CHECK (target_count >= 0),

  missing_count integer NOT NULL DEFAULT 0
    CHECK (missing_count >= 0),

  excess_count integer NOT NULL DEFAULT 0
    CHECK (excess_count >= 0),

  gap_status text NOT NULL
    CHECK (
      gap_status IN (
        'empty',
        'insufficient',
        'balanced',
        'excess'
      )
    ),

  analyzed_by_job_id uuid
    REFERENCES public.ai_jobs(id)
    ON DELETE SET NULL,

  analyzed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_question_pool_gap_results_target
ON public.question_pool_gap_results(target_id);

CREATE INDEX IF NOT EXISTS idx_question_pool_gap_results_status
ON public.question_pool_gap_results(gap_status);

ALTER TABLE public.question_pool_gap_results
ENABLE ROW LEVEL SECURITY;