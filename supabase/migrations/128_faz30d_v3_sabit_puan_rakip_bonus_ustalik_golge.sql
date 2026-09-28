-- ============================================================
-- 128_faz30d_v3_sabit_puan_rakip_bonus_ustalik_golge.sql
-- Altin Kalemler - FAZ 30D-1
-- V3 SABIT PUAN MATRISI + GORELI UZMAN SURE BANDI
--   + RAKIP BONUSU (golge) + DERS USTALIGI (golge)
--   + GLOBAL PUAN (golge)
--
-- ONAYLI KURALLAR (30D-0 kanit + urun onayi):
--
--   1) SABIT MATRIS (9,10,11,12 siniflarin TAMAMINDA ayni):
--        mukemmel dogru  130 / 195 / 260
--        iyi dogru       120 / 180 / 240
--        orta dogru      110 / 165 / 220
--        kotu (+ kotu uzatma) dogru  100 / 150 / 200
--        yanlis          -20 / -30 / -40
--        timeout         -20 / -30 / -40
--        pas              0 /   0 /   0
--      (kolay / orta / zor)
--
--   2) UZMAN SURE BANDI (goreli T):
--        T = questions.expert_solution_time_seconds
--        perfect            elapsed <= T
--        good               T < elapsed <= 1.20T
--        average            1.20T < elapsed <= 1.40T
--        poor               1.40T < elapsed <= 1.60T
--        poor_grace         1.60T < elapsed <= 1.75T
--        proposed timeout   elapsed > 1.75T
--      proposed_timeout YALNIZ golge kaydidir; mevcut deadline /
--      timeout sonucu DEGISTIRILMEZ.
--
--   3) RAKIP BONUSU (yalniz finalizasyonda, soru bazinda):
--        kendi sonucu correct DEGILSE                       0
--        rakip pass                                          0
--        rakip wrong veya timeout                           +20
--        ikisi de correct: rank farki
--            poor=0 average=1 good=2 perfect=3
--            gap = kendi rank - rakip rank
--            gap 1 / 2 / 3      -> +5 / +10 / +15
--            gap <= 0            -> 0
--      sinif/zorluktan BAGIMSIZ; yalniz yarisma puani ve
--      global puani etkiler. Lig rating / XP / leaderboard
--      KAYNAKLARINA DOKUNMAZ.
--
--   4) DERS USTALIGI (golge, ders basina bagimsiz):
--        perfect dogru    +150
--        diger dogru        0
--        yanlis / timeout  easy -20 / medium -30 / hard -40
--        pas               0
--        toplam GREATEST(0, onceki + delta)
--        seviye esikleri: easy 0-14999 / medium 15000-37499
--                         hard 37500+
--        ACILMIS en yuksek seviye ASLA dusmez.
--
--   5) GLOBAL PUAN (golge): tum derslerdeki V3 net soru
--      puani + rakip bonuslarinin toplami. Lig tablosu,
--      rating, XP ve leaderboard DEGISTIRILMEZ.
--
--   6) T (expert_solution_time_seconds) YOKSA:
--        V3 bantli puan / rakip bonusu / ders ustaligi
--        URETILMEZ. V2 uyumlu temel puan korunur
--        (NULL-band correct fallback = kotu degeri).
--        reason_code + provenance yazilir. T UYDURULMAZ.
--
-- KAPSAM KORUMASI (ZORUNLU):
--   - V1 (094) ve V2 (127) migration dosyalarina DOKUNULMAZ.
--   - V1/V2 puan satirlari, gecmis yarisma snapshotlari,
--     XP, lig rating, leaderboard, UI, routing DEGISMEZ.
--   - Gecmis yarismalara backfill/recompute YAPILMAZ.
--   - Bu migration YALNIZ yeni V3 kural setiyle acilan
--     yarismalari etkiler; V1/V2 yarismalarinda butun
--     trigger'ler erken cikis yapar.
--
-- TEK AKTIF KURAL SETI:
--   128 sonrasi aktif varsayilan competition_scoring_v3_fixed
--   olur; V2 is_active=false yapilir ancak V2 SATIRLARI AKTIF
--   KALIR (gecmis V2 yarismalari kendi rule_set_id ile
--   cozulmeye devam eder).
--
-- DOSYA KODLAMA: tamamen ASCII.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. SEMA EKLEMELERI
-- ============================================================

-- 1.1) Uzman cozum suresi (saniye). NULL = bilinmiyor.
--      Tahmin/uretim akisi DEGISTIRILMEZ; backfill YOK.
DO $blk$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'questions'
       AND column_name = 'expert_solution_time_seconds'
  ) THEN
    ALTER TABLE public.questions
      ADD COLUMN expert_solution_time_seconds integer;
  END IF;
END;
$blk$;

DO $blk$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'questions_expert_solution_time_seconds_check'
       AND conrelid = 'public.questions'::regclass
  ) THEN
    ALTER TABLE public.questions
      ADD CONSTRAINT questions_expert_solution_time_seconds_check
      CHECK (expert_solution_time_seconds IS NULL
             OR expert_solution_time_seconds > 0);
  END IF;
END;
$blk$;

-- 1.2) Oyuncu bazli rakip bonusu toplami (yalniz golge/yarisma
--      puani). V1/V2 yarismalarinda 0 kalir.
DO $blk$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'competition_players'
       AND column_name = 'opponent_bonus_points'
  ) THEN
    ALTER TABLE public.competition_players
      ADD COLUMN opponent_bonus_points integer NOT NULL DEFAULT 0;
  END IF;
END;
$blk$;

DO $blk$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'competition_players_opponent_bonus_points_check'
       AND conrelid = 'public.competition_players'::regclass
  ) THEN
    ALTER TABLE public.competition_players
      ADD CONSTRAINT competition_players_opponent_bonus_points_check
      CHECK (opponent_bonus_points >= 0);
  END IF;
