-- ============================================================================
-- 163_weekly_student_quota.sql — AK-MEB-VAULT-42: HAFTALIK ÖĞRENCİ KOTASI
-- ============================================================================
-- 42-17 uyarması: GUARD_163 taban kontrolü set-biçimine çevrildi
--   (v_max NOT IN (162, 164)); dosyanın geri kalanı 42-16 ile birebir.
--   Gerekçe + kanıt: docs/reports/ak-vault-vis-04-migration-siralama-guvenligi.md
--
-- Ürün kuralları (görev 42-16):
--   * Öğrenci başına haftada en fazla 40 yarışma.
--   * Yarışma başına 5 soru (motor sabiti; burada değişmez).
--   * Haftada en fazla 200 YENİ (öğrencinin daha önce hiç görmediği) soru.
--   * Kota DERS/SINIF/ZORLUK GÖZETMEZ — öğrenci + akademik yıl + hafta ortak.
--   * Ders/seviye değiştirmek kotayı yenilemez (anahtarda ders/seviye YOKTUR).
--
-- MİMARİ: EKLENTİ (additive) kota katmanı. Mevcut yarışma/puanlama motoru
-- (join_matchmaking_queue, prepare_competition_pack, finalize_competition_if_ready,
--  021/022/023 akışı) YENİDEN TANIMLANMAZ. Kota, motorun kendi yazma noktalarına
-- STATEMENT tetikleri ile bağlanır ve motorun atomik transaction sözleşmesini
-- (082: match + prepare tek işlem) kullanır:
--   1) competition_players INSERT    → yarışma rezervasyonu (+1; 40 ise KOTA_163)
--   2) competition_questions INSERT  → yeni soru rezervasyonu (gösterilen sorular;
--      200 aşımı KOTA_163). HOOK NOTU: student_pack_exposures yazımı
--      "ON CONFLICT DO NOTHING" olduğu için tetiği ATLANABİLİR (B-yedek yolu aynı
--      kasayı ikinci kez kullanabilir); bu yüzden tek doğru yazım noktası
--      competition_questions snapshot'ıdır (077 son yazım noktası).
--   3) competitions.status kesinleşmesi → denetim olayı (refund YOK — GAP-163-A)
-- Rezervasyon motorun kendi atomik rollback'i ile geri alınır: kota aşımı
-- yarışmanın OLUŞMASINI engeller (kota yarım yarışma bırakmaz).
--
-- GÖRÜLMÜŞ SORU: new = gösterilen soru AND bu hafta ledger'da yok AND
-- exposure kaydı YOK ya da ilk gösterimi bu yarışmanın creation'ından ÖNCE
-- DEĞİL (aynı transaction'ın now() değeri created_at'a eşittir → motorun bu
-- prepare içinde yazdığı exposure'lar "önceden görülmüş" sayılmaz; önceki
-- commit'lerin now() değeri kesinlikle daha eskidir). Görüntülenen soru DERS/
-- HAFTA/SINIF/SORU KASASI FARKETMEKSIZIN görülmüş sayılır (exposure tablosu
-- bağlamdan bağımsız). Motorun exposure anti-join'i (077) seçim katmanında
-- zaten çalışır; bu katman SAYIM doğruluğunu garanti eder (exposure = gösterim
-- olayı; competition_answers = cevap olayı — ayrı).
--
-- EŞZAMANLILIK: kullanıcı+hafta başına pg_advisory_xact_lock; kilitler her
-- statement tetiğinde user_id SIRALI alınır → kilit döngüsü (deadlock) yok.
-- Çift tıklama: 082 zaten idempotent 'waiting' geri dönüşü verir (kota değişmez).
--
-- 063/068/077 MEVCUT DAVRANIŞLARI KORUNUR: subject-bazlı 500 sayacı ve clamp'i
-- aynen durur; 163 üstüne global-200 sert kapısını ekler (GAP-163-B).
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ============================================================
-- 0) GUARD_163 — taban + kalıntı + motor anıtkoruma snapshot'ı
-- ============================================================
DO $guard$
DECLARE
  v_max int;
