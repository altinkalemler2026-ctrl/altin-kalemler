-- ============================================================
-- 089_admin_audit_and_question_edit.sql
-- Phase 4A — GENERIC IMMUTABLE AUDIT LOG + audit.view +
--            CONTROLLED QUESTION MUTATION RPC (admin_question_edit)
--
-- Tasarım (Phase 4A security refinement):
--   1. Genel, EKLEMSEL (append-only), DEĞİŞMEZ (immutable)
--      public.admin_audit_log tablosu.
--       - Yalnızca SECURITY DEFINER mutation fonksiyonları yazar.
--       - authenticated/browser için INSERT/UPDATE/DELETE politika
--         YOKTUR -> doğrudan yazım DENIED.
--       - SELECT yalnızca audit.view sahibi admin'e.
--   2. audit.view yetki kodu + super_admin'e minimum, açık atama.
--   3. public.questions için TEK dar, kontrollü mutation RPC:
--      admin_question_edit (public INVOKER sarmalayıcı ->
--      private SECURITY DEFINER). İzin: questions.edit.
--      - Yaşam döngüsü/güvenlik alanları (approval_status, is_active,
--        ownership_status, license_status, id, question_code, vb.)
--        DÜZENLENEMEZ; kanonik approve/reject/activate/deactivate
--        akışlarına (014/040/047) bırakılır.
--      - Mutation + audit aynı fonksiyon = AYNI transaction => atomik.
--
-- Model, migration 040 (controlled_question_activation) tarafından
-- kurulan kanonik SECURITY DEFINER desenini birebir izler:
--   public.* INVOKER sarmalayici -> private.* DEFINER,
--   SET search_path = '', schema-qualified, katı validasyon,
--   explicit EXECUTE grant + PUBLIC revoke, atomik mutation+audit.
-- ============================================================

BEGIN;


-- ============================================================
-- 1. GENEL IMMUTABLE AUDIT LOG TABLOSU
-- ============================================================

