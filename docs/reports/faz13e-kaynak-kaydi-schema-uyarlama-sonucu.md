# Faz 13E — Kaynak Kayıt Modülünü Gerçek DB Sözleşmesine Uyarlama Sonucu

- Tarih: 2026-09-16
- Durum: UYGULANDI VE DOĞRULANDI. DB'ye yazma, migration 116 değişikliği/uygulaması,
  soru üretimi, AI çağrısı, fixture/vault, UI, commit/push ve hosted bağlantı YOK.

---

## 1. Değiştirilen dosyalar (yalnız modül kapsamı)

| Dosya | Değişiklik |
|---|---|
| `src/lib/content/types.ts` | Kaynak tipleri gerçek DB sözleşmesine hizalandı. |
| `src/lib/content/source-registry.ts` | Servis gerçek DB kollarıyla yeniden yazıldı; hayali alanlar kaldırıldı. |
| `src/lib/content/source-registry.test.ts` | DB sözleşmesine göre yeniden yazıldı; 11 test. |

Dokunulmayan: `src/lib/content/curriculum-mapper.ts` ve `.test.ts` (yalnız
`isSourceType` + müfredat tiplerini kullanıyor — korundu, 15 testi geçti).

## 2. Gerçek DB sözleşmesi (otorite)

- `question_sources`: `source_type` (CHECK), `title NOT NULL`, `publisher`,
  `author`, `publication_year`, `file_name`, `source_reference`,
  `ownership_status NOT NULL` (CHECK: owned/licensed/third_party/ai_original/unknown),
  `license_status NOT NULL` (CHECK: unknown/pending/approved/restricted),
  `commercial_use_allowed NOT NULL`, `notes`, `created_at`, `updated_at`.
- `question_source_locations`: `question_id`+`source_id` (UNIQUE ikili),
  `page_number`, `test_number`, `test_code`, `question_number`,
  `source_question_code`, `crop_reference`, `extraction_confidence (0..1)`.
- Fark: DB'de `file_hash`, `process_status`, `needs_ocr`, `metadata`, serbest
  `section_name` vb. YOKTUR ve eklenmedi.

## 3. Kodun kullandığı, artık KALDIRILAN hayali alanlar

`source_name`, `file_hash`, `file_size_bytes`, `page_count`, `document_version`,
`rights_owner`, `usage_rights`, `metadata`, `process_status`, `needs_ocr`,
`section_name`, `question_number_on_page`, `confidence_score`,
`needs_manual_review` — tümü arayüz/girdi/servis/select'lerden çıkarıldı.
`toSourceDocumentRecord` yeni eklenen künye okuyucudur (hayali alan içermez).

## 4. Gerçek DB alanlarının kullanımı

`registerSourceDocument` insert eder: `source_type, title, publisher, author,
publication_year, file_name, source_reference, ownership_status, license_status,
commercial_use_allowed, notes` — DB'deki kolon setiyle birebir.

`linkQuestionToSource` insert eder: `question_id, source_id, page_number,
test_number, test_code, question_number, source_question_code, crop_reference,
extraction_confidence` (0..1 kıstırma fonksiyonu `clampConfidence`).

## 5. Güvenli/idempotent davranış

- `registerSourceDocument`: yinelenen kayıt koruması `file_name` üzerinden
  sorgu + `maybeSingle`; uygun kayıt varsa `duplicate` döner, insert YAPMAZ
  (DB'de bu kolonda unique kısıt yok — servis okuma öncelikli).
- `linkQuestionToSource`: (question_id, source_id) ikilisi için insert; UNIQUE
  ihlali (23505) oluşursa mevcut kayıt `maybeSingle` ile bulunur ve
  `{ duplicate: true }` döner — 039 promotion'daki
  `UNIQUE(question_id, source_id) + ON CONFLICT DO NOTHING` deseniyle aynı
  davranış (yarış içi mükerrer bağlama güvenli).

## 6. Lisans güvencesi (gevşetme YOK)

- `ownership_status` / `license_status` DB CHECK allowlist'ine sınırlıdır
  (`isOwnershipStatus` / `isLicenseStatus`).
- `unknown` + `commercial_use_allowed=false` olan bir kaynak hiçbir yoldan
  "üretim girdisi" olarak işaretlenmez: servis içerik üretmez, `title` dışında
  içerik yazmaz ve telif kapısı (036) bu kaydın dışında çalışır.
- DB'de varsayılanlar korundu; migration 116'daki statülerle tutarlı.

## 7. Doğrulama (tümü yeşil)

- `npx vitest run src/lib/content/source-registry.test.ts` → **11 passed**
- `npx vitest run src/lib/content/curriculum-mapper.test.ts src/lib/content/source-registry.test.ts` → **26 passed** (kurulu bozulmadı)
- `npx eslint src/lib/content/source-registry.ts src/lib/content/types.ts src/lib/content/source-registry.test.ts` → **0 hata, 0 uyarı**
- `npx tsc --noEmit --skipLibCheck` → **genel proje 0 hata**
  (görev dışı mevcut hata yok; ortadan kalkan eski modül hataları dahil temiz)

## 8. Devredilmeyen / bekleyen (kural ihlali yok)

- Migration 116 (`supabase/migrations/116_faz13c_...`) DEĞİŞTİRİLMEDİ ve
  uygulanmadı (ayrı onay gerekir).
- DB'ye hiçbir yazma yapılmadı; soru üretimi / AI çağrısı / fixture-vault yok.
- Modül halen izole: dış çağıran yok (yalnız kendi testleri).

## 9. Görev dışı notlar (bu fazın kapsamı dışında, rapora bilgi)

- `supabase_vector_yarisma-programi` konteyneri restart döngüsünde (gözlem,
  önceki fazlarda da not edildi; ilgili role bildirilmelidir).
- `src/lib/content/` klasörü git'te henüz untracked (üretim commit öncesi
  pakette); migration 110–116 dahil yeni faz ürünleri aynı pakette beklemede.