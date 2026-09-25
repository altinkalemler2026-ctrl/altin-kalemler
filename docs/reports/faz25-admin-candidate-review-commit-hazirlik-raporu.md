# Faz 25 — Admin Candidate-Review Commit Öncesi Dar Kapsamlı QA

- Tarih: 2026-09-25
- Kapsam: Yalnız Faz 24–25 **admin candidate-review** değişiklikleri için commit öncesi QA.
  Öğrenci canlı giriş testi bu oturumda otomasyonla yapılmadı; iki normal öğrenci hesabıyla
  manuel kabul kullanıcı tarafından verildi (bkz. `faz25-normal-ogrenci-yonlendirme-ve-admin-erisim-kabul-testi.md`).
- Yöntem: salt-okunur envanter + hedef dosyalarla sınırlı komutlar. Fixture oluşturma, otomatik
  öğrenci login denemesi, DB yazma, migration, intake, publish, approval, sunucu yeniden başlatma,
  commit, stage ve push **yapılmadı**.
- `SAFE_FOR_LOCAL_COMMIT: YES`
- `SAFE_FOR_PUSH: NO`

## 1. Hedef dosya envanteri

Kapsam belirleme yöntemi: `git status --porcelain` + `git diff --stat` + hedef dosyaların
import grafiği kontrolü. `candidate-batches.ts` ve üç admin sayfası yalnızca **değiştirilmemiş**
modüllere bağlıdır (`@/lib/supabase/server`, `@/lib/admin/question-bank`,
`@/lib/admin/candidate-batches-errors`); `src/lib/review/*` veya `src/lib/training/*` bağımlılığı
yoktur. Bu nedenle aşağıdaki liste commit için bağımsız ve tutarlıdır.

### 1.1 Kaynak (üretim) dosyalar — 5 değişiklik

| Dosya | Durum |
|---|---|
| `src/app/(admin)/admin/candidate-batches/page.tsx` | M |
| `src/app/(admin)/admin/candidate-batches/[id]/page.tsx` | M |
| `src/app/(admin)/admin/page.tsx` | M |
| `src/lib/admin/candidate-batches.ts` | M |
| `src/lib/admin/admin-panel-messages.ts` | M |

### 1.2 Test dosyaları — 4 değişiklik

| Dosya | Durum |
|---|---|
| `src/app/(admin)/admin/candidate-batches/page.test.tsx` | M |
| `src/app/(admin)/admin/candidate-batches/[id]/page.test.tsx` | M |
| `src/app/(admin)/admin/page.test.tsx` | M |
| `src/lib/admin/candidate-batches.test.ts` | M |

### 1.3 Migration ve QA scripti — 2 yeni dosya

| Dosya | Durum |
|---|---|
| `supabase/migrations/126_faz24_admin_candidate_review_low_confidence.sql` | ?? |
| `scripts/qa_faz24_admin_candidate_review_126_local.sql` | ?? |

Migration 126 yalnız `CREATE OR REPLACE FUNCTION` + `REVOKE`/`GRANT` içerir (DDL-only, append-only);
`INSERT`/`UPDATE`/`DELETE` yoktur. 120/121/123/124/125 dosyalarına geri dokunulmaz, yeni dosya
ekleyen zincirdir. QA scripti disposable ortam içindir (tam rollback) ve ana stack'te çalıştırılmaz.

### 1.4 Faz 24–25 kanıt raporları — 9 yeni dosya

| Dosya | Durum |
|---|---|
| `docs/reports/admin-candidate-review-dto-tasarim-raporu.md` | ?? |
| `docs/reports/admin-fizik-p01-batch-kabul-kontrolu.md` | ?? |
| `docs/reports/admin-gorsel-test-en-dar-rol-denetimi.md` | ?? |
| `docs/reports/faz24-ana-db-salt-okunur-dogrulama.md` | ?? |
| `docs/reports/faz25-admin-candidate-etkilesim-ve-yetki-kabul-testi.md` | ?? |
| `docs/reports/faz25-admin-candidate-review-gorsel-kabul-testi.md` | ?? |
| `docs/reports/faz25-admin-candidate-review-ui-qa.md` | ?? |
| `docs/reports/faz25-ogrenci-fixture-olusturma-kok-neden-teshisi.md` | ?? |
| `docs/reports/faz25-normal-ogrenci-yonlendirme-ve-admin-erisim-kabul-testi.md` | ?? |
| `docs/reports/faz25-admin-candidate-review-commit-hazirlik-raporu.md` | ?? (bu rapor) |

## 2. Commit'e girecek kesin dosya listesi

Sıralama: kaynak → test → migration/QA → raporlar. Toplam **21 dosya**
(9 değiştirilmiş izlenen dosya + 12 yeni dosya).

