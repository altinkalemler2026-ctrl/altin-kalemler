# Faz 13D — Kaynak Kayıt Modülü / DB Şeması Uyumsuzluğu Çözüm Planı

- Tarih: 2026-09-16
- Durum: ANALİZ TAMAM — hiçbir kod, DB, migration, test, UI, kaynak kaydı veya PDF
  değişikliği YAPILMADI. Raporla-dur fazıdır.

---

## 0. Yöntem ve kanıt kaynakları

- DB sözleşmesi: `004_questions_foundation.sql` + canlı `supabase_db_yarisma-programi`
  üzerinde `information_schema.columns`, `pg_policies`, `role_table_grants`, `pg_roles`
  salt-okunur sorguları.
- Kod: `src/lib/content/source-registry.ts`, `src/lib/content/types.ts`,
  `src/lib/content/source-registry.test.ts`, `src/lib/supabase/types.ts`
  (Supabase generated — DB'ye birebir bağlı).
- İlişki/üretim hattı: `006_ai_question_pipeline.sql`, `007_ai_copyright_and_review.sql`,
  `036_originality_similarity_copyright_gate.sql`, `039_human_final_question_promotion.sql`.
- Kullanım/takip: codebase-memory `trace_path` (inbound) — servis fonksiyonlarının
  **0 canlı çağıranı** var (yalnız kendi test dosyası).
- Derleme kanıtı: `npx tsc --noEmit --skipLibCheck` çıktısı (salt-okunur, yazma yok).
- Faz 13C teslimi: migration 116 taslağı + fiş künyeleri.

Altta "DB", canlı lokal DB'nin gerçek durumunu (004 + tüm zincir uygulanmış),
"DB-tipi" ise `src/lib/supabase/types.ts`'i ifade eder. İkisi birebir uyumludur.

---

## 1. Kodun kullandığı ama DB'de olmayan alanlar

`source-registry.ts` + `types.ts` aşağıdaki alanları referans/insert eder; bunların
hiçbiri DB'de (ve dolayısıyla DB-tipinde) YOKTUR:

### insert edilen (registerSourceDocument → question_sources)
| Alan | DB durumu | Sonuç |
|---|---|---|
| `source_name` | yok (gerçek: `title`) | TS2353 excess property + runtime 42703 |
| `file_hash` | yok | TS2345 (`.eq("file_hash", ...)`) + runtime 42703 |
| `file_size_bytes` | yok | TS2353 |
| `page_count` | yok | TS2353 |
| `document_version` | yok | TS2353 |
| `rights_owner` | yok (gerçek: `ownership_status`) | TS2353 |
| `usage_rights` | yok (gerçek: `license_status` + `commercial_use_allowed`) | TS2353 |
| `metadata` (jsonb) | yok | TS2353 |

### select edilen ama kodu karşılayan (registerSourceDocument sonrası)
| Alan | DB durumu |
|---|---|
| `process_status` | yok |
| `needs_ocr` | yok |

### insert edilen (linkQuestionToSource → question_source_locations)
| Alan | DB durumu | Sonuç |
|---|---|---|
| `section_name` | yok (gerçek: `test_code` + `test_number`) | TS2322 never |
| `question_number_on_page` | yok (gerçek: `question_number`) | TS2322 |
| `confidence_score` | yok (gerçek: `extraction_confidence`) | TS2322 |
| `needs_manual_review` | yok | TS2322 |
| `metadata` (jsonb) | yok | TS2322 |

`types.ts` içindeki `SourceDocumentInput`/`SourceLocationInput`/`SourceDocumentRecord`
soyut arayüzleri de bu hayali alanlarla yazılmıştır.

---

## 2. DB'de olan ama kodun ele almadığı gerekli alanlar

### question_sources (DB), servis tarafından hiç kullanılmıyor
- `title text NOT NULL` — kod `source_name` ile doldurmaya çalışır; bu kolon yok.
- `publisher`, `author`, `publication_year` — Fiş taslağında NULL; servis yok.
- `file_name` — gerçek dosya adı; serviste alan yok.
- `source_reference` — kaynak yolu; serviste alan yok.
- `ownership_status` (NOT NULL, 'unknown') — sahiplik; `rights_owner` serbest metin
  ile karıştırılmış, allowlist'e aykırı.
- `license_status` (NOT NULL, 'unknown') — `usage_rights` serbest metin yerine
  denetlenebilir durum değeri.
- `commercial_use_allowed` (NOT NULL, false) — ticari kullanım; hiç yok.
- `notes` — lisans notu/inceleme yönlendirmesi; hiç yok.

### question_source_locations (DB), servis tarafından kullanılmıyor
- `test_number`, `test_code`, `question_number`, `source_question_code`,
  `crop_reference` — gerçek konum sözleşmesi.
- `extraction_confidence numeric(5,4) [0..1]` — `confidence_score (0..1 clamp)`
  yerine sabit aralık CHECK.
- `UNIQUE(question_id, source_id)` + `idx_question_source_locations_lookup` —
  servis ON CONFLICT kullanmaz; tekrar bağlamada hata üretir.

---

## 3. Her servis fonksiyonunun canlı DB'de vereceği olası hata

| Fonksiyon | Derleme | Canlı DB (service_role ile) |
|---|---|---|
| `validateSourceInput` | 🟢 derlenir (kendi içinde tutarlı) | DB ile ilgisi yok; sorun `register...` aşamasında |
| `registerSourceDocument` | 🔴 TS2345 (.eq file_hash), TS2353 (7 excess prop), TS2339 (id, select kolonları) | `.select("source_type...").eq("file_hash", h)` → `column "file_hash" does not exist` (42703). Düzeltilse bile insert `source_name` vb. → 42703. select-list `process_status`, `needs_ocr` → 42703. **Asla başarılı olmaz.** |
| `routeExtraction` | 🟢 saf fonksiyon, DB yok | Etkilenmez; ancak `process_status`/`needs_ocr` DB'de olmadığından ürettiği sonuç saklanamaz |
| `mapProcessStatus` | 🟢 | DB'de `process_status` kolonu yok → okuyacak kaynak yok (allowlist zaten DB dışında) |
| `linkQuestionToSource` | 🔴 TS2322 (5 satır: page/section/conf/question/needs_manual/metadata 'never') | Insert `section_name`, `confidence_score`, `needs_manual_review`, `metadata` → 42703; tekrarlanan (question_id,source_id) → UNIQUE ihlali 23505 (ON CONFLICT yok) |

Modern harness testleri (`source-registry.test.ts`) sahte client üzerinde çalıştığı
için bu hataları **yakalamaz**; üstelik test dosyası da derleme hatası verir
(TS2345 — eksik zorunlu alanlar; `SourceDocumentInput` üyeleri required).

Diğer yandan **üretim hattı DB sözleşmesini doğru kullanıyor**: 039 promotion
`question_source_locations`'ı `v_staging.source_*` kolonlarıyla (`page_number`,
`test_number`, `test_code`, `question_number`, `source_question_code`,
`extraction_confidence`) ve `ON CONFLICT (question_id, source_id) DO NOTHING` ile
doldurur. Yani DB, canlı kullanımda tutarlı; sorun yalnız TS modülünde.

