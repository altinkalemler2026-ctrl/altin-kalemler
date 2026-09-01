-- ================================================================
-- [086] ÖĞRENCİ GÜNLÜK DENEME TRENDİ (TRAINING ANALYTICS PHASE 2)
--
-- get_student_attempt_trend(p_days integer)
--   Oturumdaki öğrencinin kendi student_question_attempts (061) ham
--   fact verisinden GÜNLÜK toplama üretir: doğru/yanlış/boş/
--   pas+zaman-aşımı, günlük başarı oranı ve günlük ort çözüm süresi.
--   Kullanıcı parametresi ALMAZ; kimlik yalnızca auth.uid()'dir.
--
-- DETERMINISM KURALLARI:
--   - Saat dilimi: yalnızca UTC takvim günü (067 ile birebir aynı
--     konvansiyon: (ts at time zone 'utc')::date). Pencere "bugün"ü
--     = (current_timestamp at time zone 'utc')::date; PENCERE BUNA
--     DAHİL DEĞİL SEN HEP EN SON GÜN. → p_days = {7,30} ancak.
--   - Sıfır günler: generate_series ile kesintisiz GÜNGÜN dizi; deneme
--     olmayan günler 0-satır DÖNER (UI grafik boşluksuz çizer). Günlük
--     satır sayısı her zaman p_days'edir.
--   - success_rate: project yardımcısı public.calculate_accuracy (015)
--     ile correct/toplam. TOPLAM payda boş/pas/zaman-aşımı DAHİL; tek
--     +1'ler (069:214-217 dimension metrikleriyle aynı semantik).
--   - avg_time_ms: sum(coalesce(time_ms,0)) / toplam. NULL time_ms 0
--     SAYILIR — 069:221 coalesce(greatest(p_time_ms,0),0) toplamasıyla
--     aynı konvansiyon (Phase 1 avg ile tutarlı).
--   - CONTEXT: tüm attempt_context değerleri dahildir; filtre YOKTUR.
--     Kanıt: 069 birikme bump'ları ∀ context için üretir (Phase 1
--     dimension metrikleri de tüm context'leri içerir). Bugün tek üretici
--     'training' (070:192, 076:783); istenirse ileride veri modeli
--     değişmeden context filtre algı eklenebilir.
--
-- ÇIKTI: PII ve soru gizli alanı YOK; yalnız tarih + sayımlar + oranlar.
-- ================================================================

begin;

create or replace function public.get_student_attempt_trend(p_days integer)
returns table (
  day           date,
  total         integer,
  correct       integer,
  wrong         integer,
  blank         integer,
  pass_timeout  integer,
  success_rate  numeric,
  avg_time_ms   numeric
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid;
  v_today date := (current_timestamp at time zone 'utc')::date;
begin
  if p_days is null or (p_days <> 7 and p_days <> 30) then
    raise exception 'Gecersiz pencere; yalniz 7 veya 30 gun desteklenir.'
      using errcode = '22023';
  end if;

  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  return query
  -- Kesintisiz gün dizisi: [bugün - (p_days - 1), bugün] UTC takvim günleri.
  with days as (
    select v_today - gs::integer as day
      from generate_series(0, p_days - 1) as gs
  ),
  -- Günlük ham toplama: TÜM context'ler; NULL time_ms 0 (069 konvansiyonu).
  agg as (
    select (a.answered_at at time zone 'utc')::date as day,
           count(*)                                                as total,
           count(*) filter (where a.result = 'correct')            as correct,
           count(*) filter (where a.result = 'wrong')              as wrong,
           count(*) filter (where a.result = 'blank')              as blank,
           count(*) filter (where a.result in ('pass', 'timeout')) as pass_timeout,
           sum(coalesce(a.time_ms, 0))                             as total_time_ms
      from public.student_question_attempts a
     where a.user_id = v_user
       and (a.answered_at at time zone 'utc')::date between v_today - (p_days - 1) and v_today
     group by 1
  )
  select
    d.day,
    coalesce(g.total, 0)::integer as total,
    coalesce(g.correct, 0)::integer as correct,
    coalesce(g.wrong, 0)::integer as wrong,
    coalesce(g.blank, 0)::integer as blank,
    coalesce(g.pass_timeout, 0)::integer as pass_timeout,
    public.calculate_accuracy(
      coalesce(g.correct, 0)::integer,
      coalesce(g.total, 0)::integer
    ) as success_rate,
    case
      when coalesce(g.total, 0) <= 0 then 0
      else round(coalesce(g.total_time_ms, 0)::numeric / g.total, 0)
    end::numeric as avg_time_ms
    from days d
    left join agg g on g.day = d.day
   order by d.day desc;
end;
$$;

comment on function public.get_student_attempt_trend(integer) is
  'Oturumdaki öğrencinin kendi denemelerinden günlük trend (7/30 gün, UTC takvim günü, bugün dahil). Sıfır günler 0-satır; NULL time_ms 0 sayılır; tüm context değerleri dahildir.';

revoke execute on function public.get_student_attempt_trend(integer) from public, anon, authenticated;
grant execute on function public.get_student_attempt_trend(integer) to authenticated;

commit;