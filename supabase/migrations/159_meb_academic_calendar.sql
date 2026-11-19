-- ============================================================
-- 159_meb_academic_calendar.sql
-- AK-MEB-VAULT-42-01 §13 sıra-159: MEB 2026–2027 takvimi + çift sayaç (ADDITIVE)
-- ============================================================
-- KAYNAK (erişim 10.11.2026; master plan §1 kanıtlarıyla birebir):
--   A) MEB 2026-2027 takvimi: meb.gov.tr haber/41057 (+ haber/41907 kademe)
--   B) MEB mesleki çalışmalar: 01.09.2026 ve 28–30.06.2027
--   C) Diyanet 2027 dinî günler: vakithesaplama.diyanet.gov.tr
--      (Ramazan Bayramı 09–11.03.2027 + arife 08.03; Kurban 16–19.05.2027 + arife 15.05)
--   Kanonik hafta tablosu: docs/reports/ak-meb-42hafta-tatil-altkonu-kasa-master-plani.md §2–§3
--   Canlı academic_weeks (salt-okunur doğrulandı): 41 satır, 2026-2027,
--   K1..K41, 14.09.2026 → 28.06.2027 (ends exclusive) — birebir örtüşür.
--
-- KAPSAM (görev AK-MEB-VAULT-42-04 + master plan §13 satır-159):
--   1) academic_weeks ADDITIVE kolonlar: week_kind
--      (teaching|partial_teaching|holiday_review|year_end_review),
--      is_instruction_week, instruction_week_number (I#), holiday_kind,
--      actual_class_days (0–5; 0.1 hassasiyet — K07 arife kanıtı 3,5),
--      partial_week_policy (advance|hold|review), new_topic_allowed,
--      new_topic_admin_approved + new_topic_approved_by/at,
--      needs_admin_review, requires_admin_activation + activated_by/at.
--   ÜÇ DURUMLU METADATA: metadata kolonları NULL = "atanmamış yıl/hafta".
--   Kontrat CHECK'leri yalnız week_kind ATANMIŞ satırları zorlar → 073
--   yönetim RPC'si gelecek yıl haftası ekleyebilir (regresyon yok);
--   okuyucu taraflar (160+) NULL'u kapalı sayar (fail-closed varsayılan).
--   2) ÇİFT SAYAÇ: K = PK (academic_year, week) — her hafta ilerler;
--      I = instruction_week_number — YALNIZ tam tatil olmayan haftalarda
--      ilerler. 2026-2027: tam tatil K10/K20/K21/K26 → 37 öğretim haftası
--      (I1–I37); K36 Kısmi-Ağır I32 (2 fiili gün, review); K42 I dışı.
--   3) meb_holiday_days: gün bazlı resmî tatil defteri. PK(holiday_date) =
--      aynı güne denk gelen tatiller TEK sayılır (19.05.2027 = Kurban 4. gün
--      + 19 Mayıs Anma Günü örneği). class_day_loss {0, 0.5, 1}: hafta sonu
--      0 (çift sayma yok: 01.05/15.05 Cmt, 16.05 Paz), arife 0.5.
--   4) K42 satırı: 28.06–02.07.2027 ÖNERİSİYLE (master plan §2/§11 — türetilmiş
--      öneri; kesin tarih yönetici onayına bağlı) year_end_review,
--      is_instruction_week=false, new_topic_allowed=false,
--      requires_admin_activation=true, activated_by/at=NULL → PASİF.
--      Çözümleyici fail-closed: aktivasyonsuz hiçbir akış K42'yi göremez.
--   5) Çözümleyici: resolve_academic_week_at(p_date) (yeni; definer; EXECUTE
--      public/anon/auth'dan REVOKE — sunucu tarafı). resolve_current_academic_period()
--      067 imzasını KORUR, inceden sarmalar; tek davranış farkı: aktivasyon
--      bekleyen (activated_at IS NULL) satır görünmez — K1..K41 aynı çözülür.
--   6) Yeni tablo ACL'si 067 kalıbı: RLS açık + SIFIR politika; anon/
--      authenticated yetkisiz; service_role tam. academic_weeks relacl'i
--      değişmez (157 matrisi + 158 modeli korunur).
--
-- DOKUNULMAZLAR (GUARD/FINAL assert):
--   - Mevcut 41 satırın (academic_year, week, starts_at, ends_at) değerleri
--     silinmez / yeniden numaralanmaz; seed YALNIZ yeni kolonları doldurur
--     ve starts_at eşleşmesiyle yazar (takvim sözleşmesi dışı satıra dokunmaz;
--     SEED_159 kapsam assert'i 41/41 doldurmayı doğrular).
--   - 36 kasa / 13 LEGACY / memberships; yarışma/puanlama/antrenman motoru;
--     158 nesneleri; 065; 151; 155/156/157 güvenlik matrisleri değişmez.
--   - 159 tek başına öğrenci yarışma akışını DEĞİŞTİRMEZ: hiçbir çağırıcı
--     yeni kolonları okumaz; RPC üretilmez; K42 fail-closed pasiftir.
--   - 073 takvim yönetimi (gelecek yıl yükleme/silme) ÇALIŞMAYA DEVAM eder:
--     yeni CHECK'ler atanmamış (week_kind IS NULL) satırları serbest bırakır.
--
-- BAĞIMLILIKLAR (ileride; buraya alınmadı):
--   160 first_instruction_week eşlemesi · 161 seed (tatil haftaları
--   vault_kind tatil_tekrari/genel_tekrar olarak academic_weeks'ten okur) ·
--   162 instruction_day_weight ölçeği · 165/166 new_topic_allowed + I#
--   dağıtım kapıları (NULL = kapalı okunacak) · 167 activate_week42 + K36
--   onay RPC'leri (new_topic_admin_approved / activated_by/at YAZIM YÜZEYİ
--   167'dedir; 159 yalnız veri modeli + fail-closed şema sözleşmesidir).
--
-- İDEMPOTENT: add column if not exists; adlı CHECK'ler DO-guard'lu;
--   seed UPDATE deterministik VALUES; INSERT'ler ON CONFLICT DO NOTHING;
--   create or replace function; history WHERE NOT EXISTS. (QA T11.)
--
-- ROLLBACK (yalnız açık yetki; canlıda henüz UYGULANMAMIŞ):
--   resolve_current_academic_period() 067 orijinal gövdesine iade;
--   resolve_academic_week_at(date) DROP; academic_weeks yeni kolonları +
--   adlı CHECK'leri + uq_academic_weeks_instruction_number DROP;
--   meb_holiday_days DROP; K42 satırı DELETE; history 159 silinir.
--   (Drill QA'da uygulandı — rapor §Rollback.)
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- GUARD_159 — ön koşullar (fail-closed)
-- ------------------------------------------------------------
DO $guard$
DECLARE
  v_rows int;
  v_min_week int;
  v_max_week int;
  v_first date;
  v_last date;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='academic_weeks')
  THEN
    RAISE EXCEPTION 'GUARD_159: public.academic_weeks yok (067 beklenir).';
  END IF;

  -- Takvim sözleşmesi: 2026-2027 K1..K41 = 14.09.2026 → 28.06.2027 (exclusive).
  -- Canlı ön kontrol bu sayıları ölçtü; uyuşmazlık = seed kayması riski → DUR.
  SELECT count(*) FILTER (WHERE week BETWEEN 1 AND 41),
         min(week) FILTER (WHERE week BETWEEN 1 AND 41),
         coalesce(max(week) FILTER (WHERE week BETWEEN 1 AND 41), 0),
         min(starts_at) FILTER (WHERE week BETWEEN 1 AND 41),
         max(ends_at)   FILTER (WHERE week BETWEEN 1 AND 41)
    INTO v_rows, v_min_week, v_max_week, v_first, v_last
    FROM public.academic_weeks
   WHERE academic_year = '2026-2027';

  IF v_rows <> 41 OR v_min_week <> 1 OR v_max_week <> 41
     OR v_first IS DISTINCT FROM DATE '2026-09-14'
     OR v_last IS DISTINCT FROM DATE '2027-06-28'
  THEN
    RAISE EXCEPTION
      'GUARD_159: 2026-2027 takvim sözleşmesi uymuyor (rows=%, week %..%, % .. %).',
      v_rows, v_min_week, v_max_week, coalesce(v_first::text,'-'), coalesce(v_last::text,'-');
  END IF;

  -- Zincir ön koşulu: 158 uygulanmış olmalı (history + nesne probe'u).
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='158')
     OR NOT EXISTS (SELECT 1 FROM pg_indexes
                    WHERE schemaname='public' AND indexname='uq_question_vaults_weekly_scope')
  THEN
    RAISE EXCEPTION 'GUARD_159: migration 158 zinciri eksik.';
  END IF;

  -- 157 SEC probe'u (geri sarma tespit cihazı).
  IF has_table_privilege('anon','public.questions','SELECT')
  THEN
    RAISE EXCEPTION 'GUARD_159: 157 uygulanmamış/geri sarilmiş (anon questions SELECT).';
  END IF;

  -- Korunanlar yerinde mi (065 trigger + 151 index).
  IF (SELECT count(*) FROM pg_trigger t
        JOIN pg_class c ON c.oid=t.tgrelid
        JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public'
         AND t.tgname IN ('trg_vault_memberships_pack_limit','trg_question_vaults_pack_limit')) <> 2
     OR NOT EXISTS (SELECT 1 FROM pg_indexes
                    WHERE schemaname='public' AND indexname='uq_question_active_single_vault')
  THEN
    RAISE EXCEPTION 'GUARD_159: 065/151 korunacak kısıtlar eksik.';
  END IF;
END
$guard$;

-- ------------------------------------------------------------
-- 1) academic_weeks — ADDITIVE takvim sözleşmesi kolonları
--    Metadata üç durumlu: NULL = atanmamış (gelecek yıllar 073 ile
--    yüklenmeye devam edebilir; okuyucu NULL'u KAPALI sayar).
-- ------------------------------------------------------------
ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS week_kind text;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS is_instruction_week boolean;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS instruction_week_number smallint;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS holiday_kind text;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS actual_class_days numeric(3,1);

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS partial_week_policy text;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS new_topic_allowed boolean;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS new_topic_admin_approved boolean NOT NULL DEFAULT false;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS new_topic_approved_by uuid
    REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS new_topic_approved_at timestamptz;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS needs_admin_review boolean NOT NULL DEFAULT false;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS requires_admin_activation boolean NOT NULL DEFAULT false;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS activated_by uuid
    REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.academic_weeks
  ADD COLUMN IF NOT EXISTS activated_at timestamptz;

COMMENT ON COLUMN public.academic_weeks.week_kind IS
  'Hafta türü (görev §3): teaching | partial_teaching | holiday_review | year_end_review. NULL = atanmamış yıl (073 ile yüklenmiş, seed''lenmemiş).';
COMMENT ON COLUMN public.academic_weeks.instruction_week_number IS
  'Müfredat ilerleme sayacı I# (K''dan ayrı; master plan §2). Yalnız öğretim haftasında dolu.';
COMMENT ON COLUMN public.academic_weeks.new_topic_allowed IS
  'Yeni alt konu erişimi (fail-closed; dağıtım kapısı 165/166 NULL''u kapalı okur). Tatil/year_end_review asla true olamaz.';
COMMENT ON COLUMN public.academic_weeks.requires_admin_activation IS
  'K42: yönetici onayı olmadan çözümleyici bu haftayı DÖNDÜRMEZ (fail-closed). Yazım yüzeyi 167.';

-- ------------------------------------------------------------
-- 2) Adlı CHECK ailesi (idempotent DO-guard)
--    Çekirdek: academic_weeks_assignment_check — ya TAM atanmamış
--    (tüm metadata NULL) ya TAM atanmış (zorunlu metadata dolu).
-- ------------------------------------------------------------
DO $chk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_week_kind_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_week_kind_check
      CHECK (week_kind IS NULL
             OR week_kind IN ('teaching','partial_teaching','holiday_review','year_end_review'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_assignment_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_assignment_check
      CHECK (
        (week_kind IS NULL AND is_instruction_week IS NULL
         AND instruction_week_number IS NULL AND actual_class_days IS NULL
         AND new_topic_allowed IS NULL)
        OR
        (week_kind IS NOT NULL AND is_instruction_week IS NOT NULL
         AND actual_class_days IS NOT NULL AND new_topic_allowed IS NOT NULL)
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_kind_instruction_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_kind_instruction_check
      CHECK (
        week_kind IS NULL
        OR (week_kind IN ('teaching','partial_teaching') AND is_instruction_week)
        OR (week_kind IN ('holiday_review','year_end_review') AND NOT is_instruction_week)
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_instruction_pair_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_instruction_pair_check
      CHECK (week_kind IS NULL OR is_instruction_week = (instruction_week_number IS NOT NULL));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_instruction_number_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_instruction_number_check
      CHECK (instruction_week_number IS NULL
             OR instruction_week_number BETWEEN 1 AND 52);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_actual_class_days_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_actual_class_days_check
      CHECK (actual_class_days IS NULL OR actual_class_days BETWEEN 0 AND 5);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_holiday_zero_days_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_holiday_zero_days_check
      CHECK (week_kind IS NULL
             OR week_kind NOT IN ('holiday_review','year_end_review')
             OR actual_class_days = 0);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_holiday_kind_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_holiday_kind_check
      CHECK (holiday_kind IS NULL
             OR holiday_kind IN (
               'ara_tatil_1','yariyil_tatili','ara_tatil_2_ramazan_bayrami',
               'resmi_tatil_kismi','kurban_bayrami_kismi','genel_tekrar'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_partial_policy_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_partial_policy_check
      CHECK (
        (week_kind = 'partial_teaching'
         AND partial_week_policy IN ('advance','hold','review'))
        OR (week_kind IS DISTINCT FROM 'partial_teaching' AND partial_week_policy IS NULL)
      );
  END IF;

  -- YENİ KONU KAPISI (görev §3 fail-closed sözleşmesi):
  --   allowed=true SADECE: teaching, ya da partial+advance,
  --   ya da partial+review+YÖNETİCİ ONAYI. holiday_review / year_end_review /
  --   hold → hiçbir kombinasyonda true OLAMAZ (K10/K20/K21/K26/K36/K42).
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_new_topic_gate_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_new_topic_gate_check
      CHECK (
        new_topic_allowed IS NOT TRUE
        OR week_kind = 'teaching'
        OR (week_kind = 'partial_teaching' AND partial_week_policy = 'advance')
        OR (week_kind = 'partial_teaching' AND partial_week_policy = 'review'
            AND new_topic_admin_approved IS TRUE)
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_admin_approval_pair_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_admin_approval_pair_check
      CHECK (
        (new_topic_approved_by IS NULL) = (new_topic_approved_at IS NULL)
        AND (new_topic_admin_approved IS NOT TRUE
             OR (week_kind = 'partial_teaching' AND partial_week_policy = 'review'))
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_admin_review_flag_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_admin_review_flag_check
      CHECK (needs_admin_review IS NOT TRUE
             OR (week_kind = 'partial_teaching'
                 AND partial_week_policy IN ('hold','review')));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_activation_kind_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_activation_kind_check
      CHECK (
        (requires_admin_activation IS NOT TRUE OR week_kind = 'year_end_review')
        -- Karşılıklı sıkılaştırma: her year_end_review haftası onay ZORUNLU
        -- taşır → K42 aktivasyon şartı şema düzeyinde kalıcı (fail-closed).
        AND (week_kind IS DISTINCT FROM 'year_end_review'
             OR requires_admin_activation IS TRUE)
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.academic_weeks'::regclass
                   AND conname='academic_weeks_activation_pair_check')
  THEN
    ALTER TABLE public.academic_weeks
      ADD CONSTRAINT academic_weeks_activation_pair_check
      CHECK ((activated_by IS NULL) = (activated_at IS NULL));
  END IF;
END
$chk$;

-- I# yıl içinde benzersiz (K sayacından AYRIK kanıtlanabilir sayaç).
CREATE UNIQUE INDEX IF NOT EXISTS uq_academic_weeks_instruction_number
  ON public.academic_weeks (academic_year, instruction_week_number)
  WHERE instruction_week_number IS NOT NULL;

-- ------------------------------------------------------------
-- 3) MEB HOLIDAY DAYS — gün bazlı tatil defteri (067 ACL kalıbı)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.meb_holiday_days (
  holiday_date date PRIMARY KEY,

  academic_year text NOT NULL
    CHECK (academic_year ~ '^[0-9]{4}-[0-9]{4}$'),

  label text NOT NULL,

  holiday_type text NOT NULL
    CHECK (holiday_type IN ('ulusal_bayram','dini_bayram','anma_toreni','mesleki_calisma')),

  is_public_holiday boolean NOT NULL DEFAULT true,

  -- Ders günü kaybı: hafta sonu = 0 (çift sayma YOK); arife = 0.5; tatil = 1.
  -- PK(holiday_date): aynı güne denk gelen tatiller TEK satır = tek sayım.
  class_day_loss numeric(2,1) NOT NULL DEFAULT 1
    CHECK (class_day_loss IN (0, 0.5, 1)),

  source_note text
);

COMMENT ON TABLE public.meb_holiday_days IS
  'MEB/Diyanet resmî takvim gün defteri 2026-2027. PK(holiday_date) aynı gün çakışmalarını tek sayar; class_day_loss hafta sonu 0 / arife 0.5 / tatil 1.';

CREATE INDEX IF NOT EXISTS idx_meb_holiday_days_year
  ON public.meb_holiday_days (academic_year, holiday_date);

ALTER TABLE public.meb_holiday_days ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.meb_holiday_days FROM public, anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.meb_holiday_days TO service_role;

-- Seed (master plan §3 tablosunun birebir SQL karşılığı; idempotent).
INSERT INTO public.meb_holiday_days
  (holiday_date, academic_year, label, holiday_type, is_public_holiday, class_day_loss, source_note)
VALUES
  ('2026-10-28','2026-2027','Cumhuriyet Bayrami arifesi (yarim gun)','ulusal_bayram',true,0.5,'MEB takvimi; K07 -0,5 gun'),
  ('2026-10-29','2026-2027','Cumhuriyet Bayrami','ulusal_bayram',true,1,'Persembe; K07 -1 gun'),
  ('2026-11-10','2026-2027','Ataturk''u Anma Gunu','anma_toreni',false,0,'Tatil degil; toren — ilerleme sayaci ilerler (K09)'),
  ('2027-01-01','2026-2027','Yilbasi','ulusal_bayram',true,1,'Cuma; K16 -1 gun'),
  ('2027-03-08','2026-2027','Ramazan Bayrami arifesi (yarim gun)','dini_bayram',true,0.5,'Diyanet 2027; II. ara tatille ayni gun (K26 zaten tam tatil)'),
  ('2027-03-09','2026-2027','Ramazan Bayrami 1. gunu','dini_bayram',true,1,'Sevval 1448/10; II. ara tatille TAM cakisma — ek kayip yok'),
  ('2027-03-10','2026-2027','Ramazan Bayrami 2. gunu','dini_bayram',true,1,'Sevval 1448/11; ara tatil icinde'),
  ('2027-03-11','2026-2027','Ramazan Bayrami 3. gunu','dini_bayram',true,1,'Sevval 1448/12; ara tatil icinde'),
  ('2027-04-23','2026-2027','Ulusal Egemenlik ve Cocuk Bayrami','ulusal_bayram',true,1,'Cuma; K32 -1 gun'),
  ('2027-05-01','2026-2027','Emek ve Dayanisma Gunu (Cumartesi)','ulusal_bayram',true,0,'Hafta sonu → ders gunu kaybi YOK (cift sayma yok)'),
  ('2027-05-15','2026-2027','Kurban Bayrami arifesi (Cumartesi)','dini_bayram',true,0,'Zilhicce 1448/9; hafta sonu → kayip yok'),
  ('2027-05-16','2026-2027','Kurban Bayrami 1. gunu (Pazar)','dini_bayram',true,0,'Pazar → hafta sonu; K36 kayibina girmez'),
  ('2027-05-17','2026-2027','Kurban Bayrami 2. gunu','dini_bayram',true,1,'Pazartesi; K36 -1 gun'),
  ('2027-05-18','2026-2027','Kurban Bayrami 3. gunu','dini_bayram',true,1,'Sali; K36 -1 gun'),
  ('2027-05-19','2026-2027','Kurban Bayrami 4. gunu (19 Mayis Anma Gunu ile ayni gun)','dini_bayram',true,1,'Carsamba; ayni gun = TEK sayim (PK), K36 -1 gun'),
  ('2027-06-28','2026-2027','Ogretmen yil sonu mesleki calismasi','mesleki_calisma',false,1,'K42''nin resmi ders haftasi olmadiginin kaniti (MEB kaynak B)'),
  ('2027-06-29','2026-2027','Ogretmen yil sonu mesleki calismasi','mesleki_calisma',false,1,'Kaynak B'),
  ('2027-06-30','2026-2027','Ogretmen yil sonu mesleki calismasi','mesleki_calisma',false,1,'Kaynak B')
ON CONFLICT (holiday_date) DO NOTHING;

-- ------------------------------------------------------------
-- 4) TAKVİM SEED'İ — master plan §2 tablosunun birebir karşılığı
--    Yalnız YENİ kolonlar yazılır; starts_at eşleşmeyen satıra dokunulmaz.
-- ------------------------------------------------------------
UPDATE public.academic_weeks w
   SET week_kind               = s.week_kind,
       is_instruction_week     = (s.i_number IS NOT NULL),
       instruction_week_number = s.i_number,
       holiday_kind            = s.holiday_kind,
       actual_class_days       = s.class_days,
       partial_week_policy     = s.partial_policy,
       new_topic_allowed       = s.new_topic_allowed,
       needs_admin_review      = s.needs_admin_review
  FROM (VALUES
    --  K   starts_at      week_kind,         I#,  gün, holiday_kind,                   policy,   new_topic, review
    (1,  DATE '2026-09-14','teaching',         1, 5.0, NULL::text, NULL::text, true, false),
    (2,  DATE '2026-09-21','teaching',         2, 5.0, NULL, NULL, true, false),
    (3,  DATE '2026-09-28','teaching',         3, 5.0, NULL, NULL, true, false),
    (4,  DATE '2026-10-05','teaching',         4, 5.0, NULL, NULL, true, false),
    (5,  DATE '2026-10-12','teaching',         5, 5.0, NULL, NULL, true, false),
    (6,  DATE '2026-10-19','teaching',         6, 5.0, NULL, NULL, true, false),
    (7,  DATE '2026-10-26','partial_teaching', 7, 3.5,'resmi_tatil_kismi','advance', true, false),
    (8,  DATE '2026-11-02','teaching',         8, 5.0, NULL, NULL, true, false),
    (9,  DATE '2026-11-09','teaching',         9, 5.0, NULL, NULL, true, false),
    (10, DATE '2026-11-16','holiday_review', NULL, 0.0,'ara_tatil_1', NULL, false, false),
    (11, DATE '2026-11-23','teaching',        10, 5.0, NULL, NULL, true, false),
    (12, DATE '2026-11-30','teaching',        11, 5.0, NULL, NULL, true, false),
    (13, DATE '2026-12-07','teaching',        12, 5.0, NULL, NULL, true, false),
    (14, DATE '2026-12-14','teaching',        13, 5.0, NULL, NULL, true, false),
    (15, DATE '2026-12-21','teaching',        14, 5.0, NULL, NULL, true, false),
    (16, DATE '2026-12-28','partial_teaching',15, 4.0,'resmi_tatil_kismi','advance', true, false),
    (17, DATE '2027-01-04','teaching',        16, 5.0, NULL, NULL, true, false),
    (18, DATE '2027-01-11','teaching',        17, 5.0, NULL, NULL, true, false),
    (19, DATE '2027-01-18','teaching',        18, 5.0, NULL, NULL, true, false),
    (20, DATE '2027-01-25','holiday_review', NULL, 0.0,'yariyil_tatili', NULL, false, false),
    (21, DATE '2027-02-01','holiday_review', NULL, 0.0,'yariyil_tatili', NULL, false, false),
    (22, DATE '2027-02-08','teaching',        19, 5.0, NULL, NULL, true, false),
    (23, DATE '2027-02-15','teaching',        20, 5.0, NULL, NULL, true, false),
    (24, DATE '2027-02-22','teaching',        21, 5.0, NULL, NULL, true, false),
    (25, DATE '2027-03-01','teaching',        22, 5.0, NULL, NULL, true, false),
    (26, DATE '2027-03-08','holiday_review', NULL, 0.0,'ara_tatil_2_ramazan_bayrami', NULL, false, false),
    (27, DATE '2027-03-15','teaching',        23, 5.0, NULL, NULL, true, false),
    (28, DATE '2027-03-22','teaching',        24, 5.0, NULL, NULL, true, false),
    (29, DATE '2027-03-29','teaching',        25, 5.0, NULL, NULL, true, false),
    (30, DATE '2027-04-05','teaching',        26, 5.0, NULL, NULL, true, false),
    (31, DATE '2027-04-12','teaching',        27, 5.0, NULL, NULL, true, false),
    (32, DATE '2027-04-19','partial_teaching',28, 4.0,'resmi_tatil_kismi','advance', true, false),
    (33, DATE '2027-04-26','teaching',        29, 5.0, NULL, NULL, true, false),
    (34, DATE '2027-05-03','teaching',        30, 5.0, NULL, NULL, true, false),
    (35, DATE '2027-05-10','teaching',        31, 5.0, NULL, NULL, true, false),
    (36, DATE '2027-05-17','partial_teaching',32, 2.0,'kurban_bayrami_kismi','review', false, true),
    (37, DATE '2027-05-24','teaching',        33, 5.0, NULL, NULL, true, false),
    (38, DATE '2027-05-31','teaching',        34, 5.0, NULL, NULL, true, false),
    (39, DATE '2027-06-07','teaching',        35, 5.0, NULL, NULL, true, false),
    (40, DATE '2027-06-14','teaching',        36, 5.0, NULL, NULL, true, false),
    (41, DATE '2027-06-21','teaching',        37, 5.0, NULL, NULL, true, false)
  ) AS s(week_no, starts_at, week_kind, i_number, class_days,
         holiday_kind, partial_policy, new_topic_allowed, needs_admin_review)
 WHERE w.academic_year = '2026-2027'
   AND w.week = s.week_no
   AND w.starts_at = s.starts_at;

-- Seed kapsam kanıtı: tam 41 satır atanmış olmalı (tarih uyuşmazlığı = DUR).
DO $seedcnt$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v
    FROM public.academic_weeks
   WHERE academic_year = '2026-2027'
     AND week BETWEEN 1 AND 41
     AND week_kind IS NOT NULL;
  IF v <> 41 THEN
    RAISE EXCEPTION 'SEED_159: beklenen 41 atanmis hafta, olculen % (tarih eslesmeyen satir var).', v;
  END IF;
END
$seedcnt$;

-- ------------------------------------------------------------
-- 5) K42 satırı — PASİF, yönetici onayı bekler (fail-closed)
--    Tarih: TÜRETİLMİŞ ÖNERİ 28.06–02.07.2027 (master plan §2/§11;
--    resmî bitişin hemen sonraki Pzt–Cum; mesleki çalışma kanıtı §3).
--    Kesin tarih + açılış YALNIZ 167 yönetici onayıyla.
-- ------------------------------------------------------------
INSERT INTO public.academic_weeks
  (academic_year, week, starts_at, ends_at,
   week_kind, is_instruction_week, instruction_week_number, holiday_kind,
   actual_class_days, partial_week_policy,
   new_topic_allowed, new_topic_admin_approved, needs_admin_review,
   requires_admin_activation)
VALUES
  ('2026-2027', 42, DATE '2027-06-28', DATE '2027-07-03',
   'year_end_review', false, NULL, 'genel_tekrar',
   0.0, NULL,
   false, false, false,
   true)
ON CONFLICT (academic_year, week) DO NOTHING;

-- ------------------------------------------------------------
-- 6) ÇÖZÜMLEYİCİ — tarih argümanlı yeni fonksiyon + 067 ince sarmalayıcı
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_academic_week_at(p_date date)
RETURNS TABLE (
  academic_year text,
  week integer,
  week_kind text,
  is_instruction_week boolean,
  instruction_week_number smallint,
  actual_class_days numeric,
  holiday_kind text,
  new_topic_allowed boolean,
  requires_admin_activation boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT w.academic_year,
         w.week,
         w.week_kind,
         w.is_instruction_week,
         w.instruction_week_number,
         w.actual_class_days,
         w.holiday_kind,
         w.new_topic_allowed,
         w.requires_admin_activation
    FROM public.academic_weeks w
   WHERE p_date >= w.starts_at
     AND p_date < w.ends_at
     -- FAIL-CLOSED: aktivasyon bekleyen satır hiçbir akışa görünmez (K42).
     AND NOT (w.requires_admin_activation AND w.activated_at IS NULL)
   ORDER BY w.starts_at
   LIMIT 1;
$$;

-- 067 imzası KORUNUR; tek fark: pasif-beklemedeki satır filtrelenir.
-- 28.06.2027 öncesi canlıda davranış FARKI YOKTUR (K42 aralığı gelecektir).
CREATE OR REPLACE FUNCTION public.resolve_current_academic_period()
RETURNS TABLE (
  academic_year text,
  week integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT r.academic_year, r.week
    FROM public.resolve_academic_week_at(
           ((current_timestamp AT TIME ZONE 'utc')::date)) r;
$$;

REVOKE EXECUTE
  ON FUNCTION public.resolve_academic_week_at(date)
  FROM public, anon, authenticated;

REVOKE EXECUTE
  ON FUNCTION public.resolve_current_academic_period()
  FROM public, anon, authenticated;

COMMENT ON FUNCTION public.resolve_academic_week_at(date) IS
  'Sunucu tarafı takvim çözümleyici (067 deseni; EXECUTE kapalı). Aktivasyon bekleyen hafta fail-closed görünmez.';

-- ------------------------------------------------------------
-- History — idempotent (151/158 deseni)
-- ------------------------------------------------------------
INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
SELECT '159', '159_meb_academic_calendar', NULL
 WHERE NOT EXISTS (
   SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '159'
 );

-- ------------------------------------------------------------
-- FINAL_159 — fail-closed son matris
-- ------------------------------------------------------------
DO $final$
DECLARE
  v int;
  v_def text;
BEGIN
  -- 1) Kolon ailesi
  SELECT count(*) INTO v
    FROM information_schema.columns
   WHERE table_schema='public' AND table_name='academic_weeks'
     AND column_name IN ('week_kind','is_instruction_week','instruction_week_number',
                         'holiday_kind','actual_class_days','partial_week_policy',
                         'new_topic_allowed','new_topic_admin_approved',
                         'new_topic_approved_by','new_topic_approved_at',
                         'needs_admin_review','requires_admin_activation',
                         'activated_by','activated_at');
  IF v <> 14 THEN
    RAISE EXCEPTION 'FINAL_159: ek kolon sayısı % (beklenen 14).', v;
  END IF;

  -- 2) CHECK ailesi (14 ad)
  SELECT count(*) INTO v
    FROM pg_constraint
   WHERE conrelid='public.academic_weeks'::regclass
     AND conname IN ('academic_weeks_week_kind_check',
                     'academic_weeks_assignment_check',
                     'academic_weeks_kind_instruction_check',
                     'academic_weeks_instruction_pair_check',
                     'academic_weeks_instruction_number_check',
                     'academic_weeks_actual_class_days_check',
                     'academic_weeks_holiday_zero_days_check',
                     'academic_weeks_holiday_kind_check',
                     'academic_weeks_partial_policy_check',
                     'academic_weeks_new_topic_gate_check',
                     'academic_weeks_admin_approval_pair_check',
                     'academic_weeks_admin_review_flag_check',
                     'academic_weeks_activation_kind_check',
                     'academic_weeks_activation_pair_check');
  IF v <> 14 THEN
    RAISE EXCEPTION 'FINAL_159: CHECK ailesi % (beklenen 14).', v;
  END IF;

  -- 3) Çift sayaç tohum doğruları (master plan §2)
  IF EXISTS (SELECT 1 FROM public.academic_weeks
              WHERE academic_year='2026-2027' AND week BETWEEN 1 AND 42
                AND week_kind IS NULL)
     OR (SELECT count(*) FROM public.academic_weeks
          WHERE academic_year='2026-2027' AND is_instruction_week) <> 37
     OR (SELECT count(DISTINCT instruction_week_number) FROM public.academic_weeks
          WHERE academic_year='2026-2027' AND instruction_week_number IS NOT NULL) <> 37
     OR (SELECT max(instruction_week_number) FROM public.academic_weeks
          WHERE academic_year='2026-2027') <> 37
     OR EXISTS (SELECT 1 FROM public.academic_weeks
                 WHERE academic_year='2026-2027' AND week IN (10,20,21,26)
                   AND (instruction_week_number IS NOT NULL
                        OR is_instruction_week
                        OR week_kind <> 'holiday_review'
                        OR actual_class_days <> 0
                        OR new_topic_allowed))
     OR EXISTS (SELECT 1 FROM public.academic_weeks
                 WHERE academic_year='2026-2027' AND week = 11
                   AND instruction_week_number <> 10)
     OR EXISTS (SELECT 1 FROM public.academic_weeks
                 WHERE academic_year='2026-2027' AND week = 36
                   AND (week_kind <> 'partial_teaching'
                        OR partial_week_policy <> 'review'
                        OR actual_class_days <> 2.0
                        OR new_topic_allowed
                        OR needs_admin_review IS NOT TRUE
                        OR instruction_week_number <> 32))
     OR EXISTS (SELECT 1 FROM public.academic_weeks
                 WHERE academic_year='2026-2027' AND week = 7
                   AND actual_class_days <> 3.5)
  THEN
    RAISE EXCEPTION 'FINAL_159: takvim tohumu master plan §2 ile uyuşmuyor.';
  END IF;

  -- 4) Fiili gün formülü: öğretim haftaları = 5 − (Pzt–Cum tatil kaybı)
  IF EXISTS (
    SELECT 1
      FROM public.academic_weeks w
      JOIN LATERAL (
        SELECT coalesce(sum(h.class_day_loss), 0)::numeric(3,1) AS loss
          FROM public.meb_holiday_days h
         WHERE h.holiday_date >= w.starts_at
           AND h.holiday_date < w.ends_at
           AND EXTRACT(ISODOW FROM h.holiday_date) BETWEEN 1 AND 5
      ) L ON TRUE
     WHERE w.academic_year = '2026-2027'
       AND w.week BETWEEN 1 AND 41
       AND w.is_instruction_week
       AND w.actual_class_days <> (5 - L.loss)
  ) THEN
    RAISE EXCEPTION 'FINAL_159: actual_class_days ↔ tatil defteri formülü tutmuyor.';
  END IF;

  -- 5) K42 pasif + fail-closed şekil
  IF EXISTS (SELECT 1 FROM public.academic_weeks
              WHERE academic_year='2026-2027' AND week=42
                AND (week_kind <> 'year_end_review'
                     OR is_instruction_week
                     OR instruction_week_number IS NOT NULL
                     OR actual_class_days <> 0
                     OR new_topic_allowed
                     OR requires_admin_activation IS NOT TRUE
                     OR activated_by IS NOT NULL
                     OR activated_at IS NOT NULL
                     OR starts_at <> DATE '2027-06-28'
                     OR ends_at <> DATE '2027-07-03'))
  THEN
    RAISE EXCEPTION 'FINAL_159: K42 satırı pasif/genel-tekrar sözleşmesine uymuyor.';
  END IF;

  -- 6) Tatil defteri: 18 satır; 19.05 tek sayım; formül sabitleri
  IF (SELECT count(*) FROM public.meb_holiday_days) <> 18
     OR (SELECT count(*) FROM public.meb_holiday_days
          WHERE holiday_date = DATE '2027-05-19') <> 1
     OR (SELECT coalesce(sum(class_day_loss),0) FROM public.meb_holiday_days
          WHERE holiday_date BETWEEN DATE '2027-05-17' AND DATE '2027-05-21'
            AND EXTRACT(ISODOW FROM holiday_date) BETWEEN 1 AND 5) <> 3
     OR (SELECT coalesce(sum(class_day_loss),0) FROM public.meb_holiday_days
          WHERE holiday_date IN (DATE '2027-05-01', DATE '2027-05-15', DATE '2027-05-16')) <> 0
  THEN
    RAISE EXCEPTION 'FINAL_159: meb_holiday_days kanonik sabitleri tutmuyor.';
  END IF;

  -- 7) I# benzersizlik indexi + çözümleyici fail-closed predicate
  SELECT indexdef INTO v_def FROM pg_indexes
   WHERE schemaname='public' AND indexname='uq_academic_weeks_instruction_number';
  IF v_def IS NULL OR v_def NOT LIKE 'CREATE UNIQUE%'
     OR position('instruction_week_number' IN v_def) = 0
  THEN
    RAISE EXCEPTION 'FINAL_159: I# indexi beklenmedik: %', coalesce(v_def,'<yok>');
  END IF;

  SELECT pg_get_functiondef('public.resolve_academic_week_at(date)'::regprocedure)
    INTO v_def;
  IF v_def IS NULL
     OR position('requires_admin_activation AND w.activated_at IS NULL' IN v_def) = 0
  THEN
    RAISE EXCEPTION 'FINAL_159: çözümleyici fail-closed filtresi yok.';
  END IF;

  IF has_function_privilege('anon','public.resolve_academic_week_at(date)'::regprocedure,'EXECUTE')
     OR has_function_privilege('authenticated','public.resolve_academic_week_at(date)'::regprocedure,'EXECUTE')
     OR has_function_privilege('anon','public.resolve_current_academic_period()'::regprocedure,'EXECUTE')
     OR has_function_privilege('authenticated','public.resolve_current_academic_period()'::regprocedure,'EXECUTE')
  THEN
    RAISE EXCEPTION 'FINAL_159: çözümleyici EXECUTE sızıntısı.';
  END IF;

  -- 8) meb_holiday_days ACL/RLS (067 modeli)
  IF (SELECT relrowsecurity FROM pg_class
       WHERE oid='public.meb_holiday_days'::regclass) IS NOT TRUE
     OR EXISTS (SELECT 1 FROM pg_policy
                WHERE polrelid='public.meb_holiday_days'::regclass)
     OR has_table_privilege('anon','public.meb_holiday_days','SELECT')
     OR has_table_privilege('authenticated','public.meb_holiday_days','SELECT')
     OR has_table_privilege('public','public.meb_holiday_days','SELECT')
     OR NOT (has_table_privilege('service_role','public.meb_holiday_days','SELECT')
             AND has_table_privilege('service_role','public.meb_holiday_days','INSERT')
             AND has_table_privilege('service_role','public.meb_holiday_days','UPDATE')
             AND has_table_privilege('service_role','public.meb_holiday_days','DELETE'))
  THEN
    RAISE EXCEPTION 'FINAL_159: meb_holiday_days ACL/RLS modeli bozuk.';
  END IF;

  -- academic_weeks: istemci SELECT hakkı DOKUNULMADI (anon YOK), RLS açık
  IF has_table_privilege('anon','public.academic_weeks','SELECT')
     OR (SELECT relrowsecurity FROM pg_class
          WHERE oid='public.academic_weeks'::regclass) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'FINAL_159: academic_weeks istemci ACL/RLS bozuldu.';
  END IF;

  -- 9) KORUNANLAR: 065 + 151 + 158 nesneleri
  IF (SELECT count(*) FROM pg_trigger t
        JOIN pg_class c ON c.oid=t.tgrelid
        JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public'
         AND t.tgname IN ('trg_vault_memberships_pack_limit','trg_question_vaults_pack_limit',
                          'trg_weekly_placements_limit','trg_question_vaults_weekly_type')) <> 4
     OR NOT EXISTS (SELECT 1 FROM pg_indexes
                    WHERE schemaname='public' AND indexname='uq_question_active_single_vault')
     OR NOT EXISTS (SELECT 1 FROM pg_indexes
                    WHERE schemaname='public' AND indexname='uq_question_vaults_weekly_scope')
     OR NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='weekly_vault_placements')
  THEN
    RAISE EXCEPTION 'FINAL_159: 065/151/158 korunumları bozuldu.';
  END IF;

  -- 10) 157 matrisi (kritik kesit — 158 FINAL'la aynı)
  SELECT count(*) INTO v
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p','v')
     AND (has_table_privilege('anon',c.oid,'SELECT')
          OR has_table_privilege('anon',c.oid,'INSERT')
          OR has_table_privilege('anon',c.oid,'UPDATE')
          OR has_table_privilege('anon',c.oid,'DELETE'));
  IF v <> 0 THEN
    RAISE EXCEPTION 'FINAL_159: anon hak kirligi % nesnede (157 geri sarmasi?).', v;
  END IF;

  IF has_function_privilege('anon','public.get_internal_correct_answer(uuid)'::regprocedure,'EXECUTE')
     OR has_function_privilege('authenticated','public.get_internal_correct_answer(uuid)'::regprocedure,'EXECUTE')
  THEN
    RAISE EXCEPTION 'FINAL_159: SEC-1 geri sarildi.';
  END IF;

  SELECT count(*) INTO v
    FROM information_schema.column_privileges
   WHERE table_schema='public' AND table_name='questions'
     AND grantee='authenticated' AND privilege_type='SELECT';
  IF v <> 30 THEN
    RAISE EXCEPTION 'FINAL_159: questions auth kolon SELECT % (beklenen 30).', v;
  END IF;

  SELECT count(*) INTO v
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relispartition=false
     AND (has_table_privilege('authenticated',c.oid,'INSERT')
          OR has_table_privilege('authenticated',c.oid,'UPDATE')
          OR has_table_privilege('authenticated',c.oid,'DELETE'));
  IF v <> (
    SELECT count(*)
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relispartition=false
       AND EXISTS (SELECT 1 FROM pg_policy p
                    WHERE p.polrelid=c.oid AND p.polcmd IN ('a','w','d','*')
                      AND p.polroles @> ARRAY['authenticated'::regrole::oid]
                      AND p.polpermissive)
  ) THEN
    RAISE EXCEPTION 'FINAL_159: yazilabilir tablo != yazma politikali (157-C esitligi bozuk).';
  END IF;

  SELECT count(*) INTO v
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relrowsecurity=false;
  IF v <> 0 THEN
    RAISE EXCEPTION 'FINAL_159: RLS kapali % tablo var.', v;
  END IF;

  -- 11) history
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='159') THEN
    RAISE EXCEPTION 'FINAL_159: history kaydi yok.';
  END IF;

  RAISE NOTICE 'MEB159 OK: takvim sozlesmesi + cift sayac (37 I) + tatil defteri (18 gun) + K42 pasif fail-closed; K1..K41 korundu; 065/151/157/158 matrisleri duruyor';
END
$final$;

COMMIT;
