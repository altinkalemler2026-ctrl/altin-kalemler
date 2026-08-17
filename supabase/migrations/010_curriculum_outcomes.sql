-- 010_curriculum_outcomes.sql
-- Altın Kalemler müfredat kazanım / öğrenme çıktısı altyapısı.

-- =========================================================
-- 1. KAZANIMLAR / ÖĞRENME ÇIKTILARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.curriculum_outcomes (
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
    ON DELETE SET NULL,

  subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE SET NULL,

  outcome_code text,

  outcome_text text NOT NULL,

  sort_order integer NOT NULL DEFAULT 0
    CHECK (sort_order >= 0),

  source_reference text,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_curriculum_outcomes_lookup
ON public.curriculum_outcomes(
  curriculum_version_id,
  grade_level,
  subject_id,
  topic_id,
  subtopic_id
);

CREATE INDEX IF NOT EXISTS idx_curriculum_outcomes_code
ON public.curriculum_outcomes(outcome_code);

ALTER TABLE public.curriculum_outcomes
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated users can read active curriculum outcomes"
ON public.curriculum_outcomes
FOR SELECT
TO authenticated
USING (is_active = true);

DROP TRIGGER IF EXISTS trigger_curriculum_outcomes_set_updated_at
ON public.curriculum_outcomes;

CREATE TRIGGER trigger_curriculum_outcomes_set_updated_at
BEFORE UPDATE ON public.curriculum_outcomes
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. SORU -> KAZANIM EŞLEŞTİRMELERİ
-- Bir soru birden fazla kazanımı ölçebilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_outcome_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  question_id uuid NOT NULL
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  outcome_id uuid NOT NULL
    REFERENCES public.curriculum_outcomes(id)
    ON DELETE CASCADE,

  mapping_source text NOT NULL DEFAULT 'manual'
    CHECK (
      mapping_source IN (
        'manual',
        'rule_based',
        'ai'
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

  is_primary boolean NOT NULL DEFAULT false,

  reviewed_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  reviewed_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (question_id, outcome_id)
);

CREATE INDEX IF NOT EXISTS idx_question_outcome_mappings_question
ON public.question_outcome_mappings(question_id);

CREATE INDEX IF NOT EXISTS idx_question_outcome_mappings_outcome
ON public.question_outcome_mappings(outcome_id);

CREATE INDEX IF NOT EXISTS idx_question_outcome_mappings_review
ON public.question_outcome_mappings(review_status);

ALTER TABLE public.question_outcome_mappings
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_question_outcome_mappings_set_updated_at
ON public.question_outcome_mappings;

CREATE TRIGGER trigger_question_outcome_mappings_set_updated_at
BEFORE UPDATE ON public.question_outcome_mappings
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. AI STAGING -> KAZANIM ÖNERİLERİ
-- AI'nin henüz ana soru bankasına aktarılmamış aday soruları
-- için kazanım eşleştirmesi.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.staging_outcome_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  staging_question_id uuid NOT NULL
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  outcome_id uuid NOT NULL
    REFERENCES public.curriculum_outcomes(id)
    ON DELETE CASCADE,

  mapping_source text NOT NULL DEFAULT 'ai'
    CHECK (
      mapping_source IN (
        'manual',
        'rule_based',
        'ai'
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

  is_primary boolean NOT NULL DEFAULT false,

  reasoning_summary text,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (staging_question_id, outcome_id)
);

CREATE INDEX IF NOT EXISTS idx_staging_outcome_mappings_staging
ON public.staging_outcome_mappings(staging_question_id);

CREATE INDEX IF NOT EXISTS idx_staging_outcome_mappings_outcome
ON public.staging_outcome_mappings(outcome_id);

ALTER TABLE public.staging_outcome_mappings
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_staging_outcome_mappings_set_updated_at
ON public.staging_outcome_mappings;

CREATE TRIGGER trigger_staging_outcome_mappings_set_updated_at
BEFORE UPDATE ON public.staging_outcome_mappings
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 4. ESKİ -> YENİ KAZANIM EŞLEMELERİ
-- Müfredat değiştiğinde eski kazanımı silmeden
-- yeni kazanıma bağlamak için.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.curriculum_outcome_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  source_outcome_id uuid NOT NULL
    REFERENCES public.curriculum_outcomes(id)
    ON DELETE CASCADE,

  target_outcome_id uuid NOT NULL
    REFERENCES public.curriculum_outcomes(id)
    ON DELETE CASCADE,

  relation_type text NOT NULL
    CHECK (
      relation_type IN (
        'same',
        'renamed',
        'merged',
        'split',
        'restructured',
        'mapped'
      )
    ),

  mapping_source text NOT NULL DEFAULT 'manual'
    CHECK (
      mapping_source IN (
        'manual',
        'rule_based',
        'ai'
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

  reviewed_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  reviewed_at timestamptz,

  notes text,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (source_outcome_id <> target_outcome_id),

  UNIQUE (
    source_outcome_id,
    target_outcome_id,
    relation_type
  )
);

CREATE INDEX IF NOT EXISTS idx_curriculum_outcome_aliases_source
ON public.curriculum_outcome_aliases(source_outcome_id);

CREATE INDEX IF NOT EXISTS idx_curriculum_outcome_aliases_target
ON public.curriculum_outcome_aliases(target_outcome_id);

ALTER TABLE public.curriculum_outcome_aliases
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 5. ÜRETİM ŞARTNAMESİNE KAZANIM EKLE
-- AI artık belirli bir kazanıma göre soru üretebilir.
-- =========================================================

ALTER TABLE public.ai_generation_specs
ADD COLUMN IF NOT EXISTS outcome_id uuid
REFERENCES public.curriculum_outcomes(id)
ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ai_generation_specs_outcome
ON public.ai_generation_specs(outcome_id);


-- =========================================================
-- 6. SORU HAVUZU HEDEF MATRİSİNE KAZANIM EKLE
-- =========================================================

ALTER TABLE public.question_pool_targets
ADD COLUMN IF NOT EXISTS outcome_id uuid
REFERENCES public.curriculum_outcomes(id)
ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_question_pool_targets_outcome
ON public.question_pool_targets(outcome_id);