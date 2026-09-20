# Faz 21 Nihai Rapor

**Tarih:** 2026-09-20
**Model:** big-pickle (opencode)
**Sorumlu:** selami

---

## 1. Sonuç Özeti

| Metrik | Değer |
|---|---|
| **Durum** | ✅ BAŞARILI (duran görev tamamlandı) |
| Migration | 122_admin_question_edit_content_change_gate.sql (635 satır) |
| Migration durumu | UYGULANDI + QA **yalnız izole disposable klonda** (`supabase_db_qa-faz21`, port 61422, default bridge) |
| Migration hedefi | Ana stack / hosted **DOKUNULMADI**; disposable container QA sonrası **SİLİNDİ** |
| Bulunan hata | QA scriptinde `auth.users.email_confirmed_at` → `confirmed_at` (17.6.1.155 image gerçeği) |
| tsc --noEmit | ✅ 0 hata |
| eslint (Faz 21 dosyaları) | ✅ 0 hata |
| vitest (2 dosya) | ✅ 60/60 (actions.test.ts 30 + question-edit.test.ts 30) |
| DB QA (scripts/qa_question_edit_gate_122_local.sql) | ✅ **19/19 PASS, 0 FAIL** (disposable klonda) |
| Production build | ✅ `next build` başarılı (24 sayfa; admin/questions/[id] dahil) |
| Git | Commit YAPILMADI (onay bekleniyor) |
| Push | YAPILMADI |

---

## 2. Duran Görevin Kapsamı ve Kök Nedeni

Bir önceki oturumda duran görev, **P0 "işleyen soruda değişiklik kapısı"**
uygulamasıydı (Faz 16 §8 P0 maddesi): yayında/onaylı bir sorunun içeriği
değişir değişmez **otomatik pasife alınması + yeniden denetim (needs_review)**
+ güvenli yeniden onay (requalify) akışı.

Kod tarafı tamamlanmış ve testleri yazılmıştı; duran adım **DB QA idi**.
Hata kaydı `docs/reports/` içinde faz21 raporu olmadığından doğrudan yok:
kök neden, QA scriptinin disposable image (`public.ecr.aws/supabase/
postgres:17.6.1.155`) üzerinde `auth.users.email_confirmed_at` kolonunu
kullanmasıydı — bu image'da kolon adı **`confirmed_at`** (Faz 20 raporunun
"QA kurulum notları" bölümünde aynı gerçek not edilmişti). Migration'ların
hiçbirinde bu kolon geçmez; hata yalnız QA scriptindeki auth.fixture
INSERT'inde patladı.

**Düzeltme (en küçük güvenli):** `scripts/qa_question_edit_gate_122_local.sql`
satır ~156-160 — `email_confirmed_at` → `confirmed_at`. Davranış değiştirmedi;
yalnız fixture insert şemasını image gerçeğine uydurdu.

---

## 3. Görev Kapsamı (tamamlanan)

**Migration 122** (`supabase/migrations/122_admin_question_edit_content_change_gate.sql`):

1. `private.admin_question_edit` — 089 signature birebir korunur, davranış
   additive genişler:
   - **TETİKLEYİCİ alanlar:** question_text, option_a..e, correct_answer,
     has_visual (öğrencinin gördüğü içerik + görsel içerik).
   - **TETİKLEMEYEN alanlar:** difficulty, cognitive_type, quality_level,
     primary/secondary_question_type, estimated_solve_time_seconds,
     is_new_generation (metadata).
   - No-op tespiti: tetikleyici alanların hiçbiri değişmediyse kapı tetiklenmez.
   - Onaylı sorunun içeriği değiştiyse → `approval_status='needs_review'`,
     `is_active=false`; yayındayken (was_active) ayrıca
     `question_publication_events`'e otomatik `deactivate` event yazılır
     (`checks_snapshot` + `metadata.automatic_content_change_gate=true`).
   - Approval/metadata geçmişi değişmez; audit append-only.
2. `private.admin_question_requalify` — YALNIZ `needs_review` → `approved`;
   `is_active=false` KALIR (öğrenciye otomatik açılmaz; yayın için 040
   activate ayrı insan adımı). İzin `questions.approve` (42501). Audit
   `question.requalify` atomik. Zaten approved → `already_approved` (no-op,
   yeni audit yok). Draft/rejected → 22023.
3. Public INVOKER sarmalayıcılar + canonical grant matrisi (revoke
   public/anon; grant authenticated/service_role) — 040/089 deseni.

**Kod katmanı:**
- `src/app/(admin)/admin/questions/[id]/actions.ts` — `editQuestionAction`
  RPC yanıtındaki `review_required`'a göre özel Türkçe flash
  (`editReviewRequired`); yeni `requalifyQuestionAction`. İzin guard'ı
  hem aksiyonda (fail-closed) hem RPC'de (otoriter 42501).
- `src/app/(admin)/admin/questions/[id]/page.tsx` — yalnız
  `questions.approve` sahibi için, `needs_review` durumunda "Yeniden Denetim
  Gerekli" kartı + "Yeniden Onayla" formu (SEMANTİK: requalify öğrenciye
  açmaz, ayrı yayın adımı gerektiği metinle belirtilir).
