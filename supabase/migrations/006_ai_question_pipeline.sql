-- 006_ai_question_pipeline.sql
-- Altın Kalemler AI soru üretim ve doğrulama hattı.

-- =========================================================
-- 1. SORU ÜRETİM ŞARTNAMELERİ
-- Hangi sınıf, ders, konu, alt konu ve seviyede kaç soru üretilecek?
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_generation_specs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  curriculum_version_id uuid
    REFERENCES public.curriculum_versions(id)
    ON DELETE SET NULL,

  grade_level smallint NOT NULL
    CHECK (grade_level BETWEEN 1 AND 12),

  subject_id uuid NOT NULL
    REFERENCES public.subjects(id)
    ON DELETE RESTRICT,

  topic_id uuid
    REFERENCES public.topics(id)
    ON DELETE SET NULL,

  subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE SET NULL,

  desired_count integer NOT NULL
    CHECK (desired_count > 0),

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

  primary_question_type text,
  secondary_question_type text,

  is_new_generation boolean,

  min_solve_time_seconds integer
    CHECK (
      min_solve_time_seconds IS NULL
      OR min_solve_time_seconds > 0
    ),

  max_solve_time_seconds integer
    CHECK (
      max_solve_time_seconds IS NULL
      OR max_solve_time_seconds > 0
    ),

  originality_min_score numeric(5,4)
    CHECK (
      originality_min_score IS NULL
      OR (
        originality_min_score >= 0
        AND originality_min_score <= 1
      )
    ),

  similarity_max_score numeric(5,4)
    CHECK (
      similarity_max_score IS NULL
      OR (
        similarity_max_score >= 0
        AND similarity_max_score <= 1
      )
    ),

  generation_instructions text,

  constraints jsonb NOT NULL DEFAULT '{}'::jsonb,

  status text NOT NULL DEFAULT 'draft'
    CHECK (
      status IN (
        'draft',
        'ready',
        'processing',
        'completed',
        'cancelled'
      )
    ),

  created_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    min_solve_time_seconds IS NULL
    OR max_solve_time_seconds IS NULL
    OR min_solve_time_seconds <= max_solve_time_seconds
  )
);

CREATE INDEX IF NOT EXISTS idx_ai_generation_specs_target
ON public.ai_generation_specs(
  grade_level,
  subject_id,
  topic_id,
  subtopic_id
);

CREATE INDEX IF NOT EXISTS idx_ai_generation_specs_status
ON public.ai_generation_specs(status);

ALTER TABLE public.ai_generation_specs
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_ai_generation_specs_set_updated_at
ON public.ai_generation_specs;

CREATE TRIGGER trigger_ai_generation_specs_set_updated_at
BEFORE UPDATE ON public.ai_generation_specs
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. AI İŞLERİ
-- PDF analiz, sınıflandırma, üretim, kontrol vb.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  workflow_id uuid
    REFERENCES public.ai_workflows(id)
    ON DELETE SET NULL,

  job_type text NOT NULL
    CHECK (
      job_type IN (
        'pdf_extraction',
        'page_classification',
        'question_segmentation',
        'asset_extraction',
        'formula_reconstruction',
        'excel_matching',
        'source_matching',
        'answer_key_extraction',
        'answer_validation',
        'classification',
        'curriculum_mapping',
        'grade_appropriateness',
        'topic_coherence',
        'prerequisite_check',
        'difficulty_analysis',
        'cognitive_analysis',
        'question_type_analysis',
        'language_review',
        'scientific_review',
        'similarity_check',
        'originality_check',
        'question_generation',
        'question_review',
        'solution_generation',
        'solution_review',
        'gap_analysis',
        'pool_balancing'
      )
    ),

  status text NOT NULL DEFAULT 'pending'
    CHECK (
      status IN (
        'pending',
        'queued',
        'processing',
        'completed',
        'completed_with_warnings',
        'failed',
        'cancelled'
      )
    ),

  source_id uuid
    REFERENCES public.question_sources(id)
    ON DELETE SET NULL,

  import_batch_id uuid
    REFERENCES public.import_batches(id)
    ON DELETE SET NULL,

  generation_spec_id uuid
    REFERENCES public.ai_generation_specs(id)
    ON DELETE SET NULL,

  parent_job_id uuid
    REFERENCES public.ai_jobs(id)
    ON DELETE SET NULL,

  input_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  output_data jsonb,

  attempt_count integer NOT NULL DEFAULT 0
    CHECK (attempt_count >= 0),

  max_attempts integer NOT NULL DEFAULT 3
    CHECK (max_attempts > 0),

  estimated_cost numeric(12,6)
    CHECK (
      estimated_cost IS NULL
      OR estimated_cost >= 0
    ),

  actual_cost numeric(12,6)
    CHECK (
      actual_cost IS NULL
      OR actual_cost >= 0
    ),

  error_code text,
  error_message text,

  started_at timestamptz,
  completed_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_jobs_status
