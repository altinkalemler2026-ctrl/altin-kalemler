-- ============================================================================
-- qa_sec_privilege_drift_audit.sql — AK-SEC-ANSWER-02 §5 DRIFT DENETİMİ
-- ============================================================================
-- AMAÇ: Migration GEÇMİŞİNDEN DIŞ bir izin değişimi (021/025/080 sonrası
--   Studio/ad-hoc GRANT drifti, 2026-10 cloud-recovery taban geri sarması)
--   tekrarlanırsa TESPİT etmek. Salt-okunur; hiçbir yazma yapmaz, hiçbir
--   DB'ye bağlanti yan etkisi yoktur — canlıda koşabilir.
--
-- KOŞUM: docker exec supabase_db_yarisma-programi psql -U postgres \
--          -d postgres -f scripts/qa_sec_privilege_drift_audit.sql
--   (veya psql -h ... ; hedef ne olursa)
--
-- ÇIKTI: Her satır [PASS]/[DRIFT]/[INFO]. CRITICAL dilimde DRIFT varsa
--   sonda EXCEPTION (exit≠0) → CI/cron bu betiği non-zero exit ile yakalar.
--   INFO satırlar (şema-geneli 108 sertleştirmesi) ayrı karar maddesidir
--   (AK-SEC-HARDEN önerisi; kritik exit'i tetiklemez).
--
-- BEKLENEN KRİTİK MATRİS (sözleşme kaynakları):
--   M1 get_internal_correct_answer EXECUTE = {postgres, service_role} (155)
--   M2 questions anon: hiçbir tablo hakkı yok (156)
--   M3 questions authenticated: yalnız SELECT (I/U/D/T/R/Tr yok) (156)
--   M4 questions kolon yetki kaydı (anon/auth/public) = 0 (156)
--   M5 questions okuma politikası = 1 ve yalnız yönetici politikası (156)
--   M6 lig RPC-only: leaderboard_entries / student_league_memberships /
--      student_league_history — anon+authenticated SELECT yok (108)
--   M7 service_role.questions SELECT durur (iç akış) (156 assert'ı ile aynı)
--
-- DIGEST: Kritik nesnelerin yetki+politika parmak izi (sha256). Kanonik
--   değer docs/reports içinde KAYDEDİLİR; sonraki koşumlarda digest
--   değiştiyse migration dışı izin hareketi olmuştur (satır satır DRIFT
--   olmasa bile — ör. yeni nesne eklenmesi).
-- ============================================================================

\set ON_ERROR_STOP on

do $audit$
declare
  v_drift int := 0;
  v_oid oid;
  v_set text;
  v_cnt int;
  v_pol text;
  r record;

  function_log text := '';
  league_rec int;

  v_digest text;
begin
  create temp table _drift (satir text);

  -- ---- M1: SEC-1 fonksiyon ACL ------------------------------------------
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='get_internal_correct_answer';
  if v_oid is null then
    insert into _drift values ('[DRIFT] M1 get_internal_correct_answer BULUNAMADI');
    v_drift := v_drift + 1;
  else
    select string_agg(pg_get_userbyid(grantee), ',' order by grantee)
      into v_set
      from aclexplode((select proacl from pg_proc where oid = v_oid))
     where privilege_type = 'EXECUTE';
    if v_set = 'postgres,service_role' then
      insert into _drift values ('[PASS ] M1 get_internal_correct_answer EXECUTE = {postgres,service_role}');
    else
      insert into _drift values ('[DRIFT] M1 get_internal_correct_answer EXECUTE = {' || coalesce(v_set,'<NULL>') || '} (beklenen {postgres,service_role})');
      v_drift := v_drift + 1;
    end if;
  end if;

  -- ---- M2: questions anon tablo hakları ----------------------------------
  select count(*) into v_cnt from aclexplode(
           (select relacl from pg_class where oid='public.questions'::regclass))
   where pg_get_userbyid(grantee) = 'anon';
  if v_cnt = 0 then
    insert into _drift values ('[PASS ] M2 questions: anon hak kaydi yok');
  else
    insert into _drift values ('[DRIFT] M2 questions anon hak kaydi=' || v_cnt || ' (beklenen 0)');
    v_drift := v_drift + 1;
  end if;

  -- ---- M3: questions authenticated en az ayrıcalık ------------------------
  if has_table_privilege('authenticated','public.questions','SELECT')
     and not has_table_privilege('authenticated','public.questions','INSERT')
     and not has_table_privilege('authenticated','public.questions','UPDATE')
     and not has_table_privilege('authenticated','public.questions','DELETE')
     and not has_table_privilege('authenticated','public.questions','TRUNCATE')
     and not has_table_privilege('authenticated','public.questions','REFERENCES')
     and not has_table_privilege('authenticated','public.questions','TRIGGER')
     and not has_table_privilege('authenticated','public.questions','MAINTAIN') then
    insert into _drift values ('[PASS ] M3 questions: authenticated yalniz SELECT');
  else
    insert into _drift values ('[DRIFT] M3 questions authenticated haklasi asiri (SELECT disinda hak var)');
    v_drift := v_drift + 1;
  end if;

  -- ---- M4: kolon yetki kayıtları ------------------------------------------
  -- Beklenen (156 sonrasu): anon/public hic kayd yok; authenticated yalniz
  -- SELECT kaydi (tablo SELECT'iyle ayni etkin hak, RLS ile kilitli).
  select count(*) into v_cnt
    from information_schema.column_privileges
   where table_schema='public' and table_name='questions'
     and (grantee in ('anon','public')
          or (grantee = 'authenticated' and privilege_type <> 'SELECT'));
  if v_cnt = 0 then
    insert into _drift values ('[PASS ] M4 questions: anon/public kolon kaydi yok, authenticated kolon yazma kaydi yok');
  else
    insert into _drift values ('[DRIFT] M4 questions yazma/anon kolon ayricalik kaydi=' || v_cnt || ' (beklenen 0)');
    v_drift := v_drift + 1;
  end if;

  -- ---- M5: RLS okuma politikası -------------------------------------------
  select count(*) into v_cnt from pg_policy
   where polrelid='public.questions'::regclass and polcmd in ('r','*');
  select polname into v_pol from pg_policy
   where polrelid='public.questions'::regclass and polcmd in ('r','*') limit 1;
  if v_cnt = 1 and v_pol = 'question admins read all questions' then
    insert into _drift values ('[PASS ] M5 questions okuma politikasi = yalniz yonetici');
  else
    insert into _drift values ('[DRIFT] M5 questions okuma politikasi sayi=' || v_cnt
      || ' kalan=' || coalesce(v_pol,'<YOK>') || ' (beklenen 1 x yonetici)');
    v_drift := v_drift + 1;
  end if;

  -- ---- M6: lig tabloları RPC-only (108 sözleşmesi) -------------------------
  for r in select t from unnest(array[
      'public.leaderboard_entries','public.student_league_memberships',
      'public.student_league_history']) t loop
    if has_table_privilege('authenticated', r.t, 'SELECT')
       or has_table_privilege('anon', r.t, 'SELECT') then
      insert into _drift values ('[DRIFT] M6 ' || r.t || ': anon/auth SELECT var (108 RPC-only bozuldu)');
      v_drift := v_drift + 1;
    end if;
  end loop;
  select count(*) into league_rec from _drift where satir like '[DRIFT] M6%';
  if league_rec = 0 then
    insert into _drift values ('[PASS ] M6 lig tablolari RPC-only (anon/auth SELECT yok)');
  end if;

  -- ---- M7: service_role iç akış hakkı --------------------------------------
  if has_table_privilege('service_role','public.questions','SELECT') then
    insert into _drift values ('[PASS ] M7 service_role.questions SELECT duruyor');
  else
    insert into _drift values ('[DRIFT] M7 service_role.questions SELECT KAYBEDILDI (ic akis kirik)');
    v_drift := v_drift + 1;
  end if;

  -- ---- INFO: şema-geneli 108 sertleştirme envanteri ------------------------
  select count(*) into v_cnt
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relkind in ('r','p')
     and (has_table_privilege('anon',c.oid,'TRUNCATE')
       or has_table_privilege('anon',c.oid,'REFERENCES')
       or has_table_privilege('anon',c.oid,'TRIGGER')
       or has_table_privilege('authenticated',c.oid,'TRUNCATE'));
  insert into _drift values ('[INFO ] 108-geneli: TRUNCATE/REF/TRIGGER kirilmis public tablo sayisi='
    || v_cnt || ' (beklenen 0; AK-SEC-HARDEN ayriz karar maddesi)');

  select count(*) into v_cnt
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relkind in ('r','p')
     and (has_table_privilege('anon',c.oid,'INSERT')
       or has_table_privilege('anon',c.oid,'UPDATE')
       or has_table_privilege('anon',c.oid,'DELETE'));
  insert into _drift values ('[INFO ] 108-geneli: anon yazma hakki olan public tablo sayisi='
    || v_cnt || ' (RLS yazar; yine de hijyen ihlali)');

  -- ---- DIGEST: kritik nesnelerin izin+politika parmak izi ------------------
  select encode(digest(coalesce(string_agg(line, E'\n' order by line),'YOK'), 'sha256'), 'hex')
    into v_digest
    from (
      select 'fn:' || p.proname || '=' ||
             coalesce((select string_agg(pg_get_userbyid(grantee) || ':' || privilege_type, ',' order by grantee)
                        from aclexplode(p.proacl) a
                       where privilege_type = 'EXECUTE'),'-') as line
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public'
         and p.proname in ('get_internal_correct_answer','admin_question_edit',
                           'prepare_competition_pack','join_matchmaking_queue')
      union all
      select 'tbl:questions=' || coalesce((
               select string_agg(pg_get_userbyid(grantee) || ':' || privilege_type, ',' order by grantee)
                 from aclexplode((select relacl from pg_class where oid='public.questions'::regclass)) a
             ),'-')
      union all
      select 'rls:questions=' || coalesce(string_agg(polname || '/' || polcmd::text, ',' order by polname), '-')
        from pg_policy where polrelid='public.questions'::regclass
      union all
      select 'colg:questions=' || coalesce((
               select string_agg(grantee || ':' || privilege_type || ':' || column_name, ',' order by grantee, privilege_type, column_name)
                 from information_schema.column_privileges
                where table_schema='public' and table_name='questions'
                  and grantee in ('anon','authenticated','public')
             ),'-')
    ) q;
  insert into _drift values ('[INFO ] DIGEST (kritik izin+politika parmak izi)=' || v_digest);

  -- ---- YAZDIR ----------------------------------------------------------------
  for r in select satir from _drift order by satir loop
    raise notice '%', r.satir;
  end loop;

  if v_drift > 0 then
    raise exception 'PRIVILEGE DRIFT: % kritik sapma (yukarida [DRIFT] satirlari)',
      v_drift using errcode='P0998';
  end if;
  raise notice 'PRIVILEGE AUDIT TEMIZ: kritik matris beklenen durumda';
end;
$audit$;