END;
$blk$;


-- ============================================================
-- 2. KATALOG / GOLGE TABLOLARI
--
-- Tum yeni tablolar RLS acik ve HICBIR role GRANT
-- VERILMEZ (yalnizca SECURITY DEFINER tetikleyiciler erisir).
-- Faz 10B guvenlik invaryanti: authenticated/anon'a
-- TRUNCATE/REFERENCES/TRIGGER verilmez.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.faz30d_v3_bands (
  band_code           text PRIMARY KEY,
  sort_order          integer NOT NULL,
  label_key           text NOT NULL,
  min_ratio           numeric(6,3),
  max_ratio           numeric(6,3),
  is_grace_window     boolean NOT NULL DEFAULT false,
  is_proposed_timeout boolean NOT NULL DEFAULT false,
  is_scored_band      boolean NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.faz30d_v3_mastery_rules (
  difficulty   text PRIMARY KEY,
  perfect_gain integer NOT NULL,
  correct_gain integer NOT NULL,
  fault_penalty integer NOT NULL,
  -- isaret sozlesmesi: kazanc pozitif, ceza negatif bir delta olarak saklanir
  CONSTRAINT faz30d_v3_mastery_rules_sign_chk
    CHECK (perfect_gain >= 0 AND correct_gain >= 0 AND fault_penalty <= 0)
);

CREATE TABLE IF NOT EXISTS public.faz30d_v3_level_thresholds (
  level_no   integer PRIMARY KEY,
  level_name text NOT NULL,
  min_points integer NOT NULL
);

CREATE TABLE IF NOT EXISTS public.faz30d_v3_opponent_bonus_rules (
  rule_key   text PRIMARY KEY,
  rule_value integer NOT NULL,
  description text NOT NULL
);

-- 2.1) Soru bazli golge kaydi (V3 bant / sure / provenance).
CREATE TABLE IF NOT EXISTS public.faz30d_answer_shadow (
  competition_answer_id uuid PRIMARY KEY,
  competition_id        uuid NOT NULL,
  competition_question_id uuid NOT NULL,
  user_id               uuid NOT NULL,
  subject_id            uuid,
  grade_level           smallint,
  difficulty            text,
  answer_result         text NOT NULL,
  elapsed_ms            integer NOT NULL,
  expert_time_seconds   integer,
  band_code             text,
  is_grace_window       boolean NOT NULL DEFAULT false,
  elapsed_ratio         numeric(8,4),
  base_points           integer NOT NULL,
  reason_code           text NOT NULL,
  provenance            jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at            timestamptz NOT NULL DEFAULT now()
);

-- 2.2) Rakip bonusu ledger'i (append-only, soru bazinda).
CREATE TABLE IF NOT EXISTS public.faz30d_opponent_bonus_ledger (
  id                       bigserial PRIMARY KEY,
  competition_id           uuid NOT NULL,
  user_id                  uuid NOT NULL,
  competition_question_id  uuid NOT NULL,
  competition_answer_id    uuid NOT NULL,
  opponent_user_id         uuid,
  opponent_answer_result   text,
  own_answer_result        text NOT NULL,
  own_band_code            text,
  opponent_band_code       text,
  band_rank_gap            smallint,
  bonus_points             integer NOT NULL DEFAULT 0,
  reason_code              text NOT NULL,
  provenance               jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at               timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT faz30d_bonus_ledger_answer_uniq
    UNIQUE (user_id, competition_answer_id)
);

-- 2.3) Ders ustaligi olaylari (append-only) + anlik durum.
CREATE TABLE IF NOT EXISTS public.faz30d_subject_mastery_events (
  id                    bigserial PRIMARY KEY,
  event_key             text NOT NULL UNIQUE,
  user_id               uuid NOT NULL,
  subject_id            uuid NOT NULL,
  competition_id        uuid NOT NULL,
  competition_answer_id uuid NOT NULL,
  difficulty            text NOT NULL,
  answer_result         text NOT NULL,
  band_code             text,
  delta_points          integer NOT NULL,
  reason_code           text NOT NULL,
  total_points_after    integer NOT NULL,
  level_after           integer NOT NULL,
  created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.faz30d_subject_mastery_current (
  user_id         uuid NOT NULL,
  subject_id      uuid NOT NULL,
  total_points    integer NOT NULL DEFAULT 0,
  current_level   integer NOT NULL DEFAULT 1,
  highest_level   integer NOT NULL DEFAULT 1,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, subject_id)
);

-- 2.4) Global puan (golge) olaylari + toplamlar.
CREATE TABLE IF NOT EXISTS public.faz30d_global_points_events (
  id                    bigserial PRIMARY KEY,
  event_key             text NOT NULL UNIQUE,
  user_id               uuid NOT NULL,
  subject_id            uuid,
  competition_id        uuid NOT NULL,
  event_kind            text NOT NULL
                          CHECK (event_kind IN ('base','opponent_bonus')),
  competition_answer_id uuid,
  points                integer NOT NULL,
  reason_code           text NOT NULL,
  provenance            jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.faz30d_global_points_totals (
  user_id      uuid PRIMARY KEY,
  total_points bigint NOT NULL DEFAULT 0,
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- 2.5) Dizinler
CREATE INDEX IF NOT EXISTS idx_faz30d_shadow_competition
  ON public.faz30d_answer_shadow (competition_id, user_id);

CREATE INDEX IF NOT EXISTS idx_faz30d_bonus_ledger_competition
  ON public.faz30d_opponent_bonus_ledger (competition_id, user_id);

CREATE INDEX IF NOT EXISTS idx_faz30d_mastery_events_user
  ON public.faz30d_subject_mastery_events (user_id, subject_id);

CREATE INDEX IF NOT EXISTS idx_faz30d_global_events_user
  ON public.faz30d_global_points_events (user_id, created_at);

-- 2.6) RLS: policy YOK, rol GRANT'I YOK. Yalnizca tetikleyiciler.
ALTER TABLE public.faz30d_v3_bands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faz30d_v3_mastery_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faz30d_v3_level_thresholds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faz30d_v3_opponent_bonus_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faz30d_answer_shadow ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faz30d_opponent_bonus_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faz30d_subject_mastery_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faz30d_subject_mastery_current ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faz30d_global_points_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faz30d_global_points_totals ENABLE ROW LEVEL SECURITY;

