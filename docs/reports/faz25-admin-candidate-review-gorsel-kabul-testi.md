# Faz 25 — Admin Candidate-Review Görsel Kabul Testi

**Tarih:** 2026-09-25
**Kapsam:** Yerel admin candidate batch liste ve detay ekranlarının yetkili `question_reviewer` oturumuyla masaüstü `1440×900` ve mobil `375×812` viewport'larında görsel kabulü.
**Test hedefi:** `9310097d-168c-498e-b8cc-4531d46c0825`
**Test ortamı:** `http://localhost:3000`
**Karar:** `VISUAL_ACCEPTANCE: PASS`

## 1. Sonuç özeti

| Kontrol | Sonuç |
|---|---|
| Anonim admin erişimi | PASS — temizlenmiş anonim browser oturumu `/admin/candidate-batches` isteğinde `/login` adresine yönlendi |
| Masaüstü liste | PASS — hedef batch görünür; `32/32/32` ve `32/32 Doğrulandı` |
| Masaüstü detay | PASS — 32 aday, fizik verisi, seçenekler, çözüm ve pasif kararlar görünür |
| Mobil liste | PASS — hedef batch görünür; yatay taşma veya kırpılma yok |
| Mobil detay içeriği | PASS — 32 aday, alanlar, seçenekler, çözüm ve disabled karar düğmeleri görünür |
| Mobil detay yerleşimi | PASS — başlık ve batch key görünür alan içinde sarılıyor; kırpılma yok |
| Publish/live aksiyonu | PASS — görünür publish/live kontrolü yok |
| Veri/karar mutasyonu | PASS — test sırasında karar düğmesi kullanılmadı; post-test DB sayıları değişmedi |
| Konsol hatası | PASS — 0 hata |
| Sunucu | PASS — Next sunucusu çalışır bırakıldı |

**Düzeltme sonucu:** Mobil detay başlık bloğunda `min-w-0`, mobil tam genişlik ve uzun batch key için güvenli satır kırma eklendi. Masaüstü başlık/link yerleşimi korunuyor.

## 2. Anonim erişim kontrolü

Browser context'indeki önceki oturum temizlendikten sonra anonim olarak şu istek yapıldı:

```text
GET http://localhost:3000/admin/candidate-batches
→ http://localhost:3000/login
```

Admin içeriği anonim kullanıcıya açılmadı. Bu kontrol için ikinci bir anonim deneme yapılmadı.

## 3. Masaüstü görsel kontrolleri

### Liste

`1440×900` viewport'unda:

- `Aday Soru Paketleri` başlığı ve iki paket görünür.
- Hedef batch `notebook:md:886bdde8c5a93aae5d3bf8b5bf11c59908c97d587a813014aa646c520dd33332` görünür.
- Hedef batch sayaçları: toplam `32`, geçerli `32`, yerleştirilen `32`.
- Doğrulama özeti: `32/32 Doğrulandı`.
- `İncele` bağlantısı mevcut ve hedef detay rotasına gidiyor.
- Publish/live kontrolü görünmüyor.
- `documentElement.scrollWidth = clientWidth = 1440`; viewport dışına taşan element yok.

### Detay

`1440×900` viewport'unda:

- Batch durumu `İçe Aktarıldı`; kaynak `curriculum_original`; üretici `notebook`.
- Sayaçlar `32 / 32 / 0 / 32`; toplam, geçerli, geçersiz ve yerleştirilen madde bilgileri görünür.
- Preflight bölümünde `İnceleme gerekiyor: Evet`, `Yayın izni: Hayır`, `Aktif: Hayır` görünür.
- `Adaylar (32)` başlığı altında 32 aday bölümü render edildi.
- İlk adayda `Ders: Fizik`, `Sınıf: 9. Sınıf`, `Kazanım: FIZ.9.1.2` görünür.
- İlk adayda A–E şıkları, önerilen doğru cevap, çözüm yöntemi, adımlar, sonuç, gerekçe ve yaygın hatalar görünür.
- 32 aday için 32 `Doğrulama Sonuçları` bölümü görünür.
- Her aday için `İncelemeyi Onayla`, `Düzeltmeye Gönder` ve `Reddet` düğmeleri bulundu; toplam 32'şer düğmenin tamamı disabled.
- Publish/live düğmesi veya bağlantısı bulunmadı.
- `documentElement.scrollWidth = clientWidth = 1425`; viewport dışına taşan element yok.

