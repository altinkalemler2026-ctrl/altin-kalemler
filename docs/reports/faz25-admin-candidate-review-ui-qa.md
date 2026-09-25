# Faz 25 — Aday Soru Paketleri + Tek Aday İnceleme Detayı UI (Stitch Tasarımları Bağlama)

**Tarih:** 2026-09-24
**Kapsam:** Stitch onaylı iki tasarımın (Paketler Kuyruğu + Tek Aday İnceleme Detayı) mevcut admin candidate-batches ekranlarına **yalnız gerçek RPC verisiyle** bağlanması. Veri kıyası salt-okunurdur; bu fazda hiçbir karar DB'ye yazılmaz.
**Kanıt:** vitest 216/216 (sayfa testleri 34 + src/lib/admin 182), `tsc --noEmit` 0 hata, eslint 0 hata, ana DB baseline 2|8|33|1 değişmedi.

---

## 1. Sonuç Özeti

| Metrik | Değer |
|---|---|
| **Durum** | ✅ BAŞARILI (kısım tamamlandı) |
| Migration | YOK (bu fazda DDL/DML yok) |
| DB yazma işlemi | YOK (yalnız salt-okunur SELECT kanıt) |
| Ana DB sayıları | batches=2, questions=8, ai_question_staging=33, review_queue=1 — **değişmedi** |
| Değiştirilen dosyalar | 5 (yalnız admin candidate-batches + mesajlar) |
| vitest | ✅ list 14 + detay 10 + islem-durumu 10 + lib/admin 182 → **216/216 PASS** |
| tsc --noEmit | ✅ 0 hata |
| eslint | ✅ 0 hata (değişiklik kapsamı) |
| Yeni migration / DB yazımı | Hayır |
| UI kararları | Fizik/Sınıf/Kazanım **yalnız detayda**, liste düzeyinde ders/sınıf kolonu **yok** (liste RPC sözleşmesinin bilinçli sınırı) |
| Karar düğmeleri | Görünür ama **pasif** (işlem akışı sonraki fazda bağlanır) |
| Git | Commit YAPILMADI (onay bekleniyor) |

---

## 2. Kullanıcı Kararı (uygulandı)

"1'i uygula" kararı şu dört kurala dönüştürüldü ve uygulandı:

1. **Liste düzeyinde Ders/Sınıf kolonu YOK.** Liste RPC'si (`list_candidate_question_batches`, migration 120) ders/sınıf/meta alanı döndürmediği için bu sürümde liste tablosunda Ders ve Sınıf gösterilmez. Bu, **liste RPC sözleşmesinin bilinçli sınırıdır** (aşağıda madde 4).
2. **Satır başına detay fetch YOK (N+1 yasak).** Liste yalnız tek bir `listCandidateQuestionBatches(page)` çağrısı yapar; satır başına `getCandidateBatchDetail` çağrısı yoktur.
3. **Teknik etiket YOK.** "Listeleme desteği yok", "filtreleme yok" gibi kullanıcıyı ilgilendirmeyen teknik ibareler kullanıcıya gösterilmez. Desteklenmeyen filtreler (ders/sınıf/durum/tarih/search) hiç render edilmez; desteklenen sayfalama ve refresh gösterilir.
4. **Detayda gerçek aday verisi**: Paket detayına girildiğinde her adayın künye şeridinde gerçek verilerden `subject_name = Fizik`, sınıf seviyesi ve outcome kodu (örn. `FIZ.11.1.10`) gösterilir (kaynak: `ai_question_staging.metadata` + staging join, detay RPC).

---

## 3. Yapılan Değişiklikler

