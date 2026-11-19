-- ============================================================
-- 162_editable_vault_plans.sql
-- AK-MEB-VAULT-42-14: Düzenlenebilir kasa planları — sürüm + hedef + override (ADDITIVE)
-- ============================================================
-- KAPSAM (42-09 tasarım sözleşmesi §3–§9 + görev 42-14):
--   1) PLAN SÜRÜMLERİ: vault_plan_versions (draft → validated → published →
--      superseded; kasa başına TEK aktif published; sürüm no tekil).
--      Yayınlanmış sürüm ve satırları trigger ile DEĞİŞTİRİLEMEZ; geri dönüş
--      = eski sürümün kopyalanıp YENİ sürüm numarasıyla yayınlanması.
--   2) HEDEF MATRİSİ: vault_subtopic_targets (sürüm + alt konu + hedef soru
--      1..200; UNIQUE(sürüm, alt konu)). Kasa başı hedef toplamı ≤200
--      (158 ≤200 sert yerleşim kapağına EK erken uyarı katmanı; 065 ≤5 ve
--      151 tek-aktif-üyelik DOKUNULMAZ).
--   3) HAFTA OVERRIDE: vault_plan_week_overrides (sürüm bazlı; base 160 satırı
--      HİÇ değiştirilmez — effective_first_I = coalesce(son published
--      override, 160 base)). Yalnız new_topic_allowed=true I-slots hedef;
--      K10/K20/K21/K26 (I'sız tatil), K36 (allow=false), K42 pasif yapısal
--      hedef dışı. ERTELEME serbest; ÖNE ALMA yalnız resmî+doğrulanmış
--      eşlemede, tam K2-biçim kanıtla (KANIT_162) ve o haftalarda kullanılmış
--      yerleşim yoksa (tamamlanmış yarışma geçmişi korunur).
--   4) MOTOR ENTEGRASYONU: curriculum_subtopic_week_state yeniden tanımlanır;
--      TEK değişiklik first_instruction_week okuması artık effective
--      (published override varsa o). override yoksa çıktı BAYT-BAYT aynıdır
--      (QA'da 29 çift × 42 hafta snapshot karşıtlığıyla kanıtlanır). FIX-160-A
--      K1 kapısı (resmî + EXISTS(verify) + hafta gelmiş + gate) AYNEN korunur.
--   5) YAYIN KAPISI (vault_plan_publish, super_admin-only yetki + İKİ-KİŞİ
--      kuralı: yayımlayan ≠ oluşturan): yayın anında CANLI takvim
--      yeniden-okuması (tatil/K36/K42 + meb_holiday_days), hedef toplamı ≤200,
--      her hedef alt konu için motor FIX-160-A usable kontrolü (tahminî
--      eşleme ASLA yayınlamaz — GAP-160-A dururken hiçbir kasa planı
--      yayınlanamaz; bu tasarım gereğidir), K42 kasaları takvim aktivasyonu
--      olmadan yayınlayamaz. Yayın, etkilenen override'ları
--      vault_plan_recalc_queue'ya yazar (worker 165+; GAP).
--   6) DENETİM: vault_plan_changes append-only (eski/yeni değer, etkilenen
--      kasa listesi, actor, zaman); sürüm zinciri base_version_id ile uçtan
--      uca okunur. vault_plan_history/_impact_preview/_gaps salt-okunur RPC.
--   7) HARDEN-1 (42-09 §9 önerisi): academic_weeks'te week_kind NOT NULL
--      (159 metadata'lı) haftaların TARİH kaydırma UPDATE'i ve DELETE'i
--      trigger ile reddedilir (takvim tarihiyle kapı baypası yapısal kapanır;
--      K42 activated_at ve week_kind atama/bayrak UPDATE'leri serbesttir).
--   8) YETKİ: vault_plan.manage → super_admin+content_admin (taslak mutasyonu,
--      salt-okunur önizleme/geçmiş/gaps); vault_plan.publish → YALNIZ
--      super_admin (yayın + rollback — iki-kişi kuralı). Tüm tablolar RLS ON
--      + FORCE + 0 politika; anon/authenticated'e HİÇBİR GRANT yok; erişim
--      yalnız SECURITY DEFINER RPC'ler (073/160 idiomu, academic_calendar_
--      has_permission). Öğrenci yüzeyi: 162 hiçbir erişim hakkı eklemez.
--
-- KORUNANLAR (GUARD/FINAL + snapparmak iziyle): 3.654 haftalık kasa (161),
--   36 eski kasa, 13 LEGACY, 546 tahminî eşleme (onay/resmî ÜRETİLMEZ),
--   weekly_vault_placements (0), 151/158 mekanizmaları, 159 takvim verisi,
--   FIX-160-A motoru, SEC-1.
--
-- YAPISI: BEGIN → GUARD_162 → yetki tohumu → tablolar/tetikler → RPC'ler →
--   motor yeniden tanımı → HARDEN-1 → history → FINAL_162 → COMMIT.
-- GERİ ALMA (yetkili operasyon): RPC'leri DROP et, HARDEN-1 tetiğini düşür,
--   motoru 160 sürümüne döndür (160 migration dosyasındaki tanım), yeni
--   tabloları DROP et, history 161+162 kayıtlarını sil.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- GUARD_162 — ön koşullar (fail-closed) + koruma anlık görüntüleri
-- ------------------------------------------------------------
DO $guard$
DECLARE
  v        bigint;
  n        bigint;
  p        RECORD;
  v_usable bigint := 0;
BEGIN
  -- 1) Zincir: 158..161 applied; 162 yok
  IF (SELECT count(*) FROM supabase_migrations.schema_migrations
      WHERE version IN ('158','159','160','161')) <> 4 THEN
    RAISE EXCEPTION 'GUARD_162: 158-161 migration zinciri eksik.';
  END IF;
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='162') THEN
    RAISE EXCEPTION 'GUARD_162: 162 kaydi zaten var — yeniden uygulama GUARD disi.';
  END IF;

  -- 2) Takvim matrisi (159 donmuş sözleşme)
  IF (SELECT count(*) FROM public.academic_weeks WHERE academic_year='2026-2027') <> 42
     OR (SELECT count(DISTINCT instruction_week_number) FROM public.academic_weeks
         WHERE academic_year='2026-2027' AND instruction_week_number IS NOT NULL) <> 37
     OR (SELECT count(*) FROM public.meb_holiday_days) <> 18
     OR EXISTS (SELECT 1 FROM public.academic_weeks
         WHERE academic_year='2026-2027' AND week IN (10,20,21,26,36) AND new_topic_allowed)
     OR NOT EXISTS (SELECT 1 FROM public.academic_weeks
         WHERE academic_year='2026-2027' AND week=42
           AND requires_admin_activation AND activated_at IS NULL) THEN
    RAISE EXCEPTION 'GUARD_162: 159 takvim matrisi/kapi sozlesmesi bozuk.';
  END IF;

  -- 3) 160 motoru + eşleme kaynağı duruyor
  IF (SELECT count(*) FROM public.curriculum_subtopic_week_map
      WHERE academic_year='2026-2027') <> 546
     OR (SELECT count(*) FROM (SELECT DISTINCT grade_level, subject_id
         FROM public.curriculum_subtopic_week_map WHERE academic_year='2026-2027') x) <> 29
     OR to_regprocedure('public.curriculum_subtopic_week_state(smallint,uuid,date)') IS NULL
     OR to_regclass('public.curriculum_week_map_verification') IS NULL THEN
    RAISE EXCEPTION 'GUARD_162: 160 esleme/motor nesneleri eksik.';
  END IF;

  -- 4) 161 kasa bandı tam ve temiz
  IF (SELECT count(*) FROM public.question_vaults WHERE vault_type='weekly') <> 3654
     OR (SELECT count(*) FROM public.weekly_vault_placements) <> 0
     OR EXISTS (SELECT 1 FROM public.question_vault_memberships m
                JOIN public.question_vaults q ON q.id=m.vault_id
                WHERE q.vault_type='weekly') THEN
    RAISE EXCEPTION 'GUARD_162: 161 kasa bandi beklenen durumda degil.';
  END IF;
  IF (SELECT count(*) FROM public.question_vault_topics
      WHERE legacy_topic_code IS NOT NULL) <> 13 THEN
    RAISE EXCEPTION 'GUARD_162: 13 LEGACY baglantisi bulunamadi.';
  END IF;

  -- 5) 151/158/160 korunum imzaları
  IF (SELECT count(*) FROM pg_indexes WHERE schemaname='public'
      AND indexname IN ('uq_question_vaults_weekly_scope','uq_question_active_single_vault')) <> 2
     OR (SELECT count(*) FROM pg_trigger t
         WHERE t.tgname IN ('trg_vault_memberships_pack_limit','trg_question_vaults_pack_limit',
                            'trg_weekly_placements_limit','trg_question_vaults_weekly_type',
                            'trg_question_vaults_weekly_pair','trg_cwmv_immutable')
           AND NOT t.tgisinternal) <> 6 THEN
    RAISE EXCEPTION 'GUARD_162: 151/158/160 tetik/indeks imzalari eksik.';
  END IF;

  -- 6) 162 nesneleri henüz YOK (kısmi kalıntı = abort)
  IF to_regclass('public.vault_plan_versions') IS NOT NULL
     OR to_regclass('public.vault_subtopic_targets') IS NOT NULL
     OR to_regclass('public.vault_plan_week_overrides') IS NOT NULL
     OR to_regclass('public.vault_plan_changes') IS NOT NULL
     OR to_regclass('public.vault_plan_recalc_queue') IS NOT NULL THEN
    RAISE EXCEPTION 'GUARD_162: 162 tablo kalintisi var — elle incele.';
  END IF;

  -- 7) SEC-1 kapalı
  IF has_function_privilege('authenticated',
      'public.get_internal_correct_answer(uuid)'::regprocedure, 'EXECUTE')
     OR has_function_privilege('anon',
      'public.get_internal_correct_answer(uuid)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'GUARD_162: SEC-1 acik.';
  END IF;

  -- 8) Koruma anlık görüntüleri
  DROP TABLE IF EXISTS pg_temp.ak162_snap;
  CREATE TEMP TABLE ak162_snap ON COMMIT DROP AS
  SELECT
    (SELECT md5(string_agg(id||'|'||vault_code, ',' ORDER BY vault_code))
       FROM public.question_vaults WHERE vault_type='weekly') AS fp_weekly,
    (SELECT count(*) FROM public.question_vaults)::bigint AS n_vaults,
    (SELECT md5(string_agg(vault_code||'|'||is_active::text||'|'
       ||coalesce(difficulty_level,'-')||'|'||coalesce(week_number::text,'-'), ',' ORDER BY vault_code))
       FROM public.question_vaults WHERE vault_type<>'weekly') AS fp_nonweekly,
    (SELECT count(*) FROM public.question_vault_topics
      WHERE legacy_topic_code IS NOT NULL)::bigint AS n_legacy,
    (SELECT count(*) FROM public.curriculum_subtopic_week_map
      WHERE academic_year='2026-2027')::bigint AS n_map,
    (SELECT count(*) FROM public.curriculum_subtopic_week_map
      WHERE approved_at IS NOT NULL)::bigint AS n_map_approved,
    0::bigint AS n_engine_usable;

  FOR p IN SELECT DISTINCT m.grade_level, m.subject_id
           FROM public.curriculum_subtopic_week_map m
          WHERE m.academic_year='2026-2027' LOOP
    SELECT count(*) INTO n
      FROM public.curriculum_subtopic_week_state(
             p.grade_level::smallint, p.subject_id, current_date) x
     WHERE x.is_usable;
    v_usable := v_usable + n;
  END LOOP;
  UPDATE pg_temp.ak162_snap SET n_engine_usable = v_usable;

  RAISE NOTICE 'GUARD_162 OK: zincir + takvim + 160 motoru + 161 bandi + imzalar + snapler saglam';
