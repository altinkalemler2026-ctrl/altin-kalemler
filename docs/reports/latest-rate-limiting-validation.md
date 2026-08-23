# Faz 4 Doğrulama Raporu — Rate Limiting (075/076)

- **Tarih:** 23 Ağustos 2026
- **Kapsam:** Öğrenciye açık dört training RPC'sine kullanıcı-bazlı, DB tabanlı sabit-pencereli istek sınırı (Faz 4 read-only analiz → kullanıcı onayı + iki zorunlu düzeltme).
- **Ortam:** Yalnız yerel (`supabase db reset` dahil). Production, `.env`, secret, login/link/db push **dokunulmadı**.
- **Git:** Commit/push **YOK** (kullanıcı talimatı); yalnız çalışma ağacı değişti.

## 1. Uygulanan Zorunlu Düzeltmeler

| # | İstem | Karşılanma |
|---|-------|------------|
| K-1 | Pencere hesabı `date_trunc('minute', now())` OLMAZ; `to_timestamp(floor(extract(epoch from clock_timestamp()) / p_window_seconds) * p_window_seconds)` olmalı | `075_rate_limiting_core.sql` — `v_win` ifadesi birebir bu formül; T-12 pencere eşitliğini kanıtlar |
| K-2 | Geçersiz iç parametrede fail-closed: `p_limit`/`p_window_seconds` > 0 doğrulaması | Helper gövdesi başında üç ayrı kontrol (`rpc_name` boş/64+ karakter, `p_limit < 1`, `p_window_seconds < 1`) → P0001 `Rate limit yapilandirmasi gecersiz (...)`; T-04/05/06 |

## 2. Mimari Özet

- **Katman:** Yalnız `auth.uid()`. RPC trafiği Next sunucusundan çıktığı için IP katmanı Postgres'te anlamsız; cihaz izi kapsam dışı.
- **Depo:** Redis/edge yerine Postgres tablosu (`rpc_rate_limits`). Yeni infra yok; atomiklik 063/068 sayaç deseninin aynısı.
- **Pencere:** Epoch hizalı sabit pencere; PK `(user_id, rpc_name, window_start)`.
- **Atomik tüketim:** `INSERT ... ON CONFLICT DO NOTHING` + tek ifade `UPDATE ... WHERE hit_count < p_limit RETURNING 1`. Guard'lı UPDATE satır kilidinde serileşir; toplam `hit_count` limiti ASLA aşamaz. Reddedilen istek kota tüketmez.
- **Limit matrisi (076):**

| RPC | Anahtar | Limit | Pencere | Bağlantı noktası |
|-----|---------|-------|---------|------------------|
| `select_training_questions` | `training_select` | 90 | 3600 sn | auth guard'ından hemen sonra; bağlam/dönem çözümünden önce |
| `get_my_weekly_usage` | `weekly_usage` | 60 | 300 sn | auth guard'ından hemen sonra |
| `prepare_competition_pack` | `pack_prepare` | 30 | 3600 sn | yarışma satırı `FOR UPDATE` kilidinden önce |
| `submit_training_attempt` | `training_submit` | 240 | 3600 sn | duplicate/replay ön-okumasından SONRA → replay kota tüketmez |

- **Güvenlik modeli:** `rpc_rate_limits`: RLS açık + policy yok + anon/authenticated'a hiçbir grant yok. `_faz4_consume_rate_limit`: SECURITY DEFINER, `search_path=''`, EXECUTE'u public/anon/authenticated'dan alınmış — hiçbir role grant verilmez (yalnız definer RPC gövdeleri içinden çağrılır).
- **Mesajlar:** DB ASCII Türkçe: `Cok fazla istek gonderildi; lutfen kisa bir sure sonra tekrar deneyin.` (P0001), `Kimlik dogrulamasi gerekli.` (42501), config için `Rate limit yapilandirmasi gecersiz (...)`. UI sabit Türkçe: "Çok hızlı işlem yaptınız; lütfen birkaç saniye bekleyip tekrar deneyin." Ham DB metni kullanıcıya sızmaz.

## 3. Dosya Envanteri

| Dosya | Değişim |
|-------|---------|
| `supabase/migrations/075_rate_limiting_core.sql` | YENİ — sayaç tablosu + helper + revokelar |
| `supabase/migrations/076_rate_limit_wire_rpc.sql` | YENİ — dört RPC'nin birebir yeniden yayını + FAZ4 imli tek ekleme her gövdede + EXECUTE drift-guard |
| `src/lib/training/errors.ts` | `rateLimit` mesajı + `RATE_LIMIT_PATTERN = /cok fazla istek/i` + eşleme sırası |
| `src/lib/training/errors.test.ts` | +2 test: rate mesajı UI'ya çevrilir (PostgrestError şekli dahil); iç yapılandırma hatası genel mesaja düşer (sızma yok) |
| `src/lib/supabase/types.ts` | Yeniden üretim (`rpc_rate_limits`, `_faz4_consume_rate_limit` imzaları) |
| `scripts/qa_faz4_local_validation.sql` | YENİ — T-01..T-22 suite |
| `scripts/qa_faz4_parallel_probe.sql` | YENİ — aynı-kullanıcı son-kota yarışı probe'u |
| `.github/workflows/ci.yml` | `run_suite faz4 parsed` + "Parallel rate-limit probe (Faz 4)" adımı + özet satırı |