-- 2.7) Acikca yetki geri alimi.
-- Supabase imajindaki varsayilan yetkiler yeni tablolara SELECT
-- verir. RLS + policy yok oldugu icin veri SIZMAZ, ama
-- "bu tablolara rol erisimi YOK" sozlesmesi icin grant'i
-- deterministik olarak kaldiriyoruz. Tablo sahibi (postgres)
-- haklarini korur; tetikleyiciler sahip rolle calistigi icin
-- yazma yolu etkilenmez.
REVOKE ALL ON TABLE
  public.faz30d_v3_bands,
  public.faz30d_v3_mastery_rules,
  public.faz30d_v3_level_thresholds,
  public.faz30d_v3_opponent_bonus_rules,
  public.faz30d_answer_shadow,
  public.faz30d_opponent_bonus_ledger,
  public.faz30d_subject_mastery_events,
  public.faz30d_subject_mastery_current,
  public.faz30d_global_points_events,
  public.faz30d_global_points_totals
  FROM PUBLIC, anon, authenticated, service_role;

-- 2.8) Dizi yetkileri. YALNIZCA 128'in olusturdugu diziler;
-- semadaki diger dizilere dokunulmaz. Varlik kontrolu ile
-- idempotent.
DO $$
DECLARE
  v_seq text;
BEGIN
  FOREACH v_seq IN ARRAY ARRAY[
    'faz30d_global_points_events_id_seq'
  ] LOOP
    IF to_regclass('public.' || v_seq) IS NOT NULL THEN
      EXECUTE format(
        'REVOKE ALL ON SEQUENCE public.%I FROM PUBLIC, anon, authenticated, service_role',
        v_seq);
    END IF;
  END LOOP;
END;
$$;


-- ============================================================
-- 3. BELIRLEZLIK KAPISI (V3 bandli satirlarda tek kayit)
--
-- public.resolve_competition_points bandli aramada
-- "ORDER BY created_at DESC LIMIT 1" kullanir. V3 icin
-- (rule_set, grade, difficulty, result, band) basina TEK
-- aktif satir garantisi olmazsa bu yol belirsizdir.
--
-- COALESCE(band_code,'') ile NULL bant satirlari da kapsama
-- alinir; boylece hem bandli arama hem de NULL-band
-- fallback tekillestirilir.
--
-- V1 (094) ve V2 (127) satirlarinin tamami band_code IS NULL
-- ve (rule_set, grade, difficulty, result) basina TEK
-- satirdir (30C QA A-04: max_group = 1); bu indeks mevcut
-- veriyi ETKILEMEZ.
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_scoring_point_rules_active_key
  ON public.scoring_point_rules
     (rule_set_id, grade_level, difficulty, answer_result,
      COALESCE(band_code, ''))
  WHERE is_active = true;


-- ============================================================
-- 4. SAF GORELI-SURE BAND COZUMLEYICI
--
-- IMMUTABLE, tablo erisimi YOK: girdi (elapsed_ms, T) ->
-- cikti (band_code, reason_code, ratio) birebir ve
-- tekrarlanabilir. T yoksa band uretilmez.
--
-- Butunlu esikler numeric ile hesaplanir; float yuvarlama
-- belirsizligi yoktur.
-- ============================================================

