# FAZ 14F — QA FIXTURE ÇAKIŞMA DÜZELTMELERİ: UYGULAMA VE DOĞRULAMA

- Tarih: 2026-09-17
- Durum: TAMAMLANDI — tüm doğrulamalar yeşil; commit/push YAPILMADI (sözleşme gereği izin bekler)
- Kapsam: 14E §8 önerilerinin uygulanması + disposable ortamda eksiksiz doğrulama
- Kanıt ortamı: disposable stack `supabase_db_faz14e-qa`

## 1. Başlangıç gerçeklik kontrolü (salt okunur)

- Aktif branch: `main`; yerel HEAD: `5adcc85a9803ed3b1ebcb9675f9596e7d4ffae7b` (Faz 12 kodu)
- Kullanıcıya ait geniş modified/untracked küme korundu; hiçbirine dokunulmadı
- Ürün SQL'ine (`067/068/073/074/083/111`) dokunulmadı; `resolve_current_academic_period()` davranışı değişmedi
- Alan adı / DB envanteri aynı; `supabase_db_yarisma-programi` (ana lokal) sıfırlanmadı, ana stack E2E runner'ları (`run-faz7-e2e.ps1` vb.) ÇALIŞTIRILMADI

## 2. Amaç

Migration 111 (resmî 2026-2027 takvimi) + 074 (global exclusion) ile kırılan 14 QA/yerel
E2E fixture'ının, ürün kararlarına dokunmadan gerçek döneme bağlanması ve disposable DB'de
tam doğrulanması. V1 puan/lig/XP sözleşmeleri, sınıf izolasyonu ve ürün sabitleri değişmedi.

## 3. Uygulanan düzenlemeler (14E §8 yönünde)

### 3.1 Yerel E2E fixture'ları

**`scripts/local-faz7-e2e-fixture.sql`**
- 44 haftalık sahte `academic_weeks` insert bloğu **kaldırıldı** (w42/w43 sabit tarihleri 111
  takvimiyle kesişip 23P01 veriyordu; düzeltme öncesi kalıcı kırık).
- `E2E7-FAZ7` sürümü ve `E2E7-PROF-2026-2027` profili `is_default=false` yapıldı (059
  tek-default-per-year; 111'de TYMM-2026 varsayılan).
- POSTCONDITION artık gerçek `resolve_current_academic_period()` döneminin varlığını doğrular.

**`scripts/local-faz11-e2e-fixture.sql`**
- `QA11E-Y` hafta 5 için `current_date±` sahte takvim insert'i **kaldırıldı** (bugün gerçek K1 ile
  kesişiyordu). `_faz2_require_period` gerçek (resolved) dönemi kullanır; QA11E kapsamı
  `QA11E-SCHED` profilinin `is_default`'uyla çözülür.

**`scripts/local-faz15a-e2e-fixture.sql`**
- Kendi takvimi zaten yoktu; takvim nesnesi yazılmaz. `start_week` runtime'da resolved haftaya
  bağlandı (`end_week := NULL`, açık uçlu) — sabit `start_week=3` zaman-kırılganlığı giderildi.

### 3.2 QA doğrulama scriptleri (A/B grubu)

Tümünde ortak düzeltme şablonu: sahte `academic_weeks` yazımı kaldırıldı; sayaç/exposure/kota
beklentileri ve validasyon sorguları runtime'da çözülen **gerçek** `(academic_year, week)`'e bağlandı;
`qd` kalıcı yazımı amaçlanan scriptlerde transaction+rollback/cleanup kullanıldı; assertion
zayıflatma/yok etme YOK (beklenti sayıları korundu, yalnız bağlam resolved döneme hizalandı).