## 4. Doğrulama Sonuçları (yerel)

### Migration zinciri
- `supabase db reset`: 001→**076** uyarısız uygulandı (seed.sql yok bilgisi bilinen durum).
- Dinamik zincir assertion'ı CI'da dosya listesinden türetir (075/076 otomatik kapsanır).

### SQL QA suite'leri

| Suite | Sonuç |
|-------|-------|
| Faz 1 | 34/34, kalan=0 |
| Faz 2 | 49/49, kalan=0 |
| Faz 3 | 34 PASS / 0 FAIL, kalan=0 (self-raising) |
| Faz 3.5 | 24/24, kalan=0 |
| **Faz 4** | **22/22, kalan=0** |

### Paralel probe'lar (gerçek OS paralelliği)

| Probe | Sonuç |
|-------|-------|
| Faz 2 farklı-kullanıcı (work) | FINAL_USED=500 / 500, VERIFY_PASS |
| Faz 2 aynı-kullanıcı (same) | tavan 500 korundu, VERIFY_PASS |
| **Faz 4 son-kota yarışı** | a=**OK**, b=**LIMITED** (tam bir OK + bir LIMITED), `hit_count=5`, ek pencere yok, VERIFY_PASS |

### TS kalite kapıları

| Kapı | Sonuç |
|------|-------|
| `npx tsc --noEmit` | exit 0 |
| `npm run lint:faz3` | exit 0 |
| `npm run test:unit` + integration | **61/61** (önceki 59 + 2 yeni) |
| `npx yaml-lint .github/workflows/ci.yml` | başarılı |

### Faz 4 suite vurguları
- **T-01..03:** anon helper'ı çağıramaz (EXECUTE-denied); anon/authenticated sayaç tablosunu okuyamaz (grant yok → 42501).
- **T-04..06:** config fail-closed üç varyantta kanıtlandı.
- **T-07..09:** limit dolusu tüketim tek pencere satırında birikir; 4.'sü P0001 rate mesajıyla reddedilir; reddedilen istek sayacı arttırmaz (hit=3 kalır).
- **T-10..12:** B kullanıcısı A'nın dolu sayacından bağımsız; kaydedilen `window_start` epoch hizalı formülle birebir eşit; önceki pencereye kaydırılan dolu satır yeni pencereyi bloklamaz (yeni hit=1, eski hit=3 korunur).
- **T-13..15:** Eşiğe taşınan sayaçlarla üç RPC de doğal hata mesajlarından (dönem/bağlam/yarisma-bulunamadı) ÖNCE rate mesajı verir → gate'in bağlantı noktası kanıtlanır.
- **T-16..20:** Submit zinciri: K1 normal yazım (`duplicate=false`, grading DB'de), bilet kesildi (hit=1); sayaç 240'a taşındıktan sonra replay K1 hâlâ gerçek yanıtla döner (`duplicate=true`) ve **kotayı tüketmez** (hit=240 kalır); yeni anahtar K2 reddedilir.
- **T-21..22:** Drift guard: helper EXECUTE'u kapalı, tablo grant'sız (075 son durumu).

## 5. Sınırlar ve Notlar

- Suite/probe'lar tamamen rollback/idempotent; kalıcı artefakt bırakmaz (temizlik sayaçları 0 gösterdi).
- Rate-limit tablosu zamanla birikir (aktif kullanıcı × rpc × pencere). Prod operasyon notu: periyodik `DELETE WHERE window_start < now() - interval '1 day'` temizlik işi önerilir (uygulama kapsam dışı, prod planına eklenecek).
- Pencere sınırında (saat/5 dk dönümü) test ile kontrol arasındaki mikrosaniyelik geçiş teorik bir yanlış-negatif üretebilir; yerel koşularda görülmedi, CI deterministik değildir ama idempotent yeniden koşuyla yönetilir.
- `submit` replay muafiyeti yalnız aynı `client_key` için geçerlidir; saldırgan her denemede yeni anahtar üretirse 240/saat tavanı yine devrededir.

## 6. Üretim Kontrol Listesi (güncel)

1. Supabase Dashboard → Database → Backups: mevcut anlık yedek.
2. Sıra: 001…074 (mevcut plan) → **075** → **076**. Her biri ayrı `migrate` turu; 076 sonrası EXECUTE matrisi sorgusu teyit edilir.
3. 076 yayın sonrası canlı trafikte ilk dakika log izleme: beklenmedik P0001 rate patlaması varsa limit matrisi gözden geçirilir (kod geri alımı migration gerektirmez — limitler helper argümanıdır).
4. Prod QA: T-01..03 + T-21..22 alt kümesi (salt-okunur/etkisiz doğrulamalar) dashboard SQL editöründe koşturulabilir; veri yazan testler prod'da ÇALIŞTIRILMAZ.

---
*Rapor yalnızca yerel doğrulamayı belgeler; commit/push yapılmadı. Ayrı bir read-only inceleme turu takip edecektir.*
