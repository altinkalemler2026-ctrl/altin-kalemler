# Faz 24 — Yerel Ana DB Salt-Okunur Dogrulama

- Tarih: 2026-09-24
- Kapsam: Migration `126_faz24_admin_candidate_review_low_confidence.sql` yerel ana DB'de
  (`supabase_db_yarisma-programi`, PostgreSQL 17.6) uygulanmis mi ve veri butunlugu korunmus mu?
- Yontem: Yalnizca salt-okunur sorgular (`docker exec ... psql -f`), DML yok, migration/intake/
  publish/approval/backfill yok. Kanit dosyasi: `.opencode/tmp/faz24_verify_local.sql`.
- Kimlik bagi: `service_role` icin `request.jwt.claims` (cogul) + `request.jwt.claim.sub` ve
  `request.jwt.claim.role` (tekil) GUC'lari **session-level** (`is_local=false`) set edilir.
  (Not: `is_local=true` tek tek autocommit ifadelerde kaybolur ve RPC `42501` verir; disposable
  QA'da kanitlanan `_qa_f24_as_role` deseni bu uclusun ayni oturumda set edilmesidir.)

## 1. Migration 126 uygulanmis mi? — EVET

```sql
select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='get_candidate_question_batch_detail';
-- 1
```

`get_candidate_question_batch_detail` govdesinde `low_confidence` alani mevcut. Migration 126
**yalniz DDL**'dir: iki `CREATE OR REPLACE FUNCTION` + `REVOKE`/`GRANT`. Migration uygulanirken
`INSERT/UPDATE/DELETE` calismaz (DML yalniz fonksiyon govdelerinin icindedir), bu nedenle satir
sayilarinin degismemesi yapisal olarak zorunludur.

## 2. Sayilar — BEKLENEN BASELINE, DEGISMEDI

| olcum | deger |
|---|---|
| candidate_question_batches | 2 |
| questions | 8 |
| ai_question_staging (validating) | 33 |
| review_queue | 1 |

## 3. "33 vs 32" farkinin aciklamasi — Fizik 32 + Matematik 1

Fark, migration 126'dan DEGIL, ana DB'deki iki ayri batch'ten gelir:

| batch_id | batch_key (kisaltilmis) | origin | status | total_items | valid_items |
|---|---|---|---|---|---|
| `9310097d-168c-498e-b8cc-4531d46c0825` | `notebook:md:886b...` | curriculum_original | ingested | 32 | 32 |
| `7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3` | `opencode-big-pickle:783f...` | curriculum_original | ingested | 1 | 1 |

Validating staging kayitlarinin batch bagi:

| candidate_batch_id | staging_sayisi |
|---|---|
| `9310097d-...` (Fizik) | 32 |
| `7ea1ff55-...` (Matematik) | 1 |

- `9310097d-...` = Fizik batch (32 aday; `subject_name=Fizik`).
- `7ea1ff55-...` = Matematik batch'inin 1 kaydi; `ai_question_staging`
  id `03682255-734d-407f-9b26-3168653fe21e`, `staging_source=manual_candidate`,
  `created_at=2026-09-16` (bu fazdan ONCE, baseline). Ayni kayit Fizik detay RPC'sinde gorunmez
  cunku farkli batch'e baglidir.

Sonuc: 33 = Fizik 32 + Matematik 1. Onceki "32" beklentisi yalniz Fizik batch'ini sayiyordu;
ana DB baseline'i 33'tur ve 126 sonrasi degismemistir.

## 4. Fizik batch detay RPC (service_role) — DOGRU ALANLAR

`get_candidate_question_batch_detail('9310097d-168c-498e-b8cc-4531d46c0825')`:

- `subject_name = Fizik`
- `outcome_code = FIZ.11.1.10` (dolu)
- `low_confidence = NULL` (kayit yok → geriye donuk backfill YOK)
- `solution` = `object` (JSON nesnesi mevcut)
- `candidate_sayisi = 32`, `solution_object_sayisi = 32`, `outcome_code_dolu_sayisi = 32`
- `batch.schema_version = 1.0`, `validation_summary.preflight.schema_version = 1.1`

## 5. low_confidence backfill yok

```sql
select count(*) from public.ai_question_staging where metadata ? 'low_confidence';
-- 0
```

## 6. ACL / fail-closed

- `has_function_privilege('anon', 'public.get_candidate_question_batch_detail(uuid)', 'EXECUTE')` = **f**
- Claimsiz (GUC temiz) cagri → `ERROR: Kimlik dogrulamasi gerekli.` (42501), fail-closed. **OK**

## Karar

Tum maddeler yesil. Migration 126 yerel ana DB'de uygulanmis, DDL-only oldugu icin satir sayilari
degismemis, Fizik batch detayi beklenen alanlari donuyor, low_confidence backfill yok ve erisim
fail-closed.

**SAFE_FOR_ADMIN_UI_IMPLEMENTATION: YES**