BEGIN
  SELECT max(version::int) INTO v_max
    FROM supabase_migrations.schema_migrations;

  -- 42-17 / VIS-04 §6 kanıtı: SET BİÇİMİ. Canlı yolu 164 uygulanmış tabana
  -- (max=164) out-of-order 163; CI dosya sırası 163'ü max=162 iken uygular.
  -- Diğer her taban (<=161, >=165, NULL) fail-closed abort etmeye devam eder.
  IF v_max IS NULL OR v_max NOT IN (162, 164) THEN
    RAISE EXCEPTION 'GUARD_163: taban migration 162 ya da 164 degil (max=%).', v_max;
  END IF;

  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
              WHERE version = '163') THEN
    RAISE EXCEPTION 'GUARD_163: 163 kaydi zaten var — yeniden uygulama GUARD disi.';
  END IF;

  IF (SELECT count(*) FROM supabase_migrations.schema_migrations
       WHERE version::int BETWEEN 158 AND 162) <> 5 THEN
    RAISE EXCEPTION 'GUARD_163: 158-162 zinciri eksik.';
  END IF;

  -- 163 kalıntısı olmamalı (fail-closed; klasik replay değil)
  IF to_regclass('public.student_week_quota') IS NOT NULL
     OR to_regclass('public.student_week_question_ledger') IS NOT NULL
     OR to_regclass('public.student_week_quota_events') IS NOT NULL THEN
    RAISE EXCEPTION 'GUARD_163: 163 tablo kalintisi var — elle incele.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname LIKE '_q163%'
             OR proname = 'weekly_quota_status') THEN
    RAISE EXCEPTION 'GUARD_163: 163 fonksiyon kalintisi var — elle incele.';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
              JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public' AND NOT t.tgisinternal
               AND t.tgname IN ('trg_sqw_comp_players','trg_sqw_comp_questions',
                                'trg_sqw_comp_finalize','trg_sqwe_append_only')) THEN
    RAISE EXCEPTION 'GUARD_163: 163 tetik kalintisi var — elle incele.';
  END IF;

  -- Motor önkoşulları (163 bunların üstüne tetik bağlar)
  IF to_regclass('public.student_weekly_counters') IS NULL
     OR to_regclass('public.student_question_exposures') IS NULL
     OR to_regclass('public.student_pack_exposures') IS NULL
     OR to_regclass('public.competitions') IS NULL
     OR to_regclass('public.competition_players') IS NULL
     OR to_regclass('public.matchmaking_queue') IS NULL THEN
    RAISE EXCEPTION 'GUARD_163: motor onkosul tablosu yok (062/063/019).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'join_matchmaking_queue'
                 AND pronargs = 1 AND proargtypes::text LIKE '%2950%')
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'prepare_competition_pack')
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'resolve_current_academic_period') THEN
    RAISE EXCEPTION 'GUARD_163: motor RPC/period fonksiyonu bulunamadi.';
  END IF;

  -- Takvim + kasa/eşleme bantları (159/160/161 sözleşmeleri)
  IF (SELECT count(*) FROM public.academic_weeks
      WHERE academic_year = '2026-2027') < 42 THEN
    RAISE EXCEPTION 'GUARD_163: 2026-2027 takvimi eksik.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.academic_weeks
             WHERE academic_year = '2026-2027' AND week IN (10,20,21,26)
               AND instruction_week_number IS NOT NULL) THEN
    RAISE EXCEPTION 'GUARD_163: tatil haftasi I-slot tasiyor (159 matrisi bozuk).';
  END IF;
  IF EXISTS (SELECT 1 FROM public.academic_weeks
             WHERE academic_year = '2026-2027' AND week = 36 AND new_topic_allowed) THEN
    RAISE EXCEPTION 'GUARD_163: K36 kapisi bozuk.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.academic_weeks
             WHERE academic_year = '2026-2027' AND week = 42 AND activated_at IS NOT NULL) THEN
    RAISE EXCEPTION 'GUARD_163: K42 aktif olmamali (161 pasif dogus).';
  END IF;
  IF (SELECT count(*) FROM public.question_vaults WHERE vault_type = 'weekly') <> 3654
     OR (SELECT count(*) FROM public.question_vaults) <> 3690
     OR (SELECT count(*) FROM public.question_vault_topics
         WHERE legacy_topic_code IS NOT NULL) <> 13 THEN
    RAISE EXCEPTION 'GUARD_163: kasa bandi beklenmedik (3654/3690/13).';
  END IF;
  IF (SELECT count(*) FROM public.curriculum_subtopic_week_map
      WHERE academic_year = '2026-2027') <> 546
     OR (SELECT count(*) FROM public.curriculum_subtopic_week_map
         WHERE approved_at IS NOT NULL) <> 0 THEN
    RAISE EXCEPTION 'GUARD_163: 546/0-onay esleme bandi bozuk.';
  END IF;

  -- Kota tabloları boş doğacak; mevcut taban sayaçları FINAL'da karşılaştırılır.
  CREATE TEMP TABLE ak163_snap ON COMMIT DROP AS
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
                       'curriculum_subtopic_week_state')
  UNION ALL SELECT 'cnt:competitions', count(*)::text FROM public.competitions
  UNION ALL SELECT 'cnt:competition_players', count(*)::text FROM public.competition_players
  UNION ALL SELECT 'cnt:matchmaking_queue', count(*)::text FROM public.matchmaking_queue
  UNION ALL SELECT 'cnt:counters', count(*)::text FROM public.student_weekly_counters
  UNION ALL SELECT 'cnt:exp_q', count(*)::text FROM public.student_question_exposures
  UNION ALL SELECT 'cnt:exp_p', count(*)::text FROM public.student_pack_exposures
  UNION ALL SELECT 'cnt:vaults_weekly', count(*)::text FROM public.question_vaults WHERE vault_type = 'weekly'
  UNION ALL SELECT 'cnt:map', count(*)::text FROM public.curriculum_subtopic_week_map WHERE academic_year = '2026-2027';
