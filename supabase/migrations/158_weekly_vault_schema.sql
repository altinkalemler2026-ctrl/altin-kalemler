-- ============================================================
-- 158_weekly_vault_schema.sql
-- AK-MEB-VAULT-42-01 §13 sıra-158: Haftalık kasa şeması (ADDITIVE dilim)
-- ============================================================
-- KAPSAM (kesin, master plan §7 + AK-LEVEL-VAULT-01 §3):
--   1) question_vaults: week_number (1–42, NULL=eski) + vault_kind
--      + vault_type CHECK genişletmesi ('weekly') + weekly şekil CHECK
--      + dört'lü partial UNIQUE (sınıf+ders+zorluk+hafta, aktif weekly).
--   2) weekly_vault_placements: haftalık yarışma yerleşimleri
--      (üyelik DEĞİL — 151 tek-aktif-üyelik sözleşmesine DOKUNULMAZ;
--      görev kuralı §8 "bir soru birden çok haftalık kasaya yerleşebilir"
--      bu yeni tablo ile karşılanır, eski membership yolu aynen kalır).
--   3) Kapasite: haftalık kasaya aktif yerleşim en fazla 200
--      (065 kalıbı: kasa satır kilidi + sayım; 065 ≤5 PAKET limiti
--      değiştirilmez, yeni trigger yalnız placements tablosuna bakar).
--   4) matchmaking_queue.competition_level (NULL=henüz seviyesiz):
--      master plan §13 satır-158; KULLANIMI migration 166'dadır
--      (kuyruk kovası + eşleşme filtresi). Bu migration yalnız kolon.
--
-- DOKUNULMAZLAR (assert edilir):
--   065 (validate_competition_vault_member_limit + iki trigger) —
--   151 (uq_question_active_single_vault) — 157 ACL/RLS matrisi
--   (anon sıfır hak, SEC-1/1b kapanışları, yazılabilir==yazma-poli
--   eşitliği, RLS her tabloda) — eski 36 kasa satırı (DML YOK).
--
-- GÜVENLİK MODELİ (157 sonrası dünya):
--   Yeni tablo postgres sahibi → 157 default-privilege sertleştirmesi
--   nedeniyle örtük anon/authenticated hakkı ÜRETİLMEZ; yine de açık
--   REVOKE hijyeni + FINAL ACL assert. RLS açık, SIFIR politika
--   (öğrenci/istemci okuyamaz-yazamaz; yazım yolu migration 165'te
--   definer RPC + insan onay kapısı — bu migration RPC ÜRETMEZ).
--
-- İLERİ MADDE BAĞIMLILIKLARI (bu dosyaya gizlice alınmadı):
--   159 takvim (hafta geçerliliği/öğretim sayacı/K42 pasif) →
--   160 alt konu hafta eşlemesi → 161 seed 3.654 → 162 hedef matrisi →
--   163 öğrenci haftalık kota (200/40) → 164 seviye üçlüsü →
--   165 otomatik yerleşim (onaylı soru kapısı + stok/uygunluk) →
--   166 yarışma entegrasyonu (queue seviye + pack weekly dal + kota).
--   Bu migration'da weekly kasalar PASİF kalır (hiç kasa tohumlanmaz;
--   seed 161'dedir), hiçbir mevcut RPC haftalık dal görmez.
--
-- İDEMPOTENT: add column if not exists / drop+add constraint (adlı) /
--   create table+index if not exists / create or replace function /
--   drop trigger if exists. Tekrar koşum = no-op (QA T12).
--
-- ROLLBACK (yalnız açık yetki; canlıda henüz UYGULANMAMIŞ):
--   DROP TRIGGER trg_weekly_placements_limit / trg_question_vaults_weekly_type;
--   DROP FUNCTION validate_weekly_vault_placement_rules();
--   DROP TABLE weekly_vault_placements;  -- additive, bağımlı yokken
--   DROP INDEX uq_question_vaults_weekly_scope;
--   ALTER TABLE question_vaults DROP CONSTRAINT question_vaults_weekly_shape;
--   ALTER TABLE question_vaults DROP CONSTRAINT question_vaults_vault_type_check;
--     + 048 tanımının 8 değerle geri eklenmesi (önceki relacl/kolon verisi
--     korunur; haftalık satır üretilmediği sürece veri kaybı yoktur —
--     seed 161 öncesi);
--   ALTER TABLE question_vaults DROP COLUMN week_number, DROP COLUMN vault_kind;
--   ALTER TABLE matchmaking_queue DROP COLUMN competition_level;
--   history version='158' satırı silinir.
--   (Bu sıralama QA'da uygulanıp geri-alım kanıtlanmıştır — rapor §Rollback.)
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- GUARD_158 — ön koşul zinciri (155/156/157 uygulanmış, 065/151 yerinde)
-- ------------------------------------------------------------
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='question_vaults')
  THEN
    RAISE EXCEPTION 'GUARD_158: public.question_vaults yok (048 beklenir).';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_indexes
                 WHERE schemaname='public' AND indexname='uq_question_active_single_vault')
  THEN
    RAISE EXCEPTION 'GUARD_158: 151 tek-kasa indexi yok — korunacak kısıt bulunamadı.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  JOIN pg_class c ON c.oid=t.tgrelid
                  JOIN pg_namespace n ON n.oid=c.relnamespace
                 WHERE n.nspname='public' AND t.tgname='trg_vault_memberships_pack_limit')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger t
                  JOIN pg_class c ON c.oid=t.tgrelid
                  JOIN pg_namespace n ON n.oid=c.relnamespace
                 WHERE n.nspname='public' AND t.tgname='trg_question_vaults_pack_limit')
  THEN
    RAISE EXCEPTION 'GUARD_158: 065 paket limiti triggerları eksik.';
  END IF;

  -- 157 uygulanmış olmalı (SEC-1/1b/2 kapanış probe'ları + history)
  IF has_table_privilege('anon','public.questions','SELECT')
     OR has_table_privilege('anon','public.question_vaults','SELECT')
  THEN
    RAISE EXCEPTION 'GUARD_158: 157 uygulanmamış (anon hâlâ SELECT görebiliyor).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='157')
  THEN
    RAISE EXCEPTION 'GUARD_158: migration history''de 157 kaydı yok.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='matchmaking_queue')
  THEN
    RAISE EXCEPTION 'GUARD_158: public.matchmaking_queue yok (019 beklenir).';
  END IF;

  -- Index önceliği: aktif weekly mükerrer olamaz (bugün weekly satır
  -- yok; yine de 151 kalıbıyla fail-closed).
  IF EXISTS (SELECT 1 FROM pg_attribute
              WHERE attrelid='public.question_vaults'::regclass
                AND attname='week_number' AND attnum>0 AND NOT attisdropped)
  THEN
    IF EXISTS (
      SELECT 1 FROM public.question_vaults
       WHERE vault_type='weekly' AND is_active=true
       GROUP BY grade_level, subject_id, difficulty_level, week_number
      HAVING count(*) > 1
    ) THEN
      RAISE EXCEPTION 'GUARD_158: aktif weekly mükerrer kapsam var — index kurulamaz.';
    END IF;
  END IF;
END
$guard$;

-- ------------------------------------------------------------
-- 1) question_vaults: week_number + vault_kind (additive kolonlar)
-- ------------------------------------------------------------
ALTER TABLE public.question_vaults
  ADD COLUMN IF NOT EXISTS week_number smallint;

