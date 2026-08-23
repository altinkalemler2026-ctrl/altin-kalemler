# Faz 3 Temel Doğrulama Raporu — Güvenli Antrenman Cevap Gönderimi (070)

**Tarih:** 23 Ağustos 2026 (2. tur: final güvenlik incelemesi düzeltmeleri dahil)
**Kapsam:** Migration `070_training_answer_submission.sql`, `071_faz2_rpc_execute_hardening.sql` + `scripts/qa_faz3_local_validation.sql`
**Ortam:** Yerel Supabase/Docker (`supabase_db_yarisma-programi`), dal `main` @ `efc1276`
**Git:** Bu görev kapsamında commit/push/production işlemi YAPILMADI; tüm çıktılar yerel çalışma ağacında (bkz. §11).

---

## 1. Amaç

Faz 2'de istemci `ingest_student_attempt`'a correct/wrong sonucunu kendisi bildiriyordu.
Training bağlamında bu güvenilir değildir: doğruluk yalnız sunucuda,
`questions.correct_answer` üzerinden hesaplanmalıdır. Faz 3 temeli olarak:

- İstemcinin gönderebildiği: `question_id`, şık (`A..E`) veya eylem
  (`pass|timeout|blank`), `time_ms`, zorunlu idempotency anahtarı (`client_key`).
- Sunucunun ürettiği: sonuç (`correct/wrong`), attempt kaydı, metrikler.
- İstemcinin asla alamayacağı: `correct_answer`, çözüm içeriği.

## 2. Değişen / Eklenen Dosyalar

| Dosya | İşlem |
|---|---|
| `supabase/migrations/070_training_answer_submission.sql` | **YENİ** — RPC + idempotency index + sahte-sonuç kapanışı (2. turda yalnız bölüm-4 yorumu F-A ile uyumlu hale getirildi) |
| `supabase/migrations/071_faz2_rpc_execute_hardening.sql` | **YENİ (2. tur)** — Faz 2 üç RPC'si için PUBLIC/anon EXECUTE revoke + authenticated grant |
| `scripts/qa_faz3_local_validation.sql` | **YENİ** — 34 testlik Faz 3 QA suite (T-D4/T-F3 sorguları 2. turda kullanıcı filtreli) |
| `scripts/qa_faz2_local_validation.sql` | **DÜZELTME** — T-06/T-07/T-11 rolleri (bkz. §5a); 2. turda T-01d..l EXECUTE matris testleri eklendi |
| `docs/reports/latest-phase3-foundation-validation.md` | **YENİ** — bu rapor |

`001–069` migration dosyaları **değiştirilmedi** (069 dahil; F-B için 068 yerine
additive `071` üretildi). `021/023` yarışma akışına dokunulmadı.
`.env*`, seed, import betikleri, `.opencode/`, `opencode.json`, `supabase/snippets/`
hiçbir oturumda değiştirilmedi.

## 3. 070 İçeriği

### 3.1 `submit_training_attempt(p_question_id, p_choice, p_action, p_time_ms, p_client_key)`

- `SECURITY DEFINER`, `set search_path=''`, `auth.uid()` zorunlu (42501).
- `p_client_key` **zorunlu uuid** (22004) — idempotency istemciye zorlatılır.
- Süre clamp'i: negatif 0 olur, üst sınır 3.600.000 ms.
- Şık/eylem karşılıklı dışlayıcı (P0001); şık normalizasyonu `upper(btrim())`.
- Puanlama tek kaynak: aktif sorunun `correct_answer`'ı (CHECK: NULL veya A–E).
  Aktif olmayan ya da cevap anahtarsız soru **fail-closed** (P0001).
- Gösterim kapısı: `student_question_exposures` PK `(user_id, question_id, 'training')`
  yoksa P0001 — başkasının sorusuna cevap yazılamaz; `user_id` her zaman
  `auth.uid()`'den gelir.
- Yazım `public.ingest_student_attempt(...)`'a devredilir: aynı advisory lock,
  `attempt_number`, dönem zorunluluğu ve 7 metrik kapsamı korunur.
  Metadata: `client_key` + `graded_by=db_correct_answer`.

