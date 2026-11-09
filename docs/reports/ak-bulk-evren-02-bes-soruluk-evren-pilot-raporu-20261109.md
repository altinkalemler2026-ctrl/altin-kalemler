# AK-BULK-EVREN-02 — 5 Soruluk Gerçek Toplu Denetim Pilot Raporu

**Tarih:** 8–9 Kas 2026 · **Mod:** Kontrollü canlı pilot · **Yetki:** tek koşu, ≤5 EVREN çağrısı

## 1) Ön kontrol — TÜMÜ PASS
History=154; eski 219 görev `skipped/run_cancelled`; pilot öncesi pending/running=0; completed=20; #69 `skipped/attempt=2`; Fizik NB-FIZ-P01-001 quality `verified/approve`; beyaz liste `opencode-go/glm-5.3-flash, evren/qwen3.8-flash-next`; aktif/kiralı görev yok.

## 2) Pilot koşusu ve çağrı sayısı
- **Koşu UUID:** `ede47948-7974-4415-b12a-8a93c1698965` (scope=selection, gates=quality, model=EVREN, `created_task_count=5`, hatalar boş).
- **Seçilen 5 aday (staging UUID → soru kodu, hepsi Matematik 9. sınıf, `validating`, kapı `waiting_reviewer_1`):**
  `cf5a7940…`→M9-ILK-005 · `4437f68d…`→M9-ILK-006 · `ef50d4e2…`→M9-ILK-007 · `6acc3b24…`→M9-ILK-008 · `0b35ced5…`→M9-ILK-009. **#69 hariç** (plan `q69_var=0`).
- Selection plan önizlemesi: görev=5, çağrı=5, atlanan=0 ✔
- **Gerçek model çağrısı: 5** (worker logu 5× "tamamlandı"; görev başına tek çağrı; `--once` = tek claim, iç retry yok — kod kanıtı: `claim-loop.ts` + `run-bulk-gate-work.ts [4/5]`). Worker **bir kez** çalıştırıldı.
- İzolasyon kanıtı: koşu öncesi global pending+running=0 → claim havuzu = **yalnız bu 5 görev** (hedef dışı=0).

## 3) Görev sonuçları (önce/sonra)
| Durum | Pilot görevleri (reviewer_1) | Zincir (reviewer_2) |
|---|---|---|
| completed | **5/5** | 0 (çalıştırılmadı — söz konusu olduğu gibi) |
| pending | 0 | **5** (kapı sözleşmesinin `waiting_reviewer_2` görevleri; `stop=false`, resume edilebilir) |
| failed | 0 | 0 |

Global completed: 20 → **25** (+5 pilot). Global pending+running=5 (yalnız reviewer_2 zincir görevleri).

## 4) Aday bazlı kalite sonuçları (reviewer_1, EVREN, `wp09-gate-review-p1`)
| Soru | overall | confidence | risk bayrakları |
|---|---|---|---|
| M9-ILK-005 | 0.95 | 0.95 | hepsi false |
| M9-ILK-006 | 0.92 | 0.90 | hepsi false |
| M9-ILK-007 | 0.83 | 0.85 | hepsi false |
| M9-ILK-008 | 0.92 | 0.90 | hepsi false |
| M9-ILK-009 | 0.95 | 0.95 | hepsi false |

Kapı durumları `waiting_reviewer_2`; `human_review_required=false`; consensus ikinci reviewer sonrası oluşacak (tasarım).

## 5) JSON parse / provenance
- 5/5 yanıt mevcut `parseQualityReply` sözleşmesinden geçti (`invalid_reply` YOK); DB kayıtları yalnız gerçek yanıttan.
- 5/5 kanıt dosyası: prompt SHA-256 + CLI session id + run/task eşleşmesi (`/tmp/opencode/ak-evren02/*-kanit.json`); istem dosyaları 0600.
- İhlal/koruma: eski 219 `run_cancelled` yerinde; completed 20 korundu; **#69 `skipped/attempt=2` değişmedi** (deneme kullanılmadı); 112 aday / 0 yayınlanmış soru / 36 kasa / 0 üyelik sabit.

## 6) Maliyet / token
- Token ölçümü **KISMEN DOĞRULANABİLDİ**: CLI kanalı yalnız 2/5 çağrıda token raporladı (g1: 10463 g / 208 ç; g8: 2804 g / 199 ç; diğerleri 0/0). Sağlayıcı raporlamadığı için toplam ölçülemedi.
- Parasal maliyet: **DOĞRULANAMADI** (DB `cost_estimate_status='unavailable'`; sağlayıcı fiyatlandırması canlıdan doğrulanmadı) — kesin tutar beyan edilmiyor.

## KARAR: **PİLOT BAŞARILI**
Kanıt: 5/5 teknik tamamlanma, 0 `model_call_failed`/`invalid_reply`, provenance eksiksiz, ≤5 çağrı tavanı fiilen korundu (tam 5), hedef dışı tek bir işlem yok, #69 ve eski kayıtlar bit-bit korundu. EVREN-01 §4'teki dört başarı ölçütünün dördü de karşılandı (`technical_error` grubu oluşmadı).

## Sonraki adımlar — AYRI KULLANICI ONAYI GEREKİR
1. **reviewer_2 zinciri (5 görev, 5 çağrı):** bu pilotun doğal devamı; otomatik devam ettirilmedi — ayrı onay.
2. **Tam toplu denetim** (EVREN-01 §6 sırası: P2 95 → P1 kalan 214 → P3 3; #69 için attempt=2 taşıması başlatta doğrulanacak) — ayrı onay.
3. Panel G2 "İptal et" UI ve commit/push — ayrı iş/onay.

**GÜVENLİ DUR — pilot sonrası hiçbir görev başlatılmadı; 5 reviewer_2 görevi planlanıp BEKLETİLİYOR.**
