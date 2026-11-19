#!/bin/bash
# AK-DB-CONSISTENCY-02 — IZOLE TEMIZ KURULUM RUNNER (sifir manuel ENV_REPAIR).
#
# supabase db reset semantigini taklit eder: zincir dosyalari sirayla
# uygulanir, her basarili dosyadan sonra history kaydi eklenir.
# Fark (01'deki manuel ENV_REPAIR'den farki): iki BELGELENMIS, versionlu,
# idempotent on-kosul adimi zincire KANCALI asistanir:
#   155 sonrasi -> hook_after155_service_role_baseline.sql
#   156 sonrasi -> hook_after156_write_matrix_baseline.sql
#   165 sonrasi -> hook_after165_service_role_baseline.sql (AK-GIT-CHECKPOINT-08)
# Kalip kaynagi: drafts/ak-db-consistency-01/cc_build.sh (Ayni C1-C3 adimlari,
# canli supabase postgres container ici; benzersiz DB adi disposable.)
#
# Kullanim (supabase_db_yarisma-programi container icinde):
#   QA_DB=qa_akdbc02_b MIGRATIONS=<dir> HOOKS=<dir> bash clean_install.sh [beklenen_dosya=160]
set -uo pipefail
export PGHOST=/var/run/postgresql
QA=${QA_DB:?QA_DB verilmeli (benzersiz disposable ad)}
M=${MIGRATIONS:?MIGRATIONS verilmeli}
H=${HOOKS:?HOOKS verilmeli}
D=${LOGDIR:-/tmp/${QA}_logs}
EXPECT_FILES=${1:-160}
ADMIN="psql -U supabase_admin"

