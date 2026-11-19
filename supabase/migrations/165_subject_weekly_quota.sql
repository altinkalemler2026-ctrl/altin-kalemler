-- ============================================================================
-- 165_subject_weekly_quota.sql — AK-QUOTA-SUBJECT-01: DERS BAZLI HAFTALIK KOTA
-- ============================================================================
-- ÜRÜN KARARI (kullanıcı, 2026-11-16 — 163'ün GLOBAL modeli geçersizdir):
--   * Her öğrenci, HER DERSTEN haftada en fazla 40 yarışmaya katılabilir.
--   * Her dersin haftalık YENİ soru hakkı ayrı ayrı 200'dür.
--   * Dersler arası sayaçlar BAĞIMSIZDIR (Matematik hakkı Fizik'i azaltmaz).
--   * Aynı dersin kolay/orta/zor seviyeleri ORTAK 40/200 kotasını paylaşır
--     (zorluk anahtarda YOKTUR; motor zaten tek paket içinde karıştırır — 077).
--   * Ders/seviye değiştirmek ilgili dersin kotasını yenilemez.
--   * Kota tüketimi paket OLUŞUMU anındadır (163 sözleşmesi korunur);
--     bağlantı kopmasında iade YOKTUR (GAP-163-A sözleşmesi aynen durur).
--   * Haftalık hak bitişinde yalnız İLGİLİ ders engellenir; diğerleri açık.
--
-- KANONİK DERS KİMLİĞİ: public.subjects.id (uuid).
--   * join_matchmaking_queue(p_subject_id) dersi DOĞRUDAN subjects.id ile alır
--     (079/082); competitions.subject_id aynı kimliği taşır (019). Zorluk ve
--     sınıf (grade_level) kota anahtarına GİRMEZ: sınıf değişimi haftayı
--     sıfırlamaz, zorluklar ortak sayacı paylaşır (ürün kararları 3/5/6).
--   * subject_id NULL yarışma: motor zaten fail-closed (077:122 prepare
--     reddeder); kota katmanı da fail-closed düşürür (sessiz saymaz).
--
-- MİMARİ: 163'ün ÜSTÜNE eklenen ileri migration; 163/164 dosyalarına
-- dokunulmaz. 163'ün MOTOR TABLOLARINDAKİ üç uygulama tetiği
-- (trg_sqw_comp_players / trg_sqw_comp_questions / trg_sqw_comp_finalize)
-- kaldırılır ve yerlerine DERS BAZLI muadilleri bağlanır. 163 nesneleri
-- (tablolar, _q163_* fonksiyonları, events append-only tetiği) DENETİM
-- ARŞİVİ olarak kalır; GUARD_165 kota/defter tabloları BOŞ olmadan ilerlemez
-- (kayıpsızlık: doluysa DURUR, otomatik taşıma/silme yapmaz — rapor §6).
--
-- HAFTA İÇİ GEÇİŞ SEMANTİĞİ: Global sayaçlar ders bazına dönüştürülemez
-- (hangi dersin tükendiği global kayıtta bilinmiyor); geçiş haftasında yeni
-- model sıfırdan başlar. Eski model ÖĞRENCİ ALEYHİNE fazla sayıyordu
-- (40 global), dolayısıyla yeni model hiçbir öğrencinin hakkını azaltmaz.
-- 163 satırları arşiv olarak durur (silinmez).
--
-- EŞZAMANLILIK: kullanıcı+hafta+DERS başına pg_advisory_xact_lock; kilitler
-- her statement tetiğinde user_id SIRALI alınır → kilit döngüsü yok.
-- Çift tıklama: 082 idempotent 'waiting' döner (kota değişmez); cq tekrar
-- yazımı ON CONFLICT ile atlar → statement tetiği boş new_rows ile çalışır.
--
-- 063/068/077 MEVCUT DAVRANIŞLARI KORUNUR: subject-bazlı 500 sayacı ve
-- clamp'i aynen durur; 165 global-200 kapısı yerine DERS BAZLI 200 kapısıdır.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ============================================================
-- 0) GUARD_165 — taban + 163 katmanı + kalıntı + anıtkoruma snapshot'ı
-- ============================================================
DO $guard$
DECLARE
  v_max int;
BEGIN
  SELECT max(version::int) INTO v_max
    FROM supabase_migrations.schema_migrations;

  -- 165 yalnız 164 uygulanmış tabana kurulur (CI dosya sırası ve canlı
  -- out-of-order yolu aynı anda max=164 üretir — 42-17/VIS-04 dersi).
  IF v_max IS NULL OR v_max <> 164 THEN
    RAISE EXCEPTION 'GUARD_165: taban migration 164 degil (max=%).', v_max;
  END IF;

  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
              WHERE version = '165') THEN
    RAISE EXCEPTION 'GUARD_165: 165 kaydi zaten var — yeniden uygulama GUARD disi.';
  END IF;

  -- 163/164 katmanı durmalı (bu migration 163 tetiklerini DEVRALIR)
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '163')
     OR NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '164') THEN
    RAISE EXCEPTION 'GUARD_165: 163/164 kaydi eksik — ders bazli kota 163 katmanini devralir.';
  END IF;

  -- 165 kalıntısı olmamalı (fail-closed; klasik replay değil)
  IF to_regclass('public.student_week_subject_quota') IS NOT NULL
     OR to_regclass('public.student_week_subject_question_ledger') IS NOT NULL
     OR to_regclass('public.student_week_subject_quota_events') IS NOT NULL THEN
    RAISE EXCEPTION 'GUARD_165: 165 tablo kalintisi var — elle incele.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname LIKE '_q165%'
             OR proname = 'weekly_quota_status_per_subject') THEN
    RAISE EXCEPTION 'GUARD_165: 165 fonksiyon kalintisi var — elle incele.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
              JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public' AND NOT t.tgisinternal
               AND t.tgname IN ('trg_sqsq_comp_players','trg_sqsq_comp_questions',
                                'trg_sqsq_comp_finalize','trg_sqse_append_only')) THEN
    RAISE EXCEPTION 'GUARD_165: 165 tetik kalintisi var — elle incele.';
  END IF;

  -- 163 uygulama katmanı yerinde olmalı (tetikleri bu migration devralır)
  IF to_regclass('public.student_week_quota') IS NULL THEN
    RAISE EXCEPTION 'GUARD_165: 163 kota tablosu yok (once 163 uygulanmali).';
  END IF;
  IF (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
       WHERE NOT t.tgisinternal
         AND t.tgname IN ('trg_sqw_comp_players','trg_sqw_comp_questions',
                          'trg_sqw_comp_finalize','trg_sqwe_append_only')) <> 4 THEN
    RAISE EXCEPTION 'GUARD_165: 163 tetikleri tam degil (4 beklenir) — taban bozuk.';
  END IF;

  -- KAYIPTSIZLIK KAPISI: 163 kota/defter satırları varsa DUR.
  -- Otomatik dönüşüm YAPILMAZ (ders dağılımı global kayıtta bilinmiyor);
  -- dolu tablo = kullanıcı kararı gerekir (rapor §6 taşıma planı).
  IF EXISTS (SELECT 1 FROM public.student_week_quota)
     OR EXISTS (SELECT 1 FROM public.student_week_question_ledger) THEN
    RAISE EXCEPTION 'GUARD_165: 163 kota/defter tablolari BOS DEGIL — kayipsiz gecis icin elle karar gerekli (AK-QUOTA-SUBJECT-01 §6).';
  END IF;

  -- Motor önkoşulları (163 ile aynı bant)
  IF to_regclass('public.student_weekly_counters') IS NULL
     OR to_regclass('public.student_question_exposures') IS NULL
     OR to_regclass('public.student_pack_exposures') IS NULL
     OR to_regclass('public.competitions') IS NULL
     OR to_regclass('public.competition_players') IS NULL
     OR to_regclass('public.matchmaking_queue') IS NULL
     OR to_regclass('public.subjects') IS NULL THEN
    RAISE EXCEPTION 'GUARD_165: motor onkosul tablosu yok (062/063/019/002).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'join_matchmaking_queue'
                 AND pronargs = 1 AND proargtypes::text LIKE '%2950%')
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'prepare_competition_pack')
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'resolve_current_academic_period') THEN
    RAISE EXCEPTION 'GUARD_165: motor RPC/period fonksiyonu bulunamadi.';
  END IF;

  -- Motor + 163 anıtkoruma snapshot'ı (bu migration bunları DEĞİŞTİRMEZ;
  -- 163 tetiklerinin KALDIRILMASI bilinçli tek farktır ve FINAL'da assert edilir)
  CREATE TEMP TABLE ak165_snap ON COMMIT DROP AS
  SELECT 'fn:' || p.proname || '=' || md5(coalesce(p.prosrc, '')) AS k,
         md5(coalesce(p.prosrc, '')) AS v
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('join_matchmaking_queue','prepare_competition_pack',
                       'finalize_competition_if_ready','submit_competition_answer',
                       'recalculate_competition_player_score','resolve_competition_points',
                       'get_competition_scoreboard','advance_competition_progress',
                       'release_competition_question','set_competition_player_ready',
                       'get_current_competition_question','sync_competition_state',
                       'create_missing_competition_timeouts','after_competition_answer_progress',
                       'resolve_current_academic_period','_faz2_require_period',
                       '_faz2_lock_weekly_counter','_faz2_consume_weekly_capacity',
                       'curriculum_subtopic_week_state',
                       '_q163_period','_q163_lock','_q163_reserve_competition',
                       '_q163_reserve_questions','_q163_trg_comp_players',
                       '_q163_trg_comp_questions','_q163_trg_comp_finalize',
                       '_q163_trg_events_append_only')
   UNION ALL SELECT 'cnt:competitions', count(*)::text FROM public.competitions
   UNION ALL SELECT 'cnt:competition_players', count(*)::text FROM public.competition_players
   UNION ALL SELECT 'cnt:matchmaking_queue', count(*)::text FROM public.matchmaking_queue
   UNION ALL SELECT 'cnt:counters', count(*)::text FROM public.student_weekly_counters
   UNION ALL SELECT 'cnt:exp_q', count(*)::text FROM public.student_question_exposures
   UNION ALL SELECT 'cnt:exp_p', count(*)::text FROM public.student_pack_exposures
   UNION ALL SELECT 'cnt:q163_quota', count(*)::text FROM public.student_week_quota
   UNION ALL SELECT 'cnt:q163_ledger', count(*)::text FROM public.student_week_question_ledger;