END
$guard$;

-- ------------------------------------------------------------
-- YETKİ TOHUMLARI (073/160 idiomu)
--   manage → super_admin + content_admin ; publish → YALNIZ super_admin
-- ------------------------------------------------------------
INSERT INTO public.admin_permissions (permission_code, name, description)
VALUES
  ('vault_plan.manage',
   'Kasa Planlarini Duzenle',
   'Haftalik kasa plan surumleri (alt konu hedefleri, hafta override) taslaklarini olusturur/duzenler; etki onizleme ve gecmisi goruntuler.'),
  ('vault_plan.publish',
   'Kasa Planlarini Yayinla',
   'Dogrulanmis kasa plan surumunu yayinlar veya geri-alim surumu yayar. Iki-kisi kurali: yayimlayan olusturandan farkli olmali.')
ON CONFLICT (permission_code) DO UPDATE
SET name = excluded.name, description = excluded.description;

INSERT INTO public.admin_role_permissions (role_id, permission_id)
SELECT ar.id, ap.id
FROM public.admin_roles ar
CROSS JOIN public.admin_permissions ap
WHERE ar.role_code IN ('super_admin', 'content_admin')
  AND ar.is_active = true
  AND ap.permission_code = 'vault_plan.manage'
ON CONFLICT DO NOTHING;

INSERT INTO public.admin_role_permissions (role_id, permission_id)
SELECT ar.id, ap.id
FROM public.admin_roles ar
CROSS JOIN public.admin_permissions ap
WHERE ar.role_code = 'super_admin'
  AND ar.is_active = true
  AND ap.permission_code = 'vault_plan.publish'
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------
-- 1) TABLO — vault_plan_versions (kasa başına sürümlü plan)
-- ------------------------------------------------------------
CREATE TABLE public.vault_plan_versions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academic_year     text NOT NULL CHECK (academic_year ~ '^[0-9]{4}-[0-9]{4}$'),
  vault_id          uuid NOT NULL REFERENCES public.question_vaults (id) ON DELETE CASCADE,
  version_no        integer NOT NULL CHECK (version_no >= 1),
  status            text NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','validated','published','superseded')),
  base_version_id   uuid REFERENCES public.vault_plan_versions (id) ON DELETE RESTRICT,
  reason            text NOT NULL CHECK (length(btrim(reason)) >= 3),
  created_by        uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  approved_by       uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  published_at      timestamptz,
  UNIQUE (vault_id, version_no)
);
-- kasa başına en fazla TEK published sürüm
CREATE UNIQUE INDEX uq_vpv_single_published
  ON public.vault_plan_versions (vault_id) WHERE status = 'published';
CREATE INDEX idx_vpv_vault ON public.vault_plan_versions (vault_id, version_no DESC);

-- Değişmezlik: published/superseded sürüm satırı donar; tek istisna
-- published → superseded GEÇİŞİDİR ve yalnız status kolonu değişebilir.
CREATE OR REPLACE FUNCTION public.enforce_vault_plan_version_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $fn$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status IN ('published','superseded') THEN
      RAISE EXCEPTION 'VAULTPLAN_162: yayinlanmis/degistirilmis surum silinemez.';
    END IF;
    RETURN OLD;
  END IF;
  IF OLD.status = 'superseded' THEN
    RAISE EXCEPTION 'VAULTPLAN_162: superseded surum degistirilemez.';
  END IF;
  IF OLD.status = 'published' THEN
    IF NEW.status = 'superseded'
       AND NEW.id = OLD.id AND NEW.academic_year = OLD.academic_year
       AND NEW.vault_id = OLD.vault_id AND NEW.version_no = OLD.version_no
       AND NEW.base_version_id IS NOT DISTINCT FROM OLD.base_version_id
       AND NEW.reason = OLD.reason
       AND NEW.created_by IS NOT DISTINCT FROM OLD.created_by
       AND NEW.approved_by IS NOT DISTINCT FROM OLD.approved_by
       AND NEW.created_at = OLD.created_at
       AND NEW.published_at IS NOT DISTINCT FROM OLD.published_at
    THEN
      RETURN NEW; -- tek izinli geçiş: supersedé (yalnız status kolonu)
    END IF;
    RAISE EXCEPTION 'VAULTPLAN_162: published surum degistirilemez (geri donus yeni surum olarak yayimlanir).';
  END IF;
  -- draft/validated: kimlik kolonları yine sabittir
  IF NEW.id <> OLD.id OR NEW.vault_id <> OLD.vault_id
     OR NEW.version_no <> OLD.version_no
     OR NEW.created_by IS DISTINCT FROM OLD.created_by
     OR NEW.created_at <> OLD.created_at
     OR NEW.base_version_id IS DISTINCT FROM OLD.base_version_id
  THEN
    RAISE EXCEPTION 'VAULTPLAN_162: surum kimlik kolonlari degistirilemez.';
  END IF;
  RETURN NEW;
END $fn$;

CREATE TRIGGER trg_vpv_immutable
  BEFORE UPDATE OR DELETE ON public.vault_plan_versions
  FOR EACH ROW EXECUTE FUNCTION public.enforce_vault_plan_version_immutable();

-- ------------------------------------------------------------
-- 2) TABLO — vault_subtopic_targets (hedef matrisi, sürüm bazlı)
-- ------------------------------------------------------------
CREATE TABLE public.vault_subtopic_targets (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id       uuid NOT NULL REFERENCES public.vault_plan_versions (id) ON DELETE CASCADE,
  subtopic_id      uuid NOT NULL REFERENCES public.subtopics (id) ON DELETE RESTRICT,
  question_target  integer NOT NULL CHECK (question_target BETWEEN 1 AND 200),
  note             text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (version_id, subtopic_id)
);

-- ------------------------------------------------------------
-- 3) TABLO — vault_plan_week_overrides (sürüm bazlı hafta planı değişikliği)
--    base 160 satırı hiç değişmez; etki yalnız published sürümde doğar.
-- ------------------------------------------------------------
CREATE TABLE public.vault_plan_week_overrides (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id       uuid NOT NULL REFERENCES public.vault_plan_versions (id) ON DELETE CASCADE,
  subtopic_id      uuid NOT NULL REFERENCES public.subtopics (id) ON DELETE RESTRICT,
  old_first_I      smallint NOT NULL CHECK (old_first_I BETWEEN 1 AND 37),
  new_first_I      smallint NOT NULL CHECK (new_first_I BETWEEN 1 AND 37),
  reason           text NOT NULL CHECK (length(btrim(reason)) >= 3),
  advance_evidence jsonb,  -- öne almada zorunlu, tam K2-biçim kanıt (KANIT_162)
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (version_id, subtopic_id)
);

