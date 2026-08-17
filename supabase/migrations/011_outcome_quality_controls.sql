-- 011_outcome_quality_controls.sql
-- Altın Kalemler kazanım uygunluğu ve üretim kalite kontrolleri.

-- =========================================================
-- 1. STAGING SORUYA KAZANIM UYGUNLUK SKORLARI
-- =========================================================

ALTER TABLE public.ai_question_staging
ADD COLUMN IF NOT EXISTS outcome_fit_score numeric(5,4)
CHECK (
  outcome_fit_score IS NULL
  OR (
    outcome_fit_score >= 0
    AND outcome_fit_score <= 1
  )
);

ALTER TABLE public.ai_question_staging
ADD COLUMN IF NOT EXISTS outcome_drift_detected boolean
NOT NULL DEFAULT false;

ALTER TABLE public.ai_question_staging
ADD COLUMN IF NOT EXISTS grade_drift_detected boolean
NOT NULL DEFAULT false;

ALTER TABLE public.ai_question_staging
ADD COLUMN IF NOT EXISTS topic_drift_detected boolean
NOT NULL DEFAULT false;


-- =========================================================
-- 2. DOĞRULAMA TÜRLERİNE YENİ KONTROLLER EKLE
-- Mevcut CHECK constraint'i genişletiyoruz.
-- =========================================================

DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT conname
  INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'public.ai_validation_results'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%validation_type%';

  IF constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE public.ai_validation_results DROP CONSTRAINT %I',
      constraint_name
    );
  END IF;
END $$;

ALTER TABLE public.ai_validation_results
ADD CONSTRAINT ai_validation_results_validation_type_check
CHECK (
  validation_type IN (
    'structure',
    'answer',
    'single_correct_answer',
    'curriculum',
    'classification',
    'grade_appropriateness',
    'topic_coherence',
    'prerequisite_check',
    'outcome_appropriateness',
    'outcome_drift',
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
    'diversity',
    'overall'
  )
);


-- =========================================================
-- 3. KAZANIM UYGUNLUK EŞİĞİ
-- =========================================================

INSERT INTO public.ai_quality_thresholds (
  threshold_code,
  name,
  scope_type,
  min_score,
  max_score,
  is_blocking,
  notes
)
VALUES
(
  'outcome_fit',
  'Minimum kazanım uygunluğu',
  'global',
  0.9000,
  NULL,
  true,
  'Hedef kazanımı yeterince ölçmeyen soru otomatik onaylanmaz.'
),
(
  'question_diversity',
  'Minimum soru çeşitliliği',
  'global',
  0.8000,
  NULL,
  false,
  'Aynı kazanım için sürekli aynı kalıpta soru üretilmesini engellemeye yardımcı olur.'
)
ON CONFLICT (threshold_code) DO UPDATE
SET
  name = EXCLUDED.name,
  scope_type = EXCLUDED.scope_type,
  min_score = EXCLUDED.min_score,
  max_score = EXCLUDED.max_score,
  is_blocking = EXCLUDED.is_blocking,
  notes = EXCLUDED.notes,
  is_active = true;


-- =========================================================
-- 4. KAZANIM DENETÇİSİ AI AJANI
-- =========================================================

INSERT INTO public.ai_agents (
  agent_code,
  name,
  description,
  agent_category,
  risk_level,
  can_generate_content,
  can_validate_content,
  can_recommend_approval
)
VALUES
(
  'outcome_reviewer',
  'Kazanım Uygunluğu Denetçisi AI',
  'Sorunun hedef kazanımı gerçekten ölçüp ölçmediğini ve başka kazanıma kayıp kaymadığını denetler.',
  'review',
  'critical',
  false,
  true,
  true
),
(
  'diversity_reviewer',
  'Soru Çeşitlilik Denetçisi AI',
  'Aynı kazanım için üretilen soruların kalıp, bağlam, çözüm yolu ve soru tipi çeşitliliğini denetler.',
  'review',
  'high',
  false,
  true,
  true
)
ON CONFLICT (agent_code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  agent_category = EXCLUDED.agent_category,
  risk_level = EXCLUDED.risk_level,
  can_generate_content = EXCLUDED.can_generate_content,
  can_validate_content = EXCLUDED.can_validate_content,
  can_recommend_approval = EXCLUDED.can_recommend_approval,
  is_active = true;


-- =========================================================
-- 5. AI QUESTION GENERATION WORKFLOW'A
-- KAZANIM VE ÇEŞİTLİLİK KONTROLLERİ EKLE
-- =========================================================

DO $$
DECLARE
  wf_id uuid;
  outcome_agent_id uuid;
  diversity_agent_id uuid;
BEGIN
  SELECT id
  INTO wf_id
  FROM public.ai_workflows
  WHERE workflow_code = 'ai_question_generation';

  SELECT id
  INTO outcome_agent_id
  FROM public.ai_agents
  WHERE agent_code = 'outcome_reviewer';

  SELECT id
  INTO diversity_agent_id
  FROM public.ai_agents
  WHERE agent_code = 'diversity_reviewer';

  IF wf_id IS NOT NULL THEN

    -- Mevcut 5 ve sonrası adımları iki sıra ileri kaydır.
    UPDATE public.ai_workflow_steps
    SET step_order = step_order + 100
    WHERE workflow_id = wf_id
      AND step_order >= 5;

    INSERT INTO public.ai_workflow_steps (
      workflow_id,
      step_order,
      step_code,
      agent_id,
      step_type,
      is_required,
      failure_action,
      configuration
    )
    VALUES
    (
      wf_id,
      5,
      'outcome_appropriateness',
      outcome_agent_id,
      'ai',
      true,
      'review',
      '{"purpose":"Sorunun hedef kazanımı gerçekten ölçüp ölçmediğini kontrol et"}'::jsonb
    ),
    (
      wf_id,
      6,
      'question_diversity',
      diversity_agent_id,
      'ai',
      true,
      'review',
      '{"purpose":"Aynı kazanım için soru kalıbı ve çözüm yolu çeşitliliğini kontrol et"}'::jsonb
    )
    ON CONFLICT (workflow_id, step_code) DO NOTHING;

    UPDATE public.ai_workflow_steps
    SET step_order = step_order - 98
    WHERE workflow_id = wf_id
      AND step_order >= 105;

  END IF;
END $$;