-- 007_ai_copyright_and_review.sql
-- Altın Kalemler telif, özgünlük, ticari kullanım ve inceleme katmanı.

-- =========================================================
-- 1. AI KALİTE EŞİKLERİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.ai_quality_thresholds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  threshold_code text NOT NULL UNIQUE,
  name text NOT NULL,

  scope_type text NOT NULL DEFAULT 'global'
    CHECK (
      scope_type IN (
        'global',
        'subject',
        'grade',
        'commercial'
      )
    ),

  subject_id uuid
    REFERENCES public.subjects(id)
    ON DELETE CASCADE,

  grade_level smallint
    CHECK (
      grade_level IS NULL
      OR grade_level BETWEEN 1 AND 12
    ),

  min_score numeric(5,4)
    CHECK (
      min_score IS NULL
      OR (
        min_score >= 0
        AND min_score <= 1
      )
    ),

  max_score numeric(5,4)
    CHECK (
      max_score IS NULL
      OR (
        max_score >= 0
        AND max_score <= 1
      )
    ),

  is_blocking boolean NOT NULL DEFAULT false,
  notes text,
  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    min_score IS NULL
    OR max_score IS NULL
    OR min_score <= max_score
  )
);

ALTER TABLE public.ai_quality_thresholds
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_ai_quality_thresholds_set_updated_at
ON public.ai_quality_thresholds;

CREATE TRIGGER trigger_ai_quality_thresholds_set_updated_at
BEFORE UPDATE ON public.ai_quality_thresholds
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. TELİF / ÖZGÜNLÜK İNCELEMELERİ
-- AI burada hukuki karar vermez.
-- Sadece risk ve kullanım uygunluğu önerir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.copyright_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  staging_question_id uuid
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  question_id uuid
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  source_id uuid
    REFERENCES public.question_sources(id)
    ON DELETE SET NULL,

  review_type text NOT NULL
    CHECK (
      review_type IN (
        'source_rights',
        'license',
        'text_similarity',
        'semantic_similarity',
        'structural_similarity',
        'solution_similarity',
        'originality',
        'commercial_use'
      )
    ),

  risk_level text NOT NULL DEFAULT 'unknown'
    CHECK (
      risk_level IN (
        'unknown',
        'low',
        'medium',
        'high',
        'blocked'
      )
    ),

  originality_score numeric(5,4)
    CHECK (
      originality_score IS NULL
      OR (
        originality_score >= 0
        AND originality_score <= 1
      )
    ),

  commercial_use_recommendation text NOT NULL DEFAULT 'not_reviewed'
    CHECK (
      commercial_use_recommendation IN (
        'not_reviewed',
        'allow',
        'do_not_allow',
        'human_review_required'
      )
    ),

  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,

  reviewer_type text NOT NULL
    CHECK (
      reviewer_type IN (
        'deterministic',
        'ai',
        'human'
      )
    ),

  provider_name text,
  model_name text,
  prompt_version text,

  reviewed_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  notes text,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    staging_question_id IS NOT NULL
    OR question_id IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS idx_copyright_reviews_staging
ON public.copyright_reviews(staging_question_id);

CREATE INDEX IF NOT EXISTS idx_copyright_reviews_question
ON public.copyright_reviews(question_id);

CREATE INDEX IF NOT EXISTS idx_copyright_reviews_risk
ON public.copyright_reviews(risk_level);

ALTER TABLE public.copyright_reviews
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 3. TİCARİ KULLANIM GÜVENLİK KAPISI
-- Bir soru satılacak ürüne girmeden önce buradan geçer.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.commercial_question_clearance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  question_id uuid
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  staging_question_id uuid
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  clearance_status text NOT NULL DEFAULT 'pending'
    CHECK (
      clearance_status IN (
        'pending',
        'approved',
        'rejected',
        'human_review_required',
        'blocked'
      )
    ),

  ownership_check_passed boolean NOT NULL DEFAULT false,
  license_check_passed boolean NOT NULL DEFAULT false,
  originality_check_passed boolean NOT NULL DEFAULT false,
  similarity_check_passed boolean NOT NULL DEFAULT false,
  copyright_review_passed boolean NOT NULL DEFAULT false,
  quality_review_passed boolean NOT NULL DEFAULT false,

  originality_score numeric(5,4)
    CHECK (
      originality_score IS NULL
      OR (
        originality_score >= 0
        AND originality_score <= 1
      )
    ),

  highest_similarity_score numeric(5,4)
    CHECK (
      highest_similarity_score IS NULL
      OR (
        highest_similarity_score >= 0
        AND highest_similarity_score <= 1
      )
    ),

  decision_reason text,

  reviewed_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  reviewed_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    (
      question_id IS NOT NULL
      AND staging_question_id IS NULL
    )
    OR
    (
      question_id IS NULL
      AND staging_question_id IS NOT NULL
    )
  ),

  CHECK (
    clearance_status <> 'approved'
    OR (
      ownership_check_passed = true
      AND license_check_passed = true
      AND originality_check_passed = true
      AND similarity_check_passed = true
      AND copyright_review_passed = true
      AND quality_review_passed = true
    )
  )
);