---

## 4. Çözüm seçenekleri

### Seçenek A — Kodu mevcut DB şemasına uyarla (ÖNERİLEN)
`source-registry.ts`, `types.ts` ve testleri DB sözleşmesine hizala:
- `registerSourceDocument`: `source_name`→`title`, `file_hash`→kaldır,
  lookup anahtarı `file_name`, insert `publisher/author/publication_year/file_name/
  source_reference/ownership_status/license_status/commercial_use_allowed/notes`;
  selamete dönen select DB kolonlarıyla. `process_status`/`needs_ocr` çıkar,
  `mapProcessStatus` durum haritasını `license_status`+`ownership_status` override
  ile ya da kaldır.
- `linkQuestionToSource`: `section_name`→`test_code`(+`test_number`),
  `question_number_on_page`→`question_number`, `confidence_score`→`extraction_confidence`,
  `needs_manual_review`→kaldır (DB'de yok; NOT çözümü 039'da yok), `metadata`→kaldır.
  `UNIQUE(question_id,source_id)` için `ON CONFLICT ... DO UPDATE/NOTHING` semantiği.
- `types.ts`: arayüzleri DB Row/Insert'e eşle; hayali `process_status` sabitleri/
  `needs_ocr` kaldır.
- Testler: mock adları gerçek kolonlara çevrilir; DB-tipiyle uyum varsayılan mock.

DB değişikliği: **sıfır**. Migration eklenmez.

### Seçenek B — Yalnız gerekli ise DB'ye additive alan ekle
Koda zorunlu `file_hash`/metadata desteği isteniyorsa (içerik değişmediği sürece
mükerrer koruması için künye tanımı), sıfır-risk additive migration:
- `file_hash text` + kısmi unique index (`WHERE file_hash IS NOT NULL`).
- Yalnız gerekiyorsa `file_size_bytes bigint`, `page_count integer`,
  `document_version text` — hepsi NULL-able, defaultsuz (mevcut satır yok).
