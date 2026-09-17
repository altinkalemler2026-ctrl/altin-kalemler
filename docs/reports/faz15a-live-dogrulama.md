# Faz 15A — Canlı Yerel Doğrulama ve Kök Neden Düzeltmesi

Tarih: 2026-09-15 · Kapsam: yalnız yerel (commit/push yok, hosted Supabase'e dokunulmadı)

## 1. Özet

Faz 15A'nın üç ayağı doğrulandı:

1. **`TrainingSessionSingle` tek soru UI'si** — daha önce sabitlenen a11y/keyed `QuestionStep`
   refactor'ü korunuyor; bu oturumda TS değişikliği yok.
2. **Migration 110 local durumu** — objeler mevcut; ACL'ler kontrol edildi;
   `supabase_migrations.schema_migrations`'a `110` tracking satırı eklendi
   (`statements='{}'`).
3. **Canlı 4 senaryo** — izole fixture (`scripts/local-faz15a-e2e-fixture.sql`) ile
   canlı stack üzerinde doğrulandı. Bu sırada **yeni bir gerçek DB hatası** bulunup
   düzeltildi (aşağıda).

## 2. Bulunan ve Düzeltilen Kök Neden (Migration 110)

`public._faz15_eligible_scope`'un **ready** dönüşünde `'lock', null` anahtarı vardı.
JSON-null değer SQL `NULL` değildir; bu yüzden `v_scope->'lock' is not null` kontrolü
çalışılabilir kapsamda dahi `true` dönüyor ve üç arayüz (`get_training_session_state`,
`start_training_session`, `select_gated_targeted_review_questions`) hazır durumu
`locked` + boş kilit olarak dönüyordu.

- Kanıt: `({"lock": null}::jsonb -> 'lock') IS NOT NULL` → `true`
- Düzeltme: ready dönüşünden `'lock', null` **çıkarıldı** (tek nokta; üç arayüz
  anlamsal olarak düzelir). Gerçek kilit kolları değişmedi.
- Uygulama: `supabase/migrations/110_faz15_training_gating.sql` + local DB'de ilgili
  fonksiyon `CREATE OR REPLACE` ile güncellendi.

Düzeltme sonrası DB kanıtı (in-DB, `request.jwt.claims` ile fixture kullanıcısı olarak):

- `get_training_session_state(T1)` → `state: ready, topics:[T1]`
- `get_training_session_state(T2)` → `state: locked, kind: "konu_islenmedi"` (değişmedi)
- `start_training_session(T1)` → `state: question` + Q1 (queue 2) — rollback doğrulama

## 3. Fixture Kurulum Notu

Local GoTrue admin API, direkt SQL ile yerleştirilen `auth.users` satırını
tanımıyordu (`/auth/v1/admin/users/<id>` → 404). Kullanıcı onayıyla:

- İnert placeholder satır (yalnız kendi oluşturduğum `15aa…001` auth + profil) silindi.
- Aktör, GoTrue **signup** akışıyla oluşturuldu (faz7/8 deseni); `student_profiles`
  izole profile bağlandı (id `eda31974-…e2c5`).
- `scripts/local-faz15a-e2e-fixture.sql`, aktörü SQL ile oluşturmak yerine runner'a
  (signup) bırakacak şekilde güncellendi.

## 4. Senaryo Doğrulaması

| # | Senaryo | Sonuç | Kanıt |
|---|---------|-------|-------|
| 1 | Onaysız T2'ye direct URL | Kilitli kart: "Konu işlenmedi"; soru metni yok; exposure 0 | `faz15a-sec1-locked-t2-375.png`; DB exposures=0 |
| 2 | Onaylı T1: ready → "Antrenmana Başla" → Q1 | Ready ekranı + tek soru (4 seçenek) | `faz15a-sec2-ready-t1-375.png`; Q1 ekranı |
| 3 | Cevap (B) → geri bildirim → Sonraki → Q2 | "Doğru", "Doğru cevap: B) 2", çözüm açıklaması; Q2'ye geçiş | `faz15a-sec3-feedback-q1-375.png`; Q2 başlığı |
| 4 | Q2'deyken sayfayı yenile | Aynı soru kalır; sayaç/exposure artmaz | `faz15a-sec4-q2-after-refresh-375.png`, `…-1440.png` |

Senaryo-4 DB kanıdı (yenileme öncesi = sonrası):

```
exposures=2 | queues=2 (Q1 answered, Q2 queued) | weekly_ct=1 (used 2) | daily_ct=1 (used 2) | attempts=1
```

## 5. Kapsam ve Sınırlar

- Yalnız local main stack; hosted/remote erişilmedi; ana stack sıfırlanmadı.
- Lint/typecheck TS gerektiren bir borç yok (bu oturumda TS değişikliği yapılmadı;
  `TrainingSessionSingle` testleri önceki oturumda 6/6 yeşildi).
- Commit/push yapılmadı — faz onayı bekleniyor.
- Düzeltilen fonksiyon: `supabase/migrations/110_faz15_training_gating.sql`
  (`_faz15_eligible_scope` ready dönüşü), sürüm değiştirilmedi (tracking satırı 110).