CREATE TABLE IF NOT EXISTS public.admin_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action_code text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  performed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_entity
ON public.admin_audit_log(entity_type, entity_id, performed_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_actor
ON public.admin_audit_log(actor_user_id, performed_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_action
ON public.admin_audit_log(action_code, performed_at DESC);

ALTER TABLE public.admin_audit_log
ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 2. AUDIT LOG RLS — EKLEMSEL / DEĞİŞMEZ
--    Sadece SELECT policy (audit.view). INSERT/UPDATE/DELETE
--    politikası YOKTUR -> authenticated/browser doğrudan yazamaz;
--    yazım yalnızca SECURITY DEFINER fonksiyonlarından (sahip olarak)
--    yapılır.
-- ============================================================

DROP POLICY IF EXISTS "audit view admins read audit log"
ON public.admin_audit_log;

CREATE POLICY "audit view admins read audit log"
ON public.admin_audit_log
FOR SELECT
TO authenticated
USING (
  public.current_user_has_admin_permission('audit.view')
);

GRANT SELECT
ON public.admin_audit_log
TO authenticated;


-- ============================================================
-- 3. audit.view YETKİSİ + SUPER ADMIN ATAMASI
--    (yalnızca audit.view tohumlanır; questions.review,
--     admins.manage, roles.manage tohumlanmaz.)
-- ============================================================

INSERT INTO public.admin_permissions (
  permission_code,
  name,
  description
)
VALUES (
  'audit.view',
  'Denetim Kaydını Görüntüle',
  'Genel denetim kaydını (admin_audit_log) görüntüleyebilir.'
)
ON CONFLICT (permission_code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description;

-- Minimum, açık ve belirsiz olmayan atama: yalnızca super_admin
-- denetim kaydını okur. content/question/copyright rolleri bu fazda
-- audit.view almaz.
INSERT INTO public.admin_role_permissions (role_id, permission_id, created_at)
SELECT ar.id, ap.id, now()
FROM public.admin_roles ar
JOIN public.admin_permissions ap
  ON ap.permission_code = 'audit.view'
WHERE ar.role_code = 'super_admin'
ON CONFLICT DO NOTHING;


-- ============================================================
-- 4. PRIVATE SECURITY DEFINER: admin_question_edit
--
--    Düzenlenebilir (allowlist) alanlar — yalnızca içerik/metadata:
--      question_text, option_a..e, correct_answer, difficulty,
--      cognitive_type, quality_level, primary_question_type,
--      secondary_question_type, estimated_solve_time_seconds,
--      is_new_generation, has_visual
--
--    KORUNAN (düzenlenemez) alanlar:
--      id, question_code, legacy_question_key, legacy_taxonomy_id,
--      subject_id, grade_level, exam_track, approval_status,
--      is_active, ownership_status, license_status,
--      commercial_use_allowed, created_at, updated_at
--      -> yaşam döngüsü/güvenlik/qnb alanları; kanonik akışlara ait.
--
--    Semantik:
--      - NULL parametre => alana dokunma (değiştirme).
--      - Boş string (text alanı için) => NULL'a temizle.
--    Mutation + audit INSERT aynı fonksiyon = AYNI transaction.
-- ============================================================

CREATE OR REPLACE FUNCTION private.admin_question_edit(
  p_question_id uuid,
  p_question_text text DEFAULT NULL,
  p_option_a text DEFAULT NULL,
  p_option_b text DEFAULT NULL,
  p_option_c text DEFAULT NULL,
  p_option_d text DEFAULT NULL,
  p_option_e text DEFAULT NULL,
  p_correct_answer text DEFAULT NULL,
  p_difficulty text DEFAULT NULL,
  p_cognitive_type text DEFAULT NULL,
  p_quality_level text DEFAULT NULL,
  p_primary_question_type text DEFAULT NULL,
  p_secondary_question_type text DEFAULT NULL,
  p_estimated_solve_time_seconds integer DEFAULT NULL,
  p_is_new_generation boolean DEFAULT NULL,
  p_has_visual boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid;
  v_question public.questions%ROWTYPE;
  v_before_data jsonb;
  v_after_data jsonb;
  v_next_question_text public.questions.question_text%TYPE;
  v_next_option_a public.questions.option_a%TYPE;
  v_next_option_b public.questions.option_b%TYPE;
  v_next_option_c public.questions.option_c%TYPE;
  v_next_option_d public.questions.option_d%TYPE;
  v_next_option_e public.questions.option_e%TYPE;
  v_next_correct_answer public.questions.correct_answer%TYPE;
  v_next_difficulty public.questions.difficulty%TYPE;
  v_next_cognitive_type public.questions.cognitive_type%TYPE;
  v_next_quality_level public.questions.quality_level%TYPE;
  v_next_primary public.questions.primary_question_type%TYPE;
  v_next_secondary public.questions.secondary_question_type%TYPE;
  v_next_solve integer;
  v_next_is_new_generation boolean;
  v_next_has_visual boolean;
  v_audit_id uuid;
BEGIN

  -- Gerçek authenticated kullanıcı gerekir.
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required.';
  END IF;

  IF NOT private.current_user_has_admin_permission('questions.edit') THEN
    RAISE EXCEPTION 'Question edit permission required.'
      USING ERRCODE = '42501';
  END IF;

  -- Satırı kilitle + oku.
  SELECT *
  INTO v_question
  FROM public.questions q
  WHERE q.id = p_question_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Question not found.'
      USING ERRCODE = 'P0002';
  END IF;

  -- ======================================================
  -- GİRİŞ DOĞRULAMA (strict; DB CHECK kısıtları ile tutarlı)
  -- ======================================================
  IF p_difficulty IS NOT NULL
     AND p_difficulty NOT IN ('easy', 'medium', 'hard') THEN
    RAISE EXCEPTION 'Invalid difficulty.'
      USING ERRCODE = '22023';
  END IF;

  IF p_cognitive_type IS NOT NULL
     AND p_cognitive_type NOT IN ('learning', 'comprehension', 'application') THEN
    RAISE EXCEPTION 'Invalid cognitive type.'
      USING ERRCODE = '22023';
  END IF;

  IF p_quality_level IS NOT NULL
     AND p_quality_level NOT IN ('low', 'medium', 'high') THEN
    RAISE EXCEPTION 'Invalid quality level.'
      USING ERRCODE = '22023';
  END IF;

  IF p_correct_answer IS NOT NULL
     AND p_correct_answer NOT IN ('A', 'B', 'C', 'D', 'E') THEN
    RAISE EXCEPTION 'Invalid correct answer.'
      USING ERRCODE = '22023';
  END IF;

  IF p_estimated_solve_time_seconds IS NOT NULL
     AND p_estimated_solve_time_seconds <= 0 THEN
    RAISE EXCEPTION 'Solve time must be positive.'
      USING ERRCODE = '22023';
  END IF;

  -- ======================================================
  -- YENİ DEĞERLERİ HESAPLA (NULL => değiştirme, '' => NULL)
  -- ======================================================
  v_next_question_text := COALESCE(p_question_text, v_question.question_text);
  v_next_option_a := COALESCE(p_option_a, v_question.option_a);
  v_next_option_b := COALESCE(p_option_b, v_question.option_b);
  v_next_option_c := COALESCE(p_option_c, v_question.option_c);
  v_next_option_d := COALESCE(p_option_d, v_question.option_d);
  v_next_option_e := COALESCE(p_option_e, v_question.option_e);
  v_next_correct_answer := COALESCE(p_correct_answer, v_question.correct_answer);
  v_next_difficulty := COALESCE(p_difficulty, v_question.difficulty);
  v_next_cognitive_type := COALESCE(p_cognitive_type, v_question.cognitive_type);
  v_next_quality_level := COALESCE(p_quality_level, v_question.quality_level);
  v_next_primary := COALESCE(p_primary_question_type, v_question.primary_question_type);
  v_next_secondary := COALESCE(p_secondary_question_type, v_question.secondary_question_type);
  v_next_solve := COALESCE(p_estimated_solve_time_seconds, v_question.estimated_solve_time_seconds);
  v_next_is_new_generation := COALESCE(p_is_new_generation, v_question.is_new_generation);
  v_next_has_visual := COALESCE(p_has_visual, v_question.has_visual);

  -- Boş string => NULL temizleme (yalnız text alanları).
  IF p_question_text IS NOT NULL AND btrim(p_question_text) = '' THEN
    v_next_question_text := NULL;
  END IF;
  IF p_option_a IS NOT NULL AND btrim(p_option_a) = '' THEN v_next_option_a := NULL; END IF;
  IF p_option_b IS NOT NULL AND btrim(p_option_b) = '' THEN v_next_option_b := NULL; END IF;
  IF p_option_c IS NOT NULL AND btrim(p_option_c) = '' THEN v_next_option_c := NULL; END IF;
  IF p_option_d IS NOT NULL AND btrim(p_option_d) = '' THEN v_next_option_d := NULL; END IF;
  IF p_option_e IS NOT NULL AND btrim(p_option_e) = '' THEN v_next_option_e := NULL; END IF;
  IF p_primary_question_type IS NOT NULL AND btrim(p_primary_question_type) = '' THEN
    v_next_primary := NULL;
  END IF;
  IF p_secondary_question_type IS NOT NULL AND btrim(p_secondary_question_type) = '' THEN
    v_next_secondary := NULL;
  END IF;

  -- before_data: yalnızca düzenlenebilir allowlist alanlarının anlık görüntüsü.
  v_before_data := jsonb_build_object(
    'question_text', v_question.question_text,
    'option_a', v_question.option_a,
    'option_b', v_question.option_b,
    'option_c', v_question.option_c,
    'option_d', v_question.option_d,
    'option_e', v_question.option_e,
    'correct_answer', v_question.correct_answer,
    'difficulty', v_question.difficulty,
    'cognitive_type', v_question.cognitive_type,
    'quality_level', v_question.quality_level,
    'primary_question_type', v_question.primary_question_type,
    'secondary_question_type', v_question.secondary_question_type,
    'estimated_solve_time_seconds', v_question.estimated_solve_time_seconds,
    'is_new_generation', v_question.is_new_generation,
    'has_visual', v_question.has_visual
  );

  -- ======================================================
  -- MUTATION (yalnız allowlist alanları)
  -- ======================================================
  UPDATE public.questions
  SET
    question_text = v_next_question_text,
    option_a = v_next_option_a,
    option_b = v_next_option_b,
    option_c = v_next_option_c,
    option_d = v_next_option_d,
    option_e = v_next_option_e,
    correct_answer = v_next_correct_answer,
    difficulty = v_next_difficulty,
    cognitive_type = v_next_cognitive_type,
    quality_level = v_next_quality_level,
    primary_question_type = v_next_primary,
    secondary_question_type = v_next_secondary,
    estimated_solve_time_seconds = v_next_solve,
    is_new_generation = v_next_is_new_generation,
    has_visual = v_next_has_visual,
    updated_at = now()
  WHERE id = p_question_id;

  -- after_data: mutation sonrası allowlist alanları (öngörülen değerler).
  v_after_data := jsonb_build_object(
    'question_text', v_next_question_text,
    'option_a', v_next_option_a,
    'option_b', v_next_option_b,
    'option_c', v_next_option_c,
    'option_d', v_next_option_d,
    'option_e', v_next_option_e,
    'correct_answer', v_next_correct_answer,
    'difficulty', v_next_difficulty,
    'cognitive_type', v_next_cognitive_type,
    'quality_level', v_next_quality_level,
    'primary_question_type', v_next_primary,
    'secondary_question_type', v_next_secondary,
    'estimated_solve_time_seconds', v_next_solve,
    'is_new_generation', v_next_is_new_generation,
    'has_visual', v_next_has_visual
  );

  -- ======================================================
  -- ATOMIC AUDIT — aynı fonksiyon (aynı transaction).
  -- Audit INSERT başarısız olursa mutation da döner.
  -- ======================================================
  INSERT INTO public.admin_audit_log (
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    before_data,
    after_data
  )
  VALUES (
    v_user_id,
    'question.edit',
    'question',
    p_question_id,
    v_before_data,
    v_after_data
  )
  RETURNING id
  INTO v_audit_id;

  RETURN jsonb_build_object(
    'status', 'updated',
    'question_id', p_question_id,
    'audit_id', v_audit_id,
    'before_data', v_before_data,
    'after_data', v_after_data
  );

END;
$$;


-- ============================================================
-- 5. PUBLIC INVOKER SARMALAYICI
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_question_edit(
  p_question_id uuid,
  p_question_text text DEFAULT NULL,
  p_option_a text DEFAULT NULL,
  p_option_b text DEFAULT NULL,
  p_option_c text DEFAULT NULL,
  p_option_d text DEFAULT NULL,
  p_option_e text DEFAULT NULL,
  p_correct_answer text DEFAULT NULL,
  p_difficulty text DEFAULT NULL,
  p_cognitive_type text DEFAULT NULL,
  p_quality_level text DEFAULT NULL,
  p_primary_question_type text DEFAULT NULL,
  p_secondary_question_type text DEFAULT NULL,
  p_estimated_solve_time_seconds integer DEFAULT NULL,
  p_is_new_generation boolean DEFAULT NULL,
  p_has_visual boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.admin_question_edit(
    p_question_id,
    p_question_text,
    p_option_a,
    p_option_b,
    p_option_c,
    p_option_d,
    p_option_e,
    p_correct_answer,
    p_difficulty,
    p_cognitive_type,
    p_quality_level,
    p_primary_question_type,
    p_secondary_question_type,
    p_estimated_solve_time_seconds,
    p_is_new_generation,
    p_has_visual
  );
$$;


-- ============================================================
-- 6. EXECUTE GRANT'LARI (canonical desen)
-- ============================================================

-- private SECURITY DEFINER: PUBLIC/anon'e kapalı.
-- authenticated, public INVOKER sarmalayıcının çağrıyı asıl kullanıcı
-- rolüyle (INVOKER) ileri taşıyabilmesi için EXECUTE alır — migration 040
-- deseniyle birebir (040:973-978). Güvenlik fonksiyonun içindeki
-- questions.edit kontrolü + SECURITY DEFINER ile sağlanır; fonksiyonu
-- gizlemekten gelmez. service_role de doğrudan çağırabilir.
REVOKE ALL
ON FUNCTION private.admin_question_edit(uuid, text, text, text, text, text,
                                        text, text, text, text, text, text,
                                        text, integer, boolean, boolean)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION private.admin_question_edit(uuid, text, text, text, text, text,
                                        text, text, text, text, text, text,
                                        text, integer, boolean, boolean)
FROM anon;

GRANT EXECUTE
ON FUNCTION private.admin_question_edit(uuid, text, text, text, text, text,
                                        text, text, text, text, text, text,
                                        text, integer, boolean, boolean)
TO authenticated;

GRANT EXECUTE
ON FUNCTION private.admin_question_edit(uuid, text, text, text, text, text,
                                        text, text, text, text, text, text,
                                        text, integer, boolean, boolean)
TO service_role;

-- public INVOKER sarmalayıcı: authenticated admin'ler çağırabilir.
REVOKE ALL
ON FUNCTION public.admin_question_edit(uuid, text, text, text, text, text,
                                       text, text, text, text, text, text,
                                       text, integer, boolean, boolean)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.admin_question_edit(uuid, text, text, text, text, text,
                                       text, text, text, text, text, text,
                                       text, integer, boolean, boolean)
FROM anon;

GRANT EXECUTE
ON FUNCTION public.admin_question_edit(uuid, text, text, text, text, text,
                                       text, text, text, text, text, text,
                                       text, integer, boolean, boolean)
TO authenticated;


COMMIT;
