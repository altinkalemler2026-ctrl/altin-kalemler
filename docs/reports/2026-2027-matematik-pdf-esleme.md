# 2026–2027 Resmî Müfredat ↔ Mevcut PDF Haritası Eşlemesi

Tarih: 2026-09-15 (son düzeltme turu — matematik.pdf yeniden bind) · Sınıflar: 9–12 · Salt-okunur (commit/push yok)
Referans: `2026-2027-matematik-resmi-mufredat.md` (sürüm/karar doğrulaması) ·
`pdf-matematik-konu-sayfa-haritasi.md` (§2, §4 diğer kaynaklar; NOT: matematik.pdf için eski çıkarım KULLANILMADI)
Önemli: TYT/AYT burada **sınıf etiketi değildir**; eşleme resmî temadaki içerik üzerinden yapılır. Belirsiz
eşleme **tahmin edilmez**, "İnceleme gerekli" olarak işaretlenir.

## 1. Eşleme Kuralları ve Lejant

- `matematik.pdf` için **kanıt = doğrulanmış İçindekiler listesi (§2)**; başlangıç sayfaları bu listeden gelir.
- Bölüm **bitiş** sayfaları "sonraki bölüm başlangıcı − 1" varsayımıdır (Yüksek başlangıç, Orta bitiş).
- `?` işareti: ilgili kaynak İçindekiler okumasında glyph bozulması olan/doğrulanmamış sayfa → **görsel doğrulama ister**.
- Güven kuralı: bir satırda `?` işaretli veya görsel doğrulama gerektiren **herhangi bir** hücre varsa o satır
  `Yüksek` olamaz; `Orta` yapılır. Kaynakta doğrudan karşılığı olmayan kavram `İnceleme gerekli` olur.
- Bind kuralı: sınıf satırının konu başlığı, §2'deki doğrulanmış İçindekiler başlığıyla uyuşmuyorsa o eşleme
  `İnceleme gerekli` yapılır; matematik.pdf hücresine sayfa yazılmaz.
- Çözüm ilkesi: kaynak PDF'lerdeki çözümlerden **doğrudan türetme/kopyalama yapılmaz**; soru çözümleri bağımsız
  üretilir ve ayrı doğrulanır (bkz. §8).

## 2. matematik.pdf — Doğrulanmış İçindekiler (temel kanıt) ve Resmî Tema Bind'i

Kullanıcı doğrulamalı İçindekiler listesi (bölüm başlangıç sayfaları). Bitişler "sonraki başlangıç − 1".

