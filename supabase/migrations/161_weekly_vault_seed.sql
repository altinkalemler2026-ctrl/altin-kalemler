-- ============================================================
-- 161_weekly_vault_seed.sql
-- AK-MEB-VAULT-42-12: 2026-2027 haftalık yarışma kasası tohumu (ADDITIVE dilim)
-- ============================================================
-- KAPSAM (kesin; master plan §17 sıra-161 + görev 42-12 §3–§9):
--   1) SEED: 29 kanonik sınıf-ders çifti × 42 hafta (K1–K42, academic_weeks)
--      × 3 zorluk (easy/kolay, medium/orta, hard/zor) = 3.654 haftalık kasa
--      satırı. Tohum KAYNAKLARI: curriculum_subtopic_week_map (160 — kanonik
--      29 çift) + academic_weeks (159 — takvim, week_kind). Ayrı/çelişen
--      takvim ÜRETİLMEZ; vault_kind 159 week_kind'ından TÜRETİLİR:
--        teaching        → 'yeni_konu'
--        holiday_review  → 'tatil_tekrari'  (K10, K20, K21, K26)
--        partial_teaching→ 'karma'          (K7, K16, K32, K36)
--        year_end_review → 'genel_tekrar'   (K42)
--   2) BAŞLANGIÇ DURUMU: kasalar BOŞ (0 membership, 0 placement), öğrenci
--      yarışmasına kapalı (allow_practice/competition/one_v_one/exam = false),
--      manuel atama kapalı (manual_question_assignment_allowed = false —
--      162 düzenlenebilir kasa akışı açana dek), öğrenciye gösterilmez
--      (question_vaults RLS zaten 0 politikalı; 161 HİÇBİR yeni anon/auth
--      hakkı vermez). K42'nin 87 kasası is_active=false + metadata
--      requires_admin_activation=true doğar (K42 takvim kapısı 159'dur;
--      question_vaults'ta ayrı aktif-hafta çelişkisi yoktur).
--      is_active semantics: K1–K41 = idari varlık (maçlaşma/yerleşim yok);
--      öğrenci kapısı allow_* bayraklarıdır — 3.567 aktif + 87 pasif.
--   3) KOD SÖZLEŞMESİ: vault_code = '<sınıf>.<dersAdı>.<kolay|orta|zor>.<KK>'
--      (dersAdı = subjects.name kanonik kimliği; örnek 12.Matematik.kolay.01).
--      BEFORE tetiği (trg_question_vaults_weekly_pair) TÜM weekly satırlarda
--      (a) çiftin 160 eşleme kümesinde olmasını (CIFT_161) ve (b) kodun bu
--      kimlikle birebir olmasını (KOD_161) zorlar → "yanlış çift / yanlış kod"
--      yapısal olarak reddedilir.
--   4) BENZERSİZLİK: 158 dört'lü partial UNIQUE (grade,subject,difficulty,week
--      WHERE weekly+aktif) AYNEN korunur; vault_code global UNIQUE tüm
--      satırları (pasif K42 dahil) doğal anahtar olarak ayrıca korur.
--      Kapasite (≤200 aktif yerleşim, 065 kalıbı) 158 tetiklerindedir —
--      200 HEDEF kapasitedir, mevcut soru anlamına gelmez; 065 ≤5 pakete,
--      151 tek-aktif-üyelik kısıtına DOKUNULMAZ.
--   5) 160 KORUNUMU: 546 tahminî eşleme OKUNUR, hiçbir satır onaylanmaz,
--      resmî statü üretilmez, motor (curriculum_subtopic_week_state)
--      değişmez. GUARD motorun bugünkü usable sayısını anlık görüntüler;
--      FINAL aynı değeri görmezse transaction abort (fail-closed).
--   6) ESKİ KASALAR: 36 akademik kasa + 13 LEGACY bağlantı GUARD'da
--      parmak iziyle (md5 kod+aktiflik kümesi) snapshotlanır; FINAL
--      değişim görürse abort. Silme/yeniden adlandırma/pasifleştirme YOK.
--   7) DÜZENLENEBİLİRLİK (42-09 kararı): tohum alt konu İÇERİĞİ sabitlemez
--      (0 yerleşim); 162'nin alt konu ekleme/çıkarma, hafta erteleme/öne
--      alma, sürümlü yayın akışını engelleyen kısıt EKLENMEZ (tetik yalnız
--      kimlik+çift doğrular; içerik/idare 162'nindir).
--
-- YAPISI (158/159/160 deseni): BEGIN → GUARD_161 → tetik → SEED
--   (ON CONFLICT (vault_code) DO NOTHING — yalnız idempotent yeniden işleme;
--   metadata uyuşmazlığı Sessizlik DEĞİL FINAL anti-join'iyle fail-closed) →
--   history INSERT → FINAL_161 → COMMIT. Hata = tam rollback.
-- İKİNCİ UYGULAMA: aynı küme varsa 0 yeni satır, FINAL küme eşitliğini
--   yeniden kanıtlar; beklenmeyen fazla/eksik/uyuşmaz satır → RAISE → rollback.
-- GERİ ALMA (yetkili operasyon, tek transaction):
--   DELETE FROM public.question_vaults WHERE vault_type='weekly';
--   DROP TRIGGER trg_question_vaults_weekly_pair ON public.question_vaults;
--   DROP FUNCTION public.validate_weekly_vault_pair();
--   DELETE FROM supabase_migrations.schema_migrations WHERE version='161';
--   (placement/membership 0 olduğu süveri temiz silinir; 158 nesneleri kalır.)
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- GUARD_161 — ön koşullar (fail-closed) + koruma anlık görüntüleri
-- ------------------------------------------------------------
DO $guard$
DECLARE
  v        bigint;
  n        bigint;
  p        RECORD;
  v_usable bigint := 0;
BEGIN
  -- 1) Zincir: 158 + 159 + 160 applied; 161 kaydı henüz yok
  IF (SELECT count(*) FROM supabase_migrations.schema_migrations
      WHERE version IN ('158','159','160')) <> 3 THEN
    RAISE EXCEPTION 'GUARD_161: 158/159/160 migration zinciri eksik.';
  END IF;

  -- 2) 159 takvim matrisi (donmuş sözleşme — sapma = abort)
  IF to_regclass('public.academic_weeks') IS NULL
     OR (SELECT count(*) FROM public.academic_weeks
         WHERE academic_year = '2026-2027') <> 42 THEN
    RAISE EXCEPTION 'GUARD_161: 2026-2027 K1-K42 takvimi yok (159 beklenir).';
  END IF;
  IF (SELECT count(DISTINCT instruction_week_number) FROM public.academic_weeks
      WHERE academic_year = '2026-2027' AND instruction_week_number IS NOT NULL) <> 37 THEN
    RAISE EXCEPTION 'GUARD_161: I1-I37 sayaci yok (159 beklenir).';
  END IF;
  IF (SELECT count(*) FROM public.academic_weeks WHERE academic_year = '2026-2027'
        AND week_kind = 'holiday_review'
        AND week NOT IN (10,20,21,26)) <> 0
     OR (SELECT count(*) FROM public.academic_weeks WHERE academic_year = '2026-2027'
        AND week_kind = 'holiday_review') <> 4 THEN
    RAISE EXCEPTION 'GUARD_161: tatil haftasi kumesi {10,20,21,26} degisti.';
  END IF;
  IF (SELECT count(*) FROM public.academic_weeks WHERE academic_year = '2026-2027'
        AND week_kind = 'partial_teaching') <> 4
     OR EXISTS (SELECT 1 FROM public.academic_weeks WHERE academic_year = '2026-2027'
        AND week_kind = 'partial_teaching' AND week NOT IN (7,16,32,36)) THEN
    RAISE EXCEPTION 'GUARD_161: kismi tatil kumesi {7,16,32,36} degisti.';
  END IF;
  IF (SELECT count(*) FROM public.academic_weeks WHERE academic_year = '2026-2027'
        AND week_kind = 'teaching') <> 33 THEN
    RAISE EXCEPTION 'GUARD_161: tam ogretim haftasi sayisi 33 degil.';
  END IF;
  IF (SELECT count(*) FROM public.academic_weeks WHERE academic_year = '2026-2027'
        AND week_kind = 'year_end_review' AND week = 42) <> 1 THEN
    RAISE EXCEPTION 'GUARD_161: K42 year_end_review tanimi degisti.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.academic_weeks
      WHERE academic_year = '2026-2027' AND week = 42
        AND requires_admin_activation AND activated_at IS NULL) THEN
    RAISE EXCEPTION 'GUARD_161: K42 yonetici-aktivasyon kapisi acilmis/pasif degil.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.academic_weeks
      WHERE academic_year = '2026-2027' AND week IN (10,20,21,26,36)
        AND new_topic_allowed) THEN
    RAISE EXCEPTION 'GUARD_161: tatil/K36 haftalarindan birinde yeni-konu acik.';
  END IF;
  IF to_regclass('public.meb_holiday_days') IS NULL
     OR (SELECT count(*) FROM public.meb_holiday_days) <> 18 THEN
    RAISE EXCEPTION 'GUARD_161: meb_holiday_days 18 satir degil.';
  END IF;

  -- 3) 160 eşleme kaynağı: tam kapsam + 29 kanonik çift
  IF to_regclass('public.curriculum_subtopic_week_map') IS NULL THEN
    RAISE EXCEPTION 'GUARD_161: esleme tablosu yok (160 beklenir).';
  END IF;
  IF (SELECT count(*) FROM public.curriculum_subtopic_week_map
      WHERE academic_year = '2026-2027') <> 546 THEN
    RAISE EXCEPTION 'GUARD_161: 2026-2027 esleme sayisi 546 degil.';
  END IF;
  IF (SELECT count(*) FROM (SELECT DISTINCT m.grade_level, m.subject_id
        FROM public.curriculum_subtopic_week_map m
       WHERE m.academic_year = '2026-2027') x) <> 29 THEN
    RAISE EXCEPTION 'GUARD_161: kanonik sinif-ders cifti 29 degil.';
  END IF;

  -- 4) Kasa bandı saflığı: haftalık ya hiç yok ya tam (kısmi kalıntı = abort)
  IF (SELECT count(*) FROM public.question_vaults
      WHERE vault_type = 'weekly') NOT IN (0, 3654) THEN
    RAISE EXCEPTION 'GUARD_161: kismi haftalik kasa kalintisi var (0/3654 disi).';
  END IF;
  IF (SELECT count(*) FROM public.weekly_vault_placements) <> 0 THEN
    RAISE EXCEPTION 'GUARD_161: 161 oncesinde weekly_vault_placements bos degil.';
  END IF;
  IF (SELECT count(*) FROM public.question_vault_memberships m
      JOIN public.question_vaults q ON q.id = m.vault_id
      WHERE q.vault_type = 'weekly') <> 0 THEN
    RAISE EXCEPTION 'GUARD_161: haftalik kasaya eskiden membership var.';
  END IF;
  IF (SELECT count(*) FROM public.question_vault_topics
      WHERE legacy_topic_code IS NOT NULL) <> 13 THEN
    RAISE EXCEPTION 'GUARD_161: 13 LEGACY baglantisi bulunamadi.';
  END IF;

  -- 5) 151/158 korunum imzaları
  IF (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public'
      AND indexname IN ('uq_question_vaults_weekly_scope',
                        'uq_question_active_single_vault')) <> 2 THEN
    RAISE EXCEPTION 'GUARD_161: 151/158 benzersizlik imzalari eksik.';
  END IF;
  IF (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
      WHERE t.tgname IN ('trg_vault_memberships_pack_limit','trg_question_vaults_pack_limit',
                         'trg_weekly_placements_limit','trg_question_vaults_weekly_type')
        AND NOT t.tgisinternal) <> 4 THEN
    RAISE EXCEPTION 'GUARD_161: 158 kapasite/tip tetikleri eksik.';
  END IF;

  -- 6) SEC-1 gerisarmasi kapali olmali
  IF has_function_privilege('authenticated',
      'public.get_internal_correct_answer(uuid)'::regprocedure, 'EXECUTE')
     OR has_function_privilege('anon',
      'public.get_internal_correct_answer(uuid)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'GUARD_161: SEC-1 acik — get_internal_correct_answer kirilgan.';
  END IF;

  -- 7) Koruma anlık görüntüleri (FINAL birebir ayniligini kanitlar)
  DROP TABLE IF EXISTS pg_temp.ak161_snap;
  CREATE TEMP TABLE ak161_snap ON COMMIT DROP AS
  SELECT
    (SELECT count(*) FROM public.question_vaults
      WHERE vault_type <> 'weekly')::bigint AS n_nonweekly,
    coalesce((SELECT md5(string_agg(vault_code || '|' || is_active::text
              || '|' || coalesce(difficulty_level, '-') || '|'
              || coalesce(week_number::text, '-'), ',' ORDER BY vault_code))
        FROM public.question_vaults WHERE vault_type <> 'weekly'), 'YOK') AS fp_nonweekly,
    (SELECT count(*) FROM public.question_vault_topics
      WHERE legacy_topic_code IS NOT NULL)::bigint AS n_legacy,
    (SELECT count(*) FROM public.curriculum_subtopic_week_map
      WHERE academic_year = '2026-2027')::bigint AS n_map,
    (SELECT count(*) FROM public.curriculum_subtopic_week_map
      WHERE approved_at IS NOT NULL)::bigint AS n_map_approved,
    (SELECT count(*) FROM public.weekly_vault_placements)::bigint AS n_placement,
    0::bigint AS n_engine_usable;

  -- motor kullanilabilirlik sayimi (bugun) — 161 hicbir sey acamaz
  FOR p IN SELECT DISTINCT m.grade_level, m.subject_id
           FROM public.curriculum_subtopic_week_map m
          WHERE m.academic_year = '2026-2027' LOOP
    SELECT count(*) INTO n
      FROM public.curriculum_subtopic_week_state(
             p.grade_level::smallint, p.subject_id, current_date) x
     WHERE x.is_usable;
    v_usable := v_usable + n;
  END LOOP;
  UPDATE pg_temp.ak161_snap SET n_engine_usable = v_usable;

  RAISE NOTICE 'GUARD_161 OK: zincir + takvim matrisi + 29 cift + bant safligi + 151/158/SEC-1 imzalari + snapler saglam';