### 3.2 Idempotency

- Partial unique index:
  `(user_id, metadata->>'client_key') WHERE attempt_context='training'
  AND metadata->>'client_key' IS NOT NULL`.
- Ön-okuma hızlı yol; eşzamanlı yarışta index ihlali (23505) yakalanır,
  ikinci çağrının kısmi etkileri geri alınır ve mevcut attempt
  `duplicate:true` ile döner. Çift metrik DB seviyesinde imkânsızdır.

### 3.3 Minimal Yanıt Sözleşmesi

`{attempt_id, attempt_number, result, duplicate}` — allowlist testiyle sabitlenir;
`correct_answer`/`solution` sızıntısı test edilir (T-F2).

## 4. KRİTİK BULGU: 069'daki PUBLIC EXECUTE Açığı

Doğrulama sırasında saptandı: **069, `ingest_student_attempt` için PostgreSQL'in
varsayılan `PUBLIC EXECUTE` grant'ını geri almamıştı.** Anon/authenticated fonksiyonu
PUBLIC üzerinden çağırabiliyordu; Faz 2 suite'inin anon reddi testi aslında
fonksiyon-içi `auth.uid()` kontrolünden (42501) geçiyordu, yetki reddinden değil.

**070 kapanışı:** `REVOKE EXECUTE ... FROM public, anon, authenticated`.
Fonksiyon artık HİÇBİR istemci rolü tarafından çağrılamaz; yalnız owner (postgres)
bağlamındaki sunucu içi çağrı çözülür. Bu bilinçli ve gerekli bir davranış
değişikliğidir (güvenlik düzeltmesi).

## 4A. Final Güvenlik İncelemesi: Bulgular ve Çözümler

Salt-okunur final inceleme üç bulgu üretti (KARAR: ONAY, bloklayıcı yok);
ikinci turda tamamı giderildi:

### F-A — 070 yorumu service_role izni hakkında yanıltıcıydı (Düşük)

`pg_proc` doğrulaması: `ingest_student_attempt` ve `submit_training_attempt`
her ikisi de `SECURITY DEFINER`, `search_path=""`, **owner=postgres**.
069'da service_role'a explicit EXECUTE hiç verilmemişti. Yorum "service_role
kalır" diyordu; gerçekte revoke sonrası explicit EXECUTE'i olan sıfır rol var.

**Çözüm:** Grant tahmin edilerek eklenmedi. 070 bölüm-4 yorumu gerçek modelle
değiştirildi: sunucu içi yol, definer-owner (postgres) kimliğiyle çalıştığı
için çağıran rolun EXECUTE iznine bağlı değildir — şemadan kanıtlandı.

### F-B — 068'in üç RPC'sinde PUBLIC EXECUTE kalıntısı (Düşük → kapatıldı)

Canlı `proacl`: üç RPC'de `=X/postgres` (PUBLIC) vardı. 068 commit'li olduğu
için dosya DEĞİŞTİRİLMEDİ; additive **071_faz2_rpc_execute_hardening.sql**
üretildi:

- İmzalar `pg_get_function_identity_arguments` ile şemadan doğrulandı:
  `select_training_questions(uuid, integer)`,
  `get_my_weekly_usage()`,
  `prepare_competition_pack(uuid)` — hepsi SECURITY DEFINER +
  `search_path=''` + owner=postgres.
- Her biri için `REVOKE EXECUTE FROM public, anon` + `GRANT EXECUTE TO
  authenticated`. Definer/auth.uid()/search_path modeline dokunulmadı;
  service_role'a bilerek grant eklenmedi.
- Reset sonrası canlı ACL teyidi: PUBLIC girdisi üçünde de kalktı,
  yalnız `postgres=X, authenticated=X` kaldı.

### F-C — qa_faz3 T-D4/T-F3 sorguları kullanıcı filtresizdi (Çok düşük)

Her iki sorguya da ilgili fixture kullanıcısı (`user_id = …901 / …902`)
filtresi eklendi; test artık kullanıcı izolasyonunu açıkça doğrular.

## 5. Sapma Beyanları

