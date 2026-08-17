-- 003_curriculum_versions.sql
-- Müfredat versiyonlama ve eski sınıflandırmaları koruma altyapısı.

-- =========================================================
-- 1. MÜFREDAT VERSİYONLARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.curriculum_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  academic_year text NOT NULL,
  framework text NOT NULL,

  source_name text NOT NULL DEFAULT 'Milli Eğitim Bakanlığı',
  source_url text,
  published_at date,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (academic_year, framework)
);

ALTER TABLE public.curriculum_versions
ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS curriculum_versions_read_active
ON public.curriculum_versions;

CREATE POLICY curriculum_versions_read_active
ON public.curriculum_versions
FOR SELECT
TO authenticated
USING (is_active = true);

DROP TRIGGER IF EXISTS trigger_curriculum_versions_set_updated_at
ON public.curriculum_versions;

CREATE TRIGGER trigger_curriculum_versions_set_updated_at
BEFORE UPDATE ON public.curriculum_versions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. TOPICS TABLOSUNU MÜFREDAT VERSİYONUNA BAĞLA
-- =========================================================

ALTER TABLE public.topics
ADD COLUMN IF NOT EXISTS curriculum_version_id uuid
REFERENCES public.curriculum_versions(id)
ON DELETE RESTRICT;

-- topics tablosu şu anda boş olduğu için bu alan zorunlu yapılabilir.
ALTER TABLE public.topics
ALTER COLUMN curriculum_version_id SET NOT NULL;

ALTER TABLE public.topics
DROP CONSTRAINT IF EXISTS topics_subject_id_grade_level_slug_key;

CREATE UNIQUE INDEX IF NOT EXISTS
idx_topics_curriculum_subject_grade_slug
ON public.topics (
  curriculum_version_id,
  subject_id,
  grade_level,
  slug
);

CREATE INDEX IF NOT EXISTS idx_topics_curriculum_version
ON public.topics(curriculum_version_id);


-- =========================================================
-- 3. ESKİ / LEGACY SINIFLANDIRMA
-- =========================================================
-- Elimizdeki mevcut 9-12. sınıf soru havuzunun eski konu ve
-- alt konu başlıkları burada aynen korunur.

CREATE TABLE IF NOT EXISTS public.legacy_taxonomy (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  source_name text NOT NULL DEFAULT 'Mevcut Soru Havuzu',

  grade_level smallint NOT NULL
    CHECK (grade_level BETWEEN 1 AND 12),

  subject_name text NOT NULL,
  topic_name text NOT NULL,
  subtopic_name text,

  legacy_code text,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS
idx_legacy_taxonomy_unique
ON public.legacy_taxonomy (
  source_name,
  grade_level,
  subject_name,
  topic_name,
  subtopic_name
)
NULLS NOT DISTINCT;

CREATE INDEX IF NOT EXISTS idx_legacy_taxonomy_grade_subject
ON public.legacy_taxonomy (
  grade_level,
  subject_name
);

ALTER TABLE public.legacy_taxonomy
ENABLE ROW LEVEL SECURITY;

-- Öğrenci uygulamasının doğrudan kullanacağı tablo değil.
DROP POLICY IF EXISTS legacy_taxonomy_read
ON public.legacy_taxonomy;

DROP TRIGGER IF EXISTS trigger_legacy_taxonomy_set_updated_at
ON public.legacy_taxonomy;

CREATE TRIGGER trigger_legacy_taxonomy_set_updated_at
BEFORE UPDATE ON public.legacy_taxonomy
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 4. ESKİ BAŞLIK -> GÜNCEL MÜFREDAT EŞLEŞTİRMESİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.curriculum_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  legacy_taxonomy_id uuid NOT NULL
    REFERENCES public.legacy_taxonomy(id)
    ON DELETE CASCADE,

  curriculum_version_id uuid NOT NULL
    REFERENCES public.curriculum_versions(id)
    ON DELETE CASCADE,

  topic_id uuid
    REFERENCES public.topics(id)
    ON DELETE CASCADE,

  subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE CASCADE,

  relation_type text NOT NULL DEFAULT 'mapped'
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

  confidence_score numeric(5,4)
    CHECK (
      confidence_score IS NULL
      OR (
        confidence_score >= 0
        AND confidence_score <= 1
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
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS
idx_curriculum_aliases_unique
ON public.curriculum_aliases (
  legacy_taxonomy_id,
  curriculum_version_id,
  topic_id,
  subtopic_id
)
NULLS NOT DISTINCT;

CREATE INDEX IF NOT EXISTS idx_curriculum_aliases_legacy
ON public.curriculum_aliases(legacy_taxonomy_id);

CREATE INDEX IF NOT EXISTS idx_curriculum_aliases_version
ON public.curriculum_aliases(curriculum_version_id);

CREATE INDEX IF NOT EXISTS idx_curriculum_aliases_topic
ON public.curriculum_aliases(topic_id);

CREATE INDEX IF NOT EXISTS idx_curriculum_aliases_subtopic
ON public.curriculum_aliases(subtopic_id);

ALTER TABLE public.curriculum_aliases
ENABLE ROW LEVEL SECURITY;

-- Öğrenci uygulamasının doğrudan kullanacağı tablo değil.
DROP POLICY IF EXISTS curriculum_aliases_read_approved
ON public.curriculum_aliases;

DROP TRIGGER IF EXISTS trigger_curriculum_aliases_set_updated_at
ON public.curriculum_aliases;

CREATE TRIGGER trigger_curriculum_aliases_set_updated_at
BEFORE UPDATE ON public.curriculum_aliases
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();