END $guard$;

-- ============================================================
-- 1) HAFTALIK KOTA ANA TABLOSU (küresel — ders/seviye YOK)
-- ============================================================
CREATE TABLE public.student_week_quota (
  user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE CASCADE,
  academic_year text NOT NULL,
  week integer NOT NULL
    CHECK (week BETWEEN 0 AND 52),

  -- Yarışma rezervasyonu: yarışma OLUŞUMUNDA +1 (iptal/timeout refund etmez
  -- — GAP-163-A önerilen sözleşme). Son savunma: CHECK.
  competitions_reserved integer NOT NULL DEFAULT 0
    CHECK (competitions_reserved BETWEEN 0 AND 40),

  -- Yeni (hiç görülmemiş) soru rezervasyonu — gösterim anında, cevaptan bağımsız.
  new_questions_reserved integer NOT NULL DEFAULT 0
    CHECK (new_questions_reserved BETWEEN 0 AND 200),

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (user_id, academic_year, week)
);
COMMENT ON TABLE public.student_week_quota IS
  'Haftalik ogrenci kotasi: 40 yarisma + 200 yeni soru. Ders/sinif/zorluk ortaktir; anahtar user+yil+hafta.';

CREATE TRIGGER trg_sqw_updated_at
BEFORE UPDATE ON public.student_week_quota
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.student_week_quota ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_week_quota FORCE ROW LEVEL SECURITY;
CREATE POLICY student_reads_own_week_quota ON public.student_week_quota
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE TABLE public.student_week_question_ledger (
  user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE CASCADE,
  academic_year text NOT NULL,
  week integer NOT NULL
    CHECK (week BETWEEN 0 AND 52),
  question_id uuid NOT NULL
    REFERENCES public.questions(id) ON DELETE CASCADE,
  source_vault_id uuid
    REFERENCES public.question_vaults(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, academic_year, week, question_id)
);
COMMENT ON TABLE public.student_week_question_ledger IS
  'Haftanin BENZERSIZ yeni soru defteri (PK tekil-dogrulama; ayni soru haftada bir kez sayilir).';

CREATE INDEX idx_sqwql_vault ON public.student_week_question_ledger(source_vault_id);

