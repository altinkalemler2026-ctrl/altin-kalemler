# docs/rollbacks — Migration Akışı Dışı Rollback/Taslak Dosyaları

Bu dizin, `supabase/migrations/` akışından ÇIKARILMIŞ dosyaları barındırır.
`supabase db reset` buradaki dosyaları **uygulamaz**; bu dosyalar dokümantasyon
amaçlıdır.

## Neden Taşındı?

`supabase db reset`, `supabase/migrations/*.sql` dosyalarını numerik sırayla
uygular. Sıralı zincire giren şu dosyalar temiz reset'i bozuyordu:

| Dosya | Sorun |
|---|---|
| `113_faz12b_rollback_kazanim_ve_alt_konu.sql` | `112`'nin yüklediği a6 alt konu ve a7 kazanım kayıtlarını DELETE ediyordu → temiz DB verisiz kalıyordu. |
| `115_faz12c_rollback_belirsiz_kazanim.sql` | `114`'ün eklediği 5 belirsiz kazanım UUID'sini DELETE ediyordu. |
| `116_faz13c_mat1046_pilot_kaynak_fisleme.sql` | Elle uygulanması gereken (implante edilmemiş) taslaktı; dosya içinde lokal `D:\evraklar` yolu vardı ve seeds kaynak kaydı ekliyordu. |

Detaylı kanıt: `docs/reports/faz14d-migration-zinciri-duzeltme-sonucu.md`

## 116 Özel İşaret

`116_faz13c_mat1046_pilot_kaynak_fisleme_UYGULANMADI_TASLAK.sql` adındaki
**UYGULANMADI_TASLAK** eki, bu dosyanın migration sayacına kaydedilmediğini ve
gerçek bir migration olarak kullanılamayacağını kalıcı olarak belirtir.

## Elle Nasıl Uygulanır (Gerekirse)

Bu dosyalar bilinçli olarak migrate edilmemiştir. Bir ortamda gerçekten
uygulanması gerekiyorsa, sorumlu kişi dosya içeriğini incelemeli ve aşağıdaki
şartlara uygun olmalıdır:

- `116` için: millî eğitim kaynak dosyalarına erişim (draft yollar) ve ürün
  onayı; `schema_migrations`'a el ile eklenmesi ve disposable ortamda QA'sı.
- Hiçbir durumda bu dosyalar `supabase/migrations/` içine geri taşınmaz.

## Dizin Dosyaları (SHA-256 teyitli, içerik değişmedi)

- `113_faz12b_rollback_kazanim_ve_alt_konu.sql`
  `57B8E1FDD89BB3D631DC1DE0D4A7C506B61BDBDFA2221C6DDF308FA0B4AFE095`
- `115_faz12c_rollback_belirsiz_kazanim.sql`
  `911CC864F813B78EFCA3A233FB35B3BF2ED88DBB6F44CD370A907E0177E1E509`
- `116_faz13c_mat1046_pilot_kaynak_fisleme_UYGULANMADI_TASLAK.sql`
  `2063210CC855838D766F687F850299FD61A15368BB80624E8933ED397FE4D6CD`