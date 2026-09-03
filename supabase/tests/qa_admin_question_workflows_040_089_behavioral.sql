-- ============================================================
-- QA: Altın Kalemler — 040/089 DAVRANIŞSAL DB SÖZLEŞME TESTİ
--
-- Kapsam (gerçek transaction + JWT claim + izin kayıtları ile):
--   A. admin_question_edit (089): kimlik/izin matrisi, alan
--      mutasyonu, audit satırı doğruluğu, başarısız işlem
--      yan etkisizliği ve mutation+audit ATOMİKLİĞİ.
--   B. admin_audit_log RLS (089): rol matrisi + fail-closed.
--   C. Aktivasyon (040): readiness blokerleri, izin matrisi
--      (questions.approve / ai.manage), publication event.
--   D. Deaktivasyon (040): zorunlu sebep, izin matrisi,
--      publication event, idempotency.
--
-- Desen: supabase/tests/qa_phase4b_schema_and_grants_091.sql
-- Çalıştırma (disposable QA DB, localhost only):
--   docker cp <bu dosya> <container>:/tmp/qa_behavioral.sql
--   docker exec <container> psql -U supabase_admin -d postgres \
--     -f /tmp/qa_behavioral.sql
--
-- Tek transaction; sonunda ROLLBACK -> tamamen tekrar
-- çalıştırılabilir, kalıcı veri BIRAKMAZ. Fixture UUID'leri
-- deterministik sabitlerdir.
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- ============================================================
-- 0. SONUÇ TABLOSU + DETERMİNİSTİK FİXTURE'LAR
-- ============================================================

CREATE TEMP TABLE qa_results (
  test_id text PRIMARY KEY,
  result  text NOT NULL
);

GRANT INSERT, SELECT ON qa_results TO authenticated, anon;

-- --- Fixture kullanıcıları (auth.users) ---------------------
INSERT INTO auth.users (id, email) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-0000000000a1', 'qa-super@example.invalid'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-0000000000a2', 'qa-content@example.invalid'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-0000000000a3', 'qa-copyright@example.invalid'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-0000000000a4', 'qa-plain@example.invalid'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-0000000000a5', 'qa-qreview@example.invalid'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-0000000000a6', 'qa-aimgr@example.invalid'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-0000000000a7', 'qa-atomic@example.invalid');

-- --- Rol atamaları -------------------------------------------
-- super_admin: tüm izinler (013)
INSERT INTO public.admin_user_roles (user_id, role_id)
SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a1', ar.id
FROM public.admin_roles ar WHERE ar.role_code = 'super_admin';

-- content_admin: questions.edit + questions.approve var
INSERT INTO public.admin_user_roles (user_id, role_id)
SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a2', ar.id
FROM public.admin_roles ar WHERE ar.role_code = 'content_admin';

-- copyright_reviewer: questions.edit / approve / ai.manage / audit.view YOK
INSERT INTO public.admin_user_roles (user_id, role_id)
SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a3', ar.id
FROM public.admin_roles ar WHERE ar.role_code = 'copyright_reviewer';

-- question_reviewer: yalnız questions.approve (questions.edit / ai.manage YOK)
INSERT INTO public.admin_user_roles (user_id, role_id)
SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a5', ar.id
FROM public.admin_roles ar WHERE ar.role_code = 'question_reviewer';

-- content_admin (atomiklik testi için ikinci edit yetkilisi)
INSERT INTO public.admin_user_roles (user_id, role_id)
SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a7', ar.id
FROM public.admin_roles ar WHERE ar.role_code = 'content_admin';

-- Yalnız ai.manage izni olan geçici QA rolü (C6 için)
INSERT INTO public.admin_roles (role_code, name, description, is_active)
VALUES ('qa_ai_manager_only', 'QA AI Manager Only',
        'Behavioral test: sadece ai.manage', true);

INSERT INTO public.admin_role_permissions (role_id, permission_id)
SELECT ar.id, ap.id
FROM public.admin_roles ar
JOIN public.admin_permissions ap ON ap.permission_code = 'ai.manage'
WHERE ar.role_code = 'qa_ai_manager_only';