## 4. Mobil görsel kontrolleri

### Liste

`375×812` viewport'unda:

- İki paket görünür.
- Hedef batch ilk sırada ve `32 / 32 / 32`, `32/32 Doğrulandı` değerleri görünür.
- Kartlar ve `İncele` bağlantısı görünür alan içinde kalıyor.
- `documentElement.scrollWidth = clientWidth = 360` (dikey scrollbar nedeniyle client width 360); viewport dışına taşan element yok.
- Yatay overflow veya görünür kırpılma yok.

### Detay

`375×812` viewport'unda içerik ve güvenlik kontrolleri:

- `Adaylar (32)` başlığı ve 32 aday bölümü görünür.
- İlk adayda `Ders: Fizik`, `Sınıf: 9. Sınıf`, `Kazanım: FIZ.9.1.2`, A–E şıkları ve çözüm görünür.
- 32 `Doğrulama Sonuçları` bölümü görünür.
- Üç karar düğmesinin 32'şer adedinin tamamı disabled.
- Publish/live kontrolü yok.
- Aday içeriğinin geri kalanında yatay taşma görülmedi.

- Üst başlık bloğunda `min-w-0`, mobil tam genişlik davranışı ve uzun batch key için `break-all` uygulandı.
- H1 ve batch key wrapper'ı `left=40.8`, `right=319.2`, `width=278.4`; görünür içerik alanı dışına taşmıyor.
- H1 ve batch key için `scrollWidth=clientWidth=278`; header flex için de `scrollWidth=clientWidth=278`.
- İşlem durumu linki mobilde başlık altında kalıyor; `left=40.8`, `right=223.9`, viewport dışına taşan element yok.
- `documentElement.scrollWidth = clientWidth = 360` (dikey scrollbar nedeniyle client width 360); yatay overflow veya görünür kırpılma yok.

## 5. Değişiklik ve temizlik doğrulaması

Görsel testten sonra salt-okunur DB kontrolü:

```text
candidate_question_batches|2
candidate_batch_candidate_results|33
ai_question_staging|33
target_batch_results|32
admin_user_roles|1
```

- Testte hiçbir approve/reject/decision düğmesine tıklanmadı.
- Publish, live veya intake işlemi yapılmadı.
- Yalnız `src/app/(admin)/admin/candidate-batches/[id]/page.tsx:634-645` içindeki mobil header sınıfları güncellendi; migration, candidate verisi veya karar durumu değiştirilmedi.
- İlgili Vitest kontrolleri 2 dosyada 24 test ile geçti.
- `npx tsc --noEmit` geçti.
- Değişen dosyaya yönelik `npx --no-install eslint "src/app/(admin)/admin/candidate-batches/[id]/page.tsx"` geçti.
- Genel `npm run lint`, kapsam dışı mevcut `pdfprobe.js` ve `pdftext.js` dosyalarındaki 4 ESLint hatası nedeniyle başarısız oldu; bu dosyalara dokunulmadı.
- Üç geçici screenshot alındı ve test sonunda silindi.
- Next sunucusu kapatılmadı; `localhost:3000` üzerinde Node process'i çalışır durumda bırakıldı.
- Fixture hesabı, parola, token veya key rapora yazılmadı.

## 6. Nihai karar

**`VISUAL_ACCEPTANCE: PASS`**

Anonim erişim engeli, masaüstü detay/liste, mobil liste ve düzeltilen mobil detay yerleşimi başarıyla doğrulandı. Mobil başlık ve batch key artık görünür alan içinde sarılıyor; publish/live veya veri/karar mutasyonu yapılmadı. Genel lint sonucundaki kapsam dışı mevcut dosya hataları bu görsel kabul kararını değiştirmez ve ayrı teknik borç olarak bırakılmıştır.
