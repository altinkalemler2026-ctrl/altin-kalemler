# 2026–2027 Matematik Yıllık Konu Açılma Planı (Önerilen Takvim)

Tarih: 2026-09-15 · Kapsam: **yalnız planlama + rapor** — kod/DB/migration/soru/commit/push YOK
Kaynaklar: `docs/reports/2026-2027-matematik-resmi-mufredat.md`,
`docs/reports/2026-2027-matematik-pdf-esleme.md`, `docs/references/mufredat/2026-2027/`,
MEB resmî çalışma takvimi (aşağıda doğrulandı), `academic_weeks` / `curriculum_schedule_items` / Faz 15A
yapısı (salt-okunur inceleme — migration 059, 067, 074, 110).

> Uyarı: Bu plan **yalnız önerilen takvimdir**. Öğrenciye soru açılması için ayrıca
> öğretmen "konu işlendi" onayı (`curriculum_teaching_approvals`, 110) ve önkoşul tamamlama kapısı
> (fail-closed) gerekir; takvimin haftasının gelmesi otomatik onay **vermez**.

## 1. 2026–2027 Resmî Çalışma Takvimi (resmî kaynaktan doğrulandı)

Doğrulama kaynağı: MEB tarafından 81 ile gönderilen genelge (Orta Öğretim Genel Müdürlüğü;
13.06.2026 tarihli, 2026/68 sayılı çalışma takvimi genelgesi — kamuya duyuruları meb.gov.tr alan adındaki
**bursa.meb.gov.tr/www/2026-2027-egitim-ogretim-yili-takvimi-aciklandi/icerik/6330/tr**, kayseri.meb.gov.tr ve
sivas.meb.gov.tr çalışma takvimi sayfaları).

| Etkinlik | Tarih |
|---|---|
| Öğretmen mesleki çalışmaları | 1 Eylül 2026 (Salı) |
| Uyum/ön rehberlik çalışmaları (9. sınıflar dahil ortaöğretim) | 7–11 Eylül 2026 |
| **1. dönem başlangıcı** | **14 Eylül 2026 (Pazartesi)** |
| **1. dönem ara tatili** | **16–20 Kasım 2026** |
| 1. dönem sonu | 22 Ocak 2027 (Cuma) |
| **Yarıyıl tatili** | **25 Ocak – 5 Şubat 2027** |
| **2. dönem başlangıcı** | **8 Şubat 2027 (Pazartesi)** |
| **2. dönem ara tatili** | **8–12 Mart 2027** (Ramazan Bayramı arifesi ve 1–3. günleri bu haftaya denk gelir) |
| 2. dönem sonu / yıl kapanışı | 25 Haziran 2027 (Cuma) |
| Resmî tatiller (öğretim günü kaybı): | 29 Ekim 2026 (Cumhuriyet), 1 Ocak 2027 (Yılbaşı), 23 Nisan 2027 (Ulusal Egemenlik), 17–19 Mayıs 2027 (Kurban Bayramı + 19 Mayıs) |

## 2. Hafta Modeli ve Varsayımlar (şeffaf hesap)

- **Takvim haftaları (K1–K41):** 14 Eylül 2026 (Pzt) – 25 Haziran 2027 (Cum) arası **41 takvim haftası**dır.
  **Öğretim haftaları (T1–T37)** yalnız resmî takvimde okul açık olan haftalardır (1. dönem 18, 2. dönem 19).
  Ara tatil (K10, K26) ve yarıyıl tatili (K20–K21) öğretim haftası DEĞİLDİR. Tüm yerleştirme aşağıdaki kanonik
  tabloya göre **yalnız T1–T37 üzerinden** yapılır; K# takvim bilgisi ayrıca verilir (eski melez `W#` etiketi
  kullanılmaz — aynı etiket iki anlam taşımaz).
- **Kanonik takvim tablosu (tek kaynak):**

