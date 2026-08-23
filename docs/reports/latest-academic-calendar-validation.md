# Latest Academic Calendar (Faz 3.5) Validation Report

- **Revizyon:** 2 — R-1 eşzamanlılık düzeltmesi eklendi (migration **074** DB backstop)
- **Tarih:** 23 Ağustos 2026
- **Kapsam:** `academic_weeks` admin yönetimi — additive migration 073 + güvenli RPC yüzeyi + `/admin/academic-calendar` ekranı + SQL QA süiti + CI güncellemesi + **074 yıllar-arası çakışma DB backstop'u**
- **Ortam:** Yalnız yerel Supabase/Docker (`supabase_db_yarisma-programi`), Node v24.19.0
- **Sonuç:** **TÜM DOĞRULAMALAR PASS** — Faz 3.5 QA **24/24**, Faz 1 34/34, Faz 2 49/49, Faz 3 kalan=0, paralel probe work+same VERIFY_PASS, vitest unit 57/57 / full **59/59**, tsc/lint/yaml temiz, dinamik zincir iddiası **73|074** ile doğrulandı

## 1. Güvenlik Kuralları → Uygulama Eşlemesi

| # | Zorunlu kural | Uygulama |
| --- | --- | --- |
| 1 | Admin olmayan authenticated ve anon hiçbir takvim RPC'sini kullanamaz | Tüm RPC'lerde fonksiyon içi `calendar.manage` kontrolü; okuma fonksiyonları dahil (T-01..T-08) |
| 2 | Her mutasyon RPC'si fonksiyon içinde yetki kontrolü tekrarlar | `upsert_week`/`delete_week` ilk satır olarak `academic_calendar_has_permission('calendar.manage')`; yoksa `42501` |
| 3 | `search_path=''`, `auth.uid()`, PUBLIC/anon revoke, yalnız authenticated EXECUTE | Beş fonksiyonun hepsinde; her biri için `revoke execute from public, anon, authenticated` + `grant to authenticated` |
| 4 | `academic_weeks` istemciye açılmaz | Tablonun RLS/ACL modeli DOKUNULMADI (policy yok, anon/authenticated privilege yok); UI yalnız DEFINER RPC okur |
| 5 | Farklı yıllar arası çakışma RPC düzeyinde RED | Upsert'te `daterange '[)' &&` cross-year ön-kontrolü → P0001; **074'ten itibaren ayrıca DB seviyesinde global EXCLUDE (23P01) — yarış penceresi kapalı** (T-11, T-19) |
| 6 | Başlamış/geçmiş hafta (`starts_at <= current_date`) değiştirilemez/silinemez | Upsert mevcut satır kontrolü + delete kontrolü; iki ayrı ASCII mesaj (T-12/T-13) |
| 7 | Attempt referanslı hafta silinemez | `EXISTS(student_question_attempts WHERE academic_year=… AND week=…)` (T-14) |
| 8 | Yalnız gelecek + referanssız hafta silinir | 6+7 kurallarının bileşkesi; pozitif yol w21 ile kanıtlandı (T-15) |
| 9 | Takvim boşsa Training fail-closed korunur | `_faz2_require_period` P0001 "Gecerli akademik donem bulunamadi" + resolver boş (T-18); Training kodu/akışı DEĞİŞTİRİLMEDİ |

## 2. Migration 073 — İçerik

`supabase/migrations/073_academic_weeks_admin_management.sql` (additive; şema değişikliği yok):

1. `admin_permissions`: `'calendar.manage'` INSERT … ON CONFLICT DO UPDATE (idempotent).
2. Rol bağlama: `super_admin` **ve** `content_admin` → CROSS JOIN + ON CONFLICT DO NOTHING (idempotent).
3. `academic_calendar_has_permission(text)` — 047 deseninin `search_path=''` sürümü.
4. `academic_calendar_list_years()` → `(academic_year, week_count)`; yetkili özet.
5. `academic_calendar_list_weeks(p_year)` → haftalar + sunucu-otoritatif `is_started boolean` (`starts_at <= current_date`); UI saat dilimi hesabına yaslanmaz.
6. `academic_calendar_upsert_week(p_year, p_week, p_starts_at, p_ends_at)` — girdi doğrulama, başlamış-koruma, aynı-yıl ve farklı-yıl çakışma redleri, `ON CONFLICT (academic_year, week) DO UPDATE`.
7. `academic_calendar_delete_week(p_year, p_week)` — bulunamadı/başlamış/referans redleri.
8. Hata mesajları ASCII Türkçe; `errcode='42501'` (yetki) / `'P0001'` (iş kuralı).