ALTER TABLE public.student_week_question_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_week_question_ledger FORCE ROW LEVEL SECURITY;
CREATE POLICY student_reads_own_week_ledger ON public.student_week_question_ledger
FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- 2) EKLENMEZ DENETİM KAYDI (append-only)
-- ============================================================
CREATE TABLE public.student_week_quota_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL
    REFERENCES auth.users(id) ON DELETE CASCADE,
  academic_year text NOT NULL,
  week integer NOT NULL
    CHECK (week BETWEEN 0 AND 52),
  competition_id uuid
    REFERENCES public.competitions(id) ON DELETE SET NULL,
  event text NOT NULL
    CHECK (event IN ('competition_reserved','questions_reserved',
                     'questions_refunded','competition_finalized')),
  delta integer NOT NULL DEFAULT 0,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.student_week_quota_events IS
  'Kota yasami icin eklenmez denetim: rezervasyon + kesinlesme olaylari. Refund varsayilan YOK (GAP-163-A).';

CREATE INDEX idx_sqwe_user_week ON public.student_week_quota_events
  (user_id, academic_year, week);
CREATE INDEX idx_sqwe_competition ON public.student_week_quota_events
  (competition_id);

ALTER TABLE public.student_week_quota_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_week_quota_events FORCE ROW LEVEL SECURITY;
CREATE POLICY student_reads_own_week_events ON public.student_week_quota_events
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE FUNCTION public._q163_trg_events_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  RAISE EXCEPTION 'KOTA_163: kota denetim kaydi eklenmez (append-only).';
END $fn$;

CREATE TRIGGER trg_sqwe_append_only
BEFORE UPDATE OR DELETE ON public.student_week_quota_events
FOR EACH ROW EXECUTE FUNCTION public._q163_trg_events_append_only();

-- ============================================================
-- 3) İÇ İŞLEVLER (istemciye tam kapalı)
-- ============================================================