END
$guard$;

-- ------------------------------------------------------------
-- KİMLİK TETİĞİ — weekly kasalar yalnız kanonik çift + kanonik kod
-- (görev 42-12 §3: "Kanonik ders kimlikleriyle eşleşmeyen kodları kabul etme")
-- SECURITY DEFINER: iç okumalar tablo sahibiyle koşar; tetik işlevi
-- anon/authenticated'e kapalıdır (REVOKE) — INSERT yolu zaten RLS+GRANT dışı.
-- NOT: çift kümesi 160 eşlemesinden OKUNUR (tüm eğitim-öğretim yılları);
-- 2027-2028 genişlemesi 162+ kararıdır — eşleme satırı eklenince tetik
-- kendiliğinden o çiftleri de kanonik sayar (sert yıl sabiti YOK).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_weekly_vault_pair()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_name     text;
  v_tr       text;
  v_expected text;
BEGIN
  IF NEW.vault_type <> 'weekly' THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.curriculum_subtopic_week_map m
                  WHERE m.grade_level = NEW.grade_level
                    AND m.subject_id  = NEW.subject_id) THEN
    RAISE EXCEPTION 'CIFT_161: weekly kasa yalniz 160 eslemesindeki kanonik sinif-ders cifti icin olusabilir (sinif=%, ders=%).',
      NEW.grade_level, NEW.subject_id;
  END IF;

  SELECT s.name INTO v_name FROM public.subjects s WHERE s.id = NEW.subject_id;
  v_tr := CASE NEW.difficulty_level
            WHEN 'easy'   THEN 'kolay'
            WHEN 'medium' THEN 'orta'
            WHEN 'hard'   THEN 'zor'
            ELSE NULL
          END;

  IF NEW.grade_level IS NULL OR NEW.week_number IS NULL
     OR v_tr IS NULL OR v_name IS NULL THEN
    RAISE EXCEPTION 'KOD_161: weekly kasa icin sinif+ders+zorluk(easy|medium|hard)+hafta eksiksiz olmali.';
  END IF;

  v_expected := NEW.grade_level || '.' || v_name || '.' || v_tr
                || '.' || lpad(NEW.week_number::text, 2, '0');
  IF NEW.vault_code IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'KOD_161: kasa kodu kanonik kimlikle eslesmiyor (beklenen=%, gelen=%).',
      v_expected, NEW.vault_code;
  END IF;

  RETURN NEW;