- `src/lib/admin/question-edit-errors.ts` / `question-bank.ts` /
  `admin-panel-messages.ts` — kapı ve requalify Türkçe mesaj eşleme +
  `statusNeedsReview` etiketi.
- `actions.test.ts` (+149), `question-edit.test.ts` (+97) — kapı flash'ı,
  fail-closed, izin matrisi, 122 sözleşmesi.

---

## 4. Doğrulama Sonuçları

| Kontrol | Komut | Sonuç |
|---|---|---|
| Faz 21 birim test | `vitest run` (2 dosya) | ✅ 60/60 passed / 0 failed |
| tip kontrolü | `tsc --noEmit` | ✅ 0 hata |
| lint (Faz 21 dosyaları) | `eslint ... admin/questions, src/lib/admin` | ✅ 0 hata |
| DB QA (disposable klon) | `docker exec psql -f qa_question_edit_gate_122_local.sql` | ✅ 19 PASS / 0 FAIL |
| Production build | `npm run build` | ✅ başarılı (24 sayfa) |

**DB QA sonuçları (disposable `supabase_db_qa-faz21`, 001–122 uygulandı):**

```
T-01a|PASS|icindekim degisti: review_required=true cikisi
T-01b|PASS|kapı sonrasi: is_active=false ve approval_status=needs_review
T-01c|PASS|deactivate publication event yazildi (automatic_content_change_gate)
T-01d|PASS|audit question.edit yazildi
T-02 |PASS|difficulty degisikligi kapıyı tetiklemez; approved+active kalir
T-03 |PASS|has_visual degisikligi kapıyı tetikler (needs_review+pasif)
T-04a|PASS|pasif onayli soruda icerik degisikligi needs_review yapar
T-04b|PASS|pasif soruda publication event YAZILMAZ (event_sayisi=0)
T-05 |PASS|ayni degerlerle kayit kapıyı tetiklemez (no-op)
T-06a|PASS|requalify needs_review -> approved yapar
T-06b|PASS|requalify sonrasi is_active FALSe KALIR
T-06c|PASS|requalify audit question.requalify yazar
T-07a|PASS|zaten approved soru already_approved no-op dondurur
T-07b|PASS|already_approved icin yeni audit yazilmaz
T-08 |PASS|draft soru requalify edilemez (22023)
T-09 |PASS|questions.edit izni olmayan edit -> 42501
T-10 |PASS|questions.approve izni olmayan requalify -> 42501
T-11 |PASS|needs_review soru 040 readiness ile yayinlanamaz (question_not_approved)
T-12 |PASS|audit append-only (onceki=7 sonra=8)
toplam|gecen|kalan = 19|19|0
```

**QA kurulum notları (disposable ortam gerçeği; test gevşetme değil):**
- `apply_mig_tmp.sh` deseniyle 001–122 tüm migrationlar `qa` DB'sine psql
  ile uygulandı → `ALL_MIGRATIONS_OK`.
- `auth.users.email_confirmed_at` → `confirmed_at` (17.6.1.155 image gerçeği,
  Faz 20 ile aynı); bu tek satırlık düzeltme duran görevin kök nedeniydi.
- Tüm suite TEK TRANSACTION içinde çalışır ve ROLLBACK ile biter — hiçbir
  test artefaktı kalıcı değildir.

---

## 5. Çalıştırılmayan / Yapılmayan İşler

- **Ana stack / hosted'e migration UYGULANMADI** — kullanıcı yasağı
  gereği; 122 yalnız izole disposable klonda uygulandı ve QA edildi,
  container silindi.
- **Commit yapılmadı** (açık izin istenecek); **Push yapılmadı**.
- Kullanıcının "görev dışı" değişiklikleri (öğrenci alanı tema/training/
  review, `src/app/globals.css` arena/atolye renk paleti vb.) hiçbir şekilde
  değiştirilmedi; yalnız Faz 21 kapsamındaki dosyalar dokunuldu.

---

## 6. Git Durumu

- Çalışma HEAD: Faz 20 commit'i (`173c6d0`) — push edilmemiş (origin 2 geride).
- Faz 21'e ait değişiklikler (madde 3) commit değil.
- Faz 21 dosyaları:
  - `supabase/migrations/122_admin_question_edit_content_change_gate.sql` (untracked)
  - `scripts/qa_question_edit_gate_122_local.sql` (untracked)
  - `src/app/(admin)/admin/questions/[id]/actions.ts` (+70)
  - `src/app/(admin)/admin/questions/[id]/actions.test.ts` (+149)
  - `src/app/(admin)/admin/questions/[id]/page.tsx` (+37)
  - `src/app/(admin)/admin/questions/page.tsx` (+2)
  - `src/lib/admin/question-edit-errors.ts` (+10)
  - `src/lib/admin/question-edit.test.ts` (+97)
  - `src/lib/admin/question-bank.ts` (+1)
  - `src/lib/admin/admin-panel-messages.ts` (+2)

---

## 7. Sonraki Adımlar

1. Commit onayı al (yalnız Faz 21 dosyaları) → ardından push onayı.
2. Üretim DB'ye migration 122 alımı ürün/dağıtım kararıyla ayrıca planlanır.
3. Matematik içerik kaydı (soru-uretim-takip-v8) bağımsız inceleme sırasında;
   bu fazla ilgisi yoktur.