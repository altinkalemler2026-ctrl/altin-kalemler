-- ============================================================
-- 104_faz9_gamification_wiring.sql
-- Altın Kalemler - Migration Faz 9 (104): mevcut akışlara bağlantı.
--
-- APPEND-ONLY YENİDEN TANIMLAR (mevcut davranış birebir korunur,
-- yalnız Faz 9 bağlantıları eklenir):
--
--   1. ingest_student_attempt      (069 birebir + FAZ9 bloğu)
--      - training bağlamında correct → XP grant (easy 2/medium 3/
--        hard 5; yanlış/pas/timeout/boş 0 XP, ledger kaydı yok).
--      - training bağlamında correct/wrong → günlük aktivite + seri.
--      - Idempotency: attempt başına tek XP olayı (103 UNIQUE),
--        aynı gün ikinci etkinlik seriyi değiştirmez.
--
--   2. select_training_questions   (097 birebir + FAZ9 günlük kota)
--   3. select_targeted_review_questions (098 birebir + FAZ9 kota)
--      - Günlük 500 soru kotası (yeni + tekrar; yarışma paketi
--        HARİÇ — prepare_competition_pack'e dokunulmaz).
--      - Kota dolunca teslim YOK: reason='gunluk_kota_doldu',
--        boş soru listesi. Reddedilen istek hiçbir şey tüketmez
--        (kota kilidi teslimden önce kalan hakkı döndürür, yalnız
--        teslim edilen soru kadar tüketilir).
--      - Mevcut haftalık 500 YENİ soru zinciri (063/068) AYNEN
--        korunur ve çağrı sırası değişmez.
--
--   4. _faz5_apply_competition_points (102 birebir + FAZ9 bloğu)
--      - Rating döngüsünün başında (lig yapılandırmasından bağımsız):
--        kazanan +15 XP, beraberlik +10 XP, kaybeden +5 XP;
--        günlük aktivite + rozet değerlendirmesi.
--      - İptal/tamamlanmamış (results satırı yok / status≠completed)
--        zaten erken dönüş ile XP almaz.
--      - Duplicate finalize: mevcut rating idempotency erken
--        dönüşü XP'nin ikinci kez üretimini de engeller; ayrıca
--        103 UNIQUE(source_type, source_id, user_id) savunmadır.
--      - Yarışmadaki soru puanları XP'ye DÖNÜŞTÜRÜLMEZ (094);
--        rating (+24/-12/0) değişmez.
-- ============================================================

begin;


-- ============================================================
-- 1. INGEST_STUDENT_ATTEMPT (069 birebir + FAZ9)
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
  v_answered_at    timestamptz;
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
  returning id, answered_at into v_attempt_id, v_answered_at;

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

  -- ----------------------------------------------------------
  -- FAZ 9: XP + günlük aktivite (yalnız training bağlamı:
  -- antrenman + hedefli tekrar). Olay zamanı otoriter attempt
  -- zamanıdır; istemciden tarih ALINMAZ.
  -- ----------------------------------------------------------
  if p_attempt_context = 'training' then
    if p_result = 'correct' then
      perform public._faz9_grant_training_xp(
        v_user, v_attempt_id, r_q.difficulty, v_answered_at
      );
    end if;

    -- Seri günü: yalnız kabul edilmiş correct/wrong cevabı;
    -- blank/pass/timeout günlük etkinlik OLUŞTURMAZ.
    if p_result in ('correct', 'wrong') then
      perform public._faz9_record_daily_activity(v_user, v_answered_at);
    end if;

    perform public._faz9_evaluate_badges(v_user);
  end if;

  return jsonb_build_object(
    'attempt_id', v_attempt_id,
    'attempt_number', v_attempt_number,
    'metrics_updated', v_scopes,
    'metric_scopes', v_scope_list
  );
end;
$$;


-- ============================================================
-- 2. SELECT_TRAINING_QUESTIONS (097 birebir + FAZ9 günlük kota)
-- ============================================================

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
  v_day         date;
  v_daily_left  integer;
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
  -- FAZ 9: günlük kota kilidi (Europe/Istanbul günü). Sayaç satırı
  -- kilitlenir; teslim edilene kadar TÜKETİM OLMAZ.
  -- ----------------------------------------------------------
  v_day := public._faz9_local_day(now());
  v_daily_left := public._faz9_lock_daily_counter(v_user, v_day);

  if v_daily_left <= 0 then
    return jsonb_build_object(
      'questions', '[]'::jsonb,
      'new_count', 0,
      'repeat_count', 0,
      'reason', 'gunluk_kota_doldu',
      'daily', jsonb_build_object(
        'day', v_day,
        'questions_used', 500,
        'limit', 500,
        'remaining', 0
      ),
      'weekly', jsonb_build_object(
        'academic_year', v_year,
        'week', v_week,
        'new_questions_used', 0,
        'limit', 500
      )
    );
  end if;

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
      'daily', jsonb_build_object(
        'day', v_day,
        'questions_used', 500 - v_daily_left,
        'limit', 500,
        'remaining', v_daily_left
      ),
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
        'daily', jsonb_build_object(
          'day', v_day,
          'questions_used', 500 - v_daily_left,
          'limit', 500,
          'remaining', v_daily_left
        ),
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
        'daily', jsonb_build_object(
          'day', v_day,
          'questions_used', 500 - v_daily_left,
          'limit', 500,
          'remaining', v_daily_left
        ),
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
  -- FAZ 9: v_take günlük kalanla da sınırlandırılır.
  -- ----------------------------------------------------------
  v_take := least(v_limit, greatest(v_remaining, 0), v_daily_left);

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

  -- ----------------------------------------------------------
  -- FAZ 9: günlük kota tüketimi — teslim edilen toplam soru
  -- (yeni + tekrar). Seçim zaten kalanla sınırlandırıldığından
  -- 500 aşımı imkânsız; CHECK backstop son savunmadır.
  -- ----------------------------------------------------------
  perform public._faz9_consume_daily_quota(
    v_user,
    v_day,
    coalesce(array_length(v_all_ids, 1), 0)::integer
  );

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
    'daily', jsonb_build_object(
      'day', v_day,
      'questions_used', (500 - v_daily_left)
        + coalesce(array_length(v_all_ids, 1), 0),
      'limit', 500,
      'remaining', v_daily_left
        - coalesce(array_length(v_all_ids, 1), 0)
    ),
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
-- 3. SELECT_TARGETED_REVIEW_QUESTIONS (098 birebir + FAZ9 kota)
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
  v_day        date;
  v_daily_left integer;
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
  -- FAZ 9: günlük kota kilidi (Europe/Istanbul). Havuz seçimi de
  -- kalan hakka göre sınırlandırılır; teslim öncesi tüketim yok.
  -- ----------------------------------------------------------
  v_day := public._faz9_local_day(now());
  v_daily_left := public._faz9_lock_daily_counter(v_user, v_day);

  if v_daily_left <= 0 then
    return jsonb_build_object(
      'questions', '[]'::jsonb,
      'session_kind', 'targeted_review',
      'outcome_id', p_outcome_id,
      'wrong_review_count', 0,
      'new_count', 0,
      'reason', 'gunluk_kota_doldu',
      'daily', jsonb_build_object(
        'day', v_day,
        'questions_used', 500,
        'limit', 500,
        'remaining', 0
      ),
      'weekly', jsonb_build_object(
        'academic_year', v_year,
        'week', v_week,
        'subject_id', p_subject_id,
        'new_questions_used', 0,
        'limit', 500
      )
    );
  end if;

  -- FAZ 9: etkili limit günlük kalanla sınırlandırılır.
  v_limit := least(v_limit, v_daily_left);

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
      'daily', jsonb_build_object(
        'day', v_day,
        'questions_used', 500 - v_daily_left,
        'limit', 500,
        'remaining', v_daily_left
      ),
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
      'daily', jsonb_build_object(
        'day', v_day,
        'questions_used', 500 - v_daily_left,
        'limit', 500,
        'remaining', v_daily_left
      ),
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

  -- ----------------------------------------------------------
  -- FAZ 9: günlük kota tüketimi — teslim edilen toplam soru
  -- (hata havuzu + yeni).
  -- ----------------------------------------------------------
  perform public._faz9_consume_daily_quota(
    v_user,
    v_day,
    coalesce(array_length(v_all_ids, 1), 0)::integer
  );

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
    'daily', jsonb_build_object(
      'day', v_day,
      'questions_used', (500 - v_daily_left)
        + coalesce(array_length(v_all_ids, 1), 0),
      'limit', 500,
      'remaining', v_daily_left
        - coalesce(array_length(v_all_ids, 1), 0)
    ),
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
  'Faz 6: deterministik hedefli tekrar secimi. Faz 9: gunluk 500 soru kotasi (Europe/Istanbul) uygulanir; kota dolunca gunluk_kota_doldu. Kapsam fail-closed; rate limit 30/3600sn.';


-- ============================================================
-- 4. _FAZ5_APPLY_COMPETITION_POINTS (102 birebir + FAZ9 bloğu)
-- ============================================================

create or replace function public._faz5_apply_competition_points(
  p_competition_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r_comp        public.competitions%rowtype;
  v_result_type text;
  v_winner      uuid;
  v_delta_map   jsonb;
  r_player      record;

  v_delta       integer;
  v_before      integer;
  v_after       integer;

  v_membership_id uuid;
  v_cur_league    uuid;
  v_cur_sort      integer;
  v_target        record;

  v_comp_time   timestamptz;
  v_xp          smallint;
begin
  select * into r_comp
    from public.competitions c
   where c.id = p_competition_id;

  if r_comp.id is null or r_comp.status <> 'completed' then
    return;
  end if;

  -- Idempotency hizli cikisi: bu yarisma icin rating yazildiysa dokunma.
  if exists (
       select 1
         from public.competition_point_changes cpc
        where cpc.competition_id = r_comp.id
          and cpc.change_type = 'rating'
      ) then
    return;
  end if;

  select cr.result_type, cr.winner_user_id
    into v_result_type, v_winner
    from public.competition_results cr
   where cr.competition_id = r_comp.id;

  if v_result_type is null then
    return;
  end if;

  -- FAZ 9: olay zamanı otoriter yarışma tamamlanma zamanıdır.
  v_comp_time := coalesce(
    r_comp.server_completed_at, r_comp.completed_at, now()
  );

  select coalesce(srs.configuration, '{}'::jsonb) into v_delta_map
    from public.league_rule_sets srs
   where srs.rule_set_code = 'faz5_competition_rating'
     and srs.is_active = true
   limit 1;

  if v_delta_map is null then
    v_delta_map := jsonb_build_object(
      'win', 24, 'loss', 12, 'draw', 0,
      'forfeit_win', 24, 'forfeit_loss', 12
    );
  end if;

  for r_player in
    select cp.user_id, cp.status
      from public.competition_players cp
     where cp.competition_id = r_comp.id
     order by cp.user_id
  loop
    -- --------------------------------------------------------
    -- FAZ 9: XP + günlük aktivite + rozetler. Lig üyelik
    -- yapılandırmasından BAĞIMSIZDIR (fail-closed erken dönüşler
    -- XP'yi engelleyemez). Kazanan +15, beraberlik +10 (her iki
    -- oyuncu), kaybeden +5. Karar verilmemiş sonuçlar (cancelled,
    -- disputed) 0 XP üretir (grant fonksiyonu 0'ı yok sayar);
    -- iptal/tamamlanmamış yarışmada results satırı zaten yok.
    -- Soru puanları XP'ye dönüştürülmez; rating değişmez.
    -- --------------------------------------------------------
    v_xp := case
              when v_result_type = 'draw' then 10::smallint
              when v_result_type in ('win_loss', 'forfeit')
                then case
                       when r_player.user_id = v_winner
                         then 15::smallint
                       else 5::smallint
                     end
              else 0::smallint
            end;

    perform public._faz9_grant_competition_xp(
      r_player.user_id, r_comp.id, v_xp, v_result_type, v_comp_time
    );

    perform public._faz9_record_daily_activity(
      r_player.user_id, v_comp_time
    );

    perform public._faz9_evaluate_badges(r_player.user_id);

    v_delta := case
      when v_result_type = 'draw'
        then coalesce((v_delta_map ->> 'draw')::integer, 0)
      when r_player.user_id = v_winner
        then case
               when r_player.status = 'active'
                 then coalesce((v_delta_map ->> 'win')::integer, 24)
               else coalesce((v_delta_map ->> 'forfeit_win')::integer, 24)
             end
      else
        case
          when r_player.status = 'forfeited'
            then -coalesce((v_delta_map ->> 'forfeit_loss')::integer, 12)
          else -coalesce((v_delta_map ->> 'loss')::integer, 12)
        end
    end;

    -- CUTGUARD: yalniz ACIK PENCEREDEKI sezonun (veya null-sezon)
    -- guncel uyeligi rating hedefidir. Penceresi KAPANMIS sezonun
    -- uyeligi (ends_at <= now()) rating icin SECILMEZ; boylece
    -- ends_at sonrasi sonuclar eski sezon rating'ini degistiremez.
    select m.id, m.league_id, m.current_points
      into v_membership_id, v_cur_league, v_before
      from public.student_league_memberships m
      left join public.leaderboard_seasons ms
        on ms.id = m.season_id
     where m.user_id = r_player.user_id
       and m.is_current = true
       and m.membership_scope = 'general'
       and (m.season_id is null
            or ms.ends_at is null
            or ms.ends_at > now())
     order by m.entered_at desc
     limit 1;

    if v_membership_id is null then
      -- CUTGUARD rollover: penceresi kapanmis guncel uyelikler
      -- kapatilir (eski sezon verisi close snapshot'inda korunur);
      -- rating yeni hedefe (acik pencere sezonu / null) yazilir.
      update public.student_league_memberships m
         set is_current = false,
             exited_at = now(),
             updated_at = now()
       where m.user_id = r_player.user_id
         and m.is_current = true
         and m.membership_scope = 'general'
         and m.season_id is not null
         and exists (
           select 1
             from public.leaderboard_seasons ms
            where ms.id = m.season_id
              and ms.ends_at <= now()
         );

      -- Ilk kez lig sistemine giris / yeni sezon: en dusuk aktif lig.
      insert into public.student_league_memberships
        (user_id, league_id, membership_scope,
         points_at_entry, current_points, is_current)
      select r_player.user_id, l.id, 'general', 0, 0, true
        from public.leagues l
       where l.is_active = true
       order by l.sort_order asc, l.min_points asc
       limit 1
      returning id, league_id, current_points
        into v_membership_id, v_cur_league, v_before;

      if v_membership_id is null then
        -- Hic aktif lig tanimli degil: puan uygulama yok (fail-closed).
        -- FAZ 9: XP yukarida zaten uygulandi; lig ve rating dokunulmaz.
        return;
      end if;
    end if;

    v_after := greatest(v_before + v_delta, 0);

    update public.student_league_memberships m
       set current_points = v_after,
           updated_at = now()
     where m.id = v_membership_id;

    insert into public.competition_point_changes
      (competition_id, user_id, change_type,
       points_before, points_change, points_after,
       reason_code, rule_reference)
    values
      (r_comp.id, r_player.user_id, 'rating',
       v_before, v_after - v_before, v_after,
       'competition_' || v_result_type,
       jsonb_build_object(
         'rule_set_code', 'faz5_competition_rating',
         'result_type', v_result_type,
         'player_status', r_player.status
       ))
    on conflict (competition_id, user_id, change_type) do nothing;

    -- Lig bandi degisimi (promotion/demotion).
    select l.id, l.sort_order
      into v_target
      from public.leagues l
     where l.is_active = true
       and l.min_points <= v_after
       and (l.max_points is null or v_after <= l.max_points)
     order by l.sort_order asc, l.min_points asc
     limit 1;

    if v_target.id is not null
       and v_target.id is distinct from v_cur_league then

      select l.sort_order into v_cur_sort
        from public.leagues l
       where l.id = v_cur_league;

      update public.student_league_memberships m
         set is_current = false,
             exited_at = now(),
             updated_at = now()
       where m.id = v_membership_id;

      insert into public.student_league_memberships
        (user_id, league_id, membership_scope,
         points_at_entry, current_points, is_current)
      values
        (r_player.user_id, v_target.id, 'general',
         v_after, v_after, true);

      insert into public.student_league_history
        (user_id, from_league_id, to_league_id,
         transition_type, points_at_transition, reason)
      values
        (r_player.user_id, v_cur_league, v_target.id,
         case when coalesce(v_target.sort_order, 0)
                   > coalesce(v_cur_sort, 0)
              then 'promotion' else 'demotion' end,
         v_after,
         'competition_' || v_result_type);
    end if;
  end loop;
end;
$$;


-- ============================================================
-- 5. ACL TEYİTLERİ (create or replace ACL'leri korur; idempotent
--    ve savunmacı yeniden teyit — 097 deseni)
-- ============================================================

revoke execute
on function public.ingest_student_attempt(uuid, text, text, integer, uuid, jsonb)
from public, anon, authenticated;

revoke execute
on function public.select_training_questions(uuid, integer, uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.select_training_questions(uuid, integer, uuid, uuid)
to authenticated;

revoke execute
on function public.select_targeted_review_questions(uuid, uuid, integer)
from public, anon, authenticated;

grant execute
on function public.select_targeted_review_questions(uuid, uuid, integer)
to authenticated;

revoke execute
on function public._faz5_apply_competition_points(uuid)
from public, anon, authenticated;

comment on function public.ingest_student_attempt(uuid, text, text, integer, uuid, jsonb) is
  'Sunucu-ici kullanim (070). Faz 9: training correct/wrong kayitlari XP, gunluk aktivite ve rozet degerlendirmesi uretir; idempotenttir.';
comment on function public.select_training_questions(uuid, integer, uuid, uuid) is
  'Faz 9: gunluk 500 soru kotasi (Europe/Istanbul) uygulanir; kota dolunca gunluk_kota_doldu. Haftalik 500 yeni soru zinciri (068) korunur.';
comment on function public._faz5_apply_competition_points(uuid) is
  'Faz 5 rating motoru (+24/-12/0, 078/102). Faz 9: tamamlandi yarismada oyuncu basina tek seferlik XP (15/10/5), gunluk aktivite ve rozet degerlendirmesi; yarisma puanindan bagimsizdir.';


commit;
