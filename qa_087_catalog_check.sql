-- Scratch catalog verification for migration 087 (read-only, RLS/grants/policy)
SELECT 'RLS_QUESTIONS' AS probe,
       relrowsecurity::text AS rls_enabled,
       relforcerowsecurity::text AS rls_forced
FROM pg_class WHERE oid = 'public.questions'::regclass;

SELECT 'RLS_STAGING' AS probe,
       relrowsecurity::text AS rls_enabled,
       relforcerowsecurity::text AS rls_forced
FROM pg_class WHERE oid = 'public.ai_question_staging'::regclass;

SELECT 'RLS_REVIEW_QUEUE' AS probe,
       relrowsecurity::text AS rls_enabled,
       relforcerowsecurity::text AS rls_forced
FROM pg_class WHERE oid = 'public.review_queue'::regclass;

SELECT 'GRANTS_QUESTIONS' AS probe,
       has_table_privilege('authenticated','public.questions','SELECT') AS sel,
       has_table_privilege('authenticated','public.questions','INSERT') AS ins,
       has_table_privilege('authenticated','public.questions','UPDATE') AS upd,
       has_table_privilege('authenticated','public.questions','DELETE') AS del;

SELECT 'GRANTS_STAGING' AS probe,
       has_table_privilege('authenticated','public.ai_question_staging','SELECT') AS sel,
       has_table_privilege('authenticated','public.ai_question_staging','INSERT') AS ins,
       has_table_privilege('authenticated','public.ai_question_staging','UPDATE') AS upd,
       has_table_privilege('authenticated','public.ai_question_staging','DELETE') AS del;

SELECT 'GRANTS_REVIEW_QUEUE' AS probe,
       has_table_privilege('authenticated','public.review_queue','SELECT') AS sel,
       has_table_privilege('authenticated','public.review_queue','INSERT') AS ins,
       has_table_privilege('authenticated','public.review_queue','UPDATE') AS upd,
       has_table_privilege('authenticated','public.review_queue','DELETE') AS del;

SELECT 'ADMIN_POLICY_QUESTIONS' AS probe, count(*) AS admin_pol_count
FROM pg_policies
WHERE schemaname='public' AND tablename='questions'
  AND policyname='question admins read all questions';

SELECT 'ADMIN_POLICY_STUDENT_ALSO_PRESENT' AS probe, count(*) AS student_pol_count
FROM pg_policies
WHERE schemaname='public' AND tablename='questions'
  AND policyname='questions_student_read';

SELECT 'HELPER_ADMIN_PERMISSION' AS probe,
       exists(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public' AND p.proname='current_user_has_admin_permission') AS helper_exists;

SELECT 'IS_MIGRATION_APPLIED' AS probe,
       count(*) AS applied
FROM supabase_migrations.schema_migrations
WHERE version LIKE '087%';
