# CI Hattı Doğrulama Raporu — GitHub Actions (Yerel Otonom Döngü)

- **Tarih:** 23 Ağustos 2026
- **Kapsam:** Push/PR'da otomatik TypeScript kontrolü, görev kapsamlı ESLint, Vitest birim/bileşen testleri, temiz migration zinciri, Faz 1/2/3 SQL QA suite'leri ve Faz 2 paralel sayaç probe'u
- **Ortam:** Windows 11 / PowerShell 5.1 / Node v24.19.0 / npm 11.17.0 / Docker Desktop + local Supabase (`supabase_db_yarisma-programi`)
- **Revizyon:** Rev. 1

---

## 1. Oluşturulan / Değişen Dosyalar

| Dosya | Durum | Açıklama |
|---|---|---|
| `.github/workflows/ci.yml` | YENİ | Tek job'luk CI hattı; kalite kapıları pahalı DB adımlarından önce |
| `package.json` | DEĞİŞTİ (+3 satır) | Yalnızca `scripts` bölümüne `lint:faz3` ve `test:unit` eklendi; `test` aynen korundu |
| `docs/reports/latest-ci-validation.md` | YENİ | Bu rapor |

Dokunulmayan (yasaklı) dosyalar: `.env*`, anahtar/secret dosyaları, `.opencode/`, `opencode.json`, `supabase/snippets/`, `scripts/import-legacy-excel.ts`, tüm 001–072 migration'ları, uygulama kodu.

### package.json script farkı

```json
"lint:faz3": "eslint src/components/student src/lib/training \"src/app/(student)/training\" src/app/layout.tsx \"src/app/(student)/layout.tsx\" \"src/app/(student)/dashboard/page.tsx\" vitest.config.ts src/test",
"test:unit": "vitest run --exclude \"**/*.local.test.ts\""
```

`npm test` davranışı birebir aynıdır (38 testin tamamı). `lint:faz3`, daha önce elle çalıştırılan kapsamlı lint listesini sabitler.

---

## 2. CI İş Adımları (`.github/workflows/ci.yml`)

**Tetikleyiciler:** `push -> main`, `pull_request` (tüm dallar), `workflow_dispatch`. `concurrency` ile aynı ref'te eski koşular iptal edilir. `permissions: contents: read`.

**Tek job (`ci`, ubuntu-latest, timeout 30 dk)** — ucuz kapılar önce, pahalı DB adımları sonra:

1. `actions/checkout@v4`
2. `actions/setup-node@v4` → **node-version: 24.19.0 sabit** (yerelde doğrulanmış sürümle aynı), `cache: npm`
3. `npm ci`
4. `npx tsc --noEmit`
5. `npm run lint:faz3`
6. `npm run test:unit` (36 test; integration hariç)
7. `supabase/setup-cli@v1` → `supabase start`
8. **Sağlık kontrolü:** container içinde `pg_isready` 60x2 sn poll; başarısızsa `::error::Supabase DB 120 saniye icinde hazir olmadı.`
9. **Teşhis adımı** (yalnız start/health fail ise): `supabase status --debug`, `docker ps -a`, db container logları (son 100 satır)
10. `supabase db reset` → temiz migration zinciri
11. **Zincir iddiası (SQL):** `schema_migrations` sayısı **71** (repoda 050 yok), `version='072' name='subjects_read_grant'` varlığı, `authenticated -> subjects SELECT` izni VAR, `anon -> subjects SELECT` izni YOK; ihlalde `MIGRATION_CHAIN_FAIL` / `GRANT_FAIL` exception ile step başarısız
12. **SQL QA süitleri:** her süit `docker cp` + `psql -v ON_ERROR_STOP=1 -q -A -t`
    - Faz 3 *self-raising*: exit code + `QA FAZ 3 TAMAM: kalan=0` marker'ı zorunlu
    - Faz 1/2 *parsed*: exit code + çıktıda `|FAIL|` satırı yok + son satır `toplam|gecen|kalan` özeti ve `kalan=0 ve gecen=toplam`
