# Admin Panel — Fizik P01 Batch Kabul Kontrolü (Salt-Okunur)

**Tarih:** 2026-09-24
**Kapsam:** Yerel ana DB (`supabase_db_yarisma-programi`) — yalnız okuma.
**Hedef batch:** `9310097d-168c-498e-b8cc-4531d46c0825`
**batch_key:** `notebook:md:886bdde8c5a93aae5d3bf8b5bf11c59908c97d587a813014aa646c520dd33332`
**Kaynak paket:** `docs/question-production/normalized/fizik-p01-autofix-cognitive-v3.json` (SHA256 `685136A7462AF9D31039D633B80733E9AB64E62B9BAE56B7C9F7691F6866A4D0`)

## Yöntem

- Salt-okunur gerçeklik kontrolü: DB SELECT'leri + `supabase/migrations/` kaynak okuma + admin frontend
  (`src/lib/admin/candidate-batches.ts` → list/detail/islem-durumu sayfaları) alan-by-alan doğrulama.
- DB yazma, migration uygulama, intake, onay/red/yayın, commit, push: YAPILMADI.
- İzin modeli doğrulaması hem migration kaynağından (RPC fail-closed kapı) hem DB policy/RLS
  sorgularından yapıldı.

## Batch'in DB anlık görüntüsü (salt-okunur SELECT)

| Ölçüt | Değer |
|---|---|
| `candidate_question_batches` durumu | `ingested` |
| sayaçlar | total 32 / valid 32 / invalid 0 / inserted 32 / duplicate 0 |
| sonuç satırları | 32 (`candidate_batch_candidate_results`) |
| staging | 32 aday, hepsi `staging_status='validating'` |
| `batch.schema_version` kolonu | **1.0** (preflight içinde 1.1 — aşağıda gap) |
| origin / producer | `curriculum_original` / `notebook` |
| preflight (validation_summary) | adapter `v1.1_markdown`, schema_version `1.1`, root_valid `true`, review_required `true`, publication_allowed **false**, is_active **false**, out_of_package_count 0 |

Kabul önkoşulları sağlanıyor: paket yayın kapalı, inceleme zorunlu, aktif değil, 32/32 inserted, 0 invalid/duplicate.

## Kontrol Sonuçları

### 1) Batch admin listesinde görünürlük — KOŞULLU (bloker)

- DB satırı mevcut ve doğru. Liste sıralaması `created_at desc` (120 RPC).
- **Bloker:** Yerel DB'de Faz 19/20 okuma RPC'leri **TANIMLI DEĞİL**:
  - `public.list_candidate_question_batches(integer, integer)` — YOK (120)
  - `public.get_candidate_question_batch_detail(uuid)` — YOK (120)
  - `public.get_candidate_question_batch_operation_status(uuid)` — YOK (121)
- `pg_proc` taraması (tüm şemalar): yalnız `get_candidate_question_batch_contract`,
  `register_candidate_md_batch` (public+private), `register_candidate_question_batch`,
  `validate_*` bulundu. `supabase_migrations.schema_migrations` son kayıt **110**; 120/121 hiç
  uygulanmamış (123/124/125 önceki intake sırasında elle uygulanmıştı).
- Sonuç: Sayfa `listCandidateQuestionBatches` → RPC hata döner → `{status:"error"}` → listede
  `M.listError` gösterilir. **Batch, migration 120/121 uygulanana kadar admin UI'da GÖRÜNMEZ.**
- Not: Bu kabul kontrolü salt-okunurdur; migration uygulamak DB değişikliği kapsamındadır ve
  yapılmadı. Öneri olarak aşağıda listelendi.

### 2) Detay sayfası bilgileri (32, ders, durum, preflight) — KOŞULLU / GAP

- RPC mevcut olduğunda alan eşlemesi doğrudur: sayaçlar 32/32/0/32/0, `status=ingested`,
  preflight bloğu `İnceleme gerekiyor=Evet`, `Yayın izni=Hayır`, `Aktif=Hayır` gösterir
  (`PreflightBlock` → `yesNo`).
- **GAP — Ders adı gösterilmiyor:** Aday önizlemesinde yalnız `subject_id` (UUID)
  gösterilir; "Fizik" adı UI'da hiçbir yerde yok. `xref`/join yapılmaz.
- **GAP (küçük):** `batch.schema_version=1.0` görüntülenirken preflight `schema_version=1.1`
  — paket aslında v1.1; batch künyesiyle preflight arasında gösterim tutarsızlığı var.

### 3) Aday detayı: soru, A–E, doğru cevap, çözüm, outcome, cognitive_type

| Alan | RPC (120) | Frontend (DTO+UI) | Durum |
|---|---|---|---|
| Soru metni | `s.question_text` | `preview.questionText` | ✓ |
| Seçenekler A–E | `option_a..e` | `preview.options` | ✓ |
| Doğru cevap | `s.proposed_correct_answer` | ✓ | ✓ |
| Çözüm | `metadata -> 'solution'` | `preview.solution` | ✓ |
| Cognitive type | `s.proposed_cognitive_type` | ✓ | ✓ |
| **Outcome (outcome_code)** | — | — | **GAP** |
| Staging durumu | `s.staging_status` | ✓ (`validating`) | ✓ |