CREATE OR REPLACE FUNCTION private.faz30d_v3_resolve_band(
  p_time_ms              integer,
  p_expert_time_seconds  integer
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $fn$
DECLARE
  v_t_ms   numeric;
  v_ratio  numeric;
BEGIN
  -- T yoksa V3 band uretilmez (fail-closed).
  IF p_expert_time_seconds IS NULL OR p_expert_time_seconds <= 0 THEN
    RETURN jsonb_build_object(
      'band_code',             NULL,
      'reason_code',           'v3_missing_expert_time',
      'is_grace_window',       false,
      'is_proposed_timeout',   false,
      'ratio',                 NULL,
      'expert_time_seconds',   p_expert_time_seconds
    );
  END IF;

  v_t_ms  := p_expert_time_seconds::numeric * 1000;
  v_ratio := round(p_time_ms::numeric / v_t_ms, 4);

  IF p_time_ms <= v_t_ms THEN
    RETURN jsonb_build_object(
      'band_code', 'perfect', 'reason_code', 'v3_band_perfect',
      'is_grace_window', false, 'is_proposed_timeout', false,
      'ratio', v_ratio, 'expert_time_seconds', p_expert_time_seconds);

  ELSIF p_time_ms <= v_t_ms * 1.20 THEN
    RETURN jsonb_build_object(
      'band_code', 'good', 'reason_code', 'v3_band_good',
      'is_grace_window', false, 'is_proposed_timeout', false,
      'ratio', v_ratio, 'expert_time_seconds', p_expert_time_seconds);

  ELSIF p_time_ms <= v_t_ms * 1.40 THEN
    RETURN jsonb_build_object(
      'band_code', 'average', 'reason_code', 'v3_band_average',
      'is_grace_window', false, 'is_proposed_timeout', false,
      'ratio', v_ratio, 'expert_time_seconds', p_expert_time_seconds);

  ELSIF p_time_ms <= v_t_ms * 1.60 THEN
    RETURN jsonb_build_object(
      'band_code', 'poor', 'reason_code', 'v3_band_poor',
      'is_grace_window', false, 'is_proposed_timeout', false,
      'ratio', v_ratio, 'expert_time_seconds', p_expert_time_seconds);

  ELSIF p_time_ms <= v_t_ms * 1.75 THEN
    RETURN jsonb_build_object(
      'band_code', 'poor_grace', 'reason_code', 'v3_band_poor_grace',
      'is_grace_window', true, 'is_proposed_timeout', false,
      'ratio', v_ratio, 'expert_time_seconds', p_expert_time_seconds);

  ELSE
    RETURN jsonb_build_object(
      'band_code', 'proposed_timeout', 'reason_code',
      'v3_band_proposed_timeout',
      'is_grace_window', false, 'is_proposed_timeout', true,
      'ratio', v_ratio, 'expert_time_seconds', p_expert_time_seconds);
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION private.faz30d_v3_resolve_band(integer, integer)
  FROM PUBLIC;


-- ============================================================
-- 5. V3 KURAL SETI + SEED
-- ============================================================

INSERT INTO public.scoring_rule_sets
  (rule_set_code, name, description, version, is_active)
VALUES
  ('competition_scoring_v3_fixed',
   'Yarisma Puanlama Sozlesmesi V3 (sabit matris + rakip bonusu)',
   'V3: sabit 9-12 matrisi (130/195/260 ... 100/150/200, yanlis/timeout -20/-30/-40, pas 0), goreli uzman sure bandlari (T, T*1.20, T*1.40, T*1.60, T*1.75), soru bazli rakip bonusu (+20 rakip hata, rank farki +5/+10/+15) ve ders ustaligi/global puan golge kayitlari. Lig rating, XP ve leaderboard degismez.',
   '3',
   TRUE)
ON CONFLICT (rule_set_code) DO UPDATE
SET name        = EXCLUDED.name,
    description = EXCLUDED.description,
    version     = EXCLUDED.version,
    is_active   = TRUE;

-- 5.1) BANT KATALOGU (denetim/UI etiketi; esikler saf
--      fonksiyonda sabittir).
INSERT INTO public.faz30d_v3_bands
  (band_code, sort_order, label_key, min_ratio, max_ratio,
   is_grace_window, is_proposed_timeout, is_scored_band)
VALUES
  ('perfect',          1, 'band_perfect',        0.000, 1.000, false, false, true),
  ('good',             2, 'band_good',           1.001, 1.200, false, false, true),
  ('average',          3, 'band_average',        1.201, 1.400, false, false, true),
  ('poor',             4, 'band_poor',           1.401, 1.600, false, false, false),
  ('poor_grace',       5, 'band_poor',           1.601, 1.750, true,  false, false),
  ('proposed_timeout', 6, 'band_proposed_timeout', 1.751, NULL, false, true,  false)
ON CONFLICT (band_code) DO UPDATE
SET sort_order          = EXCLUDED.sort_order,
    label_key           = EXCLUDED.label_key,
    min_ratio           = EXCLUDED.min_ratio,
    max_ratio           = EXCLUDED.max_ratio,
    is_grace_window     = EXCLUDED.is_grace_window,
    is_proposed_timeout = EXCLUDED.is_proposed_timeout,
    is_scored_band      = EXCLUDED.is_scored_band;

-- 5.2) USTALIK KURALLARI
INSERT INTO public.faz30d_v3_mastery_rules
  (difficulty, perfect_gain, correct_gain, fault_penalty)
VALUES
  ('easy',   150, 0,  -20),
  ('medium', 150, 0,  -30),
  ('hard',   150, 0,  -40)
ON CONFLICT (difficulty) DO UPDATE
SET perfect_gain  = EXCLUDED.perfect_gain,
    correct_gain  = EXCLUDED.correct_gain,
    fault_penalty = EXCLUDED.fault_penalty;

-- 5.3) SEVIYE ESIKLERI (kumulatif)
INSERT INTO public.faz30d_v3_level_thresholds
  (level_no, level_name, min_points)
VALUES
  (1, 'baslangic',       0),
  (2, 'gelismekte',  15000),
  (3, 'uzman',       37500)
ON CONFLICT (level_no) DO UPDATE
SET level_name = EXCLUDED.level_name,
    min_points = EXCLUDED.min_points;

-- 5.4) RAKIP BONUSU KURALLARI (append-only seed)
INSERT INTO public.faz30d_v3_opponent_bonus_rules
  (rule_key, rule_value, description)
VALUES
  ('opponent_wrong_or_timeout', 20,
   'Rakip wrong veya timeout yaptiysa sabit bonus.'),
  ('band_gap_1',   5,  'Iki dogru, rank farki 1.'),
  ('band_gap_2',  10,  'Iki dogru, rank farki 2.'),
  ('band_gap_3',  15,  'Iki dogru, rank farki 3.'),
  ('same_or_worse_band', 0, 'Ayni bant veya daha kotu bant: bonus yok.')
ON CONFLICT (rule_key) DO UPDATE
SET rule_value  = EXCLUDED.rule_value,
    description = EXCLUDED.description;

-- 5.5) V3 PUNAN SATIRLARI
--   12 sinif x 3 zorluk x 7 satir = 252 satir
--     correct + perfect/good/average  (bandli, puanli)
--     correct + NULL band            (kotu / kotu uzatma / T yok)
--     wrong  + NULL band
--     timeout + NULL band
--     pass   + NULL band
--   NOT EXISTS guard: tekrar calistirmada duplicate olusmaz.
INSERT INTO public.scoring_point_rules
  (rule_set_id, grade_level, difficulty, answer_result, band_code, points, is_active)
