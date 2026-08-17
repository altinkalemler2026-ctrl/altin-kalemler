-- 028_competition_pool_demand_planner.sql
-- Altın Kalemler
--
-- Yarışma soru havuzu ihtiyaç analizi ve
-- AI soru üretim planlama altyapısı.
--
-- Amaç:
-- - Sadece toplam soru sayısını değil,
--   soru çeşitliliğini analiz etmek.
-- - Sınıf / ders / konu / alt konu / kazanım
-- - zorluk
-- - soru tipi
-- - bilişsel seviye
-- - yeni nesil
-- - görsel / grafik / tablo ihtiyacı
-- - okuma / muhakeme / işlem yükü
-- - soru çözüm süresi
-- - kullanım sıklığı
-- - aşırı tekrar kullanımı
-- gibi boyutlarda açıkları görmek.
--
-- Eksik bulunması halinde AI üretim TALEBİ oluşturulur.
--
-- AI doğrudan production question bank'a soru ekleyemez.
-- Mevcut staging -> validation -> review -> approval
-- zinciri korunur.

BEGIN;


-- =========================================================
-- 1. YARIŞMA SORU HAVUZU HEDEF PROFİLLERİ
--
-- Örnek:
-- 10. sınıf
-- Matematik
-- Fonksiyonlar
-- Orta
-- Grafik
-- 60-90 saniye
-- Hedef: 40 soru
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competition_pool_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  profile_code text NOT NULL UNIQUE,

  name text NOT NULL,
  description text,

  -- -------------------------------------------------------
  -- Müfredat boyutları
  -- -------------------------------------------------------

  curriculum_version_id uuid
    REFERENCES public.curriculum_versions(id)
    ON DELETE SET NULL,

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

  outcome_id uuid
    REFERENCES public.curriculum_outcomes(id)
    ON DELETE SET NULL,

  -- -------------------------------------------------------
  -- Soru özellikleri
  -- -------------------------------------------------------

  difficulty text
    CHECK (
      difficulty IS NULL
      OR difficulty IN (
        'easy',
        'medium',
        'hard',
        'mixed'
      )
    ),

  question_type text,

  cognitive_level text,

  new_generation_required boolean,

  requires_visual boolean,
  requires_graph boolean,
  requires_table boolean,
  requires_diagram boolean,

  -- -------------------------------------------------------
  -- Süre / bilişsel yük
  -- -------------------------------------------------------

  min_solve_time_seconds numeric(10,2)
    CHECK (
      min_solve_time_seconds IS NULL
      OR min_solve_time_seconds >= 0
    ),

  max_solve_time_seconds numeric(10,2)
    CHECK (
      max_solve_time_seconds IS NULL
      OR max_solve_time_seconds > 0
    ),

  reading_load text
    CHECK (
      reading_load IS NULL
      OR reading_load IN (
        'very_low',
        'low',
        'medium',
        'high',
        'very_high'
      )
    ),

  reasoning_load text
    CHECK (
      reasoning_load IS NULL
      OR reasoning_load IN (
        'very_low',
        'low',
        'medium',
        'high',
        'very_high'
      )
    ),

  calculation_load text
    CHECK (
      calculation_load IS NULL
      OR calculation_load IN (
        'none',
        'very_low',
        'low',
        'medium',
        'high',
        'very_high'
      )
    ),

  visual_load text
    CHECK (
      visual_load IS NULL
      OR visual_load IN (
        'none',
        'very_low',
        'low',
        'medium',
        'high',
        'very_high'
      )
    ),

  -- -------------------------------------------------------
  -- Havuz hedefleri
  -- -------------------------------------------------------

  target_question_count integer NOT NULL DEFAULT 20
    CHECK (target_question_count > 0),

  minimum_safe_count integer NOT NULL DEFAULT 10
    CHECK (minimum_safe_count >= 0),

  preferred_buffer_percent numeric(5,2)
    NOT NULL DEFAULT 20
    CHECK (
      preferred_buffer_percent >= 0
      AND preferred_buffer_percent <= 500
    ),

  -- -------------------------------------------------------
  -- Tekrar kullanım kontrolü
  --
  -- Örn:
  -- Son 90 günde bir soru 10'dan fazla yarışmada
  -- kullanılmışsa "overused" kabul edilebilir.
  -- -------------------------------------------------------

  usage_window_days integer NOT NULL DEFAULT 90
    CHECK (usage_window_days > 0),

  max_uses_per_window integer NOT NULL DEFAULT 10
    CHECK (max_uses_per_window > 0),

  -- -------------------------------------------------------
  -- Çeşitlilik
  -- -------------------------------------------------------

  diversity_rules jsonb NOT NULL DEFAULT '{}'::jsonb,

  selection_rules jsonb NOT NULL DEFAULT '{}'::jsonb,

  ai_generation_rules jsonb NOT NULL DEFAULT '{}'::jsonb,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  priority smallint NOT NULL DEFAULT 50
    CHECK (priority BETWEEN 1 AND 100),

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    min_solve_time_seconds IS NULL
    OR max_solve_time_seconds IS NULL
    OR max_solve_time_seconds >= min_solve_time_seconds
  ),

  CHECK (
    minimum_safe_count <= target_question_count
  )
);


