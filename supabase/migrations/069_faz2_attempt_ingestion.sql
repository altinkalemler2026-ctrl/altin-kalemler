-- ============================================================
-- 069_faz2_attempt_ingestion.sql
-- Altın Kalemler - Migration Faz 2 (069)
--
-- Soru denemesi kaydı + deterministik metrik güncelleme.
--
-- Faz 2 mimari kararları:
--   - ingest_student_attempt YALNIZ attempt, süre ve deterministik
--     metrikleri kaydeder. Exposure/haftalık sayaç BURADA ARTIRILMAZ;
--     o işlem show-time'da (068 seçim/paket RPC'leri) atomiktir.
--   - Kullanıcı yalnız auth.uid()'den türetilir; başka öğrenci adına
--     kayıt imkânsızdır.
--   - question_type / cognitive_type / difficulty metrik anahtarları
--     normalize edilir; boş/serbest metin -> 'tanimsiz'.
--   - Snapshot değiştirilemezliği: competition_questions satırlarının
--     question_id'si sonradan ASLA değiştirilemez; aktif/biten
--     yarışmanın soru satırı silinemez. (Yeni additive trigger;
--     021/023'e dokunulmaz.)
--
-- AI hiçbir yerde karar vermez: tüm metrikler ham veriden SQL ile.
-- ============================================================

begin;


-- ============================================================
-- 1. DESTEK INDEKSI
--    attempt_number hesabı ve soru bazlı geçmiş erişimi için.
-- ============================================================

create index if not exists idx_student_question_attempts_user_question
  on public.student_question_attempts (user_id, question_id);


-- ============================================================
-- 2. SNAPSHOT DEĞİŞTİRİLMEZLİĞİ (karar #4)
-- ============================================================

create or replace function public.guard_competition_question_snapshot()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status text;
begin
  if tg_op = 'UPDATE'
     and new.question_id is distinct from old.question_id
  then
    raise exception
      'Yarisma snapshot sorusu degistirilemez.'
      using errcode = 'P0001';
  end if;

  if tg_op = 'DELETE' then
    select c.status into v_status
      from public.competitions c
     where c.id = old.competition_id;

    if v_status in ('active', 'completed', 'disputed') then
      raise exception
        'Aktif/biten yarismadan snapshot sorusu silinemez (%).', v_status
        using errcode = 'P0001';
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_competition_questions_snapshot_guard
  on public.competition_questions;

create trigger trg_competition_questions_snapshot_guard
before update or delete on public.competition_questions
for each row
execute function public.guard_competition_question_snapshot();

revoke execute
on function public.guard_competition_question_snapshot()
from public, anon, authenticated;


-- ============================================================
-- 3. PUBLIC RPC: DENEME KAYDI
--
-- ingest_student_attempt(
--   p_question_id, p_attempt_context, p_result,
--   p_time_ms default null,
--   p_source_answer_id default null,
--   p_metadata default '{}')
--
-- Davranış:
--   1. kullanıcı = auth.uid() (yoksa reddet).
--   2. soru varlığı doğrulanır; subject/difficulty/cognitive/type
--      SORUDAN türetilir (istemciye güvenilmez).
--   3. dönem çözülemezse FAIL-CLOSED.
--   4. aynı (kullanıcı,soru) yazımları advisory transaction kilidiyle
--      serileşir -> attempt_number tutarlı.
--   5. attempt INSERT.
--   6. TEK ifadeyle çok satırlı metrik upsert (7 kapsam):
--      subject/topic/subtopic/outcome/difficulty/cognitive_type/
--      question_type. Repeat ve süre toplamları dahil.
--   7. Exposure/sayaç dokunulmaz.
-- ============================================================

create or replace function public.ingest_student_attempt(
  p_question_id      uuid,
  p_attempt_context  text,
  p_result           text,
  p_time_ms          integer default null,
  p_source_answer_id uuid    default null,
  p_metadata         jsonb   default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user           uuid;
  r_q              public.questions%rowtype;
  v_year           text;
  v_week           integer;
  v_attempt_number integer;
  v_attempt_id     uuid;
  v_scopes         integer := 0;
  v_scope_list     jsonb;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  if p_question_id is null then
    raise exception 'Soru zorunludur.' using errcode = '22004';
  end if;

  select * into r_q
    from public.questions q
   where q.id = p_question_id;
  if r_q.id is null then
    raise exception 'Soru bulunamadi.' using errcode = 'P0001';
  end if;

  select * into v_year, v_week from public._faz2_require_period();

  -- Aynı öğrenci+soru için serileştirme (attempt_number yarışı).
  perform pg_advisory_xact_lock(
    hashtextextended(v_user::text || ':' || p_question_id::text, 0)
  );

  select coalesce(max(a.attempt_number), 0) + 1
    into v_attempt_number
    from public.student_question_attempts a
   where a.user_id = v_user
     and a.question_id = p_question_id;

  insert into public.student_question_attempts
    (user_id, question_id, subject_id, attempt_context, result,
     attempt_number, time_ms, academic_year, week,
     source_answer_id, metadata)
  values
    (v_user, p_question_id, r_q.subject_id, p_attempt_context, p_result,
     v_attempt_number, p_time_ms, v_year, v_week,
     p_source_answer_id, coalesce(p_metadata, '{}'::jsonb))
  returning id into v_attempt_id;

  -- ----------------------------------------------------------
  -- Tek ifadeyle tüm kapsamlar. Tablo CHECK'leri her satır için
  -- toplam tutarlılığını doğrular (sum <= total, repeat <= total).
  -- ----------------------------------------------------------
  with pairs as (
    select 'subject'::text        as scope,
           r_q.subject_id::text   as key
    union all
    select 'difficulty',
           public._faz2_normalize_metric_key(r_q.difficulty)
    union all
    select 'cognitive_type',
           public._faz2_normalize_metric_key(r_q.cognitive_type)
    union all
    select 'question_type',
           public._faz2_normalize_metric_key(r_q.primary_question_type)
    union all
    select distinct 'topic',
           cm.topic_id::text
      from public.question_curriculum_mappings cm
     where cm.question_id = r_q.id
    union all
    select distinct 'subtopic',
           cm.subtopic_id::text
      from public.question_curriculum_mappings cm
     where cm.question_id = r_q.id
       and cm.subtopic_id is not null
    union all
    select distinct 'outcome',
           om.outcome_id::text
      from public.question_outcome_mappings om
     where om.question_id = r_q.id
  ),
  bumped as (
    insert into public.student_dimension_metrics as d
      (user_id, metric_scope, scope_key,
       total_attempts, correct_count, wrong_count, blank_count,
       pass_timeout_count, repeat_total, repeat_correct,
       total_time_ms, last_attempted_at)
    select v_user,
           pr.scope,
           pr.key,
           1,
           case when p_result = 'correct' then 1 else 0 end,
           case when p_result = 'wrong'   then 1 else 0 end,
           case when p_result = 'blank'   then 1 else 0 end,
           case when p_result in ('pass', 'timeout') then 1 else 0 end,
           case when v_attempt_number > 1 then 1 else 0 end,
           case when v_attempt_number > 1
                 and p_result = 'correct' then 1 else 0 end,
           coalesce(greatest(p_time_ms, 0), 0),
           now()
      from pairs pr
    on conflict (user_id, metric_scope, scope_key) do update
      set total_attempts       = d.total_attempts + 1,
          correct_count        = d.correct_count + excluded.correct_count,
          wrong_count          = d.wrong_count + excluded.wrong_count,
          blank_count          = d.blank_count + excluded.blank_count,
          pass_timeout_count   = d.pass_timeout_count + excluded.pass_timeout_count,
          repeat_total         = d.repeat_total + excluded.repeat_total,
          repeat_correct       = d.repeat_correct + excluded.repeat_correct,
          total_time_ms        = d.total_time_ms + excluded.total_time_ms,
          last_attempted_at    = excluded.last_attempted_at,
          updated_at           = now()
    returning d.metric_scope
  )
  select count(*), coalesce(jsonb_agg(distinct b.metric_scope), '[]'::jsonb)
    into v_scopes, v_scope_list
    from bumped b;

  return jsonb_build_object(
    'attempt_id', v_attempt_id,
    'attempt_number', v_attempt_number,
    'metrics_updated', v_scopes,
    'metric_scopes', v_scope_list
  );
end;
$$;


-- ============================================================
-- 3b. SNAPSHOT KAYNAĞI SABİTLEME (Faz 2 review F-1)
--
-- prepare_competition_pack (068) seçilen kesin soru listesini
-- competitions.configuration.faz2_pack.question_ids'e yazar.
-- Bu trigger, o listede işaretlenmiş yarışmalara snapshot satırı
-- yazan HERHANGİ bir yazıcıyı (mevcut veya gelecekteki) listeye
-- kilitler: faz2_pack kapsamındaki yarışmaya pakette OLMAYAN bir
-- question_id ile competition_questions satırı yazılamaz.
--
-- faz2_pack içermeyen yarışmalar (Faz 1 akışı) etkilenmez.
-- guard_competition_question_snapshot (bölüm 2) ile uyumludur:
-- biri kaynağı sabitler, diğeri değişmezliği korur.
-- ============================================================

create or replace function public.guard_faz2_snapshot_source()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_pack jsonb;
begin
  select c.configuration -> 'faz2_pack'
    into v_pack
    from public.competitions c
   where c.id = new.competition_id;

  if v_pack is not null and v_pack ? 'question_ids' then
    -- to_jsonb(uuid[]) elemanları kanonik lowercase metin UUID'lerdir;
    -- uuid::text çıktısıyla birebir eşleşir.
    if not (v_pack -> 'question_ids') ? new.question_id::text then
      raise exception
        'Snapshot sorusu faz2_pack listesinde yok; paket disi soru giremez.'
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_competition_questions_faz2_source_guard
  on public.competition_questions;

create trigger trg_competition_questions_faz2_source_guard
before insert or update of question_id
on public.competition_questions
for each row
execute function public.guard_faz2_snapshot_source();


-- ============================================================
-- 4. EXECUTE İZİNLERİ
-- ============================================================

revoke execute
on function public.guard_faz2_snapshot_source()
from public, anon, authenticated;

grant execute
on function public.ingest_student_attempt(uuid, text, text, integer, uuid, jsonb)
to authenticated;


commit;
