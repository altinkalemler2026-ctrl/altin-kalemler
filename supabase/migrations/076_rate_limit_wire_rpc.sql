-- ============================================================
-- 076_rate_limit_wire_rpc.sql
-- Altın Kalemler - Faz 4 (076): Rate limit'in RPC'lere bağlanması
--
-- Yöntem: 074 drift-guard deseniyle dört öğrenci RPC'sinin
-- create or replace ile yeniden yayınlanması. Gövdeler 068/070'ten
-- BIREBIR kopyalanmıştır; TEK fark, her gövdeye eklenen
-- _faz4_consume_rate_limit çağrısıdır (aşağıda "FAZ4" imli).
--
-- Bağlantı matrisi (kullanıcı onaylı Faz 4 tasarımı):
--   select_training_questions : 'training_select' 90 / 3600 sn
--                                (auth sonrası, her şeyden önce)
--   get_my_weekly_usage       : 'weekly_usage'    60 /  300 sn
--   prepare_competition_pack  : 'pack_prepare'    30 / 3600 sn
--                                (yarışma satırı kilidinden önce)
--   submit_training_attempt   : 'training_submit'240 / 3600 sn
--                                (duplicate ön-okumasından SONRA:
--                                 replay kota tüketmez)
--
-- Korunan davranışlar: auth.uid(), dönem fail-closed, haftalık 500
-- yeni soru sınırı, exposure/puanlama/idempotency mantığı,
-- EXECUTE matrisi (071) — sonda bilinçli olarak yeniden teyit edilir.
-- ============================================================

begin;


-- ============================================================
-- 1. SELECT_TRAINING_QUESTIONS(uuid, integer)   [068 birebir + FAZ4]
-- ============================================================