| # | Bölüm (İçindekiler) | Başlangıç | Bitiş | Resmî tema bağlantısı | Bind durum / güven |
|---|---|---|---|---|---|
| 1 | Önermeler ve Bileşik Önermeler | 9 | 24 | MAT.9.5.2 (mantık bağlaçları) | Orta (algoritma bağlamı kısmi) |
| 2 | Kümelerde Temel Kavramlar | 25 | 36 | MAT.9.1.2 (küme kısmı) | Orta (aralık başlığı yok) |
| 3 | Kümelerde İşlemler | 37 | 52 | MAT.9.1.2 (küme işlemleri, kısmi) | Orta |
| 4 | Sayı Kümeleri | 53 | 64 | MAT.9.1.3 | Yüksek |
| 5 | Bölünebilme Kuralları | 65 | 80 | MAT.10.3.3 | Yüksek |
| 6 | Birinci Dereceden Denklemler ve Eşitsizlikler | 81 | 108 | MAT.9.2.1 / 9.2.3 | Yüksek |
| 7 | Üslü İfadeler ve Denklemler | 109 | 124 | MAT.9.1.1 üslü kısmı | Orta (köklü başlığı yok) |
| 8 | Denklemler ve Eşitsizliklerle İlgili Uygulamalar | 125 | 166 | MAT.9.2 (problemler) | Orta (alt içerik doğrulanamadı) |
| 9 | Üçgenlerde Temel Kavramlar | 167 | 180 | MAT.9.3.1 | Yüksek |
| 10 | Üçgenlerde Eşlik ve Benzerlik | 181 | 210 | MAT.9.4 (eşlik/benzerlik) | Yüksek |
| 11 | Üçgenlerin Yardımcı Elemanları | 211 | 232 | MAT.10.1.2 | Yüksek |
| 12 | Dik Üçgen ve Trigonometri | 233 | 252 | MAT.10.1.1; Pisagor/Öklid kesiti MAT.9.4.4 | Orta (bölüm içi iki temaya ayırma) |
| 13 | Üçgenin Alanı | 253 | 272 | MAT.10.1.3 | Yüksek |
| 14 | Merkezi Eğilim ve Yayılım Ölçüleri | 273 | 286 | MAT.9.6 | Yüksek (başlık birebir) |
| 15 | Verilerin Grafik ile Gösterilmesi | 287 | 302 | MAT.9.6 | Yüksek (başlık birebir) |
| 16 | Sıralama ve Seçme | 303 | 328 | MAT.10.5.1 (sayma stratejileri) | Yüksek |
| 17 | Basit Olayların Olasılıkları | 329 | 342 | MAT.9.7.1–9.7.2 | Yüksek |
| 18 | Fonksiyon Kavramı ve Gösterimi | 343 | 362 | MAT.10.4.1 | Yüksek |
| 19 | İki Fonksiyonun Bileşkesi ve Ters Fonksiyon | 363 | 388 | MAT.11.3(3) (bileşke) + MAT.10.4.5 (ters) | Orta (iki tema paylaşır) |
| 20 | Polinom Kavramı ve Polinomlarda İşlemler | 389 | 402 | MAT.9.1.4 (cebirsel ifade işlemleri kısmı) | Orta (2018 polinom ünitesi dağınık karşılık) |
| 21 | Polinomların Çarpanlara Ayrılması | 403 | 420 | MAT.9.1.4 (özdeşlik/çarpanlara ayırma) | Yüksek |
| 22 | İkinci Dereceden Bir Bilinmeyenli Denklemler | 421 | 456 | MAT.10.4.6 | Yüksek |
| 23 | Çokgenler – Dörtgenler ve Özellikleri | 457 | 476 | MAT.11.2.1–11.2.2 | Yüksek |
| 24 | Özel Dörtgenler | 477 | 524 | MAT.11.2.2 | Yüksek |
| 25 | Katı Cisimler | 525 | 552 | resmî 9–12 karşılığı yok (2018-erası 10.6 UZAY GEOMETRİ) | İnceleme gerekli |
| 26 | Cevap Anahtarı | 553 | — | — (harf tablosu) | bağ yok |

Doğrulanmış başlangıçların konuya bağlanması: **9 = Önermeler (9.5.2)**, **25/37 = Kümeler (9.1.2)**,
**53 = Sayı Kümeleri (9.1.3)**, **65 = Bölünebilme (10.3.3)**, **81 = 1. Derece Denklem-Eşitsizlik (9.2)**,
**109 = Üslü (9.1.1)**, **125 = Uygulamalar (9.2)**, **167 = Üçgen Kavramları (9.3)**, **181 = Eşlik/Benzerlik
(9.4)**, **211 = Yardımcı Elemanlar (10.1.2)**, **233 = Dik Üçgen+Trigonometri (10.1.1)**, **253 = Üçgenin Alanı
(10.1.3)**, **273/287 = İstatistik (9.6)**, **303 = Sıralama/Seçme (10.5.1)**, **329 = Olasılıklar (9.7)**,
**343 = Fonksiyon (10.4.1)**, **363 = Bileşke/Ters (11.3(3)+10.4.5)**, **389/403 = Polinom (9.1.4)**,
**421 = 2. Derece Denklem (10.4.6)**, **457/477 = Çokgen/Dörtgen (11.2)**, **525 = Katı Cisimler
(İnceleme gerekli)**, **553 = Cevap Anahtarı (bağ yok)**.

## 3. Sınıf 9 (TYMM 2026) Eşleme

