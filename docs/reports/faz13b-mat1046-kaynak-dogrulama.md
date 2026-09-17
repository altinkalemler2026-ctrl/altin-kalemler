# Faz 13B — MAT.10.4.6 Pilot Kaynak Sayfaları: Sınırlı Doğrulama

Tarih: 2026-09-16 · Kapsam: salt-okunur (DB yazma, soru üretimi, AI, fixture/vault, kod/UI, commit/push, hosted YOK)
Yöntem: pdfjs-dist legacy (Node 24) ile yalnızca belirlenmiş PDF + sayfa aralıkları okundu; başka dosya/disk taraması yapılmadı.
Geçici ayrıştırıcı `_tmp_extract13b.cjs` workspace'te oluşturulup doğrulama sonunda silindi.

## 1. Sayfa Numarası Uyumu (PDF indeksi ↔ basılı sayfa)

Üç PDF'te de **PDF indeksi = basılı sayfa + 2** olduğu, sayfa içi gömülü numaralarla birebir doğrulandı:

| Kaynak | Basılı → İndeks | Kanıt örnekleri |
|---|---|---|
| matematik.pdf | +2 | indeks 415 te basılı "413"; indeks 423 te "421"; indeks 555 te "553" |
| tyt-matematik.pdf | +2 | indeks 104 te "MATEMATİK - TYT 102"; indeks 108 te "… TYT 106" |
| matematik (2).pdf | +2 | indeks 37 de basılı "35 / 1. ADIM"; indeks 211 de "209" |

Sayfa eşlemesinde hata/çelişki bulunmadı; Faz 13A'nın esleme-raporu sayfaları (421–456 / 102–106 / 35–41) PDF gerçeğiyle örtüşüyor.

## 2. Kaynak Başına İçerik Doğrulaması

### 2.1 matematik.pdf — "İkinci Dereceden Bir Bilinmeyenli Denklemler" (basılı 421–456)

- **Bölüm/sayfa:** ÇÖZÜMLÜ SORULAR 421–438; TESTLER 439–456 (1. TEST… 4. TEST blokları).
  457'den itibaren "Çokgenler-Dörtgenler" bölümü başlıyor (sınır doğru).
- **İçerik varlığı:** anlatım + **çözümlü sorular** (421–438) + **testler** (439–456) + **cevap anahtarı**.
  Cevap anahtarı 553–558'de; **"İKİNCİ DERECEDEN BİR BİLİNMEYENLİ DENKLEMLER" tablosu basılı 557'de**
  (1.–4. TEST, alt bloklar dahil harf tablosu).
- **Kullanılabilecek soru türleri (kalıp):** ikinci derece denklem olmayı/olma şartını parametreyle denetleme,
  kök bulma ve çift kök (çözüm kümesi tek elemanlı), diskriminant, kökler toplamı/çarpımı (Vieta), kök
  simetrik ifadeler (kareler/küpler toplamı), kökleri verilenden denklem kurma, eşlenik kök (gerçel
  katsayılı denklemin katsayı bulma), **şekil/alan tabanlı problemler** (kare levha köşe kesme, dikdörtgen,
  üçgen) ve **sayı problemi** (arkaplan: satış fiyatı bağıntısı, konuşmalı soru).
- **Çözüm yaklaşımı türleri:** çarpanlara ayırma, diskriminant, kök-katsayı ilişkileri, mutlak değerli
  formsda alt konrol, grafik yardımıyla kök varlığı.
- **Kapsam dışı:** bu bölümde **eşitsizlik yok** (421–456 tamamında "eşitsizlik" sözcüğü geçmiyor; içerik
  denklem ağırlıklı). Geometri çizimi gerektiren sorular görsel bağımlı olduğundan özgün üretimde
  sekil-bağımsız metne çevrilmelidir.

### 2.2 tyt-matematik.pdf — "İkinci Dereceden" konu özeti (basılı 102–106)

- **Bölüm/sayfa:** 102 konu özeti "İkinci Dereceden Bir Bilinmeyenli Denklemler"; 103 çözüm kümesi
  (çarpanlara ayırma); 104 diskriminant kavramı/uygulaması; 105 karmaşık sayılarla Δ<0 çözümü;
  106 kök-katsayı ilişkisi + kökleri verilen denklemi kurma.
- **İçerik varlığı:** konu özeti (tanımlar, kritik bilgi kutuları, ispatlar) + **Örnek/Çözüm** blokları.
  Bu aralıkta test/küçük sınav ve cevap anahtarı yoktur (konu özeti kitabı).
- **Kullanılabilecek soru türleri (kalıp):** kavram güven («hangi denklem ikinci derecedendir»),
  parametreli katsayı denetimi, çarpanlara ayırma, diskriminant tabanlı kök sayısı, eşlenik karmaşık kök
  (Δ<0), kök-katsayı ilişkileri ve köklerinden denklem kurma.
- **Çözüm yaklaşımı türleri:** çarpanlara ayırma, diskriminant, Vieta, karmaşık eşlenik kök yaklaşımı.
- **Kapsam dışı:** bu sayfalarda eşitsizlik konusu yer almıyor; karmaşık sayı bölümü yalnızca Δ<0
  bağlamındaki kullanım kadar pilotsaja alınmalı (karmaşık sayı konusunun tamamı MAT.10.4.6 değil).

### 2.3 matematik (2).pdf — "İkinci Dereceden Denklemler, Eşitsizlikler ve Eşitsizlik Sistemleri" (basılı 35–41)