### 3.1 `src/lib/admin/admin-panel-messages.ts`
- Liste mesaj blokuna **gerçek DB status sözlüğü → Türkçe etiket eşlemesi** eklendi: `received→Alındı`, `validating→Doğrulanıyor`, `validated→Doğrulandı`, `partially_valid→Kısmen Doğrulandı`, `rejected→Reddedildi`, `ingested→İçe Aktarıldı`, `failed→Başarısız`. Bilinmeyen değerde ham değer gösterilir; ham status sayfada `title` özniteliğinde korunur (denetim izi, sahte değil).
- Kokpit metinleri: `sourceChip` ("İçerik & Soru Havuzu"), `modeChip` ("Salt İnceleme"), başlık "Aday Soru Paketleri", gerçek görüntülenme sayacı şablonu, güvenlik protokolü kutusu.
- Detay mesaj blokuna: aday künye şeridi etiketleri (Ders/Sınıf/Kazanım/Zorluk/Önerilen Süre/Bilişsel Düzey), pasif karar paneli metinleri (İncelemeyi Onayla / Düzeltmeye Gönder / Reddet + "işlem akışı bir sonraki fazda bağlanacak"), **İki Aşamalı Yayın İlkesi** güvenlik kutusu.
- `lowConfidence` kalıpları standarta çekildi: `true → "Öncelikli İnsan İncelemesi"`, `null → "Bu eski batch için öncelik kaydı yok."`.

### 3.2 `src/app/(admin)/admin/candidate-batches/page.tsx` (liste)
- Editorial Command kokpit görünümü: üst başlık şeridi (İçerik & Soru Havuzu + Salt İnceleme rozetleri), başlık + canlı paket sayısı rozeti.
- **Metrik kartları yalnız gerçek RPC verisi**: "Toplam Paket" (`result.total`, global) ve "Bu Sayfada Görüntülenen" (`items.length`, sayfa ölçekli). Stitch mokabındaki sahte metrikler (14/418/5/28 vs.) ve sahte audit log **üretilmedi**.
- Satır: paket anahtarı + şema sürümü + origin/producer model + oluşturulma tarihi + gerçek durum rozeti (etiket + ham `title`) + `preflight.review_required=true` olduğunda "İnceleme Gerekli" rozeti + gerçek sayaç hapı (Toplam/Geçerli/Yerleştirilen) + doğrulama oranı rozeti (yalnız gerçek valid/total) + "İncele →" bağlantısı.
- Filtre çubuğu **yok** (backend desteklemiyor; sahte buton üretilmedi). Sayfalama (gerçek toplam) + "Yenile" bağlantısı + salt-inceleme güvenlik kutusu.
- Ders/Sınıf kolonu yok; satır başına N+1 fetch yok.

### 3.3 `src/app/(admin)/admin/candidate-batches/[id]/page.tsx` (detay)
- Her aday başlığı altına **gerçek aday künye şeridi**: Ders (subjectName), Sınıf ("N. Sınıf") ve Kazanım (outcomeCode) öne çıkan rozetler; mevcutsa Zorluk / Bilişsel Düzey / Önerilen Süre.
- `lowConfidence` eşlemesi doğru: `true` → öncelikli inceleme rozeti; `null` → "Bu eski batch için öncelik kaydı yok."
- Aday karar paneli **pasif**: İncelemeyi Onayla / Düzeltmeye Gönder / Reddet `disabled` düğmeler + "İşlem akışı bir sonraki fazda bağlanacak; bu sürümde karar düğmeleri pasiftir ve hiçbir veri yazılmaz."
- Sayfa sonunda **İki Aşamalı Yayın İlkesi** bilgi kutusu: bu ekrandaki hiçbir karar öğrenciye doğrudan yayın sağlamaz; onaylanan sorular bağımsız yayın inceleme kapılarından geçmelidir.
- Batch durumu artık Türkçe etiketle gösteriliyor (liste ile aynı eşleme); detay mevcut çözüm nesnesi render'ı korundu (`solution` jsonb object → adım/ sonuç/ gerekçe/ yaygın hata).

### 3.4 Testler
- `page.test.tsx` (liste): yeni başlık/metin (Aday Soru Paketleri) + durum etiketi ("Alındı") doğrulamaları güncellendi; boş/hata ayırımı, DTO allowlist, bozuk tarih, sayfalama (ilk sayfada `aria-disabled`), no-mutation korundu.
- `[id]/page.test.tsx` (detay): durum etiketi, "Öncelikli İnsan İncelemesi", karar paneli düğmeleri ve "İki Aşamalı Yayın İlkesi" doğrulamaları eklendi; allowlist/no-mutation korundu. Test gevşetme yok.

