-- 004_questions_foundation.sql
-- Altın Kalemler soru bankası çekirdek altyapısı.

-- =========================================================
-- 1. SORU KAYNAKLARI
-- Kitap, PDF, Excel, manuel giriş veya AI üretimi.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_sources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  source_type text NOT NULL
    CHECK (
      source_type IN (
        'book',
        'pdf',
        'excel',
        'manual',
        'ai_generated',
        'other'
      )
    ),

  title text NOT NULL,
  publisher text,
  author text,
  publication_year smallint,

  file_name text,
  source_reference text,

  ownership_status text NOT NULL DEFAULT 'unknown'
    CHECK (
      ownership_status IN (
        'owned',
        'licensed',
        'third_party',
        'ai_original',
        'unknown'
      )
    ),

  license_status text NOT NULL DEFAULT 'unknown'
    CHECK (
      license_status IN (
        'unknown',
        'pending',
        'approved',
        'restricted'
      )
    ),

  commercial_use_allowed boolean NOT NULL DEFAULT false,

  notes text,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.question_sources
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_question_sources_set_updated_at
ON public.question_sources;

CREATE TRIGGER trigger_question_sources_set_updated_at
BEFORE UPDATE ON public.question_sources
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. ANA SORU TABLOSU
-- =========================================================

CREATE TABLE IF NOT EXISTS public.questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Altın Kalemler kalıcı soru kodu.
  question_code text NOT NULL UNIQUE,

  -- Eski sistemden gelen benzersiz anahtar.
  -- Örn: TESTKODU-SORUNO
  legacy_question_key text UNIQUE,

  exam_track text
    CHECK (
      exam_track IS NULL
      OR exam_track IN ('TYT', 'AYT')
    ),

  grade_level smallint NOT NULL
    CHECK (grade_level BETWEEN 1 AND 12),

  subject_id uuid NOT NULL
    REFERENCES public.subjects(id)
    ON DELETE RESTRICT,

  -- Eski konu/alt konu sınıflandırması korunur.
  legacy_taxonomy_id uuid
    REFERENCES public.legacy_taxonomy(id)
    ON DELETE SET NULL,

  question_text text,

  option_a text,
  option_b text,
  option_c text,
  option_d text,
  option_e text,

  correct_answer text
    CHECK (
      correct_answer IS NULL
      OR correct_answer IN ('A', 'B', 'C', 'D', 'E')
    ),

  difficulty text
    CHECK (
      difficulty IS NULL
      OR difficulty IN ('easy', 'medium', 'hard')
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

  quality_level text
    CHECK (
      quality_level IS NULL
      OR quality_level IN (
        'low',
        'medium',
        'high'
      )
    ),

  primary_question_type text,
  secondary_question_type text,

  is_new_generation boolean NOT NULL DEFAULT false,
  has_visual boolean NOT NULL DEFAULT false,

  estimated_solve_time_seconds integer
    CHECK (
      estimated_solve_time_seconds IS NULL
      OR estimated_solve_time_seconds > 0
    ),

  approval_status text NOT NULL DEFAULT 'pending_review'
    CHECK (
      approval_status IN (
        'draft',
        'pending_review',
        'needs_review',
        'approved',
        'rejected'
      )
    ),

  is_active boolean NOT NULL DEFAULT false,

  ownership_status text NOT NULL DEFAULT 'unknown'
    CHECK (
      ownership_status IN (
        'owned',
        'licensed',
        'third_party',
        'ai_original',
        'unknown'
      )
    ),

  license_status text NOT NULL DEFAULT 'unknown'
    CHECK (
      license_status IN (
        'unknown',
        'pending',
        'approved',
        'restricted'
      )
    ),

  commercial_use_allowed boolean NOT NULL DEFAULT false,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    is_active = false
    OR approval_status = 'approved'
  )
);

CREATE INDEX IF NOT EXISTS idx_questions_grade_subject
ON public.questions(grade_level, subject_id);

CREATE INDEX IF NOT EXISTS idx_questions_legacy_taxonomy
ON public.questions(legacy_taxonomy_id);

CREATE INDEX IF NOT EXISTS idx_questions_approval_active
ON public.questions(approval_status, is_active);

CREATE INDEX IF NOT EXISTS idx_questions_difficulty
ON public.questions(difficulty);

ALTER TABLE public.questions
ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS questions_student_read
ON public.questions;