CREATE INDEX IF NOT EXISTS
idx_competition_pool_profiles_lookup
ON public.competition_pool_profiles(
  grade_level,
  subject_id,
  topic_id,
  difficulty
);


CREATE INDEX IF NOT EXISTS
idx_competition_pool_profiles_active
ON public.competition_pool_profiles(
  is_active,
  priority
);


ALTER TABLE public.competition_pool_profiles
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS
trigger_competition_pool_profiles_updated_at
ON public.competition_pool_profiles;


CREATE TRIGGER
trigger_competition_pool_profiles_updated_at
BEFORE UPDATE
ON public.competition_pool_profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. HAVUZ ANALİZ ÇALIŞMALARI
--
-- Her analiz ayrı snapshot.
-- Böylece zaman içinde:
--
-- Ocak: 80 eksik
-- Şubat: 34 eksik
-- Mart: 7 eksik
--
-- gibi gelişimi görebiliriz.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competition_pool_analysis_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  run_code text NOT NULL UNIQUE,

  run_type text NOT NULL DEFAULT 'full'
    CHECK (
      run_type IN (
        'full',
        'grade',
        'subject',
        'profile',
        'scheduled',
        'manual',
        'custom'
      )
    ),

  status text NOT NULL DEFAULT 'pending'
    CHECK (
      status IN (
        'pending',
        'running',
        'completed',
        'failed',
        'cancelled'
      )
    ),

  requested_grade_level smallint
    CHECK (
      requested_grade_level IS NULL
      OR requested_grade_level BETWEEN 1 AND 12
    ),

  requested_subject_id uuid
    REFERENCES public.subjects(id)
    ON DELETE SET NULL,

  requested_profile_id uuid
    REFERENCES public.competition_pool_profiles(id)
    ON DELETE SET NULL,

  started_at timestamptz,
  completed_at timestamptz,

  summary jsonb NOT NULL DEFAULT '{}'::jsonb,

  error_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  created_at timestamptz NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS
idx_competition_pool_analysis_runs_status
ON public.competition_pool_analysis_runs(
  status,
  created_at DESC
);


