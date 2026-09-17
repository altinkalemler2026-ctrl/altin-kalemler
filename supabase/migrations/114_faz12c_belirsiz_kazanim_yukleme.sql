-- ============================================================
-- 114_faz12c_belirsiz_kazanim_yukleme.sql
-- Altın Kalemler — Faz 12C: MAT.10.4.2, MAT.10.4.4, MAT.11.3.1, MAT.11.3.3, MAT.11.3.5
--                        yüklemenin tamamlanması (5 belirsiz kazanım, resmî PDF doğrulamalı)
--
-- SCOP: VERİ YÜKLEME (data-only). Şema/RLS/RPC değişmez.
--   Yüklenen: curriculum_outcomes — Faz 12B'de matematiksel gösterim (üst simge/kesir/alt simge)
--             doğrulanamadığı için atlanan 5 öğrenme çıktısı. Metinler resmî TYMM 2026 PDF
--             (ortaogretim-matematik-dersi-ogretim-programi-tymm-2026.pdf) satır/kutu geometrisi
--             üzerinden birebir çıkarılmış ve üst/alt simge + kesir gösterimleri tekrar kurulmuştur.
--   YÜKLENMEZ: soru üretimi, AI, öğretmen onayı, UI, test1 değişikliği, alt konu (subtopic) değişikliği.
-- Kanıt eşlemesi (kod → PDF sayfası → gösterim):
--   MAT.10.4.2  → sf.104: f(x) = x²   (2 üst simge; üst simge satırı y=593.7 < ana metin y=588.2)
--   MAT.10.4.4  → sf.105: f(x) = 1/x  (kesir; "1" y=634.5 üst, "x" y=624.1 alt, aynı x≈321)
--   MAT.11.3.1  → sf.142: x ≠ π/2 + kπ (kesir; "π" y=730.9 üst, "2" y=719.6 alt, aynı x≈465)
--   MAT.11.3.3  → sf.149: f(x) = aˣ   (x üst simge; x y=756.7, a y=752.2, üst simge font 7)
--   MAT.11.3.5  → sf.149: f(x) = logₐx (a alt simge font 7; log y=317.4, a y=315.4)
-- UUID kuralı (112 ile aynı): a7 + GG (sınıf) + sıra (3 hane). Sıra ardışık devam eder:
--   10. sınıf son kayıt a710...019 → a710...020 (MAT.10.4.2), a710...021 (MAT.10.4.4);
--   11. sınıf son kayıt a711...012 → a711...013, a711...014, a711...015.
-- Idempotent: deterministic UUID + ON CONFLICT (id) DO NOTHING.
-- NOT: sort_order değerleri mevcut 112 yüklemesindeki komşu kayıtlarla tutarlıdır
--   (MAT.10.4.2→2, 10.4.4→4; 11.3.1→1; 11.3.3→1; 11.3.5→3). 11.3.x için sıralama
--   kod son basamağı değil, alt konu (subtopic) içi yerel sıradır: trig → 1,2;
--   üstel(3)→1, üstel ters(4)→2, logaritmik(5)→3, üstel-log problemleri(6)→4.
-- Kontrollü: Faz 12C uygulaması — yalnız bu 5 kayıt eklenir; önceki 85 kayıt ve 69 alt konu
--   (Faz 12B) değiştirilmez; rollback migration 113'e dokunulmaz.
-- ============================================================

begin;