DO $c1$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.question_vaults'::regclass
                   AND conname='question_vaults_week_number_check')
  THEN
    ALTER TABLE public.question_vaults
      ADD CONSTRAINT question_vaults_week_number_check
      CHECK (week_number IS NULL OR week_number BETWEEN 1 AND 42);
  END IF;
END
$c1$;

ALTER TABLE public.question_vaults
  ADD COLUMN IF NOT EXISTS vault_kind text;

DO $c2$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.question_vaults'::regclass
                   AND conname='question_vaults_vault_kind_check')
  THEN
    ALTER TABLE public.question_vaults
      ADD CONSTRAINT question_vaults_vault_kind_check
      CHECK (vault_kind IS NULL
             OR vault_kind IN ('yeni_konu','karma','tatil_tekrari','genel_tekrar'));
  END IF;
END
$c2$;

-- ------------------------------------------------------------
-- 2) vault_type CHECK genişletmesi: 'weekly' eklenir, 8 eski değer aynen
--    (048 kanonik tanım korundu — FINAL birebir doğrular)
-- ------------------------------------------------------------
ALTER TABLE public.question_vaults
  DROP CONSTRAINT IF EXISTS question_vaults_vault_type_check;

ALTER TABLE public.question_vaults
  ADD CONSTRAINT question_vaults_vault_type_check
  CHECK (vault_type IN (
    'source','academic','practice','competition','one_v_one',
    'exam','quarantine','archive','weekly'
  ));