-- Dönem çözümleyici: motorla AYNI kaynak (fail-closed; 068 sözleşmesi).
CREATE FUNCTION public._q163_period()
RETURNS TABLE (academic_year text, week integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  RETURN QUERY SELECT * FROM public.resolve_current_academic_period();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'KOTA_163: gecerli akademik donem yok; kota fail-closed.';
  END IF;
END $fn$;

CREATE FUNCTION public._q163_lock(p_user uuid, p_year text, p_week integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended('kq163:' || p_user::text || '|' || p_year || '|' || p_week::text, 0)
  );
END $fn$;

-- Yarışma rezervasyonu (+1). Çağıran: competition_players statement tetiği.
-- ÖNCE-KONTROL desenı: CHECK değil, anlaşılır KOTA_163 mesajı atar.
CREATE FUNCTION public._q163_reserve_competition(p_user uuid, p_comp uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE v_year text; v_week integer; v_res integer;
BEGIN
  SELECT y, w INTO v_year, v_week FROM public._q163_period() AS t(y, w);
  PERFORM public._q163_lock(p_user, v_year, v_week);

  INSERT INTO public.student_week_quota
    (user_id, academic_year, week)
  VALUES (p_user, v_year, v_week)
  ON CONFLICT (user_id, academic_year, week) DO NOTHING;

  SELECT competitions_reserved INTO v_res
    FROM public.student_week_quota
   WHERE user_id = p_user AND academic_year = v_year AND week = v_week
     FOR UPDATE;

  IF v_res >= 40 THEN
    RAISE EXCEPTION 'KOTA_163: haftalik yarisma kotasi doldu (%/40) — yeni yarisma olusamiyor.', v_res;
  END IF;

  UPDATE public.student_week_quota
     SET competitions_reserved = competitions_reserved + 1
   WHERE user_id = p_user AND academic_year = v_year AND week = v_week;

  INSERT INTO public.student_week_quota_events
    (user_id, academic_year, week, competition_id, event, delta)
  VALUES (p_user, v_year, v_week, p_comp, 'competition_reserved', 1);
END $fn$;

-- Yeni soru rezervasyonu: yarışmaya ATANAN (cq snapshot) sorulardan öğrencinin
-- bu haftada henüz defterde olmayan ve bu yarışmadan ÖNCE görmemiş olduğu
-- soruları sayar. ÇAĞIRAN: competition_questions statement tetiği (077
-- sirasi: pack exposure → soru exposure → cq snapshot; cq son yazim noktasi
-- oldugundan gosterilecek sorular burada KESIN olarak bilinir).
-- GORULMUSLUK: ayni transaction'in now() degeri competitions.created_at ile
-- birebir esittir → bu prepare'in yazdigi exposure'lar "onceden gorulmus"
-- sayilmaz; onceki commit'lerin exposure'i ise kesinlikle daha eski time-
-- stamp tasir. Ders/hafta/sinif/kasa ayrimi YOKTUR (exposure baglamsizdir).
CREATE FUNCTION public._q163_reserve_questions(p_user uuid, p_comp uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_year text; v_week integer; v_take uuid[]; v_n int; v_res integer;
  v_created timestamptz; v_vault uuid;
BEGIN
  SELECT c.created_at,
         (c.configuration -> 'faz2_pack' ->> 'vault_id')::uuid
    INTO v_created, v_vault
    FROM public.competitions c
   WHERE c.id = p_comp;
  IF v_created IS NULL THEN
    RETURN;                                    -- yarışma satırı yok: rezervasyon yok
  END IF;

  SELECT y, w INTO v_year, v_week FROM public._q163_period() AS t(y, w);
  PERFORM public._q163_lock(p_user, v_year, v_week);

  SELECT coalesce(array_agg(u.question_id ORDER BY u.question_id), '{}'::uuid[])
    INTO v_take
  FROM (
    SELECT DISTINCT cq.question_id
      FROM public.competition_questions cq
     WHERE cq.competition_id = p_comp
       AND NOT EXISTS (                       -- bu haftada zaten defterde
         SELECT 1 FROM public.student_week_question_ledger l
          WHERE l.user_id = p_user AND l.academic_year = v_year
            AND l.week = v_week AND l.question_id = cq.question_id)
       AND NOT EXISTS (                       -- bu yarismadan ONCE gorulmus
         SELECT 1 FROM public.student_question_exposures e
          WHERE e.user_id = p_user AND e.question_id = cq.question_id
            AND e.first_exposed_at < v_created)
  ) u;

  v_n := coalesce(array_length(v_take, 1), 0);
  IF v_n = 0 THEN
    RETURN;                                    -- tekrar paketi: yeni soru tuketmez
  END IF;

  INSERT INTO public.student_week_quota
    (user_id, academic_year, week)
  VALUES (p_user, v_year, v_week)
  ON CONFLICT (user_id, academic_year, week) DO NOTHING;

  SELECT new_questions_reserved INTO v_res
    FROM public.student_week_quota
   WHERE user_id = p_user AND academic_year = v_year AND week = v_week
     FOR UPDATE;

  IF v_res + v_n > 200 THEN
    RAISE EXCEPTION 'KOTA_163: haftalik yeni soru kotasi asilirdi (%+%>200) — paket dagitilamiyor.', v_res, v_n;
  END IF;

  UPDATE public.student_week_quota
     SET new_questions_reserved = new_questions_reserved + v_n
   WHERE user_id = p_user AND academic_year = v_year AND week = v_week;

  INSERT INTO public.student_week_question_ledger
    (user_id, academic_year, week, question_id, source_vault_id)
  SELECT p_user, v_year, v_week, u, v_vault FROM unnest(v_take) AS u
  ON CONFLICT DO NOTHING;

  INSERT INTO public.student_week_quota_events
    (user_id, academic_year, week, competition_id, event, delta, detail)
  VALUES (p_user, v_year, v_week, p_comp, 'questions_reserved', v_n,
          jsonb_build_object('vault_id', v_vault));
END $fn$;

-- ============================================================
-- 4) TETİK FONKSİYONLARI (motor tablolarına EKLENTİ — gövdeler değişmez)
-- ============================================================

-- 4a) Yarışma oluşumu: her yeni oyuncu satırı = 1 kota rezervasyonu.
CREATE FUNCTION public._q163_trg_comp_players()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE r record;
BEGIN
  -- Kilit siralamasi deterministik (deadlock yasağı): user,comp sirali.
  FOR r IN
    SELECT DISTINCT nr.user_id, nr.competition_id
      FROM new_rows nr ORDER BY nr.user_id, nr.competition_id
  LOOP
    PERFORM public._q163_reserve_competition(r.user_id, r.competition_id);
  END LOOP;
  RETURN NULL;
END $fn$;

-- 4b) Soru ataması (cq snapshot): gösterilen sorular = kota tüketimi.
CREATE FUNCTION public._q163_trg_comp_questions()
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
    PERFORM public._q163_reserve_questions(r.user_id, r.competition_id);
  END LOOP;
  RETURN NULL;
