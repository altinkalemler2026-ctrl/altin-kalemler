-- ============================================================
-- 053_question_import_security_hardening.sql
-- Altın Kalemler
--
-- Question Vault + Excel Import security hardening
-- ============================================================

begin;


-- ============================================================
-- 1. FUNCTION SEARCH PATH HARDENING
-- ============================================================

alter function public.set_question_vault_updated_at()
set search_path = pg_catalog;


alter function public.build_legacy_question_key(
  text,
  integer
)
set search_path = pg_catalog;


alter function public.normalize_excel_exam_track(text)
set search_path = pg_catalog;


alter function public.normalize_excel_answer(text)
set search_path = pg_catalog;


alter function public.normalize_excel_difficulty(text)
set search_path = pg_catalog;


alter function public.normalize_excel_quality(text)
set search_path = pg_catalog;


alter function public.normalize_excel_cognitive_type(text)
set search_path = pg_catalog;


alter function public.normalize_excel_new_generation(text)
set search_path = pg_catalog;


alter function public.normalize_excel_secondary_question_type(text)
set search_path = pg_catalog;


alter function public.normalize_excel_grade_level(text)
set search_path = pg_catalog;


alter function public.normalize_excel_positive_integer(text)
set search_path = pg_catalog;


alter function public.normalize_excel_question_import_row(uuid)
set search_path = pg_catalog, public;


alter function public.get_excel_import_batch_summary(uuid)
set search_path = pg_catalog, public;


-- ============================================================
-- 2. MAIN SECURITY DEFINER NORMALIZER
--
-- PUBLIC / anon / authenticated erişimi yok.
-- Yalnız service_role.
-- ============================================================

revoke execute
on function public.normalize_excel_question_import_row(uuid)
from public;

revoke execute
on function public.normalize_excel_question_import_row(uuid)
from anon;

revoke execute
on function public.normalize_excel_question_import_row(uuid)
from authenticated;

grant execute
on function public.normalize_excel_question_import_row(uuid)
to service_role;


-- ============================================================
-- 3. IMPORT SUMMARY
-- Server-side import altyapısında kullanılacak.
-- ============================================================

revoke execute
on function public.get_excel_import_batch_summary(uuid)
from public;

revoke execute
on function public.get_excel_import_batch_summary(uuid)
from anon;

revoke execute
on function public.get_excel_import_batch_summary(uuid)
from authenticated;

grant execute
on function public.get_excel_import_batch_summary(uuid)
to service_role;


-- ============================================================
-- 4. HELPER FUNCTIONS
-- API yüzeyine açık olmalarına gerek yok.
-- ============================================================

revoke execute
on function public.build_legacy_question_key(text, integer)
from public;

revoke execute
on function public.normalize_excel_exam_track(text)
from public;

revoke execute
on function public.normalize_excel_answer(text)
from public;

revoke execute
on function public.normalize_excel_difficulty(text)
from public;

revoke execute
on function public.normalize_excel_quality(text)
from public;

revoke execute
on function public.normalize_excel_cognitive_type(text)
from public;

revoke execute
on function public.normalize_excel_new_generation(text)
from public;

revoke execute
on function public.normalize_excel_secondary_question_type(text)
from public;

revoke execute
on function public.normalize_excel_grade_level(text)
from public;

revoke execute
on function public.normalize_excel_positive_integer(text)
from public;


grant execute
on function public.build_legacy_question_key(text, integer)
to service_role;

grant execute
on function public.normalize_excel_exam_track(text)
to service_role;

grant execute
on function public.normalize_excel_answer(text)
to service_role;

grant execute
on function public.normalize_excel_difficulty(text)
to service_role;

grant execute
on function public.normalize_excel_quality(text)
to service_role;

grant execute
on function public.normalize_excel_cognitive_type(text)
to service_role;

grant execute
on function public.normalize_excel_new_generation(text)
to service_role;

grant execute
on function public.normalize_excel_secondary_question_type(text)
to service_role;

grant execute
on function public.normalize_excel_grade_level(text)
to service_role;

grant execute
on function public.normalize_excel_positive_integer(text)
to service_role;


commit;