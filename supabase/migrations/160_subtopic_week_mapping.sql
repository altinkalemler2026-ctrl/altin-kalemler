-- ============================================================
-- 160_subtopic_week_mapping.sql
-- AK-MEB-VAULT-42-07 sıra-160: Alt konu → MEB öğretim haftası eşlemesi (ADDITIVE)
-- ============================================================
-- KAYNAK (erişim 11.11.2026; kanonik ağaç YENİDEN YAZILMAZ, yalnız eşlenir):
--   A) Müfredat ağacı: subjects/topics/subtopics/curriculum_outcomes
--      (migration 111–112 + 142–149; canlı ölçüm: 8 ders / 29 sınıf–ders çifti /
--      127 tema / 546 aktif alt konu — tümü 9–12 ve aktif).
--   B) Matematik tema bantları: curriculum_schedule_items 26 satır
--      (migration 111; start_week DAHİL / end_week HARİÇ, K ölçegi; tatil
--      haftalarına start atanmaz — 111 §5). Bu bantlar MEB DÖP resmî DERS
--      SAATLERİNDEN türetilmiş ÖNERİLEN takvimdir
--      (docs/reports/2026-2027-matematik-yillik-konu-plani.md — belgenin kendi
--      uyarısı: "bu plan uydurur, varsayımdır"); resmî HAFTALIK plan değildir.
--   C) MAT.11.3 pencere→alt konu bağları: aynı plan §5 satırları
--      (w1: 11.3.1–2, w2: 11.3.3–6, w3: 11.3.7–8) — canlıdaki sort_order'ı
--      pencere-yönelimli (1,1,1/2,2,2/3/4) olduğu için resmî sıraya göre ADA
--      BAZLI bağlanır; GUARD birebir örtüşmeyi zorunlu kılar.
--   D) MEB 2026–2027 resmî HAFTALIK (yıllık) plan dosyası (ZIP/PDF) ne
--      repoda ne resmi-kaynak-envanterinde DOĞRULANMIŞTIR (GAP-160-A);
--      doğrulananlar yalnız DÖP PDF'leridir (kapsam + ders saati). Görev
--      ek-kuralı gereği: hiçbiri KESİN eşleme olarak kaydedilmez — TÜM
--      tohum satırları mapping_confidence='tahmini_onay_bekliyor'; kanıt
--      kalitesi evidence_kind ile TİPLEŞTİRİLİR ayrı tutulur:
--        resmi_ders_saati_turetilmis → Matematik (DÖP saatleri + 111 bandı)
--        okul_plani_duz_esit_dagilim → diğer 24 sınıf–ders çifti
--        meb_yillik_plan_dogrulanmis → HENÜZ KULLANILMADI (ZIP/PDF doğrulanır
--          ve yönetici 167 akışında yükseltirse kullanılır; enum hazırdır).
--   E) Kanıt URL'leri: curriculum_versions.source_url (mufredat.meb.gov.tr).
--
-- KAPSAM (görev AK-MEB-VAULT-42-07 + master plan §6/§13 satır-160 + EK KURAL):
--   1) curriculum_subtopic_week_map: yıllık, alt konu başına TEK satır.
--      Kimlikler mevcut ağaçtan (FK + tutarlılık trigger'ı; yeni kimlik icat yok).
--      first_instruction_week = ilk uygun ÖĞRETİM haftası (I#; 159 sayaçları).
--      Yalnız new_topic_allowed=true öğretim haftaları slot olarak kullanılır
--      → hiçbir alt konu K36(review)/tatil haftasına ilk-açılış planlanmaz.
--   2) mapping_confidence üç durumu: resmi_dogrudan / resmi_dolayli (yalnız
--      DOĞRULANMIŞ resmî haftalık planla; kaynak + KANIT KAYDI zorunlu — FIX-160-A) /
--      tahmini_onay_bekliyor. Bu tohumda TÜMÜ tahmini_onay_bekliyor.
--      FIX-160-A (42-10): Yönetici onayı (approved_by/approved_at) TEK BAŞINA
--      öğrenci erişimi SAĞLAMAZ; onay yalnız beyandır ve kapı açmaz. Erişim
--      ancak curriculum_week_map_verify ile resmî belge kanıtı (kurum + URL +
--      belge adı/yıl + dosya SHA-256 + belge içi konum) işlenip satır resmî
--      statüye yükseltilince ve öğretim-haftası/eşik kapıları geçilince doğar.
--   3) Motor okuması: curriculum_subtopic_week_state(grade, subject, date) —
--      definer; EXECUTE yalnız service_role/postgres. Durumlar:
--      new_this_week / opened_repeat / held_pending (hafta yeni konuya kapalı)
--      / locked_future (gelecek alt konu ERKEN AÇILMAZ) / locked_unapproved
--      (tahmini + onaysız) / approved_pending_official (FIX-160-A: tahmini +
--      onaylı ama resmî doğrulama YOK → KAPALI). is_usable YALNIZ resmî statü
--      + haftası gelmiş + kapılar geçmiş satırlarda TRUE (K1).
--      Tatil haftasında I sayacı durur (159) → eşikler kaymaz, müfredat
--      kaldığı yerden devam eder; K42 aktivasyonsuz hiç görünmez (fail-closed).
--   4) ÖĞRENCİ GÖRÜNÜRLÜĞÜ: tablo RLS+FORCE + SIFIR politika; anon/
--      authenticated'e HİÇBİR hak yok (158/meb_holiday_days kalıbı).
--      Kasa/soru dağıtımı bu migration'da YOK (161+).
--
-- DOKUNULMAZLAR (GUARD/FINAL assert):
--   - 159 takvim nesneleri (academic_weeks 42 satır / 37 I / 18 tatil günü,
--     meb_holiday_days, resolver'lar) OKUNUR, DEĞİŞTİRİLMEZ.
--   - 158 kasa şeması, 151 tek-üyelik, 065 ≤5 paket, 157 güvenlik matrisi,
--     36 eski kasa + 13 LEGACY: GUARD/FINAL aynı probe'ları çalıştırır.
--   - curriculum_versions / subjects / topics / subtopics satırlarına
--     yazılmaz; curriculum_schedule_items okunur, değişmez.
--
-- İKİNCİ UYGULAMA (idempotent): tablo/index/function ON CONFLICT DO NOTHING /
--   create or replace; seed yeni alt konu eklenmediyse 0 satır. Tree büyüdüyse
--   official_order çakışmasında satır atlanır ve FINAL coverage raise eder →
--   transaction rollback (fail-closed; yeniden-eşleme yönetici akışıdır).
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- GUARD_160 — ön koşullar (fail-closed)
-- ------------------------------------------------------------
DO $guard$
DECLARE
  v  bigint;
  v_has boolean;
BEGIN
  -- 1) Zincir: 158 + 159 applied
  IF (SELECT count(*) FROM supabase_migrations.schema_migrations
      WHERE version IN ('158','159')) <> 2 THEN
    RAISE EXCEPTION 'GUARD_160: 158/159 migration zinciri eksik.';
  END IF;

  -- 2) 159 takvim sözleşmesi (2026-2027)
  IF to_regclass('public.academic_weeks') IS NULL THEN
    RAISE EXCEPTION 'GUARD_160: public.academic_weeks yok (067/159 beklenir).';
  END IF;
  IF (SELECT count(*) FROM public.academic_weeks WHERE academic_year = '2026-2027') <> 42 THEN
    RAISE EXCEPTION 'GUARD_160: 2026-2027 hafta sayısı 42 değil (159 beklenir).';
  END IF;
  IF (SELECT count(DISTINCT instruction_week_number) FROM public.academic_weeks
      WHERE academic_year = '2026-2027' AND instruction_week_number IS NOT NULL) <> 37 THEN
    RAISE EXCEPTION 'GUARD_160: I1–I37 sayacı yok (159 beklenir).';
  END IF;
  IF EXISTS (SELECT 1 FROM public.academic_weeks
             WHERE academic_year = '2026-2027' AND week_kind IS NULL) THEN
    RAISE EXCEPTION 'GUARD_160: atanmamış (week_kind NULL) 2026-2027 haftası var.';
  END IF;
  IF (SELECT count(*) FROM public.academic_weeks
      WHERE academic_year = '2026-2027' AND week = 42) <> 1 THEN
    RAISE EXCEPTION 'GUARD_160: K42 satırı yok.';
  END IF;
  IF to_regclass('public.meb_holiday_days') IS NULL
     OR (SELECT count(*) FROM public.meb_holiday_days) <> 18 THEN
    RAISE EXCEPTION 'GUARD_160: meb_holiday_days 18 satır değil.';
  END IF;

  -- 3) Slot sözleşmesi: yeni-konu-açık öğretim haftaları 36–37 adet
  --    (33 tam + advance partial; K36 review slot DEĞİLDİR)
  IF (SELECT count(*) FROM public.academic_weeks
      WHERE academic_year = '2026-2027' AND instruction_week_number IS NOT NULL
        AND new_topic_allowed) NOT BETWEEN 36 AND 37 THEN
    RAISE EXCEPTION 'GUARD_160: yeni-konu-acik slot sayisi 36/37 disinda.';
  END IF;

  -- 4) Müfredat ağacı varlığı + nüfus sınırı (9–12 aktif temalar)
  IF to_regclass('public.subjects') IS NULL OR to_regclass('public.topics') IS NULL
     OR to_regclass('public.subtopics') IS NULL
     OR to_regclass('public.curriculum_schedule_items') IS NULL THEN
    RAISE EXCEPTION 'GUARD_160: müfredat ağaç tabloları eksik.';
  END IF;
  SELECT count(*) INTO v FROM public.subtopics st
    JOIN public.topics t ON t.id = st.topic_id
   WHERE st.is_active AND t.is_active
     AND t.grade_level NOT BETWEEN 9 AND 12;
  IF v > 0 THEN
    RAISE EXCEPTION 'GUARD_160: 9–12 dışı aktif alt konu sayısı %.', v;
  END IF;
  IF (SELECT count(*) FROM public.subtopics st
      JOIN public.topics t ON t.id = st.topic_id
      WHERE st.is_active AND t.is_active) = 0 THEN
    RAISE EXCEPTION 'GUARD_160: aktif alt konu yok.';
  END IF;

  -- 5) Schedule zinciri: yalnız Matematik satırları; her matematik teması
  --    bantlı; bant başlangıçları I sayacına çözülür (tatil-start yok);
  --    çok-pencereli tema yalnız MAT.11.3 olabilir
  SELECT count(*) INTO v FROM public.curriculum_schedule_items i
    JOIN public.subjects s ON s.id = i.subject_id
   WHERE i.is_active AND s.slug <> 'matematik';
  IF v > 0 THEN
    RAISE EXCEPTION 'GUARD_160: matematik dışı aktif schedule_item var (%); bu sürüm yalnız 111 matrisini bant kaynağı sayar.', v;
  END IF;
  SELECT count(*) INTO v FROM public.topics t
    JOIN public.subjects s ON s.id = t.subject_id
   WHERE s.slug = 'matematik' AND t.is_active
     AND NOT EXISTS (SELECT 1 FROM public.curriculum_schedule_items i
                     WHERE i.topic_id = t.id AND i.is_active);
  IF v > 0 THEN
    RAISE EXCEPTION 'GUARD_160: bandı olmayan aktif matematik teması sayısı %.', v;
  END IF;
  SELECT count(*) INTO v
  FROM (SELECT DISTINCT i.start_week FROM public.curriculum_schedule_items i
        JOIN public.subjects s ON s.id = i.subject_id
        WHERE i.is_active AND s.slug = 'matematik') b
  WHERE NOT EXISTS (SELECT 1 FROM public.academic_weeks aw
                    WHERE aw.academic_year = '2026-2027'
                      AND aw.week = b.start_week
                      AND aw.instruction_week_number IS NOT NULL);
  IF v > 0 THEN
    RAISE EXCEPTION 'GUARD_160: bant başlangıcı öğretim haftasına çözülemiyor (% adet) — takvim 159 ile uyumsuz.', v;
  END IF;
  SELECT count(*) INTO v
  FROM (SELECT i.topic_id FROM public.curriculum_schedule_items i
        JOIN public.subjects s ON s.id = i.subject_id
        WHERE i.is_active AND s.slug = 'matematik' AND i.topic_id IS NOT NULL
        GROUP BY i.topic_id HAVING count(*) > 1) w;
  IF v <> 1 THEN
    RAISE EXCEPTION 'GUARD_160: beklenmeyen çok-pencereli tema sayısı % (yalnız MAT.11.3 beklenir).', v;
  END IF;

  -- 6) MAT.11.3 plan-kodu bağı birebir örtüşmeli (8 aktif alt konu;
  --    eksik/çoklu eşleşme = ağaç değişmiş → seed'de sessiz kayma yerine raise)
  IF (SELECT count(*) FROM public.subtopics st
      JOIN public.topics t ON t.id = st.topic_id
      JOIN public.subjects s ON s.id = t.subject_id
      WHERE s.slug = 'matematik' AND t.grade_level = 11
        AND t.name = 'MAT.11.3 NİCELİKLER VE DEĞİŞİMLER'
        AND st.is_active) <> 8 THEN
    RAISE EXCEPTION 'GUARD_160: MAT.11.3 alt konu sayısı 8 değil (ağaç değişti?).';
  END IF;

  -- 7) Yönetim altyapısı (073) — onay RPC'si bağımlılığı
  IF to_regclass('public.admin_permissions') IS NULL
     OR to_regclass('public.admin_roles') IS NULL
     OR to_regclass('public.admin_role_permissions') IS NULL
     OR to_regclass('public.admin_user_roles') IS NULL THEN
    RAISE EXCEPTION 'GUARD_160: yönetim yetki tabloları eksik (047/073 beklenir).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid =
      'public.academic_calendar_has_permission(text)'::regprocedure) THEN
    RAISE EXCEPTION 'GUARD_160: academic_calendar_has_permission yok (073 beklenir).';
  END IF;

  -- 8) Güvenlik matrisi probe'ları (157/SEC-1/158/151 — koruyarak ilerle)
  IF has_table_privilege('anon', 'public.questions', 'SELECT') THEN
    RAISE EXCEPTION 'GUARD_160: 157 geri sarilmiş (anon questions SELECT).';
  END IF;
  IF has_function_privilege('authenticated',
      'public.get_internal_correct_answer(uuid)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'GUARD_160: SEC-1 geri sarildi.';
  END IF;
  IF (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public'
      AND indexname IN ('uq_question_vaults_weekly_scope', 'uq_question_active_single_vault')) <> 2 THEN
    RAISE EXCEPTION 'GUARD_160: 158/151 koruma indexleri eksik.';
  END IF;

  -- 9) Kısmi önceki durum: tablo varsa ve satır taşıyorsa 160 kaydı da olmalı
  --    (EXISTS dinamik koşulur: ilk uygulamada tablo yokken plan derlenmez)
  IF to_regclass('public.curriculum_subtopic_week_map') IS NOT NULL THEN
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.curriculum_subtopic_week_map)' INTO v_has;
    IF v_has
       AND NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '160') THEN
      RAISE EXCEPTION 'GUARD_160: eşleme tablosu var ama 160 kaydı yok — kısmi durum, elle incele.';
    END IF;
  END IF;

  RAISE NOTICE 'GUARD_160 OK: zincir + takvim + agac + bant + yetki + guvenlik on kosullari saglam';
