-- ============================================================
-- 102_faz8_cutoff_guard.sql
-- Altın Kalemler - Faz 8 düzeltme (append-only; 101 değiştirilmez)
--
-- SÖZLEŞME DENETİMİ KARARLARI (kullanıcı onaylı kesin kural):
--   K-A (cutoff): ends_at ESKİ SEZONUN cutoff'idur. ends_at
--     sonrasında ama close_league_season çağrısından ÖNCE
--     finalize edilen yarışma sonucu:
--       - eski sezon rating/entry/history kayıtlarını DEĞİŞTİREMEZ,
--       - uygun yeni (açık penceredeki) sezona yazılır; açık
--         pencere yoksa ara dönem null-sezon üyeliğine yazılır ve
--         kapanışta yeni sezona bağlanır.
--   K-B (sıralama determinizmi): rating + entered_at + nickname
--     üçlüsü eşit olduğunda son sunucu-içi benzersiz anahtar
--     (membership/entry user_id) sıralamayı belirler; bu anahtar
--     DTO'ya ASLA döndürülmez.
--
-- 078 DAVRANIŞ KORUMA LİSTESİ (_faz5_apply_competition_points
-- birebir yeniden yayınlanır; yalnız üyelik seçimi + rollover
-- değişmiştir):
--   - SECURITY DEFINER, search_path='' (tam niteleme) korunur.
--   - EXECUTE public/anon/authenticated'dan yine alınır (bölüm 4).
--   - Idempotency hızlı çıkışı (competition_point_changes UNIQUE
--     (competition_id,user_id,change_type)) değişmeden korunur.
--   - Sabit tablo (win +24 / loss -12 / draw 0 / forfeit) aynı.
--   - clamp (greatest(v_after, 0)) aynı.
--   - Puan bandı promotion/demotion + history aynı.
--   - İlk üyelik en düşük aktif lig (sort_order asc) aynı.
--   - Oyuncu döngüsü order by cp.user_id (deterministik) aynı.
--   - finalize_competition_if_ready (022/078) DOKUNULMAZ.
--
-- close_league_season değişiklikleri:
--   - Snapshot, kapanan sezonun üyeliklerinin KAPANIŞ ANINDAKİ
--     (cutoff sonrası rollover edilenler dahil) son durumundan
--     alınır: distinct on (user_id) en son üyelik.
--   - Snapshot/history yalnız season_id = kapanan sezon üyeliklerini
--     kapsar; null-sezon (ara dönem/legacy) üyelikleri ESAS İÇERMEZ
--     (post-cutoff rating eski sezona sızmaz).
--   - Üyelik kapanışı yalnız kapanan sezonun güncel üyeliklerine
--     uygulanır; null-sezon üyelikler (ara dönem rating'i yeni
--     sezona taşır) kapatılmaz ve yeni sezona bağlanır.
-- ============================================================

begin;


-- ============================================================
-- 1. RATING MOTORU (078 birebir + CUTGUARD)
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
-- 2. KAPANIŞ RPC (101 birebir + cutoff snapshot + rollover uyumu)
-- ============================================================

