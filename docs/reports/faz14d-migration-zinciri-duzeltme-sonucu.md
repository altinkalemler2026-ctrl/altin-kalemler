# Faz 14D Nihai Rapor — Migration Zinciri Düzeltmesi (113/115/116 Taşındı)

**Tarih:** 2026-09-17
**Model:** big-pickle (opencode)
**Sorumlu:** selami
**Faz:** 14D (disposable ortamda temiz reset zinciri doğrulaması + QA)

---

## 1. Sonuç Özeti

| Metrik | Değer |
|---|---|
| **Durum** | ⚠️ KISMI BAŞARI (taşıma doğrulandı; 2 önceden var CI engeli raporlandı) |
| Taşınan dosyalar | `113`, `115`, `116` → `docs/rollbacks/` |
| 116 işareti | `116_faz13c_mat1046_pilot_kaynak_fisleme_UYGULANMADI_TASLAK.sql` |
| `supabase/migrations/` dosya sayısı | **114** |
| Disposable ortam | `faz14d-qa` (port 58322), CLI `supabase@2.115.0` (CI ile aynı) |
| Uygulanan zincir | 001→112, 114, 117, 118 (113/115/116 YOK) |
| `schema_migrations` sırası teyidi | ✅ 113/115/116 yok, son 118 |
| Alt konu (a6) | ✅ **69** |
| Kazanım (a7) | ✅ **90** |
| 114'ün 5 UUID'si | ✅ **5** |
| 116 kaynak kaydı | ✅ `question_sources` = 0 (uygulanmadı, doğru beklenen) |
| 117/118 nesneleri | ✅ tablolar + RPC mevcut |
| CI chain assertion (chain) | ✅ CHAIN_OK |
| Faz 10B invariant | ✅ SECURITY_INVARIANT_OK |
| Tip drift guard | ⚠️ **DRIFT VAR** (önceden var, taşımayla ilgisiz) |
| QA suite'leri | ⚠️ faz1 OK; faz2/3/35/4 FAIL (önceden var, taşımayla ilgisiz) |
| Ana DB | ✅ değişmedi (109 migration, a7=90, a6=69) |
| Docker envanter | ✅ faz14d izi yok (container + volume + temp silindi) |
| Commit / push | **YAPILMADI** (kontrat gereği yasak) |

---

## 2. Yapılan Değişiklik

`supabase/migrations/` içindeki rollback-varisi dosyalar, `supabase db reset` sıralı
uyguladığı için temiz zinciri bozuyordu:

- `113` (a6/a7 DELETE) → `112`'nin yüklediği alt konu/kazanımı siliyordu.
- `115` (belirsiz kazanım rollback) → `114`'ün eklediği 5 UUID'yi siliyordu.
- `116` (draft, `D:\evraklar` yolu içeriyor) → uygulanıyordu ve tohum kaynak
  kayıtları oluşturuyordu.

Bu üç dosya, otomatik migration akışının DIŞINA alındı (çalıştırılmayacak
dokümantasyon konumu). Taşıma sırasında içerik DEĞİŞTİRİLMEDİ (hash ile teyit edildi):

| Yeni ad | SHA-256 |
|---|---|
| `docs/rollbacks/113_faz12b_rollback_kazanim_ve_alt_konu.sql` | `57B8E1FDD89BB3D631DC1DE0D4A7C506B61BDBDFA2221C6DDF308FA0B4AFE095` |
| `docs/rollbacks/115_faz12c_rollback_belirsiz_kazanim.sql` | `911CC864F813B78EFCA3A233FB35B3BF2ED88DBB6F44CD370A907E0177E1E509` |
| `docs/rollbacks/116_faz13c_mat1046_pilot_kaynak_fisleme_UYGULANMADI_TASLAK.sql` | `2063210CC855838D766F687F850299FD61A15368BB80624E8933ED397FE4D6CD` |

`116`, adına `_UYGULANMADI_TASLAK` eklenerek kalıcı olarak işaretlendi. `111`, `112`,
`114`, `117`, `118` yerinde duruyor.

---

## 3. Disposable Ortamda Temiz Reset Doğrulaması

