-- ============================================================
-- 145_curriculum_cografya_tymm2026_agac.sql
-- Altın Kalemler — CURRICULUM-ALL-01 Coğrafya dilimi: TYMM 2026 Coğrafya
--   müfredat ağacının (28 ünite + 76 İçerik Çerçevesi maddesi + 76 yeni outcome)
--   YÜKLENMESİ ve tymm_2026_cografya curriculum_versions satırının OLUŞTURULMASI.
--
-- KULLANICI ONAYLI KAPSAM (2026-10-27)
--   - 1 sürüm + 28 topic + 76 subtopic + 76 outcome YÜKLENİR (9. sınıf: 7 ünite + 19 madde + 19 çıktı; 10. sınıf: 7 ünite + 18 madde + 18 çıktı; 11. sınıf: 7 ünite + 19 madde + 19 çıktı; 12. sınıf: 7 ünite + 20 madde + 20 çıktı).
--   - Coğrafya için DB'de ÖNCEDEN COG.* outcome / topic / subtopic YOKTUR
--     (2026-10-27 salt-okunur ölçüm; dry-run eşleşen=0). Bu yüzden bölüm 4'teki
--     gibi "mevcut kayıt linkleme UPDATE'i" YOKTUR — migration salt EKLEME yapar.
--
-- KAYNAK (yalnız resmî)
--   Türkiye Yüzyılı Maarif Modeli — Ortaöğretim Coğrafya Dersi (9, 10, 11 ve
--   12. Sınıflar) Öğretim Programı (2026); PDF basılı sayfa numaraları.
--   Yerel: docs/references/mufredat/2026-2027/tymm-2026-cografya-9-12.pdf
--   Ağaç:  docs/question-production/curriculum-mapping/cografya-9-12-kanonik-esleme-v1.md
--   Dry-run: scripts/mufredat-dry-run.ts --ders=cografya → cografya-dry-run-sonuc.md
--   (180/180 veri satırı, 28/76/76, eşleşen 0, metin farkı 0, engelli 0)
--
-- UUID ŞEMASI (142 deseni; aileler DB envanteriyle çakışmasız seçildi)
--   Mevcut deterministik aileler: a1=versions, a2=schedule_profiles, a3=MAT topics,
--   a4=schedule_items, a5=FIZ topics, a6=MAT subtopics, a7=MAT outcomes,
--   a8=FIZ subtopics, a9=FIZ outcomes. YENİ AİLELER (topics/subtopics/outcomes
--   tablolarında envanterle boş doğrulandı — information_schema + hedef tablo taraması):
--   Coğrafya topic    : b7 + GG (sınıf) → b7GG0000-0000-4000-8000-0000000000NN
--   Coğrafya subtopic : b8 + GG (sınıf) → b8GG0000-0000-4000-8000-0000000000NN
--   Coğrafya outcome : b9 + GG (sınıf) → b9GG0000-0000-4000-8000-0000000000NN
--     (NN = sınıf içi (ünite, k) sıralamasında kesintisiz sayaç, 001'den başlar)
--   Sürüm id: a1000000-0000-4000-8000-0000000000c6 (tymm_2026_cografya; a1 ailesinde c1/c2/c3'ten sonraki ilk boş değer).
--   Subject id: cae032d4-54c0-41d2-b420-17a88fd3770a (Coğrafya, migration 045).
--
-- AD / SLUG / SIRA KARARLARI (142 birebir)
--   - topic.name: 'COG.9.1 <ÜNİTE ADI>' deseni; ünite adı PDF'teki resmî
--     büyük harfli başlıktır ('N. ÜNİTE: ' öneki atılır).
--   - topic.slug : cografya-GG-N-<ünite-adı-slug>  (dry-run öneri formülüyle aynı).
--     DB kısıtı: UNIQUE (curriculum_version_id, subject_id, grade_level, slug).
--   - subtopic.name: İçerik Çerçevesi kutusundaki basılı madde (resmî).
--   - subtopic.slug: <topic-slug>-<madde-slug> (112 matematik deseni; UNIQUE (topic_id, slug)).
--   - subtopic.sort_order: sınıf içi kesintisiz (kutu sırası; ünite değişince sıfırlanmaz).
--   - outcome.sort_order: kodun son basamağı k (ünite-içi sıra) — 125/142 sözleşmesi.
--   - outcome.subtopic_id: NULL (kaynakta çıktı→alt konu ilişkisi numaralandırılmamıştır;
--     yakınlık/sıra/isim benzerliğiyle atama YASAKTIR — kanonik dosya §2, BLOKAJ-1 kuralı).
--   - source_reference: 'TYMM 2026 Coğrafya Öğretim Programı, s.NN' (125/142 deseni); NN = kazanım bloğunun
--     basılı sayfası (kanonik dosya §4/§5).
--
-- SÜRÜM SATIRI (125 fizik deseninden fark)
--   Fizik sürümü 125'te ayrı kurulmuştu; bu ders için curriculum_versions satırı YOKTU
--   (dry-run: 'BULUNAMADI'). Sürüm INSERT'i bölüm 0.5'tedir: is_default=false
--   (yıl-tek-default kısmi indeksi bozulmaz), UNIQUE (academic_year, framework) uyumlu.
--
-- İDEMPOTENCE
--   - Tüm INSERT'ler ON CONFLICT (id) DO NOTHING → tekrar koşum SIFIR yeni satır.
--   - GUARD: ağaç ya (0,0,0) (ilk uygulama) ya (28/76/76) dolu hâlde
--     olmalı; karışık/kısmi durum fail-closed durur. Dolu hâlde tüm id'ler tanınır.
--   - outcome_code'da UNIQUE KISIT YOKTUR (yalnız idx_curriculum_outcomes_code normal
--     indeks); mükerrer kod riski GUARD'ın benzersiz-kod denetimi + deterministik id ile
--     kapanır (142'nin iki katmanlı koruması).
--   - History: supabase_migrations.schema_migrations'a version='145' kaydı WHERE NOT
--     EXISTS ile idempotent eklenir; statements=NULL (psql koşumunda dosya kendi metnini
--     içine koyamaz; CLI uygulayan ortamda CLI statements'i doldurur — 142 notu birebir).
--
-- GERİ DÖNÜŞ: scripts/cografya-mufredat-geri-donus.sql (tek transaction;
--   76 outcome DELETE → 76 subtopic DELETE → 28 topic DELETE → sürüm satırı DELETE →
--   145 history DELETE; FK sırası korunur, fail-closed üçüncü-taraf referans taraması
--   içerir). Uygulama öncesi yedek (boş ön-durum kanıtı):
--   docs/references/mufredat/yedekler/cografya-on-yedek-20261027.sql
--
-- YASAKLAR / DOKUNULMAZLAR
--   - AK-M12-ILK-008 ve tüm matematik kayıtlarına (a3/a6/a7, c1/c2), Fizik kayıtlarına
--     (a5/a8/a9, c3) DOKUNULMAZ. Şema/RLS/RPC değişmez (data-only). Soru üretimi,
--     staging, takvim dağıtımı YOK. Geometri/Türkçe subjects satırlarına dokunulmaz.
-- ============================================================

BEGIN;

-- ============================================================
-- 0. ÖN-KOŞUL DENETİMİ (fail-closed; en küçük güvenli durum)
-- ============================================================
DO $guard$
DECLARE
  v_topic_sayi integer;
  v_subtopic_sayi integer;
  v_outcome_sayi integer;
  v_surum integer;
  v_yabanci integer;
  v_tanimli integer;
  v_benzersiz integer;
BEGIN
  -- Ders var mı?
  IF NOT EXISTS (SELECT 1 FROM public.subjects WHERE id = 'cae032d4-54c0-41d2-b420-17a88fd3770a') THEN
    RAISE EXCEPTION 'GUARD_145: Coğrafya subject satırı yok — migration 045 uygulanmamış ortam.';
  END IF;

  -- Sürüm satırı: ya hiç yok (ilk uygulama) ya da TAM bu çift var (tekrar koşum).
  SELECT count(*) INTO v_surum FROM public.curriculum_versions
   WHERE framework = 'tymm_2026_cografya' OR id = 'a1000000-0000-4000-8000-0000000000c6';
  IF v_surum > 0 THEN
    IF NOT EXISTS (SELECT 1 FROM public.curriculum_versions
                   WHERE id = 'a1000000-0000-4000-8000-0000000000c6' AND framework = 'tymm_2026_cografya'
                     AND academic_year = '2026-2027' AND is_default = false) THEN
      RAISE EXCEPTION 'GUARD_145: tymm_2026_cografya/a1000000-0000-4000-8000-0000000000c6 sürüm satırı çelişkili (farklı id/framework/is_default) — fail-closed dur.';
    END IF;
  END IF;

  -- Ağaç durumu: ya boş ya tam dolu. Kısmi/yabancı durum fail-closed.
  SELECT count(*) INTO v_topic_sayi FROM public.topics
   WHERE subject_id = 'cae032d4-54c0-41d2-b420-17a88fd3770a';
  SELECT count(*) INTO v_subtopic_sayi FROM public.subtopics s
   JOIN public.topics t ON t.id = s.topic_id
   WHERE t.subject_id = 'cae032d4-54c0-41d2-b420-17a88fd3770a';
  SELECT count(*) INTO v_outcome_sayi FROM public.curriculum_outcomes
   WHERE outcome_code LIKE 'COG.%';
  IF NOT (v_topic_sayi = 0 AND v_subtopic_sayi = 0 AND v_outcome_sayi = 0)
     AND NOT (v_topic_sayi = 28 AND v_subtopic_sayi = 76 AND v_outcome_sayi = 76) THEN
    RAISE EXCEPTION 'GUARD_145: Coğrafya ağacı kısmi/yabancı durumda (topics=%, subtopics=%, outcomes=%; beklenen 0/0/0 veya 28/76/76) — fail-closed dur.', v_topic_sayi, v_subtopic_sayi, v_outcome_sayi;
  END IF;

  -- Dolu hâl: id'lerin tamamı bu migration'ın deterministik kümesinden mi?
  IF v_topic_sayi = 28 THEN
    SELECT count(*) INTO v_yabanci FROM public.topics
     WHERE subject_id = 'cae032d4-54c0-41d2-b420-17a88fd3770a' AND id NOT IN (
      'b7090000-0000-4000-8000-000000000001',
      'b7090000-0000-4000-8000-000000000002',
      'b7090000-0000-4000-8000-000000000003',
      'b7090000-0000-4000-8000-000000000004',
      'b7090000-0000-4000-8000-000000000005',
      'b7090000-0000-4000-8000-000000000006',
      'b7090000-0000-4000-8000-000000000007',
      'b7100000-0000-4000-8000-000000000001',
      'b7100000-0000-4000-8000-000000000002',
      'b7100000-0000-4000-8000-000000000003',
      'b7100000-0000-4000-8000-000000000004',
      'b7100000-0000-4000-8000-000000000005',
      'b7100000-0000-4000-8000-000000000006',
      'b7100000-0000-4000-8000-000000000007',
      'b7110000-0000-4000-8000-000000000001',
      'b7110000-0000-4000-8000-000000000002',
      'b7110000-0000-4000-8000-000000000003',
      'b7110000-0000-4000-8000-000000000004',
      'b7110000-0000-4000-8000-000000000005',
      'b7110000-0000-4000-8000-000000000006',
      'b7110000-0000-4000-8000-000000000007',
      'b7120000-0000-4000-8000-000000000001',
      'b7120000-0000-4000-8000-000000000002',
      'b7120000-0000-4000-8000-000000000003',
      'b7120000-0000-4000-8000-000000000004',
      'b7120000-0000-4000-8000-000000000005',
      'b7120000-0000-4000-8000-000000000006',
      'b7120000-0000-4000-8000-000000000007'
    );
    IF v_yabanci > 0 THEN
      RAISE EXCEPTION 'GUARD_145: % yabancı Coğrafya topic id''si bulundu — fail-closed dur.', v_yabanci;
    END IF;
    SELECT count(*) INTO v_yabanci FROM public.subtopics s
     JOIN public.topics t ON t.id = s.topic_id
     WHERE t.subject_id = 'cae032d4-54c0-41d2-b420-17a88fd3770a' AND s.id NOT IN (
      'b8090000-0000-4000-8000-000000000001',
      'b8090000-0000-4000-8000-000000000002',
      'b8090000-0000-4000-8000-000000000003',
      'b8090000-0000-4000-8000-000000000004',
      'b8090000-0000-4000-8000-000000000005',
      'b8090000-0000-4000-8000-000000000006',
      'b8090000-0000-4000-8000-000000000007',
      'b8090000-0000-4000-8000-000000000008',
      'b8090000-0000-4000-8000-000000000009',
      'b8090000-0000-4000-8000-000000000010',
      'b8090000-0000-4000-8000-000000000011',
      'b8090000-0000-4000-8000-000000000012',
      'b8090000-0000-4000-8000-000000000013',
      'b8090000-0000-4000-8000-000000000014',
      'b8090000-0000-4000-8000-000000000015',
      'b8090000-0000-4000-8000-000000000016',
      'b8090000-0000-4000-8000-000000000017',
      'b8090000-0000-4000-8000-000000000018',
      'b8090000-0000-4000-8000-000000000019',
      'b8100000-0000-4000-8000-000000000001',
      'b8100000-0000-4000-8000-000000000002',
      'b8100000-0000-4000-8000-000000000003',
      'b8100000-0000-4000-8000-000000000004',
      'b8100000-0000-4000-8000-000000000005',
      'b8100000-0000-4000-8000-000000000006',
      'b8100000-0000-4000-8000-000000000007',
      'b8100000-0000-4000-8000-000000000008',
      'b8100000-0000-4000-8000-000000000009',
      'b8100000-0000-4000-8000-000000000010',
      'b8100000-0000-4000-8000-000000000011',
      'b8100000-0000-4000-8000-000000000012',
      'b8100000-0000-4000-8000-000000000013',
      'b8100000-0000-4000-8000-000000000014',
      'b8100000-0000-4000-8000-000000000015',
      'b8100000-0000-4000-8000-000000000016',
      'b8100000-0000-4000-8000-000000000017',
      'b8100000-0000-4000-8000-000000000018',
      'b8110000-0000-4000-8000-000000000001',
      'b8110000-0000-4000-8000-000000000002',
      'b8110000-0000-4000-8000-000000000003',
      'b8110000-0000-4000-8000-000000000004',
      'b8110000-0000-4000-8000-000000000005',
      'b8110000-0000-4000-8000-000000000006',
      'b8110000-0000-4000-8000-000000000007',
      'b8110000-0000-4000-8000-000000000008',
      'b8110000-0000-4000-8000-000000000009',
      'b8110000-0000-4000-8000-000000000010',
      'b8110000-0000-4000-8000-000000000011',
      'b8110000-0000-4000-8000-000000000012',
      'b8110000-0000-4000-8000-000000000013',
      'b8110000-0000-4000-8000-000000000014',
      'b8110000-0000-4000-8000-000000000015',
      'b8110000-0000-4000-8000-000000000016',
      'b8110000-0000-4000-8000-000000000017',
      'b8110000-0000-4000-8000-000000000018',
      'b8110000-0000-4000-8000-000000000019',
      'b8120000-0000-4000-8000-000000000001',
      'b8120000-0000-4000-8000-000000000002',
      'b8120000-0000-4000-8000-000000000003',
      'b8120000-0000-4000-8000-000000000004',
      'b8120000-0000-4000-8000-000000000005',
      'b8120000-0000-4000-8000-000000000006',
      'b8120000-0000-4000-8000-000000000007',
      'b8120000-0000-4000-8000-000000000008',
      'b8120000-0000-4000-8000-000000000009',
      'b8120000-0000-4000-8000-000000000010',
      'b8120000-0000-4000-8000-000000000011',
      'b8120000-0000-4000-8000-000000000012',
      'b8120000-0000-4000-8000-000000000013',
      'b8120000-0000-4000-8000-000000000014',
      'b8120000-0000-4000-8000-000000000015',
      'b8120000-0000-4000-8000-000000000016',
      'b8120000-0000-4000-8000-000000000017',
      'b8120000-0000-4000-8000-000000000018',
      'b8120000-0000-4000-8000-000000000019',
      'b8120000-0000-4000-8000-000000000020'
    );
    IF v_yabanci > 0 THEN
      RAISE EXCEPTION 'GUARD_145: % yabancı Coğrafya subtopic id''si bulundu — fail-closed dur.', v_yabanci;
    END IF;
    SELECT count(*), count(*) FILTER (WHERE id IN (
      'b9090000-0000-4000-8000-000000000001', 'b9090000-0000-4000-8000-000000000002', 'b9090000-0000-4000-8000-000000000003', 'b9090000-0000-4000-8000-000000000004', 'b9090000-0000-4000-8000-000000000005', 'b9090000-0000-4000-8000-000000000006', 'b9090000-0000-4000-8000-000000000007', 'b9090000-0000-4000-8000-000000000008', 'b9090000-0000-4000-8000-000000000009', 'b9090000-0000-4000-8000-000000000010', 'b9090000-0000-4000-8000-000000000011', 'b9090000-0000-4000-8000-000000000012', 'b9090000-0000-4000-8000-000000000013', 'b9090000-0000-4000-8000-000000000014', 'b9090000-0000-4000-8000-000000000015', 'b9090000-0000-4000-8000-000000000016', 'b9090000-0000-4000-8000-000000000017', 'b9090000-0000-4000-8000-000000000018', 'b9090000-0000-4000-8000-000000000019', 'b9100000-0000-4000-8000-000000000001', 'b9100000-0000-4000-8000-000000000002', 'b9100000-0000-4000-8000-000000000003', 'b9100000-0000-4000-8000-000000000004', 'b9100000-0000-4000-8000-000000000005', 'b9100000-0000-4000-8000-000000000006', 'b9100000-0000-4000-8000-000000000007', 'b9100000-0000-4000-8000-000000000008', 'b9100000-0000-4000-8000-000000000009', 'b9100000-0000-4000-8000-000000000010', 'b9100000-0000-4000-8000-000000000011', 'b9100000-0000-4000-8000-000000000012', 'b9100000-0000-4000-8000-000000000013', 'b9100000-0000-4000-8000-000000000014', 'b9100000-0000-4000-8000-000000000015', 'b9100000-0000-4000-8000-000000000016', 'b9100000-0000-4000-8000-000000000017', 'b9100000-0000-4000-8000-000000000018', 'b9110000-0000-4000-8000-000000000001', 'b9110000-0000-4000-8000-000000000002', 'b9110000-0000-4000-8000-000000000003', 'b9110000-0000-4000-8000-000000000004', 'b9110000-0000-4000-8000-000000000005', 'b9110000-0000-4000-8000-000000000006', 'b9110000-0000-4000-8000-000000000007', 'b9110000-0000-4000-8000-000000000008', 'b9110000-0000-4000-8000-000000000009', 'b9110000-0000-4000-8000-000000000010', 'b9110000-0000-4000-8000-000000000011', 'b9110000-0000-4000-8000-000000000012', 'b9110000-0000-4000-8000-000000000013', 'b9110000-0000-4000-8000-000000000014', 'b9110000-0000-4000-8000-000000000015', 'b9110000-0000-4000-8000-000000000016', 'b9110000-0000-4000-8000-000000000017', 'b9110000-0000-4000-8000-000000000018', 'b9110000-0000-4000-8000-000000000019', 'b9120000-0000-4000-8000-000000000001', 'b9120000-0000-4000-8000-000000000002', 'b9120000-0000-4000-8000-000000000003', 'b9120000-0000-4000-8000-000000000004', 'b9120000-0000-4000-8000-000000000005', 'b9120000-0000-4000-8000-000000000006', 'b9120000-0000-4000-8000-000000000007', 'b9120000-0000-4000-8000-000000000008', 'b9120000-0000-4000-8000-000000000009', 'b9120000-0000-4000-8000-000000000010', 'b9120000-0000-4000-8000-000000000011', 'b9120000-0000-4000-8000-000000000012', 'b9120000-0000-4000-8000-000000000013', 'b9120000-0000-4000-8000-000000000014', 'b9120000-0000-4000-8000-000000000015', 'b9120000-0000-4000-8000-000000000016', 'b9120000-0000-4000-8000-000000000017', 'b9120000-0000-4000-8000-000000000018', 'b9120000-0000-4000-8000-000000000019', 'b9120000-0000-4000-8000-000000000020'
    )), count(DISTINCT outcome_code) INTO v_outcome_sayi, v_tanimli, v_benzersiz
      FROM public.curriculum_outcomes WHERE outcome_code LIKE 'COG.%';
    IF v_outcome_sayi <> 76 OR v_tanimli <> 76 OR v_benzersiz <> 76 THEN
      RAISE EXCEPTION 'GUARD_145: COG.* outcomes=% (tanınan id=%, benzersiz kod=%; beklenen 76/76/76) — id/kod drifti, fail-closed dur.', v_outcome_sayi, v_tanimli, v_benzersiz;
    END IF;
  END IF;
END
$guard$;

-- ============================================================
-- 0.5. SÜRÜM SATIRI (125 fizik deseni; is_default=false — yıl-tek-default bozulmaz)
-- ============================================================
insert into public.curriculum_versions (
  id, academic_year, framework, source_name, source_url, published_at,
  is_active, is_default, created_at, updated_at
) values (
  'a1000000-0000-4000-8000-0000000000c6',
  '2026-2027',
  'tymm_2026_cografya',
  'Türkiye Yüzyılı Maarif Modeli Coğrafya Dersi (9, 10, 11 ve 12. Sınıflar) Öğretim Programı (2026)',
  'https://mufredat.meb.gov.tr/Dosyalar/2026518151120283-cogd%C3%B6p.pdf',
  '2026-05-18',  -- mufredat.meb.gov.tr resmî URL zaman damgasından (125 fizik kararıyla aynı yöntem)
  true, false, now(), now()
)
on conflict (id) do nothing;

-- ============================================================
-- 1. TOPICS (28) — COG.GG.N <ÜNİTE ADI>; sort_order = resmî ünite no (sınıf içi)
--    UNIQUE (curriculum_version_id, subject_id, grade_level, slug) koruması:
--    farklı id ile aynı slug varsa INSERT doğal olarak HATA verir (fail-closed).
-- ============================================================
insert into public.topics (
  id, subject_id, grade_level, name, slug, sort_order,
  is_active, curriculum_version_id, created_at, updated_at
) values
  ('b7090000-0000-4000-8000-000000000001', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 9, 'COG.9.1 COĞRAFYANIN DOĞASI', 'cografya-9-1-cografyanin-dogasi', 1, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7090000-0000-4000-8000-000000000002', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 9, 'COG.9.2 MEKÂNSAL BİLGİ TEKNOLOJİLERİ', 'cografya-9-2-mekansal-bilgi-teknolojileri', 2, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7090000-0000-4000-8000-000000000003', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 9, 'COG.9.3 DOĞAL SİSTEMLER VE SÜREÇLER', 'cografya-9-3-dogal-sistemler-ve-surecler', 3, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7090000-0000-4000-8000-000000000004', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 9, 'COG.9.4 BEŞERÎ SİSTEMLER VE SÜREÇLER', 'cografya-9-4-beseri-sistemler-ve-surecler', 4, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7090000-0000-4000-8000-000000000005', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 9, 'COG.9.5 EKONOMİK FAALİYETLER VE ETKİLERİ', 'cografya-9-5-ekonomik-faaliyetler-ve-etkileri', 5, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7090000-0000-4000-8000-000000000006', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 9, 'COG.9.6 AFETLER VE SÜRDÜRÜLEBİLİR ÇEVRE', 'cografya-9-6-afetler-ve-surdurulebilir-cevre', 6, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7090000-0000-4000-8000-000000000007', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 9, 'COG.9.7 BÖLGELER, ÜLKELER VE KÜRESEL BAĞLANTILAR', 'cografya-9-7-bolgeler-ulkeler-ve-kuresel-baglantilar', 7, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7100000-0000-4000-8000-000000000001', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 10, 'COG.10.1 COĞRAFYANIN DOĞASI', 'cografya-10-1-cografyanin-dogasi', 1, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7100000-0000-4000-8000-000000000002', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 10, 'COG.10.2 MEKÂNSAL BİLGİ TEKNOLOJİLERİ', 'cografya-10-2-mekansal-bilgi-teknolojileri', 2, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7100000-0000-4000-8000-000000000003', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 10, 'COG.10.3 DOĞAL SİSTEMLER VE SÜREÇLER', 'cografya-10-3-dogal-sistemler-ve-surecler', 3, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7100000-0000-4000-8000-000000000004', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 10, 'COG.10.4 BEŞERÎ SİSTEMLER VE SÜREÇLER', 'cografya-10-4-beseri-sistemler-ve-surecler', 4, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7100000-0000-4000-8000-000000000005', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 10, 'COG.10.5 EKONOMİK FAALİYETLER VE ETKİLERİ', 'cografya-10-5-ekonomik-faaliyetler-ve-etkileri', 5, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7100000-0000-4000-8000-000000000006', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 10, 'COG.10.6 AFETLER VE SÜRDÜRÜLEBİLİR ÇEVRE', 'cografya-10-6-afetler-ve-surdurulebilir-cevre', 6, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7100000-0000-4000-8000-000000000007', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 10, 'COG.10.7 BÖLGELER, ÜLKELER VE KÜRESEL BAĞLANTILAR', 'cografya-10-7-bolgeler-ulkeler-ve-kuresel-baglantilar', 7, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7110000-0000-4000-8000-000000000001', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 11, 'COG.11.1 COĞRAFYANIN DOĞASI', 'cografya-11-1-cografyanin-dogasi', 1, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7110000-0000-4000-8000-000000000002', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 11, 'COG.11.2 MEKÂNSAL BİLGİ TEKNOLOJİLERİ', 'cografya-11-2-mekansal-bilgi-teknolojileri', 2, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7110000-0000-4000-8000-000000000003', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 11, 'COG.11.3 DOĞAL SİSTEMLER VE SÜREÇLER', 'cografya-11-3-dogal-sistemler-ve-surecler', 3, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7110000-0000-4000-8000-000000000004', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 11, 'COG.11.4 BEŞERÎ SİSTEMLER VE SÜREÇLER', 'cografya-11-4-beseri-sistemler-ve-surecler', 4, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7110000-0000-4000-8000-000000000005', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 11, 'COG.11.5 EKONOMİK FAALİYETLER VE ETKİLERİ', 'cografya-11-5-ekonomik-faaliyetler-ve-etkileri', 5, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7110000-0000-4000-8000-000000000006', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 11, 'COG.11.6 AFETLER VE SÜRDÜRÜLEBİLİR ÇEVRE', 'cografya-11-6-afetler-ve-surdurulebilir-cevre', 6, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7110000-0000-4000-8000-000000000007', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 11, 'COG.11.7 BÖLGELER, ÜLKELER VE KÜRESEL BAĞLANTILAR', 'cografya-11-7-bolgeler-ulkeler-ve-kuresel-baglantilar', 7, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7120000-0000-4000-8000-000000000001', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 12, 'COG.12.1 COĞRAFYANIN DOĞASI', 'cografya-12-1-cografyanin-dogasi', 1, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7120000-0000-4000-8000-000000000002', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 12, 'COG.12.2 MEKÂNSAL BİLGİ TEKNOLOJİLERİ', 'cografya-12-2-mekansal-bilgi-teknolojileri', 2, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7120000-0000-4000-8000-000000000003', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 12, 'COG.12.3 DOĞAL SİSTEMLER VE SÜREÇLER', 'cografya-12-3-dogal-sistemler-ve-surecler', 3, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7120000-0000-4000-8000-000000000004', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 12, 'COG.12.4 BEŞERÎ SİSTEMLER VE SÜREÇLER', 'cografya-12-4-beseri-sistemler-ve-surecler', 4, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7120000-0000-4000-8000-000000000005', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 12, 'COG.12.5 EKONOMİK FAALİYETLER VE ETKİLERİ', 'cografya-12-5-ekonomik-faaliyetler-ve-etkileri', 5, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7120000-0000-4000-8000-000000000006', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 12, 'COG.12.6 AFETLER VE SÜRDÜRÜLEBİLİR ÇEVRE', 'cografya-12-6-afetler-ve-surdurulebilir-cevre', 6, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now()),
  ('b7120000-0000-4000-8000-000000000007', 'cae032d4-54c0-41d2-b420-17a88fd3770a', 12, 'COG.12.7 BÖLGELER, ÜLKELER VE KÜRESEL BAĞLANTILAR', 'cografya-12-7-bolgeler-ulkeler-ve-kuresel-baglantilar', 7, true, 'a1000000-0000-4000-8000-0000000000c6', now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 2. SUBTOPICS (76) — İçerik Çerçevesi maddeleri (resmî, basılı sıra);
--    sort_order sınıf içi kesintisiz (9: 1..19, 10: 1..18, 11: 1..19, 12: 1..20);
--    subtopic_id bağlantısı çıktılara AÇILMAZ (kaynak numaralandırmamış).
-- ============================================================
insert into public.subtopics (
  id, topic_id, name, slug, sort_order, is_active, created_at, updated_at
) values
  ('b8090000-0000-4000-8000-000000000001', 'b7090000-0000-4000-8000-000000000001', 'Coğrafya Biliminin Konusu ve Bölümleri', 'cografya-9-1-cografyanin-dogasi-cografya-biliminin-konusu-ve-bolumleri', 1, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000002', 'b7090000-0000-4000-8000-000000000001', 'Niçin Coğrafya Öğrenmeliyiz?', 'cografya-9-1-cografyanin-dogasi-nicin-cografya-ogrenmeliyiz', 2, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000003', 'b7090000-0000-4000-8000-000000000001', 'Coğrafya Biliminin Gelişimi', 'cografya-9-1-cografyanin-dogasi-cografya-biliminin-gelisimi', 3, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000004', 'b7090000-0000-4000-8000-000000000002', 'Mekânın Aynası Haritalar', 'cografya-9-2-mekansal-bilgi-teknolojileri-mekanin-aynasi-haritalar', 4, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000005', 'b7090000-0000-4000-8000-000000000002', 'Türkiye’nin Coğrafi Konumu', 'cografya-9-2-mekansal-bilgi-teknolojileri-turkiyenin-cografi-konumu', 5, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000006', 'b7090000-0000-4000-8000-000000000002', 'Mekânsal Bilgi Teknolojilerinin Bileşenleri', 'cografya-9-2-mekansal-bilgi-teknolojileri-mekansal-bilgi-teknolojilerinin-bilesenleri', 6, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000007', 'b7090000-0000-4000-8000-000000000003', 'Hava Olayları ve Günlük Hayata Etkileri', 'cografya-9-3-dogal-sistemler-ve-surecler-hava-olaylari-ve-gunluk-hayata-etkileri', 7, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000008', 'b7090000-0000-4000-8000-000000000003', 'İklim Sisteminin Bileşen ve Değişkenleri', 'cografya-9-3-dogal-sistemler-ve-surecler-iklim-sisteminin-bilesen-ve-degiskenleri', 8, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000009', 'b7090000-0000-4000-8000-000000000003', 'İklim Türleri', 'cografya-9-3-dogal-sistemler-ve-surecler-iklim-turleri', 9, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000010', 'b7090000-0000-4000-8000-000000000003', 'İklim Sisteminde Yaşanan Değişiklikler', 'cografya-9-3-dogal-sistemler-ve-surecler-iklim-sisteminde-yasanan-degisiklikler', 10, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000011', 'b7090000-0000-4000-8000-000000000004', 'Nüfusun Tarihsel Değişimi ve Geleceği', 'cografya-9-4-beseri-sistemler-ve-surecler-nufusun-tarihsel-degisimi-ve-gelecegi', 11, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000012', 'b7090000-0000-4000-8000-000000000004', 'Nüfusun Dağılışı ve Hareketleri', 'cografya-9-4-beseri-sistemler-ve-surecler-nufusun-dagilisi-ve-hareketleri', 12, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000013', 'b7090000-0000-4000-8000-000000000004', 'Demografik Dönüşüm ve Nüfus Piramitleri', 'cografya-9-4-beseri-sistemler-ve-surecler-demografik-donusum-ve-nufus-piramitleri', 13, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000014', 'b7090000-0000-4000-8000-000000000004', 'Nüfusla İlgili Fırsat, Sorun ve Politikalar', 'cografya-9-4-beseri-sistemler-ve-surecler-nufusla-ilgili-firsat-sorun-ve-politikalar', 14, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000015', 'b7090000-0000-4000-8000-000000000005', 'Ekonomik Faaliyetleri Etkileyen Coğrafi Faktörler', 'cografya-9-5-ekonomik-faaliyetler-ve-etkileri-ekonomik-faaliyetleri-etkileyen-cografi-faktorler', 15, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000016', 'b7090000-0000-4000-8000-000000000006', 'Tehlike, Risk ve Afet', 'cografya-9-6-afetler-ve-surdurulebilir-cevre-tehlike-risk-ve-afet', 16, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000017', 'b7090000-0000-4000-8000-000000000006', 'Afet Türleri', 'cografya-9-6-afetler-ve-surdurulebilir-cevre-afet-turleri', 17, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000018', 'b7090000-0000-4000-8000-000000000006', 'Bütüncül Afet Yönetimi', 'cografya-9-6-afetler-ve-surdurulebilir-cevre-butuncul-afet-yonetimi', 18, true, now(), now()),
  ('b8090000-0000-4000-8000-000000000019', 'b7090000-0000-4000-8000-000000000007', 'Bölge ve Bölge Sınırı', 'cografya-9-7-bolgeler-ulkeler-ve-kuresel-baglantilar-bolge-ve-bolge-siniri', 19, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000001', 'b7100000-0000-4000-8000-000000000001', 'Coğrafi Bakış', 'cografya-10-1-cografyanin-dogasi-cografi-bakis', 1, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000002', 'b7100000-0000-4000-8000-000000000002', 'CBS ve Uzaktan Algılamanın Uygulama Alanları', 'cografya-10-2-mekansal-bilgi-teknolojileri-cbs-ve-uzaktan-algilamanin-uygulama-alanlari', 2, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000003', 'b7100000-0000-4000-8000-000000000002', 'Mekânsal Verilerin Haritalara Aktarılması', 'cografya-10-2-mekansal-bilgi-teknolojileri-mekansal-verilerin-haritalara-aktarilmasi', 3, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000004', 'b7100000-0000-4000-8000-000000000003', 'Tektonik Süreçler', 'cografya-10-3-dogal-sistemler-ve-surecler-tektonik-surecler', 4, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000005', 'b7100000-0000-4000-8000-000000000003', 'İklim ve Kayaç Yapısının Aşınma ve Çözünme Süreçlerine Etkisi', 'cografya-10-3-dogal-sistemler-ve-surecler-iklim-ve-kayac-yapisinin-asinma-ve-cozunme-sureclerine-etkisi', 5, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000006', 'b7100000-0000-4000-8000-000000000003', 'Aşınım ve Birikim Süreçlerinin Yeryüzü Şekillerinin Oluşumuna Etkisi', 'cografya-10-3-dogal-sistemler-ve-surecler-asinim-ve-birikim-sureclerinin-yeryuzu-sekillerinin-olusumuna-etkisi', 6, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000007', 'b7100000-0000-4000-8000-000000000003', 'Yeryüzü Şekilleri ile İlgili Gözlem ve Saha Çalışması', 'cografya-10-3-dogal-sistemler-ve-surecler-yeryuzu-sekilleri-ile-ilgili-gozlem-ve-saha-calismasi', 7, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000008', 'b7100000-0000-4000-8000-000000000003', 'Yeryüzü Şekilleri ile Beşerî Faaliyetler Arasındaki Etkileşim', 'cografya-10-3-dogal-sistemler-ve-surecler-yeryuzu-sekilleri-ile-beseri-faaliyetler-arasindaki-etkilesim', 8, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000009', 'b7100000-0000-4000-8000-000000000004', 'Yerleşmelerin Kuruluşu ve Gelişimi', 'cografya-10-4-beseri-sistemler-ve-surecler-yerlesmelerin-kurulusu-ve-gelisimi', 9, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000010', 'b7100000-0000-4000-8000-000000000004', 'Yerleşmelerin Fonksiyonları', 'cografya-10-4-beseri-sistemler-ve-surecler-yerlesmelerin-fonksiyonlari', 10, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000011', 'b7100000-0000-4000-8000-000000000005', 'Ekonomik Faaliyetlerin Özellikleri', 'cografya-10-5-ekonomik-faaliyetler-ve-etkileri-ekonomik-faaliyetlerin-ozellikleri', 11, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000012', 'b7100000-0000-4000-8000-000000000005', 'Ekonomik Sektörler ve Gelişmişlik', 'cografya-10-5-ekonomik-faaliyetler-ve-etkileri-ekonomik-sektorler-ve-gelismislik', 12, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000013', 'b7100000-0000-4000-8000-000000000005', 'Türkiye Ekonomisinin Sektörel Dağılımı', 'cografya-10-5-ekonomik-faaliyetler-ve-etkileri-turkiye-ekonomisinin-sektorel-dagilimi', 13, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000014', 'b7100000-0000-4000-8000-000000000006', 'Afetlerle Mücadelede İyi Uygulama Örnekleri', 'cografya-10-6-afetler-ve-surdurulebilir-cevre-afetlerle-mucadelede-iyi-uygulama-ornekleri', 14, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000015', 'b7100000-0000-4000-8000-000000000006', 'Afetlere Karşı Dirençli Yaşam Alanları', 'cografya-10-6-afetler-ve-surdurulebilir-cevre-afetlere-karsi-direncli-yasam-alanlari', 15, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000016', 'b7100000-0000-4000-8000-000000000006', 'Afetlerden Korunma', 'cografya-10-6-afetler-ve-surdurulebilir-cevre-afetlerden-korunma', 16, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000017', 'b7100000-0000-4000-8000-000000000006', 'Afet Bilinci', 'cografya-10-6-afetler-ve-surdurulebilir-cevre-afet-bilinci', 17, true, now(), now()),
  ('b8100000-0000-4000-8000-000000000018', 'b7100000-0000-4000-8000-000000000007', 'Türk Kültürünün Mekânsal Özellikleri', 'cografya-10-7-bolgeler-ulkeler-ve-kuresel-baglantilar-turk-kulturunun-mekansal-ozellikleri', 18, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000001', 'b7110000-0000-4000-8000-000000000001', 'Mekânsal Sorunlar Karşısında Coğrafya Bilimi', 'cografya-11-1-cografyanin-dogasi-mekansal-sorunlar-karsisinda-cografya-bilimi', 1, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000002', 'b7110000-0000-4000-8000-000000000002', 'Web Tabanlı CBS Uygulamaları', 'cografya-11-2-mekansal-bilgi-teknolojileri-web-tabanli-cbs-uygulamalari', 2, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000003', 'b7110000-0000-4000-8000-000000000003', 'Su Kaynakları', 'cografya-11-3-dogal-sistemler-ve-surecler-su-kaynaklari', 3, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000004', 'b7110000-0000-4000-8000-000000000003', 'Türkiye’deki Su Kaynaklarının Etkileri', 'cografya-11-3-dogal-sistemler-ve-surecler-turkiyedeki-su-kaynaklarinin-etkileri', 4, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000005', 'b7110000-0000-4000-8000-000000000004', 'Yerleşmelerin Mekânsal Organizasyonları', 'cografya-11-4-beseri-sistemler-ve-surecler-yerlesmelerin-mekansal-organizasyonlari', 5, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000006', 'b7110000-0000-4000-8000-000000000004', 'Yerleşmelerin Etki Alanları', 'cografya-11-4-beseri-sistemler-ve-surecler-yerlesmelerin-etki-alanlari', 6, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000007', 'b7110000-0000-4000-8000-000000000005', 'Tarımsal Faaliyetler ve Gıda Güvencesi', 'cografya-11-5-ekonomik-faaliyetler-ve-etkileri-tarimsal-faaliyetler-ve-gida-guvencesi', 7, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000008', 'b7110000-0000-4000-8000-000000000005', 'Tarım Uygulamalarında Sürdürülebilirlik', 'cografya-11-5-ekonomik-faaliyetler-ve-etkileri-tarim-uygulamalarinda-surdurulebilirlik', 8, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000009', 'b7110000-0000-4000-8000-000000000005', 'Stratejik ve Kritik Madenler', 'cografya-11-5-ekonomik-faaliyetler-ve-etkileri-stratejik-ve-kritik-madenler', 9, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000010', 'b7110000-0000-4000-8000-000000000005', 'Enerji Kaynakları', 'cografya-11-5-ekonomik-faaliyetler-ve-etkileri-enerji-kaynaklari', 10, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000011', 'b7110000-0000-4000-8000-000000000005', 'Sanayileşmenin Mekânsal Etkileri', 'cografya-11-5-ekonomik-faaliyetler-ve-etkileri-sanayilesmenin-mekansal-etkileri', 11, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000012', 'b7110000-0000-4000-8000-000000000006', 'Gezegen Sınırı', 'cografya-11-6-afetler-ve-surdurulebilir-cevre-gezegen-siniri', 12, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000013', 'b7110000-0000-4000-8000-000000000006', 'Küresel İklim Değişikliği', 'cografya-11-6-afetler-ve-surdurulebilir-cevre-kuresel-iklim-degisikligi', 13, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000014', 'b7110000-0000-4000-8000-000000000006', 'Türkiye’de Suyun Sürdürülebilir Kullanımı', 'cografya-11-6-afetler-ve-surdurulebilir-cevre-turkiyede-suyun-surdurulebilir-kullanimi', 14, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000015', 'b7110000-0000-4000-8000-000000000007', 'Türkiye’nin Kültürel Hinterlandı', 'cografya-11-7-bolgeler-ulkeler-ve-kuresel-baglantilar-turkiyenin-kulturel-hinterlandi', 15, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000016', 'b7110000-0000-4000-8000-000000000007', 'Tarımsal Üretim: Örnek Ülke', 'cografya-11-7-bolgeler-ulkeler-ve-kuresel-baglantilar-tarimsal-uretim-ornek-ulke', 16, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000017', 'b7110000-0000-4000-8000-000000000007', 'Sanayileşme Süreci: Örnek Ülkeler', 'cografya-11-7-bolgeler-ulkeler-ve-kuresel-baglantilar-sanayilesme-sureci-ornek-ulkeler', 17, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000018', 'b7110000-0000-4000-8000-000000000007', 'Madencilik Faaliyetleri: Örnek Ülke', 'cografya-11-7-bolgeler-ulkeler-ve-kuresel-baglantilar-madencilik-faaliyetleri-ornek-ulke', 18, true, now(), now()),
  ('b8110000-0000-4000-8000-000000000019', 'b7110000-0000-4000-8000-000000000007', 'Enerji Kaynakları: Örnek Ülkeler', 'cografya-11-7-bolgeler-ulkeler-ve-kuresel-baglantilar-enerji-kaynaklari-ornek-ulkeler', 19, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000001', 'b7120000-0000-4000-8000-000000000001', 'Geleceğin Dünyasında Coğrafya Bilimi', 'cografya-12-1-cografyanin-dogasi-gelecegin-dunyasinda-cografya-bilimi', 1, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000002', 'b7120000-0000-4000-8000-000000000002', 'Web Tabanlı CBS Uygulamaları ve Tematik Haritalar', 'cografya-12-2-mekansal-bilgi-teknolojileri-web-tabanli-cbs-uygulamalari-ve-tematik-haritalar', 2, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000003', 'b7120000-0000-4000-8000-000000000003', 'Toprak Oluşumu', 'cografya-12-3-dogal-sistemler-ve-surecler-toprak-olusumu', 3, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000004', 'b7120000-0000-4000-8000-000000000003', 'Türkiye’de Toprakların Kullanımı', 'cografya-12-3-dogal-sistemler-ve-surecler-turkiyede-topraklarin-kullanimi', 4, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000005', 'b7120000-0000-4000-8000-000000000003', 'Coğrafi Faktörlerin Bitki Türlerinin Çeşitliliği ve Dağılışına Etkisi', 'cografya-12-3-dogal-sistemler-ve-surecler-cografi-faktorlerin-bitki-turlerinin-cesitliligi-ve-dagilisina-etkisi', 5, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000006', 'b7120000-0000-4000-8000-000000000004', 'Kültür-Mekân Etkileşimi', 'cografya-12-4-beseri-sistemler-ve-surecler-kultur-mekan-etkilesimi', 6, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000007', 'b7120000-0000-4000-8000-000000000004', 'Kültürel Peyzaj ve Sürdürülebilirlik', 'cografya-12-4-beseri-sistemler-ve-surecler-kulturel-peyzaj-ve-surdurulebilirlik', 7, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000008', 'b7120000-0000-4000-8000-000000000005', 'Ulaşım Sistemleri', 'cografya-12-5-ekonomik-faaliyetler-ve-etkileri-ulasim-sistemleri', 8, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000009', 'b7120000-0000-4000-8000-000000000005', 'Küresel Ticaret', 'cografya-12-5-ekonomik-faaliyetler-ve-etkileri-kuresel-ticaret', 9, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000010', 'b7120000-0000-4000-8000-000000000005', 'Turizm Faaliyetleri', 'cografya-12-5-ekonomik-faaliyetler-ve-etkileri-turizm-faaliyetleri', 10, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000011', 'b7120000-0000-4000-8000-000000000006', 'Türkiye’de Toprağın Sürdürülebilir Kullanımı', 'cografya-12-6-afetler-ve-surdurulebilir-cevre-turkiyede-topragin-surdurulebilir-kullanimi', 11, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000012', 'b7120000-0000-4000-8000-000000000006', 'Türkiye’de Bitki Türlerinin Değişim ve Sürekliliği', 'cografya-12-6-afetler-ve-surdurulebilir-cevre-turkiyede-bitki-turlerinin-degisim-ve-surekliligi', 12, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000013', 'b7120000-0000-4000-8000-000000000006', 'Çevre Sorunlarının Önlenmesine Yönelik Politika ve Uygulamalar', 'cografya-12-6-afetler-ve-surdurulebilir-cevre-cevre-sorunlarinin-onlenmesine-yonelik-politika-ve-uygulamalar', 13, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000014', 'b7120000-0000-4000-8000-000000000006', 'Çevresel Organizasyonlar ve Anlaşmalar', 'cografya-12-6-afetler-ve-surdurulebilir-cevre-cevresel-organizasyonlar-ve-anlasmalar', 14, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000015', 'b7120000-0000-4000-8000-000000000006', 'Çevre Sorunlarına Çözümler', 'cografya-12-6-afetler-ve-surdurulebilir-cevre-cevre-sorunlarina-cozumler', 15, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000016', 'b7120000-0000-4000-8000-000000000006', 'Ortak Doğal ve Kültürel Miras', 'cografya-12-6-afetler-ve-surdurulebilir-cevre-ortak-dogal-ve-kulturel-miras', 16, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000017', 'b7120000-0000-4000-8000-000000000007', 'Uluslararası Birliktelik ve Anlaşmazlıklar', 'cografya-12-7-bolgeler-ulkeler-ve-kuresel-baglantilar-uluslararasi-birliktelik-ve-anlasmazliklar', 17, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000018', 'b7120000-0000-4000-8000-000000000007', 'Ulaşım Sistemleri: Örnek Ülkeler', 'cografya-12-7-bolgeler-ulkeler-ve-kuresel-baglantilar-ulasim-sistemleri-ornek-ulkeler', 18, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000019', 'b7120000-0000-4000-8000-000000000007', 'Ticari Faaliyetler: Örnek Ülke', 'cografya-12-7-bolgeler-ulkeler-ve-kuresel-baglantilar-ticari-faaliyetler-ornek-ulke', 19, true, now(), now()),
  ('b8120000-0000-4000-8000-000000000020', 'b7120000-0000-4000-8000-000000000007', 'Turizm Faaliyetleri: Örnek Ülkeler', 'cografya-12-7-bolgeler-ulkeler-ve-kuresel-baglantilar-turizm-faaliyetleri-ornek-ulkeler', 20, true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 3. OUTCOMES (76) — COG.s.u.k (resmî kodlar; türetilmemiş).
--    sort_order = k (ünite-içi; 125 sözleşmesi). subtopic_id = NULL
--    (kaynakta numaralandırılmamış — kasıtlı ve onaylı).
--    id NN sırası: sınıf içi (ünite, k) — 9: 7/19/19, 10: 7/18/18, 11: 7/19/19, 12: 7/20/20.
-- ============================================================
insert into public.curriculum_outcomes (
  id, curriculum_version_id, grade_level, subject_id, topic_id, subtopic_id,
  outcome_code, outcome_text, sort_order, source_reference, is_active, created_at, updated_at
) values
  ('b9090000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000001', NULL, 'COG.9.1.1', 'Coğrafya biliminin konusu ve bölümlerini çözümleyebilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.16', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000001', NULL, 'COG.9.1.2', 'Örnek olay, olgu veya konu üzerinden mekânsal düşünme ile coğrafya öğrenmenin önemini çözümleyebilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.16', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000001', NULL, 'COG.9.1.3', 'Coğrafya biliminin gelişimi hakkında bilgi toplayabilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.16', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000002', NULL, 'COG.9.2.1', 'Harita uygulamaları yapabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.20', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000002', NULL, 'COG.9.2.2', 'Türkiye’nin konum özelliklerini algılayabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.20', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000002', NULL, 'COG.9.2.3', 'Mekânsal bilgi teknolojilerini oluşturan bileşenleri çözümleyebilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.20', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000003', NULL, 'COG.9.3.1', 'Hava olaylarının günlük hayata etkisini gözleme dayalı tahmin edebilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.24', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000003', NULL, 'COG.9.3.2', 'İklim sisteminin bileşen ve değişkenlerini çözümleyebilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.24', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000003', NULL, 'COG.9.3.3', 'Türkiye ve dünyadaki farklı iklim türlerine sahip yerlerin iklim verilerini kullanarak tablo, grafik, şekil ve/veya diyagram hazırlayabilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.24', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000003', NULL, 'COG.9.3.4', 'İklim sistemi ve sürecinde meydana gelen değişiklikleri algılayabilme', 4, 'TYMM 2026 Coğrafya Öğretim Programı, s.24', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000004', NULL, 'COG.9.4.1', 'Nüfusun zaman içerisindeki değişimini tablo ve grafikler aracılığı ile yorumlayabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.29', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000004', NULL, 'COG.9.4.2', 'Dünya ve Türkiye’deki nüfusun dağılışı ve hareketlerini etkileyen faktörler hakkında haritalar üzerinden çıkarımda bulunabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.29', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000004', NULL, 'COG.9.4.3', 'Türkiye ve farklı ülkelerin nüfus piramitlerinden yararlanarak demografik dönüşüm sürecini yorumlayabilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.29', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000004', NULL, 'COG.9.4.4', 'Türkiye ve farklı ülkelerdeki nüfusla ilgili fırsat ve sorunların nüfus politikalarının belirlenmesindeki etkisini sorgulayabilme', 4, 'TYMM 2026 Coğrafya Öğretim Programı, s.29', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000005', NULL, 'COG.9.5.1', 'Doğal ve beşerî faktörlerin ekonomik faaliyetlere etkilerini sorgulayabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.34', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000006', NULL, 'COG.9.6.1', 'Tehlike, risk ve afet kavramlarını çözümleyebilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.37', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000006', NULL, 'COG.9.6.2', 'Afetleri sınıflandırabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.37', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000006', NULL, 'COG.9.6.3', 'Bütüncül afet yönetimi uygulamalarını tablo, grafik, şekil ve/veya diyagramlar aracılığıyla yorumlayabilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.37', true, now(), now()),
  ('b9090000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c6', 9, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7090000-0000-4000-8000-000000000007', NULL, 'COG.9.7.1', 'Bölgelerin belirlenmesinde kullanılan kriterlere göre bölge hakkında çıkarım yapabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.41', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000001', NULL, 'COG.10.1.1', 'Örnek olay, olgu ve/veya mekânı coğrafyanın temel kavramları ile ilişkilendirebilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.44', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000002', NULL, 'COG.10.2.1', 'Örnek uygulamalar üzerinden CBS ve uzaktan algılamanın kullanım alanlarını özetleyebilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.47', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000002', NULL, 'COG.10.2.2', 'Mekânsal bilgi teknolojilerini kullanarak altlık haritalar üzerinde mekânsal veriler oluşturabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.47', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000003', NULL, 'COG.10.3.1', 'Yerkürenin tektonik yapısını çözümleyebilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.50', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000003', NULL, 'COG.10.3.2', 'Yeryüzü şekillerinin oluşumunda etkili olan aşınma ve çözünme süreçleri ile iklim ve kayaç özellikleri arasındaki ilişkileri yapılandırabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.50', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000003', NULL, 'COG.10.3.3', 'Yeryüzü şekillerinin oluşumunu aşınım ve birikim süreçleri açısından çözümleyebilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.50', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000003', NULL, 'COG.10.3.4', 'Yeryüzü şekillerinin oluşumunda doğal süreçlerin etkilerini saha/sanal saha çalışmalarıyla araştırabilme', 4, 'TYMM 2026 Coğrafya Öğretim Programı, s.50', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000003', NULL, 'COG.10.3.5', 'Yakın çevresindeki yeryüzü şekilleri ile beşerî faaliyetler arasındaki etkileşimi sorgulayabilme', 5, 'TYMM 2026 Coğrafya Öğretim Programı, s.50', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000004', NULL, 'COG.10.4.1', 'Yerleşme yeri seçiminde ve yerleşmelerin gelişiminde etkili olan coğrafi faktörleri sorgulayabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.55', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000004', NULL, 'COG.10.4.2', 'Türkiye ve dünyadaki yerleşmeleri fonksiyonlarına göre sınıflandırabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.55', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000005', NULL, 'COG.10.5.1', 'Ekonomik faaliyetleri sektörlere göre sınıflandırabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.58', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000005', NULL, 'COG.10.5.2', 'Ekonomik sektörlerin dağılımını gösteren tablo, grafik, şekil ve/veya diyagramlar üzerinden farklı gelişmişlik seviyesine sahip ülkeleri karşılaştırabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.58', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000005', NULL, 'COG.10.5.3', 'Ekonomik sektörlerin Türkiye ekonomisindeki yeri ve önemini gösteren tablo, grafik, şekil ve/veya diyagram hazırlayabilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.58', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000006', NULL, 'COG.10.6.1', 'Afetlerle mücadelede iyi uygulama örneklerini sorgulayabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.62', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000006', NULL, 'COG.10.6.2', 'Afete dirençli yaşam alanlarının coğrafi koşullarını çözümleyebilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.62', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000006', NULL, 'COG.10.6.3', 'Mekânın özelliklerine göre afetlerden korunma uygulamalarına karar verebilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.62', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000006', NULL, 'COG.10.6.4', 'Afetlerden korunma amacı ile afet bilinci oluşturmanın faydalarını yansıtabilme', 4, 'TYMM 2026 Coğrafya Öğretim Programı, s.62', true, now(), now()),
  ('b9100000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c6', 10, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7100000-0000-4000-8000-000000000007', NULL, 'COG.10.7.1', 'Türk dünyasının ortak kültürel özellikleri hakkında analojik çıkarım yapabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.66', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000001', NULL, 'COG.11.1.1', 'Mekânsal sorunların çözümünde coğrafya biliminin katkılarını yapılandırabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.69', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000002', NULL, 'COG.11.2.1', 'Web tabanlı CBS aracılığı ile harita uygulamaları yapabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.72', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000003', NULL, 'COG.11.3.1', 'Yeryüzündeki su kaynaklarını sınıflandırabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.75', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000003', NULL, 'COG.11.3.2', 'Türkiye’deki su kaynaklarının çevresel, ekonomik, politik ve sosyokültürel etkilerini sorgulayabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.75', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000004', NULL, 'COG.11.4.1', 'Türkiye ve dünyadaki yerleşmelerin mekânsal organizasyonunu çözümleyebilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.79', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000004', NULL, 'COG.11.4.2', 'Türkiye ve dünyadaki yerleşmelerin etki alanını sorgulayabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.79', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000005', NULL, 'COG.11.5.1', 'Tarımsal faaliyetleri gıda güvencesi açısından sorgulayabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.82', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000005', NULL, 'COG.11.5.2', 'Dünya ve Türkiye’deki tarım uygulamalarını sürdürülebilirlik ölçütlerine göre değerlendirebilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.82', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000005', NULL, 'COG.11.5.3', 'Dünya ve Türkiye’de bulunan stratejik-kritik madenlerin ülke ekonomileri ve ülkeler arası ilişkilerdeki yerine yönelik çıkarım yapabilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.82', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000005', NULL, 'COG.11.5.4', 'Dünya ve Türkiye’deki enerji kaynaklarının kullanımında meydana gelen değişim ve sürekliliği algılayabilme', 4, 'TYMM 2026 Coğrafya Öğretim Programı, s.82', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000005', NULL, 'COG.11.5.5', 'Sanayi faaliyetlerinin mekânsal etkilerini sorgulayabilme', 5, 'TYMM 2026 Coğrafya Öğretim Programı, s.83', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000006', NULL, 'COG.11.6.1', 'Gezegen sınırının zorlanması sonucu oluşan çevre sorunlarına yönelik içerik oluşturabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.88', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000006', NULL, 'COG.11.6.2', 'Küresel iklim değişikliğinin etkilerini azaltma ve iklim değişikliğine uyum sağlamaya yönelik stratejileri tartışabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.88', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000006', NULL, 'COG.11.6.3', 'Türkiye’de bulunan su kaynaklarının sürdürülebilir kullanımını sorgulayabilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.88', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000007', NULL, 'COG.11.7.1', 'Türkiye ile Türkiye’nin kültürel açıdan güçlü ve köklü bağlara sahip olduğu yerler arasındaki etkileşimi sorgulayabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.93', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000007', NULL, 'COG.11.7.2', 'Örnek bir ülkenin tarımsal üretim özelliklerini coğrafi açıdan özetleyebilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.93', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000007', NULL, 'COG.11.7.3', 'Örnek ülkelerin sanayileşme süreçlerini coğrafi açıdan karşılaştırabilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.93', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000007', NULL, 'COG.11.7.4', 'Örnek bir ülkede yürütülen madencilik faaliyetleriyle ilgili tablo, grafik, şekil ve/veya diyagram hazırlayabilme', 4, 'TYMM 2026 Coğrafya Öğretim Programı, s.93', true, now(), now()),
  ('b9110000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c6', 11, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7110000-0000-4000-8000-000000000007', NULL, 'COG.11.7.5', 'Örnek ülkelerin enerji kaynaklarını coğrafi açıdan karşılaştırabilme', 5, 'TYMM 2026 Coğrafya Öğretim Programı, s.93', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000001', NULL, 'COG.12.1.1', 'Geleceğin dünyasında coğrafya biliminin etkilerine ilişkin öngörüde bulunabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.98', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000002', NULL, 'COG.12.2.1', 'Web tabanlı CBS ile oluşturulan tematik haritaları kullanarak uygulamalar yapabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.101', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000003', NULL, 'COG.12.3.1', 'Toprak oluşum sürecini toprak türleri açısından yapılandırabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.104', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000003', NULL, 'COG.12.3.2', 'Türkiye’de toprak kullanımının etkilerini sorgulayabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.104', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000003', NULL, 'COG.12.3.3', 'Coğrafi faktörlerin dünya ve Türkiye’deki bitki örtüsünün çeşitliliği ve dağılışı üzerindeki etkisi hakkında haritalardan çıkarım yapabilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.104', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000004', NULL, 'COG.12.4.1', 'Kültür-mekân etkileşimini coğrafi açıdan sorgulayabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.108', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000004', NULL, 'COG.12.4.2', 'Kültürel peyzajı sürdürülebilirlik açısından karşılaştırabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.108', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000005', NULL, 'COG.12.5.1', 'Dünya ve Türkiye’deki ulaşım sistemlerinin gelişim sürecinde meydana gelen değişim ve sürekliliği algılayabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.111', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000005', NULL, 'COG.12.5.2', 'Küresel ticaretin mekânsal bağlantılarını çözümleyebilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.111', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000005', NULL, 'COG.12.5.3', 'Turizm faaliyetlerinin dünya ve Türkiye’deki sosyal, kültürel, ekonomik, politik ve çevresel etkilerini sorgulayabilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.111', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000006', NULL, 'COG.12.6.1', 'Türkiye’de toprağın sürdürülebilir kullanımını sorgulayabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.115', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000006', NULL, 'COG.12.6.2', 'Türkiye’deki bitki topluluklarında görülen değişim ve sürekliliği algılayabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.115', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000006', NULL, 'COG.12.6.3', 'Türkiye ve farklı gelişmişlik seviyesine sahip ülkelerde çevre sorunlarının önlenmesi amacıyla hazırlanan politika ve uygulamaları karşılaştırabilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.115', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000006', NULL, 'COG.12.6.4', 'Doğal çevrenin korunması amacıyla yapılan organizasyon ve anlaşmaların etkisine ilişkin bilgi toplayabilme', 4, 'TYMM 2026 Coğrafya Öğretim Programı, s.115', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000006', NULL, 'COG.12.6.5', 'Dünya veya Türkiye’den örnek bir çevre problemine yönelik çözüm önerisi geliştirebilme', 5, 'TYMM 2026 Coğrafya Öğretim Programı, s.115', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000006', NULL, 'COG.12.6.6', 'Doğal ve kültürel mirasa yönelik tehditleri ortadan kaldırmak için ihtiyaç duyulan uygulamalara karar verebilme', 6, 'TYMM 2026 Coğrafya Öğretim Programı, s.116', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000007', NULL, 'COG.12.7.1', 'Uluslararası birlikteliklerin anlaşmazlıklara sunduğu çözümleri tartışabilme', 1, 'TYMM 2026 Coğrafya Öğretim Programı, s.121', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000007', NULL, 'COG.12.7.2', 'Örnek ülkelerin ulaşım sistemlerini karşılaştırabilme', 2, 'TYMM 2026 Coğrafya Öğretim Programı, s.121', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000007', NULL, 'COG.12.7.3', 'Örnek bir ülkeyi ticari faaliyetleri açısından sentezleyebilme', 3, 'TYMM 2026 Coğrafya Öğretim Programı, s.121', true, now(), now()),
  ('b9120000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c6', 12, 'cae032d4-54c0-41d2-b420-17a88fd3770a', 'b7120000-0000-4000-8000-000000000007', NULL, 'COG.12.7.4', 'Örnek ülkelerin turizm faaliyetlerini karşılaştırabilme', 4, 'TYMM 2026 Coğrafya Öğretim Programı, s.121', true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 4. MIGRATION HISTORY — idempotent kayıt (psql koşumunda statements=NULL;
--    CLI koşan ortamda CLI'ın kendi kaydı varsa bu INSERT atlanır).
-- ============================================================
insert into supabase_migrations.schema_migrations (version, name, statements)
select '145', '145_curriculum_cografya_tymm2026_agac', NULL
 where not exists (
   select 1 from supabase_migrations.schema_migrations where version = '145'
 );

-- ============================================================
-- 5. SON DENETİM (transaction içi; beklentiden sapan durum COMMIT'i durdurur)
-- ============================================================
DO $final$
DECLARE
  v_t integer; v_s integer; v_o integer; v_null_t integer; v_null_s integer; v_linked integer;
BEGIN
  SELECT count(*) INTO v_t FROM public.topics WHERE subject_id = 'cae032d4-54c0-41d2-b420-17a88fd3770a';
  SELECT count(*) INTO v_s FROM public.subtopics s JOIN public.topics t ON t.id = s.topic_id
   WHERE t.subject_id = 'cae032d4-54c0-41d2-b420-17a88fd3770a';
  SELECT count(*),
         count(*) FILTER (WHERE topic_id IS NULL),
         count(*) FILTER (WHERE subtopic_id IS NULL),
         count(*) FILTER (WHERE topic_id IS NOT NULL)
    INTO v_o, v_null_t, v_null_s, v_linked
    FROM public.curriculum_outcomes WHERE outcome_code LIKE 'COG.%';
  IF v_t <> 28 OR v_s <> 76 OR v_o <> 76 OR v_null_t <> 0 OR v_null_s <> 76 OR v_linked <> 76 THEN
    RAISE EXCEPTION 'FINAL_145: beklenen 28/76/76 (topic/subtopic/outcome), topic-bağlı=76, NULL subtopic=76; bulunan %/%/%/%/%/%', v_t, v_s, v_o, v_linked, v_null_s, v_null_t;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.curriculum_versions
                 WHERE id = 'a1000000-0000-4000-8000-0000000000c6' AND framework = 'tymm_2026_cografya') THEN
    RAISE EXCEPTION 'FINAL_145: sürüm satırı (a1000000-0000-4000-8000-0000000000c6) yok — beklenmeyen durum.';
  END IF;
END
$final$;

COMMIT;
