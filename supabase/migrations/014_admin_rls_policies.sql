-- 014_admin_rls_policies.sql
-- Altın Kalemler admin RLS ve yetki politikaları.

-- =========================================================
-- 1. YARDIMCI YETKİ FONKSİYONLARI
-- =========================================================

CREATE OR REPLACE FUNCTION public.is_current_user_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_user_roles aur
    JOIN public.admin_roles ar
      ON ar.id = aur.role_id
    WHERE aur.user_id = auth.uid()
      AND ar.is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION public.is_current_user_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_user_roles aur
    JOIN public.admin_roles ar
      ON ar.id = aur.role_id
    WHERE aur.user_id = auth.uid()
      AND ar.role_code = 'super_admin'
      AND ar.is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION public.current_user_has_admin_permission(
  p_permission_code text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.is_current_user_super_admin()
    OR public.has_admin_permission(
      auth.uid(),
      p_permission_code
    );
$$;

REVOKE ALL
ON FUNCTION public.is_current_user_admin()
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.is_current_user_super_admin()
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.current_user_has_admin_permission(text)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.is_current_user_admin()
TO authenticated;

GRANT EXECUTE
ON FUNCTION public.is_current_user_super_admin()
TO authenticated;

GRANT EXECUTE
ON FUNCTION public.current_user_has_admin_permission(text)
TO authenticated;


-- =========================================================
-- 2. ADMIN ROL TABLOLARI
-- =========================================================

DROP POLICY IF EXISTS "admins read admin roles"
ON public.admin_roles;

CREATE POLICY "admins read admin roles"
ON public.admin_roles
FOR SELECT
TO authenticated
USING (
  public.is_current_user_admin()
);

DROP POLICY IF EXISTS "users managers manage admin roles"
ON public.admin_roles;

CREATE POLICY "users managers manage admin roles"
ON public.admin_roles
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('users.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('users.manage')
);


DROP POLICY IF EXISTS "admins read admin permissions"
ON public.admin_permissions;

CREATE POLICY "admins read admin permissions"
ON public.admin_permissions
FOR SELECT
TO authenticated
USING (
  public.is_current_user_admin()
);

DROP POLICY IF EXISTS "users managers manage admin permissions"
ON public.admin_permissions;

CREATE POLICY "users managers manage admin permissions"
ON public.admin_permissions
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('users.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('users.manage')
);


DROP POLICY IF EXISTS "admins read role permissions"
ON public.admin_role_permissions;

CREATE POLICY "admins read role permissions"
ON public.admin_role_permissions
FOR SELECT
TO authenticated
USING (
  public.is_current_user_admin()
);

DROP POLICY IF EXISTS "users managers manage role permissions"
ON public.admin_role_permissions;

CREATE POLICY "users managers manage role permissions"
ON public.admin_role_permissions
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('users.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('users.manage')
);


DROP POLICY IF EXISTS "admin reads own roles"
ON public.admin_user_roles;

CREATE POLICY "admin reads own roles"
ON public.admin_user_roles
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR public.current_user_has_admin_permission('users.manage')
);

DROP POLICY IF EXISTS "users managers manage user roles"
ON public.admin_user_roles;

CREATE POLICY "users managers manage user roles"
ON public.admin_user_roles
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('users.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('users.manage')
);


-- =========================================================
-- 3. AI YÖNETİM TABLOLARI
-- =========================================================

DROP POLICY IF EXISTS "ai managers manage agents"
ON public.ai_agents;

CREATE POLICY "ai managers manage agents"
ON public.ai_agents
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('ai.manage')
);


DROP POLICY IF EXISTS "ai managers manage agent versions"
ON public.ai_agent_versions;

CREATE POLICY "ai managers manage agent versions"
ON public.ai_agent_versions
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('ai.manage')
);


DROP POLICY IF EXISTS "ai managers manage workflows"
ON public.ai_workflows;

CREATE POLICY "ai managers manage workflows"
ON public.ai_workflows
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('ai.manage')
);


DROP POLICY IF EXISTS "ai managers manage workflow steps"
ON public.ai_workflow_steps;

CREATE POLICY "ai managers manage workflow steps"
ON public.ai_workflow_steps
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('ai.manage')
);