SELECT
  srs.id,
  g.grade_level,
  d.difficulty,
  r.answer_result,
  r.band_code,
  CASE
    WHEN r.answer_result = 'pass' THEN 0
    WHEN r.answer_result IN ('wrong','timeout') THEN
      CASE d.difficulty
        WHEN 'easy'   THEN -20
        WHEN 'medium' THEN -30
        ELSE -40
      END
    WHEN r.band_code = 'perfect' THEN
      CASE d.difficulty
        WHEN 'easy'   THEN 130
        WHEN 'medium' THEN 195
        ELSE 260
      END
    WHEN r.band_code = 'good' THEN
      CASE d.difficulty
        WHEN 'easy'   THEN 120
        WHEN 'medium' THEN 180
        ELSE 240
      END
    WHEN r.band_code = 'average' THEN
      CASE d.difficulty
        WHEN 'easy'   THEN 110
        WHEN 'medium' THEN 165
        ELSE 220
      END
    ELSE
      CASE d.difficulty
        WHEN 'easy'   THEN 100
        WHEN 'medium' THEN 150
        ELSE 200
      END
  END,
  TRUE
FROM public.scoring_rule_sets srs
CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) AS g(grade_level)
CROSS JOIN (VALUES ('easy'),('medium'),('hard'))                        AS d(difficulty)
CROSS JOIN (
  VALUES
    ('correct','perfect'),
    ('correct','good'),
    ('correct','average'),
    ('correct',NULL::text),
    ('wrong',  NULL::text),
    ('timeout',NULL::text),
    ('pass',   NULL::text)
) AS r(answer_result, band_code)
WHERE srs.rule_set_code = 'competition_scoring_v3_fixed'
  AND NOT EXISTS (
    SELECT 1
      FROM public.scoring_point_rules existing
     WHERE existing.rule_set_id   = srs.id
       AND existing.grade_level   = g.grade_level
       AND existing.difficulty    = d.difficulty
       AND existing.answer_result = r.answer_result
       AND existing.band_code IS NOT DISTINCT FROM r.band_code
       AND existing.is_active     = TRUE
  );

-- 5.6) TEK AKTIF KURAL SETI
UPDATE public.scoring_rule_sets
   SET is_active = FALSE
 WHERE rule_set_code = 'competition_scoring_v2_negative_wrong_timeout'
   AND is_active = TRUE;

UPDATE public.scoring_rule_sets
   SET is_active = TRUE
 WHERE rule_set_code = 'competition_scoring_v3_fixed';

-- V1 ve V2 puan satirlari AKTIF kalir (gecmis cozumleme).
-- Yalniz kural seti bayragi pasife cekilir.


-- ============================================================
-- 6. BEFORE INSERT: V3 BAND + SABIT PUAN
--
-- Yalniz V3 kural setine sahip yarismalarda calisir.
-- V1/V2 yarismalarinda NEW DEGISTIRILMEDEN doner.
-- ============================================================

CREATE OR REPLACE FUNCTION private.faz30d_v3_score_answer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $fn$
DECLARE
  v_rule_code    text;
  v_grade        smallint;
  v_difficulty   text;
  v_expert_t     integer;
  v_band         jsonb;
  v_band_code    text;
BEGIN
  SELECT srs.rule_set_code,
         c.grade_level,
         cq.difficulty,
         q.expert_solution_time_seconds
    INTO v_rule_code, v_grade, v_difficulty, v_expert_t
    FROM public.competitions c
    JOIN public.scoring_rule_sets srs
      ON srs.id = c.scoring_rule_set_id
    JOIN public.competition_questions cq
      ON cq.competition_id = c.id
    JOIN public.questions q
      ON q.id = cq.question_id
   WHERE cq.id = NEW.competition_question_id;

  -- V1 / V2 koruma: hicbir sey degismez.
  IF v_rule_code IS DISTINCT FROM 'competition_scoring_v3_fixed' THEN
    RETURN NEW;
  END IF;

  v_band := private.faz30d_v3_resolve_band(
              COALESCE(NEW.time_ms, 0), v_expert_t);

  v_band_code := v_band ->> 'band_code';

  -- T yoksa band uretilmez; NULL-band correct fallback
  -- (kotu degeri) V2 uyumlu temel puan olarak korunur.
  NEW.time_band_code := v_band_code;
  NEW.points_awarded := public.resolve_competition_points(
    (SELECT c.scoring_rule_set_id
       FROM public.competitions c
      WHERE c.id = NEW.competition_id),
    v_grade,
    v_difficulty,
    NEW.answer_result,
    v_band_code);

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION private.faz30d_v3_score_answer() FROM PUBLIC;

DROP TRIGGER IF EXISTS trigger_faz30d_v3_score_answer
  ON public.competition_answers;

CREATE TRIGGER trigger_faz30d_v3_score_answer
BEFORE INSERT ON public.competition_answers
FOR EACH ROW
EXECUTE FUNCTION private.faz30d_v3_score_answer();


-- ============================================================
-- 7. AFTER INSERT: GOLGE KAYIT + GLOBAL TEMEL PUAN + USTALIK
--
-- Tum yazmalar idempotenttir:
--   answer_shadow      -> PK competition_answer_id
--   global_points      -> UNIQUE event_key
--   mastery_events     -> UNIQUE event_key
-- Tekrar calistirma yeni satir uretmez.
-- ============================================================

CREATE OR REPLACE FUNCTION private.faz30d_v3_record_answer_events()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $fn$
DECLARE
  v_rule_code  text;
  v_subject    uuid;
  v_grade      smallint;
  v_difficulty text;
  v_expert_t   integer;
  v_band       jsonb;
  v_reason     text;
  v_delta      integer;
  v_prev       integer;
  v_total      integer;
  v_level      integer;
  v_gain       integer;
  v_penalty    integer;
  v_corr_gain  integer;