INSERT INTO public.admin_user_roles (user_id, role_id)
SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a6', ar.id
FROM public.admin_roles ar WHERE ar.role_code = 'qa_ai_manager_only';

-- a4 (plain) ve a3'e bilinçli olarak rol atanmaz/az atanır.

-- --- Test subject --------------------------------------------
INSERT INTO public.subjects (name, slug)
VALUES ('QA Behavior Subject 040089', 'qa-behavior-subject-040089')
RETURNING id AS qa_subject_id \gset

-- --- Test soruları -------------------------------------------
-- q101: edit testi sorusu (approved, pasif)
INSERT INTO public.questions (
  id, question_code, grade_level, subject_id, question_text,
  option_a, option_b, option_c, option_d, correct_answer,
  difficulty, quality_level, estimated_solve_time_seconds,
  approval_status, is_active, ownership_status, license_status,
  commercial_use_allowed, has_visual
) VALUES (
  'aaaaaaaa-bbbb-4aaa-8aaa-000000000101', 'QA-040089-EDIT-0001',
  5, :'qa_subject_id', 'Original edit text',
  'opt a', 'opt b', 'opt c', 'opt d', 'A',
  'medium', 'medium', 90,
  'approved', false, 'owned', 'unknown', false, false
);

-- q102: READY soru (C4/C5/C8/D testleri)
-- q103: READY soru 2 (C6, ai.manage-only)
-- q104: BLOCKED soru (C1/C2/C3/C7, pending_review)
INSERT INTO public.questions (
  id, question_code, grade_level, subject_id, question_text,
  option_a, option_b, option_c, option_d, correct_answer,
  difficulty, approval_status, is_active,
  ownership_status, license_status
) VALUES
  ('aaaaaaaa-bbbb-4aaa-8aaa-000000000102', 'QA-040089-READY-0001',
   5, :'qa_subject_id', 'Ready question one',
   'a1', 'b1', 'c1', 'd1', 'C', 'easy',
   'approved', false, 'owned', 'unknown'),
  ('aaaaaaaa-bbbb-4aaa-8aaa-000000000103', 'QA-040089-READY-0002',
   6, :'qa_subject_id', 'Ready question two',
   'a2', 'b2', 'c2', 'd2', 'B', 'hard',
   'approved', false, 'owned', 'unknown'),
  ('aaaaaaaa-bbbb-4aaa-8aaa-000000000104', 'QA-040089-BLOCK-0001',
   7, :'qa_subject_id', 'Blocked question one',
   'a3', 'b3', 'c3', 'd3', 'D', 'medium',
   'pending_review', false, 'owned', 'unknown');


-- ============================================================
-- A. admin_question_edit (089) — DAVRANIŞSAL
-- ============================================================

-- A1: Kimliği doğrulanmamış kullanıcı REDDEDİLİR
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '';
DO $$
BEGIN
  PERFORM public.admin_question_edit(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000101',
    p_question_text := 'should not happen'
  );
  RAISE EXCEPTION 'A1 FAIL: unauthenticated call did not raise';
EXCEPTION
  WHEN OTHERS THEN
    IF sqlerrm = 'Authentication required.' THEN
      INSERT INTO qa_results VALUES ('A1', 'PASS');
    ELSE
      RAISE EXCEPTION 'A1 FAIL unexpected error: %', sqlerrm;
    END IF;
END $$;

-- A2: Normal kullanıcı (admin rolü yok) REDDEDİLİR
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a4';
DO $$
BEGIN
  PERFORM public.admin_question_edit(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000101',
    p_question_text := 'should not happen'
  );
  RAISE EXCEPTION 'A2 FAIL: plain user call did not raise';
EXCEPTION
  WHEN OTHERS THEN
    IF sqlerrm = 'Question edit permission required.' THEN
      INSERT INTO qa_results VALUES ('A2', 'PASS');
    ELSE
      RAISE EXCEPTION 'A2 FAIL unexpected error: %', sqlerrm;
    END IF;
END $$;