CREATE INDEX IF NOT EXISTS idx_commercial_clearance_question
ON public.commercial_question_clearance(question_id);

CREATE INDEX IF NOT EXISTS idx_commercial_clearance_staging
ON public.commercial_question_clearance(staging_question_id);

CREATE INDEX IF NOT EXISTS idx_commercial_clearance_status
ON public.commercial_question_clearance(clearance_status);

ALTER TABLE public.commercial_question_clearance
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_commercial_question_clearance_set_updated_at
ON public.commercial_question_clearance;

CREATE TRIGGER trigger_commercial_question_clearance_set_updated_at
BEFORE UPDATE ON public.commercial_question_clearance
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 4. İNCELEME KUYRUĞU
-- AI'nin emin olmadığı veya riskli gördüğü işler buraya gelir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.review_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  entity_type text NOT NULL
    CHECK (
      entity_type IN (
        'staging_question',
        'question',
        'curriculum_mapping',
        'similarity_match',
        'copyright_review',
        'commercial_clearance',
        'solution_asset',
        'question_asset',
        'source',
        'import_error',
        'ai_job'
      )
    ),

  entity_id uuid NOT NULL,

  reason_code text NOT NULL,

  reason_details jsonb NOT NULL DEFAULT '{}'::jsonb,

  priority text NOT NULL DEFAULT 'normal'
    CHECK (
      priority IN (
        'low',
        'normal',
        'high',
        'critical'
      )
    ),

  status text NOT NULL DEFAULT 'open'
    CHECK (
      status IN (
        'open',
        'assigned',
        'approved',
        'rejected',
        'resolved',
        'cancelled'
      )
    ),

  assigned_to uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  decision_notes text,

  created_at timestamptz NOT NULL DEFAULT now(),
  assigned_at timestamptz,
  resolved_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_review_queue_status_priority
ON public.review_queue(status, priority);

CREATE INDEX IF NOT EXISTS idx_review_queue_entity
ON public.review_queue(entity_type, entity_id);

CREATE INDEX IF NOT EXISTS idx_review_queue_assigned
ON public.review_queue(assigned_to);

ALTER TABLE public.review_queue
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_review_queue_set_updated_at
ON public.review_queue;

CREATE TRIGGER trigger_review_queue_set_updated_at
BEFORE UPDATE ON public.review_queue
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 5. BAŞLANGIÇ KALİTE EŞİKLERİ
-- Bunlar hukuki sınır değildir.
-- Sistem içi risk/kalite eşikleridir.
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
  'answer_confidence',
  'Minimum cevap güveni',
  'global',
  0.9500,
  NULL,
  true,
  'Düşük güvenli cevaplar otomatik incelemeye gönderilir.'
),

(
  'grade_fit',
  'Minimum sınıf uygunluğu',
  'global',
  0.9000,
  NULL,
  true,
  'Sınıf seviyesine uygun olmayan sorular otomatik onaylanmaz.'
),

(
  'topic_fit',
  'Minimum konu bütünlüğü',
  'global',
  0.9000,
  NULL,
  true,
  'Hedef konu ve alt konudan sapan sorular incelemeye gönderilir.'
),

(
  'classification_confidence',
  'Minimum sınıflandırma güveni',
  'global',
  0.9000,
  NULL,
  false,
  'Düşük güvenli müfredat sınıflandırmaları uzman incelemesine gider.'
),

(
  'commercial_originality',
  'Ticari içerik minimum özgünlük skoru',
  'commercial',
  0.9200,
  NULL,
  true,
  'Ticari yayın adaylarında yüksek özgünlük hedeflenir.'
),

(
  'commercial_similarity',
  'Ticari içerik maksimum benzerlik skoru',
  'commercial',
  NULL,
  0.8000,
  true,
  'Bu sınırın üzerindeki benzerlik otomatik ticari onayı engeller.'
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
-- 6. BAŞLANGIÇ AI AJANLARI
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
  'orchestrator',
  'AI Orkestratör',
  'AI workflow adımlarını koordine eder.',
  'orchestration',
  'high',
  false,
  false,
  false
),

