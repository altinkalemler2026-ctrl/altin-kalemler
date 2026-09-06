-- ============================================================
-- 098_faz6_targeted_review.sql
-- Altın Kalemler - Migration Faz 6: Hedefli Tekrar ve Kazanım Analitiği
--
-- AMAÇ (docs/project/faz6-tasarim.md ile birebir):
--   1. get_outcome_review_plan(p_subject_id): öğrencinin KENDİ dönem-
--      kapılı kazanımları için kazanım analitiği + tekrar etkisi özeti.
--      Yetersiz veride yüzde NULL (yanıltıcı yüzde engellenir).
--   2. select_targeted_review_questions(p_subject_id, p_outcome_id,
--      p_limit): deterministik, öğrenciye özgü tekrar oturumu. Genel
--      konu listesine yönlendirme DEĞİL; öğrencinin kendi yanlışları
--      (hata havuzu) öncelikli. Aynı yanlışın gereksiz tekrarı
--      cooldown (UTC takvim günü) ile sınırlandırılır.
--
-- GÜVENLİK MODELİ (mevcut desenlerle aynı):
--   - Her iki RPC SECURITY DEFINER + set search_path='' + auth.uid()
--     türetimi; kullanıcı parametresi YOKTUR (başkasının analitiği
--     okunamaz).
--   - Kapsam kapısı: outcome, öğrencinin kendi dönem-kapılı işlenmiş
--     kazanımı değilse FAIL-CLOSED (reason='gecersiz_kapsam').
--   - Rate limit: _faz4_consume_rate_limit('targeted_review_select',
--     30, 3600) — auth kontrolünden HEMEN sonra (076/097 konumu);
--     reddedilen istek hiçbir şey tüketmez.
--   - ACL: tam revoke → yalnız authenticated grant.
--
-- SİSTEMİK RİSK ÖNLEMİ: mevcut fonksiyonlara CREATE OR REPLACE ile
-- DOKUNULMAZ (Faz 5 SYSTEMIC_MIGRATION_REPLACEMENT_RISK dersleri);
-- yalnız YENİ fonksiyonlar eklenir. Tablo/kolon/RLS değişikliği YOK.
--
-- DETERMİNİZM: random YOK. Havuz sırası question_id ASC; en-son-deneme
-- çözümlemesi (answered_at DESC, id DESC) belirli tie-break ile.
-- ============================================================

begin;


-- ============================================================
-- 1. GET_OUTCOME_REVIEW_PLAN: KAZANIM ANALİTİĞİ + TEKRAR ETKİSİ
-- ============================================================

