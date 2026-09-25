# Admin Candidate Batch İnceleme Ekranı — DTO/RPC Tasarım Denetimi

**Tarih:** 2026-09-24
**Tür:** Yalnız tasarım + salt-okunur inceleme. Kod/migration/DB/UI DEĞİŞİKLİĞİ YAPILMADI.
**Hedef batch:** `9310097d-168c-498e-b8cc-4531d46c0825` (Fizik, ingested, 32 valid)
**Durum:** Migration 120/121 yerel ana DB'de uygulanmış; 3 RPC çalışıyor.
**İncelenen dosyalar (dar kapsam — candidate-batches):**
- `src/lib/admin/candidate-batches.ts` (DTO allowlist, 120/121 RPC sarmayıcıları)
- `src/app/(admin)/admin/candidate-batches/[id]/page.tsx` (detay sayfası)
- `src/lib/admin/candidate-batches.test.ts` (DTO pin testleri)
- `src/lib/admin/admin-panel-messages.ts` (etiketler)
- `supabase/migrations/120_faz19_admin_candidate_batch_read.sql` (detail RPC)
- `supabase/migrations/124_faz22_candidate_md_curriculum_spec_link.sql` (register)
- Salt-okunur DB sorguları (metadata/content doğrulama)

## 1. Akış özeti

`page.tsx` → `hasCandidateBatchReadPermission()` (UI gating) → `getCandidateBatchDetail()` →
`get_candidate_question_batch_detail(p_batch_id)` (SECURITY DEFINER, fail-closed:
auth.uid() zorunlu + service_role VEYA ai.manage/questions.approve; anon revoked) →
jsonb → `mapCandidateBatchListItem` + `mapCandidate` → allowlist DTO. Çözüm dahil tüm
critk alanlar yalnız bu admin RPC'sinden gelir; öğrenci tarafı staging/metadata'ya dokunamaz.

## 2. Beş eksik alanın gerçek DB kaynağı ve neden dönmediği