CREATE POLICY questions_student_read
ON public.questions
FOR SELECT
TO authenticated
USING (
  approval_status = 'approved'
  AND is_active = true
);

DROP TRIGGER IF EXISTS trigger_questions_set_updated_at
ON public.questions;

CREATE TRIGGER trigger_questions_set_updated_at
BEFORE UPDATE ON public.questions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. SORUNUN KAYNAKTAKİ KONUMU
-- Bir soru bir PDF/kitap/Excel kaynağında nerede?
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_source_locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  question_id uuid NOT NULL
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  source_id uuid NOT NULL
    REFERENCES public.question_sources(id)
    ON DELETE CASCADE,

  page_number integer
    CHECK (page_number IS NULL OR page_number > 0),

  test_number integer
    CHECK (test_number IS NULL OR test_number > 0),

  test_code text,

  question_number integer
    CHECK (question_number IS NULL OR question_number > 0),

  source_question_code text,

  crop_reference text,

  extraction_confidence numeric(5,4)
    CHECK (
      extraction_confidence IS NULL
      OR (
        extraction_confidence >= 0
        AND extraction_confidence <= 1
      )
    ),

  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    question_id,
    source_id
  )
);

CREATE INDEX IF NOT EXISTS idx_question_source_locations_source
ON public.question_source_locations(source_id);

CREATE INDEX IF NOT EXISTS idx_question_source_locations_lookup
ON public.question_source_locations(
  source_id,
  page_number,
  test_code,
  question_number
);

ALTER TABLE public.question_source_locations
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 4. ÇÖZÜM / MEDYA VARLIKLARI
-- Video, ses, PDF, görsel, eski SWF/XAML vb.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_solution_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  question_id uuid NOT NULL
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  asset_type text NOT NULL
    CHECK (
      asset_type IN (
        'video',
        'audio',
        'pdf',
        'image',
        'text_solution',
        'interactive_player',
        'legacy_swf',
        'legacy_xaml',
        'other'
      )
    ),

  asset_url text,
  asset_text text,

  source_type text NOT NULL DEFAULT 'legacy'
    CHECK (
      source_type IN (
        'legacy',
        'manual',
        'ai_generated',
        'uploaded'
      )
    ),

  validation_status text NOT NULL DEFAULT 'pending'
    CHECK (
      validation_status IN (
        'pending',
        'valid',
        'invalid',
        'duplicate_suspected',
        'needs_review'
      )
    ),

  is_active boolean NOT NULL DEFAULT false,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_question_solution_assets_question
ON public.question_solution_assets(question_id);

CREATE INDEX IF NOT EXISTS idx_question_solution_assets_status
ON public.question_solution_assets(validation_status);

ALTER TABLE public.question_solution_assets
ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS question_solution_assets_student_read
ON public.question_solution_assets;

CREATE POLICY question_solution_assets_student_read
ON public.question_solution_assets
FOR SELECT
TO authenticated
USING (
  is_active = true
  AND validation_status = 'valid'
  AND EXISTS (
    SELECT 1
    FROM public.questions q
    WHERE q.id = question_solution_assets.question_id
      AND q.approval_status = 'approved'
      AND q.is_active = true
  )
);

DROP TRIGGER IF EXISTS trigger_question_solution_assets_set_updated_at
ON public.question_solution_assets;

CREATE TRIGGER trigger_question_solution_assets_set_updated_at
BEFORE UPDATE ON public.question_solution_assets
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 4B. SORU İÇERİK VARLIKLARI
-- Sorunun kendi görseli, grafik, şekil veya PDF kırpımı.
-- Çözüm medyasından ayrıdır.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  question_id uuid NOT NULL
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  asset_type text NOT NULL
    CHECK (
      asset_type IN (
        'question_image',
        'diagram',
        'graph',
        'table',
        'geometry_figure',
        'formula_image',
        'pdf_crop',
        'other'
      )
    ),

  asset_url text,
  storage_path text,

  alt_text text,

  sort_order integer NOT NULL DEFAULT 0,

  validation_status text NOT NULL DEFAULT 'pending'
    CHECK (
      validation_status IN (
        'pending',
        'valid',
        'invalid',
        'needs_review'
      )
    ),

  is_active boolean NOT NULL DEFAULT false,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    asset_url IS NOT NULL
    OR storage_path IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS idx_question_assets_question
