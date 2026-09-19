-- ============================================================
-- qa_faz20_candidate_batch_fixture_local.sql
-- Altın Kalemler - SQL QA Faz 20 filter (yalniz disposable QA DB)
--
-- QA betigi (qa_faz20_candidate_batch_operation_status_local.sql)
-- '7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3' paketinin VAR oldugunu
-- varsayar (deterministik test paketi; gercek kullanici verisi
-- degildir, migration'larda gecmez). Bu dosya fixture'i olusturur:
--
--   * 1 adet candidate_question_batches (origin=curriculum_original,
--     raw_payload dummy, error_data dummy -> has_batch_error_data=true)
--   * 5 adet candidate_batch_candidate_results (pending/valid/invalid/
--     inserted/failed), failed olanin validation_errors'u dolu ->
--     candidate_validation_error_count=1
--
-- Idempotent: on conflict (id) do nothing (+ per-index cleanup islemi
-- yok). Yalniz disposable klonda, QA betiginden ONCE kosulur.
-- ============================================================

begin;

insert into public.candidate_question_batches (
  id, batch_key, origin, producer_id, producer_model, status,
  total_items, valid_items, invalid_items, inserted_items, duplicate_items,
  error_data, raw_payload, metadata
)
values (
  '7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3',
  'QA_FAZ20_BATCH_001',
  'curriculum_original',
  'qa-producer-faz20',
  'qa-model-faz20',
  'validated',
  5, 3, 1, 3, 1,
  '{"qa_fixture":"provider_orijinli dummy hata ozeti"}'::jsonb,
  '{"qa_fixture":true,"external_batch_key":"QA_FAZ20_BATCH_001"}'::jsonb,
  '{"qa_fixture":true}'::jsonb
)
on conflict (id) do nothing;

insert into public.candidate_batch_candidate_results (
  id, batch_id, candidate_index, client_question_id, validation_status,
  validation_errors, validation_warnings
)
values
  ('7ea1ff55-2d0d-4e65-b4d0-cade3724f001',
   '7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3', 0, 'qa-client-q-00',
   'pending', '[]'::jsonb, '[]'::jsonb),
  ('7ea1ff55-2d0d-4e65-b4d0-cade3724f002',
   '7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3', 1, 'qa-client-q-01',
   'valid', '[]'::jsonb, '[]'::jsonb),
  ('7ea1ff55-2d0d-4e65-b4d0-cade3724f003',
   '7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3', 2, 'qa-client-q-02',
   'invalid', '["dummy duzen hata"]'::jsonb, '[]'::jsonb),
  ('7ea1ff55-2d0d-4e65-b4d0-cade3724f004',
   '7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3', 3, 'qa-client-q-03',
   'inserted', '[]'::jsonb, '[]'::jsonb),
  ('7ea1ff55-2d0d-4e65-b4d0-cade3724f005',
   '7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3', 4, 'qa-client-q-04',
   'failed', '["dummy uretim hatasi"]'::jsonb, '[]'::jsonb)
on conflict (id) do nothing;

commit;