ALTER TABLE public.competition_pool_analysis_runs
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 3. ANALİZ SONUCU / GAP ITEMS
--
-- Her profile için analiz sonucunu ayrı kaydeder.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competition_pool_gap_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  analysis_run_id uuid NOT NULL
    REFERENCES public.competition_pool_analysis_runs(id)
    ON DELETE CASCADE,

  profile_id uuid NOT NULL
    REFERENCES public.competition_pool_profiles(id)
    ON DELETE CASCADE,

  -- -------------------------------------------------------
  -- Havuz adetleri
  -- -------------------------------------------------------

  total_matching_questions integer NOT NULL DEFAULT 0
    CHECK (total_matching_questions >= 0),

  approved_active_questions integer NOT NULL DEFAULT 0
    CHECK (approved_active_questions >= 0),

  questions_with_time_profile integer NOT NULL DEFAULT 0
    CHECK (questions_with_time_profile >= 0),

  scoring_ready_questions integer NOT NULL DEFAULT 0
    CHECK (scoring_ready_questions >= 0),

  overused_questions integer NOT NULL DEFAULT 0
    CHECK (overused_questions >= 0),

  diversity_rejected_questions integer NOT NULL DEFAULT 0
    CHECK (diversity_rejected_questions >= 0),

  quality_rejected_questions integer NOT NULL DEFAULT 0
    CHECK (quality_rejected_questions >= 0),

  copyright_blocked_questions integer NOT NULL DEFAULT 0
    CHECK (copyright_blocked_questions >= 0),

  -- -------------------------------------------------------
  -- Gerçek kullanılabilir havuz
  -- -------------------------------------------------------

  usable_question_count integer NOT NULL DEFAULT 0
    CHECK (usable_question_count >= 0),

  target_question_count integer NOT NULL
    CHECK (target_question_count > 0),

  buffer_target_count integer NOT NULL DEFAULT 0
    CHECK (buffer_target_count >= 0),

  missing_question_count integer NOT NULL DEFAULT 0
    CHECK (missing_question_count >= 0),

  -- -------------------------------------------------------
  -- Risk seviyesi
  -- -------------------------------------------------------

  gap_status text NOT NULL DEFAULT 'unknown'
    CHECK (
      gap_status IN (
        'healthy',
        'watch',
        'low',
        'critical',
        'empty',
        'unknown'
      )
    ),

  urgency_score numeric(5,2) NOT NULL DEFAULT 0
    CHECK (
      urgency_score >= 0
      AND urgency_score <= 100
    ),

  -- -------------------------------------------------------
  -- Çeşitlilik / kullanım analizi
  -- -------------------------------------------------------

  usage_analysis jsonb NOT NULL DEFAULT '{}'::jsonb,

  diversity_analysis jsonb NOT NULL DEFAULT '{}'::jsonb,

  time_profile_analysis jsonb NOT NULL DEFAULT '{}'::jsonb,

  quality_analysis jsonb NOT NULL DEFAULT '{}'::jsonb,

  copyright_analysis jsonb NOT NULL DEFAULT '{}'::jsonb,

  recommendation jsonb NOT NULL DEFAULT '{}'::jsonb,

  calculated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    analysis_run_id,
    profile_id
  )
);


CREATE INDEX IF NOT EXISTS
idx_competition_pool_gap_items_run
ON public.competition_pool_gap_items(
  analysis_run_id,
  gap_status,
  urgency_score DESC
);


CREATE INDEX IF NOT EXISTS
idx_competition_pool_gap_items_profile
ON public.competition_pool_gap_items(
  profile_id,
  calculated_at DESC
);


ALTER TABLE public.competition_pool_gap_items
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 4. SORU YARIŞMA KULLANIM İSTATİSTİKLERİ
--
-- Tek bir sorunun çok fazla tekrarlanmasını takip etmek için.
--
-- Bireysel öğrenci bilgisi burada tutulmaz.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_competition_usage_stats (
  question_id uuid PRIMARY KEY
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  total_competition_uses bigint NOT NULL DEFAULT 0
    CHECK (total_competition_uses >= 0),

  uses_last_7_days integer NOT NULL DEFAULT 0
    CHECK (uses_last_7_days >= 0),

  uses_last_30_days integer NOT NULL DEFAULT 0
    CHECK (uses_last_30_days >= 0),

  uses_last_90_days integer NOT NULL DEFAULT 0
    CHECK (uses_last_90_days >= 0),

  last_used_at timestamptz,

  first_used_at timestamptz,

  average_position numeric(6,2),

  usage_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  calculated_at timestamptz NOT NULL DEFAULT now()
);


