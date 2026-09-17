# Faz 13C — MAT.10.4.6 Pilot Kaynak Fişleme Planı

- Tarih: 2026-09-16
- Durum: PLAN HAZIR — DB'ye hiçbir yazma yapılmadı, migration taslağı UYGULANMADI
- Kapsam: Üç doğrulanmış PDF kaynağının `question_sources` / `question_source_locations`
  yapısına uygun kayıt künyesi ve önizleme satırları.

---

## 1. Gerçek schema incelemesi (salt-okunur, DB'den alındı)

Kaynak: `supabase_db_yarisma-programi` üzerinde `information_schema.columns` SELECT'i
(001–115 migration zinciri uygulanmış durumda; tablolar `004_questions_foundation.sql`
ile kurulu).

### public.question_sources (satır sayısı: 0)
| Kolon | Tür | Null | Varsayılan |
|---|---|---|---|
| id | uuid | NO | gen_random_uuid() |
| source_type | text | NO | — (CHECK: book,pdf,excel,manual,ai_generated,other) |
| title | text | NO | — |
| publisher | text | YES | — |
| author | text | YES | — |
| publication_year | smallint | YES | — |
| file_name | text | YES | — |
| source_reference | text | YES | — |
| ownership_status | text | NO | 'unknown' (CHECK: owned,licensed,third_party,ai_original,unknown) |
| license_status | text | NO | 'unknown' (CHECK: unknown,pending,approved,restricted) |
| commercial_use_allowed | boolean | NO | false |
| notes | text | YES | — |
| created_at / updated_at | timestamptz | NO | now() |

### public.question_source_locations (satır sayısı: 0)
| Kolon | Tür | Null |
|---|---|---|
| id | uuid | NO |
| question_id | uuid (FK→questions, CASCADE) | NO |
| source_id | uuid (FK→question_sources, CASCADE) | NO |
| page_number | integer (CHECK > 0) | YES |
| test_number | integer (CHECK > 0) | YES |
| test_code | text | YES |
| question_number | integer (CHECK > 0) | YES |
| source_question_code | text | YES |
| crop_reference | text | YES |
| extraction_confidence | numeric(5,4) (0≤x≤1) | YES |
| created_at | timestamptz | NO |

UNIQUE(question_id, source_id) + index(source_id, page_number, test_code, question_number).
source_type='pdf' CHECK kapsamında mevcuttur.

---

## 2. KRİTİK BULGU — `source-registry.ts` mevcut şemayla UYUMSUZ

Faz 13C görevi "service davranışını incele"yi içeriyordu. İnceleme sonucu:

`src/lib/content/source-registry.ts` ve `src/lib/content/types.ts` şu alanları
kullanıyor/üretiyor:
- `question_sources`: `source_name`, `file_hash`, `file_size_bytes`, `page_count`,
  `document_version`, `rights_owner`, `usage_rights`, `metadata`, `process_status`,
  `needs_ocr`
- `question_source_locations`: `page_number`, `section_name`, `question_number_on_page`,
  `confidence_score`, `needs_manual_review`, `metadata`

DB'de BUNLARIN HİÇBİRİ YOK. Migration zincirinde `file_hash`, `process_status`,
`needs_ocr`, `document_version`, `usage_rights`, `rights_owner` anahtar kelimeleri
tek migration'da dahi geçmiyor (grep: 0 sonuç). `types.ts`'teki açıklama
"001_source_foundation migration'ındaki process_status değerleriyle" der; gerçek
migration adı `001_auth_foundation.sql`'dir ve `process_status` kolonu yoktur.

Sonuç:
- `registerSourceDocument` ve `linkQuestionToSource` mevcut hâliyle canlı DB'ye
  bağlanırsa unknown-column hatası verir; şu an çalışmaz durumdadır.
- `source-registry.test.ts` sahte client ile çalıştığı için bu uyumsuzluğu
  yakalayamaz.