create or replace function public.close_league_season(
  p_season_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r_season public.leaderboard_seasons%rowtype;
  r_next public.leaderboard_seasons%rowtype;
  v_definition uuid;
  v_bronze uuid;
  v_snapshot_count integer;
  v_close_count integer;
  v_is_closed boolean;
begin
  if p_season_id is null then
    raise exception 'Sezon kimligi gerekli.'
      using errcode = 'P0001';
  end if;

  -- Rating motoruyla ve diğer kapanışlarla serileşme.
  lock table public.student_league_memberships in exclusive mode;

  select s.*
    into r_season
    from public.leaderboard_seasons s
   where s.id = p_season_id
     for update;

  if r_season.id is null then
    raise exception 'Sezon bulunamadi.'
      using errcode = 'P0001';
  end if;

  -- İdempotensi: bu sezon daha önce kapanmışsa no-op.
  select true
    into v_is_closed
    from public.league_season_close_results c
   where c.season_id = r_season.id;
  if v_is_closed is true then
    return jsonb_build_object(
      'status', 'already_closed',
      'season_id', r_season.id
    );
  end if;

  if r_season.is_active is not true then
    raise exception 'Sezon aktif degil; kapanis reddedildi.'
      using errcode = 'P0001';
  end if;

  if now() < r_season.ends_at then
    raise exception 'Sezon suresi dolmadi; kapanis ends_at oncesinde tetiklenemez.'
      using errcode = 'P0001';
  end if;

  select d.id
    into v_definition
    from public.leaderboard_definitions d
   where d.leaderboard_code = 'league_ranking'
     and d.is_active = true
   limit 1;
  if v_definition is null then
    raise exception 'league_ranking tanimi yok; kapanis iptal.'
      using errcode = 'P0001';
  end if;

  select l.id
    into v_bronze
    from public.leagues l
   where l.is_active = true
   order by l.sort_order asc, l.min_points asc
   limit 1;
  if v_bronze is null then
    raise exception 'Aktif lig tanimi yok; kapanis iptal.'
      using errcode = 'P0001';
  end if;

  -- Bir sonraki sezon (bu sezonun bitişinden sonra başlayan,
  -- henüz kapanmamış en erken sezon).
  select n.*
    into r_next
    from public.leaderboard_seasons n
   where n.id <> r_season.id
     and n.starts_at >= r_season.ends_at
     and not exists (
       select 1
         from public.league_season_close_results c
        where c.season_id = n.id
     )
   order by n.starts_at asc
   limit 1;

  -- 1) SNAPSHOT: kapanan sezonun leaderboard entry'leri.
  --    CUTGUARD: kaynak, trigger'in her rating olayinda guncel
  --    tuttugu TEK entry satiridir (kullanici basina tek satir
  --    degismezligi) -> cutoff anindaki FINAL durum, deterministik.
  --    Ayni transaction'da uretilmis uyeliklerde entered_at esit
  --    olabileceginden uyelik-temelli distinct-on kullanilmaz.
  --    Post-cutoff rollover uyelikleri null-sezon oldugundan entry
  --    uretmez; eski sezon entry'si asla degismez.
  --    Kapsam: entry'si ve kapanan sezon uyeligi olan ogrenciler.
  --    Siralama (K-B): rating desc, nickname asc, user_id asc
  --    (user_id DTO'ya donmez). Gizlilik liste okuma katmaninda.
  with snap as (
    insert into public.leaderboard_entries
      (season_id, leaderboard_definition_id, user_id, grade_level,
       scope_type, scope_reference_id, league_code, points, rank_position,
       updated_at)
    select
      e.season_id,
      v_definition,
      e.user_id,
      e.grade_level,
      'league',
      e.scope_reference_id,
      e.league_code,
      e.points,
      row_number() over (
        partition by e.grade_level, e.scope_reference_id
        order by e.points desc, coalesce(pp.nickname, '') asc,
                 e.user_id asc
      ),
      now()
    from public.leaderboard_entries e
    join public.student_public_profiles pp
      on pp.user_id = e.user_id
    where e.season_id = r_season.id
      and e.leaderboard_definition_id = v_definition
      and e.scope_type = 'league'
      and exists (
        select 1
          from public.student_league_memberships m
         where m.user_id = e.user_id
           and m.membership_scope = 'general'
           and m.season_id = r_season.id)
    on conflict (
      season_id,
      leaderboard_definition_id,
      user_id,
      scope_type,
      coalesce(scope_reference_id, '00000000-0000-0000-0000-000000000000'::uuid)
    )
    do update
      set points = excluded.points,
          league_code = excluded.league_code,
          grade_level = excluded.grade_level,
          rank_position = excluded.rank_position,
          updated_at = now()
    returning 1
  )
  select count(*) into v_snapshot_count from snap;

  -- 2) KAPANIŞ sayımı (yalnız kapanan sezonun GÜNCEL üyelikleri;
  --    cutoff sonrasi rollover edilenler motor tarafindan zaten
  --    kapatilmistir).
  select count(*)
    into v_close_count
    from public.student_league_memberships m
   where m.is_current = true
     and m.membership_scope = 'general'
     and m.season_id = r_season.id;

  -- 3) RESET HISTORY (K2): kapanan sezonun entry tabanli FINAL
  --    durumundan (cutoff anindaki puan) append-only kayit.
  insert into public.student_league_history
    (user_id, season_id, from_league_id, to_league_id,
     transition_type, points_at_transition, reason)
  select
    e.user_id,
    r_season.id,
    e.scope_reference_id,
    v_bronze,
    'reset',
    e.points,
    'season_reset'
  from public.leaderboard_entries e
  where e.season_id = r_season.id
    and e.leaderboard_definition_id = v_definition
    and e.scope_type = 'league'
    and exists (
      select 1
        from public.student_league_memberships m
       where m.user_id = e.user_id
         and m.membership_scope = 'general'
         and m.season_id = r_season.id);

  -- 4) ÜYELİK KAPANIŞI: yalnız kapanan sezonun güncel üyelikleri.
  --    Null-sezon (ara dönem/legacy) üyelikler KAPATILMAZ; onlar
  --    yeni sezona taşınır (adım 6).
  update public.student_league_memberships m
     set is_current = false,
         exited_at = now(),
         updated_at = now()
   where m.is_current = true
     and m.membership_scope = 'general'
     and m.season_id = r_season.id;

  -- 5) SEZON DURUM GEÇİŞİ: önce kapanan sezon pasifleşir
  --    (tek-aktif-sezon UNIQUE indeksini bozmamak için sıralı).
  update public.leaderboard_seasons s
     set is_active = false,
         updated_at = now()
   where s.id = r_season.id;

  -- 6) YENİ SEZON: null-sezon güncel üyelikler (ara dönem rating'i
  --    taşıyanlar + legacy) yeni sezona bağlanır; reset geçmişi
  --    olan ama hâlâ üyeliği olmayanlar için Bronz rating 0
  --    üyeliği açılır.
  if r_next.id is not null then
    update public.student_league_memberships m
       set season_id = r_next.id,
           updated_at = now()
     where m.is_current = true
       and m.membership_scope = 'general'
       and m.season_id is null;

    insert into public.student_league_memberships
      (user_id, league_id, membership_scope, season_id,
       points_at_entry, current_points, is_current)
    select distinct
      h.user_id,
      v_bronze,
      'general',
      r_next.id,
      0,
      0,
      true
    from public.student_league_history h
    where h.season_id = r_season.id
      and h.transition_type = 'reset'
      and h.reason = 'season_reset'
    on conflict do nothing;

    update public.leaderboard_seasons n
       set is_active = true,
           updated_at = now()
     where n.id = r_next.id;
  end if;

  -- 7) KAPANIŞ KAYDI (idempotency + audit).
  insert into public.league_season_close_results
    (season_id, snapshot_entry_count, membership_close_count,
     next_season_id, metadata)
  values
    (r_season.id, v_snapshot_count, v_close_count, r_next.id,
     jsonb_build_object(
       'bronze_league_id', v_bronze,
       'trigger', 'close_league_season',
       'cutoff_rule', 'ends_at'
     ))
  on conflict (season_id) do nothing;

  return jsonb_build_object(
    'status', 'closed',
    'season_id', r_season.id,
    'snapshot_entry_count', v_snapshot_count,
    'membership_close_count', v_close_count,
    'next_season_id', r_next.id
  );
