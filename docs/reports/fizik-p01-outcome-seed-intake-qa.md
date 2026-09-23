# Fizik TYMM 2026 Outcome Seed — Intake QA Raporu (BLOCKED → PASS)

Tarih: 2026-09-23
Kapsam: Faz 22 — Migration 125 `tymm_2026_fizik` outcome seed + disposable yerel intake QA (2 tur)
Sonuç: **PASS**
Koşul özeti: `SAFE_FOR_LOCAL_INTAKE: YES` · `SAFE_FOR_PUSH: NO`
Önceki durum: `docs/reports/fizik-p01-intake-readiness-qa.md` → `BLOCKED_BY_MISSING_CURRICULUM_SEED` (2026-09-22)

---

## 1. Yapılan iş

Önceki raporun "Sonraki zorunlu küçük adım" planı birebir uygulandı:

1. Migration `supabase/migrations/125_faz22_fizik_tymm_2026_outcome_seed.sql` (veri-only,
   append-only) — resmî TYMM 2026 Fizik Öğretim Programı'ndan (PID 2254,
   `fizik-p01-curriculum-mapping-evidence.md` kanıtı) birebir uyumla 22 kanonik `FIZ.*`
   outcome seed'ler; mevcut kayıtlara dokunmaz.
2. Yeni seed sonrası yetkili Fizik intake yeniden koşuldu → **PASS** (2 ayrı disposable tur).
3. Mevcut inventory'ye göre 123/124 regression suite **değişmedi**: iki turda da 67/67 PASS.

Doğrulama yalnız yeni, disposable QA klonlarında yapıldı; ana local stack / hosted DB'ye
**hiçbir yazım yapılmadı** (yalnız salt-okunur SELECT). Commit/stage/push: **YAPILMADI**.

## 2. Migration 125 özeti (kanıtlanan desen)

| Alan | Değer |
|---|---|
| Versiyon satırı | `curriculum_versions`: id `a1000000-0000-4000-8000-0000000000c3`, `tymm_2026_fizik`, academic_year `2026-2027`, is_active=true, is_default=false, published_at `2026-05-18` |
| Matematik korunumu | `...c1` (`tymm_2026`) is_default=true olarak **tek default** kaldı (059 partial unique index korur) |
| Subject | `57a959a8-43e7-4f0e-8b54-a7299386fdb3` (Fizik, migration 045) — tüm satırlarda sabit |
| Outcome deseni | 22 satır `curriculum_outcomes`, topic_id/subtopic_id NULL, outcome_code `FIZ.(9|10|11|12).N.N`, source_reference `TYMM 2026 Fizik ...` |
| UUID ailesi | cv `...c3`; outcome `a909.../a90a...` serisi (Matematik `a7*` ailesiyle çakışmaz) |
| Idempotency | `ON CONFLICT (id) DO NOTHING`; yeniden uygulama 0 yeni satır (F-04 PASS) |

