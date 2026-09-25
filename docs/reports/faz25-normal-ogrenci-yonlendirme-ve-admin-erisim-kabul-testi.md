# Faz 25 — İzole Öğrenci Test Fixture'ları ve Canlı E2E

- Tarih: 2026-09-25
- Kapsam: Yalnız iki yeni local Supabase öğrenci fixture hesabı ve normal öğrenci/admin erişim regresyonu.
- Sonuç: **BLOCKED**
- `NORMAL_STUDENT_REGRESSION: BLOCKED`
- `SAFE_FOR_LOCAL_COMMIT: NO`
- `SAFE_FOR_PUSH: NO`

## Sonuç özeti

Çakışma ön kontrolü iki hedef adres için sıfır kayıt döndürdü. Üç kontrollü local transaction denemesi de tam rollback oldu; assertion aşamasındaki son deneme `step=assertions`, `SQLSTATE P0001` ile sonlandı. Post-rollback salt-okunur kontrolde iki hedef için `auth.users`, `auth.identities`, `public.student_profiles` ve `admin_user_roles` sayıları sıfırdır.

Otomasyon fixture akışında hesap oluşturulamadı ve canlı otomatik E2E çalıştırılamadı. Kullanıcı tarafından ayrıca iki normal öğrenci hesabı oluşturulup giriş kabulü verildi. Mevcut kullanıcı, rol, profil ve E2E verileri korunmuştur.

## Manuel öğrenci kabulü

- `MANUAL_STUDENT_ACCEPTANCE: PASS`
- Doğrulayan: kullanıcı
- Doğrulama tarihi: 2026-09-25
- Kullanıcı, iki normal öğrenci hesabını uygulama üzerinden oluşturdu ve giriş yaptı.
- İki normal öğrenci hesabı ile giriş sonrası her ikisinde de öğrenci ana ekranı (öğrenci paneli) açıldı.
- Admin candidate-batches ekranı hiçbirinde görünmedi veya erişilemedi; bu beklenen davranıştır.
- Parola, e-posta dışındaki credential, token, cookie veya ekran oturumu istenmedi ve kullanılmadı.
- Bu manuel kabul, otomatik credential tabanlı E2E’nin yerine geçmez; işlevsel kanıttır.
- `NORMAL_STUDENT_REGRESSION: BLOCKED` olarak korunur.
- Commit-öncesi dar kapsamlı QA: `faz25-admin-candidate-review-commit-hazirlik-raporu.md`.

## Fixture hedefleri

- `e2e-faz25-student-a@e2e.test`
- `e2e-faz25-student-b@e2e.test`

Bu iki adres dışındaki auth kullanıcılarına, profillere, rollerine veya verilerine dokunulmadı.

## Oluşturma ve önceden doğrulama durumu

- Otomasyon fixture'ı: **0**
- Önceden bulunup doğrulanan Faz 25 fixture: **0**
- Manuel kabulde kullanılan normal öğrenci hesabı: **2**
- Başka kullanıcı değiştirilmedi.
- Dördüncü yazma denemesi yapılmadı; bu oturumdaki üç kontrollü deneme sınırı doldu.

## Local DB kayıt sayıları

| Kayıt türü | Oluşturulan | Post-rollback |
|---|---:|---:|
| `auth.users` | 0 | 0 |
| `auth.identities` | 0 | 0 |
| `public.student_profiles` | 0 | 0 |
| `public.admin_user_roles` | 0 | 0 |

Otomasyon fixture'ında hedeflere bağlı `admin_user_roles` kaydı yok; ancak auth kullanıcısı oluşmadığı için normal öğrenci profili ve admin rolü yokluğu fixture üzerinde başarıyla doğrulanamadı. Manuel kabulde iki kullanıcı da öğrenci ana ekranına yönlendi ve admin paneli görünmedi/erişilemedi.

## Kontrollü deneme sonuçları

- Ön kontrol: iki hedef auth kaydı, profil ve admin role bağlantısı yoktu.
- Birinci deneme: transaction rollback; credential-safe çıktı yalnız rollback sonucunu verdi.
- İkinci deneme: transaction rollback; sanitized sınıflandırma `SCHEMA_OR_ASSERTION`.
- Üçüncü deneme: transaction rollback; `fixture_step=assertions`, `SQLSTATE P0001`.
- Üç denemede de tek transaction sınırı korundu; hedef veya başka kullanıcı kaydı oluşmadı.

## Canlı E2E durumu

| Kontrol | Sonuç |
|---|---|
| A fixture ile öğrenci login ve öğrenci yönlendirmesi | BLOCKED |
| A ile `/admin/candidate-batches` koruması | BLOCKED |
| A ile `/admin/candidate-batches/9310097d-168c-498e-b8cc-4531d46c0825` koruması | BLOCKED |
| B fixture ile öğrenci login ve öğrenci yönlendirmesi | BLOCKED |
| B ile `/admin/candidate-batches` koruması | BLOCKED |
| B ile `/admin/candidate-batches/9310097d-168c-498e-b8cc-4531d46c0825` koruması | BLOCKED |
| 375×812 görünümü | BLOCKED |
| 768×1024 görünümü | BLOCKED |
| 1440×900 görünümü | BLOCKED |
| Konsol, redirect-loop, HTTP, network veya RPC sızıntı kontrolü | BLOCKED |

Otomasyon fixture'ı bulunmadığı için hiçbir route, ekran boyutu, konsol mesajı, ağ isteği veya RPC yanıtı ölçülmedi. Manuel kabul bu ölçümlerin yerine geçmez. Mevcut localhost sekmesi kullanılmadı; sunucu durdurulmadı, başlatılmadı veya yeniden başlatılmadı.

## Güvenlik ve kapsam sınırları

- Credential, parola, hash, token, cookie veya geçici değer rapora, dosyaya veya çıktıya yazılmadı.
- Ajan tarafından auth/DB/fixture seed-reset, migration, intake, publish veya approval yapılmadı.
- Kullanıcının manuel uygulama üzerinden verdiği iki öğrenci kabulü yalnız davranış kanıtıdır; credential veya ham DB kaydı rapora yazılmadı.
- Mevcut kullanıcılar, roller, öğrenci profilleri ve mevcut E2E hesapları korundu.
- Kod değişikliği, commit, stage ve push yapılmadı.

## Devam koşulu

Fixture yazma denemeleri bu çalışma oturumunda tükendi. Yeni deneme ancak assertion kök nedeni ayrı kontrollü teşhis ve yeni açık izin ile düzeltilirse yapılabilir; bu raporla yeni fixture veya E2E başarısı iddia edilmez.
