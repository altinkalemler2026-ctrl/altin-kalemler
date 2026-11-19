# AK-GIT-CHECKPOINT-02 — 001–165 Temiz Kurulum ve CI Ön Kapısı

- **Faz:** AK-GIT-CHECKPOINT-02 (AK-GIT-CHECKPOINT-01 devamı)
- **Tarih:** 2026-11-17 (kosular 19:56–22:30 UTC+3)
- **Mod:** İzole QA + CI hazırlık doğrulaması; canlı DB salt-okunur
- **Bitiş durumu:** GÜVENLİ DUR — **ÖN KAPI AÇILDI (kurulum kanıtlı), CI yeşil kapısı GAP'li**
- **Kanıt klasörü:** `drafts/ak-git-checkpoint-02/` (40 dosya, bundle SHA-256[:16] `d9c9c87c1c606df3`)

## 0. Yönetici özeti

| # | Soru | Cevap | Kanıt |
|---|------|-------|-------|
| 1 | 001–165 hook'lu runner ile sıfır manuel ENV_REPAIR kuruluyor mu? | **PASS — 161/161** | §2 |
| 2 | `supabase db reset` (hooksuz) neden batıyor — kanıtlı mı? | **PASS — deterministik fail-closed reproduksiyonu** | §5.1 |
| 3 | En küçük güvenli CI düzeltmesi hazır mı? | **PASS — ci.yml dar yamalı + izole replikada birebir simüle** | §5.2–5.4 |
| 4 | Kota davranış regresyonu yeni kurulumda sağlam mı? | **PASS — 50/50 + eşzamanlı S6/S7 + GUARD'lar** | §4 |
| 5 | İlk W1 push'unda CI yeşil olur mu? | **HAYIR — GAP'ler var (legacy suite'ler, types, AdminNav)** | §6–7 |

## 1. Ön kontroller (salt-okunur)

- Git: HEAD `f3ba037` (main), dirty 689 — kullanıcı WIP'si değişmedi.
- Migration envanteri: 161 dosya; 162/163/164/165 SHA-256 checkpoint-01 ile birebir (`e2093b55…`, `300d1e87…`, `780cc250…`, `655b510396d0…d4e36`).
- Kanlı DB: `live_max=165 hist=148` — faz boyunca dokunulmadı (kosu oncesi/sonrasi ayni).
- Docker envanteri karsilastirmali alindi ve temizlik sonrasi **birebir ayni** (`DOCKER_ENVANTER_SABIT`).
- Onceki QA DB'leri `qa_aqs01_a/b` korundu (kosu oncesi/sonrasi envanterde).
- ≤131 zincir dosyalarinin **gercek icerik degisikligi YOK** (CR-normalize SHA: HEAD == calisma agaci; 62 CRLF grubu kozmetik) — W1 zamirsiz zincir icerigi = CI HEAD zinciri + 132–165.

## 2. Izole temiz kurulum — 161/161 PASS

### 2.1 Runner A: `scripts/qa-clean-install/clean_install.sh`
- Hedef: `qa_agc02_c165` (benzersiz disposable), container ici unix socket.
- Sonuc: `dosya_sayisi=161 beklenen=161` → **uygulanan=161 hist=161 max=165 dup=0** (~64 sn).
- On-kosul kancari zincire hok edilmis halde calisti: `PRE156_BASELINE_OK`, `PRE157_BASELINE_OK policy=63 writable=63`.
- `FINAL_162 OK`, `FINAL_163 OK`, `FINAL_164 OK`, `FINAL_165 OK` loglandi.
- **Sifir manuel ENV_REPAIR mudahalesi.**

### 2.2 Yapisanin 165 dogrulamasi (14/14 PASS) + YETKI
- 3 tablo + RLS+FORCE 3/3, yeni tetikler 5/5, eski 163 yarisma tetikleri 0, arsiv tetigi 1, `weekly_quota_status` KOTA_165_DEPRECATED 1, `weekly_quota_status_per_subject` auth=true/anon=false, `_q165%` iç fonksiyonlar authenticated'a kapali, bos dogus 0/0/0, 163 tablolari duruyor, CHECK(40/200) 3.
- `SET LOCAL ROLE authenticated` → **YETKI_165 fail-closed hati** attı.
- 164 RPC md5 anıtı: `b1ded12a…` / `3f3f481e…` (canlı ile ayni).

### 2.3 M1–M7 güvenlik sözleşmesi
- Runner A DB: 7/7 PASS, `PRIVILEGE AUDIT TEMIZ`, DIGEST `c58bf8ce…621c6f` (consistency-02 temiz kurulum tabani ile birebir).
- CI-replika DB (§5.3): 7/7 PASS, `PRIVILEGE AUDIT TEMIZ`, DIGEST `3509ab09…0fc0` — fark ADP+canli-bazli yazma matrisinden; matrisin kendisi TEMIZ.

## 3. Davranis regresyonu (yalniz izole QA) — PASS

Onceki QA kanitlari yeniden kullanildi (`qa163_fixture.sql` + `qa165_suite.sql` + `qa165_concurrency.sh`), yeni temiz kurulumda tekrar kosuldu:

- **qa165_suite: 50/50 PASS, FAIL=0** — Matematik 40/40 iken Fizik hakki acik; 41. yarisma reddi; ayni dersin zorluklari ortak kota; 200 yeni soru siniri; haftalik donem ayrimi; KOTA_165 hata sozlesmesi.
- **Eszamanli S6/S7: PASS** — paralel talepler kotayi asamiyor (41. istek `KOTA_165: … 40/40`).
- **Negatif re-apply:** NEG162 `GUARD_162`, NEG163 `GUARD_163`, NEG165 `GUARD_165` ile abort. **164 tasarim geregi idempotent** (`RE164` semantigi): re-apply basarili + md5 cercesi + tetikler + hist dup=0 korundu (consistency-02 §B5 karari ile tutarli — FAIL degil).
- Tutarlilik: hist=161 max=165 dup=0.

## 4. Migration zincir butunlugu — kanitlar

- Zincir 001→165 sirayla, her dosyada `supabase_migrations.schema_migrations` satiri runner tarafindan yazildi; duplicate=0.
- 132–165 untracked listede (34 dosya); ≤131 tracked + icerik olarak HEAD ile birebir (§1).
- 163 eski tablolari (`student_week_quota*`) temiz kurulumda da korunuyor.

## 5. CI entegrasyonu

### 5.1 `supabase db reset` neden basiniziz — KANITLI
hooksuz zincir kosusu izole DB'de deterministik olarak reprodukte edildi:
- 156 → `SEC1B fail-closed: service_role SELECT hakki kaybedildi` (hook #1 tabani olmadan).
- 157 → `157 fail-closed: _meshru insert_own/update_own yazma yollari kapandi` (hook #2 63-tablo matrisi olmadan).
- Hook geri yuklendiginde 156/157 tekrar basariyla uygulaniyor (hook'lar idempotent).
Ayni sınıf hata consistency-02 §4'te de loglanmisti. Ek kanit: canli history forensics — `supabase start` ilk-init adimi da migrasyonlari uygular (107–110 history kayitlari start ile eklenmisti); yani CI'da `start` adimi de hooksuz zincirle 156'da kirilir.

### 5.2 En küçük guvenli CI duzeltmesi (yalniz `.github/workflows/ci.yml`)
Yamali akis (23 adim, YAML gecerli):
1. **Yeni adim — "Shelve migrations before start":** `supabase/migrations/*.sql` → `/tmp/ci_migrations`. `start` stok yigini kurar, zincire hic dokunmaz (start'in ilk-init migrasyon adimi 156 tuzagina giremez). Migration dosyalari chain adimi sonunda geri konur (chain assert adimi repoyu dinamik okur).
2. **"Reset database" → "Apply migration chain with versioned hooks":** `supabase db reset` kaldirildi; chain assert adimi **degismedi** (161 beklentisini `ls`'ten dinamik uretir, 156'da patlamaz).
- **Fail-closed ilkeler:** yalniz docker-ici unix socket + tek hedef `DB=postgres` (CI konteyneri); URL/token/secret/hosted baglanti yok; env'den DB_URL okunmaz; DB create/drop yok; `CI_CHAIN_DONE` isareti olmadan step cokmezse CI kirmizi (exit-code discipline `set -euo pipefail`).
- Migration dosyalarina, guvenlik guard'larina veya CI testlerine dokunulmadi; test atlanmiyor.
- Ayni betigin referans kopyasi: `drafts/ak-git-checkpoint-02/ci_apply_chain.sh`.

### 5.3 CI replika simulasyonu (birebir)
`qa_agc02_ci` DB'si **CI gercekcosumune replike** edildi: taze DB + uzanti/sema on-kosullari + CLI gomulu **public ADP tohumu** (`ALTER DEFAULT PRIVILEGES … GRANT ALL … TO anon, authenticated, service_role` — CLI binary'sinden dogrulandi) → ardindan ci.yml'den **birebir cikarilan** zincir betigi kosuldu:
- `ADP_PARITY_OK → PRE156_BASELINE_OK → PRE157_BASELINE_OK policy=63 writable=63 → FINAL_162/163/164/165 OK → uygulanan=161 hist=161 max=165 dup=0 → CI_CHAIN_DONE` (~43 sn).
- **CI<->canli yetki parite adimi** (betige gomulu): zincir oncesi `postgres` rolunun public ADP'sinden `anon, authenticated` geri alinir — canlida ADP satiri yoktur; service_role bakim yolu (faz10b T-10/T-11c) korunur. Kanit: ADP tohumlu+parity'li replikada faz10b **54/54 gecti**; ADP'siz eslemde svc yollari yanıslılığa FAIL veriyordu (replika kalibrasyonu bulundu).
- chain assert SQL'i birebir: `CHAIN_OK` (161/165, subjects grant). Faz10B guvenlik invarianti: `SECURITY_INVARIANT_OK`.

### 5.4 CI SQL QA pilunun replikada sonucu (18 suite + 2 paralel probe)
- **Yesil (11):** faz3, faz4, faz5, faz6, faz11, scoring127, faz30d1, qgate122, faz35b, role_mgmt + faz10b(replikada) + **tüm Faz2 sayac ve Faz4 rate-limit probe'lari OK**.
- **Kirmizi (7) — hepsi zincir-132+ etkilesimidir, temiz kurulum hatasi DEGIL** (≤131 kontrol DB'sinde ayni suite'ler ✅, tam zincirde ❌):

| Suite | Koken neden | Nitelik |
|-------|-------------|---------|
| faz1 | 151 `uq_question_active_single_vault` + kasa-donusturme kapilari | Eski fixture 132+ kurallarina gore bayat |
| faz2 | 165 events FK `ON DELETE SET NULL` × `_q165_trg_events_append_only` (temizlik DELETE'i `KOTA_165` ile bloklanıyor) | **BULGU B-1** |
| faz35 | `current_date-60` QA-CAL penceresi 111 gercek takvimiyle **bugun** cakisiyor (exclusion) | **BULGU B-2 tarih bombasi** |
| grade093 | 157 meşru yazma yollari `authenticated` UPDATE aciyor → 42501 beklentileri aşıldı | Bayat suite (canlıda da aynı durum) |
| boundary095 | Ayni aile (loadout/grade_level 42501 + antrenman sekme) | Bayat suite |
| scoring094 | `prepare_competition_pack` yeni haftalik kasa zinciri (158/161/162) fixture istemiyor | Bayat suite |
| faz10 | Ayni 157 yazma-yol ailesi (P-06/07) | Bayat suite |

**BULGU B-1 (urun notu):** 165 events FK'i `competition_id ON DELETE SET NULL`; append-only tetik bu FK guncellemesini de bloklar → **kota olayi bulunan yarisma artik silinemez** (canlıda da gecerli; veri koruma sozlesmesiyle tutarli ama yarisma silme akisi varsa kirilir). Ayrica eski 163 events FK'i de ayni desende — canlida 163 satirlariyla da ayni bloklama gecerli.
**BULGU B-2 (ci hazirlik notu):** faz35 **bugun mevcut CI'da da kirmizi olur** (tarih bagimli; zincirle ilgisiz). Push oncesi suite duzeltmesi gerekir (test gevşetme degil — pencereyi 111 takvimi disina sabitleme).

## 6. Types drift — GUNCEL GERCEKLIK (oneemli duzeltme)

Disk gercekligi, bir onceki fazin iddiasini dogrulamadi:
- `src/lib/supabase/types.ts` calisma agaci: **12786 satir, mtime 2026-11-16**, 165 nesneleri **ICERMIYOR** (`student_week_subject_quota` sayacı 0); HEAD'den farki yalniz 26 satir `list_question_generation_requests` manuel override bloğu.
- `docs/reports/ak-db-consistency-03-*.md` ve `drafts/ak-db-consistency-03/` **diskte YOK**.
- ⇒ Konsanlık-03 "merge yerlestirildi" iddiasi **dogrulanmadi** (kayit-kod farki; bu rapor disk gercegini esas alir).

Bu fazda olcutulen yeni kanitlar:
- CLI 2.115.1-beta.13 ile: **CI-zincir DB'den generated == CANLI DB'den generated, BIREBIR** (14524 satir; `diff -q` identical). Kanit: `drafts/ak-git-checkpoint-02/types.chain-165.generated.ts` (`9543de6e…`).
- Commitli (HEAD/working) types ile generated arasi fark ~1871 satir → CI drift guard W1 sonrasi **kirmizi** olur; W3 (types commit) zorunlu.
- K1/K2 karari gecerli: generated dosyada `list_question_generation_requests` alanlari **non-null**; calisma agacindaki 26-satir override bunlari `| null` yapar (uygulama `uretim-talepleri.ts` nullable bekler) → K1 (pure generated + sandbox tsc) henuz test edilmedi; K2 (override koru + drift guard muafiyet hunk'i) yedekte. **Karar kullaniciya kalmis (GAP-CI-03).**

## 7. Kalan engeller (ilk yesil push icin)

| ID | Engel | Durum |
|----|-------|-------|
| GAP-CI-01 | `AdminNav.test.tsx` 1/15 FAIL (bu fazda tekrar dogruladi: 14 pass/1 fail) | Acik — frontend gorevi, WIP dosya bu fazda degistirilmedi |
| GAP-CI-02 | hooksuz `db reset` CI kirilmasi | **KAPANDI** — ci.yml yamasi hazir + replika simulesi yesil (§5) |
| GAP-CI-03 | types drift + K1/K2 karari + konsanlik-03 disk gercekligi | Acik (§6) |
| **GAP-CI-04 (YENI)** | 7 legacy suite 132+ zincirinde kirmizi (BULGU B-1/B-2 dahil) | Acik — suite fixture guncelleme gorevi (test gevşetme OLmadan: gercek beklenti 132+ sozlesmesine tasma) |
| GAP-F1 | Ogrenci ekrani gorsel kabuli (Ogrenci A girisi) | Kullanici adimi |

## 8. W1 degerlendirmesi

- **W1 commit grubu READY_WITH_GAPS:** zincir icerigi temiz kurulumla kanitli, ci.yml yamasi replikada yesil. Ancak **push sirasinda CI su an kirmizi olur** (GAP-CI-01 + GAP-CI-04 + GAP-CI-03).
- Oneilen siralamayi koruyorum: W1 (migrationlar + qa-clean-install + ci.yml) → suite/types isleri ayri fazlarda → yesil kontrol sonrasi push izni.
- `git add .` yok; commit listeleri checkpoint-01 §6 allowlist'i + bu fazdan `scripts/qa-clean-install/` (mevcut 3 dosya) ve `ci.yml` yamasi ile ayni.

## 9. Temizlik kaniti

- Bu fazin disposable DB'leri dusuruldu: `qa_agc02_c165`, `qa_agc02_ci`, `qa_agc02_ctl` → DROP.
- Sonrasi envanter: `postgres, qa_aqs01_a, qa_aqs01_b` (onceden var olanlar sag).
- Container `/tmp` kalintilari (`/tmp/agc02`, `/tmp/pgwork`, zincir betikleri) silindi; container `/tmp`'deki onceki fazlara ait eskiler kullanici alanina dokunmamak icin birakildi.
- Docker envanteri kosu basi ile birebir (`DOCKER_ENVANTER_SABIT`); canli `live_max=165 hist=148`; `login=200`.

## 10. Hukum

**TEMIZ KURULUM: PASS (161/161, hook'lu, sifir ENV_REPAIR, FINAL_165 + M1–M7 + kota regresyonu yesil).**
**CI ON KAPISI: HAZIR — en kucuk dar kapsamlı ci.yml duzeltmesi yazildi ve CI replikasinda birebir kanitlandi; GitHub'a push YAPILMADI (yok zaten).**
**GIT KAYDINA HAZIRLIK: W1 READY_WITH_GAPS — yesil CI icin GAP-CI-01/03/04 onceliklendirilmeli.**

GÜVENLİ DUR — temiz kurulum kanitlandi; kalan is kayit altinda, sira kullanici kararinda.
