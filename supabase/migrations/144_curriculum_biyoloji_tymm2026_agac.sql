-- ============================================================
-- 144_curriculum_biyoloji_tymm2026_agac.sql
-- Altın Kalemler — CURRICULUM-ALL-01 Biyoloji dilimi: TYMM 2026 Biyoloji
--   müfredat ağacının (8 tema + 89 İçerik Çerçevesi maddesi + 75 yeni outcome)
--   YÜKLENMESİ ve tymm_2026_biyoloji curriculum_versions satırının OLUŞTURULMASI.
--
-- KULLANICI ONAYLI KAPSAM (2026-10-27)
--   - 1 sürüm + 8 topic + 89 subtopic + 75 outcome YÜKLENİR (9. sınıf: 2 tema + 17 madde + 14 çıktı; 10. sınıf: 2 tema + 19 madde + 19 çıktı; 11. sınıf: 2 tema + 28 madde + 22 çıktı; 12. sınıf: 2 tema + 25 madde + 20 çıktı).
--   - Biyoloji için DB'de ÖNCEDEN BIY.* outcome / topic / subtopic YOKTUR
--     (2026-10-27 salt-okunur ölçüm; dry-run eşleşen=0). Bu yüzden bölüm 4'teki
--     gibi "mevcut kayıt linkleme UPDATE'i" YOKTUR — migration salt EKLEME yapar.
--
-- KAYNAK (yalnız resmî)
--   Türkiye Yüzyılı Maarif Modeli — Ortaöğretim Biyoloji Dersi (9, 10, 11 ve
--   12. Sınıflar) Öğretim Programı (2026); PDF basılı sayfa numaraları.
--   Yerel: docs/references/mufredat/2026-2027/tymm-2026-biyoloji-9-12.pdf
--   Ağaç:  docs/question-production/curriculum-mapping/biyoloji-9-12-kanonik-esleme-v1.md
--   Dry-run: scripts/mufredat-dry-run.ts --ders=biyoloji → biyoloji-dry-run-sonuc.md
--   (172/172 veri satırı, 8/89/75, eşleşen 0, metin farkı 0, engelli 0)
--
-- UUID ŞEMASI (142 deseni; aileler DB envanteriyle çakışmasız seçildi)
--   Mevcut deterministik aileler: a1=versions, a2=schedule_profiles, a3=MAT topics,
--   a4=schedule_items, a5=FIZ topics, a6=MAT subtopics, a7=MAT outcomes,
--   a8=FIZ subtopics, a9=FIZ outcomes. YENİ AİLELER (topics/subtopics/outcomes
--   tablolarında envanterle boş doğrulandı — information_schema + hedef tablo taraması):
--   Biyoloji topic    : b4 + GG (sınıf) → b4GG0000-0000-4000-8000-0000000000NN
--   Biyoloji subtopic : b5 + GG (sınıf) → b5GG0000-0000-4000-8000-0000000000NN
--   Biyoloji outcome : b6 + GG (sınıf) → b6GG0000-0000-4000-8000-0000000000NN
--     (NN = sınıf içi (tema, k) sıralamasında kesintisiz sayaç, 001'den başlar)
--   Sürüm id: a1000000-0000-4000-8000-0000000000c5 (tymm_2026_biyoloji; a1 ailesinde c1/c2/c3'ten sonraki ilk boş değer).
--   Subject id: 71191e01-220a-4682-9351-3d62631308d2 (Biyoloji, migration 045).
--
-- AD / SLUG / SIRA KARARLARI (142 birebir)
--   - topic.name: 'BIY.9.1 <TEMA ADI>' deseni; tema adı PDF'teki resmî
--     büyük harfli başlıktır ('N. TEMA: ' öneki atılır).
--   - topic.slug : biyoloji-GG-N-<tema-adı-slug>  (dry-run öneri formülüyle aynı).
--     DB kısıtı: UNIQUE (curriculum_version_id, subject_id, grade_level, slug).
--   - subtopic.name: İçerik Çerçevesi kutusundaki basılı madde (resmî).
--   - subtopic.slug: <topic-slug>-<madde-slug> (112 matematik deseni; UNIQUE (topic_id, slug)).
--   - subtopic.sort_order: sınıf içi kesintisiz (kutu sırası; tema değişince sıfırlanmaz).
--   - outcome.sort_order: kodun son basamağı k (tema-içi sıra) — 125/142 sözleşmesi.
--   - outcome.subtopic_id: NULL (kaynakta çıktı→alt konu ilişkisi numaralandırılmamıştır;
--     yakınlık/sıra/isim benzerliğiyle atama YASAKTIR — kanonik dosya §2, BLOKAJ-1 kuralı).
--   - source_reference: 'TYMM 2026 Biyoloji Öğretim Programı, s.NN' (125/142 deseni); NN = kazanım bloğunun
--     basılı sayfası (kanonik dosya §4/§5).
--
-- SÜRÜM SATIRI (125 fizik deseninden fark)
--   Fizik sürümü 125'te ayrı kurulmuştu; bu ders için curriculum_versions satırı YOKTU
--   (dry-run: 'BULUNAMADI'). Sürüm INSERT'i bölüm 0.5'tedir: is_default=false
--   (yıl-tek-default kısmi indeksi bozulmaz), UNIQUE (academic_year, framework) uyumlu.
--
-- İDEMPOTENCE
--   - Tüm INSERT'ler ON CONFLICT (id) DO NOTHING → tekrar koşum SIFIR yeni satır.
--   - GUARD: ağaç ya (0,0,0) (ilk uygulama) ya (8/89/75) dolu hâlde
--     olmalı; karışık/kısmi durum fail-closed durur. Dolu hâlde tüm id'ler tanınır.
--   - outcome_code'da UNIQUE KISIT YOKTUR (yalnız idx_curriculum_outcomes_code normal
--     indeks); mükerrer kod riski GUARD'ın benzersiz-kod denetimi + deterministik id ile
--     kapanır (142'nin iki katmanlı koruması).
--   - History: supabase_migrations.schema_migrations'a version='144' kaydı WHERE NOT
--     EXISTS ile idempotent eklenir; statements=NULL (psql koşumunda dosya kendi metnini
--     içine koyamaz; CLI uygulayan ortamda CLI statements'i doldurur — 142 notu birebir).
--
-- GERİ DÖNÜŞ: scripts/biyoloji-mufredat-geri-donus.sql (tek transaction;
--   75 outcome DELETE → 89 subtopic DELETE → 8 topic DELETE → sürüm satırı DELETE →
--   144 history DELETE; FK sırası korunur, fail-closed üçüncü-taraf referans taraması
--   içerir). Uygulama öncesi yedek (boş ön-durum kanıtı):
--   docs/references/mufredat/yedekler/biyoloji-on-yedek-20261027.sql
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
  IF NOT EXISTS (SELECT 1 FROM public.subjects WHERE id = '71191e01-220a-4682-9351-3d62631308d2') THEN
    RAISE EXCEPTION 'GUARD_144: Biyoloji subject satırı yok — migration 045 uygulanmamış ortam.';
  END IF;

  -- Sürüm satırı: ya hiç yok (ilk uygulama) ya da TAM bu çift var (tekrar koşum).
  SELECT count(*) INTO v_surum FROM public.curriculum_versions
   WHERE framework = 'tymm_2026_biyoloji' OR id = 'a1000000-0000-4000-8000-0000000000c5';
  IF v_surum > 0 THEN
    IF NOT EXISTS (SELECT 1 FROM public.curriculum_versions
                   WHERE id = 'a1000000-0000-4000-8000-0000000000c5' AND framework = 'tymm_2026_biyoloji'
                     AND academic_year = '2026-2027' AND is_default = false) THEN
      RAISE EXCEPTION 'GUARD_144: tymm_2026_biyoloji/a1000000-0000-4000-8000-0000000000c5 sürüm satırı çelişkili (farklı id/framework/is_default) — fail-closed dur.';
    END IF;
  END IF;

  -- Ağaç durumu: ya boş ya tam dolu. Kısmi/yabancı durum fail-closed.
  SELECT count(*) INTO v_topic_sayi FROM public.topics
   WHERE subject_id = '71191e01-220a-4682-9351-3d62631308d2';
  SELECT count(*) INTO v_subtopic_sayi FROM public.subtopics s
   JOIN public.topics t ON t.id = s.topic_id
   WHERE t.subject_id = '71191e01-220a-4682-9351-3d62631308d2';
  SELECT count(*) INTO v_outcome_sayi FROM public.curriculum_outcomes
   WHERE outcome_code LIKE 'BIY.%';
  IF NOT (v_topic_sayi = 0 AND v_subtopic_sayi = 0 AND v_outcome_sayi = 0)
     AND NOT (v_topic_sayi = 8 AND v_subtopic_sayi = 89 AND v_outcome_sayi = 75) THEN
    RAISE EXCEPTION 'GUARD_144: Biyoloji ağacı kısmi/yabancı durumda (topics=%, subtopics=%, outcomes=%; beklenen 0/0/0 veya 8/89/75) — fail-closed dur.', v_topic_sayi, v_subtopic_sayi, v_outcome_sayi;
  END IF;

  -- Dolu hâl: id'lerin tamamı bu migration'ın deterministik kümesinden mi?
  IF v_topic_sayi = 8 THEN
    SELECT count(*) INTO v_yabanci FROM public.topics
     WHERE subject_id = '71191e01-220a-4682-9351-3d62631308d2' AND id NOT IN (
      'b4090000-0000-4000-8000-000000000001',
      'b4090000-0000-4000-8000-000000000002',
      'b4100000-0000-4000-8000-000000000001',
      'b4100000-0000-4000-8000-000000000002',
      'b4110000-0000-4000-8000-000000000001',
      'b4110000-0000-4000-8000-000000000002',
      'b4120000-0000-4000-8000-000000000001',
      'b4120000-0000-4000-8000-000000000002'
    );
    IF v_yabanci > 0 THEN
      RAISE EXCEPTION 'GUARD_144: % yabancı Biyoloji topic id''si bulundu — fail-closed dur.', v_yabanci;
    END IF;
    SELECT count(*) INTO v_yabanci FROM public.subtopics s
     JOIN public.topics t ON t.id = s.topic_id
     WHERE t.subject_id = '71191e01-220a-4682-9351-3d62631308d2' AND s.id NOT IN (
      'b5090000-0000-4000-8000-000000000001',
      'b5090000-0000-4000-8000-000000000002',
      'b5090000-0000-4000-8000-000000000003',
      'b5090000-0000-4000-8000-000000000004',
      'b5090000-0000-4000-8000-000000000005',
      'b5090000-0000-4000-8000-000000000006',
      'b5090000-0000-4000-8000-000000000007',
      'b5090000-0000-4000-8000-000000000008',
      'b5090000-0000-4000-8000-000000000009',
      'b5090000-0000-4000-8000-000000000010',
      'b5090000-0000-4000-8000-000000000011',
      'b5090000-0000-4000-8000-000000000012',
      'b5090000-0000-4000-8000-000000000013',
      'b5090000-0000-4000-8000-000000000014',
      'b5090000-0000-4000-8000-000000000015',
      'b5090000-0000-4000-8000-000000000016',
      'b5090000-0000-4000-8000-000000000017',
      'b5100000-0000-4000-8000-000000000001',
      'b5100000-0000-4000-8000-000000000002',
      'b5100000-0000-4000-8000-000000000003',
      'b5100000-0000-4000-8000-000000000004',
      'b5100000-0000-4000-8000-000000000005',
      'b5100000-0000-4000-8000-000000000006',
      'b5100000-0000-4000-8000-000000000007',
      'b5100000-0000-4000-8000-000000000008',
      'b5100000-0000-4000-8000-000000000009',
      'b5100000-0000-4000-8000-000000000010',
      'b5100000-0000-4000-8000-000000000011',
      'b5100000-0000-4000-8000-000000000012',
      'b5100000-0000-4000-8000-000000000013',
      'b5100000-0000-4000-8000-000000000014',
      'b5100000-0000-4000-8000-000000000015',
      'b5100000-0000-4000-8000-000000000016',
      'b5100000-0000-4000-8000-000000000017',
      'b5100000-0000-4000-8000-000000000018',
      'b5100000-0000-4000-8000-000000000019',
      'b5110000-0000-4000-8000-000000000001',
      'b5110000-0000-4000-8000-000000000002',
      'b5110000-0000-4000-8000-000000000003',
      'b5110000-0000-4000-8000-000000000004',
      'b5110000-0000-4000-8000-000000000005',
      'b5110000-0000-4000-8000-000000000006',
      'b5110000-0000-4000-8000-000000000007',
      'b5110000-0000-4000-8000-000000000008',
      'b5110000-0000-4000-8000-000000000009',
      'b5110000-0000-4000-8000-000000000010',
      'b5110000-0000-4000-8000-000000000011',
      'b5110000-0000-4000-8000-000000000012',
      'b5110000-0000-4000-8000-000000000013',
      'b5110000-0000-4000-8000-000000000014',
      'b5110000-0000-4000-8000-000000000015',
      'b5110000-0000-4000-8000-000000000016',
      'b5110000-0000-4000-8000-000000000017',
      'b5110000-0000-4000-8000-000000000018',
      'b5110000-0000-4000-8000-000000000019',
      'b5110000-0000-4000-8000-000000000020',
      'b5110000-0000-4000-8000-000000000021',
      'b5110000-0000-4000-8000-000000000022',
      'b5110000-0000-4000-8000-000000000023',
      'b5110000-0000-4000-8000-000000000024',
      'b5110000-0000-4000-8000-000000000025',
      'b5110000-0000-4000-8000-000000000026',
      'b5110000-0000-4000-8000-000000000027',
      'b5110000-0000-4000-8000-000000000028',
      'b5120000-0000-4000-8000-000000000001',
      'b5120000-0000-4000-8000-000000000002',
      'b5120000-0000-4000-8000-000000000003',
      'b5120000-0000-4000-8000-000000000004',
      'b5120000-0000-4000-8000-000000000005',
      'b5120000-0000-4000-8000-000000000006',
      'b5120000-0000-4000-8000-000000000007',
      'b5120000-0000-4000-8000-000000000008',
      'b5120000-0000-4000-8000-000000000009',
      'b5120000-0000-4000-8000-000000000010',
      'b5120000-0000-4000-8000-000000000011',
      'b5120000-0000-4000-8000-000000000012',
      'b5120000-0000-4000-8000-000000000013',
      'b5120000-0000-4000-8000-000000000014',
      'b5120000-0000-4000-8000-000000000015',
      'b5120000-0000-4000-8000-000000000016',
      'b5120000-0000-4000-8000-000000000017',
      'b5120000-0000-4000-8000-000000000018',
      'b5120000-0000-4000-8000-000000000019',
      'b5120000-0000-4000-8000-000000000020',
      'b5120000-0000-4000-8000-000000000021',
      'b5120000-0000-4000-8000-000000000022',
      'b5120000-0000-4000-8000-000000000023',
      'b5120000-0000-4000-8000-000000000024',
      'b5120000-0000-4000-8000-000000000025'
    );
    IF v_yabanci > 0 THEN
      RAISE EXCEPTION 'GUARD_144: % yabancı Biyoloji subtopic id''si bulundu — fail-closed dur.', v_yabanci;
    END IF;
    SELECT count(*), count(*) FILTER (WHERE id IN (
      'b6090000-0000-4000-8000-000000000001', 'b6090000-0000-4000-8000-000000000002', 'b6090000-0000-4000-8000-000000000003', 'b6090000-0000-4000-8000-000000000004', 'b6090000-0000-4000-8000-000000000005', 'b6090000-0000-4000-8000-000000000006', 'b6090000-0000-4000-8000-000000000007', 'b6090000-0000-4000-8000-000000000008', 'b6090000-0000-4000-8000-000000000009', 'b6090000-0000-4000-8000-000000000010', 'b6090000-0000-4000-8000-000000000011', 'b6090000-0000-4000-8000-000000000012', 'b6090000-0000-4000-8000-000000000013', 'b6090000-0000-4000-8000-000000000014', 'b6100000-0000-4000-8000-000000000001', 'b6100000-0000-4000-8000-000000000002', 'b6100000-0000-4000-8000-000000000003', 'b6100000-0000-4000-8000-000000000004', 'b6100000-0000-4000-8000-000000000005', 'b6100000-0000-4000-8000-000000000006', 'b6100000-0000-4000-8000-000000000007', 'b6100000-0000-4000-8000-000000000008', 'b6100000-0000-4000-8000-000000000009', 'b6100000-0000-4000-8000-000000000010', 'b6100000-0000-4000-8000-000000000011', 'b6100000-0000-4000-8000-000000000012', 'b6100000-0000-4000-8000-000000000013', 'b6100000-0000-4000-8000-000000000014', 'b6100000-0000-4000-8000-000000000015', 'b6100000-0000-4000-8000-000000000016', 'b6100000-0000-4000-8000-000000000017', 'b6100000-0000-4000-8000-000000000018', 'b6100000-0000-4000-8000-000000000019', 'b6110000-0000-4000-8000-000000000001', 'b6110000-0000-4000-8000-000000000002', 'b6110000-0000-4000-8000-000000000003', 'b6110000-0000-4000-8000-000000000004', 'b6110000-0000-4000-8000-000000000005', 'b6110000-0000-4000-8000-000000000006', 'b6110000-0000-4000-8000-000000000007', 'b6110000-0000-4000-8000-000000000008', 'b6110000-0000-4000-8000-000000000009', 'b6110000-0000-4000-8000-000000000010', 'b6110000-0000-4000-8000-000000000011', 'b6110000-0000-4000-8000-000000000012', 'b6110000-0000-4000-8000-000000000013', 'b6110000-0000-4000-8000-000000000014', 'b6110000-0000-4000-8000-000000000015', 'b6110000-0000-4000-8000-000000000016', 'b6110000-0000-4000-8000-000000000017', 'b6110000-0000-4000-8000-000000000018', 'b6110000-0000-4000-8000-000000000019', 'b6110000-0000-4000-8000-000000000020', 'b6110000-0000-4000-8000-000000000021', 'b6110000-0000-4000-8000-000000000022', 'b6120000-0000-4000-8000-000000000001', 'b6120000-0000-4000-8000-000000000002', 'b6120000-0000-4000-8000-000000000003', 'b6120000-0000-4000-8000-000000000004', 'b6120000-0000-4000-8000-000000000005', 'b6120000-0000-4000-8000-000000000006', 'b6120000-0000-4000-8000-000000000007', 'b6120000-0000-4000-8000-000000000008', 'b6120000-0000-4000-8000-000000000009', 'b6120000-0000-4000-8000-000000000010', 'b6120000-0000-4000-8000-000000000011', 'b6120000-0000-4000-8000-000000000012', 'b6120000-0000-4000-8000-000000000013', 'b6120000-0000-4000-8000-000000000014', 'b6120000-0000-4000-8000-000000000015', 'b6120000-0000-4000-8000-000000000016', 'b6120000-0000-4000-8000-000000000017', 'b6120000-0000-4000-8000-000000000018', 'b6120000-0000-4000-8000-000000000019', 'b6120000-0000-4000-8000-000000000020'
    )), count(DISTINCT outcome_code) INTO v_outcome_sayi, v_tanimli, v_benzersiz
      FROM public.curriculum_outcomes WHERE outcome_code LIKE 'BIY.%';
    IF v_outcome_sayi <> 75 OR v_tanimli <> 75 OR v_benzersiz <> 75 THEN
      RAISE EXCEPTION 'GUARD_144: BIY.* outcomes=% (tanınan id=%, benzersiz kod=%; beklenen 75/75/75) — id/kod drifti, fail-closed dur.', v_outcome_sayi, v_tanimli, v_benzersiz;
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
  'a1000000-0000-4000-8000-0000000000c5',
  '2026-2027',
  'tymm_2026_biyoloji',
  'Türkiye Yüzyılı Maarif Modeli Biyoloji Dersi (9, 10, 11 ve 12. Sınıflar) Öğretim Programı (2026)',
  'https://mufredat.meb.gov.tr/Dosyalar/202651815105221-biyolojid%C3%B6p.pdf',
  '2026-05-18',  -- mufredat.meb.gov.tr resmî URL zaman damgasından (125 fizik kararıyla aynı yöntem)
  true, false, now(), now()
)
on conflict (id) do nothing;

-- ============================================================
-- 1. TOPICS (8) — BIY.GG.N <TEMA ADI>; sort_order = resmî tema no (sınıf içi)
--    UNIQUE (curriculum_version_id, subject_id, grade_level, slug) koruması:
--    farklı id ile aynı slug varsa INSERT doğal olarak HATA verir (fail-closed).
-- ============================================================
insert into public.topics (
  id, subject_id, grade_level, name, slug, sort_order,
  is_active, curriculum_version_id, created_at, updated_at
) values
  ('b4090000-0000-4000-8000-000000000001', '71191e01-220a-4682-9351-3d62631308d2', 9, 'BIY.9.1 YAŞAM', 'biyoloji-9-1-yasam', 1, true, 'a1000000-0000-4000-8000-0000000000c5', now(), now()),
  ('b4090000-0000-4000-8000-000000000002', '71191e01-220a-4682-9351-3d62631308d2', 9, 'BIY.9.2 ORGANİZASYON', 'biyoloji-9-2-organizasyon', 2, true, 'a1000000-0000-4000-8000-0000000000c5', now(), now()),
  ('b4100000-0000-4000-8000-000000000001', '71191e01-220a-4682-9351-3d62631308d2', 10, 'BIY.10.1 ENERJİ', 'biyoloji-10-1-enerji', 1, true, 'a1000000-0000-4000-8000-0000000000c5', now(), now()),
  ('b4100000-0000-4000-8000-000000000002', '71191e01-220a-4682-9351-3d62631308d2', 10, 'BIY.10.2 EKOLOJİ', 'biyoloji-10-2-ekoloji', 2, true, 'a1000000-0000-4000-8000-0000000000c5', now(), now()),
  ('b4110000-0000-4000-8000-000000000001', '71191e01-220a-4682-9351-3d62631308d2', 11, 'BIY.11.1 TEPKİ', 'biyoloji-11-1-tepki', 1, true, 'a1000000-0000-4000-8000-0000000000c5', now(), now()),
  ('b4110000-0000-4000-8000-000000000002', '71191e01-220a-4682-9351-3d62631308d2', 11, 'BIY.11.2 HOMEOSTAZİ', 'biyoloji-11-2-homeostazi', 2, true, 'a1000000-0000-4000-8000-0000000000c5', now(), now()),
  ('b4120000-0000-4000-8000-000000000001', '71191e01-220a-4682-9351-3d62631308d2', 12, 'BIY.12.1 ÜREME', 'biyoloji-12-1-ureme', 1, true, 'a1000000-0000-4000-8000-0000000000c5', now(), now()),
  ('b4120000-0000-4000-8000-000000000002', '71191e01-220a-4682-9351-3d62631308d2', 12, 'BIY.12.2 GEN', 'biyoloji-12-2-gen', 2, true, 'a1000000-0000-4000-8000-0000000000c5', now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 2. SUBTOPICS (89) — İçerik Çerçevesi maddeleri (resmî, basılı sıra);
--    sort_order sınıf içi kesintisiz (9: 1..17, 10: 1..19, 11: 1..28, 12: 1..25);
--    subtopic_id bağlantısı çıktılara AÇILMAZ (kaynak numaralandırmamış).
-- ============================================================
insert into public.subtopics (
  id, topic_id, name, slug, sort_order, is_active, created_at, updated_at
) values
  ('b5090000-0000-4000-8000-000000000001', 'b4090000-0000-4000-8000-000000000001', 'Biyolojinin Önemi', 'biyoloji-9-1-yasam-biyolojinin-onemi', 1, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000002', 'b4090000-0000-4000-8000-000000000001', 'Biyoloji Biliminin Gelişimindeki Dönüm Noktaları', 'biyoloji-9-1-yasam-biyoloji-biliminin-gelisimindeki-donum-noktalari', 2, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000003', 'b4090000-0000-4000-8000-000000000001', 'Bilimin Doğası', 'biyoloji-9-1-yasam-bilimin-dogasi', 3, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000004', 'b4090000-0000-4000-8000-000000000001', 'Bilimsel Araştırma Süreçleri', 'biyoloji-9-1-yasam-bilimsel-arastirma-surecleri', 4, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000005', 'b4090000-0000-4000-8000-000000000001', 'Bilim Etiği', 'biyoloji-9-1-yasam-bilim-etigi', 5, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000006', 'b4090000-0000-4000-8000-000000000001', 'Canlıların Ortak Özellikleri (Hücresel Yapı, Organizasyon, Beslenme, Enerji Üretimi ve Tüketimi, Boşaltım, Büyüme ve Gelişme, Metabolizma, Uyarılara Tepki, Homeostazi, Üreme, Varyasyon ve Adaptasyon)', 'biyoloji-9-1-yasam-canlilarin-ortak-ozellikleri-hucresel-yapi-organizasyon-beslenme-enerji-uretimi-ve-tuketimi-bosaltim-buyume-ve-gelisme-metabolizma-uyarilara-tepki-homeostazi-ureme-varyasyon-ve-adaptasyon', 6, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000007', 'b4090000-0000-4000-8000-000000000001', 'İnorganik Moleküller (Su, Mineraller)', 'biyoloji-9-1-yasam-inorganik-molekuller-su-mineraller', 7, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000008', 'b4090000-0000-4000-8000-000000000001', 'Organik Moleküller (Karbohidratlar [Monosakkaritler (Riboz, Deoksiriboz, Fruktoz, Glikoz, Galaktoz)], Disakkaritler (Sükroz, Maltoz, Laktoz), Polisakkaritler (Glikojen, Nişasta, Selüloz, Kitin), Lipitler (Yağ Asitleri, Trigliseritler, Fosfolipitler, Steroitler), Proteinler (Amino Asitlerin Yapısı, Enzimler (Basit ve Bileşik Enzimler, Aktivasyon Enerjisi, Enzim-Substrat İlişkisi, Enzimatik Reaksiyonlara Etki Eden Faktörler), Nükleik Asitler (DNA ve RNA’nın Yapısı), Vitaminler (Yağda Çözünen Vitaminler, Suda Çözünen Vitaminler))', 'biyoloji-9-1-yasam-organik-molekuller-karbohidratlar-monosakkaritler-riboz-deoksiriboz-fruktoz-glikoz-galaktoz-disakkaritler-sukroz-maltoz-laktoz-polisakkaritler-glikojen-nisasta-seluloz-kitin-lipitler-yag-asitleri-trigliseritler-fosfolipitler-steroitler-proteinler-amino-asitlerin-yapisi-enzimler-basit-ve-bilesik-enzimler-aktivasyon-enerjisi-enzim-substrat-iliskisi-enzimatik-reaksiyonlara-etki-eden-faktorler-nukleik-asitler-dna-ve-rnanin-yapisi-vitaminler-yagda-cozunen-vitaminler-suda-cozunen-vitaminler', 8, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000009', 'b4090000-0000-4000-8000-000000000002', 'Prokaryot ve Ökaryot Hücre', 'biyoloji-9-2-organizasyon-prokaryot-ve-okaryot-hucre', 9, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000010', 'b4090000-0000-4000-8000-000000000002', 'Hücre Zarı', 'biyoloji-9-2-organizasyon-hucre-zari', 10, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000011', 'b4090000-0000-4000-8000-000000000002', 'Sitoplazma', 'biyoloji-9-2-organizasyon-sitoplazma', 11, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000012', 'b4090000-0000-4000-8000-000000000002', 'Sitoplazmik Yapılar', 'biyoloji-9-2-organizasyon-sitoplazmik-yapilar', 12, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000013', 'b4090000-0000-4000-8000-000000000002', 'Organeller ve Çekirdek', 'biyoloji-9-2-organizasyon-organeller-ve-cekirdek', 13, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000014', 'b4090000-0000-4000-8000-000000000002', 'Hücre Zarından Madde Geçişleri (Pasif Taşıma, Basit Difüzyon, Kolaylaştırılmış Difüzyon, Ozmoz, Aktif Taşıma, Endositoz, Ekzositoz)', 'biyoloji-9-2-organizasyon-hucre-zarindan-madde-gecisleri-pasif-tasima-basit-difuzyon-kolaylastirilmis-difuzyon-ozmoz-aktif-tasima-endositoz-ekzositoz', 14, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000015', 'b4090000-0000-4000-8000-000000000002', 'Sınıflandırmada Temel Yaklaşımlar ve Modern Sınıflandırma (Linne ve İkili Adlandırma, Sınıflandırma Kategorileri)', 'biyoloji-9-2-organizasyon-siniflandirmada-temel-yaklasimlar-ve-modern-siniflandirma-linne-ve-ikili-adlandirma-siniflandirma-kategorileri', 15, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000016', 'b4090000-0000-4000-8000-000000000002', 'Üç Üst Âlem (Domain) Sisteminde Yer Alan Canlılar ve Genel Özellikleri [Bakteriler, Arkeler, Ökaryotlar (Protistler, Bitkiler, Mantarlar, Hayvanlar)]', 'biyoloji-9-2-organizasyon-uc-ust-alem-domain-sisteminde-yer-alan-canlilar-ve-genel-ozellikleri-bakteriler-arkeler-okaryotlar-protistler-bitkiler-mantarlar-hayvanlar', 16, true, now(), now()),
  ('b5090000-0000-4000-8000-000000000017', 'b4090000-0000-4000-8000-000000000002', 'Biyoçeşitlilik', 'biyoloji-9-2-organizasyon-biyocesitlilik', 17, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000001', 'b4100000-0000-4000-8000-000000000001', 'Canlılık İçin Enerjinin Önemi (ATP’nin Yapısı ve Enerji Aktarımında ATP’nin Rolü)', 'biyoloji-10-1-enerji-canlilik-icin-enerjinin-onemi-atpnin-yapisi-ve-enerji-aktariminda-atpnin-rolu', 1, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000002', 'b4100000-0000-4000-8000-000000000001', 'Işık Enerjisi Kullanılarak Besin Sentezi: Fotosentez (Işığın Kullanıldığı Tepkimeler, Işığın Kullanılmadığı Tepkimeler, Fotosentez Hızına Etki Eden Çevresel Faktörler)', 'biyoloji-10-1-enerji-isik-enerjisi-kullanilarak-besin-sentezi-fotosentez-isigin-kullanildigi-tepkimeler-isigin-kullanilmadigi-tepkimeler-fotosentez-hizina-etki-eden-cevresel-faktorler', 2, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000003', 'b4100000-0000-4000-8000-000000000001', 'Işık Enerjisi Kullanılmadan Besin Sentezi: Kemosentez', 'biyoloji-10-1-enerji-isik-enerjisi-kullanilmadan-besin-sentezi-kemosentez', 3, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000004', 'b4100000-0000-4000-8000-000000000001', 'Sindirim (Hücre İçi Sindirim ve Hücre Dışı Sindirim)', 'biyoloji-10-1-enerji-sindirim-hucre-ici-sindirim-ve-hucre-disi-sindirim', 4, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000005', 'b4100000-0000-4000-8000-000000000001', 'Canlılarda Sindirim Yapıları', 'biyoloji-10-1-enerji-canlilarda-sindirim-yapilari', 5, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000006', 'b4100000-0000-4000-8000-000000000001', 'İnsanda Sindirim, Emilim ve Taşınma', 'biyoloji-10-1-enerji-insanda-sindirim-emilim-ve-tasinma', 6, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000007', 'b4100000-0000-4000-8000-000000000001', 'Hücresel Solunum (Glikoliz, Sitrik Asit Döngüsü, Elektron Taşıma Sistemi)', 'biyoloji-10-1-enerji-hucresel-solunum-glikoliz-sitrik-asit-dongusu-elektron-tasima-sistemi', 7, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000008', 'b4100000-0000-4000-8000-000000000001', 'Besinlerin Solunuma Katılma Yolları', 'biyoloji-10-1-enerji-besinlerin-solunuma-katilma-yollari', 8, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000009', 'b4100000-0000-4000-8000-000000000001', 'Fermantasyon (Laktik Asit Fermantasyonu, Etil Alkol Fermantasyonu)', 'biyoloji-10-1-enerji-fermantasyon-laktik-asit-fermantasyonu-etil-alkol-fermantasyonu', 9, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000010', 'b4100000-0000-4000-8000-000000000001', 'Enerji-Metabolizma İlişkisi', 'biyoloji-10-1-enerji-enerji-metabolizma-iliskisi', 10, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000011', 'b4100000-0000-4000-8000-000000000002', 'Ekosistemin Bileşenleri (Cansız ve Canlı Bileşenler, Popülasyon, Komünite, Ekosistem)', 'biyoloji-10-2-ekoloji-ekosistemin-bilesenleri-cansiz-ve-canli-bilesenler-populasyon-komunite-ekosistem', 11, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000012', 'b4100000-0000-4000-8000-000000000002', 'Tür İçi ve Türler Arası Etkileşimler', 'biyoloji-10-2-ekoloji-tur-ici-ve-turler-arasi-etkilesimler', 12, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000013', 'b4100000-0000-4000-8000-000000000002', 'Süksesyon', 'biyoloji-10-2-ekoloji-suksesyon', 13, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000014', 'b4100000-0000-4000-8000-000000000002', 'Popülasyon Dinamikleri', 'biyoloji-10-2-ekoloji-populasyon-dinamikleri', 14, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000015', 'b4100000-0000-4000-8000-000000000002', 'Ekosistemde Madde ve Enerji Akışı (Besin Zinciri, Besin Ağı, Ekolojik Piramitler, Biyolojik Birikim ve Etkileri)', 'biyoloji-10-2-ekoloji-ekosistemde-madde-ve-enerji-akisi-besin-zinciri-besin-agi-ekolojik-piramitler-biyolojik-birikim-ve-etkileri', 15, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000016', 'b4100000-0000-4000-8000-000000000002', 'Madde Döngüleri (Su, Karbon, Azot Döngüsü)', 'biyoloji-10-2-ekoloji-madde-donguleri-su-karbon-azot-dongusu', 16, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000017', 'b4100000-0000-4000-8000-000000000002', 'Ekolojik Sürdürülebilirliğin Önemi', 'biyoloji-10-2-ekoloji-ekolojik-surdurulebilirligin-onemi', 17, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000018', 'b4100000-0000-4000-8000-000000000002', 'Ekolojik Sürdürülebilirliği Kısıtlayan/Engelleyen Durumlar (Habitat Kaybı/Parçalanması, Kirlilik ve Çevre Sorunları, Biyoçeşitlilik Kaybı)', 'biyoloji-10-2-ekoloji-ekolojik-surdurulebilirligi-kisitlayan-engelleyen-durumlar-habitat-kaybi-parcalanmasi-kirlilik-ve-cevre-sorunlari-biyocesitlilik-kaybi', 18, true, now(), now()),
  ('b5100000-0000-4000-8000-000000000019', 'b4100000-0000-4000-8000-000000000002', 'Ekolojik Sürdürülebilirliğin Sağlanması (Ekolojik Ayak İzinin Küçültülmesi, Doğal Kaynakların ve Biyoçeşitliliğin Korunması, Atık Yönetimi)', 'biyoloji-10-2-ekoloji-ekolojik-surdurulebilirligin-saglanmasi-ekolojik-ayak-izinin-kucultulmesi-dogal-kaynaklarin-ve-biyocesitliligin-korunmasi-atik-yonetimi', 19, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000001', 'b4110000-0000-4000-8000-000000000001', 'Farklı Canlıların Uyaranlara Karşı Oluşturduğu Tepkiler', 'biyoloji-11-1-tepki-farkli-canlilarin-uyaranlara-karsi-olusturdugu-tepkiler', 1, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000002', 'b4110000-0000-4000-8000-000000000001', 'Bitkisel Hormonlar', 'biyoloji-11-1-tepki-bitkisel-hormonlar', 2, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000003', 'b4110000-0000-4000-8000-000000000001', 'Bitkilerde Tepki Mekanizmaları (Tropizma, Nasti)', 'biyoloji-11-1-tepki-bitkilerde-tepki-mekanizmalari-tropizma-nasti', 3, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000004', 'b4110000-0000-4000-8000-000000000001', 'Uyartıların Alınması (Reseptörler, Uyaran Çeşitleri)', 'biyoloji-11-1-tepki-uyartilarin-alinmasi-reseptorler-uyaran-cesitleri', 4, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000005', 'b4110000-0000-4000-8000-000000000001', 'Nöronların Yapısı', 'biyoloji-11-1-tepki-noronlarin-yapisi', 5, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000006', 'b4110000-0000-4000-8000-000000000001', 'Nöronlarda Sinyal İletimi ve Sinaps', 'biyoloji-11-1-tepki-noronlarda-sinyal-iletimi-ve-sinaps', 6, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000007', 'b4110000-0000-4000-8000-000000000001', 'Duyu Organları', 'biyoloji-11-1-tepki-duyu-organlari', 7, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000008', 'b4110000-0000-4000-8000-000000000001', 'Uyarıların Yorumlanması', 'biyoloji-11-1-tepki-uyarilarin-yorumlanmasi', 8, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000009', 'b4110000-0000-4000-8000-000000000001', 'Hayvanlarda Sinir Sistemi Farklılıkları', 'biyoloji-11-1-tepki-hayvanlarda-sinir-sistemi-farkliliklari', 9, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000010', 'b4110000-0000-4000-8000-000000000001', 'İnsan Sinir Sisteminin Yapısı', 'biyoloji-11-1-tepki-insan-sinir-sisteminin-yapisi', 10, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000011', 'b4110000-0000-4000-8000-000000000001', 'Refleksler', 'biyoloji-11-1-tepki-refleksler', 11, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000012', 'b4110000-0000-4000-8000-000000000001', 'Kemik, Eklem ve Kasların Hareketteki Rolü', 'biyoloji-11-1-tepki-kemik-eklem-ve-kaslarin-hareketteki-rolu', 12, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000013', 'b4110000-0000-4000-8000-000000000001', 'Kemik ve Kasların Birlikte Çalışma İlişkisi', 'biyoloji-11-1-tepki-kemik-ve-kaslarin-birlikte-calisma-iliskisi', 13, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000014', 'b4110000-0000-4000-8000-000000000001', 'Kaslarda Kasılmanın Kontrolü', 'biyoloji-11-1-tepki-kaslarda-kasilmanin-kontrolu', 14, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000015', 'b4110000-0000-4000-8000-000000000001', 'Kasların Kasılma Mekanizması', 'biyoloji-11-1-tepki-kaslarin-kasilma-mekanizmasi', 15, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000016', 'b4110000-0000-4000-8000-000000000001', 'Doğal Bağışıklık', 'biyoloji-11-1-tepki-dogal-bagisiklik', 16, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000017', 'b4110000-0000-4000-8000-000000000001', 'Kazanılmış Bağışıklık (Aktif ve Pasif Bağışıklık)', 'biyoloji-11-1-tepki-kazanilmis-bagisiklik-aktif-ve-pasif-bagisiklik', 17, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000018', 'b4110000-0000-4000-8000-000000000001', 'Alerji', 'biyoloji-11-1-tepki-alerji', 18, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000019', 'b4110000-0000-4000-8000-000000000002', 'Farklı Canlı Türlerindeki Homeostatik Yapı ve Sistemler', 'biyoloji-11-2-homeostazi-farkli-canli-turlerindeki-homeostatik-yapi-ve-sistemler', 19, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000020', 'b4110000-0000-4000-8000-000000000002', 'Homeostatik Süreçler', 'biyoloji-11-2-homeostazi-homeostatik-surecler', 20, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000021', 'b4110000-0000-4000-8000-000000000002', 'Pozitif ve Negatif Geri Bildirim', 'biyoloji-11-2-homeostazi-pozitif-ve-negatif-geri-bildirim', 21, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000022', 'b4110000-0000-4000-8000-000000000002', 'Sinir Sistemi ve Homeostazi', 'biyoloji-11-2-homeostazi-sinir-sistemi-ve-homeostazi', 22, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000023', 'b4110000-0000-4000-8000-000000000002', 'Endokrin Sistem ve Homeostazi', 'biyoloji-11-2-homeostazi-endokrin-sistem-ve-homeostazi', 23, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000024', 'b4110000-0000-4000-8000-000000000002', 'Dolaşım Sistemi ve Homeostazi', 'biyoloji-11-2-homeostazi-dolasim-sistemi-ve-homeostazi', 24, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000025', 'b4110000-0000-4000-8000-000000000002', 'Solunum Sistemi ve Homeostazi', 'biyoloji-11-2-homeostazi-solunum-sistemi-ve-homeostazi', 25, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000026', 'b4110000-0000-4000-8000-000000000002', 'Boşaltım Sistemi ve Homeostazi', 'biyoloji-11-2-homeostazi-bosaltim-sistemi-ve-homeostazi', 26, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000027', 'b4110000-0000-4000-8000-000000000002', 'Sistemlerin Es Güdümlü Çalışması', 'biyoloji-11-2-homeostazi-sistemlerin-es-gudumlu-calismasi', 27, true, now(), now()),
  ('b5110000-0000-4000-8000-000000000028', 'b4110000-0000-4000-8000-000000000002', 'Homeostazinin Sağlanamadığı Durumlarda Oluşabilecek Sağlık Problemleri (Diabetes Mellitus, Diabetes İnsipidus, Kan Basıncı Anormallikleri, Obezite)', 'biyoloji-11-2-homeostazi-homeostazinin-saglanamadigi-durumlarda-olusabilecek-saglik-problemleri-diabetes-mellitus-diabetes-insipidus-kan-basinci-anormallikleri-obezite', 28, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000001', 'b4120000-0000-4000-8000-000000000001', 'Hücre Bölünmesinin Canlılar İçin Önemi', 'biyoloji-12-1-ureme-hucre-bolunmesinin-canlilar-icin-onemi', 1, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000002', 'b4120000-0000-4000-8000-000000000001', 'Kromozom Yapısı ve Özellikleri', 'biyoloji-12-1-ureme-kromozom-yapisi-ve-ozellikleri', 2, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000003', 'b4120000-0000-4000-8000-000000000001', 'Hücre Döngüsü (İnterfaz, Mitoz ve Sitokinez, Mayoz)', 'biyoloji-12-1-ureme-hucre-dongusu-interfaz-mitoz-ve-sitokinez-mayoz', 3, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000004', 'b4120000-0000-4000-8000-000000000001', 'Kromozomlarda Ayrılmama', 'biyoloji-12-1-ureme-kromozomlarda-ayrilmama', 4, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000005', 'b4120000-0000-4000-8000-000000000001', 'Eşeysiz Üreme (İkiye Bölünme, Tomurcuklanma, Sporla Üreme, Rejenerasyon, Partenogenez, Vejetatif Üreme)', 'biyoloji-12-1-ureme-eseysiz-ureme-ikiye-bolunme-tomurcuklanma-sporla-ureme-rejenerasyon-partenogenez-vejetatif-ureme', 5, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000006', 'b4120000-0000-4000-8000-000000000001', 'Eşeyli Üreme (Gametogenez, Döllenme)', 'biyoloji-12-1-ureme-eseyli-ureme-gametogenez-dollenme', 6, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000007', 'b4120000-0000-4000-8000-000000000001', 'Eşeysiz ve Eşeyli Üreme Arasındaki Farklar', 'biyoloji-12-1-ureme-eseysiz-ve-eseyli-ureme-arasindaki-farklar', 7, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000008', 'b4120000-0000-4000-8000-000000000001', 'İnsanda Üreme ve Gelişme (Dişi ve Erkek Üreme Sistemlerinin Yapısı, Menstrual Döngü, Döllenme, Kısırlık ve Tedavi Teknikleri, Embriyonik Gelişim)', 'biyoloji-12-1-ureme-insanda-ureme-ve-gelisme-disi-ve-erkek-ureme-sistemlerinin-yapisi-menstrual-dongu-dollenme-kisirlik-ve-tedavi-teknikleri-embriyonik-gelisim', 8, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000009', 'b4120000-0000-4000-8000-000000000001', 'Bitkilerde Eşeyli Üreme ve Gelişme (Çiçeğin Kısımları ve Görevleri, Çiçekli Bitkilerde Tozlaşma, Döllenme, Tohum ve Meyvenin Oluşumu, Çimlenme)', 'biyoloji-12-1-ureme-bitkilerde-eseyli-ureme-ve-gelisme-cicegin-kisimlari-ve-gorevleri-cicekli-bitkilerde-tozlasma-dollenme-tohum-ve-meyvenin-olusumu-cimlenme', 9, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000010', 'b4120000-0000-4000-8000-000000000002', 'Nükleik Asitlerin Canlılıktaki Rolü', 'biyoloji-12-2-gen-nukleik-asitlerin-canliliktaki-rolu', 10, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000011', 'b4120000-0000-4000-8000-000000000002', 'DNA ve RNA’nın Moleküler Yapısı', 'biyoloji-12-2-gen-dna-ve-rnanin-molekuler-yapisi', 11, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000012', 'b4120000-0000-4000-8000-000000000002', 'DNA Replikasyonu', 'biyoloji-12-2-gen-dna-replikasyonu', 12, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000013', 'b4120000-0000-4000-8000-000000000002', 'Gen İfadesi (Gen, Genetik Kod, Transkripsiyon, Translasyon)', 'biyoloji-12-2-gen-gen-ifadesi-gen-genetik-kod-transkripsiyon-translasyon', 13, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000014', 'b4120000-0000-4000-8000-000000000002', 'Genetik Yapıdaki Değişiklikler', 'biyoloji-12-2-gen-genetik-yapidaki-degisiklikler', 14, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000015', 'b4120000-0000-4000-8000-000000000002', 'Kalıtımın Temel İlkeleri (Monohibrit Çaprazlama, Dihibrit Çaprazlama, Kontrol (Geri) Çaprazlama)', 'biyoloji-12-2-gen-kalitimin-temel-ilkeleri-monohibrit-caprazlama-dihibrit-caprazlama-kontrol-geri-caprazlama', 15, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000016', 'b4120000-0000-4000-8000-000000000002', 'Mendel Kalıtımından Farklılıklar (Eş Baskınlık, Çok Alellilik)', 'biyoloji-12-2-gen-mendel-kalitimindan-farkliliklar-es-baskinlik-cok-alellilik', 16, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000017', 'b4120000-0000-4000-8000-000000000002', 'Eşeye Bağlı Kalıtım (Eşeyin Kromozomal Temeli, X Bağlı Kalıtım, Y Bağlı Kalıtım)', 'biyoloji-12-2-gen-eseye-bagli-kalitim-eseyin-kromozomal-temeli-x-bagli-kalitim-y-bagli-kalitim', 17, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000018', 'b4120000-0000-4000-8000-000000000002', 'Soyağacı Analizi', 'biyoloji-12-2-gen-soyagaci-analizi', 18, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000019', 'b4120000-0000-4000-8000-000000000002', 'Genetik Testler ve Genetik Danışmanlık', 'biyoloji-12-2-gen-genetik-testler-ve-genetik-danismanlik', 19, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000020', 'b4120000-0000-4000-8000-000000000002', 'Biyoteknolojinin Tıp Alanındaki Uygulamaları (İlaç Üretimi, Hücre Kültürü, Kök Hücre, Rekombinant Aşılar, Protein ve Hormon Üretimi)', 'biyoloji-12-2-gen-biyoteknolojinin-tip-alanindaki-uygulamalari-ilac-uretimi-hucre-kulturu-kok-hucre-rekombinant-asilar-protein-ve-hormon-uretimi', 20, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000021', 'b4120000-0000-4000-8000-000000000002', 'Biyoteknolojinin Tarım Alanındaki Uygulamaları', 'biyoloji-12-2-gen-biyoteknolojinin-tarim-alanindaki-uygulamalari', 21, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000022', 'b4120000-0000-4000-8000-000000000002', 'Bitki Doku Kültürü', 'biyoloji-12-2-gen-bitki-doku-kulturu', 22, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000023', 'b4120000-0000-4000-8000-000000000002', 'Ökaryotik Hücrelere Gen Aktarımı', 'biyoloji-12-2-gen-okaryotik-hucrelere-gen-aktarimi', 23, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000024', 'b4120000-0000-4000-8000-000000000002', 'Biyoteknolojinin Endüstri, Çevre ve Adli Tıp Alanlarındaki Uygulamaları', 'biyoloji-12-2-gen-biyoteknolojinin-endustri-cevre-ve-adli-tip-alanlarindaki-uygulamalari', 24, true, now(), now()),
  ('b5120000-0000-4000-8000-000000000025', 'b4120000-0000-4000-8000-000000000002', 'Biyoteknoloji ve Etik', 'biyoloji-12-2-gen-biyoteknoloji-ve-etik', 25, true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 3. OUTCOMES (75) — BIY.s.u.k (resmî kodlar; türetilmemiş).
--    sort_order = k (tema-içi; 125 sözleşmesi). subtopic_id = NULL
--    (kaynakta numaralandırılmamış — kasıtlı ve onaylı).
--    id NN sırası: sınıf içi (tema, k) — 9: 2/17/14, 10: 2/19/19, 11: 2/28/22, 12: 2/25/20.
-- ============================================================
insert into public.curriculum_outcomes (
  id, curriculum_version_id, grade_level, subject_id, topic_id, subtopic_id,
  outcome_code, outcome_text, sort_order, source_reference, is_active, created_at, updated_at
) values
  ('b6090000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000001', NULL, 'BIY.9.1.1', 'Biyolojideki dönüm noktalarının insan hayatına katkılarını sorgulayabilme', 1, 'TYMM 2026 Biyoloji Öğretim Programı, s.16', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000001', NULL, 'BIY.9.1.2', 'Bilimsel araştırma süreçlerinde bilimin doğasını yorumlayabilme', 2, 'TYMM 2026 Biyoloji Öğretim Programı, s.16', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000001', NULL, 'BIY.9.1.3', 'Bilimsel araştırmaların bilim etiğine uygunluğu ile ilgili bilgi toplayabilme', 3, 'TYMM 2026 Biyoloji Öğretim Programı, s.16', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000001', NULL, 'BIY.9.1.4', 'Çevresindeki canlıların özelliklerini bilimsel olarak gözlemleyebilme', 4, 'TYMM 2026 Biyoloji Öğretim Programı, s.16', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000001', NULL, 'BIY.9.1.5', 'İnorganik moleküllerin önemi hakkında bilimsel çıkarım yapabilme', 5, 'TYMM 2026 Biyoloji Öğretim Programı, s.16', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000001', NULL, 'BIY.9.1.6', 'Organik moleküllerin yapısı ve çeşitleriyle ilgili bilgi toplayabilme', 6, 'TYMM 2026 Biyoloji Öğretim Programı, s.16', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000001', NULL, 'BIY.9.1.7', 'Besinlerin yapısında karbohidrat, lipit ve protein varlığının belirlenmesiyle ilgili deney yapabilme', 7, 'TYMM 2026 Biyoloji Öğretim Programı, s.16', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000001', NULL, 'BIY.9.1.8', 'pH ve sıcaklığın enzim aktivitesini etkilediğini gösteren deney yapabilme', 8, 'TYMM 2026 Biyoloji Öğretim Programı, s.17', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000002', NULL, 'BIY.9.2.1', 'Hücre alt birimlerini ve bu birimlerin işlevleri arasındaki ilişkileri çözümleyebilme', 1, 'TYMM 2026 Biyoloji Öğretim Programı, s.24', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000002', NULL, 'BIY.9.2.2', 'Hücre zarından madde geçişlerini sınıflandırabilme', 2, 'TYMM 2026 Biyoloji Öğretim Programı, s.24', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000002', NULL, 'BIY.9.2.3', 'Küçük moleküllerin hücre zarından pasif geçişi ile ilgili deney yapabilme', 3, 'TYMM 2026 Biyoloji Öğretim Programı, s.24', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000002', NULL, 'BIY.9.2.4', 'Canlıları sınıflandırabilme', 4, 'TYMM 2026 Biyoloji Öğretim Programı, s.24', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000002', NULL, 'BIY.9.2.5', 'Üç üst âlem (domain) sisteminde yer alan canlıların özellikleri ile ilgili çıkarım yapabilme', 5, 'TYMM 2026 Biyoloji Öğretim Programı, s.24', true, now(), now()),
  ('b6090000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c5', 9, '71191e01-220a-4682-9351-3d62631308d2', 'b4090000-0000-4000-8000-000000000002', NULL, 'BIY.9.2.6', 'Biyoçeşitliliği oluşturan unsurlarla ilgili bilimsel çıkarım yapabilme', 6, 'TYMM 2026 Biyoloji Öğretim Programı, s.24', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000001', NULL, 'BIY.10.1.1', 'Canlıların yaşamına devam edebilmesi için enerjinin gerekliliğini sorgulayabilme', 1, 'TYMM 2026 Biyoloji Öğretim Programı, s.30', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000001', NULL, 'BIY.10.1.2', 'Fotosentez reaksiyonlarıyla ilgili bilimsel model oluşturabilme', 2, 'TYMM 2026 Biyoloji Öğretim Programı, s.30', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000001', NULL, 'BIY.10.1.3', 'Fotosentezde kullanılan ve üretilen maddelerle ilgili deney yapabilme', 3, 'TYMM 2026 Biyoloji Öğretim Programı, s.30', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000001', NULL, 'BIY.10.1.4', 'Kemosentez hakkında bilgi toplayabilme', 4, 'TYMM 2026 Biyoloji Öğretim Programı, s.30', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000001', NULL, 'BIY.10.1.5', 'Canlılarda sindirim çeşitlerini ve yapılarını sınıflandırabilme', 5, 'TYMM 2026 Biyoloji Öğretim Programı, s.30', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000001', NULL, 'BIY.10.1.6', 'İnsanda enerji eldesi için sindirim, emilim ve taşıma süreçlerinin gerekliliği ile ilgili bilimsel çıkarım yapabilme', 6, 'TYMM 2026 Biyoloji Öğretim Programı, s.30', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000001', NULL, 'BIY.10.1.7', 'Hücresel solunum reaksiyonlarıyla ilgili bilimsel model oluşturabilme', 7, 'TYMM 2026 Biyoloji Öğretim Programı, s.30', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000001', NULL, 'BIY.10.1.8', 'Farklı besin gruplarından enerji eldesi süreçlerini karşılaştırabilme', 8, 'TYMM 2026 Biyoloji Öğretim Programı, s.30', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000001', NULL, 'BIY.10.1.9', 'Fermantasyon ile ilgili deney yapabilme', 9, 'TYMM 2026 Biyoloji Öğretim Programı, s.31', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000001', NULL, 'BIY.10.1.10', 'Besinlerden elde edilen enerjinin canlının metabolik süreçlerine katkısı ile ilgili bilimsel çıkarım yapabilme', 10, 'TYMM 2026 Biyoloji Öğretim Programı, s.31', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000002', NULL, 'BIY.10.2.1', 'Ekosistemin cansız ve canlı bileşenleri arasındaki ilişkileri çözümleyebilme', 1, 'TYMM 2026 Biyoloji Öğretim Programı, s.38', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000002', NULL, 'BIY.10.2.2', 'Komünitelerde ve popülasyonlarda görülen etkileşimleri ve değişimleri sorgulayabilme', 2, 'TYMM 2026 Biyoloji Öğretim Programı, s.38', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000002', NULL, 'BIY.10.2.3', 'Ekosistemdeki enerji akışıyla ilgili tümevarımsal akıl yürütebilme', 3, 'TYMM 2026 Biyoloji Öğretim Programı, s.38', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000002', NULL, 'BIY.10.2.4', 'Madde döngüleri ile ilgili bilimsel model oluşturabilme', 4, 'TYMM 2026 Biyoloji Öğretim Programı, s.38', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000002', NULL, 'BIY.10.2.5', 'Ekolojik sürdürülebilirliğin önemini yorumlayabilme', 5, 'TYMM 2026 Biyoloji Öğretim Programı, s.38', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000002', NULL, 'BIY.10.2.6', 'Çevresinde sürdürülebilirliği kısıtlayan durumlarla ilgili gözleme dayalı tahmin yapabilme', 6, 'TYMM 2026 Biyoloji Öğretim Programı, s.38', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000002', NULL, 'BIY.10.2.7', 'Ekolojik ayak izini küçültebilme yollarını bilimsel olarak sorgulayabilme', 7, 'TYMM 2026 Biyoloji Öğretim Programı, s.38', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000002', NULL, 'BIY.10.2.8', 'Doğal kaynakların ve biyoçeşitliliğin korunması için alınan önlemleri sorgulayabilme', 8, 'TYMM 2026 Biyoloji Öğretim Programı, s.39', true, now(), now()),
  ('b6100000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c5', 10, '71191e01-220a-4682-9351-3d62631308d2', 'b4100000-0000-4000-8000-000000000002', NULL, 'BIY.10.2.9', 'Çevresinde atık yönetimi konusunda yapılan çalışmalarla ilgili bilgi toplayabilme', 9, 'TYMM 2026 Biyoloji Öğretim Programı, s.39', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.1', 'Farklı canlıların uyaranlara karşı oluşturduğu tepki mekanizmaları ile ilgili tümevarımsal akıl yürütebilme', 1, 'TYMM 2026 Biyoloji Öğretim Programı, s.48', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.2', 'Bitkisel hormonların etkileri hakkında akıl yürütebilme', 2, 'TYMM 2026 Biyoloji Öğretim Programı, s.48', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.3', 'Bitkilerdeki tepki mekanizmalarını sınıflandırabilme', 3, 'TYMM 2026 Biyoloji Öğretim Programı, s.48', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.4', 'Bitkilerde yönelme hareketlerini gözlemleyebileceği deney yapabilme', 4, 'TYMM 2026 Biyoloji Öğretim Programı, s.48', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.5', 'Duyu reseptörlerini ve duyu reseptörlerinin bulunduğu duyu organlarını sınıflandırabilme', 5, 'TYMM 2026 Biyoloji Öğretim Programı, s.48', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.6', 'Hayvanlardaki sinir sistemi farklılıkları ile ilgili analojik akıl yürütebilme', 6, 'TYMM 2026 Biyoloji Öğretim Programı, s.48', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.7', 'İnsanda sinir sistemi yapısını çözümleyebilme', 7, 'TYMM 2026 Biyoloji Öğretim Programı, s.48', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.8', 'Refleks olayını yorumlayabilme', 8, 'TYMM 2026 Biyoloji Öğretim Programı, s.48', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.9', 'Harekete dayalı tepkinin oluşmasında iskelet, kas ve eklemlerin eş güdümlü çalışmasıyla ilgili eleştirel düşünebilme', 9, 'TYMM 2026 Biyoloji Öğretim Programı, s.49', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.10', 'İskelet kaslarının kasılma ve gevşeme mekanizması ile ilgili bilimsel model oluşturabilme', 10, 'TYMM 2026 Biyoloji Öğretim Programı, s.49', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.11', 'Bağışıklığı sınıflandırabilme', 11, 'TYMM 2026 Biyoloji Öğretim Programı, s.49', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000001', NULL, 'BIY.11.1.12', 'Alerjik tepkilerin oluşumunu sorgulayabilme', 12, 'TYMM 2026 Biyoloji Öğretim Programı, s.49', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000002', NULL, 'BIY.11.2.1', 'Homeostazinin canlılar için önemiyle ilgili bilimsel çıkarım yapabilme', 1, 'TYMM 2026 Biyoloji Öğretim Programı, s.59', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000002', NULL, 'BIY.11.2.2', 'Homeostatik süreçleri sorgulayabilme', 2, 'TYMM 2026 Biyoloji Öğretim Programı, s.59', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000002', NULL, 'BIY.11.2.3', 'Pozitif ve negatif geri bildirim mekanizmalarını karşılaştırabilme', 3, 'TYMM 2026 Biyoloji Öğretim Programı, s.59', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000002', NULL, 'BIY.11.2.4', 'Homeostazinin sağlanmasında sinir sisteminin etkilerini çözümleyebilme', 4, 'TYMM 2026 Biyoloji Öğretim Programı, s.59', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000002', NULL, 'BIY.11.2.5', 'Endokrin sisteminin homeostazi işlevine yönelik bilimsel çıkarım yapabilme', 5, 'TYMM 2026 Biyoloji Öğretim Programı, s.59', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000002', NULL, 'BIY.11.2.6', 'Dolaşım sistemi ve homeostazi arasındaki ilişki ile ilgili bilimsel model oluşturabilme', 6, 'TYMM 2026 Biyoloji Öğretim Programı, s.59', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000002', NULL, 'BIY.11.2.7', 'Solunum sisteminin homeostazinin sağlanmasındaki rolünü kanıtlarla ortaya koyabilme', 7, 'TYMM 2026 Biyoloji Öğretim Programı, s.59', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000002', NULL, 'BIY.11.2.8', 'Boşaltım sisteminin homeostazi işlevine yönelik bilimsel çıkarım yapabilme', 8, 'TYMM 2026 Biyoloji Öğretim Programı, s.59', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000021', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000002', NULL, 'BIY.11.2.9', 'Homeostazinin sağlanmasında sistemlerin eş güdümlü çalışmasıyla ilgili eleştirel düşünebilme', 9, 'TYMM 2026 Biyoloji Öğretim Programı, s.60', true, now(), now()),
  ('b6110000-0000-4000-8000-000000000022', 'a1000000-0000-4000-8000-0000000000c5', 11, '71191e01-220a-4682-9351-3d62631308d2', 'b4110000-0000-4000-8000-000000000002', NULL, 'BIY.11.2.10', 'Homeostazinin sağlanamadığı durumlarda oluşabilecek sağlık problemleri hakkında hipotez oluşturabilme', 10, 'TYMM 2026 Biyoloji Öğretim Programı, s.60', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000001', NULL, 'BIY.12.1.1', 'Hücre bölünmesinin ve üremenin canlılar için önemini yorumlayabilme', 1, 'TYMM 2026 Biyoloji Öğretim Programı, s.69', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000001', NULL, 'BIY.12.1.2', 'Hücredeki genetik materyalin organizasyonunu çözümleyebilme', 2, 'TYMM 2026 Biyoloji Öğretim Programı, s.69', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000001', NULL, 'BIY.12.1.3', 'Canlılarda hücre döngüsü ve hücre bölünmesini sorgulayabilme', 3, 'TYMM 2026 Biyoloji Öğretim Programı, s.69', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000001', NULL, 'BIY.12.1.4', 'Kromozomlarda ayrılmamanın sonuçlarıyla ilgili bilimsel çıkarım yapabilme', 4, 'TYMM 2026 Biyoloji Öğretim Programı, s.69', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000001', NULL, 'BIY.12.1.5', 'Üreme hücrelerinin oluşum süreci ve yapılarını karşılaştırabilme', 5, 'TYMM 2026 Biyoloji Öğretim Programı, s.69', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000001', NULL, 'BIY.12.1.6', 'Eşeysiz ve eşeyli üreme ile ilgili bilimsel çıkarım yapabilme', 6, 'TYMM 2026 Biyoloji Öğretim Programı, s.69', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000001', NULL, 'BIY.12.1.7', 'Erkek ve dişi üreme sistemlerinin yapısı ve işleyişiyle ilgili bilgi toplayabilme', 7, 'TYMM 2026 Biyoloji Öğretim Programı, s.69', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000001', NULL, 'BIY.12.1.8', 'Embriyonik gelişimle ilgili bilgi toplayabilme', 8, 'TYMM 2026 Biyoloji Öğretim Programı, s.69', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000001', NULL, 'BIY.12.1.9', 'Çiçeğin kısımları ve görevleriyle ilgili bilimsel gözlem yapabilme', 9, 'TYMM 2026 Biyoloji Öğretim Programı, s.70', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000001', NULL, 'BIY.12.1.10', 'Çimlenmeyi etkileyen faktörleri gözlemleyebileceği deney yapabilme', 10, 'TYMM 2026 Biyoloji Öğretim Programı, s.70', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000002', NULL, 'BIY.12.2.1', 'Nükleik asitlerin yapısını ve canlılıktaki rolünü sorgulayabilme', 1, 'TYMM 2026 Biyoloji Öğretim Programı, s.78', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000002', NULL, 'BIY.12.2.2', 'DNA replikasyonunun bilimsel modelini oluşturabilme', 2, 'TYMM 2026 Biyoloji Öğretim Programı, s.78', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000002', NULL, 'BIY.12.2.3', 'Genetik bilginin ürüne dönüşüm sürecini çözümleyebilme', 3, 'TYMM 2026 Biyoloji Öğretim Programı, s.78', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000002', NULL, 'BIY.12.2.4', 'Genetik yapıdaki değişikliklerin canlı yaşamına etkileri hakkında eleştirel düşünebilme', 4, 'TYMM 2026 Biyoloji Öğretim Programı, s.78', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000002', NULL, 'BIY.12.2.5', 'Mendel kalıtım ilkelerinin geçerli olduğu genetik problemleri çözebilme', 5, 'TYMM 2026 Biyoloji Öğretim Programı, s.78', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000002', NULL, 'BIY.12.2.6', 'Eş baskınlık ve çok alellilikle ilgili deney yapabilme', 6, 'TYMM 2026 Biyoloji Öğretim Programı, s.78', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000002', NULL, 'BIY.12.2.7', 'Eşeye bağlı kalıtıma ilişkin tümevarımsal akıl yürütebilme', 7, 'TYMM 2026 Biyoloji Öğretim Programı, s.78', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000002', NULL, 'BIY.12.2.8', 'Genetik testlerin ve genetik danışmanlığın önemini sorgulayabilme', 8, 'TYMM 2026 Biyoloji Öğretim Programı, s.79', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000002', NULL, 'BIY.12.2.9', 'Biyoteknolojinin uygulama alanları ile ilgili bilgi toplayabilme', 9, 'TYMM 2026 Biyoloji Öğretim Programı, s.79', true, now(), now()),
  ('b6120000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c5', 12, '71191e01-220a-4682-9351-3d62631308d2', 'b4120000-0000-4000-8000-000000000002', NULL, 'BIY.12.2.10', 'Biyoteknolojik uygulamaların etik boyutunu eleştirel düşünebilme', 10, 'TYMM 2026 Biyoloji Öğretim Programı, s.79', true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 4. MIGRATION HISTORY — idempotent kayıt (psql koşumunda statements=NULL;
--    CLI koşan ortamda CLI'ın kendi kaydı varsa bu INSERT atlanır).
-- ============================================================
insert into supabase_migrations.schema_migrations (version, name, statements)
select '144', '144_curriculum_biyoloji_tymm2026_agac', NULL
 where not exists (
   select 1 from supabase_migrations.schema_migrations where version = '144'
 );

-- ============================================================
-- 5. SON DENETİM (transaction içi; beklentiden sapan durum COMMIT'i durdurur)
-- ============================================================
DO $final$
DECLARE
  v_t integer; v_s integer; v_o integer; v_null_t integer; v_null_s integer; v_linked integer;
BEGIN
  SELECT count(*) INTO v_t FROM public.topics WHERE subject_id = '71191e01-220a-4682-9351-3d62631308d2';
  SELECT count(*) INTO v_s FROM public.subtopics s JOIN public.topics t ON t.id = s.topic_id
   WHERE t.subject_id = '71191e01-220a-4682-9351-3d62631308d2';
  SELECT count(*),
         count(*) FILTER (WHERE topic_id IS NULL),
         count(*) FILTER (WHERE subtopic_id IS NULL),
         count(*) FILTER (WHERE topic_id IS NOT NULL)
    INTO v_o, v_null_t, v_null_s, v_linked
    FROM public.curriculum_outcomes WHERE outcome_code LIKE 'BIY.%';
  IF v_t <> 8 OR v_s <> 89 OR v_o <> 75 OR v_null_t <> 0 OR v_null_s <> 75 OR v_linked <> 75 THEN
    RAISE EXCEPTION 'FINAL_144: beklenen 8/89/75 (topic/subtopic/outcome), topic-bağlı=75, NULL subtopic=75; bulunan %/%/%/%/%/%', v_t, v_s, v_o, v_linked, v_null_s, v_null_t;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.curriculum_versions
                 WHERE id = 'a1000000-0000-4000-8000-0000000000c5' AND framework = 'tymm_2026_biyoloji') THEN
    RAISE EXCEPTION 'FINAL_144: sürüm satırı (a1000000-0000-4000-8000-0000000000c5) yok — beklenmeyen durum.';
  END IF;
END
$final$;

COMMIT;
