-- ============================================================
-- 068_faz2_question_selection.sql
-- Altın Kalemler - Migration Faz 2 (068)
--
-- Öğrenciye uygun soru seçimi RPC'leri.
--
-- Faz 2 mimari kararları (kullanıcı onaylı):
--   1. Akademik dönem academic_weeks (067) ile deterministik çözülür;
--      geçerli dönem yoksa seçim FAIL-CLOSED olur.
--   2. Haftalık 500 YENİ soru sınırı ATTEMPT anında değil, soru öğrenciye
--      İLK KEZ seçilip gösterilirken uygulanır. Exposure kaydı ve haftalık
--      sayaç artışı aynı transaction içinde atomiktir. Tekrar gösterilen
--      soru sayaç tüketmez.
--   3. SECURITY DEFINER fonksiyonlar kullanıcıyı yalnız auth.uid()
--      ile türetir; search_path='' sabittir; PUBLIC/anon/authenticated
--      varsayılan EXECUTE'u kaldırılır, yalnız gerekli RPC'lere
--      authenticated verilir.
--
-- Kural eşlemesi (059-product-rules):
--   - Konu/kazanım işlenmeden soru sorulamaz -> schedule gating
--     (start_week <= güncel hafta; end_week antrenmanı KAPATMAZ).
--   - Ortak görülmemiş kasa önceliği -> prepare_competition_pack
--     Öncelik A (kasa hiç görülmemiş) / Öncelik B (ortak görülmemiş
--     soru sayısı yeterli).
--   - Paket başına en fazla 5 soru -> 048/065 yapısı korunur; bu
--     migration yalnız SEÇİM katmanıdır, limit tetikleyicisine dokunmaz.
--   - Performans -> aday havuzları küçük tutulur; COUNT(*) yalnız
--     indeksli dar alt küme üzerinde; sayaç COUNT'suz satır kilidiyle.
-- ============================================================

begin;


-- ============================================================
-- 1. PRIVATE: HAFTALIK SAYAÇ KİLİDİ / TÜKETİMİ
-- ============================================================

