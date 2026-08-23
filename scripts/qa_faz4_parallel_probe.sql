-- ============================================================
-- scripts/qa_faz4_parallel_probe.sql
-- Altin Kalemler - Faz 4 rate-limit eszamanliiyik probe'u
--
-- SENARYO (ayni-kullanici son-kota yarisi):
--   Tek oyuncu (R) icin probe_race limiti 5'e ayarlanir ve sayac
--   kurulumda 4'e PRIME edilir (son tek kota). TAG=a ve TAG=b
--   oturumlari AYNI kullanici kimligiyle AYNI anda tuketir.
--   _faz4_consume_rate_limit'in guard'li UPDATE'i satir kilidinde
--   serilestirir; beklenen DETERMINISTIK sonuc:
--
--     tam BIR isci RESULT=OK, oteki RESULT=LIMITED
--     hit_count == 5   (tavan ASLA asilmaz)
--     yalnizca PRIME edilen pencere satiri vardir
--
-- Kullanim (LOCAL ONLY):
--   docker cp scripts/qa_faz4_parallel_probe.sql supabase_db_yarisma-programi:/tmp/
--   # 1) fikstur + sayaç PRIME (idempotent)
--   docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -v MODE=setup -f /tmp/qa_faz4_parallel_probe.sql
--   # 2) iki eszamanli isci (iki ayri terminal, ayni anda)
--   docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -v MODE=work -v TAG=a -f /tmp/qa_faz4_parallel_probe.sql
--   docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -v MODE=work -v TAG=b -f /tmp/qa_faz4_parallel_probe.sql
--   # 3) dogrulama (herhangi FAIL -> exit code != 0)
--   docker exec ... -v MODE=verify -f ...
--   # 4) temizlik
--   docker exec ... -v MODE=cleanup -f ...
--
-- NOT: Isciler postgres baglantisi + request.jwt.claims ile oyuncu
-- adina hareket eder (helper EXECUTE'u istemcilere kapalidir;
-- Faz 4 QA suite ve Faz 2 probe ile ayni kalip).
-- ============================================================

\set ON_ERROR_STOP on

\if :{?MODE}
\else
\warn MODE tanimli degil: setup|work|verify|cleanup bekleniyor
\q
\endif

select :'MODE' = 'setup'   as m_setup,
       :'MODE' = 'work'    as m_work,
       :'MODE' = 'cleanup' as m_cleanup,
       :'MODE' = 'verify'  as m_verify
\gset


-- ------------------------------------------------------------
-- MODE=setup : oyuncu + probe tablosu + sayac PRIME (hit=4/5)
-- ------------------------------------------------------------

\if :m_setup

begin;

insert into auth.users (id, email)
values ('99999999-9999-9999-9999-999999999931', 'qa4-race@test.local')
on conflict (id) do nothing;

insert into public.student_profiles (id, grade_level, nickname)
values ('99999999-9999-9999-9999-999999999931', 12, 'QA4-NICK-RACE')
on conflict (id) do nothing;

create table if not exists public._qa4_probe_results (
  tag    text primary key,
  result text not null check (result in ('OK', 'LIMITED')),
  at     timestamptz not null default clock_timestamp()
);

grant select, insert, update, delete
  on public._qa4_probe_results
  to anon, authenticated, service_role;

-- Idempotent PRIME: eski probe sayaclarini temizle, taze satiri
-- mevcut epoch-hizali pencerede hit=LIMIT-1 olarak ac.
delete from public.rpc_rate_limits
 where user_id = '99999999-9999-9999-9999-999999999931'
   and rpc_name = 'probe_race';

insert into public.rpc_rate_limits
  (user_id, rpc_name, window_start, hit_count)
values
  ('99999999-9999-9999-9999-999999999931',
   'probe_race',
   to_timestamp(floor(extract(epoch from clock_timestamp()) / 3600) * 3600),
   4);

commit;

\echo SETUP_OK

\endif


-- ------------------------------------------------------------
-- MODE=work : TEK statement'lik yaris (autocommit). Sonuc hem
-- ekrana hem _qa4_probe_results'a yazilir (commit'li kanit).
-- ------------------------------------------------------------

\if :m_work