- **Bölüm/sayfa:** "- 1" bloku 35–40 (1./2./3. ADIM); "- 2" bloku 41'den itibaren başlıyor (sınır doğru).
- **İçerik varlığı:** test kitabı (AYT); bu aralıkta anlatım yok, **çok sayıda test sorusu** var; ayrıca
  blok bazlı `1. ADIM / 2. ADIM / 3. ADIM` düzeni ve **2018/2020/2021 AYT çıkmış soruları** başlıklı madde
  örnekleri mevcut. **Cevap anahtarı 209–212'de**: "İkinci Dereceden Denklemler, Eşitsizlikler ve
  Eşitsizlik Sistemleri - 1/-2" ADIM bazlı harf tabloları **basılı 209–210'da** doğrulandı.
- **Kullanılabilecek soru türleri (kalıp):** eşitsizlik çözüm kümeleri (aralık), eşitsizlik sistemleri,
  **grafik tabanlı** f·g < 0 / x·f ≤ 0 → çözüm kümesi, diskriminant, kök-katsayı, mutlak değerli eşitsizlik,
  üstel ifadenin ikinci dereceye indirgenmesi (4^x − 28·2^x + 27 biçimi), iki bilinmeyenli ikinci derece
  denklem sistemleri, Δ<0 eşlenik kök mantığı.
- **Çözüm yaklaşımı türleri:** aralık işaret tablosu, grafik okuma, çarpanlara ayırma, diskriminant,
  Vieta, değişken değiştirme.
- **Kapsam dışı:** bu kaynakta i kuvvetleri / eşlenik karmaşık sayı içeren maddeler ve üstel-eşitsizlik
  maddeleri ikinci derece probleminin ötesinde kalabilir; **çıkmış AYT soruları telif açısından kaynak
  kalitesi göstergesidir, doğrudan kopyalanamaz** (özgün üretim ilkesi korunur).

## 3. Kaynak Kararı

| Kaynak | Durum | Not |
|---|---|---|
| matematik.pdf (421–456, cevap 557) | ✅ **Kullanılabilir** | ana anlatım+çözümlü+test kaynağı; **yalnız denklem** kapsamı |
| tyt-matematik.pdf (102–106) | ✅ **Kullanılabilir** | kavram/çözüm kalıpları + çözümlü örnek; test yok |
| matematik (2).pdf (35–41, cevap 209–210) | ✅ **Kullanılabilir** | **eşitsizlik + sistem + grafik** kapsamını sağlayan tek kaynak; telif işaretli çıkmış sorular kopyalanmaz |

Sayfa eşlemesi hatalı veya belirsiz bir kaynak tespit edilmedi; **hiçbir kaynak pilot için kapatılmadı**.

Önemli kapsam notu: MAT.10.4.6'nın "denklem **ve eşitsizlik**" bileşeni üç kaynakta şöyle dağılıyor —
denklem: matematik.pdf + tyt-matematik; eşitsizlik & sistem & grafik çözümü: yalnız matematik (2).pdf.
Pilot soru seti denklem ve eşitsizlik dengesini korumak için matematik (2).pdf'e bel bağlamalı.

## 4. Sonraki Aşamaya Geçiş İçin Somut Veri Adımları

1. **Kaynak fişleme (üretim fazında):** `question_sources` (şu an 0 kayıt) içine 3 PDF kaydı +
   `question_source_locations` ile basılı sayfa aralıkları (matematik 421–438 / 439–456,
   tyt 102–106, mat(2) 35–40 / 41+). Faz 13B salt-okunurdu; bu adım izin ayrıca alınır.
2. **Kapsam füzelemesi:** MAT.10.4.6 pilotunda yalnız ikinci derece denklem + eşitsizlik + sistem +
   grafik çözümü; kapsam dışı alanlar (karmaşık sayı genel konusu, üstel eşitsizlik, çok fonksiyonlu
   grafik sistemleri, geometri-görsel bağımlı maddeler) için ayrı "hariç" listesi niyetlenir.
3. **Cevap şahidi:** üretilen sorular için matematik(2) 209–210 ve matematik.pdf 557 harf tablosu,
   çözüm-validasyon girdisi olarak yazılı çözümle çapraz kontrol kullanılır (kopyalama değil, denetim).
4. **Türkçe/psikometri kalıbı:** her soru için Faz 13A paketi (20 hedef/30 üst, zorunlu yazılı çözüm,
   8 kapılı denetim zinciri) korunur; soru tipi dağılımı §2'deki kalıplardan türetilir.
5. Bir sonraki fazda PDF erişimi için bu oturumdaki betik yolu (pdfjs-dist legacy, `file:///` import,
   offset +2) yeniden kullanılabilir; liste beklendik.

## 5. Sonuç

- Üç kaynak da doğrulandı; sayfa numarası uyumu ve ikinci dereceden içerik varlığı teyit edildi.
- Pilot için üç kaynak da **kullanılabilir**; belirsiz/hatalı eşleme yok.
- Rapor yazıldı; soru üretimi, DB yazımı, AI, fixture/vault, kod, commit/push **yapılmadı**.
  Faz 13B burada durur; bir sonraki faza "devam" onayı beklenir.

## 6. Kaynaklar

- `D:\evraklar\proje\Meb Sorular\9-12\matematik.pdf` (560 sf), `tyt-matematik.pdf` (160 sf),
  `matematik (2).pdf` (216 sf) — yalnız yukarıdaki aralıklar
- Faz 13A: `docs/reports/faz13a-ilk-soru-pilotu-uygunluk.md` (aday/paket/denetim kararları)
- Eşleme otoritesi: `docs/reports/2026-2027-matematik-pdf-esleme.md`
- Betik: geçici `_tmp_extract13b.cjs` (silindi) — çıktıların özeti §2'dedir; kaynak soru/çözüm metinleri
  bu rapora **kopyalanmadı**.