END
$guard$;

-- ------------------------------------------------------------
-- 1) YETİ KODU + ROL BAĞLAMA (073 idiomu, idempotent)
-- ------------------------------------------------------------
INSERT INTO public.admin_permissions (permission_code, name, description)
VALUES (
  'curriculum_week_map.manage',
  'Mufredat Hafta Eslemesini Yonet',
  'Alt konu -> ogretim haftasi eslemesini goruntuler ve tahmini eslemeleri onaylar.'
)
ON CONFLICT (permission_code) DO UPDATE
SET name = excluded.name, description = excluded.description;

INSERT INTO public.admin_role_permissions (role_id, permission_id)
SELECT ar.id, ap.id
FROM public.admin_roles ar
CROSS JOIN public.admin_permissions ap
WHERE ar.role_code IN ('super_admin', 'content_admin')
  AND ar.is_active = true
  AND ap.permission_code = 'curriculum_week_map.manage'
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------
-- 2) TABLO — curriculum_subtopic_week_map (yıllık, alt konu başına tek satır)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.curriculum_subtopic_week_map (
  id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academic_year                 text NOT NULL CHECK (academic_year ~ '^[0-9]{4}-[0-9]{4}$'),
  grade_level                   smallint NOT NULL CHECK (grade_level BETWEEN 9 AND 12),
  subject_id                    uuid NOT NULL REFERENCES public.subjects (id) ON DELETE RESTRICT,
  curriculum_version_id         uuid NOT NULL REFERENCES public.curriculum_versions (id) ON DELETE RESTRICT,
  topic_id                      uuid NOT NULL REFERENCES public.topics (id) ON DELETE RESTRICT,
  subtopic_id                   uuid NOT NULL REFERENCES public.subtopics (id) ON DELETE RESTRICT,
  official_order                integer NOT NULL CHECK (official_order >= 1),
  first_instruction_week        smallint NOT NULL CHECK (first_instruction_week >= 1),
  planned_week_band             int4range NOT NULL,
  repeat_from_instruction_week  smallint NOT NULL CHECK (repeat_from_instruction_week >= 1),
  mapping_confidence            text NOT NULL CHECK (mapping_confidence IN
                                  ('resmi_dogrudan', 'resmi_dolayli', 'tahmini_onay_bekliyor')),
  evidence_kind                 text NOT NULL CHECK (evidence_kind IN
                                  ('meb_yillik_plan_dogrulanmis',
                                   'resmi_ders_saati_turetilmis',
                                   'okul_plani_duz_esit_dagilim')),
  source_url                    text,
  source_note                   text,
  approved_by                   uuid REFERENCES auth.users (id) ON DELETE RESTRICT,
  approved_at                   timestamptz,
  created_at                    timestamptz NOT NULL DEFAULT now(),
  updated_at                    timestamptz NOT NULL DEFAULT now(),
  -- resmî statüm kanıtsız olamaz (ek-kural: doğrulanmış kaynak zorunlu)
  CHECK (mapping_confidence = 'tahmini_onay_bekliyor' OR source_url IS NOT NULL),
  -- kanıt tipi ile güven düzeyi tutarlı: yalnız DOĞRULANMIŞ yıllık plan
  -- resmî güven statüsü taşıyabilir
  CHECK (mapping_confidence = 'tahmini_onay_bekliyor'
         OR evidence_kind = 'meb_yillik_plan_dogrulanmis'),
  -- tahmini satır doğrulanmış-yıllık-plan kanıtı iddia edemez (tek yönlü
  -- yükseltme yönetici akışıyladır; seed bunu ihlal edemez)
  CHECK (evidence_kind <> 'meb_yillik_plan_dogrulanmis'
         OR mapping_confidence <> 'tahmini_onay_bekliyor'),
  -- onay cifti ayrilamaz
  CHECK ((approved_by IS NULL) = (approved_at IS NULL)),
  -- tekrara giris kendi acilisindan geriye olamaz (gelecek konuyu tekrar
  -- kilifiyla acmaya kapali)
  CHECK (repeat_from_instruction_week <= first_instruction_week),
  CHECK (lower(planned_week_band) >= 1 AND NOT isempty(planned_week_band)),
  UNIQUE (academic_year, subtopic_id),
  UNIQUE (academic_year, grade_level, subject_id, official_order)
);

