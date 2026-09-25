# Faz 25 — Admin Candidate Etkileşim ve Yetki Kabul Testi

Tarih: 25 Eylül 2026
Ortam: `http://localhost:3000`
Test rolü: `question_reviewer`
Test hesabı: `mevcut yerel admin hesabı`
Görünümler: `1440×900`, `768×1024` ve `375×812`

## Kapsam ve güvenlik

Bu test yalnız mevcut yerel uygulamada, mevcut reviewer oturumuyla, anonim cookie’siz HTTP isteğiyle ve salt-okunur E2E navigasyonuyla yapıldı.

- Parola rapora yazılmadı veya okunmadı.
- Secret, `.env*`, API anahtarı veya oturum bilgisi dosyası okunmadı.
- Kod dışında migration, rol, kullanıcı, aday verisi, karar durumu veya DB değiştirilmedi.
- `İncelemeyi Onayla`, `Düzeltmeye Gönder` ve `Reddet` düğmelerine tıklanmadı.
- Publish, approval, reject, intake, commit ve push yapılmadı.
- Yerel Next sunucusu açık bırakıldı.

## Gözlenen veri

- Candidate batch listesinde 2 paket görünüyor.
- İlk paketin detayında 32 aday bulunuyor.
- Detay artık tüm adayları tek akışta render etmek yerine seçili adayı gösteriyor.
- Gerçek veride `candidateIndex` değerleri listede kesintisiz değil. İlk düzeltmede URL sırası bu alana bağlandığı için `?candidate=2` ikinci kaydı seçmedi; seçim artık RPC’nin sıralı döndürdüğü liste konumuna bağlandı ve test fixture’ında kesintili dizin örneği kullanıldı.
- Gerçek 32 adaylı batch’te `?candidate=2` çalışma anında `Aday 2 / 32`, `?candidate=32` çalışma anında `Aday 32 / 32` gösterdi.
- `question_reviewer` için admin menüsünde yalnız `Soru Bankası`, `Aday Soru Paketleri` ve `Öğretmen İncelemeleri` görünüyor.
- `Toplam kullanıcı` kartı ve `/admin/users` bağlantısı reviewer oturumunda görünmüyor.

## Test tablosu