| Takvim haftası (K) | Tarih aralığı | Durum | Öğretim haftası (T) |
|---|---|---|---|
| K1 | 14–18 Eylül 2026 | öğretim | T1 |
| K2 | 21–25 Eylül 2026 | öğretim | T2 |
| K3 | 28 Eylül – 2 Ekim 2026 | öğretim | T3 |
| K4 | 5–9 Ekim 2026 | öğretim | T4 |
| K5 | 12–16 Ekim 2026 | öğretim | T5 |
| K6 | 19–23 Ekim 2026 | öğretim | T6 |
| K7 | 26–30 Ekim 2026 | kısa hafta (29 Ekim, Cumhuriyet Bayramı) | T7 |
| K8 | 2–6 Kasım 2026 | öğretim | T8 |
| K9 | 9–13 Kasım 2026 | öğretim | T9 |
| K10 | 16–20 Kasım 2026 | ara tatil | — |
| K11 | 23–27 Kasım 2026 | öğretim | T10 |
| K12 | 30 Kasım – 4 Aralık 2026 | öğretim | T11 |
| K13 | 7–11 Aralık 2026 | öğretim | T12 |
| K14 | 14–18 Aralık 2026 | öğretim | T13 |
| K15 | 21–25 Aralık 2026 | öğretim | T14 |
| K16 | 28 Aralık 2026 – 1 Ocak 2027 | kısa hafta (1 Ocak, Yılbaşı) | T15 |
| K17 | 4–8 Ocak 2027 | öğretim | T16 |
| K18 | 11–15 Ocak 2027 | öğretim | T17 |
| K19 | 18–22 Ocak 2027 | öğretim | T18 |
| K20 | 25–29 Ocak 2027 | yarıyıl tatili | — |
| K21 | 1–5 Şubat 2027 | yarıyıl tatili | — |
| K22 | 8–12 Şubat 2027 | öğretim — **2. dönem başlangıcı** | T19 |
| K23 | 15–19 Şubat 2027 | öğretim | T20 |
| K24 | 22–26 Şubat 2027 | öğretim | T21 |
| K25 | 1–5 Mart 2027 | öğretim | T22 |
| K26 | 8–12 Mart 2027 | ara tatil (Ramazan Bayramı arifesi + 1–3. gün) | — |
| K27 | 15–19 Mart 2027 | öğretim | T23 |
| K28 | 22–26 Mart 2027 | öğretim | T24 |
| K29 | 29 Mart – 2 Nisan 2027 | öğretim | T25 |
| K30 | 5–9 Nisan 2027 | öğretim | T26 |
| K31 | 12–16 Nisan 2027 | öğretim | T27 |
| K32 | 19–23 Nisan 2027 | kısa hafta (23 Nisan, Ulusal Egemenlik) | T28 |
| K33 | 26–30 Nisan 2027 | öğretim | T29 |
| K34 | 3–7 Mayıs 2027 | öğretim (1 Mayıs Cumartesi — gün kaybı yok) | T30 |
| K35 | 10–14 Mayıs 2027 | öğretim | T31 |
| K36 | 17–21 Mayıs 2027 | kısa hafta (17–19 Mayıs, Kurban Bayramı + 19 Mayıs) | T32 |
| K37 | 24–28 Mayıs 2027 | öğretim | T33 |
| K38 | 31 Mayıs – 4 Haziran 2027 | öğretim | T34 |
| K39 | 7–11 Haziran 2027 | öğretim | T35 |
| K40 | 14–18 Haziran 2027 | öğretim | T36 |
| K41 | 21–25 Haziran 2027 | öğretim | T37 |

- **Tatil anlamı:** Ara tatil, yarıyıl tatili ve kısa resmî tatil haftalarında **yeni konu açılışı ve ders
  saati YOKTUR** (üstteki tüm tablolarda tatil haftalarının T numarası boştur). Ancak tatil, soru çözme yasağı
  DEĞİLDİR: daha önce öğretmen tarafından onaylanmış konuların (`curriculum_teaching_approvals`)
  **antrenman ve hedefli tekrar erişimi tatilde de açık kalır** — erişim takvime değil onaya bağlıdır (110).
- **Ders saati modeli:** matematik haftalık 6 saattir (hazırlık hariç; 9–12). Resmî yıllık **216 saat** =
  temalar **206 saat** + **okul temelli planlama 10 saat** (TYMM; OGM 2018'de temalar toplamı 216'dır, okul
  temelli pay yoktur). 216 ÷ 6 = **36 planlama haftası (T1–T36)**; **T37 (K41) yedek/kapanış** olarak bırakılır.
- **Yerleştirme kuralı (resmî belgede haftalık dağılım yoktur — bu plan uydurur, varsayımdır):**
  1) Tema saatleri resmî tablodan alınır (müfredat raporu §4); ondalık kalan tema içi esnekliktir.
  2) Tema başlangıç öğretim haftası `T = floor(kümülatif_başlangıç_saati/6) + 1` (T1–T37; tatiller yok sayılır);
     satırda gösterilen aralık = temanın ilk dersinin haftasından son saatine kadar olan T aralığıdır
     (T(S)–T(E), `T(x) = floor((x−1)/6) + 1`).
  3) Bir hafta iki temanın kesişirse (sınır haftası), haftanın ilk dersleri önceki temanın kuyruğu, sonraki
     hafta yeni tema başlar — `start_week` yeni temanın ilk açıldığı öğretim haftasıdır.
  4) Satırın tarih aralığı tatil haftası içerebilir; **saatler yalnız T haftalarınadır, tatil haftasına ders
     saati ve yeni açılış yazılmaz**.
