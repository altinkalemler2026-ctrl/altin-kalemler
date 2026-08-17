-- 020_question_solve_time_intelligence.sql
-- Altın Kalemler
-- Her soru için ayrı okuma, değerlendirme, görsel inceleme,
-- işlem ve toplam çözüm süresi analizi.
--
-- AI tahmini + bağımsız AI incelemesi + gerçek öğrenci
-- performans verisi ile kalibrasyon altyapısı.
--
-- ÖNEMLİ:
-- Süre sınıf/konu/zorluk bazında topluca atanmaz.
-- Her question_id için ayrı profil oluşturulur.


-- =========================================================
-- 1. SORU SÜRE ANALİZ PROFİLLERİ
-- Her soru için ayrı ve versiyonlanabilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_solve_time_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  question_id uuid NOT NULL
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  analysis_version integer NOT NULL DEFAULT 1
    CHECK (analysis_version > 0),

  -- -------------------------------------------------------
  -- İçerik değişikliği takibi
  -- Soru metni/görseli değişirse yeni analiz yapılabilsin.
  -- -------------------------------------------------------

  content_fingerprint text,

  -- -------------------------------------------------------
  -- SÜRENİN ANA BİLEŞENLERİ
  -- Her soru için ayrı ayrı hesaplanır.
  -- -------------------------------------------------------

  estimated_reading_time_seconds numeric(8,2) NOT NULL DEFAULT 0
    CHECK (estimated_reading_time_seconds >= 0),

  estimated_reasoning_time_seconds numeric(8,2) NOT NULL DEFAULT 0
    CHECK (estimated_reasoning_time_seconds >= 0),

  estimated_visual_analysis_time_seconds numeric(8,2) NOT NULL DEFAULT 0
    CHECK (estimated_visual_analysis_time_seconds >= 0),

  estimated_calculation_time_seconds numeric(8,2) NOT NULL DEFAULT 0
    CHECK (estimated_calculation_time_seconds >= 0),

  -- Ek özel süre.
  -- Örneğin tablo karşılaştırma, veri aktarma,
  -- geometrik çizimi zihinde tamamlama vb.
  estimated_other_time_seconds numeric(8,2) NOT NULL DEFAULT 0
    CHECK (estimated_other_time_seconds >= 0),

  -- Toplam süre bileşenlerden otomatik hesaplanır.
  estimated_total_time_seconds numeric(10,2)
    GENERATED ALWAYS AS (
      estimated_reading_time_seconds
      + estimated_reasoning_time_seconds
      + estimated_visual_analysis_time_seconds
      + estimated_calculation_time_seconds
      + estimated_other_time_seconds
    ) STORED,

  -- Yarışmada kullanılacak önerilen üst süre.
  -- Toplam tahminden farklı olabilir.
  recommended_time_limit_seconds numeric(10,2)
    CHECK (
      recommended_time_limit_seconds IS NULL
      OR recommended_time_limit_seconds > 0
    ),

  -- -------------------------------------------------------
  -- AI GÜVEN SKORLARI
  -- 0.00 - 1.00
  -- -------------------------------------------------------

  reading_time_confidence numeric(5,4)
    CHECK (
      reading_time_confidence IS NULL
      OR reading_time_confidence BETWEEN 0 AND 1
    ),

  reasoning_time_confidence numeric(5,4)
    CHECK (
      reasoning_time_confidence IS NULL
      OR reasoning_time_confidence BETWEEN 0 AND 1
    ),

  visual_time_confidence numeric(5,4)
    CHECK (
      visual_time_confidence IS NULL
      OR visual_time_confidence BETWEEN 0 AND 1
    ),

  calculation_time_confidence numeric(5,4)
    CHECK (
      calculation_time_confidence IS NULL
      OR calculation_time_confidence BETWEEN 0 AND 1
    ),

  total_time_confidence numeric(5,4)
    CHECK (
      total_time_confidence IS NULL
      OR total_time_confidence BETWEEN 0 AND 1
    ),

  -- -------------------------------------------------------
  -- SORUNUN SÜREYİ ETKİLEYEN ÖZELLİKLERİ
  -- -------------------------------------------------------

  text_character_count integer
    CHECK (
      text_character_count IS NULL
      OR text_character_count >= 0
    ),

  text_word_count integer
    CHECK (
      text_word_count IS NULL
      OR text_word_count >= 0
    ),

  sentence_count integer
    CHECK (
      sentence_count IS NULL
      OR sentence_count >= 0
    ),

  option_word_count integer
    CHECK (
      option_word_count IS NULL
      OR option_word_count >= 0
    ),

  visual_count integer NOT NULL DEFAULT 0
    CHECK (visual_count >= 0),

  table_count integer NOT NULL DEFAULT 0
    CHECK (table_count >= 0),

  graph_count integer NOT NULL DEFAULT 0
    CHECK (graph_count >= 0),

  diagram_count integer NOT NULL DEFAULT 0
    CHECK (diagram_count >= 0),

  formula_count integer NOT NULL DEFAULT 0
    CHECK (formula_count >= 0),

  estimated_reasoning_step_count integer
    CHECK (
      estimated_reasoning_step_count IS NULL
      OR estimated_reasoning_step_count >= 0
    ),

  estimated_calculation_step_count integer
    CHECK (
      estimated_calculation_step_count IS NULL
      OR estimated_calculation_step_count >= 0
    ),

  required_formula_count integer
    CHECK (
      required_formula_count IS NULL
      OR required_formula_count >= 0
    ),

  -- -------------------------------------------------------
  -- BİLİŞSEL / İŞLEM YÜKÜ
  -- Bunlar AI analizleri için yardımcı özelliklerdir.
  -- -------------------------------------------------------

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

  -- -------------------------------------------------------
  -- DENETİM DURUMU
  -- -------------------------------------------------------

  review_status text NOT NULL DEFAULT 'pending'
    CHECK (
      review_status IN (
        'pending',
        'ai_reviewed',
        'needs_review',
        'human_reviewed',
        'approved',
        'rejected',
        'needs_recalibration'
      )
    ),

  calibration_status text NOT NULL DEFAULT 'unverified'
    CHECK (
      calibration_status IN (
        'unverified',
        'collecting_data',
        'calibrated',
        'needs_recalibration',
        'insufficient_data'
      )
    ),

  is_current boolean NOT NULL DEFAULT true,

  is_approved_for_scoring boolean NOT NULL DEFAULT false,

  analysis_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_by_agent_id uuid
    REFERENCES public.ai_agents(id)
    ON DELETE SET NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    question_id,
    analysis_version
  )
);