insert into public.curriculum_outcomes (
  id, curriculum_version_id, grade_level, subject_id, topic_id, subtopic_id,
  outcome_code, outcome_text, sort_order, source_reference, is_active, created_at, updated_at
) values
  -- 10. sınıf — NİCELİKLER VE DEĞİŞİMLER: Karesel fonksiyon
  ('a7100000-0000-4000-8000-000000000020', 'a1000000-0000-4000-8000-0000000000c1', 10, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3100000-0000-4000-8000-000000000004', NULL, 'MAT.10.4.2', 'Gerçek sayılarda f(x) = x² şeklinde tanımlı karesel referans fonksiyonun nitel özellikleri ile bu fonksiyondan türetilen (g(x) = a ∙ f(x ± r) ± k (a, r, k ∈ ℝ, a ≠ 0)) karesel fonksiyonların nitel özelliklerine ilişkin matematiksel muhakeme yapabilme', 2, 'TYMM 2026, 10. sınıf', true, now(), now()),
  -- 10. sınıf — NİCELİKLER VE DEĞİŞİMLER: Rasyonel fonksiyon
  ('a7100000-0000-4000-8000-000000000021', 'a1000000-0000-4000-8000-0000000000c1', 10, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3100000-0000-4000-8000-000000000004', NULL, 'MAT.10.4.4', 'Gerçek sayılarda f(x) = 1/x (x ≠ 0) şeklinde tanımlı rasyonel referans fonksiyonun nitel özellikleri ile bu fonksiyondan türetilen (g(x) = a ∙ f(x ± r) ± k (a, r, k ∈ ℝ, a ≠ 0)) rasyonel fonksiyonların nitel özelliklerine ilişkin matematiksel muhakeme yapabilme', 4, 'TYMM 2026, 10. sınıf', true, now(), now()),
  -- 11. sınıf — NİCELİKLER VE DEĞİŞİMLER (1): Trigonometrik fonksiyonlar
  ('a7110000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-0000000000c1', 11, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3110000-0000-4000-8000-000000000003', NULL, 'MAT.11.3.1', 'f(x) = sinx (x ∈ ℝ), f(x) = cosx (x ∈ ℝ), f(x) = tanx (x ∈ ℝ, x ≠ π/2 + kπ, k ∈ ℤ) ve f(x) = cotx (x ∈ ℝ, x ≠ kπ, k ∈ ℤ) şeklinde tanımlı trigonometrik referans fonksiyonların nitel özellikleri ile bu fonksiyonlardan türetilen [g(x) = k ∙ f(mx ± r) ± s (k, m, r, s ∈ ℝ, k ≠ 0, m ≠ 0)] trigonometrik fonksiyonların nitel özelliklerine ilişkin matematiksel muhakeme yapabilme', 1, 'TYMM 2026, 11. sınıf', true, now(), now()),
  -- 11. sınıf — NİCELİKLER VE DEĞİŞİMLER (2): Üstel fonksiyonlar
  ('a7110000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-0000000000c1', 11, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3110000-0000-4000-8000-000000000003', NULL, 'MAT.11.3.3', 'Gerçek sayılarda f(x) = aˣ (a > 0, a ≠ 1) şeklinde tanımlı üstel referans fonksiyonun nitel özellikleri ile bu fonksiyondan türetilen [g(x) = k ∙ f(mx ± r) ± s (k, m, r, s ∈ ℝ, k ≠ 0, m ≠ 0)] üstel fonksiyonların nitel özelliklerine ilişkin matematiksel muhakeme yapabilme', 1, 'TYMM 2026, 11. sınıf', true, now(), now()),
  -- 11. sınıf — NİCELİKLER VE DEĞİŞİMLER (2): Logaritmik fonksiyonlar
  ('a7110000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-0000000000c1', 11, '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'a3110000-0000-4000-8000-000000000003', NULL, 'MAT.11.3.5', 'f(x) = logₐx (a > 0, a ≠ 1, x > 0) şeklinde tanımlı logaritmik referans fonksiyonun nitel özellikleri ile bu fonksiyondan türetilen [g(x) = k ∙ f(mx ± r) ± s (k, m, r, s ∈ ℝ, k ≠ 0, m ≠ 0)] logaritmik fonksiyonların nitel özelliklerine ilişkin matematiksel muhakeme yapabilme', 3, 'TYMM 2026, 11. sınıf', true, now(), now())
on conflict (id) do nothing;

commit;