CI ile aynı CLI sürümü (`npx supabase@2.115.0`) ve benzersiz ad/portlarla
(`faz14d-qa`, db port 58322, ana stack'ten ayrı) kurulan geçici ortamda
`supabase db reset` uygulandı. Ortam CI ile aynı konfigürasyonda (config kopyası +
114 migration, seed yok).

Doğrulananlar:

1. **Sıra:** `schema_migrations` baştan sona 113/115/116 İÇERMEZ; son uygulanan 118.
2. **Veri:** `subtopics` a6 = 69, `curriculum_outcomes` a7 = 90 → dolu müfredat.
3. **114'ün 5 UUID'si** tam mevcut (115 rollback uygulanmadığı için).
4. **117/118** `candidate_question_batches`, `candidate_batch_candidate_results`,
   `register_candidate_question_batch(jsonb)`, `get_candidate_question_batch_contract()`
   mevcut.
5. **116 etkisiz:** `question_sources` = 0, `ai_generation_specs` = 0,
   `ai_question_staging` = 0 → draft migration yürümedi.
6. **CI chain assertion:** authenticated → `subjects` SELECT var, anon →
   `subjects` kaldırılmış → `CHAIN_OK`.
7. **Faz 10B invariant:** `SECURITY_INVARIANT_OK` (yeni migration'larla bozulmamış).

Bu sonuçlar, taşımanın SUCCESS olduğunu gösterir: temiz reset, dolu ve tutarlı bir
11. sınıf matematik şeması üretiyor.

---

## 4. Önceden Var CI Engelleri (Taşımayla İlgisiz)

Düzeltme amaçLANDIĞI gibi çalışsa da, CI bütününün yeşile dönmesi için taşınan
dosyalarla İLGİSİZ iki ayrı sorun var:

### 4.1 Tip drift guard FAIL

Disposable DB'den üretilen tipler `12385` satır; committed
`src/lib/supabase/types.ts` `12263` satır. Fark, `117/118` migration'larının
(`candidate_question_batches`, `candidate_batch_candidate_results` ve RPC'leri)
committed types.ts'te bulunmamasından kaynaklanıyor. 117/118 "untracked" olduğu ve
types.ts hiç yeniden üretilmediği için bu drift 113/115/116'dan bağımsız; commit
öncesi types.ts rejenerasyonu (veya guard'ın bu tabloları tanıması) gerekir.

### 4.2 QA suite'leri: academic_weeks çakışması

QA fixture'ları `current_date` merkezli hafta ekliyor (örn.
`qa_faz2` satır 139-141: `('QA-Y-2099', 5, current_date - 3, current_date + 4)`).
Bugün `2026-09-17` olduğundan bu aralık `[2026-09-14, 2026-09-21)` oluyor ve
`111_faz12a_2026_2027_matematik_mufredati.sql` satır 99-103'ün eklediği
`2026-2027` hafta 1 (`[2026-09-14, 2026-09-21)`) ile birebir çakışıyor →
`academic_weeks_no_cross_year_overlap` exclusion constraint ihlali.

Sonuçlar (disposable, doğru sırayla):
- `qa_faz1_local_validation.sql` → OK (34|34|0)
- `qa_faz2` → FAIL(3) — academic_weeks çakışması
- `qa_faz35` → FAIL(3) — aynı sebepten
- `qa_faz4` → FAIL(3) — aynı sebepten
- `qa_faz3` → FAIL(3) — aynı sebepten (self-raising)

Bu, `current_date` fixture'ları ile 111'in kalıcı 2026-2027 takviminin her
"bugün" tarihinde çakışabilecek deterministik olmayan bir etkileşimi; taşınan
dosyaların varlığına/yokluğuna bağlı değil. Test gevşetme/skip yapılmadı; ortam
yerinde kalıp gerçek çıktı kaydedildi. Kalıcı çözüm, QA fixture tarihlerinin sabit
bir referans tarihle (veya 2026-2027 dışı bir aralıkla) deterministik hale
getirilmesidir — ayrı bir faz konusu.

---

## 5. Ana DB ve Çevre Temizliği

- **Ana DB:** Hiçbir yazma işlemi yapılmadı. Son durum başlangıçla aynı:
  `schema_migrations` = 109, a7 = 90, a6 = 69. (Tüm doğrulama disposable container'a.)
- **Temizlik:** `supabase stop --no-backup` sonrası faz14d container ve volume'ları
  tamamen kaldırıldı; geçici tip dosyası ve temp dizini silindi. Docker envanterinde
  faz14d izi yok.

---

## 6. Commit/Push Kararı

- **Migration zinciri düzeltmesi:** GÜVENLİ — 113/115/116 artık reset'i bozmayacak;
  disposable temiz zincir doğrulandı (69/90 dolu şema + CHAIN_OK + invariant OK).
- **Bütünün CI yeşili:** GÜVENLİ DEĞİL — commit/push sonrası CI'ın (1) tip drift
  guard ve (2) academic_weeks QA çakışmasında kırmızı kalacağı kesindir. Bu iki
  engel taşınan dosyalardan kaynaklanmaz; ayrıca ele alınmalıdır.
- Kontrat gereği commit/push yapılmadı; onay bekleniyor.

---

## 7. Önerilen Sıradaki Adım

1. `src/lib/supabase/types.ts` rejenerasyonu (117/118 tabloları dahil) → tip drift
   engeli çözülür.
2. QA fixture tarihlerini deterministik referansla 2026-2027 takviminin dışına
   taşıma (ör. sabit `2000-12-xx` aralıkları) → academic_weeks çakışması çözülür.
3. Her iki engel yeşillendikten sonra 111-118 + 14D değişiklikleri tek fazlı
   commit ile CI doğrulamasına verilir.