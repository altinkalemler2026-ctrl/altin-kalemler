-- ============================================================
-- 111_faz12a_2026_2027_matematik_mufredati.sql
-- Altın Kalemler — Faz 12A: 2026-2027 Matematik Müfredatı (yıllık plan uygulaması)
--
-- SCOP: VERİ YÜKLEME (data-only). Şema/RLS/RPC değişmez.
--   Yüklenen: curriculum_versions, curriculum_schedule_profiles,
--             academic_weeks (resmî K1-K41, tatil haftaları dahil),
--             topics (TYMM 2026: 9/10/11; OGM 2018: 12), curriculum_schedule_items,
--             curriculum_prerequisites (resmî sıra/temel kabul zinciri), student profilleri.
--   YÜKLENMEZ: curriculum_teaching_approvals (otomatik onay YOK), question stock/sources,
--              soru üretimi, UI.
-- İdempotent: deterministic UUID'ler + ON CONFLICT DO NOTHING / UPDATE; yeniden çalıştırılabilir.
-- K1-K41 = resmî MEB 2026-2027 çalışma takvimi (14 Eyl 2026 – 25 Haz 2027).
-- Tatil haftaları K10, K20, K21, K26 satır olarak VAR; bu haftalara start_week ATANMAZ.
-- Kaynaklar: docs/reports/2026-2027-matematik-resmi-mufredat.md (§4),
--            docs/reports/2026-2027-matematik-yillik-konu-plani.md (§2 kanonik takvim, §3-§6).
-- ============================================================

begin;

-- ============================================================
-- 1. CURRICULUM_VERSIONS — TYMM-2026 (9/10/11) ve OGM-2018 (12)
--    Karar (Faz 12A): TYMM-2026 = is_default true (tek varsayılan).
--    Mevcut E2E7-FAZ7 varsayılanlığını flip'le: idx bir yılda tek default'a izin verir (059).
-- ============================================================

update public.curriculum_versions
   set is_default = false
 where id = 'e2e70000-0000-4000-8000-0000000000c1';

insert into public.curriculum_versions (
  id, academic_year, framework, source_name, source_url, published_at,
  is_active, is_default, created_at, updated_at
) values
  (
    'a1000000-0000-4000-8000-0000000000c1',
    '2026-2027',
    'tymm_2026',
    'Türkiye Yüzyılı Maarif Modeli Ortaöğretim Matematik Dersi Öğretim Programı (2026)',
    'https://mufredat.meb.gov.tr/',
    '2026-05-13',
    true, true, now(), now()
  ),
  (
    'a1000000-0000-4000-8000-0000000000c2',
    '2026-2027',
    'ogm_2018',
    'Ortaöğretim Matematik Dersi (9, 10, 11 ve 12. Sınıflar) Öğretim Programı (2018)',
    'https://mufredat.meb.gov.tr/',
    '2018-01-19',
    true, false, now(), now()
  )
on conflict (id) do update
  set is_active = excluded.is_active,
      is_default = excluded.is_default;
-- ON CONFLICT: yeniden çalıştırmada is_default doğrusunu koru.

-- ============================================================
-- 2. CURRICULUM_SCHEDULE_PROFILES
--    TYMM-PROF varsayılan (fmt); OGM-PROF açık atama (12. sınıf).
--    E2E7-PROF default'unu flip'le: _faz2_student_context tek default istiyor.
-- ============================================================

update public.curriculum_schedule_profiles
   set is_default = false
 where id = 'e2e70000-0000-4000-8000-0000000000c2';

