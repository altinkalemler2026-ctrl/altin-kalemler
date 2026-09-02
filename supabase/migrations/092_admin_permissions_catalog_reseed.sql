-- 092_admin_permissions_catalog_reseed.sql
-- Faz 4B — Admin Permissions Katalog Garantisi
--
-- NEDEN GEREKLİ:
--   Canlı (hosted) şema dump'ı (live_dump.sql) yalnızca şema içerir; hiçbir
--   veri satırı taşımaz (0 COPY bloğu). Bu nedenle şema-only restore yapan
--   izole prova ortamlarında (rehearsal DB) migration 013'ün admin_permissions
--   katalog seed'i (10 canonical izin) bulunmaz; yalnız sonraki migration'ların
--   kendi eklediği kodlar (073: calendar.manage, 089: audit.view) mevcut olur.
--   Aynı drift riski hosted ortamında da vardır: dump veri taşımadığından
--   hosted admin_permissions kataloğunun bütünlüğü bu migration ile garanti
--   altına alınır.
--
-- KAPSAM (minimum ayrıcalık):
--   - Yalnız migration 013'ün kanıtlanmış 10 canonical izni (satır 178-237).
--   - calendar.manage (073) ve audit.view (089) sahipliği kendi migration'larında
--     kalır; burada kopyalanmaz.
--   - ON CONFLICT (permission_code) DO UPDATE: 013'ün kendi davranışı ile birebir
--     aynı; name/description canonical değerlerle güncel tutulur.
--   - Mevcut kayıtların ID'leri korunur; yeni UUID yalnız eksik kayıtlar için
--     üretilir (013'te gen_random_uuid() default'a bağlıdır).
--   - Rol-permission ataması, admin kullanıcı/rolü, RLS, policy, grant ve
--     fonksiyon değişikliği YAPILMAZ. Veri silme YOKTUR.
--
-- Idempotent: tekrar çalıştırılması satır sayısını veya ID'leri değiştirmez.

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
