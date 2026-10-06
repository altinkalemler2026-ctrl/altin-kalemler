# DEV-ENV-02B — Port Hizalama ve Test Keşfi Kapanış Raporu

- **Tarih:** 2026-10-06
- **Faz:** DEV-ENV-02B — DEV-ENV-02A raporundaki O1 hizalama + K6/K7 keşfi kapanışı
- **Öncül:** DEV-ENV-02A raporu — `ROOT_CAUSE: B`, O1 önerisi, K6, K7 verildi.
- **Yasaklara uyum:** `supabase start/stop/restart/reset/db push` YOK; Docker
  restart/prune YOK; ana DB'de SQL/fixture/migration yazımı YOK; `supabase
  status -o env` okunmadı; `.env*`, token/key/parola okunmadı; yalnız hedef
  portlar için yazmasız TCP/HEAD kontrolü ve salt-okunur keşif koşumları
  yapıldı; entegrasyon testleri anal stack'e karşı KOŞULMADI (yalnız
  ölü-hedef skip koşumu yapıldı: `beforeAll` başında erken dönüş → DB/docker
  dokunuşu yok).

## 1. DEĞİŞEN TAM DOSYA LİSTESİ

| Dosya | Değişiklik |
|---|---|
| `supabase/config.toml` | 6 port değeri 55321 ailesine hizalandı; `[db]` değişmedi |
| `vitest.config.ts` | `exclude` glob `src/**/integration.local.test.ts` → `src/**/*.local.test.ts` |
| `src/lib/admin/review-actions.integration.local.test.ts` | Skip guard erken kesinleşme: `HEAD /rest/v1/` probe'u `beforeAll`'dan modül üstüne taşındı |

Fazın `git status --porcelain` farkı yalnız bu 3 dosya (+ bu rapor) içerir;
kullanıcının 45+ modified/untracked dosyasına dokunulmadı.

## 2. ESKİ ↔ YENİ PORT TABLOSU

| Ayar | Eski | Yeni | Not |
|---|---|---|---|
| `[api] port` | 54321 | **55321** | Çalışan kong `0.0.0.0:55321`, ölçülmüş |
| `[db] port` | 54322 | **54322 (SABİT)** | Çalışan db 54322 healthy, değişmedi |
| `shadow_port` | 54320 | **55320** | db diff için yalnızlıkta boş port; aile hizalaması |
| `[db.pooler] port` | 54329 | **55329** | pooler `enabled=false`; 02A O1 değeri |
| `[studio] port` | 54323 | **55323** | Çalışan studio 55323, ölçülmüş |
| `[local_smtp] port` | 54324 | **55324** | Çalışan inbucket 55324, ölçülmüş |
| `[analytics] port` | 54327 | **55327** | Çalışan analytics 55327, ölçülmüş |

`project_id`, migration/seed, secret/env aboneleri (env(...) şablonları)
hiçbirini içermeyen tüm diğer ayarlar değiştirilmedi (git diff ile doğrulandı);
TOML-port kontrol scripti: `TOML-PORT-KONTROL: OK` (7/7 eşleşme).

## 3. K6/K7 KARARI VE KANITI

### K6 — normal unit/full koşumda entegrasyon dosyalarının toplanması

Ön-kanıt (düzeltmeden önce 02B'de yeniden ölçüldü):
- `npx vitest list --filesOnly` (env yok) → **yalnız**
  `review-actions.integration.local.test.ts` toplanıyordu. training/analytics
  dosyaları base adları birebir `integration.local.test.ts` olarak
  `src/**/integration.local.test.ts` pattern'ine eşleşiyor; review-actions dosyasının
  base adı `review-actions.integration.local.test.ts` olduğundan eşleşmiyordu.
- `E2E_DB_CONTAINER` set iken 3 dosya da toplanıyordu (disposable koşuma
  doğru).

Post-kanıt (düzeltmeden sonra):
- env **yok** → 0 `.local.test.ts` dosyası toplanıyor (yanlış toplama kaldırıldı;
  tam koşum keşfi 79 dosya — local.test yok)
- `E2E_DB_CONTAINER` var → 3 dosya toplanıyor (disposable/CI açıkça çağrılabilir)

### K7 — skip guard'ın geç değerlendirilmesi

`it.skipIf(shouldSkip)` koleksiyon (modül yükleme) anında değerlendirilir.
Eski kodda `beforeAll` içindeki `HEAD /rest/v1/` probe'u `shouldSkip = true`
yapıyordu — fakat skipIf çoktan işlenmiş olduğundan testler çalışıp ağ
hatasıyla düşüyordu (02A'da gözlenen 'TypeError: fetch failed' biçimli 9 hata).
Düzeltme: probe üst düzeye (modül kapsamına, top-level `await`) taşındı;
hedefe erişilemiyorsa `shouldSkip` test tanımlarından ÖNCE kesinleşir.
`beforeAll` yalnız `if (shouldSkip) return` + fixture akışını içerir; skip
durumunda fixture/auth/docker yazımı hiç başlamaz (afterAll benzer).

Post-kanıt: dummy `E2E_API_URL=http://127.0.0.1:54321` + dummy `E2E_ANON_KEY`
+ dummy `E2E_SERVICE_KEY` + dummy `E2E_DB_CONTAINER` ile
`npx vitest run src/lib/admin/review-actions.integration.local.test.ts`:

