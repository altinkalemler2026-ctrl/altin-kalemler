# Migration 067/068/069 Faz 2 — Son Yerel Doğrulama Raporu

- **Tarih/Saat:** 23 Ağustos 2026 (+02:00) — **Review düzeltme turu (F-1/F-2/F-4/F-5)**
- **Ortam:** Yalnızca yerel Supabase (Docker: `supabase_db_yarisma-programi`, PostgreSQL 17). Production'a bağlanmadı; `link`/`login`/`db push` çalıştırılmadı.
- **Kapsam:** Önceki oturumun read-only Security+Reality+Code Review bulgularından **F-1, F-2, F-4, F-5**'in uygulanması ve tam yeniden doğrulama. (F-3/F-6/F-7 bilgi notu niteliğindeydi; kapsam dışı bırakıldı.)
- **QA Suite:** `scripts/qa_faz2_local_validation.sql` — **40 test** / tek transaction + final ROLLBACK
- **Paralel Probe:** `scripts/qa_faz2_parallel_probe.sql` — MODE=setup/work/**same**/verify/cleanup; farklı-kullanıcı VE aynı-kullanıcı paralel koşumları

## Özet Sonuç

| Metrik | Değer |
|---|---|
| Temiz reset | `npx supabase db reset` sıfırdan hatasız (001→069) — düzeltme sonrası yeniden koşuldu |
| Faz 1 QA suite | **34 / 34 PASS** (`kalan=0`) — T-01 ileriye dönük uyumlulaştırıldı (aşağıda beyan) |
| Faz 2 QA suite | **40 / 40 PASS** (`kalan=0`) — yeni F-testleri dahil |
| Probe (farklı kullanıcı) | A=500, B=500 → verify PASS/PASS, `VERIFY_PASS`, exit=0 |
| Probe (aynı kullanıcı, F-2) | İki işçi AYNI sayaçta yarıştı → paylaşılan sayaç **500**, exposure **500**, `VERIFY_PASS`, exit=0 |
| Kalıntı | Sıfır (suite ROLLBACK + probe cleanup + bağımsız kalıntı sorgusu = 12 tabloda 0) |

## Uygulanan Bulgular ve Çözümler

### F-1 — Paket kesin listesi + snapshot kaynak sabitleme (ORTA)
- **068:** `prepare_competition_pack` artık seçilen kesin `question_ids` dizisini `competitions.configuration.faz2_pack.question_ids` alanına yazıyor (`vault_id/context/priority/question_ids/selected_at`). UPDATE `found=false` ise P0001.
- **069:** Yeni `guard_faz2_snapshot_source()` BEFORE INSERT OR UPDATE OF question_id trigger'ı (`trg_competition_questions_faz2_source_guard`): `faz2_pack.question_ids` içeren yarışmaya listede OLMAYAN soru yazılamaz (P0001). Böylece hangi yazıcı kullanılırsa kullanılsın snapshot yalnız bu listeden gelebilir. `faz2_pack` olmayan yarışmalar (Faz 1 akışı) etkilenmez. Fonksiyon EXECUTE public/anon/authenticated'dan alınmış (kapalı-varsayılan). Mevcut `guard_competition_question_snapshot` ile uyumlu (biri kaynağı sabitler, diğeri değişmezliği korur).
- **Test:** Yeni **T-08g** (metadata'da 5 elemanlı liste, tümü VA aktif üyeleri), **T-08h** (listeden olmayan Q9 K1'e giremez → P0001), **T-08i** (listeden PA-1 yazılabilir; yasal yol açık).

### F-2 — Aynı-kullanıcı paralel seçim kanıtı (ORTA)
- **Probe:** Yeni `MODE=same`: TAG=a ve TAG=b **bilinçli olarak aynı oyuncuyla** (PC) çalışır; iki oturum aynı haftalık sayacın kilitlenmesi için yarışır. 12 tur × 50 × 2 oturum = 1200 talep, paylaşılan tavan 500.
- **verify güçlendirildi:** Sert geçit eklendi — herhangi bir sayaç satırında `kullanilan > 500` veya `kullanilan != training exposure` varsa ya da hiç sayaç yoksa DO bloğu exception fırlatır; `ON_ERROR_STOP=1` ile psql exit code ≠ 0 olur. Başarıda `VERIFY_PASS`.
- **Sonuç:** Her iki işçi hatasız tamamladı; paylaşılan sayaç her iki oturumdan da **500** okundu; `kullanilan == exposure == 500` → PASS.

