\# 059 — Annual Curriculum, Inventory and Competition Pack Rules



\## Temel planlama



\- Yıl başlamadan bütün soru kasaları hazırlanacak.

\- Haftalık ders temel stok hedefi öğrenci sayısından bağımsız olacak.

\- Başlangıç minimumu ders/hafta için 300 soru.

\- Öğrenci başına ders/hafta yeni soru üst sınırı 500.

\- Competition/1v1 kasaları maksimum 5 soru.

\- Kolay/orta/zor geçiş puanları değiştirilmeyecek.

\- Mevcut `leagues` ve `league\_transition\_rules` tabloları kullanılacak.



\## Müfredat ve sorulabilirlik



\- Konu/kazanım müfredatta işlenmeden o soru öğrenciye sorulamaz.

\- Farklı okul veya kurumların konu işleme sıraları desteklenmeli.

\- Varsayılan MEB planı bulunmalı.

\- Okul/kurum profili aynı kazanımı farklı haftalarda açabilmeli.

\- Soru seçimi sırasında müfredat uygunluğu tekrar doğrulanmalı.



\## Competition / 1v1 kasa modeli



\- Mevcut `question\_vaults` büyük akademik soru havuzlarını temsil etmeye devam etmeli.

\- 5 soruluk yarışma kasaları `question\_vaults` yapısının yerine geçmemeli.

\- Bunlar büyük havuzların üzerinde hızlı seçim/paket katmanı olmalı.

\- Her competition/1v1 kasası maksimum 5 soru taşımalı.

\- İki öğrenci yarışırken öncelikle ikisinin de hiç görmediği ortak 5 soruluk kasa seçilmeli.

\- Tamamen ortak çözülmemiş kasa yoksa ikisinin de görmediği yeterli soru bulunan uygun kasa değerlendirilmeli.

\- Yarışma başladıktan sonra seçilen 5 soru snapshot olarak kilitlenmeli.

\- Aynı yarışmadaki iki öğrenci aynı soruları çözmeli.

\- Her yarışmada bütün `questions` tablosunu tarayan bir sistem kurulmayacak.



\## Performans



Soru seçim sırası:



1\. eğitim yılı / müfredat profili

2\. sınıf

3\. ders

4\. hafta

5\. sorulabilir konu ve kazanımlar

6\. lig / zorluk seviyesi

7\. kullanım eligibility

8\. uygun hazır kasalar

9\. iki öğrencinin ortak görmediği kasalar

10\. ortak görülmemiş sorular

11\. yarışma snapshot



\- `student/question` exposure kayıtları indeksli olmalı.

\- `student/pack` exposure kayıtları indeksli olmalı.

\- Haftalık 500 sınırı için her istekte `COUNT(\*)` yapılmamalı.

\- Öğrenci + eğitim yılı + hafta + ders bazında hızlı sayaç/özet tutulmalı.

\- Performans kritik sorgular küçük aday havuzlarında çalışmalı.



\## Haftalık stok



\- Soru stok ihtiyacının ana belirleyicisi öğrenci sayısı değildir.

\- Ders/hafta için başlangıç temel minimumu 300 sorudur.

\- 300 soru, 5 soruluk paketlerde teorik olarak 60 kasa anlamına gelebilir.

\- Kolay/orta/zor dağılımı mevcut lig ve zorluk kurallarına göre ayrıca planlanmalıdır.

\- 500 toplam kasa kapasitesi değildir.

\- 500 öğrenci başına ders/hafta yeni benzersiz soru tüketim üst sınırıdır.

\- Öğrenci 500. yeni soruya ulaştığında o ders için o haftaki yeni soru akışı durmalıdır.

\- Geçmiş yanlış, boş ve tekrar sorularının analizi/erişimi devam edebilir.



\## Operasyonel stok artırımı



\- 057 kullanıcı sayısına dayalı demand formülü yıllık temel stok belirleyicisi olarak kullanılmayacak.

\- Kullanıcı sayısı daha sonra operasyonel bir sinyal olabilir.

\- Tekrar oranı operasyonel bir sinyal olabilir.

\- En ileri öğrencinin soru tüketimi operasyonel bir sinyal olabilir.

\- Ortak görülmemiş stok miktarı operasyonel bir sinyal olabilir.

\- Aylık değerlendirmelerde ek üretim önerileri oluşturulabilir.

\- En ileri öğrencinin kullanılmamış soru rezervi kritik seviyeye düşerse erken stok alarmı oluşturulabilir.

\- Bu alarm AI üretimini otomatik başlatamaz.

\- Ek üretim için insan onayı gerekir.



\## Antrenman Sahası