-- Weekly şekil sözleşmesi: weekly türlü kasa dört'lü kapsamı TAM taşır.
DO $c3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.question_vaults'::regclass
                   AND conname='question_vaults_weekly_shape')
  THEN
    ALTER TABLE public.question_vaults
      ADD CONSTRAINT question_vaults_weekly_shape
      CHECK (
        vault_type <> 'weekly'
        OR (
          week_number IS NOT NULL
          AND difficulty_level IN ('easy','medium','hard')
          AND grade_level IS NOT NULL
          AND subject_id IS NOT NULL
        )
      );
  END IF;
END
$c3$;

-- Dört'lü partial UNIQUE (aktif weekly; 151 kalıbı, seed 161 için
-- ON CONFLICT (vault_code) hedefinden bağımsız kapsam garantisi).
CREATE UNIQUE INDEX IF NOT EXISTS uq_question_vaults_weekly_scope
  ON public.question_vaults (grade_level, subject_id, difficulty_level, week_number)
  WHERE vault_type = 'weekly' AND is_active = true;

-- ------------------------------------------------------------
-- 3) WEEKLY VAULT PLACEMENTS (yerleşim ≠ üyelik; 151 kapsamı dışı)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.weekly_vault_placements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  vault_id uuid NOT NULL
    REFERENCES public.question_vaults(id) ON DELETE CASCADE,

  question_id uuid NOT NULL
    REFERENCES public.questions(id) ON DELETE CASCADE,

  -- Alt konu denetimi 160/162'de doldurulur; yerleşim için opsiyonel.
  subtopic_id uuid
    REFERENCES public.subtopics(id) ON DELETE SET NULL,

  placement_source text NOT NULL DEFAULT 'auto'
    CHECK (placement_source IN ('auto','manual','seed')),

  placement_status text NOT NULL DEFAULT 'active'
    CHECK (placement_status IN ('active','inactive')),

  placed_by uuid
    REFERENCES auth.users(id) ON DELETE SET NULL,

  placed_at timestamptz NOT NULL DEFAULT now(),

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  CONSTRAINT weekly_vault_placements_unique UNIQUE (vault_id, question_id)
);

CREATE INDEX IF NOT EXISTS idx_weekly_vault_placements_question
  ON public.weekly_vault_placements (question_id);

CREATE INDEX IF NOT EXISTS idx_weekly_vault_placements_active
  ON public.weekly_vault_placements (vault_id)
  WHERE placement_status = 'active';

ALTER TABLE public.weekly_vault_placements
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.weekly_vault_placements FROM public, anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.weekly_vault_placements TO service_role;

-- ------------------------------------------------------------
-- 4) Kapasite + hedef tip doğrulaması (065 kalıbı; 065'in KENDİNE
--    dokunulmaz — ayrı fonksiyon, ayrı triggerlar)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_weekly_vault_placement_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_vault_type  text;
  v_active_count integer;