END $guard$;

-- ============================================================
-- 1) DERS BAZLI HAFTALIK KOTA ANA TABLOSU
--    Anahtar: ogrenci + akademik yil + hafta + KANONIK DERS (subjects.id).
--    Zorluk ve SINIF anahtarda yok (zorluklar ortaktir; sinif degisimi
--    haftayi sifirlamaz).
-- ============================================================
CREATE TABLE public.student_week_subject_quota (
  user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE CASCADE,
  academic_year text NOT NULL,
  week integer NOT NULL
    CHECK (week BETWEEN 0 AND 52),
  subject_id uuid NOT NULL
    REFERENCES public.subjects(id),

  -- Yarışma rezervasyonu: yarışma OLUŞUMUNDA +1 (iptal/timeout refund etmez
  -- — GAP-163-A sözleşmesi aynen). Son savunma: CHECK.
  competitions_reserved integer NOT NULL DEFAULT 0
    CHECK (competitions_reserved BETWEEN 0 AND 40),

  -- Yeni (hiç görülmemiş) soru rezervasyonu — gösterim anında, DERS BAZLI.
  new_questions_reserved integer NOT NULL DEFAULT 0
    CHECK (new_questions_reserved BETWEEN 0 AND 200),

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (user_id, academic_year, week, subject_id)
);
COMMENT ON TABLE public.student_week_subject_quota IS
  'Ders bazli haftalik ogrenci kotasi: ders basina 40 yarisma + 200 yeni soru. Dersler bagimsiz; zorluk ortaktir. Anahtar user+yil+hafta+ders.';