| Test edilen bağlantı/aksiyon | Beklenen | Gözlenen | Sonuç | Hata sınıfı |
|---|---|---|---|---|
| Anonim `/admin` | Girişe yönlenmeli | Cookie’siz `HEAD /admin` isteği `307` ve `location: /login` döndü | PASS | YOK |
| Başarılı reviewer giriş yönlendirmesi | `questions.view` ve candidate yetkisi varsa candidate başlangıcına gitmeli | `questions.view + questions.approve` fixture’ı `/admin/candidate-batches` hedefini seçti | PASS | YOK |
| Öğrenci giriş yönlendirmesi | Candidate izni yoksa `/dashboard` olmalı | Öğrenci ve reviewer dışı izin fixture’ı `/dashboard` hedefini seçti | PASS | YOK |
| `questions.view` olmadan reviewer başlangıcı | Candidate başlangıcı açılmamalı | Eksik view izni fixture’ı `/dashboard` hedefini seçti | PASS | YOK |
| Doğrudan `/admin/candidate-batches` | Reviewer liste ekranını açabilmeli | 2 paket ve 2 görünür `İncele` aksiyonu açıldı | PASS | YOK |
| İlk batch `İncele` aksiyonu | 32 adaylı batch detayını açmalı | `9310097d…` detayı açıldı | PASS | `LABEL_DIFFERENCE` çözüldü |
| Detaydan listeye dönüş | Candidate listesine dönmeli | `/admin/candidate-batches` adresine dönüldü | PASS | YOK |
| Varsayılan aday | İlk aday görünmeli | `Aday 1 / 32`, `Aday #1`; önceki pasif, sonraki `?candidate=2` | PASS | YOK |
| Orta aday | URL sırasındaki kayıt seçilmeli | `?candidate=2` → `Aday 2 / 32`, `Aday #2`; önceki/sonraki URL’leri doğru | PASS | `CANDIDATE_POSITION` düzeltildi |
| Son aday | Son kayıt görünmeli, sonraki pasif olmalı | `?candidate=32` → `Aday 32 / 32`, `Aday #32`; sonraki pasif | PASS | YOK |
| Geçersiz aday sırası | Güvenli varsayılana dönülmeli | `0`, negatif, ondalık ve sınır dışı değerler testte ilk adaya döndü | PASS | YOK |
| Tekil aday render’ı | Yalnız seçili adayın karar ve içerik blokları görünmeli | 32 aday × 3 düğme yerine 1 aday × 3 pasif düğme göründü | PASS | YOK |
| `375×812` aday navigasyonu | Taşma olmamalı, kontroller ≥44px olmalı | Navigation kutusu `278px`; iki kontrol `44px` yükseklikte, yatay taşma yok | PASS | YOK |
| `768×1024` aday navigasyonu | Taşma olmamalı, kontroller ≥44px olmalı | Navigation kutusu `639px`; iki kontrol `44px` yükseklikte, yatay taşma yok | PASS | YOK |
| `1440×900` aday navigasyonu | Kontroller görünür ve çalışır olmalı | İlk, ikinci ve son aday geçişleri gerçek batch’te çalıştı | PASS | YOK |
| Pasif karar düğmeleri | `disabled` olmalı, yazmamalı | `İncelemeyi Onayla`, `Düzeltmeye Gönder`, `Reddet` tek adayda göründü ve üçü de pasifti | PASS | YOK |
| Candidate liste/detay sızıntısı | Öğrenci paneline yönlendirme olmamalı | Liste ve detay adresleri korundu; `/dashboard` yönlendirmesi görülmedi | PASS | YOK |
| Admin `Soru Bankası` bağlantısı | `questions.view` olan reviewer açabilmeli | `/admin/questions` açıldı | PASS | YOK |
| Admin `Aday Soru Paketleri` bağlantısı | Candidate yetkisi olan reviewer açabilmeli | `/admin/candidate-batches` açıldı | PASS | YOK |
| Admin `Öğretmen İncelemeleri` bağlantısı | `questions.view` olan reviewer açabilmeli | `/admin/teacher-reviews` açıldı; bekleyen inceleme yoktu | PASS | YOK |
| Yetkisiz admin bağlantıları | Menüde görünmemeli | Akademik takvim, kullanıcılar, konu onayı ve denetim bağlantıları 1440/768/375’te görünmedi | PASS | YOK |
| Kullanıcı özeti kartı | `users.manage` yoksa görünmemeli | `Toplam kullanıcı` kartı ve `countUsers()` çağrısı çalışmadı; kart görünmedi | PASS | YOK |
| Menü izin sorgu hatası | Yetki belirsizliğinde linkler gizlenmeli | Hata durumu fail-closed testi; linkler render edilmedi | PASS | YOK |
| Konsol | E2E akışında uygulama hatası olmamalı | Admin, candidate, question ve teacher-review gezinmelerinde 0 konsol hatası | PASS | YOK |

## A11y ve responsive kabul

- Navigation anlık görünür `role="status"` ve `aria-live="polite"` ile aday konumunu bildiriyor.
- Önceki/sonraki kontrollerin görünür metinleri kısa, erişilebilir adları “Önceki aday” ve “Sonraki aday”.
- İlk adayda önceki, son adayda sonraki kontrolü disabled.
- `375×812` ve `768×1024` ölçümlerde iki kontrolün yüksekliği `44px`.
- `375×812` admin menü sayfasında yatay taşma yok; yalnız üç yetkili bağlantı görünür.
- `768×1024` admin menüde yalnız üç yetkili bağlantı görünür.
- `1440×900` reviewer menüsünde yalnız üç yetkili bağlantı görünür.

## Otomatik kontroller