-- Her soru için yalnızca bir current profil bulunabilir.
CREATE UNIQUE INDEX IF NOT EXISTS
idx_question_solve_time_current_unique
ON public.question_solve_time_profiles(question_id)
WHERE is_current = true;

CREATE INDEX IF NOT EXISTS
idx_question_solve_time_question
ON public.question_solve_time_profiles(question_id);

CREATE INDEX IF NOT EXISTS
idx_question_solve_time_review
ON public.question_solve_time_profiles(
  review_status,
  calibration_status
);

CREATE INDEX IF NOT EXISTS
idx_question_solve_time_scoring
ON public.question_solve_time_profiles(
  question_id,
  is_approved_for_scoring
)
WHERE is_current = true;

ALTER TABLE public.question_solve_time_profiles
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS
trigger_question_solve_time_profiles_updated_at
ON public.question_solve_time_profiles;

CREATE TRIGGER
trigger_question_solve_time_profiles_updated_at
BEFORE UPDATE ON public.question_solve_time_profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. AI STAGING SÜRE PROFİLLERİ
-- AI tarafından üretilen veya PDF'den gelen soru,
-- ana soru bankasına geçmeden süre kontrolünden geçebilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.staging_solve_time_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  staging_question_id uuid NOT NULL
    REFERENCES public.ai_question_staging(id)
    ON DELETE CASCADE,

  estimated_reading_time_seconds numeric(8,2) NOT NULL DEFAULT 0
    CHECK (estimated_reading_time_seconds >= 0),

  estimated_reasoning_time_seconds numeric(8,2) NOT NULL DEFAULT 0
    CHECK (estimated_reasoning_time_seconds >= 0),

  estimated_visual_analysis_time_seconds numeric(8,2) NOT NULL DEFAULT 0
    CHECK (estimated_visual_analysis_time_seconds >= 0),

  estimated_calculation_time_seconds numeric(8,2) NOT NULL DEFAULT 0
    CHECK (estimated_calculation_time_seconds >= 0),

  estimated_other_time_seconds numeric(8,2) NOT NULL DEFAULT 0
    CHECK (estimated_other_time_seconds >= 0),

  estimated_total_time_seconds numeric(10,2)
    GENERATED ALWAYS AS (
      estimated_reading_time_seconds
      + estimated_reasoning_time_seconds
      + estimated_visual_analysis_time_seconds
      + estimated_calculation_time_seconds
      + estimated_other_time_seconds
    ) STORED,

  recommended_time_limit_seconds numeric(10,2)
    CHECK (
      recommended_time_limit_seconds IS NULL
      OR recommended_time_limit_seconds > 0
    ),

  reading_time_confidence numeric(5,4)
    CHECK (
      reading_time_confidence IS NULL
      OR reading_time_confidence BETWEEN 0 AND 1
    ),

  reasoning_time_confidence numeric(5,4)
    CHECK (
      reasoning_time_confidence IS NULL
      OR reasoning_time_confidence BETWEEN 0 AND 1
    ),

  visual_time_confidence numeric(5,4)
    CHECK (
      visual_time_confidence IS NULL
      OR visual_time_confidence BETWEEN 0 AND 1
    ),

  calculation_time_confidence numeric(5,4)
    CHECK (
      calculation_time_confidence IS NULL
      OR calculation_time_confidence BETWEEN 0 AND 1
    ),

  total_time_confidence numeric(5,4)
    CHECK (
      total_time_confidence IS NULL
      OR total_time_confidence BETWEEN 0 AND 1
    ),

  feature_analysis jsonb NOT NULL DEFAULT '{}'::jsonb,

  review_status text NOT NULL DEFAULT 'pending'
    CHECK (
      review_status IN (
        'pending',
        'ai_reviewed',
        'needs_review',
        'approved',
        'rejected'
      )
    ),

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (staging_question_id)
);

