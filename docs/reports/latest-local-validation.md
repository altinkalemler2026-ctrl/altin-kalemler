# Migration 059 Faz 1 — Son Yerel Doğrulama Raporu

- **Tarih/Saat:** 22 Ağustos 2026, 20:55 (+02:00)
- **Ortam:** Yalnızca yerel Supabase (Docker: `supabase_db_yarisma-programi`, PostgreSQL 17.6.1.159)
- **Kapsam:** `supabase/migrations/059` … `066` (Migration 059 Faz 1 zinciri) + önceki zincirin temiz oynatılabilirliği
- **QA Suite:** `scripts/qa_faz1_local_validation.sql` (21 test / 34 alt doğrulama; tek transaction + final ROLLBACK)

## Özet Sonuç

| Metrik | Değer |
|---|---|
| Toplam test (grup) | **21** |
| Geçen | **21 / 21 PASS** |
| Alt doğrulama | 34 / 34 PASS |
| Temizlik | Sıfır kalıntı (suite içi ve ayrı oturumla iki kez doğrulandı) |

## Dokunulan / Doğrulanan Migration'lar

| Dosya | Durum |
|---|---|
| `059_curriculum_schedule_profiles.sql` | Değişiklik yok; QA ile doğrulandı |
| `060_annual_stock_targets.sql` | Değişiklik yok; QA ile doğrulandı |
| `061_student_question_attempts.sql` | Değişiklik yok; QA ile doğrulandı |
| `062_student_exposure_tables.sql` | Değişiklik yok; QA ile doğrulandı |
| `063_student_weekly_counters.sql` | Değişiklik yok; QA ile doğrulandı |
| `064_student_dimension_metrics.sql` | Değişiklik yok; QA ile doğrulandı |
| **`065_competition_vault_member_limit.sql`** | **Düzeltildi (F-2)** — bkz. "Bulunan Sorunlar" #1 |
| `066_fix_student_profiles_grants.sql` | Değişiklik yok; QA ile doğrulandı |
| (önceden düzeltilmiş) `001`, `025`, `045` | Temiz reset zincirinde sorunsuz uygulandı |

## Test Sonuç Tablosu

| T-id | Test | Sonuç |
|---|---|---|
| T-01 | Migration geçmişi tam (001..066, 050 hariç, 65 sürüm) | PASS |
| T-02 | Ders seed: 10 kanonik ders + matematik UUID sabiti (045) | PASS |
| T-03 | 8 Faz1 tablosunun varlığı | PASS |
| T-04 | 8 Faz1 tablosunda RLS açık | PASS |
| T-05 | Kritik Faz1 indeksleri (10 adet) | PASS |
| T-06 | Aynı eğitim yılında ikinci default versiyon engeli (059) | PASS |
| T-07a/b | schedule_item: end_week ≤ start_week reddi + geçerli aralık kabulü | PASS |
| T-08a/b | schedule_item: topic/outcome zorunluluğu + yalnız-outcome kabulü | PASS |
| T-09 | weekly_competition hedefi < 300 reddi (060) | PASS |
| T-10 | Kapsam ayrımı: weekly ≥ 300; training/rewarded serbest | PASS |
| T-11 | Zorluk kırılımı toplamı base hedefini aşamaz | PASS |
| T-12 | Stok hücresi tekilliği (versiyon+scope+sınıf+ders+hafta) | PASS |
| T-13a/b/c | Haftalık sayaç: 500 kabul, 501 red, week=53 red (063) | PASS |
| T-14 | Dolu competition kasasına 6. aktif üye engeli (065) | PASS |
| T-15 | Academic kasada limit yok (toplam 8 aktif üye) | PASS |
| T-16 | Dolu kasaya inactive üye ekleme serbest (F-2 sonrası) | PASS |
| T-17 | Inactive→active dönüşümü dolu kasada engellenir | PASS |
| T-18 | 5+ aktif üyeli academic kasa competition tipine çevrilemez | PASS |
| T-19 | Aktif üyenin dolu başka competition kasasına taşınması engellenir | PASS |
| T-20a–f | RLS/grant modeli: anon erişemez; authenticated yalnız kendi satırı + yazamaz; service_role yazar ve bypass | PASS |
| T-21a–e | schedule_profile guard: authenticated INSERT/UPDATE engelli, NULL serbest; postgres serbest | PASS |