```
Test Files 1 skipped (1)
Tests 9 skipped (9)   Duration 1.75s
```

9 test skip edilir; fixture/docker/psql dokunulmaz; hata YOK.

Not: bu koşum "ana stack'e karşı gerçek entegrasyon koşumu" DEĞİLDİR — hedef
ölü port (54321) idi ve skip yolu erken döndü. Gerçek koşum yapılmadı (yasak).

### Ek discovery/port senaryoları

- TCP kanıt: `127.0.0.1:54321 => False`, `127.0.0.1:55321 => True` (faz başı
  ve sonu aynı; hedef yüzey canlı).
- `docker ps` (yarisma-programi): yalnız db (54322 healthy) + kong (55321
  healthy) — değişiklik yok.

## 4. STACK / DB / GIT DEĞİŞMEZLİK KANITI

- HEAD: faz başı ve sonu `a3710fc` (main) — commit bu fazın данışmasıyla
  yalnız faz SONUNDA ve yalnız istek üzerine yapılacaktır.
- `docker ps` faz başı = faz sonu (yukarıdaki satırlar birebir aynı).
- Ana DB'ye docker exec/docker cp/sql yazımı yok.
- Kullanıcın modified/untracked dosyalarına dokunulmadı.

## 5. ANA STACK'E GERÇEK ENTİGRASYON TESTİ KOŞULMADI

- `review-actions.integration.local.test.ts` gerçek RPC yazma senaryoları
  **koşulmadı**. Yalnızca yazmasız `HEAD /rest/v1/` probe'lu skip koşumu
  (ölü-hedef h. 9 skipped / 0 failed) yapıldı.
- Keşif kanıtları `npx vitest list --filesOnly` ile alındı (test koşumu yapmayan
  keşif komutu).

## 6. SAFE_FOR_LOCAL_TEST_ENV

`SAFE_FOR_LOCAL_TEST_ENV: YES`

- `npm test` / `vitest run` (E2E env set�cati, yerel): `.local.test.ts`
  dosyaları toplanmıyor (keşif kanıtı: 0) → normal koşum ana stack'e
  entegrasyon yazması yapmıyor; 79 dosya unit suite keşifte sağlıklı.
- `E2E_DB_CONTAINER` set iken 3 dosya keşfediliyor; hedef URL
  `E2E_API_URL`/`E2E_ANON_KEY`/`E2E_SERVICE_KEY` mevcutsa override geçerli;
  yoksa `supabase status -o env` (02A K5) — O1 sonrası config artık gerçek
  stack ile uyumlu (55321) → yanlış hedef yok.
- Çalışan stack + config ölçülmüş portlar hizalandı; ana DB'ye yazım yok.
- CI: fresh runner'da `supabase start` config'ten 55321'de stack başlatır;
  `supabase status` config=realite; exclude env set → üç entegrasyon dosyası
  açıkça koşar → CI davranışı değişmez.
- Kullanıcı dosyalarına, ana DB'ye, git geçmişine dokunma yok.

## 7. ÖNERİLEN COMMIT KÜMESİ

Tek commit; mesaj: `fix(dev): align local Supabase ports and test discovery`

Dosya kümesi:
- `supabase/config.toml` — api/studio/smtp/analytics/pooler/shadow 55321-ailesi
  ölçülmüş değerler; `[db] port = 54322` sabit (02A `ROOT_CAUSE: B` + O1)
- `vitest.config.ts` — exclude glob `src/**/*.local.test.ts` (K6: review-actions
  base adı önceki glob'a eşleşmiyordu)
- `src/lib/admin/review-actions.integration.local.test.ts` — K7: skip karar
  zamanı düzeltmesi, probe modül üstüne await olarak taşındı; beforeAll yalnız
  fixture akışı
- `docs/reports/dev-env-02b-port-hizalama-ve-test-kesfi-kapanis-raporu.md`

## 8. KAPSAM DIŞI NOTLAR

- training/analytics entegrasyon dosyalarında aynı K7 pattern'i (probe
  beforeAll'da) hâlâ mevcut; yerel keşifte dosyalar exclude edildiği ve CI'da
  gerçek stack mevcut olduğu için etkilenmiyorlar — kullanıcı onayıyla aynı
  kalıbın uygulanması ayrı faz olarak önerilir.
- `supabase_vector_yarisma-programi` crash-loop durumu değişmedi (önceden var;
  bu fazın kapsamına girmiyor).

## KAPANIŞ

Faz tamamlandı: O1 uygulandı (6 port, `[db]` sabit), K6/K7 en küçük değişiklik
setinde düzeltildi ve koşumla doğrulandı (K7: 9 skipped; K6: env yokken 0
toplanma, env setken 3 toplanma); tsc --noEmit 0, lint:faz3 0, git diff --check
0, TOML-port kontrol OK. Commit yalnız açık kullanıcı isteğiyle bu raporun
tetiklendiği mesajla yapılır; push ayrı onay + CI (completed/success) şartına
tabidir.