END
$fn$;

REVOKE EXECUTE ON FUNCTION public.validate_weekly_vault_pair()
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.validate_weekly_vault_pair() IS
  'AK-MEB-VAULT-42-12: weekly question_vaults satirlarinda kanonik sinif-ders cifti (160) ve kanonik vault_code kimligini zorlar (CIFT_161/KOD_161).';

DROP TRIGGER IF EXISTS trg_question_vaults_weekly_pair ON public.question_vaults;
CREATE TRIGGER trg_question_vaults_weekly_pair
  BEFORE INSERT OR UPDATE OF vault_type, grade_level, subject_id,
                               difficulty_level, week_number, vault_code
  ON public.question_vaults
  FOR EACH ROW EXECUTE FUNCTION public.validate_weekly_vault_pair();

-- ------------------------------------------------------------
-- SEED_161 — 29 çift × 42 hafta × 3 zorluk = 3.654 boş, kapalı kasa
-- ON CONFLICT (vault_code) DO NOTHING YALNIZ idempotent yeniden isleme
-- amaçlıdır; beklenen-metadata uyuşmazlığı FINAL anti-join'iyle fail-closed.
-- ------------------------------------------------------------
INSERT INTO public.question_vaults
  (vault_code, name, vault_type, grade_level, subject_id, difficulty_level,
   week_number, vault_kind, is_active,
   allow_practice, allow_competition, allow_one_v_one, allow_exam,
   manual_question_assignment_allowed, is_dynamic, metadata)