ALTER TABLE public.staging_solve_time_profiles
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS
trigger_staging_solve_time_profiles_updated_at
ON public.staging_solve_time_profiles;

CREATE TRIGGER
trigger_staging_solve_time_profiles_updated_at
BEFORE UPDATE ON public.staging_solve_time_profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. BAĞIMSIZ SÜRE DENETİMLERİ
-- İlk AI'nın tahminini başka AI veya insan kontrol eder.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_solve_time_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  solve_time_profile_id uuid NOT NULL
    REFERENCES public.question_solve_time_profiles(id)
    ON DELETE CASCADE,

  reviewer_type text NOT NULL
    CHECK (
      reviewer_type IN (
        'ai',
        'human',
        'system'
      )
    ),

  reviewer_agent_id uuid
    REFERENCES public.ai_agents(id)
    ON DELETE SET NULL,

  reviewer_user_id uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  decision text NOT NULL
    CHECK (
      decision IN (
        'approve',
        'request_changes',
        'reject',
        'recalibrate'
      )
    ),

  reviewed_reading_time_seconds numeric(8,2)
    CHECK (
      reviewed_reading_time_seconds IS NULL
      OR reviewed_reading_time_seconds >= 0
    ),

  reviewed_reasoning_time_seconds numeric(8,2)
    CHECK (
      reviewed_reasoning_time_seconds IS NULL
      OR reviewed_reasoning_time_seconds >= 0
    ),

  reviewed_visual_time_seconds numeric(8,2)
    CHECK (
      reviewed_visual_time_seconds IS NULL
      OR reviewed_visual_time_seconds >= 0
    ),

  reviewed_calculation_time_seconds numeric(8,2)
    CHECK (
      reviewed_calculation_time_seconds IS NULL
      OR reviewed_calculation_time_seconds >= 0
    ),

  reviewed_total_time_seconds numeric(10,2)
    CHECK (
      reviewed_total_time_seconds IS NULL
      OR reviewed_total_time_seconds >= 0
    ),

  confidence_score numeric(5,4)
    CHECK (
      confidence_score IS NULL
      OR confidence_score BETWEEN 0 AND 1
    ),

  difference_percent numeric(8,2),

  notes text,

  review_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    reviewer_type <> 'ai'
    OR reviewer_agent_id IS NOT NULL
  ),

  CHECK (
    reviewer_type <> 'human'
    OR reviewer_user_id IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS
idx_question_solve_time_reviews_profile
ON public.question_solve_time_reviews(
  solve_time_profile_id,
  created_at DESC
);

ALTER TABLE public.question_solve_time_reviews
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 4. GERÇEK ÖĞRENCİ VERİSİNDEN SORU BAZLI İSTATİSTİK
--
-- Öğrenci kimlikleri burada tutulmaz.
-- Toplu/aggregate istatistik tutulur.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_solve_time_statistics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  question_id uuid NOT NULL
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  -- İstatistik hangi öğrenci grubundan geldi?
  cohort_type text NOT NULL DEFAULT 'all'
    CHECK (
      cohort_type IN (
        'all',
        'grade',
        'difficulty_segment',
        'performance_segment',
        'competition',
        'practice',
        'training',
        'custom'
      )
    ),

  cohort_key text NOT NULL DEFAULT 'all',

  sample_size integer NOT NULL DEFAULT 0
    CHECK (sample_size >= 0),

  correct_sample_size integer NOT NULL DEFAULT 0
    CHECK (correct_sample_size >= 0),

  wrong_sample_size integer NOT NULL DEFAULT 0
    CHECK (wrong_sample_size >= 0),

  pass_sample_size integer NOT NULL DEFAULT 0
    CHECK (pass_sample_size >= 0),

  -- -------------------------------------------------------
  -- GERÇEK SÜRE DAĞILIMI
  -- Ortalama yerine medyan özellikle tutulur.
  -- -------------------------------------------------------

  p10_time_seconds numeric(10,2)
    CHECK (
      p10_time_seconds IS NULL
      OR p10_time_seconds >= 0
    ),

  p25_time_seconds numeric(10,2)
    CHECK (
      p25_time_seconds IS NULL
      OR p25_time_seconds >= 0
    ),

  median_time_seconds numeric(10,2)
    CHECK (
      median_time_seconds IS NULL
      OR median_time_seconds >= 0
    ),

  p75_time_seconds numeric(10,2)
    CHECK (
      p75_time_seconds IS NULL
      OR p75_time_seconds >= 0
    ),

  p90_time_seconds numeric(10,2)
    CHECK (
      p90_time_seconds IS NULL
      OR p90_time_seconds >= 0
    ),

  average_time_seconds numeric(10,2)
    CHECK (
      average_time_seconds IS NULL
      OR average_time_seconds >= 0
    ),

  correct_median_time_seconds numeric(10,2)
    CHECK (
      correct_median_time_seconds IS NULL
      OR correct_median_time_seconds >= 0
    ),

  wrong_median_time_seconds numeric(10,2)
    CHECK (
      wrong_median_time_seconds IS NULL
      OR wrong_median_time_seconds >= 0
    ),

  -- Aykırı veriler temizlendikten sonraki medyan.
  cleaned_median_time_seconds numeric(10,2)
    CHECK (
      cleaned_median_time_seconds IS NULL
      OR cleaned_median_time_seconds >= 0
    ),

  excluded_outlier_count integer NOT NULL DEFAULT 0
    CHECK (excluded_outlier_count >= 0),

  statistical_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  calculated_at timestamptz NOT NULL DEFAULT now(),

  UNIQUE (
    question_id,
    cohort_type,
    cohort_key
  ),

  CHECK (
    correct_sample_size
    + wrong_sample_size
    + pass_sample_size
    <= sample_size
  )
);

