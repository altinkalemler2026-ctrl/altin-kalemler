# AK-SEC-GRADE-01 — Sınıf seviyesi yetki açığı (GAP-SEC-01) izole onarım raporu

**Tarih:** 2026-11-19 · **HEAD:** `f3ba037` (main; commit/push YOK) · **Canlı migration:** 165 (dokunulmadı)
**Kaynak:** AK-GIT-CHECKPOINT-03 §3 GAP-SEC-01 · **Mod:** güvenlik incelemesi + izole çözüm + doğrulama
**Sonuç:** İZLEK ONARIM **PASS** · Dört aile **YEŞİL** · Canlı uygulama **YAPILMADI** (açık onay gerekir) → **GÜVENLİ DUR**

---

## 1. GAP-SEC-01 kesin kök nedeni

Kök neden zinciri (bu fazda dosya satırı + ölçümle kesinleştirildi):

1. `001_auth_foundation.sql` `authenticated`'a `student_profiles` üzerinde **tablo-seviyeli**
   SELECT/INSERT/UPDATE verir; `update_own` RLS politikası (001:40-45) yalnız **SATIR**
   kapsar (`USING/WITH CHECK (auth.uid() = id)`) — kolon kapsamı yok.
2. `066_fix_student_profiles_grants.sql` aynı tablo-UPDATE'i idempotent olarak tekrarlar.
3. `093_student_profile_grade_update_hardening.sql` sözleşmeyi doğru sertleştirir:
   tablo UPDATE REVOKE + yalnız `GRANT UPDATE (nickname)` (kolon). Diskteki 093'te
   `grade_level` kolon grant'i **yoktur** ve guard trigger **yoktur** (repo geneli grep
   negatif) — 093'ün tasarımı ayrıcalık katmanındadır.
4. **Çelişkinin kalbi — 157 §6 guard'ı** (`157_sec2_schema_privilege_hardening.sql`):
   `has_table_privilege('authenticated','student_profiles','UPDATE') = true` ister.
   PostgreSQL'de tablo yetkisi sorgusu **kolon yetkisini karşılamaz** (≤131'de `false`
   ölçülü; bu fazda `qa_asg01_repro`/`ctl` ölçümleriyle tekrar doğrulandı). Hook'suz
   temiz zincirde 157 fail-closed düşer.
5. Bu yüzden temiz kurulum önkosul adımı
   `scripts/qa-clean-install/hook_after156_write_matrix_baseline.sql` (satır 30-42),
   `pg_policies`'ten türeterek **tüm** authenticated-yazma-politikalı 63 tabloya
   tablo-genel INSERT/UPDATE/DELETE verir. Bu, 093'ü **fiilen iptal eder**:
   - `student_profiles`: tablo UPDATE dirilir → öğrenci kendi `grade_level`'ını
     değiştirebilir (Altın Kalem sınıf kapısı baypası).
   - `student_loadouts`: 108'in "authenticated = SELECT only, yazma yalnız RPC"
     sözleşmesi delinir (095 RPC-only sınırının ihlali). Tohum: 017'nin
     `student updates/inserts own loadout` INSERT/UPDATE politikaları.
6. Aynı durum **canlıda** da vardır (modül-dönemi manuel GRANT ALL mirası; §2).

Önceki checkpoint'lerdeki iki eksik düzeltildi:
- Canlıdaki `grade_level` "kolon granti" aslında **tablo-genel `arw`** yetkisinden
  gelen `has_column_privilege=true` yanıltmasıdır; canlı kolon ACL kaydında yalnız
  `nickname:UPDATE` vardır (§2 ölçümü).
- 017 loadout INSERT/UPDATE **politikaları**, hook geri alınsa bile her temiz
  kurulumda yazma yetkisini yeniden tohumlar; politika kaldırılmadan konverjans kalıcı olmaz.

## 2. Canlı ortamda salt-okunur yetki kanıtı

Yalnız katalog sorgusu; canlı öğrenci kaydına hiçbir UPDATE denenmedi.
Ölçüm: `supabase_db_yarisma-programi`, 2026-11-19 (`out/canli_kanit.txt`):

```
CANLI profiles relacl=authenticated=arw/postgres|postgres=arwdDxtm/postgres|service_role=arwdDxtm/postgres
CANLI loadouts relacl=authenticated=arw/postgres|postgres=arwdDxtm/postgres|service_role=arwdDxtm/postgres
CANLI col:nickname=authenticated:UPDATE
CANLI auth_table_update=true auth_col_grade=true auth_col_nick=true loadouts_update=true
```

