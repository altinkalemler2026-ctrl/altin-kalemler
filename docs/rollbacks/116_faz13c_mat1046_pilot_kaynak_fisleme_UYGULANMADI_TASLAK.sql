-- 116_faz13c_mat1046_pilot_kaynak_fisleme.sql
-- Faz 13C: MAT.10.4.6 pilot kaynak fişlemesi (önizleme taslağı).
--
-- DURUM: UYGULANMADI. Bu taslak, Faz 13C raporunun teslim parçasıdır.
-- Uygulama yalnızca ayrı ve açık kullanıcı onayı ile gerçekleştirilir.
--
-- Kapsam: Yalnızca 3 question_sources satırı. Şema değişikliği YOK.
-- İdempotentlik: file_name üzerinde NOT EXISTS guard (tabloda unique kısıt yok).
-- Kaynak veriler Faz 13B (sayfa doğrulama) ve Faz 13C (hash/boyut) kapsamında
-- salt-okunur alındı. Hiçbir soru metni/çözümü kopyalanmadı.
-- question_source_locations satırları SORU üretimi sonrası eklenecek (question_id
-- FK zorunlu). Lisans/sahiplik DB default'undadır; "inceleme gerekli" notu da
-- karar listesiyle saklanır (bkz. docs/reports/faz13c-mat1046-kaynak-fisleme-plani.md §5).

BEGIN;

INSERT INTO public.question_sources
  (source_type, title, publisher, author, publication_year, file_name,
   source_reference, ownership_status, license_status, commercial_use_allowed, notes)
SELECT 'pdf', 'matematik', NULL, NULL, NULL,
       'matematik.pdf',
       'D:\evraklar\proje\Meb Sorular\9-12\matematik.pdf',
       'unknown', 'unknown', false,
       'dogrulanmis kunye: sha256 fee06b28fbbafec7c81fac4e653bc2a80bfc4787bea6544eb206abaeb634efe; 35480489 bayt; 560 sayfa; basilı 421-456 MAT.10.4.6 denklem cozumlu+test; cevap 553-558 sahit; lisans incelemesi gerekli'
WHERE NOT EXISTS (SELECT 1 FROM public.question_sources WHERE file_name = 'matematik.pdf');

INSERT INTO public.question_sources
  (source_type, title, publisher, author, publication_year, file_name,
   source_reference, ownership_status, license_status, commercial_use_allowed, notes)
SELECT 'pdf', 'tyt-matematik', NULL, NULL, NULL,
       'tyt-matematik.pdf',
       'D:\evraklar\proje\Meb Sorular\9-12\tyt-matematik.pdf',
       'unknown', 'unknown', false,
       'dogrulanmis kunye: sha256 df65e71ce0a483aeb27c4c7d3099df440736a2c2a0579fa0f3097bb1a7fed6b7; 33313356 bayt; 160 sayfa; basilı 102-106 MAT.10.4.6 konu ozeti (yalniz denklem); lisans incelemesi gerekli'
WHERE NOT EXISTS (SELECT 1 FROM public.question_sources WHERE file_name = 'tyt-matematik.pdf');

INSERT INTO public.question_sources
  (source_type, title, publisher, author, publication_year, file_name,
   source_reference, ownership_status, license_status, commercial_use_allowed, notes)
SELECT 'pdf', 'matematik (2)', NULL, NULL, NULL,
       'matematik (2).pdf',
       'D:\evraklar\proje\Meb Sorular\9-12\matematik (2).pdf',
       'unknown', 'unknown', false,
       'dogrulanmis kunye: sha256 f24da478f7706ff9009de28644d75f0de730245d4ead3cddb17aa3cbc1d7dc0a; 20464449 bayt; 216 sayfa; basilı 35-41 esitsizlik/sistem/grafik; cevap 209-212 sahit; lisans incelemesi gerekli'
WHERE NOT EXISTS (SELECT 1 FROM public.question_sources WHERE file_name = 'matematik (2).pdf');

COMMIT;