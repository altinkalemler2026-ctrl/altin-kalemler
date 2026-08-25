-- ============================================================
-- 079_faz5_matchmaking_entry.sql
-- Altın Kalemler - Faz 5a
--
-- Öğrenci giriş noktası RPC'leri (MVP karar #1 ve #8):
--
--   join_matchmaking_queue(p_subject_id uuid) -> jsonb
--     - Rastgele standart kuyruk: aynı grade + ders içindeki
--       en eski bekleyen öğrenciyle FIFO eşleşme.
--     - Kuyruk girişinde zaten bekleyen kayıt varsa idempotent
--       davranır ve eşleşme fırsatını yeniden dener.
--     - Eşleşme bulunursa yarisma + iki oyuncu AYNI
--       transaction'da kurulur; kuyruk satirlari 'matched'.
--     - Eşzamanlılık: (grade,subject) basina advisory
--       transaction kilidi -> iki islem ayni cifti kuramaz,
--       ayni ogrenciyi iki farkli yarisma ya yazamaz.
--
--   leave_matchmaking_queue() -> jsonb
--     - Bekleyen kuyruk girisini iptal eder.
--
-- MVP kararlarinin DB yansimalari:
--   #8 Soru sayisi: kurulan her yarisma question_count = 5.
--      (CHECK 1..5 ust siniri zaten vardi; alt sinir burada.)
--   #7 Kapasite: kuyruk/yarisma kurulumu haftalik soru
--      kapasitesini kontrol etmez; kapasite paket hazirlama
--      sirasinda clamp ile islenmeye devam eder (076).
--
-- Guvenlik:
--   - SECURITY DEFINER + search_path='' (tam niteleme).
--   - Kimlik yalniz auth.uid()'den; parametreyle kullanici alinmaz.
--   - Ders aktif degilse / profil yoksa FAIL-CLOSED.
--   - Rate limit FAZ4: queue_join 10/300sn.
--   - Tablolarda ogrenci INSERT policy'si yoktur; yazim yalniz
--     bu RPC'ler uzerinden yapilir.
--
-- Idempotency: create or replace function + on conflict do nothing.
-- ============================================================

begin;


-- ============================================================
-- 1. VARSAYILAN PUANLAMA KURAL SETI (idempotent seed)
--
-- Yarisma kurulusu scoring_rule_set_id zorunludur (019 NOT NULL).
-- ============================================================

insert into public.scoring_rule_sets
  (rule_set_code, name, description, version, is_active)
values
  ('faz5_default',
   'Faz 5 Varsayılan Puanlama',
   'Yarışmalar için varsayılan puanlama kural seti.',
   '1',
   true)
on conflict (rule_set_code) do nothing;


-- ============================================================
-- 2. JOIN_MATCHMAKING_QUEUE(uuid)
-- ============================================================

