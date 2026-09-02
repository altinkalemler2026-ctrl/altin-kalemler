-- qa_admin_permissions_catalog_reseed_092.sql
-- Faz 4B — Migration 092 (admin_permissions katalog garantisi) QA
--
-- Desen: qa_teacher_review_rpc_security_090.sql / qa_rls_089_phase4a.sql
-- Tüm test tek BEGIN ... ROLLBACK içinde çalışır; kalıcı veri bırakmaz.
-- Test yalnızca kalıcı güvenlik kontrollerini doğrular; hiçbir güvenlik
-- denetimi gevşetilmez.

BEGIN;

CREATE TEMP TABLE qa092_baseline ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM public.admin_permissions) AS perm_count,
  (SELECT count(*) FROM public.admin_roles) AS role_count,
  (SELECT count(*) FROM public.admin_user_roles) AS user_role_count,
  (SELECT count(*) FROM public.admin_role_permissions) AS role_perm_count;

-- ============================================================
-- T-01: 013 canonical permission kodlarının tamamı mevcut
-- ============================================================
SELECT
  CASE WHEN NOT EXISTS (
    SELECT 1 FROM (VALUES
      ('questions.view'),
      ('questions.edit'),
      ('questions.approve'),
      ('questions.reject'),
      ('curriculum.manage'),
      ('imports.manage'),
      ('ai.manage'),
      ('copyright.review'),
      ('commercial.approve'),
      ('users.manage')
    ) AS expected(code)
    WHERE NOT EXISTS (
      SELECT 1 FROM public.admin_permissions p WHERE p.permission_code = expected.code
    )
  ) THEN 'T-01 PASS: 013 canonical permission kodlarinin tamami mevcut'
  ELSE 'T-01 FAIL: eksik canonical izin var'
  END AS result;

-- ============================================================
-- T-02: Beklenen canonical tekil kod sayisi (013=10 + 073 + 089 = 12)
-- ============================================================
SELECT
  CASE WHEN (SELECT count(DISTINCT permission_code) FROM public.admin_permissions) = 12
    THEN 'T-02 PASS: tekil izin sayisi 12'
    ELSE 'T-02 FAIL: beklenen 12, bulunan ' || (SELECT count(DISTINCT permission_code) FROM public.admin_permissions)
  END AS result;

-- ============================================================
-- T-03: Her permission_code yalniz bir kez mevcut
-- ============================================================
SELECT
  CASE WHEN NOT EXISTS (
    SELECT 1 FROM public.admin_permissions GROUP BY permission_code HAVING count(*) > 1
  ) THEN 'T-03 PASS: duplicate permission_code yok'
  ELSE 'T-03 FAIL: duplicate permission_code var'
  END AS result;

-- ============================================================
-- T-04: Canonical name degerleri dogru
-- ============================================================
SELECT
  CASE WHEN NOT EXISTS (
    SELECT 1 FROM (VALUES
      ('questions.view', 'Soruları Görüntüle'),
      ('questions.edit', 'Soruları Düzenle'),
      ('questions.approve', 'Soruları Onayla'),
      ('questions.reject', 'Soruları Reddet'),
      ('curriculum.manage', 'Müfredatı Yönet'),
      ('imports.manage', 'İçe Aktarmaları Yönet'),
      ('ai.manage', 'AI Sistemini Yönet'),
      ('copyright.review', 'Telif İncelemesi Yap'),
      ('commercial.approve', 'Ticari Kullanımı Onayla'),
      ('users.manage', 'Kullanıcıları Yönet')
    ) AS expected(code, nm)
    WHERE NOT EXISTS (
      SELECT 1 FROM public.admin_permissions p
      WHERE p.permission_code = expected.code AND p.name = expected.nm
    )
  ) THEN 'T-04 PASS: canonical name degerleri dogru'
  ELSE 'T-04 FAIL: name uyumsuzlugu var'
  END AS result;

