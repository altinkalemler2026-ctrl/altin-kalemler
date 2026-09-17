# Faz 14A Nihai Rapor — Aday Soru Alım ve Denetim Köprüsü

**Tarih:** 2026-09-16
**Model:** big-pickle (opencode)
**Sorumlu:** selami
**Faz:** 14A (kullanıcı onaylı kapsam): TS kod katmanı + yeni migration + disposable local DB QA

---

## 1. Sonuç Özeti

| Metrik | Değer |
|---|---|
| **Durum** | ✅ BAŞARILI (kod + migration + local QA tamam) |
| TS sözleşmesi | `src/lib/content/candidate-batch-types.ts` (schema v1.0) |
| TS validatör | `src/lib/content/candidate-batch-validator.ts` (deterministik, Türkçe hata kodları) |
| C-1 orchestrator | `src/lib/content/candidate-batch-orchestrator.ts` (DI + GateProvider) |
| Unit test | `candidate-batch-orchestrator.test.ts` — **14/14 PASS** (7 senaryo) |
| Migration | `supabase/migrations/117_faz14a_candidate_question_batch.sql` |
| `npx tsc --noEmit` | ✅ 0 hata |
| `npm run test` (full) | ✅ 60 dosya / **827 test** PASS |
| `npx eslint` (yeni dosyalar) | ✅ 0 hata |
| `npm run lint` (full) | ✅ yeni dosyalarda 0 hata (1 mevcut error `probe-sharp.cjs`, 8 mevcut uyarı — bizim değil) |
| DB QA (disposable) | ✅ 2× uygulama + rollback + 9 fixture senaryo PASS |
| Docker envanter | ✅ Öncesi/sonrası aynı (yalnız kendi QA konteyneri eklenip kaldırıldı) |
| Commit / push | **YAPILMADI** (kullanıcı onayı bekleniyor) |

---

## 2. Fare Hikayesi (Kapsam)