BEGIN
  SELECT srs.rule_set_code, c.subject_id, c.grade_level,
         cq.difficulty, q.expert_solution_time_seconds
    INTO v_rule_code, v_subject, v_grade, v_difficulty, v_expert_t
    FROM public.competitions c
    JOIN public.scoring_rule_sets srs
      ON srs.id = c.scoring_rule_set_id
    JOIN public.competition_questions cq
      ON cq.competition_id = c.id
    JOIN public.questions q
      ON q.id = cq.question_id
   WHERE cq.id = NEW.competition_question_id;

  IF v_rule_code IS DISTINCT FROM 'competition_scoring_v3_fixed' THEN
    RETURN NEW;
  END IF;

  v_band   := private.faz30d_v3_resolve_band(
                COALESCE(NEW.time_ms, 0), v_expert_t);
  v_reason := v_band ->> 'reason_code';

  -- 7.1) GOLGE KAYIT
  INSERT INTO public.faz30d_answer_shadow
    (competition_answer_id, competition_id, competition_question_id,
     user_id, subject_id, grade_level, difficulty, answer_result,
     elapsed_ms, expert_time_seconds, band_code, is_grace_window,
     elapsed_ratio, base_points, reason_code, provenance)
  VALUES
    (NEW.id, NEW.competition_id, NEW.competition_question_id,
     NEW.user_id, v_subject, v_grade, v_difficulty, NEW.answer_result,
     COALESCE(NEW.time_ms, 0), v_expert_t, v_band ->> 'band_code',
     COALESCE((v_band ->> 'is_grace_window')::boolean, false),
     (v_band ->> 'ratio')::numeric, NEW.points_awarded, v_reason,
     jsonb_build_object(
       'rule_set',        'competition_scoring_v3_fixed',
       'resolver',        'private.faz30d_v3_resolve_band',
       'time_ms',         COALESCE(NEW.time_ms, 0),
       'expert_t',        v_expert_t,
       'band_from_1.75T', COALESCE((v_band ->> 'is_proposed_timeout')::boolean, false),
       'deadline_changed', false))
  ON CONFLICT (competition_answer_id) DO NOTHING;

  -- 7.2) GLOBAL PUAN (golge) - temel katki
  INSERT INTO public.faz30d_global_points_events
    (event_key, user_id, subject_id, competition_id, event_kind,
     competition_answer_id, points, reason_code, provenance)
  VALUES
    ('answer:' || NEW.id::text, NEW.user_id, v_subject, NEW.competition_id,
     'base', NEW.id, NEW.points_awarded, v_reason,
     jsonb_build_object('band_code', v_band ->> 'band_code', 'difficulty', v_difficulty))
  ON CONFLICT (event_key) DO NOTHING;

  INSERT INTO public.faz30d_global_points_totals (user_id, total_points)
  VALUES (NEW.user_id, NEW.points_awarded)
  ON CONFLICT (user_id) DO UPDATE
     SET total_points = public.faz30d_global_points_totals.total_points
                       + EXCLUDED.total_points,
         updated_at = now();

  -- 7.3) DERS USTALIGI
  --   T yoksa V3 ustaligi URETILMEZ (kural 6).
  IF v_reason = 'v3_missing_expert_time' OR v_subject IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT mr.perfect_gain, mr.correct_gain, mr.fault_penalty
    INTO v_gain, v_corr_gain, v_penalty
    FROM public.faz30d_v3_mastery_rules mr
   WHERE mr.difficulty = v_difficulty;

  v_gain    := COALESCE(v_gain, 150);
  v_corr_gain := COALESCE(v_corr_gain, 0);
  v_penalty := COALESCE(v_penalty, 0);

  v_delta := 0;
  IF NEW.answer_result = 'correct'
     AND (v_band ->> 'band_code') = 'perfect' THEN
    v_delta := v_gain;
  ELSIF NEW.answer_result = 'correct' THEN
    v_delta := v_corr_gain;      -- diger dogru: 0
  ELSIF NEW.answer_result IN ('wrong','timeout') THEN
    v_delta := v_penalty;        -- fault_penalty zaten negatif bir delta
  ELSE
    v_delta := 0;                -- pas: 0
  END IF;
  -- onceki anlik durum (yoksa 0)
  SELECT COALESCE(cur.total_points, 0) INTO v_prev
    FROM public.faz30d_subject_mastery_current cur
   WHERE cur.user_id = NEW.user_id
     AND cur.subject_id = v_subject;

  v_total := GREATEST(0, COALESCE(v_prev, 0) + v_delta);

  SELECT COALESCE(MAX(lt.level_no), 1) INTO v_level
    FROM public.faz30d_v3_level_thresholds lt
   WHERE lt.min_points <= v_total;

  INSERT INTO public.faz30d_subject_mastery_events
    (event_key, user_id, subject_id, competition_id,
     competition_answer_id, difficulty, answer_result, band_code,
     delta_points, reason_code, total_points_after, level_after)
  VALUES
    ('answer:' || NEW.id::text, NEW.user_id, v_subject, NEW.competition_id,
     NEW.id, v_difficulty, NEW.answer_result, v_band ->> 'band_code',
     v_delta, v_reason, v_total, v_level)
  ON CONFLICT (event_key) DO NOTHING;

  IF NOT FOUND THEN
    RETURN NEW;   -- ayni cevap zaten islenmis; toplamlar degismez
  END IF;

  INSERT INTO public.faz30d_subject_mastery_current
    (user_id, subject_id, total_points, current_level, highest_level)
  VALUES (NEW.user_id, v_subject, v_total, v_level, v_level)
  ON CONFLICT (user_id, subject_id) DO UPDATE
     SET total_points  = EXCLUDED.total_points,
         current_level = EXCLUDED.current_level,
         highest_level = GREATEST(
           public.faz30d_subject_mastery_current.highest_level,
           EXCLUDED.highest_level),
         updated_at    = now();

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION private.faz30d_v3_record_answer_events() FROM PUBLIC;

