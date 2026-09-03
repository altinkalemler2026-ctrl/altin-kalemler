-- ============================================================
-- 093_student_profile_grade_update_hardening.sql
-- Altın Kalemler - Öğrenci sınıf değişikliği güvenlik sertleştirmesi
--
-- SORUN:
--   001_auth_foundation, authenticated rolüne student_profiles
--   üzerinde TABLO-seviyeli UPDATE verir (GRANT SELECT, INSERT,
--   UPDATE). RLS politikası "update_own" yalnız SATIR kapsamını
--   sınırlar (kendi satırı); kolon kapsamını sınırlamaz.
--   Sonuç: öğrenci doğrudan Supabase/API üzerinden kendi
--   grade_level değerini değiştirebilir ve böylece kayıtlı
--   olmadığı sınıfın ders/konu/kazanım ve antrenman içeriğine
--   erişebilir (select_training_questions ve join_matchmaking_queue
--   sınıfı bu profilden türetir).
--
-- ÇÖZÜM — KOLON-SEVİYELİ AYRICALIK (en az riskli seçenek):
--   1) Tablo-seviyeli UPDATE, authenticated'dan geri alınır.
--   2) Yalnız nickname kolonu için kolon-seviyeli UPDATE verilir.
--      (Öğrencinin bugün meşru güncelleyebildiği tek alan budur;
--      uygulama kodunda student_profiles UPDATE çağrısı yoktur,
--      auth/callback yalnız profil YOKSA INSERT yapar.)
--   3) grade_level, schedule_profile_id, id ve zaman damgaları
--      artık öğrenci tarafından güncellenemez (fail-closed).
--   4) anon zaten 001'de tüm ayrıcalıklardan arındırılmıştı;
--      savunma derinliği için UPDATE ayrıca yine reddedilir.
--
-- NEDEN KOLON AYRICALIĞI (alternatiflere karşı):
--   - Koruyucu trigger yerine: ayrıcalık, RLS'in de altındaki
--     yetki katmanında uygulanır; rol/claims sezgisel kuralları,
--     SECURITY DEFINER yüzeyi veya tetikleyici sıralaması yoktur.
--   - Güvenli RPC yerine: meşru bir öğrenci profil-güncelleme
--     ürünü olmadığından yeni ürün yüzeyi açılmaz.
--   - Kısıtlı bir kolon içeren her UPDATE ifadesi BÜTÜNÜYLE
--     reddedilir (SQLSTATE 42501): işlem atomiktir, satırın
--     izinli kolonları kısmen değişemez.
--   - service_role / tablo sahibi etkilenmez; admin/service-role
--     yönetim yolu (087/088 salt-okunur admin okuması + 083
--     SECURITY DEFINER auth trigger'ı) aynen çalışır.
--   - RLS "update_own" politikası satır-kapsamı korumaya devam
--     eder; iki katman birlikte fail-closed davranır.
--
-- IDEMPOTENT: REVOKE/GRANT tekrar çalıştırılabilir.
-- Migration type: FORWARD ONLY. Mevcut migration'lar değişmez.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Tablo-seviyeli UPDATE geri alınıyor (authenticated + anon).
-- ------------------------------------------------------------
REVOKE UPDATE ON TABLE public.student_profiles FROM authenticated;
REVOKE UPDATE ON TABLE public.student_profiles FROM anon;

-- ------------------------------------------------------------
-- 2. Öğrenciye yalnız nickname için kolon-seviyeli UPDATE.
-- ------------------------------------------------------------
GRANT UPDATE (nickname) ON TABLE public.student_profiles TO authenticated;

COMMENT ON TABLE public.student_profiles IS
  'Ogrenci profili. 093: authenticated yalniz nickname kolonunu guncelleyebilir; grade_level/schedule_profile_id degisimi yalniz service_role/tablo sahibi icin aciktir (fail-closed).';

COMMIT;