- Mükerrer koruması (file_hash üzerinden) DB tarafında tutulamaz; tabloda hash
  kolonu ve unique kısıt yoktur.

Bu fazdaki karar: **fişleme mevcut gerçek şemaya uygun yapılır**; servis uyumsuzluğu
ayrı bir bulgu olarak raporlanır ve servis/şema uyumu ayrı bir görev olarak
sürece bırakılır (bu görevin kapsamı: kod/UI değişiklik yok).

---

## 3. Kaynak künyeleri (fiş taslağı)

PDF'lerden salt-okunur alınan künyeler (Get-FileHash / Get-Item; sayfa sayıları
Faz 13B doğrulamasından):

| Dosya | Boyut (bayt) | SHA-256 (hex, küçük harf) | Sayfa | Son değişiklik |
|---|---|---|---|---|
| matematik.pdf | 35.480.489 | fee06b28fbbafec7c81fac4e653bc2a80bfc4787bea6544eb206abaeb634efe | 560 | 2026-01-09 21:47 |
| tyt-matematik.pdf | 33.313.356 | df65e71ce0a483aeb27c4c7d3099df440736a2c2a0579fa0f3097bb1a7fed6b7 | 160 | 2026-01-09 21:58 |
| matematik (2).pdf | 20.464.449 | f24da478f7706ff9009de28644d75f0de730245d4ead3cddb17aa3cbc1d7dc0a | 216 | 2026-01-09 21:50 |