13. **Paralel sayaç probe'u:** iki ayrı `docker exec` süreci bash `&` + `wait` ile gerçek işletim sistemi paralelliğinde
    - setup → SETUP_OK; `work TAG=a // TAG=b` → FINAL_USED; verify DO bloğu (kişi başı <=500 ve sayaç==exposure, aksi halde exception) → VERIFY_PASS; cleanup → CLEANUP_OK
    - Ardından aynı döngü `same` moduyla (iki işçi AYNI kullanıcının sayacına yarışır — Faz 2 F-2 senaryosu) ve ikinci cleanup
14. `npm test` (integration dahil — çalışan Supabase üzerinde gerçek RPC akışı)
15. Summary echo

## 3. Yerel Doğrulama Sonuçları (CI adım sırasıyla)

| # | Adım | Sonuç |
|---|---|---|
| 1 | `npm ci` | BASARILI — 581 paket, 28 sn (bilinen zararsız esbuild/unrs-resolver postinstall uyarıları) |
| 2 | `npx tsc --noEmit` | BASARILI — 0 hata |
| 3 | `npm run lint:faz3` | BASARILI — 0 hata/uyarı (PowerShell'de tırnaklı globlar da sorunsuz) |
| 4 | `npm run test:unit` | BASARILI — 4 dosya / 36/36 (integration doğru şekilde hariç) |
| 5 | Sağlık kontrolü (`pg_isready`) | BASARILI — deneme 1'de hazır |
| 6 | `npx supabase db reset` | BASARILI — 001→072 zinciri temiz uygulandı (050 mevcut değil; seed.sql uyarısı bilinen zararsız gürültü) |
| 7 | Zincir iddiası | BASARILI — pozitif yol `CHAIN_OK` exit=0; negatif yol da test edildi: beklenti 72'ye çevrilince `MIGRATION_CHAIN_FAIL: ... bulunan 71` exit=3 |
| 8 | Faz 1 QA (CI ayrıştırma mantığıyla) | BASARILI — `34|34|0`, `|FAIL|` yok |
| 9 | Faz 2 QA | BASARILI — `49|49|0` |
| 10 | Faz 3 QA | BASARILI — exit=0 + `QA FAZ 3 TAMAM: kalan=0` |
| 11 | Probe farklı-kullanıcı (`work a+b paralel`, Start-Job = ayrı süreçler) | BASARILI — FINAL_USED=500 / 500; verify: C 500/500 PASS, D 500/500 PASS |
| 12 | Probe aynı-kullanıcı (`same a+b paralel`) | BASARILI — paylaşılan sayaç 500'de kaldı; verify PASS (sayaç==exposure atomikliği) |
| 13 | `npm test` tam paket | BASARILI — 5 dosya / 38/38 (integration: gerçek RPC akışı + kalıntı sıfır) |
| 14 | YAML sözdizimi (`yaml-lint`) | BASARILI — docker cp düzeltmesinden sonra yeniden doğrulandı |

### Döngüde yakalanan ve düzeltilen hatalar

1. **Teşhis koşulu dar:** başlangıçta yalnızca `sbstart` failure'ında tetikleniyordu; sağlık kontrolü failure'ını da kapsayacak şekilde genişletildi (`steps.sbhealth.conclusion` eklendi).
2. **`docker cp` hedef yolu:** `/tmp/$file`, container'da olmayan `scripts/` alt dizinine kopyalamaya çalışacaktı (CI Linux'ta mutlak hata; yerel testim basename kullandığı için yakalanmamıştı). `basename` ile `/tmp/<dosya>` olarak düzeltildi; düzeltilmiş mantık Faz 2 ile yerelde tekrar doğrulandı.
3. **Migration sayısı sabiti:** ilk taslakta 72 yazılmıştı; gerçek zincir 71 (050 numaralı dosya repoda hiç var olmamış). Sabit düzeltildi + isim tabanlı ek kontrol (`version='072' AND name='subjects_read_grant'`) eklendi; hem pozitif hem negatif yol yerelde kanıtlandı.

---

## 4. Linux/Windows Farklarının Çözümü