- `scripts/qa_faz2_local_validation.sql` — QA-Y-2099 sahte hafta yazımı kaldırıldı; beklentiler resolved dönemde
- `scripts/qa_faz3_local_validation.sql` — QA3-Y-2099 sahte hafta kaldırıldı
- `scripts/qa_faz4_local_validation.sql` — QA4-Y-2099 sahte hafta kaldırıldı
- `scripts/qa_faz5_local_validation.sql` — QA5-Y-2099 sahte hafta kaldırıldı
- `scripts/qa_faz6_targeted_review_local.sql` — QA6-Y w5 sahte hafta kaldırıldı
- `scripts/qa_faz9_gamification_local.sql` — guard-bazlı sahte yıl yazımı kaldırıldı (B grubu sessiz atlaması giderildi); QA9 beklentileri gerçek dönem sayaçlarına bağlandı
- `scripts/qa_faz11_progress_feedback_local.sql` — QA11-Y w5 sahte hafta kaldırıldı
- `scripts/qa_grade_hardening_093_local.sql` — QA93-Y w5 sahte hafta kaldırıldı
- `scripts/qa_scoring_v1_094_local.sql` — QA94-Y w5 sahte hafta kaldırıldı
- `scripts/qa_data_boundary_095_local.sql` — QA95-Y w5 sahte hafta kaldırıldı
- `scripts/qa_competition_pack_auto_prepare.sql` — geçmiş yıl etiketi (`'2025-2026'`) düzeltildi; cari döneme bağlandı
- `scripts/qa_faz35_local_validation.sql` — QA-CAL-2099 sahte takvim + yıllar-arası senaryosu gerçek takvimden izole edildi; resolved dönemle yeniden kuruldu
- `scripts/qa_faz2_parallel_probe.sql` — A grubu sahte hafta kaldırıldı; **verify bloğunda `p_year` → `academic_year` sütun adı düzeltildi** (`_faz2_require_period()::TABLE(academic_year text, week integer)`)

`scripts/qa_faz1_local_validation.sql` sahte hafta yazmaz; dokunulmadı.

## 4. Özel durum: faz9 T-78 beklenmedik ikinci bağlantı (dblink)

- T-78, kota paralelliğini ikinci bir DB bağlantısıyla test ediyordu: dblink socket/TCP
  (`host=/var/run/postgresql port=5432 dbname=postgres user=supabase_admin`) her koşulda
  `password or GSSAPI delegated credentials required` (scram) verdi. psql'in aynı conninfo'larla
  socket ve TCP trust bağlantısı YEDERKEN dblink'in domerdiği kanıtlandı → supabase fork
  (supautils vb.) DB-içi ikinci bağlantıları pg_hba'dan bağımsız scram'a zorluyor.
- `host all all all trust` + `pg_reload_conf()` denemesi çözmedi; gerçek hba_file
  `/etc/postgresql/pg_hba.conf`'un yedeği alınıp (`pg_hba.conf.14f.bak`) **geri alındı**.
- **Kullanıcı kararı**: T-78 yeniden yazılmadı, rapor dışı bırakılmadı; kod/ana DB/pg_hba/test
  mantığı değişmeden, host tarafından açılan **iki bağımsız psql bağlantısıyla** gerçek paralel test
  koşuldu. Bu yalnız disposable QA ortamında; çalışmazsa fail/bloklu raporlanırdı (gerek kalmadı).

### T-78 dış koşum kanıtı (iki bağımsız docker exec psql oturumu)

- A1 (Bağlantı A): gerçek işlevin kullandığı yolla kota sayacı satırını kilitli tuttu (`pg_sleep(12)` + commit)
- B1 (Bağlantı B, `lock_timeout=1500`): `T78A-OK 55P03 lock wait timeout` → beklendiseril, gözlemlendi
- Kilit serbestken A2: `_faz9_consume_daily_quota(...)` 499→500 atomik tüketim
- B2 doğrulama: `T78B2-final-used=500` (tam 500), `T78C-501-red-OK P0001` (501 reddedildi), `T78D-remaining=0`
- CLEANUP: `DELETE 1`+`DELETE 1` → tüm fixture verisi temizlendi

## 5. Doğrulama tablosu (supabase_db_faz14e-qa)

