# AK-GUN-SONU-20261109 — Gün Sonu Kapanış Raporu

**Tarih:** 9 Kasım 2026 · **Durum:** GÜVENLİ DUR — yalnızca yerel commit, canlı uygulama yok

---

## 1. Bugün tamamlanan denetimler

| görev | çıktı | sonuç |
|---|---|---|
| AK-VAULT-42W | `docs/reports/ak-vault-42w-eski-mimari-gecis-plani.md` | Eski 36 kasa → haftalık K1–K42 ADDITIVE geçiş planı (M0–M8, QA Q1–Q10); A1–A5 ürün kararları kullanıcıda |
| AK-SYSTEM-AUDIT-01 | `docs/reports/ak-puanlama-antrenman-yarisma-tam-denetim.md` | v3 puan matrisi canlı örneklerle; 13 adımlı yarışma akışı kanıtlı; antrenman puansız/bireysel; SEC-1 + SEC-1b bulguları; 8 karar maddesi |
| AK-SEC-ANSWER-01 | `docs/reports/ak-sec-answer-01-duzeltme-hazirligi.md` | SEC-1 (`get_internal_correct_answer` fonksiyon ACL) kanıtı + 155 taslağı + izole QA 11 PASS/0 FAIL/1 GAP + rollback kanıtı |
| AK-SEC-ANSWER-02 | `docs/reports/ak-sec-answer-02-sec1b-duzeltme-hazirligi.md` | SEC-1b üç katmanlı açık (politika+tablo+kolon ACL) + 156 taslağı + BİRLEŞİK QA 16 PASS/0 FAIL/0 GAP + drift denetimi |

## 2. İki başarılı EVREN pilotu

- **AK-BULK-EVREN-02** (`docs/reports/ak-bulk-evren-02-bes-soruluk-evren-pilot-raporu-20261109.md`): 5 soruluk gerçek toplu denetim pilotu tek koşuda (`ede47948-…`) **5/5 completed**, tam 5 gerçek model çağrısı, izolasyon kanıtlı (koşu öncesi havuz boş), global completed 20→25.
- **AK-BULK-EVREN-03** (`docs/reports/ak-bulk-evren-03-ikinci-degerlendirici-pilot-raporu-20261109.md`): aynı koşunun ikinci değerlendiricisi **BAŞARILI**; istem baytları birebir aynı (SHA-256 eşitliği) + puanlar farklılaşıyor → bağımsızlık kanıtlı. Uzlaşma: 2 aday `verified` (M9-ILK-005/009), 3 aday `low_confidence` → insan incelemesi kuyruğunda. Otomatik onay/yayınlama YOK.
- Gün sonu kuyruk (salt-okunur): `pending=0 running=0 completed=30`, aktif bulk koşusu=0, makinede worker süreci yok.

## 3. Canlı veri durumu (9 Kas son ölçüm, hepsi salt-okunur)

- **112** aday sonuç satırı (`candidate_batch_candidate_results`), **0** soru (`questions`), **36** kasa (tamamı `academic`), **0** kasa üyeliği (`question_vault_memberships`).
- Soru bankası boş → pack/antrenman fail-closed; yarışma runtime tabloları boş.
- Migration geçmişi maksimumu: **154**.

## 4. 155/156 YALNIZCA TASLAKTIR

- `drafts/ak-sec-answer-01/155_sec1_answer_key_acl.sql` — SEC-1 fonksiyon ACL düzeltmesi.
- `drafts/ak-sec-answer-02/156_sec1b_questions_answer_key_hardening.sql` — SEC-1b politika+ACL düzeltmesi.
- İkisi de canlıya UYGULANMADI; zincirde (`supabase/migrations/`) DEĞİL. İzole kopyada ikişer kez uygulanıp idempotency + fail-closed + tam senaryo QA'si kanıtlandı; QA DB'leri imha edildi.

## 5. SEC-1 ve SEC-1b canlıda HENÜZ KAPATILMADI

