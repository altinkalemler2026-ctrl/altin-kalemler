# Faz 14B — Migration 117 Ana Lokal DB Uygulama Raporu

**Tarih:** 2026-09-16
**Model:** big-pickle (opencode)
**Sorumlu:** selami
**Kapsam:** Migration 117'yi yalnız `supabase_db_yarisma-programi` ana lokal DB'ye kontrollü uygulama + şema/RPC/fonksiyonel doğrulama

---

## 1. Sonuç Özeti

| Metrik | Değer |
|---|---|
| **Durum** | ✅ BAŞARILI |
| Hedef DB | `supabase_db_yarisma-programi` (port 54322) |
| Migration dosyası | `supabase/migrations/117_faz14a_candidate_question_batch.sql` (QA'da test edilen nihai sürüm — `convert_to` + `v_received_count` düzeltmeleri dahil) |
| Uygulama yöntemi | Tek transaksiyon (`ON_ERROR_STOP=1`, BEGIN/COMMIT dosya içinde) |
| Uygulama sonucu | ✅ COMMIT — tüm DDL başarılı |
| Candidate tabloları | ✅ `candidate_question_batches`, `candidate_batch_candidate_results` mevcut |
| RPC fonksiyonları | ✅ `register_candidate_question_batch`, `get_candidate_question_batch_contract`, `validate_candidate_question_batch_candidate` |
| Grant (anon/auth/svc) | ✅ anon=false · authenticated=true · service_role=true |
| RLS aktif | ✅ her iki tabloda `relrowsecurity = true` |
| npx tsc --noEmit | ✅ 0 hata |
| npm run test | ✅ 60 dosya / 827 PASS |
| Docker envanter | ✅ Öncesi=sonrası=12 konteyner (aynı isimler) |
| Fixture verisi kalıcı mı? | ✅ Hayır — tüm fixture'lar BEGIN...ROLLBACK içinde, tamamı geri alındı (0/0/0) |
| Gerçek veri eklendi mi? | ✅ Hayır — YALNIZCA fixture)
| Commit / push | ✅ YAPILMADI |

---

## 2. Ön Kontroller (uygulama öncesi)

| Kontrol | Durum | Kanıt |
|---|---|---|
| Ana DB'de candidate tablo yok | ✅ 0 satır | `pg_tables WHERE tablename LIKE 'candidate%'` → count=0 |
| Ana DB'de register RPC yok | ✅ yok | `pg_proc WHERE proname='register_candidate_question_batch'` → count=0 |
| Ana DB migration kaydı | ✅ 110'da bitiyor (117 henüz uygulanmadı) | `schema_migrations ORDER BY version DESC LIMIT 5` → 110,109,108,107,106 |
| Migration dosyası nihai sürüm | ✅ convert_to + v_received_count düzeltmeleri mevcut | `grep convert_to` ve `grep v_received_count := v_received_count + 1` → her ikisi doğrulandı |
| Docker hedef | ✅ yalnız `supabase_db_yarisma-programi` | 12 konteyner listelendi, sadece bu hedef |

---

## 3. Uygulama Adımları

### 3.1 Migration kopyalama

```
docker cp 117_faz14a_candidate_question_batch.sql → supabase_db_yarisma-programi:/tmp/117_faz14a.sql
```

### 3.2 Uygulama (tek transaksiyon)

```
docker exec supabase_db_yarisma-programi psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -f /tmp/117_faz14a.sql
```

Sonuç: `BEGIN` → CREATE TABLE ×2 + CREATE INDEX ×4 + CREATE FUNCTION ×4 + DROP POLICY ×2 + CREATE POLICY ×2 + GRANT ×2 + REVOKE ×2 + ALTER DEFAULT PRIVILEGES ×2 → `COMMIT`. Tüm NOTICE'lar beklenen IF NOT EXISTS/OR REPLACE squeeze'ları.

---

## 4. Doğrulama Fixture'ları (hepsi BEGIN...ROLLBACK içinde — kalıcı veri yok)

### 4.1 Senaryo sonuçları

| # | Senaryo | Beklenen | Gerçek | |
|---|---|---|---|---|
| S1 | Geçerli paket (çözümlü) → ingested | `ingested` + 1 inserted | ✅ `ingested`, total=1, inserted=1 | PASS |
| S2 | Çözümsüz geçerli aday → needs_review | `ingested` + review_queue kaydı | ✅ status=needs_review, readiness=needs_review, review_queue=1 | PASS |
| S3 | Hatalı paket → rejected | `rejected` + invalid=1 | ✅ rejected, invalid=1 | PASS |
| S4 | Idempotent tekrar → already_received | Aynı batch_id + already_received | ✅ 1.→ingested, 2.→already_received, aynı batch_id, total=1 | PASS |
| S5 | Otomatik yayın yok | staging id → questions'ta 0 satır | ✅ pub_count=0 | PASS |