**a) `qa_faz2_local_validation.sql` T-06/T-07/T-11 düzenlemesi (zorunlu uyum):**
070 sonrası bu blokların `set local role authenticated` ile ingest çağırması mümkün değil
(fonksiyona istemci erişimi kapandı). Bloklar postgres rolüyle ama aynı JWT claim
GUC'leriyle çalışacak biçimde güncellendi (`auth.uid()` claim'den okunur;
fonksiyonlar SECURITY DEFINER olduğundan davranış birebir aynıdır). Suite çıktısı
değişmedi: 40/40. Bu düzenleme, 070'in güvenlik düzeltmesinin kaçınılmaz sonucudur
ve Faz 2 test kapsamında azaltma (zayıflatma) yaratmaz.

**b) Faz 1 T-01 forward-compatible hali korundu** (önceki oturumda onaylı sapma;
bu oturumda ek dokunuş yapılmadı).

## 6. Test Sonuçları (2. tur final koşu)

Yöntem (LOCAL ONLY): `npx supabase db reset` (001–071 temiz uygulandı) sonrası üç suite
`psql -v ON_ERROR_STOP=1` ile koşuldu; her suite tek transaction + final ROLLBACK.

| Suite | Sonuç |
|---|---|
| `qa_faz1_local_validation.sql` | **34/34 PASS**, kalan=0 |
| `qa_faz2_local_validation.sql` | **49/49 PASS**, kalan=0 (40 + 9 yeni EXECUTE matris testi T-01d..l) |
| `qa_faz3_local_validation.sql` | **34/34 PASS**, kalan=0 |

### Paralel Probe'lar (2. tur)

| Probe | Sonuç |
|---|---|
| Farklı-kullanıcı (`MODE=setup`→`work TAG=a/b` paralel) | Her işçi `FINAL_USED=500`, hata 0; verify: iki kullanıcı PASS/PASS, **VERIFY_PASS exit=0** |
| Aynı-kullanıcı (`MODE=same TAG=a/b` paralel, ortak sayaç) | İki işçi 0 ERROR; paylaşılan sayaç **500'de kilitli** (tavan aşılmadı); verify PASS/PASS, **VERIFY_PASS exit=0** |
| `MODE=cleanup` | CLEANUP_OK |

Post-071 ACL teyidi (canlı): üç Faz 2 RPC'sinde PUBLIC girdisi yok;
yalnız `postgres=X/postgres, authenticated=X/postgres`.

Faz 3 test haritası:

| Blok | Kapsam | Durum |
|---|---|---|
| T-S1–S6 | Yetki sınırları; **sahte-sonuç kapısı** (authenticated→ingest 42501); attempts/exposures doğrudan INSERT reddi | 6/6 |
| T-A1–A2 | Seçim → 5 yeni soru → 5 training exposure | 2/2 |
| T-B1–B7 | DB-side puanlama (wrong/correct/harf esnekliği), metrik birikimi, `p_result` yokluğu (42883), geçersiz şık, şık+eylem çelişkisi | 7/7 |
| T-C1–C4 | Idempotency: aynı key → duplicate=true, orijinal sonuç korunur, tek attempt, metrik sabit; DB seviyesinde 23505 savunması | 4/4 |
| T-D1–D4 | Exposure olmadan cevap yok (cross-user); bağımsız seçim; ownership=user_id(auth.uid()) | 4/4 |
| T-E1–E5 | pass/timeout/blank eylemleri + geçersiz eylem + pass_timeout metriği | 5/5 |
| T-F1–F6 | Yanıt allowlist (yalnız 4 anahtar), sızıntı yok, negatif süre clamp, aktif olmayan/anahtarsız soru fail-closed, client_key zorunlu | 6/6 |

## 7. Kalıntı Kontrolü

Suite'lerin ROLLBACK'i sonrası canlı veritabanında:

```
users_test 0 | attempts 0 | q_exposures 0 | pack_exposures 0
metrics 0 | counters 0 | vaults_qa 0 | questions_qa 0
weeks_qa 0 | curriculum_qa 0 | _qa% tabloları 0
```

Kalıntı: **0**.

