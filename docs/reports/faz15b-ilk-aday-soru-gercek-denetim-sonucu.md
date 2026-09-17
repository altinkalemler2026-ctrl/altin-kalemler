# Faz 15B — İlk Aday Soru Gerçek Denetim Sonucu

- **Tarih:** 2026-09-16
- **Durum:** PARTIAL_SUCCESS (intake tamamlandı; C-1 denetimi gerçek akışla denendi, tam C-1 başarısı üretilemedi — eksik AI/chip yapılandırması nedeniyle)
- **Kapsam:** Yalnız ana lokal DB (`supabase_db_yarisma-programi`, port 54322). Hosted/UI/commit/push yapılmadı. PDF erişimi kullanılmadı.

---

## 1. Özet

- Faz 15A'da onaylanan ve düzeltilen MAT.10.4.6 aday sorusu (`cur-mat10-mat1046-0001`) **gösterim/sahneleme (staging) alımı başarıyla tamamlandı**: batch `status=ingested`, `automatic_publication_allowed=false`.
- C-1 denetimi (cevap, müfredat uyumu, çözüm süresi, özgünlük, kalite, readiness) **gerçek RPC akışıyla çalıştırıldı**. Sonuç **hiçbir kapıdan geçemedi**: readiness skoru `0.0000`, durum `human_review_required`.
- **Hiçbir üretime/yayına geçilmedi.** `questions` tablosu 8 satırda sabit kaldı; staging kaydında `final_question_id=NULL`.

## 2. İntake Sonucu (gerçek RPC çıktısı)

`public.register_candidate_question_batch` (service_role claim ile) döndürdü:

| Alan | Değer |
|---|---|
| status | `ingested` |
| batch_id | `7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3` |
| batch_key | `opencode-big-pickle:783ff9610897706ec0e97dd29945348a008448e700bb23b76609d212e1f80bc2` |
| staging_ids | `["03682255-734d-407f-9b26-3168653fe21e"]` |
| total / valid / invalid / inserted / duplicate | 1 / 1 / 0 / 1 / 0 |
| automatic_publication_allowed | `false` |

## 3. Sözleşme Doğrulaması (DB gerçeği)

- `candidate_question_batches`: `origin=curriculum_original`, `producer_id=opencode-big-pickle`, `producer_model=big-pickle`, `schema_version=1.0`, `validation_summary={received:1, valid:1, invalid:0, inserted:1, duplicates:0}`, `error_data={}`.
- `ai_question_staging` (id `03682255-...`): `staging_source=manual_candidate`, `staging_status=validating`, `grade_level=10`, `subject_id=430903f3-...`, `outcome_code=MAT.10.4.6` (kazanım), `proposed_correct_answer=D`, `proposed_cognitive_type=application`, `proposed_difficulty=medium`, `proposed_solve_time_seconds=120`, `ownership_status=ai_original`, `copyright_risk_level=unknown`, `commercial_use_allowed=false`.
- `metadata`: `deterministic_ingestion_passed=true`, `candidate_batch_deterministic_checks_passed=true`, `final_readiness_status=pending` (intake anında), `automatic_publication_allowed=false`, çözüm adımları eksiksiz saklandı.
- `candidate_batch_candidate_results` (id `e589188e-...`): `validation_status="inserted"`, `validation_errors=[]`, `validation_warnings=[]`, `candidate_index=0`.
- **Beklenti farkı:** Kullanıcı yönergesindeki "review_queue'e `needs_review`" beklentisi bu aday için **DB sözleşmesiyle üretilmiyor**: çözüm adımları, sınıf ve kazanım eksiksiz olduğundan intake sonrası durum `staging_status=validating` + `final_readiness_status=pending` olarak oluşuyor; `reason_code='candidate_batch_intake_incomplete'` ile review_queue girdisi **oluşmadı** (0 satır). C-1 denetiminin ardından readiness durumu DB tarafından `human_review_required`'a yükseldi (bkz. bölüm 4-5).

## 4. C-1 Denetimi — Gerçek Akış Sonuçları (RPC'lerle çağrıldı)