(
  'pdf_structure_analyzer',
  'PDF Yapı Analiz AI',
  'PDF sayfalarını, testleri, cevap anahtarlarını ve soru bölgelerini analiz eder.',
  'extraction',
  'high',
  false,
  true,
  false
),

(
  'legacy_matcher',
  'Excel ve Legacy Eşleştirme AI',
  'PDF sorularını mevcut Excel ve legacy kayıtlarla eşleştirir.',
  'matching',
  'high',
  false,
  true,
  false
),

(
  'question_generator',
  'Soru Üretim AI',
  'Hedef sınıf, ders, konu, zorluk ve bilişsel seviyeye göre özgün aday soru üretir.',
  'generation',
  'critical',
  true,
  false,
  false
),

(
  'grade_reviewer',
  'Sınıf Uygunluğu Denetçisi AI',
  'Sorunun hedef sınıf seviyesine uygunluğunu ve ileri sınıf bilgisi gerektirip gerektirmediğini denetler.',
  'review',
  'critical',
  false,
  true,
  true
),

(
  'topic_coherence_reviewer',
  'Konu Bütünlüğü Denetçisi AI',
  'Sorunun hedef konu, alt konu ve kazanım bütünlüğünü denetler.',
  'review',
  'critical',
  false,
  true,
  true
),

(
  'prerequisite_reviewer',
  'Ön Koşul Bilgisi Denetçisi AI',
  'Sorunun hedef sınıfta henüz işlenmemiş bilgi gerektirip gerektirmediğini kontrol eder.',
  'review',
  'critical',
  false,
  true,
  true
),

(
  'curriculum_classifier',
  'Müfredat Sınıflandırma AI',
  'Sorunun sınıf, ders, konu ve alt konu eşleştirmesini önerir.',
  'classification',
  'high',
  false,
  true,
  false
),

(
  'curriculum_reviewer',
  'Müfredat Denetçisi AI',
  'Müfredat sınıflandırmasını bağımsız olarak denetler.',
  'review',
  'critical',
  false,
  true,
  true
),

(
  'answer_solver',
  'Bağımsız Soru Çözücü AI',
  'Soruyu bağımsız çözer ve cevap önerir.',
  'validation',
  'critical',
  false,
  true,
  false
),

(
  'answer_reviewer',
  'İkinci Cevap Denetçisi AI',
  'İlk çözümden bağımsız olarak ikinci cevap kontrolü yapar.',
  'review',
  'critical',
  false,
  true,
  true
),

(
  'language_reviewer',
  'Dil ve Anlatım Denetçisi AI',
  'Dil, anlatım, belirsizlik ve seçenek kalitesini kontrol eder.',
  'review',
  'high',
  false,
  true,
  true
),

(
  'scientific_reviewer',
  'Bilimsel Doğruluk Denetçisi AI',
  'Soru içeriğinin bilimsel ve akademik doğruluğunu kontrol eder.',
  'review',
  'critical',
  false,
  true,
  true
),

(
  'similarity_reviewer',
  'Benzerlik Denetçisi AI',
  'Yeni soruları mevcut soru havuzu ve staging sorularıyla karşılaştırır.',
  'copyright',
  'critical',
  false,
  true,
  false
),

(
  'originality_reviewer',
  'Özgünlük Denetçisi AI',
  'AI tarafından üretilen soruların özgünlük seviyesini değerlendirir.',
  'copyright',
  'critical',
  false,
  true,
  true
),

(
  'copyright_reviewer',
  'Telif Risk Denetçisi AI',
  'Kaynak, lisans, benzerlik ve ticari kullanım risklerini işaretler.',
  'copyright',
  'critical',
  false,
  true,
  false
),

(
  'commercial_gatekeeper',
  'Ticari Yayın Denetçisi AI',
  'Satışa girecek soruların telif, lisans, özgünlük ve kalite kontrollerini denetler.',
  'publishing',
  'critical',
  false,
  true,
  true
),

(
  'gap_analyzer',
  'Soru Havuzu Eksik Analiz AI',
  'Sınıf, ders, konu, zorluk ve soru tiplerine göre eksik alanları belirler.',
  'analytics',
  'medium',
  false,
  true,
  false
),

(
  'security_reviewer',
  'AI Güvenlik Denetçisi',
  'Dosya, URL, prompt injection ve olağandışı girdileri risk açısından inceler.',
  'security',
  'critical',
  false,
  true,
  false
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