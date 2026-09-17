-- Faz 12B geri alma (rollback) migration'ı.
-- Migration 112 ile eklenen Faz 12B alt konu ve kazanımlarını siler.
-- Sıra önemli: önce kazanımlar (FK → subtopics), sonra alt konular.
-- Yalnızca migration 112 UUID aralıkları hedeflenir (a6*/a7*); Faz 12A/15A verisine dokunulmaz.
-- Not: migration 111 (topic/curriculum_version) verisi korunur.

begin;

delete from public.curriculum_outcomes
where id::text like 'a7%';

delete from public.subtopics
where id::text like 'a6%';

commit;