END $fn$;

-- 4c) Kesinleşme: completed/cancelled/abandoned → denetim olayı (refund YOK).
-- Denetim en-iyi-çaba: hafta önce bu yarışmanın competition_reserved olayından
-- okunur; yoksa güncel dönem denenir; dönem de yoksa olay ATLANIR — motorun
-- kesinleştirme akışı ASLA bloklanmaz (audit kota kapısı değildir).
CREATE FUNCTION public._q163_trg_comp_finalize()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  r record; v_year text; v_week integer;
BEGIN
  SELECT e.academic_year, e.week INTO v_year, v_week
    FROM public.student_week_quota_events e
   WHERE e.competition_id = NEW.id AND e.event = 'competition_reserved'
   ORDER BY e.created_at LIMIT 1;

  IF v_year IS NULL THEN
    BEGIN
      SELECT y, w INTO v_year, v_week FROM public._q163_period() AS t(y, w);
    EXCEPTION WHEN raise_exception THEN
      RETURN NULL;   -- donem disi kesinelesme: denetim yazilamaz, motor engellenmez
    END;
  END IF;

  FOR r IN
    SELECT cp.user_id FROM public.competition_players cp
     WHERE cp.competition_id = NEW.id ORDER BY cp.user_id
  LOOP
    PERFORM public._q163_lock(r.user_id, v_year, v_week);
    INSERT INTO public.student_week_quota_events
      (user_id, academic_year, week, competition_id, event, delta, detail)
    VALUES (r.user_id, v_year, v_week, NEW.id, 'competition_finalized', 0,
            jsonb_build_object('old_status', OLD.status, 'new_status', NEW.status));
  END LOOP;
  RETURN NULL;
END $fn$;

-- ============================================================
-- 5) TETİK BAĞLARI
-- ============================================================
CREATE TRIGGER trg_sqw_comp_players
AFTER INSERT ON public.competition_players
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION public._q163_trg_comp_players();

CREATE TRIGGER trg_sqw_comp_questions
AFTER INSERT ON public.competition_questions
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION public._q163_trg_comp_questions();

CREATE TRIGGER trg_sqw_comp_finalize
AFTER UPDATE OF status ON public.competitions
FOR EACH ROW
WHEN (NEW.status IS DISTINCT FROM OLD.status
      AND NEW.status IN ('completed','cancelled','abandoned'))
EXECUTE FUNCTION public._q163_trg_comp_finalize();

-- ============================================================
-- 6) ÖĞRENCİ OKUMA ARAYÜZÜ (yalnız kendi kotası)
-- ============================================================
CREATE FUNCTION public.weekly_quota_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_user uuid; v_year text; v_week integer;
  q public.student_week_quota%rowtype;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'YETKI_163: kimlik dogrulamasi gerekli.'
      USING errcode = '42501';
  END IF;
  SELECT r.academic_year, r.week INTO v_year, v_week
    FROM public.resolve_current_academic_period() AS r;
  IF v_year IS NULL THEN
    RETURN jsonb_build_object(
      'academic_year', NULL, 'week', NULL,
      'competitions_used', 0, 'competitions_limit', 40,
      'new_questions_used', 0, 'new_questions_limit', 200,
      'note', 'gecerli akademik donem yok');
  END IF;
  SELECT * INTO q FROM public.student_week_quota
   WHERE user_id = v_user AND academic_year = v_year AND week = v_week;
  RETURN jsonb_build_object(
    'academic_year', v_year, 'week', v_week,
    'competitions_used', coalesce(q.competitions_reserved, 0), 'competitions_limit', 40,
    'new_questions_used', coalesce(q.new_questions_reserved, 0), 'new_questions_limit', 200,
    'updated_at', q.updated_at);
END $fn$;