create or replace function public.join_matchmaking_queue(
  p_subject_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user      uuid;
  v_grade     smallint;
  v_subject   uuid;
  v_queue_id  uuid;
  r_partner   public.matchmaking_queue%rowtype;
  v_rule_set  uuid;
  v_comp_id   uuid;
  v_comp_code text;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  -- FAZ4: kuyruk yazimi korumasi.
  perform public._faz4_consume_rate_limit('queue_join', 10, 300);

  if p_subject_id is null then
    raise exception 'Ders zorunludur.' using errcode = '22004';
  end if;

  select s.id into v_subject
    from public.subjects s
   where s.id = p_subject_id
     and s.is_active = true;

  if v_subject is null then
    raise exception 'Ders bulunamadi veya pasif.'
      using errcode = 'P0001';
  end if;

  select sp.grade_level into v_grade
    from public.student_profiles sp
   where sp.id = v_user;

  if v_grade is null then
    raise exception 'Ogrenci profili bulunamadi; kuyruğa girilemez.'
      using errcode = 'P0001';
  end if;

  -- Zaten bekliyor mu? (idempotent yeniden deneme noktasi)
  select mq.id into v_queue_id
    from public.matchmaking_queue mq
   where mq.user_id = v_user
     and mq.status = 'waiting'
   order by mq.joined_at desc
   limit 1;

  if v_queue_id is null then
    insert into public.matchmaking_queue
      (user_id, grade_level, subject_id, queue_type,
       status, preferences, expires_at)
    values
      (v_user, v_grade, v_subject, 'standard',
       'waiting', '{}'::jsonb, now() + interval '15 minutes')
    returning id into v_queue_id;
  else
    -- Eşleşme güncellemesinden önce kendi satirimizi kilitle.
    perform 1
      from public.matchmaking_queue mq
     where mq.id = v_queue_id
       and mq.status = 'waiting'
       for update;

    if not found then
      -- Bu ara kendi kaydımız eşleşmiş/iptal olmuş; güncel durumu oku.
      select mq.id into v_queue_id
        from public.matchmaking_queue mq
       where mq.user_id = v_user
         and mq.status = 'waiting'
       order by mq.joined_at desc
       limit 1;
    end if;
  end if;

  if v_queue_id is null then
    -- Nadir: ilk insert sonrasi beklemeden matched oldu (paralel
    -- cagri). Tekrar girip durum raporla.
    select mq.id into v_queue_id
      from public.matchmaking_queue mq
     where mq.user_id = v_user
     order by mq.joined_at desc
     limit 1;
  end if;

  -- ------------------------------------------------------------
  -- Eslesme serilestirme: ayni (grade,subject) kovasinda tek islem.
  -- ------------------------------------------------------------
  perform pg_advisory_xact_lock(
    hashtextextended('faz5mm:' || v_grade::text || ':' || v_subject::text, 0)
  );

  select * into r_partner
    from public.matchmaking_queue mq2
   where mq2.id is distinct from v_queue_id
     and mq2.status = 'waiting'
     and mq2.grade_level = v_grade
     and mq2.subject_id = v_subject
     and mq2.user_id <> v_user
     and (mq2.expires_at is null or mq2.expires_at > now())
   order by mq2.joined_at asc
   limit 1;

  if r_partner.id is null then
    return jsonb_build_object(
      'status', 'waiting',
      'queue_id', v_queue_id,
      'grade_level', v_grade,
      'subject_id', v_subject
    );
  end if;

  -- Partner satirini kilitle (READ COMMITTED altinda taze deger).
  select * into r_partner
    from public.matchmaking_queue mq2
   where mq2.id = r_partner.id
     and mq2.status = 'waiting'
     for update;

  if r_partner.id is null then
    return jsonb_build_object(
      'status', 'waiting',
      'queue_id', v_queue_id,
      'grade_level', v_grade,
      'subject_id', v_subject
    );
  end if;

  -- ------------------------------------------------------------
  -- Yarisma kurulumu (question_count = 5, MVP #8).
  -- ------------------------------------------------------------
  select srs.id into v_rule_set
    from public.scoring_rule_sets srs
   where srs.is_active = true
   order by (srs.rule_set_code = 'faz5_default') desc,
            srs.created_at asc
   limit 1;

  if v_rule_set is null then
    raise exception 'Aktif puanlama kural seti yok; yarisma kurulamaz.'
      using errcode = 'P0001';
  end if;

  v_comp_code :=
    'F5-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

  insert into public.competitions
    (competition_code, competition_type, grade_level,
     subject_id, scoring_rule_set_id, status, question_count)
  values
    (v_comp_code, 'one_vs_one', v_grade,
     v_subject, v_rule_set, 'waiting', 5)
  returning id into v_comp_id;

  insert into public.competition_players
    (competition_id, user_id, player_slot)
  values
    (v_comp_id, r_partner.user_id, 1),
    (v_comp_id, v_user, 2);

  update public.matchmaking_queue mq
     set status = 'matched',
         matched_at = now()
   where mq.id in (r_partner.id, v_queue_id);

  return jsonb_build_object(
    'status', 'matched',
    'queue_id', v_queue_id,
    'competition_id', v_comp_id,
    'competition_code', v_comp_code,
    'grade_level', v_grade,
    'subject_id', v_subject
  );
end;
$$;


-- ============================================================
-- 3. LEAVE_MATCHMAKING_QUEUE()
-- ============================================================

create or replace function public.leave_matchmaking_queue()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid;
  v_count integer := 0;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  update public.matchmaking_queue mq
     set status = 'cancelled'
   where mq.user_id = v_user
     and mq.status = 'waiting';

  get diagnostics v_count = row_count;

  return jsonb_build_object('cancelled', v_count);
end;
$$;


-- ============================================================
-- 4. EXECUTE MATRISI (drift guard)
-- ============================================================

revoke execute
on function public.join_matchmaking_queue(uuid)
from public, anon, authenticated;
grant execute
on function public.join_matchmaking_queue(uuid)
to authenticated;

revoke execute
on function public.leave_matchmaking_queue()
from public, anon, authenticated;
grant execute
on function public.leave_matchmaking_queue()
to authenticated;


commit;


-- ============================================================
-- DOGRULAMA
-- ============================================================

select
  p.proname as function_name,
  p.prosecdef as is_security_definer,
  has_function_privilege('authenticated', p.oid, 'EXECUTE')
    as authenticated_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'join_matchmaking_queue',
    'leave_matchmaking_queue'
  )
order by p.proname;

select rule_set_code, version, is_active
from public.scoring_rule_sets
where rule_set_code = 'faz5_default';