create or replace function public._faz2_lock_weekly_counter(
  p_user_id       uuid,
  p_academic_year text,
  p_week          integer,
  p_subject_id    uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_remaining integer;
begin
  -- Sayaç satırı yoksa sıfırdan aç; sonra kilitle.
  insert into public.student_weekly_counters
    (user_id, academic_year, week, subject_id, new_questions_used)
  values
    (p_user_id, p_academic_year, p_week, p_subject_id, 0)
  on conflict do nothing;

  select 500 - c.new_questions_used
    into v_remaining
    from public.student_weekly_counters c
   where c.user_id = p_user_id
     and c.academic_year = p_academic_year
     and c.week = p_week
     and c.subject_id = p_subject_id
   for update;

  return v_remaining;
end;
$$;

create or replace function public._faz2_consume_weekly_capacity(
  p_user_id       uuid,
  p_academic_year text,
  p_week          integer,
  p_subject_id    uuid,
  p_count         integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_count is null or p_count <= 0 then
    return;
  end if;

  update public.student_weekly_counters c
     set new_questions_used = c.new_questions_used + p_count,
         updated_at = now()
   where c.user_id = p_user_id
     and c.academic_year = p_academic_year
     and c.week = p_week
     and c.subject_id = p_subject_id
     and c.new_questions_used + p_count <= 500;

  if not found then
    raise exception
      'Haftalik yeni soru siniri asilamaz (500).'
      using errcode = 'P0001';
  end if;
end;
$$;


-- ============================================================
-- 2. PRIVATE: METRİK ANAHTARI NORMALİZASYONU
--    Boş/serbest metin -> güvenli normalize değer ('tanimsiz').
-- ============================================================

create or replace function public._faz2_normalize_metric_key(
  p_value text
)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(
    nullif(
      btrim(
        regexp_replace(
          regexp_replace(
            lower(btrim(coalesce(p_value, ''))),
            '[^a-z0-9]+', '_', 'g'
          ),
          '_{2,}', '_', 'g'
        ),
        '_'
      ),
      ''
    ),
    'tanimsiz'
  );
$$;


-- ============================================================
-- 3. PRIVATE: HASSAS ALAN TEMİZLİĞİ (ALLOWLIST)
--
-- DENYLIST yerine ALLOWLIST: payload yalnız öğrenciye gösterilmesi
-- gereken alanlardan açıkça kurulur. correct_answer, çözüm/açıklama,
-- onay/reviewer/internal alanları ve GELECEKTE questions tablosuna
-- eklenecek herhangi yeni kolon bu listeye yazılmadıkça payload'a
-- ASLA sızmaz.
-- ============================================================

create or replace function public._faz2_sanitize_question_payload(
  p_question jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id',                           p_question->>'id',
    -- question_code: ogrenciye zaten acik referans kodudur (021
    -- payload'i da gosterir); cevap/ cozum sizmasi soz konusu degil.
    'question_code',                p_question->>'question_code',
    'grade_level',                  p_question->'grade_level',
    'subject_id',                   p_question->'subject_id',
    'question_text',                p_question->'question_text',
    'option_a',                     p_question->'option_a',
    'option_b',                     p_question->'option_b',
    'option_c',                     p_question->'option_c',
    'option_d',                     p_question->'option_d',
    'option_e',                     p_question->'option_e',
    'difficulty',                   p_question->'difficulty',
    'has_visual',                   p_question->'has_visual',
    'estimated_solve_time_seconds', p_question->'estimated_solve_time_seconds'
  );
$$;


-- ============================================================
-- 4. PRIVATE: ÖĞRENCİ BAĞLAMI
--    Profil -> takvim profili -> müfredat sürümü zinciri.
--    schedule_profile_id NULL ise sürümün aktif VARSAYILAN (MEB)
--    profili kullanılır. Çözülemezse FAIL-CLOSED.
-- ============================================================

create or replace function public._faz2_student_context(
  p_user_id uuid
)
returns table (
  grade_level          smallint,
  schedule_profile_id  uuid,
  curriculum_version_id uuid,
  academic_year        text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
    with ctx as (
      select sp.grade_level as g, sp.schedule_profile_id as spi
        from public.student_profiles sp
       where sp.id = p_user_id
    )
    select
      ctx.g,
      coalesce(
        ctx.spi,
        (select dflt.id
           from public.curriculum_schedule_profiles dflt
          where dflt.is_default = true
            and dflt.is_active = true
          order by (select cv.academic_year
                      from public.curriculum_versions cv
                     where cv.id = dflt.curriculum_version_id) desc,
                   dflt.id
          limit 1)
      ) as resolved_profile_id,
      prof.curriculum_version_id,
      cv.academic_year
    from ctx
    left join public.curriculum_schedule_profiles prof
      on prof.id = coalesce(ctx.spi,
           (select dflt.id
              from public.curriculum_schedule_profiles dflt
             where dflt.is_default = true
               and dflt.is_active = true
             order by (select cv2.academic_year
                         from public.curriculum_versions cv2
                        where cv2.id = dflt.curriculum_version_id) desc,
                     dflt.id
             limit 1))
    left join public.curriculum_versions cv
      on cv.id = prof.curriculum_version_id
    where ctx.g is not null
      and prof.id is not null
      and prof.is_active = true
      and cv.id is not null;
end;
$$;


-- ============================================================
-- 5. PRIVATE: DÖNEM ZORUNLULUĞU (FAIL-CLOSED)
-- ============================================================

create or replace function public._faz2_require_period()
returns table (
  academic_year text,
  week integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select * from public.resolve_current_academic_period();
  if not found then
    raise exception
      'Gecerli akademik donem bulunamadi; soru akisi fail-closed olarak durduruldu.'
      using errcode = 'P0001';
  end if;
end;
$$;


-- ============================================================
-- 6. PUBLIC RPC: ANTRENMAN SAHASI SORU SEÇİMİ
--
-- select_training_questions(p_subject_id, p_limit)
--   - Kullanıcı auth.uid()'den türetilir.
--   - Dönem yoksa FAIL-CLOSED.
--   - Yalnız işlenmiş konu/kazanımdan soru döner (start_week <= hafta;
--     end_week antrenman erişimini kapatmaz).
--   - Yeni sorular kapasite kadar; kalan tekrar sorularla tamamlanır.
--   - Exposure INSERT + sayaç artışı aynı transaction'da atomik;
--     tekrar soru sayacı tüketmez.
--   - Deterministik sıralama: yeni önce (id asc), ardından tekrar (id asc).
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
   -- F-4: eşleme onay kapısı. question_curriculum_mappings ve
   -- question_outcome_mappings.review_status enum'u şemada
   -- ('pending','approved','rejected','needs_review') olarak
   -- tanımlıdır (004/010); öğrenciye yalnız ONAYLANMIŞ eşleme
   -- üzerinden soru gider.
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

  -- ----------------------------------------------------------
  -- SHOW-TIME ATOMİK YAZIMI: exposure INSERT + sayaç artışı.
  -- ON CONFLICT DO NOTHING geri dönüşü gerçek artışı verir;
  -- yarışta başkasının önceden yazdığı satır sayaç tüketmez.
  -- Tekrar sorular için INSERT denenmez (satır zaten vardır).
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


-- ============================================================
-- 7. PUBLIC RPC: HAFTALIK KULLANIM GÖRÜNTÜSÜ
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
-- 8. PUBLIC RPC: YARIŞMA PAKETİ SEÇİMİ
--
-- prepare_competition_pack(p_competition_id)
--   Öncelik A: iki oyuncunun da hiç görmediği (pack/question exposure
--              satırı olmayan) tam dolu paket kasa.
--   Öncelik B: ortak görülmemiş soru sayısı question_count kadar olan
--              uygun kasa.
--   Snapshot başladıktan sonra değiştirilemez (bkz. 069 trigger);
--   bu fonksiyon snapshot satırı VARSA çalışmaz.
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

  -- --------------------------------------------------------
  -- Yarışma satırını kilitle; durum + snapshot koruması.
  -- --------------------------------------------------------
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

  -- --------------------------------------------------------
  -- Öncelik A: hiçbir oyuncunun görmediği TAM dolu paket.
  -- Üyelik sayımı dar alt kümede (vault_id) indeksli COUNT'tur.
  -- --------------------------------------------------------
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
    -- ------------------------------------------------------
    -- Öncelik B: ORTAK görülmemiş soru sayısı yeterli kasa.
    -- ------------------------------------------------------
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

  -- 065 disiplini: hedef kasa satırını kilitle, koşulu kilit altında doğrula.
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

  -- --------------------------------------------------------
  -- Soru listesi: A -> tüm uygun üyeler; B -> ortak görülmemişler.
  -- Deterministik: question_id asc.
  -- --------------------------------------------------------
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

  -- --------------------------------------------------------
  -- Pack exposure (her iki oyuncu) + show-time question exposure /
  -- haftalık sayaç (oyuncu bazında, clamp'li: başlayan maç bozulmaz,
  -- aşan yeni sorular bu hafta sayilmaz; akış sonraki seçimde durur).
  -- --------------------------------------------------------
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

    -- Kalan yeni sorular da gösterilir (snapshot); kapasite doluysa
    -- sayaç CLAMP'lenir: CHECK(<=500) ihlal edilmez, akış sonrakinde durur.
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

  -- İz kaydı: hangi kasadan, hangi KESİN soru listesiyle seçildi.
  --
  -- F-1: question_ids bilinçli olarak metadata'ya yazılır. Snapshot
  -- yazıcısı YALNIZ bu listeyi kullanır; kasadaki başka hiçbir soru
  -- snapshot'a giremez. Baskı katmanı 069 guard_faz2_snapshot_source
  -- trigger'idır (INSERT/UPDATE question_id bu listeden doğrulanır).
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
-- 9. EXECUTE İZİNLERİ
-- ============================================================

revoke execute
on function public._faz2_lock_weekly_counter(uuid, text, integer, uuid)
from public, anon, authenticated;

revoke execute
on function public._faz2_consume_weekly_capacity(uuid, text, integer, uuid, integer)
from public, anon, authenticated;

revoke execute
on function public._faz2_normalize_metric_key(text)
from public, anon, authenticated;

revoke execute
on function public._faz2_sanitize_question_payload(jsonb)
from public, anon, authenticated;

revoke execute
on function public._faz2_student_context(uuid)
from public, anon, authenticated;

revoke execute
on function public._faz2_require_period()
from public, anon, authenticated;

grant execute
on function public.select_training_questions(uuid, integer)
to authenticated;

grant execute
on function public.get_my_weekly_usage()
to authenticated;

grant execute
on function public.prepare_competition_pack(uuid)
to authenticated;


commit;