CREATE TRIGGER trg_sqsq_updated_at
BEFORE UPDATE ON public.student_week_subject_quota
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.student_week_subject_quota ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_week_subject_quota FORCE ROW LEVEL SECURITY;
CREATE POLICY student_reads_own_subject_week_quota ON public.student_week_subject_quota
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE TABLE public.student_week_subject_question_ledger (
  user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE CASCADE,
  academic_year text NOT NULL,
  week integer NOT NULL
    CHECK (week BETWEEN 0 AND 52),
  subject_id uuid NOT NULL
    REFERENCES public.subjects(id),
  question_id uuid NOT NULL
    REFERENCES public.questions(id) ON DELETE CASCADE,
  source_vault_id uuid
    REFERENCES public.question_vaults(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, academic_year, week, subject_id, question_id)
);
COMMENT ON TABLE public.student_week_subject_question_ledger IS
  'Dersin haftalik BENZERSIZ yeni soru defteri (PK tekil-dogrulama; ayni soru derste haftada bir kez sayilir).';

CREATE INDEX idx_sqsqql_vault ON public.student_week_subject_question_ledger(source_vault_id);
CREATE INDEX idx_sqsqql_user_week ON public.student_week_subject_question_ledger
  (user_id, academic_year, week, subject_id);

ALTER TABLE public.student_week_subject_question_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_week_subject_question_ledger FORCE ROW LEVEL SECURITY;
CREATE POLICY student_reads_own_subject_week_ledger ON public.student_week_subject_question_ledger
FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- 2) EKLENMEZ DENETİM KAYDI (append-only, ders bazlı)
-- ============================================================
CREATE TABLE public.student_week_subject_quota_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE CASCADE,
  academic_year text NOT NULL,
  week integer NOT NULL
    CHECK (week BETWEEN 0 AND 52),
  subject_id uuid NOT NULL
    REFERENCES public.subjects(id),
  competition_id uuid
    REFERENCES public.competitions(id) ON DELETE SET NULL,
  event text NOT NULL
    CHECK (event IN ('competition_reserved','questions_reserved',
                     'questions_refunded','competition_finalized')),
  delta integer NOT NULL DEFAULT 0,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.student_week_subject_quota_events IS
  'Ders bazli kota yasami icin eklenmez denetim. Refund varsayilan YOK (GAP-163-A sozlesmesi surer).';

CREATE INDEX idx_sqse_user_week ON public.student_week_subject_quota_events
  (user_id, academic_year, week, subject_id);
CREATE INDEX idx_sqse_competition ON public.student_week_subject_quota_events
  (competition_id);

ALTER TABLE public.student_week_subject_quota_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_week_subject_quota_events FORCE ROW LEVEL SECURITY;
CREATE POLICY student_reads_own_subject_week_events ON public.student_week_subject_quota_events
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE FUNCTION public._q165_trg_events_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  RAISE EXCEPTION 'KOTA_165: kota denetim kaydi eklenmez (append-only).';
END $fn$;

CREATE TRIGGER trg_sqse_append_only
BEFORE UPDATE OR DELETE ON public.student_week_subject_quota_events
FOR EACH ROW EXECUTE FUNCTION public._q165_trg_events_append_only();

-- ============================================================
-- 3) İÇ İŞLEVLER (istemciye tam kapalı)
-- ============================================================