-- ------------------------------------------------------------
-- 3) TUTARLILIK TRIGGER'I — sınıf/ders/sürüm uyumsuz eşleme reddi
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_subtopic_week_map_consistency()
RETURNS trigger
LANGUAGE plpgsql
AS $cons$
DECLARE
  t    public.topics%ROWTYPE;
  st   public.subtopics%ROWTYPE;
  vmin int;
  vmax int;
  nsl  int;
BEGIN
  SELECT stx.* INTO st FROM public.subtopics stx WHERE stx.id = NEW.subtopic_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ESLEME_160: alt konu bulunamadi (%).', NEW.subtopic_id
      USING ERRCODE = '23514';
  END IF;
  SELECT ttx.* INTO t FROM public.topics ttx WHERE ttx.id = st.topic_id;
  IF t.id IS DISTINCT FROM NEW.topic_id
     OR t.subject_id IS DISTINCT FROM NEW.subject_id
     OR t.grade_level IS DISTINCT FROM NEW.grade_level
     OR t.curriculum_version_id IS DISTINCT FROM NEW.curriculum_version_id THEN
    RAISE EXCEPTION 'ESLEME_160: sinif/ders/mufredat-surumu agac gercekligiyle celisiyor (subtopic=%).', NEW.subtopic_id
      USING ERRCODE = '23514';
  END IF;
  IF NOT st.is_active OR NOT t.is_active THEN
    RAISE EXCEPTION 'ESLEME_160: pasif agac dugumu eslenemez (subtopic=%).', NEW.subtopic_id
      USING ERRCODE = '23514';
  END IF;

  -- Yıl MEB metadata'sız eşlenemez (159 üç-durumlu kapısı; fail-closed)
  SELECT coalesce(min(aw.instruction_week_number), -1),
         coalesce(max(aw.instruction_week_number), -1),
         count(*) FILTER (WHERE aw.new_topic_allowed)
    INTO vmin, vmax, nsl
  FROM public.academic_weeks aw
  WHERE aw.academic_year = NEW.academic_year
    AND aw.instruction_week_number IS NOT NULL
    AND aw.week_kind IS NOT NULL;
  IF vmax < 1 OR nsl < 1 THEN
    RAISE EXCEPTION 'ESLEME_160: % yilinda MEB ogretim-haftasi sayaci yok (159 metadata beklenir).', NEW.academic_year
      USING ERRCODE = '23514';
  END IF;
  IF NEW.first_instruction_week NOT BETWEEN vmin AND vmax THEN
    RAISE EXCEPTION 'ESLEME_160: first_instruction_week % (%) yil araligi disinda [%..%].',
      NEW.first_instruction_week, NEW.academic_year, vmin, vmax
      USING ERRCODE = '23514';
  END IF;
  IF NEW.repeat_from_instruction_week NOT BETWEEN vmin AND vmax THEN
    RAISE EXCEPTION 'ESLEME_160: repeat_from_instruction_week % yil araligi disinda.',
      NEW.repeat_from_instruction_week
      USING ERRCODE = '23514';
  END IF;
  IF lower(NEW.planned_week_band) < vmin
     OR (NOT upper_inf(NEW.planned_week_band) AND upper(NEW.planned_week_band) > vmax + 1) THEN
    RAISE EXCEPTION 'ESLEME_160: planlanan bant yil I araligi disinda.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END
$cons$;

REVOKE EXECUTE ON FUNCTION public.enforce_subtopic_week_map_consistency()
  FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_subtopic_week_map_consistency
  ON public.curriculum_subtopic_week_map;
CREATE TRIGGER trg_subtopic_week_map_consistency
  BEFORE INSERT OR UPDATE ON public.curriculum_subtopic_week_map
  FOR EACH ROW EXECUTE FUNCTION public.enforce_subtopic_week_map_consistency();

-- ------------------------------------------------------------
-- 4) INDEKSLER (161 dağıtım motoru + etki sorgusu için)
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_swmap_pair_first_i
  ON public.curriculum_subtopic_week_map
     (academic_year, grade_level, subject_id, first_instruction_week);
CREATE INDEX IF NOT EXISTS idx_swmap_topic
  ON public.curriculum_subtopic_week_map (topic_id);
CREATE INDEX IF NOT EXISTS idx_swmap_version
  ON public.curriculum_subtopic_week_map (curriculum_version_id);

-- ------------------------------------------------------------
-- 5) RLS + ACL — öğrenci yüzeyi YOK (158/meb_holiday_days kalıbı)
-- ------------------------------------------------------------
ALTER TABLE public.curriculum_subtopic_week_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curriculum_subtopic_week_map FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.curriculum_subtopic_week_map FROM public, anon, authenticated;
GRANT SELECT ON public.curriculum_subtopic_week_map TO service_role;

-- ------------------------------------------------------------
-- 5b) TABLO — curriculum_week_map_verification (FIX-160-A K2, APPEND-ONLY)
--     Resmî kaynak doğrulama izleri: kurum + URL + belge adı/eğitim-yılı +
--     dosya SHA-256 (veya değişmez kanıt kimliği) + belge içi konum +
--     sınıf/ders/tema/alt-konu/hafta kimlikleri + doğrulayan + zaman.
--     URL veya serbest metin TEK BAŞINA kanıt DEĞİLDİR (sha/proof zorunlu).
--     DB yalnız KANIT BİÇİMİNİ ve yetkili işlemi doğrular; belgenin gerçekten
--     incelendiğinin mutlak garantisi DEĞİLDİR (güven sınırı — rapor §2).
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.curriculum_week_map_verification (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  map_id                   uuid NOT NULL REFERENCES public.curriculum_subtopic_week_map (id)
                           ON DELETE RESTRICT,
  source_institution       text NOT NULL CHECK (length(btrim(source_institution)) >= 3),
  document_url             text NOT NULL CHECK (document_url ~* '^https?://'),
  document_title           text NOT NULL CHECK (length(btrim(document_title)) >= 3),
  document_academic_year   text NOT NULL CHECK (document_academic_year ~ '^[0-9]{4}-[0-9]{4}$'),
  document_sha256          text CHECK (document_sha256 ~ '^[0-9a-f]{64}$'),
  proof_ref_id             text CHECK (length(btrim(proof_ref_id)) >= 8),
  -- SHA-256 VEYA değişmez kanıt kimliği EN AZ BİRİ zorunlu (K2 çekirdeği):
  CONSTRAINT verification_proof_required
    CHECK (document_sha256 IS NOT NULL OR proof_ref_id IS NOT NULL),
  document_location        text NOT NULL CHECK (length(btrim(document_location)) >= 2),
  grade_level              smallint NOT NULL CHECK (grade_level BETWEEN 9 AND 12),
  subject_id               uuid NOT NULL REFERENCES public.subjects (id) ON DELETE RESTRICT,
  topic_id                 uuid NOT NULL REFERENCES public.topics (id) ON DELETE RESTRICT,
  subtopic_id              uuid NOT NULL REFERENCES public.subtopics (id) ON DELETE RESTRICT,
  first_instruction_week   smallint NOT NULL CHECK (first_instruction_week >= 1),
  verified_by              uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  verified_at              timestamptz NOT NULL DEFAULT now(),
  created_at               timestamptz NOT NULL DEFAULT now()
);

