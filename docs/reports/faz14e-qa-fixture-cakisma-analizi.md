# FAZ 14E — QA FIXTURE ÇAKIŞMA ANALİZİ

- Tarih: 2026-09-17
- Durum: ANALİZ TAMAMLANDI — DEĞİŞİKLİK YAPILMADI
- Kapsam: `resolve_current_academic_period()` / current-timestamp bağımlılığı ve
  2026-2027 resmî takviminin QA/yerel E2E fixture'larıyla çakışması
- Kanıt ortamı: disposable stack `supabase_db_faz14e-qa` (yalnız okuma SELECT +
  geri alınan DO blokları; kalıcı yazım yok)

## 1. Başlangıç gerçeklik kontrolü (salt okunur)

- Aktif branch: `main`
- Yerel HEAD: `5adcc85a9803ed3b1ebcb9675f9596e7d4ffae7b`
- `origin/main`: `5adcc85a9803ed3b1ebcb9675f9596e7d4ffae7b` (aynı; ahead/behind 0/0)
- Çalışma ağacı: kullanıcıya ait geniş modified/untracked küme — dokunulmadı
- CI: Faz 12 sonrası push yapılmadığından bu analiz salt okunur kalmıştır

## 2. Amaç

Migration 111 (`111_faz12a_2026_2027_matematik_mufredati.sql`) resmî 2026-2027
takvimini (K1–K41) yükledikten sonra, `current_date`-bağımlı veya sabit 2026-2027
tarihli akademik hafta yazan QA/yerel E2E fixture'larının neden ve nasıl
çakıştığını kanıtlı şekilde ortaya koymak; dosya üzerinde herhangi bir değişiklik
yapmamak.

## 3. Kök nedenler

### RC-1 — Global (yıllar arası) EXCLUDE constraint'i aktif

- `067` aynı yıl içi `academic_weeks_no_overlap` GiST kısıtını koyar.
- `074` buna ek olarak **yıllar arası global** `academic_weeks_no_cross_year_overlap`
  GiST kısıtını ekler: `daterange(starts_at, ends_at, '[)')` herhangi iki satırda
  kesişirse `23P01 exclusion_violation`.
- `111` resmî 2026-2027 takvimini `[2026-09-14, 2027-06-28)` aralığına döşer
  (41 satır; `delete from ... where academic_year='2026-2027'` ile başlar).
- Sonuç: Bu pencere içinde **başka hiçbir eğitim yılı/adı** o tarih aralığının
  herhangi bir gününe dokunamaz.

### RC-2 — `ON CONFLICT DO NOTHING` exclusion'ı korumaz

