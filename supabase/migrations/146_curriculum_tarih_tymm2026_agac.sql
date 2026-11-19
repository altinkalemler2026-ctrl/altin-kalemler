-- ============================================================
-- 146_curriculum_tarih_tymm2026_agac.sql
-- Altın Kalemler — CURRICULUM-ALL-01 Tarih dilimi: TYMM 2026 Tarih
--   müfredat ağacının (9 ünite + 38 İçerik Çerçevesi maddesi +
--   38 yeni outcome) YÜKLENMESİ ve
--   tymm_2026_tarih curriculum_versions satırının OLUŞTURULMASI.
--
-- KULLANICI ONAYLI KAPSAM (2026-10-27)
--   - 1 sürüm + 9 topic + 38 subtopic + 38 outcome YÜKLENİR (9. sınıf: 3 ünite / 13 madde / 13 çıktı; 10. sınıf: 3 ünite / 14 madde / 14 çıktı; 11. sınıf: 3 ünite / 11 madde / 11 çıktı).
--   - Tarih için DB'de ÖNCEDEN TAR.* outcome / topic / subtopic YOKTUR
--     (2026-10-27 salt-okunur ölçüm; dry-run eşleşen=0). Bu yüzden "mevcut
--     kayıt linkleme UPDATE'i" YOKTUR — migration salt EKLEME yapar.
--   - Sınıf kapsamı 9-11 (resmî program bu sınıfları kapsar; kapsam
--     dışı sınıflar için satır UYDURULMAZ — kanonik dosya §1).
--
-- KAYNAK (yalnız resmî)
--   Türkiye Yüzyılı Maarif Modeli — Ortaöğretim Tarih Dersi (9-11) Öğretim
--   Programı (2026); PDF basılı sayfa numaraları.
--   Yerel: docs/references/mufredat/2026-2027/tymm-2026-tarih-9-11.pdf
--   Ağaç:  docs/question-production/curriculum-mapping/tarih-9-11-kanonik-esleme-v1.md
--   Dry-run: scripts/mufredat-dry-run.ts --ders=tarih → tarih-dry-run-sonuc.md
--   (85/85 veri satırı, 9/38/38, eşleşen 0, metin farkı 0, engelli 0)
--
-- UUID ŞEMASI (142/145 deseni; aileler DB envanteriyle çakışmasız seçildi)
--   Mevcut deterministik aileler: a1=versions, a2=schedule_profiles, a3=MAT topics,
--   a4=schedule_items, a5=FIZ topics, a6=MAT subtopics, a7=MAT outcomes,
--   a8=FIZ subtopics, a9=FIZ outcomes; Kimya=b1/b2/b3 (c4 sürüm), Biyoloji=b4/b5/b6
--   (c5), Coğrafya=b7/b8/b9 (c6). YENİ AİLELER (topics/subtopics/outcomes +
--   curriculum_schedule_* tablolarında id LIKE 'c%' = 0 doğrulandı —
--   2026-10-27 salt-okunur tarama):
--   Tarih topic    : c1 + GG (sınıf) → c1GG0000-0000-4000-8000-0000000000NN
--   Tarih subtopic : c2 + GG (sınıf) → c2GG0000-0000-4000-8000-0000000000NN
--   Tarih outcome : c3 + GG (sınıf) → c3GG0000-0000-4000-8000-0000000000NN
--     (NN = sınıf içi (ünite, k) sıralamasında kesintisiz sayaç, 001'den başlar)
--   NOT: 'c' ailesi topics/subtopics/outcomes tablolarında BOŞTUR; sürüm
--   id'lerindeki 'cN' SONEKİ (a1 ailesi …0000000000c1..c6) farklı konumdadır
--   ve çakışmaz — iki gösterim migration 145 başlığında da birlikte belgelenir.
--   Sürüm id: a1000000-0000-4000-8000-0000000000c7 (tymm_2026_tarih; a1 ailesinde c6'dan sonraki ilk boş değer).
--   Subject id: 4245101d-6269-40d0-a663-2016ab9d1ee4 (Tarih, migration 045).
--
-- AD / SLUG / SIRA KARARLARI (142/145 birebir)
--   - topic.name: 'TAR.GG.N <ÜNİTE ADI>' deseni; ünite adı PDF'teki resmî
--     büyük harfli başlıktır ('N. ÜNİTE: ' öneki atılır).
--   - topic.slug : tarih-GG-N-<ünite-adı-slug>  (dry-run öneri formülüyle aynı).
--     DB kısıtı: UNIQUE (curriculum_version_id, subject_id, grade_level, slug).
--   - subtopic.name: İçerik Çerçevesi kutusundaki basılı madde (resmî).
--   - subtopic.slug: <topic-slug>-<madde-slug> (112 matematik deseni; UNIQUE (topic_id, slug)).
--   - subtopic.sort_order: sınıf içi kesintisiz (kutu sırası; ünite değişince sıfırlanmaz).
--   - outcome.sort_order: kodun son basamağı k (ünite-içi sıra) — 125/142 sözleşmesi.
--   - outcome.subtopic_id: NULL (kaynakta çıktı→alt konu ilişkisi numaralandırılmamıştır;
--     yakınlık/sıra/isim benzerliğiyle atama YASAKTIR — kanonik dosya §2, BLOKAJ-1 kuralı).
--   - source_reference: 'TYMM 2026 Tarih Öğretim Programı, s.NN' (142/145 deseni); NN = kazanım bloğunun
--     basılı sayfası (kanonik dosya §4/§5).
--
-- SÜRÜM SATIRI (125 fizik deseni; 145 ile aynı durum)
--   Bu ders için curriculum_versions satırı YOKTU (dry-run: 'BULUNAMADI').
--   Sürüm INSERT'i bölüm 0.5'tedir: is_default=false (yıl-tek-default kısmi
--   indeksi bozulmaz), UNIQUE (academic_year, framework) uyumlu.
--   published_at: resmî URL zaman damgası (2026691344767 → 2026-06-09; 125/145 yöntemi).
--
-- İDEMPOTENCE
--   - Tüm INSERT'ler ON CONFLICT (id) DO NOTHING → tekrar koşum SIFIR yeni satır.
--   - GUARD: ağaç ya (0,0,0) (ilk uygulama) ya (9/38/38) dolu hâlde
--     olmalı; karışık/kısmi durum fail-closed durur. Dolu hâlde tüm id'ler tanınır.
--   - outcome_code'da UNIQUE KISIT YOKTUR (yalnız idx_curriculum_outcomes_code normal
--     indeks); mükerrer kod riski GUARD'ın benzersiz-kod denetimi + deterministik id ile
--     kapanır (142'nin iki katmanlı koruması).
--   - History: supabase_migrations.schema_migrations'a version='146' kaydı WHERE NOT
--     EXISTS ile idempotent eklenir; statements=NULL (psql koşumunda dosya kendi metnini
--     içine koyamaz; CLI uygulayan ortamda CLI statements'i doldurur — 142 notu birebir).
--
-- GERİ DÖNÜŞ: scripts/tarih-mufredat-geri-donus.sql (tek transaction;
--   38 outcome DELETE → 38 subtopic DELETE → 9 topic DELETE → sürüm satırı DELETE →
--   146 history DELETE; FK sırası korunur, fail-closed üçüncü-taraf referans taraması
--   içerir). Uygulama öncesi yedek (boş ön-durum kanıtı):
--   docs/references/mufredat/yedekler/tarih-on-yedek-20261027.sql
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
  IF NOT EXISTS (SELECT 1 FROM public.subjects WHERE id = '4245101d-6269-40d0-a663-2016ab9d1ee4') THEN
    RAISE EXCEPTION 'GUARD_146: Tarih subject satırı yok — migration 045 uygulanmamış ortam.';
  END IF;

  -- Sürüm satırı: ya hiç yok (ilk uygulama) ya da TAM bu çift var (tekrar koşum).
  SELECT count(*) INTO v_surum FROM public.curriculum_versions
   WHERE framework = 'tymm_2026_tarih' OR id = 'a1000000-0000-4000-8000-0000000000c7';
  IF v_surum > 0 THEN
    IF NOT EXISTS (SELECT 1 FROM public.curriculum_versions
                   WHERE id = 'a1000000-0000-4000-8000-0000000000c7' AND framework = 'tymm_2026_tarih'
                     AND academic_year = '2026-2027' AND is_default = false) THEN
      RAISE EXCEPTION 'GUARD_146: tymm_2026_tarih/a1000000-0000-4000-8000-0000000000c7 sürüm satırı çelişkili (farklı id/framework/is_default) — fail-closed dur.';
    END IF;
  END IF;

  -- Ağaç durumu: ya boş ya tam dolu. Kısmi/yabancı durum fail-closed.
  SELECT count(*) INTO v_topic_sayi FROM public.topics
   WHERE subject_id = '4245101d-6269-40d0-a663-2016ab9d1ee4';
  SELECT count(*) INTO v_subtopic_sayi FROM public.subtopics s
   JOIN public.topics t ON t.id = s.topic_id
   WHERE t.subject_id = '4245101d-6269-40d0-a663-2016ab9d1ee4';
  SELECT count(*) INTO v_outcome_sayi FROM public.curriculum_outcomes
   WHERE outcome_code LIKE 'TAR.%';
  IF NOT (v_topic_sayi = 0 AND v_subtopic_sayi = 0 AND v_outcome_sayi = 0)
     AND NOT (v_topic_sayi = 9 AND v_subtopic_sayi = 38 AND v_outcome_sayi = 38) THEN
    RAISE EXCEPTION 'GUARD_146: Tarih ağacı kısmi/yabancı durumda (topics=%, subtopics=%, outcomes=%; beklenen 0/0/0 veya 9/38/38) — fail-closed dur.', v_topic_sayi, v_subtopic_sayi, v_outcome_sayi;
  END IF;

  -- Dolu hâl: id'lerin tamamı bu migration'ın deterministik kümesinden mi?
  IF v_topic_sayi = 9 THEN
    SELECT count(*) INTO v_yabanci FROM public.topics
     WHERE subject_id = '4245101d-6269-40d0-a663-2016ab9d1ee4' AND id NOT IN (
       'c1090000-0000-4000-8000-000000000001',
       'c1090000-0000-4000-8000-000000000002',
       'c1090000-0000-4000-8000-000000000003',
       'c1100000-0000-4000-8000-000000000001',
       'c1100000-0000-4000-8000-000000000002',
       'c1100000-0000-4000-8000-000000000003',
       'c1110000-0000-4000-8000-000000000001',
       'c1110000-0000-4000-8000-000000000002',
       'c1110000-0000-4000-8000-000000000003'
    );
    IF v_yabanci > 0 THEN
      RAISE EXCEPTION 'GUARD_146: % yabancı Tarih topic id''si bulundu — fail-closed dur.', v_yabanci;
    END IF;
    SELECT count(*) INTO v_yabanci FROM public.subtopics s
     JOIN public.topics t ON t.id = s.topic_id
     WHERE t.subject_id = '4245101d-6269-40d0-a663-2016ab9d1ee4' AND s.id NOT IN (
       'c2090000-0000-4000-8000-000000000001',
       'c2090000-0000-4000-8000-000000000002',
       'c2090000-0000-4000-8000-000000000003',
       'c2090000-0000-4000-8000-000000000004',
       'c2090000-0000-4000-8000-000000000005',
       'c2090000-0000-4000-8000-000000000006',
       'c2090000-0000-4000-8000-000000000007',
       'c2090000-0000-4000-8000-000000000008',
       'c2090000-0000-4000-8000-000000000009',
       'c2090000-0000-4000-8000-000000000010',
       'c2090000-0000-4000-8000-000000000011',
       'c2090000-0000-4000-8000-000000000012',
       'c2090000-0000-4000-8000-000000000013',
       'c2100000-0000-4000-8000-000000000001',
       'c2100000-0000-4000-8000-000000000002',
       'c2100000-0000-4000-8000-000000000003',
       'c2100000-0000-4000-8000-000000000004',
       'c2100000-0000-4000-8000-000000000005',
       'c2100000-0000-4000-8000-000000000006',
       'c2100000-0000-4000-8000-000000000007',
       'c2100000-0000-4000-8000-000000000008',
       'c2100000-0000-4000-8000-000000000009',
       'c2100000-0000-4000-8000-000000000010',
       'c2100000-0000-4000-8000-000000000011',
       'c2100000-0000-4000-8000-000000000012',
       'c2100000-0000-4000-8000-000000000013',
       'c2100000-0000-4000-8000-000000000014',
       'c2110000-0000-4000-8000-000000000001',
       'c2110000-0000-4000-8000-000000000002',
       'c2110000-0000-4000-8000-000000000003',
       'c2110000-0000-4000-8000-000000000004',
       'c2110000-0000-4000-8000-000000000005',
       'c2110000-0000-4000-8000-000000000006',
       'c2110000-0000-4000-8000-000000000007',
       'c2110000-0000-4000-8000-000000000008',
       'c2110000-0000-4000-8000-000000000009',
       'c2110000-0000-4000-8000-000000000010',
       'c2110000-0000-4000-8000-000000000011'
    );
    IF v_yabanci > 0 THEN
      RAISE EXCEPTION 'GUARD_146: % yabancı Tarih subtopic id''si bulundu — fail-closed dur.', v_yabanci;
    END IF;
    SELECT count(*), count(*) FILTER (WHERE id IN (
       'c3090000-0000-4000-8000-000000000001',
       'c3090000-0000-4000-8000-000000000002',
       'c3090000-0000-4000-8000-000000000003',
       'c3090000-0000-4000-8000-000000000004',
       'c3090000-0000-4000-8000-000000000005',
       'c3090000-0000-4000-8000-000000000006',
       'c3090000-0000-4000-8000-000000000007',
       'c3090000-0000-4000-8000-000000000008',
       'c3090000-0000-4000-8000-000000000009',
       'c3090000-0000-4000-8000-000000000010',
       'c3090000-0000-4000-8000-000000000011',
       'c3090000-0000-4000-8000-000000000012',
       'c3090000-0000-4000-8000-000000000013',
       'c3100000-0000-4000-8000-000000000001',
       'c3100000-0000-4000-8000-000000000002',
       'c3100000-0000-4000-8000-000000000003',
       'c3100000-0000-4000-8000-000000000004',
       'c3100000-0000-4000-8000-000000000005',
       'c3100000-0000-4000-8000-000000000006',
       'c3100000-0000-4000-8000-000000000007',
       'c3100000-0000-4000-8000-000000000008',
       'c3100000-0000-4000-8000-000000000009',
       'c3100000-0000-4000-8000-000000000010',
       'c3100000-0000-4000-8000-000000000011',
       'c3100000-0000-4000-8000-000000000012',
       'c3100000-0000-4000-8000-000000000013',
       'c3100000-0000-4000-8000-000000000014',
       'c3110000-0000-4000-8000-000000000001',
       'c3110000-0000-4000-8000-000000000002',
       'c3110000-0000-4000-8000-000000000003',
       'c3110000-0000-4000-8000-000000000004',
       'c3110000-0000-4000-8000-000000000005',
       'c3110000-0000-4000-8000-000000000006',
       'c3110000-0000-4000-8000-000000000007',
       'c3110000-0000-4000-8000-000000000008',
       'c3110000-0000-4000-8000-000000000009',
       'c3110000-0000-4000-8000-000000000010',
       'c3110000-0000-4000-8000-000000000011'
    )), count(DISTINCT outcome_code) INTO v_outcome_sayi, v_tanimli, v_benzersiz
      FROM public.curriculum_outcomes WHERE outcome_code LIKE 'TAR.%';
    IF v_outcome_sayi <> 38 OR v_tanimli <> 38 OR v_benzersiz <> 38 THEN
      RAISE EXCEPTION 'GUARD_146: TAR.* outcomes=% (tanınan id=%, benzersiz kod=%; beklenen 38/38/38) — id/kod drifti, fail-closed dur.', v_outcome_sayi, v_tanimli, v_benzersiz;
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
  'a1000000-0000-4000-8000-0000000000c7',
  '2026-2027',
  'tymm_2026_tarih',
  'Türkiye Yüzyılı Maarif Modeli Tarih Dersi (9, 10 ve 11. Sınıflar) Öğretim Programı (2026)',
  'https://mufredat.meb.gov.tr/Dosyalar/2026691344767-tarihd%C3%B6p.pdf',
  '2026-06-09',  -- mufredat.meb.gov.tr resmî URL zaman damgası (2026691344767 → 2026-06-09; 125/145 yöntemi)
  true, false, now(), now()
)
on conflict (id) do nothing;

-- ============================================================
-- 1. TOPICS (9) — TAR.GG.N <ÜNİTE ADI>; sort_order = resmî ünite no (sınıf içi)
--    UNIQUE (curriculum_version_id, subject_id, grade_level, slug) koruması:
--    farklı id ile aynı slug varsa INSERT doğal olarak HATA verir (fail-closed).
-- ============================================================
insert into public.topics (
  id, subject_id, grade_level, name, slug, sort_order,
  is_active, curriculum_version_id, created_at, updated_at
) values
  ('c1090000-0000-4000-8000-000000000001', '4245101d-6269-40d0-a663-2016ab9d1ee4', 9, 'TAR.9.1 GEÇMİŞİN İNŞA SÜRECİNDE TARİH', 'tarih-9-1-gecmisin-insa-surecinde-tarih', 1, true, 'a1000000-0000-4000-8000-0000000000c7', now(), now()),
  ('c1090000-0000-4000-8000-000000000002', '4245101d-6269-40d0-a663-2016ab9d1ee4', 9, 'TAR.9.2 ESKİ ÇAĞ MEDENİYETLERİ', 'tarih-9-2-eski-cag-medeniyetleri', 2, true, 'a1000000-0000-4000-8000-0000000000c7', now(), now()),
  ('c1090000-0000-4000-8000-000000000003', '4245101d-6269-40d0-a663-2016ab9d1ee4', 9, 'TAR.9.3 ORTA ÇAĞ MEDENİYETLERİ', 'tarih-9-3-orta-cag-medeniyetleri', 3, true, 'a1000000-0000-4000-8000-0000000000c7', now(), now()),
  ('c1100000-0000-4000-8000-000000000001', '4245101d-6269-40d0-a663-2016ab9d1ee4', 10, 'TAR.10.1 TÜRKİSTAN’DAN TÜRKİYE’YE (1040-1299)', 'tarih-10-1-turkistandan-turkiyeye-1040-1299', 1, true, 'a1000000-0000-4000-8000-0000000000c7', now(), now()),
  ('c1100000-0000-4000-8000-000000000002', '4245101d-6269-40d0-a663-2016ab9d1ee4', 10, 'TAR.10.2 BEYLİKTEN DEVLETE OSMANLI (1299-1453)', 'tarih-10-2-beylikten-devlete-osmanli-1299-1453', 2, true, 'a1000000-0000-4000-8000-0000000000c7', now(), now()),
  ('c1100000-0000-4000-8000-000000000003', '4245101d-6269-40d0-a663-2016ab9d1ee4', 10, 'TAR.10.3 CİHAN DEVLETİ OSMANLI (1453-1683)', 'tarih-10-3-cihan-devleti-osmanli-1453-1683', 3, true, 'a1000000-0000-4000-8000-0000000000c7', now(), now()),
  ('c1110000-0000-4000-8000-000000000001', '4245101d-6269-40d0-a663-2016ab9d1ee4', 11, 'TAR.11.1 DEĞİŞEN DÜNYADA OSMANLI (1683-1789)', 'tarih-11-1-degisen-dunyada-osmanli-1683-1789', 1, true, 'a1000000-0000-4000-8000-0000000000c7', now(), now()),
  ('c1110000-0000-4000-8000-000000000002', '4245101d-6269-40d0-a663-2016ab9d1ee4', 11, 'TAR.11.2 DÖNÜŞÜM SÜRECİNDE OSMANLI (1789-1908)', 'tarih-11-2-donusum-surecinde-osmanli-1789-1908', 2, true, 'a1000000-0000-4000-8000-0000000000c7', now(), now()),
  ('c1110000-0000-4000-8000-000000000003', '4245101d-6269-40d0-a663-2016ab9d1ee4', 11, 'TAR.11.3 SAVAŞLAR SARMALINDA OSMANLI (1908-1918)', 'tarih-11-3-savaslar-sarmalinda-osmanli-1908-1918', 3, true, 'a1000000-0000-4000-8000-0000000000c7', now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 2. SUBTOPICS (38) — İçerik Çerçevesi maddeleri (resmî, basılı sıra);
--    sort_order sınıf içi kesintisiz (9:13, 10:14, 11:11);
--    subtopic_id bağlantısı çıktılara AÇILMAZ (kaynak numaralandırmamış).
-- ============================================================
insert into public.subtopics (
  id, topic_id, name, slug, sort_order, is_active, created_at, updated_at
) values
  ('c2090000-0000-4000-8000-000000000001', 'c1090000-0000-4000-8000-000000000001', 'Tarih Öğrenmenin Faydaları', 'tarih-9-1-gecmisin-insa-surecinde-tarih-tarih-ogrenmenin-faydalari', 1, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000002', 'c1090000-0000-4000-8000-000000000001', 'Tarihin Doğası', 'tarih-9-1-gecmisin-insa-surecinde-tarih-tarihin-dogasi', 2, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000003', 'c1090000-0000-4000-8000-000000000001', 'Tarihsel Bilginin Üretim Süreci', 'tarih-9-1-gecmisin-insa-surecinde-tarih-tarihsel-bilginin-uretim-sureci', 3, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000004', 'c1090000-0000-4000-8000-000000000001', 'Tarih Araştırma ve Yazımında Dijitalleşme', 'tarih-9-1-gecmisin-insa-surecinde-tarih-tarih-arastirma-ve-yaziminda-dijitallesme', 4, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000005', 'c1090000-0000-4000-8000-000000000002', 'Tarım Devrimi’nin Eski Çağ Medeniyetlerindeki Yerleşmeye ve Ekonomiye Etkisi', 'tarih-9-2-eski-cag-medeniyetleri-tarim-devriminin-eski-cag-medeniyetlerindeki-yerlesmeye-ve-ekonomiye-etkisi', 5, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000006', 'c1090000-0000-4000-8000-000000000002', 'Eski Çağ Medeniyetlerinde Yönetim ve Ordu', 'tarih-9-2-eski-cag-medeniyetleri-eski-cag-medeniyetlerinde-yonetim-ve-ordu', 6, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000007', 'c1090000-0000-4000-8000-000000000002', 'Eski Çağ Medeniyetlerinde Hukuk', 'tarih-9-2-eski-cag-medeniyetleri-eski-cag-medeniyetlerinde-hukuk', 7, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000008', 'c1090000-0000-4000-8000-000000000002', 'Eski Çağ’da İnançlar ile Bilim ve Sanat Anlayışları', 'tarih-9-2-eski-cag-medeniyetleri-eski-cagda-inanclar-ile-bilim-ve-sanat-anlayislari', 8, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000009', 'c1090000-0000-4000-8000-000000000002', 'Türklerde Konargöçer Yaşam', 'tarih-9-2-eski-cag-medeniyetleri-turklerde-konargocer-yasam', 9, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000010', 'c1090000-0000-4000-8000-000000000003', 'Orta Çağ’da Yaşanan Kitlesel Göçler', 'tarih-9-3-orta-cag-medeniyetleri-orta-cagda-yasanan-kitlesel-gocler', 10, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000011', 'c1090000-0000-4000-8000-000000000003', 'Orta Çağ’daki Başlıca Devletlerin Yönetim ve Ordu Yapıları', 'tarih-9-3-orta-cag-medeniyetleri-orta-cagdaki-baslica-devletlerin-yonetim-ve-ordu-yapilari', 11, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000012', 'c1090000-0000-4000-8000-000000000003', 'Orta Çağ’daki Ticaret Yolları', 'tarih-9-3-orta-cag-medeniyetleri-orta-cagdaki-ticaret-yollari', 12, true, now(), now()),
  ('c2090000-0000-4000-8000-000000000013', 'c1090000-0000-4000-8000-000000000003', 'Orta Çağ’daki Başlıca Medeniyet Havzalarında Bilim, Kültür ve Sanat', 'tarih-9-3-orta-cag-medeniyetleri-orta-cagdaki-baslica-medeniyet-havzalarinda-bilim-kultur-ve-sanat', 13, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000001', 'c1100000-0000-4000-8000-000000000001', 'Türkistan’dan Türkiye’ye Uzanan Süreçte Meydana Gelen Önemli Askerî Mücadeleler', 'tarih-10-1-turkistandan-turkiyeye-1040-1299-turkistandan-turkiyeye-uzanan-surecte-meydana-gelen-onemli-askeri-mucadeleler', 1, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000002', 'c1100000-0000-4000-8000-000000000001', 'Türkistan’dan Türkiye’ye Uzanan Süreçte Türk Devlet ve Ordu Teşkilatında Meydana Gelen Değişim', 'tarih-10-1-turkistandan-turkiyeye-1040-1299-turkistandan-turkiyeye-uzanan-surecte-turk-devlet-ve-ordu-teskilatinda-meydana-gelen-degisim', 2, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000003', 'c1100000-0000-4000-8000-000000000001', 'Türkistan’dan Türkiye’ye Uzanan Süreçte Türklerin Sosyal Yaşamları ve Ekonomik Faaliyetleri', 'tarih-10-1-turkistandan-turkiyeye-1040-1299-turkistandan-turkiyeye-uzanan-surecte-turklerin-sosyal-yasamlari-ve-ekonomik-faaliyetleri', 3, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000004', 'c1100000-0000-4000-8000-000000000001', 'Türk-İslam Medeniyetinin Bilim, Kültür, Eğitim ve Sanat Alanlarında Ortaya Çıkardığı Etkiler', 'tarih-10-1-turkistandan-turkiyeye-1040-1299-turk-islam-medeniyetinin-bilim-kultur-egitim-ve-sanat-alanlarinda-ortaya-cikardigi-etkiler', 4, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000005', 'c1100000-0000-4000-8000-000000000002', 'Osmanlı Devleti’nin Kuruluşuna Dair Farklı Görüşler', 'tarih-10-2-beylikten-devlete-osmanli-1299-1453-osmanli-devletinin-kurulusuna-dair-farkli-gorusler', 5, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000006', 'c1100000-0000-4000-8000-000000000002', 'Osmanlı Devleti’nin Anadolu ve Rumeli’deki Siyasi ve Askerî Mücadeleleri', 'tarih-10-2-beylikten-devlete-osmanli-1299-1453-osmanli-devletinin-anadolu-ve-rumelideki-siyasi-ve-askeri-mucadeleleri', 6, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000007', 'c1100000-0000-4000-8000-000000000002', 'Osmanlı Devleti’nin Devletleşme Süreci ile Ordu, Hukuk ve Toprak Sistemleri Arasındaki İlişkiler', 'tarih-10-2-beylikten-devlete-osmanli-1299-1453-osmanli-devletinin-devletlesme-sureci-ile-ordu-hukuk-ve-toprak-sistemleri-arasindaki-iliskiler', 7, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000008', 'c1100000-0000-4000-8000-000000000002', 'Osmanlı Devleti’nin Fethettiği Topraklarda Kalıcı Olabilmek İçin İzlediği Politikalar', 'tarih-10-2-beylikten-devlete-osmanli-1299-1453-osmanli-devletinin-fethettigi-topraklarda-kalici-olabilmek-icin-izledigi-politikalar', 8, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000009', 'c1100000-0000-4000-8000-000000000002', 'Osmanlı Devleti’nin İlim ve İrfan Geleneğinin Oluşmasında Mekânların ve Kişilerin Etkisi', 'tarih-10-2-beylikten-devlete-osmanli-1299-1453-osmanli-devletinin-ilim-ve-irfan-geleneginin-olusmasinda-mekanlarin-ve-kisilerin-etkisi', 9, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000010', 'c1100000-0000-4000-8000-000000000003', '1453-1683 Yılları Arasındaki Siyasi ve Askerî Mücadeleler', 'tarih-10-3-cihan-devleti-osmanli-1453-1683-1453-1683-yillari-arasindaki-siyasi-ve-askeri-mucadeleler', 10, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000011', 'c1100000-0000-4000-8000-000000000003', 'Osmanlı Devleti’nin Yönetim ve Ordu Yapısında Meydana Gelen Değişim', 'tarih-10-3-cihan-devleti-osmanli-1453-1683-osmanli-devletinin-yonetim-ve-ordu-yapisinda-meydana-gelen-degisim', 11, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000012', 'c1100000-0000-4000-8000-000000000003', 'Avrupa’nın Sömürgeci Politikalarının Etkileri', 'tarih-10-3-cihan-devleti-osmanli-1453-1683-avrupanin-somurgeci-politikalarinin-etkileri', 12, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000013', 'c1100000-0000-4000-8000-000000000003', 'Osmanlı Devleti’ndeki Önemli İsyanların Neden ve Sonuçları', 'tarih-10-3-cihan-devleti-osmanli-1453-1683-osmanli-devletindeki-onemli-isyanlarin-neden-ve-sonuclari', 13, true, now(), now()),
  ('c2100000-0000-4000-8000-000000000014', 'c1100000-0000-4000-8000-000000000003', '1453-1683 Yılları Arasında Osmanlı Devleti’nde Bilim, Kültür, Eğitim ve Sanat Alanında Yaşanan Gelişmeler', 'tarih-10-3-cihan-devleti-osmanli-1453-1683-1453-1683-yillari-arasinda-osmanli-devletinde-bilim-kultur-egitim-ve-sanat-alaninda-yasanan-gelismeler', 14, true, now(), now()),
  ('c2110000-0000-4000-8000-000000000001', 'c1110000-0000-4000-8000-000000000001', 'Osmanlı Devleti’nin 1683-1789 Yılları Arasındaki Siyasi ve Askerî Mücadeleleri', 'tarih-11-1-degisen-dunyada-osmanli-1683-1789-osmanli-devletinin-1683-1789-yillari-arasindaki-siyasi-ve-askeri-mucadeleleri', 1, true, now(), now()),
  ('c2110000-0000-4000-8000-000000000002', 'c1110000-0000-4000-8000-000000000001', 'Lale Devri’nin Devlet ve Toplum Hayatına Etkileri', 'tarih-11-1-degisen-dunyada-osmanli-1683-1789-lale-devrinin-devlet-ve-toplum-hayatina-etkileri', 2, true, now(), now()),
  ('c2110000-0000-4000-8000-000000000003', 'c1110000-0000-4000-8000-000000000001', '1755 Lizbon ve 1766 İstanbul Depremlerinin Etkileri', 'tarih-11-1-degisen-dunyada-osmanli-1683-1789-1755-lizbon-ve-1766-istanbul-depremlerinin-etkileri', 3, true, now(), now()),
  ('c2110000-0000-4000-8000-000000000004', 'c1110000-0000-4000-8000-000000000001', 'Sanayi Devrimi’nin Meydana Getirdiği Siyasi, Sosyal ve Ekonomik Değişim', 'tarih-11-1-degisen-dunyada-osmanli-1683-1789-sanayi-devriminin-meydana-getirdigi-siyasi-sosyal-ve-ekonomik-degisim', 4, true, now(), now()),
  ('c2110000-0000-4000-8000-000000000005', 'c1110000-0000-4000-8000-000000000002', 'Fransız İhtilali’nin Devlet ve Toplum Hayatında Meydana Getirdiği Değişim', 'tarih-11-2-donusum-surecinde-osmanli-1789-1908-fransiz-ihtilalinin-devlet-ve-toplum-hayatinda-meydana-getirdigi-degisim', 5, true, now(), now()),
  ('c2110000-0000-4000-8000-000000000006', 'c1110000-0000-4000-8000-000000000002', '1789-1908 Yılları Arasında Osmanlı Devleti’nde Meydana Gelen Siyasi, Askerî ve İdari Gelişmeler', 'tarih-11-2-donusum-surecinde-osmanli-1789-1908-1789-1908-yillari-arasinda-osmanli-devletinde-meydana-gelen-siyasi-askeri-ve-idari-gelismeler', 6, true, now(), now()),
  ('c2110000-0000-4000-8000-000000000007', 'c1110000-0000-4000-8000-000000000002', '1789-1908 Yılları Arasında Osmanlı Devleti’nde Bilim, Sanat ve Teknoloji Alanlarında Meydana Gelen Gelişmeler', 'tarih-11-2-donusum-surecinde-osmanli-1789-1908-1789-1908-yillari-arasinda-osmanli-devletinde-bilim-sanat-ve-teknoloji-alanlarinda-meydana-gelen-gelismeler', 7, true, now(), now()),
  ('c2110000-0000-4000-8000-000000000008', 'c1110000-0000-4000-8000-000000000002', 'Osmanlı Devleti’nde Sanayileşme Çabaları', 'tarih-11-2-donusum-surecinde-osmanli-1789-1908-osmanli-devletinde-sanayilesme-cabalari', 8, true, now(), now()),
  ('c2110000-0000-4000-8000-000000000009', 'c1110000-0000-4000-8000-000000000003', '1908-1918 Yılları Arasında Osmanlı Devleti’nde Meydana Gelen Siyasi ve Askerî Gelişmeler', 'tarih-11-3-savaslar-sarmalinda-osmanli-1908-1918-1908-1918-yillari-arasinda-osmanli-devletinde-meydana-gelen-siyasi-ve-askeri-gelismeler', 9, true, now(), now()),
  ('c2110000-0000-4000-8000-000000000010', 'c1110000-0000-4000-8000-000000000003', '1908-1918 Yılları Arasında Gerçekleşen Kitlesel Göç ve Salgınlar', 'tarih-11-3-savaslar-sarmalinda-osmanli-1908-1918-1908-1918-yillari-arasinda-gerceklesen-kitlesel-goc-ve-salginlar', 10, true, now(), now()),
  ('c2110000-0000-4000-8000-000000000011', 'c1110000-0000-4000-8000-000000000003', 'Osmanlı Devleti’nin İnsanlık Tarihine Katkıları', 'tarih-11-3-savaslar-sarmalinda-osmanli-1908-1918-osmanli-devletinin-insanlik-tarihine-katkilari', 11, true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 3. YENİ TAR.* OUTCOMES (38) — salt ekleme (mevcut kayıt YOKTUR).
--    sort_order = k (ünite-içi; 125 sözleşmesi). subtopic_id = NULL
--    (kaynakta numaralandırılmamış — kasıtlı ve onaylı).
-- ============================================================
insert into public.curriculum_outcomes (
  id, curriculum_version_id, grade_level, subject_id, topic_id, subtopic_id,
  outcome_code, outcome_text, sort_order, source_reference, is_active, created_at, updated_at
) values
  ('c3090000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000001', NULL, 'TAR.9.1.1', 'Tarih öğrenmenin bireye ve topluma faydalarını yorumlayabilme', 1, 'TYMM 2026 Tarih Öğretim Programı, s.17', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000001', NULL, 'TAR.9.1.2', 'Tarihin doğasını farklı kaynaklar üzerinden inceleyebilme', 2, 'TYMM 2026 Tarih Öğretim Programı, s.17', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000001', NULL, 'TAR.9.1.3', 'Tarihsel bilginin üretim sürecini çözümleyebilme', 3, 'TYMM 2026 Tarih Öğretim Programı, s.17', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000001', NULL, 'TAR.9.1.4', 'Dijitalleşmenin tarih araştırma ve yazımının dönüşümüne etkisini değerlendirebilme', 4, 'TYMM 2026 Tarih Öğretim Programı, s.17', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000002', NULL, 'TAR.9.2.1', 'Tarım Devrimi’nin Eski Çağ medeniyetlerindeki yerleşmeye ve ekonomik faaliyetlere etkisini değerlendirebilme', 1, 'TYMM 2026 Tarih Öğretim Programı, s.22', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000002', NULL, 'TAR.9.2.2', 'Eski Çağ’daki farklı medeniyetlerin yönetim ve ordu sistemlerini özetleyebilme', 2, 'TYMM 2026 Tarih Öğretim Programı, s.22', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000002', NULL, 'TAR.9.2.3', 'Eski Çağ medeniyetlerinde hukukun toplumsal düzeni sağlamadaki rolünü sorgulayabilme', 3, 'TYMM 2026 Tarih Öğretim Programı, s.22', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000002', NULL, 'TAR.9.2.4', 'Eski Çağ toplumlarındaki inançlar ile bilim ve sanat anlayışları arasındaki ilişkiyi yorumlayabilme', 4, 'TYMM 2026 Tarih Öğretim Programı, s.22', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000002', NULL, 'TAR.9.2.5', 'Türklerde konargöçer yaşama ilişkin bakış açısı geliştirebilme', 5, 'TYMM 2026 Tarih Öğretim Programı, s.22', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000003', NULL, 'TAR.9.3.1', 'Orta Çağ’da yaşanan kitlesel göçlerin Avrupa ve Asya’da oluşturduğu değişimi neden ve sonuçlarıyla birlikte yorumlayabilme', 1, 'TYMM 2026 Tarih Öğretim Programı, s.28', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000003', NULL, 'TAR.9.3.2', 'Orta Çağ’daki başlıca devletlerin yönetim ve ordu yapılarını karşılaştırabilme', 2, 'TYMM 2026 Tarih Öğretim Programı, s.28', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000003', NULL, 'TAR.9.3.3', 'Orta Çağ’daki ticaret yollarının kendi çevresinde meydana getirdiği etkiyi sorgulayabilme', 3, 'TYMM 2026 Tarih Öğretim Programı, s.28', true, now(), now()),
  ('c3090000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c7', 9, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1090000-0000-4000-8000-000000000003', NULL, 'TAR.9.3.4', 'Orta Çağ’daki başlıca medeniyet havzalarının bilim, kültür ve sanata etkilerine ilişkin oluşturduğu ürünleri paylaşabilme', 4, 'TYMM 2026 Tarih Öğretim Programı, s.28', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000001', NULL, 'TAR.10.1.1', 'Türkistan’dan Türkiye’ye uzanan süreçte 1040-1299 yılları arasında meydana gelen önemli askerî mücadelelerin Türk tarihinin seyrine etkilerini karşılaştırabilme', 1, 'TYMM 2026 Tarih Öğretim Programı, s.34', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000001', NULL, 'TAR.10.1.2', 'Türkistan’dan Türkiye’ye uzanan süreçte Türklerde devlet ve ordu teşkilatında meydana gelen değişim ve sürekliliği yorumlayabilme', 2, 'TYMM 2026 Tarih Öğretim Programı, s.34', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000001', NULL, 'TAR.10.1.3', 'Türkistan’dan Türkiye’ye uzanan süreçte Türklerin sosyoekonomik faaliyetleri ile yerleşme ve şehirleşme anlayışları arasındaki ilişkiyi sorgulayabilme', 3, 'TYMM 2026 Tarih Öğretim Programı, s.34', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000001', NULL, 'TAR.10.1.4', 'Türkistan’dan Türkiye’ye uzanan süreçte Türk-İslam medeniyetinde bilim, kültür, eğitim ve sanat alanlarında meydana gelen gelişmeleri Anadolu’nun Türkleşme ve İslamlaşma sürecine etkisi açısından değerlendirebilme', 4, 'TYMM 2026 Tarih Öğretim Programı, s.34', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000002', NULL, 'TAR.10.2.1', 'Osmanlı Devleti’nin kuruluşuna dair farklı görüşleri tartışabilme', 1, 'TYMM 2026 Tarih Öğretim Programı, s.40', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000002', NULL, 'TAR.10.2.2', '1299-1453 yılları arasında Osmanlı Devleti’nin Anadolu ve Rumeli’de gerçekleştirdiği siyasi ve askerî mücadeleleri yorumlayabilme', 2, 'TYMM 2026 Tarih Öğretim Programı, s.40', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000002', NULL, 'TAR.10.2.3', 'Osmanlı Devleti’nin ordu, hukuk ve toprak sistemi ile devletleşme süreci arasındaki ilişkiyi çözümleyebilme', 3, 'TYMM 2026 Tarih Öğretim Programı, s.40', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000002', NULL, 'TAR.10.2.4', 'Osmanlı Devleti’nin fethettiği topraklarda kalıcı olabilmek için izlediği politikaları sorgulayabilme', 4, 'TYMM 2026 Tarih Öğretim Programı, s.40', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000002', NULL, 'TAR.10.2.5', 'Osmanlı Devleti’nin ilim ve irfan geleneğinin oluşmasında şehir, kurum ve şahsiyetlerin etkilerine dair fikirler üretebilme', 5, 'TYMM 2026 Tarih Öğretim Programı, s.40', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000003', NULL, 'TAR.10.3.1', '1453-1683 yılları arasındaki siyasi ve askerî mücadelelerin Osmanlı Devleti’nin cihan devleti hâline gelmesindeki rolüne ilişkin özgün fikirler üretebilme', 1, 'TYMM 2026 Tarih Öğretim Programı, s.45', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000003', NULL, 'TAR.10.3.2', '1453-1683 yılları arasında Osmanlı Devleti’nin yönetim ve ordu yapısında meydana gelen değişim ve sürekliliğe ilişkin kaynakları yorumlayabilme', 2, 'TYMM 2026 Tarih Öğretim Programı, s.45', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000003', NULL, 'TAR.10.3.3', 'Avrupalıların sömürgeci politikalarının etkilerini tarihsel bağlamı içerisinde değerlendirebilme', 3, 'TYMM 2026 Tarih Öğretim Programı, s.45', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000003', NULL, 'TAR.10.3.4', '1453-1683 yılları arasında Osmanlı Devleti’nde gerçekleşen önemli isyanların neden ve sonuçlarını müzakere edebilme', 4, 'TYMM 2026 Tarih Öğretim Programı, s.45', true, now(), now()),
  ('c3100000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c7', 10, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1100000-0000-4000-8000-000000000003', NULL, 'TAR.10.3.5', '1453-1683 yılları arasında Osmanlı Devleti’nde bilim, kültür, eğitim ve sanat alanlarında ortaya çıkan gelişmelere ilişkin oluşturduğu özgün ürünleri paylaşabilme', 5, 'TYMM 2026 Tarih Öğretim Programı, s.46', true, now(), now()),
  ('c3110000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c7', 11, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1110000-0000-4000-8000-000000000001', NULL, 'TAR.11.1.1', 'Osmanlı Devleti’nin 1683-1789 yılları arasındaki siyasi ve askerî mücadelelerini sonuçları açısından değerlendirebilme', 1, 'TYMM 2026 Tarih Öğretim Programı, s.52', true, now(), now()),
  ('c3110000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c7', 11, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1110000-0000-4000-8000-000000000001', NULL, 'TAR.11.1.2', 'Lale Devri’nde Osmanlı devlet ve toplum hayatında meydana gelen değişimi tarihsel bağlamı içerisinde yorumlayabilme', 2, 'TYMM 2026 Tarih Öğretim Programı, s.52', true, now(), now()),
  ('c3110000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c7', 11, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1110000-0000-4000-8000-000000000001', NULL, 'TAR.11.1.3', '1755 Lizbon ve 1766 İstanbul depremlerini ortaya çıkardığı etkiler bakımından karşılaştırabilme', 3, 'TYMM 2026 Tarih Öğretim Programı, s.52', true, now(), now()),
  ('c3110000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c7', 11, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1110000-0000-4000-8000-000000000001', NULL, 'TAR.11.1.4', 'Sanayi Devrimi’nin meydana getirdiği siyasi, sosyal ve ekonomik değişimi neden ve sonuçlarıyla birlikte yorumlayabilme', 4, 'TYMM 2026 Tarih Öğretim Programı, s.52', true, now(), now()),
  ('c3110000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c7', 11, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1110000-0000-4000-8000-000000000002', NULL, 'TAR.11.2.1', 'Fransız İhtilali’nin devlet ve toplum hayatında meydana getirdiği değişimi neden ve sonuçlarıyla yorumlayabilme', 1, 'TYMM 2026 Tarih Öğretim Programı, s.56', true, now(), now()),
  ('c3110000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c7', 11, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1110000-0000-4000-8000-000000000002', NULL, 'TAR.11.2.2', '1789-1908 yılları arasında meydana gelen siyasi, askerî ve idari gelişmelerin Osmanlı Devleti’nin yönetim ve toplum yapısına etkilerini sorgulayabilme', 2, 'TYMM 2026 Tarih Öğretim Programı, s.56', true, now(), now()),
  ('c3110000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c7', 11, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1110000-0000-4000-8000-000000000002', NULL, 'TAR.11.2.3', '1789-1908 yılları arasında Osmanlı Devleti’nde bilim, sanat ve teknoloji alanlarında yapılan uygulamaları yorumlayabilme', 3, 'TYMM 2026 Tarih Öğretim Programı, s.56', true, now(), now()),
  ('c3110000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c7', 11, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1110000-0000-4000-8000-000000000002', NULL, 'TAR.11.2.4', 'Osmanlı Devleti’nin sanayileşmede geri kalmasına neden olan etmenleri ortadan kaldırmaya yönelik alternatif fikirler üretebilme', 4, 'TYMM 2026 Tarih Öğretim Programı, s.57', true, now(), now()),
  ('c3110000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c7', 11, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1110000-0000-4000-8000-000000000003', NULL, 'TAR.11.3.1', '1908-1918 yılları arasında Osmanlı Devleti’nde meydana gelen siyasi ve askerî gelişmelerin sonuçlarını tarihsel bağlamı içerisinde değerlendirebilme', 1, 'TYMM 2026 Tarih Öğretim Programı, s.62', true, now(), now()),
  ('c3110000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c7', 11, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1110000-0000-4000-8000-000000000003', NULL, 'TAR.11.3.2', '1908-1918 yılları arasında yaşanan kitlesel göç ve salgınların Osmanlı devlet ve toplum hayatına etkilerine ilişkin bakış açısı geliştirebilme', 2, 'TYMM 2026 Tarih Öğretim Programı, s.62', true, now(), now()),
  ('c3110000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c7', 11, '4245101d-6269-40d0-a663-2016ab9d1ee4', 'c1110000-0000-4000-8000-000000000003', NULL, 'TAR.11.3.3', 'Osmanlı Devleti’nin insanlık tarihine katkılarına ilişkin oluşturduğu özgün ürünleri paylaşabilme', 3, 'TYMM 2026 Tarih Öğretim Programı, s.62', true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 4. MIGRATION HISTORY — idempotent kayıt (psql koşumunda statements=NULL;
--    CLI koşan ortamda CLI'ın kendi kaydı varsa bu INSERT atlanır).
-- ============================================================
insert into supabase_migrations.schema_migrations (version, name, statements)
select '146', '146_curriculum_tarih_tymm2026_agac', NULL
 where not exists (
   select 1 from supabase_migrations.schema_migrations where version = '146'
 );

-- ============================================================
-- 5. SON DENETİM (transaction içi; beklentiden sapan durum COMMIT'i durdurur)
-- ============================================================
DO $final$
DECLARE
  v_t integer; v_s integer; v_o integer; v_null_t integer; v_null_s integer; v_linked integer;
BEGIN
  SELECT count(*) INTO v_t FROM public.topics WHERE subject_id = '4245101d-6269-40d0-a663-2016ab9d1ee4';
  SELECT count(*) INTO v_s FROM public.subtopics s JOIN public.topics t ON t.id = s.topic_id
   WHERE t.subject_id = '4245101d-6269-40d0-a663-2016ab9d1ee4';
  SELECT count(*),
         count(*) FILTER (WHERE topic_id IS NULL),
         count(*) FILTER (WHERE subtopic_id IS NULL),
         count(*) FILTER (WHERE topic_id IS NOT NULL)
    INTO v_o, v_null_t, v_null_s, v_linked
    FROM public.curriculum_outcomes WHERE outcome_code LIKE 'TAR.%';
  IF v_t <> 9 OR v_s <> 38 OR v_o <> 38 OR v_null_t <> 0 OR v_null_s <> 38 OR v_linked <> 38 THEN
    RAISE EXCEPTION 'FINAL_146: beklenen 9/38/38 (topic/subtopic/outcome), topic-bağlı=38, NULL subtopic=38; bulunan %/%/%/%/%/%', v_t, v_s, v_o, v_linked, v_null_s, v_null_t;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.curriculum_versions
                 WHERE id = 'a1000000-0000-4000-8000-0000000000c7' AND framework = 'tymm_2026_tarih') THEN
    RAISE EXCEPTION 'FINAL_146: sürüm satırı (a1000000-0000-4000-8000-0000000000c7) yok — beklenmeyen durum.';
  END IF;
END
$final$;

COMMIT;