CREATE INDEX IF NOT EXISTS
idx_question_solve_time_statistics_question
ON public.question_solve_time_statistics(question_id);

ALTER TABLE public.question_solve_time_statistics
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 5. AI TAHMİNİ - GERÇEK VERİ KALİBRASYONU
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_solve_time_calibrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  question_id uuid NOT NULL
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  solve_time_profile_id uuid NOT NULL
    REFERENCES public.question_solve_time_profiles(id)
    ON DELETE CASCADE,

  statistics_id uuid
    REFERENCES public.question_solve_time_statistics(id)
    ON DELETE SET NULL,

  ai_estimated_seconds numeric(10,2) NOT NULL
    CHECK (ai_estimated_seconds >= 0),

  observed_median_seconds numeric(10,2)
    CHECK (
      observed_median_seconds IS NULL
      OR observed_median_seconds >= 0
    ),

  absolute_difference_seconds numeric(10,2),

  difference_percent numeric(10,2),

  calibration_decision text NOT NULL DEFAULT 'insufficient_data'
    CHECK (
      calibration_decision IN (
        'keep',
        'adjust_up',
        'adjust_down',
        'manual_review',
        'insufficient_data'
      )
    ),

  proposed_total_time_seconds numeric(10,2)
    CHECK (
      proposed_total_time_seconds IS NULL
      OR proposed_total_time_seconds >= 0
    ),

  minimum_sample_required integer NOT NULL DEFAULT 30
    CHECK (minimum_sample_required > 0),

  reason text,

  calibration_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_by_agent_id uuid
    REFERENCES public.ai_agents(id)
    ON DELETE SET NULL,

  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS
