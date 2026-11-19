-- ============================================================
-- 151_vault_single_active_membership.sql
-- Altın Kalemler — VAULT-SETUP-01 dilim: TEK KASA GARANTİSİ (dar DB çözümü)
--
-- >>> DURUM: TASLAK — UYGULANMAMIŞTIR (bu taslak
--     supabase/migrations/ DIŞINDA tutulur: onaylı provadan/GÜNLÜK
--     DB uygulamasından önce kullanıcı kararı yeterlidir — kullanıcı
--     "bir soru tek kasaya ait olur" kararını 2026-10-29'da KESİN
--     olarak verdi).
--
-- KULLANICI KARARI (kesin; yeniden karara gerek yok):
--   "Bir soru tek kasaya ait olur." — bir sorunun aynı anda yalnız
--   TEK bir kasada AKTİF üyeliği bulunabilir.
--
-- TEKNİK BULGU (kayıtlı, 2026-10-28):
--   051:74 unique(vault_id, question_id) YALNIZ aynı kasaya ikinci
--   aktif satır yazımını engeller; SORU boyutunda tek-kasa garantisi
--   YOKTUR (sınıflar-arası ikinci kasa üyeliği engellenmez).
--
-- EN DAR ÇÖZÜM (eşzamanlı yazımda güvenli):
--   Yeni partial UNIQUE INDEX: question_id üzerinde (aktif üyelikte
--   benzersiz). PostgreSQL eşzamanlı INSERT'te unique_violation döner;
--   yarış koruması DB çekirdeğiyle sağlanır (RPC guard'ına gerekrence
--   daha güvenli). Yeni RPC YOK, fonksiyon gövdesi değişimi YOK.
--
-- MEVCUT YAZMA YOLLARINI KORUR:
--   - partial: WHERE membership_status = 'active' → pasif/geçmiş
--     üyelik satırlarında çokluk serbest kalır (geçmiş kayıtlar
--     bozulmaz).
--   - ADDITIVE: tablo/RLS/iş yolları DEĞİŞMEZ; yalnız yeni index.
--   - GÜNLÜK DB'DE ÜYELİK=0 (049'dan beri) → uygulama anı veri
--     değişikliği SIFIR; mükerrer aktif üyelik yok.
--
-- ÜST/ÖZET KASA AYRI ÜYE VARSAYIMI YASAK:
--   Kısıt soru BOYUTUNDADIR: bir sorunun kök/ebeveyn/yaprak hangi
--   düzey olursa olsun en fazla 1 aktif üyeliği olabilir. Üst/özet
--   kasalara "ayrıca üye" yazılırsa unique_violation ile RED sistemi
--   bunu zorlar (1010/üretim akışı zaten tek hedefli yerleştirme
--   yapar; KULLANICI kararı §16.10.10-6).
--
-- TAŞIMA (movel) YOLU:
--   Bir soru kasalar arasında taşınacaksa mevcut aktif satır
--   membership_status='inactive' yapılıp yeni satır açılır (tek
--   satırlık UPDATE + INSERT; eşzamanlılıkta yine kısıt korur).
--
-- GERİ DÖNÜŞ (data-only): DROP INDEX IF EXISTS
--   uq_question_active_single_vault; (fonksiyon/chart değişikliği yok).
--
-- DOĞRULAMA (FINAL): index var + UNIQUE + kolon + WHERE koşulu;
-- history version='151' (146/147/148/149/150 deseni; idempotent
-- in-transaction). GUARD: question_vault_memberships (051) var +
-- question_id kolonu var + mevcut aktif üyelikte soru-boyutlu
-- mükerrerlik 0 (yoksa fail-closed: kırık geçmiş veri yüklenmez).
-- ============================================================

BEGIN;

DO $guard$
DECLARE
  v_mukerrer integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='question_vault_memberships')
  THEN
    RAISE EXCEPTION 'GUARD_151: public.question_vault_memberships yok (migration 051).';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='question_vault_memberships'
                   AND column_name='question_id')
  THEN
    RAISE EXCEPTION 'GUARD_151: question_id kolonu yok (beklenmedik şema).';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='question_vault_memberships'
                   AND column_name='membership_status')
  THEN
    RAISE EXCEPTION 'GUARD_151: membership_status kolonu yok (beklenmedik şema).';
  END IF;

  -- Aktif üyelikte soru-boyutlu mükerrerlik: index kurulamaz (veri etkisi!)
  SELECT count(*) INTO v_mukerrer FROM (
    SELECT 1 FROM public.question_vault_memberships
     WHERE membership_status = 'active'
     GROUP BY question_id HAVING count(*) > 1
  ) x;
  IF v_mukerrer <> 0 THEN
    RAISE EXCEPTION
      'GUARD_151: aktif üyelikte % soru için birden fazla kasa üyeliği var —
       index kurulamaz; taşımalar için kullanıcı kararına bağlı, fail-closed dur.',
      v_mukerrer;
  END IF;
END
$guard$;

-- EN DAR TEK-KASA GARANTİSİ
CREATE UNIQUE INDEX IF NOT EXISTS uq_question_active_single_vault
  ON public.question_vault_memberships (question_id)
  WHERE membership_status = 'active';

-- History — idempotent (146/147/148/149/150 deseni; FINAL'DEN ÖNCE:
-- FINAL_151 history kaydının VARLIĞINI doğrular, bu yüzden INSERT önce
-- olmalı; aksi halde ilk koşumda FINAL fail-closed patlar ve
-- transaction tümüyle geri sarılır → dosya hiç uygulanamaz).
insert into supabase_migrations.schema_migrations (version, name, statements)
select '151', '151_vault_single_active_membership', NULL
 where not exists (
   select 1 from supabase_migrations.schema_migrations where version = '151'
 );

DO $final$
DECLARE
  v_index_def text;
BEGIN
  -- Index var + UNIQUE + kolon + WHERE koşulu (yalnız ad kontrolü değil)
  SELECT indexdef INTO v_index_def FROM pg_indexes
   WHERE schemaname='public' AND indexname='uq_question_active_single_vault';

  IF v_index_def IS NULL
     OR v_index_def NOT LIKE 'CREATE UNIQUE%'
     OR position('(question_id)' in v_index_def) = 0
     OR position('membership_status' in v_index_def) = 0
     OR position(chr(39) || 'active' || chr(39) in v_index_def) = 0
  THEN
    RAISE EXCEPTION 'FINAL_151: index tanımı beklenmedik: % — reject.', coalesce(v_index_def, '<yok>');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '151') THEN
    RAISE EXCEPTION 'FINAL_151: history kaydı (version=151) yok — fail-closed.';
  END IF;
END
$final$;

COMMIT;
