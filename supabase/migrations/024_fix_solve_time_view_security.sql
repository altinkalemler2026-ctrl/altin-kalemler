-- 024_fix_solve_time_view_security.sql
-- question_solve_time_overview view'ını
-- SECURITY INVOKER olarak çalıştır.
--
-- Böylece view'ı sorgulayan kullanıcının yetkileri
-- ve alttaki tabloların RLS politikaları uygulanır.

ALTER VIEW public.question_solve_time_overview
SET (security_invoker = true);


-- View'a genel erişimi kapat.
REVOKE ALL
ON public.question_solve_time_overview
FROM PUBLIC;

REVOKE ALL
ON public.question_solve_time_overview
FROM anon;

REVOKE ALL
ON public.question_solve_time_overview
FROM authenticated;


-- Şimdilik doğrudan client erişimi vermiyoruz.
-- Admin paneli için daha sonra güvenli RPC veya
-- özel admin erişim katmanı üzerinden kullanacağız.