-- ============================================================
-- 143_curriculum_kimya_tymm2026_agac.sql
-- Altın Kalemler — CURRICULUM-ALL-01 Kimya dilimi: TYMM 2026 Kimya
--   müfredat ağacının (12 tema + 92 İçerik Çerçevesi maddesi + 93 yeni outcome)
--   YÜKLENMESİ ve tymm_2026_kimya curriculum_versions satırının OLUŞTURULMASI.
--
-- KULLANICI ONAYLI KAPSAM (2026-10-27)
--   - 1 sürüm + 12 topic + 92 subtopic + 93 outcome YÜKLENİR (9. sınıf: 3 tema + 20 madde + 23 çıktı; 10. sınıf: 3 tema + 20 madde + 21 çıktı; 11. sınıf: 3 tema + 26 madde + 25 çıktı; 12. sınıf: 3 tema + 26 madde + 24 çıktı).
--   - Kimya için DB'de ÖNCEDEN KIM.* outcome / topic / subtopic YOKTUR
--     (2026-10-27 salt-okunur ölçüm; dry-run eşleşen=0). Bu yüzden bölüm 4'teki
--     gibi "mevcut kayıt linkleme UPDATE'i" YOKTUR — migration salt EKLEME yapar.
--
-- KAYNAK (yalnız resmî)
--   Türkiye Yüzyılı Maarif Modeli — Ortaöğretim Kimya Dersi (9, 10, 11 ve
--   12. Sınıflar) Öğretim Programı (2026); PDF basılı sayfa numaraları.
--   Yerel: docs/references/mufredat/2026-2027/tymm-2026-kimya-9-12.pdf
--   Ağaç:  docs/question-production/curriculum-mapping/kimya-9-12-kanonik-esleme-v1.md
--   Dry-run: scripts/mufredat-dry-run.ts --ders=kimya → kimya-dry-run-sonuc.md
--   (197/197 veri satırı, 12/92/93, eşleşen 0, metin farkı 0, engelli 0)
--
-- UUID ŞEMASI (142 deseni; aileler DB envanteriyle çakışmasız seçildi)
--   Mevcut deterministik aileler: a1=versions, a2=schedule_profiles, a3=MAT topics,
--   a4=schedule_items, a5=FIZ topics, a6=MAT subtopics, a7=MAT outcomes,
--   a8=FIZ subtopics, a9=FIZ outcomes. YENİ AİLELER (topics/subtopics/outcomes
--   tablolarında envanterle boş doğrulandı — information_schema + hedef tablo taraması):
--   Kimya topic    : b1 + GG (sınıf) → b1GG0000-0000-4000-8000-0000000000NN
--   Kimya subtopic : b2 + GG (sınıf) → b2GG0000-0000-4000-8000-0000000000NN
--   Kimya outcome : b3 + GG (sınıf) → b3GG0000-0000-4000-8000-0000000000NN
--     (NN = sınıf içi (tema, k) sıralamasında kesintisiz sayaç, 001'den başlar)
--   Sürüm id: a1000000-0000-4000-8000-0000000000c4 (tymm_2026_kimya; a1 ailesinde c1/c2/c3'ten sonraki ilk boş değer).
--   Subject id: 6dbbbd2f-14d5-47aa-aef0-609a5e339b12 (Kimya, migration 045).
--
-- AD / SLUG / SIRA KARARLARI (142 birebir)
--   - topic.name: 'KIM.9.1 <TEMA ADI>' deseni; tema adı PDF'teki resmî
--     büyük harfli başlıktır ('N. TEMA: ' öneki atılır).
--   - topic.slug : kimya-GG-N-<tema-adı-slug>  (dry-run öneri formülüyle aynı).
--     DB kısıtı: UNIQUE (curriculum_version_id, subject_id, grade_level, slug).
--   - subtopic.name: İçerik Çerçevesi kutusundaki basılı madde (resmî).
--   - subtopic.slug: <topic-slug>-<madde-slug> (112 matematik deseni; UNIQUE (topic_id, slug)).
--   - subtopic.sort_order: sınıf içi kesintisiz (kutu sırası; tema değişince sıfırlanmaz).
--   - outcome.sort_order: kodun son basamağı k (tema-içi sıra) — 125/142 sözleşmesi.
--   - outcome.subtopic_id: NULL (kaynakta çıktı→alt konu ilişkisi numaralandırılmamıştır;
--     yakınlık/sıra/isim benzerliğiyle atama YASAKTIR — kanonik dosya §2, BLOKAJ-1 kuralı).
--   - source_reference: 'TYMM 2026 Kimya Öğretim Programı, s.NN' (125/142 deseni); NN = kazanım bloğunun
--     basılı sayfası (kanonik dosya §4/§5).
--
-- SÜRÜM SATIRI (125 fizik deseninden fark)
--   Fizik sürümü 125'te ayrı kurulmuştu; bu ders için curriculum_versions satırı YOKTU
--   (dry-run: 'BULUNAMADI'). Sürüm INSERT'i bölüm 0.5'tedir: is_default=false
--   (yıl-tek-default kısmi indeksi bozulmaz), UNIQUE (academic_year, framework) uyumlu.
--
-- İDEMPOTENCE
--   - Tüm INSERT'ler ON CONFLICT (id) DO NOTHING → tekrar koşum SIFIR yeni satır.
--   - GUARD: ağaç ya (0,0,0) (ilk uygulama) ya (12/92/93) dolu hâlde
--     olmalı; karışık/kısmi durum fail-closed durur. Dolu hâlde tüm id'ler tanınır.
--   - outcome_code'da UNIQUE KISIT YOKTUR (yalnız idx_curriculum_outcomes_code normal
--     indeks); mükerrer kod riski GUARD'ın benzersiz-kod denetimi + deterministik id ile
--     kapanır (142'nin iki katmanlı koruması).
--   - History: supabase_migrations.schema_migrations'a version='143' kaydı WHERE NOT
--     EXISTS ile idempotent eklenir; statements=NULL (psql koşumunda dosya kendi metnini
--     içine koyamaz; CLI uygulayan ortamda CLI statements'i doldurur — 142 notu birebir).
--
-- GERİ DÖNÜŞ: scripts/kimya-mufredat-geri-donus.sql (tek transaction;
--   93 outcome DELETE → 92 subtopic DELETE → 12 topic DELETE → sürüm satırı DELETE →
--   143 history DELETE; FK sırası korunur, fail-closed üçüncü-taraf referans taraması
--   içerir). Uygulama öncesi yedek (boş ön-durum kanıtı):
--   docs/references/mufredat/yedekler/kimya-on-yedek-20261027.sql
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
  IF NOT EXISTS (SELECT 1 FROM public.subjects WHERE id = '6dbbbd2f-14d5-47aa-aef0-609a5e339b12') THEN
    RAISE EXCEPTION 'GUARD_143: Kimya subject satırı yok — migration 045 uygulanmamış ortam.';
  END IF;

  -- Sürüm satırı: ya hiç yok (ilk uygulama) ya da TAM bu çift var (tekrar koşum).
  SELECT count(*) INTO v_surum FROM public.curriculum_versions
   WHERE framework = 'tymm_2026_kimya' OR id = 'a1000000-0000-4000-8000-0000000000c4';
  IF v_surum > 0 THEN
    IF NOT EXISTS (SELECT 1 FROM public.curriculum_versions
                   WHERE id = 'a1000000-0000-4000-8000-0000000000c4' AND framework = 'tymm_2026_kimya'
                     AND academic_year = '2026-2027' AND is_default = false) THEN
      RAISE EXCEPTION 'GUARD_143: tymm_2026_kimya/a1000000-0000-4000-8000-0000000000c4 sürüm satırı çelişkili (farklı id/framework/is_default) — fail-closed dur.';
    END IF;
  END IF;

  -- Ağaç durumu: ya boş ya tam dolu. Kısmi/yabancı durum fail-closed.
  SELECT count(*) INTO v_topic_sayi FROM public.topics
   WHERE subject_id = '6dbbbd2f-14d5-47aa-aef0-609a5e339b12';
  SELECT count(*) INTO v_subtopic_sayi FROM public.subtopics s
   JOIN public.topics t ON t.id = s.topic_id
   WHERE t.subject_id = '6dbbbd2f-14d5-47aa-aef0-609a5e339b12';
  SELECT count(*) INTO v_outcome_sayi FROM public.curriculum_outcomes
   WHERE outcome_code LIKE 'KIM.%';
  IF NOT (v_topic_sayi = 0 AND v_subtopic_sayi = 0 AND v_outcome_sayi = 0)
     AND NOT (v_topic_sayi = 12 AND v_subtopic_sayi = 92 AND v_outcome_sayi = 93) THEN
    RAISE EXCEPTION 'GUARD_143: Kimya ağacı kısmi/yabancı durumda (topics=%, subtopics=%, outcomes=%; beklenen 0/0/0 veya 12/92/93) — fail-closed dur.', v_topic_sayi, v_subtopic_sayi, v_outcome_sayi;
  END IF;

  -- Dolu hâl: id'lerin tamamı bu migration'ın deterministik kümesinden mi?
  IF v_topic_sayi = 12 THEN
    SELECT count(*) INTO v_yabanci FROM public.topics
     WHERE subject_id = '6dbbbd2f-14d5-47aa-aef0-609a5e339b12' AND id NOT IN (
      'b1090000-0000-4000-8000-000000000001',
      'b1090000-0000-4000-8000-000000000002',
      'b1090000-0000-4000-8000-000000000003',
      'b1100000-0000-4000-8000-000000000001',
      'b1100000-0000-4000-8000-000000000002',
      'b1100000-0000-4000-8000-000000000003',
      'b1110000-0000-4000-8000-000000000001',
      'b1110000-0000-4000-8000-000000000002',
      'b1110000-0000-4000-8000-000000000003',
      'b1120000-0000-4000-8000-000000000001',
      'b1120000-0000-4000-8000-000000000002',
      'b1120000-0000-4000-8000-000000000003'
    );
    IF v_yabanci > 0 THEN
      RAISE EXCEPTION 'GUARD_143: % yabancı Kimya topic id''si bulundu — fail-closed dur.', v_yabanci;
    END IF;
    SELECT count(*) INTO v_yabanci FROM public.subtopics s
     JOIN public.topics t ON t.id = s.topic_id
     WHERE t.subject_id = '6dbbbd2f-14d5-47aa-aef0-609a5e339b12' AND s.id NOT IN (
      'b2090000-0000-4000-8000-000000000001',
      'b2090000-0000-4000-8000-000000000002',
      'b2090000-0000-4000-8000-000000000003',
      'b2090000-0000-4000-8000-000000000004',
      'b2090000-0000-4000-8000-000000000005',
      'b2090000-0000-4000-8000-000000000006',
      'b2090000-0000-4000-8000-000000000007',
      'b2090000-0000-4000-8000-000000000008',
      'b2090000-0000-4000-8000-000000000009',
      'b2090000-0000-4000-8000-000000000010',
      'b2090000-0000-4000-8000-000000000011',
      'b2090000-0000-4000-8000-000000000012',
      'b2090000-0000-4000-8000-000000000013',
      'b2090000-0000-4000-8000-000000000014',
      'b2090000-0000-4000-8000-000000000015',
      'b2090000-0000-4000-8000-000000000016',
      'b2090000-0000-4000-8000-000000000017',
      'b2090000-0000-4000-8000-000000000018',
      'b2090000-0000-4000-8000-000000000019',
      'b2090000-0000-4000-8000-000000000020',
      'b2100000-0000-4000-8000-000000000001',
      'b2100000-0000-4000-8000-000000000002',
      'b2100000-0000-4000-8000-000000000003',
      'b2100000-0000-4000-8000-000000000004',
      'b2100000-0000-4000-8000-000000000005',
      'b2100000-0000-4000-8000-000000000006',
      'b2100000-0000-4000-8000-000000000007',
      'b2100000-0000-4000-8000-000000000008',
      'b2100000-0000-4000-8000-000000000009',
      'b2100000-0000-4000-8000-000000000010',
      'b2100000-0000-4000-8000-000000000011',
      'b2100000-0000-4000-8000-000000000012',
      'b2100000-0000-4000-8000-000000000013',
      'b2100000-0000-4000-8000-000000000014',
      'b2100000-0000-4000-8000-000000000015',
      'b2100000-0000-4000-8000-000000000016',
      'b2100000-0000-4000-8000-000000000017',
      'b2100000-0000-4000-8000-000000000018',
      'b2100000-0000-4000-8000-000000000019',
      'b2100000-0000-4000-8000-000000000020',
      'b2110000-0000-4000-8000-000000000001',
      'b2110000-0000-4000-8000-000000000002',
      'b2110000-0000-4000-8000-000000000003',
      'b2110000-0000-4000-8000-000000000004',
      'b2110000-0000-4000-8000-000000000005',
      'b2110000-0000-4000-8000-000000000006',
      'b2110000-0000-4000-8000-000000000007',
      'b2110000-0000-4000-8000-000000000008',
      'b2110000-0000-4000-8000-000000000009',
      'b2110000-0000-4000-8000-000000000010',
      'b2110000-0000-4000-8000-000000000011',
      'b2110000-0000-4000-8000-000000000012',
      'b2110000-0000-4000-8000-000000000013',
      'b2110000-0000-4000-8000-000000000014',
      'b2110000-0000-4000-8000-000000000015',
      'b2110000-0000-4000-8000-000000000016',
      'b2110000-0000-4000-8000-000000000017',
      'b2110000-0000-4000-8000-000000000018',
      'b2110000-0000-4000-8000-000000000019',
      'b2110000-0000-4000-8000-000000000020',
      'b2110000-0000-4000-8000-000000000021',
      'b2110000-0000-4000-8000-000000000022',
      'b2110000-0000-4000-8000-000000000023',
      'b2110000-0000-4000-8000-000000000024',
      'b2110000-0000-4000-8000-000000000025',
      'b2110000-0000-4000-8000-000000000026',
      'b2120000-0000-4000-8000-000000000001',
      'b2120000-0000-4000-8000-000000000002',
      'b2120000-0000-4000-8000-000000000003',
      'b2120000-0000-4000-8000-000000000004',
      'b2120000-0000-4000-8000-000000000005',
      'b2120000-0000-4000-8000-000000000006',
      'b2120000-0000-4000-8000-000000000007',
      'b2120000-0000-4000-8000-000000000008',
      'b2120000-0000-4000-8000-000000000009',
      'b2120000-0000-4000-8000-000000000010',
      'b2120000-0000-4000-8000-000000000011',
      'b2120000-0000-4000-8000-000000000012',
      'b2120000-0000-4000-8000-000000000013',
      'b2120000-0000-4000-8000-000000000014',
      'b2120000-0000-4000-8000-000000000015',
      'b2120000-0000-4000-8000-000000000016',
      'b2120000-0000-4000-8000-000000000017',
      'b2120000-0000-4000-8000-000000000018',
      'b2120000-0000-4000-8000-000000000019',
      'b2120000-0000-4000-8000-000000000020',
      'b2120000-0000-4000-8000-000000000021',
      'b2120000-0000-4000-8000-000000000022',
      'b2120000-0000-4000-8000-000000000023',
      'b2120000-0000-4000-8000-000000000024',
      'b2120000-0000-4000-8000-000000000025',
      'b2120000-0000-4000-8000-000000000026'
    );
    IF v_yabanci > 0 THEN
      RAISE EXCEPTION 'GUARD_143: % yabancı Kimya subtopic id''si bulundu — fail-closed dur.', v_yabanci;
    END IF;
    SELECT count(*), count(*) FILTER (WHERE id IN (
      'b3090000-0000-4000-8000-000000000001', 'b3090000-0000-4000-8000-000000000002', 'b3090000-0000-4000-8000-000000000003', 'b3090000-0000-4000-8000-000000000004', 'b3090000-0000-4000-8000-000000000005', 'b3090000-0000-4000-8000-000000000006', 'b3090000-0000-4000-8000-000000000007', 'b3090000-0000-4000-8000-000000000008', 'b3090000-0000-4000-8000-000000000009', 'b3090000-0000-4000-8000-000000000010', 'b3090000-0000-4000-8000-000000000011', 'b3090000-0000-4000-8000-000000000012', 'b3090000-0000-4000-8000-000000000013', 'b3090000-0000-4000-8000-000000000014', 'b3090000-0000-4000-8000-000000000015', 'b3090000-0000-4000-8000-000000000016', 'b3090000-0000-4000-8000-000000000017', 'b3090000-0000-4000-8000-000000000018', 'b3090000-0000-4000-8000-000000000019', 'b3090000-0000-4000-8000-000000000020', 'b3090000-0000-4000-8000-000000000021', 'b3090000-0000-4000-8000-000000000022', 'b3090000-0000-4000-8000-000000000023', 'b3100000-0000-4000-8000-000000000001', 'b3100000-0000-4000-8000-000000000002', 'b3100000-0000-4000-8000-000000000003', 'b3100000-0000-4000-8000-000000000004', 'b3100000-0000-4000-8000-000000000005', 'b3100000-0000-4000-8000-000000000006', 'b3100000-0000-4000-8000-000000000007', 'b3100000-0000-4000-8000-000000000008', 'b3100000-0000-4000-8000-000000000009', 'b3100000-0000-4000-8000-000000000010', 'b3100000-0000-4000-8000-000000000011', 'b3100000-0000-4000-8000-000000000012', 'b3100000-0000-4000-8000-000000000013', 'b3100000-0000-4000-8000-000000000014', 'b3100000-0000-4000-8000-000000000015', 'b3100000-0000-4000-8000-000000000016', 'b3100000-0000-4000-8000-000000000017', 'b3100000-0000-4000-8000-000000000018', 'b3100000-0000-4000-8000-000000000019', 'b3100000-0000-4000-8000-000000000020', 'b3100000-0000-4000-8000-000000000021', 'b3110000-0000-4000-8000-000000000001', 'b3110000-0000-4000-8000-000000000002', 'b3110000-0000-4000-8000-000000000003', 'b3110000-0000-4000-8000-000000000004', 'b3110000-0000-4000-8000-000000000005', 'b3110000-0000-4000-8000-000000000006', 'b3110000-0000-4000-8000-000000000007', 'b3110000-0000-4000-8000-000000000008', 'b3110000-0000-4000-8000-000000000009', 'b3110000-0000-4000-8000-000000000010', 'b3110000-0000-4000-8000-000000000011', 'b3110000-0000-4000-8000-000000000012', 'b3110000-0000-4000-8000-000000000013', 'b3110000-0000-4000-8000-000000000014', 'b3110000-0000-4000-8000-000000000015', 'b3110000-0000-4000-8000-000000000016', 'b3110000-0000-4000-8000-000000000017', 'b3110000-0000-4000-8000-000000000018', 'b3110000-0000-4000-8000-000000000019', 'b3110000-0000-4000-8000-000000000020', 'b3110000-0000-4000-8000-000000000021', 'b3110000-0000-4000-8000-000000000022', 'b3110000-0000-4000-8000-000000000023', 'b3110000-0000-4000-8000-000000000024', 'b3110000-0000-4000-8000-000000000025', 'b3120000-0000-4000-8000-000000000001', 'b3120000-0000-4000-8000-000000000002', 'b3120000-0000-4000-8000-000000000003', 'b3120000-0000-4000-8000-000000000004', 'b3120000-0000-4000-8000-000000000005', 'b3120000-0000-4000-8000-000000000006', 'b3120000-0000-4000-8000-000000000007', 'b3120000-0000-4000-8000-000000000008', 'b3120000-0000-4000-8000-000000000009', 'b3120000-0000-4000-8000-000000000010', 'b3120000-0000-4000-8000-000000000011', 'b3120000-0000-4000-8000-000000000012', 'b3120000-0000-4000-8000-000000000013', 'b3120000-0000-4000-8000-000000000014', 'b3120000-0000-4000-8000-000000000015', 'b3120000-0000-4000-8000-000000000016', 'b3120000-0000-4000-8000-000000000017', 'b3120000-0000-4000-8000-000000000018', 'b3120000-0000-4000-8000-000000000019', 'b3120000-0000-4000-8000-000000000020', 'b3120000-0000-4000-8000-000000000021', 'b3120000-0000-4000-8000-000000000022', 'b3120000-0000-4000-8000-000000000023', 'b3120000-0000-4000-8000-000000000024'
    )), count(DISTINCT outcome_code) INTO v_outcome_sayi, v_tanimli, v_benzersiz
      FROM public.curriculum_outcomes WHERE outcome_code LIKE 'KIM.%';
    IF v_outcome_sayi <> 93 OR v_tanimli <> 93 OR v_benzersiz <> 93 THEN
      RAISE EXCEPTION 'GUARD_143: KIM.* outcomes=% (tanınan id=%, benzersiz kod=%; beklenen 93/93/93) — id/kod drifti, fail-closed dur.', v_outcome_sayi, v_tanimli, v_benzersiz;
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
  'a1000000-0000-4000-8000-0000000000c4',
  '2026-2027',
  'tymm_2026_kimya',
  'Türkiye Yüzyılı Maarif Modeli Kimya Dersi (9, 10, 11 ve 12. Sınıflar) Öğretim Programı (2026)',
  'https://mufredat.meb.gov.tr/Dosyalar/2026518151539674-kimya.pdf',
  '2026-05-18',  -- mufredat.meb.gov.tr resmî URL zaman damgasından (125 fizik kararıyla aynı yöntem)
  true, false, now(), now()
)
on conflict (id) do nothing;

-- ============================================================
-- 1. TOPICS (12) — KIM.GG.N <TEMA ADI>; sort_order = resmî tema no (sınıf içi)
--    UNIQUE (curriculum_version_id, subject_id, grade_level, slug) koruması:
--    farklı id ile aynı slug varsa INSERT doğal olarak HATA verir (fail-closed).
-- ============================================================
insert into public.topics (
  id, subject_id, grade_level, name, slug, sort_order,
  is_active, curriculum_version_id, created_at, updated_at
) values
  ('b1090000-0000-4000-8000-000000000001', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 9, 'KIM.9.1 ETKİLEŞİM', 'kimya-9-1-etkilesim', 1, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now()),
  ('b1090000-0000-4000-8000-000000000002', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 9, 'KIM.9.2 ÇEŞİTLİLİK', 'kimya-9-2-cesitlilik', 2, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now()),
  ('b1090000-0000-4000-8000-000000000003', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 9, 'KIM.9.3 SÜRDÜRÜLEBİLİRLİK', 'kimya-9-3-surdurulebilirlik', 3, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now()),
  ('b1100000-0000-4000-8000-000000000001', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 10, 'KIM.10.1 ETKİLEŞİM', 'kimya-10-1-etkilesim', 1, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now()),
  ('b1100000-0000-4000-8000-000000000002', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 10, 'KIM.10.2 ÇEŞİTLİLİK', 'kimya-10-2-cesitlilik', 2, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now()),
  ('b1100000-0000-4000-8000-000000000003', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 10, 'KIM.10.3 SÜRDÜRÜLEBİLİRLİK', 'kimya-10-3-surdurulebilirlik', 3, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now()),
  ('b1110000-0000-4000-8000-000000000001', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 11, 'KIM.11.1 ETKİLEŞİM', 'kimya-11-1-etkilesim', 1, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now()),
  ('b1110000-0000-4000-8000-000000000002', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 11, 'KIM.11.2 ÇEŞİTLİLİK', 'kimya-11-2-cesitlilik', 2, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now()),
  ('b1110000-0000-4000-8000-000000000003', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 11, 'KIM.11.3 SÜRDÜRÜLEBİLİRLİK', 'kimya-11-3-surdurulebilirlik', 3, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now()),
  ('b1120000-0000-4000-8000-000000000001', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 12, 'KIM.12.1 ETKİLEŞİM', 'kimya-12-1-etkilesim', 1, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now()),
  ('b1120000-0000-4000-8000-000000000002', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 12, 'KIM.12.2 ÇEŞİTLİLİK', 'kimya-12-2-cesitlilik', 2, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now()),
  ('b1120000-0000-4000-8000-000000000003', '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 12, 'KIM.12.3 SÜRDÜRÜLEBİLİRLİK', 'kimya-12-3-surdurulebilirlik', 3, true, 'a1000000-0000-4000-8000-0000000000c4', now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 2. SUBTOPICS (92) — İçerik Çerçevesi maddeleri (resmî, basılı sıra);
--    sort_order sınıf içi kesintisiz (9: 1..20, 10: 1..20, 11: 1..26, 12: 1..26);
--    subtopic_id bağlantısı çıktılara AÇILMAZ (kaynak numaralandırmamış).
-- ============================================================
insert into public.subtopics (
  id, topic_id, name, slug, sort_order, is_active, created_at, updated_at
) values
  ('b2090000-0000-4000-8000-000000000001', 'b1090000-0000-4000-8000-000000000001', 'Günlük Hayatta Kimya', 'kimya-9-1-etkilesim-gunluk-hayatta-kimya', 1, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000002', 'b1090000-0000-4000-8000-000000000001', 'Kimyasal Maddelerin Kullanımı ve Güvenlik', 'kimya-9-1-etkilesim-kimyasal-maddelerin-kullanimi-ve-guvenlik', 2, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000003', 'b1090000-0000-4000-8000-000000000001', 'Kimyanın Alt Disiplinleri', 'kimya-9-1-etkilesim-kimyanin-alt-disiplinleri', 3, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000004', 'b1090000-0000-4000-8000-000000000001', 'Kimya Alanında Kariyer Olanakları', 'kimya-9-1-etkilesim-kimya-alaninda-kariyer-olanaklari', 4, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000005', 'b1090000-0000-4000-8000-000000000001', 'Atom Teorileri (Bohr Atom Teorisi, Modern Atom Teorisi) ve Atomun Yapısı', 'kimya-9-1-etkilesim-atom-teorileri-bohr-atom-teorisi-modern-atom-teorisi-ve-atomun-yapisi', 5, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000006', 'b1090000-0000-4000-8000-000000000001', 'Atom Orbitalleri ve Elektron Dizilimi', 'kimya-9-1-etkilesim-atom-orbitalleri-ve-elektron-dizilimi', 6, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000007', 'b1090000-0000-4000-8000-000000000001', 'Periyodik Tabloda Yer Bulma', 'kimya-9-1-etkilesim-periyodik-tabloda-yer-bulma', 7, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000008', 'b1090000-0000-4000-8000-000000000001', 'Periyodik Özellikler (Atom Yarıçapı, İyonlaşma Enerjisi ve Elektronegatiflik)', 'kimya-9-1-etkilesim-periyodik-ozellikler-atom-yaricapi-iyonlasma-enerjisi-ve-elektronegatiflik', 8, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000009', 'b1090000-0000-4000-8000-000000000002', 'Metalik Bağ', 'kimya-9-2-cesitlilik-metalik-bag', 9, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000010', 'b1090000-0000-4000-8000-000000000002', 'İyonik Bağ', 'kimya-9-2-cesitlilik-iyonik-bag', 10, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000011', 'b1090000-0000-4000-8000-000000000002', 'Kovalent Bağ', 'kimya-9-2-cesitlilik-kovalent-bag', 11, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000012', 'b1090000-0000-4000-8000-000000000002', 'Lewis Nokta Yapısı', 'kimya-9-2-cesitlilik-lewis-nokta-yapisi', 12, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000013', 'b1090000-0000-4000-8000-000000000002', 'Molekül Polarlığı ve Apolarlığı', 'kimya-9-2-cesitlilik-molekul-polarligi-ve-apolarligi', 13, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000014', 'b1090000-0000-4000-8000-000000000002', 'Bileşiklerin Adlandırılması', 'kimya-9-2-cesitlilik-bilesiklerin-adlandirilmasi', 14, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000015', 'b1090000-0000-4000-8000-000000000002', 'Moleküller Arası Etkileşimler', 'kimya-9-2-cesitlilik-molekuller-arasi-etkilesimler', 15, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000016', 'b1090000-0000-4000-8000-000000000002', 'Katılar ve Özellikleri (Amorf ve Kristal Katılar)', 'kimya-9-2-cesitlilik-katilar-ve-ozellikleri-amorf-ve-kristal-katilar', 16, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000017', 'b1090000-0000-4000-8000-000000000002', 'Sıvılar ve Özellikleri (Kaynama Sıcaklığı ve Buhar Basıncı, Viskozite, Adezyon ve Kohezyon Kuvvetleri, Yüzey Gerilimi)', 'kimya-9-2-cesitlilik-sivilar-ve-ozellikleri-kaynama-sicakligi-ve-buhar-basinci-viskozite-adezyon-ve-kohezyon-kuvvetleri-yuzey-gerilimi', 17, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000018', 'b1090000-0000-4000-8000-000000000003', 'Metal Nanoparçacıklar', 'kimya-9-3-surdurulebilirlik-metal-nanoparcaciklar', 18, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000019', 'b1090000-0000-4000-8000-000000000003', 'Metal, Alaşım ve Metal Nanoparçacıkların Çevresel Etkileri', 'kimya-9-3-surdurulebilirlik-metal-alasim-ve-metal-nanoparcaciklarin-cevresel-etkileri', 19, true, now(), now()),
  ('b2090000-0000-4000-8000-000000000020', 'b1090000-0000-4000-8000-000000000003', 'Yeşil Kimyanın Atık Önleme İlkesi', 'kimya-9-3-surdurulebilirlik-yesil-kimyanin-atik-onleme-ilkesi', 20, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000001', 'b1100000-0000-4000-8000-000000000001', 'Kimyasal Değişimin Göstergeleri', 'kimya-10-1-etkilesim-kimyasal-degisimin-gostergeleri', 1, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000002', 'b1100000-0000-4000-8000-000000000001', 'Kimyasal Tepkimelerin Oluşumu', 'kimya-10-1-etkilesim-kimyasal-tepkimelerin-olusumu', 2, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000003', 'b1100000-0000-4000-8000-000000000001', 'Kimyasal Tepkime Türleri', 'kimya-10-1-etkilesim-kimyasal-tepkime-turleri', 3, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000004', 'b1100000-0000-4000-8000-000000000001', 'Mol Kavramı', 'kimya-10-1-etkilesim-mol-kavrami', 4, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000005', 'b1100000-0000-4000-8000-000000000001', 'Kimyasal Tepkime Denklemlerinin Denkleştirilmesi', 'kimya-10-1-etkilesim-kimyasal-tepkime-denklemlerinin-denklestirilmesi', 5, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000006', 'b1100000-0000-4000-8000-000000000001', 'Kimyasal (Stokiyometrik) Hesaplamalar', 'kimya-10-1-etkilesim-kimyasal-stokiyometrik-hesaplamalar', 6, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000007', 'b1100000-0000-4000-8000-000000000001', 'Gazların Özellikleri ve Kinetik Moleküler Teori', 'kimya-10-1-etkilesim-gazlarin-ozellikleri-ve-kinetik-molekuler-teori', 7, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000008', 'b1100000-0000-4000-8000-000000000001', 'Gaz Yasaları', 'kimya-10-1-etkilesim-gaz-yasalari', 8, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000009', 'b1100000-0000-4000-8000-000000000001', 'İdeal Gaz Yasası', 'kimya-10-1-etkilesim-ideal-gaz-yasasi', 9, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000010', 'b1100000-0000-4000-8000-000000000001', 'Graham Difüzyon ve Efüzyon Yasası', 'kimya-10-1-etkilesim-graham-difuzyon-ve-efuzyon-yasasi', 10, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000011', 'b1100000-0000-4000-8000-000000000002', 'Çözünme Süreci', 'kimya-10-2-cesitlilik-cozunme-sureci', 11, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000012', 'b1100000-0000-4000-8000-000000000002', 'Maddelerin Birbiri İçindeki Çözünebilirliği', 'kimya-10-2-cesitlilik-maddelerin-birbiri-icindeki-cozunebilirligi', 12, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000013', 'b1100000-0000-4000-8000-000000000002', 'Çözünme Olayının Sınıflandırılması', 'kimya-10-2-cesitlilik-cozunme-olayinin-siniflandirilmasi', 13, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000014', 'b1100000-0000-4000-8000-000000000002', 'Çözünürlük', 'kimya-10-2-cesitlilik-cozunurluk', 14, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000015', 'b1100000-0000-4000-8000-000000000002', 'Çözünürlüğe Etki Eden Faktörler (Sıcaklık, Basınç ve Madde Cinsi)', 'kimya-10-2-cesitlilik-cozunurluge-etki-eden-faktorler-sicaklik-basinc-ve-madde-cinsi', 15, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000016', 'b1100000-0000-4000-8000-000000000002', 'Çözeltilerin Sınıflandırılması', 'kimya-10-2-cesitlilik-cozeltilerin-siniflandirilmasi', 16, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000017', 'b1100000-0000-4000-8000-000000000002', 'Derişim Birimleri (Molarite ve ppm)', 'kimya-10-2-cesitlilik-derisim-birimleri-molarite-ve-ppm', 17, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000018', 'b1100000-0000-4000-8000-000000000002', 'Koligatif Özellikler (Kaynama Noktası Yükselmesi ve Donma Noktası Düşmesi)', 'kimya-10-2-cesitlilik-koligatif-ozellikler-kaynama-noktasi-yukselmesi-ve-donma-noktasi-dusmesi', 18, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000019', 'b1100000-0000-4000-8000-000000000003', 'Makro ve Mikro Ölçekli Deneyler', 'kimya-10-3-surdurulebilirlik-makro-ve-mikro-olcekli-deneyler', 19, true, now(), now()),
  ('b2100000-0000-4000-8000-000000000020', 'b1100000-0000-4000-8000-000000000003', 'Atmosferdeki Tepkimeler ve Küresel Sorunlar', 'kimya-10-3-surdurulebilirlik-atmosferdeki-tepkimeler-ve-kuresel-sorunlar', 20, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000001', 'b1110000-0000-4000-8000-000000000001', 'Tepkimelerde Meydana Gelen Enerji Değişimi', 'kimya-11-1-etkilesim-tepkimelerde-meydana-gelen-enerji-degisimi', 1, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000002', 'b1110000-0000-4000-8000-000000000001', 'Maddelerin Enerji Kaynağı Olma Potansiyeli', 'kimya-11-1-etkilesim-maddelerin-enerji-kaynagi-olma-potansiyeli', 2, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000003', 'b1110000-0000-4000-8000-000000000001', 'Bağ Enerjileriyle Tepkime Entalpisinin Hesaplanması', 'kimya-11-1-etkilesim-bag-enerjileriyle-tepkime-entalpisinin-hesaplanmasi', 3, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000004', 'b1110000-0000-4000-8000-000000000001', 'Standart Oluşum Entalpileriyle Tepkime Entalpisinin Hesaplanması', 'kimya-11-1-etkilesim-standart-olusum-entalpileriyle-tepkime-entalpisinin-hesaplanmasi', 4, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000005', 'b1110000-0000-4000-8000-000000000001', 'Kimyasal Tepkimelerin Gerçekleşmesi İçin Gerekli Şartlar', 'kimya-11-1-etkilesim-kimyasal-tepkimelerin-gerceklesmesi-icin-gerekli-sartlar', 5, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000006', 'b1110000-0000-4000-8000-000000000001', 'Tepken ve Ürün Derişimleriyle Ortalama Tepkime Hızlarının Hesaplanması', 'kimya-11-1-etkilesim-tepken-ve-urun-derisimleriyle-ortalama-tepkime-hizlarinin-hesaplanmasi', 6, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000007', 'b1110000-0000-4000-8000-000000000001', 'Tepkime Hızına Etki Eden Faktörler (Tepken Cinsi, Maddelerin Fiziksel Hâlleri, Derişim, Sıcaklık, Katı Tepkenin Temas Yüzeyi ve Katalizör)', 'kimya-11-1-etkilesim-tepkime-hizina-etki-eden-faktorler-tepken-cinsi-maddelerin-fiziksel-halleri-derisim-sicaklik-kati-tepkenin-temas-yuzeyi-ve-katalizor', 7, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000008', 'b1110000-0000-4000-8000-000000000001', 'Tek Basamaklı Kimyasal Tepkimelerin Hız Denkleminin Deneysel Veriler Yardımıyla Belirlenmesi', 'kimya-11-1-etkilesim-tek-basamakli-kimyasal-tepkimelerin-hiz-denkleminin-deneysel-veriler-yardimiyla-belirlenmesi', 8, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000009', 'b1110000-0000-4000-8000-000000000002', 'Tersinir Tepkimelerin Özellikleri', 'kimya-11-2-cesitlilik-tersinir-tepkimelerin-ozellikleri', 9, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000010', 'b1110000-0000-4000-8000-000000000002', 'Fiziksel ve Kimyasal Değişimlerde Denge', 'kimya-11-2-cesitlilik-fiziksel-ve-kimyasal-degisimlerde-denge', 10, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000011', 'b1110000-0000-4000-8000-000000000002', 'Denge Sabiti İfadesinin Yazılması', 'kimya-11-2-cesitlilik-denge-sabiti-ifadesinin-yazilmasi', 11, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000012', 'b1110000-0000-4000-8000-000000000002', 'Tepkime Oranı', 'kimya-11-2-cesitlilik-tepkime-orani', 12, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000013', 'b1110000-0000-4000-8000-000000000002', 'Dengeyi Etkileyen Faktörler (Derişim, Hacim, Basınç, Sıcaklık ve Katalizör)', 'kimya-11-2-cesitlilik-dengeyi-etkileyen-faktorler-derisim-hacim-basinc-sicaklik-ve-katalizor', 13, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000014', 'b1110000-0000-4000-8000-000000000002', 'Suyun Otoiyonizasyonu', 'kimya-11-2-cesitlilik-suyun-otoiyonizasyonu', 14, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000015', 'b1110000-0000-4000-8000-000000000002', 'Asit Baz Teorilerinin Karşılaştırılması', 'kimya-11-2-cesitlilik-asit-baz-teorilerinin-karsilastirilmasi', 15, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000016', 'b1110000-0000-4000-8000-000000000002', 'Asitlerin ve Bazların Kuvveti', 'kimya-11-2-cesitlilik-asitlerin-ve-bazlarin-kuvveti', 16, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000017', 'b1110000-0000-4000-8000-000000000002', 'Kuvvetli Asit-Zayıf Asit ve Kuvvetli Baz-Zayıf Baz Sulu Çözeltilerindeki pH Hesaplamaları', 'kimya-11-2-cesitlilik-kuvvetli-asit-zayif-asit-ve-kuvvetli-baz-zayif-baz-sulu-cozeltilerindeki-ph-hesaplamalari', 17, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000018', 'b1110000-0000-4000-8000-000000000002', 'Kuvvetli Asit ve Kuvvetli Bazların Nötralleşme Tepkimeleri', 'kimya-11-2-cesitlilik-kuvvetli-asit-ve-kuvvetli-bazlarin-notrallesme-tepkimeleri', 18, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000019', 'b1110000-0000-4000-8000-000000000002', 'Kuvvetli Asit-Kuvvetli Baz Titrasyonları', 'kimya-11-2-cesitlilik-kuvvetli-asit-kuvvetli-baz-titrasyonlari', 19, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000020', 'b1110000-0000-4000-8000-000000000002', 'Asidik ve Bazik Ürünlerin Seçiminde Dikkat Edilmesi Gerekenler', 'kimya-11-2-cesitlilik-asidik-ve-bazik-urunlerin-seciminde-dikkat-edilmesi-gerekenler', 20, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000021', 'b1110000-0000-4000-8000-000000000002', 'Suda Az Çözünen Tuzların Molar Çözünürlükleri', 'kimya-11-2-cesitlilik-suda-az-cozunen-tuzlarin-molar-cozunurlukleri', 21, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000022', 'b1110000-0000-4000-8000-000000000002', 'Çözünürlük Çarpımı (Kçç)', 'kimya-11-2-cesitlilik-cozunurluk-carpimi-kcc', 22, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000023', 'b1110000-0000-4000-8000-000000000002', 'Tuzların Çözünürlüğüne Etki Eden Faktörler (Sıcaklık ve Ortak İyon)', 'kimya-11-2-cesitlilik-tuzlarin-cozunurlugune-etki-eden-faktorler-sicaklik-ve-ortak-iyon', 23, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000024', 'b1110000-0000-4000-8000-000000000003', 'Fermantasyon Yöntemi ile Yeşil Hidrojen Enerjisi ve Hidrojen Gazı Miktarına Etki Eden Faktörler', 'kimya-11-3-surdurulebilirlik-fermantasyon-yontemi-ile-yesil-hidrojen-enerjisi-ve-hidrojen-gazi-miktarina-etki-eden-faktorler', 24, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000025', 'b1110000-0000-4000-8000-000000000003', 'Nanoteknolojik Ürünlerin Potansiyel Faydaları ve Olası Zararları', 'kimya-11-3-surdurulebilirlik-nanoteknolojik-urunlerin-potansiyel-faydalari-ve-olasi-zararlari', 25, true, now(), now()),
  ('b2110000-0000-4000-8000-000000000026', 'b1110000-0000-4000-8000-000000000003', 'Mikroplastik ve Nanoplastiklerin Etkileri', 'kimya-11-3-surdurulebilirlik-mikroplastik-ve-nanoplastiklerin-etkileri', 26, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000001', 'b1120000-0000-4000-8000-000000000001', 'Redoks Tepkimeleri ve Yarı Tepkimeler', 'kimya-12-1-etkilesim-redoks-tepkimeleri-ve-yari-tepkimeler', 1, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000002', 'b1120000-0000-4000-8000-000000000001', 'Metalik Aktiflik', 'kimya-12-1-etkilesim-metalik-aktiflik', 2, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000003', 'b1120000-0000-4000-8000-000000000001', 'Galvanik Hücreler', 'kimya-12-1-etkilesim-galvanik-hucreler', 3, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000004', 'b1120000-0000-4000-8000-000000000001', 'Standart Hidrojen Elektrot', 'kimya-12-1-etkilesim-standart-hidrojen-elektrot', 4, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000005', 'b1120000-0000-4000-8000-000000000001', 'Standart İndirgenme Potansiyeli', 'kimya-12-1-etkilesim-standart-indirgenme-potansiyeli', 5, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000006', 'b1120000-0000-4000-8000-000000000001', 'Standart Hücre Potansiyeline Etki Eden Faktörler (Elektrotların Aktifliği, Elektrolit Derişimi ve Sıcaklık)', 'kimya-12-1-etkilesim-standart-hucre-potansiyeline-etki-eden-faktorler-elektrotlarin-aktifligi-elektrolit-derisimi-ve-sicaklik', 6, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000007', 'b1120000-0000-4000-8000-000000000001', 'Elektrolitik Hücreler', 'kimya-12-1-etkilesim-elektrolitik-hucreler', 7, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000008', 'b1120000-0000-4000-8000-000000000001', 'Madde-Elektrik İlişkisi', 'kimya-12-1-etkilesim-madde-elektrik-iliskisi', 8, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000009', 'b1120000-0000-4000-8000-000000000001', 'Elektrolizle Kaplama', 'kimya-12-1-etkilesim-elektrolizle-kaplama', 9, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000010', 'b1120000-0000-4000-8000-000000000001', 'Korozyon ve Korozyonu Önleme Yöntemleri', 'kimya-12-1-etkilesim-korozyon-ve-korozyonu-onleme-yontemleri', 10, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000011', 'b1120000-0000-4000-8000-000000000002', 'Sigma ve Pi Bağları', 'kimya-12-2-cesitlilik-sigma-ve-pi-baglari', 11, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000012', 'b1120000-0000-4000-8000-000000000002', 'Hibritleşme', 'kimya-12-2-cesitlilik-hibritlesme', 12, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000013', 'b1120000-0000-4000-8000-000000000002', 'Molekül Geometrisi ve VSEPR Kuramı', 'kimya-12-2-cesitlilik-molekul-geometrisi-ve-vsepr-kurami', 13, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000014', 'b1120000-0000-4000-8000-000000000002', 'Organik Bileşiklerin Yapı Formülleri', 'kimya-12-2-cesitlilik-organik-bilesiklerin-yapi-formulleri', 14, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000015', 'b1120000-0000-4000-8000-000000000002', 'Alifatik ve Aromatik Hidrokarbonlar', 'kimya-12-2-cesitlilik-alifatik-ve-aromatik-hidrokarbonlar', 15, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000016', 'b1120000-0000-4000-8000-000000000002', 'Alifatik Hidrokarbonların Sınıflandırılması', 'kimya-12-2-cesitlilik-alifatik-hidrokarbonlarin-siniflandirilmasi', 16, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000017', 'b1120000-0000-4000-8000-000000000002', 'Alifatik Hidrokarbonların Sistematik Adlandırılması', 'kimya-12-2-cesitlilik-alifatik-hidrokarbonlarin-sistematik-adlandirilmasi', 17, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000018', 'b1120000-0000-4000-8000-000000000002', 'Alifatik Hidrokarbonların İzomerlikleri', 'kimya-12-2-cesitlilik-alifatik-hidrokarbonlarin-izomerlikleri', 18, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000019', 'b1120000-0000-4000-8000-000000000002', 'Alifatik Hidrokarbonların Fiziksel ve Kimyasal Özellikleri', 'kimya-12-2-cesitlilik-alifatik-hidrokarbonlarin-fiziksel-ve-kimyasal-ozellikleri', 19, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000020', 'b1120000-0000-4000-8000-000000000002', 'Organik Bileşikleri Fonksiyonel Gruplarına Göre Sınıflandırma', 'kimya-12-2-cesitlilik-organik-bilesikleri-fonksiyonel-gruplarina-gore-siniflandirma', 20, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000021', 'b1120000-0000-4000-8000-000000000002', 'Fonksiyonel Gruba Sahip Organik Bileşiklerin Sistematik Adlandırılması', 'kimya-12-2-cesitlilik-fonksiyonel-gruba-sahip-organik-bilesiklerin-sistematik-adlandirilmasi', 21, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000022', 'b1120000-0000-4000-8000-000000000002', 'Fonksiyonel Grup İzomerliği', 'kimya-12-2-cesitlilik-fonksiyonel-grup-izomerligi', 22, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000023', 'b1120000-0000-4000-8000-000000000002', 'Karbon Temelli Enerji Kaynakları', 'kimya-12-2-cesitlilik-karbon-temelli-enerji-kaynaklari', 23, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000024', 'b1120000-0000-4000-8000-000000000003', 'Boyaya Duyarlı Güneş Pili', 'kimya-12-3-surdurulebilirlik-boyaya-duyarli-gunes-pili', 24, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000025', 'b1120000-0000-4000-8000-000000000003', 'Biyobozunur Polimer', 'kimya-12-3-surdurulebilirlik-biyobozunur-polimer', 25, true, now(), now()),
  ('b2120000-0000-4000-8000-000000000026', 'b1120000-0000-4000-8000-000000000003', 'Yapay Zekâ ve Sürdürülebilirlik', 'kimya-12-3-surdurulebilirlik-yapay-zeka-ve-surdurulebilirlik', 26, true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 3. OUTCOMES (93) — KIM.s.u.k (resmî kodlar; türetilmemiş).
--    sort_order = k (tema-içi; 125 sözleşmesi). subtopic_id = NULL
--    (kaynakta numaralandırılmamış — kasıtlı ve onaylı).
--    id NN sırası: sınıf içi (tema, k) — 9: 3/20/23, 10: 3/20/21, 11: 3/26/25, 12: 3/26/24.
-- ============================================================
insert into public.curriculum_outcomes (
  id, curriculum_version_id, grade_level, subject_id, topic_id, subtopic_id,
  outcome_code, outcome_text, sort_order, source_reference, is_active, created_at, updated_at
) values
  ('b3090000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000001', NULL, 'KIM.9.1.1', 'Kimya biliminin günlük hayata katkısına ilişkin bilimsel çıkarım yapabilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.14', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000001', NULL, 'KIM.9.1.2', 'Farklı ortamlarda kimyasal maddelerin kullanımından kaynaklanan problemleri çözebilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.14', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000001', NULL, 'KIM.9.1.3', 'Atom teorilerindeki varsayımları kullanarak bilimsel bilginin değişebilirliğine ilişkin bilimsel çıkarım yapabilme', 3, 'TYMM 2026 Kimya Öğretim Programı, s.14', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000001', NULL, 'KIM.9.1.4', 'Atom orbitallerinin bağıl enerjilerine ilişkin bilimsel veriye dayalı tahminde bulunabilme', 4, 'TYMM 2026 Kimya Öğretim Programı, s.14', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000001', NULL, 'KIM.9.1.5', 'Elektronların atom orbitallerine yerleşimine ilişkin tümevarımsal akıl yürütebilme', 5, 'TYMM 2026 Kimya Öğretim Programı, s.14', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000001', NULL, 'KIM.9.1.6', 'Elementlerin periyodik tablodaki yerlerine ilişkin tümevarımsal akıl yürütebilme', 6, 'TYMM 2026 Kimya Öğretim Programı, s.14', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000001', NULL, 'KIM.9.1.7', 'İyon oluşumuna ilişkin tümevarımsal akıl yürütebilme', 7, 'TYMM 2026 Kimya Öğretim Programı, s.15', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000001', NULL, 'KIM.9.1.8', 'Elementlerin periyodik özelliklerinin periyodik tablodaki değişimini çözümleyebilme', 8, 'TYMM 2026 Kimya Öğretim Programı, s.15', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.1', 'Metalik bağın oluşumuna yönelik tümevarımsal akıl yürütebilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.23', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.2', 'İyonik bağın oluşumunu bilimsel gözleme dayalı tahmin edebilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.23', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.3', 'Kovalent bağ oluşumunu bilimsel gözleme dayalı tahmin edebilme', 3, 'TYMM 2026 Kimya Öğretim Programı, s.23', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.4', 'Moleküllerin Lewis nokta yapısına ilişkin çıkarımda bulunabilme', 4, 'TYMM 2026 Kimya Öğretim Programı, s.23', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.5', 'Molekülleri polar ya da apolar olarak sınıflandırabilme', 5, 'TYMM 2026 Kimya Öğretim Programı, s.23', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.6', 'Bileşikleri adlandırma kurallarına ilişkin tümdengelimsel akıl yürütebilme', 6, 'TYMM 2026 Kimya Öğretim Programı, s.23', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.7', 'Moleküller arası etkileşimleri sınıflandırabilme', 7, 'TYMM 2026 Kimya Öğretim Programı, s.24', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.8', 'Etkileşimlerin katıların özellikleri üzerindeki etkilerine ilişkin bilimsel çıkarım yapabilme', 8, 'TYMM 2026 Kimya Öğretim Programı, s.24', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.9', 'Sıvıların buhar basıncını etkileyen faktörlere ilişkin hipotez oluşturabilme', 9, 'TYMM 2026 Kimya Öğretim Programı, s.24', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.10', 'Sıvıların kaynama sıcaklığını etkileyen faktörleri belirlemeye yönelik kanıt kullanabilme', 10, 'TYMM 2026 Kimya Öğretim Programı, s.24', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.11', 'Sıvıların viskozitesini etkileyen faktörlere ilişkin bilimsel gözlem yapabilme', 11, 'TYMM 2026 Kimya Öğretim Programı, s.24', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.12', 'Adezyon ve kohezyon kuvvetlerinin sıvıların özellikleri üzerindeki etkilerine ilişkin bilimsel çıkarım yapabilme', 12, 'TYMM 2026 Kimya Öğretim Programı, s.24', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000021', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000002', NULL, 'KIM.9.2.13', 'Sıvıların yüzey gerilimini etkileyen faktörlere ilişkin bilimsel sorgulama yapabilme', 13, 'TYMM 2026 Kimya Öğretim Programı, s.25', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000022', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000003', NULL, 'KIM.9.3.1', 'Evsel atıklardan metal nanoparçacık elde etmek üzere deney yapabilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.35', true, now(), now()),
  ('b3090000-0000-4000-8000-000000000023', 'a1000000-0000-4000-8000-0000000000c4', 9, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1090000-0000-4000-8000-000000000003', NULL, 'KIM.9.3.2', 'Metal, alaşım ve metal nanoparçacıkların ekosistemdeki etkilerine ilişkin problem çözebilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.35', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000001', NULL, 'KIM.10.1.1', 'Kimyasal değişimlere ilişkin kanıtları belirlemeye yönelik bilimsel gözlem yapabilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.40', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000001', NULL, 'KIM.10.1.2', 'Kimyasal tepkimelerin oluşumunu açıklamak için bilimsel model oluşturabilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.40', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000001', NULL, 'KIM.10.1.3', 'Kimyasal tepkime türlerinin oluşum sürecine ilişkin bilimsel gözlem yapabilme', 3, 'TYMM 2026 Kimya Öğretim Programı, s.40', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000001', NULL, 'KIM.10.1.4', 'Mol kavramına ilişkin operasyonel tanımlama yapabilme', 4, 'TYMM 2026 Kimya Öğretim Programı, s.40', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000001', NULL, 'KIM.10.1.5', 'Saf maddelerin ölçülebilir özellikleri arasındaki ilişkileri belirlemeye yönelik tümdengelimsel akıl yürütebilme', 5, 'TYMM 2026 Kimya Öğretim Programı, s.40', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000001', NULL, 'KIM.10.1.6', 'Kimyasal tepkime denklemlerinde tanecik sayılarının tutarsızlıklarına ilişkin çelişkiyi giderebilme', 6, 'TYMM 2026 Kimya Öğretim Programı, s.40', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000001', NULL, 'KIM.10.1.7', 'Kimyasal tepkimelerde stokiyometrik ilişkilere yönelik tümdengelimsel akıl yürütebilme', 7, 'TYMM 2026 Kimya Öğretim Programı, s.41', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000001', NULL, 'KIM.10.1.8', 'Gazların özelliklerine ilişkin bilimsel gözlem yapabilme', 8, 'TYMM 2026 Kimya Öğretim Programı, s.41', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000001', NULL, 'KIM.10.1.9', 'Gazların özellikleri arasındaki ilişkileri bilimsel sorgulayabilme', 9, 'TYMM 2026 Kimya Öğretim Programı, s.41', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000001', NULL, 'KIM.10.1.10', 'İdeal gaz denklemini tümevarımsal akıl yürütme yoluyla oluşturabilme', 10, 'TYMM 2026 Kimya Öğretim Programı, s.41', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000001', NULL, 'KIM.10.1.11', 'Gazların farklı ortamlarda yayılmasına ilişkin deney yapabilme', 11, 'TYMM 2026 Kimya Öğretim Programı, s.41', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000002', NULL, 'KIM.10.2.1', 'Çözünme sürecine ilişkin bilimsel model oluşturabilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.49', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000002', NULL, 'KIM.10.2.2', 'Farklı maddelerin birbiri içinde çözünebilirliğini kanıt kullanarak açıklayabilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.49', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000002', NULL, 'KIM.10.2.3', 'Çözünme olayını sınıflandırabilme', 3, 'TYMM 2026 Kimya Öğretim Programı, s.49', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000002', NULL, 'KIM.10.2.4', 'Çözünürlük kavramına ilişkin operasyonel tanımlama yapabilme', 4, 'TYMM 2026 Kimya Öğretim Programı, s.49', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000002', NULL, 'KIM.10.2.5', 'Çözünürlüğe etki eden faktörleri belirlemeye yönelik kanıt kullanabilme', 5, 'TYMM 2026 Kimya Öğretim Programı, s.49', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000002', NULL, 'KIM.10.2.6', 'Çözeltileri sınıflandırabilme', 6, 'TYMM 2026 Kimya Öğretim Programı, s.49', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000002', NULL, 'KIM.10.2.7', 'Çözeltilerin molar derişimine ilişkin tümevarımsal akıl yürütebilme', 7, 'TYMM 2026 Kimya Öğretim Programı, s.49', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000002', NULL, 'KIM.10.2.8', 'Çözünen maddenin tanecik sayısının çözeltilerin kaynama ve donma noktasına etkisini belirlemeye yönelik hipotez oluşturabilme', 8, 'TYMM 2026 Kimya Öğretim Programı, s.50', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000003', NULL, 'KIM.10.3.1', 'Kimya dersinde mikro ölçekli deney tercih etmenin sonuçlarını ekosistem açısından değerlendirebilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.57', true, now(), now()),
  ('b3100000-0000-4000-8000-000000000021', 'a1000000-0000-4000-8000-0000000000c4', 10, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1100000-0000-4000-8000-000000000003', NULL, 'KIM.10.3.2', 'Kimyasal tepkimeler sonucunda atmosferin doğasındaki değişimin ekosisteme etkilerine yönelik problem çözebilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.57', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000001', NULL, 'KIM.11.1.1', 'Fiziksel ve kimyasal olaylardaki enerji değişimine ilişkin deney yapabilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.61', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000001', NULL, 'KIM.11.1.2', 'Maddelerin enerji kaynağı olma potansiyeline ilişkin hipotezler oluşturabilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.61', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000001', NULL, 'KIM.11.1.3', 'Bağ enerjileri temelinde tepkimelerin entalpi değişimine ilişkin tümevarımsal akıl yürütebilme', 3, 'TYMM 2026 Kimya Öğretim Programı, s.61', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000001', NULL, 'KIM.11.1.4', 'Kimyasal tepkimelerin standart tepkime entalpilerini standart oluşum entalpi verilerini kullanarak tahmin edebilme', 4, 'TYMM 2026 Kimya Öğretim Programı, s.61', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000001', NULL, 'KIM.11.1.5', 'Kimyasal tepkimelerin gerçekleşme şartlarını açıklamak için kanıt kullanabilme', 5, 'TYMM 2026 Kimya Öğretim Programı, s.61', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000001', NULL, 'KIM.11.1.6', 'Tepkime hızının zamanla değişimini bilimsel veriye dayalı tahmin edebilme', 6, 'TYMM 2026 Kimya Öğretim Programı, s.61', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000001', NULL, 'KIM.11.1.7', 'Tepkime hızına etki eden faktörleri bilimsel sorgulayabilme', 7, 'TYMM 2026 Kimya Öğretim Programı, s.62', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000001', NULL, 'KIM.11.1.8', 'Kimyasal tepkimelerin hız denklemini bilimsel veriye dayalı tahmin edebilme', 8, 'TYMM 2026 Kimya Öğretim Programı, s.62', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.1', 'Tepkimelerin tersinir olabileceğine ilişkin bilimsel gözlem yapabilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.70', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.2', 'Tepkimelerdeki denge sürecine ilişkin bilimsel gözleme dayalı tahminde bulunabilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.70', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.3', 'Denge sabiti ifadesinin oluşturulmasına ilişkin tümevarımsal akıl yürütebilme', 3, 'TYMM 2026 Kimya Öğretim Programı, s.70', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.4', 'Tersinir tepkimelerin dengeye ulaşıp ulaşmadığını bilimsel veriye dayalı tahmin edebilme', 4, 'TYMM 2026 Kimya Öğretim Programı, s.70', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.5', 'Dengeye etki eden faktörleri bilimsel sorgulayabilme', 5, 'TYMM 2026 Kimya Öğretim Programı, s.70', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.6', 'Saf suyun otoiyonizasyonuna ilişkin bilimsel gözlem yapabilme', 6, 'TYMM 2026 Kimya Öğretim Programı, s.70', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.7', 'Asit ve baz teorilerini karşılaştırabilme', 7, 'TYMM 2026 Kimya Öğretim Programı, s.70', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.8', 'Asitlerin ve bazların kuvvetlerine ilişkin bilimsel sorgulama yapabilme', 8, 'TYMM 2026 Kimya Öğretim Programı, s.70', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.9', 'Kuvvetli asit-zayıf asit ve kuvvetli baz-zayıf baz sulu çözeltilerindeki pH hesaplamalarını karşılaştırabilme', 9, 'TYMM 2026 Kimya Öğretim Programı, s.71', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.10', 'Nötralleşme olayını operasyonel tanımlayabilme', 10, 'TYMM 2026 Kimya Öğretim Programı, s.71', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.11', 'Kuvvetli asit ve kuvvetli baz çözeltilerinin derişimlerini titrasyon yöntemiyle belirlemeye yönelik deney yapabilme', 11, 'TYMM 2026 Kimya Öğretim Programı, s.71', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.12', 'Asidik ya da bazik ürünlerin en uygun olanına karar verebilme', 12, 'TYMM 2026 Kimya Öğretim Programı, s.71', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000021', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.13', 'Suda az çözünen tuzların çözünürlüğüne ilişkin bilimsel model oluşturabilme', 13, 'TYMM 2026 Kimya Öğretim Programı, s.71', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000022', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000002', NULL, 'KIM.11.2.14', 'Suda az çözünen tuzların çözünürlüğüne etki eden faktörlere ilişkin bilimsel çıkarım yapabilme', 14, 'TYMM 2026 Kimya Öğretim Programı, s.71', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000023', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000003', NULL, 'KIM.11.3.1', 'Evsel atıklardan fermantasyon yöntemi ile yeşil hidrojen enerjisi elde etme sürecine yönelik hipotez oluşturabilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.80', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000024', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000003', NULL, 'KIM.11.3.2', 'Nanoteknolojik ürünlerin seçimine yönelik eleştirel düşünebilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.80', true, now(), now()),
  ('b3110000-0000-4000-8000-000000000025', 'a1000000-0000-4000-8000-0000000000c4', 11, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1110000-0000-4000-8000-000000000003', NULL, 'KIM.11.3.3', 'Mikroplastik ve nanoplastiklerin etkilerini sorgulayabilme', 3, 'TYMM 2026 Kimya Öğretim Programı, s.80', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000001', NULL, 'KIM.12.1.1', 'İndirgenme-yükseltgenme (redoks) tepkime sürecine ilişkin bilimsel gözlem yapabilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.86', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000001', NULL, 'KIM.12.1.2', 'Metallerin aktiflik sıralamasını belirlemeye ilişkin bilimsel sorgulama yapabilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.86', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000001', NULL, 'KIM.12.1.3', 'Galvanik bir hücrenin özelliklerini bilimsel gözleme dayalı tahmin edebilme', 3, 'TYMM 2026 Kimya Öğretim Programı, s.86', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000001', NULL, 'KIM.12.1.4', 'Standart hücre potansiyelinin hesaplanmasına ilişkin tümevarımsal akıl yürütebilme', 4, 'TYMM 2026 Kimya Öğretim Programı, s.86', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000001', NULL, 'KIM.12.1.5', 'Galvanik hücrelerin potansiyelini etkileyen faktörlere ilişkin hipotez oluşturabilme', 5, 'TYMM 2026 Kimya Öğretim Programı, s.86', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000001', NULL, 'KIM.12.1.6', 'Elektrolitik bir hücrenin özelliklerini bilimsel gözlemlere dayalı tahmin edebilme', 6, 'TYMM 2026 Kimya Öğretim Programı, s.87', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000001', NULL, 'KIM.12.1.7', 'Elektroliz olayında madde-elektrik akımı miktarı ilişkisini açıklayabilmek için kanıt kullanabilme', 7, 'TYMM 2026 Kimya Öğretim Programı, s.87', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000001', NULL, 'KIM.12.1.8', 'Metallerin elektrolizle kaplanmasına yönelik deney yapabilme', 8, 'TYMM 2026 Kimya Öğretim Programı, s.87', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000001', NULL, 'KIM.12.1.9', 'Korozyonu önlemeye yönelik bilimsel sorgulama yapabilme', 9, 'TYMM 2026 Kimya Öğretim Programı, s.87', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.1', 'Molekülleri oluşturan atomlar arasındaki sigma ve pi bağlarını açıklamak için kanıt kullanabilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.96', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.2', 'Hibrit orbitallerinin oluşumunu açıklamak için kanıt kullanabilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.96', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.3', 'Moleküllerin geometrisinin belirlenmesine ilişkin çıkarımda bulunabilme', 3, 'TYMM 2026 Kimya Öğretim Programı, s.96', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.4', 'Organik bileşiklerin gösterimi için kullanılan farklı formüllere ilişkin tümevarımsal akıl yürütebilme', 4, 'TYMM 2026 Kimya Öğretim Programı, s.96', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.5', 'Hidrokarbonları sınıflandırabilme', 5, 'TYMM 2026 Kimya Öğretim Programı, s.96', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.6', 'Alifatik hidrokarbonların sistematik adlandırılmasına ilişkin tümevarımsal akıl yürütebilme', 6, 'TYMM 2026 Kimya Öğretim Programı, s.96', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.7', 'Alifatik hidrokarbonların izomerliklerini sınıflandırabilme', 7, 'TYMM 2026 Kimya Öğretim Programı, s.96', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.8', 'Alifatik hidrokarbonların fiziksel ve kimyasal özelliklerini karşılaştırabilme', 8, 'TYMM 2026 Kimya Öğretim Programı, s.97', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.9', 'Organik bileşikleri fonksiyonel grubuna göre sınıflandırabilme', 9, 'TYMM 2026 Kimya Öğretim Programı, s.97', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.10', 'Fonksiyonel gruba sahip organik bileşiklerin sistematik adlandırılma kurallarına ilişkin tümdengelimsel akıl yürütebilme', 10, 'TYMM 2026 Kimya Öğretim Programı, s.97', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.11', 'Fonksiyonel grup izomeri olan organik bileşiklerin bilimsel modelini oluşturabilme', 11, 'TYMM 2026 Kimya Öğretim Programı, s.97', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000021', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000002', NULL, 'KIM.12.2.12', 'Karbon temelli enerji kaynaklarının yanma tepkimelerinin sonuçlarına ilişkin çıkarım yapabilme', 12, 'TYMM 2026 Kimya Öğretim Programı, s.97', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000022', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000003', NULL, 'KIM.12.3.1', 'Boyaya duyarlı güneş pillerinin verimliliklerine ilişkin bilimsel çıkarım yapabilme', 1, 'TYMM 2026 Kimya Öğretim Programı, s.107', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000023', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000003', NULL, 'KIM.12.3.2', 'Biyobozunur polimer eldesinde kullanılacak bileşenlere karar verebilme', 2, 'TYMM 2026 Kimya Öğretim Programı, s.107', true, now(), now()),
  ('b3120000-0000-4000-8000-000000000024', 'a1000000-0000-4000-8000-0000000000c4', 12, '6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'b1120000-0000-4000-8000-000000000003', NULL, 'KIM.12.3.3', 'Yapay zekâ uygulamalarının sürdürülebilirliğe etkilerine yönelik eleştirel düşünebilme', 3, 'TYMM 2026 Kimya Öğretim Programı, s.107', true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 4. MIGRATION HISTORY — idempotent kayıt (psql koşumunda statements=NULL;
--    CLI koşan ortamda CLI'ın kendi kaydı varsa bu INSERT atlanır).
-- ============================================================
insert into supabase_migrations.schema_migrations (version, name, statements)
select '143', '143_curriculum_kimya_tymm2026_agac', NULL
 where not exists (
   select 1 from supabase_migrations.schema_migrations where version = '143'
 );

-- ============================================================
-- 5. SON DENETİM (transaction içi; beklentiden sapan durum COMMIT'i durdurur)
-- ============================================================
DO $final$
DECLARE
  v_t integer; v_s integer; v_o integer; v_null_t integer; v_null_s integer; v_linked integer;
BEGIN
  SELECT count(*) INTO v_t FROM public.topics WHERE subject_id = '6dbbbd2f-14d5-47aa-aef0-609a5e339b12';
  SELECT count(*) INTO v_s FROM public.subtopics s JOIN public.topics t ON t.id = s.topic_id
   WHERE t.subject_id = '6dbbbd2f-14d5-47aa-aef0-609a5e339b12';
  SELECT count(*),
         count(*) FILTER (WHERE topic_id IS NULL),
         count(*) FILTER (WHERE subtopic_id IS NULL),
         count(*) FILTER (WHERE topic_id IS NOT NULL)
    INTO v_o, v_null_t, v_null_s, v_linked
    FROM public.curriculum_outcomes WHERE outcome_code LIKE 'KIM.%';
  IF v_t <> 12 OR v_s <> 92 OR v_o <> 93 OR v_null_t <> 0 OR v_null_s <> 93 OR v_linked <> 93 THEN
    RAISE EXCEPTION 'FINAL_143: beklenen 12/92/93 (topic/subtopic/outcome), topic-bağlı=93, NULL subtopic=93; bulunan %/%/%/%/%/%', v_t, v_s, v_o, v_linked, v_null_s, v_null_t;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.curriculum_versions
                 WHERE id = 'a1000000-0000-4000-8000-0000000000c4' AND framework = 'tymm_2026_kimya') THEN
    RAISE EXCEPTION 'FINAL_143: sürüm satırı (a1000000-0000-4000-8000-0000000000c4) yok — beklenmeyen durum.';
  END IF;
END
$final$;

COMMIT;
