BEGIN;


-- =========================================================
-- Phase 4B — Schema + Grant Hardening
-- =========================================================
-- 1. question_similarity_matches: eksik copyright_risk sütunu
-- 2. decide_teacher_review / teacher_review_admin_has_permission:
--    service_role EXECUTE'i kaldır
-- 3. ai_teacher_human_review_audit: REVOKE ALL → SELECT only


-- =========================================================
-- 1. COPYRIGHT RISK COLUMN
-- =========================================================
-- Migration 036'daki private.submit_originality_review(),
-- question_similarity_matches tablosuna INSERT sırasında
-- copyright_risk sütununu kullanır (satır 928).
-- Ancak sütun 006'da hiç eklenmemiş; RUNTIME HATASI.

ALTER TABLE public.question_similarity_matches
ADD COLUMN IF NOT EXISTS copyright_risk boolean
NOT NULL DEFAULT false;


-- =========================================================
-- 2. PUBLIC WRAPPER GRANTS — service_role KALDIR
-- =========================================================
-- Migration 090'da REVOKE ALL FROM PUBLIC/anon yapıldı,
-- ancak canlıya deployment sonrası service_role'a GRANT ALL
-- eklenmiş ve 090 bunu geri almamış.
-- Doğrulanmış durum: canlı dump'ta service_role'a EXECUTE var.

REVOKE ALL
ON FUNCTION public.decide_teacher_review(
  uuid, text, uuid, text
)
FROM service_role;

REVOKE ALL
ON FUNCTION public.teacher_review_admin_has_permission(text)
FROM service_role;


-- =========================================================
-- 3. AUDIT TABLE — DETERMINISTIC REVOKE → SELECT ONLY
-- =========================================================
-- 047'de yalnız GRANT SELECT TO service_role idi.
-- Canlıya deployment sonrası GRANT ALL TO anon/authenticated
-- eklenmiş. Deterministik REVOKE → sadece SELECT modeli.

REVOKE ALL ON TABLE public.ai_teacher_human_review_audit
FROM PUBLIC;

REVOKE ALL ON TABLE public.ai_teacher_human_review_audit
FROM anon;

REVOKE ALL ON TABLE public.ai_teacher_human_review_audit
FROM authenticated;

REVOKE ALL ON TABLE public.ai_teacher_human_review_audit
FROM service_role;

GRANT SELECT ON TABLE public.ai_teacher_human_review_audit
TO authenticated;

GRANT SELECT ON TABLE public.ai_teacher_human_review_audit
TO service_role;


COMMIT;
