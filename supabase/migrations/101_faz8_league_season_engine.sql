-- ============================================================
-- 101_faz8_league_season_engine.sql
-- Altın Kalemler - Faz 8
--
-- Aynı sınıf ligi, leaderboard entry üretici motoru ve sezon
-- yaşam döngüsü.
--
-- MEVCUT SÖZLEŞME (dokunulmaz, birebir korunur):
--   016: Bronz 0-999 / Gümüş 1000-2499 / Altın 2500-4999 /
--        Elmas 5000+ puan bantları; lig tabloları.
--   078: rating sabit tablosu (win +24 / loss -12 / draw 0);
--        competition_point_changes UNIQUE(competition_id,user_id,
--        change_type) idempotency; puan bandı ile sürekli
--        promotion/demotion; student_league_history.
--   finalize_competition_if_ready ve _faz5_apply_competition_points
--   gövdeDeğişikliği YAPILMAZ; davranış yalnızca additive trigger
--   ve yeni fonksiyonlarla genişletilir.
--
-- KULLANICI ONAYLI FAZ 8 ÜRÜN KARARLARI (bu oturum):
--   K1 Sezon durumları zamandan türetilir (is_active + starts_at/
--      ends_at): upcoming / active / closing / completed.
--   K2 Sezon kapanışında rating 0'a sıfırlanır ve öğrenci en alt
--      (Bronz) lige placement üyeliğiyle başlar; eski sezon rating
--      bilgisi history + snapshot entry'de kalır.
--   K3 Sıralama beraberliği (tie-break): eşit rating'te üyelik
--      giriş tarihi (entered_at) önce olan üstte; o da eşitse
--      takma ad alfabetik. Kural yalnız sunucuda uygulanır.
--   K4 Sezon kapanışı yalnız yetkili service/admin bakım RPC'siyle
--      tetiklenir; ends_at sabit cutoff'tur; kapanıştan sonra
--      gelen yarışma sonucu yeni sezon üyeliğine yazılır.
--
-- YENİ YÜZEYLER:
--   - league_season_close_results: kapanış idempotency/audit kaydı
--     (season_id UNIQUE -> aynı kapanış en fazla bir sonuç üretir).
--   - student_league_memberships üzerinde kısmi UNIQUE indeks:
--     kullanıcı başına en fazla bir güncel genel üyelik.
--   - leaderboard_seasons üzerinde tek-aktif-sezon UNIQUE indeksi.
--   - _faz8_attach_membership_season: üyeliğe güncel sezonu
--     sunucu-otoriter bağlar (istemci sezon gönderemez).
--   - _faz8_upsert_membership_entry: rating olayında aynı sezon/
--     sınıf/lig kapsamında atomik entry üretimi (duplicate yok).
--   - get_my_league_ranking: öğrenci okuma RPC'si; grade/season
--     parametresi ALMAZ; auth.uid + student_profiles'tan türetir;
--     PII allowlist; rate limit; UUID sızdırmaz.
--   - close_league_season: service/admin bakım RPC'si; öğrenciye
--     kapalı; tablo kilidiyle rating motoruyla serileşir; iki
--     eşzamanlı kapanış güvenli; ikinci kapanış no-op.
-- ============================================================

begin;


-- ============================================================
-- 1. SEZON KAPANIŞ SONUÇ TABLOSU (idempotency + audit)
-- ============================================================

create table if not exists public.league_season_close_results (
  season_id uuid primary key
    references public.leaderboard_seasons(id)
    on delete cascade,

  closed_at timestamptz not null default now(),

  snapshot_entry_count integer not null default 0
    check (snapshot_entry_count >= 0),

  membership_close_count integer not null default 0
    check (membership_close_count >= 0),

  next_season_id uuid
    references public.leaderboard_seasons(id),

  metadata jsonb not null default '{}'::jsonb
);

alter table public.league_season_close_results
  enable row level security;

revoke all on table public.league_season_close_results
  from public;

revoke all on table public.league_season_close_results
  from anon, authenticated;

grant select, insert, update, delete
  on table public.league_season_close_results
  to service_role;

comment on table public.league_season_close_results is
  'Faz 8: sezon kapanis idempotency kaydi. season_id PRIMARY KEY ile ayni sezon en fazla bir kez kapanir. Istemci erisimi yoktur; kapanis yalniz close_league_season (service bakim yolu) ile yapilir.';


-- ============================================================
-- 2. TAMPON KISITLAR (veri bütünlüğü)
-- ============================================================