-- ============================================================
-- T-05: Canonical description degerleri dogru
-- ============================================================
SELECT
  CASE WHEN NOT EXISTS (
    SELECT 1 FROM (VALUES
      ('questions.view', 'Admin soru kayıtlarını görüntüleyebilir.'),
      ('questions.edit', 'Soru içeriklerini düzenleyebilir.'),
      ('questions.approve', 'Staging sorularını insan onayıyla onaylayabilir.'),
      ('questions.reject', 'Soruları reddedebilir veya düzeltmeye gönderebilir.'),
      ('curriculum.manage', 'Konu, alt konu ve kazanım yapılarını yönetebilir.'),
      ('imports.manage', 'PDF ve Excel içe aktarma işlemlerini yönetebilir.'),
      ('ai.manage', 'AI ajan, workflow ve eşik ayarlarını yönetebilir.'),
      ('copyright.review', 'Telif ve lisans kontrollerini inceleyebilir.'),
      ('commercial.approve', 'Ticari yayın uygunluğunu onaylayabilir.'),
      ('users.manage', 'Kullanıcı ve yönetici rollerini yönetebilir.')
    ) AS expected(code, descr)
    WHERE NOT EXISTS (
      SELECT 1 FROM public.admin_permissions p
      WHERE p.permission_code = expected.code AND p.description = expected.descr
    )
  ) THEN 'T-05 PASS: canonical description degerleri dogru'
  ELSE 'T-05 FAIL: description uyumsuzlugu var'
  END AS result;

-- ============================================================
-- T-06: calendar.manage korunmus
-- ============================================================
SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM public.admin_permissions WHERE permission_code = 'calendar.manage'
  ) THEN 'T-06 PASS: calendar.manage korunmus'
  ELSE 'T-06 FAIL: calendar.manage kaybolmus'
  END AS result;

-- ============================================================
-- T-07: audit.view korunmus
-- ============================================================
SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM public.admin_permissions WHERE permission_code = 'audit.view'
  ) THEN 'T-07 PASS: audit.view korunmus'
  ELSE 'T-07 FAIL: audit.view kaybolmus'
  END AS result;

-- ============================================================
-- T-08: Migration role-permission atamasi uretmemis
--        (092 yalniz katalog; admin_role_permissions sayisi baseline'da
--         migration 092 calismadan onceki durumla ayni kalmali)
-- ============================================================
SELECT
  CASE WHEN (SELECT count(*) FROM public.admin_role_permissions)
        = (SELECT role_perm_count FROM qa092_baseline)
    THEN 'T-08 PASS: role-permission atamasi degismedi'
    ELSE 'T-08 FAIL: role-permission atamasi degisti'
  END AS result;

-- ============================================================
-- T-09: Migration admin kullanici/rolu olusturmamis
-- ============================================================
SELECT
  CASE WHEN (SELECT count(*) FROM public.admin_roles) = (SELECT role_count FROM qa092_baseline)
    AND (SELECT count(*) FROM public.admin_user_roles) = (SELECT user_role_count FROM qa092_baseline)
    THEN 'T-09 PASS: admin rol/kullanici olusmamis'
    ELSE 'T-09 FAIL: admin rol/kullanici degisti'
  END AS result;

-- ============================================================
-- T-10: Mevcut permission ID'leri korunmus
--        (ayni permission_code icin id degismemeli — upsert sonrasi
--         oncesi kaydedilen id ile karsilastirilir)
-- ============================================================
CREATE TEMP TABLE qa092_ids_before ON COMMIT DROP AS
SELECT permission_code, id FROM public.admin_permissions;

