-- ============================================================
-- 125_faz22_fizik_tymm_2026_outcome_seed.sql
-- Altın Kalemler — Fizik P01 TYMM 2026 kanonik kazanım seed'i
--
-- SCOP: VERİ YÜKLEME (data-only). Şema/RLS/RPC/uygulama kodu değişmez.
--   Yüklenen: 1 yeni curriculum_versions satırı (Fizik TYMM 2026) + 22 kanonik
--             FIZ.* curriculum_outcomes kaydı. Fizik topic/subtopic satırı
--             DB'de yoktur; kazanımlar topic_id/subtopic_id = NULL ile bağlanır
--             (010 şemasında her ikisi nullable). Yalnız paketin fiilen
--             kullandığı kodlar eklenir; başka FIZ.* icat edilmez.
--   YÜKLENMEZ: soru üretimi, staging, AI, yayın, topic/subtopic oluşturma,
--             mevcut kayıt değiştirme, test değişikliği.
--
-- Kaynak (yalnız resmî): Türkiye Yüzyılı Maarif Modeli — FİZİK DERSİ
--   (9, 10, 11 VE 12. SINIFLAR) ÖĞRETİM PROGRAMI (2026)
--   PID 2254 · https://mufredat.meb.gov.tr/Dosyalar/2026518151437471-fizikd%C3%B6p.pdf
--   Yerel: docs/references/mufredat/2026-2027/tymm-2026-fizik-9-12.pdf
--   Sayfa: PDF basılı sayfa numaraları (rapor:
--   docs/reports/fizik-p01-curriculum-mapping-evidence.md)
--
-- curriculum_versions kararı (kullanıcı onaylı 2026-09-22): mevcut
--   tymm_2026 satırı source_name olarak "Matematik Dersi Öğretim Programı"
--   taşıdığından Fizik kazanımları ona bağlanmaz; ayrı append-only
--   'tymm_2026_fizik' versiyonu (id ...c3, is_default=false) eklenir.
--   UNIQUE(academic_year, framework) ile çakışmaz; varsayılan değişmez.
--
-- UUID kuralı: a9 + GG (sınıf) + 3 hane sıra — 'a9' MAT 'a7' serisiyle
--   çakışmaz (aynı desen, farklı aile). Deterministic + ON CONFLICT
--   (id) DO NOTHING → idempotent.
-- sort_order: kod son basamağına eşittir (Fizik alt konusu yok; ünite-içi
--   yerel sıra, 112/114 alt-konu-içi sıra anlayışına karşılık gelir).
-- ============================================================

begin;

-- ============================================================
-- 1. FİZİK TYMM 2026 curriculum_versions satırı
-- ============================================================

insert into public.curriculum_versions (
  id, academic_year, framework, source_name, source_url, published_at,
  is_active, is_default, created_at, updated_at
) values
  (
    'a1000000-0000-4000-8000-0000000000c3',
    '2026-2027',
    'tymm_2026_fizik',
    'Türkiye Yüzyılı Maarif Modeli Fizik Dersi (9, 10, 11 ve 12. Sınıflar) Öğretim Programı (2026)',
    'https://mufredat.meb.gov.tr/Dosyalar/2026518151437471-fizikd%C3%B6p.pdf',
    '2026-05-18',
    true, false, now(), now()
  )
on conflict (id) do nothing;

-- ============================================================
-- 2. KANONİK FIZ.* KAZANIMLAR (22) — subject: Fizik
--    (57a959a8-43e7-4f0e-8b54-a7299386fdb3, migration 045)
-- ============================================================