CREATE INDEX IF NOT EXISTS
idx_question_competition_usage_overuse
ON public.question_competition_usage_stats(
  uses_last_90_days DESC
);


CREATE INDEX IF NOT EXISTS
idx_question_competition_usage_last
ON public.question_competition_usage_stats(
  last_used_at DESC
);


ALTER TABLE public.question_competition_usage_stats
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 5. AI ÜRETİM İHTİYAÇ TALEPLERİ
--
-- Bu tablo production question oluşturmaz.
--
-- Sadece:
-- "Bu özelliklerde X yeni soru üretmemiz gerekiyor."
--
-- talebi oluşturur.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.competition_ai_generation_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  request_code text NOT NULL UNIQUE,

  analysis_run_id uuid
    REFERENCES public.competition_pool_analysis_runs(id)
    ON DELETE SET NULL,

  gap_item_id uuid
    REFERENCES public.competition_pool_gap_items(id)
    ON DELETE SET NULL,

  profile_id uuid NOT NULL
    REFERENCES public.competition_pool_profiles(id)
    ON DELETE CASCADE,

  requested_question_count integer NOT NULL
    CHECK (
      requested_question_count > 0
    ),

  -- -------------------------------------------------------
  -- AI'nin üretmesi istenen profilin snapshot'ı
  -- -------------------------------------------------------

  generation_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  quality_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  solve_time_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  diversity_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  copyright_requirements jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- -------------------------------------------------------
  -- AI Question Factory bağlantısı
  -- -------------------------------------------------------

  generation_spec_id uuid
    REFERENCES public.ai_generation_specs(id)
    ON DELETE SET NULL,

  ai_job_id uuid
    REFERENCES public.ai_jobs(id)
    ON DELETE SET NULL,

  -- -------------------------------------------------------
  -- Talep durumu
  -- -------------------------------------------------------

  status text NOT NULL DEFAULT 'planned'
    CHECK (
      status IN (
        'planned',
        'approved',
        'queued',
        'generating',
        'reviewing',
        'partially_completed',
        'completed',
        'rejected',
        'cancelled',
        'failed'
      )
    ),

  generated_count integer NOT NULL DEFAULT 0
    CHECK (generated_count >= 0),

  staging_count integer NOT NULL DEFAULT 0
    CHECK (staging_count >= 0),

  approved_count integer NOT NULL DEFAULT 0
    CHECK (approved_count >= 0),

  rejected_count integer NOT NULL DEFAULT 0
    CHECK (rejected_count >= 0),

  -- -------------------------------------------------------
  -- İnsan onayı zorunlu
  -- -------------------------------------------------------

  human_approval_required boolean NOT NULL DEFAULT true,

  human_approval_received boolean NOT NULL DEFAULT false,

  approved_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  approved_at timestamptz,

  notes text,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    human_approval_received = false
    OR approved_by IS NOT NULL
  ),

  CHECK (
    human_approval_received = false
    OR approved_at IS NOT NULL
  )
);


CREATE INDEX IF NOT EXISTS
idx_competition_ai_generation_requests_status
ON public.competition_ai_generation_requests(
  status,
  created_at DESC
);


CREATE INDEX IF NOT EXISTS
idx_competition_ai_generation_requests_profile
ON public.competition_ai_generation_requests(
  profile_id,
  created_at DESC
);


ALTER TABLE public.competition_ai_generation_requests
ENABLE ROW LEVEL SECURITY;


DROP TRIGGER IF EXISTS
trigger_competition_ai_generation_requests_updated_at
ON public.competition_ai_generation_requests;


CREATE TRIGGER
trigger_competition_ai_generation_requests_updated_at
BEFORE UPDATE
ON public.competition_ai_generation_requests
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 6. AI TALEBİNİN DOĞRUDAN PRODUCTION'A GEÇMESİNİ
-- VERİTABANI SEVİYESİNDE ENGELLE
--
-- queued/generating aşamasına geçmeden önce insan onayı.
-- =========================================================

