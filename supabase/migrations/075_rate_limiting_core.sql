-- ============================================================
-- 075_rate_limiting_core.sql
-- Altın Kalemler - Faz 4 (075): Öğrenci RPC rate limiting ÇEKİRDEĞİ
--
-- Amaç:
--   select_training_questions / get_my_weekly_usage /
--   prepare_competition_pack / submit_training_attempt gibi
--   öğrenciye açık RPC'ler için kullanıcı-bazlı, DB tabanlı
--   sabit-pencereli (fixed-window) istek sınırı.
--
-- Tasarım kararları (Faz 4 read-only analizi -> kullanıcı onayı):
--   - Yalnız auth.uid() katmanı: RPC trafiği Next sunucusundan
--     çıktığı için IP katmanı Postgres'te anlamsızdır; cihaz izi yok.
--   - Redis/edge yerine Postgres: yeni infra yok; atomiklik
--     student_weekly_counters (063/068) deseninin aynısıdır.
--   - Pencere hesabı epoch hizalıdır:
--       to_timestamp(floor(extract(epoch from clock_timestamp())
--                    / p_window_seconds) * p_window_seconds)
--     (date_trunc KULLANILMAZ: pencere uzunluğu parametrikken yanlış
--     hizalanır.)
--   - Geçersiz iç parametrede fail-closed: p_limit/p_window_seconds
--     > 0 ve rpc_name boş olmamak zorundadır; aksi halde P0001.
--   - Reddedilen istek kota TÜKETMEZ (guard'lı UPDATE satırı
--     güncellemez, raise ile transaction geri alınır).
--
-- Güvenlik modeli:
--   - rpc_rate_limits: RLS AÇIK + policy YOK + anon/authenticated'a
--     HİÇBİR direct grant YOK (academic_weeks modeli). İstemci bu
--     tabloya asla erişemez; yalnız SECURITY DEFINER helper yazar.
--   - _faz4_consume_rate_limit: SECURITY DEFINER + search_path=''.
--     EXECUTE public/anon/authenticated'dan alınır; HİÇBİR role
--     grant VERİLMEZ (yalnız definer gövdeleri içinden çağrılır;
--     definer zinciri EXECUTE kontrolünden geçmez -- 070 §4 önceli).
-- ============================================================

begin;


-- ------------------------------------------------------------
-- 1. SAYAÇ TABLOSU (additive)
--    Büyüme sınırlıdır: PK (user_id, rpc_name, window_start)
--    sayesinde satır sayisi ~ aktif kullanici x rpc x pencere.
-- ------------------------------------------------------------

create table if not exists public.rpc_rate_limits (
  user_id      uuid        not null,
  rpc_name     text        not null,
  window_start timestamptz not null,
  hit_count    integer     not null default 0,

  primary key (user_id, rpc_name, window_start),

  constraint rpc_rate_limits_hit_nonnegative
    check (hit_count >= 0)
);

alter table public.rpc_rate_limits enable row level security;

comment on table public.rpc_rate_limits is
  'Faz 4: kullanici-bazli sabit-pencereli RPC rate limit sayacları. RLS acik + policy yok + istemci grant yok; yalniz _faz4_consume_rate_limit (SECURITY DEFINER) yazar.';

comment on column public.rpc_rate_limits.window_start is
  'Epoch hizali pencere baslangici: floor(unix_ts / window_seconds) * window_seconds.';


-- ------------------------------------------------------------
-- 2. ATOMİK TÜKETİM HELPER'I (internal-only)
-- ------------------------------------------------------------

create or replace function public._faz4_consume_rate_limit(
  p_rpc_name       text,
  p_limit          integer,
  p_window_seconds integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_win  timestamptz;
  v_ok   integer;
begin
  -- --------------------------------------------------------
  -- Fail-closed iç yapılandırma doğrulaması: çağıranlar bizim
  -- kendi RPC gövdelerimizdir; bozuk konfigürasyon sessizce
  -- limitsiz davranış ÜRETMEZ, açıkça patlar.
  -- --------------------------------------------------------
  if p_rpc_name is null or btrim(p_rpc_name) = ''
     or length(p_rpc_name) > 64 then
    raise exception 'Rate limit yapilandirmasi gecersiz (rpc_name).'
      using errcode = 'P0001';
  end if;

  if p_limit is null or p_limit < 1 then
    raise exception 'Rate limit yapilandirmasi gecersiz (p_limit).'
      using errcode = 'P0001';
  end if;

  if p_window_seconds is null or p_window_seconds < 1 then
    raise exception 'Rate limit yapilandirmasi gecersiz (p_window_seconds).'
      using errcode = 'P0001';
  end if;

  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  -- Epoch hizalı pencere başlangıcı (parametrik uzunluk).
  v_win := to_timestamp(
    floor(
      extract(epoch from clock_timestamp()) / p_window_seconds
    ) * p_window_seconds
  );

  -- Pencere satırı yoksa sıfırdan aç.
  insert into public.rpc_rate_limits
    (user_id, rpc_name, window_start, hit_count)
  values
    (v_user, btrim(p_rpc_name), v_win, 0)
  on conflict (user_id, rpc_name, window_start) do nothing;

  -- TEK İFADE atomik artış: WHERE guard'ı limit aşımında satırı
  -- güncellemez. Eşzamanlı çağrılar satır kilidinde serileşir;
  -- toplam hit_count p_limit'i ASLA aşamaz (068 sayaç deseni).
  update public.rpc_rate_limits r
     set hit_count = r.hit_count + 1
   where r.user_id = v_user
     and r.rpc_name = btrim(p_rpc_name)
     and r.window_start = v_win
     and r.hit_count < p_limit
  returning 1 into v_ok;

  if v_ok is null then
    raise exception
      'Cok fazla istek gonderildi; lutfen kisa bir sure sonra tekrar deneyin.'
      using errcode = 'P0001';
  end if;
end;
$$;

comment on function public._faz4_consume_rate_limit(text, integer, integer) is
  'Faz 4 internal: kullanici-bazli fixed-window rate limit tuketimi. Istemciye KAPALI; yalniz RPC govdelerinden cagrilir. Reddedilen istek kota tuketmez.';


-- ------------------------------------------------------------
-- 3. EXECUTE MATRİSİ: tamamen kapalı (internal-only)
-- ------------------------------------------------------------

revoke execute
on function public._faz4_consume_rate_limit(text, integer, integer)
from public, anon, authenticated;


commit;