→ Canlıda öğrenci rolünde `grade_level` yazılabilir durumdadır ve loadouts üzerinde
doğrudan UPDATE yetkisi vardır. **Canlı hâlâ ihlallidir; bu fazda düzeltilmedi (§12).**

## 3. Çözüm alternatiflerinin güvenlik karşılaştırması

| Kriter | **A — Post-konverjans Migration 166 (SEÇİLDİ)** | B — Guard trigger (BE 093) | C — RPC-only tam REVOKE |
|---|---|---|---|
| Öğrenci grade değiştiremez | ✔ Ayrıcalık katmanı (42501) | ✔ ama P0001; SQLSTATE sözleşmesi bozuk (testler 42501 ister) | ✔ |
| T-00a "tablo UPDATE YOK" / T-00c kolon matrisi | ✔ Birebir ≤131 sözleşmesi | ✘ Yetki durur, trigger maskeler | ✔ |
| Meşru nickname güncellemesi (T-01, H04a, app `update({nickname})`) | ✔ Kolon grant'i korunur | ✔ | ✘ Yeni RPC yüzeyi açmayı gerektirir (ürün kararı yok) |
| 157 §6 + hook sözleşmesi | ✔ Korunur (157 166'dan önce koşar; hook 157 önkosuludur) | ✔ | ✘ Hook'suz 157 zaten düşüyor; ayrı revizyon ister |
| SECURITY DEFINER / claims sezgisi | Yok (093'ün reddettiği yüzeyler) | Trigger sırası + rol sezgisi riski | RPC yüzeyi genişler |
| Hook tohumu (017 politikaları) | ✔ 4b ile kurutulur (kalıcı) | ✘ Tohum durur, next hook re-grant eder | ✘ Aynı sorun |
| service_role/admin yolu | ✔ Değişmez | ✔ | ✔ |
| Geçmiş migration değişikliği | Yok (FORWARD ONLY) | Yok | 093/108 revizyonu ister |

Ek reddedilen seçenek: **hook'u student_profiles'a kapatmak** → 157 §6 hook'suz zinciri
kırar (görev uyarısı: "157, 166'dan önce kırılıyorsa saklama" — ölçüldü: hook'suz 157
§6/§C düşer; bu yüzden hook AYNEN korundu, ek hook düzeltmesine gerek kalmadı ve bunun
güvenlik gerekçesi 166 başlık bloğunda belgelendi).

## 4. Seçilen çözüm ve gerekçesi

**Migration 166 `student_profile_write_convergence` (taslak — canlıya UYGULANMADI):**
zincir sonunda iki tabloyu zincirin kendi istediği fail-closed sözleşmeye (≤131 yeşil
durumu) konverje eder ve **tohumu kurutur**:

- `student_profiles`: tablo UPDATE/DELETE revoke (authenticated+anon); kolon yazma
  allow-list'i **yalnız** `nickname/UPDATE/authenticated`; tablo INSERT (signup
  `insert_own`) + SELECT korunur; RLS politikalarına dokunulmaz.
- `student_loadouts`: tablo I/U/D + kolon yazma kayıtları sıfırlanır (SELECT kalır,
  108 UI yolu); 017 `student updates/inserts own loadout` INSERT/UPDATE politikaları
  **DROP** edilir (hook re-grant tohumu — 157 §C paritesi 62==62 kalır).
- 5 fail-closed assert bloğu (ACL, kolon allow-listi, RPC-only sınırı, service_role
  yolları, 157 meşru yazma yolları geri-sarma dedektörü, RLS+politika sayıları, **§C
  paritesinin son durumda da sürdüğü**).
- İdempotent (yalnız ACL'de ölçülen hedefe REVOKE) + `FINAL_166 OK` + history kaydı.

Gerekçe: 093'ün belgelediği tasarım kararı (ayrıcalık katmanı > trigger/RPC), 157/hook
sozleşmelerinin bozulmadan korunması, CI'ın dinamik sayaçları sayesinde altyapı
değişikliği gerektirmemesi ve en küçük güvenli değişiklik.

**Audit notu:** her iki tabloda `relforcerowsecurity=false` (≤131'den beri böyle; RPC
sahibi owner-pass'ı buna bağlı). FORCE RLS eklemek ayrı ürün/mimari kararına bağlı bir
sertleştirme olduğundan 166 KAPSAMINA BİLİNÇLİ ALINMADI; 166 5f assert'ı RLS'in
kapalıya döndürülmesini engelleyecek şekilde daraltıldı.

## 5. Değişen dosyalar (tam liste)

| Dosya | Durum |
|---|---|
| `supabase/migrations/166_student_profile_write_convergence.sql` | **YENİ (taslak, uygulanmamış)** · SHA-256 `5d8296ba10634902d1efffb2b2cd2978d40bb42f3b78d4028db2de81ca7fbe26` |
| `docs/reports/ak-sec-grade-01-sinif-yetki-acigi-onarimi.md` | YENİ (bu rapor) |
| Başka hiçbir repoda içerik değişikliği YOK | Tarihî migration'lar `git diff --ignore-cr-at-eol` ile **temiz**; `src/lib/supabase/types.ts` dokunulmadı (SHA `80435cb2…d097`, 12786 satır, checkpoint-03 kaydıyla birebir); checkpoint-03'ün 3 QA suite dosyası + checkpoint-03 raporu aynı hâlde duruyor (o fazın teslimi) |

Kanıt scriptleri (bu görev, izole): `/tmp/opencode/asg01/` (`10_build.sh`, `chain_asg01.sh`,
`15_acl_evidence.sql`, `20_run.sh`, `30_negatives.sql`, `40_battery.sh`, `50_proof.sh`,
`60_reg165.sh`, `out/`).

## 6. Migration 166 taslağı SHA-256

`5d8296ba10634902d1efffb2b2cd2978d40bb42f3b78d4028db2de81ca7fbe26`
(`supabase/migrations/166_student_profile_write_convergence.sql`, 284 satır; git'te untracked)

## 7. Dört eski test ailesinin sonucu

Aynı DB'de before/after (`qa_asg01_repro`, 001–165 taze kurulum → 166 uygulanması):

| Suite | 001–165 (önce) | 001–166 (sonra) | Sonra (fresh `qa_asg01_full` pili) |
|---|---|---|---|
| grade093 | ❌ 13/23 (T-00a, T-00c, T-02, T-03a/b, T-07, T-08, T-09, T-10c/d) | ✅ **23/23** | ✅ 23/23 |
| boundary095 | ❌ 38/42 (B-01, B-02, E-01, E-03) | ✅ **42/42** | ✅ 42/42 |
| faz10 | ❌ 22/26 (P-06/07/08, V-08) | ✅ **26/26** | ✅ 26/26 |
| scoring094 | ❌ rc=3 (E-46→E-49 kaskadı) | ✅ **53/53** | ✅ 53/53 |

Önce/sonra ACL kanıtı (`qa_asg01_repro`): `authenticated=arw` → `ar` + `nickname`
kolonu; `loadouts authenticated=arw` → `r`; öğrenci grade denemesi
`GRADE_UPDATE=ALLOWED (ACIK!)` → `DENIED sqlstate=42501`.
Testlerde **hiçbir gevşetme/skip yok**; dört ailede ürün kaynaklı ek hata bulunmadı.

## 8. Saldırgan rolüyle negatif test kanıtları (`qa_asg01_full`, 001–166)

| # | Senaryo | Sonuç |
|---|---|---|
| N-1 | `authenticated` kendi `grade_level`'ını değiştirir | **PASS 42501** |
| N-2 | `authenticated` başka öğrencinin `grade_level`'ını değiştirir | **PASS 42501** |
| N-3 | Meşru öğrenci nickname günceller | **PASS row_count=1** |
| N-4 | Yönetim yolu (`service_role`) grade günceller | **PASS row_count=1** (sonra geri alındı) |
| N-5a/b | `anon` profiles UPDATE / loadouts INSERT | **PASS 42501 / 42501** |
| N-6a-c | `authenticated` loadouts INSERT/UPDATE/DELETE doğrudan | **PASS 42501 ×3** |
| N-6d | SECURITY DEFINER yetki genişetmez: `get_internal_correct_answer` öğrenciye kapalı | **PASS 42501** |
| N-7 | Envanter: `rls_profiles=true force=false policies=4` · `rls_loadouts=true force=false policies=1` · relacl `authenticated=ar` / `authenticated=r` | kaydedildi |
| N-8 | Meşru RPC `select_own_avatar('character_1')` çalışır, grade'i DEĞİŞTİRMEZ (5→5) | **PASS** |

## 9. 001–165 ve onarım zinciri temiz kurulum sonuçları

- `qa_asg01_repro` = stok ADP tohum + ADP parite + hook 155/156 + **001–165** (161 dosya):
  `uygulanan=161 hist=161 max=165 dup=0`, PRE156/PRE157 OK, FINAL_162–165 OK → kırmızı
  durumun bağımsız yeniden üretimi (checkpoint-03 ile birebir sınıflar).
- `qa_asg01_full` = aynı yöntemle **001–166** (162 dosya): `uygulanan=162 hist=162
  max=166 dup=0`, `ADP_PARITY_OK`, `PRE157_BASELINE_OK policy=63 writable=63`,
  **FINAL_166 OK** dahil FINAL_162–166 OK. 166 idempotence ek koşumu repro'da tekrar
  `FINAL_166 OK` üretti.
- CI replika pili `qa_asg01_full` üzerinde (ci.yml parse semantiği, 18 suite + 2 probe):
  **BATTERY_RESULT FAILS=0** — faz1 34/34 · faz2 52/52 · faz3 self-raising · faz35 24/24 ·
  faz4 22/22 · faz5 15 PASS/0 FAIL · grade093 23/23 · scoring094 53/53 · boundary095
  42/42 · faz6 31/31 · faz10 26/26 · faz10b 54/54 · faz11 41/41 · scoring127 48/48 ·
  faz30d1 32/32 · qgate122 19 PASS · faz35b 42 PASS · role_mgmt 35 PASS · faz2 paralel
  sayaç + faz4 rate-limit probe'ları OK.

## 10. M1–M7 ve kota 165 regresyonu

- **M1–M7:** 7/7 PASS, `PRIVILEGE AUDIT TEMIZ`, **DIGEST
  `3509ab094790b4aaa4f9b03533a5b50ba25607e0d208d0cdd612f39a4df10fc0`** — checkpoint-02/03
  CI-replika temeli ile **birebir** (166, digest kapsamdaki questions/lig nesnelerine dokunmaz).
- **164 RPC fingerprint'leri değişmedi:** `uretim_planlayici_list_vaults`
  `b1ded12a16d4c40dea8ac3c247ecf940` · `uretim_planlayici_list_vault_stock`
  `3f3f481e8aa7201a339bd091be74a043` (anıtla birebir).
- **165 kota regresyonu (onarım zincirli `qa_asg01_repro`):** fixture OK ·
  qa165_suite **50/50** · eşzamanlı **S6=PASS S7=PASS** (40/40 kota kapısı concurrent) ·
  negatif re-apply NEG_162/NEG_163/NEG_165 GUARD abort OK · dup=162 max=166.
- **Migration dosya SHA-256 (162–165):** checkpoint-01/02/03 anıtlarıyla birebir
  (`e2093b55…`, `300d1e87…`, `780cc250…`, `655b5103…`); zincirin tamamı
  `git diff --ignore-cr-at-eol` ile değişmemiş.

## 11. CI entegrasyonuna etkisi

- `ci.yml` zincir adımı dosya sayısını ve son sürümü **dinamik** okur (satır 137,
  192-193) → 166 dosyası eklendiğinde CI değişikliği gerekmez; 166 zincir sonunda
  koşar, 157 kendi adımında hook grant'iyle geçmeye devam eder.
- Tip drift guard'ı: 166 kolon/tablo şeması DEĞİŞTİRMEZ (yalnız ACL/policy) →
  `supabase gen types` çıktısı etkilenmez.
- SECURITY_INVARIANT (ci.yml): 001–166 üzerinde `SECURITY_INVARIANT_OK`.
- qa_sec157 CI'da değildir; yine de koşildi: **pre-166 (001–165) 25 PASS/2 FAIL =
  post-166 25 PASS/2 FAIL** (aynı iki test) → 166 regresyonu YOK; 166 sonrası H08c
  parite testi 62==62 ile PASS. Kalıcı iki失败 166-öncesi mevcut GAP'lerdir:
  - **GAP-SEC-G02 (YENİ kayıt):** temiz zincirde `student_visibility_settings`
    `authenticated=aw` (SELECT yok; 156/157 asgari yetki) → `INSERT … ON CONFLICT
    (user_id) DO NOTHING` arbiter çıkarımı 42501 verir (SELECT verildiğinde geçti —
    mekanizma ölçüldü). Canlı `arw` olduğundan suite tarihî olarak yeşildi; `src/`'te
    bu ifadeyi kullanan akış bulunamadı. Düzeltmi bu fazın kapsamı dışında (ayrı karar).
  - **H09:** qa_sec157 taban-veri beklentisi canlı-dönemi (112 aday/36 kasa/249 görev)
    vs temiz kurulum (0/3690/0) — ortam varsayım uyuşmazlığı, 166 ile ilgisiz.
- **Önemli:** 166 commit/push'lanana kadar CI'da 4 suite bilinçli-kırmızı kalmaya devam
  eder (GAP-SEC-01 canlı zincirde duruyor).

## 12. Canlı uygulama için ön koşullar (BU FAZDA YAPILMADI)

1. **Açık kullanıcı onayı** (migration uygulaması + ACL daraltması canlıda).
2. Uygulama yöntemi: ana stack container'ında tek işlem (`BEGIN…COMMIT` dosyası hazır),
   `psql -v ON_ERROR_STOP=1` ile `166_student_profile_write_convergence.sql`;
   `FINAL_166 OK` beklenir (assert blokunu geçemeyen canlı = beklenmeyen drift → abort,
   hiçbir şey commit'lenmez).
3. Önce: katalog anlık görüntüsü (`pg_class.relacl`, `pg_attribute.attacl`, `pg_policy`
   dökümü) + `pg_dump --schema-only` yedeği.
4. Sonra (salt-okunur): §8 envanteri + M1–M7 + SECURITY_INVARIANT + `has_column_privilege`
   matrisi; davranış kanıtı **yalnız disposable klon** üzerinde (canlı ana stack'te QA
   suite'leri çalıştırılmaz — Altın Kalem protokolü).
5. Uygulama penceresinde app dumanı: kullanıcı kendi nickname'ini güncelleyebilmeli;
   admin sınıf güncellemesi service_role ile çalışmalı.
6. Geri alma planı: tek transaction REVOKE olduğu için başarısızlıkta otomatik geri alma;
   başarı sonrası acil geri dönüş = checkpoint-03 §2'deki GRANT'ların iadesi (önerilmez,
   yalnız acil durum).
7. Uygulama sonrası bu raporun §2 ölçümü tekrarlanmalı: `auth_table_update=false`,
   `auth_col_grade=false`, `loadouts_update=false` beklenir.

## 13. KARAR

| Alan | Durum |
|---|---|
| GAP-SEC-01 kök neden | **KESİN** (093 ⇄ 157 §6 çelişkisi + hook tohumu + 017 politika tohumu; canlıda aynı) |
| İzole onarım (001–166) | **PASS** — 166 FINAL assertion'ları dahil; 4 aile 23/23·42/42·26/26·53/53; negatifler N-1…N-8 PASS |
| CI replika pili (18 suite + 2 probe) | **PASS (FAILS=0)** |
| M1–M7 / SECURITY_INVARIANT / 164 md5 / SHA-162–165 | **PASS** (hepsi anıtlarla birebir) |
| 165 kota regresyonu | **PASS** (50/50 + S6/S7 + GUARD'lar) |
| Geçmiş migration dosyaları | **DEĞİŞMEDİ** (content-diff temiz); canlı DB **dokunulmadı** (yalnız salt-okunur) |
| Canlı GAP-SEC-01 | **AÇIK / GAP** — düzeltme taslakta; canlıda ihlal sürüyor (§2) |
| GAP-SEC-G02 (visibility ON CONFLICT) | **GAP** (166-öncesi mevcut, düşük öncelik, ayrı karar) |
| H09 (sec157 taban veri) | **GAP** (ortam varsayımı, bilgi) |
| types.ts / AdminNav | Bu görev kapsamı dışı; checkpoint-03 kayıtları geçerli (GAP-CI-03 / GAP-CI-01) |
| **W1 push (166 dahil commit) → CI** | **GO** — tek koşul: 166'nın commit'e dahil edilmesi (kullanıcı izni gerekir) |
| **Canlı 166 uygulaması** | **NO-GO** — §12 ön koşulları + açık kullanıcı onayı olmadan uygulanmaz |

**GÜVENLİ DUR.** Commit/push yapılmadı; canlıya dokunulmadı; bu görevin disposable
kaynakları (`qa_asg01_full`, `qa_asg01_repro`, `sec157_qa_asg01`, `sec157_qa_asg01pre` +
container `/tmp/asg01*`) silindi; `qa_aqs01_a/b` ve ana stack korundu; Docker envanteri
baseline ile aynı.
