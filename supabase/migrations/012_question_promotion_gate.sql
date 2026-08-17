-- 012_question_promotion_gate.sql
-- Altın Kalemler admin onay ve soru yayınlama güvenlik kapısı.

-- =========================================================
-- 1. İNCELEME KARARLARI
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_review_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  staging_question_id uuid NOT NULL
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  decision text NOT NULL
    CHECK (
      decision IN (
        'approve',
        'reject',
        'request_changes'
      )
    ),

  decision_source text NOT NULL
    CHECK (
      decision_source IN (
        'human',
        'ai_recommendation'
      )
    ),

  reviewer_user_id uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  reviewer_agent_id uuid
    REFERENCES public.ai_agents(id)
    ON DELETE SET NULL,

  reason_code text,
  notes text,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    (decision_source = 'human' AND reviewer_user_id IS NOT NULL)
    OR
    (decision_source = 'ai_recommendation' AND reviewer_agent_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_question_review_decisions_staging
ON public.question_review_decisions(staging_question_id);

CREATE INDEX IF NOT EXISTS idx_question_review_decisions_decision
ON public.question_review_decisions(decision);

ALTER TABLE public.question_review_decisions
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 2. PROMOTION İSTEKLERİ
-- staging -> questions geçiş talebi
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_promotion_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  staging_question_id uuid NOT NULL UNIQUE
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  status text NOT NULL DEFAULT 'pending'
    CHECK (
      status IN (
        'pending',
        'checking',
        'approved',
        'rejected',
        'blocked',
        'completed'
      )
    ),

  deterministic_checks_passed boolean NOT NULL DEFAULT false,
  answer_checks_passed boolean NOT NULL DEFAULT false,
  grade_checks_passed boolean NOT NULL DEFAULT false,
  topic_checks_passed boolean NOT NULL DEFAULT false,
  outcome_checks_passed boolean NOT NULL DEFAULT false,
  prerequisite_checks_passed boolean NOT NULL DEFAULT false,
  quality_checks_passed boolean NOT NULL DEFAULT false,
  similarity_checks_passed boolean NOT NULL DEFAULT false,
  originality_checks_passed boolean NOT NULL DEFAULT false,

  human_approval_required boolean NOT NULL DEFAULT true,
  human_approval_received boolean NOT NULL DEFAULT false,

  blocking_reason text,

  approved_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  approved_at timestamptz,

  promoted_question_id uuid
    REFERENCES public.questions(id)
    ON DELETE SET NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    status <> 'completed'
    OR promoted_question_id IS NOT NULL
  ),

  CHECK (
    human_approval_received = false
    OR approved_by IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS idx_question_promotion_requests_status
ON public.question_promotion_requests(status);

ALTER TABLE public.question_promotion_requests
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_question_promotion_requests_set_updated_at
ON public.question_promotion_requests;

CREATE TRIGGER trigger_question_promotion_requests_set_updated_at
BEFORE UPDATE ON public.question_promotion_requests
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. PROMOTION GÜVENLİK FONKSİYONU
-- Tüm kapılar geçmeden status='approved' yapılamaz.
-- =========================================================

CREATE OR REPLACE FUNCTION public.validate_question_promotion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  human_approval_exists boolean;
  failing_validation_exists boolean;
  dangerous_copyright_exists boolean;
  staging_record public.ai_question_staging%ROWTYPE;
BEGIN

  IF NEW.status NOT IN ('approved', 'completed') THEN
    RETURN NEW;
  END IF;

  SELECT *
  INTO staging_record
  FROM public.ai_question_staging
  WHERE id = NEW.staging_question_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Staging question not found.';
  END IF;


  -- -------------------------------------------------------
  -- Zorunlu kapılar
  -- -------------------------------------------------------

  IF NEW.deterministic_checks_passed IS NOT TRUE
     OR NEW.answer_checks_passed IS NOT TRUE
     OR NEW.grade_checks_passed IS NOT TRUE
     OR NEW.topic_checks_passed IS NOT TRUE
     OR NEW.outcome_checks_passed IS NOT TRUE
     OR NEW.prerequisite_checks_passed IS NOT TRUE
     OR NEW.quality_checks_passed IS NOT TRUE
     OR NEW.similarity_checks_passed IS NOT TRUE
     OR NEW.originality_checks_passed IS NOT TRUE
  THEN
    RAISE EXCEPTION
      'Question cannot be promoted: required validation gates have not passed.';
  END IF;


  -- -------------------------------------------------------
  -- Sınıf / konu / kazanım sapması
  -- -------------------------------------------------------

  IF staging_record.prerequisite_violation IS TRUE
     OR staging_record.grade_drift_detected IS TRUE
     OR staging_record.topic_drift_detected IS TRUE
     OR staging_record.outcome_drift_detected IS TRUE
  THEN
    RAISE EXCEPTION
      'Question cannot be promoted: grade, topic, outcome or prerequisite violation detected.';
  END IF;


  -- -------------------------------------------------------
  -- FAIL doğrulama sonucu var mı?
  -- -------------------------------------------------------

  SELECT EXISTS (
    SELECT 1
    FROM public.ai_validation_results
    WHERE staging_question_id = NEW.staging_question_id
      AND result = 'fail'
  )
  INTO failing_validation_exists;

  IF failing_validation_exists THEN
    RAISE EXCEPTION
      'Question cannot be promoted: failing validation result exists.';
  END IF;


  -- -------------------------------------------------------
  -- Yüksek / bloklanmış telif riski var mı?
  -- -------------------------------------------------------

  SELECT EXISTS (
    SELECT 1
    FROM public.copyright_reviews
    WHERE staging_question_id = NEW.staging_question_id
      AND risk_level IN ('high', 'blocked')
  )
  INTO dangerous_copyright_exists;

  IF dangerous_copyright_exists THEN
    RAISE EXCEPTION
      'Question cannot be promoted: high or blocked copyright risk exists.';
  END IF;


  -- -------------------------------------------------------
  -- İnsan onayı zorunlu
  -- -------------------------------------------------------

  SELECT EXISTS (
    SELECT 1
    FROM public.question_review_decisions
    WHERE staging_question_id = NEW.staging_question_id
      AND decision = 'approve'
      AND decision_source = 'human'
      AND reviewer_user_id IS NOT NULL
  )
  INTO human_approval_exists;

  IF NEW.human_approval_required
     AND NOT human_approval_exists
  THEN
    RAISE EXCEPTION
      'Question cannot be promoted without human approval.';
  END IF;


  IF NEW.human_approval_required
     AND NEW.human_approval_received IS NOT TRUE
  THEN
    RAISE EXCEPTION
      'Human approval flag has not been recorded.';
  END IF;


  RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trigger_validate_question_promotion
ON public.question_promotion_requests;

CREATE TRIGGER trigger_validate_question_promotion
BEFORE INSERT OR UPDATE
ON public.question_promotion_requests
FOR EACH ROW
EXECUTE FUNCTION public.validate_question_promotion();


-- =========================================================
-- 4. PROMOTION AUDIT
-- Kim, hangi staging sorusunu ne zaman aktardı?
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_promotion_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  promotion_request_id uuid NOT NULL
    REFERENCES public.question_promotion_requests(id)
    ON DELETE CASCADE,

  staging_question_id uuid NOT NULL
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  question_id uuid
    REFERENCES public.questions(id)
    ON DELETE SET NULL,

  action text NOT NULL
    CHECK (
      action IN (
        'requested',
        'approved',
        'rejected',
        'blocked',
        'promoted'
      )
    ),

  performed_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  details jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_question_promotion_audit_staging
ON public.question_promotion_audit(staging_question_id);

CREATE INDEX IF NOT EXISTS idx_question_promotion_audit_question
ON public.question_promotion_audit(question_id);

ALTER TABLE public.question_promotion_audit
ENABLE ROW LEVEL SECURITY;