\- Antrenman Sahası stoğu normal haftalık competition/1v1 stoğundan ayrı tutulmalı.

\- Sorular konu/kazanım bazında tutulmalı.

\- Öğretim sırasına göre açılmalı.

\- Önceden işlenmiş konular tekrar çalışılabilmeli.

\- Antrenman soruları haftanın geçmesiyle zorunlu olarak kapanmamalı.

\- Öğrenciye bireysel çalışma amacıyla kullanılabilmeli.



\## Ödüllü yarışmalar



\- Ödüllü yarışma stoğu normal haftalık stoktan ayrı tutulmalı.

\- Normal competition eligibility ile ödüllü yarışma eligibility aynı kabul edilmemeli.

\- Daha sıkı kalite ve insan onayı uygulanabilmeli.



\## Soru üretim paketi



AI tarafından üretilen soru yalnız soru metninden oluşmamalı.



Her soru mümkün olduğunca şu bilgileri taşımalı:



\- soru metni

\- seçenekler

\- doğru cevap

\- ayrıntılı çözüm

\- kısa çözüm

\- mümkünse alternatif çözüm

\- sınıf

\- ders

\- konu

\- alt konu

\- kazanım

\- zorluk

\- bilişsel düzey

\- soru tipi

\- yeni nesil bilgisi

\- tahmini çözüm süresi

\- gerekli görseller

\- video çözüm senaryosu / storyboard

\- video üretim durumu

\- kalite kontrolleri

\- akademik doğrulama bilgileri



Mevcut `question\_solution\_assets` ve `question\_assets` altyapısı mümkün olduğunca yeniden kullanılmalı.



\## AI ve insan onayı



AI hiçbir soruyu doğrudan production'a veya yarışma kasasına yayınlayamaz.



Akış:



Demand / yıllık stok açığı

→ üretim önerisi

→ insan üretim onayı

→ AI üretimi

→ akademik kontroller

→ kalite kontrolleri

→ benzerlik/duplicate kontrolü

→ insan nihai onayı

→ production

→ deterministic kasa yerleştirme

→ stok tekrar hesaplama



İki ayrı insan kapısı korunmalı:



1\. üretim ihtiyacının onayı

2\. üretilen sorunun yayın onayı



\## Canonical question



\- Aynı canonical soru gerektiğinde birden fazla uygun havuza bağlanabilmeli.

\- Aynı soru sırf farklı kasa için kopyalanmamalı.

\- Vault membership/pack membership ilişkileri kullanılmalı.



\## Öğrenci analizi



Öğrenci çözüm geçmişi en az şu boyutlarda analiz edilebilmeli:



\- ders

\- konu

\- alt konu

\- kazanım

\- zorluk

\- bilişsel düzey

\- soru tipi

\- doğru

\- yanlış

\- boş

\- çözüm süresi

\- tekrar performansı



Bu veriler daha sonra:



\- güçlü konular

\- zayıf konular

\- eksik kazanımlar

\- zorluk seviyesi performansı

\- soru tipi performansı

\- bireyselleştirilmiş çalışma önerisi

\- öğrenci gelişim raporu



üretmek için kullanılacak.



AI öğrenci tavsiyesini ham veriden kafasına göre oluşturmamalı.

Önce deterministic/analitik metrikler hesaplanmalı, AI bunları anlaşılır çalışma tavsiyesine dönüştürmeli.



\## Mevcut sistemi yeniden kullan



Yeni migration mevcut şemayı tekrar oluşturmamalı.



Özellikle mümkün olduğunca yeniden kullanılacak yapılar:



\- `curriculum\_versions`

\- `curriculum\_outcomes`

\- `curriculum\_prerequisites`

\- `question\_curriculum\_mappings`

\- `question\_outcome\_mappings`

\- `leagues`

\- `league\_rule\_sets`

\- `league\_transition\_rules`

\- `student\_league\_memberships`

\- `question\_vaults`

\- `question\_vault\_memberships`

\- `question\_vault\_topics`

\- `question\_vault\_rules`

\- `question\_vault\_activation\_windows`

\- `question\_assets`

\- `question\_solution\_assets`

\- `question\_pool\_targets`

\- `question\_pool\_gap\_results`

\- `question\_generation\_requests`

\- mevcut AI review/promotion altyapısı



\## Migration 059



\- Migration numarası `059` olacak.

\- Önce mimari plan hazırlanacak.

\- Architect migration dosyasını yazmayacak.

\- Migration dosyasına aynı anda yalnız Database ajanı dokunacak.

\- Database ajanından sonra Security ve Reality Checker read-only review yapacak.

\- Son olarak Code Reviewer diff'i inceleyecek.