---

## 4. Liste RPC Sözleşmesinin Bilinçli Sınırı

`list_candidate_question_batches` (migration 120) aşağıdaki alanları döndürür; **daha fazlasını döndürmez**:

`schema_version, origin, producer_id, producer_model, status, counts(summary), validation_summary, created_at, updated_at`

- **Ders, sınıf, outcome, metadata döndürmez.** Bu alanlar yalnız detay RPC'sinde (staging join üzerinden) vardır.
- Bu fazda yalnızca eksik görünüm tamamlanmıştır; liste RPC'si **bilinçli olarak dar tutulmuştur** (performans + allowlist güvenliği). Ders/Sınıfın liste düzeyinde gösterilmesi, RPC sözleşmesinin genişletilmesini ve yeni bir migration'ı gerektirir — bu fazın kapsamı dışındadır.
- Bu nedenle: liste sayfasında Ders/Sınıf **gösterilmez**; bilgi detay sayfasında gerçek aday verisinden (`subject_name=Fizik`, sınıf, outcome kodu) sunulur.

---

## 5. Doğrulama Kanıtları

### 5.1 Ana DB baseline (salt-okunur)
```
candidate_question_batches=2 | questions=8 | ai_question_staging=33 | review_queue=1
```
Değişmedi (önceki faz sonrası aynı).

### 5.2 Gerçek batch satırları (status vocab + eşleme kaynağı)
| id | batch_key (44) | origin | producer | status | total | valid | schema |
|---|---|---|---|---|---|---|---|
| `7ea1ff55-…` | `opencode-big-pickle:783ff9…` | curriculum_original | big-pickle | ingested | 1 | 1 | 1.0 |
| `9310097d-…` | `notebook:md:886b…` | curriculum_original | notebook | ingested | 32 | 32 | 1.0 |

Gerçek UI davranışı: her iki durum "İçe Aktarıldı" etiketiyle, ham `ingested` `title`'da gösterilir.

### 5.3 Testler
- liste `page.test.tsx`: 14 PASS (auth gating, sayfalama, allowlist, no-mutation)
- detay `[id]/page.test.tsx`: 10 PASS (render + karar/şerit doğrulamaları)
- `islem-durumu/page.test.tsx`: 10 PASS (değişmedi)
- `src/lib/admin` birim testleri: 182 PASS
- `tsc --noEmit`: 0 hata; eslint (kapsam): 0 hata

---

## 6. Sınırlar / Sonraki Faz (Faz 26+) İçin Not

- **Karar düğmeleri pasiftir**: Onayla/Düzeltmeye Gönder/Reddet sürümde veri yazmaz; işlem akışı (DB yazımı, review kararı kaydı, iki-aşamalı yayın) **Faz 26 kapsamıdır** ve ayrı onay + migration + QA gerektirir (`SAFE_FOR_REVIEW_ACTIONS: NO`).
- Liste RPC'sinde ders/sınıf istenirse: migration ile RPC genişletmesi gerekir (bu fazda yapılmadı).
- Fizik batch `preflight.review_required=true` ve `publication_allowed=false` gerçek değerlerdir; bu fazda gösterildi, değiştirilmedi.
- Tasarım tokenları (indigo/amber/slate) standart Tailwind sınıflarıyla uygulandı; proje token sistemine (`globals.css` @theme / `tokens.ts`) dokunulmadı — tasarıma global token eklenmek istenirse ayrı bir stil fazı gerekir.

---

## Karar

Tüm maddeler yeşil: yalnız gerçek RPC verisi gösterildi, sahte metrik/karar/etiket üretilmedi, Ders/Sınıf liste düzeyinde bilinçli olarak dışarıda bırakıldı, detayda gerçek Fizik/sınıf/outcome sunuldu, N+1 yok, DB salt-okunur kaldı, testler/type/lint yeşil, git temiz (commit yapılmadı).

**SAFE_FOR_ADMIN_READONLY_REVIEW: YES**
**SAFE_FOR_REVIEW_ACTIONS: NO** (karar/yayın yazımı Faz 26+ için ayrı onay gerektirir)