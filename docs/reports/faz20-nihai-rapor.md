# Faz 20 Nihai Rapor

**Tarih:** 2026-09-19
**Model:** big-pickle (opencode)
**Sorumlu:** selami

---

## 1. Sonuç Özeti

| Metrik | Değer |
|---|---|
| **Durum** | ✅ BAŞARILI |
| Migration | 121_faz20_candidate_batch_operation_status.sql (353 satır) |
| Migration durumu | UYGULANDI + QA **yalnız izole disposable klonda** (`supabase_db_qa-faz20`, port 60422, default bridge) |
| Migration hedefi | Ana stack / hosted **DOKUNULMADI**; disposable container QA sonrası **SİLİNDİ** |
| Yeni sayfa | /admin/candidate-batches/[id]/islem-durumu |
| tsc --noEmit | ✅ 0 hata |
| eslint (Faz 20 dosyaları) | ✅ 0 hata |
| vitest unit (tüm repo) | ✅ 926 passed / 68 suite / 0 failed |
| Faz 20 testleri | ✅ 60/60 (lib + errors + 2 page) |
| DB QA (scripts/qa_faz20_*) | ✅ **10/10 PASS, 0 FAIL** (disposable klonda) |
| Production build | ✅ `next build` başarılı (24 sayfa; islem-durumu rotası dahil) |
| Git | Commit YAPILMADI (onay bekleniyor) |
| Push | YAPILMADI |

---

## 2. Görev Kapsamı

Faz 16 §8 P1 ikinci madde: **"Üretim/denetim işlem durumu"** görünümü —
paket aşaması, `waiting_*` gate'leri, provider hatası ve güvenli yeniden
deneme görünümü. Tümü **salt-okunur**; API anahtarı/secret UI'da ASLA
görünmez. Ayrı faz ürün gerçeği: önceki fazların (117–120) verilerini
güvenli DTO özeti olarak sunar; intake/gate/promotion tetiklemez.

## 3. Dağıtım Mimarisi

```
supabase/migrations/121_faz20_candidate_batch_operation_status.sql
  └ get_candidate_question_batch_operation_status(p_batch_id)
      → SECURITY DEFINER, STABLE, search_path=''
      → auth.uid() gate (42501)
      → (ai.manage VEYA questions.approve) VEYA service_role
      → ACL: revoke public/anon → grant authenticated/service_role
      → JSON:
          batch            (künye + sayaçlar; raw_payload/error_data YOK)
          phase            (candidate_counts: pending/valid/invalid/duplicate/inserted/failed)
          gates            (7 gate; her biri son-run DISTINCT ON sayaçları)
          provider         (has_batch_error_data boolean + candidate_validation_error_count)
          retry            (supported=false, reason_key='gate_retry_not_supported')

src/lib/admin/candidate-batches.ts
  └ mapOperationGateCounts / mapCandidateBatchOperationStatus / getCandidateBatchOperationStatus
      → allowlist DTO; ham RPC hatası + raw alan ASLA sızmaz
      → notFound → ok+null; diğer hata → error (fail-closed)

src/lib/admin/candidate-batches-errors.ts
  └ değişiklik GEREKMEDİ — yeni RPC hata metinleri mevcut
    (Kimlik/authRequired, ai.manage veya questions.approve/forbidden,
    zorunludur/required, Aday paketi bulunamadi/notFound) ile eşleşir;
    test coverage eklendi.

src/lib/admin/admin-panel-messages.ts
  └ ADMIN_CANDIDATE_BATCH_OPERATION_STATUS_MESSAGES (UI metinleri) + detailLinkLabel

src/app/(admin)/admin/candidate-batches/[id]/islem-durumu/page.tsx
  └ admin yetki kapısı (hasCandidateBatchReadPermission fail-closed)
  └ paket aşaması + gate waiting_* sayaçları + provider hata özeti
    + retry "desteklenmiyor" bilgisi (düğme ÜRETİLMEZ)

src/app/(admin)/admin/candidate-batches/[id]/page.tsx
  └ başlıktan "İşlem durumunu gör" linki (detailLinkLabel)

scripts/qa_faz20_candidate_batch_operation_status_local.sql
  └ disposable klon için 8 başlıklı QA (CI uyumlu toplam|gecen|kalan)

scripts/qa_faz20_candidate_batch_fixture_local.sql
  └ determinedistik fixture: 1 paket (7ea1ff55-...) + 5 candidate
    (pending/valid/invalid/inserted/failed); gerçek kullanıcı verisi
    değildir, QA'dan ÖNCE disposable klonda uygulanır
```