```
src/app/(admin)/admin/candidate-batches/page.tsx
src/app/(admin)/admin/candidate-batches/[id]/page.tsx
src/app/(admin)/admin/page.tsx
src/lib/admin/candidate-batches.ts
src/lib/admin/admin-panel-messages.ts
src/app/(admin)/admin/candidate-batches/page.test.tsx
src/app/(admin)/admin/candidate-batches/[id]/page.test.tsx
src/app/(admin)/admin/page.test.tsx
src/lib/admin/candidate-batches.test.ts
supabase/migrations/126_faz24_admin_candidate_review_low_confidence.sql
scripts/qa_faz24_admin_candidate_review_126_local.sql
docs/reports/admin-candidate-review-dto-tasarim-raporu.md
docs/reports/admin-fizik-p01-batch-kabul-kontrolu.md
docs/reports/admin-gorsel-test-en-dar-rol-denetimi.md
docs/reports/faz24-ana-db-salt-okunur-dogrulama.md
docs/reports/faz25-admin-candidate-etkilesim-ve-yetki-kabul-testi.md
docs/reports/faz25-admin-candidate-review-gorsel-kabul-testi.md
docs/reports/faz25-admin-candidate-review-ui-qa.md
docs/reports/faz25-ogrenci-fixture-olusturma-kok-neden-teshisi.md
docs/reports/faz25-normal-ogrenci-yonlendirme-ve-admin-erisim-kabul-testi.md
docs/reports/faz25-admin-candidate-review-commit-hazirlik-raporu.md
```

## 3. QA sonuçları

### 3.1 `git diff --check` — PASS

- Kapsam: 1.1 ve 1.2'deki 9 değiştirilmiş dosya.
- Sonuç: `EXITCODE=0`, whitespace hatası yok.
- Not: `core.autocrlf=true` nedeniyle "LF will be replaced by CRLF" uyarıları çıktı; bunlar hata
  değil, mevcut depo satır sonu davranışıdır ve bu fazın değişikliği değildir.
- Yeni (izlenmeyen) iki dosyada ayrıca kontrol: satır sonu boşluğu 0, dosya sonu satır sonu
  mevcut değil (`git diff --check --no-index` yalnız CRLF uyarısı üretti, hata üretmedi).

### 3.2 Vitest (kapsamlı) — PASS

Komut: `npx vitest run` — yalnız 4 ilgili test dosyası.

| Test dosyası | Sonuç |
|---|---|
| `src/lib/admin/candidate-batches.test.ts` | 33/33 PASS |
| `src/app/(admin)/admin/page.test.tsx` | 10/10 PASS |
| `src/app/(admin)/admin/candidate-batches/page.test.tsx` | 14/14 PASS |
| `src/app/(admin)/admin/candidate-batches/[id]/page.test.tsx` | 13/13 PASS |
| **Toplam** | **4 dosya / 70 test PASS**, süre 3.43 sn |

Test gevşetme, `skip`, `only`, `todo` veya eşik düşürme yapılmadı.

### 3.3 TypeScript — PASS