create or replace function public.select_training_questions(
  p_subject_id uuid,
  p_limit      integer default 10
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

  -- FAZ4: kullanici-bazli sabit-pencere limiti; baglam/veri isi
  -- tamamen ONCESINDE. Reddedilen istek hicbir sey tuketmez.
  perform public._faz4_consume_rate_limit('training_select', 90, 3600);

  v_limit := coalesce(p_limit, 10);
  if v_limit < 1 or v_limit > 50 then
    raise exception 'p_limit 1..50 araliginda olmalidir.'
      using errcode = '22023';
  end if;

  select * into v_grade, v_profile, v_version, v_ctx_year
    from public._faz2_student_context(v_user);
  if v_grade is null or v_profile is null or v_version is null then
    raise exception 'Ogrenci baglami cozulemedi (profil/mufredat).'
      using errcode = 'P0001';
  end if;

  select * into v_year, v_week from public._faz2_require_period();

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

  v_remaining := public._faz2_lock_weekly_counter(
    v_user, v_year, v_week, p_subject_id
  );

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
                select 1 from public.question_curriculum_mappings cm
                 where cm.question_id = q.id
                   and cm.curriculum_version_id = v_version
                   and cm.topic_id = any(v_topics)
                   and cm.review_status = 'approved'
              )
              or exists (
                select 1 from public.question_outcome_mappings om
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
                  select 1 from public.question_curriculum_mappings cm
                   where cm.question_id = q.id
                     and cm.curriculum_version_id = v_version
                     and cm.topic_id = any(v_topics)
                     and cm.review_status = 'approved'
                )
                or exists (
                  select 1 from public.question_outcome_mappings om
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


-- ============================================================
-- 2. GET_MY_WEEKLY_USAGE()   [068 birebir + FAZ4]
-- ============================================================

create or replace function public.get_my_weekly_usage()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid;
  v_year  text;
  v_week  integer;
  v_rows  jsonb;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  -- FAZ4: ucuz okuma icin cömert döngü koruması (5 dakika / 60).
  perform public._faz4_consume_rate_limit('weekly_usage', 60, 300);

  select * into v_year, v_week from public._faz2_require_period();

  select coalesce(jsonb_agg(jsonb_build_object(
           'subject_id', c.subject_id,
           'new_questions_used', c.new_questions_used,
           'limit', 500
         ) order by c.subject_id), '[]'::jsonb)
    into v_rows
    from public.student_weekly_counters c
   where c.user_id = v_user
     and c.academic_year = v_year
     and c.week = v_week;

  return jsonb_build_object(
    'academic_year', v_year,
    'week', v_week,
    'subjects', v_rows
  );
end;
$$;


-- ============================================================
-- 3. PREPARE_COMPETITION_PACK(uuid)   [068 birebir + FAZ4]
-- ============================================================

create or replace function public.prepare_competition_pack(
  p_competition_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user        uuid;
  r_comp        public.competitions%rowtype;
  v_pack_type   text;
  v_flag_ok     boolean;
  v_players     uuid[];
  p             uuid;
  v_vault       uuid;
  v_qids        uuid[];
  v_chosen_from text;
  i             integer;
  v_ctx_year    text;
  v_ctx_profile uuid;
  v_ctx_version uuid;
  v_ctx_grade   smallint;
  v_year        text;
  v_week        integer;
  v_remaining   integer;
  v_new_all     uuid[];
  v_take_n      integer;
  v_delta       integer;
  v_used        integer;
  v_per_player  jsonb := '{}'::jsonb;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  -- FAZ4: agir paket seciminden ve yarisma satiri kilidinden ONCE.
  perform public._faz4_consume_rate_limit('pack_prepare', 30, 3600);

  select * into r_comp
    from public.competitions c
   where c.id = p_competition_id
   for update;

  if r_comp.id is null then
    raise exception 'Yarisma bulunamadi.'
      using errcode = 'P0001';
  end if;

  if r_comp.status not in ('waiting', 'ready') then
    raise exception
      'Yarisma durumu paket hazirlamaya izin vermiyor (%).', r_comp.status
      using errcode = 'P0001';
  end if;

  if exists (
       select 1 from public.competition_questions cq
        where cq.competition_id = r_comp.id
     ) then
    raise exception
      'Yarisma snapshot''i zaten olusturulmus; degistirilemez.'
      using errcode = 'P0001';
  end if;

  if r_comp.configuration ? 'faz2_pack' then
    raise exception
      'Bu yarisma icin paket zaten secildi.'
      using errcode = 'P0001';
  end if;

  if not exists (
       select 1 from public.competition_players cp
        where cp.competition_id = r_comp.id
          and cp.user_id = v_user
     ) then
    raise exception
      'Bu yarismanin katilimcisi degilsiniz.'
      using errcode = '42501';
  end if;

  if r_comp.subject_id is null then
    raise exception
      'Yarismanin ders bilgisi yok; paket secimi fail-closed.'
      using errcode = 'P0001';
  end if;

  select array(
    select cp.user_id
      from public.competition_players cp
     where cp.competition_id = r_comp.id
     order by cp.player_slot
  )
  into v_players;

  if coalesce(array_length(v_players, 1), 0) <> 2 then
    raise exception
      'Yarismada iki oyuncu bulunmali.'
      using errcode = 'P0001';
  end if;

  v_pack_type := case
    when r_comp.competition_type = 'one_vs_one' then 'one_v_one'
    else 'competition'
  end;

  v_flag_ok := (v_pack_type = 'one_v_one');

  select v.id into v_vault
    from public.question_vaults v
   where v.vault_type = v_pack_type
     and v.is_active = true
     and v.grade_level = r_comp.grade_level
     and v.subject_id = r_comp.subject_id
     and (
       select count(*)
         from public.question_vault_memberships m
        where m.vault_id = v.id
          and m.membership_status = 'active'
          and (case when v_flag_ok
                    then m.one_v_one_eligible
                    else m.competition_eligible end) = true
     ) = r_comp.question_count
     and not exists (
       select 1 from public.student_pack_exposures pe
        where pe.vault_id = v.id
          and pe.user_id = any(v_players)
     )
   order by v.id
   limit 1;

  if v_vault is not null then
    v_chosen_from := 'A';
  else
    select v.id into v_vault
      from public.question_vaults v
     where v.vault_type = v_pack_type
       and v.is_active = true
       and v.grade_level = r_comp.grade_level
       and v.subject_id = r_comp.subject_id
       and (
         select count(*)
           from public.question_vault_memberships m
          where m.vault_id = v.id
            and m.membership_status = 'active'
            and (case when v_flag_ok
                      then m.one_v_one_eligible
                      else m.competition_eligible end) = true
            and not exists (
              select 1 from public.student_question_exposures qe
               where qe.user_id = any(v_players)
                 and qe.question_id = m.question_id
            )
       ) >= r_comp.question_count
     order by v.id
     limit 1;

    if v_vault is null then
      raise exception 'Uygulanabilir ortak gorulmemis paket kasa yok.'
        using errcode = 'P0001';
    end if;

    v_chosen_from := 'B';
  end if;

  perform 1 from public.question_vaults v where v.id = v_vault for update;

  if (select count(*)
        from public.question_vault_memberships m
       where m.vault_id = v_vault
         and m.membership_status = 'active'
         and (case when v_flag_ok
                   then m.one_v_one_eligible
                   else m.competition_eligible end) = true) < r_comp.question_count
  then
    raise exception 'Paket kasasi uyari sonrasi gecersizlesti.'
      using errcode = 'P0001';
  end if;

  if v_chosen_from = 'A' then
    v_qids := array(
      select m.question_id
        from public.question_vault_memberships m
       where m.vault_id = v_vault
         and m.membership_status = 'active'
         and (case when v_flag_ok
                   then m.one_v_one_eligible
                   else m.competition_eligible end) = true
       order by m.question_id
       limit r_comp.question_count
    );
  else
    v_qids := array(
      select m.question_id
        from public.question_vault_memberships m
       where m.vault_id = v_vault
         and m.membership_status = 'active'
         and (case when v_flag_ok
                   then m.one_v_one_eligible
                   else m.competition_eligible end) = true
         and not exists (
           select 1 from public.student_question_exposures qe
            where qe.user_id = any(v_players)
              and qe.question_id = m.question_id
         )
       order by m.question_id
       limit r_comp.question_count
    );
  end if;

  insert into public.student_pack_exposures
    (user_id, vault_id, attempt_context)
  select pl, v_vault, v_pack_type
    from unnest(v_players) pl
  on conflict do nothing;

  foreach p in array v_players loop
    select * into v_ctx_grade, v_ctx_profile, v_ctx_version, v_ctx_year
      from public._faz2_student_context(p);

    if v_ctx_version is null then
      raise exception
        'Oyuncu baglami cozulemedi; paket yazimi durduruldu.'
        using errcode = 'P0001';
    end if;

    select * into v_year, v_week from public._faz2_require_period();

    v_remaining := public._faz2_lock_weekly_counter(
      p, v_year, v_week, r_comp.subject_id
    );

    v_new_all := array(
      select u
        from unnest(v_qids) u
       where not exists (
         select 1 from public.student_question_exposures e
          where e.user_id = p
            and e.question_id = u
       )
       order by u
    );

    v_take_n := least(
      coalesce(array_length(v_new_all, 1), 0),
      greatest(coalesce(v_remaining, 0), 0)
    );

    v_delta := 0;
    if v_take_n > 0 then
      with ins as (
        insert into public.student_question_exposures
          (user_id, question_id, attempt_context)
        select p, u, v_pack_type
          from (
            select u from unnest(v_new_all) u
            order by u
            limit v_take_n
          ) pick
        on conflict do nothing
        returning question_id
      )
      select count(*) into v_delta from ins;
    end if;

    if v_delta > 0 then
      begin
        perform public._faz2_consume_weekly_capacity(
          p, v_year, v_week, r_comp.subject_id, v_delta::integer
        );
      exception when others then
        null;  -- clamp: yarışma gösterimi geri alınamaz
      end;
    end if;

    select c.new_questions_used into v_used
      from public.student_weekly_counters c
     where c.user_id = p
       and c.academic_year = v_year
       and c.week = v_week
       and c.subject_id = r_comp.subject_id;

    v_per_player := v_per_player || jsonb_build_array(jsonb_build_object(
      'user_id', p,
      'exposed_now', v_delta,
      'skipped_by_cap', coalesce(array_length(v_new_all, 1), 0) - v_delta,
      'new_questions_used', coalesce(v_used, 0)
    ));
  end loop;

  update public.competitions c
     set configuration = c.configuration ||
         jsonb_build_object(
           'faz2_pack',
           jsonb_build_object(
             'vault_id', v_vault,
             'context', v_pack_type,
             'priority', v_chosen_from,
             'question_ids', to_jsonb(v_qids),
             'selected_at', now()
           )
         ),
         updated_at = now()
   where c.id = r_comp.id;

  if not found then
    raise exception
      'Paket metadata yazimi basarisiz; yarisma kaybolmus olabilir.'
      using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'competition_id', r_comp.id,
    'vault_id', v_vault,
    'priority', v_chosen_from,
    'context', v_pack_type,
    'question_ids', to_jsonb(v_qids),
    'players', v_per_player
  );
end;
$$;


-- ============================================================
-- 4. SUBMIT_TRAINING_ATTEMPT(...)   [070 birebir + FAZ4]
--    Sıralama kritiği: duplicate/replay ön-okuması rate-limitten
--    ÖNCE kalır -> replay kota tüketmez, her zaman gerçek yanıt.
-- ============================================================

create or replace function public.submit_training_attempt(
  p_question_id uuid,
  p_choice      text    default null,
  p_action      text    default null,
  p_time_ms     integer default null,
  p_client_key  uuid    default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user     uuid;
  v_choice   text;
  v_correct  text;
  v_result   text;
  v_time_ms  integer;
  v_prior    record;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  if p_question_id is null then
    raise exception 'Soru zorunludur.'
      using errcode = '22004';
  end if;

  if p_client_key is null then
    raise exception 'Idempotency anahtari (p_client_key) zorunludur.'
      using errcode = '22004';
  end if;

  v_time_ms := least(greatest(coalesce(p_time_ms, 0), 0), 3600000);

  if p_choice is not null and p_action is not null then
    raise exception 'Secim ve eylem birlikte gonderilemez.'
      using errcode = 'P0001';
  end if;

  if p_choice is not null then
    v_choice := upper(btrim(p_choice));
    if v_choice not in ('A', 'B', 'C', 'D', 'E') then
      raise exception 'Gecersiz sik secimi.'
        using errcode = 'P0001';
    end if;

    select q.correct_answer
      into v_correct
      from public.questions q
     where q.id = p_question_id
       and q.is_active;

    if v_correct is null then
      raise exception 'Soru puanlanamaz; cevap anahtari yok ya da soru aktif degil.'
        using errcode = 'P0001';
    end if;

    v_result := case when v_choice = v_correct
                     then 'correct'
                     else 'wrong'
                end;

  elsif p_action is not null then
    if btrim(p_action) not in ('pass', 'timeout', 'blank') then
      raise exception 'Gecersiz eylem; pass|timeout|blank bekleniyor.'
        using errcode = 'P0001';
    end if;
    v_result := btrim(p_action);

  else
    raise exception 'Secim (p_choice) veya eylem (p_action) zorunludur.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1
      from public.student_question_exposures e
     where e.user_id = v_user
       and e.question_id = p_question_id
       and e.attempt_context = 'training'
  ) then
    raise exception 'Bu soru size antrenman baglaminda gosterilmedi.'
      using errcode = 'P0001';
  end if;

  select a.id, a.attempt_number, a.result
    into v_prior
    from public.student_question_attempts a
   where a.user_id = v_user
     and a.attempt_context = 'training'
     and a.metadata ->> 'client_key' = p_client_key::text
   limit 1;

  if found then
    return jsonb_build_object(
      'attempt_id',     v_prior.id,
      'attempt_number', v_prior.attempt_number,
      'result',         v_prior.result,
      'duplicate',      true
    );
  end if;

  -- FAZ4: rate limit DUPLICATE ON-OKUMASINDAN SONRA. Replay yolu
  -- yukarida erken dondugu icin kota tüketmez; yalnız gerçek yeni
  -- yazım buraya ulaşır ve sayılır.
  perform public._faz4_consume_rate_limit('training_submit', 240, 3600);

  begin
    perform public.ingest_student_attempt(
      p_question_id,
      'training',
      v_result,
      v_time_ms,
      null,
      jsonb_build_object(
        'client_key', p_client_key::text,
        'graded_by',  'db_correct_answer'
      )
    );
  exception
    when unique_violation then
      select a.id, a.attempt_number, a.result
        into v_prior
        from public.student_question_attempts a
       where a.user_id = v_user
         and a.attempt_context = 'training'
         and a.metadata ->> 'client_key' = p_client_key::text
       limit 1;

      if not found then
        raise;
      end if;

      return jsonb_build_object(
        'attempt_id',     v_prior.id,
        'attempt_number', v_prior.attempt_number,
        'result',         v_prior.result,
        'duplicate',      true
      );
  end;

  select a.id, a.attempt_number, a.result
    into v_prior
    from public.student_question_attempts a
   where a.user_id = v_user
     and a.attempt_context = 'training'
     and a.metadata ->> 'client_key' = p_client_key::text
   limit 1;

  return jsonb_build_object(
    'attempt_id',     v_prior.id,
    'attempt_number', v_prior.attempt_number,
    'result',         v_prior.result,
    'duplicate',      false
  );
end;
$$;


-- ============================================================
-- 5. EXECUTE MATRİSİ (drift guard; 071 durumu korunur)
-- ============================================================

revoke execute
on function public.select_training_questions(uuid, integer)
from public, anon, authenticated;
grant execute
on function public.select_training_questions(uuid, integer)
to authenticated;

revoke execute
on function public.get_my_weekly_usage()
from public, anon, authenticated;
grant execute
on function public.get_my_weekly_usage()
to authenticated;

revoke execute
on function public.prepare_competition_pack(uuid)
from public, anon, authenticated;
grant execute
on function public.prepare_competition_pack(uuid)
to authenticated;

revoke execute
on function public.submit_training_attempt(uuid, text, text, integer, uuid)
from public, anon, authenticated;
grant execute
on function public.submit_training_attempt(uuid, text, text, integer, uuid)
to authenticated;


commit;