## 8. Döngüde Alınan Düzeltmeler

**1. tur (070 geliştirme):**

1. Fixture: outcome schedule item'ı topic kolonuna yazılmıştı → iki ayrı INSERT'e bölündü.
2. `_qa_faz3_results` ve yardımcılara faz2'deki gibi grant'lar eklendi
   (authenticated rolünde koşan `_qa_expect` için gerekli).
3. T-A1 payload anahtarı `weekly_counters` değil `weekly` idi.
4. **070 ilk halinde yalnız authenticated'dan revoke edilmişti; PUBLIC grant
   kaldığı için istemci çağrısı hâlâ başarıyordu (T-S4 bunu yakaladı).
   Revoke `public, anon, authenticated`'a genişletildi** → tüm basamaklı
   testler (T-B1/C1/C2/C3/E5) kendiliğinden düzeldi.

**2. tur (final inceleme düzeltmeleri):**

5. F-A: 070 bölüm-4 yorumu gerçek izin modeliyle değiştirildi (grant eklenmedi;
   definer-owner çağrı yolu şemadan doğrulandı).
6. F-B: Additive `071_faz2_rpc_execute_hardening.sql` üretildi; 068 dosyasına
   dokunulmadı; imzalar şemadan doğrulandı; ACL reset sonrası canlı doğrulandı.
7. F-C: qa_faz3 T-D4/T-F3 sorgularına kullanıcı filtresi eklendi.
8. qa_faz2'ye T-01d..l (9 test) EXECUTE matrisi eklendi → suite 40→49'a çıktı;
   070 submit/ingest yetki testleri (faz3 T-S1–S4, faz2 T-01c) korundu.

## 9. Sonuç ve Sonraki Adımlar

- Faz 3 güvenlik temeli tamam: doğruluk sunucuda, idempotency garanti,
  exposure kapılı, minimal yanıt, sahte-sonuç kanalı kapandı.
- Final inceleme bulgularının tamamı (F-A/F-B/F-C) giderildi ve tam
  regresyonla doğrulandı: üç suite + iki paralel probe yeşil, kalıntı sıfır.
- Önerilen ayrı işler:
  1. UI katmanı: `submit_training_attempt` RPC çağrısı + client_key üretimi
     (Faz 3 hazırlık raporundaki `src/lib/faz2` planına göre).
  2. Veritabanı tiplerinin yeniden üretilmesi (`database.types.ts`) —
     yeni fonksiyon imzalarıyla.
  3. Kalan migration'lar için genel PUBLIC EXECUTE taraması (067 dahil;
     068/069 kapanışı 070+071 ile tamam).

## 10. Doğrulama Ortamı Notları

- Migration zinciri: 001→071 hatasız uygulandı (seed yok — bilinen uyarı).
- Suite çıktıları psql üzerinden doğrulandı; `ON_ERROR_STOP=1` aktif.
- Hiçbir production kaynağına erişilmedi; supabase link/login/db push yapılmadı.

## 11. Git Durumu ve İşlem Teyidi

- HEAD değişmedi: `efc1276 test(phase1): make migration history check forward-compatible`.
- **Commit YAPILMADI, push YAPILMADI, production işlemi YOK.**
- Çalışma ağacı (git status --short):

```
 M scripts/qa_faz2_local_validation.sql
?? .opencode/
?? docs/reports/latest-phase3-foundation-validation.md
?? opencode.json
?? scripts/qa_faz3_local_validation.sql
?? supabase/migrations/070_training_answer_submission.sql
?? supabase/migrations/071_faz2_rpc_execute_hardening.sql
?? supabase/snippets/
```

- Commit onayında stage listesi yalnız şu beş dosya olmalı:
  `supabase/migrations/070_training_answer_submission.sql`,
  `supabase/migrations/071_faz2_rpc_execute_hardening.sql`,
  `scripts/qa_faz2_local_validation.sql`,
  `scripts/qa_faz3_local_validation.sql`,
  `docs/reports/latest-phase3-foundation-validation.md`.
  `.opencode/`, `opencode.json`, `supabase/snippets/` hariç tutulur.

