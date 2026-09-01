-- ================================================================
-- [085] ÖĞRENCİ BOYUT ÖZETİ (TRAINING ANALYTICS PHASE 1)
--
-- get_student_dimension_summary()
--   Oturumdaki öğrencinin kendi student_dimension_metrics (064)
--   verisini subject/topic/subtopic/outcome kapsamlarında okur.
--   Kullanıcı parametresi ALMAZ; kimlik yalnızca auth.uid()'dir.
--   Çıktı satırlarına müfredat tablolarından display_name/subject_name
--   LEFT JOIN ile eklenir.
--
-- TASARIM NOTU (scope_key eşitleme):
--   Join'ler d.scope_key = <dimension>.id::text biçiminde YAPILIR,
--   scope_key::uuid cast KULLANILMAZ. İleride ingestion dışı bir yol
--   malformed/stale bir scope_key üretirse tüm RPC cast exception ile
--   düşmemeli; LEFT JOIN + text eşitliği + coalesce fallback ile
--   eksik/bozuk dimension güvenli şekilde kayıp (display_name =
--   scope_key) olarak döner.
--
-- Yalnızca subject/topic/subtopic/outcome OKUNUR. difficulty,
-- cognitive_type, question_type kapsam satırlarına dokunulmaz.
-- PII ve soru gizli alanı (correct_answer/solution/review vb.)
-- dönmez.
--
-- RATE KONVANSİYONU (0..100, ROUND 1 hane):
--   success_rate için proje yardımcısı public.calculate_accuracy
--   (015) fully-qualified çağrılır; playout tek kaynaktan gelir.
--   repeat_success_rate ve avg_time_ms zero-safe yerel CASE'lerdir.
-- ================================================================

begin;

create or replace function public.get_student_dimension_summary()
returns table (
  scope_type          text,
  scope_key           text,
  display_name        text,
  subject_id          uuid,
  subject_name        text,
  total               integer,
  correct             integer,
  wrong               integer,
  blank               integer,
  pass_timeout        integer,
  repeat_total        integer,
  repeat_correct      integer,
  total_time_ms       bigint,
  success_rate        numeric,
  repeat_success_rate numeric,
  avg_time_ms         numeric,
  last_attempted_at   timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  return query
  -- subject: scope_key = subjects.id::text
  select
    d.metric_scope::text as scope_type,
    d.scope_key as scope_key,
    coalesce(s.name, d.scope_key)                     as display_name,
    s.id                                              as subject_id,
    s.name                                            as subject_name,
    d.total_attempts,
    d.correct_count,
    d.wrong_count,
    d.blank_count,
    d.pass_timeout_count,
    d.repeat_total,
    d.repeat_correct,
    d.total_time_ms,
    public.calculate_accuracy(d.correct_count, d.total_attempts) as success_rate,
    case
      when d.repeat_total > 0
        then round((d.repeat_correct::numeric / d.repeat_total::numeric) * 100, 1)
      else 0
    end::numeric                                      as repeat_success_rate,
    case
      when d.total_attempts > 0
        then round(d.total_time_ms::numeric / d.total_attempts, 0)
      else 0
    end::numeric                                      as avg_time_ms,
    d.last_attempted_at
  from public.student_dimension_metrics d
  left join public.subjects s on s.id::text = d.scope_key
  where d.user_id = v_user
    and d.metric_scope = 'subject'

  union all

  -- topic: scope_key = topics.id::text; subject topics.subject_id üzerinden
  select
    d.metric_scope::text as scope_type,
    d.scope_key as scope_key,
    coalesce(t.name, d.scope_key)                     as display_name,
    s.id                                              as subject_id,
    s.name                                            as subject_name,
    d.total_attempts,
    d.correct_count,
    d.wrong_count,
    d.blank_count,
    d.pass_timeout_count,
    d.repeat_total,
    d.repeat_correct,
    d.total_time_ms,
    public.calculate_accuracy(d.correct_count, d.total_attempts) as success_rate,
    case
      when d.repeat_total > 0
        then round((d.repeat_correct::numeric / d.repeat_total::numeric) * 100, 1)
      else 0
    end::numeric                                      as repeat_success_rate,
    case
      when d.total_attempts > 0
        then round(d.total_time_ms::numeric / d.total_attempts, 0)
      else 0
    end::numeric                                      as avg_time_ms,
    d.last_attempted_at
  from public.student_dimension_metrics d
  left join public.topics t on t.id::text = d.scope_key
  left join public.subjects s on s.id = t.subject_id
  where d.user_id = v_user
    and d.metric_scope = 'topic'

  union all

  -- subtopic: scope_key = subtopics.id::text; subject subtopics → topics üzerinden
  select
    d.metric_scope::text as scope_type,
    d.scope_key as scope_key,
    coalesce(st.name, d.scope_key)                    as display_name,
    s.id                                              as subject_id,
    s.name                                            as subject_name,
    d.total_attempts,
    d.correct_count,
    d.wrong_count,
    d.blank_count,
    d.pass_timeout_count,
    d.repeat_total,
    d.repeat_correct,
    d.total_time_ms,
    public.calculate_accuracy(d.correct_count, d.total_attempts) as success_rate,
    case
      when d.repeat_total > 0
        then round((d.repeat_correct::numeric / d.repeat_total::numeric) * 100, 1)
      else 0
    end::numeric                                      as repeat_success_rate,
    case
      when d.total_attempts > 0
        then round(d.total_time_ms::numeric / d.total_attempts, 0)
      else 0
    end::numeric                                      as avg_time_ms,
    d.last_attempted_at
  from public.student_dimension_metrics d
  left join public.subtopics st on st.id::text = d.scope_key
  left join public.topics t on t.id = st.topic_id
  left join public.subjects s on s.id = t.subject_id
  where d.user_id = v_user
    and d.metric_scope = 'subtopic'

  union all

  -- outcome: scope_key = curriculum_outcomes.id::text; display = outcome_text
  select
    d.metric_scope::text as scope_type,
    d.scope_key as scope_key,
    coalesce(o.outcome_text, d.scope_key)             as display_name,
    s.id                                              as subject_id,
    s.name                                            as subject_name,
    d.total_attempts,
    d.correct_count,
    d.wrong_count,
    d.blank_count,
    d.pass_timeout_count,
    d.repeat_total,
    d.repeat_correct,
    d.total_time_ms,
    public.calculate_accuracy(d.correct_count, d.total_attempts) as success_rate,
    case
      when d.repeat_total > 0
        then round((d.repeat_correct::numeric / d.repeat_total::numeric) * 100, 1)
      else 0
    end::numeric                                      as repeat_success_rate,
    case
      when d.total_attempts > 0
        then round(d.total_time_ms::numeric / d.total_attempts, 0)
      else 0
    end::numeric                                      as avg_time_ms,
    d.last_attempted_at
  from public.student_dimension_metrics d
  left join public.curriculum_outcomes o on o.id::text = d.scope_key
  left join public.subjects s on s.id = o.subject_id
  where d.user_id = v_user
    and d.metric_scope = 'outcome'

  order by scope_type, subject_name, display_name;
end;
$$;

comment on function public.get_student_dimension_summary() is
  'Oturumdaki öğrencinin kendi boyut metrik özeti (subject/topic/subtopic/outcome). scope_key text eşitliği ile LEFT JOIN; bozuk/eksik dimension tüm sonucu düşürmez.';

revoke execute on function public.get_student_dimension_summary() from public, anon, authenticated;
grant execute on function public.get_student_dimension_summary() to authenticated;

commit;