# ALTIN KALEMLER — OPENCODE ANA PROJE SÖZLEŞMESİ VE FAZ PLANI

Sürüm: 1.0
Tarih: 3 Eylül 2026
Durum: Puanlama V1 görevinden sonraki çalışmalar için ana yol haritası

> BU DOSYA ZORUNLU OTURUM SÖZLEŞMESİDİR. Proje `AGENTS.md` içindeki
> `ALTIN-KALEMLER-ANA-SOZLESME` bloğu her oturumun başında bu dosyanın
> okunmasını ve uygulanmasını zorunlu kılar.

## 1. Nihai hedef

Altın Kalemler; Türkiye'deki öğrenciler için Türkçe, güvenli, oyunlaştırılmış ve müfredata bağlı bir matematik öğrenme platformudur.

Nihai öğrenci döngüsü:

1. Kayıt ve güvenli giriş
2. Öğrencinin kayıtlı sınıfının belirlenmesi
3. Yalnız kendi sınıfına ait ders, konu ve kazanımları görmesi
4. Tanılama ve uygun soru seçimi
5. On soruluk matematik antrenmanı
6. Doğru/yanlış geri bildirimi
7. Öğretmen/alan uzmanı tarafından onaylanmış çözüm ve hata açıklaması
8. Zayıf kazanımlara göre hedefli tekrar
9. Kazanım ilerlemesinin ölçülmesi
10. En fazla beş soruluk rekabetçi bilgi yarışması
11. Sunucu tarafından hesaplanan yarışma puanı
12. Aynı sınıf düzeyindeki öğrencilerden oluşan lig ve sıralama
13. XP, kişisel seviye, seri, rozet ve güvenli ödül ekonomisi
14. Harcanabilir yıldız/puan, mağaza, envanter ve avatar özelleştirme
15. Öğrencinin gelişimini anlaşılır ve motive edici biçimde izlemesi

Platformun ilk sürümü yalnız öğrenci ürünüdür. İçerik ve sistem yönetimi için gerekli admin ekranları bulunur; öğretmen, veli, okul paneli ve B2B okul yönetimi bulunmaz.

## 2. Değişmez ürün kapsamı

Bu kurallar kullanıcı tarafından açıkça değiştirilmedikçe kalıcıdır:

- Pazar: Türkiye.
- Dil: Türkçe.
- İlk ders: Matematik.
- Kullanıcı deneyimi: Öğrenci.
- Yönetim deneyimi: Yalnız içerik ve sistem yönetimi için gerekli admin paneli.
- Öğretmen paneli yok.
- Veli paneli yok.
- Okul paneli ve okul sıralaması yok.
- B2B okul yönetimi yok.
- Almanya yerelleştirmesi ve ek pazarlar, ancak hibe onayından sonra ayrı kararla değerlendirilir.
- İlkokul kapsamı; çocuk güvenliği, veli izni ve veri koruma süreçleri tamamlanmadan yayımlanmaz.
- Hazır olmayan sınıf, ders, konu veya kazanım için "İçerikler hazırlanıyor" durumu gösterilir.
- Yapay zekâ tarafından üretilen soru veya çözüm doğrudan yayımlanmaz.
- İçerik zinciri: müfredat kazanımı → AI destekli taslak → otomatik kontroller → öğretmen/alan uzmanı denetimi → onay → yayın.

## 3. Sınıf, öğrenci görünürlüğü ve lig kuralları

- Öğrenci yalnız `student_profiles.grade_level` değerindeki kendi sınıfına ait eğitim içeriğini görür.
- Öğrenci antrenman ekranından sınıf seçemez veya değiştiremez.
- Öğrenci başka sınıfların ders, konu, kazanım veya sorularını göremez.
- Öğrenci başka sınıflardaki öğrencilerin profilini, sıralamasını, ligini veya arkadaş bilgisini göremez.
- Öğrenci yalnız kendi sınıf düzeyindeki öğrencilerin izin verilen halka açık lig/sıralama bilgilerini görebilir.
- "Sınıf", "kişisel seviye" ve "lig" ayrı kavramlardır.
- Örnek: `7. Sınıf` müfredat kapsamıdır; `Seviye 12` kişisel gelişimdir; `Altın Lig` rekabet grubudur.
- Ligler aynı `grade_level` içinde çalışır.
- Lig/sıralama sonuçlarında gerçek ad yerine güvenli takma ad ve izin verilen avatar tercih edilir.
- Gereksiz kişisel veri, okul bilgisi, iletişim bilgisi veya konum gösterilmez.

## 4. Oyun değerlerinin ayrılması

Sistem aşağıdaki değerleri birbirine karıştırmaz:

