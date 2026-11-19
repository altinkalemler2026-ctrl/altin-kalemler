-- ============================================================
-- 142_curriculum_fizik_tymm2026_agac.sql
-- Altın Kalemler — CURRICULUM-ALL-01 Fizik dilimi: TYMM 2026 Fizik
--   müfredat ağacının (15 topic + 82 subtopic + 84 yeni outcome) YÜKLENMESİ
--   ve mevcut 22 FIZ.* kazanımının ünite bağlantısının tamamlanması.
--
-- KULLANICI ONAYLI KAPSAM (2026-10-27)
--   - 15 topic + 82 subtopic + 84 yeni outcome YÜKLENİR.
--   - Mevcut 22 outcome'un id / outcome_code / outcome_text SABİTTİR;
--     yalnızca topic_id (kodun FIZ.s.u.k alanındaki resmî ünite numarasından)
--     tamamlanır ve subtopic_id NULL olarak KALIR (kaynakta çıktı→alt konu
--     ilişkisi numaralandırılmamıştır; yakınlık/sıra/isim benzerliğiyle
--     atama YASAKTIR — kanonik dosya §2, Matematik BLOKAJ-1 kuralı).
--
-- KAYNAK (yalnız resmî)
--   Türkiye Yüzyılı Maarif Modeli — Ortaöğretim Fizik Dersi (9, 10, 11 ve
--   12. Sınıflar) Öğretim Programı (2026); PDF basılı sayfa numaraları.
--   Yerel: docs/references/mufredat/2026-2027/tymm-2026-fizik-9-12.pdf
--   Ağaç:  docs/question-production/curriculum-mapping/fizik-9-12-kanonik-esleme-v1.md
--   Dry-run: scripts/fizik-mufredat-dry-run.ts → fizik-dry-run-sonuc.md
--   (203/203 satır, 15/82/106, eşleşen 22, metin farkı 0, engelli 0)
--
-- UUID ŞEMASI (migration 125/111/112 deseniyle uyumlu; bu dosyada belgelenir)
--   Fizik topic     : a5 + GG (sınıf) + ünite no  → a5GG0000-0000-4000-8000-0000000000NN
--     ('a5' ailesi DB'de boştur: a1=versions, a2=schedule_profiles, a3=MAT
--      topics, a4=schedule_items, a6=MAT subtopics, a7=MAT outcomes,
--      a9=FIZ outcomes(125). 'a9' topic için KULLANILMAZ — a9090000-... id'li
--      outcome PK'larıyla ÇAKIŞIRDI.)
--   Fizik subtopic  : a8 + GG (sınıf) + sınıf-içi sıra → a8GG0000-...-0000000000NN
--   Yeni FIZ outcome: a9 ailesi 125'ten DEVAM EDER; NN = sınıf içi (ünite, k)
--     sıralamasında kesintisiz sayaç (125'te mevcut 22 kayıt 001..006 / 001..005
--     / 001..008 / 001..003'ü kullanır; yeniler kalan numaraları alır).
--   Sürüm id: a1000000-0000-4000-8000-0000000000c3 (tymm_2026_fizik, 125).
--   Subject id: 57a959a8-43e7-4f0e-8b54-a7299386fdb3 (Fizik, 045).
--
-- AD / SLUG / SIRA KARARLARI
--   - topic.name: 'FIZ.9.1 <ÜNİTE ADI>' deseni (matematik 'MAT.9.1 SAYILAR'
--     deseniyle aynı; üretim planlayıcı çiplerinde tutarlılık). Ünite adı
--     PDF'teki resmî büyük harfli başlıktır ('1. ÜNİTE: ' öneki atılır).
--   - topic.slug : fiz-GG-N-<ünite-adı-slug>  (dry-run öneri formülüyle aynı).
--     DB kısıtı: UNIQUE (curriculum_version_id, subject_id, grade_level, slug).
--   - subtopic.name: İçerik Çerçevesi kutusundaki basılı madde (resmî).
--   - subtopic.slug: <topic-slug>-<madde-slug> (112 matematik deseni;
--     DB kısıtı UNIQUE (topic_id, slug) — desen bunu aşan global benzersizlik de verir).
--   - subtopic.sort_order: sınıf içi kesintisiz 1..20 / 1..19 / 1..18 / 1..25
--     (kutu sırası; ünite değişince sıfırlanmaz). Topic içi sıralama yine doğrudur.
--   - outcome.sort_order: kodun son basamağı k (ünite-içi sıra) — migration 125
--     sözleşmesi ('sort_order: kod son basamağına eşittir') ve 112 matematik
--     deseniyle tutarlı. Görev metnindeki 'ağaç dosyasındaki kesintisiz sıra'
--     (1..203 global) BİLİNÇLİ OLARAK KULLANILMAMIŞTIR: aynı ünitedeki mevcut
--     22 kayıt (sort_order=k) ile karışırsa ünite-içi sıralama BOZULUR
--     (ör. FIZ.9.1.3 global 8 alsa FIZ.9.1.4'ten sonra sıralanırdı).
--     Planlayıcı outcomes'u sort_order'a göre sıralar; k değeri her ünite
--     içinde 1..max kesintisizdir (dry-run kanıtlar).
--   - source_reference: 'TYMM 2026 Fizik Öğretim Programı, s.NN' (125 birebir);
--     NN = kazanım bloğunun basılı sayfası (kanonik dosya §4/§5).
--
-- İDEMPOTENCE
--   - Tüm INSERT'ler ON CONFLICT (id) DO NOTHING → tekrar koşum SIFIR yeni satır.
--   - UPDATE'ler değer-eşitliği korumalı (IS DISTINCT FROM) → tekrar koşum
--     0 satır günceller.
--   - outcome_code'da UNIQUE KISIT YOKTUR (yalnız idx_curriculum_outcomes_code
--     normal indeks; information_schema/pg_indexes ile doğrulandı). Bu yüzden
--     çift koruma var: (1) deterministic id + ON CONFLICT (id); (2) ön-koşul
--     bloğu, 84 yeni kodtan herhangi biri BAŞKA bir id ile mevcutsa fail-closed
--     olarak durur (mükerrer kod satırı oluşamaz).
--   - History: supabase_migrations.schema_migrations'a version='142' kaydı
--     WHERE NOT EXISTS ile idempotent eklenir. statements=NULL (dosya kendi
--     metnini içine koyamaz; CLI ile uygulayan ortamda CLI statements'i doldurur).
--     NOT: Bu proje migration'ları psql (ON_ERROR_STOP) ile uygular; supabase
--     CLI push kullanılırsa CLI kendi history kaydını da açar — WHERE NOT
--     EXISTS çakışmayı önler.
--
-- GERİ DÖNÜŞ: scripts/fizik-mufredat-geri-donus.sql (tek transaction;
-- 84 outcome DELETE → 22 outcome link=NULL → 82 subtopic DELETE → 15 topic
-- DELETE → 142 history DELETE; FK sırası korunur, fail-closed referans
-- kontrolleri içerir). Uygulama öncesi yedek:
-- docs/references/mufredat/yedekler/fizik-on-yedek-20261027.sql
--
-- YASAKLAR / DOKUNULMAZLAR
--   - AK-M12-ILK-008 ve tüm matematik kayıtlarına (a3/a6/a7 aileleri, c1/c2)
--     DOKUNULMAZ. Şema/RLS/RPC değişmez (data-only). Soru üretimi, staging,
--     takvim dağıtımı YOK.
-- ============================================================

BEGIN;

-- ============================================================
-- 0. ÖN-KOŞUL DENETİMİ (fail-closed; en küçük güvenli durum)
-- ============================================================
DO $guard$
DECLARE
  v_topic_sayi integer;
  v_outcome_sayi integer;
  v_yabanci_kod integer;
  v_k22 integer;
BEGIN
  -- Sürüm + ders var mı?
  IF NOT EXISTS (SELECT 1 FROM public.curriculum_versions
                 WHERE id = 'a1000000-0000-4000-8000-0000000000c3'
                   AND framework = 'tymm_2026_fizik') THEN
    RAISE EXCEPTION 'GUARD_142: tymm_2026_fizik sürüm satırı (…c3) yok — migration 125 uygulanmamış ortam.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.subjects WHERE id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3') THEN
    RAISE EXCEPTION 'GUARD_142: Fizik subject satırı yok — migration 045 uygulanmamış ortam.';
  END IF;

  -- Fizik ağacı ya boş (ilk uygulama) ya da bu migration'ın bıraktığı dolu hâlde olmalı.
  SELECT count(*) INTO v_topic_sayi FROM public.topics
   WHERE subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3';
  IF v_topic_sayi NOT IN (0, 15) THEN
    RAISE EXCEPTION 'GUARD_142: Fizik topics=% (beklenen 0 veya 15) — yabancı/kısmi durum, fail-closed dur.', v_topic_sayi;
  END IF;

  SELECT count(*) INTO v_outcome_sayi FROM public.curriculum_outcomes
   WHERE outcome_code LIKE 'FIZ.%';
  IF v_outcome_sayi NOT IN (22, 106) THEN
    RAISE EXCEPTION 'GUARD_142: FIZ.* outcomes=% (beklenen 22 veya 106) — yabancı/kısmi durum, fail-closed dur.', v_outcome_sayi;
  END IF;

  -- 22 sabit kayıt gerçekten 125'teki id+kod çiftleri mi? (drift koruması)
  SELECT count(*) INTO v_k22
    FROM public.curriculum_outcomes
   WHERE (id, outcome_code) IN (
      ('a9090000-0000-4000-8000-000000000001','FIZ.9.1.1'),
      ('a9090000-0000-4000-8000-000000000002','FIZ.9.1.2'),
      ('a9090000-0000-4000-8000-000000000003','FIZ.9.1.4'),
      ('a9090000-0000-4000-8000-000000000004','FIZ.9.2.1'),
      ('a9090000-0000-4000-8000-000000000005','FIZ.9.2.2'),
      ('a9090000-0000-4000-8000-000000000006','FIZ.9.2.4'),
      ('a9100000-0000-4000-8000-000000000001','FIZ.10.1.3'),
      ('a9100000-0000-4000-8000-000000000002','FIZ.10.2.1'),
      ('a9100000-0000-4000-8000-000000000003','FIZ.10.3.2'),
      ('a9100000-0000-4000-8000-000000000004','FIZ.10.3.4'),
      ('a9100000-0000-4000-8000-000000000005','FIZ.10.3.5'),
      ('a9110000-0000-4000-8000-000000000001','FIZ.11.1.1'),
      ('a9110000-0000-4000-8000-000000000002','FIZ.11.1.3'),
      ('a9110000-0000-4000-8000-000000000003','FIZ.11.1.4'),
      ('a9110000-0000-4000-8000-000000000004','FIZ.11.1.7'),
      ('a9110000-0000-4000-8000-000000000005','FIZ.11.1.10'),
      ('a9110000-0000-4000-8000-000000000006','FIZ.11.2.4'),
      ('a9110000-0000-4000-8000-000000000007','FIZ.11.2.5'),
      ('a9110000-0000-4000-8000-000000000008','FIZ.11.2.6'),
      ('a9120000-0000-4000-8000-000000000001','FIZ.12.1.3'),
      ('a9120000-0000-4000-8000-000000000002','FIZ.12.1.5'),
      ('a9120000-0000-4000-8000-000000000003','FIZ.12.1.6')
   );
  IF v_k22 <> 22 THEN
    RAISE EXCEPTION 'GUARD_142: 22 sabit FIZ. kaydından yalnız % tanındı (id/kod drifti) — fail-closed dur.', v_k22;
  END IF;

  -- 84 yeni kodtan biri BAŞKA id ile var mı? (outcome_code unique olmadığından
  -- mükerrer kod satırı oluşmasını önleyen ikinci koruma)
  SELECT count(*) INTO v_yabanci_kod
    FROM public.curriculum_outcomes
   WHERE outcome_code IN (
      'FIZ.9.1.3','FIZ.9.2.3','FIZ.9.2.5','FIZ.9.2.6','FIZ.9.2.7',
      'FIZ.9.3.1','FIZ.9.3.2','FIZ.9.3.3','FIZ.9.3.4','FIZ.9.3.5','FIZ.9.3.6','FIZ.9.3.7',
      'FIZ.9.4.1','FIZ.9.4.2','FIZ.9.4.3','FIZ.9.4.4','FIZ.9.4.5','FIZ.9.4.6',
      'FIZ.10.1.1','FIZ.10.1.2','FIZ.10.2.2','FIZ.10.2.3','FIZ.10.2.4','FIZ.10.2.5',
      'FIZ.10.3.1','FIZ.10.3.3','FIZ.10.3.6','FIZ.10.3.7',
      'FIZ.10.4.1','FIZ.10.4.2','FIZ.10.4.3','FIZ.10.4.4','FIZ.10.4.5','FIZ.10.4.6','FIZ.10.4.7',
      'FIZ.11.1.2','FIZ.11.1.5','FIZ.11.1.6','FIZ.11.1.8','FIZ.11.1.9',
      'FIZ.11.2.1','FIZ.11.2.2','FIZ.11.2.3','FIZ.11.2.7','FIZ.11.2.8','FIZ.11.2.9','FIZ.11.2.10','FIZ.11.2.11','FIZ.11.2.12','FIZ.11.2.13',
      'FIZ.11.3.1','FIZ.11.3.2','FIZ.11.3.3','FIZ.11.3.4','FIZ.11.3.5','FIZ.11.3.6','FIZ.11.3.7','FIZ.11.3.8','FIZ.11.3.9','FIZ.11.3.10',
      'FIZ.12.1.1','FIZ.12.1.2','FIZ.12.1.4','FIZ.12.2.1','FIZ.12.2.2','FIZ.12.2.3','FIZ.12.2.4','FIZ.12.2.5','FIZ.12.2.6',
      'FIZ.12.3.1','FIZ.12.3.2','FIZ.12.3.3','FIZ.12.3.4','FIZ.12.3.5','FIZ.12.3.6','FIZ.12.3.7',
      'FIZ.12.4.1','FIZ.12.4.2','FIZ.12.4.3','FIZ.12.4.4','FIZ.12.4.5','FIZ.12.4.6','FIZ.12.4.7','FIZ.12.4.8'
   ) AND id NOT IN (
      'a9090000-0000-4000-8000-000000000007','a9090000-0000-4000-8000-000000000008','a9090000-0000-4000-8000-000000000009','a9090000-0000-4000-8000-000000000010','a9090000-0000-4000-8000-000000000011','a9090000-0000-4000-8000-000000000012','a9090000-0000-4000-8000-000000000013','a9090000-0000-4000-8000-000000000014','a9090000-0000-4000-8000-000000000015','a9090000-0000-4000-8000-000000000016','a9090000-0000-4000-8000-000000000017','a9090000-0000-4000-8000-000000000018','a9090000-0000-4000-8000-000000000019','a9090000-0000-4000-8000-000000000020','a9090000-0000-4000-8000-000000000021','a9090000-0000-4000-8000-000000000022','a9090000-0000-4000-8000-000000000023','a9090000-0000-4000-8000-000000000024',
      'a9100000-0000-4000-8000-000000000006','a9100000-0000-4000-8000-000000000007','a9100000-0000-4000-8000-000000000008','a9100000-0000-4000-8000-000000000009','a9100000-0000-4000-8000-000000000010','a9100000-0000-4000-8000-000000000011','a9100000-0000-4000-8000-000000000012','a9100000-0000-4000-8000-000000000013','a9100000-0000-4000-8000-000000000014','a9100000-0000-4000-8000-000000000015','a9100000-0000-4000-8000-000000000016','a9100000-0000-4000-8000-000000000017','a9100000-0000-4000-8000-000000000018','a9100000-0000-4000-8000-000000000019','a9100000-0000-4000-8000-000000000020','a9100000-0000-4000-8000-000000000021','a9100000-0000-4000-8000-000000000022',
      'a9110000-0000-4000-8000-000000000009','a9110000-0000-4000-8000-000000000010','a9110000-0000-4000-8000-000000000011','a9110000-0000-4000-8000-000000000012','a9110000-0000-4000-8000-000000000013','a9110000-0000-4000-8000-000000000014','a9110000-0000-4000-8000-000000000015','a9110000-0000-4000-8000-000000000016','a9110000-0000-4000-8000-000000000017','a9110000-0000-4000-8000-000000000018','a9110000-0000-4000-8000-000000000019','a9110000-0000-4000-8000-000000000020','a9110000-0000-4000-8000-000000000021','a9110000-0000-4000-8000-000000000022','a9110000-0000-4000-8000-000000000023','a9110000-0000-4000-8000-000000000024','a9110000-0000-4000-8000-000000000025','a9110000-0000-4000-8000-000000000026','a9110000-0000-4000-8000-000000000027','a9110000-0000-4000-8000-000000000028','a9110000-0000-4000-8000-000000000029','a9110000-0000-4000-8000-000000000030','a9110000-0000-4000-8000-000000000031','a9110000-0000-4000-8000-000000000032','a9110000-0000-4000-8000-000000000033',
      'a9120000-0000-4000-8000-000000000004','a9120000-0000-4000-8000-000000000005','a9120000-0000-4000-8000-000000000006','a9120000-0000-4000-8000-000000000007','a9120000-0000-4000-8000-000000000008','a9120000-0000-4000-8000-000000000009','a9120000-0000-4000-8000-000000000010','a9120000-0000-4000-8000-000000000011','a9120000-0000-4000-8000-000000000012','a9120000-0000-4000-8000-000000000013','a9120000-0000-4000-8000-000000000014','a9120000-0000-4000-8000-000000000015','a9120000-0000-4000-8000-000000000016','a9120000-0000-4000-8000-000000000017','a9120000-0000-4000-8000-000000000018','a9120000-0000-4000-8000-000000000019','a9120000-0000-4000-8000-000000000020','a9120000-0000-4000-8000-000000000021','a9120000-0000-4000-8000-000000000022','a9120000-0000-4000-8000-000000000023','a9120000-0000-4000-8000-000000000024','a9120000-0000-4000-8000-000000000025','a9120000-0000-4000-8000-000000000026','a9120000-0000-4000-8000-000000000027'
   );
  IF v_yabanci_kod > 0 THEN
    RAISE EXCEPTION 'GUARD_142: % adet yeni FIZ. kodu BAŞKA id ile zaten mevcut (mükerrer kod riski) — fail-closed dur.', v_yabanci_kod;
  END IF;
END
$guard$;

-- ============================================================
-- 1. TOPICS (15) — FIZ.GG.N <ÜNİTE ADI>; sort_order = resmî ünite no (sınıf içi)
--    UNIQUE (curriculum_version_id, subject_id, grade_level, slug) koruması:
--    farklı id ile aynı slug varsa INSERT doğal olarak HATA verir (fail-closed).
-- ============================================================
insert into public.topics (
  id, subject_id, grade_level, name, slug, sort_order,
  is_active, curriculum_version_id, created_at, updated_at
) values
  -- 9. SINIF (4 ünite)
  ('a5090000-0000-4000-8000-000000000001', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 9,  'FIZ.9.1 FİZİK BİLİMİ VE KARİYER KEŞFİ',   'fiz-9-1-fizik-bilimi-ve-kariyer-kesfi',   1, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  ('a5090000-0000-4000-8000-000000000002', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 9,  'FIZ.9.2 KUVVET VE HAREKET',               'fiz-9-2-kuvvet-ve-hareket',               2, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  ('a5090000-0000-4000-8000-000000000003', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 9,  'FIZ.9.3 AKIŞKANLAR',                      'fiz-9-3-akiskanlar',                      3, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  ('a5090000-0000-4000-8000-000000000004', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 9,  'FIZ.9.4 ENERJİ',                          'fiz-9-4-enerji',                          4, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  -- 10. SINIF (4 ünite)
  ('a5100000-0000-4000-8000-000000000001', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 10, 'FIZ.10.1 KUVVET VE HAREKET',              'fiz-10-1-kuvvet-ve-hareket',              1, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  ('a5100000-0000-4000-8000-000000000002', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 10, 'FIZ.10.2 ENERJİ',                         'fiz-10-2-enerji',                         2, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  ('a5100000-0000-4000-8000-000000000003', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 10, 'FIZ.10.3 ELEKTRİK',                       'fiz-10-3-elektrik',                       3, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  ('a5100000-0000-4000-8000-000000000004', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 10, 'FIZ.10.4 DALGALAR',                       'fiz-10-4-dalgalar',                       4, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  -- 11. SINIF (3 ünite)
  ('a5110000-0000-4000-8000-000000000001', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 11, 'FIZ.11.1 KUVVET VE HAREKET',              'fiz-11-1-kuvvet-ve-hareket',              1, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  ('a5110000-0000-4000-8000-000000000002', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 11, 'FIZ.11.2 ELEKTRİK VE MANYETİZMA',         'fiz-11-2-elektrik-ve-manyetizma',         2, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  ('a5110000-0000-4000-8000-000000000003', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 11, 'FIZ.11.3 OPTİK',                          'fiz-11-3-optik',                          3, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  -- 12. SINIF (4 ünite)
  ('a5120000-0000-4000-8000-000000000001', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 12, 'FIZ.12.1 KUVVET VE HAREKET',              'fiz-12-1-kuvvet-ve-hareket',              1, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  ('a5120000-0000-4000-8000-000000000002', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 12, 'FIZ.12.2 ENERJİ',                         'fiz-12-2-enerji',                         2, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  ('a5120000-0000-4000-8000-000000000003', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 12, 'FIZ.12.3 DALGALAR',                       'fiz-12-3-dalgalar',                       3, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now()),
  ('a5120000-0000-4000-8000-000000000004', '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 12, 'FIZ.12.4 MADDE VE DOĞASI',                'fiz-12-4-madde-ve-dogasi',                4, true, 'a1000000-0000-4000-8000-0000000000c3', now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 2. SUBTOPICS (82) — İçerik Çerçevesi maddeleri (resmî, basılı sıra);
--    sort_order sınıf içi kesintisiz (9: 1..20, 10: 1..19, 11: 1..18, 12: 1..25);
--    subtopic_id bağlantısı çıktılara AÇILMAZ (kaynak numaralandırmamış).
-- ============================================================
insert into public.subtopics (
  id, topic_id, name, slug, sort_order, is_active, created_at, updated_at
) values
  -- 9.1 FİZİK BİLİMİ VE KARİYER KEŞFİ (kutu sırası 1-4)
  ('a8090000-0000-4000-8000-000000000001', 'a5090000-0000-4000-8000-000000000001', 'Fizik Bilimi',                                        'fiz-9-1-fizik-bilimi-ve-kariyer-kesfi-fizik-bilimi',                                        1,  true, now(), now()),
  ('a8090000-0000-4000-8000-000000000002', 'a5090000-0000-4000-8000-000000000001', 'Fizik Biliminin Alt Dalları',                         'fiz-9-1-fizik-bilimi-ve-kariyer-kesfi-fizik-biliminin-alt-dallari',                         2,  true, now(), now()),
  ('a8090000-0000-4000-8000-000000000003', 'a5090000-0000-4000-8000-000000000001', 'Fizik Bilimine Yön Verenler',                         'fiz-9-1-fizik-bilimi-ve-kariyer-kesfi-fizik-bilimine-yon-verenler',                         3,  true, now(), now()),
  ('a8090000-0000-4000-8000-000000000004', 'a5090000-0000-4000-8000-000000000001', 'Fizik Bilimi İle İlgili Kariyer Keşfi',               'fiz-9-1-fizik-bilimi-ve-kariyer-kesfi-fizik-bilimi-ile-ilgili-kariyer-kesfi',               4,  true, now(), now()),
  -- 9.2 KUVVET VE HAREKET (kutu sırası 5-9)
  ('a8090000-0000-4000-8000-000000000005', 'a5090000-0000-4000-8000-000000000002', 'Temel ve Türetilmiş Nicelikler',                      'fiz-9-2-kuvvet-ve-hareket-temel-ve-turetilmis-nicelikler',                                  5,  true, now(), now()),
  ('a8090000-0000-4000-8000-000000000006', 'a5090000-0000-4000-8000-000000000002', 'Skaler ve Vektörel Nicelikler',                       'fiz-9-2-kuvvet-ve-hareket-skaler-ve-vektorel-nicelikler',                                   6,  true, now(), now()),
  ('a8090000-0000-4000-8000-000000000007', 'a5090000-0000-4000-8000-000000000002', 'Vektörler',                                           'fiz-9-2-kuvvet-ve-hareket-vektorler',                                                       7,  true, now(), now()),
  ('a8090000-0000-4000-8000-000000000008', 'a5090000-0000-4000-8000-000000000002', 'Doğadaki Temel Kuvvetler',                            'fiz-9-2-kuvvet-ve-hareket-dogadaki-temel-kuvvetler',                                        8,  true, now(), now()),
  ('a8090000-0000-4000-8000-000000000009', 'a5090000-0000-4000-8000-000000000002', 'Hareket ve Hareket Türleri',                          'fiz-9-2-kuvvet-ve-hareket-hareket-ve-hareket-turleri',                                      9,  true, now(), now()),
  -- 9.3 AKIŞKANLAR (kutu sırası 10-14)
  ('a8090000-0000-4000-8000-000000000010', 'a5090000-0000-4000-8000-000000000003', 'Basınç',                                              'fiz-9-3-akiskanlar-basinc',                                                                 10, true, now(), now()),
  ('a8090000-0000-4000-8000-000000000011', 'a5090000-0000-4000-8000-000000000003', 'Sıvılarda Basınç',                                    'fiz-9-3-akiskanlar-sivilarda-basinc',                                                       11, true, now(), now()),
  ('a8090000-0000-4000-8000-000000000012', 'a5090000-0000-4000-8000-000000000003', 'Açık Hava Basıncı',                                   'fiz-9-3-akiskanlar-acik-hava-basinci',                                                      12, true, now(), now()),
  ('a8090000-0000-4000-8000-000000000013', 'a5090000-0000-4000-8000-000000000003', 'Kaldırma Kuvveti',                                    'fiz-9-3-akiskanlar-kaldirma-kuvveti',                                                       13, true, now(), now()),
  ('a8090000-0000-4000-8000-000000000014', 'a5090000-0000-4000-8000-000000000003', 'Bernoulli İlkesi',                                    'fiz-9-3-akiskanlar-bernoulli-ilkesi',                                                       14, true, now(), now()),
  -- 9.4 ENERJİ (kutu sırası 15-20)
  ('a8090000-0000-4000-8000-000000000015', 'a5090000-0000-4000-8000-000000000004', 'İç Enerji, Isı ve Sıcaklık Arasındaki İlişki',        'fiz-9-4-enerji-ic-enerji-isi-ve-sicaklik-arasindaki-iliski',                                15, true, now(), now()),
  ('a8090000-0000-4000-8000-000000000016', 'a5090000-0000-4000-8000-000000000004', 'Isı, Öz Isı, Isı Sığası ve Sıcaklık Farkı Arasındaki İlişki', 'fiz-9-4-enerji-isi-oz-isi-isi-sigasi-ve-sicaklik-farki-arasindaki-iliski',          16, true, now(), now()),
  ('a8090000-0000-4000-8000-000000000017', 'a5090000-0000-4000-8000-000000000004', 'Hâl Değişimi',                                        'fiz-9-4-enerji-hal-degisimi',                                                               17, true, now(), now()),
  ('a8090000-0000-4000-8000-000000000018', 'a5090000-0000-4000-8000-000000000004', 'Isıl Denge',                                          'fiz-9-4-enerji-isil-denge',                                                                 18, true, now(), now()),
  ('a8090000-0000-4000-8000-000000000019', 'a5090000-0000-4000-8000-000000000004', 'Isı Aktarım Yolları',                                 'fiz-9-4-enerji-isi-aktarim-yollari',                                                        19, true, now(), now()),
  ('a8090000-0000-4000-8000-000000000020', 'a5090000-0000-4000-8000-000000000004', 'Isı İletim Hızı',                                     'fiz-9-4-enerji-isi-iletim-hizi',                                                            20, true, now(), now()),
  -- 10.1 KUVVET VE HAREKET (kutu sırası 1-2)
  ('a8100000-0000-4000-8000-000000000001', 'a5100000-0000-4000-8000-000000000001', 'Sabit Hızlı Hareket',                                 'fiz-10-1-kuvvet-ve-hareket-sabit-hizli-hareket',                                            1,  true, now(), now()),
  ('a8100000-0000-4000-8000-000000000002', 'a5100000-0000-4000-8000-000000000001', 'Bir Boyutta Sabit İvmeli Hareket',                    'fiz-10-1-kuvvet-ve-hareket-bir-boyutta-sabit-ivmeli-hareket',                               2,  true, now(), now()),
  -- 10.2 ENERJİ (kutu sırası 3-6)
  ('a8100000-0000-4000-8000-000000000003', 'a5100000-0000-4000-8000-000000000002', 'İş, Enerji ve Güç',                                   'fiz-10-2-enerji-is-enerji-ve-guc',                                                          3,  true, now(), now()),
  ('a8100000-0000-4000-8000-000000000004', 'a5100000-0000-4000-8000-000000000002', 'Enerji Biçimleri',                                    'fiz-10-2-enerji-enerji-bicimleri',                                                          4,  true, now(), now()),
  ('a8100000-0000-4000-8000-000000000005', 'a5100000-0000-4000-8000-000000000002', 'Mekanik Enerji',                                      'fiz-10-2-enerji-mekanik-enerji',                                                            5,  true, now(), now()),
  ('a8100000-0000-4000-8000-000000000006', 'a5100000-0000-4000-8000-000000000002', 'Enerji Kaynakları',                                   'fiz-10-2-enerji-enerji-kaynaklari',                                                         6,  true, now(), now()),
  -- 10.3 ELEKTRİK (kutu sırası 7-13)
  ('a8100000-0000-4000-8000-000000000007', 'a5100000-0000-4000-8000-000000000003', 'Basit Elektrik Devreleri',                            'fiz-10-3-elektrik-basit-elektrik-devreleri',                                                7,  true, now(), now()),
  ('a8100000-0000-4000-8000-000000000008', 'a5100000-0000-4000-8000-000000000003', 'Elektrik Akımı',                                      'fiz-10-3-elektrik-elektrik-akimi',                                                          8,  true, now(), now()),
  ('a8100000-0000-4000-8000-000000000009', 'a5100000-0000-4000-8000-000000000003', 'Ohm Yasası',                                          'fiz-10-3-elektrik-ohm-yasasi',                                                              9,  true, now(), now()),
  ('a8100000-0000-4000-8000-000000000010', 'a5100000-0000-4000-8000-000000000003', 'Dirençlerin Bağlanması',                              'fiz-10-3-elektrik-direnclerin-baglanmasi',                                                  10, true, now(), now()),
  ('a8100000-0000-4000-8000-000000000011', 'a5100000-0000-4000-8000-000000000003', 'Üreteçlerin Bağlanması',                              'fiz-10-3-elektrik-ureteclerin-baglanmasi',                                                  11, true, now(), now()),
  ('a8100000-0000-4000-8000-000000000012', 'a5100000-0000-4000-8000-000000000003', 'Elektrik Akımının Oluşturabileceği Tehlikelere Karşı Alınması Gereken Önlemler', 'fiz-10-3-elektrik-elektrik-akiminin-olusturabilecegi-tehlikelere-karsi-alinmasi-gereken-onlemler', 12, true, now(), now()),
  ('a8100000-0000-4000-8000-000000000013', 'a5100000-0000-4000-8000-000000000003', 'Topraklamanın Önemi',                                 'fiz-10-3-elektrik-topraklamanin-onemi',                                                     13, true, now(), now()),
  -- 10.4 DALGALAR (kutu sırası 14-19)
  ('a8100000-0000-4000-8000-000000000014', 'a5100000-0000-4000-8000-000000000004', 'Periyodik Hareketler',                                'fiz-10-4-dalgalar-periyodik-hareketler',                                                    14, true, now(), now()),
  ('a8100000-0000-4000-8000-000000000015', 'a5100000-0000-4000-8000-000000000004', 'Dalgaların Temel Kavramları',                         'fiz-10-4-dalgalar-dalgalarin-temel-kavramlari',                                             15, true, now(), now()),
  ('a8100000-0000-4000-8000-000000000016', 'a5100000-0000-4000-8000-000000000004', 'Dalgaların Sınıflandırılması',                        'fiz-10-4-dalgalar-dalgalarin-siniflandirilmasi',                                            16, true, now(), now()),
  ('a8100000-0000-4000-8000-000000000017', 'a5100000-0000-4000-8000-000000000004', 'Dalgaların Yayılma Süratini Etkileyen Etmenler',      'fiz-10-4-dalgalar-dalgalarin-yayilma-suratini-etkileyen-etmenler',                          17, true, now(), now()),
  ('a8100000-0000-4000-8000-000000000018', 'a5100000-0000-4000-8000-000000000004', 'Su Dalgalarında Yansıma ve Kırılma',                  'fiz-10-4-dalgalar-su-dalgalarinda-yansima-ve-kirilma',                                      18, true, now(), now()),
  ('a8100000-0000-4000-8000-000000000019', 'a5100000-0000-4000-8000-000000000004', 'Rezonans ve Deprem',                                  'fiz-10-4-dalgalar-rezonans-ve-deprem',                                                      19, true, now(), now()),
  -- 11.1 KUVVET VE HAREKET (kutu sırası 1-6)
  ('a8110000-0000-4000-8000-000000000001', 'a5110000-0000-4000-8000-000000000001', 'Serbest Düşme',                                       'fiz-11-1-kuvvet-ve-hareket-serbest-dusme',                                                  1,  true, now(), now()),
  ('a8110000-0000-4000-8000-000000000002', 'a5110000-0000-4000-8000-000000000001', 'İki Boyutta Sabit İvmeli Hareket',                    'fiz-11-1-kuvvet-ve-hareket-iki-boyutta-sabit-ivmeli-hareket',                               2,  true, now(), now()),
  ('a8110000-0000-4000-8000-000000000003', 'a5110000-0000-4000-8000-000000000001', 'Newton''ın Hareket Yasaları',                         'fiz-11-1-kuvvet-ve-hareket-newtonin-hareket-yasalari',                                      3,  true, now(), now()),
  ('a8110000-0000-4000-8000-000000000004', 'a5110000-0000-4000-8000-000000000001', 'Sürtünme Kuvveti',                                    'fiz-11-1-kuvvet-ve-hareket-surtunme-kuvveti',                                               4,  true, now(), now()),
  ('a8110000-0000-4000-8000-000000000005', 'a5110000-0000-4000-8000-000000000001', 'Limit Hız',                                           'fiz-11-1-kuvvet-ve-hareket-limit-hiz',                                                      5,  true, now(), now()),
  ('a8110000-0000-4000-8000-000000000006', 'a5110000-0000-4000-8000-000000000001', 'Düzgün Çembersel Hareket',                            'fiz-11-1-kuvvet-ve-hareket-duzgun-cembersel-hareket',                                       6,  true, now(), now()),
  -- 11.2 ELEKTRİK VE MANYETİZMA (kutu sırası 7-10)
  ('a8110000-0000-4000-8000-000000000007', 'a5110000-0000-4000-8000-000000000002', 'Elektriksel Kuvvet ve Elektriksel Alan',              'fiz-11-2-elektrik-ve-manyetizma-elektriksel-kuvvet-ve-elektriksel-alan',                    7,  true, now(), now()),
  ('a8110000-0000-4000-8000-000000000008', 'a5110000-0000-4000-8000-000000000002', 'Manyetik Alan ve Manyetik Kuvvet',                    'fiz-11-2-elektrik-ve-manyetizma-manyetik-alan-ve-manyetik-kuvvet',                          8,  true, now(), now()),
  ('a8110000-0000-4000-8000-000000000009', 'a5110000-0000-4000-8000-000000000002', 'İndüksiyon Akımı',                                    'fiz-11-2-elektrik-ve-manyetizma-induksiyon-akimi',                                          9,  true, now(), now()),
  ('a8110000-0000-4000-8000-000000000010', 'a5110000-0000-4000-8000-000000000002', 'Transformatörler',                                    'fiz-11-2-elektrik-ve-manyetizma-transformatorler',                                          10, true, now(), now()),
  -- 11.3 OPTİK (kutu sırası 11-18)
  ('a8110000-0000-4000-8000-000000000011', 'a5110000-0000-4000-8000-000000000003', 'Işık Şiddeti, Işık Akısı ve Aydınlanma',              'fiz-11-3-optik-isik-siddeti-isik-akisi-ve-aydinlanma',                                      11, true, now(), now()),
  ('a8110000-0000-4000-8000-000000000012', 'a5110000-0000-4000-8000-000000000003', 'Düzlem Aynalar',                                      'fiz-11-3-optik-duzlem-aynalar',                                                             12, true, now(), now()),
  ('a8110000-0000-4000-8000-000000000013', 'a5110000-0000-4000-8000-000000000003', 'Küresel Aynalar',                                     'fiz-11-3-optik-kuresel-aynalar',                                                            13, true, now(), now()),
  ('a8110000-0000-4000-8000-000000000014', 'a5110000-0000-4000-8000-000000000003', 'Kırılma',                                             'fiz-11-3-optik-kirilma',                                                                    14, true, now(), now()),
  ('a8110000-0000-4000-8000-000000000015', 'a5110000-0000-4000-8000-000000000003', 'Görünür Derinlik',                                    'fiz-11-3-optik-gorunur-derinlik',                                                           15, true, now(), now()),
  ('a8110000-0000-4000-8000-000000000016', 'a5110000-0000-4000-8000-000000000003', 'Fiber Optik',                                         'fiz-11-3-optik-fiber-optik',                                                                16, true, now(), now()),
  ('a8110000-0000-4000-8000-000000000017', 'a5110000-0000-4000-8000-000000000003', 'Prizmalar',                                           'fiz-11-3-optik-prizmalar',                                                                  17, true, now(), now()),
  ('a8110000-0000-4000-8000-000000000018', 'a5110000-0000-4000-8000-000000000003', 'Mercekler',                                           'fiz-11-3-optik-mercekler',                                                                  18, true, now(), now()),
  -- 12.1 KUVVET VE HAREKET (kutu sırası 1-6)
  ('a8120000-0000-4000-8000-000000000001', 'a5120000-0000-4000-8000-000000000001', 'Tork',                                                'fiz-12-1-kuvvet-ve-hareket-tork',                                                           1,  true, now(), now()),
  ('a8120000-0000-4000-8000-000000000002', 'a5120000-0000-4000-8000-000000000001', 'Denge',                                               'fiz-12-1-kuvvet-ve-hareket-denge',                                                          2,  true, now(), now()),
  ('a8120000-0000-4000-8000-000000000003', 'a5120000-0000-4000-8000-000000000001', 'İtme (İmpuls) ve Momentum',                           'fiz-12-1-kuvvet-ve-hareket-itme-impuls-ve-momentum',                                        3,  true, now(), now()),
  ('a8120000-0000-4000-8000-000000000004', 'a5120000-0000-4000-8000-000000000001', 'Momentumun Korunumu',                                 'fiz-12-1-kuvvet-ve-hareket-momentumun-korunumu',                                            4,  true, now(), now()),
  ('a8120000-0000-4000-8000-000000000005', 'a5120000-0000-4000-8000-000000000001', 'Eylemsizlik Momenti',                                 'fiz-12-1-kuvvet-ve-hareket-eylemsizlik-momenti',                                            5,  true, now(), now()),
  ('a8120000-0000-4000-8000-000000000006', 'a5120000-0000-4000-8000-000000000001', 'Açısal Momentum',                                     'fiz-12-1-kuvvet-ve-hareket-acisal-momentum',                                                6,  true, now(), now()),
  -- 12.2 ENERJİ (kutu sırası 7-11)
  ('a8120000-0000-4000-8000-000000000007', 'a5120000-0000-4000-8000-000000000002', 'Yay Sabiti',                                          'fiz-12-2-enerji-yay-sabiti',                                                                7,  true, now(), now()),
  ('a8120000-0000-4000-8000-000000000008', 'a5120000-0000-4000-8000-000000000002', 'Yayın Esneklik Potansiyel Enerjisi',                  'fiz-12-2-enerji-yayin-esneklik-potansiyel-enerjisi',                                        8,  true, now(), now()),
  ('a8120000-0000-4000-8000-000000000009', 'a5120000-0000-4000-8000-000000000002', 'Sürtünme Kuvvetinin Yaptığı İş',                      'fiz-12-2-enerji-surtunme-kuvvetinin-yaptigi-is',                                            9,  true, now(), now()),
  ('a8120000-0000-4000-8000-000000000010', 'a5120000-0000-4000-8000-000000000002', 'Enerjinin Korunumu',                                  'fiz-12-2-enerji-enerjinin-korunumu',                                                        10, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000011', 'a5120000-0000-4000-8000-000000000002', 'Verim',                                               'fiz-12-2-enerji-verim',                                                                     11, true, now(), now()),
  -- 12.3 DALGALAR (kutu sırası 12-18)
  ('a8120000-0000-4000-8000-000000000012', 'a5120000-0000-4000-8000-000000000003', 'Su Dalgalarında Kırınım',                             'fiz-12-3-dalgalar-su-dalgalarinda-kirinim',                                                 12, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000013', 'a5120000-0000-4000-8000-000000000003', 'Işıkta Kırınım',                                      'fiz-12-3-dalgalar-isikta-kirinim',                                                          13, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000014', 'a5120000-0000-4000-8000-000000000003', 'Su Dalgalarında Girişim',                             'fiz-12-3-dalgalar-su-dalgalarinda-girisim',                                                 14, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000015', 'a5120000-0000-4000-8000-000000000003', 'Işıkta Girişim',                                      'fiz-12-3-dalgalar-isikta-girisim',                                                          15, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000016', 'a5120000-0000-4000-8000-000000000003', 'Elektromanyetik Dalgalar',                            'fiz-12-3-dalgalar-elektromanyetik-dalgalar',                                                16, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000017', 'a5120000-0000-4000-8000-000000000003', 'Işık Renkleri',                                       'fiz-12-3-dalgalar-isik-renkleri',                                                           17, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000018', 'a5120000-0000-4000-8000-000000000003', 'Mekanik veya Elektromanyetik Dalgaların Kullanıldığı Cihazlar', 'fiz-12-3-dalgalar-mekanik-veya-elektromanyetik-dalgalarin-kullanildigi-cihazlar', 18, true, now(), now()),
  -- 12.4 MADDE VE DOĞASI (kutu sırası 19-25)
  ('a8120000-0000-4000-8000-000000000019', 'a5120000-0000-4000-8000-000000000004', 'Siyah Cisim Işıması',                                 'fiz-12-4-madde-ve-dogasi-siyah-cisim-isimasi',                                              19, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000020', 'a5120000-0000-4000-8000-000000000004', 'Fotoelektrik Etki',                                   'fiz-12-4-madde-ve-dogasi-fotoelektrik-etki',                                                20, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000021', 'a5120000-0000-4000-8000-000000000004', 'Yarı İletkenlik',                                     'fiz-12-4-madde-ve-dogasi-yari-iletkenlik',                                                  21, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000022', 'a5120000-0000-4000-8000-000000000004', 'Süper İletkenlik',                                    'fiz-12-4-madde-ve-dogasi-super-iletkenlik',                                                 22, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000023', 'a5120000-0000-4000-8000-000000000004', 'Standart Model',                                      'fiz-12-4-madde-ve-dogasi-standart-model',                                                   23, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000024', 'a5120000-0000-4000-8000-000000000004', 'Modern Atom Teorisi',                                 'fiz-12-4-madde-ve-dogasi-modern-atom-teorisi',                                              24, true, now(), now()),
  ('a8120000-0000-4000-8000-000000000025', 'a5120000-0000-4000-8000-000000000004', 'Nükleer Enerji',                                      'fiz-12-4-madde-ve-dogasi-nukleer-enerji',                                                   25, true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 3. YENİ FIZ.* OUTCOMES (84) — 22 mevcut kayıt BURADA YOK (id/kod/metin
--    sabittir; bağlantıları bölüm 4'te UPDATE edilir).
--    sort_order = k (ünite-içi; 125 sözleşmesi). subtopic_id = NULL
--    (kaynakta numaralandırılmamış — kasıtlı ve onaylı).
-- ============================================================
insert into public.curriculum_outcomes (
  id, curriculum_version_id, grade_level, subject_id, topic_id, subtopic_id,
  outcome_code, outcome_text, sort_order, source_reference, is_active, created_at, updated_at
) values
  -- 9. SINIF — ÜNİTE 1 (mevcut 9.1.1/9.1.2/9.1.4; yeni: 9.1.3)
  ('a9090000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000001', NULL, 'FIZ.9.1.3', 'Fizik bilimine katkıda bulunmuş bilim insanlarının deneyimlerini yansıtabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.15', true, now(), now()),
  -- 9. SINIF — ÜNİTE 2 (mevcut 9.2.1/9.2.2/9.2.4; yeni: 9.2.3, 9.2.5, 9.2.6, 9.2.7)
  ('a9090000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000002', NULL, 'FIZ.9.2.3', 'Aynı doğrultu üzerinde yer alan farklı vektörlerin yön ve büyüklüklerine yönelik bilimsel çıkarım yapabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.20', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000002', NULL, 'FIZ.9.2.5', 'Doğadaki temel kuvvetleri karşılaştırabilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.20', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000002', NULL, 'FIZ.9.2.6', 'Hareketin temel kavramlarının tanımlarına yönelik tümevarımsal akıl yürütebilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.20', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000002', NULL, 'FIZ.9.2.7', 'Hareket türlerini sınıflandırabilme', 7, 'TYMM 2026 Fizik Öğretim Programı, s.20', true, now(), now()),
  -- 9. SINIF — ÜNİTE 3 AKIŞKANLAR (tümü yeni)
  ('a9090000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000003', NULL, 'FIZ.9.3.1', 'Basınca yönelik bilimsel çıkarımlarda bulunabilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.25', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000003', NULL, 'FIZ.9.3.2', 'Durgun sıvılarda basınca yönelik bilimsel çıkarımlarda bulunabilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.25', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000003', NULL, 'FIZ.9.3.3', 'Sıvılarda basıncın kullanıldığı günlük hayat örneklerine ilişkin sorgulama yapabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.25', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000003', NULL, 'FIZ.9.3.4', 'Açık hava basıncına ilişkin çıkarım yapabilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.25', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000003', NULL, 'FIZ.9.3.5', 'Kaldırma kuvvetini etkileyen değişkenleri belirlemeye yönelik deney yapabilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.25', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000003', NULL, 'FIZ.9.3.6', 'Kaldırma kuvveti ile sıvılardaki basınca neden olan kuvvet arasındaki ilişkiye yönelik çıkarım yapabilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.25', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000003', NULL, 'FIZ.9.3.7', 'Akışkanın geçtiği borunun kesit alanı ile akışkanın sürati ve boru çeperlerine yaptığı basınç arasındaki ilişkiye yönelik tümevarımsal akıl yürütebilme', 7, 'TYMM 2026 Fizik Öğretim Programı, s.26', true, now(), now()),
  -- 9. SINIF — ÜNİTE 4 ENERJİ (tümü yeni)
  ('a9090000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000004', NULL, 'FIZ.9.4.1', 'İç enerjinin ısı ve sıcaklık ile arasındaki ilişki hakkında tümevarımsal akıl yürütebilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.32', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000004', NULL, 'FIZ.9.4.2', 'Isı, öz ısı, ısı sığası ve sıcaklık farkı arasındaki matematiksel modele ilişkin tümevarımsal akıl yürütebilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.32', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000021', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000004', NULL, 'FIZ.9.4.3', 'Hâl değiştirme sıcaklığında bulunan saf bir maddenin hâl değiştirmesi için alınan veya verilen ısı miktarının bağlı olduğu değişkenler hakkında bilimsel çıkarım yapabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.32', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000022', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000004', NULL, 'FIZ.9.4.4', 'Isıl denge durumu hakkında bilimsel gözlem yapabilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.32', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000023', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000004', NULL, 'FIZ.9.4.5', 'Isı aktarım yollarını sınıflayabilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.32', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000024', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5090000-0000-4000-8000-000000000004', NULL, 'FIZ.9.4.6', 'Günlük hayattaki deneyimlerinden yola çıkarak katı maddelerdeki ısı iletim hızını etkileyen etmenlere yönelik yansıtma yapabilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.32', true, now(), now()),
  -- 10. SINIF — ÜNİTE 1 (mevcut 10.1.3; yeni: 10.1.1, 10.1.2)
  ('a9100000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000001', NULL, 'FIZ.10.1.1', 'Yatay doğrultuda sabit hızlı hareket ile ilgili tümevarımsal akıl yürütebilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.37', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000001', NULL, 'FIZ.10.1.2', 'İvme ve hız değişimi arasındaki ilişkiye yönelik tümevarımsal akıl yürütebilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.37', true, now(), now()),
  -- 10. SINIF — ÜNİTE 2 (mevcut 10.2.1; yeni: 10.2.2, 10.2.3, 10.2.4, 10.2.5)
  ('a9100000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000002', NULL, 'FIZ.10.2.2', 'İş, enerji ve güç kavramlarına ilişkin çıkarım yapabilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.41', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000002', NULL, 'FIZ.10.2.3', 'Enerji biçimlerini karşılaştırabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.41', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000002', NULL, 'FIZ.10.2.4', 'Mekanik enerjiyi çözümleyebilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.41', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000002', NULL, 'FIZ.10.2.5', 'Yenilenebilen ve yenilenemeyen enerji kaynaklarını karşılaştırabilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.41', true, now(), now()),
  -- 10. SINIF — ÜNİTE 3 (mevcut 10.3.2/10.3.4/10.3.5; yeni: 10.3.1, 10.3.3, 10.3.6, 10.3.7)
  ('a9100000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000003', NULL, 'FIZ.10.3.1', 'Basit elektrik devresinde potansiyel fark, elektrik akımı ve direnç kavramlarının tanımına ilişkin analojik akıl yürütebilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.46', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000003', NULL, 'FIZ.10.3.3', 'Ohm Yasası ile ilgili tümevarımsal akıl yürütebilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.46', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000003', NULL, 'FIZ.10.3.6', 'Elektrik akımının oluşturabileceği tehlikelere karşı alınması gereken önlemlerle ilgili bilgi toplayabilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.46', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000003', NULL, 'FIZ.10.3.7', 'Topraklama olayının önemini sorgulayabilme', 7, 'TYMM 2026 Fizik Öğretim Programı, s.46', true, now(), now()),
  -- 10. SINIF — ÜNİTE 4 DALGALAR (tümü yeni)
  ('a9100000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000004', NULL, 'FIZ.10.4.1', 'Periyodik hareketlere ilişkin deneyimlerini yansıtabilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.52', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000004', NULL, 'FIZ.10.4.2', 'Dalgaların temel kavramlarına ilişkin operasyonel tanımlama yapabilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.52', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000004', NULL, 'FIZ.10.4.3', 'Dalgaları özelliklerine göre sınıflandırabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.52', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000004', NULL, 'FIZ.10.4.4', 'Dalgaların yayılma süratini etkileyen etmenlere ilişkin bilimsel gözleme dayalı tahmin yapabilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.52', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000004', NULL, 'FIZ.10.4.5', 'Su dalgalarında yansıma ve kırılma ile ilgili tümevarımsal akıl yürütebilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.52', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000021', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000004', NULL, 'FIZ.10.4.6', 'Rezonans ve depreme ilişkin kavramlar üzerinden depremi sorgulayabilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.52', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000022', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5100000-0000-4000-8000-000000000004', NULL, 'FIZ.10.4.7', 'Depremle ilgili bilimsel model oluşturabilme', 7, 'TYMM 2026 Fizik Öğretim Programı, s.52', true, now(), now()),
  -- 11. SINIF — ÜNİTE 1 (mevcut 11.1.1/11.1.3/11.1.4/11.1.7/11.1.10; yeni: 11.1.2, 11.1.5, 11.1.6, 11.1.8, 11.1.9)
  ('a9110000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000001', NULL, 'FIZ.11.1.2', 'Serbest düşme hareketi ile ilgili kanıt kullanabilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.59', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000001', NULL, 'FIZ.11.1.5', 'Newton''ın Hareket Yasalarını serbest cisim diyagramını kullanarak yorumlayabilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.59', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000001', NULL, 'FIZ.11.1.6', 'Statik ve kinetik sürtünme kuvvetlerini karşılaştırabilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.59', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000001', NULL, 'FIZ.11.1.8', 'Limit hızı etkileyen değişkenler ile ilgili bilimsel çıkarım yapabilme', 8, 'TYMM 2026 Fizik Öğretim Programı, s.59', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000001', NULL, 'FIZ.11.1.9', 'Düzgün çembersel hareket yapan cisimlerin yörüngeleri ve hız vektörleri hakkında analojik akıl yürütebilme', 9, 'TYMM 2026 Fizik Öğretim Programı, s.59', true, now(), now()),
  -- 11. SINIF — ÜNİTE 2 (mevcut 11.2.4/11.2.5/11.2.6; yeni: 11.2.1, 11.2.2, 11.2.3, 11.2.7 (s.66) ve 11.2.8-13 (s.67))
  ('a9110000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000002', NULL, 'FIZ.11.2.1', 'Elektrik yükleri arasındaki elektriksel kuvvetin matematiksel modeline yönelik tümevarımsal akıl yürütebilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.66', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000002', NULL, 'FIZ.11.2.2', 'Elektriksel alanın matematiksel modeline yönelik tümevarımsal akıl yürütebilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.66', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000002', NULL, 'FIZ.11.2.3', 'Faraday kafesi ve Faraday kafesinin kullanım alanları ile ilgili bilgi toplayabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.66', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000002', NULL, 'FIZ.11.2.7', 'Elektromıknatısların kullanım alanlarına ilişkin bilgi toplayabilme', 7, 'TYMM 2026 Fizik Öğretim Programı, s.66', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000002', NULL, 'FIZ.11.2.8', 'Manyetik alanda akım geçen düz bir tele etki eden kuvvete ilişkin matematiksel modele yönelik tümevarımsal akıl yürütebilme', 8, 'TYMM 2026 Fizik Öğretim Programı, s.67', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000002', NULL, 'FIZ.11.2.9', 'Manyetik alanda akım geçen düz bir tele etki eden kuvvet ile ilgili deneyimini elektrik motorlarının çalışma prensibine yansıtabilme', 9, 'TYMM 2026 Fizik Öğretim Programı, s.67', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000002', NULL, 'FIZ.11.2.10', 'Manyetik akıya etki eden etmenleri çözümleyebilme', 10, 'TYMM 2026 Fizik Öğretim Programı, s.67', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000021', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000002', NULL, 'FIZ.11.2.11', 'İndüksiyon geriliminin matematiksel modeline ilişkin tümevarımsal akıl yürütebilme', 11, 'TYMM 2026 Fizik Öğretim Programı, s.67', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000022', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000002', NULL, 'FIZ.11.2.12', 'İndüklenme sonucu oluşan alternatif (değişken) akım hakkında bilimsel çıkarım yapabilme', 12, 'TYMM 2026 Fizik Öğretim Programı, s.67', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000023', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000002', NULL, 'FIZ.11.2.13', 'Transformatörün yapısı ve kullanım alanlarına yönelik bilimsel çıkarım yapabilme', 13, 'TYMM 2026 Fizik Öğretim Programı, s.67', true, now(), now()),
  -- 11. SINIF — ÜNİTE 3 OPTİK (tümü yeni; 11.3.1-8 s.74, 11.3.9-10 s.75)
  ('a9110000-0000-4000-8000-000000000024', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000003', NULL, 'FIZ.11.3.1', 'Işık şiddeti, ışık akısı ve aydınlanma kavramlarına ilişkin bilimsel çıkarım yapabilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.74', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000025', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000003', NULL, 'FIZ.11.3.2', 'Düzlem aynaları kullanarak bilimsel model oluşturabilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.74', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000026', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000003', NULL, 'FIZ.11.3.3', 'Küresel aynaların özelliklerine ilişkin karşılaştırma yapabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.74', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000027', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000003', NULL, 'FIZ.11.3.4', 'Küresel aynalarda görüntü oluşumu ile ilgili deney yapabilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.74', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000028', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000003', NULL, 'FIZ.11.3.5', 'Işığın saydam ortamlardaki davranışını kullanarak deney yapabilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.74', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000029', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000003', NULL, 'FIZ.11.3.6', 'Saydam ortamlarda görünür derinliğin, gerçek derinlik ve ortamların ışığı kırma indislerine bağlı olarak değiştiğine ilişkin bilimsel gözlem yapabilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.74', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000030', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000003', NULL, 'FIZ.11.3.7', 'Fiber optik malzemelerin yapısı, çalışma prensibi ve kullanım alanlarına ilişkin bilgi toplayabilme', 7, 'TYMM 2026 Fizik Öğretim Programı, s.74', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000031', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000003', NULL, 'FIZ.11.3.8', 'Prizmalar ve prizmalar ile kurulan birleşik sistemlerde ışığın izlediği yola ilişkin tümdengelimsel akıl yürütebilme', 8, 'TYMM 2026 Fizik Öğretim Programı, s.74', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000032', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000003', NULL, 'FIZ.11.3.9', 'Merceklerin özelliklerine ilişkin karşılaştırma yapabilme', 9, 'TYMM 2026 Fizik Öğretim Programı, s.75', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000033', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5110000-0000-4000-8000-000000000003', NULL, 'FIZ.11.3.10', 'Merceklerde görüntü oluşumu ile ilgili deney yapabilme', 10, 'TYMM 2026 Fizik Öğretim Programı, s.75', true, now(), now()),
  -- 12. SINIF — ÜNİTE 1 (mevcut 12.1.3/12.1.5/12.1.6; yeni: 12.1.1, 12.1.2, 12.1.4)
  ('a9120000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000001', NULL, 'FIZ.12.1.1', 'Torkun matematiksel modeline yönelik tümevarımsal akıl yürütebilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.81', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000001', NULL, 'FIZ.12.1.2', 'Denge, kütle merkezi ve ağırlık merkezi ile ilgili kanıt kullanabilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.81', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000001', NULL, 'FIZ.12.1.4', 'Momentumun korunumunu veriye dayalı tahmin edebilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.81', true, now(), now()),
  -- 12. SINIF — ÜNİTE 2 ENERJİ (tümü yeni)
  ('a9120000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000002', NULL, 'FIZ.12.2.1', 'Yay sabitini tanımlamak için deney yapabilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.86', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000002', NULL, 'FIZ.12.2.2', 'Yay sabitinin matematiksel modeline ilişkin tümevarımsal akıl yürütebilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.86', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000002', NULL, 'FIZ.12.2.3', 'Yayın esneklik potansiyel enerjisinin matematiksel modeline ilişkin tümevarımsal akıl yürütebilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.86', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000002', NULL, 'FIZ.12.2.4', 'Sürtünme kuvvetinin yaptığı işe yönelik tümevarımsal akıl yürütebilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.86', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000002', NULL, 'FIZ.12.2.5', 'Enerjinin dönüşümü ve korunumuna ilişkin bilimsel çıkarım yapabilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.86', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000002', NULL, 'FIZ.12.2.6', 'Mekanik sistemlerin verimi ile ilgili tümevarımsal akıl yürütebilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.86', true, now(), now()),
  -- 12. SINIF — ÜNİTE 3 DALGALAR (tümü yeni)
  ('a9120000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000003', NULL, 'FIZ.12.3.1', 'Doğrusal su dalgalarında kırınım olayına ilişkin tümevarımsal akıl yürütebilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.91', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000003', NULL, 'FIZ.12.3.2', 'Dairesel su dalgalarında girişim olayına ilişkin tümevarımsal akıl yürütebilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.91', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000003', NULL, 'FIZ.12.3.3', 'Işıkta girişim ile ilgili deney yapabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.91', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000003', NULL, 'FIZ.12.3.4', 'Işıkta kırınım ile ilgili deney yapabilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.91', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000017', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000003', NULL, 'FIZ.12.3.5', 'Elektromanyetik dalgaları sınıflandırabilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.91', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000018', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000003', NULL, 'FIZ.12.3.6', 'Işık renklerinin dalga boyları hakkında tümevarımsal akıl yürütebilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.91', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000019', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000003', NULL, 'FIZ.12.3.7', 'Mekanik veya elektromanyetik dalgaların kullanıldığı cihazlardaki dalga türlerini sorgulayabilme', 7, 'TYMM 2026 Fizik Öğretim Programı, s.91', true, now(), now()),
  -- 12. SINIF — ÜNİTE 4 MADDE VE DOĞASI (tümü yeni)
  ('a9120000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000004', NULL, 'FIZ.12.4.1', 'Planck sabitinin modern fiziğin doğuşundaki etkisini çözümleyebilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.97', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000021', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000004', NULL, 'FIZ.12.4.2', 'Fotoelektrik etkinin bağlı olduğu koşullar ve foton kavramına ilişkin tümevarımsal akıl yürütebilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.97', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000022', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000004', NULL, 'FIZ.12.4.3', 'Fotoelektrik etkinin uygulamaları ile ilgili sorgulama yapabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.97', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000023', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000004', NULL, 'FIZ.12.4.4', 'Yarı iletkenlerin kullanım alanlarını ve önemini sorgulayabilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.97', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000024', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000004', NULL, 'FIZ.12.4.5', 'Süper iletkenlerin kullanım alanlarını ve önemini sorgulayabilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.97', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000025', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000004', NULL, 'FIZ.12.4.6', 'Standart modelin bileşenlerini çözümleyebilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.97', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000026', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000004', NULL, 'FIZ.12.4.7', 'Modern Atom Teorisi ile ilgili bilgileri yapılandırabilme', 7, 'TYMM 2026 Fizik Öğretim Programı, s.97', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000027', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'a5120000-0000-4000-8000-000000000004', NULL, 'FIZ.12.4.8', 'Nükleer enerjiyi sorgulayabilme', 8, 'TYMM 2026 Fizik Öğretim Programı, s.97', true, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 4. MEVCUT 22 KAZANIMIN ÜNİTE BAĞLANTISI (id/kod/metin DEĞİŞMEZ)
--    topic_id ← FIZ.s.u.k kodunun resmî ünite numarası (u); subtopic_id NULL
--    kalır (kaynakta numaralandırılmamış). IS DISTINCT FROM → tekrar koşum
--    0 satır günceller (idempotent).
-- ============================================================
-- 9.1 FİZİK BİLİMİ VE KARİYER KEŞFİ (FIZ.9.1.1, FIZ.9.1.2, FIZ.9.1.4)
update public.curriculum_outcomes
   set topic_id = 'a5090000-0000-4000-8000-000000000001', subtopic_id = NULL, updated_at = now()
 where id in (
       'a9090000-0000-4000-8000-000000000001',  -- FIZ.9.1.1
       'a9090000-0000-4000-8000-000000000002',  -- FIZ.9.1.2
       'a9090000-0000-4000-8000-000000000003'   -- FIZ.9.1.4
 ) and (topic_id is distinct from 'a5090000-0000-4000-8000-000000000001' or subtopic_id is not null);

-- 9.2 KUVVET VE HAREKET (FIZ.9.2.1, FIZ.9.2.2, FIZ.9.2.4)
update public.curriculum_outcomes
   set topic_id = 'a5090000-0000-4000-8000-000000000002', subtopic_id = NULL, updated_at = now()
 where id in (
       'a9090000-0000-4000-8000-000000000004',  -- FIZ.9.2.1
       'a9090000-0000-4000-8000-000000000005',  -- FIZ.9.2.2
       'a9090000-0000-4000-8000-000000000006'   -- FIZ.9.2.4
 ) and (topic_id is distinct from 'a5090000-0000-4000-8000-000000000002' or subtopic_id is not null);

-- 10.1 KUVVET VE HAREKET (FIZ.10.1.3)
update public.curriculum_outcomes
   set topic_id = 'a5100000-0000-4000-8000-000000000001', subtopic_id = NULL, updated_at = now()
 where id in ('a9100000-0000-4000-8000-000000000001')  -- FIZ.10.1.3
   and (topic_id is distinct from 'a5100000-0000-4000-8000-000000000001' or subtopic_id is not null);

-- 10.2 ENERJİ (FIZ.10.2.1)
update public.curriculum_outcomes
   set topic_id = 'a5100000-0000-4000-8000-000000000002', subtopic_id = NULL, updated_at = now()
 where id in ('a9100000-0000-4000-8000-000000000002')  -- FIZ.10.2.1
   and (topic_id is distinct from 'a5100000-0000-4000-8000-000000000002' or subtopic_id is not null);

-- 10.3 ELEKTRİK (FIZ.10.3.2, FIZ.10.3.4, FIZ.10.3.5)
update public.curriculum_outcomes
   set topic_id = 'a5100000-0000-4000-8000-000000000003', subtopic_id = NULL, updated_at = now()
 where id in (
       'a9100000-0000-4000-8000-000000000003',  -- FIZ.10.3.2
       'a9100000-0000-4000-8000-000000000004',  -- FIZ.10.3.4
       'a9100000-0000-4000-8000-000000000005'   -- FIZ.10.3.5
 ) and (topic_id is distinct from 'a5100000-0000-4000-8000-000000000003' or subtopic_id is not null);

-- 11.1 KUVVET VE HAREKET (FIZ.11.1.1, FIZ.11.1.3, FIZ.11.1.4, FIZ.11.1.7, FIZ.11.1.10)
update public.curriculum_outcomes
   set topic_id = 'a5110000-0000-4000-8000-000000000001', subtopic_id = NULL, updated_at = now()
 where id in (
       'a9110000-0000-4000-8000-000000000001',  -- FIZ.11.1.1
       'a9110000-0000-4000-8000-000000000002',  -- FIZ.11.1.3
       'a9110000-0000-4000-8000-000000000003',  -- FIZ.11.1.4
       'a9110000-0000-4000-8000-000000000004',  -- FIZ.11.1.7
       'a9110000-0000-4000-8000-000000000005'   -- FIZ.11.1.10
 ) and (topic_id is distinct from 'a5110000-0000-4000-8000-000000000001' or subtopic_id is not null);

-- 11.2 ELEKTRİK VE MANYETİZMA (FIZ.11.2.4, FIZ.11.2.5, FIZ.11.2.6)
update public.curriculum_outcomes
   set topic_id = 'a5110000-0000-4000-8000-000000000002', subtopic_id = NULL, updated_at = now()
 where id in (
       'a9110000-0000-4000-8000-000000000006',  -- FIZ.11.2.4
       'a9110000-0000-4000-8000-000000000007',  -- FIZ.11.2.5
       'a9110000-0000-4000-8000-000000000008'   -- FIZ.11.2.6
 ) and (topic_id is distinct from 'a5110000-0000-4000-8000-000000000002' or subtopic_id is not null);

-- 12.1 KUVVET VE HAREKET (FIZ.12.1.3, FIZ.12.1.5, FIZ.12.1.6)
update public.curriculum_outcomes
   set topic_id = 'a5120000-0000-4000-8000-000000000001', subtopic_id = NULL, updated_at = now()
 where id in (
       'a9120000-0000-4000-8000-000000000001',  -- FIZ.12.1.3
       'a9120000-0000-4000-8000-000000000002',  -- FIZ.12.1.5
       'a9120000-0000-4000-8000-000000000003'   -- FIZ.12.1.6
 ) and (topic_id is distinct from 'a5120000-0000-4000-8000-000000000001' or subtopic_id is not null);

-- ============================================================
-- 5. MIGRATION HISTORY — idempotent kayıt (psql koşumunda statements=NULL;
--    CLI koşan ortamda CLI'ın kendi kaydı varsa bu INSERT atlanır).
-- ============================================================
insert into supabase_migrations.schema_migrations (version, name, statements)
select '142', '142_curriculum_fizik_tymm2026_agac', NULL
 where not exists (
   select 1 from supabase_migrations.schema_migrations where version = '142'
 );

-- ============================================================
-- 6. SON DENETİM (transaction içi; beklentiden sapan durum COMMIT'i durdurur)
-- ============================================================
DO $final$
DECLARE
  v_t integer; v_s integer; v_o integer; v_null_t integer; v_null_s integer; v_linked integer;
BEGIN
  SELECT count(*) INTO v_t FROM public.topics WHERE subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3';
  SELECT count(*) INTO v_s FROM public.subtopics s JOIN public.topics t ON t.id = s.topic_id
   WHERE t.subject_id = '57a959a8-43e7-4f0e-8b54-a7299386fdb3';
  SELECT count(*),
         count(*) FILTER (WHERE topic_id IS NULL),
         count(*) FILTER (WHERE subtopic_id IS NULL),
         count(*) FILTER (WHERE topic_id IS NOT NULL)
    INTO v_o, v_null_t, v_null_s, v_linked
    FROM public.curriculum_outcomes WHERE outcome_code LIKE 'FIZ.%';
  IF v_t <> 15 OR v_s <> 82 OR v_o <> 106 OR v_null_t <> 0 OR v_null_s <> 106 OR v_linked <> 106 THEN
    RAISE EXCEPTION 'FINAL_142: beklenen 15/82/106 (topic/subtopic/outcome), topic-bağlı=106, NULL subtopic=106; bulunan %/%/%/%/%/%', v_t, v_s, v_o, v_linked, v_null_s, v_null_t;
  END IF;
END
$final$;

COMMIT;