-- Bir eşleme satırı bir kez resmî doğrulanır (yeniden doğrulama = yeni sürüm
-- akışı; mevcut çekirdek değişmezlik sözü).
CREATE UNIQUE INDEX IF NOT EXISTS uq_cwmv_single_verification
  ON public.curriculum_week_map_verification (map_id);

-- Append-only: yayınlanmış kanıt silinmez/değiştirilmez (QA Q10 deseni).
CREATE OR REPLACE FUNCTION public.enforce_week_map_verification_immutable()
RETURNS trigger LANGUAGE plpgsql AS $verim$
BEGIN
  RAISE EXCEPTION 'DOGRULAMA_160: resmî kaynak doğrulama kaydı değiştirilemez/silinemez.'
    USING ERRCODE = '23514';
END
$verim$;

DROP TRIGGER IF EXISTS trg_cwmv_immutable ON public.curriculum_week_map_verification;
CREATE TRIGGER trg_cwmv_immutable
  BEFORE UPDATE OR DELETE ON public.curriculum_week_map_verification
  FOR EACH ROW EXECUTE FUNCTION public.enforce_week_map_verification_immutable();

REVOKE EXECUTE ON FUNCTION public.enforce_week_map_verification_immutable()
  FROM PUBLIC, anon, authenticated;

ALTER TABLE public.curriculum_week_map_verification ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.curriculum_week_map_verification FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.curriculum_week_map_verification FROM public, anon, authenticated;
GRANT SELECT ON public.curriculum_week_map_verification TO service_role;

-- ------------------------------------------------------------
-- 6) TOHUM_160A — Matematik: DÖP resmî ders saati bandı türetmesi.
--    Slot = new_topic_allowed öğretim haftaları; alt konular bandın slotlarına
--    resmî sıra ordinaliyle eşit aralıklı yerleşir (floor kuralı, deterministik).
--    EK KURAL: hafta KESİN değil ÖNERİDİR → tahmini_onay_bekliyor +
--    evidence_kind='resmi_ders_saati_turetilmis' + DÖP URL kanıtı.
-- ------------------------------------------------------------
INSERT INTO public.curriculum_subtopic_week_map (
  academic_year, grade_level, subject_id, curriculum_version_id, topic_id,
  subtopic_id, official_order, first_instruction_week, planned_week_band,
  repeat_from_instruction_week, mapping_confidence, evidence_kind,
  source_url, source_note
)
WITH slots AS (
  SELECT aw.instruction_week_number AS i
  FROM public.academic_weeks aw
  WHERE aw.academic_year = '2026-2027'
    AND aw.instruction_week_number IS NOT NULL
    AND aw.new_topic_allowed
),
items AS (
  SELECT i.grade_level, i.topic_id, i.start_week, i.end_week,
         dense_rank() OVER (
           PARTITION BY i.grade_level, i.topic_id ORDER BY i.start_week
         ) AS wr
  FROM public.curriculum_schedule_items i
  JOIN public.subjects s ON s.id = i.subject_id
  WHERE i.is_active AND s.slug = 'matematik' AND i.topic_id IS NOT NULL
),
win_k AS (
  SELECT g.grade_level, g.topic_id, g.wr,
         min(g.start_week) AS k_lo, min(g.end_week) AS k_hi
  FROM items g
  GROUP BY g.grade_level, g.topic_id, g.wr
),
win AS (
  SELECT wk.grade_level, wk.topic_id, wk.wr,
         (SELECT min(aw.instruction_week_number) FROM public.academic_weeks aw
           WHERE aw.academic_year = '2026-2027'
             AND aw.instruction_week_number IS NOT NULL
             AND aw.week >= wk.k_lo
             AND (wk.k_hi IS NULL OR aw.week < wk.k_hi)) AS i_lo,
         (SELECT max(aw.instruction_week_number) FROM public.academic_weeks aw
           WHERE aw.academic_year = '2026-2027'
             AND aw.instruction_week_number IS NOT NULL
             AND aw.week >= wk.k_lo
             AND (wk.k_hi IS NULL OR aw.week < wk.k_hi)) AS i_hi
  FROM win_k wk
),
win_ns AS (
  SELECT wns.grade_level, wns.topic_id, wns.wr, wns.i_lo, wns.i_hi,
         (SELECT count(*) FROM slots sl
           WHERE sl.i BETWEEN wns.i_lo AND wns.i_hi) AS ns
  FROM win wns
),
bind(n, win_no, plan_ord) AS (
  VALUES
    ('Trigonometrik Fonksiyonlar ve Nitel Özellikleri'::text, 1, 1),
    ('Trigonometrik Fonksiyonlarla İfade Edilebilen Denklemler İçeren Problemler', 1, 2),
    ('Üstel Fonksiyonlar ve Nitel Özellikleri', 2, 3),
    ('Üstel Fonksiyonların Ters Fonksiyonları', 2, 4),
    ('Logaritmik Fonksiyonlar ve Nitel Özellikleri', 2, 5),
    ('Üstel ve Logaritmik Fonksiyonlarla İfade Edilebilen Denklem ve Eşitsizlikler İçeren Problemler', 2, 6),
    ('Fonksiyonların Bileşkesi', 3, 7),
    ('Fonksiyonlarda Dört İşlem', 3, 8)
),
mat113 AS (
  SELECT t.id AS topic_id
  FROM public.topics t
  JOIN public.subjects s ON s.id = t.subject_id
  WHERE s.slug = 'matematik' AND t.grade_level = 11
    AND t.name = 'MAT.11.3 NİCELİKLER VE DEĞİŞİMLER'
),
d AS (
  SELECT t.grade_level, t.subject_id, t.curriculum_version_id, t.id AS topic_id,
         st.id AS subtopic_id,
         coalesce(b.win_no, 1) AS wr,
         coalesce(b.plan_ord, 1000 + st.sort_order) AS pord,
         row_number() OVER (
           PARTITION BY t.grade_level, t.id, coalesce(b.win_no, 1)
           ORDER BY coalesce(b.plan_ord, 1000 + st.sort_order), st.id
         ) - 1 AS idx,
         count(*) OVER (
           PARTITION BY t.grade_level, t.id, coalesce(b.win_no, 1)
         ) AS m
  FROM public.subtopics st
  JOIN public.topics t ON t.id = st.topic_id
  JOIN public.subjects s ON s.id = t.subject_id
  LEFT JOIN mat113 m ON m.topic_id = t.id
  LEFT JOIN bind b ON b.n = st.name AND m.topic_id IS NOT NULL
  WHERE s.slug = 'matematik' AND st.is_active AND t.is_active
),
placed AS (
  SELECT d.grade_level, d.subject_id, d.curriculum_version_id, d.topic_id,
         d.subtopic_id, wi.i_lo, wi.i_hi,
         row_number() OVER (
           PARTITION BY d.grade_level ORDER BY wi.i_lo, wi.wr, d.pord
         ) AS og,
         f.first_i
  FROM d
  JOIN win_ns wi
    ON wi.topic_id = d.topic_id AND wi.grade_level = d.grade_level AND wi.wr = d.wr
  CROSS JOIN LATERAL (
    SELECT sl.i AS first_i
    FROM slots sl
    WHERE sl.i BETWEEN wi.i_lo AND wi.i_hi
    ORDER BY sl.i
    OFFSET floor(d.idx::numeric * wi.ns::numeric / d.m)::int
    LIMIT 1
  ) f
),
vers AS (
  SELECT v.id, coalesce(v.source_url, 'https://mufredat.meb.gov.tr/') AS url
  FROM public.curriculum_versions v
)
SELECT '2026-2027', p.grade_level, p.subject_id, p.curriculum_version_id, p.topic_id,
       p.subtopic_id, p.og, p.first_i::smallint,
       int4range(p.i_lo, p.i_hi + 1),
       p.first_i::smallint,
       'tahmini_onay_bekliyor',
       'resmi_ders_saati_turetilmis',
       vers.url,
       'MEB DÖP resmî ders saatleri + migration 111 tema bandi; bant-ici alt-konu haftalari ONE RIDIR (2026-2027-matematik-yillik-konu-plani.md kendi uyarisi: varsayim). Resmî haftalik plan dosyasiyla dogrulanmadi (GAP-160-A).'
