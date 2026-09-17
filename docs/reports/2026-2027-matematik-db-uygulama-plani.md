# 2026-2027 Matematik DB Uygulama Plani

Tarih: 2026-09-15 · Kapsam: **yalniz planlama + rapor** — kod/DB/migration/soru/commit/push YOK
Kaynaklar: yillik-konu-plani, pdf-esleme, resmi-mufredat raporlari, MEB calisma takvimi,
DB shemasi (salt-okunur — migration 002/003/004/009/059/067/068/074/098/110),
mevcut DB envanteri (SELECT-only docker exec psql).

---

## 0. Kritik Duzeltme: Yillik Plan 9.2 — Tatil Satiri Sorunu

**Yillik plan 9.2, karar 2'de "tatil haftalarinin satir YOKLUGU onerilmis" ve "tatil satiri
yoklugu antrenmani etkilemez" iddia edilmistir. Bu iddia YANLISHTIR.**

Kanit (salt-okunur):
- `_faz2_require_period()` (068:249-266): `resolve_current_academic_period()` bos donerse
  P0001 istisna firlatir.
- `_faz15_eligible_scope()` (110:325): `_faz2_require_period()` cagirir.
- `start_training_session` (110:751) ve `select_gated_targeted_review_questions` (110:1196):
  her ikisi de `_faz2_require_period()` cagirir.

**Sonuc:** Tatil haftasinda `academic_weeks` satiri YOKSA -> `_faz2_require_period` P0001
firlatir -> TUM soru akislari (antrenman + hedefli tekrar) tatilde HATA verir, yani
**tamamen KAPALI** olur. Bu, "tatilde antrenman + hedefli tekrar acik kalir" kuralinin
TAM ZIDDIDIR.

**Dogru karar:** Tatil haftalarinin `academic_weeks`'te **satiri OLMALI** (K1-K41 takvim
haftasi, tatil dahil). Yeni konu acilmamasi, `start_week` degerlerinin yalniz ogretim
haftalarina atanmasiyla ve ogretmen onay kapisiyla (gate b) saglanir — satir yokluguyla DEGIL.

---

## 1. Mevcut DB Durumu (SELECT-Only Envanter)

### 1.1 Var Olan Satirlar

| Tablo | Satir | Not |
|---|---|---|
| curriculum_versions | 2 | E2E7-FAZ7 (2026-2027, is_default=true), FZ15A-E2E. **Gercek TYMM/OGM satiri YOK.** |
| curriculum_schedule_profiles | 2 | E2E7-PROF (default=true), FZ15A-PROF (default=false) |
| subjects | 11 | Matematik = 430903f3-527e-4e12-b7e8-ac0afdb784aa |
| topics | 2 | Yalniz FZ15A fixture (grade 12). **TYMM/OGM konu satiri YOK.** |
| subtopics | 0 | |
| curriculum_outcomes | 0 | |
| academic_weeks | 44 | Fixture: week1=2026-08-31, +7 gun. **Resmi K1-K41 yuklenmemis.** |
| curriculum_schedule_items | 2 | Yalniz FZ15A fixture (grade 12, start_week=3) |
| curriculum_prerequisites | 0 | **9-10-11 zinciri ve 12 onkosullari YUKLENMEMIS** |
| curriculum_teaching_approvals | 1 | Yalniz FZ15A fixture |
| question_sources | 0 | **Soru kaynagi SATIRI YOKTUR** |
| question_curriculum_mappings | 3 | Yalniz FZ15A fixture |
| questions | 8 | Grade 12, 5 matematik (approved+active) |
| question_vaults | 38 | 37 matematik (049 legacy seed, grade 12 odakli) |

### 1.2 Kritik Eksikler

Gercek 2026-2027 matematik müfredati yuklenmemis; yukaridaki tum satirlar ya bos ya da
test fixture'idir. Gereken veri durumu:

1. curriculum_versions: TYMM-2026 ve OGM-2018 satirlari
2. curriculum_schedule_profiles: TYMM ve OGM icin ayri profiller
3. academic_weeks: Resmi K1-K41 takvimi (tatil haftalari dahil)
4. topics / subtopics: TYMM 2026 (9/10/11) ve OGM 2018 (12) konu agaci
5. curriculum_outcomes: Kazanimlar
6. curriculum_schedule_items: T1-T37 yerlesimi (her sinif icin)
7. curriculum_prerequisites: 9-10-11 onkosul zinciri + 12 onkosullari
8. question_sources + soru stogu + vault eslestirmeleri
9. student_profiles: schedule_profile_id atamasi (her ogrenci)