| Script | Sonuç | Kanıt |
|---|---|---|
| qa_faz3 | 34 PASS / 0 FAIL | OZET satırı, EXIT=0 |
| qa_faz4 | EXIT=0 | ON_ERROR_STOP=1 |
| qa_faz5 | 15 PASS / 0 FAIL | OZET satırı, EXIT=0 |
| qa_grade_hardening_093 | EXIT=0 | ON_ERROR_STOP=1 |
| qa_scoring_v1_094 | EXIT=0 | C-28 PASS dahil |
| qa_data_boundary_095 | EXIT=0 | ON_ERROR_STOP=1 |
| qa_competition_pack_auto_prepare | 22/22 PASS | T-01..T-17+ |
| qa_faz11_progress_feedback | ~40 PASS | tam yeşil |
| qa_faz6_targeted_review | tüm PASS | T-10c vb. |
| qa_faz35 | 24/24 PASS | T-01..T-20 + resolved T-17/T-18a/b |
| qa_faz9 (T-78 hariç) | 64 PASS / 0 FAIL | satır dilimli pipe (repo değişmedi) |
| qa_faz9 T-78 dış koşum | 3/3 iddia doğrulandı | 55P03, final=500, 501→P0001, kalan=0, cleanup |
| qa_faz2_local_validation | tüm PASS (T-01a..T-12) | EXIT=0, tek transaction+rollback; T-11 gerçek takvim, T-12 usage resolved |
| qa_faz2_parallel_probe | tam yeşil | setup OK; a+b paralel: FINAL_USED=500 (tavan aşılmadı); verify: `500|500|PASS` (used==exposure), VERIFY_PASS; cleanup OK |
| local-faz7-e2e-fixture | uygulandı | POSTCONDITIONS: 5 soru, e2e kullanıcı temiz, period=2026-2027/hafta 1 |
| local-faz11-e2e-fixture | uygulandı | EXIT=0 (idempotent; runner signup öncesi boş geçer) |
| local-faz15a-e2e-fixture | uygulandı | PRECONDITIONS + POSTCONDITIONS doğrulandı, EXIT=0 |

Not: faz9 suite koşumunda T-78 bloğu yalnız boru hattından satır dilimlendi (blok 1272–1353,
1-indexli); repo değişmedi. T-78 ayrı olarak §4'teki dış koşumla tam doğrulandı.

## 6. Tam proje doğrulaması (TS test/tsc/lint)

- `npx vitest run` → **60 dosya / 827 test tamamen geçti** (45.8s)
- `npx tsc --noEmit` → **temiz** (hata/uyarı yok)
- `npm run lint` → 14F kapsamındaki değiştirilmiş dosyalar **temiz**; kalan 1 error + 8 uyarı
  tamamı 14F dışı, kullanıcının önceki/geçici ve untracked dosyalarından kaynaklı
  (`pgvis.mjs`, `probe-sharp.cjs`, `tests/e2e/auc-ops/verif-ops spec`leri, `tests/e2e/faz11-flows.spec.ts`,
  `src/lib/content/curriculum-mapper.ts`, `src/lib/content/solution-validator.ts`). Bu dosyalara
  dokunulmadı; 14F değişiklikleri lint'i bozmamıştır.

## 7. Sonuç ve durum

- 14E'nin belirlediği tüm çakışma kaynakları giderildi; QA/yerel E2E fixture'ları gerçek
  (resolved 2026-2027) döneme bağlandı; sahte takvim yazımı kaldırıldı; assertion'lar zayıflatılmadı.
- Ürün SQL'i, ana lokal DB, pg_hba, takvim/talimatlar, oyun verisi ve gerçek öğrenci/soru verisi
  korundu.
- Tüm doğrulamalar disposable `supabase_db_faz14e-qa`'da yeşil.
- **COMMIT/PUSH YAPILMADI.** Faz kuralı gereği ayrı açık kullanıcı izni beklenir; onay sonrası tek
  fas commit (yalnız 14F dosyaları) hazırlanabilir.
- Hali hazırda kalan tek teknik not: lint'in 1 error'u kullanıcı geçici dosyası `probe-sharp.cjs`
  kaynaklı — commit öncesi bu geçici dosyaların temizlenmesi veya eslint kapsamının daraltılması
  gerekebilir (kullanıcı onayı olmadan bu dosyalara dokunulmaz).