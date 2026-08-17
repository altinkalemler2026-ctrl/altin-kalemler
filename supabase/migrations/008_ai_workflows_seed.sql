-- 008_ai_workflows_seed.sql
-- Altın Kalemler AI workflow başlangıç tanımları.

-- =========================================================
-- 1. WORKFLOW TANIMLARI
-- =========================================================

INSERT INTO public.ai_workflows (
  workflow_code,
  name,
  description,
  workflow_type,
  is_active
)
VALUES
(
  'pdf_question_import',
  'PDF Soru İçe Aktarma',
  'PDF içeriğini analiz eder, soruları ayırır, eşleştirir ve doğrulama kuyruğuna gönderir.',
  'pdf_import',
  true
),
(
  'ai_question_generation',
  'AI Soru Üretimi',
  'Hedef sınıf, ders, konu ve zorluk seviyesine göre yeni soru üretir ve çok aşamalı denetime sokar.',
  'question_generation',
  true
),
(
  'question_revalidation',
  'Soru Yeniden Doğrulama',
  'Mevcut bir soruyu cevap, sınıf, konu, müfredat ve kalite açısından yeniden değerlendirir.',
  'question_revalidation',
  true
),
(
  'commercial_question_review',
  'Ticari Yayın İncelemesi',
  'Satışa girecek sorular için telif, lisans, benzerlik, özgünlük ve kalite kontrollerini çalıştırır.',
  'commercial_review',
  true
),
(
  'question_pool_gap_analysis',
  'Soru Havuzu Eksik Analizi',
  'Soru havuzundaki sınıf, konu, zorluk ve soru tipi eksiklerini belirler.',
  'gap_analysis',
  true
)
ON CONFLICT (workflow_code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  workflow_type = EXCLUDED.workflow_type,
  is_active = true;


-- =========================================================
-- 2. PDF IMPORT WORKFLOW
-- =========================================================

WITH wf AS (
  SELECT id
  FROM public.ai_workflows
  WHERE workflow_code = 'pdf_question_import'
),
agents AS (
  SELECT id, agent_code
  FROM public.ai_agents
)
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
SELECT
  wf.id,
  v.step_order,
  v.step_code,
  agents.id,
  v.step_type,
  v.is_required,
  v.failure_action,
  v.configuration
FROM wf
CROSS JOIN (
  VALUES
    (
      1,
      'security_check',
      'security_reviewer',
      'ai',
      true,
      'stop',
      '{"purpose":"Dosya ve içerik güvenlik kontrolü"}'::jsonb
    ),
    (
      2,
      'pdf_structure_analysis',
      'pdf_structure_analyzer',
      'ai',
      true,
      'review',
      '{"purpose":"Sayfa, test ve cevap anahtarı yapısını tespit et"}'::jsonb
    ),
    (
      3,
      'legacy_matching',
      'legacy_matcher',
      'ai',
      false,
      'review',
      '{"purpose":"Excel ve legacy kayıtlarla eşleştir"}'::jsonb
    ),
    (
      4,
      'curriculum_classification',
      'curriculum_classifier',
      'ai',
      true,
      'review',
      '{"purpose":"Sınıf, ders, konu ve alt konu öner"}'::jsonb
    ),
    (
      5,
      'curriculum_review',
      'curriculum_reviewer',
      'ai',
      true,
      'review',
      '{"purpose":"Müfredat eşleştirmesini bağımsız denetle"}'::jsonb
    )
) AS v(
  step_order,
  step_code,
  agent_code,
  step_type,
  is_required,
  failure_action,
  configuration
)
JOIN agents
  ON agents.agent_code = v.agent_code
ON CONFLICT (workflow_id, step_order) DO NOTHING;


-- =========================================================
-- 3. AI QUESTION GENERATION WORKFLOW
-- =========================================================

WITH wf AS (
  SELECT id
  FROM public.ai_workflows
  WHERE workflow_code = 'ai_question_generation'
),
agents AS (
  SELECT id, agent_code
  FROM public.ai_agents
)
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
SELECT
  wf.id,
  v.step_order,
  v.step_code,
  agents.id,
  v.step_type,
  v.is_required,
  v.failure_action,
  v.configuration
FROM wf
CROSS JOIN (
  VALUES
    (
      1,
      'generate_question',
      'question_generator',
      'ai',
      true,
      'reject',
      '{"purpose":"Hedef şartnameye göre özgün aday soru üret"}'::jsonb
    ),
    (
      2,
      'grade_appropriateness',
      'grade_reviewer',
      'ai',
      true,
      'retry',
      '{"purpose":"Sorunun hedef sınıfa uygunluğunu kontrol et"}'::jsonb
    ),
    (
      3,
      'topic_coherence',
      'topic_coherence_reviewer',
      'ai',
      true,
      'retry',
      '{"purpose":"Konu ve alt konu bütünlüğünü kontrol et"}'::jsonb
    ),
    (
      4,
      'prerequisite_check',
      'prerequisite_reviewer',
      'ai',
      true,
      'retry',
      '{"purpose":"Üst sınıf veya işlenmemiş ön koşul bilgisi gerektiriyor mu kontrol et"}'::jsonb
    ),
    (
      5,
      'curriculum_check',
      'curriculum_reviewer',
      'ai',
      true,
      'review',
      '{"purpose":"Müfredat uygunluğunu bağımsız denetle"}'::jsonb
    ),
    (
      6,
      'independent_answer',
      'answer_solver',
      'ai',
      true,
      'review',
      '{"purpose":"Soruyu bağımsız çöz"}'::jsonb
    ),
    (
      7,
      'second_answer_review',
      'answer_reviewer',
      'ai',
      true,
      'review',
      '{"purpose":"İkinci bağımsız cevap kontrolü yap"}'::jsonb
    ),
    (
      8,
      'language_review',
      'language_reviewer',
      'ai',
      true,
      'review',
      '{"purpose":"Dil, anlatım ve seçenek kalitesini kontrol et"}'::jsonb
    ),
    (
      9,
      'scientific_review',
      'scientific_reviewer',
      'ai',
      true,
      'review',
      '{"purpose":"Bilimsel ve akademik doğruluk kontrolü"}'::jsonb
    ),
    (
      10,
      'similarity_review',
      'similarity_reviewer',
      'ai',
      true,
      'review',
      '{"purpose":"Mevcut sorularla benzerlik kontrolü"}'::jsonb
    ),
    (
      11,
      'originality_review',
      'originality_reviewer',
      'ai',
      true,
      'review',
      '{"purpose":"Özgünlük ve yeniden yazım riskini kontrol et"}'::jsonb
    ),
    (
      12,
      'copyright_review',
      'copyright_reviewer',
      'ai',
      true,
      'review',
      '{"purpose":"Telif ve ticari kullanım riskini kontrol et"}'::jsonb
    )
) AS v(
  step_order,
  step_code,
  agent_code,
  step_type,
  is_required,
  failure_action,
  configuration
)
JOIN agents
  ON agents.agent_code = v.agent_code
ON CONFLICT (workflow_id, step_order) DO NOTHING;


-- =========================================================
-- 4. COMMERCIAL REVIEW WORKFLOW
-- =========================================================

WITH wf AS (
  SELECT id
  FROM public.ai_workflows
  WHERE workflow_code = 'commercial_question_review'
),
agents AS (
  SELECT id, agent_code
  FROM public.ai_agents
)
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
SELECT
  wf.id,
  v.step_order,
  v.step_code,
  agents.id,
  v.step_type,
  v.is_required,
  v.failure_action,
  v.configuration
FROM wf
CROSS JOIN (
  VALUES
    (
      1,
      'similarity_check',
      'similarity_reviewer',
      'ai',
      true,
      'stop',
      '{"purpose":"Ticari içerik için yüksek benzerlik riskini kontrol et"}'::jsonb
    ),
    (
      2,
      'originality_check',
      'originality_reviewer',
      'ai',
      true,
      'stop',
      '{"purpose":"Ticari içerik özgünlük kontrolü"}'::jsonb
    ),
    (
      3,
      'copyright_check',
      'copyright_reviewer',
      'ai',
      true,
      'review',
      '{"purpose":"Kaynak ve lisans risklerini kontrol et"}'::jsonb
    ),
    (
      4,
      'commercial_gate',
      'commercial_gatekeeper',
      'ai',
      true,
      'review',
      '{"purpose":"Tüm ticari kullanım kapılarını değerlendir"}'::jsonb
    )
) AS v(
  step_order,
  step_code,
  agent_code,
  step_type,
  is_required,
  failure_action,
  configuration
)
JOIN agents
  ON agents.agent_code = v.agent_code
ON CONFLICT (workflow_id, step_order) DO NOTHING;