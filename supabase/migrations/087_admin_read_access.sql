-- ============================================================
-- 087_admin_read_access.sql
-- Faz 4 admin paneli — SALT-OKUNUR ADMIN ERİŞİMİ (RLS + GRANT)
--
-- Amaç:
--   Yetkili (questions.view sahibi) admin'in mevcut güvenli veri
--   katmanıyla admin paneline soru yaşam döngüsü (tüm
--   approval_status / is_active) okuyabilmesini sağlamak.
--
--   Kapsam YALNIZCA ADMIN SELECT'tir:
--     - INSERT/UPDATE/DELETE yetkisi EKLENMEZ.
--     - RLS AÇIK kalır; GRANT tek başına satır açmaz.
--     - Öğrenci görünürlük semantiği (questions_student_read)
--       DEĞİŞMEZ.
--     - service_role istemcisi KULLANILMAZ.
--
-- Yaklaşım:
--   PostgreSQL permissive politikalar OR birleşir; bu nedenle
--   mevcut öğrenci SELECT politikasına dokunulmadan AYRI bir admin
--   SELECT politikası eklenir (SEPARATE_POLICY). Böylece:
--     - admin olmayan authenticated: yalnızca öğrenci politikasının
--       izin verdiği (approved + active) satırları görür.
--     - questions.view admin'i: tüm durumları görür.
--
--   Canonical helper: public.current_user_has_admin_permission('questions.view')
--   (014/045 admin RLS modellleriyle birebir; private SECURITY DEFINER
--   sarmalayıcıyı çağırır, aynı izin modelini kullanır.)
--
-- Değişmeyen tablolar:
--   ai_teacher_review_runs — şablon/referans; 045'te zaten
--   SELECT,INSERT,UPDATE,DELETE grant + questions.view RLS'i var.
-- ============================================================

BEGIN;


-- ============================================================
-- A) public.questions
--    Mevcut öğrenci politikası (questions_student_read:
--    approved AND is_active) AYNEN korunur.
-- ============================================================

DROP POLICY IF EXISTS "question admins read all questions"
ON public.questions;

CREATE POLICY "question admins read all questions"
ON public.questions
FOR SELECT
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.view')
);

GRANT SELECT
ON public.questions
TO authenticated;


-- ============================================================
-- B) public.ai_question_staging
--    Mevcut admin RLS'i (014) korunur; yalnızca SELECT grant.
-- ============================================================

GRANT SELECT
ON public.ai_question_staging
TO authenticated;


-- ============================================================
-- C) public.review_queue
--    Mevcut admin RLS'i (014) korunur; yalnızca SELECT grant.
-- ============================================================

GRANT SELECT
ON public.review_queue
TO authenticated;


-- ============================================================
-- D) ai_teacher_review_runs — DEĞİŞİKLİK YOK (referans/şablon).
-- ============================================================


COMMIT;