-- ============================================================
-- 7) İZİN MATRİSİ
-- ============================================================
-- Tablolar: istemci yalnız SELECT (kendi satırı, RLS); servis tam yetkili.
REVOKE ALL ON public.student_week_quota,
             public.student_week_question_ledger,
             public.student_week_quota_events
  FROM anon, authenticated;
GRANT SELECT ON public.student_week_quota,
               public.student_week_question_ledger,
               public.student_week_quota_events
  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.student_week_quota,
                                       public.student_week_question_ledger
  TO service_role;
GRANT SELECT, INSERT ON public.student_week_quota_events TO service_role;

-- RPC: öğrenci kendi durumunu görür.
REVOKE ALL ON FUNCTION public.weekly_quota_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.weekly_quota_status() TO authenticated, service_role;

-- İç işlevler + tetik fonksiyonları: istemciye TAM kapalı.
DO $grants$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    '_q163_period()', '_q163_lock(uuid,text,integer)',
    '_q163_reserve_competition(uuid,uuid)', '_q163_reserve_questions(uuid,uuid)',
    '_q163_trg_comp_players()', '_q163_trg_comp_questions()', '_q163_trg_comp_finalize()',
    '_q163_trg_events_append_only()'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon, authenticated', f);
  END LOOP;
END $grants$;

-- ============================================================
-- 8) FINAL_163 — yapısal + anıtkoruma kanıtları
-- ============================================================
DO $final$
DECLARE
  n int; bad int; v_u uuid;