Drift denetimi (`scripts/qa_sec_privilege_drift_audit.sql`, salt-okunur) canlı taban ölçümünde **8 kritik DRIFT**: M1 (SEC-1 fonksiyon ACL), M2–M5 (SEC-1b katmanları), M6×3 (lig tabloları). Uygulama sonrası beklenti (QA'da ölçüldü): M1–M5 PASS; M6×3, 157 gelene kadar DRIFT kalmaya devam eder. DIGEST ön durum `724ba6a0…`; 155+156 sonrası kanonik `d3e2eb58…`.

## 6. 157 — şema geneli sertleştirme ihtiyacı (KARAR-3)

108 sertleştirmesi şemanın tamamında geri sarılmış durumda: 161/161 tabloda anon/auth TRUNCATE/REFERENCES/TRIGGER, 159 tabloda anon yazma hakkı, lig tablolarında RPC-only sözleşmesi bozuk. 108'in yeniden uygulanması + ALTER DEFAULT PRIVILEGES + drift üretim kanalının (Studio/ad-hoc) belirlenmesi ayrı migration (157) ve ayrı onay olarak önerilir. En olası köken: 2026-10 cloud-recovery 108-öncesi taban (kesin kanıt yok).

## 7. Kolay → orta → zor geçişindeki eksik bağlantı

Denetim kanıtı: yarışmada zorluk seviyesi geçişi YOK — `student_training_levels`, 018 harita sistemi ve `league_transition_rules` ölü (0 satır, 0 okuyucu). Puan biriktikçe easy→medium→hard akışını sürücüleyen bağlantı hiç kurulmadı; faz30b/018 tasarımı ile kod gerçeği arasında boşluk. Ürün kararı + ayrı dilim gerektirir.

## 8. 42 haftalık kasa mimarisi hedefi

Hedef: akademik yıl 42 haftalık (K1–K42) haftalık kasa yapısına ADDITIVE geçiş — eski 36 kasa + LEGACY yerinde kalır, devreden çıkarma en sonda `is_active=false` ile. Engeller: A1 (seviye kaynağı), A2 (K41/K42 — sentetik K42 üretilmeyecek kararı kullanıcıda), A3 (vault_type politikası), A4/A5 (zorluk ekseni + "tam 5" kuralı) ürün kararları VE soru bankası/membership veri katmanının boş olması (0 soru, 0 üyelik). `academic_weeks`'te yalnız 2026-2027 K1–K41 var.

## 9. Yarın ilk yapılacak güvenli işlem

**ONAY-1 gelirse:** 155+156'nın canlıya uygulanması — AK-SEC-ANSWER-02 rapor §8 ön kontrol sırasıyla (manuel yedek → tek oturumda art arda `psql -v ON_ERROR_STOP=1 -1 -f` → beklenen `NOTICE: SEC1 OK` + `SEC1B OK` → salt-okunur drift doğrulaması M1–M5 PASS → yönetici paneli + öğrenci akış turu).
**Onay gelmezse ilk güvenli işlem:** salt-okunur drift denetiminin taban ölçümüyle karşılaştırılması (`scripts/qa_sec_privilege_drift_audit.sql`) — hiçbir yazma içermez.

## 10. Açık riskler ve bekleyen kullanıcı onayları

**Onaylar:**
- ONAY-1: 155+156 canlı uygulama (kapalı olan SEC-1/SEC-1b açıkları CANLIDA AÇIKTIR; soru bankası dolana kadar SEC-1b pratik sömürülebilirlik düşüktür ama SEC-1 fonksiyonu bugün dahi çağrılabilir).
- ONAY-2: taslakların `supabase/migrations/`'e taşınması + yerel commit (push ayrıca izin).
- KARAR-2: Studio/ad-hoc drift üretim kanalının kapatılması politikası.
- KARAR-3: 157 şema geneli yeniden-sertleştirme dilimi.
- A1–A5: haftalık kasa geçiş ürün kararları.

**Riskler:**
- SEC-1/SEC-1b canlıda açık (bkz. ONAY-1).
- Şema geneli izin hijyeni bozuk (bkz. KARAR-3); TRUNCATE hakları RLS ile korunmaz.
- `waiting→active` yarışma başlatıcısı uygulamada yok (bilinen boşluk; QA'da fixture ile simüle edildi).
- Gölge rakip bonusu yalnız `time_band` doluyken hesaplanır (128 sözleşmesi; veri/karar gerektirir).
- Çalışma ağacında kullanıcının geniş modified/untracked birikimi duruyor — bu commit kapsamı DIŞIDIR, dokunulmadı.