ON public.ai_jobs(status);

CREATE INDEX IF NOT EXISTS idx_ai_jobs_type_status
ON public.ai_jobs(job_type, status);

CREATE INDEX IF NOT EXISTS idx_ai_jobs_source
ON public.ai_jobs(source_id);

CREATE INDEX IF NOT EXISTS idx_ai_jobs_generation_spec
ON public.ai_jobs(generation_spec_id);

ALTER TABLE public.ai_jobs
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_ai_jobs_set_updated_at
ON public.ai_jobs;

CREATE TRIGGER trigger_ai_jobs_set_updated_at
BEFORE UPDATE ON public.ai_jobs
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. AJAN ÇALIŞMA KAYITLARI
-- Hangi ajan hangi modelle ne yaptı?
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_agent_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  ai_job_id uuid NOT NULL
    REFERENCES public.ai_jobs(id)
    ON DELETE CASCADE,

  agent_id uuid
    REFERENCES public.ai_agents(id)
    ON DELETE SET NULL,

  agent_version_id uuid
    REFERENCES public.ai_agent_versions(id)
    ON DELETE SET NULL,

  execution_role text NOT NULL
    CHECK (
      execution_role IN (
        'producer',
        'validator',
        'reviewer',
        'orchestrator',
        'analyzer'
      )
    ),

  status text NOT NULL DEFAULT 'processing'
    CHECK (
      status IN (
        'processing',
        'completed',
        'warning',
        'failed',
        'cancelled'
      )
    ),

  provider_name text,
  model_name text,
  prompt_version text,

  input_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  output_snapshot jsonb,

  confidence_score numeric(5,4)
    CHECK (
      confidence_score IS NULL
      OR (
        confidence_score >= 0
        AND confidence_score <= 1
      )
    ),

  input_tokens integer
    CHECK (
      input_tokens IS NULL
      OR input_tokens >= 0
    ),

  output_tokens integer
    CHECK (
      output_tokens IS NULL
      OR output_tokens >= 0
    ),

  cost_amount numeric(12,6)
    CHECK (
      cost_amount IS NULL
      OR cost_amount >= 0
    ),

  error_message text,

  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_ai_agent_executions_job
ON public.ai_agent_executions(ai_job_id);

CREATE INDEX IF NOT EXISTS idx_ai_agent_executions_agent
ON public.ai_agent_executions(agent_id);