-- TETIKLEYICI SIRASI BILINCLI KILINDI.
-- PostgreSQL ayni zaman/olay kombinasyonundaki tetikleyicileri
-- ADA GORE sirayla atar. competition_answers uzerinde iki AFTER
-- INSERT tetikleyicisi var:
--   trigger_01_faz30d_v3_record_answer_events  (once)
--   trigger_after_competition_answer_progress  (sonra)
-- Ikincisi advance_competition_progress cagiriyor ve son
-- cevapta yarismayi 'completed' yaparak bonus kancasini
-- TETIKLER. Golge kaydi bu kancanin okudugu tek veri
-- kaynagidir; kayit son cevabin INSERT'i icinde henuz
-- yazilmadiginda bonus KAYBOLUR (QA N-01 bu hatayi yakalar).
-- Bu yuzden adi sayisal onek ile onek alip kaydi garanti
-- ediyoruz. ADI DEGISTIRIRKEN BU BAGIMLILIGI KORUYUN.
DROP TRIGGER IF EXISTS trigger_01_faz30d_v3_record_answer_events
  ON public.competition_answers;

DROP TRIGGER IF EXISTS trigger_faz30d_v3_record_answer_events
  ON public.competition_answers;

CREATE TRIGGER trigger_01_faz30d_v3_record_answer_events
AFTER INSERT ON public.competition_answers
FOR EACH ROW
EXECUTE FUNCTION private.faz30d_v3_record_answer_events();


-- ============================================================
-- 8. FINALIZASYON KANCASI: RAKIP BONUSU + YARISMA TOPLAMI
--
-- Yalniz status 'active' -> 'completed' gecisinde, yalniz V3.
-- Idempotency:
--   - yarisma bazinda advisory lock (xact)
--   - ledger UNIQUE (user_id, competition_answer_id)
--   - global event UNIQUE event_key
--   - toplamlar ABSOLUT degerle yazilir (toplama degil)
-- ============================================================

CREATE OR REPLACE FUNCTION private.faz30d_v3_band_rank(p_band_code text)
RETURNS smallint
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE p_band_code
           WHEN 'perfect' THEN 3
           WHEN 'good'    THEN 2
           WHEN 'average' THEN 1
           WHEN 'poor'    THEN 0
           WHEN 'poor_grace' THEN 0
           WHEN 'proposed_timeout' THEN 0
           ELSE NULL
         END;
$fn$;

REVOKE ALL ON FUNCTION private.faz30d_v3_band_rank(text) FROM PUBLIC;


CREATE OR REPLACE FUNCTION private.faz30d_v3_apply_opponent_bonus()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $fn$
DECLARE
  v_rule_code text;
  v_fault     integer;
  v_gap1      integer;
  v_gap2      integer;
  v_gap3      integer;
  v_player    record;
  v_mine      record;
  v_opp_uid   uuid;
  v_opp_res   text;
  v_opp_band  text;
  v_row_bonus integer;
  v_gap       smallint;
  v_bonus     integer;
  v_total     integer;
  v_reason    text;
