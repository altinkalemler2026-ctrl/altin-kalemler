-- ============================================================
-- 147_curriculum_felsefe_tymm2026_agac.sql
-- Altın Kalemler — CURRICULUM-ALL-01 Felsefe dilimi: TYMM 2026 Felsefe
--   müfredat ağacının (15 ünite + 36 İçerik Çerçevesi maddesi +
--   22 yeni outcome) YÜKLENMESİ ve
--   tymm_2026_felsefe curriculum_versions satırının OLUŞTURULMASI.
--
-- KULLANICI ONAYLI KAPSAM (2026-10-27)
--   - 1 sürüm + 15 topic + 36 subtopic + 22 outcome YÜKLENİR (10. sınıf: 9 ünite / 23 madde / 10 çıktı; 11. sınıf: 6 ünite / 13 madde / 12 çıktı).
--   - Felsefe için DB'de ÖNCEDEN FEL.* outcome / topic / subtopic YOKTUR
--     (2026-10-27 salt-okunur ölçüm; dry-run eşleşen=0). Bu yüzden "mevcut
--     kayıt linkleme UPDATE'i" YOKTUR — migration salt EKLEME yapar.
--   - Sınıf kapsamı 10-11 (resmî program bu sınıfları kapsar; kapsam
--     dışı sınıflar için satır UYDURULMAZ — kanonik dosya §1).
--
-- KAYNAK (yalnız resmî)
--   Türkiye Yüzyılı Maarif Modeli — Ortaöğretim Felsefe Dersi (10-11) Öğretim
--   Programı (2026); PDF basılı sayfa numaraları.
--   Yerel: docs/references/mufredat/2026-2027/tymm-2026-felsefe-10-11.pdf
--   Ağaç:  docs/question-production/curriculum-mapping/felsefe-10-11-kanonik-esleme-v1.md
--   Dry-run: scripts/mufredat-dry-run.ts --ders=felsefe → felsefe-dry-run-sonuc.md
--   (73/73 veri satırı, 15/36/22, eşleşen 0, metin farkı 0, engelli 0)
--
-- UUID ŞEMASI (142/145 deseni; aileler DB envanteriyle çakışmasız seçildi)
--   Mevcut deterministik aileler: a1=versions, a2=schedule_profiles, a3=MAT topics,
--   a4=schedule_items, a5=FIZ topics, a6=MAT subtopics, a7=MAT outcomes,
--   a8=FIZ subtopics, a9=FIZ outcomes; Kimya=b1/b2/b3 (c4 sürüm), Biyoloji=b4/b5/b6
--   (c5), Coğrafya=b7/b8/b9 (c6). YENİ AİLELER (topics/subtopics/outcomes +
--   curriculum_schedule_* tablolarında id LIKE 'c%' = 0 doğrulandı —
--   2026-10-27 salt-okunur tarama):
--   Felsefe topic    : c4 + GG (sınıf) → c4GG0000-0000-4000-8000-0000000000NN
--   Felsefe subtopic : c5 + GG (sınıf) → c5GG0000-0000-4000-8000-0000000000NN
--   Felsefe outcome : c6 + GG (sınıf) → c6GG0000-0000-4000-8000-0000000000NN
--     (NN = sınıf içi (ünite, k) sıralamasında kesintisiz sayaç, 001'den başlar)
--   NOT: 'c' ailesi topics/subtopics/outcomes tablolarında BOŞTUR; sürüm
--   id'lerindeki 'cN' SONEKİ (a1 ailesi …0000000000c1..c6) farklı konumdadır
--   ve çakışmaz — iki gösterim migration 145 başlığında da birlikte belgelenir.
--   Sürüm id: a1000000-0000-4000-8000-0000000000c8 (tymm_2026_felsefe; a1 ailesinde c6'dan sonraki ilk boş değer).
--   Subject id: c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb (Felsefe, migration 045).
--
-- AD / SLUG / SIRA KARARLARI (142/145 birebir)
--   - topic.name: 'FEL.GG.N <ÜNİTE ADI>' deseni; ünite adı PDF'teki resmî
--     büyük harfli başlıktır ('N. ÜNİTE: ' öneki atılır).
--   - topic.slug : felsefe-GG-N-<ünite-adı-slug>  (dry-run öneri formülüyle aynı).
--     DB kısıtı: UNIQUE (curriculum_version_id, subject_id, grade_level, slug).
--   - subtopic.name: İçerik Çerçevesi kutusundaki basılı madde (resmî).
--   - subtopic.slug: <topic-slug>-<madde-slug> (112 matematik deseni; UNIQUE (topic_id, slug)).
--   - subtopic.sort_order: sınıf içi kesintisiz (kutu sırası; ünite değişince sıfırlanmaz).
--   - outcome.sort_order: kodun son basamağı k (ünite-içi sıra) — 125/142 sözleşmesi.
--   - outcome.subtopic_id: NULL (kaynakta çıktı→alt konu ilişkisi numaralandırılmamıştır;
--     yakınlık/sıra/isim benzerliğiyle atama YASAKTIR — kanonik dosya §2, BLOKAJ-1 kuralı).
--   - source_reference: 'TYMM 2026 Felsefe Öğretim Programı, s.NN' (142/145 deseni); NN = kazanım bloğunun
--     basılı sayfası (kanonik dosya §4/§5).
--
-- SÜRÜM SATIRI (125 fizik deseni; 145 ile aynı durum)
--   Bu ders için curriculum_versions satırı YOKTU (dry-run: 'BULUNAMADI').
--   Sürüm INSERT'i bölüm 0.5'tedir: is_default=false (yıl-tek-default kısmi
--   indeksi bozulmaz), UNIQUE (academic_year, framework) uyumlu.
--   published_at: resmî URL zaman damgası (2026518151339111 → 2026-05-18; 143/144/145 yöntemi).
--
-- İDEMPOTENCE
--   - Tüm INSERT'ler ON CONFLICT (id) DO NOTHING → tekrar koşum SIFIR yeni satır.
--   - GUARD: ağaç ya (0,0,0) (ilk uygulama) ya (15/36/22) dolu hâlde
--     olmalı; karışık/kısmi durum fail-closed durur. Dolu hâlde tüm id'ler tanınır.
--   - outcome_code'da UNIQUE KISIT YOKTUR (yalnız idx_curriculum_outcomes_code normal
--     indeks); mükerrer kod riski GUARD'ın benzersiz-kod denetimi + deterministik id ile
--     kapanır (142'nin iki katmanlı koruması).
--   - History: supabase_migrations.schema_migrations'a version='147' kaydı WHERE NOT
--     EXISTS ile idempotent eklenir; statements=NULL (psql koşumunda dosya kendi metnini
--     içine koyamaz; CLI uygulayan ortamda CLI statements'i doldurur — 142 notu birebir).
--
-- GERİ DÖNÜŞ: scripts/felsefe-mufredat-geri-donus.sql (tek transaction;
--   22 outcome DELETE → 36 subtopic DELETE → 15 topic DELETE → sürüm satırı DELETE →
--   147 history DELETE; FK sırası korunur, fail-closed üçüncü-taraf referans taraması
--   içerir). Uygulama öncesi yedek (boş ön-durum kanıtı):
--   docs/references/mufredat/yedekler/felsefe-on-yedek-20261027.sql
--
-- YASAKLAR / DOKUNULMAZLAR
--   - AK-M12-ILK-008 ve tüm matematik kayıtlarına (a3/a6/a7, c1/c2), Fizik (a5/a8/a9, c3),
--     Kimya (b1/b2/b3, c4), Biyoloji (b4/b5/b6, c5), Coğrafya (b7/b8/b9, c6) kayıtlarına
--     DOKUNULMAZ. Şema/RLS/RPC değişmez (data-only). Soru üretimi, staging, takvim
--     dağıtımı YOK. Geometri/Türkçe subjects satırlarına dokunulmaz.
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
  IF NOT EXISTS (SELECT 1 FROM public.subjects WHERE id = 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb') THEN
    RAISE EXCEPTION 'GUARD_147: Felsefe subject satırı yok — migration 045 uygulanmamış ortam.';
  END IF;

  -- Sürüm satırı: ya hiç yok (ilk uygulama) ya da TAM bu çift var (tekrar koşum).
  SELECT count(*) INTO v_surum FROM public.curriculum_versions
   WHERE framework = 'tymm_2026_felsefe' OR id = 'a1000000-0000-4000-8000-0000000000c8';
  IF v_surum > 0 THEN
    IF NOT EXISTS (SELECT 1 FROM public.curriculum_versions
                   WHERE id = 'a1000000-0000-4000-8000-0000000000c8' AND framework = 'tymm_2026_felsefe'
                     AND academic_year = '2026-2027' AND is_default = false) THEN
      RAISE EXCEPTION 'GUARD_147: tymm_2026_felsefe/a1000000-0000-4000-8000-0000000000c8 sürüm satırı çelişkili (farklı id/framework/is_default) — fail-closed dur.';
    END IF;
  END IF;

  -- Ağaç durumu: ya boş ya tam dolu. Kısmi/yabancı durum fail-closed.
  SELECT count(*) INTO v_topic_sayi FROM public.topics
   WHERE subject_id = 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb';
  SELECT count(*) INTO v_subtopic_sayi FROM public.subtopics s
   JOIN public.topics t ON t.id = s.topic_id
   WHERE t.subject_id = 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb';
  SELECT count(*) INTO v_outcome_sayi FROM public.curriculum_outcomes
   WHERE outcome_code LIKE 'FEL.%';
  IF NOT (v_topic_sayi = 0 AND v_subtopic_sayi = 0 AND v_outcome_sayi = 0)
     AND NOT (v_topic_sayi = 15 AND v_subtopic_sayi = 36 AND v_outcome_sayi = 22) THEN
    RAISE EXCEPTION 'GUARD_147: Felsefe ağacı kısmi/yabancı durumda (topics=%, subtopics=%, outcomes=%; beklenen 0/0/0 veya 15/36/22) — fail-closed dur.', v_topic_sayi, v_subtopic_sayi, v_outcome_sayi;
  END IF;

  -- Dolu hâl: id'lerin tamamı bu migration'ın deterministik kümesinden mi?
  IF v_topic_sayi = 15 THEN
    SELECT count(*) INTO v_yabanci FROM public.topics
     WHERE subject_id = 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb' AND id NOT IN (
       'c4100000-0000-4000-8000-000000000001',
       'c4100000-0000-4000-8000-000000000002',
       'c4100000-0000-4000-8000-000000000003',
       'c4100000-0000-4000-8000-000000000004',
       'c4100000-0000-4000-8000-000000000005',
       'c4100000-0000-4000-8000-000000000006',
       'c4100000-0000-4000-8000-000000000007',
       'c4100000-0000-4000-8000-000000000008',
       'c4100000-0000-4000-8000-000000000009',
       'c4110000-0000-4000-8000-000000000001',
       'c4110000-0000-4000-8000-000000000002',
       'c4110000-0000-4000-8000-000000000003',
       'c4110000-0000-4000-8000-000000000004',
       'c4110000-0000-4000-8000-000000000005',
       'c4110000-0000-4000-8000-000000000006'
    );
    IF v_yabanci > 0 THEN
      RAISE EXCEPTION 'GUARD_147: % yabancı Felsefe topic id''si bulundu — fail-closed dur.', v_yabanci;
    END IF;
    SELECT count(*) INTO v_yabanci FROM public.subtopics s
     JOIN public.topics t ON t.id = s.topic_id
     WHERE t.subject_id = 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb' AND s.id NOT IN (
       'c5100000-0000-4000-8000-000000000001',
       'c5100000-0000-4000-8000-000000000002',
       'c5100000-0000-4000-8000-000000000003',
       'c5100000-0000-4000-8000-000000000004',
       'c5100000-0000-4000-8000-000000000005',
       'c5100000-0000-4000-8000-000000000006',
       'c5100000-0000-4000-8000-000000000007',
       'c5100000-0000-4000-8000-000000000008',
       'c5100000-0000-4000-8000-000000000009',
       'c5100000-0000-4000-8000-000000000010',
       'c5100000-0000-4000-8000-000000000011',
       'c5100000-0000-4000-8000-000000000012',
       'c5100000-0000-4000-8000-000000000013',
       'c5100000-0000-4000-8000-000000000014',
       'c5100000-0000-4000-8000-000000000015',
       'c5100000-0000-4000-8000-000000000016',
       'c5100000-0000-4000-8000-000000000017',
       'c5100000-0000-4000-8000-000000000018',
       'c5100000-0000-4000-8000-000000000019',
       'c5100000-0000-4000-8000-000000000020',
       'c5100000-0000-4000-8000-000000000021',
       'c5100000-0000-4000-8000-000000000022',
       'c5100000-0000-4000-8000-000000000023',
       'c5110000-0000-4000-8000-000000000001',
       'c5110000-0000-4000-8000-000000000002',
       'c5110000-0000-4000-8000-000000000003',
       'c5110000-0000-4000-8000-000000000004',
       'c5110000-0000-4000-8000-000000000005',
       'c5110000-0000-4000-8000-000000000006',
       'c5110000-0000-4000-8000-000000000007',
       'c5110000-0000-4000-8000-000000000008',
       'c5110000-0000-4000-8000-000000000009',
       'c5110000-0000-4000-8000-000000000010',
       'c5110000-0000-4000-8000-000000000011',
       'c5110000-0000-4000-8000-000000000012',
       'c5110000-0000-4000-8000-000000000013'
    );
    IF v_yabanci > 0 THEN
      RAISE EXCEPTION 'GUARD_147: % yabancı Felsefe subtopic id''si bulundu — fail-closed dur.', v_yabanci;
    END IF;
    SELECT count(*), count(*) FILTER (WHERE id IN (
       'c6100000-0000-4000-8000-000000000001',
       'c6100000-0000-4000-8000-000000000002',
       'c6100000-0000-4000-8000-000000000003',
       'c6100000-0000-4000-8000-000000000004',
       'c6100000-0000-4000-8000-000000000005',
       'c6100000-0000-4000-8000-000000000006',
       'c6100000-0000-4000-8000-000000000007',
       'c6100000-0000-4000-8000-000000000008',
       'c6100000-0000-4000-8000-000000000009',
       'c6100000-0000-4000-8000-000000000010',
       'c6110000-0000-4000-8000-000000000001',
       'c6110000-0000-4000-8000-000000000002',
       'c6110000-0000-4000-8000-000000000003',
       'c6110000-0000-4000-8000-000000000004',
       'c6110000-0000-4000-8000-000000000005',
       'c6110000-0000-4000-8000-000000000006',
       'c6110000-0000-4000-8000-000000000007',
       'c6110000-0000-4000-8000-000000000008',
       'c6110000-0000-4000-8000-000000000009',
       'c6110000-0000-4000-8000-000000000010',
       'c6110000-0000-4000-8000-000000000011',
       'c6110000-0000-4000-8000-000000000012'
    )), count(DISTINCT outcome_code) INTO v_outcome_sayi, v_tanimli, v_benzersiz
      FROM public.curriculum_outcomes WHERE outcome_code LIKE 'FEL.%';
    IF v_outcome_sayi <> 22 OR v_tanimli <> 22 OR v_benzersiz <> 22 THEN
      RAISE EXCEPTION 'GUARD_147: FEL.* outcomes=% (tanınan id=%, benzersiz kod=%; beklenen 22/22/22) — id/kod drifti, fail-closed dur.', v_outcome_sayi, v_tanimli, v_benzersiz;
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
  'a1000000-0000-4000-8000-0000000000c8',
  '2026-2027',
  'tymm_2026_felsefe',
  'Türkiye Yüzyılı Maarif Modeli Felsefe Dersi (10 ve 11. Sınıflar) Öğretim Programı (2026)',
  'https://mufredat.meb.gov.tr/Dosyalar/2026518151339111-felsefed%C3%B6p.pdf',
  '2026-05-18',  -- mufredat.meb.gov.tr resmî URL zaman damgası (2026518151339111 → 2026-05-18; 143/144/145 yöntemi)
  true, false, now(), now()
)
on conflict (id) do nothing;

-- ============================================================
-- 1. TOPICS (15) — FEL.GG.N <ÜNİTE ADI>; sort_order = resmî ünite no (sınıf içi)
--    UNIQUE (curriculum_version_id, subject_id, grade_level, slug) koruması:
--    farklı id ile aynı slug varsa INSERT doğal olarak HATA verir (fail-closed).
-- ============================================================
insert into public.topics (
  id, subject_id, grade_level, name, slug, sort_order,
  is_active, curriculum_version_id, created_at, updated_at
) values
  ('c4100000-0000-4000-8000-000000000001', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 10, 'FEL.10.1 FELSEFENİN DOĞASI', 'felsefe-10-1-felsefenin-dogasi', 1, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4100000-0000-4000-8000-000000000002', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 10, 'FEL.10.2 FELSEFE, MANTIK VE ARGÜMANTASYON', 'felsefe-10-2-felsefe-mantik-ve-argumantasyon', 2, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4100000-0000-4000-8000-000000000003', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 10, 'FEL.10.3 VARLIK FELSEFESİ', 'felsefe-10-3-varlik-felsefesi', 3, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4100000-0000-4000-8000-000000000004', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 10, 'FEL.10.4 BİLGİ FELSEFESİ', 'felsefe-10-4-bilgi-felsefesi', 4, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4100000-0000-4000-8000-000000000005', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 10, 'FEL.10.5 AHLAK FELSEFESİ', 'felsefe-10-5-ahlak-felsefesi', 5, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4100000-0000-4000-8000-000000000006', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 10, 'FEL.10.6 ESTETİK VE SANAT FELSEFESİ', 'felsefe-10-6-estetik-ve-sanat-felsefesi', 6, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4100000-0000-4000-8000-000000000007', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 10, 'FEL.10.7 SİYASET FELSEFESİ', 'felsefe-10-7-siyaset-felsefesi', 7, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4100000-0000-4000-8000-000000000008', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 10, 'FEL.10.8 DİN FELSEFESİ', 'felsefe-10-8-din-felsefesi', 8, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4100000-0000-4000-8000-000000000009', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 10, 'FEL.10.9 BİLİM FELSEFESİ', 'felsefe-10-9-bilim-felsefesi', 9, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4110000-0000-4000-8000-000000000001', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 11, 'FEL.11.1 ÇEVRE SORUNLARI VE FELSEFE', 'felsefe-11-1-cevre-sorunlari-ve-felsefe', 1, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4110000-0000-4000-8000-000000000002', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 11, 'FEL.11.2 TEKNOLOJİ VE HAYAT', 'felsefe-11-2-teknoloji-ve-hayat', 2, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4110000-0000-4000-8000-000000000003', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 11, 'FEL.11.3 AKIL VE İNANÇ', 'felsefe-11-3-akil-ve-inanc', 3, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4110000-0000-4000-8000-000000000004', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 11, 'FEL.11.4 EDEBİYAT VE FELSEFE', 'felsefe-11-4-edebiyat-ve-felsefe', 4, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4110000-0000-4000-8000-000000000005', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 11, 'FEL.11.5 HAYATIN ANLAMI', 'felsefe-11-5-hayatin-anlami', 5, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now()),
  ('c4110000-0000-4000-8000-000000000006', 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 11, 'FEL.11.6 HUKUK VE FELSEFE', 'felsefe-11-6-hukuk-ve-felsefe', 6, true, 'a1000000-0000-4000-8000-0000000000c8', now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 2. SUBTOPICS (36) — İçerik Çerçevesi maddeleri (resmî, basılı sıra);
--    sort_order sınıf içi kesintisiz (10:23, 11:13);
--    subtopic_id bağlantısı çıktılara AÇILMAZ (kaynak numaralandırmamış).
-- ============================================================
insert into public.subtopics (
  id, topic_id, name, slug, sort_order, is_active, created_at, updated_at
) values
  ('c5100000-0000-4000-8000-000000000001', 'c4100000-0000-4000-8000-000000000001', 'Felsefenin Anlamı', 'felsefe-10-1-felsefenin-dogasi-felsefenin-anlami', 1, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000002', 'c4100000-0000-4000-8000-000000000001', 'Felsefi Düşüncenin Özellikleri', 'felsefe-10-1-felsefenin-dogasi-felsefi-dusuncenin-ozellikleri', 2, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000003', 'c4100000-0000-4000-8000-000000000001', 'Felsefi Düşüncenin Gelişimi', 'felsefe-10-1-felsefenin-dogasi-felsefi-dusuncenin-gelisimi', 3, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000004', 'c4100000-0000-4000-8000-000000000001', 'Felsefi Sorunun Temel Özellikleri', 'felsefe-10-1-felsefenin-dogasi-felsefi-sorunun-temel-ozellikleri', 4, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000005', 'c4100000-0000-4000-8000-000000000001', 'Felsefenin Diğer Alanlarla İlişkisi', 'felsefe-10-1-felsefenin-dogasi-felsefenin-diger-alanlarla-iliskisi', 5, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000006', 'c4100000-0000-4000-8000-000000000001', 'Felsefenin Bireysel ve Toplumsal İşlevi', 'felsefe-10-1-felsefenin-dogasi-felsefenin-bireysel-ve-toplumsal-islevi', 6, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000007', 'c4100000-0000-4000-8000-000000000002', 'Düşünme ve Dil İlişkisi', 'felsefe-10-2-felsefe-mantik-ve-argumantasyon-dusunme-ve-dil-iliskisi', 7, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000008', 'c4100000-0000-4000-8000-000000000002', 'Mantık ve Argümantasyonun Temel Kavramları', 'felsefe-10-2-felsefe-mantik-ve-argumantasyon-mantik-ve-argumantasyonun-temel-kavramlari', 8, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000009', 'c4100000-0000-4000-8000-000000000002', 'Argümantasyonun Yapısı', 'felsefe-10-2-felsefe-mantik-ve-argumantasyon-argumantasyonun-yapisi', 9, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000010', 'c4100000-0000-4000-8000-000000000003', 'Varlık Felsefesinin Konusu ve Temel Kavramları', 'felsefe-10-3-varlik-felsefesi-varlik-felsefesinin-konusu-ve-temel-kavramlari', 10, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000011', 'c4100000-0000-4000-8000-000000000003', 'Varlık Felsefesinin Temel Problemleri (Varlığın Var Olup Olmadığı, Varlığın Ne Olduğu)', 'felsefe-10-3-varlik-felsefesi-varlik-felsefesinin-temel-problemleri-varligin-var-olup-olmadigi-varligin-ne-oldugu', 11, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000012', 'c4100000-0000-4000-8000-000000000004', 'Bilgi Felsefesinin Konusu ve Temel Kavramları', 'felsefe-10-4-bilgi-felsefesi-bilgi-felsefesinin-konusu-ve-temel-kavramlari', 12, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000013', 'c4100000-0000-4000-8000-000000000004', 'Bilgi Felsefesinin Temel Problemleri (Bilginin İmkânı, Kaynağı ve Doğruluk Ölçütleri)', 'felsefe-10-4-bilgi-felsefesi-bilgi-felsefesinin-temel-problemleri-bilginin-imkani-kaynagi-ve-dogruluk-olcutleri', 13, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000014', 'c4100000-0000-4000-8000-000000000005', 'Ahlak Felsefesinin Konusu ve Temel Kavramları', 'felsefe-10-5-ahlak-felsefesi-ahlak-felsefesinin-konusu-ve-temel-kavramlari', 14, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000015', 'c4100000-0000-4000-8000-000000000005', 'Ahlak Felsefesinin Temel Problemleri (Evrensel Ahlak Yasasının İmkânı, Özgürlük)', 'felsefe-10-5-ahlak-felsefesi-ahlak-felsefesinin-temel-problemleri-evrensel-ahlak-yasasinin-imkani-ozgurluk', 15, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000016', 'c4100000-0000-4000-8000-000000000006', 'Estetik ve Sanat Felsefesinin Konusu ve Temel Kavramları', 'felsefe-10-6-estetik-ve-sanat-felsefesi-estetik-ve-sanat-felsefesinin-konusu-ve-temel-kavramlari', 16, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000017', 'c4100000-0000-4000-8000-000000000006', 'Estetik ve Sanat Felsefesinin Temel Problemleri (Sanatın Ne Olduğu, Güzellik ve Ortak Estetik Yargıların İmkânı)', 'felsefe-10-6-estetik-ve-sanat-felsefesi-estetik-ve-sanat-felsefesinin-temel-problemleri-sanatin-ne-oldugu-guzellik-ve-ortak-estetik-yargilarin-imkani', 17, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000018', 'c4100000-0000-4000-8000-000000000007', 'Siyaset Felsefesinin Konusu ve Temel Kavramları', 'felsefe-10-7-siyaset-felsefesi-siyaset-felsefesinin-konusu-ve-temel-kavramlari', 18, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000019', 'c4100000-0000-4000-8000-000000000007', 'Siyaset Felsefesinin Temel Problemleri (Devletin Kökeni, İktidarın Kaynağı ve Meşruiyeti, İdeal Düzen ve Ütopyalar)', 'felsefe-10-7-siyaset-felsefesi-siyaset-felsefesinin-temel-problemleri-devletin-kokeni-iktidarin-kaynagi-ve-mesruiyeti-ideal-duzen-ve-utopyalar', 19, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000020', 'c4100000-0000-4000-8000-000000000008', 'Din Felsefesinin Konusu ve Temel Kavramları', 'felsefe-10-8-din-felsefesi-din-felsefesinin-konusu-ve-temel-kavramlari', 20, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000021', 'c4100000-0000-4000-8000-000000000008', 'Din Felsefesinin Temel Problemleri (Tanrı’nın Varlığına İlişkin Görüşler, Tanrı’nın Varlığına Yönelik argüman, Evrenin Sonluluğu ve Sonsuzluğu, Ruhun Ölümsüzlüğü)', 'felsefe-10-8-din-felsefesi-din-felsefesinin-temel-problemleri-tanrinin-varligina-iliskin-gorusler-tanrinin-varligina-yonelik-arguman-evrenin-sonlulugu-ve-sonsuzlugu-ruhun-olumsuzlugu', 21, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000022', 'c4100000-0000-4000-8000-000000000009', 'Bilim Felsefesinin Konusu ve Temel Kavramları', 'felsefe-10-9-bilim-felsefesi-bilim-felsefesinin-konusu-ve-temel-kavramlari', 22, true, now(), now()),
  ('c5100000-0000-4000-8000-000000000023', 'c4100000-0000-4000-8000-000000000009', 'Bilim Felsefesinin Temel Problemleri (Bilimin Ne Olduğu, Bilimi Oluşturan Unsurlar)', 'felsefe-10-9-bilim-felsefesi-bilim-felsefesinin-temel-problemleri-bilimin-ne-oldugu-bilimi-olusturan-unsurlar', 23, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000001', 'c4110000-0000-4000-8000-000000000001', 'Çevre ve İnsan İlişkisi', 'felsefe-11-1-cevre-sorunlari-ve-felsefe-cevre-ve-insan-iliskisi', 1, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000002', 'c4110000-0000-4000-8000-000000000001', 'Çevre Etiği (İnsan Merkezci Etik, Canlı Merkezci Etik, Çevre Merkezci Etik)', 'felsefe-11-1-cevre-sorunlari-ve-felsefe-cevre-etigi-insan-merkezci-etik-canli-merkezci-etik-cevre-merkezci-etik', 2, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000003', 'c4110000-0000-4000-8000-000000000002', 'Teknoloji ve İnsan Hayatı', 'felsefe-11-2-teknoloji-ve-hayat-teknoloji-ve-insan-hayati', 3, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000004', 'c4110000-0000-4000-8000-000000000002', 'Teknoloji Bağlamında Ontolojik Problemler (Ontolojik Anlam Kaybı, Yabancılaşma)', 'felsefe-11-2-teknoloji-ve-hayat-teknoloji-baglaminda-ontolojik-problemler-ontolojik-anlam-kaybi-yabancilasma', 4, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000005', 'c4110000-0000-4000-8000-000000000002', 'Teknoloji Bağlamında Aksiyolojik Problemler (Güvenlik Sorunları, Değerlerin Tahribatı, Ahlaki Eylemin İmkânı)', 'felsefe-11-2-teknoloji-ve-hayat-teknoloji-baglaminda-aksiyolojik-problemler-guvenlik-sorunlari-degerlerin-tahribati-ahlaki-eylemin-imkani', 5, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000006', 'c4110000-0000-4000-8000-000000000003', 'Akıl-İnanç İlişkisine Yönelik Felsefi Sorular ve Problemler', 'felsefe-11-3-akil-ve-inanc-akil-inanc-iliskisine-yonelik-felsefi-sorular-ve-problemler', 6, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000007', 'c4110000-0000-4000-8000-000000000003', 'Akıl-İnanç İlişkisine Yönelik Felsefi Görüş ve Argümanlar', 'felsefe-11-3-akil-ve-inanc-akil-inanc-iliskisine-yonelik-felsefi-gorus-ve-argumanlar', 7, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000008', 'c4110000-0000-4000-8000-000000000004', 'Edebiyat Felsefe İlişkisi', 'felsefe-11-4-edebiyat-ve-felsefe-edebiyat-felsefe-iliskisi', 8, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000009', 'c4110000-0000-4000-8000-000000000004', 'Edebiyat Felsefe İlişkisi Problemleri (Edebî Unsurlara Felsefi Bakış, Edebî Unsurlarla Felsefe Yapma)', 'felsefe-11-4-edebiyat-ve-felsefe-edebiyat-felsefe-iliskisi-problemleri-edebi-unsurlara-felsefi-bakis-edebi-unsurlarla-felsefe-yapma', 9, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000010', 'c4110000-0000-4000-8000-000000000005', 'Hayatın Anlamına Yönelik Felsefi Sorular ve Problemler (Mutluluk ve Hayat İlişkisi, Varoluş ve Kendi Olma)', 'felsefe-11-5-hayatin-anlami-hayatin-anlamina-yonelik-felsefi-sorular-ve-problemler-mutluluk-ve-hayat-iliskisi-varolus-ve-kendi-olma', 10, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000011', 'c4110000-0000-4000-8000-000000000005', 'Hayatın Anlamına Yönelik Felsefi Görüş ve Argümanlar', 'felsefe-11-5-hayatin-anlami-hayatin-anlamina-yonelik-felsefi-gorus-ve-argumanlar', 11, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000012', 'c4110000-0000-4000-8000-000000000006', 'Hukuk ve İnsan', 'felsefe-11-6-hukuk-ve-felsefe-hukuk-ve-insan', 12, true, now(), now()),
  ('c5110000-0000-4000-8000-000000000013', 'c4110000-0000-4000-8000-000000000006', 'Hukukun Doğasına Yönelik Felsefi Problemler [Hukukun Gereği ve Önemi, Hukukun Kaynağı (Doğal Hukuk, Pozitif Hukuk), Ahlak-Hukuk İlişkisi]', 'felsefe-11-6-hukuk-ve-felsefe-hukukun-dogasina-yonelik-felsefi-problemler-hukukun-geregi-ve-onemi-hukukun-kaynagi-dogal-hukuk-pozitif-hukuk-ahlak-hukuk-iliskisi', 13, true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 3. YENİ FEL.* OUTCOMES (22) — salt ekleme (mevcut kayıt YOKTUR).
--    sort_order = k (ünite-içi; 125 sözleşmesi). subtopic_id = NULL
--    (kaynakta numaralandırılmamış — kasıtlı ve onaylı).
-- ============================================================
insert into public.curriculum_outcomes (
  id, curriculum_version_id, grade_level, subject_id, topic_id, subtopic_id,
  outcome_code, outcome_text, sort_order, source_reference, is_active, created_at, updated_at
) values
  ('c6100000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c8', 10, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4100000-0000-4000-8000-000000000001', NULL, 'FEL.10.1.1', 'Felsefenin anlamını, gelişim sürecini ve işlevini sorgulayabilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.14', true, now(), now()),
  ('c6100000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c8', 10, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4100000-0000-4000-8000-000000000002', NULL, 'FEL.10.2.1', 'Düşünme ve dil ilişkisini yapılandırabilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.19', true, now(), now()),
  ('c6100000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c8', 10, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4100000-0000-4000-8000-000000000002', NULL, 'FEL.10.2.2', 'Mantığın temel kavramlarını ve argümantasyon sürecini yorumlayabilme.', 2, 'TYMM 2026 Felsefe Öğretim Programı, s.19', true, now(), now()),
  ('c6100000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c8', 10, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4100000-0000-4000-8000-000000000003', NULL, 'FEL.10.3.1', 'Varlık felsefesinin konusunu, kavramlarını ve problemlerini muhakeme edebilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.23', true, now(), now()),
  ('c6100000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c8', 10, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4100000-0000-4000-8000-000000000004', NULL, 'FEL.10.4.1', 'Bilgi felsefesinin konusunu, kavramlarını ve problemlerini muhakeme edebilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.27', true, now(), now()),
  ('c6100000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c8', 10, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4100000-0000-4000-8000-000000000005', NULL, 'FEL.10.5.1', 'Ahlak felsefesinin konusunu, kavramlarını ve problemlerini muhakeme edebilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.31', true, now(), now()),
  ('c6100000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c8', 10, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4100000-0000-4000-8000-000000000006', NULL, 'FEL.10.6.1', 'Estetik ve sanat felsefesinin konusunu, kavramlarını ve problemlerini muhakeme edebilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.35', true, now(), now()),
  ('c6100000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c8', 10, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4100000-0000-4000-8000-000000000007', NULL, 'FEL.10.7.1', 'Siyaset felsefesinin konusunu, kavramlarını ve problemlerini muhakeme edebilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.39', true, now(), now()),
  ('c6100000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c8', 10, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4100000-0000-4000-8000-000000000008', NULL, 'FEL.10.8.1', 'Din felsefesinin konusunu, kavramlarını ve problemlerini muhakeme edebilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.43', true, now(), now()),
  ('c6100000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c8', 10, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4100000-0000-4000-8000-000000000009', NULL, 'FEL.10.9.1', 'Bilim felsefesinin konusunu, kavramlarını ve problemlerini muhakeme edebilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.47', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000001', NULL, 'FEL.11.1.1', 'Çevre ile ilgili felsefi soru ve problemleri anlayabilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.51', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000001', NULL, 'FEL.11.1.2', 'Çevre sorunlarıyla ilgili felsefi düşünce ortaya koyabilme', 2, 'TYMM 2026 Felsefe Öğretim Programı, s.51', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000002', NULL, 'FEL.11.2.1', 'Teknoloji ile ilgili felsefi soru ve problemleri anlayabilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.55', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000002', NULL, 'FEL.11.2.2', 'Teknoloji ve hayat ilişkisiyle ilgili felsefi düşünce ortaya koyabilme', 2, 'TYMM 2026 Felsefe Öğretim Programı, s.55', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000003', NULL, 'FEL.11.3.1', 'Akıl-inanç ilişkisiyle ilgili felsefi soru ve problemleri anlayabilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.59', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000003', NULL, 'FEL.11.3.2', 'Akıl-inanç ilişkisiyle ilgili felsefi düşünce ortaya koyabilme', 2, 'TYMM 2026 Felsefe Öğretim Programı, s.59', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000004', NULL, 'FEL.11.4.1', 'Edebiyat felsefe ilişkisi ile ilgili soru ve problemleri anlayabilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.62', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000004', NULL, 'FEL.11.4.2', 'Edebiyat felsefe ilişkisi ile ilgili felsefi düşünce ortaya koyabilme', 2, 'TYMM 2026 Felsefe Öğretim Programı, s.62', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000005', NULL, 'FEL.11.5.1', 'Hayatın anlamına ilişkin felsefi soru ve problemleri anlayabilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.66', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000005', NULL, 'FEL.11.5.2', 'Hayatın anlamına ilişkin felsefi düşünce ortaya koyabilme', 2, 'TYMM 2026 Felsefe Öğretim Programı, s.66', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000006', NULL, 'FEL.11.6.1', 'Hukukun doğasına yönelik soru ve felsefi problemleri anlayabilme', 1, 'TYMM 2026 Felsefe Öğretim Programı, s.70', true, now(), now()),
  ('c6110000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c8', 11, 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'c4110000-0000-4000-8000-000000000006', NULL, 'FEL.11.6.2', 'Hukuk sorunları üzerine felsefi düşünce ortaya koyabilme', 2, 'TYMM 2026 Felsefe Öğretim Programı, s.70', true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 4. MIGRATION HISTORY — idempotent kayıt (psql koşumunda statements=NULL;
--    CLI koşan ortamda CLI'ın kendi kaydı varsa bu INSERT atlanır).
-- ============================================================
insert into supabase_migrations.schema_migrations (version, name, statements)
select '147', '147_curriculum_felsefe_tymm2026_agac', NULL
 where not exists (
   select 1 from supabase_migrations.schema_migrations where version = '147'
 );

-- ============================================================
-- 5. SON DENETİM (transaction içi; beklentiden sapan durum COMMIT'i durdurur)
-- ============================================================
DO $final$
DECLARE
  v_t integer; v_s integer; v_o integer; v_null_t integer; v_null_s integer; v_linked integer;
BEGIN
  SELECT count(*) INTO v_t FROM public.topics WHERE subject_id = 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb';
  SELECT count(*) INTO v_s FROM public.subtopics s JOIN public.topics t ON t.id = s.topic_id
   WHERE t.subject_id = 'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb';
  SELECT count(*),
         count(*) FILTER (WHERE topic_id IS NULL),
         count(*) FILTER (WHERE subtopic_id IS NULL),
         count(*) FILTER (WHERE topic_id IS NOT NULL)
    INTO v_o, v_null_t, v_null_s, v_linked
    FROM public.curriculum_outcomes WHERE outcome_code LIKE 'FEL.%';
  IF v_t <> 15 OR v_s <> 36 OR v_o <> 22 OR v_null_t <> 0 OR v_null_s <> 22 OR v_linked <> 22 THEN
    RAISE EXCEPTION 'FINAL_147: beklenen 15/36/22 (topic/subtopic/outcome), topic-bağlı=22, NULL subtopic=22; bulunan %/%/%/%/%/%', v_t, v_s, v_o, v_linked, v_null_s, v_null_t;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.curriculum_versions
                 WHERE id = 'a1000000-0000-4000-8000-0000000000c8' AND framework = 'tymm_2026_felsefe') THEN
    RAISE EXCEPTION 'FINAL_147: sürüm satırı (a1000000-0000-4000-8000-0000000000c8) yok — beklenmeyen durum.';
  END IF;
END
$final$;

COMMIT;