ALTER TABLE public.ai_agent_executions
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 4. AI SORU STAGING
-- PDF'den çıkarılan veya AI tarafından üretilen aday sorular.
-- Öğrenciler bu tabloyu göremez.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_question_staging (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  staging_source text NOT NULL
    CHECK (
      staging_source IN (
        'pdf_extracted',
        'excel_import',
        'pdf_excel_matched',
        'ai_generated',
        'manual_candidate'
      )
    ),

  ai_job_id uuid
    REFERENCES public.ai_jobs(id)
    ON DELETE SET NULL,

  generation_spec_id uuid
    REFERENCES public.ai_generation_specs(id)
    ON DELETE SET NULL,

  import_batch_id uuid
    REFERENCES public.import_batches(id)
    ON DELETE SET NULL,

  source_id uuid
    REFERENCES public.question_sources(id)
    ON DELETE SET NULL,

  legacy_question_key text,
  proposed_question_code text,

  exam_track text
    CHECK (
      exam_track IS NULL
      OR exam_track IN ('TYT', 'AYT')
    ),

  grade_level smallint
    CHECK (
      grade_level IS NULL
      OR grade_level BETWEEN 1 AND 12
    ),

  subject_id uuid
    REFERENCES public.subjects(id)
    ON DELETE SET NULL,

  legacy_taxonomy_id uuid
    REFERENCES public.legacy_taxonomy(id)
    ON DELETE SET NULL,

  proposed_curriculum_version_id uuid
    REFERENCES public.curriculum_versions(id)
    ON DELETE SET NULL,

  proposed_topic_id uuid
    REFERENCES public.topics(id)
    ON DELETE SET NULL,

  proposed_subtopic_id uuid
    REFERENCES public.subtopics(id)
    ON DELETE SET NULL,

  source_page_number integer
    CHECK (
      source_page_number IS NULL
      OR source_page_number > 0
    ),

  source_test_number integer
    CHECK (
      source_test_number IS NULL
      OR source_test_number > 0
    ),

  source_test_code text,

  source_question_number integer
    CHECK (
      source_question_number IS NULL
      OR source_question_number > 0
    ),

  question_text text,

  option_a text,
  option_b text,
  option_c text,
  option_d text,
  option_e text,

  proposed_correct_answer text
    CHECK (
      proposed_correct_answer IS NULL
      OR proposed_correct_answer IN ('A', 'B', 'C', 'D', 'E')
    ),

  proposed_difficulty text
    CHECK (
      proposed_difficulty IS NULL
      OR proposed_difficulty IN ('easy', 'medium', 'hard')
    ),

  proposed_cognitive_type text
    CHECK (
      proposed_cognitive_type IS NULL
      OR proposed_cognitive_type IN (
        'learning',
        'comprehension',
        'application'
      )
    ),

  proposed_quality_level text
    CHECK (
      proposed_quality_level IS NULL
      OR proposed_quality_level IN (
        'low',
        'medium',
        'high'
      )
    ),

  proposed_primary_question_type text,
  proposed_secondary_question_type text,

  proposed_is_new_generation boolean,
  proposed_has_visual boolean,

  proposed_solve_time_seconds integer
    CHECK (
      proposed_solve_time_seconds IS NULL
      OR proposed_solve_time_seconds > 0
    ),

  extraction_confidence numeric(5,4)
    CHECK (
      extraction_confidence IS NULL
      OR (
        extraction_confidence >= 0
        AND extraction_confidence <= 1
      )
    ),

  classification_confidence numeric(5,4)
    CHECK (
      classification_confidence IS NULL
      OR (
        classification_confidence >= 0
        AND classification_confidence <= 1
      )
    ),

  answer_confidence numeric(5,4)
    CHECK (
      answer_confidence IS NULL
      OR (
        answer_confidence >= 0
        AND answer_confidence <= 1
      )
    ),

  grade_fit_score numeric(5,4)
    CHECK (
      grade_fit_score IS NULL
      OR (
        grade_fit_score >= 0
        AND grade_fit_score <= 1
      )
    ),

  topic_fit_score numeric(5,4)
    CHECK (
      topic_fit_score IS NULL
      OR (
        topic_fit_score >= 0
        AND topic_fit_score <= 1
      )
    ),

  subtopic_fit_score numeric(5,4)
    CHECK (
      subtopic_fit_score IS NULL
      OR (
        subtopic_fit_score >= 0
        AND subtopic_fit_score <= 1
      )
    ),

  prerequisite_violation boolean NOT NULL DEFAULT false,

  originality_score numeric(5,4)
    CHECK (
      originality_score IS NULL
      OR (
        originality_score >= 0
        AND originality_score <= 1
      )
    ),

  staging_status text NOT NULL DEFAULT 'draft'
    CHECK (
      staging_status IN (
        'draft',
        'extracted',
        'validating',
        'needs_review',
        'approved',
        'rejected',
        'promoted'
      )
    ),

  final_question_id uuid
    REFERENCES public.questions(id)
    ON DELETE SET NULL,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    staging_status <> 'promoted'
    OR final_question_id IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS idx_ai_question_staging_status
ON public.ai_question_staging(staging_status);

CREATE INDEX IF NOT EXISTS idx_ai_question_staging_job
ON public.ai_question_staging(ai_job_id);

CREATE INDEX IF NOT EXISTS idx_ai_question_staging_source
ON public.ai_question_staging(source_id);

CREATE INDEX IF NOT EXISTS idx_ai_question_staging_target
ON public.ai_question_staging(
  grade_level,
  subject_id,
  proposed_topic_id,
  proposed_subtopic_id
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_question_staging_legacy_key
ON public.ai_question_staging(legacy_question_key)
WHERE legacy_question_key IS NOT NULL
AND staging_status <> 'rejected';

ALTER TABLE public.ai_question_staging
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_ai_question_staging_set_updated_at
ON public.ai_question_staging;

CREATE TRIGGER trigger_ai_question_staging_set_updated_at
BEFORE UPDATE ON public.ai_question_staging
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 5. DOĞRULAMA SONUÇLARI
-- Kod + AI + insan kontrolleri.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_validation_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  staging_question_id uuid NOT NULL
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  ai_job_id uuid
    REFERENCES public.ai_jobs(id)
    ON DELETE SET NULL,

  validator_type text NOT NULL
    CHECK (
      validator_type IN (
        'deterministic',
        'ai',
        'human'
      )
    ),

  validation_type text NOT NULL
    CHECK (
      validation_type IN (
        'structure',
        'answer',
        'single_correct_answer',
        'curriculum',
        'classification',

        -- Özellikle istediğin kontroller:
        'grade_appropriateness',
        'topic_coherence',
        'prerequisite_check',

        'difficulty',
        'cognitive_level',
        'question_type',
        'language',
        'scientific_accuracy',
        'source_match',
        'similarity',
        'originality',
        'visual',
        'solution',
        'overall'
      )
    ),

  result text NOT NULL
    CHECK (
      result IN (
        'pass',
        'warning',
        'fail'
      )
    ),

  score numeric(5,4)
    CHECK (
      score IS NULL
      OR (
        score >= 0
        AND score <= 1
      )
    ),

  provider_name text,
  model_name text,
  prompt_version text,

  summary text,

  details jsonb NOT NULL DEFAULT '{}'::jsonb,

  reviewed_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_validation_results_staging
ON public.ai_validation_results(staging_question_id);

CREATE INDEX IF NOT EXISTS idx_ai_validation_results_type
ON public.ai_validation_results(validation_type, result);

ALTER TABLE public.ai_validation_results
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 6. BENZERLİK / DUPLICATE KONTROLÜ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_similarity_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  candidate_staging_id uuid NOT NULL
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  matched_question_id uuid
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  matched_staging_id uuid
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  similarity_type text NOT NULL
    CHECK (
      similarity_type IN (
        'exact',
        'text',
        'semantic',
        'structure',
        'concept',
        'solution_path'
      )
    ),

  similarity_score numeric(5,4) NOT NULL
    CHECK (
      similarity_score >= 0
      AND similarity_score <= 1
    ),

  review_status text NOT NULL DEFAULT 'pending'
    CHECK (
      review_status IN (
        'pending',
        'acceptable',
        'duplicate',
        'needs_review'
      )
    ),

  details jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    (
      matched_question_id IS NOT NULL
      AND matched_staging_id IS NULL
    )
    OR
    (
      matched_question_id IS NULL
      AND matched_staging_id IS NOT NULL
    )
  ),

  CHECK (
    matched_staging_id IS NULL
    OR matched_staging_id <> candidate_staging_id
  )
);

CREATE INDEX IF NOT EXISTS idx_similarity_candidate
ON public.question_similarity_matches(candidate_staging_id);

CREATE INDEX IF NOT EXISTS idx_similarity_existing_question
ON public.question_similarity_matches(matched_question_id);

CREATE INDEX IF NOT EXISTS idx_similarity_other_staging
ON public.question_similarity_matches(matched_staging_id);

CREATE INDEX IF NOT EXISTS idx_similarity_score
ON public.question_similarity_matches(similarity_score DESC);

ALTER TABLE public.question_similarity_matches
ENABLE ROW LEVEL SECURITY;