Karar notu: YENİ hafta eklemede geçmiş tarih ENGELLENMEZ (üretim ortasında yıl geri yüklemesi/backfill ihtiyacı); mevcut başlamış haftanın değiştirilmesi/silinmesi ise kesin kapalıdır. PK çakışması upsert'i update'e yönlendirir ve oradaki koruma devreye girer.

## 2b. Migration 074 — R-1 DB Backstop (Rev. 2 eki)

`supabase/migrations/074_academic_weeks_cross_year_db_backstop.sql` (additive):

1. **`academic_weeks_no_cross_year_overlap`** — `exclude using gist (daterange(starts_at, ends_at, '[)') with &&)`: yıldan bağımsız GLOBAL çakışma yasağı (23P01). 067 aynı-yıl kuralı SOKULMEDİ (kapsanan daha sıkı savunma); RLS/ACL değişmedi; btree_gist gerekmez.
2. **upsert RPC güncellemesi:** INSERT adımı `exception when exclusion_violation` bloğuyla 074 backstop'unu yakalar ve ASCII Türkçe P0001'e çevirir: `'Tarih araligi mevcut bir akademik haftayla cakisiyor; eszamanli guncelleme algilandi.'` — eşzamanlılık yarışında bile istemci hep kürli mesaj görür.
3. EXECUTE matrisi upsert için bilinçli olarak yeniden teyit edildi (drift guard).
4. İstemci eşlemesi (`academic-calendar-errors.ts`): `/eszamanli guncelleme algilandi/i` **ve** ham-23P01 fallback `/exclusion constraint/i` → yeni `concurrentOverlap` mesajı; constraint adı sızmaz.

Eşzamanlılık modeli: exclusion index ikinci yazanı bekletir; ilk işlem commit olursa ikincisi 23P01 alır (unique gibi). Böylece iki farklı yıl için eşzamanlı onaylı upsert imkânsızlaşır.

## 3. UI Katmanı

| Dosya | İçerik |
| --- | --- |
| `src/lib/admin/academic-calendar-errors.ts` | ASCII DB mesajlarını Türkçe'ye çeviren desen tablosu + girdi/başarı mesajları; bilinmeyen hata generic'e düşer, ham mesaj SIZMAZ |
| `src/app/(admin)/admin/academic-calendar/actions.ts` | `"use server"`; `upsertWeekAction`/`deleteWeekAction`: FormData → girdi doğrulama (RPC'siz Türkçe red) → `auth.getUser` (oturum yoksa RPC yok) → typed RPC → hata mapli flash redirect → `revalidatePath` |
| `src/app/(admin)/admin/academic-calendar/page.tsx` | Layout gate'i (`questions.view`) üstüne sayfa düzeyi `calendar.manage` kontrolü (yoksa `/dashboard`); yıl seçici GET formu; hafta listesi; satır içi düzenleme (tarih input'lu upsert formu); silme butonları; `is_started` bayrağıyla başlamış satırlarda disabled + rol="alert"/"status" flash bantları |

Desenler mevcut `(admin)/layout.tsx` + `teacher-reviews` + training action disiplininden alındı; Training UI'a işlevsel dokunuş YAPILMADI (yalnız mevcut dönem-kapalı davranışı korunur).

## 4. Doğrulama Sonuçları