DROP POLICY IF EXISTS "ai managers manage thresholds"
ON public.ai_quality_thresholds;

CREATE POLICY "ai managers manage thresholds"
ON public.ai_quality_thresholds
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('ai.manage')
);


DROP POLICY IF EXISTS "ai managers manage jobs"
ON public.ai_jobs;

CREATE POLICY "ai managers manage jobs"
ON public.ai_jobs
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('ai.manage')
);


DROP POLICY IF EXISTS "ai managers manage executions"
ON public.ai_agent_executions;

CREATE POLICY "ai managers manage executions"
ON public.ai_agent_executions
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('ai.manage')
);


-- =========================================================
-- 4. STAGING / SORU İNCELEME
-- =========================================================

DROP POLICY IF EXISTS "question admins read staging"
ON public.ai_question_staging;

CREATE POLICY "question admins read staging"
ON public.ai_question_staging
FOR SELECT
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.view')
);

DROP POLICY IF EXISTS "question admins manage staging"
ON public.ai_question_staging;

CREATE POLICY "question admins manage staging"
ON public.ai_question_staging
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('questions.approve')
  OR public.current_user_has_admin_permission('questions.reject')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('questions.approve')
  OR public.current_user_has_admin_permission('questions.reject')
);


DROP POLICY IF EXISTS "question admins read validations"
ON public.ai_validation_results;

CREATE POLICY "question admins read validations"
ON public.ai_validation_results
FOR SELECT
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.view')
);

DROP POLICY IF EXISTS "question admins manage validations"
ON public.ai_validation_results;

CREATE POLICY "question admins manage validations"
ON public.ai_validation_results
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('questions.approve')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('questions.approve')
);


DROP POLICY IF EXISTS "question admins read similarities"
ON public.question_similarity_matches;

CREATE POLICY "question admins read similarities"
ON public.question_similarity_matches
FOR SELECT
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.view')
);

DROP POLICY IF EXISTS "question admins manage similarities"
ON public.question_similarity_matches;

CREATE POLICY "question admins manage similarities"
ON public.question_similarity_matches
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('questions.approve')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('questions.approve')
);


-- =========================================================
-- 5. REVIEW QUEUE
-- =========================================================

DROP POLICY IF EXISTS "question admins read review queue"
ON public.review_queue;

CREATE POLICY "question admins read review queue"
ON public.review_queue
FOR SELECT
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.view')
  OR public.current_user_has_admin_permission('copyright.review')
);

DROP POLICY IF EXISTS "reviewers manage review queue"
ON public.review_queue;

CREATE POLICY "reviewers manage review queue"
ON public.review_queue
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.approve')
  OR public.current_user_has_admin_permission('questions.reject')
  OR public.current_user_has_admin_permission('copyright.review')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.approve')
  OR public.current_user_has_admin_permission('questions.reject')
  OR public.current_user_has_admin_permission('copyright.review')
);


-- =========================================================
-- 6. TELİF / TİCARİ İNCELEME
-- =========================================================

DROP POLICY IF EXISTS "copyright reviewers manage reviews"
ON public.copyright_reviews;

CREATE POLICY "copyright reviewers manage reviews"
ON public.copyright_reviews
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('copyright.review')
)
WITH CHECK (
  public.current_user_has_admin_permission('copyright.review')
);


DROP POLICY IF EXISTS "commercial reviewers manage clearance"
ON public.commercial_question_clearance;

CREATE POLICY "commercial reviewers manage clearance"
ON public.commercial_question_clearance
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('commercial.approve')
)
WITH CHECK (
  public.current_user_has_admin_permission('commercial.approve')
);


-- =========================================================
-- 7. İNSAN ONAY / PROMOTION
-- =========================================================

DROP POLICY IF EXISTS "question admins read review decisions"
ON public.question_review_decisions;

CREATE POLICY "question admins read review decisions"
ON public.question_review_decisions
FOR SELECT
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.view')
);


DROP POLICY IF EXISTS "question reviewers create decisions"
ON public.question_review_decisions;