idx_solve_time_calibrations_question
ON public.question_solve_time_calibrations(
  question_id,
  created_at DESC
);

ALTER TABLE public.question_solve_time_calibrations
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 6. SORUYA ÖZEL YARIŞMA SÜRE BANTLARI
--
-- Artık aynı "orta zorluk" soruların hepsi aynı süre
-- bantlarını kullanmak zorunda değil.
--
-- Her soru kendi süre profiline sahip olabilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.question_scoring_time_bands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  question_id uuid NOT NULL
    REFERENCES public.questions(id)
    ON DELETE CASCADE,

  solve_time_profile_id uuid NOT NULL
    REFERENCES public.question_solve_time_profiles(id)
    ON DELETE CASCADE,

  scoring_rule_set_id uuid NOT NULL
    REFERENCES public.scoring_rule_sets(id)
    ON DELETE CASCADE,

  band_code text NOT NULL,

  band_name text NOT NULL,

  min_time_ms integer NOT NULL DEFAULT 0
    CHECK (min_time_ms >= 0),

  max_time_ms integer
    CHECK (
      max_time_ms IS NULL
      OR max_time_ms > 0
    ),

  sort_order integer NOT NULL DEFAULT 0,

  is_active boolean NOT NULL DEFAULT true,

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now(),

  CHECK (
    max_time_ms IS NULL
    OR max_time_ms > min_time_ms
  ),

  UNIQUE (
    question_id,
    scoring_rule_set_id,
    band_code
  )
);

CREATE INDEX IF NOT EXISTS
idx_question_scoring_time_bands_lookup
ON public.question_scoring_time_bands(
  question_id,
  scoring_rule_set_id,
  sort_order
);