Sayfa eşleme kuralı (Faz 13B'de doğrulandı): **basılı sayfa = (PDF 1-tabanlı sayfa no) − 2**.

### Fiş satırı önizlemesi → `question_sources`

Mevcut şemada boyut/hash/sayfa sayısı için ayrı kolon YOKTUR. Bu veriler `notes`
içinde doğrulanmış künye olarak taşınacak; `title` = dosya adı (uzantısız, deterministik);
`file_name` = gerçek dosya adı; `source_reference` = tam yol (doğrulanmış dosyanın
kimliği). Lisans/sahiplikte tahmin YOK — DB default'u korunur, "inceleme gerekli"
notu eklenir (bkz. §5).

| title | publisher | source_type | file_name | source_reference | ownership_status | license_status | commercial_use_allowed | notes |
|---|---|---|---|---|---|---|---|---|
| matematik | NULL | pdf | matematik.pdf | D:\evraklar\proje\Meb Sorular\9-12\matematik.pdf | unknown | unknown | false | doğrulanmış künye: sha256 fee06b28…634efe; 35.480.489 bayt; 560 sayfa; basılı 421–456 MAT.10.4.6 (denklem) + cevap 553–558 (şahit); lisans incelemesi gerekli |
| tyt-matematik | NULL | pdf | tyt-matematik.pdf | D:\evraklar\proje\Meb Sorular\9-12\tyt-matematik.pdf | unknown | unknown | false | doğrulanmış künye: sha256 df65e71c…fed6b7; 33.313.356 bayt; 160 sayfa; basılı 102–106 MAT.10.4.6 konu özeti (yalnız denklem); lisans incelemesi gerekli |
| matematik (2) | NULL | pdf | matematik (2).pdf | D:\evraklar\proje\Meb Sorular\9-12\matematik (2).pdf | unknown | unknown | false | doğrulanmış künye: sha256 f24da478…d7dc0a; 20.464.449 bayt; 216 sayfa; basılı 35–41 eşitsizlik/sistem/grafik + cevap 209–212 (şahit); lisans incelemesi gerekli |

Fişleme, servis yerine doğrudan migration/insert yoludur çünkü §2'deki uyumsuzluk
nedeniyle `registerSourceDocument` kullanılamaz.

---

## 4. Bölüm türü ve kesin kapsam dışı alanlar

`question_source_locations` bölümü `test_number` + `test_code` + `page_number` +
`source_question_code` ile temsil eder (serbest `section_name` kolonu yok).

### matematik.pdf (dosya 1)
- Kullanılabilir: basılı 421–438 (PDF 423–440) — "İkinci Dereceden Bir Bilinmeyenli
  Denklemler" ÇÖZÜMLÜ SORULAR; basılı 439–456 (PDF 441–458) — 1.–4. TEST.
  Bölüm kodu: `MT1046-COZ` (421→test_code), test_number 1–4 (439–456).
- Şahit: basılı 553–558 (PDF 555–560) — cevap anahtarı, İkinci Dereceden tablosu
  basılı 557'de. Yalnız denetim şahididir; üretim girdisi değildir.
- Kapsam dışı (KESİN): basılı 456 sonrası (Çokgenler, basılı 457→), 420 ve öncesi;
  cevap anahtarı çözüm/kopyalama kaynağı olarak; sorunun metni/çözümünün birebir
  tekrarı.

### tyt-matematik.pdf (dosya 2)
- Kullanılabilir: basılı 102–106 (PDF 104–108) — konu özeti (kavram, çözüm kümesi,
  diskriminant, Δ<0 karmaşık, kök-katsayı) ve çözümlü Örnek ile Çözüm blokları.
  Test yok → `test_number` NULL, `test_code` = `MT1046-OZET`.
- Kapsam dışı (KESİN): kapsamdışı sayfalar (101 ve öncesi, 107 ve sonrası); örnek
  metin/çözüm kopyalama.

### matematik (2).pdf (dosya 3)
- Kullanılabilir: basılı 35–40 (PDF 37–42) — "İkinci Dereceden Denklemler,
  Eşitsizlikler ve Eşitsizlik Sistemleri -1" (1./2./3. ADIM); basılı 41 (PDF 43) —
  "-2" başlangıcı. Bölüm kodu: `MT1046-EŞSİZ-1` / `MT1046-EŞSİZ-2`.
- Şahit: basılı 209–212 (PDF 211–214; -1/-2 ADIM cevap tabloları 209–210).
  Yalnız denetim şahididir.
- Kapsam dışı (KESİN): 35 öncesi / 42 sonrası; AYT çıkmış sorulardan (2018/2020/2021)
  doğrudan alım; cevap anahtarından kopyalama.

### Genel telif/orijinallik kuralı
- Hiçbir kaynaktan soru metni, örnek, seçenek, çözüm veya cevap birebir
  kopyalanmaz. Kaynaklar yalnız: (a) kazanım kapsamı denetimi,
  (b) zorluk/format profili referansı, (c) tür kalıbı (çözümlü/test/örtüşme),
  (d) cevap şahidi olarak kullanılır.
- Üretilecek tüm sorular orijinal olmalı; denetim hattında (036 originality/copyright
  gate) eşleşme kontrolünden geçer.

---

## 5. Açık lisans / sahiplik karar listesi

Tahmin üretilmedi; resmî belgeden doğrulanamayan her alan DB default'ta tutulur ve
"inceleme gerekli" ile işaretlenir.

| Dosya | ownership_status | license_status | commercial_use_allowed | Karar/Not |
|---|---|---|---|---|
| matematik.pdf | unknown | unknown | false | İnceleme gerekli: resmî künye (publisher/author/yıl) PDF iç meta verisinden doğrulanmadı. |
| tyt-matematik.pdf | unknown | unknown | false | İnceleme gerekli: yayımcı/sahipliği doğrulanmadı. |
| matematik (2).pdf | unknown | unknown | false | İnceleme gerekli: yayımcı/sahipliği doğrulanmadı. |

Tüm üç kaynak `license_status='unknown'` + `commercial_use_allowed=false` ile
fişlenir; onaylanmadan ticari kullanım/kopyalama yoluna girmez. Lisans onayı,
sahip/yayımcıdan doğrulanınca durumu `approved`'a güncelleyecek ayrı bir görevdir.

---

## 6. Migration taslağı (UYGULANMADI — ayrı onay ister)

Dosya: `supabase/migrations/116_faz13c_mat1046_pilot_kaynak_fisleme.sql`

- Yalnızca 3 `question_sources` satırı ekler (NOT EXISTS guard → idempotent).
- Şema değişikliği YOK; mevcut DB şemasıyla birebir uyumlu.
- Uygulanacaksa ayrı, açık kullanıcı onayı gerektiren adım. Uygulama sonrası
  doğrulama: (a) 3 satır; (b) mükerrer tekrar çalıştırmada sıfır ekleme.
- `question_source_locations` satırları SORU üretimi sonrası eklenir (question_id
  FK'sı zorunlu olduğu için henüz boş bırakılır); bölüm eşleme tablosu (§4) oraya
  girdi sağlar.

Doğrudan ham SQL önizlemesi (referans — migration içinde, psql kodlama koruması için
Türkçe karakterler ASCII karşılığıyla aynı satırlar bulunur):

```sql
INSERT INTO public.question_sources
  (source_type, title, publisher, author, publication_year, file_name,
   source_reference, ownership_status, license_status, commercial_use_allowed, notes)
SELECT 'pdf', 'matematik', NULL, NULL, NULL,
       'matematik.pdf',
       'D:\evraklar\proje\Meb Sorular\9-12\matematik.pdf',
       'unknown', 'unknown', false,
       'doğrulanmış künye: sha256 fee06b28…634efe; 35480489 bayt; 560 sayfa; basılı 421–456 MAT.10.4.6 denklem; cevap 553–558 şahit; lisans incelemesi gerekli'
WHERE NOT EXISTS (SELECT 1 FROM public.question_sources WHERE file_name = 'matematik.pdf');

-- (tyt-matematik ve matematik (2) satırları aynı desende, migration içinde)
```

---

## 7. Önerilen source-location kayıtları (önizleme — insert YOK)

Soru üretimi fazında, her üretilen orijinal soru için bu eşleme planına göre bağlama
kaydı düşülür. Satır şablonu ve planlanan aralıklar:

| source_id | test_code | test_number | page_number (basılı) | source_question_code |
|---|---|---|---|---|
| kaynak1 | MT1046-COZ | NULL | 421–438 | COZ-<soru no> |
| kaynak1 | MT1046-TEST | 1..4 | 439–456 | TEST<n>.<soru no> |
| kaynak2 | MT1046-OZET | NULL | 102–106 | OZ-<sayfa>-<no> |
| kaynak3 | MT1046-EŞSİZ-1 | NULL | 35–40 | AD1-<soru no> |
| kaynak3 | MT1046-EŞSİZ-2 | NULL | 41–… | AD2-<soru no> |

**bağlama kuralı:** source_question_code, kaynaktaki SORU metnine birebir karşılık
gelir (kopyalama değil); üretilen orijinal soru "kalıp/tür/kazanım" olarak kaynağa
bağlanır, içerik olarak DEĞİL. Cevap anahtarı (şahit) hiçbir source-location
kaydında üretim girdisi olarak kullanılmaz.

---

## 8. Sınır tutanağı
- Yalnızca üç PDF ve mevcut kod şeması incelendi; disk taraması, DB yazma, soru
  üretimi, AI çağrısı, fixture/vault, kod/UI edit, commit/push, hosted dokunulmadı.
- `supabase_vector_yarisma-programi` konteyneri şu an restart döngüsünde
  (gözlem; bu fazın kapsamı dışında, ilgili role not edildi).
- Sonraki adım adayları (ayrı onay): (1) 116 migration onayı + uygulama ve sorgu
  ile doğrulama; (2) source-registry.ts + types + test'in DB şemasına hizalanması;
  (3) lisans incelemesi (MEB yayım künyesi); (4) soru üretimi pilotu başlangıcı.