- **GAP — Outcome görünmüyor:** metadata içinde `outcome_code` saklanır (124: `metadata->'outcome_code'`),
  ancak RPC önizleme allowlist'i outcome alanı taşımaz; `curriculum_fit` gate allowlist'i
  (`GATE_ALLOWLISTS.curriculumFit`) de `expected_outcome_id`/kodu hariç tutar. Kabul edilen 22 outcome
  eşleşmesi admin'de denetlenemez.

### 4) Düşük güvenli adayların (004/010) UI'da görünümü — GAP

- `NB-FIZ-P01-004` (application) ve `NB-FIZ-P01-010` (comprehension) yalnız v3.json zarfında
  `low_confidence_candidates` listeleminde işaretli. Bu işaret DB'ye **yazılmadı** (register bunu
  saklamaz), RPC/DTO/UI'da karşılığı yok.
- Sonuç: Öncelikli inceleme göstergesi admin UI'da **hiçbir yüzeyde görünmez**; yalnız
  `client_question_id` üzerinden hedef kesimdeki adaylar ayırt edilebilir.

### 5) Yetkisiz erişim engellemesi — ✓ SAĞLAM

- UI kapısı: giriş yok → `/login`; yetki yok → `/dashboard`; `hasCandidateBatchReadPermission`
  (ai.manage VEYA questions.approve) false'da kapalı.
- RPC kapısı (120, fail-closed): `auth.uid()` null → `42501`; `service_role` dışında
  `current_user_has_admin_permission('ai.manage'/'questions.approve')` arar.
- RLS: `ai_question_staging` + alt tablolar RLS açık; staging SELECT policy'leri admin
  permission fonksiyonuna bağlı (`question admins read staging` → `questions.view`); tarayıcı
  oturumu doğrudan staging okuyamaz. Secret/devre dışı bırakma yok.
- Write tarafı: bu modülde hiçbir yazma yok; yayın/onay RPC/exposure mevcut değil.

### 6) Yayın/onay/öğrenci erişimi imkânsızlığı — ✓

- Preflight: `publication_allowed=false`, `is_active=false`, `review_required=true`.
- 124 `candidate_md_v11` zarfı invaryantı: `publication_allowed` veya `is_active` true ise register
  `raise exception` — bu batch için ikisi de false, koruma aktif.
- Admin sayfalarında publish/approve/reject/promote butonu veya formu YOKTUR (yalnız
  `islem-durumu` salt-okunur görünüm bağlantısı). Öğrenci rotasında staging/spec verisine erişim yok.

### 7) Eksik admin ekranları / göstergeler (yalnız öneri, değişiklik YAPILMADI)

Aşağıdakiler bu raporun GAP listesidir ve uygulama kapsamı dışı önerilerdir:

1. **Bloker:** Migration `120_faz19_admin_candidate_batch_read.sql` ve
   `121_faz20_candidate_batch_operation_status.sql` yerel ana DB'ye **uygulanmamış**. Admin
   list/detail/islem-durumu sayfaları RPC hatası verir; batch görüntülenemez. İnceleme öncesi
   bu iki migration'ın uygulanması gerekir (DB değişikliği — bu oturumda yapılmadı).
2. **Outcome görünürlüğü:** Aday önizlemesinde `outcome_code` (ve mümkünse outcome adı)
   gösterilmiyor; 22 kabul edilen eşleşmenin admin denetimi için gerekli.
3. **Düşük güvenli işareti:** `low_confidence_candidates` (004, 010) DB'de saklanmıyor ve UI'da
   görünmüyor; öncelikli inceleme göstergesi (rozet/sıralama/filtre) önerilir.
4. **Ders adı:** `subject_id` UUID yanında subject adı ("Fizik") gösterimi önerilir.
5. **Şema sürümü tutarlılığı:** batch künyesi `1.0` ↔ preflight `1.1`; tek kaynağa bağlanması önerilir.

## Kararlar

**SAFE_FOR_ADMIN_REVIEW: YES**
(Data doğru ve güvenli: 32/32 inserted, 0 invalid/dup, publication_allowed=false, is_active=false,
yayın/onay UI'da mümkün değil, yetkisiz erişim fail-closed. Not: Adayların görülebilmesi için
alttaki bloker gap'in (migration 120/121) giderilmesi gerekir — bu bir DB değişikliğidir.)

**ADMIN_UI_GAPS:** migration_120_121_yok; outcome_kodu_gosterilmiyor; low_confidence_gosterilmiyor; ders_adi_gosterilmiyor; schema_version_tutarsizligi

## Kapsam dışı gerçekleştirme (kontrol)

- DB'yazma/migration/onay/red/yayın/intake: HİÇBİRİ yapılmadı.
- `git status` değişiklik kaydeden dosya: yalnız bu rapor (salt-okunur analiz çıktısı).
- Frontend/backend kodu değiştirilmedi; test gevşetmeme/skip yapılmadı.