insert into public.curriculum_outcomes (
  id, curriculum_version_id, grade_level, subject_id, topic_id, subtopic_id,
  outcome_code, outcome_text, sort_order, source_reference, is_active, created_at, updated_at
) values
  -- 9. SINIF — FİZİK BİLİMİ VE KARİYER KEŞFİ
  ('a9090000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.9.1.1', 'Fizik biliminin tanımına yönelik tümevarımsal akıl yürütebilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.15', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.9.1.2', 'Fizik biliminin alt dallarını sınıflandırabilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.15', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.9.1.4', 'Bilim ve teknoloji alanında faaliyet gösteren kurum veya kuruluşlarda fizik bilimi ile ilişkili kariyer olanaklarını sorgulayabilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.15', true, now(), now()),
  -- 9. SINIF — KUVVET VE HAREKET
  ('a9090000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.9.2.1', 'Birimleri SI birim sisteminde verilen temel ve türetilmiş nicelikleri sınıflandırabilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.20', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.9.2.2', 'Skaler ve vektörel nicelikleri karşılaştırabilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.20', true, now(), now()),
  ('a9090000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c3', 9, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.9.2.4', 'Vektörlerin toplanmasında kullanılan uç uca ekleme ve paralelkenar yöntemi ile bileşenlerine ayırma işlemine ilişkin tümevarımsal akıl yürütebilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.20', true, now(), now()),
  -- 10. SINIF — KUVVET VE HAREKET
  ('a9100000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.10.1.3', 'Yatay doğrultuda sabit ivmeyle hareket eden cisimlerin hareket grafiklerinden elde edilen matematiksel modelleri yorumlayabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.37', true, now(), now()),
  -- 10. SINIF — ENERJİ
  ('a9100000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.10.2.1', 'Kuvvet-yer değiştirme grafiği kullanılarak iş ile ilgili tümevarımsal akıl yürütebilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.41', true, now(), now()),
  -- 10. SINIF — ELEKTRİK
  ('a9100000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.10.3.2', 'Elektrik yükünün hareketi üzerinden elektrik akımı kavramını çözümleyebilme', 2, 'TYMM 2026 Fizik Öğretim Programı, s.46', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.10.3.4', 'Dirençlerin bağlanma türüne göre eşdeğer dirence ilişkin bilimsel çıkarım yapabilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.46', true, now(), now()),
  ('a9100000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c3', 10, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.10.3.5', 'Üreteçlerin bağlanma türüne göre devreye sağladıkları potansiyel farka ilişkin bilimsel çıkarım yapabilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.46', true, now(), now()),
  -- 11. SINIF — KUVVET VE HAREKET
  ('a9110000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.11.1.1', 'Serbest düşme hareketi yapan cisimlerin ivmesine yönelik tümevarımsal akıl yürütebilme', 1, 'TYMM 2026 Fizik Öğretim Programı, s.59', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.11.1.3', 'İki boyutta sabit ivmeli hareket ile ilgili tümevarımsal akıl yürütebilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.59', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.11.1.4', 'Newton''ın Hareket Yasaları ile ilgili tümevarımsal akıl yürütebilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.59', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.11.1.7', 'Sürtünme kuvvetinin matematiksel modeline ilişkin tümevarımsal akıl yürütebilme', 7, 'TYMM 2026 Fizik Öğretim Programı, s.59', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.11.1.10', 'Düzgün çembersel hareketin değişkenleri arasındaki ilişkilerin matematiksel olarak modellenmesine ilişkin tümevarımsal akıl yürütebilme', 10, 'TYMM 2026 Fizik Öğretim Programı, s.59', true, now(), now()),
  -- 11. SINIF — ELEKTRİK VE MANYETİZMA
  ('a9110000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.11.2.4', 'Mıknatısların birbiriyle etkileşimine yönelik bilimsel gözlem yapabilme', 4, 'TYMM 2026 Fizik Öğretim Programı, s.66', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.11.2.5', 'Üzerinden akım geçen düz bir iletken telin oluşturduğu manyetik alana ilişkin tümevarımsal akıl yürütebilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.66', true, now(), now()),
  ('a9110000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-0000000000c3', 11, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.11.2.6', 'Akım makarasının merkez ekseninde oluşan manyetik alanın matematiksel modeline ilişkin tümevarımsal akıl yürütebilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.66', true, now(), now()),
  -- 12. SINIF — KUVVET VE HAREKET
  ('a9120000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.12.1.3', 'İtme (İmpuls) ve momentum değişimi arasındaki ilişkiye yönelik bilimsel çıkarım yapabilme', 3, 'TYMM 2026 Fizik Öğretim Programı, s.81', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.12.1.5', 'Eylemsizlik momentine yönelik tümevarımsal akıl yürütebilme', 5, 'TYMM 2026 Fizik Öğretim Programı, s.81', true, now(), now()),
  ('a9120000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c3', 12, '57a959a8-43e7-4f0e-8b54-a7299386fdb3', NULL, NULL, 'FIZ.12.1.6', 'Açısal momentumun korunumuna yönelik tümevarımsal akıl yürütebilme', 6, 'TYMM 2026 Fizik Öğretim Programı, s.81', true, now(), now())
on conflict (id) do nothing;

commit;