### F-4 — Eşleme onay kapısı (DÜŞÜK)
- Şemadan doğrulandı: `question_curriculum_mappings.review_status` (004:526) ve `question_outcome_mappings.review_status` (010:109) enum'u **('pending','approved','rejected','needs_review')** — değer tahmin edilmedi.
- **068:** Konu kapısı (her iki aday havuzu sorgusunda) artık `cm.review_status = 'approved'` istiyor; kazanım yolu `om.review_status <> 'rejected'` yerine aynı şekilde `'approved'`'e sıkılaştırıldı. Yalnız ONAYLANMIŞ eşleme üzerinden soru seçilir.
- **Test:** Fixture'a Q17 eklendi (practice kasası üyesi, eşlemesi `pending`). **T-02a** Q17'nin ilk seçimde gelmediğini doğrular; **T-02e-a/b** eşleme `approved` yapılınca Q17'nin tek yeni soru olarak geldiğini, sayacın 8→9 ve exposure'un 9 olduğunu doğrular. T-03 beklentileri 9'a güncellendi.

### F-5 — Payload sanitizasyonu denylist→allowlist (ORTA)
- **068:** `_faz2_sanitize_question_payload` artık `jsonb_build_object` ile **açık izin listesi** kurar: `id, question_code, grade_level, subject_id, question_text, option_a..option_e, difficulty, has_visual, estimated_solve_time_seconds`. `correct_answer`, çözüm/açıklama/onay/reviewer/internal alanları ve **gelecekte questions tablosuna eklenecek herhangi yeni kolon** bu listeye yazılmadıkça payload'a giremez.
- Not: `question_code` bilinçli olarak tutuldu — 021 `get_competition_question_payload` bugün de öğrenciye gösteriyor; cevap sızıntısı taşımayan referans kodudur (Faz 1 öğrenci yüzeyiyle paralellik).
- **Test:** **T-02b** allowlist dışı anahtar = 0 + `question_text` zorunluluğu ile "tam allowlist" iddiasını doğrular.

## Bu Oturumda Değişen Dosyalar

| Dosya | Değişiklik |
|---|---|
| `supabase/migrations/068_faz2_question_selection.sql` | F-1 (question_ids metadata + found guard), F-4 (approved kapısı ×2), F-5 (allowlist) |
| `supabase/migrations/069_faz2_attempt_ingestion.sql` | F-1 (guard_faz2_snapshot_source fonksiyonu + trigger + revoke) |
| `scripts/qa_faz2_local_validation.sql` | Q17 fixture, T-02a/b güçlendirme, T-02e-a/b, T-08g/h/i, T-03/T-04 uyumu (35→40 test) |
| `scripts/qa_faz2_parallel_probe.sql` | F-2 (MODE=same + verify sert geçidi) |
| `scripts/qa_faz1_local_validation.sql` | **Sapma — aşağıda beyan edildi**: yalnız T-01 boolean ifadesi |
| `docs/reports/latest-phase2-validation.md` | Bu rapor |

Dokunulmayanlar: 001–066'nın tamamı (021, 023 dahil), `scripts/import-legacy-excel.ts`, `.env*`.

### Sapma Beyanı — `scripts/qa_faz1_local_validation.sql` T-01
Zincire 067–069 eklendiği anda Faz 1 suite'inin T-01'i tasarım gereği kırılıyordu: assertion migration geçmişini **birebir** sabitliyordu (`count = 65` ve `max(version) = '066'`). Bu, "066'dan sonra hiçbir migration gelemez" iddiasıdır; Faz 2'nin varlığıyla yapısal olarak çelişir ve Faz 1 davranışıyla ilgisi yoktur (yazıldığı andaki repo durumunun kazara snapshot'ıdır). Kök-neden düzeltmesi olarak yalnız bu ifade, Faz 1 sürümlerinin **eksiksiz uygulandığını** doğrulayan (001..066 \ {050} kümesinin tamamının mevcudiyeti) ama daha yeni sürümleri yasaklayan şekle çevrildi. Faz 1'in doğruladığı hiçbir garanti zayıflatılmadı; suite **34/34 PASS**. Bu dosyanın değişimi talimat kapsamı sınırındadır; geri alınması istenirse tek hunk'tır.

## Test Sonuç Tablosu (40/40 PASS)

Önceki rapordaki T-01..T-12 sonuçlarının tümü aynen korunmuştur (PASS). Bu turda eklenen/güncellenen satırlar:

