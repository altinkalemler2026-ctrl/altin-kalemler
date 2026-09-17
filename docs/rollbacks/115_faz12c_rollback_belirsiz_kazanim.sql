-- ============================================================
-- 115_faz12c_rollback_belirsiz_kazanim.sql
-- Altın Kalemler — Faz 12C rollback: migration 114'ün geri alınması
--
-- SCOP: VERİ SİLME (data-only). Şema/RLS/RPC değişmez.
--   Silinir: migration 114'ün eklediği 5 öğrenme çıktısı
--            (MAT.10.4.2, MAT.10.4.4, MAT.11.3.1, MAT.11.3.3, MAT.11.3.5).
--   Silinmez: Faz 12A/12B kayıtları (111/112), alt konular, TYMM-2026 versiyonu.
-- Idempotent: deterministic UUID listesi ile DELETE; zaten silinmişse 0 satır etkiler.
-- Uygulama: yalnız lokal DB (supabase_db_yarisma-programi), kullanıcı izniyle.
-- ============================================================

begin;

delete from public.curriculum_outcomes
where id in (
  'a7100000-0000-4000-8000-000000000020', -- MAT.10.4.2
  'a7100000-0000-4000-8000-000000000021', -- MAT.10.4.4
  'a7110000-0000-4000-8000-000000000013', -- MAT.11.3.1
  'a7110000-0000-4000-8000-000000000014', -- MAT.11.3.3
  'a7110000-0000-4000-8000-000000000015'  -- MAT.11.3.5
);

commit;