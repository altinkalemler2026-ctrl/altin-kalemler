-- ============================================================================
-- rollback_165.sql — AK-QUOTA-SUBJECT-01: 165 GERİ ALMA PLANI (taslak)
-- ============================================================================
-- Bu betik YALNIZ yerel/QA doğrulaması için yazılmıştır; canlıda çalıştırılması
-- ayrı kullanıcı onayı gerektirir. 165 migration dosyasina dokunulmaz.
--
-- Geri alma semantigi:
--   1) 165 motor tetikleri kaldirilir; 163 motor tetikleri 163 dosyasindaki
--      TANIMLARLA BIREBIR yeniden baglanir (_q163_* fonksiyon gvdeleri
--      hicbir zaman silinmedi — 165 yalniz tetikleri devralmisti).
--   2) weekly_quota_status() orijinal 163 govdesiyle geri yuklenir
--      (CREATE OR REPLACE; ACL imzasiz degismez, 163 §7 grant'lari aynen gecerli).
--   3) 165 tablolari + _q165_* fonksiyonlari + weekly_quota_status_per_subject()
--      DURDURULMUS nesneler olarak kalir (denetim izi; bos domain'de zararsiz).
--      Kaldirilmasi istenirse aşağıdaki OPCIONAL blok açilir.
--   4) supabase_migrations kaydi (version='165') silinir — migration
--      uygulamasinin geri alindiginin kanonik işareti.
--
-- Kanit: bu betik QA'da calistirildiktan sonra 163 kuresel kapisi tekrar
-- ateşlenir (competition_players INSERT → student_week_quota +1) ve
-- weekly_quota_status() jsonb dondurur.
--
-- VERI KAPISI (KULLANICI KARARI 2026-11-16, AK-QUOTA-SUBJECT-01):
--   165 tablolarda GERCEK ders bazli kota kaydi varken otomatik geri alma
--   YASAKTIR. Sebep: 163 kuresel sayaclari 165 harcamalarini bilmez; geri
--   alinca ogrenciler ayni haftada tekrar 40/200 hakkina kavusur (cifte
--   harcama / yanlis kota hesabi). Bu betik kayitli veri gorurse abort
--   eder. Gecis yalniz planli kararla: (a) haftanin dolmasini beklemek
--   (once) veya (b) kayitlarin kayipsiz arsiv + donusum karari +
--   'aqs01.rollback_force' = 'KANITSIZ-GERI-ALMA-YASAK' bayragi.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ------------------------------------------------------------
-- 0) VERI KAPISI — kayitli kota harcamasi varsa abort
-- ------------------------------------------------------------
DO $vgate$
DECLARE
  v_rows bigint;
  v_force text := current_setting('aqs01.rollback_force', true);
BEGIN
  SELECT (SELECT count(*) FROM public.student_week_subject_quota)
       + (SELECT count(*) FROM public.student_week_subject_question_ledger)
       + (SELECT count(*) FROM public.student_week_subject_quota_events)
    INTO v_rows;
  IF v_rows > 0 AND coalesce(v_force, '') <> 'KANITSIZ-GERI-ALMA-YASAK' THEN
    RAISE EXCEPTION
      'ROLLBACK_165_VERI_KAPISI: ders bazli kota tablolarinda % kayit var — '
      'otomatik geri alma YASAK (kotada hak kaybi/yanlis hesap riski). '
      'Planli gecis gerekli: hafta dolumu veya kayipsiz arsiv+donusum karari '
      '+ acik force bayragi (aqs01.rollback_force).', v_rows
      USING errcode = 'P0001';
  END IF;
END $vgate$;

-- ------------------------------------------------------------
-- 1) TETİK DEVRİ: 165 baglari kaldir, 163 baglari geri konur
-- ------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_sqsq_comp_players ON public.competition_players;
DROP TRIGGER IF EXISTS trg_sqsq_comp_questions ON public.competition_questions;
DROP TRIGGER IF EXISTS trg_sqsq_comp_finalize ON public.competitions;

-- 163 dosyasi §5'ten BIREBIR (satir 480-495):
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

-- ------------------------------------------------------------
-- 2) weekly_quota_status() — 163 §6 govdesi BIREBIR geri
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.weekly_quota_status()
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

-- ------------------------------------------------------------
-- 3) Migration kaydi: 165 geri alindi isareti
-- ------------------------------------------------------------
DELETE FROM supabase_migrations.schema_migrations WHERE version = '165';

-- ------------------------------------------------------------
-- 4) DOGRULAMA — 163 kuresel kapisi tekrar canli
-- ------------------------------------------------------------
DO $rcheck$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_trigger
   WHERE tgname IN ('trg_sqw_comp_players','trg_sqw_comp_questions',
                    'trg_sqw_comp_finalize','trg_sqwe_append_only')
     AND NOT tgisinternal;
  IF n <> 4 THEN
    RAISE EXCEPTION 'ROLLBACK_165: 163 tetikleri % != 4', n;
  END IF;

  SELECT count(*) INTO n FROM pg_trigger
   WHERE tgname IN ('trg_sqsq_comp_players','trg_sqsq_comp_questions',
                    'trg_sqsq_comp_finalize')
     AND NOT tgisinternal;
  IF n <> 0 THEN
    RAISE EXCEPTION 'ROLLBACK_165: 165 motor tetikleri hala bagli.';
  END IF;

  IF (SELECT count(*) FROM pg_proc WHERE proname = 'weekly_quota_status'
        AND pronargs = 0
        AND prosrc NOT LIKE '%KOTA_165_DEPRECATED%') <> 1 THEN
    RAISE EXCEPTION 'ROLLBACK_165: weekly_quota_status orijinal govdeye donmedi.';
  END IF;

  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '165') THEN
    RAISE EXCEPTION 'ROLLBACK_165: 165 history kaydi duruyor.';
  END IF;

  RAISE NOTICE 'ROLLBACK_165 OK: 163 kapilari geri takildi, deprecated RPC orijinal, 165 arsivi duruyor';
END $rcheck$;

COMMIT;

-- ------------------------------------------------------------
-- OPCIONAL (varsayilan KAPALI): 165 nesnelerini tamamen kaldirma.
-- Denetim izi kayb olacagindan yalniz QA temizliginde kullanilir.
-- ------------------------------------------------------------
-- BEGIN;
-- DROP FUNCTION IF EXISTS public.weekly_quota_status_per_subject();
-- DROP FUNCTION IF EXISTS public._q165_period();
-- DROP FUNCTION IF EXISTS public._q165_subject_of(uuid);
-- DROP FUNCTION IF EXISTS public._q165_lock(uuid,text,integer,uuid);
-- DROP FUNCTION IF EXISTS public._q165_reserve_competition(uuid,uuid);
-- DROP FUNCTION IF EXISTS public._q165_reserve_questions(uuid,uuid);
-- DROP FUNCTION IF EXISTS public._q165_trg_comp_players();
-- DROP FUNCTION IF EXISTS public._q165_trg_comp_questions();
-- DROP FUNCTION IF EXISTS public._q165_trg_comp_finalize();
-- DROP TRIGGER IF EXISTS trg_sqse_append_only ON public.student_week_subject_quota_events;
-- DROP FUNCTION IF EXISTS public._q165_trg_events_append_only();
-- DROP TABLE IF EXISTS public.student_week_subject_quota_events;
-- DROP TABLE IF EXISTS public.student_week_subject_question_ledger;
-- DROP TABLE IF EXISTS public.student_week_subject_quota;
-- COMMIT;