FROM placed p
JOIN vers ON vers.id = p.curriculum_version_id
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------
-- 7) TOHUM_160B — Matematik dışı 24 çift: okul-planı düz eşit dağılım.
--    Master plan §6 + ek-kural: resmî haftalık plan kaynağı YOK →
--    tahmini_onay_bekliyor; öğrenciye otomatik açılmaz.
-- ------------------------------------------------------------
INSERT INTO public.curriculum_subtopic_week_map (
  academic_year, grade_level, subject_id, curriculum_version_id, topic_id,
  subtopic_id, official_order, first_instruction_week, planned_week_band,
  repeat_from_instruction_week, mapping_confidence, evidence_kind,
  source_url, source_note
)
WITH slots AS (
  SELECT aw.instruction_week_number AS i,
         count(*) OVER () AS ns
  FROM public.academic_weeks aw
  WHERE aw.academic_year = '2026-2027'
    AND aw.instruction_week_number IS NOT NULL
    AND aw.new_topic_allowed
),
ord AS (
  SELECT t.grade_level, t.subject_id, t.curriculum_version_id, t.id AS topic_id,
         st.id AS subtopic_id,
         row_number() OVER (
           PARTITION BY t.grade_level, t.subject_id
           ORDER BY t.sort_order, st.sort_order, st.id
         ) - 1 AS idx,
         count(*) OVER (PARTITION BY t.grade_level, t.subject_id) AS m
  FROM public.subtopics st
  JOIN public.topics t ON t.id = st.topic_id
  JOIN public.subjects s ON s.id = t.subject_id
  WHERE s.slug <> 'matematik' AND st.is_active AND t.is_active
)
SELECT '2026-2027', o.grade_level, o.subject_id, o.curriculum_version_id, o.topic_id,
       o.subtopic_id,
       (o.idx + 1)::int,
       f.first_i::smallint,
       int4range(f.first_i, coalesce(f.next_i, (SELECT max(i) FROM slots) + 1)),
       f.first_i::smallint,
       'tahmini_onay_bekliyor',
       'okul_plani_duz_esit_dagilim',
       NULL,
       'tahmini okul-plani eslemesi: alt-konu sayisi yeni-konu-acik ogretim haftalarina esit bolundu (master plan §6); resmî haftalik plan kaynagi YOK (GAP-160-A) — yonetici onayı olmadan kullanilamaz'
FROM ord o
CROSS JOIN LATERAL (
  SELECT sl.i AS first_i,
         (SELECT min(sl2.i) FROM slots sl2 WHERE sl2.i > sl.i) AS next_i
  FROM slots sl
  ORDER BY sl.i
  OFFSET floor(o.idx::numeric * (SELECT max(sl3.ns) FROM slots sl3)::numeric / o.m)::int
  LIMIT 1
) f
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------
-- 8) MOTOR OKUMASI — curriculum_subtopic_week_state (definer; EXECUTE kapalı)
--    Görev §6 sorularının tek SQL cevabı:
--    Q1 kullanılabilir = new_this_week + opened_repeat (+held_pending havuzu)
--    Q2 ilk kez açılan = state='new_this_week'
--    Q3 tekrar havuzu  = state='opened_repeat' (first_I < güncel I)
--    Q4 engelleme      = state='locked_future' (yerleştirme RPC'i reddeder, 161)
--    Q5 tatil          = I sayacı durur → eşik kaymaz; hafta kapalıysa yeni
--                        açılış 'held_pending' olarak bekler, eşik DEĞİŞMEZ
--    Q6 etki sorgusu   = idx_swmap_pair_first_i üzerinden (rapor §6 deseni)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.curriculum_subtopic_week_state(
  p_grade_level smallint,
  p_subject_id  uuid,
  p_as_of_date  date
)
RETURNS TABLE (
  subtopic_id                  uuid,
  topic_id                     uuid,
  official_order               integer,
  first_instruction_week       smallint,
  repeat_from_instruction_week smallint,
  mapping_confidence           text,
  evidence_kind                text,
  is_usable                    boolean,
  state                        text,
  academic_year                text,
  calendar_week                integer,
  instruction_week             smallint,
  week_kind                    text,
  new_topic_allowed            boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_year  text;
  v_week  integer;
  v_kind  text;
  v_allow boolean;
  v_i     smallint;
  v_start date;
BEGIN
  SELECT aw.academic_year, aw.week, aw.week_kind, aw.new_topic_allowed,
         aw.instruction_week_number, aw.starts_at
    INTO v_year, v_week, v_kind, v_allow, v_i, v_start
  FROM public.academic_weeks aw
  WHERE aw.starts_at <= p_as_of_date AND p_as_of_date < aw.ends_at
    AND NOT (aw.requires_admin_activation AND aw.activated_at IS NULL)
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN;  -- takvim disi / aktivasyon bekleyen hafta → fail-closed bos
  END IF;
  IF v_kind IS NULL THEN
    v_allow := FALSE;  -- 159 üc-durumlu kapi: atanmamis hafta yeni konu acamaz
  END IF;
  IF v_i IS NULL THEN
    SELECT max(aw2.instruction_week_number) INTO v_i
    FROM public.academic_weeks aw2
    WHERE aw2.academic_year = v_year
      AND aw2.instruction_week_number IS NOT NULL
      AND aw2.starts_at < v_start;
    IF v_i IS NULL THEN
      v_i := 0;  -- yilin ilk ögretim haftasindan önce: henuz hicbir sey acilmis degil
    END IF;
  END IF;

  RETURN QUERY
  SELECT m.subtopic_id, m.topic_id, m.official_order,
         m.first_instruction_week, m.repeat_from_instruction_week,
         m.mapping_confidence, m.evidence_kind,
         -- FIX-160-A (K1): yönetici onayı TEK BAŞINA erişim VERMEZ. Öğrenci
         -- erişimi için resmî statü (yalnız curriculum_week_map_verify ile ve
         -- resmî belge kanıtıyla kazanılır) + haftanın gelmesi GEREKLİDİR.
         (m.mapping_confidence IN ('resmi_dogrudan', 'resmi_dolayli')
          AND EXISTS (SELECT 1 FROM public.curriculum_week_map_verification v
                       WHERE v.map_id = m.id)
          AND (m.first_instruction_week < v_i
               OR (m.first_instruction_week = v_i AND coalesce(v_allow, FALSE)))) AS is_usable,
         CASE
           WHEN m.mapping_confidence = 'tahmini_onay_bekliyor'
                AND m.approved_at IS NULL THEN 'locked_unapproved'
           WHEN m.mapping_confidence = 'tahmini_onay_bekliyor'
                AND m.approved_at IS NOT NULL THEN 'approved_pending_official'
           WHEN m.first_instruction_week > v_i THEN 'locked_future'
           WHEN m.first_instruction_week = v_i AND coalesce(v_allow, FALSE) THEN 'new_this_week'
           WHEN m.first_instruction_week = v_i THEN 'held_pending'
           ELSE 'opened_repeat'
         END AS state,
         v_year, v_week, v_i, coalesce(v_kind, 'atanmamis'),
         coalesce(v_allow, FALSE)
  FROM public.curriculum_subtopic_week_map m
  JOIN public.subtopics st ON st.id = m.subtopic_id AND st.is_active
  JOIN public.topics t     ON t.id = m.topic_id AND t.is_active
  WHERE m.academic_year = v_year
    AND m.grade_level = p_grade_level
    AND m.subject_id = p_subject_id;
END
$fn$;

-- ------------------------------------------------------------
-- 9) YÖNETİCİ ONAY RPC'si (073 yetki kalıbı; idempotent; fail-closed)
--    Yalnız tahmini satırlar onaylanabilir; resmî statü reddedilir;
--    farklı yöneticinin çift onayı engellenir.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.curriculum_week_map_approve(p_map_id uuid)
RETURNS public.curriculum_subtopic_week_map
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $appr$
DECLARE
  r public.curriculum_subtopic_week_map%ROWTYPE;
BEGIN
  IF NOT public.academic_calendar_has_permission('curriculum_week_map.manage') THEN
    RAISE EXCEPTION 'Onay icin curriculum_week_map.manage yetkisi gerekli.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO r FROM public.curriculum_subtopic_week_map WHERE id = p_map_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Eşleme kaydi bulunamadi.' USING ERRCODE = 'P0002';
  END IF;
  IF r.mapping_confidence IN ('resmi_dogrudan', 'resmi_dolayli') THEN
    RAISE EXCEPTION 'Resmî kaynakli eşleme zaten gecerli; ayrica onay beklenmez.'
      USING ERRCODE = '23514';
  END IF;
  IF r.approved_at IS NOT NULL THEN
    IF r.approved_by = auth.uid() THEN
      RETURN r;  -- idempotent: ayni yoneticinin tekrar onayi zararsiz
    END IF;
    RAISE EXCEPTION 'Eşleme baska bir yonetici tarafindan onaylanmis.'
      USING ERRCODE = '23514';
  END IF;

  UPDATE public.curriculum_subtopic_week_map
     SET approved_by = auth.uid(), approved_at = now(), updated_at = now()
   WHERE id = p_map_id
  RETURNING * INTO r;
  RETURN r;
END
$appr$;

-- ------------------------------------------------------------
-- 9b) YETİ + RPC — curriculum_week_map_verify (FIX-160-A K2)
--     Resmî kaynak doğrulaması: kanıt biçimi (kurum, https URL, belge adı,
--     eğitim yılı, SHA-256/değişmez kimlik, belge içi konum) + kimlik
--     eşleşmesi (sınıf/ders/tema/alt-konu/hafta birebir map satırıyla aynı)
--     zorunlu. Başarılı doğrulama: kanıt kaydı (append-only) + satırı
--     'resmi_dolayli' + 'meb_yillik_plan_dogrulanmis' statüsüne yükseltir.
--     NOT: DB kanıtın BİÇİMİNİ doğrular; belgenin gerçekten incelendiğinin
--     mutlak garantisi değildir — bu yetkiyi kullanan kişiden güven bekler.
-- ------------------------------------------------------------
INSERT INTO public.admin_permissions (permission_code, name, description)
VALUES (
  'curriculum_week_map.verify',
  'Mufredat Hafta Eslemesini Resmî Kaynakla Dogrula',
  'Alt konu hafta eşlemesini resmî MEB belge kanıtıyla doğrular ve resmî statüye yükseltir.'
)
ON CONFLICT (permission_code) DO UPDATE
SET name = excluded.name, description = excluded.description;