create or replace function public.get_outcome_review_plan(
  p_subject_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user     uuid;
  v_grade    smallint;
  v_profile  uuid;
  v_version  uuid;
  v_ctx_year text;
  v_year     text;
  v_week     integer;
  v_today    date;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  if p_subject_id is null then
    raise exception 'Ders zorunludur.'
      using errcode = '22004';
  end if;

  select * into v_grade, v_profile, v_version, v_ctx_year
    from public._faz2_student_context(v_user);
  if v_grade is null or v_profile is null or v_version is null then
    raise exception 'Ogrenci baglami cozulemedi (profil/mufredat).'
      using errcode = 'P0001';
  end if;

  select * into v_year, v_week from public._faz2_require_period();

  v_today := (current_timestamp at time zone 'utc')::date;

  return coalesce(
    jsonb_agg(
      jsonb_build_object(
        'outcome_id',        p.outcome_id,
        'outcome_text',      p.outcome_text,
        'band',              p.band,
        'total_attempts',    p.total_attempts,
        'success_rate',      p.success_rate,
        'repeat_total',      p.repeat_total,
        'repeat_success_rate', p.repeat_success_rate,
        'pending_errors',    p.pending_errors,
        'redeemed',          p.redeemed,
        'redeem_rate',       p.redeem_rate,
        'last_reviewed_at',  p.last_reviewed_at
      )
      order by
        case p.band
          when 'weak' then 1
          when 'developing' then 2
          when 'strong' then 3
          else 4
        end,
        p.total_attempts desc,
        p.outcome_text,
        p.outcome_id
    ),
    '[]'::jsonb
  )
  from (
    -- --------------------------------------------------------
    -- Dönem kapısı (096 ile aynı): öğrencinin KENDİ sınıf + dönem
    -- kapılı işlenmiş kazanımları; ders/sürüm/sınıf eşleşmeli.
    -- --------------------------------------------------------
    select
      si.outcome_id,
      coalesce(co.outcome_text, si.outcome_id::text) as outcome_text,
      coalesce(d.total_attempts, 0)::integer          as total_attempts,
      coalesce(d.correct_count, 0)::integer           as correct_count,
      coalesce(d.repeat_total, 0)::integer            as repeat_total,
      coalesce(d.repeat_correct, 0)::integer          as repeat_correct,
      coalesce(d.last_attempted_at, eff.last_reviewed_at) as last_attempted_at,
      eff.pending_errors,
      eff.redeemed,
      eff.last_reviewed_at,
      -- Band eşikleri (SABİT ürün kararı, docs/project/faz6-tasarim.md):
      --   total < 5 → insufficient_data (yüzde NULL);
      --   rate < 40 weak; 40..70 developing; >= 70 strong.
      case
        when coalesce(d.total_attempts, 0) < 5 then 'insufficient_data'
        when public.calculate_accuracy(
               coalesce(d.correct_count, 0)::integer,
               coalesce(d.total_attempts, 0)::integer) < 40 then 'weak'
        when public.calculate_accuracy(
               coalesce(d.correct_count, 0)::integer,
               coalesce(d.total_attempts, 0)::integer) < 70 then 'developing'
        else 'strong'
      end as band,
      -- Yetersiz veride yüzde YOK (NULL) — yanıltıcı yüzde engellenir.
      case
        when coalesce(d.total_attempts, 0) < 5 then null
        else public.calculate_accuracy(
               coalesce(d.correct_count, 0)::integer,
               coalesce(d.total_attempts, 0)::integer)
      end as success_rate,
      -- repeat_success_rate 085 konvansiyonu (tekrar yoksa 0).
      case
        when coalesce(d.repeat_total, 0) > 0
          then round((coalesce(d.repeat_correct, 0)::numeric
                      / d.repeat_total::numeric) * 100, 1)
        else 0
      end::numeric as repeat_success_rate,
      -- Tekrar etkisi: payda < 5 İSE NULL (MIN_REDEEM_EVIDENCE).
      case
        when coalesce(eff.pending_errors, 0) + coalesce(eff.redeemed, 0) < 5
          then null
        else round(
               (coalesce(eff.redeemed, 0)::numeric
                / (coalesce(eff.pending_errors, 0)
                   + coalesce(eff.redeemed, 0))::numeric) * 100, 1)
      end::numeric as redeem_rate
    from public.curriculum_schedule_items si
    left join public.curriculum_outcomes co
      on co.id = si.outcome_id
     and co.subject_id = p_subject_id
     and co.grade_level = v_grade
     and co.curriculum_version_id = v_version
    left join public.student_dimension_metrics d
      on d.user_id = v_user
     and d.metric_scope = 'outcome'
     and d.scope_key = si.outcome_id::text
    left join lateral (
      -- ------------------------------------------------------
      -- Tekrar etkisi fact'leri (yalnız KENDİ training denemeleri):
      --   pending_errors: en son training denemesi 'correct' olmayan
      --     soru sayısı (wrong/blank/pass/timeout).
      --   redeemed: en son denemesi 'correct' olan, ama daha önce
      --     en az bir başarısız denemesi bulunan soru sayısı.
      -- En-son-deneme: answered_at DESC, id DESC (belirli tie-break).
      -- ------------------------------------------------------
      select
        count(*) filter (where x.last_result <> 'correct')::integer
          as pending_errors,
        count(*) filter (where x.last_result = 'correct'
                          and x.had_nonsuccess)::integer
          as redeemed,
        max(x.last_answered_at) as last_reviewed_at
      from (
        select a.question_id,
               (array_agg(a.result
                          order by a.answered_at desc, a.id))[1]
                 as last_result,
               bool_or(a.result <> 'correct') as had_nonsuccess,
               max(a.answered_at)             as last_answered_at
          from public.student_question_attempts a
          join public.question_outcome_mappings om
            on om.question_id = a.question_id
           and om.outcome_id = si.outcome_id
           and om.review_status = 'approved'
         where a.user_id = v_user
           and a.attempt_context = 'training'
         group by a.question_id
      ) x
    ) eff on true
     where si.schedule_profile_id = v_profile
       and si.grade_level = v_grade
       and si.subject_id = p_subject_id
       and si.is_active = true
       and si.start_week <= v_week
       and si.outcome_id is not null
  ) p;
end;
$$;

comment on function public.get_outcome_review_plan(uuid) is
  'Faz 6: ogrencinin kendi donem-kapili kazanimlari icin analitik + tekrar etkisi. Yetersiz veride yuzde NULL; redeem paydasi < 5 ise redeem_rate NULL. Kimlik yalniz auth.uid().';


-- ============================================================
-- 2. SELECT_TARGETED_REVIEW_QUESTIONS: DETERMİNİSTİK TEKRAR OTURUMU
-- ============================================================

create or replace function public.select_targeted_review_questions(
  p_subject_id uuid,
  p_outcome_id uuid,
  p_limit      integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user       uuid;
  v_limit      integer;
  v_grade      smallint;
  v_profile    uuid;
  v_version    uuid;
  v_ctx_year   text;
  v_year       text;
  v_week       integer;
  v_today      date;
  v_outcomes   uuid[];
  v_remaining  integer;
  v_wrong_ids  uuid[];
  v_new_ids    uuid[];
  v_all_ids    uuid[];
  v_need       integer;
  v_delta      integer;
  v_used       integer;
  v_payload    jsonb;
  r_row        record;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  -- FAZ4 desenindekiyle AYNI konum: auth sonrası, iş ÖNCESİ.
  perform public._faz4_consume_rate_limit('targeted_review_select', 30, 3600);

  if p_subject_id is null or p_outcome_id is null then
    raise exception 'Ders ve kazanim zorunludur.'
      using errcode = '22004';
  end if;

  v_limit := coalesce(p_limit, 5);
  if v_limit < 1 or v_limit > 10 then
    raise exception 'p_limit 1..10 araliginda olmalidir.'
      using errcode = '22023';
  end if;

  select * into v_grade, v_profile, v_version, v_ctx_year
    from public._faz2_student_context(v_user);
  if v_grade is null or v_profile is null or v_version is null then
    raise exception 'Ogrenci baglami cozulemedi (profil/mufredat).'
      using errcode = 'P0001';
  end if;

  select * into v_year, v_week from public._faz2_require_period();

  v_today := (current_timestamp at time zone 'utc')::date;

  -- ----------------------------------------------------------
  -- KAPSAM KAPISI (096 fail-closed deseni): outcome öğrencinin
  -- KENDİ dönem-kapılı işlenmiş kazanımı değilse kapsam dışı
  -- içerik NE hata ile ne de veri ile sızar.
  -- ----------------------------------------------------------
  v_outcomes := array(
    select si.outcome_id
      from public.curriculum_schedule_items si
     where si.schedule_profile_id = v_profile
       and si.grade_level = v_grade
       and si.subject_id = p_subject_id
       and si.is_active = true
       and si.start_week <= v_week
       and si.outcome_id is not null
  );

  if not (p_outcome_id = any(v_outcomes)) then
    return jsonb_build_object(
      'questions', '[]'::jsonb,
      'session_kind', 'targeted_review',
      'outcome_id', p_outcome_id,
      'wrong_review_count', 0,
      'new_count', 0,
      'reason', 'gecersiz_kapsam',
      'weekly', jsonb_build_object(
        'academic_year', v_year,
        'week', v_week,
        'subject_id', p_subject_id,
        'new_questions_used', 0,
        'limit', 500
      )
    );
  end if;

  -- ----------------------------------------------------------
  -- HATA HAVUZU (öğrenciye özgü): outcome'daki sorulardan en son
  -- training denemesi 'correct' olmayan sorular.
  --   COOLDOWN: en son training denemesi BUGÜN (UTC takvim günü)
  --   içinde yapılmışsa havuz DIŞI — aynı yanlışın gereksiz tekrarı
  --   sınırlandırılır (dökümante sabit kural: REDEEM_COOLDOWN = 1 gün).
  -- Sıra: question_id ASC (deterministik; random YOK).
  -- ----------------------------------------------------------
  v_wrong_ids := coalesce(array(
    select x.question_id
      from (
        select a.question_id,
               (array_agg(a.result
                          order by a.answered_at desc, a.id))[1]
                 as last_result,
               max(a.answered_at) as last_answered_at
          from public.student_question_attempts a
          join public.question_outcome_mappings om
            on om.question_id = a.question_id
           and om.outcome_id = p_outcome_id
           and om.review_status = 'approved'
          join public.questions q
            on q.id = a.question_id
           and q.is_active = true
           and q.approval_status = 'approved'
           and q.subject_id = p_subject_id
           and q.grade_level = v_grade
         where a.user_id = v_user
           and a.attempt_context = 'training'
         group by a.question_id
      ) x
     where x.last_result <> 'correct'
       and (x.last_answered_at at time zone 'utc')::date < v_today
     order by x.question_id
     limit v_limit
  ), '{}');

  if coalesce(array_length(v_wrong_ids, 1), 0) = 0 then
    return jsonb_build_object(
      'questions', '[]'::jsonb,
      'session_kind', 'targeted_review',
      'outcome_id', p_outcome_id,
      'wrong_review_count', 0,
      'new_count', 0,
      'reason', 'tekrar_gerekmiyor',
      'weekly', jsonb_build_object(
        'academic_year', v_year,
        'week', v_week,
        'subject_id', p_subject_id,
        'new_questions_used', 0,
        'limit', 500
      )
    );
  end if;

  -- ----------------------------------------------------------
  -- Tamamlama: kalan slotlar YENİ görülmemiş sorulardan (096
  -- eligible-gates: aktif + approved + practice membership +
  -- müfredat mapping approved). Haftalık kapasite kilidi yalnız
  -- yeni soru için; havuz soruları zaten exposure sahiptir.
  -- ----------------------------------------------------------
  v_need := v_limit - coalesce(array_length(v_wrong_ids, 1), 0);

  if v_need > 0 then
    v_remaining := public._faz2_lock_weekly_counter(
      v_user, v_year, v_week, p_subject_id
    );

    v_new_ids := coalesce(array(
      select c.qid
        from (
          select q.id as qid,
                 exists(
                   select 1 from public.student_question_exposures e
                    where e.user_id = v_user
                      and e.question_id = q.id
                 ) as seen
            from public.questions q
           where q.subject_id = p_subject_id
             and q.grade_level = v_grade
             and q.is_active = true
             and q.approval_status = 'approved'
             and exists (
                   select 1
                     from public.question_vault_memberships m
                     join public.question_vaults v
                       on v.id = m.vault_id
                    where m.question_id = q.id
                      and m.membership_status = 'active'
                      and m.practice_eligible = true
                      and v.is_active = true
                      and v.vault_type not in ('competition', 'one_v_one')
               )
             and exists (
                   select 1
                     from public.question_outcome_mappings om
                    where om.question_id = q.id
                      and om.outcome_id = p_outcome_id
                      and om.review_status = 'approved'
               )
        ) c
       where not c.seen
       order by c.qid
       limit least(v_need, greatest(v_remaining, 0))
    ), '{}');
  else
    v_new_ids := '{}';
  end if;

  v_all_ids := array(
    select u from unnest(v_wrong_ids) u
    union all
    select u from unnest(v_new_ids) u
  );

  -- ----------------------------------------------------------
  -- YENİ sorular için SHOW-TIME ATOMİK YAZIMI (096 deseni).
  -- ----------------------------------------------------------
  v_delta := 0;
  if coalesce(array_length(v_new_ids, 1), 0) > 0 then
    with ins as (
      insert into public.student_question_exposures
        (user_id, question_id, attempt_context)
      select v_user, u, 'training'
        from unnest(v_new_ids) u
      on conflict do nothing
      returning question_id
    )
    select count(*) into v_delta from ins;
  end if;

  if v_delta > 0 then
    perform public._faz2_consume_weekly_capacity(
      v_user, v_year, v_week, p_subject_id, v_delta::integer
    );
  end if;

  select c.new_questions_used into v_used
    from public.student_weekly_counters c
   where c.user_id = v_user
     and c.academic_year = v_year
     and c.week = v_week
     and c.subject_id = p_subject_id;

  -- ----------------------------------------------------------
  -- Payload (096 ile aynı sanitizer; hassas alan sızması YOK).
  -- ----------------------------------------------------------
  v_payload := '[]'::jsonb;
  for r_row in
    select qn.id, public._faz2_sanitize_question_payload(to_jsonb(qn)) as pb
      from public.questions qn
     where qn.id = any(v_all_ids)
     order by array_position(v_all_ids, qn.id)
  loop
    v_payload := v_payload || jsonb_build_array(r_row.pb);
  end loop;

  return jsonb_build_object(
    'questions', v_payload,
    'session_kind', 'targeted_review',
    'outcome_id', p_outcome_id,
    'wrong_review_count', coalesce(array_length(v_wrong_ids, 1), 0),
    'new_count', coalesce(array_length(v_new_ids, 1), 0),
    'reason', null,
    'weekly', jsonb_build_object(
      'academic_year', v_year,
      'week', v_week,
      'subject_id', p_subject_id,
      'new_questions_used', coalesce(v_used, 0),
      'limit', 500
    )
  );
end;
$$;

comment on function public.select_targeted_review_questions(uuid, uuid, integer) is
  'Faz 6: deterministik hedefli tekrar secimi. Hata havuzu (en son training denemesi correct olmayan sorular, bugun cooldown) oncelikli; kalan yeni sorularla dolar. Kapsam fail-closed; rate limit 30/3600sn.';


-- ============================================================
-- 3. EXECUTE İZİNLERİ
-- ============================================================

revoke execute
on function public.get_outcome_review_plan(uuid)
from public, anon, authenticated;

grant execute
on function public.get_outcome_review_plan(uuid)
to authenticated;

revoke execute
on function public.select_targeted_review_questions(uuid, uuid, integer)
from public, anon, authenticated;

grant execute
on function public.select_targeted_review_questions(uuid, uuid, integer)
to authenticated;


commit;
