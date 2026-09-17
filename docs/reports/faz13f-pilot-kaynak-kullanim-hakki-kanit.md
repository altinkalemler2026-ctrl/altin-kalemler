# Faz 13F — Pilot PDF kaynaklarının kullanım hakkı kanıt incelemesi

Sürüm: 1.0
Tarih: 16 Eylül 2026
Faz: 13F (salt-okunur kanıt incelemesi; kod/DB/UI değişikliği içermez)
Kapsam: MAT.10.4.6 pilotunda kullanılması önerilen yalnız üç PDF

Bu rapor, üç PDF dosyasının hangi düzeyde kullanılabileceğini kanıta dayalı
olarak belirler. İncelenen dosyaların **içindeki soru metinleri okunmamış ve
AI üretim girdisi olarak kullanılmamıştır**. Toplanan kanıt türleri:
(i) dosya künyesi / XMP öz verisi, (ii) resmî MEB/OGM sayfa ve PDF künye
metinleri, (iii) 5846 sayılı Fikir ve Sanat Eserleri Kanunu (FSEK) ve
Türk hukukunda AI eğitimi/türetmeye ilişkin mevcut yorumlar.

---

## 1. İncelenen kaynaklar

| # | Dosya | Boyut | Sayfa | XMP başlığı | XMP yaratıcı | Son değişiklik |
|---|---|---|---|---|---|---|
| A | `matematik.pdf` | 35.480.489 B | 560 | `kapak` | yok (araç: InDesign 20.1 / Illustrator 27.6) | 2023-07-07 |
| B | `tyt-matematik.pdf` | 33.313.356 B | 160 | `MEBI KONU OZETI-TYT-KAPAK` | yok | 2025-01-10 |
| C | `matematik (2).pdf` | 20.464.449 B | 216 | `kalıp` (mojibake `kalÄ±p`) | **C.Volkan YILDIZ** | 2022-03-11 |

