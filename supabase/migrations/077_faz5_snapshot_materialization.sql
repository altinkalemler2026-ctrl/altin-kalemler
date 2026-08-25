-- ============================================================
-- 077_faz5_snapshot_materialization.sql
-- Altın Kalemler - Faz 5a
--
-- prepare_competition_pack artık paketi yalnız metadata olarak
-- degil, GERCEK snapshot satirlari olarak da yaziyor:
--   configuration.faz2_pack.question_ids -> competition_questions
--
-- Neden gerekli:
--   076'ya kadar paket secimi yalniz competitions.configuration
--   icine yaziliyordu; 023 akis RPC'leri (release/advance/sync)
--   competition_questions satirlari uzerinde calisir ve bos
--   snapshot ile yarisma oynanamaz durumdaydi. Materializasyon
--   ayni transaction icinde yapilir; exposure/kapasite yazilariyla
--   beraber ya hep ya hic (atomik).
--
-- MVP kararlari (Faz 5, kullanici onayli):
--   #8 Soru sayisi: yalniz 5 soru. Bu kisit yeni yarisma kurma
--      katmaninda (079) zorunlu tutulur; bu fonksiyon mevcut
--      CHECK (1..5) + trigger (022) korumasini asagi cekmez.
--
-- Guvenlik:
--   - Fonksiyon 076 birebir govde + FAZ5 ekleme; davranissal
--     degisiklik yalniz snapshot INSERT'idir.
--   - difficulty NULL olan soru varsa tum paket yazimi
--     FAIL-CLOSED iptal edilir (competition_questions.difficulty
--     NOT NULL'dir; sessiz null birakma yoktur).
--   - INSERT sonrasi satir sayisi beklenen soru sayisiyla
--     dogrulanir; uyusmazlikta istisna -> transaction rollback.
--   - 069 guard'lari (degistirilemezlik) ve 022 trigger'i
--     (limit) INSERT uzerinde aynen devrede kalir.
--
-- Idempotency: create or replace function.
-- ============================================================

begin;


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
  v_materialized integer;
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

  -- ------------------------------------------------------------
  -- FAZ5: SNAPSHOT MATERIALIZASYONU
  --
  -- Secilen sorular competition_questions satirlarina yazilir.
  -- 023 akis RPC'leri bu satirlar uzerinde calisir; released_at /
  -- deadline_at doldurma sorumlulugu akis katmanindadir (023),
  -- burada dokunulmaz.
  --
  -- FAIL-CLOSED: difficulty NULL olan secili soru varsa istisna;
  -- tum transaction (exposure + kapasite + metadata dahil) geri
  -- alinir ve yarisma tekrar pack hazirlanabilir durumda kalir.
  --
  -- 022 trigger'i (validate_competition_question_limit) her INSERT
  -- satirinda declare edilen question_count ust sinirini korur;
  -- UNIQUE(competition_id, question_order / question_id) ikinci
  -- savunma hattidir.
  -- ------------------------------------------------------------
  if coalesce(array_length(v_qids, 1), 0) <> r_comp.question_count then
    raise exception
      'Secilen soru sayisi beklenenle uyumsuz (%/%).',
      coalesce(array_length(v_qids, 1), 0), r_comp.question_count
      using errcode = 'P0001';
  end if;

  if exists (
       select 1
         from unnest(v_qids) u
         join public.questions q on q.id = u
        where q.difficulty is null
           or q.difficulty not in ('easy', 'medium', 'hard')
     ) then
    raise exception
      'Secili sorularda gecersiz/eksik zorluk var; snapshot yazimi iptal.'
      using errcode = 'P0001';
  end if;

  insert into public.competition_questions
    (competition_id, question_id, question_order, difficulty)
  select
    r_comp.id,
    u.question_id,
    u.ord,
    q.difficulty
  from unnest(v_qids) with ordinality as u(question_id, ord)
  join public.questions q
    on q.id = u.question_id
  order by u.ord;

  get diagnostics v_materialized = row_count;

  if v_materialized <> r_comp.question_count then
    raise exception
      'Snapshot materializasyonu eksik (%/%); transaction geri aliniyor.',
      v_materialized, r_comp.question_count
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
-- EXECUTE MATRISI (drift guard; 076 durumu korunur)
-- ============================================================

revoke execute
on function public.prepare_competition_pack(uuid)
from public, anon, authenticated;
grant execute
on function public.prepare_competition_pack(uuid)
to authenticated;


commit;


-- ============================================================
-- DOGRULAMA
-- ============================================================

select
  p.proname as function_name,
  p.prosecdef as is_security_definer,
  p.proconfig as search_path_config
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'prepare_competition_pack';