| # | Doğrulama | Gözlenen | Durum |
| --- | --- | --- | --- |
| V-01 | Migration zinciri: `npx supabase db reset` → 001–**074** | Hatasız uygulandı | PASS |
| V-02 | Tip üretimi: `supabase gen types typescript --local` (cmd /c redirect, UTF-8) | 5 `academic_calendar_*` imzası geldi (074 imza değiştirmez) | PASS |
| V-03 | Faz 3.5 SQL QA (`qa_faz35_local_validation.sql`) | Son satır `24\|24\|0`; `\|FAIL\|` yok; temizlik `0\|0\|0\|0`; **T-19 DB backstop 23P01, T-20 constraint mevcudiyeti** | PASS |
| V-04 | Faz 1 regresyon | `34\|34\|0` | PASS |
| V-05 | Faz 2 regresyon | `49\|49\|0` | PASS |
| V-06 | Faz 3 regresyon | `QA FAZ 3 TAMAM: kalan=0` | PASS |
| V-07 | Paralel probe (work: iki ayrı docker exec) | `FINAL_USED=500`×2 + `VERIFY_PASS` + `CLEANUP_OK` | PASS |
| V-08 | Paralel probe (same: tek sayaç) | `FINAL_USED=500` + `VERIFY_PASS` + `CLEANUP_OK` | PASS |
| V-09 | Vitest unit | 6 dosya, **57/57** (+2 eşzamanlılık eşleme testi) | PASS |
| V-10 | Vitest full (integration dahil) | 7 dosya, **59/59** | PASS |
| V-11 | `npx tsc --noEmit` | 0 hata | PASS |
| V-12 | `npm run lint:faz3` (genişletilmiş kapsam) | 0 hata | PASS |
| V-13 | `npx yaml-lint .github/workflows/ci.yml` | Başarılı | PASS |
| V-14 | Dinamik zincir iddiası pozitif simülasyon — **074 ile** | `73\|074` → DO → `CHAIN_OK` | PASS |
| V-15 | Dinamik zincir iddiası negatif simülasyon | beklenen=99 → `MIGRATION_CHAIN_FAIL`, psql exit=3 | PASS |

