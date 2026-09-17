# Faz 13A — İlk Soru Üretim Pilotu: Kaynak ve Uygunluk Analizi

Tarih: 2026-09-16 · Kapsam: salt-okunur analiz (DB'ye yazma, PDF'e kayıt, AI soru üretimi, commit/push YOK)
Karar: **önerilen pilot konu seçilmiştir; bu rapordan sonra soru üretilmez** (ikinci onay beklenir).

## 1. Kapsam ve Kaynak Sınırı

Bu analizde yalnızca şunlar kullanıldı (kullanıcı talimatı):

- Altı matematik PDF'i — `D:\evraklar\proje\Meb Sorular\9-12\` (eşleme raporlarında doğrulanmış sayfa
  bilgileri esas alındı; bu oturumda PDF içerik erişimi açılmadığından soru üretimi öncesi
  **"kaynak gerekli"** notu düşüldü, bkz. §7).
- `docs/reports/2026-2027-matematik-pdf-esleme.md` (otoriter kaynak; "kullanıcı doğrulamalı İçindekiler")
- `docs/reports/pdf-matematik-konu-sayfa-haritasi.md` (ilk çıkarım; esleme raporuyla karşılaştırıldı)
- `docs/reports/pdf-matematik-pilot-analizi.md` (ürün türü/karar analizi)

DB salt-okunur doğrulamalar (lokal `supabase_db_yarisma-programi`): 90 kazanım, 26 topic,
28 schedule, 16 önkoşul, question_sources=0, ai_question_staging=0, AI denetim run'ları=0,
mentor/fixture durumu (§4).

> **Kaynak eşleme çelişkisi (açıkça ele alındı):** `konu-sayfa-haritasi.md` §4.1, matematik.pdf'in
> ilk yarısını bölüm başı farklı kümeleyerek sayıyor (ör. "Bölünebilme 53", "1. Derece 65").
> `2026-2027-matematik-pdf-esleme.md` ise Kümeleri iki bölüme ayırıp (25–36, 37–52) sonraki tüm
> bölümleri +16 sayfa kaydırmış listeliyor (ör. "Bölünebilme 65", "1. Derece 81"). Aralarında
> **matematik.pdf tarafında birebir sayfa kayması vardır ve esleme raporu otoriterdir** (başlığında
> "eski çıkarım KULLANILMADI" notu). Bu nedenle pilot sayfa planında **yalnız esleme raporunun
> sayfaları** esas alındı; harita raporu yalnız yapısal meta veri. Belirsiz hücreler (?)
> soru üretiminde kullanılmadı.

## 2. Aday Konular ve 7 Kriter Değerlendirmesi

DB'de 90 kazanımın tamamı yüklü; 10. sınıf konuları TYMM-2026 versiyonu (a1000000-…-0000c1),
12. sınıf OGM-2018. Öğrenci yalnız kendi sınıf içeriğini görür (ana sözleşme). Adaylar, eşleme
raporunun **Yüksek** güvenli ve **kaynak yoğunluğu en yüksek** satırlarından seçildi; belirsiz
eşleme aday kabul edilmedi (aşağıda açıkça işaretlendi).

### Aday A — MAT.10.4.6 İkinci dereceden denklem/eşitsizlik problemleri (10. sınıf)

1. **Resmî kazanım:** "Doğrusal, karesel, karekök, rasyonel referans fonksiyonlar ve bunlardan
   türetilen fonksiyonlarla ifade edilebilen denklem ve eşitsizlikler içeren problemleri çözebilme."
   grade_level=10, outcome_code=MAT.10.4.6, topic=MAT.10.4 (ayr0100000-…-0004).
