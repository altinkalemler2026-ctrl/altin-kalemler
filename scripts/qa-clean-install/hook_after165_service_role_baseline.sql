-- AK-GIT-CHECKPOINT-08 — İzole temiz kurulum ÖN-KOŞUL ADIMI #3 (165 uygulandıktan
-- hemen sonra, 166 uygulanmadan önce çalıştırılır).
--
-- NEDEN (CI #83 kök neden kanıtı — docs/reports/ak-git-checkpoint-07 §16):
--   * 166_student_profile_write_convergence.sql:214-217 — fail-closed FINAL_166 5d:
--       IF NOT has_table_privilege('service_role','public.student_profiles','UPDATE')
--          OR NOT has_table_privilege('service_role','public.student_loadouts','SELECT')
--         THEN RAISE 'FINAL_166: service_role yonetim yolu bozuldu'
--   * student_loadouts'u 017 oluşturur; zincirin HİÇBİR dosyası service_role'e bu
--     tabloda GRANT vermez (017'de GRANT yok; 108 yalnız authenticated SELECT verir).
--     CANLIDA tablo, service_role'ün stok ADP üzerinden ALL aldığı modül-çağında
--     oluştu; canlı relacl olcumu: service_role=arwdDxtm/postgres (CHECKPOINT-07
--     §16.2). Taze zincirin "gelecek nesne = varsayılan-hak yok" kozmosunda (157 G
--     drift kanalı; CI ADP-parity bloğu) bu tarihsel kayıt yoktur → FINAL_166 5d
--     HER taze ortamda düşer (CI #83 step 15; yerel yeniden-üretim qa_ag07ci_b:
--     sr_sel_loadouts=false, CHAIN_FAIL 166).
--   * student_profiles UPDATE ayağı zincirde zaten üretilir (taze ölçüm: t) — bu
--     hook yalnız eksik loadouts ayağını kurar.
--
-- Güven sınırı analizi (hook_after155 emsaliyle aynı):
--   * service_role tarayıcıya açık rol DEĞİLDİR (yalnız sunucu/servis anahtarı).
--   * Verilen yetki, canlıda ÖLÇÜLMÜŞ mevcut relacl'in (arwdDxtm) birebir aynasıdır:
--     yeni bir güvenlik sınırı TANIMLANMAZ, RLS/politika değişmez.
--   * authenticated/anon'a HİÇBİR yetki verilmez; 166'nın hiçbir guard'ı
--     gevşetilmez — hook yalnız 166'nın önişlem bildirdiği canlı kalıbını taze
--     kozmoya kurar (156/157 hook'larıyla aynı sınıf).
--   * En-dar-grant değerlendirmesi: FINAL_166 5d hata vermeden önce geçer; canlı
--     sözleşme service_role'e arwdDxtm verir ve YÖNETİM/Bakım yolu (166:213 başlığı)
--     okuma+yazma bütünlüğünü varsayar. Yalnız SELECT vermek taze ile canlı arasındaki
--     service_role ACL'sini kalıcı olarak ayırır ve drift denetimlerinde yeni sapma
--     üreteceği için reddedildi; ALL, canlı ölçümün birebir aynası olduğundan
--     "gereğinden fazla" DEĞİLDİR.
--
-- FAIL-CLOSED (disposable-only): public.student_profiles'ta TEK BİR satır bile
--   tespit edilirse (canlı/hosted emaresi) RAISE ile kendini kilitler; gerçek
--   veritabanında asla yetki değiştirmez.
-- Idempotent: GRANT tekrarı hatasızdır.
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF to_regclass('public.student_profiles') IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.student_profiles LIMIT 1) THEN
    RAISE EXCEPTION 'PRE166 fail-closed: student_profiles gercek veri iceriyor — hook yalniz disposable QA/CI zinciri icindir'
      USING errcode='P0001';
  END IF;
END $$;

-- FINAL_166 5d girdisi: service_role.student_loadouts (canli relacl olcumuyle birebir:
-- arwdDxtm = INSERT SELECT UPDATE DELETE TRUNCATE REFERENCES TRIGGER)
GRANT ALL ON public.student_loadouts TO service_role;

DO $$
BEGIN
  IF NOT has_table_privilege('service_role','public.student_loadouts','SELECT')
     OR NOT has_table_privilege('service_role','public.student_profiles','UPDATE') THEN
    RAISE EXCEPTION 'PRE166 baseline dogrulamasi basarisiz: service_role yonetim yolu kurulamadi'
      USING errcode='P0001';
  END IF;
  RAISE NOTICE 'PRE166_BASELINE_OK loadouts_sr_select=t profiles_sr_update=t';
END $$;

SELECT 'PRE166_BASELINE_OK';