INSERT INTO public.admin_role_permissions (role_id, permission_id)
SELECT ar.id, ap.id
FROM public.admin_roles ar
CROSS JOIN public.admin_permissions ap
WHERE ar.role_code IN ('super_admin', 'content_admin')
  AND ar.is_active = true
  AND ap.permission_code = 'curriculum_week_map.verify'
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.curriculum_week_map_verify(
  p_map_id                  uuid,
  p_source_institution      text,
  p_document_url            text,
  p_document_title          text,
  p_document_academic_year  text,
  p_document_sha256         text,
  p_proof_ref_id            text,
  p_document_location       text,
  p_grade_level             smallint,
  p_subject_id              uuid,
  p_topic_id                uuid,
  p_subtopic_id             uuid,
  p_first_instruction_week  smallint
)
RETURNS public.curriculum_week_map_verification
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $ver$
DECLARE
  r     public.curriculum_subtopic_week_map%ROWTYPE;
  v_out public.curriculum_week_map_verification%ROWTYPE;
BEGIN
  IF NOT public.academic_calendar_has_permission('curriculum_week_map.verify') THEN
    RAISE EXCEPTION 'Dogrulama icin curriculum_week_map.verify yetkisi gerekli.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO r FROM public.curriculum_subtopic_week_map WHERE id = p_map_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Eşleme kaydi bulunamadi.' USING ERRCODE = 'P0002';
  END IF;

  -- Zaten resmî: çift doğrulama yok (tekil kanıt indeksi de korur).
  IF r.mapping_confidence IN ('resmi_dogrudan', 'resmi_dolayli') THEN
    RAISE EXCEPTION 'Eşleme zaten resmî statüde; yeniden dogrulama yeni sürüm akisidir.'
      USING ERRCODE = '23514';
  END IF;

  -- Kanıt biçimi: URL/serbest metin tek başına YETMEZ — sha256 veya kanıt kimliği.
  IF p_document_sha256 IS NULL AND p_proof_ref_id IS NULL THEN
    RAISE EXCEPTION 'KANIT_160: SHA-256 veya degismez kanit kimligi zorunlu; URL/serbest metin tek basina kanit degildir.'
      USING ERRCODE = '23514';
  END IF;
  IF p_document_sha256 IS NOT NULL AND p_document_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'KANIT_160: document_sha256 64-hanelik kucuk harf hex olmali.'
      USING ERRCODE = '23514';
  END IF;
  IF p_document_url IS NULL OR p_document_url !~* '^https?://' THEN
    RAISE EXCEPTION 'KANIT_160: belge URL si https/http olmali.'
      USING ERRCODE = '23514';
  END IF;
  IF coalesce(length(btrim(p_source_institution)),0) < 3
     OR coalesce(length(btrim(p_document_title)),0) < 3
     OR coalesce(length(btrim(p_document_location)),0) < 2 THEN
    RAISE EXCEPTION 'KANIT_160: kurum/belge adi/belge ici konum alanlari eksik.'
      USING ERRCODE = '23514';
  END IF;

  -- Kimlik eşleşmesi: yanlış sınıf/ders/tema/alt-konu/hafta kanıtı reddedilir.
  IF p_grade_level IS DISTINCT FROM r.grade_level
     OR p_subject_id IS DISTINCT FROM r.subject_id
     OR p_topic_id IS DISTINCT FROM r.topic_id
     OR p_subtopic_id IS DISTINCT FROM r.subtopic_id
     OR p_first_instruction_week IS DISTINCT FROM r.first_instruction_week THEN
    RAISE EXCEPTION 'KANIT_160: kimlik alanlari esleme satiriyla celisiyor.'
      USING ERRCODE = '23514';
  END IF;
  IF p_document_academic_year IS DISTINCT FROM r.academic_year THEN
    RAISE EXCEPTION 'KANIT_160: belgenin egitim yili esleme yiliyla celisiyor.'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.curriculum_week_map_verification (
    map_id, source_institution, document_url, document_title,
    document_academic_year, document_sha256, proof_ref_id, document_location,
    grade_level, subject_id, topic_id, subtopic_id, first_instruction_week,
    verified_by
  ) VALUES (
    r.id, btrim(p_source_institution), btrim(p_document_url), btrim(p_document_title),
    p_document_academic_year, lower(p_document_sha256),
    nullif(btrim(coalesce(p_proof_ref_id,'')), ''), btrim(p_document_location),
    r.grade_level, r.subject_id, r.topic_id, r.subtopic_id,
    r.first_instruction_week, auth.uid()
  )
  RETURNING * INTO v_out;

  -- Statü yükseltmesi: tek transaction; tetikleyici kimlik tutarlılığını yine zorlar.
  UPDATE public.curriculum_subtopic_week_map
     SET mapping_confidence   = 'resmi_dolayli',
         evidence_kind        = 'meb_yillik_plan_dogrulanmis',
         source_url           = btrim(p_document_url),
         source_note          = coalesce(source_note, '')
                                || ' | verify: ' || btrim(p_document_title)
                                || ' (' || btrim(p_source_institution) || ', '
                                || btrim(p_document_location) || ')',
         approved_by          = coalesce(approved_by, auth.uid()),
         approved_at          = coalesce(approved_at, now()),
         updated_at           = now()
   WHERE id = r.id;

  RETURN v_out;
END
$ver$;

-- ------------------------------------------------------------
-- 10) EXECUTE MATRİSİ
-- ------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.curriculum_subtopic_week_state(smallint, uuid, date)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.curriculum_subtopic_week_state(smallint, uuid, date)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.curriculum_week_map_approve(uuid)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.curriculum_week_map_approve(uuid)
  TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.curriculum_week_map_verify(uuid,text,text,text,text,text,text,text,smallint,uuid,uuid,uuid,smallint)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.curriculum_week_map_verify(uuid,text,text,text,text,text,text,text,smallint,uuid,uuid,uuid,smallint)
  TO authenticated, service_role;