- **Kısa haftalar ve tampon:** T7 (29 Ekim), T15 (1 Ocak), T28 (23 Nisan), T32 (17–19 Mayıs) resmî tatil
  nedeniyle kısadır; toplam ~6 öğretim günü (~6–7 saat) kayıp beklenir. Kayıp, **9–11'de okul temelli 10 saat**
  tamponundan, **12'de T37 (K41) yedek haftasından** karşılanır; karşılamanın yeri her sınıf tablosunda açık
  "tampon" satırıyla gösterilir (§3–§6).
- **DB hafta anlamı:** `academic_weeks.week` ve `curriculum_schedule_items.start_week/end_week`
  (start INCLUSIVE, end EXCLUSIVE, end boşsa açık uçlu — migration 059). `start_week ≤ güncel hafta` ise konu
  takvimsel olarak açılmış sayılır; `end_week` yalnız "güncel içerik" penceresini sınar, **antrenman erişimini
  KAPATMAZ ve tatilde de kapatmaz**. Tablolardaki T# öğretim haftası, K# takvim haftasıdır (yalnız başvuru);
  DB'ye yüklemeden önce T/K numaralandırma kararı gerekir (§9).

## 3. Sınıf 9 (TYMM 2026) — 216 saat (206 tema + 10 okul temelli)

| Öğretim haftası (T) | Takvim (K) | Tarih aralığı | Tema/konu | Alt konu / öğrenme çıktısı | Planlanan ders saati | Açılma durumu | Kaynak eşleme durumu |
|---|---|---|---|---|---|---|---|
| T1–T7* | K1–K7 | 14 Eyl – 30 Eki 2026 | MAT.9.1 SAYILAR | 9.1.1 üslü-köklü işlemler; 9.1.2 aralıklar+ küme sembolleri; 9.1.3 sayı kümeleri; 9.1.4 özdeşlik/çarpanlara ayırma | 38 | Kısmen açık: 9.1.1 köklü, 9.1.2 aralık, 9.1.4 polinom kesiti kapalı/kaynak eksik; diğer alt konular açık (onay sonrası) | Orta–Yüksek (örgü: Yüksek; köklü/aralık/polinom kesiti İnceleme gerekli) |
| T7–T13 | K7–K13 | 26 Eki – 11 Ara 2026 | MAT.9.2 NİCELİKLER VE DEĞİŞİMLER | 9.2.1 doğrusal referans + türetilenler; 9.2.2 mutlak değer; 9.2.3 denklem/eşitsizlik problemleri | 38 | Açık (onay sonrası); matematik.pdf 125–166 alt içeriği doğrulanmadı → uygulama öncesi görsel kontrol önerilir | Orta (81–108 Yüksek; 125–166 İnceleme gerekli) |
| T13–T15 | K14–K16 | 14 Ara 2026 – 1 Oca 2027 | MAT.9.3 GEOMETRİK ŞEKİLLER | 9.3.1 üçgende açı-kenar ilişkileri (ispat) | 12 | Açık (onay sonrası); mat(3) ? sayfalar doğrulanmadan içerik kullanılmaz | Orta (matematik 167–180 Yüksek; mat3 ?) |
| T15–T21 | K16–K24 | 28 Ara 2026 – 26 Şub 2027 | MAT.9.4 EŞLİK VE BENZERLİK | 9.4.1 dönüşümler; 9.4.2 eşlik; 9.4.3 benzer üçgen; 9.4.4 Tales/Öklid/Pisagor; 9.4.5 problemler | 36 | Kısmen açık: 9.4.4 Pisagor/Öklid kesiti (matematik 233–252 içi) kapalı/kaynak eksik; diğerleri açık | Orta (181–210 Yüksek; Pisagor/Öklid İnceleme gerekli; mat3 ?) |
| T21–T26 | K24–K30 | 22 Şub – 9 Nis 2027 | MAT.9.5 ALGORİTMA VE BİLİŞİM | 9.5.1 algoritmayla problem çözme; 9.5.2 bağlaç/niceleyici; 9.5.3 matematiksel görevlere yansıtma | 30 | Kısmen açık: algoritma/niceleyici bileşeni için kaynak eksik (yalnız 9–24 mantık); 9.5.1 kapalı/kaynak eksik | Orta (9–24 Yüksek; 9.5.1 İnceleme gerekli) |
| T26–T32 | K30–K36 | 5 Nis – 21 May 2027 | MAT.9.6 İSTATİSTİKSEL ARAŞTIRMA SÜRECİ | 9.6.1 tek nicel veriyle çalışma; 9.6.2 sonuçları tartışma | 34 | Açık (onay sonrası); tyt 107 başlık garbeli → uygulama öncesi görsel kontrol önerilir | Orta (matematik 273–302 Yüksek; tyt 107 ?) |
| T32–T35 | K36–K39 | 17 May – 11 Haz 2027 | MAT.9.7 VERİDEN OLASIĞINA | 9.7.1 deneysel olasılık; 9.7.2 teorik olasılık | 18 | Açık (onay sonrası); mat(3) 121? doğrulanmadan içerik kullanılmaz | Orta (329–342 Yüksek; mat3 ?) |
| T35–T36 | K39–K40 | 7–18 Haz 2027 | Okul temelli planlama (10 s) | Tema dışı uygulama/değerlendirme + tatil-telafisi | 10 | — (müfredat konusu değil; takvim/onay gerekmez) | — |
| **Tampon** | K7·K16·K32·K36 | T7/T15/T28/T32 (29 Eki, 1 Oca, 23 Nis, 17–19 May) | Kısa hafta kaybı | Resmî tatil nedeniyle kaybedilen ~6 öğretim günü (~6–7 s) | 0 (tampon) | — (okul temelli 10 s bütçesinden karşılanır) | — |

