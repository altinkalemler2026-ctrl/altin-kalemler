# AK-GIT-CHECKPOINT-03 — Legacy QA Kırılmaları: Kök Neden + Kanıtlı Çözüm (2026-11-18)

**Sonuç: DONE_WITH_GAPS — GÜVENLİ DUR.**
Yedi kırmızı legacy suite'in tamamı tek tek sınıflandırıldı. **3 suite test tarafında
düzeltildi ve iki zincir tabanında (≤131 + 001–165) yeşil**: faz1 (34/34), faz2 (52/52),
faz35 (24/24). **4 suite (grade093, boundary095, faz10, scoring094) GERÇEK GÜVENLİK
SÖZLEŞMESİ İHLALİ (yeni GAP-SEC-01) nedeniyle FAIL olarak KORUNDU** — test gevşetilmedi,
atlanmadı, silinmedi. Migration dosyalarına, RLS/ACL guard'lara, kota 165 davranışına,
canlı DB'ye (yalnız salt-okunur ölçüm yapıldı), AdminNav WIP'e ve types.ts'ye
dokunulmadı. Commit/push YAPILMADI.

Ek bulgular: (a) faz2'de checkpoint-02'nin bildirmediği İKİNCİ bir tarih bombası
kanıtlandı ve düzeltildi; (b) scoring094'ün checkpoint-02'deki "haftalık kasa fixture
eksiği" sınıflandırması YANLIŞTI — gerçek kök neden GAP-SEC-01 ailesidir (aşağıda düzeltme).

---

## 1. Ortam ve yöntem

| Ölçüm | Değer |
|---|---|
| HEAD / dal | `f3ba037` / `main` (değişmedi; commit/push yok) |
| Disposable DB'ler | `qa_agc03_full` (001–165 CI replika), `qa_agc03_ctl` (≤131 kontrol), `qa_agc03_c165` (165 regresyon) — **hepsi drop edildi** |
| Kurulum | ci.yml'den birebir çıkarılan `ci_apply_chain.sh` (ADP tohum + ADP parite + PRE156/PRE157 hook'ları); 161/161 dosya, hist=161 max=165 dup=0, FINAL_162–165 OK |
| Korunanlar | `qa_aqs01_a/b`, ana stack `supabase_db_yarisma-programi` (salt-okunur ölçüm), container `/tmp` eski ögeleri, kullanıcı WIP dosyaları |
| Temizlik sonrası envanter | DB: yalnız `qa_aqs01_a/b`; docker ps: baseline ile birebir (5 container); `/tmp`'te AGC03 izi yok |

Parse semantiği ci.yml ile birebir (parsed / summary / self-raising + iki paralel probe).

## 2. Yedi suite — tek tek kök neden sınıflandırması

Sembol: ✅ = ≤131'de yeşil, ❌ = kırmızı.