BEGIN
  -- ---- A) weekly_vault_placements yazımları -----------------
  IF tg_table_name = 'weekly_vault_placements' THEN

    -- Kasası ve durumu değişmeyen UPDATE kapasiteyi etkilemez.
    IF tg_op = 'UPDATE'
       AND new.vault_id IS NOT DISTINCT FROM old.vault_id
       AND new.placement_status IS NOT DISTINCT FROM old.placement_status
    THEN
      RETURN new;
    END IF;

    -- Hedef kasa ZORUNLU weekly (fail-closed; kasa yoksa da reddet).
    SELECT qv.vault_type INTO v_vault_type
      FROM public.question_vaults qv
     WHERE qv.id = new.vault_id;

    IF v_vault_type IS NULL THEN
      RAISE EXCEPTION 'Vault not found for weekly placement validation.';
    END IF;

    IF v_vault_type <> 'weekly' THEN
      RAISE EXCEPTION
        'weekly_vault_placements only accepts vault_type = weekly (got %).',
        v_vault_type;
    END IF;

    -- Pasif satır doluluk taşımaz (065 F-2 semantiği).
    IF new.placement_status <> 'active' THEN
      RETURN new;
    END IF;

    -- Eşzamanlılık: kasa satır kilidi + kilit altında çift kontrol
    -- (065 F-1 kalıbı).
    SELECT qv.vault_type INTO v_vault_type
      FROM public.question_vaults qv
     WHERE qv.id = new.vault_id
       FOR UPDATE;

    IF v_vault_type <> 'weekly' THEN
      RAISE EXCEPTION
        'weekly_vault_placements only accepts vault_type = weekly (lock recheck got %).',
        v_vault_type;
    END IF;

    SELECT count(*) INTO v_active_count
      FROM public.weekly_vault_placements p
     WHERE p.vault_id = new.vault_id
       AND p.placement_status = 'active';

    IF v_active_count + 1 > 200 THEN
      RAISE EXCEPTION
        'Weekly vault placement capacity exceeded. Max: 200, active placements: %',
        v_active_count;
    END IF;

    RETURN new;
  END IF;

  -- ---- B) question_vaults: weekly -> diğer tip geçişi --------
  -- Aktif yerleşimi olan weekly kasa tipini değiştiremez
  -- (yetim yerleşim üretilmez; 065 branch-B'nin aynası).
  IF tg_table_name = 'question_vaults'
     AND tg_op = 'UPDATE'
     AND old.vault_type = 'weekly'
     AND new.vault_type <> 'weekly'
  THEN
    SELECT count(*) INTO v_active_count
      FROM public.weekly_vault_placements p
     WHERE p.vault_id = new.id
       AND p.placement_status = 'active';

    IF v_active_count > 0 THEN
      RAISE EXCEPTION
        'Vault cannot leave weekly type: active weekly placements (%) exist.',
        v_active_count;
    END IF;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trg_weekly_placements_limit
  ON public.weekly_vault_placements;

CREATE TRIGGER trg_weekly_placements_limit
BEFORE INSERT OR UPDATE ON public.weekly_vault_placements
FOR EACH ROW
EXECUTE FUNCTION public.validate_weekly_vault_placement_rules();

DROP TRIGGER IF EXISTS trg_question_vaults_weekly_type
  ON public.question_vaults;

CREATE TRIGGER trg_question_vaults_weekly_type
BEFORE UPDATE ON public.question_vaults
FOR EACH ROW
EXECUTE FUNCTION public.validate_weekly_vault_placement_rules();

-- Trigger çağrımı EXECUTE gerektirmez; doğrudan RPC yüzeyi kapalı (065).
REVOKE EXECUTE
  ON FUNCTION public.validate_weekly_vault_placement_rules()
  FROM public, anon, authenticated;

-- ------------------------------------------------------------
-- 5) matchmaking_queue.competition_level (master plan §13 satır-158;
--    kullanımı 166. NULL = seviye çözümü henüz yok. payload'lara
--    EKLENMEZ — öğrenci yüzeyi değişmez.)
-- ------------------------------------------------------------
ALTER TABLE public.matchmaking_queue
  ADD COLUMN IF NOT EXISTS competition_level text;

DO $c4$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.matchmaking_queue'::regclass
                   AND conname='matchmaking_queue_competition_level_check')
  THEN
    ALTER TABLE public.matchmaking_queue
      ADD CONSTRAINT matchmaking_queue_competition_level_check
      CHECK (competition_level IS NULL
             OR competition_level IN ('easy','medium','hard'));
  END IF;
END
$c4$;

-- ------------------------------------------------------------
-- History — idempotent (151 deseni; FINAL varlığı doğrular)
-- ------------------------------------------------------------
INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
SELECT '158', '158_weekly_vault_schema', NULL
 WHERE NOT EXISTS (
   SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '158'
 );

-- ------------------------------------------------------------
-- FINAL_158 — fail-closed son matris
-- ------------------------------------------------------------
DO $final$
DECLARE
  v_cnt int; v_keep int; v_def text;