-- 2a. Aynı anda tek aktif sezon (015 iki is_active=true'ya izin
--     veriyordu; Faz 8 kapanış determinizmi için kısıtlanır).
create unique index if not exists uq_leaderboard_seasons_one_active
  on public.leaderboard_seasons (is_active)
  where is_active = true;

-- 2b. Kullanıcı başına en fazla bir GÜNCEL genel üyelik
--     (016 iki güncel satıra izin veriyordu; 078 motoru tek satır
--     seçiyordu; Faz 8 veri bütünlüğünü veritabanı düzeyinde
--     garanti eder).
create unique index if not exists uq_slm_one_current_general
  on public.student_league_memberships (user_id)
  where is_current = true
    and membership_scope = 'general';

comment on index uq_leaderboard_seasons_one_active is
  'Faz 8: ayni anda en fazla bir aktif sezon (cakisan aktif sezon yok).';

comment on index uq_slm_one_current_general is
  'Faz 8: ogrenci ayni anda tek guncel genel lig uyeligine sahip olur.';


-- ============================================================
-- 3. SEZON DURUM YARDIMCISI (K1: zamandan türetim)
--    upcoming | active | closing | completed | inactive
-- ============================================================

create or replace function public._faz8_season_status(
  p_is_active boolean,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_is_closed boolean
)
returns text
language sql
stable
as $$
  select case
    when p_is_closed is true then 'completed'
    when coalesce(p_starts_at, 'infinity'::timestamptz) > now()
      then 'upcoming'
    when p_is_active is true
      and coalesce(p_starts_at, '-infinity'::timestamptz) <= now()
      and now() < coalesce(p_ends_at, '-infinity'::timestamptz)
      then 'active'
    when coalesce(p_ends_at, 'infinity'::timestamptz) <= now()
      then 'closing'
    else 'inactive'
  end;
$$;

revoke execute on function public._faz8_season_status(boolean, timestamptz, timestamptz, boolean)
  from public, anon, authenticated;

comment on function public._faz8_season_status(boolean, timestamptz, timestamptz, boolean) is
  'Faz 8 K1: sezon durumu is_active + zaman penceresi + kapanis kaydindan turetilir (durum kolonu yoktur).';


-- ============================================================
-- 4. ÜYELİĞE GÜNCEL SEZONU SUNUCU-OTORİTER BAĞLAMA
--    İstemci season_id gönderemez; 078 motorunun ürettiği
--    üyeliklere aktif sezon otomatik bağlanır.
-- ============================================================

create or replace function public._faz8_attach_membership_season()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_season uuid;
begin
  if new.season_id is not null then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.season_id is not null then
    return new;
  end if;

  select s.id
    into v_season
    from public.leaderboard_seasons s
   where s.is_active = true
     and s.ends_at > now()
   order by s.starts_at desc
   limit 1;

  new.season_id := v_season;

  return new;
end;
$$;

revoke execute on function public._faz8_attach_membership_season()
  from public, anon, authenticated;

drop trigger if exists faz8_attach_membership_season
  on public.student_league_memberships;

create trigger faz8_attach_membership_season
  before insert or update
  on public.student_league_memberships
  for each row
  execute function public._faz8_attach_membership_season();


-- ============================================================
-- 5. LEADERBOARD ENTRY ÜRETİCİ MOTORU
--    Rating olayında (üyelik puan güncellemesi) aynı
--    sezon/tanım/kullanıcı/kapsam için ATOMİK upsert:
--    - duplicate entry üretmez (UNIQUE index koruması),
--    - eski/hatalı entry güvenli biçimde yenilenir,
--    - grade sunucudaki student_profiles'tan alınır,
--    - season sunucudaki üyelik satırından alınır,
--    - yalnız aktif zaman penceresindeki sezon için çalışır
--      (kapanış anında eski sezona entry üretmez).
-- ============================================================

create or replace function public._faz8_upsert_membership_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_def uuid;
  v_grade smallint;
  v_league_code text;
  v_season_active boolean;