### 4.2 ROLLBACK doğrulaması

```
fixture'lar sonrası:
candidate_question_batches:          0 satır
ai_question_staging (manual_candidate): 0 satır
review_queue (candidate_batch_intake_incomplete): 0 satır
```

Tüm fixture'lar ROLLBACK ile geri alındı; ana DB'de kalıcı veri yok.

---

## 5. Yapısal Doğrulama (uygulama sonrası)

| Kontrol | Durum |
|---|---|
| `candidate_question_batches` tablosu mevcut | ✅ |
| `candidate_batch_candidate_results` tablosu mevcut | ✅ |
| `register_candidate_question_batch(jsonb)` public fonksiyon | ✅ |
| `get_candidate_question_batch_contract()` public fonksiyon | ✅ |
| `validate_candidate_question_batch_candidate(jsonb)` private fonksiyon (PUBLIC'e kapalı) | ✅ |
| anon EXECUTE = false | ✅ |
| authenticated EXECUTE = true | ✅ |
| service_role EXECUTE = true | ✅ |
| RLS enabled (her iki tablo) | ✅ relrowsecurity=true |

---

## 6. Kod Doğrulaması (uygulama sonrası)

| Kontrol | Değer |
|---|---|
| `npx tsc --noEmit` | ✅ 0 hata |
| `npm run test` | ✅ 60 dosya / 827 test PASS |

---

## 7. Docker Envanter Karşılaştırması

```
ÖNCE (12 konteyner):
supabase_db_yarisma-programi   ← HEDEF
supabase_db_qa-iso19
supabase_studio_yarisma-programi
supabase_pg_meta_yarisma-programi
supabase_storage_yarisma-programi
supabase_rest_yarisma-programi
supabase_realtime_yarisma-programi
supabase_inbucket_yarisma-programi
supabase_auth_yarisma-programi
supabase_kong_yarisma-programi
supabase_vector_yarisma-programi
supabase_analytics_yarisma-programi

SONRA (12 konteyner): AYNI LİSTE
```

Geçici konteyner/DOSYA OLUŞTURULMADI, TEMP DOSYA YARATILMADI. Sadece `/tmp/117_faz14a.sql` konteyner içinde kaldı (psql -f ile).

---

## 8. Kalan İş Notları

1. **schema_migrations kaydı:** Migration 117, `supabase_migrations.schema_migrations` tablosuna INSERT edilmemiş durumda. Bu, 111–116 ile tutarlı bir davranıştır: tümü elle uygulandı ve supabase_migrations'a kayıt düşmedi. `supabase db reset` çalıştırıldığında CI, 001–110'u uygulayacaktır; 111–117 untracked olduğundan ve schema_migrations'da kayıtlı olmadıklarından ATLANACAKTIR. CI'da bu migration'ların da uygulanabilmesi için ya:
   - (a) 111–117 dosyalarını commit/push etmek ve schema_migrations'a INSERT eklemek, ya da
   - (b) CI workflow'una `psql -f` ile elle uygulama adımı eklemek gereklidir.
2. **Gerçek aday soru verisi eklenmedi** — kapsamda değildi.
3. **PDF içeriği, kaynak fişleme, öğretmen onayı, öğrenci/profil/competition/UI** — kapsam dışı.
4. **Hosted Supabase** — dokunulmadı.
5. **Commit/push** — yapılmadı; kullanıcı onayı bekleniyor.

---

## 9. Sonuç

```
MIGRATION_117_ANA_LOCAL_DB:        PASS (tek transaksiyon, COMMIT)
YAPI_DOGRULAMA:                    PASS (tablo + fonksiyon + grant + RLS)
ROLLBACK_DOGRULAMA:                PASS (0 fixture satırı kaldı)
IDEMPOTENT_TEKRAR:                 PASS (already_received)
OTOMATIK_YAYIN_KORUMASI:          PASS (questions=0)
KOD_DOGRULAMA:                     PASS (tsc + 827 test)
DOCKER_ENVANTER:                   DEGISIKLIK YOK (12/12)
SCHEMA_MIGRATIONS_KAYDI:           110'da duruyor (tutarlı, 111–117 de kayıtsız)
REAL_VERI:                         EKLENMEDI
COMMIT/PUSH:                       YAPILMADI
```