- `process_status`/`needs_ocr`/`usage_rights`/`rights_owner`/`metadata` EKLEME
  (mevcut `ownership_status`/`license_status`/`commercial_use_allowed` zaten
  denetlenebilir; `metadata`-gibi serbest yapı DB'ye yük bindirir).

Bu seçenek yalnız A ile birlikte anlamlıdır (kod yine DB'ye göre yeniden yazılır).

---

## 5. Seçeneklerin karşılaştırması

| Boyut | Seçenek A (kodu DB'ye uyarla) | Seçenek B (additive DB) |
|---|---|---|
| Veri güvenliği | Hiçbir DB değişimi; RLS/grant sıfır risk. `title NOT NULL` vb. sözleşme DB tarafında korunur. | `file_hash` eklenirse mevcut satırları etkilemez (NULL-able). Yine de migration + RLS kapsam değerlendirmesi (108 hardening sonrası default ACL). |
| Migration etkisi | Yok. | 1 idempotent migration + kısmi unique index; backfill gerektirmez (0 satır). |
| Test etkisi | Test mock'ları gerçek kolonlara çevrilir; DB-tipiyle doğrulama mümkün olur. | A'daki test düzeltmelerine ek gereksinim yok. |
| Geriye uyumluluk | Servis **hiçbir canlı çağıranı olmayan izole modül** (trace: 0 inbound) → uyarlama başka kodu kırmaz. DB sözleşmesi dokunulmaz (039 vb. korunur). | Sütun eklemeleri geri dönüşü yalnız migration ile; kaldırılacaksa veri kaybı yok (0 satır). |

---

## 6. En küçük ve güvenli öneri

**Seçenek A, ek DB değişimi olmadan.** Gerekçe:
1. DB sözleşmesi üretimde kanıtlı (039 çalışıyor); kod yalnız fişleme/içerik hattının
   TS arayüzü — hayali şemaya endekslenmiş ve 0 çağıranı var. Doğru taraf DB'dir.
2. Mevcut şema pilot fişleme için yeterli: künye (publisher/author/yıl/file_name/
   source_reference), sahiplik/lisans allowlist'i (ownership_status/license_status/
   commercial_use_allowed) ve notes zaten var. `file_hash` içerik kimliği ancak
   mükerrer koruması için "olsa iyi"dir, şart değildir (fişleme en az `file_name`
   üzerinden idempotent; özellikle 116 NOT EXISTS guard'ı).
3. `process_status`/`needs_ocr`/`metadata` eklemek şema kirliliğidir; OCR yol haritası
   belirlenmeden alan açmak erken karar verir.

Bu seçimle **migration eklenmez**; 116 mevcut hâliyle ilerler (aşağıda).

---

## 7. Migration 116'nın bu karardan sonra güncellenmesi

Faz 13C'de yazılan `116_faz13c_mat1046_pilot_kaynak_fisleme.sql` **zaten DB
sözleşmesine uygun** (title, file_name, source_reference, ownership_status='unknown',
license_status='unknown', commercial_use_allowed=false, notes) ve idempotent.
Seçenek A kararı sonrası **değişiklik gerekmez**; yalnızca koşullar notlanır:
- Mevcut hali uygulanabilir; uygulama ayrı açık onayla (bu faz uygulamadı).
- İleride TS servisi DB'ye uyarlanınca (Seçenek A), 116'daki satırlar o servis
  üzerinden de üretilebilir olur; o noktada 116 veya servis seçimi karar verilir —
  ikisi birden çalıştırılırsa `file_name` guard'ı çakışmayı önler.
- Kapsam haritası (`test_code`: MT1046-COZ/OZET/EŞSİZ-1/-2; `test_number` 1..4;
  `page_number` basılı karşılıklar) source-location insert'lerinde kullanılacak ve
  039 promotion deseniyle uyumludur.

---

## 8. Lisansı "unknown / inceleme gerekli" kaynakların saklanma statüsü ve soru üretimine kapalı kalması

- Statü: `ownership_status='unknown'` + `license_status='unknown'` +
  `commercial_use_allowed=false`, `notes` içinde "lisans incelemesi gerekli".
  DB allowlist CHECK'leri bunu geçerli varsayılan olarak kabul eder; hiçbir tahmin
  girilmez (Faz 13C karar listesi).
- Soru üretimine neden kapalı kalır:
  1. `036_originality_similarity_copyright_gate` ve `007_copyright_reviews`
     hattı, kaynak hak durumu doğrulanmadan AI'ya "kaynak içeriği" olarak erişim
     vermez; `license_status != 'approved'` → guide sağlanmaz.
  2. `039` promotion `v_staging.source_id` ile bağlama yapar; kaynak `unknown`
     olduğunda `ownership_status` `${staging_source}` farklıysa `ai_original`
     dönüşümü risk taşır — içerik olarak bağlanmaz. Kaynak yalnız **referans
     istatistik** (tür kalıbı / zorluk profili) ve **cevap şahidi** olarak kullanılır.
  3. `commercial_use_allowed=false` + license unknown → ticari kullanım yolu kapalı;
     hak sahibinden doğrulanmadan `approved`'a geçilmez.
- Şu hâlde bu üç PDF **üretim girdisi veya kopyalama kaynağıdır**; pilot üretimi
  için kaynakların yalnız denetim (cevap şahidi 553–558, 209–212) ve kapsam
  referansı kullanılır; üretilecek sorular orijinal olur ve 036 kapısından geçer.

---

## 9. Sınır tutanağı
- Kod, DB, migration 116, test, UI, kaynak kaydı, PDF değişmedi. Soru üretimi/AI
  çağrısı/commit/push/hosted dokunulmadı. Yalnız salt-okunur sorgular + derleme
  kontrolü çalıştırıldı. Raporla ve dur.
- Not: `supabase_vector_yarisma-programi` konteyneri hâlâ restart döngüsünde; bu
  fazla ilgisiz, ilgili role bildirildi.