Dizin yolu: `D:\evraklar\proje\Meb Sorular\9-12\`. Dosya C’nin XMP
manifestinde kişisel masaüstü yolları bulundu:
`C:\Users\Ozkan KAYA\Desktop\3 adım kapaklar güncel\yeni kod.png`,
`D:\özkan çalışmalar\apple.png`, `D:\özkan çalışmalar\play.png`
(mojibake çözümü yapılarak okundu). Bu, dosya C’nin bireysel bir
tasarımcı/kapak üreticisinin çalışma dosyası olma olasılığını gösterir.

---

## 2. Her kaynak için kanıt değerlendirmesi

### 2.1 Yayıncı / sahip bilgisi

- **A (matematik.pdf):** Künye öz verisi MEB’i doğrudan göstermiyor; başlık
  `kapak` ve InDesign/Illustrator araçları OGM Materyal üretim zinciriyle
  uyumlu. Kaynak (kullanıcının `Meb Sorular\9-12\` arşivi) ve adlandırma,
  bu dosyanın MEB/OGM “3 Adım Soru Bankası” türü bir yayından geldiğini
  gösterir; **kesin sahip MEB olarak kanıtlanamadı**, çünkü dosyanın resmî
  kaynağı (indirildiği URL / basılı künye sayfası) belgelenmeden yalnız
  adlandırmaya dayanır.
- **B (tyt-matematik.pdf):** XMP başlığı `MEBI KONU OZETI-TYT-KAPAK`.
  “MEBİ” MEB’in resmî içerik/konu özeti mecrası adıyla uyumludur. Bu da
  resmî MEB kökenli bir kapak dosyası izlenimi verir; yine de resmî kaynak
  URL’si/künyesi belgelenmeden **kesinlik verilmedi**.
- **C (matematik (2).pdf):** XMP `dc:creator` alanında **gerçek kişi
  (C.Volkan YILDIZ)** yazıyor ve manifest kişisel bilgisayar yolları içeriyor.
  Bu, dosyanın resmî bir MEB yayını değil, bir **tasarım/kapak kalıp
  çalışması** olma olasılığının yüksek olduğunu gösterir. Sahiplik kanıtı
  bireysel; MEB sahipliği **kanıtlanamadı**.

### 2.2 PDF içindeki telif / kullanım notu

- Dosyaların metin katmanı CID/font kodlu olduğundan iç sayfalardaki telif
  dizgisi (varsa) düz metin olarak çıkarılamadı; yalnız davranışsal akış
  komutları (operatör `Tj`/`TJ` grafik komutları) görülebildi. Dolayısıyla
  **“PDF içinde telif notu var” ifadesi için doğrudan kanıt elde edilemedi**.
- Buna karşılık, OGM Materyal tarafından yayımlanan diğer PDF’lerde ve resmî
  sitelerde şu künye/uyarı metni yerleşiktir (aşağıda §3, resmî kanıt):
  - “5846 Sayılı Fikir ve Sanat Eserlerini Koruma Kanunu gereği tüm hakları
    **Milli Eğitim Bakanlığına aittir.** MEB’in izni olmadan bu evraktaki
    bilgiler kopyalanamaz, başka yere taşınamaz, internet üzerinde veya her
    ne şekilde olursa olsun ticari amaçla yayınlanamaz ve kullanılamaz.”
- Bu künye, üç dosyanın resmî MEB yayını olduğu doğrulanmadan onlara birebir
  atfedilemez; ancak dosyalar MEB arşivinden alındıysa geçerli kullanım
  çerçevesini bu metin tanımlar.

### 2.3 Resmî sayfadaki kullanım / lisans açıklaması

OGM Materyal’in “3 Adım Soru Bankası” ve genel soru bankası sayfalarında ve
yayımlanan PDF künyelerinde (iki bağımsız resmî kaynak, ulaşılan metinler):

1. ogmmateryal.eba.gov.tr “3 Adım Soru Bankası” sayfası:
   > “Bu sayfada bulunan kitapların **tüm yayın hakları Milli Eğitim
   > Bakanlığı’na aittir.** Hiçbir şekilde **ticari amaçla kullanılamaz veya
   > kullandırılamaz.** Bu sayfada yer alan kitapların veya kitaplardaki
   > içeriğin ticari amaçla kullanılması, 5846 sayılı Fikir ve Sanat
   > Eserleri Yasası’nın 36. maddesine aykırıdır ve açıkça suçtur. Aykırı
   > davrananlar hakkında, hukuki ve cezai her türlü başvuru hakkı saklıdır.”
2. OGM Materyal tarafından yayımlanan bir örnek PDF’deki (PISA “Problem Çözme”)
   künye metni, §2.2’deki “tüm hakları MEB’e aittir; MEB’in izni olmadan
   kopyalanamaz/taşınamaz/ticari amaçla yayınlanamaz” hükmünü birebir içerir.

Bu iki metin, MEB/OGM’nin kendi yayınları için lisans tutumunu gösteren
resmî kanıttır. Pilotun üç dosyasının bu kapsamda olduğu garantisi
olmamakla birlikte, MEB arşivi kökenliyse bu lisans bu dosyalara da uygulanır.

---

## 3. Kullanım türlerinin durumu (benimsenen varsayım ve kanıt derecesi)

Aşağıdaki tabloda her kullanım için karar gösterilir. Karar, kanıtların
bütününe ve “kanıt yoksa kesin hüküm verme” kuralına göre **İzinli /
Belirsiz (inceleme gerekli) / Kapalı** olarak işaretlenmiştir. Varsayım:
dosyalar MEB/OGM kökenli kamusal eğitim materyalidir; kesin sahiplik ispatı
(basılı/web künye ekran görüntüsü) ayrı bir fazda tamamlanmalıdır.

| Kullanım | A (matematik.pdf) | B (tyt-matematik.pdf) | C (matematik (2).pdf) | Kanıt özeti |
|---|---|---|---|---|
| Yalnız künye olarak saklama (dosya adı, başlık, yaratıcı, tarih) | İzinli | İzinli | İzinli | Bibliyografik öz veri FSEK m.22 çoğaltma/yaymaya girmez; künyenin kendisi telif ihlali değildir |
| Konu/kapsam referansı alma (sınıf, ders, konu başlığı haritası) | İzinli | İzinli | İzinli | Fikirler/kazanım adları telif dışıdır (FSEK m.1); soru metni kopyalanmadığı sürece |
| Kısa insan denetimli alıntı | Belirsiz → MEB izni gerekir | Belirsiz → MEB izni gerekir | Belirsiz → yazar izni gerekir | FSEK m.34 seçme/toplama eğitim istisnası sınırlıdır; ticari üründe alıntı FSEK m.35 + eser sahibi izni tartışması açar |
| PDF içeriğini AI üretim girdisi yapmak | **Kapalı** | **Kapalı** | **Kapalı** | Türk hukukunda TDM/AI-eğitim istisnası yoktur; kopyalama-toplu işleme FSEK m.21/m.22 ihlali riski; MEB künyesi açıkça kopyalama/taşımayı izne bağlar |
| Kaynak sorudan türetilmiş soru üretmek | **Kapalı** (MEB izinsiz) | **Kapalı** (MEB izinsiz) | **Kapalı** (yazar izinsiz) | Türetme FSEK m.6 “işlenme” ve m.21 işleme hakkına girer; pilotta kaynak soru metni girdi olarak kullanılamaz |
| Ticari üründe kullanım | **Kapalı** | **Kapalı** | **Kapalı** | Resmî OGM metni: “Hiçbir şekilde ticari amaçla kullanılamaz… açıkça suç” (5846/m.36); dosya C’de de bireysel sahip ticari lisansı yok |

Görüldüğü gibi: **yalnız künye ve konu/kapsam referansı izinlidir**;
AI girdisi, türetme ve ticari kullanım **kapalıdır**; kısa alıntı
“belirsiz/inceleme gerekli” kalır ve MEB (veya dosya C için ilgili kişi)
izni olmadan ticari üründe kullanılmamalıdır.

---

## 4. Pilot MAT.10.4.6 için önerilen kullanım modeli

Pilot, kanıt düzeyimizin izin verdiği en güvenli modelle ilerlemelidir:

1. **Kaynak fişleme (künye düzeyi):** PDF adı, dosya boyutu, XMP öz verisi
   (başlık/yaratıcı/tarih), dizin yolu ve “MEB/OGM olduğu iddialı, resmî
   kaynak URL’si ile doğrulanacak” notu bir **kaynak kaydı** olarak saklanır.
   Soru metni fişe kopyalanmaz.
2. **Kapsam/kazanım hangi PDF’de görünüyor (işaretleme düzeyi):** yalnız
   “konu/kapsam bu PDF’de mevcut” bilgisi; **soru metni veya doğru cevap
   kayda alınmaz**. Soru cümlesi pilotun DB’sine hiç girmez.
3. **Soru üretimi tamamen ayrık:** soru üretimi, PDF metninden değil, resmî
   müfredat kazanımları listesinden çekirdek alınarak ve özgün kök
   metinler yazılarak yapılır (§5, güvenli alternatif).

Bu model, Faz 13C/13E’de planlanan kaynak fişleme şemasını, PDF içeriğini
AI/DB girdisine çevirmeden korur.

---

## 5. Güvenli alternatif (önerilen üretim yolu)

PDF soru metni hiç kullanılmadan:

- Resmî müfredat kazanımları (TTKB/MEB onaylı 2026–2027 matematik ders
  programı) üretim çekirdeği olur.
- Her kazanım için **özgün** soru kökü ve seçenekler Türkçe, pedagojik
  kurallara göre yazılır; sayısal değerler ve bağlamlar yeniden tasarlanır.
- Kaynak PDF’lerden **alıntı, benzer cümle, şekil, sayısal düzen
  kopyalanmaz**.
- Çıktı, ana sözleşmedeki içerik zincirine (AI destekli taslak → otomatik
  kontroller → alan uzmanı denetimi → onay → yayın) girer.

Bu yol, FSEK m.21/22 riskini ortadan kaldırır; MEB künyesinin “ticari amaçla
kullanılamaz” şartına da doğrudan konu olmayacak biçimde, yalnız resmî
kazanım listesinden (müfredata bağlı, özgün) üretim yapar.

---

## 6. Kanıt defteri (elde edilen kanıtlar)

| Kanıt | Tür | Değer |
|---|---|---|
| Dosya varlığı + boyut + sayfa sayısı + dizin yolu | Dosya künyesi | A: 35,48 MB / 560 s.; B: 33,31 MB / 160 s.; C: 20,46 MB / 216 s. |
| XMP öz verisi (başlık/yaratıcı/araç/tarih) | Dosya öz verisi | A: `kapak`, 2023-07-07; B: `MEBI KONU OZETI-TYT-KAPAK`, 2025-01-10; C: `kalıp`, `C.Volkan YILDIZ`, 2022-03-11 |
| OGM “3 Adım Soru Bankası” sayfası telif metni | Resmî web | “tüm yayın hakları MEB’e aittir; ticari amaçla kullanılamaz; 5846/m.36 suç” |
| OGM örnek PDF künye notu | Resmî PDF | “tüm hakları Milli Eğitim Bakanlığına aittir; MEB’in izni olmadan kopyalanamaz, taşınamaz, ticari amaçla yayınlanamaz” |
| FSEK m.34 metni (eğitim-öğretim için seçme/toplama) | Mevzuat | Eğitim kapsamı sınırlı; ticari/dışı kullanım eser sahibi iznine bağlı; AI eğitimini kapsamaz |
| FSEK m.21/22 (işleme/çoğaltma) üzerine AI eğitimi yorumları | Doktrin | Türk hukukunda AI/TDM istisnası yok; izinsiz kullanım m.21/m.22 ihlali; FSEK m.25 umuma iletim bakımından ayrıca değerlendirilir |

**Doğrulanamayan / unknown kalanlar:**

- Her üç dosyanın iç sayfa telif dizgisi (teknik olarak CID kodlu;
  okunamadı) — resmî MEB yayını olduğu künyeden (basılı/web) doğrulanıncaya
  kadar kesin atıf yapılmadı.
- Dosya A ve B için üretim organı (OGM Materyal mi, MEBİ mi) — arşiv
  kökenine göre varsayım, kesin ispat ayrı fazda.
- Dosya C için hak sahibi (MEB mi, V. YILDIZ mı) — bireysel XMP yaratıcısı
  nedeniyle MEB sahipliği kanıtlanmadı; fişlemeye “sahip doğrulanacak” etiketi
  girer.

---

## 7. Sonuç

- Sözleşmenin (dosya içeriği AI girdisi yapılamaz; resmî URL/izin belgeli
  kaynak gerekliliği) gereği, **üç PDF de yalnız künye ve konu/kapsam
  referansı için kullanılabilir.**
- **PDF içeriğinin AI üretim girdisi yapılması, kaynak soru metninden
  türetilmiş soru üretilmesi ve ticari üründe kullanımı kapalıdır.**
- Pilot, §4 modeliyle (künye + kapsam işareti, soru metni DB’de hiç
  barındırılmadan) ve §5 güvenli alternatifiyle (yalnız resmî müfredat
  kazanımından özgün üretim) devam etmelidir.
- Faz sonucu: **Kanıt incelemesi tamamlandı — PARTIAL (sahip doğrulaması
  ayrı fazda)**; kod/DB/UI/commit/push yapılmadı.

---

## 8. Konum ve durum

- Bu rapor: `docs/reports/faz13f-pilot-kaynak-kullanim-hakki-kanit.md`
- İncelenen dosyalar değiştirilmedi; çalışma ağacındaki kullanıcı
  modified/untracked dosyalara dokunulmadı.
- Commit ve push **yapılmadı**.
- Sonraki adım önerisi (uygulanmaz): resmî MEB/OGM kaynak URL’lerinden üç
  dosyanın kökeninin ve künyesinin ekran görüntüsüyle doğrulanması.