-- 013_admin_roles_and_permissions.sql
-- Altın Kalemler admin roller ve yetki altyapısı.

-- =========================================================
-- 1. ADMIN ROLLERİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.admin_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  role_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_roles
ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trigger_admin_roles_set_updated_at
ON public.admin_roles;

CREATE TRIGGER trigger_admin_roles_set_updated_at
BEFORE UPDATE ON public.admin_roles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. YETKİLER
-- =========================================================

CREATE TABLE IF NOT EXISTS public.admin_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  permission_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_permissions
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 3. ROL -> YETKİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.admin_role_permissions (
  role_id uuid NOT NULL
    REFERENCES public.admin_roles(id)
    ON DELETE CASCADE,

  permission_id uuid NOT NULL
    REFERENCES public.admin_permissions(id)
    ON DELETE CASCADE,

  created_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (role_id, permission_id)
);

ALTER TABLE public.admin_role_permissions
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 4. KULLANICI -> ADMIN ROL
-- =========================================================

CREATE TABLE IF NOT EXISTS public.admin_user_roles (
  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  role_id uuid NOT NULL
    REFERENCES public.admin_roles(id)
    ON DELETE CASCADE,

  assigned_by uuid
    REFERENCES auth.users(id)
    ON DELETE SET NULL,

  assigned_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (user_id, role_id)
);

CREATE INDEX IF NOT EXISTS idx_admin_user_roles_user
ON public.admin_user_roles(user_id);

ALTER TABLE public.admin_user_roles
ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 5. YETKİ KONTROL FONKSİYONU
-- =========================================================

CREATE OR REPLACE FUNCTION public.has_admin_permission(
  p_user_id uuid,
  p_permission_code text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_user_roles aur
    JOIN public.admin_roles ar
      ON ar.id = aur.role_id
    JOIN public.admin_role_permissions arp
      ON arp.role_id = ar.id
    JOIN public.admin_permissions ap
      ON ap.id = arp.permission_id
    WHERE aur.user_id = p_user_id
      AND ar.is_active = true
      AND ap.permission_code = p_permission_code
  );
$$;


-- =========================================================
-- 6. BAŞLANGIÇ ROLLERİ
-- =========================================================

INSERT INTO public.admin_roles (
  role_code,
  name,
  description
)
VALUES
(
  'super_admin',
  'Süper Admin',
  'Tüm yönetim yetkilerine sahip ana yönetici.'
),
(
  'content_admin',
  'İçerik Yöneticisi',
  'Soru, müfredat ve içerik yönetimi yapabilir.'
),
(
  'question_reviewer',
  'Soru Denetçisi',
  'Soruları inceleyebilir, onaylayabilir veya reddedebilir.'
),
(
  'curriculum_editor',
  'Müfredat Editörü',
  'Konu, alt konu ve kazanım yapılarını yönetebilir.'
),
(
  'copyright_reviewer',
  'Telif Denetçisi',
  'Telif, lisans ve ticari kullanım incelemelerini yapabilir.'
)
ON CONFLICT (role_code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  is_active = true;


-- =========================================================
-- 7. BAŞLANGIÇ YETKİLERİ
-- =========================================================

INSERT INTO public.admin_permissions (
  permission_code,
  name,
  description
)
VALUES
(
  'questions.view',
  'Soruları Görüntüle',
  'Admin soru kayıtlarını görüntüleyebilir.'
),
(
  'questions.edit',
  'Soruları Düzenle',
  'Soru içeriklerini düzenleyebilir.'
),
(
  'questions.approve',
  'Soruları Onayla',
  'Staging sorularını insan onayıyla onaylayabilir.'
),
(
  'questions.reject',
  'Soruları Reddet',
  'Soruları reddedebilir veya düzeltmeye gönderebilir.'
),
(
  'curriculum.manage',
  'Müfredatı Yönet',
  'Konu, alt konu ve kazanım yapılarını yönetebilir.'
),
(
  'imports.manage',
  'İçe Aktarmaları Yönet',
  'PDF ve Excel içe aktarma işlemlerini yönetebilir.'
),
(
  'ai.manage',
  'AI Sistemini Yönet',
  'AI ajan, workflow ve eşik ayarlarını yönetebilir.'
),
(
  'copyright.review',
  'Telif İncelemesi Yap',
  'Telif ve lisans kontrollerini inceleyebilir.'
),
(
  'commercial.approve',
  'Ticari Kullanımı Onayla',
  'Ticari yayın uygunluğunu onaylayabilir.'
),
(
  'users.manage',
  'Kullanıcıları Yönet',
  'Kullanıcı ve yönetici rollerini yönetebilir.'
)
ON CONFLICT (permission_code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description;


-- =========================================================
-- 8. SUPER ADMIN TÜM YETKİLER
-- =========================================================

INSERT INTO public.admin_role_permissions (
  role_id,
  permission_id
)
SELECT
  ar.id,
  ap.id
FROM public.admin_roles ar
CROSS JOIN public.admin_permissions ap
WHERE ar.role_code = 'super_admin'
ON CONFLICT DO NOTHING;


-- =========================================================
-- 9. QUESTION REVIEWER YETKİLERİ
-- =========================================================

INSERT INTO public.admin_role_permissions (
  role_id,
  permission_id
)
SELECT
  ar.id,
  ap.id
FROM public.admin_roles ar
JOIN public.admin_permissions ap
  ON ap.permission_code IN (
    'questions.view',
    'questions.approve',
    'questions.reject'
  )
WHERE ar.role_code = 'question_reviewer'
ON CONFLICT DO NOTHING;


-- =========================================================
-- 10. CURRICULUM EDITOR YETKİLERİ
-- =========================================================

INSERT INTO public.admin_role_permissions (
  role_id,
  permission_id
)
SELECT
  ar.id,
  ap.id
FROM public.admin_roles ar
JOIN public.admin_permissions ap
  ON ap.permission_code IN (
    'questions.view',
    'curriculum.manage'
  )
WHERE ar.role_code = 'curriculum_editor'
ON CONFLICT DO NOTHING;


-- =========================================================
-- 11. COPYRIGHT REVIEWER YETKİLERİ
-- =========================================================

INSERT INTO public.admin_role_permissions (
  role_id,
  permission_id
)
SELECT
  ar.id,
  ap.id
FROM public.admin_roles ar
JOIN public.admin_permissions ap
  ON ap.permission_code IN (
    'questions.view',
    'copyright.review',
    'commercial.approve'
  )
WHERE ar.role_code = 'copyright_reviewer'
ON CONFLICT DO NOTHING;


-- =========================================================
-- 12. CONTENT ADMIN YETKİLERİ
-- =========================================================

INSERT INTO public.admin_role_permissions (
  role_id,
  permission_id
)
SELECT
  ar.id,
  ap.id
FROM public.admin_roles ar
JOIN public.admin_permissions ap
  ON ap.permission_code IN (
    'questions.view',
    'questions.edit',
    'questions.approve',
    'questions.reject',
    'curriculum.manage',
    'imports.manage',
    'copyright.review'
  )
WHERE ar.role_code = 'content_admin'
ON CONFLICT DO NOTHING;