echo "== C0) hazirlik =="
[ -d "$M" ] || { echo "MIGRATIONS_DIZIN_YOK"; exit 1; }
NFILES=$(ls "$M"/*.sql | wc -l)
echo "dosya_sayisi=$NFILES beklenen=$EXPECT_FILES"
[ "$NFILES" = "$EXPECT_FILES" ] || { echo "DOSYA_SAYISI_UYUSMUYOR"; exit 1; }
mkdir -p "$D"

echo "== C1) taze DB (drop-if-exists + create) =="
psql -d postgres -c "DROP DATABASE IF EXISTS $QA WITH (FORCE);" || exit 1
psql -d postgres -c "CREATE DATABASE $QA;" || exit 1
$ADMIN -d $QA -v ON_ERROR_STOP=1 -c "CREATE SCHEMA IF NOT EXISTS extensions;" || exit 1
$ADMIN -d $QA -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS btree_gist;" || exit 1
$ADMIN -d $QA -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA extensions;" || exit 1
$ADMIN -d $QA -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\" SCHEMA extensions;" || exit 1
$ADMIN -d $QA -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements SCHEMA extensions;" || exit 1

echo "== C2) supabase_migrations semasi (canli kalibi) =="
PGUSER=supabase_admin pg_dump -d postgres --schema-only -n supabase_migrations -f $D/schemamig_$QA.sql || exit 1
$ADMIN -d $QA -v ON_ERROR_STOP=1 -f $D/schemamig_$QA.sql > $D/schemamig_restore.log 2>&1 || { tail -5 $D/schemamig_restore.log; exit 1; }

echo "== C3) auth semasi round-1 (canli schema-only dump, sahibiyle) =="
PGUSER=supabase_admin pg_dump -d postgres --schema-only -n auth -f $D/auth_$QA.sql || exit 1
$ADMIN -d $QA -v ON_ERROR_STOP=0 -f $D/auth_$QA.sql > $D/auth1_$QA.log 2>&1
echo "auth1_hata=$(grep -c ERROR $D/auth1_$QA.log || true)"

echo "== C4) zincir dongusu (001..164) + kancli on-kosullar =="
APPLIED=0
for f in $(ls "$M"/*.sql | sort); do
  base=$(basename "$f" .sql)
  ver=${base%%_*}
  if ! psql -d $QA -v ON_ERROR_STOP=1 -f "$f" > "$D/log_$base.txt" 2>&1; then
    echo "CHAIN_FAIL: $base"
    tail -8 "$D/log_$base.txt"
    exit 1
  fi
  grep -E "FINAL_[0-9]+ OK" "$D/log_$base.txt" | head -2
  psql -d $QA -v ON_ERROR_STOP=1 -Atc "insert into supabase_migrations.schema_migrations (version, name, statements) select '$ver','$base',NULL where not exists (select 1 from supabase_migrations.schema_migrations where version='$ver');" >> "$D/history_inserts.log" 2>"$D/histerr_$base.txt" || { echo "HIST_FAIL: $base"; cat "$D/histerr_$base.txt"; exit 1; }
  if [ "$ver" = "155" ]; then
    echo "== ON-KOSUL #1 (kancli, 155->156 arasi): hook_after155_service_role_baseline.sql =="
    psql -d $QA -v ON_ERROR_STOP=1 -f "$H/hook_after155_service_role_baseline.sql" > "$D/hook_pre156.txt" 2>&1 || { echo "HOOK_PRE156_FAIL"; tail -5 "$D/hook_pre156.txt"; exit 1; }
    grep -E "PRE156_BASELINE_OK" "$D/hook_pre156.txt"
  fi
  if [ "$ver" = "156" ]; then
    echo "== ON-KOSUL #2 (kancli, 156->157 arasi): hook_after156_write_matrix_baseline.sql =="
    psql -d $QA -v ON_ERROR_STOP=1 -f "$H/hook_after156_write_matrix_baseline.sql" > "$D/hook_pre157.txt" 2>&1 || { echo "HOOK_PRE157_FAIL"; tail -5 "$D/hook_pre157.txt"; exit 1; }
    grep -E "PRE157_BASELINE_OK|PRE157_BASELINE_OK policy" "$D/hook_pre157.txt"
  fi
  if [ "$ver" = "165" ]; then
    echo "== ON-KOSUL #3 (kancli, 165->166 arasi): hook_after165_service_role_baseline.sql =="
    psql -d $QA -v ON_ERROR_STOP=1 -f "$H/hook_after165_service_role_baseline.sql" > "$D/hook_pre166.txt" 2>&1 || { echo "HOOK_PRE166_FAIL"; tail -5 "$D/hook_pre166.txt"; exit 1; }
    grep -E "PRE166_BASELINE_OK" "$D/hook_pre166.txt"
  fi
  APPLIED=$((APPLIED+1))
done
echo "uygulanan=$APPLIED"

echo "== C5) zincir sonrasi auth tetik kontrolu (083) =="
psql -d $QA -Atc "select 'auth_trigger='||(count(*)::text) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='auth' and c.relname='users' and not t.tgisinternal"

echo "== C6) OZET dogrulamalar =="
psql -d $QA -Atc "
select 'hist='||(select count(*) from supabase_migrations.schema_migrations)||
' max='||(select max(version::int) from supabase_migrations.schema_migrations)||
' dup='||(select count(*) from (select version from supabase_migrations.schema_migrations group by version having count(*)>1) d)||
' h162='||(select count(*) from supabase_migrations.schema_migrations where version='162')||
' h163='||(select count(*) from supabase_migrations.schema_migrations where version='163')||
' h164='||(select count(*) from supabase_migrations.schema_migrations where version='164')||
' quota_tables='||(select count(*) from pg_class where relname in ('student_week_quota','student_week_question_ledger','student_week_quota_events'))||
' q163_fns='||(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like '\_q163%' escape '\' or p.proname='weekly_quota_status'))||
' md5_list_vaults='||(select md5(prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='uretim_planlayici_list_vaults')||
' md5_list_stock='||(select md5(prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='uretim_planlayici_list_vault_stock')||
' period='||(select academic_year||'-W'||week from public.resolve_current_academic_period())||
' wqs_exec_auth='||has_function_privilege('authenticated','public.weekly_quota_status()','EXECUTE')||
' wqs_exec_anon='||has_function_privilege('anon','public.weekly_quota_status()','EXECUTE')||
' rls_swq='||(select relrowsecurity from pg_class where relname='student_week_quota')||
' pol_swq='||(select count(*) from pg_policies where tablename='student_week_quota')"
echo CLEAN_INSTALL_DONE
