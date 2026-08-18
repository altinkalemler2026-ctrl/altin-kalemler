BEGIN;

ALTER TABLE public.ai_question_staging
  DROP CONSTRAINT IF EXISTS ai_question_staging_final_question_id_fkey;

ALTER TABLE public.ai_question_staging
  ADD CONSTRAINT ai_question_staging_final_question_id_fkey
  FOREIGN KEY (final_question_id)
  REFERENCES public.questions(id)
  ON DELETE RESTRICT;

COMMIT;