CREATE OR REPLACE FUNCTION public.validate_competition_ai_generation_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN

  IF NEW.status IN (
    'queued',
    'generating'
  )
  AND NEW.human_approval_required = true
  AND NEW.human_approval_received = false
  THEN

    RAISE EXCEPTION
      'Human approval is required before AI question generation can start.';

  END IF;


  IF NEW.approved_count > NEW.staging_count
     AND NEW.staging_count > 0
  THEN

    RAISE EXCEPTION
      'Approved count cannot exceed staging count.';

  END IF;


  RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS
trigger_validate_competition_ai_generation_request
ON public.competition_ai_generation_requests;


CREATE TRIGGER
trigger_validate_competition_ai_generation_request
BEFORE INSERT OR UPDATE
ON public.competition_ai_generation_requests
FOR EACH ROW
EXECUTE FUNCTION public.validate_competition_ai_generation_request();


REVOKE EXECUTE
ON FUNCTION public.validate_competition_ai_generation_request()
FROM PUBLIC, anon, authenticated;


-- =========================================================
-- 7. GAP DURUMUNU HESAPLAYAN FONKSİYON
--
-- Bu basit deterministic hesap:
--
-- usable >= target+buffer -> healthy
-- usable >= target        -> watch
-- usable >= minimum safe  -> low
-- usable > 0              -> critical
-- usable = 0              -> empty
--
-- AI bu sonucu yorumlayabilir fakat temel adet hesabını
-- AI'ye bırakmıyoruz.
-- =========================================================