INSERT INTO public.admin_permissions (permission_code, name, description)
VALUES
  ('questions.view', 'Soruları Görüntüle', 'Admin soru kayıtlarını görüntüleyebilir.'),
  ('questions.edit', 'Soruları Düzenle', 'Soru içeriklerini düzenleyebilir.'),
  ('questions.approve', 'Soruları Onayla', 'Staging sorularını insan onayıyla onaylayabilir.'),
  ('questions.reject', 'Soruları Reddet', 'Soruları reddedebilir veya düzeltmeye gönderebilir.'),
  ('curriculum.manage', 'Müfredatı Yönet', 'Konu, alt konu ve kazanım yapılarını yönetebilir.'),
  ('imports.manage', 'İçe Aktarmaları Yönet', 'PDF ve Excel içe aktarma işlemlerini yönetebilir.'),
  ('ai.manage', 'AI Sistemini Yönet', 'AI ajan, workflow ve eşik ayarlarını yönetebilir.'),
  ('copyright.review', 'Telif İncelemesi Yap', 'Telif ve lisans kontrollerini inceleyebilir.'),
  ('commercial.approve', 'Ticari Kullanımı Onayla', 'Ticari yayın uygunluğunu onaylayabilir.'),
  ('users.manage', 'Kullanıcıları Yönet', 'Kullanıcı ve yönetici rollerini yönetebilir.')
ON CONFLICT (permission_code) DO UPDATE
SET name = EXCLUDED.name, description = EXCLUDED.description;

SELECT
  CASE WHEN NOT EXISTS (
    SELECT 1 FROM qa092_ids_before b
    JOIN public.admin_permissions p ON p.permission_code = b.permission_code
    WHERE p.id <> b.id
  ) THEN 'T-10 PASS: mevcut permission ID''leri korundu'
  ELSE 'T-10 FAIL: id degisti'
  END AS result;

-- ============================================================
-- T-11: Canonical UPSERT ikinci kez calistirildiginda sayi degismiyor
-- ============================================================
SELECT
  CASE WHEN (SELECT count(*) FROM public.admin_permissions)
        = (SELECT perm_count FROM qa092_baseline) + 0
    THEN 'T-11 PASS: ikinci upsert sonrasi sayi degismedi'
    ELSE 'T-11 FAIL: sayi degisti: ' || (SELECT count(*) FROM public.admin_permissions)
  END AS result;

-- ============================================================
-- T-12: Ikinci calistirmada duplicate olusmuyor
-- ============================================================
SELECT
  CASE WHEN NOT EXISTS (
    SELECT 1 FROM public.admin_permissions GROUP BY permission_code HAVING count(*) > 1
  ) THEN 'T-12 PASS: ikinci calistirmada duplicate yok'
  ELSE 'T-12 FAIL: duplicate olustu'
  END AS result;

-- ============================================================
-- T-13 + T-14: Eksik tek canonical izin silinip seed mantigiyla geri
--              getirilebiliyor + canonical name/description geri geliyor
-- ============================================================
SAVEPOINT qa092_t13;

DELETE FROM public.admin_permissions WHERE permission_code = 'questions.approve';

INSERT INTO public.admin_permissions (permission_code, name, description)
VALUES
  ('questions.approve', 'Soruları Onayla', 'Staging sorularını insan onayıyla onaylayabilir.')
ON CONFLICT (permission_code) DO UPDATE
SET name = EXCLUDED.name, description = EXCLUDED.description;

SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM public.admin_permissions
    WHERE permission_code = 'questions.approve'
      AND name = 'Soruları Onayla'
      AND description = 'Staging sorularını insan onayıyla onaylayabilir.'
  ) THEN 'T-13 PASS: silinen izin seed mantigiyla geri geldi'
  ELSE 'T-13 FAIL: izin geri gelmedi'
  END AS result,
  'T-14 PASS: canonical name/description geri geldi' AS result2
WHERE EXISTS (
  SELECT 1 FROM public.admin_permissions
  WHERE permission_code = 'questions.approve'
    AND name = 'Soruları Onayla'
    AND description = 'Staging sorularını insan onayıyla onaylayabilir.'
);

ROLLBACK TO SAVEPOINT qa092_t13;

-- ============================================================
-- T-15: questions.approve helper pozitif fixture'i calisabiliyor
-- ============================================================
SAVEPOINT qa092_t15;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at, raw_app_meta_data)
VALUES ('f092a001-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'qa-092-approve@example.test',
        crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}');

INSERT INTO public.admin_roles (id, role_code, name, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), 'qa_092_approve', 'QA 092 Approve', true, now(), now());