-- Dönem çözümleyici: motorla AYNI kaynak (fail-closed; 068 sözleşmesi).
CREATE FUNCTION public._q165_period()
RETURNS TABLE (academic_year text, week integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  RETURN QUERY SELECT * FROM public.resolve_current_academic_period();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'KOTA_165: gecerli akademik donem yok; kota fail-closed.';
  END IF;
END $fn$;

-- Ders kimliği: yarışmanın KANONİK subject_id'si (019/079/082 zinciri).
-- NULL yarışma satırı veya NULL ders → fail-closed (motor 077:122 ile
-- zaten aynı sözleşmeyi taşır; kota sessiz saymaz).
CREATE FUNCTION public._q165_subject_of(p_comp uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE v_subject uuid; v_found boolean;
BEGIN
  SELECT c.subject_id, true INTO v_subject, v_found
    FROM public.competitions c
   WHERE c.id = p_comp;
  IF NOT coalesce(v_found, false) OR v_subject IS NULL THEN
    RAISE EXCEPTION 'KOTA_165: yarisma bulunamadi veya ders kimligi cozulemedi — kota fail-closed.';
  END IF;
  RETURN v_subject;
END $fn$;

-- Kilit: kullanıcı+hafta+DERS. Dersler arası sayaçlar bağımsız kilitlerle
-- paralel ilerleyebilir (ürün kararı 4: aynı anda iki derse katılım).
CREATE FUNCTION public._q165_lock(p_user uuid, p_year text, p_week integer, p_subject uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended('kq165:' || p_user::text || '|' || p_year || '|' || p_week::text || '|' || p_subject::text, 0)
  );
END $fn$;

-- Yarışma rezervasyonu (+1, DERSE ÖZEL). Çağıran: competition_players
-- statement tetiği. 40 dolunca KOTA_165 (ürün mesajı errors.ts'te).
CREATE FUNCTION public._q165_reserve_competition(p_user uuid, p_comp uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE v_year text; v_week integer; v_subject uuid; v_res integer;
BEGIN
  SELECT y, w INTO v_year, v_week FROM public._q165_period() AS t(y, w);
  v_subject := public._q165_subject_of(p_comp);
  PERFORM public._q165_lock(p_user, v_year, v_week, v_subject);

  INSERT INTO public.student_week_subject_quota
    (user_id, academic_year, week, subject_id)
  VALUES (p_user, v_year, v_week, v_subject)
  ON CONFLICT (user_id, academic_year, week, subject_id) DO NOTHING;

  SELECT competitions_reserved INTO v_res
    FROM public.student_week_subject_quota
   WHERE user_id = p_user AND academic_year = v_year AND week = v_week
     AND subject_id = v_subject
     FOR UPDATE;

  IF v_res >= 40 THEN
    RAISE EXCEPTION 'KOTA_165: bu ders icin haftalik yarisma kotasi doldu (%/40) — yeni yarisma olusamiyor.', v_res;
  END IF;

  UPDATE public.student_week_subject_quota
     SET competitions_reserved = competitions_reserved + 1
   WHERE user_id = p_user AND academic_year = v_year AND week = v_week
     AND subject_id = v_subject;

  INSERT INTO public.student_week_subject_quota_events
    (user_id, academic_year, week, subject_id, competition_id, event, delta)
  VALUES (p_user, v_year, v_week, v_subject, p_comp, 'competition_reserved', 1);
END $fn$;

-- Yeni soru rezervasyonu (DERSE ÖZEL): yarışmaya ATANAN (cq snapshot)
-- sorulardan öğrencinin bu hafta BU DERSTE henüz defterde olmayan ve bu
-- yarışmadan ÖNCE görmemiş olduğu soruları sayar. ÇAĞIRAN:
-- competition_questions statement tetiği (077 sırası: pack exposure → soru
-- exposure → cq snapshot; cq son yazım noktası).
-- GÖRÜLMÜŞLÜK: aynı transaction'ın now() değeri competitions.created_at ile
-- birebir eşittir → bu prepare'in exposure'ları "önceden görülmüş" sayılmaz.
-- Küresel exposure kesiti (077 motoru) AYNEN korunur; defter kesimi dersle
-- daraltılır (ürün kararı: her dersin 200'ü ayrı).
CREATE FUNCTION public._q165_reserve_questions(p_user uuid, p_comp uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_year text; v_week integer; v_subject uuid;
  v_take uuid[]; v_n int; v_res integer;
  v_created timestamptz; v_vault uuid;
BEGIN
  SELECT c.created_at, c.subject_id,
         (c.configuration -> 'faz2_pack' ->> 'vault_id')::uuid
    INTO v_created, v_subject, v_vault
    FROM public.competitions c
   WHERE c.id = p_comp;
  IF v_created IS NULL THEN
    RETURN;                                    -- yarışma satırı yok: rezervasyon yok
  END IF;

  SELECT y, w INTO v_year, v_week FROM public._q165_period() AS t(y, w);
  PERFORM public._q165_lock(p_user, v_year, v_week, v_subject);

  SELECT coalesce(array_agg(u.question_id ORDER BY u.question_id), '{}'::uuid[])
    INTO v_take
  FROM (
    SELECT DISTINCT cq.question_id
      FROM public.competition_questions cq
     WHERE cq.competition_id = p_comp
       AND NOT EXISTS (                       -- bu hafta bu derste zaten defterde
         SELECT 1 FROM public.student_week_subject_question_ledger l
          WHERE l.user_id = p_user AND l.academic_year = v_year
            AND l.week = v_week AND l.subject_id = v_subject
            AND l.question_id = cq.question_id)
       AND NOT EXISTS (                       -- bu yarismadan ONCE gorulmus (kuresel)
         SELECT 1 FROM public.student_question_exposures e
          WHERE e.user_id = p_user AND e.question_id = cq.question_id
            AND e.first_exposed_at < v_created)
  ) u;

  v_n := coalesce(array_length(v_take, 1), 0);
  IF v_n = 0 THEN
    RETURN;                                    -- tekrar paketi: yeni soru tuketmez
  END IF;

  INSERT INTO public.student_week_subject_quota
    (user_id, academic_year, week, subject_id)
  VALUES (p_user, v_year, v_week, v_subject)
  ON CONFLICT (user_id, academic_year, week, subject_id) DO NOTHING;

  SELECT new_questions_reserved INTO v_res
    FROM public.student_week_subject_quota
   WHERE user_id = p_user AND academic_year = v_year AND week = v_week
     AND subject_id = v_subject
     FOR UPDATE;

  IF v_res + v_n > 200 THEN
    RAISE EXCEPTION 'KOTA_165: bu ders icin haftalik yeni soru kotasi asilirdi (%+%>200) — paket dagitilamiyor.', v_res, v_n;
  END IF;

  UPDATE public.student_week_subject_quota
     SET new_questions_reserved = new_questions_reserved + v_n
   WHERE user_id = p_user AND academic_year = v_year AND week = v_week
     AND subject_id = v_subject;

  INSERT INTO public.student_week_subject_question_ledger
    (user_id, academic_year, week, subject_id, question_id, source_vault_id)
  SELECT p_user, v_year, v_week, v_subject, u, v_vault FROM unnest(v_take) AS u
  ON CONFLICT DO NOTHING;

  INSERT INTO public.student_week_subject_quota_events
    (user_id, academic_year, week, subject_id, competition_id, event, delta, detail)
  VALUES (p_user, v_year, v_week, v_subject, p_comp, 'questions_reserved', v_n,
          jsonb_build_object('vault_id', v_vault));
END $fn$;

-- ============================================================
-- 4) TETİK FONKSİYONLARI (motor tablolarına EKLENTİ — gövdeler değişmez)
-- ============================================================

-- 4a) Yarışma oluşumu: her yeni oyuncu satırı = ilgili DERSTE 1 rezervasyon.
CREATE FUNCTION public._q165_trg_comp_players()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE r record;
BEGIN
  -- Kilit siralamasi deterministik (deadlock yasağı): user,comp sirali.
  FOR r IN
    SELECT DISTINCT nr.user_id, nr.competition_id
      FROM new_rows nr ORDER BY nr.user_id, nr.competition_id
  LOOP
    PERFORM public._q165_reserve_competition(r.user_id, r.competition_id);
  END LOOP;
  RETURN NULL;
END $fn$;

-- 4b) Soru ataması (cq snapshot): gösterilen sorular = ilgili derste tüketim.
CREATE FUNCTION public._q165_trg_comp_questions()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE r record;
BEGIN
  -- Kilit siralamasi deterministik: user,comp sirali.
  FOR r IN
    SELECT DISTINCT cp.user_id, nq.competition_id
      FROM new_rows nq
      JOIN public.competition_players cp ON cp.competition_id = nq.competition_id
     ORDER BY cp.user_id, nq.competition_id
  LOOP
    PERFORM public._q165_reserve_questions(r.user_id, r.competition_id);
  END LOOP;
  RETURN NULL;
END $fn$;

-- 4c) Kesinleşme: completed/cancelled/abandoned → DERS BAZLI denetim olayı
-- (refund YOK — GAP-163-A). Denetim en-iyi-çaba: motorun kesinleştirme
-- akışı ASLA bloklanmaz (audit kota kapısı değildir).
CREATE FUNCTION public._q165_trg_comp_finalize()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  r record; v_year text; v_week integer; v_subject uuid;
BEGIN
  SELECT e.academic_year, e.week, e.subject_id INTO v_year, v_week, v_subject
    FROM public.student_week_subject_quota_events e
   WHERE e.competition_id = NEW.id AND e.event = 'competition_reserved'
   ORDER BY e.created_at LIMIT 1;

  IF v_year IS NULL THEN
    -- Rezervasyon olayı yok: ders kimliği yarışmadan, dönem güncelden.
    BEGIN
      v_subject := public._q165_subject_of(NEW.id);
      SELECT y, w INTO v_year, v_week FROM public._q165_period() AS t(y, w);
    EXCEPTION WHEN raise_exception THEN
      RETURN NULL;   -- cozulemez kesinelesme: denetim yazilamaz, motor engellenmez
    END;
  END IF;

  IF v_subject IS NULL THEN
    RETURN NULL;
  END IF;

  FOR r IN
    SELECT cp.user_id FROM public.competition_players cp
     WHERE cp.competition_id = NEW.id ORDER BY cp.user_id
  LOOP
    PERFORM public._q165_lock(r.user_id, v_year, v_week, v_subject);
    INSERT INTO public.student_week_subject_quota_events
      (user_id, academic_year, week, subject_id, competition_id, event, delta, detail)
    VALUES (r.user_id, v_year, v_week, v_subject, NEW.id, 'competition_finalized', 0,
            jsonb_build_object('old_status', OLD.status, 'new_status', NEW.status));
  END LOOP;
  RETURN NULL;
END $fn$;

-- ============================================================
-- 5) TETİK DEVRALIMI: 163 motor tetikleri kalkar, 165 bağlanır.
--    (trg_sqwe_append_only 163 arşivinde DURUR.)
-- ============================================================
DROP TRIGGER trg_sqw_comp_players ON public.competition_players;
DROP TRIGGER trg_sqw_comp_questions ON public.competition_questions;
DROP TRIGGER trg_sqw_comp_finalize ON public.competitions;

CREATE TRIGGER trg_sqsq_comp_players
AFTER INSERT ON public.competition_players
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION public._q165_trg_comp_players();

CREATE TRIGGER trg_sqsq_comp_questions
AFTER INSERT ON public.competition_questions
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION public._q165_trg_comp_questions();

CREATE TRIGGER trg_sqsq_comp_finalize
AFTER UPDATE OF status ON public.competitions
FOR EACH ROW
WHEN (NEW.status IS DISTINCT FROM OLD.status
      AND NEW.status IN ('completed','cancelled','abandoned'))
EXECUTE FUNCTION public._q165_trg_comp_finalize();

-- ============================================================
-- 6) ÖĞRENCİ OKUMA ARAYÜZÜ (ders bazlı)
-- ============================================================