| Risk | Çözüm |
|---|---|
| PowerShell bağımlılığı | Workflow %100 POSIX bash; paralellik `&`/`wait` ile OS süreç seviyesinde (PowerShell Start-Job yalnızca yerel eşdeğer doğrulamada kullanıldı) |
| Container adı | `project_id=yarisma-programi` config.toml'dan okundu; `CONTAINER=supabase_db_yarisma-programi` env (CI'da CLI aynı adlandırma kuralını izler) |
| psql erişimi | Host'a psql kurulumu gerekmez; tüm SQL container içinden `docker exec` ile (yerelde doğrulanmış yolun aynısı) |
| `npx` / `.cmd` çözümleme | Integration testindeki `shell:true` spawn'lar Linux'ta da geçerli; vitest tam paketi CI'da integration dahil koşar |
| Node sürüm sapması | setup-node ile 24.19.0 pinli (lockfile ile uyumlu; yereldekiyle aynı) |
| Bağımlılık kurulumu | `npm ci` ile lockfile bütünlüğü zorunlu; cache yalnızca setup-node npm cache'i (lockfile hash anahtarlı, standart ve güvenli) |
| Secret gereksinimi | Yok — yalnız local Supabase varsayılan geliştirme anahtarları; `setup-cli` token istemez |

## 5. Kalan Riskler

1. İlk gerçek GH Actions koşusu yerelde birebir koşturulamaz: `supabase start`'ın runner üstündeki imaj çekme süresi (~2 GB) ve CLI sürüm kayması (`latest`) ilk push'ta gözlemlenmeli; istenirse `version:` ile pinlenir.
2. Faz 1/2 çıktı ayrıştırması metinseldir (`|FAIL|` taraması + son satır özeti); detay metninde literal `|FAIL|` geçmesi teorik yanlış-pozitif üretir (süit formatı değişmedikçe risk yok).
3. Probe `work` modunda başlıktaki `used_c+used_d==560` iddiası assert EDİLMEZ: gözlenen davranış (500+500, kullanıcılar arası soru paylaşımı) önceki kabul edilen yerel sonuçla aynı; bağlayıcı invariant verify DO bloğudur (<=500 ve sayaç==exposure). Başlık yorumu ile davranış farkının netleştirilmesi ayrı iş.
4. `db reset` çıktısındaki `WARN: no files matched pattern: supabase/seed.sql` bilinen zararsız gürültü (repo seed kullanmıyor).
5. Repo genelinde ESLint hâlâ kapsam dışı: pre-existing ihlaller (`scripts/import-legacy-excel.ts`, `src/ai-worker/*`) bilinçli olarak kapsam dışı; kapsam büyütme kararı ayrı iş.
6. Integration testi Docker soketine bağlıdır; GitHub hosted runner'larda Docker hazır olduğu için sorun beklenmiyor, self-hosted runner'da Docker ön şarttır.
7. `@types/node@^20` typings vs Node 24 runtime: mevcut durumda sorunsuz; ileride tip hatası çıkarsa `@types/node` major sürümü yükseltilmelidir.

## 6. Git Durumu (commit/push ÖNCESİ, rapor yazımı anı)

```
 M package.json          (+3 satır: lint:faz3, test:unit)
?? .github/              (workflows/ci.yml — yeni)
?? docs/reports/latest-ci-validation.md  (bu rapor)
?? .opencode/            (bilinçli dışlandı — commit edilmeyecek)
?? opencode.json         (bilinçli dışlandı)
?? supabase/snippets/    (bilinçli dışlandı)
```

Commit adayı: `.github/workflows/ci.yml`, `package.json`, `docs/reports/latest-ci-validation.md`.

## 7. Teyit

- Git commit / push / reset / checkout YAPILMADI; çalışma ağacı yukarıdaki durumdadır.
- Production Supabase'e bağlanma, link, login ve db push YAPILMADI — tüm DB işlemleri yerel Docker stack üzerindedir.
- `.env`, anahtar/secret dosyaları, `.opencode/`, `opencode.json`, `supabase/snippets/` ve `scripts/import-legacy-excel.ts` dosyalarına DOKUNULMADI.
- 001–072 migration dosyaları ve uygulama davranışı DEĞİŞTİRİLMEDİ (yalnızca CI yardımcı scriptleri + package.json test scriptleri).