Postgres semantiği: `ON CONFLICT (academic_year, week) DO NOTHING` yalnızca aynı
arbiter (PK) üzerindeki çakışmayı atlar; **EXCLUDE kısıtı ihlalini yakalamaz**
(23P01 arar → fixture transaction'ı düşer). Empirik olarak doğrulandı (bkz. §4).

### RC-3 — `resolve_current_academic_period()` global duvar-saati çözücüdür

`067:83-99` fonksiyonu:

```sql
where (current_timestamp at time zone 'utc')::date >= w.starts_at
  and (current_timestamp at time zone 'utc')::date < w.ends_at
order by w.starts_at
limit 1
```

- Yalnız UTC takvim gününü kullanır; kullanıcı/sınıf bağlamı yoktur (ürün
  kararı; deterministik).
- Aynı günü kapsayan birden fazla eğitim yılı varsa `starts_at`-sıralı ilk satır
  seçilir; başlangıç eşitse seçim **belirsizdir** (tie, LIMIT 1).
- QA fixture'larının "test yılım bugünü kapsayan dönem" varsayımı, gerçek
  takvimin bugünü (ve ~9,5 ay boyunca her günü) kapsaması nedeniyle **gölgelenir**:
  - QA yılının haftası gerçek K1'den sonra başlarsa → gerçek yıl kazanır.
  - Başlangıç eşitse (ör. `current_date - 3`) → belirsiz.
  - Yalnızca gerçek takvimin bugünü kapsamadığı pencerede (yaz aralığı) QA yılı
    çözülür; bu geçici/sezon bağımlıdır ve her yeni akademik yıl yeniden kırılır.

## 4. Empirik kanıt (faz14e-qa disposable stack)

- DB'de yalnız `2026-2027` (41 satır) mevcut.
- `resolve_current_academic_period()` → **`2026-2027 | 1`** (bugün K1 = 2026-09-14..09-21).

### 4.1 `local-faz7-e2e-fixture.sql` — 44 haftanın gerçek takvimle eşlemesi

Fixture haftaları `2026-08-31 + (wk-1)*7` tabanlıdır; gerçek takvim K1..K41'dir.

| Fixture haftası | Aralık | Sonuç |
|---|---|---|
| 1–41 | — | PK_SKIP (gerçek K1..K41 key'i çakar; `DO NOTHING` güvenle atlar) |
| **42** | 2027-06-14..06-21 | **EXCLUDE_FAIL (23P01)** — aralık gerçek K40 ile kesişir, key serbest |
| **43** | 2027-06-21..06-28 | **EXCLUDE_FAIL (23P01)** — aralık gerçek K41 ile kesişir, key serbest |
| 44 | 2027-06-28..07-05 | OK_INSERT (gerçek takvimin dışına taşar) |

Sonuç: fixture, sabit tarihleri yüzünden **kalıcı olarak** kırıktır; 111 varlığında
hiçbir gün çalışmaz. Doğrulama bloğunda `('2026-2027', 3, 09-14, 09-21)` insert'i
gerçek K3'ün key'ini tuttuğu için `UNIQUE_VIOLATION` döndü; bu, fixture w1–w41'in
PK tarafından korunduğunu da teyit eder.

### 4.2 `local-faz11-e2e-fixture.sql` — QA11E-Y hafta 5

- `('QA11E-Y', 5, current_date-3, current_date+4)` insert'i → DB'de
  **`EXCLUSION_VIOLATION`** (aralık bugün gerçek K1 ile kesişir). `on conflict do
  nothing` korumaz; fixture başarısız.
- Bugün ≈ 09-14..09-21 → çakışma akademik yıl içindeki **her gün** oluşur.

### 4.3 `local-faz15a-e2e-fixture.sql` — pencere bağımlılığı

- Kendi takvimi **yoktur**; gerçek takvimi kullanır ve "start_week INCLUSIVE=3;
  cari hafta = 3" varsayar (`110` `_faz15_eligible_scope`: `si.start_week <= v_week`).
- Bugün çözülen hafta = **1** → `3 <= 1` yanlış → kapsam `takvim_gelmedi` kilidine
  düşer → Faz 15A E2E bugün kilitli. Test yalnızca çözülen gerçek hafta ≥ 3 iken
  geçer (2026-09-28 sonrası). Bu, fixture'ın yazıldığı andaki duvar-saatine
  sabitlenmiş olmasının kanıtıdır (authoring dönemi gerçek hafta 3).

## 5. Etkilenen fixture envanteri

### A grubu — Insert-anı EXCLUDE çakışması (akademik yıl içinde çalışınca 23P01)

| Fixture | Yıl / hafta | Kayıt |
|---|---|---|
| `local-faz7-e2e-fixture.sql` | 2026-2027 w42/w43 (sabit) | satır 121-126; **kalıcı kırık** |
| `local-faz11-e2e-fixture.sql` | QA11E-Y w5 `current_date±` | satır 44-50 |
| `qa_faz2_local_validation.sql` | QA-Y-2099 w5/w6 | satır 139-141 |
| `qa_faz3_local_validation.sql` | QA3-Y-2099 w5/w6 | satır 136-138 |
| `qa_faz4_local_validation.sql` | QA4-Y-2099 w5/w6 | satır 235-237 |
| `qa_faz5_local_validation.sql` | QA5-Y-2099 w5/w6 | satır 205-207 |
| `qa_faz2_parallel_probe.sql` | QA-P-2099 `today±30` | satır 86-88 |
| `qa_faz6_targeted_review_local.sql` | QA6-Y w5 | satır 146-148 |
| `qa_faz11_progress_feedback_local.sql` | QA11-Y w5 | satır 151-153 |
| `qa_scoring_v1_094_local.sql` | QA94-Y w5 | satır 138-140 |
| `qa_grade_hardening_093_local.sql` | QA93-Y w5 | satır 145-147 |
| `qa_data_boundary_095_local.sql` | QA95-Y w5 | satır 134-135 |
| `qa_competition_pack_auto_prepare.sql` | **'2025-2026'** w1/w2 `today±7` | satır 124-126; ayrıca yıl adı yanlış etiketli (geçmiş yıl, cari tarih) |
| `qa_faz35_local_validation.sql` | QA-CAL-2099 w1 `today±2/5` | satır 183-186; ayrıca kendi "yıllar arası çakışma" senaryosu gerçek takvimle kirlenir |

### B grubu — Sessiz guard atlaması / çözüm gölgesi (insert başarılı ama yanlış yıl çözülür)

| Fixture | Mekanizma |
|---|---|
| `qa_faz9_gamification_local.sql:173-189` | `if not exists (bugünü kapsayan hafta)` guard'ı gerçek K1 nedeniyle **hiç tetiklenmez**; QA9-YIL haftası yazılmaz; `resolve_...` gerçek 2026-2027 döner; QA9 beklentileri (QA9-YIL sayaçları) tutmaz. |

### C grubu — Duvar-saati penceresine sabitlenmiş `start_week` (zaman-kırılgan)

| Fixture | Mekanizma |
|---|---|
| `local-faz15a-e2e-fixture.sql` | `start_week=3`; çözülen gerçek hafta < 3 iken `takvim_gelmedi`. Bugün (w1) kilitli. |

Not: `qa_faz1_local_validation.sql` hafta yazmaz (`academic_weeks` envanterinde
yok); `student_weekly_counters` satırlarını doğrudan yazar. Yine de çözüm
gölgesine açık olup olmadığı, rerun sıralamasına bağlıdır (fixture setinde teyit).

## 6. Current-timestamp özeti

- `resolve_current_academic_period()` duvar-saati UTC günüyle çalışır; QA
  fixture'larının "test yılımı dönem olarak çözdürme" gereksinimi yalnız test
  haftası bugünü kapsarken sağlanabilirdi. Gerçek takvim bugünü kapsadığından:
  1. Test haftası = gerçek pencere içi `current_date`-bağımlı aralık → EXCLUDE ile
     **hiç yazılamaz** (A grubu).
  2. Yazılabilecek durumda bile çözücü gerçek yılı tercih eder (RC-3).
  3. Guard-bazlı (QA9) durumda sessizce atlanır (B grubu).
- Kendi haftasını yazmayan fixture'lar (C grubu) gerçek haftaya göre çalışır ve
  sabit `start_week` nedeniyle zaman-kırılgandır.

## 7. Sonuç

- Migration 111 + 074, QA fixture tasarımının dayandığı iki varsayımı birden
  geçersiz kıldı: (a) "test yılımın haftası bugünü kapsayabilir ve eklenebilir",
  (b) "o hafta `resolve_current_academic_period` tarafından dönem olarak çözülür".
- Sonuç: 14 fixture'ın akademik yıl içindeki çalışmasız kalması; bunlardan
  `local-faz7` (sabit tarihler) **kalıcı olarak** kırıktır; `local-faz15a` bugün
  kilitlidir; kalanlar `current_date`-bağımlı olduğundan 2026-09-14 → 2027-06-28
  aralığında kırıktır ve **her yeni akademik yıl için düzenli yeniden kırılır**.

## 8. Önerilen iyileştirme yönleri (UYGULANMADI; onay bekler)

1. **Yerel E2E (faz7/faz11/faz15a):** sahte takvim yazmayı bırak; çözülen **gerçek**
   dönemi temel al. `faz7`: 121-126 satırlarındaki takvim insert bloğunu kaldır
   (POSTCONDITION yalnız dönemin VAR olmasını ister; gerçek K1 karşılar).
   `faz11`/`faz15a`: schedule/onay/sayaç değerlerini runtime'da çözülen
   `(academic_year, week)`'e bağla (ör. `start_week := çözülen_hafta`,
   `end_week := NULL`).
2. **QA doğrulama scriptleri (A/B grubu):** sabit `week=5` beklentisi yerine
   runtime çözülen haftayı kullan; test dokusunu (sayaç, exposure, kota) çözülen
   yıl/haftaya hizala. `qa_competition_pack` yıl adını cari yıla taşır. `qa_faz35`
   kendi yıllar-arası testini gerçek takvimden izole eder.
3. **Product SQL'e dokunulmaz:** `067/068` duvar-saati UTC çözümü ürün kararıdır;
   QA, çözücüyü değil kendini gerçek takvime bağlamalıdır.

Değişiklik kapsamı 15+ SQL fixture/runner dosyasına yayıldığı için ayrı bir faz
(14F) olarak planlanması ve "devam" onayıyla uygulanması önerilir.