2. **Kaynak PDF ve kesin sayfa:**
   - `matematik.pdf` — "İkinci Dereceden Bir Bilinmeyenli Denklemler" bölümü **421–456** (esleme §2 #22)
   - `tyt-matematik.pdf` — İkinci Dereceden Denklemler **102–106** (tamamı Yüksek)
   - `matematik (2).pdf` — İkinci Dereceden Denklemler/Eşitsizlikler testleri **35–41** (İçindekiler-doğrulamalı)
3. **Anlatım/örnek/cevap:** matematik.pdf'te konu anlatımı + **çözümlü örnek** var; cevap anahtarı
   harf tablosu (553–558). tyt-matematik özet (çözümlü örnek yok). mat(2) test; cevap 209–212.
4. **Pedagojik uygunluk:** yüksek. Sayısal deterministik cevaplar; özgün soru üretimi (kök bulma,
   diskriminant, kök–katsayı, eşitsizlik çözüm kümeleri, karesel grafik/parabol tabanlı, gerçek
   yaşam problemleri) için geniş ve sınırları net bir alan. 20–30 özgün madde rahatça üretilir.
5. **Önkoşul/schedule:** MAT.10.4 için önkoşul MAT.9.2 (doğrusal fonksiyon/1. derece) — DB'de
   `required` + `approved`. Schedule: MAT.10.4 hafta **15–28**. Hazır.
6. **Doğrulanabilirlik:** 10. sınıf soru kasası için **10. sınıf fixture öğrenci hesabı gerekli**
   (DB'de şu an yalnız 11×1, 12×3 öğrenci var) → §7'ye adım olarak eklendi. Alternatif: gerçek
   öğrenci yok; fixture hesap zorunlu.
7. **Telif/benzerlik & yanlış eşleme riski:** düşük-orta. Kaynaklar MEB eğitim materyali; kopyalama/
   doğrudan türetme yok ilkesi geçerli; sayısal değerlerle özgünleştirme kolay. Yanlış eşleme riski
   düşük (tek tema + net sayfalar). Karekök/rasyonel referans karşılığı kaynakta "İnceleme gerekli"
   olduğundan pilot soruları **2. derece denklem/eşitsizlik kısmıyla sınırlanır** (kapsam notu).

### Aday B — MAT.10.4.1 Fonksiyon kavramı ve gösterimi (10. sınıf)

1. **Kazanım:** "Gerçek sayılarda fonksiyon olma şartları ile gerçek sayılarda tanımlı
   fonksiyonların nitel özelliklerini matematiksel temsillerle değerlendirebilme." (MAT.10.4.1)
2. **Kaynak:** `matematik.pdf` — "Fonksiyon Kavramı ve Gösterimi" **343–362** (esleme §2 #18);
   `tyt-matematik.pdf` **81–92**; `matematik (2).pdf` **53–65** — tamamı Yüksek.
3. **Anlatım/örnek/cevap:** matematik.pdf çözümlü örnek + test; tyt özet; mat(2) test.
4. **Pedagojik uygunluk:** iyi. Tanım-değer kümesi, fonksiyon olma şartı, birebir/örten/ters,
   grafik okuma temaları faydalı; ancak soru kökleri daha kavramsal/sözel (özgünlük karşılaştırma
   riski orta). 20+ maddelik alan vardır.
5. **Önkoşul/schedule:** MAT.10.4 (aynı topic) altında; önkoşul ve schedule Aday A ile ortaktır.
6. **Doğrulanabilirlik:** Aday A ile aynı fixture gereksinimi.
7. **Telif/benzerlik & yanlış eşleme:** orta. Kavramsal kalıplar kaynaklar arasında yaygın olduğundan
   benzeyebilirlik yüksektir; cevap doğrulama sayısal kadar kesin değildir.

### Aday C — MAT.10.5.1 Sayma stratejileri (10. sınıf) — BELİRSİZ EŞLEME NEDENİYLE KABUL EDİLMEDİ

- Kazanım: "Sayma stratejileri kullanarak problem çözebilme." (MAT.10.5.1)
- Eşleme: tyt **69–77**, matematik.pdf **303–328** (esleme §2 #16), mat(2) **65**,
  mat(3) **113?–121?**. Grade düzeyi eşlemesi **Orta** kalır çünkü mat(3) hücresi `?`
  (görsel doğrulama gerekli) ve bölüm başı kaymasının etkisi açık değil.
- **Karar:** "Belirsiz kaynak eşlemesini aday kabul etme" kuralı gereği aday **kabul edilmez**;
  yalnız karşılaştırma için listelendi. (Görsel doğrulama ile tekrar değerlendirilebilir.)

### Karşılaştırma Tablosu

| Kriter (ağırlık) | A: MAT.10.4.6 | B: MAT.10.4.1 | C: MAT.10.5.1 |
|---|---|---|---|
| Kaynak güveni | Yüksek ×3 | Yüksek ×3 | Orta (mat3 ?) |
| Sayfa kesinliği | Yüksek (421–456,102–106,35–41) | Yüksek (343–362,81–92,53–65) | Orta |
| Çözümlü örnek | var | var | var |
| Özgün üretim alanı | geniş + deterministik cevap | orta (kavramsal) | geniş |
| Yanlış eşleme riski | düşük | düşük | orta |
| Önkoşul/schedule | hazır (15–28) | hazır (15–28) | hazır |
| Fixture doğrulama | gerekli (10. sınıf) | gerekli (10. sınıf) | gerekli |
| **Aday statüsü** | ✅ ÖNERİLEN | ☑️ alternatif | ❌ kabul edilmedi |

## 3. Önerilen Pilot Konu

**MAT.10.4.6 — "Doğrusal, karesel, karekök, rasyonel referans fonksiyonlar ve bunlardan türetilen
fonksiyonlarla ifade edilebilen denklem ve eşitsizlikler içeren problemleri çözebilme."
(10. sınıf, MAT.10.4)**

Gerekçe: iki Yüksek-güven kaynakla (matematik.pdf + tyt-matematik) artı test kitabıyla (mat(2))
üçlü doğrulanmış kaynak; çözümlü örnek varlığı; cevapları sayısal-deterministik olduğu için özgün
soru üretimi ve otomatik çapraz doğrulama için en uygun; önkoşul ve schedule onsuz hazır;
diğer Yüksek ikilinin (10.4.1) aksine kök kalıpları telif-benzerlik testinde en kolay farklılaşır.

**Kapsam daraltması:** 10.4.6 karekök/rasyonel referans bileşenleri mevcut kaynaklarda
"İnceleme gerekli" olduğundan pilot soruları **yalnız 2. dereceden denklem ve eşitsizlik** ile
sınırlanır (karesel üzerinden kurulan problemler dahil).

## 4. Önerilen Pilot Paketi

- **Hedef:** 20 soru · **Kesin üst sınır:** 30 soru.
- Her soru için **zorunlu alanlar** (hedef şema: `questions` + `question_curriculum_mappings` +
  `question_source_locations` altyapısı hazır, bu fazda yazılmaz):
  - `question_text` + `option_a..e` + `correct_answer` (A–E)
  - `difficulty` (easy/medium/hard) ve `estimated_solve_time_seconds`
  - `cognitive_type` (learning/comprehension/application)
  - **zaman içerilen zorunlu yazılı çözüm** — adım adım, `solution-validator` kuralına uygun
    (hedef: `question_solution_assets`)
  - kaynak fişi: `source=<dosya>; page=<basılı>; test=<blok>; no=<sıra>`
    (`ai_question_staging.source_*` alanlarına yazılacak)
- **Konu dağılımı (hedef, üst sınırda esnek):** kök çözümü ~8 · diskriminant/kök–katsayı ~6 ·
  eşitsizlik çözüm kümeleri ~6 · karesel grafik/parabol tabanlı problemler ~5 · gerçek yaşam
  (sayı/alan) problemi ~5.

### Denetim Kapıları (her soru için zorunlu, bu fazda yalnız tanım)

| Kapı | DB karşılığı | Not |
|---|---|---|
| Müfredat uyumu | `ai_curriculum_fit_runs` + `start_curriculum_fit_verification` | kazanım eşlemesi MAT.10.4.6 |
| Özgünlük/telif | `ai_originality_verification_runs` + `start_originality_verification` | kaynak IFADESINDEN doğrudan türetme yok |
| Kalite | `ai_question_quality_runs` + `start_question_quality_review` | madde kalitesi |
| Çözüm süresi | `ai_solve_time_verification_runs` + `start_solve_time_verification` | tahmini süre kalibrasyonu |
| Cevap doğrulama | `ai_answer_verification_runs` + `start_answer_verification` | sayısal/doğru çözüm çapraz kontrolü |
| Hazır olma | `evaluate_ai_question_readiness` + `ai_question_readiness_runs` | aktive edilebilirlik |
| Final inceleme | `ai_question_final_reviews` | promotion öncesi son kapı |
| Cevap anahtarı şahidi | matematik.pdf 553–558 · mat(2) 209–212 | harf çapraz doğrulaması (denetim şahidi, üretim girdisi değil) |

Tüm start_*/review_*/get_* rapor RPC'leri **DB'de mevcut** (sorguda doğrulandı);
run sayıları şu an 0 — ilk kez gerçek sorularla tetiklenecek (kalibrasyon adımı, §7).

## 5. Kaynak Sayfa Planı (yalnız esleme raporu sayfaları)

| Aşama | Kaynak | Sayfa aralığı |
|---|---|---|
| Konu anlatımı + çözümlü örnek | `matematik.pdf` "İkinci Dereceden Bir Bilinmeyenli Denklemler" | 421–456 |
| Konu özeti | `tyt-matematik.pdf` "İkinci Dereceden Denklemler" | 102–106 |
| Test kaynağı | `matematik (2).pdf` | 35–41 |
| Cevap anahtarı (şahit) | `matematik.pdf` | 553–558 |
| Cevap anahtarı (şahit) | `matematik (2).pdf` | 209–212 |

Not: `matematik (3).pdf` 2. derece hücresi `?` olduğundan pilot kaynak planına **alınmadı**.

## 6. Pilot Doğrulama Yolu

1. Üretilen 20–30 soru → `ai_question_staging` (staging_source='manual_candidate')
2. Denetim kapıları (yukarıdaki sırayla) → yeşil olanlar `approved`
3. Promotion → `questions` (approval_status='approved') + mapping + source_locations
4. **Fixture 10. sınıf öğrenci hesabıyla** çözüm denemesi (DB'de şu anda 10. sınıf öğrenci yok)
5. `question_solve_time_profiles` / istatistiklerle kalibrasyon; gerçek öğrenci yoktur.

## 7. Soru Üretiminden Önce Eksik Kalan Teknik/Veri Adımları

1. **KAYNAK GEREKLİ — PDF içerik erişimi:** `D:\evraklar\proje\Meb Sorular\9-12\` altına
   matematik.pdf 421–456 arası + tyt-matematik 102–106 + mat(2) 35–41 sayfalarının görsel/üç
   katmanlı okunması gerekiyor. Bu oturumda açık erişim verilmedi; eşleme raporu sayfa bilgileri
   bağımsız ve kullanıcı doğrulamalıdır ama **soru üretimi öncesi sayfa içeriği doğrulanmalıdır**.
2. **Kaynak envanteri DB'ye:** `question_sources` **0 kayıt**; 6 PDF'in kayıtları eklenmelidir
   (source_type='pdf', file_name, ownership/license — yazma fazında).
3. **Sayfa doğrulama/işaret çözümü:** mat(3) `?` hücreleri kapsam dışı bırakıldı; matematik.pdf
   bölüm 421–456 fiili içeriği (başlık/metin) teyit edilmeli (harita–esleme kayma farkı kapandı).
4. **10. sınıf fixture öğrenci hesabı:** mevcut 4 öğrencide 10. sınıf yok (11×1, 12×3). Pilot
   doğrulaması için grade_level=10 fixture hesap gerekli (yalnız lokal, kullanıcı onayıyla).
5. **10. sınıf soru kasası (vault):** DB'deki 38 vault'un tamamı 12. sınıf E2E/Faz15A fixture'ı;
   TR-G10-MATH benzeri aktif kasa tanımı gerekecek (kod/UI bu fazın dışında).
6. **AI denetim zinciri ilk çalıştırması:** start_* RPC'ler var ama hiç çalışmamış. İlk üretilen
   sorularla zinciri ilk kez çalıştırıp rapor kalibrasyonu yapılmalı (beklenen kanıt: çıktı şablonları).
7. **Cevap shestipleri:** harf tabloları yalnız denetim şahidi; üretim girdisi olarak kullanılmaz
   (telif dışlama ilkesi).

## 8. Sonuç ve Karar

- Tek önerilen pilot konu: **MAT.10.4.6** (10. sınıf, 2. dereceden denklem/eşitsizlik problemleri).
- Alternatif: MAT.10.4.1 (fonksiyon kavramı). Kabul edilmez aday: MAT.10.5.1 (belirsiz eşleme `?`).
- Paket: **hedef 20, kesin üst sınır 30**; her soru için zorunlu yazılı çözüm + 8 denetim kapısı.
- Bu fazda hiçbir şey DB'ye yazılmadı, PDF'e kayıt eklenmedi, soru üretilmedi, commit/push yok.
- **Pilot konu seçilmiştir; soru üretimi ayrı onay bekler.**

## 9. Kaynaklar

- `docs/reports/2026-2027-matematik-pdf-esleme.md` (otoriter — sayfa kaynağı)
- `docs/reports/pdf-matematik-konu-sayfa-haritasi.md` (ilk çıkarım — yapısal karşılaştırma)
- `docs/reports/pdf-matematik-pilot-analizi.md` (ürün türü/telif ilkesi)
- `D:\evraklar\proje\Meb Sorular\9-12\` (6 PDF — erişim §7.1)
- DB (salt-okunur): outcomes/schedule/prerequisites/topics/sources/staging/AI RPC'leri/vaults/students