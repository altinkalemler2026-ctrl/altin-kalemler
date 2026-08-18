-- 041_fix_ai_staging_copyright_schema_drift.sql
-- Altın Kalemler
--
-- 036 originality/copyright verification fonksiyonlarının beklediği
-- staging telif/ticari güvenlik alanlarını kalıcı şemaya ekler.
--
-- Güvenlik prensibi:
-- - Ticari kullanım varsayılan olarak kapalıdır.
-- - Originality doğrulamasının geçmesi tek başına ticari izin vermez.
-- - Commercial clearance ayrı kapı olarak kalır.
-- - Bu migration mevcut soruları otomatik yayınlamaz.

BEGIN;

ALTER TABLE public.ai_question_staging
  ADD COLUMN IF NOT EXISTS ownership_status text
    NOT NULL DEFAULT 'unknown'
    CHECK (
      ownership_status IN (
        'owned',
        'licensed',
        'third_party',
        'ai_original',
        'unknown'
      )
    );

ALTER TABLE public.ai_question_staging
  ADD COLUMN IF NOT EXISTS license_status text
    NOT NULL DEFAULT 'unknown'
    CHECK (
      license_status IN (
        'unknown',
        'pending',
        'approved',
        'restricted'
      )
    );

ALTER TABLE public.ai_question_staging
  ADD COLUMN IF NOT EXISTS commercial_use_allowed boolean
    NOT NULL DEFAULT false;

ALTER TABLE public.ai_question_staging
  ADD COLUMN IF NOT EXISTS copyright_risk_level text
    NOT NULL DEFAULT 'unknown'
    CHECK (
      copyright_risk_level IN (
        'unknown',
        'low',
        'medium',
        'high',
        'blocked'
      )
    );

ALTER TABLE public.ai_question_staging
  DROP CONSTRAINT IF EXISTS ai_question_staging_commercial_use_copyright_check;

ALTER TABLE public.ai_question_staging
  ADD CONSTRAINT ai_question_staging_commercial_use_copyright_check
  CHECK (
    commercial_use_allowed = false
    OR copyright_risk_level = 'low'
  );

CREATE INDEX IF NOT EXISTS idx_ai_question_staging_copyright
ON public.ai_question_staging (
  copyright_risk_level,
  commercial_use_allowed
);

UPDATE public.ai_question_staging
SET
  ownership_status = COALESCE(ownership_status, 'unknown'),
  license_status = COALESCE(license_status, 'unknown'),
  commercial_use_allowed = false,
  copyright_risk_level = COALESCE(copyright_risk_level, 'unknown'),
  metadata = COALESCE(metadata, '{}'::jsonb)
    || jsonb_build_object(
         'commercial_use_allowed', false,
         'commercial_clearance_required', true,
         'copyright_schema_repair_version', '041'
       );

UPDATE public.ai_question_staging
SET
  ownership_status = 'ai_original',
  metadata = COALESCE(metadata, '{}'::jsonb)
    || jsonb_build_object(
         'ownership_status', 'ai_original',
         'ownership_status_source', 'staging_source_ai_generated'
       )
WHERE staging_source = 'ai_generated'
  AND ownership_status = 'unknown';

UPDATE public.ai_question_staging
SET commercial_use_allowed = false
WHERE commercial_use_allowed = true
  AND copyright_risk_level <> 'low';

COMMIT;