| Kontrol | Sonuç |
|---|---|
| `npm test -- --reporter=dot` | PASS — 70 dosya, 979 test |
| Hedefli login/admin/candidate Vitest | PASS — 3 dosya, 28 test |
| `npx tsc --noEmit` | PASS |
| Değiştirilen 7 dosyaya yönelik `npx eslint ...` | PASS |
| Repo geneli `npm run lint` | BLOCKED — görev dışı `pdfprobe.js` ve `pdftext.js` dosyalarında `@typescript-eslint/no-require-imports` |
| Canlı öğrenci giriş E2E | NOT RUN — credential okunmadı; yönlendirme otomatik testle doğrulandı |

## Kaynak ve kapsam kanıtı

- Login reviewer yönlendirmesi ve üç paralel izin sorgusu: `src/app/(auth)/login/page.tsx:18-35`, çağrı `:74`.
- Login regresyon testleri: `src/app/(auth)/login/page.test.tsx:58-124`.
- Admin route izin haritası: `src/app/(admin)/admin/page.tsx:23-39`.
- İzin kodlarının toplanması ve paralel sorgusu: `src/app/(admin)/admin/page.tsx:64-84`.
- Menü fail-closed filtresi: `src/app/(admin)/admin/page.tsx:91-92`.
- Kullanıcı kartının koşullu çağrısı/render’ı: `src/app/(admin)/admin/page.tsx:94-99`, `:131-149`; menü render’ı `:159-179`.
- Candidate liste konum çözümü: `src/app/(admin)/admin/candidate-batches/[id]/page.tsx:46-63`.
- Aday navigasyonu ve a11y: `src/app/(admin)/admin/candidate-batches/[id]/page.tsx:70-119`.
- Seçili adayın tekil render’ı: `src/app/(admin)/admin/candidate-batches/[id]/page.tsx:827-844`.
- Next.js Promise tabanlı `searchParams` okuma: `src/app/(admin)/admin/candidate-batches/[id]/page.tsx:864-868`, `:926-930`.
- Kaynak dizinin RPC’de sıralanması: `supabase/migrations/126_faz24_admin_candidate_review_low_confidence.sql:121-127`.
- DTO `candidate_index` eşlemesi: `src/lib/admin/candidate-batches.ts:597-603`.
- Ortak admin auth ve `questions.view` koruması: `src/app/(admin)/layout.tsx:24-59`.

## Sınıflandırma

1. **Candidate navigation:** İlk gerçek veri denemesinde kesintili `candidateIndex` nedeniyle 2. ve 32. kayda yanlış konum seçildi. Seçim RPC’nin döndürdüğü sıralı liste konumuna çevrildi, kesintili fixture eklendi ve gerçek 32 kayıt üzerinde ilk/orta/son sınırları geçti.
2. **Server-side authorization:** Reviewer yalnız `questions.view` taşısa da ortak admin koruması nedeniyle `/admin` açıldı. Menü artık aynı layout kapısına rağmen candidate yetkisi olmayan kullanıcıya `/dashboard` yönlendirmesini öneriyor; backend erişim bypass’ı gözlenmedi.
3. **Navigation permission gap:** Yedi route’un tamamı tek role değil, gerçek izinlerine göre filtreleniyor. Reviewer’da üç bağlantı görünür; `users.manage` yoksa kullanıcı kartı ve bağlantısı hiç render edilmiyor.
4. **Otomatik kapı:** Tüm Vitest, TypeScript ve değişen dosyaların ESLint kontrolü geçti. Repo geneli lint, kapsam dışı iki kök dosyadaki require import hataları nedeniyle yeşil değil.

## Nihai kararlar

CANDIDATE_REVIEW_NAVIGATION: PASS

ADMIN_NAVIGATION_PERMISSION_GAP: NO

REVIEWER_RESPONSIVE_E2E: PASS

OVERALL_STATUS: PARTIAL_SUCCESS

Partial gerekçesi: görev kapsamındaki kod, hedefli testler, tam test, typecheck, scoped lint ve reviewer/anonymous kabul kontrolleri geçti; ancak repo geneli lint iki görev dışı dosya nedeniyle yeşil değil ve canlı öğrenci credential’ı okunmadığı için öğrenci girişi yeniden E2E çalıştırılmadı.