Bu faz, dış üreticilerden / farklı AI modellerinden gelen soruların
**doğrudan yayınlanmadan**, mevcut bağımsız denetim hatlarına (AI soru pipeline'ı,
033–039 denetim RPC'leri) aday olarak sokulmasını sağlayan **C-1 köprüsünü** kurar.

```
Dış üretici / farklı AI modeli
        │  (JSON, schema_version 1.0, sözleşme + validatör + istek süzgeci)
        ▼
register_candidate_question_batch(jsonb)   ← migration 117 (SECURITY DEFINER + admin gate)
        │
        ├── origin ≠ curriculum_original  → REDDEDİLİR
        ├── producer.id yok               → REDDEDİLİR
        ├── questions boş                 → REDDEDİLİR
        ├── candidate soru geçersiz       → candidate invalid (staging'e GİRMEZ)
        └── candidate geçerli             → ai_question_staging (manual_candidate, validating)
                                  │         + ai_validation_results (deterministic structure/answer)
                                  │         + metadata (own/bench/source/hash, auto-pub=false)
                                  v
                     solution.steps yok / grade yok / subject yok?
                        ├── evet → review_queue (intake_incomplete) + needs_review
                        └── hayır → metadata.final_readiness_status='pending'
                                  │
                                  ▼
              Mevcut denetim kapıları (033-039 gate'leri)
              CandidateBatchOrchestrator.auditBatch()
              ├── tüm kapılar pass  → kavramsal ready_for_human_review
              ├── herhangi fail     → rejected
              └── pending/skipped   → needs_review (fail-closed)
```

**Ürün sözleşmesi zorlukları — bu fazda DOKUNULMADI:**
- Otomatik yayın YOK (`automatic_publication_allowed` her zaman `false`)
- Ekonomi / sahte UI yok
- ZIP bu fazda uygulanmaz (yalnız doküman: `forbidden_fields` sözleşmede, uygulama sonraki faza)
- Öğrenci deneyimine / admin'e kadar hiçbir şey otomatik yayınlanmaz

---

## 3. Veri Sözleşmesi v1.0 (candidate-batch-types.ts)

### 3.1 Batch kökü

```ts
interface CandidateQuestionBatchV1 {
  schema_version: "1.0"
  origin: "curriculum_original"          // tek izinli değer — PDF türevi / yeniden yazım YASAK
  producer: { id: string; model?: string }
  questions: CandidateQuestionV1[]       // boş olamaz
}
```

### 3.2 Soru

```ts
interface CandidateQuestionV1 {
  client_question_id?: string
  grade_level: 1..12
  subject_id: string                     // UUID (birincil anahtardan)
  outcome_code: string                   // ^[A-Za-z0-9._-]+$
  question_text: string                  // ≥10 karakter
  options: { A;B;C;D zorunlu, E opsiyonel }
  correct_answer: "A"|"B"|"C"|"D"|"E"
  difficulty?: "easy"|"medium"|"hard"
  cognitive_type?: "learning"|"comprehension"|"application"
  estimated_solve_time_seconds?: positive int
  solution?: WrittenSolution             // mevcut written-solution yapısı
}
```

### 3.3 Yasaklı alanlar (kaynak türetme / PDF / görsel)

`source_question_text`, `pdf_reference`, `crop_reference`, `image_data`,
`image_url`, `source_page_number`, `source_test_code`, `source_question_code`,
`derived_from_question_id`, `derived_from_source_id`

### 3.4 Sonuç eşlemesi (kavramsal)

| - | TS orchestrator | DB karşılığı |
|---|---|---|
| Tüm gate'ler pass | `ready_for_human_review` | 033–039 sonrası bayrak; 117'de literal yok |
| Gate fail | `rejected` | — |
| Gate pending/skipped | `needs_review` (fail-closed) | review_queue + `needs_review` |
| Intake deterministik şüphe | — | review_queue `candidate_batch_intake_incomplete` |

---

## 4. Migration 117 — Yapı

### 4.1 Yeni tablolar (public)

| Tablo | Sütunlar / Notlar |
|---|---|
| `candidate_question_batches` | `id` uuid PK, `batch_key` UNIQUE (producer_id ':' sha256(payload) → **idempotent**), `schema_version` CHECK('1.0'), `origin` CHECK('curriculum_original'), `producer_id`, `producer_model`, `status` CHECK(received/validating/validated/partially_valid/rejected/ingested/failed), `valid_items/invalid_items/inserted_items/duplicate_items`, `validation_summary` jsonb, `error_data` jsonb, `raw_payload` jsonb NOT NULL, `metadata`, `created_at/updated_at` + trigger |
| `candidate_batch_candidate_results` | `batch_id` FK, `candidate_index`, `client_question_id`, `validation_status` CHECK(pending/valid/invalid/duplicate/inserted/failed), `validation_errors/validation_warnings` jsonb, `staging_question_id` FK→ai_question_staging, `updated_at` + trigger, UNIQUE(batch_id, candidate_index) |

İndeksler: batches(status, created_at DESC), batches(producer_id, created_at DESC), results(batch_id, candidate_index), results(staging_question_id).

### 4.2 Fonksiyonlar

| Fonksiyon | Mod | Not |
|---|---|---|
| `private.validate_candidate_question_batch_candidate(jsonb)` | IMMUTABLE SECURITY DEFINER, search_path='' | Soru düzeyinde deterministik doğrulama (alanlar, seçenekler, outcome_code formatı, cevap var olan seçeneğe işaret etmeli — akademik doğruluk DEĞİL) |
| `private.register_candidate_question_batch(jsonb)` | SECURITY DEFINER, search_path='' | İş akışı: `auth.role()='service_role'` VEYA `ai.manage`/`questions.approve` izni ister; idempotent batch_key; staging insert + validations + review_queue rotası |
| `public.register_candidate_question_batch(jsonb)` | SECURITY INVOKER | İnce dış kapsül: yalnız `private.register_...` çağırır |
| `public.get_candidate_question_batch_contract()` | SECURITY INVOKER | Sözleşmeyi JSON döner (origin allowlist, forbidden_fields, kurallar) — TS sözleşmesiyle birebir |

### 4.3 İzinler ve RLS

- `private.*` → PUBLIC/anon/authenticated 'den REVOKE (yalnız `service_role` + fonksiyon içi çağrı)
- `public.register_...` → anon:'evet hafıza'? **hayır**: `ANON YOK`; `authenticated` + `service_role` EXECUTE
- `public.get_contract` → anon + authenticated + service_role EXECUTE (salt-okunur sözleşme)
- İki yeni tabloda da RLS açık; politikalar `private.current_user_has_admin_permission('ai.manage'|'questions.approve')` ve `service_role` koşulu
- Yetki arkadaki yazılım `private` SEARCH_PATH='' (şema ele geçirme koruması)
- Idempotent DDL: `IF NOT EXISTS` / `OR REPLACE` / `DROP POLICY IF EXISTS`; tümü BEGIN/COMMIT

---

## 5. QA Matrisi — TS katmanı (candidate-batch-orchestrator.test.ts)

| Senaryo | Test | Sonuç |
|---|---|---|
| 1 | Geçerli paket → tüm kapılar pass → ready_for_human_review | ✅ PASS |
| 2 | Bozuk kök (producer/schema/fields) → paket geçersiz | ✅ PASS |
| 3 | outcome_code formatı bozuk → invalid | ✅ PASS |
| 4 | E seçeneği yok ama cevap E / çözüm adımsız → invalid → rejected | ✅ PASS |
| 5 | Aynı soru metni × 2 → duplicate dedupe | ✅ PASS |
| 6 | Kapı fail → rejected | ✅ PASS |
| 7 | Kapı mevcut değil / pending → needs_review (fail-closed) | ✅ PASS |
| **TOPLAM** | | **14/14** |

`npm run test` full suite: **60 dosya / 827 PASS / 0 FAIL**.

---

## 6. QA Matrisi — Disposable DB (supabase_db_qa-faz14a)

Ortam: `public.ecr.aws/supabase/postgres:17.6.1.155`, **port 56432**, ana DB'den `pg_dump --no-owner -Fc` → `pg_restore` ile **001–110 şema durumu klonlandı**, ardından migration 117 uygulandı. Ana stack (`supabase_db_yarisma-programi`, 54322) ve `supabase_db_qa-iso19` (56422) **dokunulmadı**.

| # | Test | Sonuç |
|---|---|---|
| 1 | Migration 117 ilk uygulama (ON_ERROR_STOP=1) | ✅ COMMIT |
| 2 | Migration 117 ikinci uygulama (idempotent — `already exists, skipping`) | ✅ COMMIT |
| 3 | Rollback test (BEGIN; stripped migration; ROLLBACK) → 0 candidate tablo kaldı | ✅ geçerli |
| 4 | Valid batch (2 soru, çözümlü) → `ingested`, 2 staging_id, `total_items=2` | ✅ PASS |
| 5 | Aynı batch tekrarı → `already_received`, aynı batch_id + staging_ids (yeni satır yok) | ✅ PASS |
| 6 | All-invalid batch (grade="oniki", seçenek eksik, cevap X) → `rejected`, staging_ids=[] | ✅ PASS |
| 7 | Mixed (geçerli + adımsız çözüm + geçersiz) → `partially_valid` | ✅ PASS |
| 8 | Çözümü tamamen eksik / bilinmeyen → `needs_review` + `final_readiness_status='needs_review'` + review_queue `candidate_batch_intake_incomplete` open | ✅ PASS |
| 9 | `get_candidate_question_batch_contract()` → sözleşme JSON'ı | ✅ PASS |
| 10 | GRANT: register → anon=f | authenticated=t | service_role=t | ✅ PASS |
| 11 | RLS: anon 0 satır görür, postgres 4 satır görür | ✅ PASS |
| 12 | `private.validate_candidate_question_batch_candidate` → anon/authenticated EXECUTE yok | ✅ PASS |
| 13 | anon `register_...` → `permission denied for function` | ✅ PASS |
| **TOPLAM** | | **13/13** |

### QA sırasında yakalanan ve DÜZELTİLEN 2 migration hatası

1. `p_payload::bytea` → jsonb'den bytea'ya cast yok → batch_key hesaplanamıyordu.
   Düzeltme: `encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex')`.
2. `v_received_count` hiç artırılmıyordu → fonksiyon dönen `total_items` hep **0** oluyordu.
   Düzeltme: `v_received_count := v_received_count + 1` döngü başına eklendi.

---

## 7. Docker Envanter Karşılaştırması

**Öncesi / sonrası** (değişiklik yalnız kendi konteynerim):

```
Önce : supabase_db_yarisma-programi, supabase_db_qa-iso19, studio, pg_meta, storage,
       rest, realtime, inbucket, auth, kong, vector, analytics  (12)
Ek   : supabase_db_qa-faz14a (56432)  ← disposable QA için geçici
Kaldı: supabase_db_qa-faz14a (docker stop + rm)
Sonra: 12 konteyner — önceki listeyle AYNEN AYNI
```

Geçici dosyalar (`/tmp/faz14a_main.dump`, `/tmp/117.sql`, `/tmp/117_nobegin.sql`) disposable konteynerle birlikte yok edildi.

---

## 8. Dosya Envanteri (Faz 14A kapsamı)

| Dosya | Rol |
|---|---|
| `src/lib/content/candidate-batch-types.ts` | Veri sözleşmesi + yasaklı alan listesi + gate/audit tipleri |
| `src/lib/content/candidate-batch-validator.ts` | Deterministik validatör (Türkçe hata kodları, duplicate dedupe) |
| `src/lib/content/candidate-batch-orchestrator.ts` | C-1 köprüsü: auditBatch / reevaluateBatch / GateProvider (fail-closed) |
| `src/lib/content/candidate-batch-orchestrator.test.ts` | 7 senaryo / 14 test |
| `supabase/migrations/117_faz14a_candidate_question_batch.sql` | Migration: tablolar + RPC'ler + RLS/grant + sözleşme fonksiyonu |
| `docs/reports/faz14a-aday-soru-alim-ve-denetim-koprusu.md` | Bu rapor |

---

## 9. Kalan İşler (gelecek fazlar — bu fazda YAPILMADI)

1. **Gerçek AI üretici entegrasyonu:** external producer sözleşmesi hazır; gerçek üretici tarafı JSON üretip RPC'yi çağırır. Koruma: producer_id izin listesi + `sha256` batch_key (aynı payload dedupe).
2. **033–039 gate'lerinin gerçek AI sonuçlarıyla koşturulması:** `auditBatch` mock gate'lerle prova edildi; canlı AI gate sonuçlarıyla `ready_for_human_review` / `rejected` / `needs_review` eşlemesi uçtan uca doğrulanmalı.
3. **`ready_for_human_review` DB temsili:** 117'de literal yok; 038 üzerinden `needs_review` + `final_readiness_status='ready_for_human_review'` eşlemesi tekrar kontrol edilmeli.
4. **ZIP / kaynak türetme uygulaması:** `forbidden_fields` sözleşmede uzak alan reddi şu an TS validatör + DB validator aynı listeyle çalışıyor; PDF'ten bu alanları üreten bir akış var ise gelecekte engellenecek.
5. **Test gevşetme:** yapılmadı, mevcut 827 testte skip yok.

---

## 10. Karar Kaydı (bu faz)

| Karar | Gerekçe |
|---|---|
| `import_batches` yeniden KULLANILMADI | raw payload sütunu yok; batch kök bilgisi (batch_key, sha256, üretici) saklanamaz |
| Yeni tablolar (batch + candidate results) | Kayıp penceresi olmadan tüm kanıt tek yerde; `ai_validation_results` ile eşleme staging_question_id üzerinden |
| staging_source=`manual_candidate` | Mevcut allowlist (006) içinde; AI worker akışından farklı köprünün işareti |
| `automatic_publication_allowed` her zaman false | Otomatik yayın yasak; sözleşme sabiti, ürün kararı gerektirir |
| `private` fonksiyonlar PUBLIC'e kapalı, RPC erişimi admin/service_role | Mevcut private.  pattern (014) ile tutarlı |
| Batch idempotency `sha256(payload)`: aynı içeriğin tekrarı yeni staging satırı üretmez | Üretici retry / aynı soru seti tekrarında kopya önleme |

---

## 11. Sonuç

```
FAZ14A_KOD_VE_MIGRATION: PASS
FAZ14A_UNIT_TESTS:       14/14 PASS (plus 827 full suite PASS)
FAZ14A_DB_QA_DISPOSABLE: 13/13 PASS (apply ×2, rollback, 9 fixture senaryo)
TS_ORCHESTRATOR_READY:   YES (fail-closed gate agregation)
COMMIT / PUSH:           NOT_DONE (kullanıcı onayı bekleniyor)
```