Komut: `npx tsc --noEmit` → `EXITCODE=0`, sıfır hata/diagnostic. Proje geneli kontrol hedef
dosyaların tip örüntüsünü (RPC cast'leri, yeni DTO alanları) kapsar.

### 3.4 Scoped ESLint — PASS

Komut: `npx eslint` — yalnız 1.1'deki 5 değişen kaynak dosyası.
Sonuç: `EXITCODE=0`, sıfır uyarı/hata. Tüm repo lint'i, geniş glob, `styles/**`, `frontend/**`
veya ilgisiz route taraması yapılmadı.

## 4. Yerel ana DB salt-okunur baseline

- Ortam: `supabase_db_yarisma-programi` (PostgreSQL 17.6, healthy).
- Yöntem: `docker exec ... psql -A -t -F '|' -c "<SELECT>"`. Yalnız `SELECT` ve
  `information_schema`/`pg_proc` kataloğu okuması. DDL/DML, migration, intake, publish,
  approval, backfill, `set_config` veya session kimliği taklidi **yapılmadı**.
- Ana stack sıfırlanmadı; ayrı QA konteynerlerine (`faz14e-qa`, `qa-iso19`, `supa-typesfix`)
  dokunulmadı.

| Kontrol | Ölçüm | Beklenen | Sonuç |
|---|---|---|---|
| Fizik batch künyesi | `id=9310097d-168c-498e-b8cc-4531d46c0825`, `status=ingested` | ingested | PASS |
| Batch sayaçları | total 32 / valid 32 / invalid 0 / inserted 32 / duplicate 0 | 32/32/0/32/0 | PASS |
| Aday sonuç satırı | `candidate_batch_candidate_results` = **32** | 32 | PASS |
| Aday durumu | `staging_status='validating'` × 32 (tek başka durum yok) | 32 validating | PASS |
| Preflight (review-only) | `review_required=true`, `publication_allowed=false`, `is_active=false`, `schema_version=1.1` | review-only, yayın kapalı | PASS |
| Yayın/promote | `ai_question_staging.final_question_id` dolu satır = **0** | 0 | PASS |
| `questions` toplam | **8** | 8 | PASS |
| `questions` kökeni | 8 kayıt `approved` + `is_active=true`, oluşturulma 2026-09-07 … 2026-09-15 | Faz öncesi baseline | PASS |
| `low_confidence` backfill | `metadata ? 'low_confidence'` = **0** | 0 (geriye dönük backfill yok) | PASS |
| `review_queue` toplam | 1 (Faz öncesi Matematik kaydı) | 1 | PASS |
| Toplam batch | 2 (Fizik + Matematik) | 2 | PASS |
| Migration 126 uygulanmış mı | `get_candidate_question_batch_detail` gövdesinde `low_confidence` = 1; `private.register_candidate_md_batch` gövdesinde `low_confidence_candidates` = 1 | 1 / 1 | PASS |
| ACL fail-closed | `has_function_privilege('anon', 'public.get_candidate_question_batch_detail(uuid)','EXECUTE')` = **false** | false | PASS |

### Baseline yorumu

- **Fizik batch 32 aday, review-only:** 32 adayın tamamı `validating` durumunda; preflight
  `review_required=true`, `publication_allowed=false`, `is_active=false`. Hiçbir aday
  `final_question_id` taşımadığı için **yayın/promote yok**.
- **`questions = 8`:** Bu 8 soru Faz 24 öncesinden gelen baseline'tır (2026-09-07 … 2026-09-15) ve
  Fizik batch'inden **değildir**; Fizik batch'inin `questions` tablosuna hiçbir katkısı yoktur
  (promote sayısı 0).
- **Onay yok:** Bu fazda approve/reject/publish kararı yazılmadı. Admin yüzeyleri yalnız okuma
  DTO'sudur; migration 126 append-only DDL'dir ve hiçbir veri satırını değiştirmez.
- Migration 126 ana DB'de zaten uygulanmış durumda; bu oturumda yeniden uygulanmadı ve
  `supabase_migrations.schema_migrations` (son kayıt 110) değiştirilmedi.
- Not: `faz24-ana-db-salt-okunur-dogrulama.md` içindeki service_role kimlikli RPC çağrısı
  (`_qa_f24_as_role` deseni) bu oturumda **yeniden çalıştırılmadı**; yukarıdaki baseline doğrudan
  tablo SELECT'leriyle alındı. RPC gövde/ACL kanıtı katalog okumasıyla doğrulandı.

## 5. Bilerek dışarıda bırakılan ilgisiz değişiklikler

Çalışma ağacında bu fazın kapsamı dışında çok sayıda değişiklik var. Bunlara dokunulmadı,
stage edilmedi ve commit'e önerilmedi.

### 5.1 İzlenen (M) ama kapsam dışı dosyalar — 33 dosya

- Yapılandırma/ajan: `opencode.json`, `README.md`, `src/app/globals.css`
- Öğrenci route'ları (16): `src/app/(auth)/login/page.tsx`,
  `src/app/(student)/layout.tsx`, `dashboard/`, `ilerleme/`, `league/`, `profile/`,
  `training/` (3 dosya), `competition/` (3 dosya), `tekrar/` (2 dosya)
- Öğrenci bileşenleri (13): `src/components/student/*` (`StudentHome.tsx`, `StudentNav.tsx`,
  `StudentGamification.tsx`, `StudentAnalytics.tsx`, `ThemePicker.tsx`, `QuestionRenderer.tsx`,
  `OutcomeReviewPlan.tsx`, `MatchmakingQueue.tsx`, `CompetitionSession.tsx`,
  `TrainingSession.tsx` + testler)
- Öğrenci eğitim servisi (5): `src/lib/training/service.ts`, `types.ts`, `errors.ts` + testler
- Inceleme servisi (3): `src/lib/review/service.ts`, `types.ts` + test

Gerekçe: Bunlar admin candidate-review değil, öğrenci tarafı ve eğitim/inceleme servisleri
çalışmasıdır. Admin candidate-review kodu bu modüllere bağlı değildir (bkz. bölüm 1); bu nedenle
commit'e alınmaları gerekmez ve Faz 24–25 kapsamını kirletir.

### 5.2 İzlenmeyen (??) ama kapsam dışı dosyalar

- Geçici/deneysel kök dosyalar: `apply_mig_tmp.sh`, `bootstrap_auth_tmp.sql`, `pdfprobe.js`,
  `pdftext.js`, `pgtest.mjs`, `pgtest2.mjs`, `pgvis.mjs`, `qa_rls_088.sql`,
  `tymm-2026-cover.png`
- Ajan/geçici çıktı: `.cbmignore`, `.opencode/plugins/`, `.opencode/tmp-faz25-dev.log`,
  `.playwright-mcp/`, `test-results/`, `docs/project/ai-handoff/sandbox/**`
- Diğer faz raporları ve ekran görüntüleri: `docs/reports/faz11-*`, `faz12*`, `faz13*`,
  `faz14-*`, `faz15a-live-e2e/`, `faz16b-*`, `fizik-p01-*`, `admin-candidate-rpc-120-121-*`,
  `local-main-faz22-*`, `proje-durum-gerceklik-raporu-*`, `rollback-faz12a-matematik.sql`,
  `yerel-admin-test-hesabi-giris-teshisi.md`, `yerel-kayit-hatasi-kok-neden-teshisi.md` ve
  tüm `*.png` / `*.zip` kanıt dosyaları
- Diğer dokümantasyon: `docs/design/`, `docs/question-production/`, `docs/references/`,
  `docs/project/faz5-*-devam-notu-*.md`
- Diğer scriptler: `scripts/*.ops.ps1`, `scripts/local-auth-e2e-fixture.sql`,
  `scripts/cleanup-generated-artifacts.ps1`, `scripts/run-*.ps1`
- Diğer testler: `tests/e2e/*.spec.ts` (7 dosya), `supabase/snippets/`,
  `src/app/(auth)/login/page.test.tsx`, `src/components/student/TrainingSessionSingle.tsx` + testi

Gerekçe: Bunlar ya önceki/başka fazların teslimat seti, ya geçici tanı araçları, ya da kapsam
dışı feature dallarıdır. `tests/e2e/*` dosyaları otomatik credential tabanlı E2E içindir ve bu fazda
çalıştırılmamıştır (`BLOCKED`); kanıtlanmamış testleri commit'e almak kapsam genişletmesidir.

### 5.3 Commit'e alınmaması gerekenler hakkında not

- `.gitignore` güncellemesi, ad alanı taşıma, dosya yeniden adlandırma veya biçimlendirme
  (prettier/ESLint --fix) yapılmadı; dosya içerikleri değiştirilmedi.
- `docs/reports/` altında bu faza ait olmayan raporların faz etiketi değiştirilmedi.

## 6. Karar

| Ölçüt | Sonuç |
|---|---|
| Kapsamlı Vitest | PASS (70/70) |
| TypeScript (`tsc --noEmit`) | PASS (0 hata) |
| Scoped ESLint (5 kaynak dosyası) | PASS (0 hata) |
| `git diff --check` | PASS (temiz) |
| DB baseline (32 aday / review-only / questions=8 / yayın-onay yok) | PASS (değişmedi) |
| Migration 126 uygulama + ACL | PASS |

**SAFE_FOR_LOCAL_COMMIT: YES**

Gerekçe: Commit kapsamındaki 21 dosyanın tamamı yeşil kontrollerden geçti; tip, lint, test ve
salt-okunur DB baseline tutarlı; kapsam dışı değişiklikler commit listesine girmiyor.

**SAFE_FOR_PUSH: NO**

Gerekçe:
1. Push, ana sözleşme gereği her fazda ayrı ve açık kullanıcı izniyle yapılır; bu oturumda alınmadı.
2. Bu commit tek başına çalışma ağacındaki diğer değişiklikleri kapsamaz; push öncesi kapsam
   dışı değişikliklerin durumu (commit/stage/elenmesi) kullanıcı kararıdır.
3. Push sonrası aynı SHA'da CI `completed/success` doğrulanmadan faz bitmiş sayılmaz.
4. Otomatik canlı E2E hâlâ `BLOCKED`; bu commit'in kapsamı manuel kabul kanıtı + otomatik
   credential tabanlı E2E yerine geçmez.

## 7. Bu oturumda yapılmayanlar

- Yeni fixture oluşturma; mevcut kullanıcı, parola veya rol değişikliği.
- Otomatik öğrenci login denemesi; açık localhost sunucusunu durdurma/başlatma/yeniden başlatma.
- DB yazma, migration uygulama, intake, publish, approval, backfill, seed/reset.
- `git add`, `git commit`, `git push`, `git stash`, `git checkout`, `git clean`, `git restore`.
- Tüm repo lint'i, geniş glob taraması, `styles/**`, `frontend/**` ve ilgisiz route incelemesi.
- Secret, credential, token veya cookie okuma/yazma; hiçbir rapora credential yazılmadı.

## 8. Sonraki adım

Kullanıcı onayı bekleniyor. Onay verilirse yalnız bölüm 2'deki 21 dosya stage edilip tek yerel
commit atılabilir; push ayrı ve ayrık onayla yapılır.