end;
$$;


-- ============================================================
-- 3. OKUMA RPC (101 birebir + K-B son tie-break)
--    ranked ORDER BY: rating desc, entered_at asc, nickname asc,
--    user_id asc. user_id yalniz deterministik siralama icin
--    kullanilir; DTO'ya DONMEZ (allowlist mapper da dusurur).
-- ============================================================

create or replace function public.get_my_league_ranking(
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_grade smallint;
  r_season public.leaderboard_seasons%rowtype;
  v_my_league uuid;
  v_limit integer;
  v_offset integer;
  v_result jsonb;
begin
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  perform public._faz4_consume_rate_limit('get_my_league_ranking', 30, 60);

  select sp.grade_level
    into v_grade
    from public.student_profiles sp
   where sp.id = v_user;
  if v_grade is null then
    raise exception 'Ogrenci profili bulunamadi.'
      using errcode = 'P0001';
  end if;

  v_limit := coalesce(p_limit, 50);
  if v_limit < 1 then
    raise exception 'Gecersiz limit.'
      using errcode = 'P0001';
  end if;
  v_limit := least(v_limit, 100);

  v_offset := coalesce(p_offset, 0);
  if v_offset < 0 then
    raise exception 'Gecersiz sayfa konumu.'
      using errcode = 'P0001';
  end if;
  v_offset := least(v_offset, 10000);

  select s.*
    into r_season
    from public.leaderboard_seasons s
   where s.is_active = true
     and s.starts_at <= now()
     and s.ends_at > now()
   order by s.starts_at desc
   limit 1;

  if r_season.id is null then
    return jsonb_build_object(
      'season_status', 'no_active_season',
      'grade_level', v_grade,
      'entries', '[]'::jsonb,
      'total', 0
    );
  end if;

  select m.league_id
    into v_my_league
    from public.student_league_memberships m
   where m.user_id = v_user
     and m.is_current = true
     and m.membership_scope = 'general'
     and m.season_id = r_season.id
   limit 1;

  if v_my_league is null then
    return jsonb_build_object(
      'season_status', 'no_membership',
      'season', jsonb_build_object(
        'code', r_season.season_code,
        'name', r_season.name,
        'status', 'active',
        'starts_at', r_season.starts_at,
        'ends_at', r_season.ends_at
      ),
      'grade_level', v_grade,
      'entries', '[]'::jsonb,
      'total', 0
    );
  end if;

  -- Tek sorgu: sayfa satırları + toplam + kendi sırası.
  with ranked as (
    select
      e.user_id,
      e.points as rating,
      e.league_code,
      l.name as league_name,
      pp.nickname,
      pp.avatar_key,
      pp.is_visible,
      m.entered_at,
      row_number() over (
        order by e.points desc, m.entered_at asc, pp.nickname asc,
                 e.user_id asc
      ) as row_rank
    from public.leaderboard_entries e
    join public.leaderboard_definitions d
      on d.id = e.leaderboard_definition_id
     and d.leaderboard_code = 'league_ranking'
    join public.student_league_memberships m
      on m.user_id = e.user_id
     and m.is_current = true
     and m.membership_scope = 'general'
     and m.season_id = e.season_id
    join public.student_public_profiles pp
      on pp.user_id = e.user_id
    join public.leagues l
      on l.id = e.scope_reference_id
    where e.season_id = r_season.id
      and e.grade_level = v_grade
      and e.scope_type = 'league'
      and e.scope_reference_id = v_my_league
  ),
  my_row as (
    select row_rank, rating, league_code, league_name, nickname, avatar_key
      from ranked
     where user_id = v_user
     order by row_rank
     limit 1
  ),
  page_rows as (
    select row_rank, user_id, nickname, avatar_key, league_code, league_name, rating
      from ranked
     where is_visible = true
        or user_id = v_user
     order by row_rank
     offset v_offset
     limit v_limit
  ),
  totals as (
    select count(*) as total_rows from ranked
  ),
  next_league as (
    select l2.league_code, l2.name, l2.min_points
      from public.leagues l2
     where l2.is_active = true
       and l2.sort_order > (
             select l1.sort_order
               from public.leagues l1
              where l1.id = v_my_league
           )
     order by l2.sort_order asc
     limit 1
  )
  select
    jsonb_build_object(
      'season_status', 'active',
      'season', jsonb_build_object(
        'code', r_season.season_code,
        'name', r_season.name,
        'status', 'active',
        'starts_at', r_season.starts_at,
        'ends_at', r_season.ends_at
      ),
      'grade_level', v_grade,
      'my', case
        when (select count(*) from my_row) = 0 then null
        else (
          select jsonb_build_object(
            'rank', m0.row_rank,
            'rating', m0.rating,
            'league_code', m0.league_code,
            'league_name', m0.league_name,
            'nickname', m0.nickname,
            'avatar_key', m0.avatar_key
          )
          from my_row m0
        )
      end,
      'entries', coalesce(
        (select jsonb_agg(
                  jsonb_build_object(
                    'rank', page_rows.row_rank,
                    'is_current_student', page_rows.user_id = v_user,
                    'nickname', page_rows.nickname,
                    'avatar_key', page_rows.avatar_key,
                    'league_code', page_rows.league_code,
                    'league_name', page_rows.league_name,
                    'rating', page_rows.rating
                  )
                  order by page_rows.row_rank)
         from page_rows),
        '[]'::jsonb
      ),
      'total', (select totals.total_rows from totals),
      'next_league', case
        when (select count(*) from next_league) = 0 then null
        else (
          select jsonb_build_object(
            'league_code', nl.league_code,
            'league_name', nl.name,
            'threshold', nl.min_points
          )
          from next_league nl
        )
      end
    )
    into v_result;

  return v_result;
end;
$$;


-- ============================================================
-- 4. EXECUTE MATRİSİ (drift guard; 078/101 durumu korunur)
-- ============================================================

revoke execute
  on function public._faz5_apply_competition_points(uuid)
  from public, anon, authenticated;

revoke execute
  on function public.close_league_season(uuid)
  from public, anon, authenticated;

grant execute
  on function public.close_league_season(uuid)
  to service_role;

revoke execute
  on function public.get_my_league_ranking(integer, integer)
  from public, anon;

grant execute
  on function public.get_my_league_ranking(integer, integer)
  to authenticated;


commit;


-- ============================================================
-- DOĞRULAMA
-- ============================================================

select
  p.proname as function_name,
  p.prosecdef as is_security_definer,
  p.proconfig as search_path_config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'get_my_league_ranking',
    'close_league_season',
    '_faz5_apply_competition_points'
  )
order by p.proname;

select
  has_function_privilege('anon',
    'public._faz5_apply_competition_points(uuid)', 'EXECUTE')
    as anon_can_apply,
  has_function_privilege('authenticated',
    'public._faz5_apply_competition_points(uuid)', 'EXECUTE')
    as auth_can_apply,
  has_function_privilege('authenticated',
    'public.close_league_season(uuid)', 'EXECUTE')
    as auth_can_close,
  has_function_privilege('service_role',
    'public.close_league_season(uuid)', 'EXECUTE')
    as service_can_close;