---

## 2. curriculum_versions — Yukleme Kurallari

### 2.1 Gereken Satirlar

| Surum | framework | academic_year | Kapsam | is_default |
|---|---|---|---|---|
| TYMM-2026 | tymm_2026 | 2026-2027 | Sinif 9, 10, 11 | karar gerekir (1) |
| OGM-2018 | ogm_2018 | 2026-2027 | Sinif 12 | karar gerekir (1) |

(1) `is_default` kismi benzersiz endeksi yilda tek true satira izin verir. Iki versiyondan
hangisi default olacak? Karar beklenir.

### 2.2 Teknik Kisitlar (003 migration)

- topics.curriculum_version_id FK RESTRICT: topic yuklenmeden once versiyon satiri olmali.
- UNIQUE(academic_year, framework): ayni yil = farkli framework izinli.
- is_default: her yil icin en fazla bir true.

---

## 3. academic_weeks — Tatil Haftasi Karari ve Numaralandirma

### 3.1 Dogru Karar: Tatil Satirlari DAHIL

Yillik plan 9.2 "tatil satiri yoklugu" onerir — ancak 0. bolumde acilandigi uzre bu
`_faz2_require_period` fail-closed istisnasiyla celisir. **Tatil satirlari yuklenmeli.**

### 3.2 Onerilen Numarandirma: K1-K41 (Takvim Haftasi, Tatil Dahil)

Hafta = academic_weeks.week integer; start_week ve _faz2_require_period ayni uzerinden calisir.

| K | Tarih | Durum | start_week |
|---|---|---|---|
| K1 | 14-18 Eyl 2026 | ogretim (T1) | 1 |
| K2 | 21-25 Eyl 2026 | ogretim (T2) | 2 |
| K3 | 28 Eyl-2 Eki 2026 | ogretim (T3) | 3 |
| K4 | 5-9 Eki 2026 | ogretim (T4) | 4 |
| K5 | 12-16 Eki 2026 | ogretim (T5) | 5 |
| K6 | 19-23 Eki 2026 | ogretim (T6) | 6 |
| K7 | 26-30 Eki 2026 | kisa hafta (29 Eki, T7) | 7 |
| K8 | 2-6 Kas 2026 | ogretim (T8) | 8 |
| K9 | 9-13 Kas 2026 | ogretim (T9) | 9 |
| K10 | 16-20 Kas 2026 | **ara tatil** | — |
| K11 | 23-27 Kas 2026 | ogretim (T10) | 11 |
| K12 | 30 Kas-4 Aralik 2026 | ogretim (T11) | 12 |
| K13 | 7-11 Aralik 2026 | ogretim (T12) | 13 |
| K14 | 14-18 Aralik 2026 | ogretim (T13) | 14 |
| K15 | 21-25 Aralik 2026 | ogretim (T14) | 15 |
| K16 | 28 Aralik-1 Oca 2027 | kisa hafta (1 Oca, T15) | 16 |
| K17 | 4-8 Oca 2027 | ogretim (T16) | 17 |
| K18 | 11-15 Oca 2027 | ogretim (T17) | 18 |
| K19 | 18-22 Oca 2027 | ogretim (T18) | 19 |
| K20 | 25-29 Oca 2027 | **yariyil tatili** | — |
| K21 | 1-5 Sub 2027 | **yariyil tatili** | — |
| K22 | 8-12 Sub 2027 | ogretim (T19) | 22 |
| K23 | 15-19 Sub 2027 | ogretim (T20) | 23 |
| K24 | 22-26 Sub 2027 | ogretim (T21) | 24 |
| K25 | 1-5 Mar 2027 | ogretim (T22) | 25 |
| K26 | 8-12 Mar 2027 | **ara tatil** | — |
| K27 | 15-19 Mar 2027 | ogretim (T23) | 27 |
| K28 | 22-26 Mar 2027 | ogretim (T24) | 28 |
| K29 | 29 Mar-2 Nisan 2027 | ogretim (T25) | 29 |
| K30 | 5-9 Nisan 2027 | ogretim (T26) | 30 |
| K31 | 12-16 Nisan 2027 | ogretim (T27) | 31 |
| K32 | 19-23 Nisan 2027 | kisa hafta (23 Nisan, T28) | 32 |
| K33 | 26-30 Nisan 2027 | ogretim (T29) | 33 |
| K34 | 3-7 Mayis 2027 | ogretim (1 Mayis Cmt, T30) | 34 |
| K35 | 10-14 Mayis 2027 | ogretim (T31) | 35 |
| K36 | 17-21 Mayis 2027 | kisa hafta (17-19 Mayis, T32) | 36 |
| K37 | 24-28 Mayis 2027 | ogretim (T33) | 37 |
| K38 | 31 Mayis-4 Haz 2027 | ogretim (T34) | 38 |
| K39 | 7-11 Haz 2027 | ogretim (T35) | 39 |
| K40 | 14-18 Haz 2027 | ogretim (T36) | 40 |
| K41 | 21-25 Haz 2027 | ogretim (T37) | 41 |