Not: İlk lint turunda `react-hooks/purity` ihlali saptandı (sayfa render'ında `Date.now()`). Çözüm olarak istemci saati terk edildi; `academic_calendar_list_weeks` artık sunucu-otoritatif `is_started boolean` döndürüyor ve sayfa/tip bu bayrağı kullanıyor. Rev. 2 turunda T-19 ilk koşuda 23505 aldı (T-11b'nin QA-CAL-2100 w5 PK'sıyla çakışma); test haftası w6'ya alınarak EXCLUDE yolu doğrulandı — sonrasında tüm süreçler yeniden koşuldu (tablodaki değerler son turdur).

## 5. CI Değişiklikleri (`.github/workflows/ci.yml`)

1. **Dinamik migration zinciri:** `expected_count` ve `latest_version` dosya listesinden türetilir, psql `-v` ile verilir, `set_config('qa.*', …, false)` oturum değişkeniyle DO-block'a taşınır (dollar-quote içinde psql ikamesi çalışmaz). Sabit 71/72 bağımlılığı kaldırıldı — 074+ migrasyonlarda CI dokunuşu gerekmez. `subjects_read_grant` (072) iddiaları korundu.
   - Düzeltme notu: `set_config` üç parametre ister; `is_local=false` tek `docker exec -i` oturumunda kalıcılık sağlar (ilk taslaktaki iki-parametre çağrısı V-14 öncesi yakalandı ve düzeltildi).
2. **QA adımı "Faz 1, 2, 3, 3.5":** `run_suite faz35 scripts/qa_faz35_local_validation.sql parsed` eklendi; özet/ayrıştırma mantığı ortak fonksiyonda.
3. Summary satırı güncellendi; "Reset database" adım başlığı sabit sayı yerine "dinamik" ifadesine çekildi. Önceki arc'in checkout/setup-node@**v5**, setup-cli@**v1** (2.115.0) + Verify adımları yerinde.
4. Sınırlama: CI adımları yerelde eşdeğer komutlarla doğrulandı; gerçek Actions koşusu izlenecek (bkz. R-6).
5. Rev. 2: dinamik zincir iddiasının 074 ile çalıştığı yerelde doğrulandı (V-14: `73|074 → CHAIN_OK`).

## 6. Test Envanteri (bu arc'te yeni)

| Dosya | Kapsam | Sonuç |
| --- | --- | --- |
| `scripts/qa_faz35_local_validation.sql` | 24 etiket: anon EXECUTE-red ×3; öğrenci in-func red ×2; yanlış-yetkili admin red ×2; admin okuma/upsert/liste ×3; aynı-yıl çakışma (mesaj doğrulamalı) + farklı-yıl çakışma (mesajlı) + çakışmayan farklı yıl OK; başlamış g/s ×2; attempt-referans red; gelecek+referanssız silme OK (+postgres-rolü tablo teyidi); hafta 99 red; resolver zinciri; boş takvim fail-closed ×2; **T-19: RPC'yi bypass eden doğrudan INSERT farklı yılla çakışamaz (23P01, 074 backstop); T-20: global EXCLUDE constraint mevcudiyeti**. Tek TRANSACTION + ROLLBACK; temizlik doğrulamalı | 24/24 |
| `src/lib/admin/academic-calendar-errors.test.ts` | Desen→Türkçe mesaj eşlemeleri, bilinmeyen hata generic'e düşer, ham DB mesajı sızmaz; **074 eşzamanlılık yakalama mesajı + ham 23P01 fallback (constraint adı sızmaz)** | 11/11 |
| `src/app/(admin)/admin/academic-calendar/actions.test.ts` | Girdi doğrulama, flash URL yapısı (`URLSearchParams`, `+` kodlaması dahil), RPC hata eşleme, başarı akışı | 8/8 |

## 7. Riskler, Bilinen Sınırlar, Kararlar

- **R-1 · Cross-year çakışma — ÇÖZÜLDÜ (Rev. 2, migration 074):** Eski durumda kural yalnız RPC ön-kontrolüydü; iki eşzamanlı admin çağrısı kontrolü birlikte geçebilirdi. 074 global EXCLUDE ile çakışma artık DB seviyesinde engelli (T-19: RPC'yi bypass eden doğrudan INSERT 23P01 alır); yarış penceresinde RPC `exclusion_violation` yakalayıp kürli Türkçe mesaja çevirir. Kalan not: constraint adı `academic_weeks_no_cross_year_overlap`; 067 aynı-yıl kuralı yerinde bırakıldı.
- **R-2 · Geçmiş tarihli YENİ hafta eklenebilir:** Bilinçli backfill kararı (raporda belgeli); mevcut başlamış satırın güncelleme/silmesi kesin kapalı.
- **R-3 · `list_weeks(p_year)` biçim doğrulamaz:** Boş kontrolü var; bilinmeyen yıl boş liste döner (zararsız).
- **R-4 · JS Date normalizasyonu:** `2026-02-30` regex+NaN kontrolünü geçer; PG date hatası generic mesaja düşer (sızıntı yok, UX notu).
- **R-5 · Flash mesajları URL'de taşınır:** React metin kaçışı + `mapCalendarError` kürsörü ile enjeksiyon/ham-hata riski yok. RPC rate-limit zaten genel backlog'da.
- **R-6 · Gerçek Actions koşusu henüz izlenmedi:** setup-cli kurulumu ve ~2GB start image pull süresi ilk koşuda gözlenecek.

## 8. Production Operasyon Adımları (geçiş öncesi)

1. **Yedek:** `pg_dump` tam yedek + config/storage yedekleri; geri dönüş planı yazılı olsun.
2. **Migration:** linked CLI `supabase db push` (veya psql ile 001…074 sıralı). 073 ve 074 additive ve idempotenttir; 074 constraint'i mevcut veriyle çakışırsa uygulama bilinçli olarak DURUR (fail-closed) — çakışan satır temizlenip tekrar denenir.
3. **Yetki:** 073 `calendar.manage` iznini ve super_admin/content_admin bağlarını kendisi oluşturur — ekstra SQL gerekmez.
4. **Rol ataması:** Gerçek yöneticilere content_admin/super_admin mevcut admin akışıyla atanır.
5. **Takvim doldurma:** `/admin/academic-calendar` üzerinden gelecek dönem haftaları girilir; gerekiyorsa geçmiş haftalar backfill amaçlı eklenir (sonradan değiştirilemez).
6. **Smoke:** anon erişim reddi, öğrenci Training akışı, admin ekran kontrolü; ilk Actions koşusunun yeşili izlenir.
7. **Geri dönüş:** 073/074 tersine alınabilir — 5 fonksiyonu `drop`, `academic_weeks_no_cross_year_overlap` constraint'ini `alter table … drop constraint` ve iki yetki tablosundaki kayıtları silmek yeterlidir; şema/veri artığı bırakmaz.

## 9. Git Teyidi

- Bu arc'te **commit/push yapılmadı** (onay bekleniyor). Rev. 2 sonrası `git status --short`: `M .github/workflows/ci.yml`, `M package.json` (lint:faz3 kapsamı), `M src/lib/supabase/types.ts`; yeni: `supabase/migrations/073_*.sql`, `supabase/migrations/074_academic_weeks_cross_year_db_backstop.sql`, `src/app/(admin)/admin/academic-calendar/*`, `src/lib/admin/academic-calendar-errors*`, `scripts/qa_faz35_local_validation.sql`, `docs/reports/latest-academic-calendar-validation.md`.
- Asla stage'lenmeyecekler: `.opencode/`, `opencode.json`, `supabase/snippets/`.
- Onay gelirse önerilen: tek commit — "Add academic calendar management with gated RPCs and QA coverage" (074 backstop dahil).