BEGIN
  -- 1) Kolonlar
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='question_vaults'
                   AND column_name='week_number')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='question_vaults'
                   AND column_name='vault_kind')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='matchmaking_queue'
                   AND column_name='competition_level')
  THEN
    RAISE EXCEPTION 'FINAL_158: additive kolonlar eksik.';
  END IF;

  -- 2) vault_type CHECK: 9 değer (8 eski + weekly), fazlası yok
  SELECT pg_get_constraintdef(oid) INTO v_def
    FROM pg_constraint
   WHERE conrelid='public.question_vaults'::regclass
     AND conname='question_vaults_vault_type_check';
  IF v_def IS NULL
     OR position('weekly' IN v_def) = 0
     OR position('archive' IN v_def) = 0
     OR position('quarantine' IN v_def) = 0
     OR position('one_v_one' IN v_def) = 0
  THEN
    RAISE EXCEPTION 'FINAL_158: vault_type CHECK beklenmedik: %', coalesce(v_def,'<yok>');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.question_vaults'::regclass
                   AND conname='question_vaults_weekly_shape')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.question_vaults'::regclass
                   AND conname='question_vaults_week_number_check')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.question_vaults'::regclass
                   AND conname='question_vaults_vault_kind_check')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.matchmaking_queue'::regclass
                   AND conname='matchmaking_queue_competition_level_check')
  THEN
    RAISE EXCEPTION 'FINAL_158: CHECK ailesi eksik.';
  END IF;

  -- 3) Dört'lü partial UNIQUE (151 kalıbı: tanım doğrulaması)
  SELECT indexdef INTO v_def FROM pg_indexes
   WHERE schemaname='public' AND indexname='uq_question_vaults_weekly_scope';
  IF v_def IS NULL
     OR v_def NOT LIKE 'CREATE UNIQUE%'
     OR position('(grade_level, subject_id, difficulty_level, week_number)' IN v_def) = 0
     OR position('weekly' IN v_def) = 0
     OR position('is_active' IN v_def) = 0
  THEN
    RAISE EXCEPTION 'FINAL_158: weekly kapsam indexi beklenmedik: %', coalesce(v_def,'<yok>');
  END IF;

  -- 4) placements tablosu: RLS + sıfır politika + ACL + unique + trigger
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema='public' AND table_name='weekly_vault_placements')
  THEN
    RAISE EXCEPTION 'FINAL_158: weekly_vault_placements yok.';
  END IF;

  IF (SELECT relrowsecurity FROM pg_class
       WHERE oid='public.weekly_vault_placements'::regclass) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'FINAL_158: placements RLS kapalı.';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_policy
             WHERE polrelid='public.weekly_vault_placements'::regclass)
  THEN
    RAISE EXCEPTION 'FINAL_158: placements üzerinde politika var (sıfır olmalı).';
  END IF;

  IF has_table_privilege('anon','public.weekly_vault_placements','SELECT')
     OR has_table_privilege('anon','public.weekly_vault_placements','INSERT')
     OR has_table_privilege('authenticated','public.weekly_vault_placements','SELECT')
     OR has_table_privilege('authenticated','public.weekly_vault_placements','INSERT')
     OR has_table_privilege('authenticated','public.weekly_vault_placements','UPDATE')
     OR has_table_privilege('authenticated','public.weekly_vault_placements','DELETE')
     OR has_table_privilege('authenticated','public.weekly_vault_placements','TRUNCATE')
     OR has_table_privilege('public','public.weekly_vault_placements','SELECT')
  THEN
    RAISE EXCEPTION 'FINAL_158: placements ACL sızıntısı (anon/authenticated/public).';
  END IF;

  IF NOT (has_table_privilege('service_role','public.weekly_vault_placements','SELECT')
          AND has_table_privilege('service_role','public.weekly_vault_placements','INSERT')
          AND has_table_privilege('service_role','public.weekly_vault_placements','UPDATE')
          AND has_table_privilege('service_role','public.weekly_vault_placements','DELETE'))
  THEN
    RAISE EXCEPTION 'FINAL_158: service_role placements yolu bozuk.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.weekly_vault_placements'::regclass
                   AND conname='weekly_vault_placements_unique')
  THEN
    RAISE EXCEPTION 'FINAL_158: placements unique yok.';
  END IF;

  IF (SELECT count(*) FROM pg_trigger t
        JOIN pg_class c ON c.oid=t.tgrelid
        JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public'
         AND t.tgname IN ('trg_weekly_placements_limit','trg_question_vaults_weekly_type')) <> 2
  THEN
    RAISE EXCEPTION 'FINAL_158: yeni triggerlar eksik.';
  END IF;

  -- 5) KORUNANLAR: 065 triggerları + 151 indexi + membership CHECK'leri
  IF (SELECT count(*) FROM pg_trigger t
        JOIN pg_class c ON c.oid=t.tgrelid
        JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public'
         AND t.tgname IN ('trg_vault_memberships_pack_limit','trg_question_vaults_pack_limit')) <> 2
  THEN
    RAISE EXCEPTION 'FINAL_158: 065 triggerları kayboldu.';
  END IF;

  SELECT indexdef INTO v_def FROM pg_indexes
   WHERE schemaname='public' AND indexname='uq_question_active_single_vault';
  IF v_def IS NULL OR v_def NOT LIKE 'CREATE UNIQUE%'
  THEN
    RAISE EXCEPTION 'FINAL_158: 151 indexi bozuldu.';
  END IF;

  IF (SELECT count(*) FROM pg_constraint
       WHERE conrelid='public.question_vault_memberships'::regclass
         AND contype='c') <> 3
     OR NOT EXISTS (SELECT 1 FROM pg_constraint
       WHERE conrelid='public.question_vault_memberships'::regclass
         AND conname='question_vault_membership_removed_consistency')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint
       WHERE conrelid='public.question_vault_memberships'::regclass
         AND conname='question_vault_memberships_membership_source_check')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint
       WHERE conrelid='public.question_vault_memberships'::regclass
         AND conname='question_vault_memberships_membership_status_check')
  THEN
    RAISE EXCEPTION 'FINAL_158: membership CHECK kümesi değişti (beklenen 3 adlı satır).';
  END IF;

  -- 6) 157 matrisi KORUNDU (geri sarma tespit cihazı — 157 assert'lerinin
  --    bu dilimi ilgilendiren kritik kesiti)
  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p','v')
     AND (has_table_privilege('anon',c.oid,'SELECT')
          OR has_table_privilege('anon',c.oid,'INSERT')
          OR has_table_privilege('anon',c.oid,'UPDATE')
          OR has_table_privilege('anon',c.oid,'DELETE'));
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FINAL_158: anon hak kirligi % nesnede (157 geri sarmasi?)', v_cnt;
  END IF;

  IF has_function_privilege('anon','public.get_internal_correct_answer(uuid)'::regprocedure,'EXECUTE')
     OR has_function_privilege('authenticated','public.get_internal_correct_answer(uuid)'::regprocedure,'EXECUTE')
  THEN
    RAISE EXCEPTION 'FINAL_158: SEC-1 geri sarildi.';
  END IF;

  SELECT count(*) INTO v_cnt
    FROM information_schema.column_privileges
   WHERE table_schema='public' AND table_name='questions'
     AND grantee='authenticated' AND privilege_type='SELECT';
  IF v_cnt <> 30 THEN
    RAISE EXCEPTION 'FINAL_158: questions auth kolon SELECT % (beklenen 30).', v_cnt;
  END IF;

  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relispartition=false
     AND (has_table_privilege('authenticated',c.oid,'INSERT')
          OR has_table_privilege('authenticated',c.oid,'UPDATE')
          OR has_table_privilege('authenticated',c.oid,'DELETE'));
  SELECT count(*) INTO v_keep
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relispartition=false
     AND EXISTS (SELECT 1 FROM pg_policy p
                  WHERE p.polrelid=c.oid AND p.polcmd IN ('a','w','d','*')
                    AND p.polroles @> ARRAY['authenticated'::regrole::oid]
                    AND p.polpermissive);
  IF v_cnt <> v_keep THEN
    RAISE EXCEPTION 'FINAL_158: yazilabilir tablo % != yazma politikali %', v_cnt, v_keep;
  END IF;

  SELECT count(*) INTO v_cnt
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relrowsecurity=false;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FINAL_158: RLS kapali % tablo var.', v_cnt;
  END IF;

  -- 7) history
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='158') THEN
    RAISE EXCEPTION 'FINAL_158: history kaydi yok.';
  END IF;

  RAISE NOTICE 'WEEKLY158 OK: weekly sema additive (week/kind/type/unique/placements/200 kapisi/queue kolonu); 065 + 151 + 157 matrisleri korundu (yazilabilir=yazma-p %)', v_keep;
END
$final$;

COMMIT;