SELECT
  e.vault_code,
  e.grade_level || '. Sinif ' || e.subject_name || ' ' || e.label
    || ' - K' || lpad(e.week::text, 2, '0'),
  'weekly',
  e.grade_level,
  e.subject_id,
  e.lvl,
  e.week,
  e.kind,
  (e.week < 42),
  false, false, false, false,
  false, false,
  jsonb_build_object(
    'ak_meb_seed', '161',
    'academic_year', '2026-2027',
    'requires_admin_activation', (e.week = 42),
    'calendar_week_kind', e.week_kind
  )
FROM (
  SELECT
    g.grade_level,
    s.id   AS subject_id,
    s.name AS subject_name,
    w.week,
    w.week_kind,
    d.tr,
    d.label,
    d.lvl,
    CASE w.week_kind
      WHEN 'teaching'         THEN 'yeni_konu'
      WHEN 'holiday_review'   THEN 'tatil_tekrari'
      WHEN 'partial_teaching' THEN 'karma'
      WHEN 'year_end_review'  THEN 'genel_tekrar'
    END AS kind,
    g.grade_level || '.' || s.name || '.' || d.tr
      || '.' || lpad(w.week::text, 2, '0') AS vault_code
  FROM (SELECT DISTINCT m.grade_level, m.subject_id
          FROM public.curriculum_subtopic_week_map m
         WHERE m.academic_year = '2026-2027') g
  JOIN public.subjects s       ON s.id = g.subject_id
  JOIN public.academic_weeks w ON w.academic_year = '2026-2027'
  CROSS JOIN (VALUES
    ('kolay', 'Kolay', 'easy'),
    ('orta',  'Orta',  'medium'),
    ('zor',   'Zor',   'hard')
  ) AS d (tr, label, lvl)
) e
ON CONFLICT (vault_code) DO NOTHING;