-- Sürüm-bazlı satır koruması: hedef/override satırları yalnız DRAFT taslağında
-- değişebilir; validated/published/superseded donmuştur (yayın = mühür).
CREATE OR REPLACE FUNCTION public.enforce_vault_plan_row_draft_only(p_version uuid)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_status text;
BEGIN
  SELECT status INTO v_status
    FROM public.vault_plan_versions
   WHERE id = p_version;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'VAULTPLAN_162: surum bulunamadi.';
  END IF;
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'VAULTPLAN_162: surum satirlari yalniz draft surumde degisebilir (surum: %).',
      v_status;
  END IF;
END $fn$;

CREATE OR REPLACE FUNCTION public.trg_vst_draft_only()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $fn$
BEGIN
  PERFORM public.enforce_vault_plan_row_draft_only(COALESCE(NEW.version_id, OLD.version_id));
  RETURN COALESCE(NEW, OLD);
END $fn$;

CREATE OR REPLACE FUNCTION public.trg_vpwo_draft_only()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $fn$
BEGIN
  PERFORM public.enforce_vault_plan_row_draft_only(COALESCE(NEW.version_id, OLD.version_id));
  RETURN COALESCE(NEW, OLD);
END $fn$;

CREATE TRIGGER trg_vst_draft_only
  BEFORE INSERT OR UPDATE OR DELETE ON public.vault_subtopic_targets
  FOR EACH ROW EXECUTE FUNCTION public.trg_vst_draft_only();

CREATE TRIGGER trg_vpwo_draft_only
  BEFORE INSERT OR UPDATE OR DELETE ON public.vault_plan_week_overrides
  FOR EACH ROW EXECUTE FUNCTION public.trg_vpwo_draft_only();

-- ------------------------------------------------------------
-- 4) TABLO — vault_plan_changes (append-only denetim)
-- ------------------------------------------------------------
CREATE TABLE public.vault_plan_changes (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id       uuid NOT NULL REFERENCES public.vault_plan_versions (id) ON DELETE RESTRICT,
  actor            uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  action           text NOT NULL CHECK (length(btrim(action)) >= 3),
  subtopic_id      uuid REFERENCES public.subtopics (id) ON DELETE SET NULL,
  old_value        jsonb,
  new_value        jsonb,
  affected_vaults  uuid[],
  at               timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_vpc_version ON public.vault_plan_changes (version_id, at);

CREATE OR REPLACE FUNCTION public.enforce_vault_plan_changes_append_only()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $fn$
BEGIN
  RAISE EXCEPTION 'VAULTPLAN_162: denetim kaydi append-only — % yasak.', TG_OP;
END $fn$;

CREATE TRIGGER trg_vpc_append_only
  BEFORE UPDATE OR DELETE ON public.vault_plan_changes
  FOR EACH ROW EXECUTE FUNCTION public.enforce_vault_plan_changes_append_only();

-- ------------------------------------------------------------
-- 5) TABLO — vault_plan_recalc_queue (yayının etkilediği yeniden hesap işleri)
--    Worker 165+ tüketir (GAP-165-A); 162 yalnız kuyruk yazar.
-- ------------------------------------------------------------
CREATE TABLE public.vault_plan_recalc_queue (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  academic_year   text NOT NULL,
  subtopic_id     uuid NOT NULL REFERENCES public.subtopics (id) ON DELETE RESTRICT,
  old_first_I     smallint NOT NULL,
  new_first_I     smallint NOT NULL,
  affected_vaults uuid[] NOT NULL DEFAULT '{}',
  reason          text NOT NULL,
  status          text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','drafted','done')),
  created_by      uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz
);
CREATE INDEX idx_vprq_pending ON public.vault_plan_recalc_queue (status, created_at)
  WHERE status = 'pending';

-- ------------------------------------------------------------
-- RLS: tüm yeni tablolarda ON + FORCE + SIFIR politika (073/160 idiomu)
-- ------------------------------------------------------------
DO $rls$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['vault_plan_versions','vault_subtopic_targets',
                           'vault_plan_week_overrides','vault_plan_changes',
                           'vault_plan_recalc_queue']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated', t);
    EXECUTE format('GRANT SELECT ON public.%I TO service_role', t);
  END LOOP;
END $rls$;

-- ------------------------------------------------------------
-- İÇ YARDIMCILAR (SECURITY DEFINER zincirinin private katmanı)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._vp_require(p_permission text)
RETURNS uuid LANGUAGE plpgsql STABLE SET search_path = '' AS $fn$
DECLARE v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL OR NOT public.academic_calendar_has_permission(p_permission) THEN
    RAISE EXCEPTION 'YETKI_162: "%" yetkisi yok.', p_permission
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v_uid;
END $fn$;

-- Haftalık kasa kimliği (grade/subject/week); haftalık değilse patlar.
CREATE OR REPLACE FUNCTION public._vp_vault(p_vault_id uuid)
RETURNS TABLE (grade_level smallint, subject_id uuid, week_number smallint, vault_code text)
LANGUAGE plpgsql STABLE SET search_path = '' AS $fn$
BEGIN
  SELECT q.grade_level::smallint, q.subject_id, q.week_number::smallint, q.vault_code
    INTO grade_level, subject_id, week_number, vault_code
  FROM public.question_vaults q
  WHERE q.id = p_vault_id AND q.vault_type = 'weekly';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'KASA_162: haftalik kasa bulunamadi.';
  END IF;
  RETURN NEXT;
END $fn$;

-- 160 eşleme satırı (alt konu bu kasaya ait değilse patlar) + resmîlik durumu.
CREATE OR REPLACE FUNCTION public._vp_map(p_year text, p_grade smallint, p_subject uuid, p_subtopic uuid)
RETURNS TABLE (map_id uuid, first_I smallint, is_official boolean, is_verified boolean)
LANGUAGE plpgsql STABLE SET search_path = '' AS $fn$
BEGIN
  SELECT m.id, m.first_instruction_week,
         m.mapping_confidence IN ('resmi_dogrudan','resmi_dolayli'),
         EXISTS (SELECT 1 FROM public.curriculum_week_map_verification v
                 WHERE v.map_id = m.id)
    INTO map_id, first_I, is_official, is_verified
  FROM public.curriculum_subtopic_week_map m
  WHERE m.academic_year = p_year AND m.grade_level = p_grade
    AND m.subject_id = p_subject AND m.subtopic_id = p_subtopic;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ESLEME_162: alt konu bu kasa ciftinin 160 eslemesinde yok.';
  END IF;
  RETURN NEXT;
END $fn$;