-- Ders bazlı durum: aktif TÜM dersler için öğrencinin kendi haftalık durumu.
-- UI kart başına değerleri buradan alır; uyduurulmuş sayı üretilmez.
CREATE FUNCTION public.weekly_quota_status_per_subject()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_user uuid; v_year text; v_week integer;
  v_subjects jsonb;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'YETKI_165: kimlik dogrulamasi gerekli.'
      USING errcode = '42501';
  END IF;
  SELECT r.academic_year, r.week INTO v_year, v_week
    FROM public.resolve_current_academic_period() AS r;
  IF v_year IS NULL THEN
    RETURN jsonb_build_object(
      'model', 'subject_weekly_quota_v165',
      'academic_year', NULL, 'week', NULL,
      'subjects', '[]'::jsonb,
      'note', 'gecerli akademik donem yok');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'subject_id', s.id,
           'competitions_used', coalesce(q.competitions_reserved, 0),
           'competitions_limit', 40,
           'new_questions_used', coalesce(q.new_questions_reserved, 0),
           'new_questions_limit', 200,
           'updated_at', q.updated_at
         ) ORDER BY s.sort_order, s.name), '[]'::jsonb)
    INTO v_subjects
    FROM public.subjects s
    LEFT JOIN public.student_week_subject_quota q
      ON q.subject_id = s.id
     AND q.user_id = v_user
     AND q.academic_year = v_year
     AND q.week = v_week
   WHERE s.is_active = true;

  RETURN jsonb_build_object(
    'model', 'subject_weekly_quota_v165',
    'academic_year', v_year, 'week', v_week,
    'subjects', v_subjects);
