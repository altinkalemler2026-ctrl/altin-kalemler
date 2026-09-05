-- ============================================================
-- 097_faz5_restore_training_select_rate_limit.sql
-- Altın Kalemler - Migration Faz 5 (097)
--
-- APPEND-ONLY DÜZELTME: 096, select_training_questions gövdesini
-- "068 çekirdeği" ile yeniden yazarken 076'nın (Faz 4) fonksiyona
-- eklediği kullanıcı-bazlı sabit-pencereli rate-limit bağını
-- düşürmüştü (076: 'training_select' 90 / 3600 sn; bağlam/veri
-- işinden ÖNCE, reddedilen istek hiçbir şey tüketmez).
--
-- Bu migration 096'nın 4-arg gövdesini birebir koruyarak rate-limit
-- çağrısını 076'dakiyle AYNI konuma (auth.uid() kontrolünden hemen
-- sonra, p_limit doğrulamasından önce) geri getirir. İmza değişmez
-- (uuid, integer, uuid, uuid); overload yaratmaz; ACL'ler korunur.
--
-- Kanıt: qa_faz4_local_validation.sql T-14 (eşikte RATE, bağlam
-- hatası DEĞİL) 096 sonrası "hata beklenmisti ama uygulandi" ile
-- FAIL olmuştu; 097 ile yeniden PASS beklenir.
-- ============================================================

begin;