| Kapı | Gerçek sonuç | Detay |
|---|---|---|
| answer_verification | **error** | SQLSTATE P0001: *"Independent answer verification is intended for AI generated staging questions."* (kapı `staging_source=manual_candidate` için başlatılamıyor) |
| curriculum_fit | **error** | SQLSTATE P0001: *"Generation spec is required."* |
| solve_time | **error** | SQLSTATE P0001: *"Generation spec is required."* |
| originality | **started** | run_id `542aa9d2-1e09-4e5b-be1a-2e5272e5bbcf`, durum `waiting_reviewer_1` |
| question_quality | **started** | run_id `87fdbcc8-14cd-4932-99bf-5b5c0e730b94`, durum `waiting_reviewer_1` |
| readiness | **result** | readiness_run_id `babb3ac5-b926-4141-b4bf-ebc8d9449abe` — skor `0.0000` |

Readiness raporunun özeti (038 `evaluate_ai_question_readiness`):

- `readiness_status = human_review_required`
- `readiness_score = 0.0000`
- `commercial_ready = false`
- `automatic_publication_allowed = false`
- `human_final_approval_required = true`
- Gate durumları: answer_verification=not_started, curriculum_fit=not_started, solve_time=not_started, originality=waiting_reviewer_1, question_quality=waiting_reviewer_1 → **hiçbiri passed değil**
- 5 blocking_reason üretildi (her kapı için ilgili "not passed" kodu) + 1 warning: `not_commercially_cleared`.

Kapı koşu kayıtları: `ai_originality_verification_runs`=1, `ai_question_quality_runs`=1, `ai_question_readiness_runs`=1; `ai_answer_verification_runs`=0, `ai_curriculum_fit_runs`=0, `ai_solve_time_verification_runs`=0.

## 5. Eksik Yapılandırma / Karşılaşılan Gerçek Hatalar

1. **Gerçek AI çözücü sağlayıcı yok.** `src/ai-worker/` içinde yalnız test/dry-run sağlayıcılar var; `candidate-batch-orchestrator.ts` içindeki `createDefaultGateProvider()` tüm kapıları `pending` döndürüyor ve gerçek 033-039 RPC'lerine bağlanan bir gate sağlayıcı kodda bulunmuyor. Bu nedenle `start_originality_verification` ve `start_question_quality_review` run'ları `waiting_reviewer_1` aşamasında **sonsuza dek beklemede** kalacaktır (tamamlayacak çözücü yok).
2. **Kapıların manual_candidate desteği yok:** 033 doğrudan `staging_source <> 'ai_generated'` için ret veriyor; 034/035 `generation_spec` bekliyor (manual adayda yok). Bu üç kapı, mevcut sözleşmeyle aday için **çalıştırılamıyor**.
3. Üstteki kısıtlarla bu Aday = gerçekçi olarak `human_review_required` sınıfında; DB'nin kendisi `automatic_publication_allowed=false` üretti. **Sonuç uydurulmadı**; yukarıdaki tüm değerler gerçek RPC yanıtlarıdır.

## 6. Yapılmayanlar / Güvenlik Tutanağı

- `questions` satırı eklenmedi (önce: 8, sonra: 8).
- `review_queue`'ya candidate girdisi eklenmedi (0).
- Vault/kaynak locale gömülü soru, öğrenciye gösterim, öğretmen onay akışı, fixture veya source record **oluşturulmadı**.
- Komut çıktısında secret/token/API anahtarı işlenmedi, `.env` okunmadı.
- Geçici dosyalar (_tmp payload/SQL + container /tmp) silindi.

## 7. Nihai Konum (DB gerçeği)

`ai_question_staging` id `03682255-...`: `staging_status=validating`, `final_question_id=NULL`, `metadata.final_readiness_status=human_review_required`, `metadata.deterministic_ingestion_passed=true`, `metadata.automatic_publication_allowed=false`.

## 8. Sonraki Adım (dur)

- Faz 15B burada sonlanıyor; **yayın/yükseltme yapılmadı**, commit/push yapılmadı.
- C-1 kapılarının manual_candidate için gerçek çalışır hâle gelmesi için gerekenler gelecek bir fazın kapsamındadır: gerçek AI çözücü entegrasyonu + 033-035 kapılarının aday akışına uygun gözden geçirilmesi. Kanonik görev durumu `docs/project/ai-handoff/current-task.json`'a yansıtılmadı; "devam" onayı beklenir.