\if :{?TAG}
\else
\warn TAG tanimli degil: work modunda -v TAG=a|b zorunludur
\q
\endif

select :'TAG' = 'a' as tag_a,
       :'TAG' = 'b' as tag_b
\gset

select set_config('request.jwt.claims',
  '{"sub":"99999999-9999-9999-9999-999999999931","role":"authenticated"}',
  false) as claims_set;

-- psql degiskeni dollar-quote icine interpolasyon yapamaz;
-- oturum degiskeni uzerinden tasi.
select set_config('my.qa4_tag', :'TAG', false) as tag_set;

do $blk$
declare
  v_tag text := current_setting('my.qa4_tag');
begin
  perform public._faz4_consume_rate_limit('probe_race', 5, 3600);

  insert into public._qa4_probe_results (tag, result)
  values (v_tag, 'OK')
  on conflict (tag) do update set result = 'OK', at = clock_timestamp();

  raise notice 'RESULT=OK';
exception
  when others then
    if sqlstate = 'P0001'
       and upper(sqlerrm) like '%COK FAZLA ISTEK%' then
      insert into public._qa4_probe_results (tag, result)
      values (v_tag, 'LIMITED')
      on conflict (tag) do update
        set result = 'LIMITED', at = clock_timestamp();
      raise notice 'RESULT=LIMITED';
    else
      raise;
    end if;
end;
$blk$;

select set_config('request.jwt.claims', '', false) as claims_cleared;

\endif


-- ------------------------------------------------------------
-- MODE=verify : deterministik sonuc kontrolu
--   - tam bir OK + bir LIMITED
--   - PRIME penceresinde hit_count = 5 (tavan)
--   - baska pencere/rpc satiri yok
-- Herhangi ihlal -> P0001 VERIFY_FAIL -> exit code != 0.
-- ------------------------------------------------------------

\if :m_verify

select r.tag,
       r.result,
       case when r.at > clock_timestamp() - interval '10 minutes'
            then 'PASS' else 'FAIL' end as tazelik
  from public._qa4_probe_results r
 order by r.tag;

do $blk$
declare
  v_ok      integer;
  v_limited integer;
  v_hit     integer;
  v_extra   integer;
begin
  select count(*) filter (where result = 'OK'),
         count(*) filter (where result = 'LIMITED')
    into v_ok, v_limited
    from public._qa4_probe_results;

  if v_ok <> 1 or v_limited <> 1 then
    raise exception
      'VERIFY_FAIL: beklenen tam bir OK + bir LIMITED; ok=% limited=%',
      v_ok, v_limited
      using errcode = 'P0001';
  end if;

  select rl.hit_count into v_hit
    from public.rpc_rate_limits rl
   where rl.user_id = '99999999-9999-9999-9999-999999999931'
     and rl.rpc_name = 'probe_race';

  if v_hit is distinct from 5 then
    raise exception
      'VERIFY_FAIL: hit_count beklenen 5 degil (%)', coalesce(v_hit, -1)
      using errcode = 'P0001';
  end if;

  -- Yarisa ek pencere/kayit sizmamis olmali.
  select count(*) into v_extra
    from public.rpc_rate_limits rl
   where rl.user_id = '99999999-9999-9999-9999-999999999931'
     and rl.rpc_name = 'probe_race'
     and rl.window_start <>
         to_timestamp(floor(extract(epoch from clock_timestamp()) / 3600) * 3600);

  if v_extra <> 0 then
    raise exception
      'VERIFY_FAIL: beklenmeyen % adet ek pencere satiri', v_extra
      using errcode = 'P0001';
  end if;
end;
$blk$;

\echo VERIFY_PASS

\endif


-- ------------------------------------------------------------
-- MODE=cleanup : tum probe artefaktlarini siler (committed)
-- ------------------------------------------------------------

\if :m_cleanup

begin;

drop table if exists public._qa4_probe_results;

delete from public.rpc_rate_limits
 where user_id = '99999999-9999-9999-9999-999999999931';

delete from public.student_profiles
 where nickname = 'QA4-NICK-RACE';

delete from auth.users where email = 'qa4-race@test.local';

commit;

\echo CLEANUP_OK

\endif