| Eksik alan | DB kaynağı | Mevcut durum | Gerekli değişiklik | Migration gerekir mi? | Güvenlik notu |
|---|---|---|---|---|---|
| **Ders adı** | `public.subjects.name` (`subject_id=57a959a8…` → `"Fizik"`) | 120 RPC yalnız `subject_id` (uuid) döndürür (satır 255), `subject_name` yazmaz; DTO/UI UUID gösterir, ad yok | RPC preview'a `subject_name` ekle (`LEFT JOIN public.subjects`); DTO `subjectName`; UI etiketi | **EVET — 126** (120 salt-okunur olduğundan 120'ye geri dokunulamaz; 126 `get_candidate_question_batch_detail` CREATE OR REPLACE) | `subjects` kamu tablosu; ad yalnız admin RPC çıktısına girer; öğrenci API'sine taşınmaz |
| **Outcome kodu** | `ai_question_staging.metadata->'outcome_code'` (32/32 dolu) | RPC `r.metadata`'yı SELECT ediyor (satır 220) ama preview allowlist'ine `outcome_code` YAZMIYOR (satır 240–264 yok); `required_outcome_id` metadata'da var; curriculum_fit gate'i henüz çalışmadı (expected=0) | RPC preview'a `'outcome_code', r.metadata->>'outcome_code'` ve `'required_outcome_id', r.metadata->>'required_outcome_id'` satırlarını ekle; DTO `outcomeCode` + `requiredOutcomeId`; UI | **EVET — 126** (aynı CREATE OR REPLACE) | Olgunlaşmamış gate ausu değil; kod zaten metadata'da; öğrenciye asla dönmez (yalnız admin RPC) |
| **Çözüm metni** | `ai_question_staging.metadata->'solution'` (jsonb **object**: `{method, steps[], result, correctAnswerJustification, commonMistakes[]}`) | 120 RPC ÇÖZÜMÜ DÖNDÜRÜYOR (satır 263: `'solution', r.metadata -> 'solution'`) ama DTO `asString(row.solution)` (candidate-batches.ts:373) object'i reddeder → **null** → sayfa `solutionMissing` gösterir | Yalnız DTO: `solution` alanını object allowlist'iyle map et (`method`, `steps[].title`, `steps[].content`, `result`, `correctAnswerJustification`, `commonMistakes`) → `CandidateSolution`; UI yapısal/satır bloklar; testteki string pin (candidate-batches.test.ts:136) object yapısına güncellenir (fiilen ölü yoldur: RPC her zaman object döndürür) | **HAYIR** | Çözüm zaten yalnız SECURITY DEFINER admin RPC çıktısıdır; staging metadata öğrenci okunmuşu DEĞİLDİR; DTO allowlist'e uyarak ham JSON taşınmaz |
| **Low-confidence uyarısı** | **VERİ YOK.** Üretici zarfı `fizik-p01-autofix-cognitive-v3.json` içinde `low_confidence_candidates`, ancak 123/124 register bu işareti hiç OKUMUYOR/saklamıyor → DB sorgusu 0 kayıt | Gösterilemiyor; mevcut 32 aday için işaret kayıp (geriye dönük doldurma DB yazımı olur → bu görevde YOK) | Yeni append-only **126** register tarafı: opsiyonel payload alanını `ai_question_staging.metadata->'low_confidence'` (bool) olarak sakla + DTO `lowConfidence` + UI sarı uyarı; mevcut batch N/A (veri yok) | **EVET — 126** (register CREATE OR REPLACE, 124 davranışı birebir korunur) + mevcut batch için veri kaybı açıkça raporlanır | İşaret üretici kaynaklı, yalnız admin görünümü; öğrenciye taşınmaz; zorunlu değil (opsiyonel) |
| **Schema-version görünümü** | `candidate_question_batches.schema_version` (künye **1.0**, 124 moderning 238'de sabit `'1.0'`) ↔ `validation_summary.preflight.schema_version` (**1.1**, 124:851) | 120 RPC ikisini de döndürüyor (`schema_version` = 1.0 satır 467 + `preflight.schema_version` = 1.1); DTO ikisini map ediyor (`schemaVersion` + preflight `schemaVersion`); UI ikisini ayrı gösteriyor — sorun "eksik" değil, **tutarsızlık** | Yalnız UI: künye satırında netleştirme notu (örn. "İçerik şeması 1.1 (adapter v1.1_markdown)") veya iki alanın etiketinde ayrım; veri değişmez | **HAYIR** | Salt okunur değer; sızıntı yok; veriye dokunmak bu görev kapsamı dışı |

## 3. En küçük güvenli çözüm kararı

- **ders adı**: RPC'ye alan eklemek **gerekli** (frontend UUID'den ad üretemez) → 126.
- **outcome kodu**: RPC'ye alan eklemek **gerekli** (metadata okunuyor ama allowlist'e yazılmıyor) → 126.
- **çözüm metni**: **yalnız frontend DTO** — RPC zaten object dönderiyor; dönüşüm kırığı DTO'da.
- **low-confidence**: veri saklanmadığı için **önce saklama** gerekiyor → append-only 126 (register),
  mevcut batch N/A; UI uyarısı yalnız işaret varsa gösterilir.
- **schema_version**: veri mevcut ve görünüyor; yalnız UI açıklama notu.

Tek migration **126** üç CREATE OR REPLACE'i atomik taşır (kendi `BEGIN/COMMIT`; 120/124'e
geri dokunulmaz; ACL revoke/grant korunur; anon kapalı kalır). Çözüm için migration YOK.
Kod değişikliği kapsamı: yalnız candidate-batches DTO + detay sayfası + mesaj etiketleri + testler.

## 4. Yetki ve veri sızıntısı

- Çözüm/outcome/ders adı **yalnız** `get_candidate_question_batch_detail`'in SECURITY DEFINER
  çıktısından gelir; anon execute revoked, fail-closed kapı (`auth.uid()` + ai.manage/questions.approve).
- Öğrenci API'si `questions`/`question_solution_assets` (promotion sonrası) okur; staging metadata
  öğrenci erişim kapsamında DEĞİLDİR → çözümün öğrenciye taşınması bu tasarımla imkânsız.
- DTO allowlist ilkesi korunur: `solution` object içinden yalnız bilinen alanlar okunur; `metadata`
  ham JSON'u asla taşınmaz. `low_confidence` boolean'dır, sadece gösterim işaretidir.

## 5. Önerilen uygulama planı (tek faz)