COMMENT ON TABLE public.curriculum_subtopic_week_map IS
  'Alt konu → MEB öğretim haftası eşlemesi (159 sayaçları; yıllık, alt konu başına tek satır). Tohumda TÜMÜ tahmini_onay_bekliyor (MEB resmî haftalık plan dosyası doğrulanmadı — GAP-160-A); kanıt kalitesi evidence_kind ile ayrılır. Öğrenci yüzeyi YOK (RLS+FORCE, 0 politika, istemci haksız).';
COMMENT ON FUNCTION public.curriculum_subtopic_week_state(smallint, uuid, date) IS
  'Sunucu tarafı eşleme okuyucu (definer; EXECUTE yalnız service_role). locked_future/locked_unapproved fail-closed; tatilde I durur; K42 aktivasyonsuz görünmez.';
COMMENT ON FUNCTION public.curriculum_week_map_approve(uuid) IS
  'Yönetici BEYAN onayı (curriculum_week_map.manage; 073 kalıbı). FIX-160-A: TEK BAŞINA öğrenci erişimi SAĞLAMAZ — satır approved_pending_official durumunda KAPALI kalır; erişim için curriculum_week_map_verify ile resmî belge doğrulaması gerekir. Yalnız tahmini satırlar; resmî statü reddedilir; farklı yöneticinin çift onayı engelli.';
COMMENT ON FUNCTION public.curriculum_week_map_verify(uuid,text,text,text,text,text,text,text,smallint,uuid,uuid,uuid,smallint) IS
  'Resmî kaynak doğrulaması (curriculum_week_map.verify; FIX-160-A K2). Kanıt biçimi (kurum+https URL+belge adı/yıl+SHA-256/kanıt kimliği+belge içi konum) ve kimlik eşleşmesi zorunlu; append-only kanıt kaydı yazar ve satırı resmi_dolayli/meb_yillik_plan_dogrulanmis statüsüne yükseltir. DB kanıt biçimini doğrular; belgenin gerçek muhtevasının mutlak garantisi değildir.';
COMMENT ON TABLE public.curriculum_week_map_verification IS
  'FIX-160-A K2: resmî kaynak doğrulama kanıtları (append-only; immutable trigger). Motor is_usable bu tablonun VARLIĞINI şart koşar. Öğrenci yüzeyi YOK (RLS+FORCE, 0 politika).';

-- ------------------------------------------------------------
-- History — idempotent (151/158/159 deseni)
-- ------------------------------------------------------------
INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
SELECT '160', '160_subtopic_week_mapping', NULL
 WHERE NOT EXISTS (
   SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '160'
 );

-- ------------------------------------------------------------
-- FINAL_160 — fail-closed son matris
-- ------------------------------------------------------------
DO $fin$
DECLARE
  v1  bigint;
  v2  bigint;
  v3  bigint;
  bad bigint;
  evi text;