create or replace function public.select_training_questions(
  p_subject_id uuid,
  p_limit      integer default 10,
  p_topic_id   uuid    default null,
  p_outcome_id uuid    default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user        uuid;
  v_limit       integer;
  v_grade       smallint;
  v_profile     uuid;
  v_version     uuid;
  v_ctx_year    text;
  v_year        text;
  v_week        integer;
  v_topics      uuid[];
  v_outcomes    uuid[];
  v_remaining   integer;
  v_new_ids     uuid[];
  v_repeat_ids  uuid[];
  v_all_ids     uuid[];
  v_take        integer;
  v_need        integer;
  v_delta       integer;
  v_used        integer;
  v_payload     jsonb;
  r_row         record;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  -- FAZ4 (076): kullanıcı-bazlı sabit-pencere limiti; bağlam/veri işi
  -- tamamen ÖNCESİNDE. Reddedilen istek hiçbir şey tüketmez.
  -- 097: 096'nın düşürdüğü bağ, 076'dakiyle aynı konumda geri getirildi.
  perform public._faz4_consume_rate_limit('training_select', 90, 3600);

  v_limit := coalesce(p_limit, 10);
  if v_limit < 1 or v_limit > 50 then
    raise exception 'p_limit 1..50 araliginda olmalidir.'
      using errcode = '22023';
  end if;

  if p_topic_id is not null and p_outcome_id is not null then
    raise exception
      'Yalnizca konu veya kazanim filtresinden biri kullanilabilir.'
      using errcode = 'P0001';
  end if;

  select * into v_grade, v_profile, v_version, v_ctx_year
    from public._faz2_student_context(v_user);
  if v_grade is null or v_profile is null or v_version is null then
    raise exception 'Ogrenci baglami cozulemedi (profil/mufredat).'
      using errcode = 'P0001';
  end if;

  select * into v_year, v_week from public._faz2_require_period();

  -- ----------------------------------------------------------
  -- Sorulabilir kapsam: işlenmiş konular (kalıcı antrenman erişimi)
  -- ve işlenmiş kazanımlar. end_week bilinçli olarak KULLANILMAZ.
  -- ----------------------------------------------------------
  v_topics := array(
    select si.topic_id
      from public.curriculum_schedule_items si
     where si.schedule_profile_id = v_profile
       and si.grade_level = v_grade
       and si.subject_id = p_subject_id
       and si.is_active = true
       and si.start_week <= v_week
       and si.topic_id is not null
  );

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

  if coalesce(array_length(v_topics, 1), 0) = 0
     and coalesce(array_length(v_outcomes, 1), 0) = 0 then
    return jsonb_build_object(
      'questions', '[]'::jsonb,
      'new_count', 0,
      'repeat_count', 0,
      'reason', 'sorulabilir_kapsam_bos',
      'weekly', jsonb_build_object(
        'academic_year', v_year,
        'week', v_week,
        'new_questions_used', 0,
        'limit', 500
      )
    );
  end if;

  -- ----------------------------------------------------------
  -- FAZ 5 KAPSAM FİLTRESİ: filtre değeri öğrencinin KENDİ dönemi
  -- kapılı kapsamında doğrulanır; dışarıdan gelen başka sınıf /
  -- dönem kapsamı FAIL-CLOSED ile reddedilir.
  -- ----------------------------------------------------------
  if p_topic_id is not null then
    if not (p_topic_id = any(v_topics)) then
      return jsonb_build_object(
        'questions', '[]'::jsonb,
        'new_count', 0,
        'repeat_count', 0,
        'reason', 'gecersiz_kapsam',
        'weekly', jsonb_build_object(
          'academic_year', v_year,
          'week', v_week,
          'new_questions_used', 0,
          'limit', 500
        )
      );
    end if;
    v_topics := array[p_topic_id];
    v_outcomes := '{}';
  elsif p_outcome_id is not null then
    if not (p_outcome_id = any(v_outcomes)) then
      return jsonb_build_object(
        'questions', '[]'::jsonb,
        'new_count', 0,
        'repeat_count', 0,
        'reason', 'gecersiz_kapsam',
        'weekly', jsonb_build_object(
          'academic_year', v_year,
          'week', v_week,
          'new_questions_used', 0,
          'limit', 500
        )
      );
    end if;
    v_outcomes := array[p_outcome_id];
    v_topics := '{}';
  end if;

  -- ----------------------------------------------------------
  -- Kapasiteyi KİLİTLE (eşzamanlılık: iki paralel seçim aynı satır
  -- kilidinde serileşir; toplam 500'ü aşamaz).
  -- ----------------------------------------------------------
  v_remaining := public._faz2_lock_weekly_counter(
    v_user, v_year, v_week, p_subject_id
  );

  -- ----------------------------------------------------------
  -- Adaylar: aktif + onaylı + pratik eligibility + müfredat kapısı.
  -- Görülmüşlük HERHANGİ bir bağlamdaki exposure ile belirlenir.
  --
  -- F-4: eşleme onay kapısı (068 ile aynı). Kasa ayrılığı: yalnız
  -- practice üyeliği (vault_type competition/one_v_one HARİÇ).
  -- ----------------------------------------------------------
  v_take := least(v_limit, greatest(v_remaining, 0));

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
            and (
              exists (
                select 1
                  from public.question_curriculum_mappings cm
                 where cm.question_id = q.id
                   and cm.curriculum_version_id = v_version
                   and cm.topic_id = any(v_topics)
                   and cm.review_status = 'approved'
              )
              or exists (
                select 1
                  from public.question_outcome_mappings om
                 where om.question_id = q.id
                   and om.outcome_id = any(v_outcomes)
                   and om.review_status = 'approved'
              )
            )
      ) c
     where not c.seen
     order by c.qid
     limit v_take
  ), '{}');

  v_need := v_limit - coalesce(array_length(v_new_ids, 1), 0);

  if v_need > 0 then
    v_repeat_ids := coalesce(array(
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
              and (
                exists (
                  select 1
                    from public.question_curriculum_mappings cm
                   where cm.question_id = q.id
                     and cm.curriculum_version_id = v_version
                     and cm.topic_id = any(v_topics)
                     and cm.review_status = 'approved'
                )
                or exists (
                  select 1
                    from public.question_outcome_mappings om
                   where om.question_id = q.id
                     and om.outcome_id = any(v_outcomes)
                     and om.review_status = 'approved'
                )
              )
        ) c
       where c.seen
       order by c.qid
       limit v_need
    ), '{}');
  else
    v_repeat_ids := '{}';
  end if;

  v_all_ids := array(
    select u from unnest(v_new_ids) u
    union all
    select u from unnest(v_repeat_ids) u
  );

  -- ----------------------------------------------------------
  -- SHOW-TIME ATOMİK YAZIMI: exposure INSERT + sayaç artışı.
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
  -- Payload (hassas alanlardan temiz, deterministik sıralı).
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
    'new_count', coalesce(array_length(v_new_ids, 1), 0),
    'repeat_count', coalesce(array_length(v_repeat_ids, 1), 0),
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


-- ACL yeniden teyit (096 ile aynı; create or replace ACL'leri
-- korur, teyit idempotent ve savunmacıdır):

revoke execute
on function public.select_training_questions(uuid, integer, uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.select_training_questions(uuid, integer, uuid, uuid)
to authenticated;


commit;