begin
  if new.is_current is not true
     or new.membership_scope is distinct from 'general'
     or new.season_id is null then
    return null;
  end if;

  select true
    into v_season_active
    from public.leaderboard_seasons s
   where s.id = new.season_id
     and s.is_active = true
     and s.ends_at > now();
  if v_season_active is null then
    return null;
  end if;

  select d.id
    into v_def
    from public.leaderboard_definitions d
   where d.leaderboard_code = 'league_ranking'
     and d.is_active = true
   limit 1;
  if v_def is null then
    return null;
  end if;

  select sp.grade_level
    into v_grade
    from public.student_profiles sp
   where sp.id = new.user_id;
  if v_grade is null then
    return null;
  end if;

  select l.league_code
    into v_league_code
    from public.leagues l
   where l.id = new.league_id;

  -- Tek-satır değişmezliği: aynı (sezon, tanım, kullanıcı) için
  -- eski/layıh entry güvenli biçimde yenilenir (duplicate yok).
  delete from public.leaderboard_entries e
   where e.season_id = new.season_id
     and e.leaderboard_definition_id = v_def
     and e.user_id = new.user_id
     and e.scope_type = 'league'
     and (e.scope_reference_id is distinct from new.league_id
          or e.points is distinct from new.current_points);

  insert into public.leaderboard_entries
    (season_id, leaderboard_definition_id, user_id, grade_level,
     scope_type, scope_reference_id, league_code, points, updated_at)
  values
    (new.season_id, v_def, new.user_id, v_grade,
     'league', new.league_id, v_league_code, new.current_points, now())
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
        updated_at = now();

  return null;
end;
$$;

revoke execute on function public._faz8_upsert_membership_entry()
  from public, anon, authenticated;

drop trigger if exists faz8_upsert_membership_entry
  on public.student_league_memberships;

create trigger faz8_upsert_membership_entry
  after insert or update
  on public.student_league_memberships
  for each row
  execute function public._faz8_upsert_membership_entry();


-- ============================================================
-- 6. AYNI SINIF GÜVENLİ OKUMA RPC'Sİ
--    get_my_league_ranking(p_limit, p_offset)
--
--    - p_user_id / p_grade_level / p_school_id / p_classroom_id
--      ALMAZ; grade auth.uid() + student_profiles'tan gelir.
--    - Kimliksiz ve profilsiz kullanıcı fail-closed reddedilir.
--    - Yalnız KENDİ grade + KENDİ güncel lig kapsamını döndürür.
--    - Başka öğrencilerin auth UUID'sini döndürmez.
--    - Yalnız izinli alanlar: rank, is_current_student, nickname,
--      avatar_key, league_code, league_name, rating.
--    - Rate limit: get_my_league_ranking 30 istek / 60 sn.
--    - Pagination: limit 1..100 (üstte sınırlanır), offset >= 0.
--    - Tie-break (K3): rating desc, entered_at asc, nickname asc.
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
  r_my record;
  v_limit integer;
  v_offset integer;
  v_result jsonb;
  r_next record;
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

  -- Güncel aktif sezon (zamandan türetilen durum; K1).
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

  -- Öğrencinin bu sezondaki güncel genel üyeliği (lig kapsamı).
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
        order by e.points desc, m.entered_at asc, pp.nickname asc
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

revoke execute on function public.get_my_league_ranking(integer, integer)
  from public, anon;

grant execute on function public.get_my_league_ranking(integer, integer)
  to authenticated;

comment on function public.get_my_league_ranking(integer, integer) is
  'Faz 8: ogrencinin KENDI sinif + lig kapsamindaki guvenli siralamasi. Grade/season/user parametresi yoktur; auth.uid ve student_profiles uzerinden turetilir. PII allowlist: rank/is_current_student/nickname/avatar_key/league_code/league_name/rating.';


