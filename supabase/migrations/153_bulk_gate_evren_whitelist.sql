-- ============================================================
-- 153_bulk_gate_evren_whitelist.sql — AK-QV-MODEL-03D-2 (6 Kasım 2026)
--
-- Toplu kapı kontrolü model beyaz listesi (private.bulk_allowed_models)
-- yönetici panelindeki BULK_MODEL_OPTIONS ile uyumlu hâle getirilir:
--   * opencode-go/glm-5.3-flash  — mevcut girdi KORUNUR
--   * evren/qwen3.8-flash-next   — operatör sözleşmeli sağlayıcı EKLENİR
--     (AK-QV-MODEL-01: canlı erişimi kanıtlı tek model;
--      AK-QV-MODEL-02: üretim parseQualityReply PASS;
--      AK-QV-MODEL-03B: panel seçeneği, kullanıcı kararı 2026-11-05)
--
-- Kapsam: YALNIZ bu fonksiyonun döndürdüğü dizi genişletilir.
-- İmza (text[]), LANGUAGE sql, STABLE, search_path='', sahiplik ve ACL
-- (yalnız service_role + sahip) BİREBİR korunur. Başka tablo, RPC veya
-- fonksiyon değişmez; ücretsiz (free-tier) model eklenmez.
-- Serbest (invoker) hak sahibi çağıran: public.start_bulk_gate_control.
-- Tekrar uygulanabilir (CREATE OR REPLACE + aynı GRANT/REVOKE idempotenttir).
-- ============================================================

CREATE OR REPLACE FUNCTION private.bulk_allowed_models()
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  SELECT ARRAY['opencode-go/glm-5.3-flash', 'evren/qwen3.8-flash-next']::text[];
$function$;

REVOKE ALL
  ON FUNCTION private.bulk_allowed_models()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION private.bulk_allowed_models()
  TO service_role;
