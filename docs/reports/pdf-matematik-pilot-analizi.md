# PDF Matematik Pilot Analizi — MEB 9-12 Matematik Kaynak Envanteri

Tarih: 2026-09-15 · Kapsam: yalnız salt-okunur analiz (commit/push yok, DB/uygulama dokunulmadı)
Kaynak: `D:\evraklar\proje\Meb Sorular\9-12\` — 6 ana matematik PDF'i

## 1. Özet

1. Altı matematik PDF'inin **tür ve kapsam sınıflandırması tamamlandı** (Bölüm 3).
2. `matematik.pdf` kararı: bu **ders kitabı DEĞİL**, TYT kapsamında (9.+10. sınıf konularının
   tamamı) **Konu Anlatımı + Her Konuya 4 Test + Çözümlü Örnek + Cevap Anahtarı** içeren MEB
   yardımcı kaynağıdır (Bölüm 4).
3. Dört kitabın da **son bölümleri denetlendi**: 4'ü cevap anahtarı tablolarıyla bitiyor;
   `matematik (3).pdf` ayrıca **Çıkmış TYT Soruları (2018/2020/2021)** bölümü içeriyor;
   `matematik (1).pdf` Görsel Kaynakça (EBA) ile bitiyor (Bölüm 5).
4. **Branş (salt matematik) denemesi PDF'i saptanmadı.** `tyt-1/tyt-2/ayt-say/ayt-ea/ayt-soz`
   karma tam-sınav deneme setleri gibi duruyor (görsel tabanlı; metin çıkarılamadı) (Bölüm 6).
5. Raporda TYT/AYT bir **sınıf etiketi olarak sayılmaz**; 9–12 eşlemesi, resmî MEB müfredat
   tablosuna bağlanacağı sonraki görevde netleştirilecektir. Aşağıdaki tablolar yalnızca yapısal
   (konu başlığı + sayfa aralığı) meta veridir.

## 2. Yöntem, Araç ve Okunabilirlik Sınırı

- Çıkarma: proje dışı geçici dizinde çalışan, kendi yazdığımız salt-okunur Node ayrıştırıcısı
  (`%TEMP%\opencode\pdftxt2.cjs`). Sisteme pdftotext/python/pdf kütüphanesi kurulmadı, PDF
  kopyalanmadı/dönüştürülmedi; metin yalnız konsola basıldı.
- Okunabilirlik: MEB yayınlarında fontlar **tek baytlık özel eşleme (şifreli ToUnicode)**
  kullanıyor ve eşleme kitaptan kitaba değişiyor. Sonuç: metin %70-95 okunabilir; **rakamlar,
  sayfa numaraları, seçenek harfleri (A/B/C/D/E), yapı ve tablolar güvenilir**; bazı başlıklarda
  tek tek harfler bozuk (ör. `matematik.pdf`'te hayalet 'K' karakteri).
- Güven seviyeleri:
  - **Yüksek**: dosya → ürün türü/kapsam, bölümlerin basılı sayfa aralıkları, cevap anahtarı
    varlığı/yeri, çıkmış soru bölümü varlığı, hangi sınav kapsamına (TYT/AYT) hizmet ettiği.
  - **Orta**: tek tek konu başlıklarının harf düzeyi yazımı (aile/künye adı).
  - **Düşük**: kitapların kapaklarında görünen video/QR ibarelerinin teknik içeriği.
- Sayfa numaraları raporda **basılı (kitap içi) sayfa** olarak verilir; ayrıştırıcı indeksi
  basılı sayfa + 1'dir (ör. basılı 553 = indeks 554).

## 3. Dosya Envanteri (9-12, matematik)

| Dosya | MB | Sayfa (PDF) | ISBN / Künye | Tür ve Kanıt |
|---|---|---|---|---|
| `tyt-matematik.pdf` | 31,8 | 160 | 978-975-11-8473-3 | **MEB TYT Konu Özetleri** (örnek kitap). İçindekiler 78 başlık: Sayı Kümeleri 9, Temel İşlemler 10, … Polinom 93–96 (s.9→~100). |
| `ayt-matematik.pdf` | 30,3 | 140 | 978-975-11-8472-6 | **MEB AYT Konu Özetleri**. İçindekiler AYT sıralı: Bir Fonksiyonun Grafiği ile İlgili Uygulamalar 9, Ortalama Değişim Hızı 13, Üstel–Logaritmik Fonksiyon Problemleri 61, Diziler 62–65 (s.9→~70+). |
| `matematik.pdf` | 33,8 | 560 | 978-975-11-7257-0 | **TYT Konu Anlatımı + Testler (yardımcı kaynak, ders kitabı değil)**. İçindekiler 9.–10. sınıf konuları s.9–477; cevap anahtarı tabloları s.552–558. |
| `matematik (1).pdf` | 40,5 | 531 | 978-975-11-7259-4 | **MEB AYT "Dört Dörtlük Konu Pekiştirme Testleri"** (test kitabı). İçindekiler: Yönlü Açılar 9, Trigonometrik Fonksiyonlar 23, Doğrunun Analitik İncelenmesi 67, … ; cevap anahtarı 523–528; Görsel Kaynakça 529. |
| `matematik (2).pdf` | 19,5 | 216 | 978-975-11-6000-3 | **MEB AYT test kitabı** (tam ürün adı garble nedeniyle netleşmedi). Cevap anahtarı bölüm başlıkları AYT: Fonksiyonlar ve Uygulamalar, 2. Dereceden Denklemler, Trigonometrik Fonksiyonlar ve Grafikleri, Trigonometrik Denklemler, Limit–Türev–İntegral, Diziler, Olasılık, Katı Cisimler, Dörtgenler. Son sayfalar boş. |
| `matematik (3).pdf` | 17,9 | 222 | 978-975-11-5999-1 (MEB 2023) | **MEB TYT Yardımcı Kaynak/Eğitim Materyali test kitabı** + Çıkmış Sorular. Cevap anahtarı başlıkları TYT: Mantık, Kümeler, Sayı Kümeleri, Bölünebilme, Denklemler, Üslü-Köklü, Üçgen, Fonksiyon, Analitik Geometri; **Çıkmış 2018/2020/2021 TYT s.213–214**; cevap anahtarı 215–218. |

Ön bölümlerin tümünde MEB kalıbı var (kapak → telif → İstiklal Marşı → Gençliğe Hitabe →
Atatürk → İçindekiler), yani 6 dosya da MEB/Eğitim Materyali kimliğinde.

## 4. `matematik.pdf` Tür Kararı

Sorulan "ders kitabı mı, konu anlatımı mı, soru pekiştirme mi?" sorusunun cevabı:

- **Ders kitabı değil / yardımcı kaynak**: kapakta "Her Konuya 4 Test / 100 Soru ve Çıkmış
  Seçmeli Sorular" kalıbı; içerikte çözümlü örnek kutuları + test blokları; sonda ünite bazlı
  cevap anahtarı tabloları (basılı 552–558). Ders kitaplarında bu yapı bulunmaz.
- **Kapsam TYT = 9.+10. sınıf konularının tamamı**: İçindekiler sırası: Önermeler ve Bileşik
  Önermeler 9 → Kümeler 25 → Sayı Kümeleri 37 → Bölünebilme Kuralları 53 → Birinci Dereceden
  Denklem(Eşitsizlik)ler 65 → Üslü Sayılar ve Denklemler 81 → Denklemler ve Eşitsizlikler 109 →
  Üçgende Temel Kavramlar 125 → Üçgende Eşlik ve Benzerlik 167 → Üçgende Yardımcı Elemanlar 181 →
  Dik Üçgen ve Trigonometri 211 → Üçgenin Alanı 233 → (Trigonometrik) Açı/Ölçü 253 →
  Trigonometrik Fonksiyonların Periyodik Grafikleri 273 → Sıralama ve Seçme 287 → Basit Olayların
  Olasılıkları 303 → Fonksiyon Kavramı ve Gösterimi 329 → İki Fonksiyonun Bileşkesi ve Ters
  Fonksiyon 343 → Polinom Kavramı ve İşlemleri 363 → Polinomlarda Çarpanlara Ayırma 389 →
  İkinci Dereceden Bir Bilinmeyenli Denklemler 403 → Çokgenler ve Dörtgenler 421 → Özel Dörtgenler
  457 → Katı Cisimler 477.
- Sayfa aralıkları ardışık bölüm başlangıçlarından türetilmiştir (örn. Kümeler 25–36). Tek tek
  başlık harflerinde zayıf kalan yerler "≈" ile işaretlendi; ünite grupları güvenilir.

## 5. Son Bölüm Denetimi (cevap anahtarı / çözüm / video / deneme)

| Dosya | İçerik sonu | Cevap anahtarı | Ek çözüm/video | Deneme bölümü |
|---|---|---|---|---|
| `matematik.pdf` | s.~551 | s.552–558 (üniteli, A/B/C/D harf tabloları, açıklamasız) | Çözümlü örnekler iç sayfalarda; kapakta "Video" ibaresi (QR/görsel — metinle doğrulanmadı) | yok |
| `matematik (1).pdf` | s.522 | s.523–528 | Görsel Kaynakça s.529 (EBA linki); "Video" ibaresi kapakta – doğrulanmadı | yok |
| `matematik (2).pdf` | s.208 | s.209–212 | — (yalnız harf cevap) | yok |
| `matematik (3).pdf` | s.213–214 kısmen Çıkmış | s.215–218 | Çıkmış 2018/2020/2021 TYT s.213–214; soru bazlı açıklamasız | yok |

Cevap anahtarlarında **açıklama/çözüm metni yok** (yalnız harf). Çözüm kaynağı olarak yalnızca
`matematik.pdf` ve `matematik (1).pdf`'te "çözümlü örnek/video" ibareleri var; bunlar yazılı
değil görsel (QR) olabilir.

## 6. Branş Denemesi Durumu

- Klasörde adında `deneme` geçen dosya yok.
- `tyt-1.pdf`, `tyt-2.pdf`, `ayt-say.pdf`, `ayt-ea.pdf`, `ayt-soz.pdf` içerik taraması: sayfalar
  görsel tabanlı, **okunabilir metin çıkarılamadı** (kapak/optik dosya). Konum/ad büyüklüğü
  itibarıyla karma tam-sınav (TYT 3'lü, AYT sayısal/eşit ağırlık/sözel) deneme setleri
oldukları tahmin ediliyor; **matematik branş denemesi saptanmadı**.
- Sonuç: "Mantık/kümeler… branş denemesi PDF'i ile başlayalım" kurgusu için gerekli branş
  denemesi envanterde bulunmuyor; tek konu pilotu bu raporun Bölüm 9'undaki kaynak eşlemesiyle
  (konu anlatım + konu testi + özet) yürütülebilir.

## 7. Mevcut Uygulama Yapılarıyla Karşılaştırma

| İhtiyaç | Uygulamada karşılığı | Bu envanterden gelen durum |
|---|---|---|
| **Kasa (soru bankası)** | `src/lib/admin/question-bank.ts` (listSubjects/listQuestions/parseGrade, konu-kazanım süzme) | Soru kaynakları: 4 test kitabı (ünite test tabloları + cevap anahtarı). **DB şemasında kaynak/sayfa alanları mevcuttur**: `ai_question_staging` tablosunda `source_id` (→`question_sources`), `source_page_number`, `source_test_number`, `source_test_code`, `source_question_number` sütunları; finalized sorularda `question_source_locations` tablosunda `page_number`, `test_number`, `question_number` alanları bulunur. Kaynak fişleme için altyapı hazır. |
| **Müfredat (konu → sınıf)** | Öğrenci `grade_level`; `parseGrade`/subjects; içerik sınıf bazlı (ana sözleşme) | TYT/AYT **sınıf etiketi sayılmaz**; 9–12 kesin eşleme resmî MEB ünite/kazanım tablosuna bağlanacak. `matematik.pdf` İçindekiler'inin öğretim sırası (s.9→477) bu bağlamada kullanılabilir sıra şablonudur. |
| **Önkoşul / sıralama** | Faz 15A training gating: `get_training_session_state` `'konu_islenmedi'` kilidi + konu sıralı soru seçimi | 9./10. sınıf sırası (Mantık→Kümeler→…→Katı Cisimler) önkoşul zincirine birebir oturuyor; test kitapları bu sırayla test sunuyor. |
| **Denetim (QA/dogrulama)** | `docs/reports/latest-*-validation*.md` kalıbı, migration + canlı yerel doğrulama | PDF → soru üretimi için **doğruluk/çözüm etiketi denetimi** akışı henüz yok; cevap anahtarı (harf tablosu) OCR/çıkarım sonrası otomatik çapraz doğrulama için uygun. |
| **Çözüm** | `src/lib/content/solution-validator.ts` (yalnız yazılı çözüm doğrulama) | Kaynaklarda açıklamasız cevap anahtarı + çözümlü örnek kutuları var. **Video çözüm altyapısı yok**; "Video" ibareleri QR/görsel olduğundan tüketilemiyor — üretim pilotunda yazılı çözüm süreci en uygun. |

## 8. Konu → Kaynak Eşleme Tablosu (üretim için kullanılabilir harita)

Sütunlar: Konu/alt konu · Konu anlatımı (ana kaynak, öğretim sırasıyla) · Soru/test kaynağı ve
sayfa aralığı · Çözüm/video durumu.

### TYT bloğu (9.–10. sınıf konuları)

| Konu | Konu anlatımı / özet | Soru / test kaynağı | Çözüm / video |
|---|---|---|---|
| Önermeler ve Bileşik Önermeler | `matematik.pdf` 9–24 | `matematik.pdf` (4'er test), `matematik (3).pdf` (mantık testleri; konu sayfa haritası İçindekiler'den çıkarılacak) | matematik.pdf çözümlü örnek; cevap anahtarı harf; video doğrulanmadı |
| Kümeler | `matematik.pdf` 25–36 | `matematik.pdf` testler, `matematik (3).pdf` | aynı |
| Sayı Kümeleri / Temel İşlemler | `matematik.pdf` 37–52; `tyt-matematik.pdf` 9–37 | `matematik (3).pdf` (sayı kümeleri/bölünebilme testleri) | aynı |
| Bölünebilme Kuralları | `matematik.pdf` 53–64; `tyt-matematik.pdf` 18–20 | `matematik (3).pdf` | aynı |
| Birinci Dereceden Denklem(ler)/Eşitsizlikler | `matematik.pdf` 65–80; `tyt-matematik.pdf` 38–... | `matematik (3).pdf` | aynı |
| Üslü / Karekök Sayılar | `matematik.pdf` 81–108 | `matematik (3).pdf` | aynı |
| Denklemler ve Eşitsizlikler (2. derece dahil) | `matematik.pdf` 109–124 | `matematik (3).pdf` | aynı |
| Üçgen (temel kavram, eşlik-benzerlik, yardımcı elemanlar, dik üçgen, alan) | `matematik.pdf` 125–233 (~233) | `matematik (3).pdf` (üçgen/benzerlik testleri) | aynı |
| Trigonometri (açı/ölçü + periyodik fonksiyon grafikleri, 10. sınıf giriş) | `matematik.pdf` 253–273 | `matematik.pdf` testler | aynı |
| Sıralama ve Seçme (Permütasyon–Kombinasyon) | `matematik.pdf` 287–302 | `matematik.pdf` testler, `matematik (3).pdf` | aynı |
| Basit Olayların Olasılıkları | `matematik.pdf` 303–328 | `matematik.pdf` testler | aynı |
| Fonksiyonlar (kavram, bileşke, ters, grafik) | `matematik.pdf` 329–343; `tyt-matematik.pdf` 68–73 (86–92) | `matematik.pdf` testler | aynı |
| Polinomlar | `matematik.pdf` 363–389 | `matematik.pdf` testler | aynı |
| İkinci Dereceden Denklemler | `matematik.pdf` 403–420 | `matematik.pdf` testler | aynı |
| Çokgenler ve Dörtgenler / Özel Dörtgenler | `matematik.pdf` 421–457 | `matematik.pdf` testler | aynı |
| Katı Cisimler | `matematik.pdf` 477–~500 | `matematik.pdf` testler | aynı |

### AYT bloğu (11.–12. sınıf konuları)

| Konu | Konu anlatımı / özet | Soru / test kaynağı | Çözüm / video |
|---|---|---|---|
| Yönlü Açılar | `ayt-matematik.pdf` (trigonometri maddeleri, İçindekiler s.9+) | `matematik (1).pdf` 9–22; `matematik (2).pdf` (trigonometri testleri, cevap s.209+) | mat(1) çözüm/video ibareli; doğrulanmadı |
| Trigonometrik Fonksiyonlar | aynı | `matematik (1).pdf` 23–66; `matematik (2).pdf` | aynı |
| Fonksiyonlarda Uygulamalar (grafik, artan/azalan, ortalama değişim hızı) | `ayt-matematik.pdf` 9–13 | `matematik (1).pdf` (İçindekiler); `matematik (2).pdf` | aynı |
| Üstel–Logaritmik Fonksiyonlar ve Denklemler | `ayt-matematik.pdf` (s.61 bölgesi) | `matematik (1).pdf`; `matematik (2).pdf` | aynı |
| Diziler | `ayt-matematik.pdf` 62–65+ | `matematik (1).pdf`; `matematik (2).pdf` | aynı |
| Limit, Türev, İntegral | `ayt-matematik.pdf` (İçindekiler) | `matematik (2).pdf` (limit–türev–integral testleri) | aynı |
| Doğrunun Analitik İncelenmesi / Çember | `ayt-matematik.pdf` | `matematik (1).pdf` 67–... | aynı |

Not: `tyt-matematik.pdf` ve `ayt-matematik.pdf` özet kitaplarının **konu bazlı dahili sayfa
haritası** İçindekiler sayfalarından çıkarılabilir durumda (78 ve ~43 madde); bu raporda yalnızca
okunan örnek sayfalar verildi. Test kitaplarının (1),(2),(3) cevap anahtarı başlıkları, konu →
test bloğu ayrımını İçindekiler üzerinden bağlamak için yeterli.

## 9. 11. Sınıf Tek Konu Üretim Pilotu Önerisi

Önerilen konu: **Trigonometri — "Yönlü Açılar" + "Trigonometrik Fonksiyonlar"** (11. sınıf 1. ünite).

Gerekçe: hem özet (`ayt-matematik.pdf` trigonometri maddeleri), hem konu testi (`matematik
(1).pdf` 9–66), hem pekiştirme testi (`matematik (2).pdf` trigonometrik fonksiyonlar/denklemler)
kaynakları **erken bölümlerde ve sayfa aralıkları kesin**; 9. sınıf önkoşulu (dik üçgen
trigonometrisi) `matematik.pdf` 211–233'te mevcut. Önerilen akış:

1. Konu anlatımını `matematik (1).pdf` 9–66 çıkarımıyla çözümlü örnek + kazanım eşlemesi.
2. Soru setini `matematik (1).pdf` + `matematik (2).pdf` test bloklarından seç; cevap
   anahtarı (hangi testin hangi sorusu) otomatik çapraz kontrol yapılsın.
3. Yazılı çözümleri üretim hattında `solution-validator` ile doğrula (video çözüm altyapısı yok).
4. TYT/AYT etiketi kullanma; sınıf eşlemesi için resmî MEB ünite/kazanım tablosuna bağla.

## 10. Telif Dışlama Yaklaşımı (üretim öncesi zorunlu)

Bu rapor yalnızca yapısal meta veri (ürün adı/ISBN/künye, konu başlıkları, sayfa aralıkları)
içerir; kaynak metinlerden hiçbir soru/alıntı kopyalanmamıştır. Üretim aşamasında:

- Kaynaklar ister MEB telif bildirimiyle ("ücretsiz eğitim materyali") dağıtılsın, telif dışlama
  testi olmadan ham soru senkronize edilmesin; önce türetilmiş/sentezlenmiş soru kuralı.
- Sayfa görselleri yayında kullanılmayacak; yalnızca yeniden yazılmış metin + yeniden çizilmiş
  şema.
- Soru/kazanım/sayfa izleme: her soruya `source=<dosya>; sayfa=<basılı>; test=<blok>; no=<sıra>`
  fişi; cevap anahtarındaki harf ile otomatik doğrulama (üretim girdisi değil, denetim şahidi).

## 11. Varsayımlar, Sınırlar ve Sonraki Adımlar

- Varsayımlar: (a) font eşleşmesinden kaynaklanan harf bozuklukları yapısal kararları
  etkilemez; (b) cevap anahtarındaki harfler (A/B/C/D/E) görüntü benzerliği yönünden sağlam;
  (c) "Video" ibareleri görsel/QR olup bu analizde tüketilmedi.
- Sınırlar: görsel tabanlı dosyalarda (`tyt-1/tyt-2/ayt-say-ea-soz`) metinle doğrulama
  yapılamadı; `matematik (2).pdf`'in tam ürün adı garble nedeniyle teyit edilemedi; özet
  kitaplarının konu bazlı 78/43 maddelik dahili sayfa haritası tam çıkarılmadı.
- Sonraki adımlar (onay isteği gerektirir): (1) İçindekiler haritalarının tam çıkarımı;
  (2) 11. sınıf trigonometri pilotu için ünite → kazanım eşleme (resmî MEB tablosu);
  (3) soru üretim hattı tasarımı (kaynak fişleme + cevap çapraz doğrulama + solution-validator
  entegrasyonu). Bu rapor sonrası işleme geçilmez: kullanıcı onayı beklenir.