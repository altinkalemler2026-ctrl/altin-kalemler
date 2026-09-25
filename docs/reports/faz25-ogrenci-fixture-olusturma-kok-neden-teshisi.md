# Faz 25 — Öğrenci Fixture Oluşturma Kök Neden Teşhisi

- Tarih: 2026-09-25
- Kapsam: Local Supabase katalogları, `auth.users`, `auth.identities`, `public.student_profiles`, `public.admin_user_roles` ve admin yetki bağlantıları.
- `SAFE_FOR_NEW_FIXTURE_ATTEMPT: YES`
- Bu değer yalnız aşağıdaki planın ayrı kontrollü onayla yeniden denenebileceği anlamına gelir; bu çalışma sırasında yeni kullanıcı, yazma veya Dördüncü deneme yapılmadı.
- Commit/push: **YOK**

## 1. Kesin kök neden

Önceki denemelerdeki schema hatası, fixture alanlarının yanlış seçilmesinden değil, generated column alanlarına açıkça değer verilmesinden kaynaklandı:

- `auth.users.confirmed_at` `ALWAYS` generated column'dır ve ifadesi `LEAST(email_confirmed_at, phone_confirmed_at)` şeklindedir. `INSERT` içine bu alan konulamaz; yalnız `email_confirmed_at` ve gerekiyorsa `phone_confirmed_at` yazılmalıdır.
- `auth.identities.email` `ALWAYS` generated column'dur ve ifadesi `lower(identity_data ->> 'email')` şeklindedir. `INSERT` içine `email` konulamaz; e-posta yalnız `identity_data` içinde bulunmalıdır.
- İkinci deneme psql değişken sözdizimi nedeniyle başlamadan reddedildi; bu schema kök nedeni değildir.
- Üç deneme de atomik transaction içinde rollback oldu; önceki hedefler için `auth.users`, `auth.identities`, `student_profiles` ve `admin_user_roles` kayıt sayıları `0` olarak doğrulandı.

## 2. `public.student_profiles` şema teşhisi

| Alan | Generated | NULL | Default | Değerlendirme |
|---|---|---|---|---|
| `id` | Hayır | `NO` | Yok | `auth.users.id` ile aynı FK değeri; zorunlu |
| `grade_level` | Hayır | `NO` | Yok | `1..12` CHECK; zorunlu |
| `nickname` | Hayır | `NO` | Yok | UNIQUE; zorunlu |
| `created_at` | Hayır | `NO` | `now()` | Oluşturma sırasında varsayılan bırakılabilir |
| `updated_at` | Hayır | `NO` | `now()` | Oluşturma sırasında varsayılan bırakılabilir |
| `schedule_profile_id` | Hayır | `YES` | Yok | Nullable FK; minimal fixture'ta `NULL`/atlanmalı |

Kısıtlar:

- `id` → `auth.users.id`, `ON DELETE CASCADE`.
- `nickname` → UNIQUE.
- `grade_level` → `CHECK (grade_level BETWEEN 1 AND 12)`.
- `schedule_profile_id` → `curriculum_schedule_profiles.id`, `ON DELETE SET NULL`.

Trigger'lar:

- `auth.users` üzerindeki `on_auth_user_created` AFTER INSERT trigger'ı `public.handle_new_user()` fonksiyonunu çalıştırır.
- `handle_new_user()` yalnız `raw_user_meta_data ->> 'nickname'` ve `raw_user_meta_data ->> 'grade_level'` alanlarını okur; nickname boş değilse ve grade metin olarak `1`–`12` ise `student_profiles(id, grade_level, nickname)` satırını `ON CONFLICT (id) DO NOTHING` ile oluşturur.
- `trigger_student_profiles_guard_schedule_profile`, normal kullanıcı tarafından `schedule_profile_id` değerinin atanmasını veya değiştirilmesini reddeder; minimal fixture'ta bu alan atlanmalıdır.
- `trigger_set_updated_at` ve `trigger_sync_public_profile_nickname` yalnız ilgili tablo yaşam döngüsü trigger'larıdır; minimum oluşturma için ayrıca yazılmaz.

RLS:

- `authenticated` kullanıcı kendi profilini `SELECT`, `INSERT` ve `UPDATE` edebilir (`auth.uid() = id`).
- Admin tarafından tüm profil okuma ayrı `users.manage` yetkisiyle korunur; fixture için admin yetkisi gerekmez.

Mevcut local profil aggregate'i (PII sorgulanmadan): 4 profil bağlantılı kayıt, 4/4 geçerli grade ve nickname, 4/4 `authenticated` auth rolü, 4/4 email identity ve 0 admin role bağlantısı; schedule profili nullable olduğu için mevcut kayıtlardan biri `NULL` schedule ile tutuluyor.

## 3. `auth.users` minimum yazılabilir alanlar

Catalog'da `confirmed_at` dışındaki alanlar normalde yazılabilir; fixture için semantik minimum:

- `id`: yeni UUID üretilmeli; veritabanında default yoktur.
- `instance_id`: local GoTrue için mevcut auth şemasındaki standart instance UUID değeri kullanılmalı; gerçek değer rapora yazılmaz.
- `aud`: `authenticated`.
- `role`: `authenticated`.
- `email`: hedef fixture e-postası; doğrulama bağlantısı veya PII olarak rapora yazılmaz.
- `encrypted_password`: yalnız parametrik ve process-memory secret ile üretilen hash; hiçbir çıktıya yazılmaz.
- `email_confirmed_at`: confirmation için timestamp.
- `raw_app_meta_data`: email provider bilgisi ve fixture etiketi.
- `raw_user_meta_data`: nickname ve geçerli `grade_level`; bu alanlar profile trigger'ının girdisidir.
- `is_super_admin`: `false`.
- `is_anonymous`: `false` (varsayılan da `false`).
- `created_at` / `updated_at`: auth kaydının yaşam döngüsü için yazılabilir; mevcut auth yazım desenine göre açıkça verilebilir.

`auth.users.confirmed_at` generated olduğu için **asla** INSERT/UPDATE değeri verilmemelidir. Token, recovery, confirmation veya geçici e-posta doğrulama alanları da fixture için yazılmamalıdır.

## 4. `auth.identities` minimum yazılabilir alanlar

- `provider_id`: `auth.users.id::text`.
- `user_id`: `auth.users.id` (FK).
- `identity_data`: `sub`, `email`, `email_verified=true` ve `phone_verified=false` alanlarını içeren JSONB.
- `provider`: `email`.
- `created_at` / `updated_at`: nullable ve DB default’u yoktur; minimum doğrudan kayıtta auth oluşturma katmanının zaman değerleriyle doldurulabilir.
- `id`: UUID default `gen_random_uuid()` ile üretilebilir.

`auth.identities.email` generated olduğu için **asla** açıkça yazılmamalıdır. Tekil ilişki `(provider_id, provider)` ve `user_id` FK'si vardır; `provider_id` kullanıcı UUID metnidir. `identity_data.email` yalnız veri kaynağıdır.

## 5. Normal öğrenci ve admin rolü ilişkisi

- `admin_user_roles` satırı, `admin_roles` ve permission tablolarıyla birleşerek admin yetkisi üretir.
- `private.is_current_user_admin()` yalnız aktif `admin_user_roles` + aktif `admin_roles` kaydı arar.
- `private.has_admin_permission(...)` aynı join zincirine `admin_role_permissions` ve `admin_permissions` ekler.
- `private.is_current_user_super_admin()` de `admin_user_roles` içindeki aktif `super_admin` rolünü arar; `auth.users.is_super_admin` alanına ayrı bir bypass bulunmadı.
- Bu nedenle hedef auth kullanıcı `role=authenticated`, `is_super_admin=false` ve `admin_user_roles` satırı olmadan normal öğrenci yetkisine sahip olur. Fixture oluşturma sırasında `admin_roles` veya `admin_user_roles` INSERT/UPDATE yapılmamalıdır.
- Fixture için ek admin metadata, admin permission veya admin role verisi oluşturulmamalıdır.

## 6. Bir sonraki yazma görevi için tek atomik plan

Aşağıdaki plan bu raporda **uygulanmadı**:

1. Tek read/write transaction başlatılacak; iki hedef adresin yokluğu veya daha önce oluşturulmuşsa yalnız aynı fixture marker’ı ile normal öğrenci olduğu doğrulanacak. Belirsizlik, admin role veya nickname çakışması halinde `ROLLBACK`.
2. Parola yalnız process memory’de üretilecek; SQL metnine gömülmeyen parametrik bir bağlama ile DB’ye öğretilecek. Hash, parola, token veya hata bağlamı hiçbir terminal/rapor/trace çıktısına alınmayacak.
3. `auth.users` INSERT/UPDATE’inde `id`, local instance/audience/role, `encrypted_password`, `email_confirmed_at`, provider metadata ve nickname/grade metadata yazılacak; `confirmed_at` kesinlikle atlanacak.
4. `handle_new_user()` trigger’ının oluşturduğu `student_profiles` satırı doğrulanacak. Gerekirse yalnız `id`, `grade_level`, `nickname` için `ON CONFLICT DO NOTHING` kullanılacak; `schedule_profile_id` verilmeyecek.
5. `auth.identities` INSERT’inde `provider_id`, `user_id`, `identity_data` ve `provider` yazılacak; generated `email` kesinlikle atlanacak. `(provider_id, provider)` çakışmasında yalnız aynı hedef fixture doğrulanacak.
6. Transaction içinde iki auth kullanıcısının, iki profile, iki identity’nin ve fixture marker’ının varlığı; iki kullanıcının da aktif/confirmed/authenticated olduğu ve `admin_user_roles` sayısının `0` olduğu doğrulanacak.
7. Herhangi bir assert veya hata halinde transaction `ROLLBACK`; commit veya E2E çalıştırılmayacak. Commit sonrası yalnız aggregate/read-only doğrulama yapılacak; E2E credential'ları yine process memory'de tutulacak.

## Credential güvenlik kuralı

Hiçbir parola, hash, token, cookie, geçici değer, e-posta doğrulama bağlantısı veya PII terminale, rapora, dosyaya, log’a, trace’e veya ekran görüntüsüne yazılmayacak. SQL istemci trace’i, hata gövdesi ve credential değerleri susturulacak; parametrik bağlama ve yalnız `PASS/FAIL/BLOCKED` sanitizasyonu kullanılacak.

## Kapsam dışı bırakılanlar

INSERT, UPDATE, DELETE, ALTER, migration, seed, fixture oluşturma, parola/hash üretimi, auth isteği, sunucu lifecycle, kod, git, commit, stage ve push bu teşhis çalışmasında yapılmadı.