| Resmî konu | Alt konu / kazanım | Öğr. sırası | İlgili PDF'ler | Sayfa aralıkları | Çözüm durumu | Eşleme güveni |
|---|---|---|---|---|---|---|
| MAT.9.1 SAYILAR | Üslü ve köklü gösterimlerle işlemler (9.1.1) | 1 | tyt-matematik · matematik · matematik (3) | 39–44 · 109–124 (üslü kısmı; köklü başlığı yok ➜ İnceleme gerekli) · 125?–126? | mat(3) harf cevap; matematik.pdf çözümlü örnek | Orta (mat3 ?; köklü bind yok) |
| MAT.9.1 SAYILAR | Gerçek sayı aralıkları + küme sembolleri (9.1.2) | 1 | tyt-matematik · matematik | 29 · 25–52 (kümeler; aralık başlığı yok ➜ İnceleme gerekli) | tyt özet | Orta (kısmi karşılık) |
| MAT.9.1 SAYILAR | Sayı kümeleri ve işlem özellikleri (9.1.3) | 1 | tyt-matematik · matematik · matematik (3) | 9–13 · 53–64 · 25?–26? | mat(3) harf cevap | Orta (mat3 ?) |
| MAT.9.1 SAYILAR | İşlem özelliklerini cebirsel ifade (özdeşlik/çarpanlara ayırma) (9.1.4) | 1 | tyt-matematik · matematik | 97–101 · 389–402 (kısmi) + 403–420 | matematik.pdf çözümlü örnek | Orta (polinom kısmı kısmi) |
| MAT.9.2 NİCELİKLER VE DEĞİŞİMLER | Doğrusal fonksiyonlar + nitel özellikler; mutlak değer fonksiyonu; birinci dereceden denklem/eşitsizlik problemleri (9.2.1–9.2.3) | 2 | tyt-matematik · matematik | 31–38 · 81–108 + 125–166 | matematik.pdf çözümlü örnek | Orta (125–166 alt içeriği doğrulanamadı) |
| MAT.9.3 GEOMETRİK ŞEKİLLER | Üçgende açı–kenar özellikleri/bağıntıları (9.3.1) | 3 | tyt-matematik · matematik · matematik (3) | 111–117 · 167–180 · 141?–149? | matematik.pdf çözümlü örnek | Orta (mat3 ?) |
| MAT.9.4 EŞLİK VE BENZERLİK | Dönüşümler; eşlik/benzerlik koşulları; benzer üçgen; Tales-Öklid-Pisagor; problemler (9.4.1–9.4.5) | 4 | tyt-matematik · matematik · matematik (3) | 118–123 + 132–133 · 181–210 (eşlik/benzerlik); Pisagor/Öklid kesiti (233–252 içi) ➜ İnceleme gerekli · 143?–149? | matematik.pdf çözümlü örnek | Orta (mat3 ?; Pisagor/Öklid kesiti bind'siz) |
| MAT.9.5 ALGORİTMA VE BİLİŞİM | Algoritma problemleri; mantık bağlaçları/niceleyiciler; algoritmik kullanım (9.5.1–9.5.3) | 5 | tyt-matematik · matematik · matematik (3) | 56–63 (2018 Mantık) · 9–24 · 11 | matematik.pdf çözümlü örnek | Orta (algoritma/niceleyici bileşeni için eksik) |
| MAT.9.6 İSTATİSTİKSEL ARAŞTIRMA SÜRECİ | Tek nicel değişkenli dağılımlar; yorumları tartışma (9.6.1–9.6.2) | 6 | tyt-matematik · matematik | 107–110 · 273–302 | matematik.pdf çözümlü örnek | Orta (tyt 107 başlık garbeli; kapsam çoğunlukla karşılanır) |
| MAT.9.7 VERİDEN OLASILIĞA | Deneysel olasılık; teorik olasılık (9.7.1–9.7.2) | 7 | tyt-matematik · matematik · matematik (3) | 79–80 · 329–342 · 121? | matematik.pdf çözümlü örnek | Orta (mat3 ?) |

## 4. Sınıf 10 (TYMM 2026) Eşleme

| Resmî konu | Alt konu / kazanım | Öğr. sırası | İlgili PDF'ler | Sayfa aralıkları | Çözüm durumu | Eşleme güveni |
|---|---|---|---|---|---|---|
| MAT.10.1 GEOMETRİK ŞEKİLLER | Dik üçgende trigonometrik oranlar/özdeşlikler (10.1.1) | 1 | tyt-matematik · matematik · matematik (3) | 134–136 · 233–252 · 149? | matematik.pdf çözümlü örnek | Orta (bölüm içi + mat3 ?) |
| MAT.10.1 GEOMETRİK ŞEKİLLER | Üçgende yardımcı elemanlar (10.1.2) | 1 | tyt-matematik · matematik · matematik (3) | 124–131 · 211–232 · 147?–153? | matematik.pdf çözümlü örnek | Orta (mat3 ?) |
| MAT.10.1 GEOMETRİK ŞEKİLLER | Üçgenin alanı (10.1.3) | 1 | tyt-matematik · matematik · matematik (3) | 137–138 · 253–272 · 153? | matematik.pdf çözümlü örnek | Orta (mat3 ?) |
| MAT.10.1 GEOMETRİK ŞEKİLLER | Sinüs/kosinüs teoremleri (10.1.4) | 1 | ayt-matematik? · matematik (2) | 39?–40? · 95 | mat(2) harf cevap | Orta (ayt ?) |
| MAT.10.2 İSTATİSTİKSEL ARAŞTIRMA SÜRECİ | İki kategorik değişken; ilişkililik kararı (10.2.1–10.2.2) | 2 | — | — | — | İnceleme gerekli (kategorik değişken 2018-erası kaynakta yok) |
| MAT.10.3 SAYILAR | Asal çarpanlar/bölenler; EBOB–EKOK; bölünebilme (10.3.1–10.3.3) | 3 | tyt-matematik · matematik · matematik (2) · matematik (3) | 17–25 · 65–80 (yalnız 10.3.3 bölünebilme; asal çarpan/EBOB–EKOK ➜ İnceleme gerekli) · 29 · 25?–26? | mat(2)/mat(3) harf cevap | Orta (mat3 ?; 10.3.1/10.3.2 bind yok) |
| MAT.10.4 NİCELİKLER VE DEĞİŞİMLER | Fonksiyon kavramı ve nitel özellikleri (10.4.1) | 4 | tyt-matematik · matematik · matematik (2) | 81–92 · 343–362 · 53–65 | matematik.pdf çözümlü örnek | Yüksek |
| MAT.10.4 NİCELİKLER VE DEĞİŞİMLER | Karesel referans fonksiyon + grafik (10.4.2) | 4 | ayt-matematik? · matematik | 13?–22? · 421–456 (yalnız 2. derece denklem kısmı; referans fonksiyon başlığı yok ➜ İnceleme gerekli) | ayt özet (çözüm yok) | İnceleme gerekli (referans yaklaşımı 2018'de yok; ayt sayfaları ?) |
| MAT.10.4 NİCELİKLER VE DEĞİŞİMLER | Karekök referans fonksiyon (10.4.3) | 4 | — | — | — | İnceleme gerekli |
| MAT.10.4 NİCELİKLER VE DEĞİŞİMLER | Rasyonel referans fonksiyon (10.4.4) | 4 | — | — | — | İnceleme gerekli |
| MAT.10.4 NİCELİKLER VE DEĞİŞİMLER | Ters fonksiyon (10.4.5) | 4 | tyt-matematik · matematik | 83, 91 · 363–388 (kesit, 11.3(3) ile paylaşım) | matematik.pdf çözümlü örnek | Orta (bölüm paylaşımı) |
| MAT.10.4 NİCELİKLER VE DEĞİŞİMLER | İkinci dereceden denklem/eşitsizlik problemleri (10.4.6) | 4 | tyt-matematik · matematik · matematik (2) | 102–106 · 421–456 · 35–41 | matematik.pdf çözümlü örnek | Yüksek |
| MAT.10.5 SAYMA, ALGORİTMA VE BİLİŞİM | Sayma stratejileri (10.5.1) | 5 | tyt-matematik · matematik · matematik (2) · matematik (3) | 69–77 · 303–328 · 65 · 113?–121? | matematik.pdf çözümlü örnek | Orta (mat3 ?) |
| MAT.10.5 SAYMA, ALGORİTMA VE BİLİŞİM | Algoritmik yapılandırma (10.5.2) | 5 | — | — | — | İnceleme gerekli |
| MAT.10.6 ANALİTİK İNCELEME | Noktanın ve doğrunun incelenmesi (10.6.1–10.6.2) | 6 | ayt-matematik? · matematik (1) · matematik (2) | 92?–99? · 67–498? · 155–167 | mat(2) harf cevap; mat(1) çözümlü örnek | Orta (ayt ?, mat1 bitiş ?) |
| MAT.10.7 VERİDEN OLASILIĞA | Koşullu olasılık; Bayes (10.7.1–10.7.2) | 7 | — | — (basit olaylar 329–342 yalnız MAT.9.7 kapsamındadır) | — | İnceleme gerekli (koşullu/Bayes için mevcut kaynakta karşılık yok) |

## 5. Sınıf 11 (TYMM 2026) Eşleme

| Resmî konu | Alt konu / kazanım | Öğr. sırası | İlgili PDF'ler | Sayfa aralıkları | Çözüm durumu | Eşleme güveni |
|---|---|---|---|---|---|---|
| MAT.11.1 İSTATİSTİKSEL ARAŞTIRMA SÜRECİ | İki nicel değişken; ilişkililik (11.1.1–11.1.2) | 1 | — | — (matematik.pdf 273–302 yalnız tek değişkenli; 11.1 kapsamına girmez) | — | İnceleme gerekli (korelasyon kaynağı yok) |
| MAT.11.2 GEOMETRİK ŞEKİLLER | Dörtgenler; özel dörtgenler; çokgenler (11.2.1–11.2.5) | 2 | tyt-matematik · matematik · matematik (3) | 139–151 · 457–524 · 158?–167? | matematik.pdf çözümlü örnek | Orta (mat3 ?) |
| MAT.11.3 NİCELİKLER VE DEĞİŞİMLER (1) | Trigonometrik referans fonksiyonlar; periyot/grafik; denklem problemleri (11.3.1–11.3.2) | 3 | ayt-matematik? · matematik · matematik (1) · matematik (2) | 30?–42? · — (matematik.pdf'te yönlü açı/trigonometrik fonksiyon/periyot bölümü yok) · 9–66 · 89–107 | mat(1) çözümlü örnek; mat(2) harf cevap | Orta (ayt ?; matematik.pdf bağ yok) |
| MAT.11.3 NİCELİKLER VE DEĞİŞİMLER (2) | Üstel fonksiyon; logaritma; üstel/log denklem (11.3.3–11.3.6) | 4 | ayt-matematik? · matematik · matematik (2) | 50?–61? · — (matematik.pdf'te üstel-log bölümü yok) · 71–77 | mat(2) harf cevap | Orta (ayt ?; matematik.pdf bağ yok) |
| MAT.11.3 NİCELİKLER VE DEĞİŞİMLER (3) | Fonksiyonların bileşkesi; dört işlem (11.3.7–11.3.8) | 5 | tyt-matematik · matematik | 90–91 · 363–388 (kesit; 10.4.5 ile paylaşım) | matematik.pdf çözümlü örnek | Orta (bölüm paylaşımı) |

## 6. Sınıf 12 (OGM 2018) Eşleme — 2026–27'de yürürlüktedir

| Resmî konu | Alt konu / kazanım | Öğr. sırası | İlgili PDF'ler | Sayfa aralıkları | Çözüm durumu | Eşleme güveni |
|---|---|---|---|---|---|---|
| 12.1 ÜSTEL VE LOGARİTMİK FONKSİYONLAR | Üstel fonksiyon; logaritma; üstel/log denklem-eşitsizlik | 1 | ayt-matematik? · matematik (2) | 50?–61? · 71–83 | mat(2) harf cevap | Orta (ayt ?) |
| 12.2 DİZİLER | Gerçek sayı dizileri (aritmetik/geometrik) | 2 | ayt-matematik? · matematik (2) | 62?–67? · 83–89 | mat(2) harf cevap | Orta (ayt ?) |
| 12.3 TRİGONOMETRİ | Toplam-fark / iki kat açı; trigonometrik denklemler | 3 | ayt-matematik? · matematik (2) | 45?–49? · 101–107 | mat(2) harf cevap | Orta (ayt ?) |
| 12.4 DÖNÜŞÜMLER | Analitik düzlemde temel dönüşümler | 4 | ayt-matematik? | 100? | ayt özet (çözüm yok) | Orta (tek kaynak ?) |
| 12.5 TÜREV | Limit-süreklilik; türev; türevin uygulamaları | 5 | ayt-matematik? · matematik (2) | 68?–86? · 119–131 | mat(2) harf cevap | Orta (ayt ?) |
| 12.6 İNTEGRAL | Belirsiz integral; belirli integral ve uygulamaları | 6 | ayt-matematik? · matematik (2) | 87?–91? · 143–149 | mat(2) harf cevap | Orta (ayt ?) |
| 12.7 ANALİTİK GEOMETRİ | Çemberin analitik incelenmesi | 7 | ayt-matematik? · matematik (1) | 126?–127? · 499–522 | mat(1) çözümlü örnek | Orta (ayt ?) |

## 7. Fark ve Kapsam Notları (TYMM 2026 ↔ 2018-erası kaynak)

- `matematik.pdf` içindekiler tablosunun tamamı §2'ye işlenmiştir (başlangıçlar doğrulanmış liste uyarınca);
  **525–552 (Katı Cisimler) hariç her bölümün ya resmî karşılığı bağlanmıştır ya da nedeniyle İnceleme gerekli
  işaretlenmiştir**. Cevap Anahtarı 553'ten başlar (bağ yok).
- TYMM temaları **içerik çerçevesi** ile kaynak konularına büyük ölçüde karşılık gelir ancak **başlık adları ve
  sıralama farklıdır**; "9.1 SAYILAR içinde mantık/küme" gibi yapısal kaymalar vardır (§2 bind'inde görülür).
- TYMM'ye özgü, mevcut 6 PDF'te **karşılığı olmayan** başlıklar: MAT.9.6'nın bazı alt kavramları hariç
  istatistiksel araştırma sürecinin iki değişkenli aşamaları (10.2/11.1), 9.5.1/10.5.2 algoritma-bilişim
  bileşenleri, 10.7 Bayes+koşullu olasılık, 10.4.2–10.4.4 referans fonksiyon (karesel/karekök/rasyonel)
  yaklaşımı → hepsi İnceleme gerekli.
- `?` işaretli hücreler görsel doğrulama ister (ayt-matematik.pdf İçindekiler glyph bozukluğu; mat(3) sayfa
  tokenları; mat(1) uzun bölüm bitişleri 498?); bu hücreler doğrulanmadan içerik üretiminde kullanılmaz.
- Sayfa doğrulama notu: §2 başlangıçları (9, 25, 37, 53, 65, 81, 109, 125, 167, 181, 211, 233, 253, 273, 287,
  303, 329, 343, 363, 389, 403, 421, 457, 477, 525, 553) kullanıcı doğrulamalı İçindekiler'den alındı;
  **525 = Katı Cisimler, 553 = Cevap Anahtarı** başlangıçlarıdır.
- 12. sınıf 2018 eşlemesi, aynı konular TYMM 11.3(2)/(3) ve 10.6'da tekrar göründüğü için (logaritma, bileşke,
  analitik) kaynak PDF'ler paylaşımlıdır.

## 8. Çözüm Durumu ve Çözüm Üretimi İlkesi

| Kaynak | Çözümlü örnek | Cevap anahtarı | Açıklama |
|---|---|---|---|
| `tyt-matematik.pdf` / `ayt-matematik.pdf` | yok (yalnız özet) | yok | konu özeti, görsel ağırlıklı |
| `matematik.pdf` | var (iç sayfalarda) | 553–? (harf) | TYT konu anlatımı + testler |
| `matematik (1).pdf` | var (test düzeni) | 523–528 (harf) | AYT pekiştirme testleri |
| `matematik (2).pdf` | yok | 209–212 (harf) | AYT test kitabı |
| `matematik (3).pdf` | yok | 215–218 (harf) | TYT test + Çıkmış 2018/2020/2021 (213–214) |

Tüm cevap anahtarları harf tablosudur (açıklama metni yok). Kaynaklarda görünen çözümlü örnekler/soru pasajları
**doğrudan türetme/kopyalama kaynağı değildir**: çözümler bağımsız üretilir, müfredattaki öğrenme çıktısına göre
doğrulanır; kaynak fişlemesi için `question_sources` + `question_source_locations` alanları kullanılabilir
(altyapı hazırdır, bu raporda kod/DB değişikliği yoktur).