| Değer | Amaç | Harcanabilir mi? |
|---|---|---|
| Yarışma performans puanı | Beş soruluk yarışmadaki başarı | Hayır |
| Lig rating puanı | Lig sırası, yükselme ve düşme | Hayır |
| XP | Kişisel seviye ilerlemesi | Hayır |
| Yıldız/ödül parası | Mağaza ve kozmetik ürünler | Evet |
| Rozet | Başarım göstergesi | Hayır |
| Seri | Düzenli çalışma motivasyonu | Hayır |

Kalıcı kurallar:

- Yarışma puanı istemciden alınmaz; sunucu hesaplar.
- Doğru cevap, zorluk ve süre bandı yarışma puanını belirler.
- Yanlış, pas ve timeout negatif puan üretmez; V1'de sıfırdır.
- Lig rating'i mevcut sözleşmedeki kazanma `+24`, kaybetme `−12`, beraberlik `0` değerlerinden bağımsız ürün kararı olmadan değiştirilmez.
- XP, yarışma puanıyla aynı alan veya tablo değildir.
- Harcanabilir bakiye, yarışma toplam puanı değildir.
- Bakiye değişimleri yalnız sunucu-otoriter, atomik ve idempotent işlemle yapılır.
- Öğrenci doğrudan cüzdan, ledger, envanter veya satın alma tablosuna yazamaz.
- Ödül ekonomisi kurulmadan arayüzde sahte bakiye, sahte satın alma veya sahte mağaza gösterilmez.

## 5. Sürekli çalışma ve güvenlik kuralları

Her fazda aşağıdaki çalışma sözleşmesi geçerlidir.

### 5.1 Başlangıç gerçeklik kontrolü

Her yeni fazın ilk adımı salt okunur kontroldür:

- Aktif branch
- Yerel HEAD tam hash
- `origin/main` tam hash
- Ahead/behind
- Staged alan
- `git status --short`
- Kullanıcıya ait modified/untracked dosyalar
- Aktif Git hook durumu
- Son CI çalışmasının SHA, status ve sonucu
- Codebase-memory indeks durumu

Rapor hashlerini güncel gerçeklik gibi varsayma. Gerçek Git durumu esas alınır.

### 5.2 Çalışma ağacı

- Kullanıcıya ait kirli çalışma ağacını koru.
- İlgisiz dosyayı değiştirme, silme, taşıma, stage veya commit etme.
- `AGENTS.md`, `README.md`, `opencode.json`, `.cbmignore`, `.opencode/plugins/**` ve kullanıcıya ait untracked dosyalar açık görev kapsamı olmadıkça dokunulmazdır.
- `git reset`, `clean`, `restore`, `checkout`, `rebase`, `commit --amend` ve force-push yasaktır.

### 5.3 Git işlemleri

- Her faz küçük ve mantıksal olarak tek bir yerel commit üretir.
- Yerel commit yalnız bütün faz kontrolleri yeşilse oluşturulur.
- Committen önce staged dosya listesi ve `git diff --cached --check` doğrulanır.
- Aktif otomatik push hook'u oluşturulmaz.
- Bu ana plan gelecekteki pushlar için sürekli izin değildir.
- Her faz raporundan sonra normal push için kullanıcıdan açık izin alınır.
- Push izni verilirse yalnız `git push origin main` kullanılabilir.
- Force-push hiçbir koşulda yapılmaz.
- Push sonrası aynı SHA için CI `completed/success` olmadan faz uzak ortamda tamamlandı sayılmaz.

### 5.4 Veritabanı

- Hosted/production Supabase'e kullanıcıdan işlem anında açık izin almadan bağlanma veya migration uygulama.
- Ana local stack üzerinde `supabase db reset` çalıştırma.
- `qa-iso19` veya mevcut başka stack'i değiştirme.
- Gerçek DB QA için benzersiz adlı, benzersiz portlu, ayrı geçici dizinli disposable ortam kullan.
- Başlangıç ve bitiş Docker envanterini karşılaştır.
- Yalnız bu görevde oluşturulduğu kesin kanıtlanan geçici kaynakları temizle.
- `docker system prune` ve `docker volume prune` yasaktır.
- Migration'lar append-only ilerler; eski migration değiştirilmez.
- Her yeni migration idempotentlik, RLS, grant/revoke, transaction ve rollback açısından test edilir.

### 5.5 Gizli bilgi ve veri

- `.env`, token, parola, API anahtarı, sertifika veya production bağlantısı okunmaz.
- CLI çıktısında anahtar/token oluşursa kullanıcı raporuna kopyalanmaz.
- Testlerde yalnız sahte ve deterministik fixture kullanılır.
- Gerçek öğrenci verisi testlerde kullanılmaz.
- Ham DB hatası, internal ID, doğru cevap veya hassas payload öğrenci UI'ına sızdırılmaz.

### 5.6 Kod ve mimari