END $fn$;

-- 163 küresel RPC'si DEVRE DIŞI: küresel sayım ürün kararınca YANLIŞTIR.
-- Eski UI bu RPC'yi çağırmaya devam ederse teknik hata alir ve banner'ı
-- fail-closed gizler (uydurma küresel sayi GOSTERILMEZ); kota gercegi
-- sunucu tetiklerinde ve weekly_quota_status_per_subject()'tadir.
CREATE OR REPLACE FUNCTION public.weekly_quota_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  RAISE EXCEPTION 'KOTA_165_DEPRECATED: haftalik kota artik ders bazlidir; weekly_quota_status_per_subject() kullanin.'
    USING errcode = 'P0001';
END $fn$;

-- ============================================================
-- 7) İZİN MATRİSİ (163 §7 kalıbının ders bazlısı)
-- ============================================================
REVOKE ALL ON public.student_week_subject_quota,
              public.student_week_subject_question_ledger,
              public.student_week_subject_quota_events
  FROM anon, authenticated;
GRANT SELECT ON public.student_week_subject_quota,
                public.student_week_subject_question_ledger,
                public.student_week_subject_quota_events
  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.student_week_subject_quota,
                                        public.student_week_subject_question_ledger
  TO service_role;
GRANT SELECT, INSERT ON public.student_week_subject_quota_events TO service_role;

-- RPC: öğrenci kendi ders bazlı durumunu görür.
REVOKE ALL ON FUNCTION public.weekly_quota_status_per_subject() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.weekly_quota_status_per_subject() TO authenticated, service_role;

-- weekly_quota_status() imzası değişmedi: 163 ACL'i aynen durur
-- (authenticated EXECUTE, anon yok) — gövde artık deprecated-raise.