| T-id | Test | Sonuç |
|---|---|---|
| T-02a | seçim: new_count=8; Q6/Q7 **ve Q17** (pending eşleme) payload'da değil | PASS |
| T-02b | payload **tam allowlist** (izinli 13 alan dışına çıkmaz) | PASS |
| T-02e-a | eşleme onaylanınca Q17 seçilir (new_count=1) | PASS |
| T-02e-b | UA sayaç ve training exposure 9'a çıktı | PASS |
| T-03 | tekrar seçim: repeat=9, new=0, sayaç değişmez (9) | PASS |
| T-08g | faz2_pack metadata: 5 elemanlı kesin question_ids listesi (VA üyeleriyle birebir) | PASS |
| T-08h | paket listesinde OLMAYAN soru snapshot'a giremez (P0001) | PASS |
| T-08i | listeden soru snapshot'a yazılabilir (yasal yol açık) | PASS |

## Paralel Probe Sonucu (iki mod)

1. **MODE=work (farklı kullanıcı):** Havuz 560 soru; PC ve PD eşzamanlı 12×50 çekti → FINAL_USED=500/500; verify: her iki kullanıcida `kullanilan == exposure == 500` → PASS/PASS.
2. **MODE=same (aynı kullanıcı, F-2):** Temiz fixture sonrası iki oturum PC adına eşzamanlı 12×50 çekti (talep 1200 > tavan 500). İki işçi de P0001'siz tamamladı; paylaşılan sayaç iki oturumdan da 500; verify `kullanilan == exposure == 500` → PASS. FOR UPDATE sayaç kilidi + delta tabanlı consume, gerçek aynı-hesap yarışında tavanı ve tutarlılığı korudu.
3. Her mod arasında cleanup; sonunda bağımsız kalıntı sorgusu: **12 tabloda 0 satır**.

## Güvenlik Kontrollerinin Durumu

- SECURITY DEFINER fonksiyonlar `set search_path = ''` ile tanımlı; kullanıcı kimliği yalnız `auth.uid()`'den.
- Private helper'lara EXECUTE kapalı; yalnız üç RPC authenticated'a açık. Yeni `guard_faz2_snapshot_source` da kapalı.
- Snapshot zinciri: kaynak sabitleme (F-1 trigger) + değiştirilemezlik (karar #4 trigger) birlikte çalışır; T-08h/T-08i/T-09a–d kombinasyonla kanıtlandı.
- 021/023 **değiştirilmedi**; tüm baskılar additive 067+/068/069 katmanında.

## Kalan Riskler

1. **Faz 1 raporundaki istemci DML grant boşluğu** (F-3 ile ilgili geniş konu) Faz 2 kapsamı dışında; ilgili özellikler devreye alındığında fix-forward gerekir.
2. Probe committed veri yazar; setup öncesi reset veya sonrasına cleanup önerilir (bu turda her ikisi de yapıldı).
3. Clamp semantiği (kapasite dolmuş oyuncuya paket gösterimi) ürün kararı olarak duruyor.
4. Versiyon kontrol: 067–069, QA scriptleri ve rapor git'te izlenmiyor; **ek olarak `scripts/qa_faz1_local_validation.sql` artık `M` (modified)** — yukarıdaki sapma beyanına tabidir. Commit kararı kullanıcıya aittir.

## Git Durumu (rapor anı)

```
 M scripts/qa_faz1_local_validation.sql
?? .opencode/
?? docs/reports/latest-phase2-validation.md
?? opencode.json
?? scripts/qa_faz2_local_validation.sql
?? scripts/qa_faz2_parallel_probe.sql
?? supabase/migrations/067_academic_weeks_calendar.sql
?? supabase/migrations/068_faz2_question_selection.sql
?? supabase/migrations/069_faz2_attempt_ingestion.sql
?? supabase/snippets/
```

İzlenen diğer hiçbir dosya değiştirilmedi. 021, 023 ve diğer mevcut migration'lar dokunulmadı.

## Uyum Teyidi

- Yalnız yerel Supabase/Docker kullanıldı; production bağlantısı, `supabase link/login/db push` **yapılmadı**.
- Git commit/push/reset/checkout **yapılmadı**.
- `.env`, anahtar/secret dosyaları ve `scripts/import-legacy-excel.ts` **okunmadı/değiştirilmedi**.

## Sonuç

- Review bulguları F-1, F-2, F-4, F-5 kök nedenlerinde düzeltildi; her biri için kalıcı otomatik test/probe kanıtı eklendi.
- Zincir sıfırdan oynatıldı; **Faz 1 34/34**, **Faz 2 40/40 PASS**; probe iki modda da `VERIFY_PASS` (exit=0); kalıntı sıfır.
- Bilinen tek kapsam-dışı sapma: Faz 1 QA T-01'inin ileriye dönük uyumlulaştırılması (yukarıda beyan edildi).
