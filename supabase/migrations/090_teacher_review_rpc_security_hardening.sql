-- ============================================================
-- 090_teacher_review_rpc_security_hardening.sql
-- Teacher Review RPC'lerinde SECURITY DEFINER sızıntısını kapatır.
--
-- Sorun (Supabase Security Advisor):
--   public.decide_teacher_review(...) ve
--   public.teacher_review_admin_has_permission(text)
--   SECURITY DEFINER + authenticated tarafından çağrılabilir
--   durumdaydı. Kamu (public) şemasında güvenlik ayrıcalığını
--   yükselten fonksiyon = enjeksiyon/yanlış rehberlik riski.
--
-- Çözüm (089_admin_audit_and_question_edit ile aynı kanonik desen):
--   public.*  -> SECURITY INVOKER sarmalayıcı, SET search_path = ''
--                (yalnızca ilgili private.* fonksiyonuna DELEGE eder)
--   private.* -> SECURITY DEFINER gerçek uygulama, SET search_path = ''
--                (şema-qualified, katı validasyon, explicit EXECUTE
--                 grant + PUBLIC/anon revoke, atomik mutation+audit)
--
-- Semantik değişmedi:
--   - Fonksiyon imzaları / parametre adları ve default'ları AYNEN korunur
--     (frontend RPC çağrıları kırılmaz).
--   - decide_teacher_review'in yetki kontrolü artık kanonik
--     private.current_user_has_admin_permission üzerinden yapılır
--     (super_admin bypass'ı dahil; uygulamanın kalanıyla birebir aynı).
--   - teacher_review_admin_has_permission orijinal davranışını birebir
--     korur (yeni-süper-olmayan admin rol-permission join).
--   - RLS: "Admins can view teacher review audit" politikası kamu
--     sarmalayıcısını çağırmaya devam eder; INVOKER olduğundan RLS
--     bağlamında asıl kullanıcı kimliğiyle çalışır.
-- ============================================================

BEGIN;


-- ============================================================
-- 1. PRIVATE SECURITY DEFINER: teacher_review_admin_has_permission
--
-- 047'deki SQL gövdesi birebir taşınır; SET search_path = '' ile
-- güvenlik kilidi kapatılır. auth.uid() -> request.jwt.claim.sub
-- GUC'undan okur; JWT gönderen gerçek kullanıcının kimliği korunur.
-- ============================================================

CREATE OR REPLACE FUNCTION private.teacher_review_admin_has_permission(
  p_permission_code text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1

    FROM public.admin_user_roles aur

    JOIN public.admin_roles ar
      ON ar.id = aur.role_id
     AND ar.is_active = true

    JOIN public.admin_role_permissions arp
      ON arp.role_id = ar.id

    JOIN public.admin_permissions ap
      ON ap.id = arp.permission_id

    WHERE aur.user_id = auth.uid()
      AND ap.permission_code = p_permission_code
  );
$$;


-- ============================================================
-- 2. PUBLIC INVOKER SARMALAYICI: teacher_review_admin_has_permission
--
-- Kamu çağrısı yalnızca private uygulamaya delege eder. SECURITY
-- DEFINER yok; RLS politikalarında kullanıldığında asıl kullanıcı
-- kimliğiyle (INVOKER) ileri taşınır.
-- ============================================================

CREATE OR REPLACE FUNCTION public.teacher_review_admin_has_permission(
  p_permission_code text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.teacher_review_admin_has_permission(p_permission_code);
$$;


-- ============================================================
-- 3. PRIVATE SECURITY DEFINER: decide_teacher_review
--
-- 047 gövdesi private şemaya taşınır ve yetki kontrolü kanonik
-- sisteme bağlanır:
--   public.teacher_review_admin_has_permission(...)
--     -> private.current_user_has_admin_permission(...)
-- Kanonik yardımcı (private.current_user_has_admin_permission)
-- super_admin bypass'ı + explicit rol-permission join içerir;
-- private.has_admin_permission/is_current_user_super_admin
-- zinciriyle 045/089 politikalarıyla aynı tutarlılıktadır.
--
-- SECURITY DEFINER GEREKLİDİR: ai_teacher_human_review_audit
-- tablosunda INSERT politikası YOKTUR; audit yazımı yalnızca
-- sahip (owner) bağlamında çalışan bu fonksiyondan yapılır.
-- (migration 047 satır 700-702): "Audit writes happen through
-- the SECURITY DEFINER decision function."
-- ============================================================

CREATE OR REPLACE FUNCTION private.decide_teacher_review(
  p_review_run_id uuid,
  p_decision text,
  p_correction_proposal_id uuid DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid;

  v_run public.ai_teacher_review_runs%ROWTYPE;

  v_proposal public.ai_teacher_correction_proposals%ROWTYPE;

  v_required_permission text;

  v_correction_applied boolean := false;

  v_now timestamptz := now();
BEGIN

  -- ----------------------------------------------------------
  -- Authenticated human identity required
  -- ----------------------------------------------------------

  v_actor := auth.uid();

  IF v_actor IS NULL THEN
    RAISE EXCEPTION
      'Human teacher review decision requires an authenticated user.';
  END IF;


  -- ----------------------------------------------------------
  -- Validate decision
  -- ----------------------------------------------------------

  IF p_decision NOT IN (
    'approved',
    'rejected',
    'needs_revision'
  ) THEN
    RAISE EXCEPTION
      'Invalid human decision: %',
      p_decision;
  END IF;


  -- ----------------------------------------------------------
  -- Permission mapping (canonical system)
  -- ----------------------------------------------------------

  IF p_decision = 'approved' THEN
    v_required_permission :=
      'questions.approve';
  ELSE
    v_required_permission :=
      'questions.reject';
  END IF;


  IF NOT private.current_user_has_admin_permission(
    v_required_permission
  ) THEN
    RAISE EXCEPTION
      'Permission denied. Required permission: %',
      v_required_permission
      USING ERRCODE = '42501';
  END IF;


  -- ----------------------------------------------------------
  -- Lock review run
  -- ----------------------------------------------------------

  SELECT *
  INTO v_run
  FROM public.ai_teacher_review_runs
  WHERE id = p_review_run_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Teacher review run not found: %',
      p_review_run_id;
  END IF;


  -- Human decision is only accepted when the workflow
  -- is explicitly waiting for human review.
  IF v_run.status <> 'human_review_required'
     OR v_run.current_stage <> 'human_review'
  THEN
    RAISE EXCEPTION
      'Teacher review run is not waiting for human review. status=%, stage=%',
      v_run.status,
      v_run.current_stage;
  END IF;


  -- ----------------------------------------------------------
  -- Optional correction proposal
  -- ----------------------------------------------------------

  IF p_correction_proposal_id IS NOT NULL THEN

    SELECT *
    INTO v_proposal
    FROM public.ai_teacher_correction_proposals
    WHERE id = p_correction_proposal_id
    FOR UPDATE;


    IF NOT FOUND THEN
      RAISE EXCEPTION
        'Correction proposal not found: %',
        p_correction_proposal_id;
    END IF;


    IF v_proposal.review_run_id <> p_review_run_id THEN
      RAISE EXCEPTION
        'Correction proposal does not belong to this review run.';
    END IF;


    IF v_proposal.staging_question_id
       <> v_run.staging_question_id
    THEN
      RAISE EXCEPTION
        'Correction proposal staging question does not match review run.';
    END IF;

  END IF;


  -- ==========================================================
  -- APPROVED
  -- ==========================================================

  IF p_decision = 'approved' THEN

    -- --------------------------------------------------------
    -- If a correction exists, human approval applies exactly
    -- that verified proposal to staging.
    -- --------------------------------------------------------

    IF p_correction_proposal_id IS NOT NULL THEN

      IF v_proposal.status <> 'recheck_passed' THEN
        RAISE EXCEPTION
          'Correction proposal must be recheck_passed before human approval. Current status: %',
          v_proposal.status;
      END IF;


      IF v_proposal.applied_to_staging = true THEN
        RAISE EXCEPTION
          'Correction proposal has already been applied to staging.';
      END IF;


      UPDATE public.ai_question_staging
      SET
        question_text =
          COALESCE(
            v_proposal.proposed_question_text,
            question_text
          ),

        option_a =
          COALESCE(
            v_proposal.proposed_option_a,
            option_a
          ),

        option_b =
          COALESCE(
            v_proposal.proposed_option_b,
            option_b
          ),

        option_c =
          COALESCE(
            v_proposal.proposed_option_c,
            option_c
          ),

        option_d =
          COALESCE(
            v_proposal.proposed_option_d,
            option_d
          ),

        option_e =
          COALESCE(
            v_proposal.proposed_option_e,
            option_e
          ),

        proposed_correct_answer =
          COALESCE(
            v_proposal.proposed_correct_answer,
            proposed_correct_answer
          )

      WHERE id =
        v_run.staging_question_id;


      IF NOT FOUND THEN
        RAISE EXCEPTION
          'Staging question not found while applying correction.';
      END IF;


      UPDATE public.ai_teacher_correction_proposals
      SET
        status =
          'human_approved',

        human_review_required =
          false,

        applied_to_staging =
          true,

        applied_by =
          v_actor,

        applied_at =
          v_now

      WHERE id =
        v_proposal.id;


      v_correction_applied :=
        true;


      INSERT INTO public.ai_teacher_human_review_audit (
        review_run_id,
        staging_question_id,
        correction_proposal_id,
        action,
        performed_by,
        notes,
        details
      )
      VALUES (
        v_run.id,
        v_run.staging_question_id,
        v_proposal.id,
        'correction_applied',
        v_actor,
        p_notes,
        jsonb_build_object(
          'previously_applied',
            false,

          'proposed_correct_answer',
            v_proposal.proposed_correct_answer,

          'production_publication',
            false
        )
      );

    END IF;


    UPDATE public.ai_teacher_review_runs
    SET
      status =
        'human_approved',

      current_stage =
        'complete',

      human_review_required =
        false,

      human_decision =
        'approved',

      human_reviewed_by =
        v_actor,

      human_reviewed_at =
        v_now

    WHERE id =
      v_run.id;


    INSERT INTO public.ai_teacher_human_review_audit (
      review_run_id,
      staging_question_id,
      correction_proposal_id,
      action,
      performed_by,
      notes,
      details
    )
    VALUES (
      v_run.id,
      v_run.staging_question_id,
      p_correction_proposal_id,
      'approved',
      v_actor,
      p_notes,
      jsonb_build_object(
        'correction_applied',
          v_correction_applied,

        'production_publication',
          false
      )
    );


  -- ==========================================================
  -- REJECTED
  -- ==========================================================

  ELSIF p_decision = 'rejected' THEN

    IF p_correction_proposal_id IS NOT NULL THEN

      UPDATE public.ai_teacher_correction_proposals
      SET
        status =
          'human_rejected',

        human_review_required =
          false

      WHERE id =
        v_proposal.id;

    END IF;


    UPDATE public.ai_teacher_review_runs
    SET
      status =
        'human_rejected',

      current_stage =
        'complete',

      human_review_required =
        false,

      human_decision =
        'rejected',

      human_reviewed_by =
        v_actor,

      human_reviewed_at =
        v_now

    WHERE id =
      v_run.id;


    INSERT INTO public.ai_teacher_human_review_audit (
      review_run_id,
      staging_question_id,
      correction_proposal_id,
      action,
      performed_by,
      notes,
      details
    )
    VALUES (
      v_run.id,
      v_run.staging_question_id,
      p_correction_proposal_id,
      'rejected',
      v_actor,
      p_notes,
      jsonb_build_object(
        'production_publication',
          false
      )
    );


  -- ==========================================================
  -- NEEDS REVISION
  -- ==========================================================

  ELSIF p_decision = 'needs_revision' THEN

    IF p_correction_proposal_id IS NOT NULL THEN

      UPDATE public.ai_teacher_correction_proposals
      SET
        status =
          'superseded',

        human_review_required =
          false

      WHERE id =
        v_proposal.id;

    END IF;


    UPDATE public.ai_teacher_review_runs
    SET
      status =
        'waiting_correction',

      current_stage =
        'correction',

      correction_required =
        true,

      correction_completed =
        false,

      final_checker_passed =
        NULL,

      human_review_required =
        false,

      human_decision =
        'needs_revision',

      human_reviewed_by =
        v_actor,

      human_reviewed_at =
        v_now,

      ai_review_completed_at =
        NULL

    WHERE id =
      v_run.id;


    INSERT INTO public.ai_teacher_human_review_audit (
      review_run_id,
      staging_question_id,
      correction_proposal_id,
      action,
      performed_by,
      notes,
      details
    )
    VALUES (
      v_run.id,
      v_run.staging_question_id,
      p_correction_proposal_id,
      'needs_revision',
      v_actor,
      p_notes,
      jsonb_build_object(
        'next_status',
          'waiting_correction',

        'next_stage',
          'correction',

        'production_publication',
          false
      )
    );

  END IF;


  -- ----------------------------------------------------------
  -- Return compact result
  -- ----------------------------------------------------------

  RETURN jsonb_build_object(
    'review_run_id',
      v_run.id,

    'decision',
      p_decision,

    'performed_by',
      v_actor,

    'correction_proposal_id',
      p_correction_proposal_id,

    'correction_applied',
      v_correction_applied,

    'production_publication',
      false
  );

END;
$$;


-- ============================================================
-- 4. PUBLIC INVOKER SARMALAYICI: decide_teacher_review
--
-- İmza / parametre adları / default'lar AYNEN korunur (frontend
-- RPC uyumluluğu). Yalnızca private.* uygulamaya delege edilir;
-- SECURITY DEFINER değildir.
-- ============================================================

CREATE OR REPLACE FUNCTION public.decide_teacher_review(
  p_review_run_id uuid,
  p_decision text,
  p_correction_proposal_id uuid DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT private.decide_teacher_review(
    p_review_run_id,
    p_decision,
    p_correction_proposal_id,
    p_notes
  );
$$;


-- ============================================================
-- 5. EXECUTE GRANT'LARI (kanonik desen — 089 ile aynı)
-- ============================================================

-- private SECURITY DEFINER implementasyonları: PUBLIC/anon'e kapalı.
-- authenticated, public INVOKER sarmalayıcının çağrıyı asıl kullanıcı
-- rolüyle ileri taşıyabilmesi için EXECUTE alır; güvenlik fonksiyonun
-- İÇİNDEKİ kanonik yetki kontrolü + SECURITY DEFINER ile sağlanır.
-- service_role de doğrudan çağırabilir (backend worker; yine de
-- auth.uid() doğrulamasından geçer).
REVOKE ALL
ON FUNCTION private.teacher_review_admin_has_permission(text)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION private.teacher_review_admin_has_permission(text)
FROM anon;

GRANT EXECUTE
ON FUNCTION private.teacher_review_admin_has_permission(text)
TO authenticated;

GRANT EXECUTE
ON FUNCTION private.teacher_review_admin_has_permission(text)
TO service_role;

REVOKE ALL
ON FUNCTION private.decide_teacher_review(uuid, text, uuid, text)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION private.decide_teacher_review(uuid, text, uuid, text)
FROM anon;

GRANT EXECUTE
ON FUNCTION private.decide_teacher_review(uuid, text, uuid, text)
TO authenticated;

GRANT EXECUTE
ON FUNCTION private.decide_teacher_review(uuid, text, uuid, text)
TO service_role;


-- public INVOKER sarmalayıcılar: authenticated admin'ler çağırabilir.
-- (PUBLIC ve anon ayrıca EXECUTE alamaz — REST/RPC yüzeyi yalnızca
--  kimlikli kullanıcılara açıktır.)
REVOKE ALL
ON FUNCTION public.teacher_review_admin_has_permission(text)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.teacher_review_admin_has_permission(text)
FROM anon;

GRANT EXECUTE
ON FUNCTION public.teacher_review_admin_has_permission(text)
TO authenticated;

REVOKE ALL
ON FUNCTION public.decide_teacher_review(uuid, text, uuid, text)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.decide_teacher_review(uuid, text, uuid, text)
FROM anon;

GRANT EXECUTE
ON FUNCTION public.decide_teacher_review(uuid, text, uuid, text)
TO authenticated;


COMMIT;