ALTER TABLE public.question_scoring_time_bands
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 7. PROFİL ONAY KORUMASI
--
-- Güvenilirliği düşük veya hiç gözden geçirilmemiş profil
-- doğrudan skorlamada kullanılamasın.
-- =========================================================

CREATE OR REPLACE FUNCTION public.validate_solve_time_profile_for_scoring()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

  IF NEW.is_approved_for_scoring = true THEN

    IF NEW.review_status NOT IN (
      'human_reviewed',
      'approved'
    ) THEN
      RAISE EXCEPTION
        'Solve time profile must be reviewed before scoring approval.';
    END IF;

    IF NEW.estimated_total_time_seconds <= 0 THEN
      RAISE EXCEPTION
        'Estimated total solve time must be greater than zero.';
    END IF;

    IF NEW.total_time_confidence IS NULL
       OR NEW.total_time_confidence < 0.70 THEN
      RAISE EXCEPTION
        'Solve time confidence is too low for scoring use.';
    END IF;

  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS
trigger_validate_solve_time_profile_for_scoring
ON public.question_solve_time_profiles;

CREATE TRIGGER
trigger_validate_solve_time_profile_for_scoring
BEFORE INSERT OR UPDATE
ON public.question_solve_time_profiles
FOR EACH ROW
EXECUTE FUNCTION public.validate_solve_time_profile_for_scoring();


-- =========================================================
-- 8. SORU SÜRE PROFİLİ ÖZET VIEW
-- Admin paneli için kullanışlı.
-- =========================================================

CREATE OR REPLACE VIEW public.question_solve_time_overview AS
SELECT
  q.id AS question_id,
  q.question_code,

  p.id AS solve_time_profile_id,
  p.analysis_version,

  p.estimated_reading_time_seconds,
  p.estimated_reasoning_time_seconds,
  p.estimated_visual_analysis_time_seconds,
  p.estimated_calculation_time_seconds,
  p.estimated_other_time_seconds,
  p.estimated_total_time_seconds,

  p.recommended_time_limit_seconds,

  p.total_time_confidence,

  p.review_status,
  p.calibration_status,

  p.is_approved_for_scoring,

  s.sample_size,
  s.median_time_seconds,
  s.correct_median_time_seconds,
  s.cleaned_median_time_seconds,

  CASE
    WHEN s.cleaned_median_time_seconds IS NULL
      OR p.estimated_total_time_seconds = 0
    THEN NULL

    ELSE ROUND(
      (
        (
          s.cleaned_median_time_seconds
          - p.estimated_total_time_seconds
        )
        / p.estimated_total_time_seconds
      ) * 100,
      2
    )
  END AS observed_difference_percent

FROM public.questions q

LEFT JOIN public.question_solve_time_profiles p
  ON p.question_id = q.id
 AND p.is_current = true

LEFT JOIN public.question_solve_time_statistics s
  ON s.question_id = q.id
 AND s.cohort_type = 'all'
 AND s.cohort_key = 'all';


-- =========================================================
-- 9. ADMIN RLS POLİTİKALARI
-- 014'te kurulan yetki sistemini kullanır.
-- =========================================================

CREATE POLICY "admins manage question solve time profiles"
ON public.question_solve_time_profiles
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
);


CREATE POLICY "admins manage staging solve time profiles"
ON public.staging_solve_time_profiles
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
);


CREATE POLICY "admins manage solve time reviews"
ON public.question_solve_time_reviews
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.approve')
  OR public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.approve')
  OR public.current_user_has_admin_permission('ai.manage')
);


CREATE POLICY "admins manage solve time statistics"
ON public.question_solve_time_statistics
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
);


CREATE POLICY "admins manage solve time calibrations"
ON public.question_solve_time_calibrations
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
);


CREATE POLICY "admins manage question scoring time bands"
ON public.question_scoring_time_bands
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
);