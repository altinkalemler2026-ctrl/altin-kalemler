# Yerel Admin Görsel Testi — En Dar Yetki Rolü Salt-Okunur Denetimi

Tarih: 25 Eylül 2026

## Sonuç

Mevcut rol kataloğunda candidate batch liste ve detay ekranlarını açabilen en dar rol **`question_reviewer`**dır.

İnsan kullanıcı için etkin erişim koşulu şudur:

- `questions.view` **VE**
- `ai.manage` **VEYA** `questions.approve`

Bu nedenle `question_reviewer`, `questions.view` ve `questions.approve` izinleriyle listeyi ve detayı açabilir. `content_admin` ve `super_admin` de erişebilir, ancak daha fazla yetki taşır. `copyright_reviewer` ve `curriculum_editor` erişemez.

Önemli sınırlam: Katalogda candidate-review için yalnız `questions.view` taşıyan ayrı bir salt-okunur rol yoktur. `question_reviewer` mevcut roller içindeki en dar seçenektir; buna rağmen `questions.approve` ve `questions.reject` yazma yetkileri taşır. Testin salt-okunur amacı için bu iki yetki gereksizdir; `questions.approve` yalnızca mevcut erişim kapısı bunu istediği için zorunludur.

## Kapsam ve güvenlik

Bu denetimde:

- Yalnız kaynak dosyaları ve indeks kapsamı okundu.
- Yerel ana Supabase veritabanında yalnız `SELECT` çalıştırıldı.
- `admin_user_roles` üzerinde `INSERT`, `UPDATE` veya `DELETE` çalıştırılmadı.
- Auth kullanıcısı veya şifresi oluşturulmadı/değiştirilmedi.
- Kullanıcıya rol atanmadı.
- Migration, candidate verisi, UI veya Git değiştirilmedi.
- İstenen rapor dışında dosya yazılmadı.

Çalışma ağacı denetim öncesinde zaten kirliydi; mevcut kullanıcı değişikliklerine dokunulmadı.

## Beş rolün yerel katalogdaki etkin izinleri

Aşağıdaki tablo yerel veritabanındaki `admin_roles`, `admin_role_permissions` ve `admin_permissions` tablolarından salt-okunur `SELECT` ile alınmıştır. Beş rolün de `is_active = true` değerindedir. Başlangıç rol→ izin eşleşmeleri ayrıca `supabase/migrations/013_admin_roles_and_permissions.sql:244`, `supabase/migrations/013_admin_roles_and_permissions.sql:261`, `supabase/migrations/013_admin_roles_and_permissions.sql:283`, `supabase/migrations/013_admin_roles_and_permissions.sql:304` ve `supabase/migrations/013_admin_roles_and_permissions.sql:326` bloklarında tanımlıdır. Daha sonra eklenen izinlerin etkin rol sahipliği için yerel katalog sonucu esas alınmıştır.

| Rol | Bağlı izinler |
|---|---|
| `content_admin` | `calendar.manage`, `copyright.review`, `curriculum.manage`, `imports.manage`, `questions.approve`, `questions.edit`, `questions.reject`, `questions.view` |
| `copyright_reviewer` | `commercial.approve`, `copyright.review`, `questions.view` |
| `curriculum_editor` | `curriculum.manage`, `questions.view` |
| `question_reviewer` | `questions.approve`, `questions.reject`, `questions.view` |
| `super_admin` | `ai.manage`, `audit.view`, `calendar.manage`, `commercial.approve`, `copyright.review`, `curriculum.manage`, `imports.manage`, `questions.approve`, `questions.edit`, `questions.reject`, `questions.view`, `rewards.manage`, `users.manage` |

## Candidate batch liste ve detay erişim kapısı

### 1. Ortak admin layout kapısı

`/admin/*` sayfalarının ortak layout'u önce gerçek auth kullanıcısını doğrular ve `teacher_review_admin_has_permission('questions.view')` sonucunu ister. Hata veya sonuç `true` değilse `/dashboard` adresine yönlendirir: `src/app/(admin)/layout.tsx:24`, `src/app/(admin)/layout.tsx:42`, `src/app/(admin)/layout.tsx:54`.

### 2. Liste ve detay sayfa kapıları

Hem liste hem detay sayfası `hasCandidateBatchReadPermission()` çağırır ve sonuç `false` ise ana sayfaya döner:

- Liste: `src/app/(admin)/admin/candidate-batches/page.tsx:248`, `src/app/(admin)/admin/candidate-batches/page.tsx:259`
- Detay: `src/app/(admin)/admin/candidate-batches/[id]/page.tsx:746`, `src/app/(admin)/admin/candidate-batches/[id]/page.tsx:757`

Yardımcı iki izni paralel kontrol eder ve `ai.manage` **VEYA** `questions.approve` sonucundan birini kabul eder: `src/lib/admin/candidate-batches.ts:254`, `src/lib/admin/candidate-batches.ts:258`, `src/lib/admin/candidate-batches.ts:261`, `src/lib/admin/candidate-batches.ts:269`.

### 3. Veritabanı RPC kapıları

İstemci katmanı tek başına güvenlik sınırı değildir. Liste RPC'si de kimlik doğrulama ve aynı `ai.manage` **VEYA** `questions.approve` şartını fail-closed olarak uygular: `supabase/migrations/120_faz19_admin_candidate_batch_read.sql:59`, `supabase/migrations/120_faz19_admin_candidate_batch_read.sql:61`, `supabase/migrations/120_faz19_admin_candidate_batch_read.sql:66`, `supabase/migrations/120_faz19_admin_candidate_batch_read.sql:72`.