insert into public.curriculum_schedule_profiles (
  id, code, name, description, curriculum_version_id,
  is_default, is_active, metadata, created_at, updated_at
) values
  (
    'a2000000-0000-4000-8000-0000000000c1',
    'TYMM2026-PROF-2026-2027',
    'TYMM 2026 (9-11) Varsayılan Plan',
    'MEB TYMM 2026 yıllık plan (9/10/11). 2026-2027 için sistem varsayılanı.',
    'a1000000-0000-4000-8000-0000000000c1',
    true, true, '{}'::jsonb, now(), now()
  ),
  (
    'a2000000-0000-4000-8000-0000000000c2',
    'OGM2018-PROF-2026-2027',
    'OGM 2018 (12) Plan',
    'OGM 2018 yıllık plan (12). Açık atama ile kullanılır (varsayılan değil).',
    'a1000000-0000-4000-8000-0000000000c2',
    false, true, '{}'::jsonb, now(), now()
  )
on conflict (id) do update
  set is_active = excluded.is_active,
      is_default = excluded.is_default;

-- ============================================================
-- 3. ACADEMIC_WEEKS — Resmî K1-K41 (tatil haftaları DAHİL)
--    Fixture (E2E7-FAZ7 44 hafta, 31 Ağu 2026 tabanlı) YERİNE resmî takvim.
--    start INCLUSIVE / end EXCLUSIVE: ends_at = sonraki takvim haftasının başlangıcı.
--    Tatil: K10, K20, K21, K26 (satır VAR; start_week atanmaz → burada yalnız takvim satırı).
-- ============================================================

delete from public.academic_weeks where academic_year = '2026-2027';

insert into public.academic_weeks (academic_year, week, starts_at, ends_at) values
  ('2026-2027', 1,  '2026-09-14', '2026-09-21'),
  ('2026-2027', 2,  '2026-09-21', '2026-09-28'),
  ('2026-2027', 3,  '2026-09-28', '2026-10-05'),
  ('2026-2027', 4,  '2026-10-05', '2026-10-12'),
  ('2026-2027', 5,  '2026-10-12', '2026-10-19'),
  ('2026-2027', 6,  '2026-10-19', '2026-10-26'),
  ('2026-2027', 7,  '2026-10-26', '2026-11-02'),
  ('2026-2027', 8,  '2026-11-02', '2026-11-09'),
  ('2026-2027', 9,  '2026-11-09', '2026-11-16'),
  ('2026-2027', 10, '2026-11-16', '2026-11-23'), -- K10 ara tatil
  ('2026-2027', 11, '2026-11-23', '2026-11-30'),
  ('2026-2027', 12, '2026-11-30', '2026-12-07'),
  ('2026-2027', 13, '2026-12-07', '2026-12-14'),
  ('2026-2027', 14, '2026-12-14', '2026-12-21'),
  ('2026-2027', 15, '2026-12-21', '2026-12-28'),
  ('2026-2027', 16, '2026-12-28', '2027-01-04'),
  ('2026-2027', 17, '2027-01-04', '2027-01-11'),
  ('2026-2027', 18, '2027-01-11', '2027-01-18'),
  ('2026-2027', 19, '2027-01-18', '2027-01-25'),
  ('2026-2027', 20, '2027-01-25', '2027-02-01'), -- K20 yarıyıl tatili
  ('2026-2027', 21, '2027-02-01', '2027-02-08'), -- K21 yarıyıl tatili
  ('2026-2027', 22, '2027-02-08', '2027-02-15'),
  ('2026-2027', 23, '2027-02-15', '2027-02-22'),
  ('2026-2027', 24, '2027-02-22', '2027-03-01'),
  ('2026-2027', 25, '2027-03-01', '2027-03-08'),
  ('2026-2027', 26, '2027-03-08', '2027-03-15'), -- K26 ara tatil
  ('2026-2027', 27, '2027-03-15', '2027-03-22'),
  ('2026-2027', 28, '2027-03-22', '2027-03-29'),
  ('2026-2027', 29, '2027-03-29', '2027-04-05'),
  ('2026-2027', 30, '2027-04-05', '2027-04-12'),
  ('2026-2027', 31, '2027-04-12', '2027-04-19'),
  ('2026-2027', 32, '2027-04-19', '2027-04-26'),
  ('2026-2027', 33, '2027-04-26', '2027-05-03'),
  ('2026-2027', 34, '2027-05-03', '2027-05-10'),
  ('2026-2027', 35, '2027-05-10', '2027-05-17'),
  ('2026-2027', 36, '2027-05-17', '2027-05-24'),
  ('2026-2027', 37, '2027-05-24', '2027-05-31'),
  ('2026-2027', 38, '2027-05-31', '2027-06-07'),
  ('2026-2027', 39, '2027-06-07', '2027-06-14'),
  ('2026-2027', 40, '2027-06-14', '2027-06-21'),
  ('2026-2027', 41, '2027-06-21', '2027-06-28')