CREATE OR REPLACE FUNCTION public.calculate_competition_pool_gap_status(
  p_usable_count integer,
  p_target_count integer,
  p_minimum_safe_count integer,
  p_buffer_percent numeric
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_buffer_target integer;
  v_missing integer;
  v_status text;
  v_urgency numeric(5,2);
BEGIN

  IF p_usable_count < 0
     OR p_target_count <= 0
     OR p_minimum_safe_count < 0
  THEN

    RAISE EXCEPTION
      'Invalid pool gap calculation values.';

  END IF;


  v_buffer_target :=
    CEIL(
      p_target_count
      * (
          1
          + COALESCE(
              p_buffer_percent,
              0
            ) / 100
        )
    )::integer;


  v_missing :=
    GREATEST(
      0,
      v_buffer_target - p_usable_count
    );


  IF p_usable_count >= v_buffer_target THEN

    v_status := 'healthy';
    v_urgency := 0;


  ELSIF p_usable_count >= p_target_count THEN

    v_status := 'watch';

    v_urgency :=
      LEAST(
        30,
        (
          v_missing::numeric
          / GREATEST(v_buffer_target, 1)
        ) * 100
      );


  ELSIF p_usable_count >= p_minimum_safe_count THEN

    v_status := 'low';

    v_urgency :=
      LEAST(
        60,
        30
        +
        (
          (
            p_target_count - p_usable_count
          )::numeric
          / GREATEST(p_target_count, 1)
        ) * 30
      );


  ELSIF p_usable_count > 0 THEN

    v_status := 'critical';

    v_urgency :=
      LEAST(
        95,
        60
        +
        (
          (
            p_minimum_safe_count - p_usable_count
          )::numeric
          / GREATEST(p_minimum_safe_count, 1)
        ) * 35
      );


  ELSE

    v_status := 'empty';
    v_urgency := 100;

  END IF;


  RETURN jsonb_build_object(
    'buffer_target_count',
    v_buffer_target,

    'missing_question_count',
    v_missing,

    'gap_status',
    v_status,

    'urgency_score',
    ROUND(v_urgency, 2)
  );

END;
$$;


REVOKE EXECUTE
ON FUNCTION public.calculate_competition_pool_gap_status(
  integer,
  integer,
  integer,
  numeric
)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.calculate_competition_pool_gap_status(
  integer,
  integer,
  integer,
  numeric
)
TO authenticated, service_role;


-- =========================================================
-- 8. DETERMİNİSTİK AI ÜRETİM ÖNERİSİ
--
-- Gap item'a göre kaç soru üretilmesi gerektiğini verir.
--
-- Bu fonksiyon AI çağırmaz.
-- Sadece ihtiyacı hesaplar.
-- =========================================================

CREATE OR REPLACE FUNCTION public.build_competition_generation_recommendation(
  p_gap_item_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_result jsonb;
BEGIN

  SELECT jsonb_build_object(

    'profile_id',
    g.profile_id,

    'profile_code',
    p.profile_code,

    'grade_level',
    p.grade_level,

    'subject_id',
    p.subject_id,

    'topic_id',
    p.topic_id,

    'subtopic_id',
    p.subtopic_id,

    'outcome_id',
    p.outcome_id,

    'difficulty',
    p.difficulty,

    'question_type',
    p.question_type,

    'cognitive_level',
    p.cognitive_level,

    'new_generation_required',
    p.new_generation_required,

    'solve_time',
    jsonb_build_object(
      'minimum_seconds',
      p.min_solve_time_seconds,

      'maximum_seconds',
      p.max_solve_time_seconds,

      'reading_load',
      p.reading_load,

      'reasoning_load',
      p.reasoning_load,

      'calculation_load',
      p.calculation_load,

      'visual_load',
      p.visual_load
    ),

    'visual_requirements',
    jsonb_build_object(
      'requires_visual',
      p.requires_visual,

      'requires_graph',
      p.requires_graph,

      'requires_table',
      p.requires_table,

      'requires_diagram',
      p.requires_diagram
    ),

    'target_question_count',
    g.target_question_count,

    'usable_question_count',
    g.usable_question_count,

    'missing_question_count',
    g.missing_question_count,

    'gap_status',
    g.gap_status,

    'urgency_score',
    g.urgency_score,

    'generation_rules',
    p.ai_generation_rules,

    'diversity_rules',
    p.diversity_rules,

    'important',
    'Generated questions must go through staging, answer validation, curriculum validation, solve-time validation, originality/copyright checks, independent AI review and human approval before production use.'

  )

  INTO v_result

  FROM public.competition_pool_gap_items g

  JOIN public.competition_pool_profiles p
    ON p.id = g.profile_id

  WHERE g.id = p_gap_item_id;


  IF v_result IS NULL THEN

    RAISE EXCEPTION
      'Competition pool gap item not found.';

  END IF;


  RETURN v_result;

END;
$$;


REVOKE EXECUTE
ON FUNCTION public.build_competition_generation_recommendation(uuid)
FROM PUBLIC, anon;


GRANT EXECUTE
ON FUNCTION public.build_competition_generation_recommendation(uuid)
TO authenticated, service_role;


-- =========================================================
-- 9. ADMIN RLS POLİTİKALARI
--
-- Öğrenciler bu yönetim tablolarını doğrudan görmez.
-- =========================================================


-- ---------------------------------------------------------
-- competition_pool_profiles
-- ---------------------------------------------------------

DROP POLICY IF EXISTS
"admins manage competition pool profiles"
ON public.competition_pool_profiles;


CREATE POLICY
"admins manage competition pool profiles"
ON public.competition_pool_profiles
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission(
    'questions.edit'
  )
  OR
  public.current_user_has_admin_permission(
    'ai.manage'
  )
)
WITH CHECK (
  public.current_user_has_admin_permission(
    'questions.edit'
  )
  OR
  public.current_user_has_admin_permission(
    'ai.manage'
  )
);


-- ---------------------------------------------------------
-- analysis runs
-- ---------------------------------------------------------

DROP POLICY IF EXISTS
"admins manage competition pool analysis runs"
ON public.competition_pool_analysis_runs;


CREATE POLICY
"admins manage competition pool analysis runs"
ON public.competition_pool_analysis_runs
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission(
    'questions.edit'
  )
  OR
  public.current_user_has_admin_permission(
    'ai.manage'
  )
)
WITH CHECK (
  public.current_user_has_admin_permission(
    'questions.edit'
  )
  OR
  public.current_user_has_admin_permission(
    'ai.manage'
  )
);