22 kod: 9→6 (`9.1.1, 9.1.2, 9.1.4, 9.2.1, 9.2.2, 9.2.4`), 10→5 (`10.1.3, 10.2.1,
`10.3.2, 10.3.4, 10.3.5`), 11→8 (`11.1.1, 11.1.3, 11.1.4, 11.1.7, 11.1.10, 11.2.4,
11.2.5, 11.2.6`), 12→3 (`12.1.3, 12.1.5, 12.1.6`). Paketteki 22 unique FIZ kodu ile birebir
eşleşir (32 karşılaşma → 22 unique).

## 3. Yeni QA suite: `scripts/qa_fizik_seed_intake_local.sql`

Tek transaction + sonunda ROLLBACK (kalıcı kayıt yok), `_qa_fizik_results` → TOPLAM özeti.
Test matrisi (19 assertion):

| Test | Doğrulanan |
|---|---|
| F-01a/b | `tymm_2026_fizik` aktif+default değil; Math tek default korundu |
| F-02a/b | 22 outcome, dağılım 6/5/8/3; Fizik subject, aktif, topic NULL, kod kalıbı, metin, source |
| F-03 | 22 kodun tamamı migration-124 çözümleme sorgusuyla tek satıra çözülür |
| F-04 | seed idempotency (cv 1→1, outcome 22→22) |
| F-05a–f | Yetkili Fizik intake happy-path (FIZ.9.1.1, 10.3.4, 11.1.10, 12.1.6): ingested, 4 staging (`...c3`), 4 spec ready, 8 deterministic validation, preflight (adapter v1.1, pub yasağı, review_required) |
| F-06 | Fail-closed: seed dışı `FIZ.9.1.3` → rejected + `outcome_not_found`, staging yok |
| F-07 | Fail-closed: `FIZ.9.1.1 @ grade 10` → `outcome_not_found`, staging yok |
| F-08a–c | ACL: service_role→kabul, admin(super_admin)→kabul, izinsiz→P0001 |
| F-09 | DTO iç yapı sızdırmaz + automatic_publication_allowed=false |
| F-10 | Regression: `MAT.9.1.1` intake seed sonrası da ingested (Math zarar görmedi) |

## 4. Disposable tur sonuçları

Ortam (her turda yeni, izole): image `public.ecr.aws/supabase/postgres:17.6.1.155`,
default bridge, benzersiz ad/port/volume, migrate `psql -U supabase_admin -d postgres
-q -v ON_ERROR_STOP=1` (apply_mig_tmp.sh deseni).

| Tur | Klon | Port | Migration 001–125 | Fizik QA (19) | Regression 123/124 (67) |
|---|---|---|---|---|---|
| 1 | `supabase_db_fiz-p01-r2` (+`fiz-p01-r2-data`) | 56524 | **ALL_MIGRATIONS_OK** | **19/19 PASS** | **67/67 PASS** |
| 2 | `supabase_db_fiz-p01-r3` (+`fiz-p01-r3-data`) | 56525 | **ALL_MIGRATIONS_OK** | **19/19 PASS** | **67/67 PASS** |

Tur-2'den salt-okunur kanıt sorgusu (silinmeden önce):

```
tymm_2026       | 2026-2027 | t | t | 2026-05-13   (default, aktif)
tymm_2026_fizik | 2026-2027 | f | t | 2026-05-18   (aktif, default değil)
22 | 9 | 12                                   -- outcome sayısı=22, sınıf 9..12
9|6  10|5  11|8  12|3                        -- dağılım
```

## 5. Regression doğrulaması

Mevcut `scripts/qa_candidate_md_intake_123_local.sql` suite'i her iki turda **67/67 PASS**
ile aynı kaldı — seed'in 123/124 intake mekanizması, Matematik seed'i ve ACL davranışı
üzerinde değişiklik/bozulma yok.

## 6. Temizlik ve envanter karşılaştırması

- Kaldırılanlar (yalnız bu oturumda oluşturulup bu göreve ait kanıtlanan kaynaklar):
  - container `supabase_db_fiz-p01-r2`, volume `fiz-p01-r2-data`
  - container `supabase_db_fiz-p01-r3`, volume `fiz-p01-r3-data`
- İşlem sonrası geriye yalnız önceden mevcut `supabase_db_fiz-p01-r1` (Exited 255,
  port 56523) + `fiz-p01-r1-data` kaldı — **bu oturumun üretmediği artık**; faz
  raporundan "kesintiden kalan önceki tur" olarak değerlendiriliyor. Bu oturum ona
  dokunmadı; kaldırılması için kullanıcı onayı gerekir (faz sonunda öneri).
- Dokunulmayan kullanıcı stack'leri: `supabase_db_yarisma-programi`, `supabase_db_supa-typesfix`,
  `supabase_db_faz14e-qa`, `supabase_db_qa-iso19`, `db_f11_clean`, faz11iso vb.

## 7. Kontrol ve güvence

- Ana local stack / hosted DB'ye yazım YOK; yalnız salt-okunur SELECT (subject/outcome
  teyidi). `SAFE_FOR_LOCAL_INTAKE: YES` — kanonik Fizik seed'i ve iki tur PASS ile.
- `SAFE_FOR_PUSH: NO` — migration 125, QA scripti ve bu rapor local'da untracked;
  commit/stage/push hiçbir biçimde yapılmadı. Push için faz sonunda ayrıca açık onay aranır.
- Migration 125 ve QA fixture'ları; ana sözleşmedeki "her faz tek yerel commit" kuralına
  bağlıdır — bu görevde commit yapılmadı (kullanıcıya rapor edilir; onay sonrası planlanır).

## 8. Sonuç ve sonraki adım

- Migration 125 kanonik Fizik outcome seed'i iki bağımsız disposable turda geçerlendi;
  124'ün fail-closed kapısı artık Fizik için açık ve doğru çözümler üretiyor.
- Sonraki adım (uygulanmadı): kullanıcı onayıyla 125'in faz commit'ine alınması ve
  push sonrası CI doğrulaması; ardından Fizik P01 paketi için gerçek intake çalıştırılması.

---

### Amaç: Faz 22 candidate-md intake köprüsü — Fizik P01 seed + intake geçişi

Dosya: `docs/reports/fizik-p01-outcome-seed-intake-qa.md` ·
Disposable ortamlar temizlendi · Kullanıcı modified/untracked dosyalarına dokunulmadı.