BEGIN
  IF NEW.status IS DISTINCT FROM 'completed'
     OR OLD.status IS NOT DISTINCT FROM 'completed' THEN
    RETURN NEW;
  END IF;

  SELECT srs.rule_set_code INTO v_rule_code
    FROM public.scoring_rule_sets srs
   WHERE srs.id = NEW.scoring_rule_set_id;

  IF v_rule_code IS DISTINCT FROM 'competition_scoring_v3_fixed' THEN
    RETURN NEW;
  END IF;

  -- Yarisma bazli seri lastirme (es zamanli finalize).
  PERFORM pg_advisory_xact_lock(
    hashtext('faz30d_v3_bonus:' || NEW.id::text));

  SELECT max(rule_value) FILTER (WHERE rule_key = 'opponent_wrong_or_timeout'),
         max(rule_value) FILTER (WHERE rule_key = 'band_gap_1'),
         max(rule_value) FILTER (WHERE rule_key = 'band_gap_2'),
         max(rule_value) FILTER (WHERE rule_key = 'band_gap_3')
    INTO v_fault, v_gap1, v_gap2, v_gap3
    FROM public.faz30d_v3_opponent_bonus_rules;

  v_fault := COALESCE(v_fault, 20);
  v_gap1  := COALESCE(v_gap1, 5);
  v_gap2  := COALESCE(v_gap2, 10);
  v_gap3  := COALESCE(v_gap3, 15);

  FOR v_player IN
    SELECT cp.user_id
      FROM public.competition_players cp
     WHERE cp.competition_id = NEW.id
  LOOP
    -- Yalniz KENDI dogru cevaplari bonus uretebilir.
    FOR v_mine IN
      SELECT ca.id AS answer_id,
             ca.competition_question_id AS cq_id,
             sh.band_code AS own_band
        FROM public.competition_answers ca
        JOIN public.faz30d_answer_shadow sh
          ON sh.competition_answer_id = ca.id
       WHERE ca.competition_id = NEW.id
         AND ca.user_id = v_player.user_id
         AND ca.answer_result = 'correct'
    LOOP
      SELECT ca_opp.user_id, ca_opp.answer_result, sh_opp.band_code
        INTO v_opp_uid, v_opp_res, v_opp_band
        FROM public.competition_answers ca_opp
        LEFT JOIN public.faz30d_answer_shadow sh_opp
          ON sh_opp.competition_answer_id = ca_opp.id
       WHERE ca_opp.competition_id = NEW.id
         AND ca_opp.competition_question_id = v_mine.cq_id
         AND ca_opp.user_id <> v_player.user_id
       LIMIT 1;

      -- Rakip cevabi yoksa veya T eksikse bonus uretilmez.
      CONTINUE WHEN v_opp_uid IS NULL;
      CONTINUE WHEN v_mine.own_band IS NULL OR v_opp_band IS NULL;

      v_row_bonus := 0;
      v_gap       := 0;

      IF v_opp_res IN ('wrong','timeout') THEN
        v_row_bonus := v_fault;
        v_reason    := 'v3_bonus_opponent_fault';

      ELSIF v_opp_res = 'pass' THEN
        v_row_bonus := 0;
        v_reason    := 'v3_bonus_opponent_pass';

      ELSIF v_opp_res = 'correct' THEN
        v_gap := COALESCE(private.faz30d_v3_band_rank(v_mine.own_band), 0)
               - COALESCE(private.faz30d_v3_band_rank(v_opp_band), 0);
        v_row_bonus := CASE v_gap
                         WHEN 1 THEN v_gap1
                         WHEN 2 THEN v_gap2
                         WHEN 3 THEN v_gap3
                         ELSE 0
                       END;
        v_reason    := 'v3_bonus_band_gap';
      ELSE
        v_reason    := 'v3_bonus_unknown_opponent_result';
      END IF;

      INSERT INTO public.faz30d_opponent_bonus_ledger
        (competition_id, user_id, competition_question_id,
         competition_answer_id, opponent_user_id,
         opponent_answer_result, own_answer_result,
         own_band_code, opponent_band_code, band_rank_gap,
         bonus_points, reason_code, provenance)
      VALUES
        (NEW.id, v_player.user_id, v_mine.cq_id, v_mine.answer_id,
         v_opp_uid, v_opp_res, 'correct',
         v_mine.own_band, v_opp_band, v_gap,
         v_row_bonus, v_reason,
         jsonb_build_object(
           'own_rank',     private.faz30d_v3_band_rank(v_mine.own_band),
           'opponent_rank',private.faz30d_v3_band_rank(v_opp_band),
           'independent_of_grade_and_difficulty', true))
      ON CONFLICT (user_id, competition_answer_id) DO NOTHING;
    END LOOP;

    -- Oyuncu bonus toplami: ABSOLUT deger (idempotent).
    SELECT COALESCE(SUM(l.bonus_points), 0)::integer INTO v_bonus
      FROM public.faz30d_opponent_bonus_ledger l
     WHERE l.competition_id = NEW.id
       AND l.user_id = v_player.user_id;

    UPDATE public.competition_players
       SET opponent_bonus_points = v_bonus
     WHERE competition_id = NEW.id
       AND user_id = v_player.user_id;

    -- Yarisma toplami = temel soru puanlari + bonus.
    -- V1/V2 yarismalarinda bu tetikleyici calismaz.
    SELECT (COALESCE(SUM(ca.points_awarded), 0) + v_bonus)::integer
      INTO v_total
      FROM public.competition_answers ca
     WHERE ca.competition_id = NEW.id
       AND ca.user_id = v_player.user_id;

    UPDATE public.competition_players
       SET total_points = v_total
     WHERE competition_id = NEW.id
       AND user_id = v_player.user_id;

    -- Global puan (golge): bonus olayi
    INSERT INTO public.faz30d_global_points_events
      (event_key, user_id, competition_id, event_kind,
       points, reason_code, provenance)
    VALUES
      ('bonus:' || NEW.id::text || ':' || v_player.user_id::text,
       v_player.user_id, NEW.id, 'opponent_bonus', v_bonus,
       'v3_opponent_bonus',
       jsonb_build_object('competition_id', NEW.id::text))
    ON CONFLICT (event_key) DO NOTHING;

    -- Global toplam: olay tablosundan MUTLAK hesap (idempotent).
    INSERT INTO public.faz30d_global_points_totals (user_id, total_points)
    VALUES (v_player.user_id, 0)
    ON CONFLICT (user_id) DO NOTHING;

    UPDATE public.faz30d_global_points_totals g
       SET total_points = COALESCE((
             SELECT SUM(ge.points)
               FROM public.faz30d_global_points_events ge
              WHERE ge.user_id = g.user_id), 0),
           updated_at = now()
     WHERE g.user_id = v_player.user_id;
  END LOOP;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION private.faz30d_v3_apply_opponent_bonus() FROM PUBLIC;

DROP TRIGGER IF EXISTS trigger_faz30d_v3_apply_opponent_bonus
  ON public.competitions;

CREATE TRIGGER trigger_faz30d_v3_apply_opponent_bonus
AFTER UPDATE ON public.competitions
FOR EACH ROW
EXECUTE FUNCTION private.faz30d_v3_apply_opponent_bonus();


-- ============================================================
-- 9. YORUM + IZLEME
-- ============================================================

COMMENT ON COLUMN public.questions.expert_solution_time_seconds IS
  'Uzman cozum suresi (saniye). V3 goreli sure bandinin T degeri. NULL ise V3 bant/bonus/ustalik uretilmez.';
COMMENT ON COLUMN public.competition_players.opponent_bonus_points IS
  'V3 soru bazli rakip bonusu toplami (yalniz yarisma puani + global golge). V1/V2 yarismalarinda 0.';
COMMENT ON TABLE public.faz30d_answer_shadow IS
  'V3 soru bazli bant/sure/provenance golge kaydi (append-only).';
COMMENT ON TABLE public.faz30d_opponent_bonus_ledger IS
  'V3 rakip bonusu olaylari (append-only, idempotent).';
COMMENT ON TABLE public.faz30d_subject_mastery_events IS
  'V3 ders ustaligi olaylari (append-only, idempotent).';
COMMENT ON TABLE public.faz30d_global_points_events IS
  'V3 global puan olaylari (append-only, idempotent). Lig tablosu degismez.';

DO $blk$
BEGIN
  RAISE NOTICE
    'FAZ 30D-1: V3 sabit puan + rakip bonusu + ustalik golge altyapisi kuruldu.';
END;
$blk$;

COMMIT;