-- I-slotu kapısı: yalnız new_topic_allowed=true öğretim haftası I'leri hedef
-- olabilir (K10/20/21/26 I'sız; K36=I32 allow=false; K42 hedef dışı).
CREATE OR REPLACE FUNCTION public._vp_require_I_slot(p_year text, p_I smallint)
RETURNS smallint LANGUAGE plpgsql STABLE SET search_path = '' AS $fn$
DECLARE v_week smallint;
BEGIN
  SELECT min(aw.week)::smallint INTO v_week
  FROM public.academic_weeks aw
  WHERE aw.academic_year = p_year AND aw.instruction_week_number = p_I
    AND aw.new_topic_allowed;
  IF v_week IS NULL THEN
    RAISE EXCEPTION 'TAKVIM_162: I% hedeflenemez (tatil/K36/K42 kapisi).', p_I;
  END IF;
  RETURN v_week;
END $fn$;

-- Etkin ilk-öğretim I'si: son published override, yoksa 160 base.
CREATE OR REPLACE FUNCTION public.vault_plan_effective_first_i(
  p_year text, p_grade smallint, p_subject uuid, p_subtopic uuid
)
RETURNS smallint LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE v_I smallint;
BEGIN
  SELECT coalesce((
    SELECT o.new_first_I
    FROM public.vault_plan_week_overrides o
    JOIN public.vault_plan_versions pv
      ON pv.id = o.version_id AND pv.status = 'published'
    WHERE o.subtopic_id = p_subtopic
      AND pv.vault_id IN (SELECT q.id FROM public.question_vaults q
                          WHERE q.vault_type = 'weekly'
                            AND q.grade_level = p_grade AND q.subject_id = p_subject)
    ORDER BY pv.published_at DESC LIMIT 1
  ), m.first_instruction_week)
  INTO v_I
  FROM public.curriculum_subtopic_week_map m
  WHERE m.academic_year = p_year AND m.grade_level = p_grade
    AND m.subject_id = p_subject AND m.subtopic_id = p_subtopic;
  IF v_I IS NULL THEN
    RAISE EXCEPTION 'ESLEME_162: alt konu eslemesi yok.';
  END IF;
  RETURN v_I;
END $fn$;

CREATE OR REPLACE FUNCTION public._vp_audit(
  p_version uuid, p_actor uuid, p_action text, p_subtopic uuid,
  p_old jsonb, p_new jsonb, p_affected uuid[] DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SET search_path = '' AS $fn$
BEGIN
  INSERT INTO public.vault_plan_changes
    (version_id, actor, action, subtopic_id, old_value, new_value, affected_vaults)
  VALUES (p_version, p_actor, p_action, p_subtopic, p_old, p_new, p_affected);
END $fn$;

-- ------------------------------------------------------------
-- RPC — vault_plan_version_create (yeni taslak; base = verilen veya mevcut published)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vault_plan_version_create(
  p_vault_id uuid, p_base_version_id uuid DEFAULT NULL, p_reason text DEFAULT 'plan taslagi'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_uid uuid := public._vp_require('vault_plan.manage');
  v_year text; v_vault RECORD; v_base uuid; v_no integer; v_id uuid;
BEGIN
  SELECT aw.academic_year INTO v_year
  FROM public.academic_weeks aw WHERE aw.academic_year = '2026-2027' LIMIT 1;
  SELECT * INTO v_vault FROM public._vp_vault(p_vault_id);

  v_base := COALESCE(p_base_version_id,
    (SELECT id FROM public.vault_plan_versions
     WHERE vault_id = p_vault_id AND status = 'published' LIMIT 1));
  IF p_base_version_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.vault_plan_versions
                   WHERE id = p_base_version_id AND vault_id = p_vault_id) THEN
      RAISE EXCEPTION 'SURUM_162: base surum bu kasaya ait degil.';
    END IF;
  END IF;

  SELECT coalesce(max(version_no), 0) + 1 INTO v_no
  FROM public.vault_plan_versions WHERE vault_id = p_vault_id;

  INSERT INTO public.vault_plan_versions
    (academic_year, vault_id, version_no, status, base_version_id, reason, created_by)
  VALUES (v_year, p_vault_id, v_no, 'draft', v_base, p_reason, v_uid)
  RETURNING id INTO v_id;

  IF v_base IS NOT NULL THEN
    INSERT INTO public.vault_subtopic_targets (version_id, subtopic_id, question_target, note)
    SELECT v_id, t.subtopic_id, t.question_target, t.note
    FROM public.vault_subtopic_targets t WHERE t.version_id = v_base;
    INSERT INTO public.vault_plan_week_overrides
      (version_id, subtopic_id, old_first_I, new_first_I, reason, advance_evidence)
    SELECT v_id, o.subtopic_id, o.old_first_I, o.new_first_I, o.reason, o.advance_evidence
    FROM public.vault_plan_week_overrides o WHERE o.version_id = v_base;
  END IF;

  PERFORM public._vp_audit(v_id, v_uid, 'version_create', NULL, NULL,
    jsonb_build_object('vault_id', p_vault_id, 'base', v_base, 'version_no', v_no));
  RETURN v_id;
END $fn$;

-- ------------------------------------------------------------
-- RPC — vault_plan_target_set (alt konu ekleme/hedef değiştirme; upsert)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vault_plan_target_set(
  p_version_id uuid, p_subtopic_id uuid, p_target integer, p_note text DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_uid uuid := public._vp_require('vault_plan.manage');
  v_status text; v_grade smallint; v_subject uuid; v_old integer; v_sum integer;
BEGIN
  SELECT status INTO v_status FROM public.vault_plan_versions WHERE id = p_version_id;
  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'SURUM_162: hedef degisikligi yalniz draft surumde.';
  END IF;
  SELECT v.grade_level, v.subject_id INTO v_grade, v_subject
  FROM public.vault_plan_versions pv
  JOIN public._vp_vault(pv.vault_id) v ON TRUE
  WHERE pv.id = p_version_id;
  PERFORM public._vp_map('2026-2027', v_grade, v_subject, p_subtopic_id);

  SELECT question_target INTO v_old
  FROM public.vault_subtopic_targets
  WHERE version_id = p_version_id AND subtopic_id = p_subtopic_id;

  INSERT INTO public.vault_subtopic_targets (version_id, subtopic_id, question_target, note)
  VALUES (p_version_id, p_subtopic_id, p_target, p_note)
  ON CONFLICT (version_id, subtopic_id)
  DO UPDATE SET question_target = excluded.question_target, note = excluded.note;

  SELECT coalesce(sum(question_target), 0) INTO v_sum
  FROM public.vault_subtopic_targets WHERE version_id = p_version_id;
  IF v_sum > 200 THEN
    -- erken uyarı: taslak içi toplam 200'ü aşamaz (158 kapağıyla uyum);
    -- exception çağıranın transaction'ını geri aldığı için satır da geri alır
    RAISE EXCEPTION 'KAPASITE_162: hedef toplami 200 uzerineasti (%).', v_sum;
  END IF;

  PERFORM public._vp_audit(p_version_id, v_uid,
    CASE WHEN v_old IS NULL THEN 'subtopic_add' ELSE 'target_change' END,
    p_subtopic_id,
    CASE WHEN v_old IS NULL THEN NULL ELSE jsonb_build_object('target', v_old) END,
    jsonb_build_object('target', p_target));
END $fn$;

-- ------------------------------------------------------------
-- RPC — vault_plan_target_remove (alt konu çıkarma)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vault_plan_target_remove(p_version_id uuid, p_subtopic_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_uid uuid := public._vp_require('vault_plan.manage');
  v_old integer;
BEGIN
  IF (SELECT status FROM public.vault_plan_versions WHERE id = p_version_id)
     IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'SURUM_162: hedef degisikligi yalniz draft surumde.';
  END IF;
  DELETE FROM public.vault_subtopic_targets
  WHERE version_id = p_version_id AND subtopic_id = p_subtopic_id
  RETURNING question_target INTO v_old;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'HEDEF_162: hedef satiri bulunamadi.';
  END IF;
  PERFORM public._vp_audit(p_version_id, v_uid, 'subtopic_remove', p_subtopic_id,
    jsonb_build_object('target', v_old), NULL);
END $fn$;

-- ------------------------------------------------------------
-- RPC — vault_plan_week_defer (ertelemeye taşıma; güvenli yön, serbest)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vault_plan_week_defer(
  p_version_id uuid, p_subtopic_id uuid, p_new_first_I smallint, p_reason text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_uid uuid := public._vp_require('vault_plan.manage');
  v_grade smallint; v_subject uuid; m RECORD; v_old jsonb;
BEGIN
  IF (SELECT status FROM public.vault_plan_versions WHERE id = p_version_id)
     IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'SURUM_162: hafta degisikligi yalniz draft surumde.';
  END IF;
  SELECT v.grade_level, v.subject_id INTO v_grade, v_subject
  FROM public.vault_plan_versions pv
  JOIN public._vp_vault(pv.vault_id) v ON TRUE
  WHERE pv.id = p_version_id;

  SELECT * INTO m FROM public._vp_map('2026-2027', v_grade, v_subject, p_subtopic_id);
  PERFORM public._vp_require_I_slot('2026-2027', p_new_first_I);
  IF p_new_first_I <= m.first_I THEN
    RAISE EXCEPTION 'YON_162: erteleme HEP ileri yonlu olmali (base I%, istenen I%).',
      m.first_I, p_new_first_I;
  END IF;

  SELECT to_jsonb(o) INTO v_old FROM public.vault_plan_week_overrides o
  WHERE o.version_id = p_version_id AND o.subtopic_id = p_subtopic_id;

  INSERT INTO public.vault_plan_week_overrides
    (version_id, subtopic_id, old_first_I, new_first_I, reason)
  VALUES (p_version_id, p_subtopic_id, m.first_I, p_new_first_I, p_reason)
  ON CONFLICT (version_id, subtopic_id)
  DO UPDATE SET old_first_I = excluded.old_first_I,
                new_first_I = excluded.new_first_I,
                reason = excluded.reason,
                advance_evidence = NULL;

  PERFORM public._vp_audit(p_version_id, v_uid, 'week_defer', p_subtopic_id,
    v_old, jsonb_build_object('old_I', m.first_I, 'new_I', p_new_first_I,
                              'reason', p_reason));
END $fn$;

-- ------------------------------------------------------------
-- RPC — vault_plan_week_advance (öne alma; yalnız resmî+doğrulanmış eşlemede,
--        tam K2-biçim kanıtla ve hedef haftalarda kullanılmış yerleşim yoksa)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vault_plan_week_advance(
  p_version_id uuid, p_subtopic_id uuid, p_new_first_I smallint,
  p_evidence jsonb, p_reason text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_uid uuid := public._vp_require('vault_plan.manage');
  v_grade smallint; v_subject uuid; v_vault uuid;
  m RECORD; v_old jsonb; v_ev jsonb := coalesce(p_evidence, '{}'::jsonb);
  v_knew smallint; v_kold smallint; v_used bigint;
BEGIN
  SELECT pv.vault_id INTO v_vault FROM public.vault_plan_versions pv WHERE pv.id = p_version_id;
  IF (SELECT status FROM public.vault_plan_versions WHERE id = p_version_id)
     IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'SURUM_162: hafta degisikligi yalniz draft surumde.';
  END IF;
  SELECT v.grade_level, v.subject_id INTO v_grade, v_subject
  FROM public._vp_vault(v_vault) v;

  SELECT * INTO m FROM public._vp_map('2026-2027', v_grade, v_subject, p_subtopic_id);
  PERFORM public._vp_require_I_slot('2026-2027', p_new_first_I);
  IF p_new_first_I >= m.first_I THEN
    RAISE EXCEPTION 'YON_162: one alma geri yonlu olmali (base I%, istenen I%).',
      m.first_I, p_new_first_I;
  END IF;
  -- KAPI 1: tahminî eşleme öne alınamaz (FIX-160-A ruhu)
  IF NOT (m.is_official AND m.is_verified) THEN
    RAISE EXCEPTION 'MEB_162: one alma yalniz resmî + dogrulanmis eslemede mumkun (esleme: %).',
      CASE WHEN NOT m.is_official THEN 'tahmini' ELSE 'dogrulanmamis' END;
  END IF;
  -- KAPI 2: tam K2-biçim kanıt (160 verify sözleşmesinin override karşılığı)
  IF length(btrim(coalesce(v_ev #>> '{kurum}', ''))) < 3
     OR coalesce(v_ev #>> '{kaynak_url}', '') !~* '^https?://'
     OR length(btrim(coalesce(v_ev #>> '{belge}', ''))) < 3
     OR coalesce(v_ev #>> '{belge_yili}', '') !~ '^[0-9]{4}-[0-9]{4}$'
     OR NOT (coalesce(v_ev #>> '{belge_sha256}', '') ~ '^[0-9a-f]{64}$'
             OR length(btrim(coalesce(v_ev #>> '{kanit_ref}', ''))) >= 8)
     OR length(btrim(coalesce(v_ev #>> '{belge_konumu}', ''))) < 2
     OR length(btrim(coalesce(v_ev #>> '{dogrulayan}', ''))) < 3 THEN
    RAISE EXCEPTION 'KANIT_162: one alma kaniti eksik/eksik bicimli (kurum, kaynak_url, belge, belge_yili, belge_sha256|kanit_ref, belge_konumu, dogrulayan zorunlu).';
  END IF;
  IF coalesce(v_ev #>> '{sinif}', '') <> v_grade::text
     OR coalesce(v_ev #>> '{alt_konu}', '') <> (SELECT name FROM public.subtopics WHERE id = p_subtopic_id)
     OR coalesce((v_ev #>> '{ilk_hafta}')::smallint, 0) <> p_new_first_I THEN
    RAISE EXCEPTION 'KANIT_162: kanit kimligi (sinif/alt_konu/ilk_hafta) hedefle eslesmiyor.';
  END IF;
  -- KAPI 3: hedef aralıktaki haftalarda kullanılmış yerleşim = tamamlanmış
  -- yarışma geçmişi; içeriği geriye almak geçmişi bozar → reddedilir.
  SELECT min(aw.week) INTO v_knew FROM public.academic_weeks aw
  WHERE aw.academic_year = '2026-2027' AND aw.instruction_week_number = p_new_first_I;
  SELECT min(aw.week) INTO v_kold FROM public.academic_weeks aw
  WHERE aw.academic_year = '2026-2027' AND aw.instruction_week_number = m.first_I;
  SELECT count(*) INTO v_used
  FROM public.weekly_vault_placements p
  JOIN public.question_vaults q ON q.id = p.vault_id
  WHERE q.vault_type = 'weekly' AND q.grade_level = v_grade AND q.subject_id = v_subject
    AND p.placement_status = 'active'
    AND q.week_number >= v_knew AND q.week_number < v_kold;
  IF v_used > 0 THEN
    RAISE EXCEPTION 'GECMIS_162: K%-K% bandinda kullanilmis yerlesim var — one alma gecmisi bozar.',
      v_knew, v_kold - 1;
  END IF;

  SELECT to_jsonb(o) INTO v_old FROM public.vault_plan_week_overrides o
  WHERE o.version_id = p_version_id AND o.subtopic_id = p_subtopic_id;

  INSERT INTO public.vault_plan_week_overrides
    (version_id, subtopic_id, old_first_I, new_first_I, reason, advance_evidence)
  VALUES (p_version_id, p_subtopic_id, m.first_I, p_new_first_I, p_reason, v_ev)
  ON CONFLICT (version_id, subtopic_id)
  DO UPDATE SET old_first_I = excluded.old_first_I,
                new_first_I = excluded.new_first_I,
                reason = excluded.reason,
                advance_evidence = excluded.advance_evidence;

  PERFORM public._vp_audit(p_version_id, v_uid, 'week_advance', p_subtopic_id,
    v_old, jsonb_build_object('old_I', m.first_I, 'new_I', p_new_first_I,
                              'reason', p_reason, 'evidence', v_ev));
END $fn$;

-- ------------------------------------------------------------
-- RPC — vault_plan_validate (draft → validated; sert kapıların ilk turu)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vault_plan_validate(p_version_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_uid uuid := public._vp_require('vault_plan.manage');
  v_grade smallint; v_subject uuid; v_sum integer; v_bad integer; o RECORD;
BEGIN
  IF (SELECT status FROM public.vault_plan_versions WHERE id = p_version_id)
     IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'SURUM_162: dogrulama yalniz draft surumden yapilir.';
  END IF;
  SELECT v.grade_level, v.subject_id INTO v_grade, v_subject
  FROM public.vault_plan_versions pv
  JOIN public._vp_vault(pv.vault_id) v ON TRUE
  WHERE pv.id = p_version_id;

  SELECT coalesce(sum(question_target), 0) INTO v_sum
  FROM public.vault_subtopic_targets WHERE version_id = p_version_id;
  IF v_sum > 200 THEN
    RAISE EXCEPTION 'KAPASITE_162: hedef toplami % > 200.', v_sum;
  END IF;

  SELECT count(*) INTO v_bad
  FROM public.vault_subtopic_targets t
  WHERE t.version_id = p_version_id
    AND NOT EXISTS (SELECT 1 FROM public.curriculum_subtopic_week_map m
        WHERE m.academic_year = '2026-2027' AND m.grade_level = v_grade
          AND m.subject_id = v_subject AND m.subtopic_id = t.subtopic_id);
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'ESLEME_162: % hedef bu kasa ciftine ait degil.', v_bad;
  END IF;

  FOR o IN SELECT * FROM public.vault_plan_week_overrides WHERE version_id = p_version_id
  LOOP
    PERFORM public._vp_require_I_slot('2026-2027', o.new_first_I);
    IF o.new_first_I < o.old_first_I AND NOT EXISTS (
      SELECT 1 FROM public.curriculum_subtopic_week_map m
      JOIN public.curriculum_week_map_verification v ON v.map_id = m.id
      WHERE m.academic_year = '2026-2027' AND m.grade_level = v_grade
        AND m.subject_id = v_subject AND m.subtopic_id = o.subtopic_id
        AND m.mapping_confidence IN ('resmi_dogrudan','resmi_dolayli')) THEN
      RAISE EXCEPTION 'MEB_162: one-alma overridei resmi+dogrulanmis esleme dayanimiyor.';
    END IF;
  END LOOP;

  UPDATE public.vault_plan_versions SET status = 'validated' WHERE id = p_version_id;
  PERFORM public._vp_audit(p_version_id, v_uid, 'validate', NULL, NULL,
    jsonb_build_object('target_sum', v_sum));
END $fn$;

-- ------------------------------------------------------------
-- İÇ — yayın çekirdeği (canlı kapıların tamamı; publish ve rollback ortak)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._vp_publish_core(p_version_id uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_grade smallint; v_subject uuid; v_week smallint;
  v_date date; v_sum integer; t RECORD; o RECORD;
  v_affected uuid[]; v_uids uuid[]; v_k1 smallint; v_k2 smallint;
BEGIN
  SELECT v.grade_level, v.subject_id, v.week_number INTO v_grade, v_subject, v_week
  FROM public.vault_plan_versions pv
  JOIN public._vp_vault(pv.vault_id) v ON TRUE
  WHERE pv.id = p_version_id;

  -- KAPI K42: pasif genel tekrar kasası takvim aktivasyonu olmadan yayınlayamaz
  IF v_week = 42 AND EXISTS (SELECT 1 FROM public.academic_weeks
      WHERE academic_year = '2026-2027' AND week = 42 AND activated_at IS NULL) THEN
    RAISE EXCEPTION 'KAPI_162: K42 takvim aktivasyonu yok — genel tekrar plani yayinlanamaz.';
  END IF;

  -- CANLI kapılar (taslaktan bu yana takvim/hedef değişmiş olabilir)
  SELECT coalesce(sum(question_target), 0) INTO v_sum
  FROM public.vault_subtopic_targets WHERE version_id = p_version_id;
  IF v_sum > 200 THEN
    RAISE EXCEPTION 'KAPASITE_162: hedef toplami % > 200.', v_sum;
  END IF;
  FOR o IN SELECT * FROM public.vault_plan_week_overrides WHERE version_id = p_version_id
  LOOP
    PERFORM public._vp_require_I_slot('2026-2027', o.new_first_I);
  END LOOP;

  -- YAYIN: eski published → superseded, bu sürüm → published (aynı tx)
  UPDATE public.vault_plan_versions SET status = 'superseded'
  WHERE vault_id = (SELECT vault_id FROM public.vault_plan_versions WHERE id = p_version_id)
    AND status = 'published';

  UPDATE public.vault_plan_versions
     SET status = 'published', published_at = now(), approved_by = p_actor
   WHERE id = p_version_id;

  -- KAPI FIX-160-A: her hedef alt konu, kasa haftası tarihinde MOTOR nezdinde
  -- usable olmalıdır (override ancak published olunca etkili olduğundan bu
  -- noktada motor bu sürümün override'larını zaten görür).
  SELECT aw.starts_at::date INTO v_date FROM public.academic_weeks aw
  WHERE aw.academic_year = '2026-2027' AND aw.week = v_week;
  FOR t IN SELECT subtopic_id FROM public.vault_subtopic_targets
           WHERE version_id = p_version_id
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.curriculum_subtopic_week_state(v_grade, v_subject, v_date) x
      WHERE x.subtopic_id = t.subtopic_id AND x.is_usable
    ) THEN
      RAISE EXCEPTION 'YAYIN_162: alt konu K% tarihinde motor kapisi nedeniyle kullanilabilir degil.', v_week;
    END IF;
  END LOOP;

  -- Etki kuyruğu: override'lar etkilenen kasa bandını recalc_queue'ye yazar (165+)
  FOR o IN SELECT * FROM public.vault_plan_week_overrides WHERE version_id = p_version_id
  LOOP
    SELECT min(aw.week)::smallint INTO v_k1 FROM public.academic_weeks aw
    WHERE aw.academic_year='2026-2027' AND aw.instruction_week_number = o.old_first_I;
    SELECT min(aw.week)::smallint INTO v_k2 FROM public.academic_weeks aw
    WHERE aw.academic_year='2026-2027' AND aw.instruction_week_number = o.new_first_I;
    SELECT array_agg(q.id) INTO v_uids
    FROM public.question_vaults q
    WHERE q.vault_type = 'weekly' AND q.grade_level = v_grade AND q.subject_id = v_subject
      AND q.week_number >= least(v_k1, v_k2);
    INSERT INTO public.vault_plan_recalc_queue
      (academic_year, subtopic_id, old_first_I, new_first_I, affected_vaults, reason, created_by)
    VALUES ('2026-2027', o.subtopic_id, o.old_first_I, o.new_first_I,
            coalesce(v_uids, '{}'), 'publish:' || p_version_id::text, p_actor);
    v_affected := coalesce(v_affected, '{}'::uuid[]) || coalesce(v_uids, '{}'::uuid[]);
  END LOOP;

  PERFORM public._vp_audit(p_version_id, p_actor, 'publish', NULL, NULL,
    jsonb_build_object('target_sum', v_sum), v_affected);
END $fn$;

-- ------------------------------------------------------------
-- RPC — vault_plan_publish (yetki + İKİ-KİŞİ kuralı + çekirdek)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vault_plan_publish(p_version_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_uid uuid := public._vp_require('vault_plan.publish');
  v_rec RECORD;
BEGIN
  SELECT status, created_by INTO v_rec
  FROM public.vault_plan_versions WHERE id = p_version_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SURUM_162: surum bulunamadi.';
  END IF;
  IF v_rec.status <> 'validated' THEN
    RAISE EXCEPTION 'SURUM_162: yalniz validated surum yayinlanir (durum: %).', v_rec.status;
  END IF;
  IF v_rec.created_by = v_uid THEN
    RAISE EXCEPTION 'IKIKISI_162: yayimlayan surumu olusturamaz (iki-kisi kurali).';
  END IF;
  PERFORM public._vp_publish_core(p_version_id, v_uid);
END $fn$;

-- ------------------------------------------------------------
-- RPC — vault_plan_rollback (geri dönüş = eski sürümün YENİ sürüm olarak
--        kopyalanıp yayınlanması; iki-kişi: çağıran mevcut yayının onaylayanı olamaz)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vault_plan_rollback(
  p_vault_id uuid, p_to_version_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_uid uuid := public._vp_require('vault_plan.publish');
  v_src RECORD; v_cur RECORD; v_no integer; v_id uuid;
BEGIN
  PERFORM public._vp_vault(p_vault_id);
  SELECT * INTO v_cur FROM public.vault_plan_versions
  WHERE vault_id = p_vault_id AND status = 'published';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SURUM_162: geri-alinacak yayinlanmis surum yok.';
  END IF;
  IF v_cur.approved_by = v_uid THEN
    RAISE EXCEPTION 'IKIKISI_162: plani yayinlayan yonetici geri-alimi tek basina yapamaz.';
  END IF;

  SELECT * INTO v_src FROM public.vault_plan_versions
  WHERE id = p_to_version_id AND vault_id = p_vault_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SURUM_162: kaynak surum bu kasaya ait degil.';
  END IF;
  IF v_src.id = v_cur.id THEN
    RAISE EXCEPTION 'SURUM_162: kaynak zaten yayinda.';
  END IF;

  SELECT coalesce(max(version_no), 0) + 1 INTO v_no
  FROM public.vault_plan_versions WHERE vault_id = p_vault_id;
  INSERT INTO public.vault_plan_versions
    (academic_year, vault_id, version_no, status, base_version_id, reason, created_by)
  VALUES (v_cur.academic_year, p_vault_id, v_no, 'draft', v_src.id,
          'rollback:surum-' || v_src.version_no, v_uid)
  RETURNING id INTO v_id;

  INSERT INTO public.vault_subtopic_targets (version_id, subtopic_id, question_target, note)
  SELECT v_id, t.subtopic_id, t.question_target, t.note
  FROM public.vault_subtopic_targets t WHERE t.version_id = v_src.id;
  INSERT INTO public.vault_plan_week_overrides
    (version_id, subtopic_id, old_first_I, new_first_I, reason, advance_evidence)
  SELECT v_id, o.subtopic_id, o.old_first_I, o.new_first_I, o.reason, o.advance_evidence
  FROM public.vault_plan_week_overrides o WHERE o.version_id = v_src.id;

  PERFORM public._vp_audit(v_id, v_uid, 'rollback_create', NULL, NULL,
    jsonb_build_object('source_version', v_src.id));
  UPDATE public.vault_plan_versions SET status = 'validated' WHERE id = v_id;
  PERFORM public._vp_publish_core(v_id, v_uid);
  RETURN v_id;
END $fn$;

-- ------------------------------------------------------------
-- RPC — vault_plan_impact_preview (yayınlanmadan etkilenen kasalar)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vault_plan_impact_preview(p_version_id uuid)
RETURNS TABLE (vault_id uuid, vault_code text, week_number smallint,
               subtopic_id uuid, impact text, delta integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_grade smallint; v_subject uuid; v_base uuid; v_k1 smallint; v_k2 smallint;
  v_eff smallint; r RECORD; t RECORD;
BEGIN
  PERFORM public._vp_require('vault_plan.manage');
  SELECT pv.base_version_id, v.grade_level, v.subject_id
    INTO v_base, v_grade, v_subject
  FROM public.vault_plan_versions pv
  JOIN public._vp_vault(pv.vault_id) v ON TRUE
  WHERE pv.id = p_version_id;

  -- A) hafta override'ları: taşma bandındaki kasalar
  FOR r IN SELECT * FROM public.vault_plan_week_overrides
           WHERE version_id = p_version_id
  LOOP
    SELECT min(aw.week)::smallint INTO v_k1 FROM public.academic_weeks aw
    WHERE aw.academic_year='2026-2027' AND aw.instruction_week_number = r.old_first_I;
    SELECT min(aw.week)::smallint INTO v_k2 FROM public.academic_weeks aw
    WHERE aw.academic_year='2026-2027' AND aw.instruction_week_number = r.new_first_I;
    RETURN QUERY
    SELECT q.id, q.vault_code, q.week_number::smallint, r.subtopic_id,
           CASE WHEN r.new_first_I > r.old_first_I THEN 'icerik_kaldirilir'
                ELSE 'icerik_eklenir' END,
           0
    FROM public.question_vaults q
    WHERE q.vault_type='weekly' AND q.grade_level = v_grade AND q.subject_id = v_subject
      AND ((r.new_first_I > r.old_first_I AND q.week_number >= v_k1 AND q.week_number < v_k2)
        OR (r.new_first_I < r.old_first_I AND q.week_number >= v_k2 AND q.week_number < v_k1));
  END LOOP;

  -- B) hedef eklenme/değişme (base varsa diff; yoksa tüm hedefler öneri)
  FOR t IN
    SELECT d.subtopic_id, d.question_target AS new_t, b.question_target AS old_t
    FROM public.vault_subtopic_targets d
    LEFT JOIN public.vault_subtopic_targets b
      ON b.version_id = v_base AND b.subtopic_id = d.subtopic_id
    WHERE d.version_id = p_version_id
      AND (v_base IS NULL OR b.subtopic_id IS NULL OR b.question_target <> d.question_target)
  LOOP
    SELECT coalesce((SELECT o.new_first_I FROM public.vault_plan_week_overrides o
                     WHERE o.version_id = p_version_id AND o.subtopic_id = t.subtopic_id),
                    public.vault_plan_effective_first_i('2026-2027', v_grade, v_subject, t.subtopic_id))
      INTO v_eff;
    SELECT min(aw.week)::smallint INTO v_k1 FROM public.academic_weeks aw
    WHERE aw.academic_year='2026-2027' AND aw.instruction_week_number = v_eff;
    RETURN QUERY
    SELECT q.id, q.vault_code, q.week_number::smallint, t.subtopic_id,
           CASE WHEN t.old_t IS NULL THEN 'hedef_eklenir' ELSE 'hedef_degisir' END,
           (t.new_t - coalesce(t.old_t, 0))::integer
    FROM public.question_vaults q
    WHERE q.vault_type='weekly' AND q.grade_level = v_grade AND q.subject_id = v_subject
      AND q.week_number >= v_k1;
  END LOOP;

  -- C) hedef kaldırma (base'te olup taslakta olmayan)
  IF v_base IS NOT NULL THEN
    FOR t IN
      SELECT b.subtopic_id, b.question_target
      FROM public.vault_subtopic_targets b
      WHERE b.version_id = v_base
        AND NOT EXISTS (SELECT 1 FROM public.vault_subtopic_targets d
                        WHERE d.version_id = p_version_id AND d.subtopic_id = b.subtopic_id)
    LOOP
      SELECT coalesce((SELECT o.new_first_I FROM public.vault_plan_week_overrides o
                       WHERE o.version_id = p_version_id AND o.subtopic_id = t.subtopic_id),
                      public.vault_plan_effective_first_i('2026-2027', v_grade, v_subject, t.subtopic_id))
        INTO v_eff;
      SELECT min(aw.week)::smallint INTO v_k1 FROM public.academic_weeks aw
      WHERE aw.academic_year='2026-2027' AND aw.instruction_week_number = v_eff;
      RETURN QUERY
      SELECT q.id, q.vault_code, q.week_number::smallint, t.subtopic_id,
             'hedef_kaldirilir', (-t.question_target)::integer
      FROM public.question_vaults q
      WHERE q.vault_type='weekly' AND q.grade_level = v_grade AND q.subject_id = v_subject
        AND q.week_number >= v_k1;
    END LOOP;
  END IF;
END $fn$;

-- ------------------------------------------------------------
-- RPC — vault_plan_history / vault_plan_gaps (salt-okunur yönetici görünümleri)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vault_plan_history(p_vault_id uuid)
RETURNS TABLE (version_id uuid, version_no integer, status text, reason text,
               created_by uuid, approved_by uuid, created_at timestamptz,
               published_at timestamptz, base_version_id uuid, changes_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  PERFORM public._vp_require('vault_plan.manage');
  RETURN QUERY
  SELECT pv.id, pv.version_no, pv.status, pv.reason, pv.created_by, pv.approved_by,
         pv.created_at, pv.published_at, pv.base_version_id,
         (SELECT count(*) FROM public.vault_plan_changes c WHERE c.version_id = pv.id)
  FROM public.vault_plan_versions pv
  WHERE pv.vault_id = p_vault_id
  ORDER BY pv.version_no;
END $fn$;

-- Hedef / mevcut / eksik ayrı ayrı (yalnız published planlar; 165 worker hamuru)
CREATE OR REPLACE FUNCTION public.vault_plan_gaps(p_grade smallint, p_subject uuid)
RETURNS TABLE (vault_id uuid, vault_code text, week_number smallint, subtopic_id uuid,
               target integer, placed_now integer, deficit integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  PERFORM public._vp_require('vault_plan.manage');
  RETURN QUERY
  SELECT q.id, q.vault_code, q.week_number::smallint, t.subtopic_id,
         t.question_target,
         ((SELECT count(*) FROM public.weekly_vault_placements p
           WHERE p.vault_id = q.id AND p.subtopic_id = t.subtopic_id
             AND p.placement_status = 'active'))::integer,
         (greatest(t.question_target - (SELECT count(*) FROM public.weekly_vault_placements p
           WHERE p.vault_id = q.id AND p.subtopic_id = t.subtopic_id
             AND p.placement_status = 'active'), 0))::integer
  FROM public.vault_plan_versions pv
  JOIN public.question_vaults q ON q.id = pv.vault_id
  JOIN public.vault_subtopic_targets t ON t.version_id = pv.id
  WHERE pv.status = 'published' AND q.vault_type = 'weekly'
    AND q.grade_level = p_grade AND q.subject_id = p_subject;
END $fn$;

-- ------------------------------------------------------------
-- 6) MOTOR YENİDEN TANIMI — tek diffs: first_instruction_week okuması artık
--    EFFECTIVE (yayınlanmış override varsa o, yoksa 160 base → çıktı aynı).
--    FIX-160-A (K1) kapısı yapıca birebir korunur: resmî statü + EXISTS(verify)
--    + hafta gelmiş + new_topic_allowed bayrağı.
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
         coalesce(ov.new_first_I, m.first_instruction_week),
         m.repeat_from_instruction_week,
         m.mapping_confidence, m.evidence_kind,
         -- FIX-160-A (K1): yönetici onayı TEK BAŞINA erişim VERMEZ. Öğrenci
         -- erişimi için resmî statü (yalnız curriculum_week_map_verify ile ve
         -- resmî belge kanıtıyla kazanılır) + haftanın gelmesi GEREKLİDİR.
         -- 162: hafta = EFFECTIVE I (published override varsa o).
         (m.mapping_confidence IN ('resmi_dogrudan', 'resmi_dolayli')
          AND EXISTS (SELECT 1 FROM public.curriculum_week_map_verification v
                       WHERE v.map_id = m.id)
          AND (coalesce(ov.new_first_I, m.first_instruction_week) < v_i
               OR (coalesce(ov.new_first_I, m.first_instruction_week) = v_i
                   AND coalesce(v_allow, FALSE)))) AS is_usable,
         CASE
           WHEN m.mapping_confidence = 'tahmini_onay_bekliyor'
                AND m.approved_at IS NULL THEN 'locked_unapproved'
           WHEN m.mapping_confidence = 'tahmini_onay_bekliyor'
                AND m.approved_at IS NOT NULL THEN 'approved_pending_official'
           WHEN coalesce(ov.new_first_I, m.first_instruction_week) > v_i THEN 'locked_future'
           WHEN coalesce(ov.new_first_I, m.first_instruction_week) = v_i
                AND coalesce(v_allow, FALSE) THEN 'new_this_week'
           WHEN coalesce(ov.new_first_I, m.first_instruction_week) = v_i THEN 'held_pending'
           ELSE 'opened_repeat'
         END AS state,
         v_year, v_week, v_i, coalesce(v_kind, 'atanmamis'),
         coalesce(v_allow, FALSE)
  FROM public.curriculum_subtopic_week_map m
  JOIN public.subtopics st ON st.id = m.subtopic_id AND st.is_active
  JOIN public.topics t     ON t.id = m.topic_id AND t.is_active
  LEFT JOIN LATERAL (
    -- 162: bu (yıl, sınıf, ders) çiftinin SON published plan sürümündeki
    -- override; yoksa NULL → base. Override yalnız YAYINLANINCA etkili olur.
    SELECT o.new_first_I
    FROM public.vault_plan_week_overrides o
    JOIN public.vault_plan_versions pv
      ON pv.id = o.version_id AND pv.status = 'published'
     AND pv.academic_year = m.academic_year
    JOIN public.question_vaults qv
      ON qv.id = pv.vault_id AND qv.vault_type = 'weekly'
     AND qv.grade_level = m.grade_level AND qv.subject_id = m.subject_id
    WHERE o.subtopic_id = m.subtopic_id
    ORDER BY pv.published_at DESC NULLS LAST
    LIMIT 1
  ) ov ON TRUE
  WHERE m.academic_year = v_year
    AND m.grade_level = p_grade_level
    AND m.subject_id = p_subject_id;
END
$fn$;

-- ------------------------------------------------------------
-- 7) HARDEN-1 (42-09 §9): 159 metadata'lı haftaların TARİH/HAFTA kaydırma
--    UPDATE'i ve DELETE'i yapısal olarak reddedilir. K42 activated_at ve
--    other-flag UPDATE'leri serbest; INSERT (yeni hafta) serbest.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_academic_weeks_harden1()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $fn$
BEGIN
  IF OLD.week_kind IS NOT NULL THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'CALENDAR_162: 159 metadata''li hafta silinemez (HARDEN-1).';
    END IF;
    IF NEW.starts_at IS DISTINCT FROM OLD.starts_at
       OR NEW.ends_at IS DISTINCT FROM OLD.ends_at
       OR NEW.week IS DISTINCT FROM OLD.week
    THEN
      RAISE EXCEPTION 'CALENDAR_162: 159 metadata''li haftanin tarihi/numarasi kaydirilamaz (HARDEN-1).';
    END IF;
  END IF;
  RETURN COALESCE(NEW, OLD);
END $fn$;

CREATE TRIGGER trg_academic_weeks_harden1
  BEFORE UPDATE OR DELETE ON public.academic_weeks
  FOR EACH ROW EXECUTE FUNCTION public.enforce_academic_weeks_harden1();

-- ------------------------------------------------------------
-- 8) GRANTLAR — RPC'ler yalnız authenticated+service_role (yetki RPC İÇİNDE
--    sorgulanır); iç yardımcılar ve tetik fonksiyonları authenticated'e kapalı.
-- ------------------------------------------------------------
DO $grants$
DECLARE
  v_pub text[] := ARRAY[
    'vault_plan_version_create(uuid,uuid,text)',
    'vault_plan_target_set(uuid,uuid,integer,text)',
    'vault_plan_target_remove(uuid,uuid)',
    'vault_plan_week_defer(uuid,uuid,smallint,text)',
    'vault_plan_week_advance(uuid,uuid,smallint,jsonb,text)',
    'vault_plan_validate(uuid)',
    'vault_plan_publish(uuid)',
    'vault_plan_rollback(uuid,uuid)',
    'vault_plan_impact_preview(uuid)',
    'vault_plan_history(uuid)',
    'vault_plan_gaps(smallint,uuid)',
    'vault_plan_effective_first_i(text,smallint,uuid,uuid)'];
  f text;
BEGIN
  FOREACH f IN ARRAY v_pub LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated, service_role', f);
  END LOOP;
  -- İç yardımcılar + tetik sarmalayıcıları: istemciden TAM kapalı
  v_pub := ARRAY[
    '_vp_require(text)', '_vp_vault(uuid)', '_vp_map(text,smallint,uuid,uuid)',
    '_vp_require_I_slot(text,smallint)',
    '_vp_audit(uuid,uuid,text,uuid,jsonb,jsonb,uuid[])',
    '_vp_publish_core(uuid,uuid)',
    'enforce_vault_plan_version_immutable()', 'enforce_vault_plan_row_draft_only(uuid)',
    'trg_vst_draft_only()', 'trg_vpwo_draft_only()',
    'enforce_vault_plan_changes_append_only()', 'enforce_academic_weeks_harden1()'];
  FOREACH f IN ARRAY v_pub LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon, authenticated', f);
  END LOOP;
END $grants$;

-- ------------------------------------------------------------
-- 9) Migration geçmişi
-- ------------------------------------------------------------
INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
SELECT '162', '162_editable_vault_plans', NULL
 WHERE NOT EXISTS (
   SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '162'
 );

-- ------------------------------------------------------------
-- FINAL_162 — çıkış sözleşmesi (her şey tek tx; exception = tümü geri)
-- ------------------------------------------------------------
DO $final$
DECLARE
  v        bigint;
  n        bigint;
  p        RECORD;
  v_usable bigint := 0;
  s        RECORD;
BEGIN
  -- 1) Yeni tablolar BOŞ doğmalı (162 veri eklemez)
  SELECT count(*) INTO v FROM public.vault_plan_versions;
  IF v <> 0 THEN RAISE EXCEPTION 'FINAL_162: vault_plan_versions bos dogmadi (%).', v; END IF;
  SELECT count(*) INTO v FROM public.vault_subtopic_targets;
  IF v <> 0 THEN RAISE EXCEPTION 'FINAL_162: vault_subtopic_targets bos dogmadi (%).', v; END IF;
  SELECT count(*) INTO v FROM public.vault_plan_week_overrides;
  IF v <> 0 THEN RAISE EXCEPTION 'FINAL_162: vault_plan_week_overrides bos dogmadi (%).', v; END IF;
  SELECT count(*) INTO v FROM public.vault_plan_changes;
  IF v <> 0 THEN RAISE EXCEPTION 'FINAL_162: vault_plan_changes bos dogmadi (%).', v; END IF;
  SELECT count(*) INTO v FROM public.vault_plan_recalc_queue;
  IF v <> 0 THEN RAISE EXCEPTION 'FINAL_162: vault_plan_recalc_queue bos dogmadi (%).', v; END IF;

  -- 2) Yetki bağları: manage = 2 rol; publish = YALNIZ super_admin
  SELECT count(*) INTO v
  FROM public.admin_role_permissions arp
  JOIN public.admin_roles ar ON ar.id = arp.role_id
  JOIN public.admin_permissions ap ON ap.id = arp.permission_id
  WHERE ap.permission_code = 'vault_plan.manage'
    AND ar.role_code IN ('super_admin','content_admin');
  IF v <> 2 THEN RAISE EXCEPTION 'FINAL_162: vault_plan.manage baglari % (2 olmali).', v; END IF;
  SELECT count(*) INTO v
  FROM public.admin_role_permissions arp
  JOIN public.admin_roles ar ON ar.id = arp.role_id
  JOIN public.admin_permissions ap ON ap.id = arp.permission_id
  WHERE ap.permission_code = 'vault_plan.publish';
  IF v <> 1 THEN RAISE EXCEPTION 'FINAL_162: vault_plan.publish baglari % (1 olmali).', v; END IF;
  SELECT count(*) INTO v
  FROM public.admin_role_permissions arp
  JOIN public.admin_roles ar ON ar.id = arp.role_id
  JOIN public.admin_permissions ap ON ap.id = arp.permission_id
  WHERE ap.permission_code = 'vault_plan.publish' AND ar.role_code = 'super_admin';
  IF v <> 1 THEN RAISE EXCEPTION 'FINAL_162: vault_plan.publish super_admin degil.'; END IF;

  -- 3) Tetikler + kısmi tekil indeks + RLS durumu
  SELECT count(*) INTO v FROM pg_trigger t
  WHERE t.tgname IN ('trg_vpv_immutable','trg_vst_draft_only','trg_vpwo_draft_only',
                     'trg_vpc_append_only','trg_academic_weeks_harden1')
    AND NOT t.tgisinternal AND t.tgenabled = 'O';
  IF v <> 5 THEN RAISE EXCEPTION 'FINAL_162: 162 tetikleri eksik (%/5).', v; END IF;
  IF to_regclass('public.uq_vpv_single_published') IS NULL THEN
    RAISE EXCEPTION 'FINAL_162: uq_vpv_single_published yok.';
  END IF;
  SELECT count(*) INTO v FROM pg_class c
  JOIN pg_namespace nn ON nn.oid = c.relnamespace
  WHERE nn.nspname = 'public'
    AND c.relname IN ('vault_plan_versions','vault_subtopic_targets',
                      'vault_plan_week_overrides','vault_plan_changes',
                      'vault_plan_recalc_queue')
    AND c.relrowsecurity AND c.relforcerowsecurity;
  IF v <> 5 THEN RAISE EXCEPTION 'FINAL_162: RLS/FORCE 5 tabloda da yok (%).', v; END IF;
  SELECT count(*) INTO v FROM pg_policies WHERE schemaname='public'
    AND tablename IN ('vault_plan_versions','vault_subtopic_targets',
                      'vault_plan_week_overrides','vault_plan_changes',
                      'vault_plan_recalc_queue');
  IF v <> 0 THEN RAISE EXCEPTION 'FINAL_162: yeni tablolarda politika var (%).', v; END IF;
  IF has_table_privilege('anon','public.vault_plan_versions','SELECT')
     OR has_table_privilege('authenticated','public.vault_plan_versions','SELECT')
     OR has_table_privilege('authenticated','public.vault_plan_changes','INSERT') THEN
    RAISE EXCEPTION 'FINAL_162: yeni tablolarda istemci GRANT var.';
  END IF;

  -- 4) Motor koruması: 151/158/160/161 imzaları duruyor
  SELECT count(*) INTO v FROM pg_trigger t
  WHERE t.tgname IN ('trg_vault_memberships_pack_limit','trg_question_vaults_pack_limit',
                     'trg_weekly_placements_limit','trg_question_vaults_weekly_type',
                     'trg_question_vaults_weekly_pair','trg_cwmv_immutable')
    AND NOT t.tgisinternal;
  IF v <> 6 THEN RAISE EXCEPTION 'FINAL_162: onceki tetik imzalari bozuldu (%/6).', v; END IF;

  -- 5) Snap对比: kasa bandı, legacy, eşleme, MOTOR usable sayısı değişmedi
  SELECT * INTO s FROM pg_temp.ak162_snap;
  IF (SELECT md5(string_agg(id||'|'||vault_code, ',' ORDER BY vault_code))
      FROM public.question_vaults WHERE vault_type='weekly') <> s.fp_weekly
     OR (SELECT count(*) FROM public.question_vaults)::bigint <> s.n_vaults
     OR (SELECT md5(string_agg(vault_code||'|'||is_active::text||'|'
        ||coalesce(difficulty_level,'-')||'|'||coalesce(week_number::text,'-'), ',' ORDER BY vault_code))
        FROM public.question_vaults WHERE vault_type<>'weekly') <> s.fp_nonweekly
     OR (SELECT count(*) FROM public.question_vault_topics
         WHERE legacy_topic_code IS NOT NULL)::bigint <> s.n_legacy
     OR (SELECT count(*) FROM public.curriculum_subtopic_week_map
         WHERE academic_year='2026-2027')::bigint <> s.n_map
     OR (SELECT count(*) FROM public.curriculum_subtopic_week_map
         WHERE approved_at IS NOT NULL)::bigint <> s.n_map_approved
     OR (SELECT count(*) FROM public.weekly_vault_placements) <> 0 THEN
    RAISE EXCEPTION 'FINAL_162: koruma snapshotlari degisti.';
  END IF;
  FOR p IN SELECT DISTINCT m.grade_level, m.subject_id
           FROM public.curriculum_subtopic_week_map m
          WHERE m.academic_year='2026-2027' LOOP
    SELECT count(*) INTO n
      FROM public.curriculum_subtopic_week_state(
             p.grade_level::smallint, p.subject_id, current_date) x
     WHERE x.is_usable;
    v_usable := v_usable + n;
  END LOOP;
  IF v_usable <> s.n_engine_usable THEN
    RAISE EXCEPTION 'FINAL_162: motor usable sayisi degisti (% -> %).', s.n_engine_usable, v_usable;
  END IF;

  -- 6) HARDEN-1 fonksiyonel probe: K42 satırının tarihi kaydırılamaz (subtx)
  BEGIN
    UPDATE public.academic_weeks SET starts_at = starts_at + 1
    WHERE academic_year='2026-2027' AND week=42;
    RAISE EXCEPTION 'FINAL_162: HARDEN-1 tarih kaydurmayi engellemedi.';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FINAL_162%' THEN RAISE; END IF;  -- CALENDAR_162 beklenir
  END;

  RAISE NOTICE 'FINAL_162 OK: bos dogus + yetki baglari + tetik/RLS + motor + snapler + HARDEN-1 saglam';
END
$final$;

COMMIT;
