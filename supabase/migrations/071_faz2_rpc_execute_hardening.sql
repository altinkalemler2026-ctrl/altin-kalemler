-- ============================================================
-- 071_faz2_rpc_execute_hardening.sql
-- Altın Kalemler - Migration Faz 2 RPC EXECUTE sertleştirmesi
--
-- BAGLAM (final review bulgusu F-B):
--   068, yardimci fonksiyonlar icin tam revoke desenini uyguladi ama
--   uc PUBLIC RPC icin PostgreSQL'in varsayilan PUBLIC EXECUTE
--   grant'ini geri almadı. pg_proc.proacl dogrulamasi (=X/postgres):
--     select_training_questions, get_my_weekly_usage,
--     prepare_competition_pack  ->  PUBLIC EXECUTE acikti.
--   Fonksiyonlar icindeki auth.uid() kontrolu anon cagrilara veri
--   sizdirmiyordu; ancak yetki modeli tutarsizdi ve RPC yuzeyi
--   gereksiz yere genisti.
--
-- IMZA DOGRULAMASI (pg_get_function_identity_arguments, canli sema):
--   select_training_questions(p_subject_id uuid, p_limit integer)
--   get_my_weekly_usage()
--   prepare_competition_pack(p_competition_id uuid)
--   Hepsi: SECURITY DEFINER, set search_path='', owner=postgres.
--
-- BU MIGRATION YALNIZ ACL DEGISTIRIR:
--   - SECURITY DEFINER / auth.uid() / search_path modeline DOKUNULMAZ.
--   - Her RPC icin: PUBLIC + anon EXECUTE REVOKE; authenticated GRANT.
--   - service_role'a grant EKLENMEZ (mevcut istemci yolu
--     authenticated'dir; gereksiz yuzey genisletilmez).
-- ============================================================

begin;


-- ============================================================
-- 1. SELECT_TRAINING_QUESTIONS(uuid, integer)
-- ============================================================

revoke execute
on function public.select_training_questions(uuid, integer)
from public, anon;

grant execute
on function public.select_training_questions(uuid, integer)
to authenticated;


-- ============================================================
-- 2. GET_MY_WEEKLY_USAGE()
-- ============================================================

revoke execute
on function public.get_my_weekly_usage()
from public, anon;

grant execute
on function public.get_my_weekly_usage()
to authenticated;


-- ============================================================
-- 3. PREPARE_COMPETITION_PACK(uuid)
-- ============================================================

revoke execute
on function public.prepare_competition_pack(uuid)
from public, anon;

grant execute
on function public.prepare_competition_pack(uuid)
to authenticated;


commit;