Toplam: 41 satir (DB'de 41 INSERT). Tatil haftalari (K10, K20, K21, K26) satir olarak yuklenir;
bu haftalara start_week degeri ATANMAZ (hicbir curriculum_schedule_items satiri bu haftalarda
acilmaz). Tatil haftalari:

- _faz2_require_period basariyla dondurur (hatasiz donem cozumu) -> antrenman KAPANMAZ.
- Onayli konularin start_week <= tatil_hafta_number kosulu zaten saglanmistir -> gate (a) acik.
- Gate (b) ogretmen onayi: tatilde yeni onay verilmez (insan karari); mevcut onaylar devam eder.

**Bu tablo kesinlestirilmeli ve bir karar olarak kabul edilmelidir.**

### 3.3 Kisa Hafta Etkisi

K7 (29 Eki), K16 (1 Oca), K32 (23 Nisan), K36 (17-19 Mayis): bu haftalarda da satir
vardir; haftalik 6 saat yerine ~5 saat beklenir. Sistemde "kisa hafta" kavrami yoktur;
haftalik kota 500'dur ve bu yeterlidir.

### 3.4 Fixture ile Karsilastirma

Mevcut fixture (local-faz7-e2e-fixture.sql) 44 hafta yukler (week1=2026-08-31, +7 gun);
resmi K1=2026-09-14 ise fixture week3. Yani fixture hafta numaralari ile resmi K# fark
gosterir. **Gercek veri yuklenirken fixture temizlenmeli ve resmi K1-K41 yuklenmelidir.**

---

## 4. curriculum_schedule_items — Sinif Bazinda Yerlesim

### 4.1 Zorunlu Alanlar (059 migration)

| Alan | Aciklama |
|---|---|
| schedule_profile_id | Versiyona karsilik gelen profile ait |
| grade_level | 9, 10, 11 veya 12 |
| subject_id | Matematik (430903f3-...) |
| topic_id VEYA outcome_id | Ikisinden en az biri zorunlu (CHECK); ikisi birden olamaz |
| start_week | INCLUSIVE — K# numarasi |
| end_week | EXCLUSIVE veya NULL; **antrenman erisimini KAPATMAZ** (059 notu) |

### 4.2 Sinif 9 (TYMM 2026) — 216 saat (206 tema + 10 okul temelli)

| Tema | T# | K# | start_week | end_week |
|---|---|---|---|---|
| MAT.9.1 SAYILAR | T1-T7 | K1-K7 | 1 | 8 |
| MAT.9.2 NICELIKLER VE DEGISIMLER | T7-T13 | K7-K13 | 7 | 14 |
| MAT.9.3 GEOMETRIK SEKILLER | T13-T15 | K14-K16 | 14 | 17 |
| MAT.9.4 ESLIK VE BENZERLIK | T15-T21 | K16-K24 | 17 | 25 |
| MAT.9.5 ALGORITMA VE BILISIM | T21-T26 | K24-K30 | 25 | 31 |
| MAT.9.6 OLASIGA GIRIS | T26-T32 | K30-K36 | 31 | 37 |
| MAT.9.7 UC BOYUTLU SEKILLER | T32-T35 | K36-K39 | 37 | 40 |

Not: K39-K41 (T35-T37) okul temelli planlama/tampon; schedule_item olarak yuklenmez.

### 4.3 Sinif 10 (TYMM 2026) — 216 saat (206 tema + 10 okul temelli)

| Tema | T# | K# | start_week | end_week |
|---|---|---|---|---|
| MAT.10.1 DOGRUSAL DENKLEMLER | T1-T7 | K1-K7 | 1 | 8 |
| MAT.10.2 2. DERECEDEN DENKLEMLER | T7-T11 | K7-K11 | 8 | 12 |
| MAT.10.3 MUTLAK DEGER | T11-T14 | K11-K14 | 12 | 15 |
| MAT.10.4 DENKLEM SISTEMLERI | T14-T24 | K14-K28 | 15 | 29 |
| MAT.10.5 PARCALI FONKSIYONLAR | T24-T28 | K28-K32 | 29 | 33 |
| MAT.10.6 TRIGOMETRI | T28-T32 | K32-K36 | 33 | 37 |
| MAT.10.7 OLASIGA DEVAM | T32-T35 | K36-K39 | 37 | 40 |

Not: K39-K41 (T35-T37) okul temelli/tampon; yuklenmez.

### 4.4 Sinif 11 (TYMM 2026) — 216 saat (206 tema + 10 okul temelli)

| Tema | T# | K# | start_week | end_week |
|---|---|---|---|---|
| MAT.11.1 TUREV | T1-T5 | K1-K5 | 1 | 6 |
| MAT.11.2 INTEGRAL | T5-T15 | K5-K17 | 6 | 18 |
| MAT.11.3 LOGARITMA | T15-T22 | K17-K26 | 18 | 27 |
| MAT.11.4 TRIGOMETRIK DENKLEMLER | T22-T29 | K26-K33 | 27 | 34 |
| MAT.11.5 ANALITIK GEOMETRI | T29-T35 | K33-K39 | 34 | 40 |

Not: K39-K41 (T35-T37) okul temelli/tampon; yuklenmez.

### 4.5 Sinif 12 (OGM 2018) — 216 saat (tamamı tema, okul temelli pay yok)

| Tema | T# | K# | start_week | end_week |
|---|---|---|---|---|
| MAT.12.1 TUREV UYGULAMALARI | T1-T7 | K1-K7 | 1 | 8 |
| MAT.12.2 INTEGRAL YONTEMLERI | T7-T10 | K7-K10 | 8 | 11 |
| MAT.12.3 BELIRSIZ INTEGRAL | T10-T16 | K10-K18 | 11 | 19 |
| MAT.12.4 DETERMINANT | T16-T19 | K18-K21 | 19 | 22 |
| MAT.12.5 MATRIS | T19-T26 | K21-K30 | 22 | 31 |
| MAT.12.6 OLASIGA DEVAM | T26-T33 | K30-K37 | 31 | 38 |
| MAT.12.7 GEOMETRIK DONUSUMLER | T33-T37 | K37-K41 | 38 | NULL |

Not: 12'de T37 (K41) yedek/kapanis haftasi; end_week=NULL (acik uclu) onerilir.

### 4.6 Kurallar

- Tatil haftalarina (K10, K20, K21, K26) start_week atanmaz; bu haftalar schedule_items
  araligina duser ama hicbir item "tatilde baslamaz".
- Bir temanin son haftasi ile sonrakinin baslangici ayni K degeri olabilir (sinir haftasi);
  sinif tablosunda K degerleri ustuste binmez (T# eslesmeleri dogru).
- start_week degeri K# uzerinden olmali (T# DEGIL), cunku _faz15_eligible_scope
  academic_weeks.week ile karsilastirir.
- Her sinif icin toplam ~216 saat; K sayisi = ogretim haftasi sayisi (K10/K20-K21/K26
  ogretim haftasi degildir).

---

## 5. curriculum_prerequisites — Onkosul Zinciri

### 5.1 Mevcut Durum

curriculum_prerequisites tablosu TAMAMEN BOS (0 satir). Bu durumda:
- `_faz15_eligible_scope` gate (c) (110:438-519): required+approved onkosul satiri
  yoksa hicbir konu "onkosul tamamlanmamis" sayilmaz (not exists => pass).
- Yani onkosul verisi yuklenmezse **tum konular gate (c)'den otomatik gecer** — bu
  istenmeyen bir durumdur, onkosullar yuklenmeli.

### 5.2 Gereken Veri

9->10->11 referans zinciri (TYMM 2026 icin):
- MAT.9.x onkosullari MAT.10.x icin (ornegin MAT.9.1 -> MAT.10.1 dogrusal denklem onemsi)
- MAT.10.x onkosullari MAT.11.x icin (ornegin MAT.10.6 trigonometri -> MAT.11.4 trig denklem)

12 icin (OGM 2018):
- Unite ici onkosullar (ornegin MAT.12.1 turev uygulamalari icin MAT.12.2 integral yontemleri)

Alan degerleri:
- requirement_level: required / recommended / optional
- review_status: pending / approved / rejected / needs_review
- source_type: manual / auto / import
- target_topic_id, target_subtopic_id (bir zorunlu); prerequisite_topic_id veya
  prerequisite_subtopic_id (bir zorunlu)

**Kural:** requirement_level='required' ve review_status='approved' olan onkosullar
gate (c)'de denetlenir. Diger seviyeler (recommended/optional) denetlenmez.

### 5.3 Tamamlama Kaniti

Onkosul tamamlanmasi icin: onkosul konusunda onayli eslestirmeli (approved
question_curriculum_mappings) en az 1 dogru TRAINING denemesi gerekir (110:460-476).

---

## 6. curriculum_teaching_approvals — Ogretmen Onay Kapisi

### 6.1 RPC: set_curriculum_teaching_approval

Tanim: 110:1432-1600; EXECUTE: 110:1601-1604'te PUBLIC'tan alinmis (yalniz service_role).

Parametreler:
- p_schedule_item_id UUID (curriculum_schedule_items.id)
- p_academic_year TEXT
- p_status TEXT DEFAULT 'approved' (yalniz approved/rejected)
- p_text TEXT (not, opsiyonel)

Davranis:
- Kimlik: auth.uid() (RLS)
- Yetki: current_user_has_admin_permission('curriculum.manage')
- Upsert: ON CONFLICT (academic_year, schedule_item_id) DO UPDATE
- Yalniz approved/rejected durumlarina izin verilir

### 6.2 Gate (b) Davranisi (110:378-436)

Egitim yilinda approved statuslu ogretmen onayi olan konular "konu islenmis" sayilir;
onaysiz konular "konu_islenmedi" kilidine takilir. Onay kalici; tatilde otomatik degismez.

### 6.3 Durum: Admin Arayuzu YOK (Yillik Plan 9.5 notu)

RPC var, UI yok. Plan devreye almadan once karar: UI gelistirilecek mi? Servis tarafindan
mi verilecek?

---

## 7. Soru Stogu ve Kaynak Eslesme Kapisi

### 7.1 Gereken Tablolar

- question_sources: soru kaynak fisleri (kaynak tipi, sahiplik, lisans)
- questions: sorular (subject_id, grade_level, is_active, approval_status)
- question_vaults: soru kasalari
- question_vault_memberships: soru-vault eslestirmesi (practice_eligible, membership_status)
- question_curriculum_mappings: soru-mufredat eslesmesi (topic_id, curriculum_version_id, review_status)

### 7.2 Stok Kilidi (110:937-955)

`start_training_session` icerisinde: aday soru listesi bos kalirsa "stok_yok" kilit doner.
Kosullar (110:829-876):
- Soru: subject_id eslesen, grade_level eslesen, is_active=true, approval_status='approved'
- Vault uygunlugu: question_vault_memberships'ta membership_status='active',
  practice_eligible=true, vault is_active=true, vault_type NOT IN ('competition','one_v_one')
- Mufredat eslesmesi: question_curriculum_topics'ta curriculum_version_id = v_version,
  topic_id IN eligible_topics, review_status='approved'

### 7.3 Kaynagi Belirsiz/PDF Eslemesi Eksik Konular

Bu konular icin soru uretimi KAPALI kalir:
- question_sources olmali (soru uretimi icin kaynak fisleri gerekli)
- Her soru icin question_curriculum_mappings (approved) + vault membership (practice_eligible)
  olmali
- Eksik ise: "stok_yok" kilit doner; uretim icin veri yuklenmeli

### 7.4 Kaynak Eslesme Kurallari (pdf-esleme raporundan)

- Sorular dogrudan PDF cozumlerinden turetme ile uretilmez
- Her soru icin kaynak PDF + sayfa referansi gerekli
- ? isareti veya gorsel dogrulama varsa "Inceleme gerekli"
- Bind ugusmasizligi => "Inceleme gerekli"

---

## 8. Uygulama Sirlamasi (Pre-check, Dogrulama, Geri Alma)

### 8.1 On-Kontroller (Yukleme ONCESI)

1. Mevcut fixture verilerini temizle (sadece test icin eklenmis satirlar):
   - curriculum_versions: E2E7-FAZ7 ve FZ15A-E2E satirlarini sil
   - academic_weeks: 44 haftalik fixture'i sil
   - curriculum_schedule_items: FZ15A fixture'i sil
   - curriculum_teaching_approvals: FZ15A fixture'i sil
   - question_curriculum_mappings: FZ15A fixture'i sil
2. Mevcut soru/vault verilerini koru (049 seed grade 12 vaultlari faydali olabilir)
3. Matematik subject_id dogrulama: 430903f3-527e-4e12-b7e8-ac0afdb784aa (sabit)

### 8.2 Yukleme Sirasi (FK bagimliliklari)

1. curriculum_versions (2 satir: TYMM-2026, OGM-2018)
2. curriculum_schedule_profiles (2 satir: TYMM-PROF, OGM-PROF; biri is_default=true)
3. academic_weeks (41 satir: K1-K41, tatil haftalari dahil)
4. topics (TYMM icin ~21 konu x 3 sinif; OGM icin ~7 konu x 1 sinif)
5. subtopics (TYMM icin alt konular; resmi-mufredat raporundan)
6. curriculum_outcomes (varsa, 003'teki outcomes tablosu)
7. curriculum_schedule_items (sinif bazinda T#->K# eslestirmesi, ~7-8 item/sinif)
8. curriculum_prerequisites (9->10->11 zinciri + 12 icin)
9. question_sources + questions (soru stogu yukleme; buyuk islem)
10. question_curriculum_mappings (soru-mufredat eslesmesi; approved)
11. student_profiles guncelleme (schedule_profile_id atamasi)

### 8.3 Dogrulama Senaryolari

Her yukleme adimindan sonra:

**Senaryo 1: Takvim dogrulama**
```sql
SELECT count(*) FROM academic_weeks WHERE academic_year = '2026-2027';
-- Beklenen: 41
SELECT min(starts_at), max(ends_at) FROM academic_weeks WHERE academic_year = '2026-2027';
-- Beklenen: 2026-09-14, 2027-06-28
```

**Senaryo 2: Tatil haftasi varligi**
```sql
SELECT week, starts_at, ends_at FROM academic_weeks
WHERE academic_year = '2026-2027'
  AND week IN (10, 20, 21, 26);
-- Beklenen: 4 satir (tatil haftalari mevcut)
```

**Senaryo 3: Konu agaci bagli**
```sql
SELECT count(*) FROM topics t
JOIN curriculum_versions cv ON cv.id = t.curriculum_version_id
WHERE cv.academic_year = '2026-2027'
  AND t.grade_level IN (9, 10, 11, 12);
-- Beklenen: siniflara gore toplam ~90+ (7-8 konu/sinif x 4 sinif x alt konu varyantlari)
```

**Senaryo 4: Schedule items start_week dogru aralikta**
```sql
SELECT count(*) FROM curriculum_schedule_items si
JOIN curriculum_schedule_profiles sp ON sp.id = si.schedule_profile_id
WHERE sp.academic_year = '2026-2027'
  AND si.start_week BETWEEN 1 AND 41;
-- Beklenen: tum satirlarin start_week 1-41 arasinda
```

**Senaryo 5: Onkosul verisi mevcut ve dogru**
```sql
SELECT count(*) FROM curriculum_prerequisites cp
JOIN curriculum_versions cv ON cv.id = cp.curriculum_version_id
WHERE cv.academic_year = '2026-2027'
  AND cp.requirement_level = 'approved';
-- Beklenen: > 0
```

**Senaryo 6: Soru stogu yeterli**
```sql
SELECT si.grade_level, count(DISTINCT q.id) as soru_sayisi
FROM questions q
JOIN question_curriculum_mappings qcm ON qcm.question_id = q.id
JOIN curriculum_versions cv ON cv.id = qcm.curriculum_version_id
JOIN curriculum_schedule_items si ON si.topic_id = qcm.topic_id
WHERE cv.academic_year = '2026-2027'
  AND q.is_active = true AND q.approval_status = 'approved'
  AND qcm.review_status = 'approved'
GROUP BY si.grade_level;
-- Beklenen: her sinif icin yeterli soru (min ~20-30/sinif)
```

**Senaryo 7: Tatilde antrenman erisimi**
Dogrudan test: 16-20 Kas 2026 (K10, ara tatil) tarihinde bir ogrenci
start_training_session cagirsa:
- Eger K10'da academic_weeks satiri varsa: basarili donus (onayli konular icin)
- Eger K10'da academic_weeks satiri YOKSA: P0001 hatasi (fail-closed) -> HATA

### 8.4 Geri Alma Plani

Hatali yukleme durumunda:

1. **Versiyon/tema hatali:** ilgili versiyondaki tum bagimli satirlari sil
   (topics -> subtopics -> curriculum_schedule_items -> curriculum_prerequisites)
2. **academic_weeks hatali:** 2026-2027 yilindaki tum satirlari sil ve yeniden yukle
   (EXCLUDE constraint sayesinde cakismaz)
3. **Schedule items hatali:** ilgili sinif/versiyondaki tum item'lari sil ve yeniden yukle
4. **Onkosul zinciri hatali:** curriculum_prerequisites tablosunu temizle ve yeniden yukle
5. **Soru stogu hatali:** question_curriculum_mappings'i temizle; sorulari koru

Oncelik: academic_weeks VE curriculum_versions en kritik; bunlar yanlis yuklenirse tum
sistem calismaz. Bu iki tablo icin seed script'i double-check yapilmali.

---

## 9. Karar Listesi

Acil karar bekleyen maddeler:

1. **is_default versiyonu:** TYMM-2026 mi yoksa OGM-2018 mi is_default=true olacak?
   Tum siniflar icin varsayilan versiyon bu olacak. Oneri: TYMM-2026 (9/10/11 cogunluk).

2. **academic_weeks numarandirmasi:** K1-K41 (takvim haftasi, tatil dahil) yuklenmeli;
   bu raporun onerisi bu. Karar onayi bekleniyor. Yillik plan 9.2'nin "tatil satiri
   yoklugu" onerisi REDDEDILMELIDIR.

3. **Ogretmen onay giris yontemi:** RPC mevcut (110:1432) ama UI yok. Plan:
   (a) Yalniz RPC + HyperClerk/servis tarafindan mi?
   (b) UI gelistirilecek mi? Hangi fazda?

4. **Onkosul verisi kaynagi:** 9->10->11 zinciri ve 12 onkosullari icin veri nerden
   gelecek? Manuel mi yazilacak, yoksa otomatik mi turetilecek?

5. **Soru stogu onkosulu:** Mevcut 8 grade-12 soru + 37 vault grade-12 odakli. 9/10/11
   icin soru stogu sifir. Soru uretimi / yukleme ne zaman?

6. **student_profiles schedule_profile_id:** Her ogrenciye dogru profile atanmali.
   Mevcut ogrenciler (E2E_Ogrenci_A/B, FZ15A_Ogrenci_A, test1) icin yeni
   atama gerekir; yeni ogrenciler icin servis tarafinda otomatik atama mi?

7. **Kisa hafta telafisi:** T7/T15/T28/T32'de ~1 saat kayip; 9-11'de okul temelli
   10 saat tampon; 12'de T37 (K41) yedek. Bu veri DB'de nasil temsil edilecek?

8. **Okul temelli 10 saat (9-11):** Bu 10 saat curriculum_schedule_items'ta karsiligi
   yoktur; zümre kararidir. Gerekli mi? Eger evetse nasil yuklenecek?

---

## 10. Ozet

Bu rapor salt-okunur analiz ve karar onerisi icerir; hicbir DB yazisi, migration,
kod degisikligi, soru uretimi veya commit/push icermemektedir.

**En kritik bulgu:** Yillik plan 9.2'nin "tatil satiri yoklugu" onerisi
`_faz2_require_period` fail-closed istisnasiyla celiskilidir; dogru yaklasim tatil
satirlarini da iceren K1-K41 takvimi yuklemektir.

**Sonraki adim:** Kullanici "devam" onayi ile yukaridaki karar maddelerini netlestirir;
ardindan db-uygulama-plani'na gore yukleme scripti yazilabilir.

Durdum.