ON public.question_assets(question_id);

ALTER TABLE public.question_assets
ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS question_assets_student_read
ON public.question_assets;

CREATE POLICY question_assets_student_read
ON public.question_assets
FOR SELECT
TO authenticated
USING (
  is_active = true
  AND validation_status = 'valid'
  AND EXISTS (
    SELECT 1
    FROM public.questions q
    WHERE q.id = question_assets.question_id
      AND q.approval_status = 'approved'
      AND q.is_active = true
  )
);

DROP TRIGGER IF EXISTS trigger_question_assets_set_updated_at
ON public.question_assets;

CREATE TRIGGER trigger_question_assets_set_updated_at
BEFORE UPDATE ON public.question_assets
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 5. SORU -> GÜNCEL MÜFREDAT EŞLEŞMESİ
-- Aynı soru farklı yıllardaki müfredatlara bağlanabilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_curriculum_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  question_id uuid NOT NULL
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  curriculum_version_id uuid NOT NULL
    REFERENCES public.curriculum_versions(id)
    ON DELETE CASCADE,

  topic_id uuid NOT NULL
    REFERENCES public.topics(id)
    ON DELETE RESTRICT,

  subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE RESTRICT,

  mapping_source text NOT NULL DEFAULT 'manual'
    CHECK (
      mapping_source IN (
        'manual',
        'rule_based',
        'ai'
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

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_question_curriculum_mapping_unique
ON public.question_curriculum_mappings(
  question_id,
  curriculum_version_id,
  topic_id,
  subtopic_id
)
NULLS NOT DISTINCT;

CREATE INDEX IF NOT EXISTS idx_question_curriculum_mapping_question
ON public.question_curriculum_mappings(question_id);

CREATE INDEX IF NOT EXISTS idx_question_curriculum_mapping_version
ON public.question_curriculum_mappings(curriculum_version_id);

CREATE INDEX IF NOT EXISTS idx_question_curriculum_mapping_topic
ON public.question_curriculum_mappings(topic_id);

ALTER TABLE public.question_curriculum_mappings
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_question_curriculum_mappings_set_updated_at
ON public.question_curriculum_mappings;

CREATE TRIGGER trigger_question_curriculum_mappings_set_updated_at
BEFORE UPDATE ON public.question_curriculum_mappings
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 6. IMPORT PARTİLERİ
-- PDF, Excel veya ileride AI tarafından yapılan yüklemeler.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.import_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  batch_type text NOT NULL
    CHECK (
      batch_type IN (
        'pdf',
        'excel',
        'manual',
        'ai',
        'mixed'
      )
    ),

  source_id uuid
    REFERENCES public.question_sources(id)
    ON DELETE SET NULL,

  status text NOT NULL DEFAULT 'pending'
    CHECK (
      status IN (
        'pending',
        'processing',
        'completed',
        'completed_with_errors',
        'failed',
        'cancelled'
      )
    ),

  total_items integer NOT NULL DEFAULT 0
    CHECK (total_items >= 0),

  processed_items integer NOT NULL DEFAULT 0
    CHECK (processed_items >= 0),

  success_items integer NOT NULL DEFAULT 0
    CHECK (success_items >= 0),

  error_items integer NOT NULL DEFAULT 0
    CHECK (error_items >= 0),

  started_at timestamptz,
  completed_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.import_batches
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_import_batches_set_updated_at
ON public.import_batches;

CREATE TRIGGER trigger_import_batches_set_updated_at
BEFORE UPDATE ON public.import_batches
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 7. IMPORT HATALARI / İNCELEME KAYITLARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.import_errors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  import_batch_id uuid NOT NULL
    REFERENCES public.import_batches(id)
    ON DELETE CASCADE,

  source_row_number integer,
  source_page_number integer,

  legacy_question_key text,

  error_code text NOT NULL,
  error_message text NOT NULL,

  raw_data jsonb,

  resolution_status text NOT NULL DEFAULT 'open'
    CHECK (
      resolution_status IN (
        'open',
        'resolved',
        'ignored',
        'needs_review'
      )
    ),

  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_import_errors_batch
ON public.import_errors(import_batch_id);

CREATE INDEX IF NOT EXISTS idx_import_errors_status
ON public.import_errors(resolution_status);

ALTER TABLE public.import_errors
ENABLE ROW LEVEL SECURITY;