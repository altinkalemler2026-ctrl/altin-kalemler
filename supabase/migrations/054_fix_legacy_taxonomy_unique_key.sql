-- ============================================================
-- 054_fix_legacy_taxonomy_unique_key.sql
-- Altın Kalemler
--
-- Legacy taxonomy unique key düzeltmesi
--
-- Amaç:
-- Eski Excel taxonomy kodlarını kayıpsız korumak.
--
-- Aynı:
--   sınıf + ders + konu adı
--
-- altında birden fazla legacy_code bulunabileceği için
-- legacy_code unique kimliğin parçasıdır.
-- ============================================================

begin;

drop index if exists public.idx_legacy_taxonomy_unique;

create unique index idx_legacy_taxonomy_unique
on public.legacy_taxonomy
using btree (
  source_name,
  grade_level,
  subject_name,
  legacy_code,
  topic_name,
  subtopic_name
)
nulls not distinct;

commit;