on conflict (academic_year, week) do nothing;

-- ============================================================
-- 4. TOPICS — TYMM 2026 (9/10/11) ve OGM 2018 (12) tema ağacı
--    Konu adları: resmî-müfredat raporu §4. Slug: deterministic ASCII.
--    subject_id = Matematik sabiti (004/000 migration envanteri).
--    UUID şeması: a3 + GG (sınıf) + sıra (01..07).
-- ============================================================

insert into public.topics (
  id, subject_id, grade_level, name, slug, sort_order,
  is_active, curriculum_version_id, created_at, updated_at
) values
  -- Sınıf 9 (TYMM 2026)
  ('a3090000-0000-4000-8000-000000000001', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 9, 'MAT.9.1 SAYILAR', 'mat-9-1-sayilar', 1, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3090000-0000-4000-8000-000000000002', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 9, 'MAT.9.2 NİCELİKLER VE DEĞİŞİMLER', 'mat-9-2-nicelikler-ve-degisimler', 2, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3090000-0000-4000-8000-000000000003', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 9, 'MAT.9.3 GEOMETRİK ŞEKİLLER', 'mat-9-3-geometrik-sekiller', 3, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3090000-0000-4000-8000-000000000004', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 9, 'MAT.9.4 EŞLİK VE BENZERLİK', 'mat-9-4-eslik-ve-benzerlik', 4, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3090000-0000-4000-8000-000000000005', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 9, 'MAT.9.5 ALGORİTMA VE BİLİŞİM', 'mat-9-5-algoritma-ve-bilisim', 5, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3090000-0000-4000-8000-000000000006', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 9, 'MAT.9.6 İSTATİSTİKSEL ARAŞTIRMA SÜRECİ', 'mat-9-6-istatistiksel-arastirma-sureci', 6, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3090000-0000-4000-8000-000000000007', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 9, 'MAT.9.7 VERİDEN OLASIĞA', 'mat-9-7-veriden-olasioga', 7, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  -- Sınıf 10 (TYMM 2026)
  ('a3100000-0000-4000-8000-000000000001', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10, 'MAT.10.1 GEOMETRİK ŞEKİLLER', 'mat-10-1-geometrik-sekiller', 1, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3100000-0000-4000-8000-000000000002', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10, 'MAT.10.2 İSTATİSTİKSEL ARAŞTIRMA SÜRECİ', 'mat-10-2-istatistiksel-arastirma-sureci', 2, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3100000-0000-4000-8000-000000000003', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10, 'MAT.10.3 SAYILAR', 'mat-10-3-sayilar', 3, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3100000-0000-4000-8000-000000000004', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10, 'MAT.10.4 NİCELİKLER VE DEĞİŞİMLER', 'mat-10-4-nicelikler-ve-degisimler', 4, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3100000-0000-4000-8000-000000000005', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10, 'MAT.10.5 SAYMA, ALGORİTMA VE BİLİŞİM', 'mat-10-5-sayma-algoritma-ve-bilisim', 5, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3100000-0000-4000-8000-000000000006', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10, 'MAT.10.6 ANALİTİK İNCELEME', 'mat-10-6-analitik-inceleme', 6, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3100000-0000-4000-8000-000000000007', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 10, 'MAT.10.7 VERİDEN OLASIĞA', 'mat-10-7-veriden-olasioga', 7, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  -- Sınıf 11 (TYMM 2026)
  ('a3110000-0000-4000-8000-000000000001', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 11, 'MAT.11.1 İSTATİSTİKSEL ARAŞTIRMA SÜRECİ', 'mat-11-1-istatistiksel-arastirma-sureci', 1, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3110000-0000-4000-8000-000000000002', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 11, 'MAT.11.2 GEOMETRİK ŞEKİLLER', 'mat-11-2-geometrik-sekiller', 2, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  ('a3110000-0000-4000-8000-000000000003', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 11, 'MAT.11.3 NİCELİKLER VE DEĞİŞİMLER', 'mat-11-3-nicelikler-ve-degisimler', 3, true, 'a1000000-0000-4000-8000-0000000000c1', now(), now()),
  -- Sınıf 12 (OGM 2018)
  ('a3120000-0000-4000-8000-000000000001', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 12, '12.1 ÜSTEL VE LOGARİTMİK FONKSİYONLAR', 'mat-12-1-ustel-ve-logaritmik-fonksiyonlar', 1, true, 'a1000000-0000-4000-8000-0000000000c2', now(), now()),
  ('a3120000-0000-4000-8000-000000000002', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 12, '12.2 DİZİLER', 'mat-12-2-diziler', 2, true, 'a1000000-0000-4000-8000-0000000000c2', now(), now()),
  ('a3120000-0000-4000-8000-000000000003', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 12, '12.3 TRİGONOMETRİ', 'mat-12-3-trigonometri', 3, true, 'a1000000-0000-4000-8000-0000000000c2', now(), now()),
  ('a3120000-0000-4000-8000-000000000004', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 12, '12.4 DÖNÜŞÜMLER', 'mat-12-4-donusumler', 4, true, 'a1000000-0000-4000-8000-0000000000c2', now(), now()),
  ('a3120000-0000-4000-8000-000000000005', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 12, '12.5 TÜREV', 'mat-12-5-turev', 5, true, 'a1000000-0000-4000-8000-0000000000c2', now(), now()),
  ('a3120000-0000-4000-8000-000000000006', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 12, '12.6 İNTEGRAL', 'mat-12-6-integral', 6, true, 'a1000000-0000-4000-8000-0000000000c2', now(), now()),
  ('a3120000-0000-4000-8000-000000000007', '430903f3-527e-4e12-b7e8-ac0afdb784aa', 12, '12.7 ANALİTİK GEOMETRİ', 'mat-12-7-analitik-geometri', 7, true, 'a1000000-0000-4000-8000-0000000000c2', now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 5. CURRICULUM_SCHEDULE_ITEMS — T# → K# yerleştirme (yillik plan §2 kanonik haftalar)
--    start_week = K# (takvim haftası); end_week EXCLUSIVE (bir sonraki K# başlangıcı).
--    Kanonik start'lar: G9=1,7,14,16,24,30,36 | G10=1,7,12,15,28,32,36
--                       G11=1,5,16,25,33 | G12=1,7,11,17,22,30,37
--    Tatil haftalarına (K10/20/21/26) start_week ATANMAZ: tüm start_week değerleri
--    öğretim haftalarınadır; tatil satırları yalnız takvim (dönem çözümü) içindir.
--    end_week YALNIZ güncel içerik penceresi; antrenman kapatmaz (059).
--    MAT.11.3: 3 ayrı açılış penceresi → 3 schedule item satırı.
-- ============================================================

insert into public.curriculum_schedule_items (
  id, schedule_profile_id, grade_level, subject_id, topic_id,
  start_week, end_week, is_active, metadata, created_at, updated_at
) values
  -- Sınıf 9 (TYMM-PROF)
  ('a4090000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-0000000000c1', 9, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3090000-0000-4000-8000-000000000001', 1,  7,  true, '{}'::jsonb, now(), now()),
  ('a4090000-0000-4000-8000-000000000002', 'a2000000-0000-4000-8000-0000000000c1', 9, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3090000-0000-4000-8000-000000000002', 7,  14, true, '{}'::jsonb, now(), now()),
  ('a4090000-0000-4000-8000-000000000003', 'a2000000-0000-4000-8000-0000000000c1', 9, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3090000-0000-4000-8000-000000000003', 14, 16, true, '{}'::jsonb, now(), now()),
  ('a4090000-0000-4000-8000-000000000004', 'a2000000-0000-4000-8000-0000000000c1', 9, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3090000-0000-4000-8000-000000000004', 16, 24, true, '{}'::jsonb, now(), now()),
  ('a4090000-0000-4000-8000-000000000005', 'a2000000-0000-4000-8000-0000000000c1', 9, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3090000-0000-4000-8000-000000000005', 24, 30, true, '{}'::jsonb, now(), now()),
  ('a4090000-0000-4000-8000-000000000006', 'a2000000-0000-4000-8000-0000000000c1', 9, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3090000-0000-4000-8000-000000000006', 30, 36, true, '{}'::jsonb, now(), now()),
  ('a4090000-0000-4000-8000-000000000007', 'a2000000-0000-4000-8000-0000000000c1', 9, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3090000-0000-4000-8000-000000000007', 36, NULL, true, '{}'::jsonb, now(), now()),
  -- Sınıf 10 (TYMM-PROF)
  ('a4100000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-0000000000c1', 10, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3100000-0000-4000-8000-000000000001', 1,  7,  true, '{}'::jsonb, now(), now()),
  ('a4100000-0000-4000-8000-000000000002', 'a2000000-0000-4000-8000-0000000000c1', 10, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3100000-0000-4000-8000-000000000002', 7,  12, true, '{}'::jsonb, now(), now()),
  ('a4100000-0000-4000-8000-000000000003', 'a2000000-0000-4000-8000-0000000000c1', 10, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3100000-0000-4000-8000-000000000003', 12, 15, true, '{}'::jsonb, now(), now()),
  ('a4100000-0000-4000-8000-000000000004', 'a2000000-0000-4000-8000-0000000000c1', 10, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3100000-0000-4000-8000-000000000004', 15, 28, true, '{}'::jsonb, now(), now()),
  ('a4100000-0000-4000-8000-000000000005', 'a2000000-0000-4000-8000-0000000000c1', 10, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3100000-0000-4000-8000-000000000005', 28, 32, true, '{}'::jsonb, now(), now()),
  ('a4100000-0000-4000-8000-000000000006', 'a2000000-0000-4000-8000-0000000000c1', 10, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3100000-0000-4000-8000-000000000006', 32, 36, true, '{}'::jsonb, now(), now()),
  ('a4100000-0000-4000-8000-000000000007', 'a2000000-0000-4000-8000-0000000000c1', 10, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3100000-0000-4000-8000-000000000007', 36, NULL, true, '{}'::jsonb, now(), now()),
  -- Sınıf 11 (TYMM-PROF) — MAT.11.3 üç pencere
  ('a4110000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-0000000000c1', 11, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3110000-0000-4000-8000-000000000001', 1,  5,  true, '{}'::jsonb, now(), now()),
  ('a4110000-0000-4000-8000-000000000002', 'a2000000-0000-4000-8000-0000000000c1', 11, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3110000-0000-4000-8000-000000000002', 5,  16, true, '{}'::jsonb, now(), now()),
  ('a4110000-0000-4000-8000-000000000003', 'a2000000-0000-4000-8000-0000000000c1', 11, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3110000-0000-4000-8000-000000000003', 16, 25, true, '{}'::jsonb, now(), now()),
  ('a4110000-0000-4000-8000-000000000004', 'a2000000-0000-4000-8000-0000000000c1', 11, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3110000-0000-4000-8000-000000000003', 25, 33, true, '{}'::jsonb, now(), now()),
  ('a4110000-0000-4000-8000-000000000005', 'a2000000-0000-4000-8000-0000000000c1', 11, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3110000-0000-4000-8000-000000000003', 33, NULL, true, '{}'::jsonb, now(), now()),
  -- Sınıf 12 (OGM-PROF)
  ('a4120000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-0000000000c2', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3120000-0000-4000-8000-000000000001', 1,  7,  true, '{}'::jsonb, now(), now()),
  ('a4120000-0000-4000-8000-000000000002', 'a2000000-0000-4000-8000-0000000000c2', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3120000-0000-4000-8000-000000000002', 7,  11, true, '{}'::jsonb, now(), now()),
  ('a4120000-0000-4000-8000-000000000003', 'a2000000-0000-4000-8000-0000000000c2', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3120000-0000-4000-8000-000000000003', 11, 17, true, '{}'::jsonb, now(), now()),
  ('a4120000-0000-4000-8000-000000000004', 'a2000000-0000-4000-8000-0000000000c2', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3120000-0000-4000-8000-000000000004', 17, 22, true, '{}'::jsonb, now(), now()),
  ('a4120000-0000-4000-8000-000000000005', 'a2000000-0000-4000-8000-0000000000c2', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3120000-0000-4000-8000-000000000005', 22, 30, true, '{}'::jsonb, now(), now()),
  ('a4120000-0000-4000-8000-000000000006', 'a2000000-0000-4000-8000-0000000000c2', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3120000-0000-4000-8000-000000000006', 30, 37, true, '{}'::jsonb, now(), now()),
  ('a4120000-0000-4000-8000-000000000007', 'a2000000-0000-4000-8000-0000000000c2', 12, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3120000-0000-4000-8000-000000000007', 37, NULL, true, '{}'::jsonb, now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 6. CURRICULUM_PREREQUISITES — Resmî sıra / "Temel Kabul" zinciri
--    requirement_level='required', review_status='approved' → gate (c) fail-closed.
--    source_type='manual' (resmî sıradan; AI ile üretilmedi).
--    Zincir: 9 → 10 → 11 (TYMM) ve 12 ünite içi ardışıklık (OGM).
--    prerequisite_grade_level = önkoşul konunun sınıfı (check 1-12).
-- ============================================================

insert into public.curriculum_prerequisites (
  id, curriculum_version_id, target_topic_id, prerequisite_topic_id,
  prerequisite_grade_level, requirement_level, source_type, confidence,
  review_status, notes, created_at, updated_at
) values
  -- Sınıf 10 → 9 (TYMM zincir öncelikleri; resmî Temel Kabul özetleri)
  ('a5100000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c1', 'a3100000-0000-4000-8000-000000000001', 'a3090000-0000-4000-8000-000000000003', 9, 'required', 'manual', 1.0, 'approved', '10.1 ← 9.3 üçgen temel elemanları (resmî temel kabul)', now(), now()),
  ('a5100000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c1', 'a3100000-0000-4000-8000-000000000002', 'a3090000-0000-4000-8000-000000000006', 9, 'required', 'manual', 1.0, 'approved', '10.2 ← 9.6 istatistik süreci (resmî temel kabul)', now(), now()),
  ('a5100000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c1', 'a3100000-0000-4000-8000-000000000003', 'a3090000-0000-4000-8000-000000000001', 9, 'required', 'manual', 1.0, 'approved', '10.3 ← 9.1 sayılar/asal çarpan (resmî temel kabul)', now(), now()),
  ('a5100000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c1', 'a3100000-0000-4000-8000-000000000004', 'a3090000-0000-4000-8000-000000000002', 9, 'required', 'manual', 1.0, 'approved', '10.4 ← 9.2 doğrusal/mutlak referans (resmî temel kabul)', now(), now()),
  ('a5100000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c1', 'a3100000-0000-4000-8000-000000000005', 'a3090000-0000-4000-8000-000000000005', 9, 'required', 'manual', 1.0, 'approved', '10.5 ← 9.5 algoritma (resmî temel kabul)', now(), now()),
  ('a5100000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c1', 'a3100000-0000-4000-8000-000000000006', 'a3090000-0000-4000-8000-000000000004', 9, 'required', 'manual', 1.0, 'approved', '10.6 ← 9.4 Tales/Pisagor/koordinat (resmî temel kabul)', now(), now()),
  ('a5100000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-0000000000c1', 'a3100000-0000-4000-8000-000000000007', 'a3090000-0000-4000-8000-000000000007', 9, 'required', 'manual', 1.0, 'approved', '10.7 ← 9.7 olasılık yaklaşımları (resmî temel kabul)', now(), now()),
  -- Sınıf 11 → 10 (TYMM zincir)
  ('a5110000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c1', 'a3110000-0000-4000-8000-000000000001', 'a3100000-0000-4000-8000-000000000002', 10, 'required', 'manual', 1.0, 'approved', '11.1 ← 10.2 iki kategorik (resmî temel kabul)', now(), now()),
  ('a5110000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c1', 'a3110000-0000-4000-8000-000000000002', 'a3100000-0000-4000-8000-000000000001', 10, 'required', 'manual', 1.0, 'approved', '11.2 ← 10.1 üçgen/alan (resmî temel kabul)', now(), now()),
  ('a5110000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c1', 'a3110000-0000-4000-8000-000000000003', 'a3100000-0000-4000-8000-000000000004', 10, 'required', 'manual', 1.0, 'approved', '11.3 ← 10.4 fonksiyon zinciri (resmî temel kabul)', now(), now()),
  -- Sınıf 12 ünite içi ardışıklık (OGM 2018)
  ('a5120000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c2', 'a3120000-0000-4000-8000-000000000002', 'a3120000-0000-4000-8000-000000000001', 12, 'required', 'manual', 1.0, 'approved', '12.2 ← 12.1 üstel/l ogaritma (OGM ünite sırası)', now(), now()),
  ('a5120000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000c2', 'a3120000-0000-4000-8000-000000000003', 'a3120000-0000-4000-8000-000000000002', 12, 'required', 'manual', 1.0, 'approved', '12.3 ← 12.2 diziler (OGM ünite sırası)', now(), now()),
  ('a5120000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-0000000000c2', 'a3120000-0000-4000-8000-000000000004', 'a3120000-0000-4000-8000-000000000003', 12, 'required', 'manual', 1.0, 'approved', '12.4 ← 12.3 trigonometri (OGM ünite sırası)', now(), now()),
  ('a5120000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-0000000000c2', 'a3120000-0000-4000-8000-000000000005', 'a3120000-0000-4000-8000-000000000004', 12, 'required', 'manual', 1.0, 'approved', '12.5 ← 12.4 dönüşümler (OGM ünite sırası)', now(), now()),
  ('a5120000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-0000000000c2', 'a3120000-0000-4000-8000-000000000006', 'a3120000-0000-4000-8000-000000000005', 12, 'required', 'manual', 1.0, 'approved', '12.6 ← 12.5 türev (OGM ünite sırası)', now(), now()),
  ('a5120000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-0000000000c2', 'a3120000-0000-4000-8000-000000000007', 'a3120000-0000-4000-8000-000000000006', 12, 'required', 'manual', 1.0, 'approved', '12.7 ← 12.6 integral (OGM ünite sırası)', now(), now())
on conflict (id) do nothing;

-- ============================================================
-- 7. STUDENT_PROFILES — schedule_profile_id ataması (karar: yalnız net e2e fixture)
--    E2E_Ogrenci_A/B (grade 12) → OGM2018-PROF. FZ15A öğrencisi dokunulmaz.
--    test1 (kancaselami@gmail.com — gerçek görünümlü) → ATANMAZ (durum raporu #8).
--    Guard trigger yalnız authenticated'ı engeller; migration postgres olarak çalışır (059 §7).
-- ============================================================

update public.student_profiles
   set schedule_profile_id = 'a2000000-0000-4000-8000-0000000000c2'
 where id in (
   '89e2b1bc-2cc7-4e4e-93ee-0dfd43d69607', -- E2E_Ogrenci_A
   'a31377de-fd7b-449a-b874-f22c8344deb0'  -- E2E_Ogrenci_B
 );


commit;