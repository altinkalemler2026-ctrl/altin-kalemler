-- 005_ai_core.sql
-- Altın Kalemler AI çekirdek yönetim altyapısı.

-- 1. AI AJANLARI

CREATE TABLE IF NOT EXISTS public.ai_agents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  agent_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  agent_category text NOT NULL
    CHECK (
      agent_category IN (
        'orchestration',
        'extraction',
        'matching',
        'classification',
        'validation',
        'generation',
        'review',
        'copyright',
        'analytics',
        'publishing',
        'security'
      )
    ),

  risk_level text NOT NULL DEFAULT 'medium'
    CHECK (
      risk_level IN ('low', 'medium', 'high', 'critical')
    ),

  can_generate_content boolean NOT NULL DEFAULT false,
  can_validate_content boolean NOT NULL DEFAULT false,
  can_recommend_approval boolean NOT NULL DEFAULT false,

  -- AI doğrudan ana soru bankasına aktaramaz.
  can_promote_to_question_bank boolean NOT NULL DEFAULT false,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (can_promote_to_question_bank = false)
);

ALTER TABLE public.ai_agents
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_ai_agents_set_updated_at
ON public.ai_agents;

CREATE TRIGGER trigger_ai_agents_set_updated_at
BEFORE UPDATE ON public.ai_agents
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- 2. AI AJAN SÜRÜMLERİ

CREATE TABLE IF NOT EXISTS public.ai_agent_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  agent_id uuid NOT NULL
    REFERENCES public.ai_agents(id)
    ON DELETE CASCADE,

  version text NOT NULL,

  provider_name text,
  model_name text,

  system_instructions text,
  prompt_template text,

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (agent_id, version)
);

CREATE INDEX IF NOT EXISTS idx_ai_agent_versions_agent
ON public.ai_agent_versions(agent_id);

ALTER TABLE public.ai_agent_versions
ENABLE ROW LEVEL SECURITY;


-- 3. AI WORKFLOW'LARI

CREATE TABLE IF NOT EXISTS public.ai_workflows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  workflow_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  workflow_type text NOT NULL
    CHECK (
      workflow_type IN (
        'pdf_import',
        'excel_import',
        'source_matching',
        'question_generation',
        'question_revalidation',
        'commercial_review',
        'gap_analysis',
        'solution_generation'
      )
    ),

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ai_workflows
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_ai_workflows_set_updated_at
ON public.ai_workflows;

CREATE TRIGGER trigger_ai_workflows_set_updated_at
BEFORE UPDATE ON public.ai_workflows
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- 4. WORKFLOW ADIMLARI

CREATE TABLE IF NOT EXISTS public.ai_workflow_steps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  workflow_id uuid NOT NULL
    REFERENCES public.ai_workflows(id)
    ON DELETE CASCADE,

  step_order integer NOT NULL
    CHECK (step_order > 0),

  step_code text NOT NULL,

  agent_id uuid
    REFERENCES public.ai_agents(id)
    ON DELETE SET NULL,

  step_type text NOT NULL
    CHECK (
      step_type IN (
        'ai',
        'deterministic',
        'human_review',
        'condition',
        'promotion'
      )
    ),

  is_required boolean NOT NULL DEFAULT true,

  failure_action text NOT NULL DEFAULT 'review'
    CHECK (
      failure_action IN (
        'stop',
        'retry',
        'review',
        'reject',
        'continue'
      )
    ),

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (workflow_id, step_order),
  UNIQUE (workflow_id, step_code)
);

CREATE INDEX IF NOT EXISTS idx_ai_workflow_steps_workflow
ON public.ai_workflow_steps(workflow_id);

ALTER TABLE public.ai_workflow_steps
ENABLE ROW LEVEL SECURITY;