## 4. Migration 121 — Veri Yolu ve Güvenlik Kararları

```sql
get_candidate_question_batch_operation_status(p_batch_id uuid)
→ SECURITY DEFINER, STABLE, search_path=''  (owner=supabase_admin)
→ auth.uid() yok → 42501 "Kimlik dogrulamasi gerekli."
→ yetki yok → 42501 "Iislem durumu icin ai.manage veya questions.approve yetkisi gerekli."
→ p_batch_id null → 22023 "p_batch_id zorunludur."
→ paket yok → P0002 "Aday paketi bulunamadi."
→ ACL: revoke public/anon → grant authenticated/service_role
```

**waiting_\* sayaçları (son-run ilkesi):** her adayın `staging_question_id`
için o gate'in EN SON run'ı esas alınır (`DISTINCT ON (staging_question_id)
ORDER BY created_at desc`). Böylece pending/verified/rejected geçişleri
"sıra dışı iki run" ile hatalı toplanmaz; takılı gate gerçeği doğru okunur.

**Provider özeti:** `has_batch_error_data` yalnız `error_data <> '{}'`
boolean'ı; `candidate_validation_error_count` yalnız `validation_errors`
dolu aday SAYISI. Ham `error_data`/`validation_errors`/`raw_payload`
içeriği okunmaz ve dönmez — güvenlik kabul koşulu.

## 5. "Güvenli Yeniden Deneme" doğrulaması

Backend gerçeği (salt-okunur teyit edildi):

- candidate-batch gate/intake akışı `ai_job` ÜRETMEZ; bu yüzden 032/043
  job-izleme infra'sı bu akışa uymaz.
- 043'teki worker-level retry YALNIZ `question_generation` job'larını
  kapsar; gate run'larını tekrar başlatan public RPC YOKTUR.
- Bu yüzden RPC `retry.supported = false` + `reason_key =
  'gate_retry_not_supported'` sabit döner; UI **yeniden deneme düğmesi
  üretmez** (sahte buton/ekonomi yasağı), yalnız bilgi metni gösterir.

> **Açık eksiklik:** kapı (gate) run'larını güvenli şekilde yeniden
> başlatan bir mekanizma henüz backend'de yoktur. Bu, Faz 20 kapsamı
> dışında (yalnızca görünüm) olup sonraki bir fazın ürün kararına bırakılmıştır.

## 6. Doğrulama Sonuçları

| Kontrol | Komut | Sonuç |
|---|---|---|
| Faz 20 lib+page+errors test | `vitest run` (4 dosya) | ✅ 60 passed / 0 failed |
| Tüm repo birim test | `vitest run` | ✅ 926 passed / 68 suite / 0 failed |
| tip kontrolü | `tsc --noEmit` | ✅ 0 hata |
| lint (Faz 20 dosyaları) | `eslint ...` | ✅ 0 hata |
| DB QA (disposable klon) | `docker exec ... psql -f qa_faz20_...sql` | ✅ 10 PASS / 0 FAIL |
| Production build | `npm run build` | ✅ başarılı (24 sayfa) |

**DB QA sonuçları (disposable `supabase_db_qa-faz20`, 001–121 uygulandı):**

```
T-01|PASS|claimsiz erisim reddedilir (42501)
T-02|PASS|authenticated yetkisiz reddedilir (42501)
T-03a|PASS|ai.manage islem durumu: batch/phase/gates/provider/retry
T-03b|PASS|retry.supported=false + gate_retry_not_supported
T-03c|PASS|allowlist temiz + waiting_* alanlari mevcut
T-04|PASS|authenticated + question_reviewer (questions.approve) OK
T-05|PASS|olmayan paket P0002 (Aday paketi bulunamadi.)
T-06|PASS|null id 22023 (p_batch_id zorunludur.)
T-07|PASS|EXECUTE matrisi: anon yok, authenticated+service_role var
T-08|PASS|owner=supabase_admin, SECURITY DEFINER, STABLE, search_path=""
toplam|gecen|kalan = 10|10|0
```