CREATE POLICY "question reviewers create decisions"
ON public.question_review_decisions
FOR INSERT
TO authenticated
WITH CHECK (
  (
    decision = 'approve'
    AND decision_source = 'human'
    AND reviewer_user_id = auth.uid()
    AND public.current_user_has_admin_permission('questions.approve')
  )
  OR
  (
    decision IN ('reject', 'request_changes')
    AND decision_source = 'human'
    AND reviewer_user_id = auth.uid()
    AND public.current_user_has_admin_permission('questions.reject')
  )
);


DROP POLICY IF EXISTS "question admins read promotion requests"
ON public.question_promotion_requests;

CREATE POLICY "question admins read promotion requests"
ON public.question_promotion_requests
FOR SELECT
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.view')
);


DROP POLICY IF EXISTS "question approvers manage promotion requests"
ON public.question_promotion_requests;

CREATE POLICY "question approvers manage promotion requests"
ON public.question_promotion_requests
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.approve')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.approve')
);


DROP POLICY IF EXISTS "question admins read promotion audit"
ON public.question_promotion_audit;

CREATE POLICY "question admins read promotion audit"
ON public.question_promotion_audit
FOR SELECT
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.view')
);


DROP POLICY IF EXISTS "question approvers create promotion audit"
ON public.question_promotion_audit;

CREATE POLICY "question approvers create promotion audit"
ON public.question_promotion_audit
FOR INSERT
TO authenticated
WITH CHECK (
  performed_by = auth.uid()
  AND public.current_user_has_admin_permission('questions.approve')
);


-- =========================================================
-- 8. KAZANIM / ÜRETİM KURAL TABLOLARI
-- =========================================================

DROP POLICY IF EXISTS "curriculum admins manage generation rules"
ON public.question_generation_rules;

CREATE POLICY "curriculum admins manage generation rules"
ON public.question_generation_rules
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('curriculum.manage')
  OR public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('curriculum.manage')
  OR public.current_user_has_admin_permission('ai.manage')
);


DROP POLICY IF EXISTS "curriculum admins manage prerequisites"
ON public.curriculum_prerequisites;

CREATE POLICY "curriculum admins manage prerequisites"
ON public.curriculum_prerequisites
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('curriculum.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('curriculum.manage')
);


DROP POLICY IF EXISTS "content admins manage pool targets"
ON public.question_pool_targets;

CREATE POLICY "content admins manage pool targets"
ON public.question_pool_targets
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('ai.manage')
);


DROP POLICY IF EXISTS "content admins manage gap results"
ON public.question_pool_gap_results;

CREATE POLICY "content admins manage gap results"
ON public.question_pool_gap_results
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.view')
  OR public.current_user_has_admin_permission('ai.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('ai.manage')
);


-- =========================================================
-- 9. KAZANIM EŞLEŞTİRME TABLOLARI
-- =========================================================

DROP POLICY IF EXISTS "authenticated read active outcomes"
ON public.curriculum_outcomes;

CREATE POLICY "authenticated read active outcomes"
ON public.curriculum_outcomes
FOR SELECT
TO authenticated
USING (
  is_active = true
);


DROP POLICY IF EXISTS "curriculum admins manage outcomes"
ON public.curriculum_outcomes;

CREATE POLICY "curriculum admins manage outcomes"
ON public.curriculum_outcomes
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('curriculum.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('curriculum.manage')
);


DROP POLICY IF EXISTS "question admins manage question outcomes"
ON public.question_outcome_mappings;

CREATE POLICY "question admins manage question outcomes"
ON public.question_outcome_mappings
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('curriculum.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('curriculum.manage')
);


DROP POLICY IF EXISTS "question admins manage staging outcomes"
ON public.staging_outcome_mappings;

CREATE POLICY "question admins manage staging outcomes"
ON public.staging_outcome_mappings
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('questions.approve')
)
WITH CHECK (
  public.current_user_has_admin_permission('questions.edit')
  OR public.current_user_has_admin_permission('questions.approve')
);


DROP POLICY IF EXISTS "curriculum admins manage outcome aliases"
ON public.curriculum_outcome_aliases;

CREATE POLICY "curriculum admins manage outcome aliases"
ON public.curriculum_outcome_aliases
FOR ALL
TO authenticated
USING (
  public.current_user_has_admin_permission('curriculum.manage')
)
WITH CHECK (
  public.current_user_has_admin_permission('curriculum.manage')
);