-- ------------------------------------------------------------
-- History — idempotent (151/158/159/160 deseni)
-- ------------------------------------------------------------
INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
SELECT '161', '161_weekly_vault_seed', NULL
 WHERE NOT EXISTS (
   SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '161'
 );

-- ------------------------------------------------------------
-- FINAL_161 — fail-closed son matris
-- ------------------------------------------------------------
DO $final$
DECLARE
  v            bigint;
  n            bigint;
  fp           text;
  p            RECORD;
  v_nonweekly  bigint;
  v_legacy     bigint;
  v_map        bigint;
  v_mapapp     bigint;
  v_plc        bigint;
  v_snap_usable bigint;
  v_usable     bigint := 0;
BEGIN
  -- F0) History kaydı bu transaction'da kuruldu
  IF (SELECT count(*) FROM supabase_migrations.schema_migrations
      WHERE version = '161' AND name = '161_weekly_vault_seed') <> 1 THEN
    RAISE EXCEPTION 'FINAL_161: history 161 kaydi yok.';
  END IF;

  -- F1) KÜME EŞİTLİĞİ (üç yönlü anti-join; sessiz DO NOTHING kabul edilmez)
  WITH exp AS (
    SELECT g.grade_level, s.id AS subject_id, s.name AS subject_name, w.week,
           w.week_kind, d.lvl,
           CASE w.week_kind
             WHEN 'teaching'         THEN 'yeni_konu'
             WHEN 'holiday_review'   THEN 'tatil_tekrari'
             WHEN 'partial_teaching' THEN 'karma'
             WHEN 'year_end_review'  THEN 'genel_tekrar'
           END AS kind,
           g.grade_level || '.' || s.name || '.' || d.tr
             || '.' || lpad(w.week::text, 2, '0') AS vault_code
      FROM (SELECT DISTINCT m.grade_level, m.subject_id
              FROM public.curriculum_subtopic_week_map m
             WHERE m.academic_year = '2026-2027') g
      JOIN public.subjects s       ON s.id = g.subject_id
      JOIN public.academic_weeks w ON w.academic_year = '2026-2027'
      CROSS JOIN (VALUES ('kolay','Kolay','easy'),('orta','Orta','medium'),
                         ('zor','Zor','hard')) AS d (tr, label, lvl)
  )
  SELECT count(*) INTO v FROM exp e
   WHERE NOT EXISTS (SELECT 1 FROM public.question_vaults q
                      WHERE q.vault_code = e.vault_code);
  IF v <> 0 THEN
    RAISE EXCEPTION 'FINAL_161: beklenen kasa eksik=% (idempotency bozuk).', v;
  END IF;

  -- F1b) metadata uyuşmazlığı → fail-closed (sessiz DO NOTHING YOK)
  WITH exp AS (
    SELECT g.grade_level, s.id AS subject_id, w.week,
           CASE w.week_kind
             WHEN 'teaching'         THEN 'yeni_konu'
             WHEN 'holiday_review'   THEN 'tatil_tekrari'
             WHEN 'partial_teaching' THEN 'karma'
             WHEN 'year_end_review'  THEN 'genel_tekrar'
           END AS kind,
           d.lvl,
           g.grade_level || '.' || s.name || '.' || d.tr
             || '.' || lpad(w.week::text, 2, '0') AS vault_code
      FROM (SELECT DISTINCT m.grade_level, m.subject_id
              FROM public.curriculum_subtopic_week_map m
             WHERE m.academic_year = '2026-2027') g
      JOIN public.subjects s       ON s.id = g.subject_id
      JOIN public.academic_weeks w ON w.academic_year = '2026-2027'
      CROSS JOIN (VALUES ('kolay','Kolay','easy'),('orta','Orta','medium'),
                         ('zor','Zor','hard')) AS d (tr, label, lvl)
  )
  SELECT count(*) INTO v FROM exp e
  JOIN public.question_vaults q ON q.vault_code = e.vault_code
   WHERE q.vault_type IS DISTINCT FROM 'weekly'
      OR q.grade_level IS DISTINCT FROM e.grade_level
      OR q.subject_id IS DISTINCT FROM e.subject_id
      OR q.difficulty_level IS DISTINCT FROM e.lvl
      OR q.week_number IS DISTINCT FROM e.week
      OR q.vault_kind IS DISTINCT FROM e.kind
      OR q.is_active IS DISTINCT FROM (e.week < 42)
      OR q.allow_practice IS DISTINCT FROM false
      OR q.allow_competition IS DISTINCT FROM false
      OR q.allow_one_v_one IS DISTINCT FROM false
      OR q.allow_exam IS DISTINCT FROM false
      OR q.manual_question_assignment_allowed IS DISTINCT FROM false
      OR q.metadata->>'ak_meb_seed' IS DISTINCT FROM '161'
      OR q.metadata->>'academic_year' IS DISTINCT FROM '2026-2027'
      OR q.metadata->>'requires_admin_activation'
         IS DISTINCT FROM (e.week = 42)::text;
  IF v <> 0 THEN
    RAISE EXCEPTION 'FINAL_161: beklenen metadata ile uyusmayan kasa=% — sessiz carpisma kabul edilmez.', v;
  END IF;

  -- F1c) beklenmeyen haftalık fazla satır YOK
  WITH exp AS (
    SELECT g.grade_level || '.' || s.name || '.' || d.tr
             || '.' || lpad(w.week::text, 2, '0') AS vault_code
      FROM (SELECT DISTINCT m.grade_level, m.subject_id
              FROM public.curriculum_subtopic_week_map m
             WHERE m.academic_year = '2026-2027') g
      JOIN public.subjects s       ON s.id = g.subject_id
      JOIN public.academic_weeks w ON w.academic_year = '2026-2027'
      CROSS JOIN (VALUES ('kolay'),('orta'),('zor')) AS d (tr)
  )
  SELECT count(*) INTO v FROM public.question_vaults q
   WHERE q.vault_type = 'weekly'
     AND NOT EXISTS (SELECT 1 FROM exp x WHERE x.vault_code = q.vault_code);
  IF v <> 0 THEN
    RAISE EXCEPTION 'FINAL_161: beklenmeyen haftalik kasa=%.', v;
  END IF;

  -- F2) toplam + durum matrisi
  IF (SELECT count(*) FROM public.question_vaults
      WHERE vault_type = 'weekly') <> 3654 THEN
    RAISE EXCEPTION 'FINAL_161: haftalik kasa toplami 3654 degil.';
  END IF;
  IF (SELECT count(*) FROM public.question_vaults
      WHERE vault_type = 'weekly' AND is_active) <> 3567 THEN
    RAISE EXCEPTION 'FINAL_161: aktif haftalik kasa 3567 degil.';
  END IF;
  SELECT count(*) INTO v FROM public.question_vaults
   WHERE vault_type = 'weekly' AND week_number = 42;
  IF v <> 87 OR EXISTS (SELECT 1 FROM public.question_vaults
        WHERE vault_type = 'weekly' AND week_number = 42
          AND (is_active OR vault_kind <> 'genel_tekrar'
               OR metadata->>'requires_admin_activation' <> 'true')) THEN
    RAISE EXCEPTION 'FINAL_161: K42 87 pasif genel_tekrar matrisi bozuk.';
  END IF;

  -- F3) takvim türetimi: tatil haftaları tatil_tekrari, kısmi haftalar karma
  IF EXISTS (SELECT 1 FROM public.question_vaults q
              JOIN public.academic_weeks w
                ON w.academic_year = '2026-2027' AND w.week = q.week_number
             WHERE q.vault_type = 'weekly'
               AND q.vault_kind <> CASE w.week_kind
                     WHEN 'teaching'         THEN 'yeni_konu'
                     WHEN 'holiday_review'   THEN 'tatil_tekrari'
                     WHEN 'partial_teaching' THEN 'karma'
                     WHEN 'year_end_review'  THEN 'genel_tekrar'
                   END) THEN
    RAISE EXCEPTION 'FINAL_161: vault_kind takvim metadata-sindan sapmis.';
  END IF;

  -- F4) boş + kapalı başlangıç + K42 takvim kapısı duruyor
  IF (SELECT count(*) FROM public.weekly_vault_placements) <> 0 THEN
    RAISE EXCEPTION 'FINAL_161: seed sonrasi weekly placement 0 degil.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.question_vault_memberships m
              JOIN public.question_vaults q ON q.id = m.vault_id
             WHERE q.vault_type = 'weekly') THEN
    RAISE EXCEPTION 'FINAL_161: haftalik kasada membership uretildi.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.question_vaults
              WHERE vault_type = 'weekly'
                AND (allow_practice OR allow_competition
                     OR allow_one_v_one OR allow_exam)) THEN
    RAISE EXCEPTION 'FINAL_161: haftalik kasada ogrenci kapisi acik dogdu.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.academic_weeks
      WHERE academic_year = '2026-2027' AND week = 42
        AND requires_admin_activation AND activated_at IS NULL) THEN
    RAISE EXCEPTION 'FINAL_161: K42 takvim kapisi seed sirasinda degisti.';
  END IF;

  -- F5) snapşot karşıtlıkları: hiçbir eski veri 161'den etkilenmedi
  SELECT s.n_nonweekly, s.fp_nonweekly, s.n_legacy, s.n_map, s.n_map_approved,
         s.n_placement, s.n_engine_usable
    INTO v_nonweekly, fp, v_legacy, v_map, v_mapapp, v_plc, v_snap_usable
    FROM pg_temp.ak161_snap s;

  IF (SELECT count(*) FROM public.question_vaults
      WHERE vault_type <> 'weekly') <> v_nonweekly THEN
    RAISE EXCEPTION 'FINAL_161: eski (haftalik-olmayan) kasa sayisi degisti.';
  END IF;
  IF coalesce((SELECT md5(string_agg(vault_code || '|' || is_active::text
              || '|' || coalesce(difficulty_level, '-') || '|'
              || coalesce(week_number::text, '-'), ',' ORDER BY vault_code))
        FROM public.question_vaults WHERE vault_type <> 'weekly'), 'YOK') <> fp THEN
    RAISE EXCEPTION 'FINAL_161: eski kasa parmak izi degisti (koddan/aktiflikten oynandi).';
  END IF;
  IF (SELECT count(*) FROM public.question_vault_topics
      WHERE legacy_topic_code IS NOT NULL) <> v_legacy THEN
    RAISE EXCEPTION 'FINAL_161: LEGACY 13 baglantisi degisti.';
  END IF;
  IF (SELECT count(*) FROM public.curriculum_subtopic_week_map
      WHERE academic_year = '2026-2027') <> v_map THEN
    RAISE EXCEPTION 'FINAL_161: 160 esleme satir sayisi seed sirasinda degisti.';
  END IF;
  IF (SELECT count(*) FROM public.curriculum_subtopic_week_map
      WHERE approved_at IS NOT NULL) <> v_mapapp THEN
    RAISE EXCEPTION 'FINAL_161: seed esleme onayi üretti (otomatik onay yasak).';
  END IF;
  IF (SELECT count(*) FROM public.weekly_vault_placements) <> v_plc THEN
    RAISE EXCEPTION 'FINAL_161: seed yerlesim üretti.';
  END IF;

  -- F6) motor kullanilabilirlik sayimi birebir ayni olmali (161 hicbir sey acmadi)
  v_usable := 0;
  FOR p IN SELECT DISTINCT m.grade_level, m.subject_id
           FROM public.curriculum_subtopic_week_map m
          WHERE m.academic_year = '2026-2027' LOOP
    SELECT count(*) INTO n
      FROM public.curriculum_subtopic_week_state(
             p.grade_level::smallint, p.subject_id, current_date) x
     WHERE x.is_usable;
    v_usable := v_usable + n;
  END LOOP;
  IF v_usable <> v_snap_usable THEN
    RAISE EXCEPTION 'FINAL_161: motor usable sayisi degisti (once=%, sonra=%).',
      v_snap_usable, v_usable;
  END IF;

  -- F7) 151/158 imzalari + yeni tetik + tetik isi ACL'i
  IF (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public'
      AND indexname IN ('uq_question_vaults_weekly_scope',
                        'uq_question_active_single_vault')) <> 2 THEN
    RAISE EXCEPTION 'FINAL_161: 151/158 benzersizlik imzalari kayboldu.';
  END IF;
  IF (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
      WHERE t.tgname IN ('trg_vault_memberships_pack_limit','trg_question_vaults_pack_limit',
                         'trg_weekly_placements_limit','trg_question_vaults_weekly_type',
                         'trg_question_vaults_weekly_pair')
        AND NOT t.tgisinternal AND t.tgenabled = 'O') <> 5 THEN
    RAISE EXCEPTION 'FINAL_161: 158/161 tetik matrisi (4+1 aktif) saglam degil.';
  END IF;
  IF has_function_privilege('anon', 'public.validate_weekly_vault_pair()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.validate_weekly_vault_pair()', 'EXECUTE') THEN
    RAISE EXCEPTION 'FINAL_161: kimlik tetik isi ogrenci rollerine acik.';
  END IF;

  -- F8) SEC-1 gerisarmasi hâlâ kapalı
  IF has_function_privilege('authenticated',
      'public.get_internal_correct_answer(uuid)'::regprocedure, 'EXECUTE')
     OR has_function_privilege('anon',
      'public.get_internal_correct_answer(uuid)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'FINAL_161: SEC-1 seed sirasinda acildi.';
  END IF;

  RAISE NOTICE 'KASA161 OK: 3654 kasa (3567 aktif + 87 K42 pasif) bos ve kapali; takvim turetimi dogru; eski kasa/LEGACY/160/motor snapleri ayni; 151/158/SEC-1 duruyor';
END
$final$;

COMMIT;