- Önce codebase-memory ile sembol, bağımlılık ve çağrı zinciri keşfi yap; sonra yalnız gerekli dosyaları oku.
- İndeks kullanılamıyorsa bunu bildir ve doğrudan kaynakla doğrula.
- Büyük yeniden yazım yerine en küçük güvenli değişikliği tercih et.
- Yeni paket yalnız mevcut araçlarla çözülemeyen açık ihtiyaç varsa ve kullanıcı onaylarsa eklenir.
- Test beklentileri gevşetilmez, skip eklenmez ve hata saklanmaz.
- Aynı hata için en fazla üç kontrollü düzeltme denemesi yapılır.
- Üç denemede çözülemeyen sorun `BLOCKED` olarak raporlanır.

### 5.7 UI ve erişilebilirlik

- Bütün öğrenci metinleri doğal Türkçe olmalıdır; ASCII Türkçesi kullanılmaz.
- `html lang="tr"` korunur.
- Klavye erişimi, görünür focus, doğru label, `aria-live`, hata/başarı durumu ve en az 44×44 dokunma hedefi sağlanır.
- Renk tek başına anlam taşımaz; ikon ve metinle desteklenir.
- Mobil 375×812, tablet 768×1024 ve masaüstü 1440×900 doğrulanır.
- Koyu tema tamamlanmadıkça tema seçici gösterilmez.
- Yükleniyor, boş, hata, bağlantı kesildi ve "İçerikler hazırlanıyor" durumları tasarlanır.
- Sahte çalışır düğme bırakılmaz. İşlevsiz özellik ya kaldırılır ya açıkça "yakında" olarak pasif gösterilir.

### 5.8 Emergent prototipi

- Emergent yalnız görsel/etkileşim referansıdır; kod ve veri kaynağı değildir.
- Emergent'e GitHub, Supabase, production, secret veya gerçek öğrenci verisi bağlanmaz.
- Emergent'in sabit `100 puan`, `+20 XP`, sınıf sekmeleri, okul sıralaması ve sahte kullanıcı verileri gerçek ürüne aktarılmaz.
- Onaylanan görsel parçalar mevcut Next.js mimarisinde yeniden ve testli uygulanır.

## 6. Faz yürütme protokolü

- Bir OpenCode oturumunda yalnız bir numaralı faz uygulanır.
- Faz içindeki alt adımlar birlikte tamamlanabilir.
- Faz tamamlanınca nihai rapor verilir ve durulur.
- Bir sonraki faza kullanıcı "devam" veya açık görev onayı vermeden geçilmez.
- Bağımsız bir sonraki faz önerilebilir ancak uygulanmaz.
- Faz `BLOCKED` olursa dosya commit/push edilmez.
- Faz `PARTIAL_SUCCESS` olursa başarılı ve eksik alanlar ayrı raporlanır; otomatik kapsam genişletilmez.
- Kota uyarısı gelirse güvenli noktada durulur; yarım değişiklik commit/push edilmez.

## 7. İçerik üretimi ve denetiminde toplu iş kararı (ek kapsam, 14 Eylül 2026)

Bu madde önceki madde hükümlerine EK'tir; hiçbir önceki maddeyi daraltmaz
veya değiştirmez.

- Temel kullanıcı akışı korunur: kullanıcı her soruyu tek tek çözmez veya
  ayrı ayrı onaylamaz.
- Üretilen/aktarılan TÜM sorular sistem + bağımsız AI denetimlerinden
  geçer; denetim, soru bazında tek tek "insan çözümü" ile yapılmaz.
- Sorunsuz sorular ÖZET RAPOR ile TOPLU yayın onayına gider.
- Şüpheli/çelişkili sorular GEREKÇELİ olarak inceleme kuyruğuna gider.
- Açık hatalar ve çalışmamış zorunlu kontroller yayını BLOKE eder
  (fail-closed); eksik/çelişkili içerik sessizce yayımlanmaz.
- İki ayrı onay korunur ve birbirinin yerine geçmez:
  1) Üretim ihtiyacı onayı (talep onayı; onaysız talep üretime alınmaz),
  2) Nihai yayın onayı (toplu yayın onayı; denetimlerin tümü yeşil ve
     zorunlu kapıların hepsi çalışmış olmadan toplu yayın onayı verilemez).
- Bu karar, denetçi sayısı/model/eşik/tekrar sayısı gibi somut parametreleri
  SABİTLEMEZ; bu değerler ürün kararıyla ayrıca belirlenir ve uydurulmaz.
- Yazılı çözüm ve video üretimi (ek kapsam) bu toplu iş akışına aynı
  kapılar üzerinden bağlanır; yapılandırılmamış üretim asla başarılı
  gösterilmez.

## 8. Faz 16 — Admin İçerik Operasyon Merkezi

Değişiklik günü: 18 Eylül 2026
Durum: PLANLANDI — BAŞLANMADI