\* T7 (K7) 29 Eki Perşembe resmî tatil nedeniyle kısa öğretim haftasıdır; kayıp okul temelli 10 saat tamponundan karşılanır. T = öğretim haftası (1–37); K = takvim haftası (§2 kanonik tablo). Satır aralıkları temanın T(S)–T(E) kapsamıdır; sınır haftası paylaşımı §2.4'tedir. Yarıyıl (K20–K21) içine ders saati yazılmaz.

## 4. Sınıf 10 (TYMM 2026) — 216 saat (206 tema + 10 okul temelli)

| Öğretim haftası (T) | Takvim (K) | Tarih aralığı | Tema/konu | Alt konu / öğrenme çıktısı | Planlanan ders saati | Açılma durumu | Kaynak eşleme durumu |
|---|---|---|---|---|---|---|---|
| T1–T6* | K1–K6 | 14 Eyl – 23 Eki 2026 | MAT.10.1 GEOMETRİK ŞEKİLLER | 10.1.1 dik üçgende trigonometrik oranlar; 10.1.2 yardımcı elemanlar; 10.1.3 üçgenin alanı; 10.1.4 sinüs/kosinüs teoremleri | 36 | Kısmen açık: 10.1.4 sinüs/kosinüs kaynak eksik (ayt ?); diğerleri açık | Orta (233–252, 211–232, 253–272 Yüksek; 10.1.4 İnceleme gerekli; mat3 ?) |
| T7–T10 | K7–K11 | 26 Eki – 27 Kas 2026 | MAT.10.2 İSTATİSTİKSEL ARAŞTIRMA SÜRECİ | 10.2.1 iki kategorik değişken; 10.2.2 sonuçları tartışma | 24 | **Kapalı / kaynak eksik** (kategorik değişken 2018-erası kaynakta yok) | İnceleme gerekli |
| T11–T14 | K12–K15 | 30 Kas – 25 Ara 2026 | MAT.10.3 SAYILAR | 10.3.1 asal çarpan/bölen; 10.3.2 EBOB–EKOK; 10.3.3 bölünebilme | 20 | Kısmen açık: yalnız 10.3.3 açık (65–80); 10.3.1/10.3.2 kapalı/kaynak eksik | Orta (65–80 Yüksek; 10.3.1–2 İnceleme gerekli) |
| T14–T23 | K15–K27 | 21 Ara 2026 – 19 Mar 2027 | MAT.10.4 NİCELİKLER VE DEĞİŞİMLER | 10.4.1 fonksiyon şartları; 10.4.2 karesel; 10.4.3 karekök; 10.4.4 rasyonel; 10.4.5 ters fonksiyon; 10.4.6 denklem/eşitsizlik | 58 | Kısmen açık: 10.4.1, 10.4.5, 10.4.6 açık; **10.4.2, 10.4.3, 10.4.4 kapalı/kaynak eksik** (referans fonksiyon yaklaşımı 2018'de yok) | Orta (343–362, 421–456 Yüksek; 10.4.2 → İnceleme gerekli; 10.4.3/10.4.4 → kapalı) |
| T24–T28 | K28–K32 | 22 Mar – 23 Nis 2027 | MAT.10.5 SAYMA, ALGORİTMA VE BİLİŞİM | 10.5.1 sayma stratejileri; 10.5.2 algoritmik yapılandırma | 28 | Kısmen açık: 10.5.1 açık (303–328); **10.5.2 kapalı/kaynak eksik** | Orta (303–328 Yüksek; 10.5.2 İnceleme gerekli; mat3 ?) |
| T28–T32 | K32–K36 | 19 Nis – 21 May 2027 | MAT.10.6 ANALİTİK İNCELEME | 10.6.1 iki nokta/bölen nokta; 10.6.2 doğru temsil aracı | 22 | Kısmen açık: mat(1) 67–498? + mat(2) harf cevap; bitiş ? doğrulanmadan içerik kullanılmaz | Orta (mat1 bitiş ?, ayt ?) |
| T32–T35 | K36–K39 | 17 May – 11 Haz 2027 | MAT.10.7 VERİDEN OLASIĞINA | 10.7.1 koşullu olasılık; 10.7.2 Bayes | 18 | **Kapalı / kaynak eksik** (koşullu/Bayes kaynağı yok) | İnceleme gerekli |
| T35–T36 | K39–K40 | 7–18 Haz 2027 | Okul temelli planlama (10 s) | Tema dışı uygulama/değerlendirme + tatil-telafisi | 10 | — | — |
| **Tampon** | K7·K16·K32·K36 | T7/T15/T28/T32 (29 Eki, 1 Oca, 23 Nis, 17–19 May) | Kısa hafta kaybı | Resmî tatil nedeniyle kaybedilen ~6 öğretim günü (~6–7 s) | 0 (tampon) | — (okul temelli 10 s bütçesinden karşılanır) | — |

\* T = öğretim haftası (1–37); K = takvim haftası (§2 kanonik tablo). Satır aralıkları temanın T(S)–T(E) kapsamıdır; sınır haftası paylaşımı §2.4'tedir. Yarıyıl (K20–K21) ve ara tatil (K10, K26) içine ders saati yazılmaz.

## 5. Sınıf 11 (TYMM 2026) — 216 saat (206 tema + 10 okul temelli)

| Öğretim haftası (T) | Takvim (K) | Tarih aralığı | Tema/konu | Alt konu / öğrenme çıktısı | Planlanan ders saati | Açılma durumu | Kaynak eşleme durumu |
|---|---|---|---|---|---|---|---|
| T1–T4 | K1–K4 | 14 Eyl – 9 Eki 2026 | MAT.11.1 İSTATİSTİKSEL ARAŞTIRMA SÜRECİ | 11.1.1 iki nicel değişken; 11.1.2 ilişkililik tartışması | 24 | **Kapalı / kaynak eksik** (korelasyon kaynağı yok; matematik.pdf 273–302 yalnız tek değişkenli) | İnceleme gerekli |
| T5–T15 | K5–K16 | 12 Eki 2026 – 1 Oca 2027 | MAT.11.2 GEOMETRİK ŞEKİLLER | 11.2.1 dörtgenler; 11.2.2 özel dörtgenler; 11.2.3 içbükey-dışbükey; 11.2.4 dışbükey; 11.2.5 çokgen problemleri | 62 | Açık (onay sonrası); mat(3) 158?–167? doğrulanmadan içerik kullanılmaz | Orta (457–524 Yüksek; mat3 ?) |
| T15–T22 | K16–K25 | 28 Ara 2026 – 5 Mar 2027 | MAT.11.3 NİCELİKLER VE DEĞİŞİMLER (1) | 11.3.1 trigonometrik referans fonksiyonlar; 11.3.2 denklem problemleri | 42 | Açık (onay sonrası); matematik.pdf bağ yok (mat(1) 9–66, mat(2) 89–107, ayt 30?–42?); ayt doğrulanmalı | Orta (ayt ?; matematik.pdf bağ yok) |
| T22–T29 | K25–K33 | 1 Mar – 30 Nis 2027 | MAT.11.3 NİCELİKLER VE DEĞİŞİMLER (2) | 11.3.3 üstel; 11.3.4 üstel→logaritma; 11.3.5 logaritmik referans; 11.3.6 üstel/log denklem problemleri | 42 | Açık (onay sonrası); matematik.pdf bağ yok (ayt 50?–61?, mat(2) 71–77); ayt doğrulanmalı | Orta (ayt ?; matematik.pdf bağ yok) |
| T29–T35 | K33–K39 | 26 Nis – 11 Haz 2027 | MAT.11.3 NİCELİKLER VE DEĞİŞİMLER (3) | 11.3.7 bileşke; 11.3.8 dört işlem | 36 | Açık (onay sonrası) | Orta (363–388 kesit; 10.4.5 ile paylaşım) |
| T35–T36 | K39–K40 | 7–18 Haz 2027 | Okul temelli planlama (10 s) | Tema dışı uygulama/değerlendirme + tatil-telafisi | 10 | — | — |
| **Tampon** | K7·K16·K32·K36 | T7/T15/T28/T32 (29 Eki, 1 Oca, 23 Nis, 17–19 May) | Kısa hafta kaybı | Resmî tatil nedeniyle kaybedilen ~6 öğretim günü (~6–7 s) | 0 (tampon) | — (okul temelli 10 s bütçesinden karşılanır) | — |

\* T = öğretim haftası (1–37); K = takvim haftası (§2 kanonik tablo). Satır aralıkları temanın T(S)–T(E) kapsamıdır; sınır haftası paylaşımı §2.4'tedir. Yarıyıl (K20–K21) ve ara tatil (K10, K26) içine ders saati yazılmaz.

## 6. Sınıf 12 (OGM 2018) — 216 saat (okul temelli pay yok)

| Öğretim haftası (T) | Takvim (K) | Tarih aralığı | Tema/konu | Alt konu / kazanım | Planlanan ders saati | Açılma durumu | Kaynak eşleme durumu |
|---|---|---|---|---|---|---|---|
| T1–T6* | K1–K6 | 14 Eyl – 23 Eki 2026 | 12.1 ÜSTEL VE LOGARİTMİK FONKSİYONLAR | Üstel fonksiyon; logaritma; üstel/log denklem-eşitsizlik | 36 | Açık (onay sonrası); ayt 50?–61? doğrulanmalı | Orta (ayt ?; mat(2) 71–83) |
| T7–T9 | K7–K9 | 26 Eki – 13 Kas 2026 | 12.2 DİZİLER | Gerçek sayı dizileri (aritmetik/geometrik) | 18 | Açık (onay sonrası); ayt 62?–67? doğrulanmalı | Orta (ayt ?; mat(2) 83–89) |
| T10–T15 | K11–K16 | 23 Kas 2026 – 1 Oca 2027 | 12.3 TRİGONOMETRİ | Toplam-fark / iki kat açı; trigonometrik denklemler | 36 | Açık (onay sonrası); ayt 45?–49? doğrulanmalı | Orta (ayt ?; mat(2) 101–107) |
| T16–T18 | K17–K19 | 4–22 Oca 2027 | 12.4 DÖNÜŞÜMLER | Analitik düzlemde temel dönüşümler | 18 | Kısmen açık: tek kaynak (ayt 100?) — doğrulanmadan içerik kullanılmaz | Orta (tek kaynak ?) |
| T19–T26 | K22–K30 | 8 Şub – 9 Nis 2027 | 12.5 TÜREV | Limit-süreklilik; türev; türevin uygulamaları | 46 | Açık (onay sonrası); ayt 68?–86? doğrulanmalı | Orta (ayt ?; mat(2) 119–131) |
| T26–T33 | K30–K37 | 5 Nis – 28 May 2027 | 12.6 İNTEGRAL | Belirsiz integral; belirli integral ve uygulamaları | 42 | Açık (onay sonrası); ayt 87?–91? doğrulanmalı | Orta (ayt ?; mat(2) 143–149) |
| T33–T36 | K37–K40 | 24 May – 18 Haz 2027 | 12.7 ANALİTİK GEOMETRİ | Çemberin analitik incelenmesi | 20 | Açık (onay sonrası); ayt 126?–127? doğrulanmalı | Orta (ayt ?; mat(1) 499–522) |
| **Tampon** | K41 | T37 / K41 (21–25 Haz) | Yedek hafta (kısa hafta telafisi) | 12'de okul temelli pay yoktur; T7/T15/T28/T32 kısa hafta kayıpları T37 yedek haftasından karşılanır | 0 (yedek) | — (T37; 206+10 yerine tema toplamı 216) | — |

\* 12. sınıfta okul temelli pay olmadığından 216 = tema toplamıdır (T1–T36 = 36 hafta × 6 s = 216); T37 (K41) yalnız kısa hafta kaybı için yedek haftadır. T = öğretim haftası (1–37); K = takvim haftası (§2 kanonik tablo). Satır aralıkları temanın T(S)–T(E) kapsamıdır; sınır haftası paylaşımı §2.4'tedir. Yarıyıl (K20–K21) içine ders saati yazılmaz.

## 7. Kaynak Eşlemesi "İnceleme gerekli" Olan Alt Konular (plana alındı, açılış kapalı)

Plan tablolarında kapalı/kısmen açık satırların nedeni:
- **9.1.1 köklü kısmı** — matematik.pdf'te başlık yok; tyt 39–44 var → köklü açılır, üslü+köklü bütünlüğü kaynak kısıtlı.
- **9.1.2 aralık başlığı** — matematik.pdf kümeleri karşılar, "aralık" başlığı yok.
- **9.1.4 / 9.5.1 / 9.5 niceleyici·algoritma bileşeni** — 2018-erası kaynak dağınık/kısmi.
- **9.4.4 Pisagor/Öklid kesiti** — matematik 233–252 içi (Dik Üçgen ve Trigonometri bölümünde); bind'siz.
- **10.1.4, 10.2, 10.3.1–10.3.2, 10.4.2–10.4.4, 10.5.2, 10.7** — referans fonksiyonlar, kategorik değişken,
  asal çarpan/EBOB–EKOK, algoritmik yapılandırma, koşullu olasılık/Bayes: mevcut 6 PDF'te karşılığı yok.
- **11.1** — iki nicel değişken/korelasyon kaynağı yok.
- 12. sınıfta içerik karşılığı tam olmakla birlikte **ayt-matematik.pdf İçindekiler glyph sorunu nedeniyle tüm
  sayfalar `?`** — içerik üretimi/uygulama öncesi görsel doğrulama şartı.

## 8. Özet 1 — Hafta ve Ders Saati Toplamları

| Sınıf | Takvim haftası (K1–K41) | Öğretim haftası (T1–T37) | Planlanan hafta (T) | Toplam ders saati | Açıklama |
|---|---|---|---|---|---|
| 9 | 41 | 37 (18 + 19) | T1–T36 (36) | **216** (206 tema + 10 okul temelli) | T37 (K41) yedek/kapanış |
| 10 | 41 | 37 (18 + 19) | T1–T36 (36) | **216** (206 tema + 10 okul temelli) | T37 (K41) yedek/kapanış |
| 11 | 41 | 37 (18 + 19) | T1–T36 (36) | **216** (206 tema + 10 okul temelli) | T37 (K41) yedek/kapanış |
| 12 | 41 | 37 (18 + 19) | T1–T36 (36) | **216** (OGM 2018 tema toplamı) | T37 (K41) yedek — kısa hafta telafisi rezervi (okul temelli pay yok) |

Toplam hafta: 41 takvim, 37 öğretim; kısa hafta kayıpları toplam ~6–7 saat: 9–11'de okul temelli 10 s
tamponundan, 12'de T37 yedek haftasından karşılanır. Tema saati dağılımı müfredat raporu §4'teki resmî
sayılarla birebir; saatler yalnız öğretim haftalarına aittir, tatil haftalarına yazılmaz.

## 9. Özet 3 — Bu Planı DB'ye Uygulamadan Önce Gereken Kararlar

1. **`curriculum_versions`:** 2026–27 için TYMM 2026 (9/10/11) ve OGM 2018 (12) sürümleri; her akademik yıl için
   tek `is_default=true` (059 kısıtı). Sürüm kimlikleri ve `academic_year` formatı netleştirilmeli.
2. **`academic_weeks` numaralandırması (DÜZELTMESİ — 12A):** Bu rapor T1–T37 öğretim / K1–K41 takvim
   (kanonik tablo §2) kullanır. **DB'de K1–K41'in tamamı (tatil haftaları dahil) satır olarak yüklenir.**
   Tatil haftalarına (K10, K20–K21, K26) `start_week` değeri atanmaz; bu haftalara hiçbir
   `curriculum_schedule_items` satırı açılmaz. Düzeltme gerekçesi: `_faz2_require_period()` (068:249),
   bugünü kapsayan `academic_weeks` satırı yoksa P0001 istisna fırlatır — tatil satırı YOKSA tüm
   soru akışları (antrenman + hedefli tekrar) hatayla kapanır; bu, "tatilde antrenman + hedefli tekrar
   açık kalır" kuralının tam zıddıdır. Tatil satırları yüklenerek dönem çözümü başarıyla çalışır;
   **yeni konu açılmaması** yalnızca `start_week` değerlerinin yalnız öğretim haftalarına atanmasıyla
   ve öğretmen onay kapısıyla (gate b) sağlanır — satır yokluğuyla DEĞİL. Önceki "satır YOKLUĞU
   önerilir" ifadesi REDDEDİLMİŞTİR; 12A doğrusu budur.
3. **`curriculum_schedule_items` yükü:** Kayıt başına `schedule_profile_id` (MEB varsayılan), `grade_level`,
   `subject_id`, `topic_id`/`subtopic_id`/`outcome_id`; `start_week` yukarıdaki T değerine (öğretim haftası
   1–37) çevrilmiş ilk açılış haftası; `end_week` önerisi = sonraki temanın başlangıcı (exclusive) veya NULL
   (antrenman kalıcılığı — 059). Konu/alt konu/ÖÇ ağacı rapordaki kodlarla (MAT.9.1.1…) eşleşmeli; eksik
   ağaç kayıtları önce açılmalı.
4. **Kapalı/kaynak eksik alt konular:** 10.2, 10.7, 11.1, 10.4.3–10.4.4, 10.5.2 (ve kısmi olanlar) için ya
   kaynak temin edilir ya da bu subtopic'ler `curriculum_schedule_items`'a eklenmez (plan dışı). Eklenirse bile
   `curriculum_teaching_approvals` onayı verilmemelidir — sorular fail-closed kilitli kalır.
5. **Öğretmen onay kapısı (110):** `set_curriculum_teaching_approvals` RPC'si var ama onay için bir **admin
   arayüzü yoktur** (110 notu). Onay giriş süreci kararı: bu görevde yalnız RPC mi kullanılacak, yoksa UI
   geliştirilecek mi — plan devreye almadan netleşmeli.
6. **Önkoşul verisi (`curriculum_prerequisites`):** Boşsa tüm konular `onkosul_eksik` kilidine takılır
   (110 '.fiil-closed). 9→10→11 referans fonksiyon zinciri ve 12 ünite önkoşulları (`requirement_level='required'`,
   `review_status='approved'`) yüklenmeden kapsam açılamaz.
7. **Soru stoğu:** Her açılacak subtopic için onaylı soru + `question_curriculum_mappings`
   (`review_status='approved'`) + vault `practice_eligible=true` gereklidir. Kapalı konulara soru üretilmez.
8. **Okul temelli 10 saat:** Müfredat konusu değildir, `curriculum_schedule_items`'ta karşılığı yoktur;
   yalnız takvim tamponu (tatil telafisi) olarak not edilmiştir. Fiili kullanımı zümre kararıdır.
9. **Kısa hafta (T7/T15/T28/T32) saat kayıpları ve tampon:** T7 (29 Ekim), T15 (1 Ocak), T28 (23 Nisan),
   T32 (17–19 Mayıs) resmî tatil nedeniyle kısadır; toplam ~6–7 saat kayıp beklenir. Kayıp: 9–11'de okul
   temelli 10 saat tamponundan, 12'de T37 (K41) yedek haftasından dengelenir — her sınıf tablosunda açık
   "tampon" satırıyla gösterilmiştir (§3–§6). Bu haftalara ders saati / yeni konu açılışı yazılmaz; ancak
   daha önce `curriculum_teaching_approvals` ile onaylı konuların **antrenman ve hedefli tekrar erişimi
   tatilde de açık kalır** (tatil, soru çözme yasağı değildir — §2).
10. **Görsel doğrulama listesi:** `?` işaretli tüm sayfalar (ayt-matematik İçindekiler, mat(3) tokenları,
    mat(1) 498?, tyt 107, matematik 125–166 içeriği) onaylanmadan önce doğrulanmalı — doğrulanmayan hücreler
    içerik üretiminde/uygulamada kullanılmaz (eşleme raporu §7).

## 10. Kapsam Dışı ve Kapanış

- Bu görevde hiçbir DB yazımı, migration, kod değişikliği, soru üretimi, PDF yeniden taraması veya AI çağrısı
  yapılmadı; `git` üzerinde commit/push yok.
- Kaynakların manipülasyonu yok: yalnız üç sabit rapor/arşiv + resmî MEB çalışma takvimi kullanıldı.
- Raporla; dur. Sonraki adım için (DB'e uygulama) kullanıcı "devam" onayı ve §9 kararları gerekir.

Durdum.