-- A3: questions.edit izni OLMAYAN admin (copyright_reviewer) REDDEDİLİR
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a3';
DO $$
BEGIN
  PERFORM public.admin_question_edit(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000101',
    p_question_text := 'should not happen'
  );
  RAISE EXCEPTION 'A3 FAIL: admin without questions.edit was allowed';
EXCEPTION
  WHEN OTHERS THEN
    IF sqlerrm = 'Question edit permission required.' THEN
      INSERT INTO qa_results VALUES ('A3', 'PASS');
    ELSE
      RAISE EXCEPTION 'A3 FAIL unexpected error: %', sqlerrm;
    END IF;
END $$;

-- A3b: Başarısız işlem soru verisini DEĞİŞTİRMEZ ve audit ÜRETMEZ
SET LOCAL ROLE supabase_admin;
RESET request.jwt.claim.sub;
DO $$
BEGIN
  IF (SELECT question_text FROM public.questions
      WHERE id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000101')
     IS DISTINCT FROM 'Original edit text'
  THEN
    RAISE EXCEPTION 'A3b FAIL: denied call mutated question data';
  END IF;
  IF (SELECT count(*) FROM public.admin_audit_log
      WHERE entity_id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000101') <> 0
  THEN
    RAISE EXCEPTION 'A3b FAIL: denied call produced audit row';
  END IF;
  INSERT INTO qa_results VALUES ('A3b', 'PASS');
END $$;

-- A4: Yetkili admin düzenlemesi BAŞARILI, alanlar GERÇEKTEN değişir,
--     korunan yaşam döngüsü alanları DOKUNULMAZ kalır
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a2';
DO $$
DECLARE
  v_result jsonb;
BEGIN
  v_result := public.admin_question_edit(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000101',
    p_question_text := 'Edited question text',
    p_difficulty    := 'hard'
  );
  IF v_result ->> 'status' <> 'updated' THEN
    RAISE EXCEPTION 'A4 FAIL: unexpected status %', v_result ->> 'status';
  END IF;
  INSERT INTO qa_results VALUES ('A4', 'PASS');
END $$;

SET LOCAL ROLE supabase_admin;
RESET request.jwt.claim.sub;
DO $$
BEGIN
  IF (SELECT question_text FROM public.questions
      WHERE id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000101')
     IS DISTINCT FROM 'Edited question text'
  THEN
    RAISE EXCEPTION 'A4 FAIL: question_text not mutated';
  END IF;
  IF (SELECT difficulty FROM public.questions
      WHERE id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000101') <> 'hard'
  THEN
    RAISE EXCEPTION 'A4 FAIL: difficulty not mutated';
  END IF;
  IF (SELECT approval_status FROM public.questions
      WHERE id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000101') <> 'approved'
     OR (SELECT is_active FROM public.questions
      WHERE id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000101')
  THEN
    RAISE EXCEPTION 'A4 FAIL: protected lifecycle fields mutated';
  END IF;
  INSERT INTO qa_results VALUES ('A4b', 'PASS');
END $$;

-- A4c: Audit kaydı TAM OLARAK BİR adet; actor/action/entity doğru;
--      before_data ve after_data GERÇEK değişikliği gösterir
DO $$
DECLARE
  v_audit record;
  v_cnt bigint;
BEGIN
  SELECT count(*) INTO v_cnt
  FROM public.admin_audit_log
  WHERE entity_id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000101';
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'A4c FAIL: expected exactly 1 audit row, got %', v_cnt;
  END IF;

  SELECT * INTO v_audit FROM public.admin_audit_log
  WHERE entity_id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000101';

  IF v_audit.actor_user_id
     <> 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a2'
     OR v_audit.action_code <> 'question.edit'
     OR v_audit.entity_type <> 'question'
  THEN
    RAISE EXCEPTION 'A4c FAIL: audit actor/action/entity mismatch';
  END IF;
  IF v_audit.before_data ->> 'question_text' <> 'Original edit text'
     OR v_audit.after_data  ->> 'question_text' <> 'Edited question text'
     OR v_audit.before_data ->> 'difficulty'    <> 'medium'
     OR v_audit.after_data  ->> 'difficulty'    <> 'hard'
  THEN
    RAISE EXCEPTION 'A4c FAIL: before/after data mismatch';
  END IF;
  INSERT INTO qa_results VALUES ('A4c', 'PASS');
END $$;

-- A5: ATOMİKLİK — audit INSERT zorla başarısız olursa mutation da GERİ ALINIR
CREATE FUNCTION pg_temp.qa_atomicity_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.actor_user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a7' THEN
    RAISE EXCEPTION 'forced audit failure';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER qa_atomicity_guard_trigger
BEFORE INSERT ON public.admin_audit_log
FOR EACH ROW EXECUTE FUNCTION pg_temp.qa_atomicity_guard();

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a7';
DO $$
BEGIN
  PERFORM public.admin_question_edit(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000101',
    p_question_text := 'atomicity probe text'
  );
  RAISE EXCEPTION 'A5 FAIL: forced-failure edit did not raise';
EXCEPTION
  WHEN OTHERS THEN
    IF sqlerrm = 'forced audit failure' THEN
      INSERT INTO qa_results VALUES ('A5', 'PASS');
    ELSE
      RAISE EXCEPTION 'A5 FAIL unexpected error: %', sqlerrm;
    END IF;
END $$;

SET LOCAL ROLE supabase_admin;
RESET request.jwt.claim.sub;
DO $$
BEGIN
  IF (SELECT question_text FROM public.questions
      WHERE id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000101')
     IS DISTINCT FROM 'Edited question text'
  THEN
    RAISE EXCEPTION 'A5 FAIL: mutation survived failed audit insert (NOT atomic)';
  END IF;
  IF (SELECT count(*) FROM public.admin_audit_log
      WHERE entity_id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000101') <> 1
  THEN
    RAISE EXCEPTION 'A5 FAIL: audit row count changed after failed insert';
  END IF;
  INSERT INTO qa_results VALUES ('A5b', 'PASS');
END $$;

DROP TRIGGER qa_atomicity_guard_trigger ON public.admin_audit_log;
DROP FUNCTION pg_temp.qa_atomicity_guard();


-- ============================================================
-- B. admin_audit_log RLS (089) — ROL MATRİSİ
-- ============================================================

-- B1: Anonymous OKUYAMAZ — RLS'te anon için policy YOKTUR;
--     platform default ACL'i SELECT grant'i verse bile RLS
--     tüm satırları filtreler (0 satır = fail-closed).
SET LOCAL ROLE anon;
RESET request.jwt.claim.sub;
DO $$
DECLARE v_cnt bigint;
BEGIN
  SELECT count(*) INTO v_cnt FROM public.admin_audit_log;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'B1 FAIL: anon sees % audit rows', v_cnt;
  END IF;
  INSERT INTO qa_results VALUES ('B1', 'PASS');
END $$;

-- B2: Normal authenticated kullanıcı OKUYAMAZ (policy FALSE)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a4';
DO $$
DECLARE v_cnt bigint;
BEGIN
  SELECT count(*) INTO v_cnt FROM public.admin_audit_log;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'B2 FAIL: plain user sees % audit rows', v_cnt;
  END IF;
  INSERT INTO qa_results VALUES ('B2', 'PASS');
END $$;

-- B3: audit.view izni OLMAYAN admin (content_admin) OKUYAMAZ
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a2';
DO $$
DECLARE v_cnt bigint;
BEGIN
  SELECT count(*) INTO v_cnt FROM public.admin_audit_log;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'B3 FAIL: admin without audit.view sees % rows', v_cnt;
  END IF;
  INSERT INTO qa_results VALUES ('B3', 'PASS');
END $$;

-- B4: audit.view yetkili admin (super_admin) OKUYABİLİR
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a1';
DO $$
DECLARE v_cnt bigint;
BEGIN
  SELECT count(*) INTO v_cnt FROM public.admin_audit_log;
  IF v_cnt < 1 THEN
    RAISE EXCEPTION 'B4 FAIL: audit.view admin sees no rows';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_audit_log
    WHERE entity_id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000101'
      AND action_code = 'question.edit'
  ) THEN
    RAISE EXCEPTION 'B4 FAIL: expected A4 audit row not visible';
  END IF;
  INSERT INTO qa_results VALUES ('B4', 'PASS');
END $$;

-- B5: FAIL-CLOSED — boş/hatalı JWT claim → 0 satır
SET LOCAL request.jwt.claim.sub = '';
DO $$
DECLARE v_cnt bigint;
BEGIN
  SELECT count(*) INTO v_cnt FROM public.admin_audit_log;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'B5 FAIL: empty JWT sub leaked % rows', v_cnt;
  END IF;
  INSERT INTO qa_results VALUES ('B5', 'PASS');
END $$;

-- B6: Authenticated doğrudan YAZAMAZ (INSERT policy yok; fail-closed)
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a1';
DO $$
BEGIN
  INSERT INTO public.admin_audit_log (
    actor_user_id, action_code, entity_type, entity_id
  ) VALUES (
    'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a1',
    'question.edit', 'question',
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000101'
  );
  RAISE EXCEPTION 'B6 FAIL: authenticated direct INSERT succeeded';
EXCEPTION
  WHEN insufficient_privilege THEN
    INSERT INTO qa_results VALUES ('B6', 'PASS');
  WHEN OTHERS THEN
    IF sqlerrm LIKE '%row-level security%' THEN
      INSERT INTO qa_results VALUES ('B6', 'PASS');
    ELSE
      RAISE EXCEPTION 'B6 FAIL unexpected error: %', sqlerrm;
    END IF;
END $$;


-- ============================================================
-- C. READINESS + AKTİVASYON (040)
-- ============================================================

-- C1: Blokerli soru (pending_review) için can_activate = FALSE
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a2';
DO $$
DECLARE v jsonb;
BEGIN
  v := public.check_question_activation_readiness(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000104'
  );
  IF (v ->> 'can_activate')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'C1 FAIL: blocked question reported activatable';
  END IF;
  IF (v -> 'blocking_reasons')::text NOT LIKE '%question_not_approved%' THEN
    RAISE EXCEPTION 'C1 FAIL: question_not_approved blocker missing';
  END IF;
  INSERT INTO qa_results VALUES ('C1', 'PASS');
END $$;

-- C2: Blokerli soru AKTİVE EDİLEMEZ (fonksiyon exception fırlatır)
DO $$
BEGIN
  PERFORM public.activate_question_for_students(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000104',
    'qa blocked activation attempt'
  );
  RAISE EXCEPTION 'C2 FAIL: blocked question was activated';
EXCEPTION
  WHEN OTHERS THEN
    IF sqlerrm LIKE 'Question cannot be activated.%' THEN
      INSERT INTO qa_results VALUES ('C2', 'PASS');
    ELSE
      RAISE EXCEPTION 'C2 FAIL unexpected error: %', sqlerrm;
    END IF;
END $$;

-- C3: Başarısız aktivasyon veri veya publication event BIRAKMAZ
SET LOCAL ROLE supabase_admin;
RESET request.jwt.claim.sub;
DO $$
BEGIN
  IF (SELECT is_active FROM public.questions
      WHERE id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000104') THEN
    RAISE EXCEPTION 'C3 FAIL: blocked question became active';
  END IF;
  IF (SELECT count(*) FROM public.question_publication_events
      WHERE question_id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000104') <> 0
  THEN
    RAISE EXCEPTION 'C3 FAIL: failed activation left publication event';
  END IF;
  INSERT INTO qa_results VALUES ('C3', 'PASS');
END $$;

-- C4: Hazır soru için can_activate = TRUE
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a5';
DO $$
DECLARE v jsonb;
BEGIN
  v := public.check_question_activation_readiness(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000102'
  );
  IF (v ->> 'can_activate')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'C4 FAIL: ready question blocked: %',
      v -> 'blocking_reasons';
  END IF;
  INSERT INTO qa_results VALUES ('C4', 'PASS');
END $$;

-- C5: Yalnız questions.approve izniyle AKTİVASYON BAŞARILI;
--     doğru publication event oluşur
DO $$
DECLARE v jsonb;
BEGIN
  v := public.activate_question_for_students(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000102',
    'qa activation reason'
  );
  IF v ->> 'status' <> 'activated' THEN
    RAISE EXCEPTION 'C5 FAIL: unexpected status %', v ->> 'status';
  END IF;
  INSERT INTO qa_results VALUES ('C5', 'PASS');
END $$;

SET LOCAL ROLE supabase_admin;
RESET request.jwt.claim.sub;
DO $$
BEGIN
  IF (SELECT is_active FROM public.questions
      WHERE id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000102') IS NOT TRUE THEN
    RAISE EXCEPTION 'C5 FAIL: question not active after activation';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.question_publication_events
    WHERE question_id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000102'
      AND action = 'activate'
      AND previous_is_active = false
      AND new_is_active = true
      AND performed_by = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a5'
      AND reason = 'qa activation reason'
  ) THEN
    RAISE EXCEPTION 'C5 FAIL: activate publication event mismatch';
  END IF;
  INSERT INTO qa_results VALUES ('C5b', 'PASS');
END $$;

-- C6: Yalnız ai.manage izniyle AKTİVASYON BAŞARILI (ayrı izin yolu)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a6';
DO $$
DECLARE v jsonb;
BEGIN
  v := public.activate_question_for_students(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000103',
    'qa ai-manager activation'
  );
  IF v ->> 'status' <> 'activated' THEN
    RAISE EXCEPTION 'C6 FAIL: ai.manage-only activation failed: %',
      v ->> 'status';
  END IF;
  INSERT INTO qa_results VALUES ('C6', 'PASS');
END $$;

-- C7: İki izin de YOKSA (copyright_reviewer) REDDİLİR
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a3';
DO $$
BEGIN
  PERFORM public.activate_question_for_students(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000104',
    'qa unauthorized activation'
  );
  RAISE EXCEPTION 'C7 FAIL: unauthorized activation succeeded';
EXCEPTION
  WHEN OTHERS THEN
    IF sqlerrm = 'Question approval permission required.' THEN
      INSERT INTO qa_results VALUES ('C7', 'PASS');
    ELSE
      RAISE EXCEPTION 'C7 FAIL unexpected error: %', sqlerrm;
    END IF;
END $$;

-- C8: Zaten aktif soru → GÜVENLİ/İDEMPOTENT; yeni event ÜRETMEZ
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a5';
DO $$
DECLARE v jsonb;
BEGIN
  v := public.activate_question_for_students(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000102',
    'qa idempotent activation'
  );
  IF v ->> 'status' <> 'already_active' THEN
    RAISE EXCEPTION 'C8 FAIL: expected already_active, got %',
      v ->> 'status';
  END IF;
  INSERT INTO qa_results VALUES ('C8', 'PASS');
END $$;

SET LOCAL ROLE supabase_admin;
RESET request.jwt.claim.sub;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.question_publication_events
      WHERE question_id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000102'
        AND action = 'activate') <> 1
  THEN
    RAISE EXCEPTION 'C8 FAIL: idempotent call produced extra event';
  END IF;
  INSERT INTO qa_results VALUES ('C8b', 'PASS');
END $$;


-- ============================================================
-- D. DEAKTİVASYON (040)
-- ============================================================

-- D1: Sebepsiz (boş) deaktivasyon REDDEDİLİR
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a2';
DO $$
BEGIN
  PERFORM public.deactivate_question_for_students(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000102',
    '   '
  );
  RAISE EXCEPTION 'D1 FAIL: blank-reason deactivation succeeded';
EXCEPTION
  WHEN OTHERS THEN
    IF sqlerrm = 'Deactivation reason is required.' THEN
      INSERT INTO qa_results VALUES ('D1', 'PASS');
    ELSE
      RAISE EXCEPTION 'D1 FAIL unexpected error: %', sqlerrm;
    END IF;
END $$;

-- D2: Yetkisiz kullanıcı REDDEDİLİR
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a4';
DO $$
BEGIN
  PERFORM public.deactivate_question_for_students(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000102',
    'qa unauthorized deactivation'
  );
  RAISE EXCEPTION 'D2 FAIL: unauthorized deactivation succeeded';
EXCEPTION
  WHEN OTHERS THEN
    IF sqlerrm = 'Question approval permission required.' THEN
      INSERT INTO qa_results VALUES ('D2', 'PASS');
    ELSE
      RAISE EXCEPTION 'D2 FAIL unexpected error: %', sqlerrm;
    END IF;
END $$;

-- D2b: Başarısız işlem KISMİ VERİ BIRAKMAZ
SET LOCAL ROLE supabase_admin;
RESET request.jwt.claim.sub;
DO $$
BEGIN
  IF (SELECT is_active FROM public.questions
      WHERE id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000102') IS NOT TRUE THEN
    RAISE EXCEPTION 'D2b FAIL: question mutated by failed deactivation';
  END IF;
  IF (SELECT count(*) FROM public.question_publication_events
      WHERE question_id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000102') <> 1
  THEN
    RAISE EXCEPTION 'D2b FAIL: failed deactivation left partial event';
  END IF;
  INSERT INTO qa_results VALUES ('D2b', 'PASS');
END $$;

-- D3: Geçerli sebep ve yetkiyle DEAKTİVASYON BAŞARILI;
--     soru pasifleşir; doğru event oluşur
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a2';
DO $$
DECLARE v jsonb;
BEGIN
  v := public.deactivate_question_for_students(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000102',
    'qa deactivation reason'
  );
  IF v ->> 'status' <> 'deactivated' THEN
    RAISE EXCEPTION 'D3 FAIL: unexpected status %', v ->> 'status';
  END IF;
  INSERT INTO qa_results VALUES ('D3', 'PASS');
END $$;

SET LOCAL ROLE supabase_admin;
RESET request.jwt.claim.sub;
DO $$
BEGIN
  IF (SELECT is_active FROM public.questions
      WHERE id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000102') IS NOT FALSE THEN
    RAISE EXCEPTION 'D3 FAIL: question still active after deactivation';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.question_publication_events
    WHERE question_id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000102'
      AND action = 'deactivate'
      AND previous_is_active = true
      AND new_is_active = false
      AND performed_by = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a2'
      AND reason = 'qa deactivation reason'
  ) THEN
    RAISE EXCEPTION 'D3 FAIL: deactivate publication event mismatch';
  END IF;
  INSERT INTO qa_results VALUES ('D3b', 'PASS');
END $$;

-- D4: Zaten pasif soru → IDEMPOTENT; yeni event ÜRETMEZ
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-0000000000a2';
DO $$
DECLARE v jsonb;
BEGIN
  v := public.deactivate_question_for_students(
    'aaaaaaaa-bbbb-4aaa-8aaa-000000000102',
    'qa idempotent deactivation'
  );
  IF v ->> 'status' <> 'already_inactive' THEN
    RAISE EXCEPTION 'D4 FAIL: expected already_inactive, got %',
      v ->> 'status';
  END IF;
  INSERT INTO qa_results VALUES ('D4', 'PASS');
END $$;

SET LOCAL ROLE supabase_admin;
RESET request.jwt.claim.sub;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.question_publication_events
      WHERE question_id = 'aaaaaaaa-bbbb-4aaa-8aaa-000000000102'
        AND action = 'deactivate') <> 1
  THEN
    RAISE EXCEPTION 'D4 FAIL: idempotent call produced extra event';
  END IF;
  INSERT INTO qa_results VALUES ('D4b', 'PASS');
END $$;


-- ============================================================
-- SONUÇ: TÜM BEKLENTİLER DOĞRULANDI MI?
-- ============================================================

SET LOCAL ROLE supabase_admin;
RESET request.jwt.claim.sub;
DO $$
DECLARE
  v_total bigint;
  v_bad bigint;
BEGIN
  SELECT count(*) INTO v_total FROM qa_results;
  SELECT count(*) INTO v_bad FROM qa_results WHERE result <> 'PASS';
  IF v_total <> 32 THEN
    RAISE EXCEPTION 'FAIL: expected 32 assertions, got %', v_total;
  END IF;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'FAIL: % non-PASS rows', v_bad;
  END IF;
END $$;

SELECT test_id, result FROM qa_results ORDER BY test_id;

ROLLBACK;