> Not (Faz 16A): Faz 16A yalnız soru ÖNİZLEME pilotudur; gerçek soru
> intake'ı veya yayını içermez. Gerçek alım ve yayın akışı bu fazın
> ilgili alt adımlarının kapanışıyla mümkün olur.

Sıralama, bağımlılıklar ve kabul koşulları:

- **P0.0 — CI/migration paritesi (ön koşul):** `110_faz15_training_gating.sql`
  commitli zincire alınmadan öğretmen konu-açma UI'ı yapılmaz.
  Kabul: temiz reset, types, QA ve CI; zincir 110 dahil yeşil.
- **P0.1 — Öğretmen konu açma:** `/admin/curriculum-teaching`.
  Ortak layout kapısı `questions.view` korunur; işlem ayrıca
  `curriculum.manage` RPC kapısından geçer.
- **P0 — İşleyen soruda değişiklik kapısı:** yayındaki/aktif soruda
  metin, şık veya doğru cevap değişirse soru OTOMATİK pasife alınır ve
  YENİDEN DENETİM gerektirir; aktif kalıp denetim zincirini atlayamaz.
- **P0 — Yetki matrisi ve acil yetki kaldırma:** admin yetki matrisi
  kayıtlı ve sürümlüdür; acil yetki kaldırma prosedürü tanımlıdır
  (hızlı, iz bırakan, geri dönüşü denetlenebilir kaldırma).
- **P1 — Aday paket operasyon merkezi:** paket listesi/detayı,
  staging önizlemesi, AI gate sonuçları ve blok gerekçeleri.
  Bağımlılık: aday batch altyapısı (117/118); kabul: hiçbir paket
  doğrudan production'a yazamaz.
- **P1 — Üretim/denetim işlem durumu:** paket aşaması, `waiting_*`
  gate'leri, provider hatası ve güvenli yeniden deneme görünümü.
  API anahtarı UI'da ASLA görünmez.
- **P2 — Review queue ve insan kararları:** önceliklendirme ve
  onay/ret/revizyon gerekçeleri. Bağımlılık: insan karar RPC'si
  (047/090); kabul: kararlar yalnız `human_review_required` durumunda.
- **P2 — İnceleme atama ve dört-göz kuralı:** atama, öncelik ve
  gerekçe kaydı zorunludur; aynı kişi kendi işlediği adayı TEK BAŞINA
  onaylayamaz.
- **P3 — Promotion yönetimi:** insan onayı ve readiness olmadan
  promotion/yayın yapılamaz; yayın ayrı bir aktivasyon adımıdır.
  Kabul: `approved` karar + `check_question_activation_readiness`
  PASS şartı; aktivasyon ayrı `question_publication_events` kaydı.
- **P3 — Sürümleme, geri çekme ve arşiv:** fiziksel silme yerine
  izlenebilir geri çekme (sürümlü, denetim kayıtlı, arşivde tutulan).
- **P4 — Kasa yönetimi:** kasa, konu, üyelik, aktivasyon penceresi ve
  stok. Kabul: öğrenci seçim kapsamı yalnız aktif + şartlı üyeliklerden.
- **P4 — Kapsam doğrulaması:** öğretmen konu-açma onayının okul/sınıf/
  şube/profil kapsamı uygulanmadan ÖNCE doğrulanır. (Not: madde 2'ye
  göre okul YÖNETİM PANELİ yoktur; doğrulama mevcut ürün alanlarıyla —
  sınıf/seviye, şube, profil, yıl + takvim öğesi — sınırlıdır.)
- **P5 — Soru ayrıntıları:** çözüm, medya, kaynak/provenance ve kazanım
  eşlemesi.
- **P5 — Provenance ve özgünlük:** kaynak/provenance, özgünlük/benzerlik
  bilgisi ve çözüm varlığı soru ayrıntısında GÖRÜNÜR.
- **P6 — İçerik kapsam raporları.**
- **P6 — Stok ve uyarı raporu:** kazanım × zorluk × sınıf stok raporu;
  yüksek hata, anormal çözüm süresi ve benzerlik/tekrar uyarıları.
- **P7 — Kaynak PDF/fişleme UI.**
- **P8 — Yarışma yönetim paneli.**
- **P9 — Rol/izin yönetim UI.**
- **P10 — Operasyon sağlığı:** provider sağlık durumu, başarısız işler,
  kuyruk birikimi, audit/export ve yedekleme prosedürü.

Bu bölümdeki tüm maddeler (P0.0–P10 dâhil) PLANLANDI — BAŞLANMADI
durumundadır.

Çıkış koşulu:

- "Aday paket → AI gate → insan karar → promotion → kasa → öğretmen
  onayı → öğrenci erişimi" zincirinde doğrudan yayın yolu kalmaz;
  her aşama kendi kapısından geçer ve denetim kaydı yazar.
