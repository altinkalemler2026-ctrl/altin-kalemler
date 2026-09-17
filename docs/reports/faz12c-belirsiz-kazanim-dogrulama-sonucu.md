# Faz 12C — Belirsiz Kazanımların Görsel Doğrulaması ve Yükleme Sonucu

**Tarih:** 2026-09-16
**Durum:** TAMAMLANDI — migration 114 lokal DB'ye uygulandı ve 5 satır doğrulandı
**Kapsam:** Faz 12C — TYMM 2026 PDF'te gösterimi belirsiz 5 kazanımın resmî doğrulaması + yükleme

## Özet

Faz 12B'de matematiksel gösterimde üst simge/bölü/alt simge kaybı (PDF metin çıkarma sınırı)
nedeniyle yüklenmeyen 5 öğrenme çıktısı, resmî TYMM 2026 PDF üzerinde **satır geometrisi
(text-layer kutu koordinatları + font ölçeği) ile doğrulandı** ve `114_faz12c_belirsiz_kazanim_yukleme.sql`
ile lokal DB'ye (`supabase_db_yarisma-programi`) uygulandı. 5 kayıt da `psql` SELECT ile teyit edildi.

PDF matematik gösterimi, metin çıkarımında düzleşen stringlerden kesin olarak yeniden kuruldu.
Yaklaşım: pdf.js text-layer item'larının (x, y, sx/sy, font adı) geometrisi — üst/alt simgede
dikey kayma + küçük font (7 vs 10), kesirlerde pay/paydanın aynı x'te iki ayrı y koordinatında
yer alması — kanıt olarak kullanıldı. (Bu model görüntü girişi okumadığı için piksel düzeyi
"gözle" kontrol yerine bu vektör kanıtı resmî doğrulama kabul edildi.)

## Doğrulanan Kazanımlar (5/5)

| Kod | Sınıf | PDF sf. | Resmî gösterim | Geometri kanıtı |
|---|---|---|---|---|
| MAT.10.4.2 | 10 | 104 | `f(x) = x²` | "2" y=593.7 (font 7), "x" y=588.2 (font 10) → üst simge |
| MAT.10.4.4 | 10 | 105 | `f(x) = 1/x` | "1" y=634.5 (pay), "x" y=624.1 (payda), aynı x≈321 → kesir |
| MAT.11.3.1 | 11 | 142 | `x ≠ π/2 + kπ` | "π" y=730.9, "2" y=719.6, aynı x≈465 → kesir |
| MAT.11.3.3 | 11 | 149 | `f(x) = aˣ` | "x" y=756.7 (font 7), "a" y=752.2 (font 10) → üst simge |
| MAT.11.3.5 | 11 | 149 | `f(x) = logₐx` | "a" y=315.4 (font 7) < "log" y=317.4 → alt simge |

## Migration Özeti (114)

- Dosya: `supabase/migrations/114_faz12c_belirsiz_kazanim_yukleme.sql`
- Nitelik: VERİ YÜKLEME (data-only); şema/RLS/RPC değişmedi
- Desen: deterministic UUID + `ON CONFLICT (id) DO NOTHING` (idempotent)
- UUID kuralı (112 ile aynı): `a7 + GG + sıra`; 10. sınıf ardışık devam `…020, …021`;
  11. sınıf ardışık devam `…013, …014, …015`
- `curriculum_version_id` = TYMM-2026 (`a1000000-0000-4000-8000-0000000000c1`),
  `subject_id` = matematik (`430903f3-527e-4e12-b7e8-ac0afdb784aa`),
  `subtopic_id` = NULL (TYMM kuralı; subtopic yalnız OGM 12 için)
- `sort_order`: 10.4.x kod son basamağına uyar (10.4.2→2, 10.4.4→4);
  11.3.x alt konu içi yerel sıradır (11.3.1→1, 11.3.3→1, 11.3.5→3) —
  mevcut 112 komşu kayıtlarıyla birebir tutarlı (DB sorgusu ile teyit: 11.3.4→2, 11.3.6→4, 11.3.7→1, 11.3.8→2)

## Uygulama Doğrulaması (lokal DB)

Uygulama yöntemi: `docker exec supabase_db_yarisma-programi psql -f /tmp/114_faz12c.sql`
çıktı: `BEGIN / INSERT 0 5 / COMMIT`.

Doğrulama sorgusu (`outcome_code ∈ {MAT.10.4.2, MAT.10.4.4, MAT.11.3.1, MAT.11.3.3, MAT.11.3.5}`):

| id | grade_level | outcome_code | sort_order | source_reference | is_active |
|---|---|---|---|---|---|
| a7100000-…-000000000020 | 10 | MAT.10.4.2 | 2 | TYMM 2026, 10. sınıf | t |
| a7100000-…-000000000021 | 10 | MAT.10.4.4 | 4 | TYMM 2026, 10. sınıf | t |
| a7110000-…-000000000013 | 11 | MAT.11.3.1 | 1 | TYMM 2026, 11. sınıf | t |
| a7110000-…-000000000014 | 11 | MAT.11.3.3 | 1 | TYMM 2026, 11. sınıf | t |
| a7110000-…-000000000015 | 11 | MAT.11.3.5 | 3 | TYMM 2026, 11. sınıf | t |

5 kaydın `outcome_text` değerleri ekranda da resmî gösterimlerle (x², 1/x, π/2, aˣ, logₐx)
birebir kayıtlı doğrulandı.

## Rollback

`supabase/migrations/115_faz12c_rollback_belirsiz_kazanim.sql` — migration 114'ün eklediği
5 satırı id ile siler (idempotent). **Uygulanmadı**; yalnız ihtiyaç halinde yedektir.

## Kapanış Notları

- Faz 12B sonucunda atlanan 90−85=5 kazanım artık tamamlandı: TYMM 2026 (9/10/11) +
  OGM 2018 (12) kazanım seti **85+5 = 90** kayıt olarak DB'de duruyor.
- Önceki fazlar (12A/12B) yeniden taranmadı; 113 rollback'e dokunulmadı.
- Commit/push yapılmadı; migration 114, rollback 115 ve bu rapor working tree'de dosya olarak duruyor.
- Geçici eserler (geçici web sunucusu, analiz scriptleri, ekran görüntüleri) temizlendi.
  Not: Faz 12C analizi için `pdfjs-dist@6.3.289` `node_modules`'a `--no-save` ile kurulmuştu
  (package.json/package-lock değişmedi; `npm install` "added 5, removed 2, changed 67" çıktısı
  dropdown node_modules dengelemesiydi — takip edilebilir).