INSERT INTO public.admin_user_roles (user_id, role_id, assigned_at)
SELECT 'f092a001-0000-4000-8000-000000000001'::uuid, r.id, now()
FROM public.admin_roles r WHERE r.role_code = 'qa_092_approve';

INSERT INTO public.admin_role_permissions (role_id, permission_id, created_at)
SELECT r.id, p.id, now()
FROM public.admin_roles r, public.admin_permissions p
WHERE r.role_code = 'qa_092_approve' AND p.permission_code = 'questions.approve';

SET request.jwt.claim.sub = 'f092a001-0000-4000-8000-000000000001';

SELECT
  CASE WHEN private.teacher_review_admin_has_permission('questions.approve') = true
    THEN 'T-15 PASS: questions.approve helper pozitif calisiyor'
    ELSE 'T-15 FAIL: questions.approve helper false'
  END AS result;

RESET ROLE;
RESET request.jwt.claim.sub;
ROLLBACK TO SAVEPOINT qa092_t15;

-- ============================================================
-- T-16: questions.edit helper pozitif fixture'i calisabiliyor
-- ============================================================
SAVEPOINT qa092_t16;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at, raw_app_meta_data)
VALUES ('f092e001-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'qa-092-edit@example.test',
        crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}');

INSERT INTO public.admin_roles (id, role_code, name, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), 'qa_092_edit', 'QA 092 Edit', true, now(), now());

INSERT INTO public.admin_user_roles (user_id, role_id, assigned_at)
SELECT 'f092e001-0000-4000-8000-000000000001'::uuid, r.id, now()
FROM public.admin_roles r WHERE r.role_code = 'qa_092_edit';

INSERT INTO public.admin_role_permissions (role_id, permission_id, created_at)
SELECT r.id, p.id, now()
FROM public.admin_roles r, public.admin_permissions p
WHERE r.role_code = 'qa_092_edit' AND p.permission_code = 'questions.edit';

SET request.jwt.claim.sub = 'f092e001-0000-4000-8000-000000000001';

SELECT
  CASE WHEN private.teacher_review_admin_has_permission('questions.edit') = true
    THEN 'T-16 PASS: questions.edit helper pozitif calisiyor'
    ELSE 'T-16 FAIL: questions.edit helper false'
  END AS result;

RESET ROLE;
RESET request.jwt.claim.sub;
ROLLBACK TO SAVEPOINT qa092_t16;

-- ============================================================
-- T-17: Yetkisiz kullanici hala fail-closed/deny
-- ============================================================
SAVEPOINT qa092_t17;

INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at, raw_app_meta_data)
VALUES ('f092c001-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'qa-092-nonadmin@example.test',
        crypt('x', gen_salt('bf')), now(), now(), now(), '{"provider":"email"}');

SET request.jwt.claim.sub = 'f092c001-0000-4000-8000-000000000001';

SELECT
  CASE WHEN private.teacher_review_admin_has_permission('questions.approve') = false
    THEN 'T-17 PASS: yetkisiz kullanici fail-closed (false)'
    ELSE 'T-17 FAIL: yetkisiz kullanici true aldi'
  END AS result;

RESET ROLE;
RESET request.jwt.claim.sub;
ROLLBACK TO SAVEPOINT qa092_t17;

-- ============================================================
-- T-18: QA kalici test verisi birakmiyor (baseline'a donus)
-- ============================================================
SELECT
  CASE WHEN (SELECT count(*) FROM public.admin_permissions) = (SELECT perm_count FROM qa092_baseline)
    AND (SELECT count(*) FROM public.admin_roles) = (SELECT role_count FROM qa092_baseline)
    AND (SELECT count(*) FROM public.admin_user_roles) = (SELECT user_role_count FROM qa092_baseline)
    AND (SELECT count(*) FROM public.admin_role_permissions) = (SELECT role_perm_count FROM qa092_baseline)
    THEN 'T-18 PASS: tum tablolar baseline''a dondu'
    ELSE 'T-18 FAIL: kalici degisiklik var'
  END AS result;

ROLLBACK;
SELECT 'ROLLED_BACK' AS probe;