BEGIN
  -- 1) Kapsam: aktif alt konu evreni birebir eşlenmiş (her iki yönde)
  SELECT count(*) INTO v1 FROM public.subtopics st
    JOIN public.topics t ON t.id = st.topic_id
   WHERE st.is_active AND t.is_active;
  SELECT count(*) INTO v2 FROM public.curriculum_subtopic_week_map
   WHERE academic_year = '2026-2027';
  IF v2 <> v1 THEN
    RAISE EXCEPTION 'FINAL_160: esleme sayisi % != aktif alt konu %.', v2, v1;
  END IF;
  IF EXISTS (SELECT 1 FROM public.curriculum_subtopic_week_map m
             WHERE m.academic_year = '2026-2027'
               AND NOT EXISTS (SELECT 1 FROM public.subtopics st
                               JOIN public.topics t ON t.id = st.topic_id
                               WHERE st.id = m.subtopic_id AND st.is_active AND t.is_active)) THEN
    RAISE EXCEPTION 'FINAL_160: agaçta karşılığı olmayan eşleme satırı var.';
  END IF;

  -- 2) EK KURAL matrisi: tohumda hiçbir satır resmî statüde olamaz;
  --    Matematik = resmi_ders_saati_turetilmis + DÖP URL'i;
  --    diğerleri = okul_plani_duz_esit_dagilim; tohum self-onay yapamaz
  IF EXISTS (SELECT 1 FROM public.curriculum_subtopic_week_map
             WHERE academic_year = '2026-2027'
               AND mapping_confidence <> 'tahmini_onay_bekliyor') THEN
    RAISE EXCEPTION 'FINAL_160: dogrulanmamis hafta resmi statude kaydedilemez (ek-kural).';
  END IF;
  SELECT count(*) INTO bad FROM public.curriculum_subtopic_week_map m
    JOIN public.subjects s ON s.id = m.subject_id
   WHERE m.academic_year = '2026-2027'
     AND ((s.slug = 'matematik'
           AND (m.evidence_kind <> 'resmi_ders_saati_turetilmis' OR m.source_url IS NULL))
       OR (s.slug <> 'matematik'
           AND m.evidence_kind <> 'okul_plani_duz_esit_dagilim'));
  IF bad > 0 THEN
    RAISE EXCEPTION 'FINAL_160: kanit-tipi matrisi bozuk (% satir).', bad;
  END IF;
  IF EXISTS (SELECT 1 FROM public.curriculum_subtopic_week_map WHERE approved_at IS NOT NULL) THEN
    RAISE EXCEPTION 'FINAL_160: tohumda onayli satir bulunamaz (self-approval).';
  END IF;

  -- 3) Slot saflığı: hiçbir ilk-açılış yeni-konu-kapalı öğretim haftasına
  --    (ör. I32=K36 review) denk gelmez; tüm ilk-açılışlar I sayaç kümesinde
  IF EXISTS (SELECT 1 FROM public.curriculum_subtopic_week_map m
             WHERE m.academic_year = '2026-2027'
               AND NOT EXISTS (SELECT 1 FROM public.academic_weeks aw
                               WHERE aw.academic_year = m.academic_year
                                 AND aw.instruction_week_number = m.first_instruction_week
                                 AND aw.new_topic_allowed)) THEN
    RAISE EXCEPTION 'FINAL_160: ilk-acilis slot safligi bozuk (kapali haftaya açilis planlanmis).';
  END IF;

  -- 4) Matematik bant uyumu: her matematik satırı own temasının bir bandının
  --    I aralığında olmalı (yapısal üst sınır — kanıt seviyesinden bağımsız)
  SELECT count(*) INTO bad
  FROM public.curriculum_subtopic_week_map m
  JOIN public.subjects s ON s.id = m.subject_id
  WHERE m.academic_year = '2026-2027' AND s.slug = 'matematik'
    AND NOT EXISTS (
      SELECT 1
      FROM (SELECT wk.topic_id, wk.grade_level,
                   (SELECT min(aw.instruction_week_number) FROM public.academic_weeks aw
                     WHERE aw.academic_year = '2026-2027'
                       AND aw.instruction_week_number IS NOT NULL
                       AND aw.week >= wk.k_lo
                       AND (wk.k_hi IS NULL OR aw.week < wk.k_hi)) AS i_lo,
                   (SELECT max(aw.instruction_week_number) FROM public.academic_weeks aw
                     WHERE aw.academic_year = '2026-2027'
                       AND aw.instruction_week_number IS NOT NULL
                       AND aw.week >= wk.k_lo
                       AND (wk.k_hi IS NULL OR aw.week < wk.k_hi)) AS i_hi
            FROM (SELECT g.topic_id, g.grade_level, g.wr,
                         min(g.start_week) AS k_lo, min(g.end_week) AS k_hi
                  FROM (SELECT i.topic_id, i.grade_level, i.start_week, i.end_week,
                               dense_rank() OVER (PARTITION BY i.grade_level, i.topic_id
                                                  ORDER BY i.start_week) AS wr
                        FROM public.curriculum_schedule_items i
                        WHERE i.is_active AND i.topic_id IS NOT NULL) g
                  GROUP BY g.topic_id, g.grade_level, g.wr) wk) w2
      WHERE w2.topic_id = m.topic_id AND w2.grade_level = m.grade_level
        AND m.first_instruction_week BETWEEN w2.i_lo AND w2.i_hi)
    ;
  IF bad > 0 THEN
    RAISE EXCEPTION 'FINAL_160: bant disi matematik eşleme satırı %.', bad;
  END IF;

  -- 5) Ağaç tutarlılığı (trigger'a rağmen derinlemesine savunma)
  IF EXISTS (SELECT 1 FROM public.curriculum_subtopic_week_map m
             JOIN public.subtopics st ON st.id = m.subtopic_id
             JOIN public.topics t ON t.id = st.topic_id
             WHERE m.grade_level <> t.grade_level OR m.subject_id <> t.subject_id
                OR m.topic_id <> t.id OR m.curriculum_version_id <> t.curriculum_version_id) THEN
    RAISE EXCEPTION 'FINAL_160: agac-kimlik celiskisi var.';
  END IF;

  -- 6) official_order yoğunluğu (çift yok, boşluk yok)
  IF EXISTS (SELECT m.academic_year, m.grade_level, m.subject_id,
                    count(*) AS c, max(m.official_order) AS mo
             FROM public.curriculum_subtopic_week_map m
             GROUP BY 1, 2, 3 HAVING count(*) <> max(m.official_order)) THEN
    RAISE EXCEPTION 'FINAL_160: official_order sira yogunlugu bozuk.';
  END IF;

  -- 7) MAT.11.3 pencere bölünmesi: 2/4/2 (plan §5; I eşikleri K25/K33 başlangıçları)
  SELECT count(*) FILTER (WHERE m.first_instruction_week < ev2.k25),
         count(*) FILTER (WHERE m.first_instruction_week >= ev2.k25
                            AND m.first_instruction_week < ev2.k33),
         count(*) FILTER (WHERE m.first_instruction_week >= ev2.k33)
    INTO v1, v2, v3
  FROM public.curriculum_subtopic_week_map m
  JOIN public.topics t ON t.id = m.topic_id
  JOIN public.subjects s ON s.id = t.subject_id
  CROSS JOIN LATERAL (
    SELECT (SELECT min(aw.instruction_week_number) FROM public.academic_weeks aw
             WHERE aw.academic_year = '2026-2027' AND aw.week = 25) AS k25,
           (SELECT min(aw.instruction_week_number) FROM public.academic_weeks aw
             WHERE aw.academic_year = '2026-2027' AND aw.week = 33) AS k33
  ) ev2
  WHERE s.slug = 'matematik' AND t.grade_level = 11
    AND t.name = 'MAT.11.3 NİCELİKLER VE DEĞİŞİMLER'
    AND m.academic_year = '2026-2027';
  IF v1 <> 2 OR v2 <> 4 OR v3 <> 2 THEN
    RAISE EXCEPTION 'FINAL_160: MAT.11.3 pencere bolunmesi 2/4/2 degil (bulunan %/%/%).', v1, v2, v3;
  END IF;

  -- 8) Tohum kuralı: repeat_from = first (161 politikaya kadar eşit)
  IF EXISTS (SELECT 1 FROM public.curriculum_subtopic_week_map
             WHERE academic_year = '2026-2027'
               AND repeat_from_instruction_week <> first_instruction_week) THEN
    RAISE EXCEPTION 'FINAL_160: tohumda repeat_from != first_instruction_week satiri var.';
  END IF;

  -- 9) Erişim matrisi: RLS acik+forced + 0 politika; istemci hakki yok;
  --    motor fonk ACL'si service_role+postgres; approve RPC anon'suz
  IF (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class
      WHERE oid = 'public.curriculum_subtopic_week_map'::regclass) IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'FINAL_160: esleme tablosu RLS acik/forced degil.';
  END IF;
  IF (SELECT count(*) FROM pg_policy
      WHERE polrelid = 'public.curriculum_subtopic_week_map'::regclass) <> 0 THEN
    RAISE EXCEPTION 'FINAL_160: esleme tablosunda politika bulunamaz (0 olmali).';
  END IF;
  IF has_table_privilege('anon', 'public.curriculum_subtopic_week_map', 'SELECT')
     OR has_table_privilege('authenticated', 'public.curriculum_subtopic_week_map', 'SELECT') THEN
    RAISE EXCEPTION 'FINAL_160: ogrenci yuzeyi sizdirmasi (anon/auth SELECT).';
  END IF;
  IF has_function_privilege('authenticated',
      'public.curriculum_subtopic_week_state(smallint,uuid,date)'::regprocedure, 'EXECUTE')
     OR has_function_privilege('anon',
      'public.curriculum_subtopic_week_state(smallint,uuid,date)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'FINAL_160: motor okuyucu EXECUTE sizintisi.';
  END IF;
  IF has_function_privilege('anon',
      'public.curriculum_week_map_approve(uuid)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'FINAL_160: approve RPC anon erisilebilir.';
  END IF;

  -- 9b) FIX-160-A: verify RPC + kanıt tablosu güvenlik matrisi
  IF to_regclass('public.curriculum_week_map_verification') IS NULL THEN
    RAISE EXCEPTION 'FINAL_160: dogrulama tablosu yok (FIX-160-A K2).';
  END IF;
  IF has_function_privilege('anon',
      'public.curriculum_week_map_verify(uuid,text,text,text,text,text,text,text,smallint,uuid,uuid,uuid,smallint)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'FINAL_160: verify RPC anon erisilebilir.';
  END IF;
  IF NOT has_function_privilege('authenticated',
      'public.curriculum_week_map_verify(uuid,text,text,text,text,text,text,text,smallint,uuid,uuid,uuid,smallint)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'FINAL_160: verify RPC authenticated kapali (yetki RPC ic kapisi).';
  END IF;
  IF has_table_privilege('anon', 'public.curriculum_week_map_verification', 'SELECT')
     OR has_table_privilege('authenticated', 'public.curriculum_week_map_verification', 'SELECT') THEN
    RAISE EXCEPTION 'FINAL_160: dogrulama tablosu ogrenci sizdirmasi.';
  END IF;
  IF (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class
      WHERE oid = 'public.curriculum_week_map_verification'::regclass) IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'FINAL_160: dogrulama tablosu RLS+FORCE degil.';
  END IF;
  IF (SELECT count(*) FROM pg_policy
      WHERE polrelid = 'public.curriculum_week_map_verification'::regclass) <> 0 THEN
    RAISE EXCEPTION 'FINAL_160: dogrulama tablosunda politika var (0 beklenir).';
  END IF;
  IF (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
      WHERE t.tgname = 'trg_cwmv_immutable') <> 1 THEN
    RAISE EXCEPTION 'FINAL_160: dogrulama append-only trigger eksik.';
  END IF;
  -- NOT: "tohumda doğrulama kaydı yok" iddiası seed yapısaldır (bu migration
  -- doğrulama tablosuna HİÇ yazmaz); resmî doğrulamalar meşru yönetici
  -- işlemleridir ve idempotency yeniden-koşumunu kırmamalıdır — ilk uygulama
  -- anındaki boşluk QA T08/T23'te doğrulanır.

  -- 10) Korunumlar: 157/SEC-1/158/151 + 159 takvim matrisi
  IF has_table_privilege('anon', 'public.questions', 'SELECT') THEN
    RAISE EXCEPTION 'FINAL_160: 157 geri sarildi.';
  END IF;
  IF has_function_privilege('authenticated',
      'public.get_internal_correct_answer(uuid)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'FINAL_160: SEC-1 geri sarildi.';
  END IF;
  IF (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public'
      AND indexname IN ('uq_question_vaults_weekly_scope', 'uq_question_active_single_vault')) <> 2 THEN
    RAISE EXCEPTION 'FINAL_160: 158/151 index korunumu bozuldu.';
  END IF;
  IF (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
      WHERE t.tgname IN ('trg_vault_memberships_pack_limit', 'trg_question_vaults_pack_limit',
                         'trg_weekly_placements_limit', 'trg_question_vaults_weekly_type')) <> 4 THEN
    RAISE EXCEPTION 'FINAL_160: 158 trigger korunumu bozuldu.';
  END IF;
  IF (SELECT count(*) FROM public.academic_weeks WHERE academic_year = '2026-2027') <> 42
     OR (SELECT count(*) FROM public.meb_holiday_days) <> 18 THEN
    RAISE EXCEPTION 'FINAL_160: 159 takvim matrisi bozuldu.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '160') THEN
    RAISE EXCEPTION 'FINAL_160: history kaydi yok.';
  END IF;

  SELECT DISTINCT mapping_confidence INTO evi FROM public.curriculum_subtopic_week_map
   WHERE academic_year = '2026-2027';
  IF evi <> 'tahmini_onay_bekliyor' THEN
    RAISE EXCEPTION 'FINAL_160: tohum güven düzeyi % (beklenen tahmini_onay_bekliyor).', evi;
  END IF;

  RAISE NOTICE 'ALTKONU160 OK: kapsam tam + tum satirlar tahmini_onay_bekliyor (ek-kural) + kanit-tipleri ayrik; slot safligi + fail-closed motor; 151/157/158/159 matrisleri duruyor';
END
$fin$;

COMMIT;