Güncel detay RPC'si de aynı kapıyı korur: `supabase/migrations/126_faz24_admin_candidate_review_low_confidence.sql:59`, `supabase/migrations/126_faz24_admin_candidate_review_low_confidence.sql:61`, `supabase/migrations/126_faz24_admin_candidate_review_low_confidence.sql:66`, `supabase/migrations/126_faz24_admin_candidate_review_low_confidence.sql:72`.

İzin RPC'si aktif rolü, rol→izin bağlantısını ve istenen izin kodunu birleştirir: `supabase/migrations/090_teacher_review_rpc_security_hardening.sql:43`, `supabase/migrations/090_teacher_review_rpc_security_hardening.sql:55`, `supabase/migrations/090_teacher_review_rpc_security_hardening.sql:67`.

`service_role` için RPC düzeyinde teknik bypass bulunur; bu bir insan admin rolü değildir ve görsel test rol adayı olarak değerlendirilmemiştir.

### 4. Net kapı

Bir insan kullanıcının liste ve detayı açabilmesi için gereken en az izin kümesi:

```text
questions.view AND (ai.manage OR questions.approve)
```

Gerekli olmayan izinler: `questions.edit`, `questions.reject`, `curriculum.manage`, `imports.manage`, `copyright.review`, `commercial.approve`, `users.manage`, `audit.view`, `calendar.manage` ve `rewards.manage`.

Not: `commercial.approve`, `questions.approve` yerine geçmez.

## Rol uygunluk matrisi

| Rol | `questions.view` | `ai.manage` veya `questions.approve` | Sonuç | Dar değerlendirmesi |
|---|---:|---:|---|---|
| `content_admin` | Var | `questions.approve` | Erişir | 8 izin; gereğinden geniş |
| `copyright_reviewer` | Var | Yok | Erişemez | Uygun değil |
| `curriculum_editor` | Var | Yok | Erişemez | Uygun değil |
| `question_reviewer` | Var | `questions.approve` | Erişir | 3 izin; erişebilen en dar rol |
| `super_admin` | Var | `ai.manage` ve `questions.approve` | Erişir | 14 izin; aşırı geniş |

Karşılaştırma yalnız mevcut beş rol üzerinden yapılmıştır.

## Yerel auth kullanıcıları ve mevcut rol bağlantıları

Yerel `admin_user_roles` satır sayısı: **0**.

| Auth kullanıcı ID | E-posta | Mevcut admin rolleri |
|---|---|---|
| `89e2b1bc-2cc7-4e4e-93ee-0dfd43d69607` | `e2e-ogrenci-a@e2e.test` | Yok |
| `a31377de-fd7b-449a-b874-f22c8344deb0` | `e2e-ogrenci-b@e2e.test` | Yok |
| `eda31974-9d7a-472a-9812-8faa47f9e2c5` | `faz15a-ogrenci-a@e2e.test` | Yok |
| `36a400a9-5ef6-4114-a1bf-59195e03b66b` | `mevcut yerel kullanıcı hesabı` | Yok |

Hiçbir kullanıcıya rol atanmamıştır ve bu denetimde rol atanması önerilmiş bir kullanıcı seçilmemiştir.

## Görsel test için önerilen rol ataması

### Rol adı

`question_reviewer`

### Gereken izinler

Bu rolün mevcut katalogdaki izinlerinden candidate list/detail ekranlarını açanlar:

- `questions.view`
- `questions.approve`

### Gereksiz veya yüksek yetkiler

- `questions.reject`: Görsel listeleme/detay testi için gereksiz; yazma yetkisidir.
- `questions.approve`: Görsel testin salt-okunur amacı için yüksek yetkidir, ancak mevcut UI ve RPC kapısı bunu açmak için istediğinden bu rol seçeneğinde zorunludur.
- `questions.edit`, `curriculum.manage`, `imports.manage`, `copyright.review`, `users.manage` veya diğer yönetim izinleri bu rolde yoktur.

Bu nedenle `question_reviewer`, mevcut katalog içindeki en dar rol olsa da teknik olarak tamamen salt-okunur bir rol değildir. Test politikası onay/ret yetkisi taşıyan hiçbir rolü kabul etmiyorsa mevcut katalogda uygun rol yoktur; bu durumda `NONE` gerekir. Mevcut roller arasında en az yetki seçimi esas alındığında öneri `question_reviewer`dır.

### Atama sonrası test edilecek ekranlar

1. `/admin/candidate-batches`
   - Admin layout'a geçiş
   - Liste, sayaçlar, boş/dolu durum ve sayfalama
2. Mevcut bir kaydın UUID'siyle `/admin/candidate-batches/<id>`
   - Paket özeti
   - Aday önizlemesi
   - Doğrulama sonuçları, review kuyruğu ve gate sonuçları

Bu incelemede rol atanmadığı için görsel test çalıştırılmamıştır.

## Kanıt sınırları

Codebase-memory üretimi `2026-09-24T16:28:27Z` idi ve SQL dosyalarının bazı bölümleri kısmi indekslenmişti. Rol ve erişim iddiaları bu nedenle ilgili kaynak satırları doğrudan okunarak ve etkin rol→izin sonuçları yerel veritabanından `SELECT` ile ayrıca doğrulandı. `126_faz24_admin_candidate_review_low_confidence.sql` çalışma ağacında untracked olsa da bu denetimde değiştirilmedi; kaynak olarak yalnızca okundu.

## Son karar

RECOMMENDED_LOCAL_VISUAL_TEST_ROLE: question_reviewer
