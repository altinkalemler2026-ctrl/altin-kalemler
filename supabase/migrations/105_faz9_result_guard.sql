-- ============================================================
-- 105_faz9_result_guard.sql
-- Altın Kalemler - Migration Faz 9b (105): sonuç guard'ı.
--
-- PUSH-ÖNCESİ DENETİM BULGUSU (BLOCKED):
--   104'te _faz5_apply_competition_points, günlük etkinlik
--   (streak) ve rozet değerlendirmesini result_type'a bakmaksızın
--   çalıştırıyordu. status='completed' + result_type IN
--   ('cancelled','disputed') kombinasyonu şemada mümkündür
--   (qa_faz9 T-51 fixture'ı üretti); bu durumda iptal/itiraz
--   yarışmaları streak günü ve yarışma rozetleri üretebiliyordu.
--
-- DÜZELTME (yalnız Faz 9 kapsamındaki bağlar; XP, yarışma puanı,
-- lig rating, yıldız, kota ve Faz 5-8 sözleşmeleri DEĞİŞMEZ):
--   1. Günlük etkinlik + rozet değerlendirmesi YALNIZ
--      v_result_type IN ('win_loss', 'draw', 'forfeit') iken
--      çalışır. cancelled/disputed/tamamlanmamış/sonuçsuz durumlar
--      günlük etkinlik, current/longest streak veya yarışma
--      rozeti ÜRETMEZ. (XP zaten koşulluydu: bu türler 0 XP.)
--   2. _faz9_evaluate_badges: first_competition koşuluna
--      competition_results join + geçerli sonuç türü filtresi;
--      wins_10 koşuluna geçerli sonuç türü filtresi.
--
-- FORFEIT KARARI (kanıta dayalı): mevcut sistemde forfeit
-- KARARA BAĞLANMIŞ sonuctur — 078/102 rating motoru
-- 'forfeit_win' +24 / 'forfeit_loss' -12 uygular ve
-- competition_results.result_type kataloğunda 'forfeit'
-- ayrı bir karar türüdür. Bu nedenle forfeit geçerli sonuç
-- setine dahildir; ayrı ürün kararı gerekmez.
--
-- IDEMPOTENCY: create or replace ile mevcut tanımların üzerine
-- yazar; ACL'ler korunduğu için bölüm 3'te savunmacı teyit.
-- ============================================================

begin;


-- ============================================================
-- 1. _FAZ5_APPLY_COMPETITION_POINTS (104 birebir + FAZ9B guard)
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
    -- FAZ 9: XP (kazanan +15 / beraberlik +10 / kaybeden +5).
    -- Karar verilmemiş sonuçlar (cancelled, disputed) 0 XP
    -- üretir (grant fonksiyonu 0'ı yok sayar). Soru puanları
    -- XP'ye dönüştürülmez; rating değişmez.
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

    -- --------------------------------------------------------
    -- FAZ 9B GUARD: günlük etkinlik + rozetler YALNIZ karar
    -- verilmemiş geçerli sonuçlarda. cancelled/disputed/
    -- tamamlanmamış/sonuçsuz durumlar streak günü veya yarışma
    -- rozeti ÜRETMEZ.
    -- --------------------------------------------------------
    if v_result_type in ('win_loss', 'draw', 'forfeit') then
      perform public._faz9_record_daily_activity(
        r_player.user_id, v_comp_time
      );

      perform public._faz9_evaluate_badges(r_player.user_id);
    end if;

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
-- 2. _FAZ9_EVALUATE_BADGES (103 birebir + FAZ9B sonuç filtresi)
--
-- Yalnız first_competition ve wins_10 koşulları değişir; diğer
-- rozet koşulları (first_step, first_correct, streak_*, correct_50)
-- aynen korunur.
-- ============================================================

create or replace function public._faz9_evaluate_badges(
  p_user uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- first_step: ilk geçerli öğrenme etkinliği (daily activity).
  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, 'first_step',
         jsonb_build_object('basis', 'daily_activity')
    where exists (
      select 1
        from public.student_daily_activity a
       where a.user_id = p_user
    )
  on conflict (user_id, badge_code) do nothing;

  -- first_correct + correct_50: otoriter attempt fact tablosu.
  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, 'first_correct',
         jsonb_build_object('basis', 'attempts')
    where exists (
      select 1
        from public.student_question_attempts t
       where t.user_id = p_user
         and t.result = 'correct'
    )
  on conflict (user_id, badge_code) do nothing;

  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, 'correct_50',
         jsonb_build_object('basis', 'attempts',
                            'correct_count', v_count)
    from (
      select count(*) as v_count
        from public.student_question_attempts t
       where t.user_id = p_user
         and t.result = 'correct'
    ) c
   where c.v_count >= 50
  on conflict (user_id, badge_code) do nothing;

  -- streak_3 / streak_7: sunucudaki seri kaydı.
  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, b.code, jsonb_build_object('basis', 'streak',
                                            'current_streak', s.current_streak)
    from public.student_streaks s
   cross join (values ('streak_3', 3), ('streak_7', 7)) b(code, threshold)
   where s.user_id = p_user
     and s.current_streak >= b.threshold
  on conflict (user_id, badge_code) do nothing;

  -- first_competition: tamamlanmış yarışma katılımı.
  -- FAZ 9B: yalnız KARARA BAĞLANMIŞ sonuç türleri sayılır
  -- (cancelled/disputed katılımı rozet üretmez).
  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, 'first_competition',
         jsonb_build_object('basis', 'competitions')
    where exists (
      select 1
        from public.competition_players cp
        join public.competitions c on c.id = cp.competition_id
        join public.competition_results cr
          on cr.competition_id = c.id
       where cp.user_id = p_user
         and c.status = 'completed'
         and cr.result_type in ('win_loss', 'draw', 'forfeit')
    )
  on conflict (user_id, badge_code) do nothing;

  -- wins_10: kesinleşmiş galibiyet (tamamlanmış, karara bağlanmış
  -- yarışma sonucu). FAZ 9B: geçerli sonuç türü filtresi.
  insert into public.student_badges
    (user_id, badge_code, source_ref)
  select p_user, 'wins_10',
         jsonb_build_object('basis', 'competition_results',
                            'win_count', v_wins)
    from (
      select count(*) as v_wins
        from public.competition_results cr
       where cr.winner_user_id = p_user
         and cr.result_type in ('win_loss', 'forfeit')
         and exists (
           select 1
             from public.competitions c
            where c.id = cr.competition_id
              and c.status = 'completed'
         )
    ) w
   where w.v_wins >= 10
  on conflict (user_id, badge_code) do nothing;
end;
$$;


-- ============================================================
-- 3. ACL TEYİTLERİ (savunmacı, idempotent — 097 deseni)
-- ============================================================

revoke execute
on function public._faz5_apply_competition_points(uuid)
from public, anon, authenticated;

revoke execute
on function public._faz9_evaluate_badges(uuid)
from public, anon, authenticated;

comment on function public._faz5_apply_competition_points(uuid) is
  'Faz 5 rating motoru (+24/-12/0, 078/102). Faz 9: oyuncu basina tek seferlik XP (15/10/5). Faz 9b: gunluk aktivite + rozetler yalniz win_loss/draw/forfeit icin; cancelled/disputed streak veya yarisma rozeti uretmez.';
comment on function public._faz9_evaluate_badges(uuid) is
  'Faz 9: idempotent rozet degerlendirmesi. Faz 9b: first_competition ve wins_10 yalniz karara baglanmis sonuc turlerinden (win_loss/draw/forfeit).';


commit;