**Değişecek kesin dosyalar:**
1. `supabase/migrations/126_faz22_candidate_review_fields.sql` (YENİ, append-only, `BEGIN/COMMIT`):
   - `public.get_candidate_question_batch_detail(uuid)` CREATE OR REPLACE: preview'a
     `subject_name` (join) + `outcome_code` + `required_outcome_id` (metadata) eklenir;
     `'solution'` satırı aynı kalır; ACL (revoke anon, grant authenticated, service_role) korunur.
   - `private.register_candidate_md_batch(jsonb)` CREATE OR REPLACE: opsiyonel `low_confidence`
     alanını staging metadata'sına saklar; 124'ün tüm doğrulama/idempotency/preflight davranışı aynı.
   - Tablo/enum/policy/veri DDL'si yok.
2. `src/lib/admin/candidate-batches.ts` — DTO: `CandidatePreview.subjectName`,
   `outcomeCode`, `requiredOutcomeId`, `lowConfidence`; `solution` tipini `CandidateSolution | null`
   yapıp allowlist okuyucu yaz (`mapCandidateSolution`).
3. `src/lib/admin/admin-panel-messages.ts` — yeni etiketler (Ders, Kazanım kodu, Çözüm adımı, vb.).
4. `src/app/(admin)/admin/candidate-batches/[id]/page.tsx` — PreviewBlock: ders adı + outcome kodu
   alanı; çözümü steps/method/result/blme olarak göster; `lowConfidence` ise sarı uyarı rozeti.
5. `src/lib/admin/candidate-batches.test.ts` — DTO testleri: object solution derleme, subject_name/
   outcome_code passthrough, low_confidence/érie null fallback, allowlist sızıntı yok; mevcut string
   solution pini (satır 136) object yapısına güncellenir (gevşetme değil — RPC gerçeği object).

**Migration numarası:** `126` (ile 125 en son zaten). Sıra: 126 (DB) → DTO/messages → page → test.

**DB doğrulama adımları (yerel, salt-okunur, service-role JWT):**
1. `get_candidate_question_batch_detail('<batch>')` → `preview.subject_name = 'Fizik'`,
   `preview.outcome_code` 32/32 dolu, `preview.solution` object, `schema_version` (1.0) +
   `preflight.schema_version` (1.1) ayrı.
2. `list_candidate_question_batches` ve `get_candidate_question_batch_operation_status` çıktısı
   DEĞİŞMEZ (126 yalnız detail'i günceller).
3. ACL: anon `f` (fail-closed testi); authenticated yetkisiz → `42501`.
4. Sayaçlar: batch=2, questions=8, candidate_results=32, staging validating=32 — değişmez.
5. `register_candidate_md_batch` (126 sonrası) → boş/`low_confidence` işaretsiz payload ile uçtan
   uca aynı sonuç (idempotent); işaretli payload → metadata'da `low_confidence`.

**UI doğrulama:**
- `npm test` (candidate-batches.test.ts dahil) yeşil; test gevşetme/skip yok.
- `npm run lint` / typecheck yeşil.
- Detay sayfasında (service-role veya test fixture): ders="Fizik", kazanım kodu, çözüm blokları,
  mevcut batch'te low-confidence N/A (veri kayıp uyarısı raporlanır), şema notu görünür.
- 375×812 / 768×1024 / 1440×900 responsive kontrol; lang="tr", a11y (görünür focus, aria-live) korunur.

## 6. Sonuç

**SAFE_TO_IMPLEMENT: YES**

- Kapsam en küçüktür: 3 DTO alanı + çözüm derleyici + 1 append-only migration (126) + detay
  sayfası + testler. Yalnız candidate-batches ilgili dosyalar.
- Şunlar UYGULANMAZ: publish/approval/reject, intake (126 test call dışı), commit/push,
  geniş glob/UI/styles taraması, veri yazımı (mevcut low-confidence backfill dahil), FRONTEND
  DEĞİŞİKLİĞİ BUGÜN YOK (yalnız plan).
- **Açık not (bloker değil):** mevcut Fizik batch için low-confidence işaretinin DB'de kaydı yoktur
  (register saklamadı); 126 gelecek intake'ler için çözüm üretir, mevcut 32 aday için işaret
  gösterilmez. Bu bilgi kullanıcıya raporlanmıştır.