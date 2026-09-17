# Faz 15C — Harici aday paketini AI denetim sözleşmesine bağlama (sonuç raporu)

- Tarih: 2026-09-16
- Kapsam: migration `118_faz15c_external_candidate_generation_spec_binding.sql`
- Durum: APPLIED (ana lokal stack), QA DOĞRULANDI, COMMIT/PUSH YOK

## Özet

Faz 15B'de `curriculum_original` harici üretici adayı, sahte "manuel" etiketiyle
(`manual_candidate`) ve generation şartnamesi olmadan giriyordu. Bu yüzden üç
denetim kapısı P0001 ile reddediyordu:

- `033 start_answer_verification` → "_intended for AI generated_"
- `034 start_curriculum_fit_verification` → "_Generation spec is required._"
- `035 start_solve_time_verification` → "_Generation spec is required._"

Bu faz adayı sahte kökenle değil, **mevcut şemaya uygun gerçek bir
`ai_generation_specs` bağı** ile denetim sözleşmesine bağlar. Aday kimliği
(`origin='curriculum_original'`, producer, model, provenance) korunur.

## Migration 118 (3 parça)

1. **Staging kaynak allowlist'i:** `ai_question_staging.staging_source` CHECK
   constraint'ine `'external_producer'` eklendi (artık idempotent DO ile, tam
   isimle; ilk sürümdeki geniş `LIKE '%staging_source%'` eşleşmesi bug'ı
   düzeltildi — `source_question_number_check`'i düşürme riski yoktu).
2. **`private.start_answer_verification`** (033 eşdeğeri) CREATE OR REPLACE:
   kaynak kontrolü `NOT IN ('ai_generated','external_producer')` oldu; gövde
   birebir korundu, yalnız mesaj güncellendi.
3. **`private.register_candidate_question_batch`** (117 eşdeğeri) CREATE OR
   REPLACE: davranış birebir korundu; her geçerli harici aday için
   - aktif (is_default öncelikli) müfredattan `curriculum_outcomes` çözümü
     (outcome_code + subject_id + grade_level, `MAT.10.4.6` → `a7100000-…-0013`),
   - mevcut `ai_generation_specs` şemasına uygun kayıt (`desired_count=1`,
     `status='ready'`, `constraints` içinde provenance; `outcome_id`),
   - staging insert'i `staging_source='external_producer'` + `generation_spec_id`
     + `proposed_curriculum_version_id/topic/subtopic` ve metadata'da
     `required_outcome_id`/`generation_spec_id`/`outcome_code`.

Gate/lint/yayın politikası değişmedi: kapılar yalnız denetim run'ı başlatır,
otomatik promotion asla yapılmaz.

## QA (disposable)

- Ortam: `public.ecr.aws/supabase/postgres:17.6.1.155`, container
  `supabase_db_qa-faz15c`, port `56433`, DB `qa`. Ana stack klonu
  pg_dump (`--no-owner`, **grants dahil**) ile oluşturuldu (Faz 14A yöntemi).
- Migration 118 iki kez uygulandı → idempotan (DO + CREATE OR REPLACE).
- İznin notu: intake/denetim çağrıları Faz 15B ile aynı `service_role` claim ile
  yapıldı (`request.jwt.claim.role`).

Sonuçlar (deterministik sahte fiş kullanıldı, gerçek yayın adayı değil):

| Kontrol | Sonuç |
|---|---|
| [A0] Faz15B kanıt adayı (008 köken) dokunulmadı | manual_candidate, spec yok |
| [B0] Eski aday answer gate: P0001 hâlâ (fail-closed) | PASS "_intended for AI generated or external producer…_" |
| [C0] Harici aday intake | `ingested`, staging `external_producer`, `generation_spec_id` dolu, outcome `a7100000-…-0013`, spec `status=ready`, provenance metadata+constraints ✓ |
| [D0] answer/curriculum_fit/solve_time kapıları | 3 run P0001'siz başladı (`waiting_solver_1` / `waiting_reviewer_1`); curriculum run beklenen outcome'u aldı, solve_time 75/75 sn |
| [E0] Aynı payload tekrar | `already_received`, aynı batch + staging; spec_toplam=1, external_staging=1 (tek duplikasyon yok) |
| [F0] Readiness | `human_review_required`, skor 0.0000, commercial_ready=false, **questions 8→8** (promotion yok) |
| [G0] RLS/izin | anon `ai_generation_specs` SELECT → 0 satır; anon register → fonksiyon izni yok (reddedildi) |
| Migration idempotans | 118 iki kez uygulandı, hata yok |

## Ana lokal stack uygulaması

Migration 118 ana DB'ye (port 54322) **yalnız şema değişikliği olarak** uygulandı;
yeni aday/spec oluşturulmadı. Uygulama sonrası bütünlük:

- staging_source: `manual_candidate=1`, `external_producer=0`
- `ai_generation_specs=0`, `candidate_question_batches=1`, `questions=8`
- Faz15B kanıt adayı (`03682255-…-21e`) hâlâ `manual_candidate` + spec yok
- Answer gate fonksiyonu `external_producer` içerir; eski adayı yine bloklar:
  "_Independent answer verification is intended for AI generated or external producer staging questions._"
- Constraint artık `'external_producer'` içerir

## Rejeksiyon (yapılmadı)

- Ana lokal DB'de yeni gerçek aday oluşturma: **yok** (yalnız QA'da sahte fiş)
- C-1 otomatik promotion: **yok** (readiness fail-closed, `human_review_required`)
- Gerçek AI reviewer/solver çağrısı: **yok** (çözücü yapılandırması eksik; run'lar
  `waiting_*` durumunda ve bu eksiklik oldukları gibi raporlanır)
- PDF/öğrenci/vault/öğretmen onayı/UI/hosted: **yok**
- Commit/push: **yok**; çalışma ağacındaki kullanıcı dosyaları değiştirilmedi
- Docker envanteri: oturum başı/sonu farkı yok (`supabase_db_qa-faz15c` silindi)

## Dosya

- `supabase/migrations/118_faz15c_external_candidate_generation_spec_binding.sql` (yeni, untracked)