BEGIN
  -- 8a) Nesne doğumu
  SELECT count(*) INTO n FROM pg_class
   WHERE relname IN ('student_week_quota','student_week_question_ledger','student_week_quota_events')
     AND relkind = 'r';
  IF n <> 3 THEN RAISE EXCEPTION 'FINAL_163: tablo sayisi % != 3', n; END IF;

  SELECT count(*) INTO n FROM pg_policies
   WHERE tablename IN ('student_week_quota','student_week_question_ledger','student_week_quota_events');
  IF n <> 3 THEN RAISE EXCEPTION 'FINAL_163: politika sayisi % != 3', n; END IF;

  SELECT count(*) INTO n FROM pg_class
   WHERE relname IN ('student_week_quota','student_week_question_ledger','student_week_quota_events')
     AND relrowsecurity AND relforcerowsecurity;
  IF n <> 3 THEN RAISE EXCEPTION 'FINAL_163: RLS/FORCE eksik.'; END IF;

  -- CHECK son savunma hattı yerinde mi (40/200/hafta aralıkları)
  SELECT count(*) INTO n FROM pg_constraint
   WHERE conrelid = 'public.student_week_quota'::regclass AND contype = 'c';
  IF n <> 3 THEN RAISE EXCEPTION 'FINAL_163: kota CHECK sayisi % != 3', n; END IF;

  -- 8b) Tetik bağları (motor tablolarında 3 + events append-only 1)
  SELECT count(*) INTO n FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
   WHERE t.tgname IN ('trg_sqw_comp_players','trg_sqw_comp_questions',
                      'trg_sqw_comp_finalize','trg_sqwe_append_only')
     AND NOT t.tgisinternal;
  IF n <> 4 THEN RAISE EXCEPTION 'FINAL_163: kota tetikleri % != 4', n; END IF;

  -- 8c) ACL: istemci yazamaz; RPC açık; iç işlevler kapalı
  SELECT count(*) INTO bad FROM (VALUES ('anon'),('authenticated')) AS r(rol)
   CROSS JOIN (VALUES ('student_week_quota'),('student_week_question_ledger'),
                      ('student_week_quota_events')) AS c(rel)
   WHERE has_table_privilege(r.rol, 'public.' || c.rel, 'INSERT')
      OR has_table_privilege(r.rol, 'public.' || c.rel, 'UPDATE')
      OR has_table_privilege(r.rol, 'public.' || c.rel, 'DELETE');
  IF bad <> 0 THEN RAISE EXCEPTION 'FINAL_163: istemci yazma yetkisi var.'; END IF;

  IF NOT has_function_privilege('authenticated','public.weekly_quota_status()','EXECUTE')
     OR has_function_privilege('anon','public.weekly_quota_status()','EXECUTE') THEN
    RAISE EXCEPTION 'FINAL_163: weekly_quota_status ACL bozuk.';
  END IF;

  SELECT count(*) INTO bad FROM pg_proc
   WHERE proname LIKE '_q163%'
     AND has_function_privilege('authenticated', oid, 'EXECUTE');
  IF bad <> 0 THEN RAISE EXCEPTION 'FINAL_163: ic islevler acik.'; END IF;

  -- 8d) CHECK son savunma hattı canlı probe: 41/201 reddedilmeli (probe geri alınır)
  SELECT id INTO v_u FROM auth.users ORDER BY id LIMIT 1;
  IF v_u IS NOT NULL THEN
    BEGIN
      INSERT INTO public.student_week_quota (user_id, academic_year, week, competitions_reserved)
      VALUES (v_u, '2026-2027', 1, 41);
      RAISE EXCEPTION 'FINAL_163: 41 yarisma CHECK kirmadi.';
    EXCEPTION
      WHEN check_violation THEN NULL;
      WHEN raise_exception THEN RAISE;
    END;
    BEGIN
      INSERT INTO public.student_week_quota (user_id, academic_year, week, new_questions_reserved)
      VALUES (v_u, '2026-2027', 1, 201);
      RAISE EXCEPTION 'FINAL_163: 201 soru CHECK kirmadi.';
    EXCEPTION
      WHEN check_violation THEN NULL;
      WHEN raise_exception THEN RAISE;
    END;
  ELSE
    RAISE NOTICE 'FINAL_163: auth.users bos — CHECK canli probe atlandi (katalog kontrolu yapildi).';
  END IF;

  -- 8e) Motor anıtkoruma: GUARD snapshot'ı ile birebir (geçici tablo pg_temp'te)
  -- NOT: EXCEPT/UNION ALL sol-eşleşmelidir; yenileme kümesi ALT SORGU ile
  -- sarılmalı, yoksa sayaç satırları farka karışır (yanlış pozitif).
  SELECT count(*) INTO bad FROM (
    SELECT k, v FROM ak163_snap
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
                           'curriculum_subtopic_week_state')
      UNION ALL SELECT 'cnt:competitions', count(*)::text FROM public.competitions
      UNION ALL SELECT 'cnt:competition_players', count(*)::text FROM public.competition_players
      UNION ALL SELECT 'cnt:matchmaking_queue', count(*)::text FROM public.matchmaking_queue
      UNION ALL SELECT 'cnt:counters', count(*)::text FROM public.student_weekly_counters
      UNION ALL SELECT 'cnt:exp_q', count(*)::text FROM public.student_question_exposures
      UNION ALL SELECT 'cnt:exp_p', count(*)::text FROM public.student_pack_exposures
      UNION ALL SELECT 'cnt:vaults_weekly', count(*)::text FROM public.question_vaults WHERE vault_type = 'weekly'
      UNION ALL SELECT 'cnt:map', count(*)::text FROM public.curriculum_subtopic_week_map WHERE academic_year = '2026-2027'
    ) cur
  ) d;
  IF bad <> 0 THEN RAISE EXCEPTION 'FINAL_163: motor/anit snapshot farki % — beklenmedik degisim.', bad; END IF;

  -- 8f) Boş doğuş: kota tabloları boş doğmalı
  SELECT (SELECT count(*) FROM public.student_week_quota)
       + (SELECT count(*) FROM public.student_week_question_ledger)
       + (SELECT count(*) FROM public.student_week_quota_events) INTO bad;
  IF bad <> 0 THEN RAISE EXCEPTION 'FINAL_163: kota tablolari bos dogmadi.'; END IF;

  -- 8g) 162 katmanı duruyor (plan nesneleri)
  IF to_regclass('public.vault_plan_versions') IS NULL
     OR to_regclass('public.vault_plan_recalc_queue') IS NULL THEN
    RAISE EXCEPTION 'FINAL_163: 162 plan katmani eksik.';
  END IF;

  RAISE NOTICE 'FINAL_163 OK: bos dogus + 40/200 kapilari + tetik/RLS + ACL + motor anitkorumasi saglam';
END $final$;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
SELECT '163', '163_weekly_student_quota', NULL
WHERE NOT EXISTS (
  SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '163'
);

COMMIT;