-- ---------------------------------------------------------
-- gap items
-- ---------------------------------------------------------

DROP POLICY IF EXISTS
"admins manage competition pool gap items"
ON public.competition_pool_gap_items;


CREATE POLICY
"admins manage competition pool gap items"
ON public.competition_pool_gap_items
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission(
    'questions.edit'
  )
  OR
  public.current_user_has_admin_permission(
    'ai.manage'
  )
)
WITH CHECK (
  public.current_user_has_admin_permission(
    'questions.edit'
  )
  OR
  public.current_user_has_admin_permission(
    'ai.manage'
  )
);


-- ---------------------------------------------------------
-- usage stats
-- ---------------------------------------------------------

DROP POLICY IF EXISTS
"admins manage question competition usage stats"
ON public.question_competition_usage_stats;


CREATE POLICY
"admins manage question competition usage stats"
ON public.question_competition_usage_stats
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission(
    'questions.edit'
  )
  OR
  public.current_user_has_admin_permission(
    'ai.manage'
  )
)
WITH CHECK (
  public.current_user_has_admin_permission(
    'questions.edit'
  )
  OR
  public.current_user_has_admin_permission(
    'ai.manage'
  )
);


-- ---------------------------------------------------------
-- AI generation requests
-- ---------------------------------------------------------

DROP POLICY IF EXISTS
"admins manage competition ai generation requests"
ON public.competition_ai_generation_requests;


CREATE POLICY
"admins manage competition ai generation requests"
ON public.competition_ai_generation_requests
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission(
    'questions.edit'
  )
  OR
  public.current_user_has_admin_permission(
    'questions.approve'
  )
  OR
  public.current_user_has_admin_permission(
    'ai.manage'
  )
)
WITH CHECK (
  public.current_user_has_admin_permission(
    'questions.edit'
  )
  OR
  public.current_user_has_admin_permission(
    'questions.approve'
  )
  OR
  public.current_user_has_admin_permission(
    'ai.manage'
  )
);


-- =========================================================
-- 10. ADMIN ÖZET VIEW
--
-- SECURITY INVOKER kullanıyoruz.
-- 024'te yaşadığımız Security Definer View uyarısını
-- tekrar üretmemeli.
-- =========================================================

CREATE OR REPLACE VIEW public.competition_pool_gap_overview
WITH (security_invoker = true)
AS

SELECT
  g.id AS gap_item_id,

  g.analysis_run_id,

  p.id AS profile_id,
  p.profile_code,
  p.name AS profile_name,

  p.grade_level,
  p.subject_id,
  p.topic_id,
  p.subtopic_id,
  p.outcome_id,

  p.difficulty,
  p.question_type,
  p.cognitive_level,

  p.min_solve_time_seconds,
  p.max_solve_time_seconds,

  g.total_matching_questions,
  g.approved_active_questions,
  g.questions_with_time_profile,
  g.scoring_ready_questions,
  g.overused_questions,

  g.usable_question_count,

  g.target_question_count,
  g.buffer_target_count,
  g.missing_question_count,

  g.gap_status,
  g.urgency_score,

  g.calculated_at

FROM public.competition_pool_gap_items g

JOIN public.competition_pool_profiles p
  ON p.id = g.profile_id;


REVOKE ALL
ON public.competition_pool_gap_overview
FROM PUBLIC;

REVOKE ALL
ON public.competition_pool_gap_overview
FROM anon;

GRANT SELECT
ON public.competition_pool_gap_overview
TO authenticated;


COMMIT;