**QA kurulum notları (disposable ortam gerçeği; test gevşetme değil):**
- `apply_mig_tmp.sh` deseni ile tüm migration 001–121 `qa` DB'sine
  psql ile uygulandı (`supabase_migrations` tablosu bu image'da yok).
- `auth.users` kolonu bu image 17.6.1.155'te `confirmed_at` ('email_
  confirmed_at' değil) → QA betiği buna uyarlandı; migration'ların
  hiçbirinde bu kolon geçmez.
- `auth.uid()` → `request.jwt.claim.sub`, `auth.role()` →
  `request.jwt.claim.role` GUC'larını okur → QA helper'ı üç claim
  GUC'unu da set edecek şekilde genişletildi (yalnız
  `request.jwt.claims` yetmez).

**Test kapsamı (Faz 20):**
- `candidate-batches.test.ts` (`getCandidateBatchOperationStatus` +
  `mapOperationGateCounts`): ok eşleme, allowlist sızdırmama, raw alan
  sızmaz, notFound → ok+null, hata → error (ham metin taşınmaz).
- `candidate-batches-errors.test.ts`: +%1 `Iislem durumu ... forbidden`.
- `islem-durumu/page.test.tsx`: auth/login, yetki/dashboard redirect,
  geçersiz uuid (RPC yok), ok+null, hata durumu, render içerikleri,
  raw alan sızması yok, retry düğmesi yok, mutation import yok.
- `[id]/page.test.tsx`: başlık linki için mevcut render bozulmadı.

## 6b. Production Build

`npm run build` (Next 16.3.1, Turbopack) ✅ başarılı:
- Compile OK (12.1s), TypeScript OK (19.5s), 24 sayfa statik/SSR üretildi.
- `/admin/candidate-batches/[id]/islem-durumu` rotası build'te yer aldı.
- Proxy (Middleware) dahil tüm rota ağacı hatasız numaralandı.

## 7. Çalıştırılmayan / Yapılmayan İşler

- **Ana stack / hosted'e migration UYGULANMADI** — kullanıcı yasağı
  gereği; 121 yalnız izole disposable klonda uygulandı ve QA edildi.
  RPC'nin gerçek DB davranışı (ACL matrisi, DISTINCT ON son-run sayaçları,
  error kodları 42501/22023/P0002, allowlist) çalıştırma ile doğrulandı.
- **Commit yapılmadı** (açık izin istenecek); **Push yapılmadı**.
- Çalışan tek akış: disposable container kur → 001-121 uygula → fixture
  ekle → QA koş → container sil. Bu akış tamamlandı ve sonrasında
  `supabase_db_qa-faz20` kaldırıldı; ana stack ve diğer QA/disposable
  container'lar (wana typesfix, faz14e-qa, iso19 vb.) hiç değişmedi
  (envanterle teyitli).
- 121 ana/üretim ortamına uygulanmadan `/admin/candidate-batches/[id]/
  islem-durumu` gerçek RPC ile çalışmaz — production'da migration
  uygulanana dek sayfa hata görünümü döner.

## 8. Git Durumu

- Çalışma HEAD: Faz 19 commit'i (`e361618`) — push edilmemiş (origin 1 geride).
- Faz 20'ye ait değişiklikler (madde 3) staged değil, commit yok.
- Kullanıcının modified/untracked dosyalarına dokunulmadı; yalnız Faz 20
  kapsamındaki dosyalar değiştirildi/oluşturuldu.

## 9. Sonraki Adımlar

1. Commit onayı al (yalnız Faz 20 dosyaları) → ardından push onayı.
2. Push sonrası CI'da build doğrulanır; üretim DB'ye migration 121
   alımı ürün/dağıtım kararıyla ayrıca planlanır.
3. Gate retry mekanizması ürün kararı olarak planlanır (Faz 20 kapsamı
   yalnız görünümdü; `retry.supported=false` mantıklı, davranış QA'lı).
4. QA betiği (faz20 fixture + operation_status) ve bu komut deseni
   sonraki fazlarda reusable kalıptır (apply deseni + auth GUC gerçeği).