### 2.1 faz1 — `scripts/qa_faz1_local_validation.sql` — BAYAT TEST (kanıtlı) → DÜZELTİLDİ
- Kırılan: T-15 (satır ~455) `duplicate key ... uq_question_active_single_vault` (23505);
  T-18 (satır ~496) `beklenen P0001 uygulandı` (T-15'in bıraktığı eksik üye sayısından KASKAD).
- ≤131: ✅ 34/34 | 001–165 (önce): ❌ 32/34.
- İlk sapma migration: **151** (`uq_question_active_single_vault` — bir soru aynı anda
  yalnız BİR kasada aktif üyelik olabilir).
- Kök neden: T-15 fixture'ı, yarışma kasasında (501) ZATEN aktif olan QA-Q1..Q5'i academic
  kasaya (502) eklemeyi bekliyordu. 151 öncesi bu serbestti; 151 sonrası 23505.
- Sınıflandırma: **test beklentisi eskimiş** — testin amacı (academic kasada üyelik limiti
  YOK; 5+ aktif üyeli academic kasa competition'a çevrilemez) 151 ile değişmedi.
- Düzeltme (test tarafı, en küçük): fixture'a başka kasada aktif üyeliği olmayan taze
  QA-Q9..Q13 eklendi; T-15 bu sorularla aynı semantiği doğruluyor. T-18 değişmedi
  (502'de 3+5=8 aktif üye ile P0001 yine kanıtlanıyor). T-14/T-16/T-17/T-19 davranışları
  151 ile zaten uyumlu (kapasite tetiği unique'ten önce; tek-aktif ihlali yok) — reprodükte
  edildi.
- Sonuç: ✅ full 34/34, ✅ ctl 34/34.

### 2.2 faz2 — `scripts/qa_faz2_local_validation.sql` — İKİ AYRI kök neden → DÜZELTİLDİ
**(a) BULGU B-1 zinciri (yalnız 001–165):** cleanup'ta fixture yarışmasının silinmesi
`student_week_subject_quota_events` FK'sinin `ON DELETE SET NULL` UPDATE'ini tetikliyor;
165 `_q165_trg_events_append_only` (BEFORE UPDATE OR DELETE) bunu KOTA_165 ile blokluyor →
ON_ERROR_STOP ile suite özet basamadan abort (psql:1376). **B-1'in kendisi GERÇEK ürün
bulgusudur** (kota olayı olan yarışma silinemez — denetim kaydı korunumu) ve AYNEN korundu.
Düzeltme: cleanup DELETE'i "kota olayı olmayanları sil" şeklinde korundu (to_regclass
guard'ı ile ≤165 öncesi zincirlerde eski semantik); final ROLLBACK zaten her şeyi geri
aldığı için veri kalmaz, `comps_kalan` doğrulama SELECT'i gerçek durumu raporlar (assert
değildir — gevşetme yok).
Aynı kök nedenin YENİ uzantısı kanıtlandı: `events.user_id FK ON DELETE CASCADE` olduğundan
kota olayı olan **kullanıcı** da silinemiyor → `auth.users` cleanup'ı da aynı guard ile
kuşatıldı (B-1 genişletmesi, bkz. §5).
**(b) İkinci tarih bombası (zincir-BAĞIMSIZ; ≤131'de de kırmızıydı — checkpoint-02'nin
"≤131'de hepsi ✅" iddiası faz2 için YANLIŞTI, kendi ctl_faz2.out kanıtı 47/52):**
fixture "resolved hafta = 1" varsayımıyla T_FUTURE konusunu `start_week 6`'ya sabitlemişti.
111 gerçek takvimi ilerleyip resolved hafta ≥6 olunca (bugün K10) Q6 seçim havuzuna sızdı →
T-02a/02c/02d/02e-b/T-03 beşli kırılması (new_count=9≠8). İlk sapma: **111** + takvim
ilerlemesi (B-2 ailesi).
Düzeltme: T_FUTURE `start_week = resolved hafta + 5` (göreli, deterministik; CHECK
`start_week >= 0` üst sınır gerektirmiyor). Gerçek seçim kurallarına dokunulmadı.
- Sonuç: ✅ full 52/52, ✅ ctl 52/52, ✅ **kenar senaryolar**: sentetik resolved K47 →
  52/52, sentetik K1 → 52/52 (disposable DB'de sentetik takvimle doğrulandı, takvim sonra
  orijinal 42 haftaya geri yüklendi).

### 2.3 faz35 — `scripts/qa_faz35_local_validation.sql` — BULGU B-2 (tarih bombası) → DÜZELTİLDİ
- Kırılan: fixture INSERT'i, satır 192: `academic_weeks_no_cross_year_overlap` (074 global
  EXCLUDE) — `current_date - 60` = 2026-09-19 gerçek 111 takviminin (2026-2027
  K1..K42: 2026-09-14..2027-07-03) K2 aralığıyla çakıştı. Suite özet basamadan abort.
- ≤131: ❌ (aynı hata) | 001–165: ❌ → **zincir-132+ ile ilgisi YOK**; ~13 Kasım 2026'dan
  beri her gün kırmızı olurdu (CI dahil). İlk sapma: **111** tohumu + takvim ilerlemesi.
- Düzeltme (sabit takvim fixture'ı, semantik korumalı): w1 → sabit `2020-01-06..13`
  (HER koşu tarihinde geçmiş), w20/w21 → sabit `2099-01-05..12 / 01-12..19` (HER koşuda
  gelecek); T-09a/b (w22 `2099-01-19..26`), T-10 (w23 `2099-01-08..16`, w20/w21 ile kesişir),
  T-11 (`2100` w5 `2099-01-08..15`, w20 ile farklı-yıl kesişimi), T-11b (`2099-06-01..08`,
  kesişimsiz), T-16 (hafta 99 — `2099-09-01..08` kesişimsiz sabit), T-19 (doğrudan INSERT
  `2099-01-08..15` — w20 ile 23P01). Yetki-red testi (T-02/05/07) ve T-12 red reddi
  date-lojikten önce kırpan kontrollerle çalıştığı için olduğu gibi bırakıldı (çıktıları
  tarih-bağımsız). Gerçek akademik hafta/takvim kuralları ve 074 EXCLUDE DEĞİŞMEDİ;
  sistem saati/canlı veri değiştirilmedi.
- Geçmiş+gelecek senaryoları: w1 daima geçmiş (T-12 "Başlamis..." / T-13 silme redi),
  w20/21/22 daima gelecek (T-09/10/11/14/15/16/19) — 24/24 iki tabanda da.
- Sonuç: ✅ full 24/24, ✅ ctl 24/24.

### 2.4 grade093 — `scripts/qa_grade_hardening_093_local.sql` — GERÇEK GÜVENLİK HATASI → FAIL KORUNDU
- Kırılan 10 test (tam liste raporda): T-00a:242, T-00c:250, T-02:308, T-03a:332,
  T-03b:342, T-07:440, T-08:464, T-09:496, T-10c:562, T-10d:567.
- Çekirdek hata: T-02 `ogrenci kendi grade_level degerini degistiremiyor (42501) >>> hata
  beklenmisti ama uygulandi`. Kalan 9 test bundan KASKAD (izin matrisi ölçümleri + grade
  6'ya kaçınca sınıf kapıları/antrenman havuzu/eşleşme bozuluyor).
- ≤131: ✅ 23/23 | 001–165: ❌ 13/23. İlk sapma: **156→157 adımı** — zincir dosyası değil,
  temiz-kurulum hook'u `hook_after156_write_matrix_baseline.sql` authenticated'a
  student_profiles'ta TABLO-geneli UPDATE veriyor; 157'nin fail-closed guard'ı
  (`157:414 has_table_privilege(...,'UPDATE')`) bunu ZORUNLU kılıyor (bkz. §3 kanıtı).
- Sınıflandırma: **GERÇEK ÜRÜN/GÜVENLİK HATASI (GAP-SEC-01)**. Test silinmedi/gevşetilmedi.

### 2.5 boundary095 — `scripts/qa_data_boundary_095_local.sql` — GERÇEK GÜVENLİK HATASI → FAIL KORUNDU
- Kırılan: B-01:263, B-02:268 (dogrudan INSERT/UPDATE student_loadouts 42501 beklenirken
  uygulandı — loadout'un RPC dışı yazıma açılması), E-01:556 (093 ailesi), E-03:563
  (E-01 kaskadı: sınıf kaçınca antrenman havuzu boşalıyor).
- ≤131: ✅ 42/42 | 001–165: ❌ 38/42. İlk sapma: 156→157 adımı (aynı write-matrix kökü).
- Sınıflandırma: **GAP-SEC-01 ailesi** (093 yarğı + 095 loadout RPC-only sınırı). Testler
  korundu.

### 2.6 faz10 — `scripts/qa_faz10_avatar_rpc_local.sql` — GERÇEK GÜVENLİK HATASI → FAIL KORUNDU
- Kırılan: P-06:157, P-07:161 (grade_level UPDATE 42501 beklenirken uygulandı — 093 ailesi),
  P-08:167 (P-06/07'nin uygulanan UPDATE'inin nick'i taşıması kaskadı), V-08:261
  (P-06 grade'i 7→5 yaptığı için `grade=5` okunması kaskadı).
- ≤131: ✅ 26/26 | 001–165: ❌ 22/26. İlk sapma: 156→157 adımı.
- Sınıflandırma: **GAP-SEC-01 ailesi**. Testler korundu.

### 2.7 scoring094 — `scripts/qa_scoring_v1_094_local.sql` — checkpoint-02 SINIFLANDIRMASI DÜZELTİLDİ → FAIL KORUNDU
- Simptom: E-49 (satır 1087) içinde `join_matchmaking_queue → prepare_competition_pack`
  "Uygulanabilir ortak gorulmemis paket kasa yok" → ON_ERROR_STOP rc=3.
- Kanıtlı gerçek zincir: **E-46:1005** (093 regresyon beklentisi: grade_level=6 UPDATE
  42501) tam zincirde UYGULANIYOR → U1(91)'in sınıfı 5→6 kaçar → E-49'da U1 (artık 6) ile
  U3 (6) EŞLEŞİR → 6. sınıf için fixture'ta 5. sınıf kasa var, 6. sınıf kasa YOK →
  prepare raise. Yani hata haftalık-kasa zincirinin (158/161/162) fixture isteği DEĞİL;
  checkpoint-02'nin "fixture istemiyor" sınıflandırması **yanlış**tı. (Aday havuzu sorgusu
  `v_flag_ok`/eligibility mantığı ≤131'den beri aynıdır ve ctl'de suite 53/53 geçer.)
- ≤131: ✅ 53/53 | 001–165: ❌ rc=3 (abort). İlk sapma: 156→157 adımı.
- Sınıflandırma: **GAP-SEC-01 ailesi**. Test korundu (E-46 tam da ihlal edilen sözleşmeyi
  doğruluyor).

## 3. GAP-SEC-01 (YENİ, kritik) — 093 sınıf-immutable sözleşmesi temiz zincirde ve canlıda ihlalli

**Mekanizma:** 093 kolon-seviyeli sertleştirmeyle `authenticated`'dan tablo UPDATE'ini
geri alır, yalnız `GRANT UPDATE (nickname)` verir. Ölçülen gerçeklikler:
- ≤131 temiz zincir (kontrol): `authenticated=ar`, `has_table_privilege UPDATE=false`,
  `col_grade=false` → 093 yürürlükte (suite'ler yeşil).
- 001–165 CI replika: hook_after156 tüm "yazma politikali" 63 tabloda TABLO-geneli
  INSERT/UPDATE/DELETE verir → `col_grade=true`; update_own RLS politikası yalnız SATIR
  sınırlar → öğrenci kendi `grade_level`'ını (ve kendi loadout satırına sınırsız
  character/cosmetic bağını) yazabilir.
- Canlı stack (salt-okunur ölçüm): `relacl={...authenticated=arw...}`,
  `col_grade=true` → CANLIDA DA aynı ihlal mevcut (modül-dönemi manuel GRANT ALL mirası;
  checkpoint-02 bunu "canlıda da aynı durum" olarak doğru gözlemlemişti).
- **157 kaçınılmaz kılıyor:** `157:414` guard'ı `has_table_privilege('authenticated',
  'public.student_profiles','UPDATE')` ister; PostgreSQL'de kolon yetkisi bu kontrolü
  KARŞILAMAZ (≤131'de false ölçüldü). Yani hook'suz temiz zincirde 157 guard'ı düşer;
  hook'un tablo-geneli UPDATE'i 157 sözleşmesinin ZORUNLU ön koşuludur. 093 ile 157
  arasındaki çelişki migration zincirine gömülüdür.
- Altına alınan M1–M7 / SECURITY_INVARIANT / qa_sec157 testleri bu kolon boyutunu
  kapsamıyor; bu yüzden yeşil kalırlarken 093 ailesi kırmızı.

**Etki:** Altın Kalem sabitinin ihlali — "öğrenci yalnız kendi grade_level içeriğini görür"
kapısı kendini yeniden sınıflandırarak aşılabiliyor; loadout doğrudan yazımı kozmetik
sahiplik kontrolünün (RPC) baypası. Skor/lig verisi bu yolla değişmese de sınıf ve kozmetik
bütünlüğü bozulur.

**Kapsam kararı (bu görev):** Motor/hook/migration DEĞİŞTİRİLMEDİ (görev yasağı: güvenlik
kontrollerini değiştirme; canlıya yazma yasağı). 4 suite FAIL olarak korundu.
**Önerilen remediation (ayrı güvenlik fazı, kullanıcı kararı):** yeni migration (REVOKE
tablo UPDATE authenticated; GRANT UPDATE(nickname) iadesi; 157 guard'ının kolon-farkındalıklı
`has_column_privilege` versiyonu ile uyum), hook_after156'nın öğrenci-profil/kolon korumalı
varyantı, CANLIDA aynı REVOKE (açık izinle), grade kaçırma senaryosi için ek QA assertion'ları.

## 4. Değiştirilen dosyalar (yalnız test tarafı; `--ignore-cr-at-eol`: 93+/29−)

| Dosya | Değişiklik |
|---|---|
| `scripts/qa_faz1_local_validation.sql` | QA-Q9..Q13 fixture soruları + T-15 bu sorulara bağlandı (151 sözleşmesi yorumu ile) |
| `scripts/qa_faz2_local_validation.sql` | T_FUTURE start_week göreli (`per_week+5`); cleanup: competitions/auth.users/scoring_rule_sets DELETE'leri 165 kota-olayı guard'lı (to_regclass ile ≤165 öncesi uyumlu) |
| `scripts/qa_faz35_local_validation.sql` | fixture + 8 test ifadesi sabit deterministik tarihlere (2020 geçmiş / 2099 gelecek) taşındı |

Diff'teki dev `+2328/−2264` sayıları faz1/faz2'nin oturum-öncesi mevcut CRLF satır-sonu
dönüşümleridir (checkpoint-01 §1.1); içerik diff'i yalnız yukarıdaki üç dosyadadır.
Migration SQL'leri, hook'lar, ci.yml, types.ts, AdminNav ve diğer kullanıcı WIP'leri
DEĞİŞMEDİ. Commit/push/add/reset/stash YAPILMADI.

## 5. İzole QA doğrulama pili (qa_agc03_full, 001–165)

| Gider | Sonuç |
|---|---|
| Hook-runner 001–165 kurulumu | ✅ 161/161, ADP_PARITY_OK, PRE156/PRE157 OK (policy=63 writable=63), FINAL_162–165 OK, hist=161 max=165 dup=0 |
| 3 düzeltilen legacy suite | faz1 34/34 · faz2 52/52 · faz35 24/24 (ctl ≤131'de de aynı) |
| faz2 tarih kenar senaryoları | sentetik resolved K47 → 52/52 · K1 → 52/52 (takvim sonrası orijinaline geri yüklendi) |
| CI-replika pili (18 suite + 2 probe) | 14 OK + faz2 paralel probe OK + faz4 rate-limit probe OK; 4 FAIL = yalnız GAP-SEC-01 ailesi (grade093 13/23, boundary095 38/42, faz10 22/26, scoring094 rc=3) |
| M1–M7 (qa_sec_privilege_drift_audit) | ✅ 7/7 PASS, "PRIVILEGE AUDIT TEMIZ", DIGEST=`3509ab094790b4aaa4f9b03533a5b50ba25607e0d208d0cdd612f39a4df10fc0` = checkpoint-02 CI-replika temeli ile BİREBİR |
| SECURITY_INVARIANT (ci.yml aynen) | ✅ SECURITY_INVARIANT_OK |
| Migration 164 RPC | ✅ md5(`uretim_planlayici_list_vaults`)=`b1ded12a16d4c40dea8ac3c247ecf940`, md5(`..._vault_stock`)=`3f3f481e8aa7201a339bd091be74a043` — anıtla birebir |
| Migration 165 kritik regresyon (qa_agc03_c165) | ✅ fixture OK · qa165_suite 50/50 · eşzamanlı S6/S7 PASS (40/40 kota kapısı concurrent'te doğrulandı) · negatif re-apply NEG162/NEG163/NEG165 GUARD abort OK (164 tasarım gereği idempotent — consistency-02 §B5) · dup=0 max=165 |
| Migration dosya SHA-256 (162–165) | ✅ checkpoint-01/02 temeli ile birebir (`e2093b55…`, `300d1e87…`, `780cc250…`, `655b510396d0…d4e36`) |
| B-1 ek davranış kanıtı | Kota olayı olan kullanıcı da silinemez (events FK CASCADE tetik tarafından bloklanıyor) — B-1'in yarisma→kullanici genişlemesi; admin/user-silme akışları için ayrı ürün bulgusu önerilir |

## 6. types.ts durumu (GAP-CI-03 — dokunulmadı, kayıt)

`src/lib/supabase/types.ts`: SHA-256 `80435cb2f41877ac6ec25633685adf64e0d0f5807c2e40c56cb48b90a222d097`,
12786 satır, git durumu `M`. checkpoint-02 §6 ile aynı sürüm (K1/K2 kararı kullanıcıda).
Zincir-165'ten taze üretim 14524 satır ve canlı üretimle birebir — drift sürüyor; bu görev
kapsamı dışı.

## 7. Kalan sorunlar / GAP listesi

1. **GAP-SEC-01 (YENİ, BLOCKER güvenlik):** §3. W1 push'undan önce ayrı güvenlik fazı
   kararı bekleniyor. CI push'lanırsa 4 suite bilinçli-kırmızı olur.
2. **GAP-CI-01 (AdminNav):** `src/components/admin/AdminNav.test.tsx` — 1/15 FAIL
   (bu oturumda yeniden doğrulandı; kullanıcı WIP, dokunulmadı).
3. **GAP-CI-03 (types drift):** §6.
4. **BULGU B-1 (ürün, checkpoint-02 + genişletmesi):** kota olayı olan yarışma VE kullanıcı
   silinemiyor (denetim kaydı korunumu bilinçli; ancak admin silme akışları için
   ürünleşik "anonymize/soft-delete" yolu gerekir).
5. GAP-F1 (öğrenci ekranı görsel kabulu) — değişmedi, bu görevin kapsamı dışı.

## 8. W1 GO/NO-GO

- **Test düzeltmeleri (faz1/faz2/faz35): GO.** İki tabanda da yeşil, sözleşme-korumalı,
  commit grubuna girebilir.
- **W1 push için CI yeşili: NO-GO.** GAP-SEC-01 çözülemeden CI kasıt-kırmızı 4 suite ile
  döner; AdminNav (GAP-CI-01) ve types drift (GAP-CI-03) de kapıda duruyor. Sıra önerisi:
  güvenlik fazı (GAP-SEC-01 remediation migration'ı + hook varyantı + canlı REVOKE izni)
  → types kararı → W1.
- Bu görevde commit/push YAPILMADI; push için ayrıca açık izin gerekir.

## 9. GÜVENLİ DUR

Canlı DB yalnız salt-okunur ölçüldü (izin matrisi/relacl/FK tanımları); canlıda hiçbir
yazma, migration, reset, restart yapılmadı. Disposable kaynakların tamamı (`qa_agc03_full`,
`qa_agc03_ctl`, `qa_agc03_c165`, container `/tmp` AGC03 artefaktları) silindi; `qa_aqs01_a/b`,
ana stack ve eski /tmp ögeleri yerinde. Docker envanteri baseline ile birebir. Working
tree yalnız üç QA suite dosyasındaki test-düzeltmelerini içerir; commit YOK — güvenli kayıt
noktası.