## Bulunan Sorunlar ve Uygulanan Düzeltmeler

1. **[MIGRATION] 065 — aktif olmayan üye yazımı hatalı engelleniyordu (F-2).**
   - *Belirti:* Dolu (5 aktif üyeli) competition kasasına `membership_status='inactive'` satırı INSERT edilemiyordu (`P0001: member limit exceeded`), T-16 FAIL.
   - *Kök neden:* Trigger dalı `v_active_member_count + 1 > 5` kontrolünü `NEW.membership_status`'e bakmaksızın yapıyordu; kendi belgesindeki "Limit yalnız aktif üyelere uygulanır" semantiğini ihlal ediyordu.
   - *Düzeltme:* Dalın başına erken çıkış eklendi: `if new.membership_status is distinct from 'active' then return new; end if;`. Header'daki SAYIM SEMANTİĞİ bölümüne F-2 notu eklendi. Aktif üye yollarındaki davranış değişmedi (T-14/T-17/T-18/T-19 aynı koşuda PASS).
2. **[TEST] T-02:** beklenen slug dizisi alfabetik yanlış sıralanmıştı (`felsefe` < `fizik`). Test düzeltildi.
3. **[TEST] T-15:** akademik kasada zaten üye olan q6/q7 yeniden ekleniyordu → `(vault_id, question_id)` unique ihlali. Test artık yalnız q1–q5'i ekler.
4. **[TEST] T-16:** 051'in `question_vault_membership_removed_consistency` CHECK'i gereği inactive satırda `removed_at` zorunlu; fixture'a `removed_at = now()` eklendi.
5. **[TEST] T-21d:** UPDATE denemesinden önce JWT claims u_a'ya geri alınmadığından RLS `update_own` satırı gizliyor (0 satır) ve hata üretilmiyordu. Claims geri alma adımı eklendi.

## Kalan Riskler

1. **Eski zincirde istemci DML grant'ları eksik (Faz1 dışı):** Yeni CLI davranışı nedeniyle `subjects`, `topics`, `subtopics`, `curriculum_versions`, `questions`, `competitions` gibi tablolarda anon/authenticated/service_role için SELECT/DML yetkileri tanımlı değil (yalnız REFERENCES/TRIGGER/TRUNCATE kalıntısı). Faz1 tablolarının modeli doğru; bu boşluk, ilgili uygulama özellikleri devreye alındığında 066'daki desenle fix-forward migration gerektirecektir. Bu çalışmada bilinçli olarak dokunulmadı.
2. **Versiyon kontrol durumu:** Faz1 migration dosyaları (057–066), QA suite (`scripts/qa_faz1_local_validation.sql`) ve rapor henüz git'te izlenmiyor/commit'lenmedi. Commit kararı kullanıcıya aittir.
3. `db reset` çıktısında "no files matched pattern: supabase/seed.sql" uyarısı bilgi amaçlıdır; seed dosyası henüz yok.

## Sonuç ve Öneri

- Zincir `supabase db reset` ile sıfırdan **hatasız** oynatıldı; QA **21/21 PASS**.
- Suite tek transaction + ROLLBACK kullandığından veritabanında kalıcı iz bırakmaz; ayrıca canlı veritabanında bağımsız kalıntı sorgusu da sıfır doğruladı.
- **Başka bir `db reset` gerekmez.** Bir sonraki adım olarak Faz1 dosyalarının commit edilmesi ve Security Reviewer / Code Reviewer read-only incelemeleri (docs/architecture/059-product-rules.md akışı) önerilir.