-- ============================================================
-- 7. SEZON KAPANIŞ BAKIM RPC'Sİ (service/admin yolu)
--    close_league_season(p_season_id)
--
--    - Yalnız service_role çalıştırabilir (authenticated/anon kapalı).
--    - ends_at sabit cutoff; ends_at öncesi tetiklenemez (K4).
--    - student_league_memberships üzerinde EXCLUSIVE kilit:
--      rating motoruyla serileşir; geç sonuç yeni sezona yazılır.
--    - İdempotent: ikinci kapanış 'already_closed' no-op.
--    - Snapshot: grade + lig kapsamında deterministik sıra
--      (rating desc, entered_at asc, nickname asc — K3).
--    - K2: üyelikler kapanır; bir sonraki sezon varsa Bronz
--      placement üyelikleri rating 0 ile açılır; reset history
--      satırları yazılır.
--    - Herhangi bir adımda hata -> tüm işlem rollback.
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
  --    Kapsam: genel üyeliği olan, profili (sınıf) ve public profili
  --    (takma ad) olan tüm öğrenciler. Sıra: rating desc,
  --    entered_at asc, nickname asc (K3). Gizlilik LISTE okuma
  --    katmanında uygulanır (entry üretimi gizlilik yargılamaz).
  --    Ön normalizasyon: güncel üyeliğiyle ligi uyuşmayan bayat
  --    entry'ler (varsa) güvenle yenilenir.
  delete from public.leaderboard_entries e
   where e.season_id = r_season.id
     and e.leaderboard_definition_id = v_definition
     and e.scope_type = 'league'
     and exists (
       select 1
         from public.student_league_memberships m
        where m.user_id = e.user_id
          and m.is_current = true
          and m.membership_scope = 'general'
          and (m.season_id = r_season.id or m.season_id is null)
          and m.league_id is distinct from e.scope_reference_id);

  with snap as (
    insert into public.leaderboard_entries
      (season_id, leaderboard_definition_id, user_id, grade_level,
       scope_type, scope_reference_id, league_code, points, rank_position,
       updated_at)
    select
      r_season.id,
      v_definition,
      m.user_id,
      sp.grade_level,
      'league',
      m.league_id,
      l.league_code,
      m.current_points,
      row_number() over (
        partition by sp.grade_level, m.league_id
        order by m.current_points desc, m.entered_at asc,
                 coalesce(pp.nickname, '') asc
      ),
      now()
    from public.student_league_memberships m
    join public.student_profiles sp
      on sp.id = m.user_id
    join public.student_public_profiles pp
      on pp.user_id = m.user_id
    join public.leagues l
      on l.id = m.league_id
    where m.is_current = true
      and m.membership_scope = 'general'
      and (m.season_id = r_season.id or m.season_id is null)
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

  -- 2) KAPANIŞ sayımı (history + üyelik kapanışından ÖNCE).
  select count(*)
    into v_close_count
    from public.student_league_memberships m
   where m.is_current = true
     and m.membership_scope = 'general'
     and (m.season_id = r_season.id or m.season_id is null);

  -- 3) RESET HISTORY (K2): append-only geçmiş; eski lig ve rating
  --    bilgisi kaydedilir. transition_type mevcut CHECK kümesindeki
  --    'reset' değeridir (016).
  insert into public.student_league_history
    (user_id, season_id, from_league_id, to_league_id,
     transition_type, points_at_transition, reason)
  select
    m.user_id,
    r_season.id,
    m.league_id,
    v_bronze,
    'reset',
    m.current_points,
    'season_reset'
  from public.student_league_memberships m
  where m.is_current = true
    and m.membership_scope = 'general'
    and (m.season_id = r_season.id or m.season_id is null);

  -- 4) ÜYELİK KAPANIŞI.
  update public.student_league_memberships m
     set is_current = false,
         exited_at = now(),
         updated_at = now()
   where m.is_current = true
     and m.membership_scope = 'general'
     and (m.season_id = r_season.id or m.season_id is null);

  -- 5) SEZON DURUM GEÇİŞİ: önce kapanan sezon pasifleşir
  --    (tek-aktif-sezon UNIQUE indeksini bozmamak için sıralı).
  update public.leaderboard_seasons s
     set is_active = false,
         updated_at = now()
   where s.id = r_season.id;

  -- 6) YENİ SEZON ÜYELİKLERİ (K2): Bronz, rating 0. Yeni sezon
  --    yoksa üyelik açılmaz; öğrenci ilk yarışma sonucunda motor
  --    tarafından açılır.
  if r_next.id is not null then
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
       'trigger', 'close_league_season'
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

revoke execute on function public.close_league_season(uuid)
  from public, anon, authenticated;

grant execute on function public.close_league_season(uuid)
  to service_role;

comment on function public.close_league_season(uuid) is
  'Faz 8 K2/K4: sezon kapanisi (service/admin bakim yolu). ends_at cutoff; rating 0 + Bronz placement; append-only reset history; idempotent (season_id UNIQUE). Ogrenci/anon calistiramaz.';


commit;


-- ============================================================
-- DOĞRULAMA (uygulama sonrası görünürlük)
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
    '_faz8_attach_membership_season',
    '_faz8_upsert_membership_entry',
    '_faz8_season_status'
  )
order by p.proname;

select
  has_function_privilege('authenticated',
    'public.get_my_league_ranking(integer,integer)', 'EXECUTE')
    as authenticated_can_execute,
  has_function_privilege('anon',
    'public.get_my_league_ranking(integer,integer)', 'EXECUTE')
    as anon_can_execute,
  has_function_privilege('authenticated',
    'public.close_league_season(uuid)', 'EXECUTE')
    as authenticated_can_close,
  has_function_privilege('service_role',
    'public.close_league_season(uuid)', 'EXECUTE')
    as service_can_close;