-- İç işlevler + tetik fonksiyonları: istemciye TAM kapalı.
DO $grants$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    '_q165_period()', '_q165_subject_of(uuid)',
    '_q165_lock(uuid,text,integer,uuid)',
    '_q165_reserve_competition(uuid,uuid)', '_q165_reserve_questions(uuid,uuid)',
    '_q165_trg_comp_players()', '_q165_trg_comp_questions()', '_q165_trg_comp_finalize()',
    '_q165_trg_events_append_only()'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon, authenticated', f);
  END LOOP;
END $grants$;

-- ============================================================
-- 8) FINAL_165 — yapısal + anıtkoruma kanıtları
-- ============================================================
DO $final$
DECLARE
  n int; bad int; v_u uuid;
BEGIN
  -- 8a) Nesne doğumu
  SELECT count(*) INTO n FROM pg_class
   WHERE relname IN ('student_week_subject_quota','student_week_subject_question_ledger','student_week_subject_quota_events')
     AND relkind = 'r';
  IF n <> 3 THEN RAISE EXCEPTION 'FINAL_165: tablo sayisi % != 3', n; END IF;

  SELECT count(*) INTO n FROM pg_policies
   WHERE tablename IN ('student_week_subject_quota','student_week_subject_question_ledger','student_week_subject_quota_events');
  IF n <> 3 THEN RAISE EXCEPTION 'FINAL_165: politika sayisi % != 3', n; END IF;

  SELECT count(*) INTO n FROM pg_class
   WHERE relname IN ('student_week_subject_quota','student_week_subject_question_ledger','student_week_subject_quota_events')
     AND relrowsecurity AND relforcerowsecurity;
  IF n <> 3 THEN RAISE EXCEPTION 'FINAL_165: RLS/FORCE eksik.'; END IF;

  -- CHECK son savunma hattı yerinde mi (40/200/hafta aralıkları; subject FK)
  SELECT count(*) INTO n FROM pg_constraint
   WHERE conrelid = 'public.student_week_subject_quota'::regclass AND contype = 'c';
  IF n <> 3 THEN RAISE EXCEPTION 'FINAL_165: kota CHECK sayisi % != 3', n; END IF;

  -- 8b) Tetik devralımı: 163 motor tetikleri KALKMIŞ olmalı, arşiv append-only DURMALI
  SELECT count(*) INTO n FROM pg_trigger t
   WHERE t.tgname IN ('trg_sqw_comp_players','trg_sqw_comp_questions','trg_sqw_comp_finalize')
     AND NOT t.tgisinternal;
  IF n <> 0 THEN RAISE EXCEPTION 'FINAL_165: 163 motor tetikleri henu duruyor (%).', n; END IF;

  SELECT count(*) INTO n FROM pg_trigger t
   WHERE t.tgname = 'trg_sqwe_append_only' AND NOT t.tgisinternal;
  IF n <> 1 THEN RAISE EXCEPTION 'FINAL_165: 163 arsiv append-only tetigi kaybedildi.'; END IF;

  -- 165 tetik bağları (motor tablolarında 3 + events append-only 1)
  SELECT count(*) INTO n FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
   WHERE t.tgname IN ('trg_sqsq_comp_players','trg_sqsq_comp_questions',
                      'trg_sqsq_comp_finalize','trg_sqse_append_only')
     AND NOT t.tgisinternal;
  IF n <> 4 THEN RAISE EXCEPTION 'FINAL_165: kota tetikleri % != 4', n; END IF;

  -- 8c) ACL: istemci yazamaz; RPC açık; iç işlevler kapalı
  SELECT count(*) INTO bad FROM (VALUES ('anon'),('authenticated')) AS r(rol)
   CROSS JOIN (VALUES ('student_week_subject_quota'),('student_week_subject_question_ledger'),
                      ('student_week_subject_quota_events')) AS c(rel)
   WHERE has_table_privilege(r.rol, 'public.' || c.rel, 'INSERT')
      OR has_table_privilege(r.rol, 'public.' || c.rel, 'UPDATE')
      OR has_table_privilege(r.rol, 'public.' || c.rel, 'DELETE');
  IF bad <> 0 THEN RAISE EXCEPTION 'FINAL_165: istemci yazma yetkisi var.'; END IF;

  IF NOT has_function_privilege('authenticated','public.weekly_quota_status_per_subject()','EXECUTE')
     OR has_function_privilege('anon','public.weekly_quota_status_per_subject()','EXECUTE') THEN
    RAISE EXCEPTION 'FINAL_165: weekly_quota_status_per_subject ACL bozuk.';
  END IF;

  -- deprecated RPC kanıtı: gövde KOTA_165_DEPRECATED taşır (geri alınabilir)
  IF (SELECT count(*) FROM pg_proc WHERE proname = 'weekly_quota_status'
        AND pronargs = 0
        AND prosrc LIKE '%KOTA_165_DEPRECATED%') <> 1 THEN
    RAISE EXCEPTION 'FINAL_165: weekly_quota_status deprecated govde degil.';
  END IF;

  SELECT count(*) INTO bad FROM pg_proc
   WHERE proname LIKE '_q165%'
     AND has_function_privilege('authenticated', oid, 'EXECUTE');
  IF bad <> 0 THEN RAISE EXCEPTION 'FINAL_165: ic islevler acik.'; END IF;

  -- 8d) CHECK son savunma hattı canlı probe: 41/201 reddedilmeli (probe geri alınır)
  SELECT id INTO v_u FROM auth.users ORDER BY id LIMIT 1;
  IF v_u IS NOT NULL THEN
    BEGIN
      INSERT INTO public.student_week_subject_quota
        (user_id, academic_year, week, subject_id, competitions_reserved)
      SELECT v_u, '2026-2027', 1, s.id, 41 FROM public.subjects s ORDER BY s.id LIMIT 1;
      RAISE EXCEPTION 'FINAL_165: 41 yarisma CHECK kirmadi.';
    EXCEPTION
      WHEN check_violation THEN NULL;
      WHEN raise_exception THEN RAISE;
    END;
    BEGIN
      INSERT INTO public.student_week_subject_quota
        (user_id, academic_year, week, subject_id, new_questions_reserved)
      SELECT v_u, '2026-2027', 1, s.id, 201 FROM public.subjects s ORDER BY s.id LIMIT 1;
      RAISE EXCEPTION 'FINAL_165: 201 soru CHECK kirmadi.';
    EXCEPTION
      WHEN check_violation THEN NULL;
      WHEN raise_exception THEN RAISE;
    END;
  ELSE
    RAISE NOTICE 'FINAL_165: auth.users bos — CHECK canli probe atlandi (katalog kontrolu yapildi).';
  END IF;

  -- 8e) Motor + 163 fonksiyon anıtkoruma: GUARD snapshot'ı ile birebir
    -- (bilinçli tek fark — 163 motor TETİKLERİ — snapshot fonksiyon GÖVDelerini
  --  içermez; gövdeler değişmemelidir; tetik devralimi 8b'de assert edilir).
  SELECT count(*) INTO bad FROM (
    SELECT k, v FROM ak165_snap
    EXCEPT ALL
    SELECT k, v FROM (
      SELECT 'fn:' || p.proname || '=' || md5(coalesce(p.prosrc, '')) AS k,
             md5(coalesce(p.prosrc, '')) AS v
        FROM pg_proc p JOIN pg_namespace nn ON nn.oid = p.pronamespace
       WHERE nn.nspname = 'public'
         AND p.proname IN ('join_matchmaking_queue','prepare_competition_pack',
                           'finalize_competition_if_ready','submit_competition_answer',
                           'recalculate_competition_player_score','resolve_competition_points',
                           'get_competition_scoreboard','advance_competition_progress',
                           'release_competition_question','set_competition_player_ready',
                           'get_current_competition_question','sync_competition_state',
                           'create_missing_competition_timeouts','after_competition_answer_progress',
                           'resolve_current_academic_period','_faz2_require_period',
                           '_faz2_lock_weekly_counter','_faz2_consume_weekly_capacity',
                           'curriculum_subtopic_week_state',
                           '_q163_period','_q163_lock','_q163_reserve_competition',
                           '_q163_reserve_questions','_q163_trg_comp_players',
                           '_q163_trg_comp_questions','_q163_trg_comp_finalize',
                           '_q163_trg_events_append_only')
      UNION ALL SELECT 'cnt:competitions', count(*)::text FROM public.competitions
      UNION ALL SELECT 'cnt:competition_players', count(*)::text FROM public.competition_players
      UNION ALL SELECT 'cnt:matchmaking_queue', count(*)::text FROM public.matchmaking_queue
      UNION ALL SELECT 'cnt:counters', count(*)::text FROM public.student_weekly_counters
      UNION ALL SELECT 'cnt:exp_q', count(*)::text FROM public.student_question_exposures
      UNION ALL SELECT 'cnt:exp_p', count(*)::text FROM public.student_pack_exposures
      UNION ALL SELECT 'cnt:q163_quota', count(*)::text FROM public.student_week_quota
      UNION ALL SELECT 'cnt:q163_ledger', count(*)::text FROM public.student_week_question_ledger
    ) cur
  ) d;
  IF bad <> 0 THEN RAISE EXCEPTION 'FINAL_165: motor/arsiv snapshot farki % — beklenmedik degisim.', bad; END IF;

  -- 8f) Boş doğuş: 165 tabloları boş doğmalı (163 arşivi boştu: GUARD doğruladı)
  SELECT (SELECT count(*) FROM public.student_week_subject_quota)
       + (SELECT count(*) FROM public.student_week_subject_question_ledger)
       + (SELECT count(*) FROM public.student_week_subject_quota_events) INTO bad;
  IF bad <> 0 THEN RAISE EXCEPTION 'FINAL_165: 165 tablolari bos dogmadi.'; END IF;

  -- 8g) 163/164 katmanı duruyor (arşiv tabloları + 162 plan nesneleri)
  IF to_regclass('public.student_week_quota') IS NULL
     OR to_regclass('public.vault_plan_versions') IS NULL THEN
    RAISE EXCEPTION 'FINAL_165: 163/162 arsiv katmani eksik.';
  END IF;

  RAISE NOTICE 'FINAL_165 OK: bos dogus + ders bazli 40/200 kapilari + tetik devralimi + RLS/ACL + motor anitkorumasi saglam';
END $final$;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
SELECT '165', '165_subject_weekly_quota', NULL
WHERE NOT EXISTS (
  SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '165'
);

COMMIT;
