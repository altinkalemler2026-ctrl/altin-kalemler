-- ============================================================
-- 080_faz5_competition_hardening.sql
-- Altın Kalemler - Faz 5a
--
-- 019-024 yarisma katmani hardening denetimi (Faz 2-4 standardi):
--
-- 1) SEARCH_PATH SIFIRLAMA
--    021/022/023 SECURITY DEFINER fonksiyonlari ve iki trigger
--    fonksiyonu (019/022) 'SET search_path = public' ile yazilmisti.
--    Statik denetim: tum ilgili govde tablo referanslari tam
--    nitelikli (public.*) ve ozel fonksiyon cagrilari nitelemeli;
--   yerlesik fonksiyonlar (now/jsonb_*/coalesce...) pg_catalog
--    implicit aramasindan etkilenmez. Bu nedenle search_path=''
--    GUVENLI sekilde uygulanir (065+ standardi).
--
-- 2) DRIFT GUARD
--    - Hardening sonrasi hicbir hedef fonksiyonda
--      'search_path = public' kalmamalidir (dogrulama bolumu).
--    - EXECUTE matrisine DOKUNULMAZ: ogrenci yuzlu RPC izinleri
--      021/023 + 025 + 071 durumunda kalir; burada yalniz raporlanir.
--
-- Kapsam beyaz listesi (021-023 + trigger fonksiyonlari):
--   asagidaki dizi. Baska migration'lardaki 'search_path = public'
--   kullanimlari bilinçli olarak DIŞARIDA birakildi (farklı modul,
--   ayri denetim).
-- ============================================================

begin;

DO $hardening$
declare
  v_targets text[] := array[
    -- 021_secure_competition_scoring
    'is_competition_participant',
    'get_internal_correct_answer',
    'resolve_competition_time_band',
    'resolve_competition_points',
    'recalculate_competition_player_score',
    'finalize_competition_if_ready',
    'submit_competition_answer',
    'get_competition_question_payload',
    -- 023_competition_question_flow
    'resolve_competition_question_time_limit',
    'release_competition_question',
    'set_competition_player_ready',
    'create_missing_competition_timeouts',
    'advance_competition_progress',
    'sync_competition_state',
    'after_competition_answer_progress',
    'get_current_competition_question',
    -- trigger fonksiyonlari (019/022)
    'validate_competition_question_limit',
    'snapshot_competition_answer_band_name'
  ];
  r record;
  v_altered integer := 0;
begin
  for r in
    select p.oid,
           p.proname,
           pg_get_function_identity_arguments(p.oid) as args
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prosecdef = true
       and p.proconfig is not null
       and 'search_path=public' = any (p.proconfig)
       and lower(p.proname) = any (v_targets)
     order by p.proname
  loop
    execute format(
      'alter function public.%I(%s) set search_path = ''''',
      r.proname,
      r.args
    );
    v_altered := v_altered + 1;
  end loop;

  raise notice 'FAZ5 hardening: % fonksiyon search_path='' '' yapildi.', v_altered;
end;
$hardening$;


commit;


-- ============================================================
-- DOGRULAMA
-- ============================================================

-- 1) Beyaz listede 'search_path = public' kalmamali.
select
  p.proname,
  p.proconfig
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef = true
  and p.proconfig is not null
  and 'search_path=public' = any (p.proconfig)
order by p.proname;

-- 2) Ogrenci yuzlu RPC EXECUTE matrisi raporu (degisiklik yok, gozlem).
select
  p.proname as function_name,
  pg_get_userbyid(a.grantee) as grantee,
  a.privilege_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
where n.nspname = 'public'
  and p.proname in (
    'submit_competition_answer',
    'get_competition_question_payload',
    'get_current_competition_question',
    'sync_competition_state',
    'get_competition_scoreboard'
  )
order by p.proname, a.grantee;
