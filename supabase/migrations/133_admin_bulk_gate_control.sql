-- ============================================================
-- 133_admin_bulk_gate_control.sql
-- Altın Kalemler — WP-10: Toplu kapı kontrolü (bulk gate control)
--
-- Amaç:
--   Aday toplu listesinden, insanın kapsamı GÖRÜP ONAY vermesiyle eksik
--   kapı kontrollerini toplu başlatmak; ilerlemeyi/sonuçları izlemek;
--   uygun adayları toplu olarak (yine açık insan onayıyla) nihai karara
--   bağlamak.
--
-- Güvenlik (fail-closed):
--   - Tüm yazma yolları SECURITY DEFINER + guard
--     (ai.manage VEYA questions.approve) ile korunur; yetki genişletilmez.
--   - Plan ve grup türetimi SQL tarafındadır (tek doğruluk kaynağı);
--     istemci "hazır görev listesi" gönderemez.
--   - Geçerli/tamamlanmış kontroller yeniden çalıştırılmaz; aynı kapı için
--     ikinci bir bekleyen görev oluşmaz (duplicate_pending_task).
--   - Toplu onay ayrı yazma yoludur ve mevcut karar akışını
--     (review_and_promote_ai_question) kullanır. Otomatik aktivasyon,
--     öğrenciye yayın veya kasa üyeliği YOKTUR.
--
-- Kapsam notu:
--   - Yalnız otomatikleştirilebilen kapılar toplu kapsama girer:
--     answer (çözücü 1-2), curriculum (gözden geçiren 1-2),
--     quality (gözden geçiren 1-2).
--   - solve_time ve originality kapıları gerçek insan ölçümü / dış kanıt
--     gerektirir; toplu başlatma kapsamı DIŞINDADIR, "insan kuyruğunda"
--     ayrı gösterilir.
-- ============================================================

BEGIN;

-- ============================================================
-- 1) TOPLU KOŞU (bulk run) ve GÖREV (task) TABLOLARI
-- ============================================================

CREATE TABLE IF NOT EXISTS public.admin_bulk_gate_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  batch_id uuid NOT NULL
    REFERENCES public.candidate_question_batches(id) ON DELETE CASCADE,

  -- 'selection' = yalnız seçilen adaylar; 'filter' = filtreye uyan TÜM adaylar
  scope text NOT NULL
    CHECK (scope IN ('selection', 'filter')),

  -- Filtre tanımı (örn. {"group": "waiting"}); 'filter' kapsamında anlamlı
  filter_spec jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- Toplu kapsamdaki kapı türleri
  gates text[] NOT NULL DEFAULT ARRAY[]::text[],

  -- Kullanılacak model kimliği (provenance)
  model text NOT NULL,

  status text NOT NULL DEFAULT 'planned'
    CHECK (status IN ('planned', 'running', 'stopped', 'completed', 'failed')),

  -- Durdurma: YENİ iş alımını keser; devam eden yazmayı güvensiz kesmez
  stop_requested boolean NOT NULL DEFAULT false,

  planned_candidate_count integer NOT NULL DEFAULT 0,
  planned_task_count integer NOT NULL DEFAULT 0,

  -- Bilinen model çağrısı sayısı. Zincir adımları (çözücü 2 / gözden
  -- geçiren 2) koşulludur; sayı bilinen minimum çağrıdır.
  planned_model_call_count integer NOT NULL DEFAULT 0,

  -- Maliyet tahmini: güvenilir tahmin yoksa 'unavailable' (sıfır varsayılmaz)
  cost_estimate_status text NOT NULL DEFAULT 'unavailable'
    CHECK (cost_estimate_status IN ('unavailable', 'estimate', 'known')),
  cost_estimate_minor_units bigint,
  cost_currency text,

  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  stopped_at timestamptz
);


CREATE TABLE IF NOT EXISTS public.admin_bulk_gate_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  bulk_run_id uuid NOT NULL
    REFERENCES public.admin_bulk_gate_runs(id) ON DELETE CASCADE,

  staging_question_id uuid NOT NULL,
  candidate_position integer NOT NULL,

  gate_key text NOT NULL
    CHECK (gate_key IN ('answer', 'curriculum', 'quality')),

  gate_role text NOT NULL
    CHECK (gate_role IN ('solver_1', 'solver_2', 'reviewer_1', 'reviewer_2')),

  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'running', 'completed', 'failed', 'skipped')),

  attempt_count integer NOT NULL DEFAULT 0,

  -- İlgili ai_*_runs satırı (gönderim hedefi)
  gate_run_id uuid,

  -- Plan anındaki içerik anlık görüntüsü; worker karşılaştırarak
  -- "içerik değişti" durumunu fail-closed yakalar.
  content_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,

  error_code text,
  error_message text,

  -- Lease (claim) alanları
  claimed_by text,
  lease_expires_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  completed_at timestamptz,

  CONSTRAINT admin_bulk_gate_tasks_unique
    UNIQUE (bulk_run_id, staging_question_id, gate_key, gate_role)
);


CREATE INDEX IF NOT EXISTS idx_admin_bulk_gate_runs_batch
  ON public.admin_bulk_gate_runs(batch_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_bulk_gate_tasks_claim
  ON public.admin_bulk_gate_tasks(status, created_at);

CREATE INDEX IF NOT EXISTS idx_admin_bulk_gate_tasks_staging
  ON public.admin_bulk_gate_tasks(staging_question_id, gate_key);

CREATE INDEX IF NOT EXISTS idx_admin_bulk_gate_tasks_run
  ON public.admin_bulk_gate_tasks(bulk_run_id, status);


DROP TRIGGER IF EXISTS trigger_admin_bulk_gate_runs_updated_at
  ON public.admin_bulk_gate_runs;

CREATE TRIGGER trigger_admin_bulk_gate_runs_updated_at
  BEFORE UPDATE ON public.admin_bulk_gate_runs
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ============================================================
-- 2) RLS + GRANT
-- ============================================================

ALTER TABLE public.admin_bulk_gate_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins manage bulk gate runs"
  ON public.admin_bulk_gate_runs;

CREATE POLICY "admins manage bulk gate runs"
  ON public.admin_bulk_gate_runs
  FOR ALL TO authenticated
  USING (
    public.current_user_has_admin_permission('ai.manage')
    OR public.current_user_has_admin_permission('questions.approve')
  )
  WITH CHECK (
    public.current_user_has_admin_permission('ai.manage')
    OR public.current_user_has_admin_permission('questions.approve')
  );


ALTER TABLE public.admin_bulk_gate_tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins manage bulk gate tasks"
  ON public.admin_bulk_gate_tasks;

CREATE POLICY "admins manage bulk gate tasks"
  ON public.admin_bulk_gate_tasks
  FOR ALL TO authenticated
  USING (
    public.current_user_has_admin_permission('ai.manage')
    OR public.current_user_has_admin_permission('questions.approve')
  )
  WITH CHECK (
    public.current_user_has_admin_permission('ai.manage')
    OR public.current_user_has_admin_permission('questions.approve')
  );


-- Doğrudan tablo yazımı authenticated'a açılmaz; yazma yalnız
-- SECURITY DEFINER RPC'ler üzerinden (yetiği sunucu tarafında doğrulanır).
REVOKE ALL ON public.admin_bulk_gate_runs FROM PUBLIC, anon;
REVOKE ALL ON public.admin_bulk_gate_tasks FROM PUBLIC, anon;

GRANT SELECT ON public.admin_bulk_gate_runs TO authenticated, service_role;
GRANT SELECT ON public.admin_bulk_gate_tasks TO authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.admin_bulk_gate_runs TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.admin_bulk_gate_tasks TO service_role;


-- ============================================================
-- 3) PRIVATE YARDIMCILAR (tek doğruluk kaynağı)
-- ============================================================

-- ------------------------------------------------------------
-- 3.1) ADAY SATIRLARI
--     Kapı durumları (en son run), readiness özeti, toplu görev
--     sayaçları, görüntüleme alanları ve içerik anlık görüntüsü.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.bulk_gate_candidate_rows(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_candidate record;
  v_answer record;
  v_curriculum record;
  v_quality record;
  v_solve_time record;
  v_originality record;
  v_readiness record;
  v_bulk jsonb;
  v_gates jsonb;
  v_snapshot jsonb;
  v_items jsonb := '[]'::jsonb;
BEGIN
  FOR v_candidate IN
    SELECT
      r.staging_question_id,
      r.candidate_index,
      COALESCE(
        NULLIF(r.client_question_id, ''),
        NULLIF(s.metadata ->> 'client_question_id', '')
      ) AS client_question_id,
      s.staging_status,
      s.grade_level,
      s.subject_id,
      s.proposed_topic_id,
      s.proposed_subtopic_id,
      s.proposed_correct_answer,
      s.proposed_solve_time_seconds,
      s.proposed_curriculum_version_id,
      s.question_text,
      s.option_a,
      s.option_b,
      s.option_c,
      s.option_d,
      s.option_e,
      s.metadata,
      sub.name AS subject_name,
      t.name AS topic_name,
      st.name AS subtopic_name
    FROM public.candidate_batch_candidate_results r
    JOIN public.ai_question_staging s
      ON s.id = r.staging_question_id
    LEFT JOIN public.subjects sub
      ON sub.id = s.subject_id
    LEFT JOIN public.topics t
      ON t.id = s.proposed_topic_id
    LEFT JOIN public.subtopics st
      ON st.id = s.proposed_subtopic_id
    WHERE r.batch_id = p_batch_id
    ORDER BY r.candidate_index
  LOOP
    SELECT *
    INTO v_answer
    FROM public.ai_answer_verification_runs
    WHERE staging_question_id = v_candidate.staging_question_id
    ORDER BY created_at DESC, id DESC
    LIMIT 1;

    SELECT *
    INTO v_curriculum
    FROM public.ai_curriculum_fit_runs
    WHERE staging_question_id = v_candidate.staging_question_id
    ORDER BY created_at DESC, id DESC
    LIMIT 1;

    SELECT *
    INTO v_quality
    FROM public.ai_question_quality_runs
    WHERE staging_question_id = v_candidate.staging_question_id
    ORDER BY created_at DESC, id DESC
    LIMIT 1;

    SELECT *
    INTO v_solve_time
    FROM public.ai_solve_time_verification_runs
    WHERE staging_question_id = v_candidate.staging_question_id
    ORDER BY created_at DESC, id DESC
    LIMIT 1;

    SELECT *
    INTO v_originality
    FROM public.ai_originality_verification_runs
    WHERE staging_question_id = v_candidate.staging_question_id
    ORDER BY created_at DESC, id DESC
    LIMIT 1;

    SELECT *
    INTO v_readiness
    FROM public.ai_question_readiness_runs
    WHERE staging_question_id = v_candidate.staging_question_id
    ORDER BY evaluated_at DESC NULLS LAST, created_at DESC
    LIMIT 1;

    SELECT jsonb_build_object(
      'pending', count(*) FILTER (WHERE t.status = 'pending'),
      'running', count(*) FILTER (WHERE t.status = 'running'),
      'completed', count(*) FILTER (WHERE t.status = 'completed'),
      'failed', count(*) FILTER (WHERE t.status = 'failed'),
      'skipped', count(*) FILTER (WHERE t.status = 'skipped')
    )
    INTO v_bulk
    FROM public.admin_bulk_gate_tasks t
    JOIN public.admin_bulk_gate_runs r
      ON r.id = t.bulk_run_id
    WHERE t.staging_question_id = v_candidate.staging_question_id
      AND r.batch_id = p_batch_id;

    v_snapshot := jsonb_build_object(
      'question_text', v_candidate.question_text,
      'option_a', v_candidate.option_a,
      'option_b', v_candidate.option_b,
      'option_c', v_candidate.option_c,
      'option_d', v_candidate.option_d,
      'option_e', v_candidate.option_e,
      'proposed_correct_answer', v_candidate.proposed_correct_answer,
      'grade_level', v_candidate.grade_level,
      'subject_id', v_candidate.subject_id,
      'topic_id', v_candidate.proposed_topic_id,
      'subtopic_id', v_candidate.proposed_subtopic_id,
      'solve_time_seconds', v_candidate.proposed_solve_time_seconds,
      'curriculum_version_id', v_candidate.proposed_curriculum_version_id
    );

    v_gates := jsonb_build_object(
      'answer', jsonb_build_object(
        'run_id', v_answer.id,
        'status', v_answer.consensus_status,
        'human_decision', v_answer.human_decision,
        'human_reviewed_at', v_answer.human_reviewed_at,
        'consensus_answer', v_answer.consensus_answer,
        'solver_1_model', v_answer.solver_1_model,
        'solver_2_model', v_answer.solver_2_model
      ),
      'curriculum', jsonb_build_object(
        'run_id', v_curriculum.id,
        'status', v_curriculum.status,
        'human_decision', v_curriculum.human_decision,
        'human_review_required', v_curriculum.human_review_required,
        'human_reviewed_at', v_curriculum.human_reviewed_at
      ),
      'quality', jsonb_build_object(
        'run_id', v_quality.id,
        'status', v_quality.status,
        'human_decision', v_quality.human_decision,
        'human_review_required', v_quality.human_review_required,
        'human_reviewed_at', v_quality.human_reviewed_at,
        'consensus_quality_score', v_quality.consensus_quality_score
      ),
      'solve_time', jsonb_build_object(
        'run_id', v_solve_time.id,
        'status', v_solve_time.status,
        'human_decision', v_solve_time.human_decision,
        'human_review_required', v_solve_time.human_review_required,
        'consensus_total_seconds', v_solve_time.consensus_total_seconds
      ),
      'originality', jsonb_build_object(
        'run_id', v_originality.id,
        'status', v_originality.status,
        'human_decision', v_originality.human_decision,
        'human_review_required', v_originality.human_review_required,
        'consensus_originality_score', v_originality.consensus_originality_score,
        'copyright_risk_level', v_originality.copyright_risk_level
      )
    );

    v_items := v_items || jsonb_build_object(
      'staging_question_id', v_candidate.staging_question_id,
      'candidate_position', v_candidate.candidate_index,
      'client_question_id', v_candidate.client_question_id,
      'staging_status', v_candidate.staging_status,
      'grade_level', v_candidate.grade_level,
      'subject_id', v_candidate.subject_id,
      'subject_name', v_candidate.subject_name,
      'topic_id', v_candidate.proposed_topic_id,
      'topic_name', v_candidate.topic_name,
      'subtopic_id', v_candidate.proposed_subtopic_id,
      'subtopic_name', v_candidate.subtopic_name,
      'outcome_code', v_candidate.metadata ->> 'outcome_code',
      'required_outcome_id', v_candidate.metadata ->> 'required_outcome_id',
      'curriculum_version_id', v_candidate.proposed_curriculum_version_id,
      'question_text', v_candidate.question_text,
      'options', jsonb_build_object(
        'A', v_candidate.option_a,
        'B', v_candidate.option_b,
        'C', v_candidate.option_c,
        'D', v_candidate.option_d,
        'E', v_candidate.option_e
      ),
      'content_snapshot', v_snapshot,
      'gates', v_gates,
      'readiness', jsonb_build_object(
        'run_id', v_readiness.id,
        'status', v_readiness.readiness_status,
        'score', v_readiness.readiness_score,
        'blockers', v_readiness.blocking_reasons,
        'warnings', v_readiness.warnings,
        'evaluated_at', v_readiness.evaluated_at
      ),
      'bulk', v_bulk
    );
  END LOOP;

  RETURN v_items;
END;
$$;


REVOKE ALL
  ON FUNCTION private.bulk_gate_candidate_rows(uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION private.bulk_gate_candidate_rows(uuid)
  TO service_role;


-- ------------------------------------------------------------
-- 3.2) GRUP SINIFLANDIRMA
--     Sonuç listesindeki altı grup:
--       technical_error  -> teknik hata nedeniyle tamamlanamadı
--       running          -> kontrol çalışıyor
--       needs_fix        -> düzeltme veya uyuşmazlık var
--       waiting          -> kontrol bekliyor
--       human_pending    -> insan incelemesi/ölçümü bekliyor
--       ready_for_approval -> tüm zorunlu koşulları sağladı, nihai onay bekliyor
--       closed           -> karar kapanmış (rejected/promoted) — listede ayrı
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.bulk_gate_classify(p_row jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_gates jsonb;
  v_bulk jsonb;
  v_readiness jsonb;
BEGIN
  v_gates := COALESCE(p_row -> 'gates', '{}'::jsonb);
  v_bulk := COALESCE(p_row -> 'bulk', '{}'::jsonb);
  v_readiness := COALESCE(p_row -> 'readiness', '{}'::jsonb);

  -- 1) Teknik hata
  IF COALESCE((v_bulk ->> 'failed')::integer, 0) > 0 THEN
    RETURN 'technical_error';
  END IF;

  -- 2) Karar kapanmış
  IF (p_row ->> 'staging_status') IN ('rejected', 'promoted') THEN
    RETURN 'closed';
  END IF;

  -- 3) Çalışıyor
  IF COALESCE((v_bulk ->> 'running')::integer, 0) > 0 THEN
    RETURN 'running';
  END IF;

  -- 4) Düzeltme / uyuşmazlık
  IF (v_gates -> 'answer' ->> 'status') IN (
        'answer_mismatch', 'solver_disagreement', 'rejected'
      )
     OR (v_gates -> 'curriculum' ->> 'status') IN (
        'grade_mismatch', 'subject_mismatch', 'topic_mismatch',
        'subtopic_mismatch', 'outcome_mismatch', 'prerequisite_violation',
        'reviewer_disagreement', 'rejected'
      )
     OR (v_gates -> 'quality' ->> 'status') IN (
        'language_problem', 'scientific_problem', 'ambiguity_problem',
        'option_quality_problem', 'difficulty_mismatch', 'cognitive_mismatch',
        'question_type_mismatch', 'reviewer_disagreement', 'rejected'
      )
     OR (v_gates -> 'solve_time' ->> 'status') IN (
        'producer_mismatch', 'outside_requested_range',
        'reviewer_disagreement', 'rejected'
      )
     OR (v_gates -> 'originality' ->> 'status') IN (
        'low_originality', 'high_similarity', 'possible_duplicate',
        'copyright_risk', 'blocked', 'reviewer_disagreement', 'rejected'
      )
     OR (v_readiness ->> 'status') IN ('blocked', 'rejected')
  THEN
    RETURN 'needs_fix';
  END IF;

  -- 5) Eksik otomatik kontrol var
  IF (v_gates -> 'answer' ->> 'status') IS NULL
     OR (v_gates -> 'curriculum' ->> 'status') IS NULL
     OR (v_gates -> 'quality' ->> 'status') IS NULL
     OR COALESCE((v_bulk ->> 'pending')::integer, 0) > 0
  THEN
    RETURN 'waiting';
  END IF;

  -- 6) İnsan incelemesi / ölçümü bekliyor
  IF (v_gates -> 'answer' ->> 'status') IN ('needs_human_review', 'low_confidence')
     OR (v_gates -> 'curriculum' ->> 'status') IN ('needs_human_review', 'low_confidence')
     OR (v_gates -> 'quality' ->> 'status') IN ('needs_human_review', 'low_confidence')
     OR (v_gates -> 'solve_time' ->> 'status') IS NULL
     OR (v_gates -> 'originality' ->> 'status') IS NULL
     OR (v_gates -> 'solve_time' ->> 'status') IN (
          'needs_human_review', 'low_confidence',
          'waiting_reviewer_1', 'waiting_reviewer_2'
        )
     OR (v_gates -> 'originality' ->> 'status') IN (
          'needs_human_review', 'low_confidence',
          'waiting_reviewer_1', 'waiting_reviewer_2'
        )
  THEN
    RETURN 'human_pending';
  END IF;

  -- 7) Nihai insan onayı bekliyor
  IF (v_readiness ->> 'status') = 'ready_for_human_review'
     AND COALESCE((v_readiness ->> 'score')::numeric, 0) = 1
  THEN
    RETURN 'ready_for_approval';
  END IF;

  RETURN 'human_pending';
END;
$$;


REVOKE ALL
  ON FUNCTION private.bulk_gate_classify(jsonb)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION private.bulk_gate_classify(jsonb)
  TO service_role;


-- ------------------------------------------------------------
-- 3.3) TOPLU PLAN (tek doğruluk kaynağı)
--
--     Kural seti:
--       - Yalnız otomatikleştirilebilen kapılar: answer, curriculum, quality
--       - Tamamlanmış (verified) kontroller yeniden çalıştırılmaz
--       - İnsan kararı verilmiş kapılar yeniden çalıştırılmaz
--       - Mevcut bekleyen/çalışan görev varsa ikinci kopya oluşmaz
--       - Kapı zinciri sırayla ilerler: çözücü 1 -> çözücü 2,
--         gözden geçiren 1 -> gözden geçiren 2
--       - solve_time / originality insan ölçümü gerektirir: insan kuyruğu
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.bulk_gate_plan(
  p_batch_id uuid,
  p_scope text,
  p_candidate_ids uuid[],
  p_gates text[],
  p_group_filter text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_rows jsonb;
  v_row jsonb;
  v_task jsonb;
  v_tasks jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_human_queue jsonb := '[]'::jsonb;
  v_batch_count integer := 0;
  v_selected integer := 0;
  v_gate text;
  v_role text;
  v_status text;
  v_reason text;
  v_group text;
  v_need_start boolean;
  v_run_id uuid;
  v_staging uuid;
BEGIN
  v_rows := private.bulk_gate_candidate_rows(p_batch_id);

  FOR v_row IN
    SELECT value FROM jsonb_array_elements(v_rows) AS t(value)
  LOOP
    v_batch_count := v_batch_count + 1;
    v_staging := (v_row ->> 'staging_question_id')::uuid;
    v_group := private.bulk_gate_classify(v_row);

    -- KAPSAM
    IF p_scope = 'selection' THEN
      IF NOT (
        v_staging = ANY(COALESCE(p_candidate_ids, ARRAY[]::uuid[]))
      ) THEN
        CONTINUE;
      END IF;
    ELSIF p_scope = 'filter' THEN
      IF p_group_filter IS NOT NULL AND v_group <> p_group_filter THEN
        CONTINUE;
      END IF;
    ELSE
      RAISE EXCEPTION 'Invalid bulk scope.';
    END IF;

    v_selected := v_selected + 1;

    -- Kapanmış aday
    IF (v_row ->> 'staging_status') IN ('rejected', 'promoted') THEN
      v_skipped := v_skipped || jsonb_build_object(
        'staging_question_id', v_staging,
        'candidate_position', v_row ->> 'candidate_position',
        'gate_key', NULL,
        'reason_code', 'terminal_candidate'
      );
      CONTINUE;
    END IF;

    FOR v_gate IN SELECT unnest(COALESCE(p_gates, ARRAY[]::text[]))
    LOOP
      v_role := NULL;
      v_reason := NULL;
      v_need_start := false;
      v_run_id := NULL;
      v_status := v_row -> 'gates' -> v_gate ->> 'status';

      IF v_gate = 'answer' THEN
        v_run_id := (v_row -> 'gates' -> 'answer' ->> 'run_id')::uuid;
        IF v_status IS NULL THEN
          v_role := 'solver_1';
          v_need_start := true;
        ELSIF v_status = 'waiting_solver_1' THEN
          v_role := 'solver_1';
        ELSIF v_status = 'waiting_solver_2' THEN
          v_role := 'solver_2';
        ELSIF v_status = 'verified' THEN
          v_reason := 'already_completed';
        ELSIF v_status IN ('needs_human_review', 'low_confidence') THEN
          v_reason := 'human_review_required';
        ELSIF v_status IN ('answer_mismatch', 'solver_disagreement') THEN
          v_reason := 'mismatch';
        ELSIF v_status = 'rejected' THEN
          v_reason := 'rejected';
        ELSE
          v_reason := 'gate_not_ready';
        END IF;
      ELSE
        -- curriculum / quality: gözden geçiren 1-2
        v_run_id := (v_row -> 'gates' -> v_gate ->> 'run_id')::uuid;
        IF v_status IS NULL THEN
          v_role := 'reviewer_1';
          v_need_start := true;
        ELSIF v_status = 'waiting_reviewer_1' THEN
          v_role := 'reviewer_1';
        ELSIF v_status = 'waiting_reviewer_2' THEN
          v_role := 'reviewer_2';
        ELSIF v_status = 'verified' THEN
          v_reason := 'already_completed';
        ELSIF v_status IN ('needs_human_review', 'low_confidence') THEN
          v_reason := 'human_review_required';
        ELSIF v_status IN (
          'grade_mismatch', 'subject_mismatch', 'topic_mismatch',
          'subtopic_mismatch', 'outcome_mismatch', 'prerequisite_violation',
          'language_problem', 'scientific_problem', 'ambiguity_problem',
          'option_quality_problem', 'difficulty_mismatch',
          'cognitive_mismatch', 'question_type_mismatch', 'rejected'
        ) THEN
          v_reason := 'mismatch';
        ELSE
          v_reason := 'gate_not_ready';
        END IF;
      END IF;

      -- İnsan kararı verilmiş kapı yeniden çalıştırılmaz
      IF v_reason IS NULL
         AND (v_row -> 'gates' -> v_gate ->> 'human_decision') IS NOT NULL
      THEN
        v_reason := 'human_decided';
      END IF;

      IF v_reason IS NOT NULL THEN
        v_skipped := v_skipped || jsonb_build_object(
          'staging_question_id', v_staging,
          'candidate_position', v_row ->> 'candidate_position',
          'gate_key', v_gate,
          'reason_code', v_reason
        );
        CONTINUE;
      END IF;

      -- Aynı kapı için bekleyen/çalışan görev varsa ikinci kopya oluşmaz
      IF EXISTS (
        SELECT 1
        FROM public.admin_bulk_gate_tasks t
        JOIN public.admin_bulk_gate_runs r
          ON r.id = t.bulk_run_id
        WHERE t.staging_question_id = v_staging
          AND t.gate_key = v_gate
          AND t.status IN ('pending', 'running')
          AND r.batch_id = p_batch_id
      ) THEN
        v_skipped := v_skipped || jsonb_build_object(
          'staging_question_id', v_staging,
          'candidate_position', v_row ->> 'candidate_position',
          'gate_key', v_gate,
          'reason_code', 'duplicate_pending_task'
        );
        CONTINUE;
      END IF;

      v_task := jsonb_build_object(
        'staging_question_id', v_staging,
        'candidate_position', v_row ->> 'candidate_position',
        'gate_key', v_gate,
        'gate_role', v_role,
        'need_start', v_need_start,
        'gate_run_id', v_run_id,
        'content_snapshot', v_row -> 'content_snapshot'
      );
      v_tasks := v_tasks || v_task;
    END LOOP;

    -- İnsan ölçümü gerektiren kapılar ayrı kuyrukta
    IF (v_row -> 'gates' -> 'solve_time' ->> 'status') IS NULL
       OR (v_row -> 'gates' -> 'originality' ->> 'status') IS NULL
    THEN
      v_human_queue := v_human_queue || jsonb_build_object(
        'staging_question_id', v_staging,
        'candidate_position', v_row ->> 'candidate_position',
        'reason_code', 'human_measurement_required',
        'gates', jsonb_build_array('solve_time', 'originality')
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'scope', p_scope,
    'group_filter', p_group_filter,
    'gates', to_jsonb(COALESCE(p_gates, ARRAY[]::text[])),
    'batch_candidate_count', v_batch_count,
    'selected_candidate_count', v_selected,
    'tasks', v_tasks,
    'skipped', v_skipped,
    'human_queue', v_human_queue,
    'planned_model_calls', jsonb_array_length(v_tasks),
    'cost_estimate_status', 'unavailable',
    'cost_estimate_minor_units', NULL,
    'cost_currency', NULL
  );
END;
$$;


REVOKE ALL
  ON FUNCTION private.bulk_gate_plan(uuid, text, uuid[], text[], text)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION private.bulk_gate_plan(uuid, text, uuid[], text[], text)
  TO service_role;


-- ============================================================
-- 4) PUBLIC RPC'LER (insan paneli yüzeyi)
-- ============================================================

-- ------------------------------------------------------------
-- 4.1) PLAN (salt-okunur) — kapsam öncesi önizleme
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.plan_bulk_gate_control(
  p_batch_id uuid,
  p_scope text,
  p_candidate_ids uuid[] DEFAULT ARRAY[]::uuid[],
  p_gates text[] DEFAULT ARRAY[]::text[],
  p_group_filter text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan jsonb;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  IF p_scope NOT IN ('selection', 'filter') THEN
    RAISE EXCEPTION 'Invalid bulk scope.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM unnest(COALESCE(p_gates, ARRAY[]::text[])) g(g)
    WHERE g.g NOT IN ('answer', 'curriculum', 'quality')
  ) THEN
    RAISE EXCEPTION 'Unsupported gate for bulk control.';
  END IF;

  v_plan := private.bulk_gate_plan(
    p_batch_id,
    p_scope,
    p_candidate_ids,
    p_gates,
    p_group_filter
  );

  RETURN v_plan;
END;
$$;


REVOKE ALL
  ON FUNCTION public.plan_bulk_gate_control(uuid, text, uuid[], text[], text)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.plan_bulk_gate_control(uuid, text, uuid[], text[], text)
  TO authenticated, service_role;


-- ------------------------------------------------------------
-- 4.2) TOPLU BAŞLAT — planı sunucuda yeniden hesaplar, görevleri açar
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_bulk_gate_control(
  p_batch_id uuid,
  p_scope text,
  p_candidate_ids uuid[] DEFAULT ARRAY[]::uuid[],
  p_gates text[] DEFAULT ARRAY[]::text[],
  p_group_filter text DEFAULT NULL,
  p_model text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_plan jsonb;
  v_task jsonb;
  v_run_id uuid;
  v_bulk_run_id uuid;
  v_created integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_staging uuid;
  v_gate text;
  v_role text;
  v_need_start boolean;
  v_gate_run_id uuid;
  v_snapshot jsonb;
  v_position integer;
  v_start_error text;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  IF p_scope NOT IN ('selection', 'filter') THEN
    RAISE EXCEPTION 'Invalid bulk scope.';
  END IF;

  IF COALESCE(btrim(p_model), '') = '' THEN
    RAISE EXCEPTION 'Model identifier is required.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM unnest(COALESCE(p_gates, ARRAY[]::text[])) g(g)
    WHERE g.g NOT IN ('answer', 'curriculum', 'quality')
  ) THEN
    RAISE EXCEPTION 'Unsupported gate for bulk control.';
  END IF;

  IF p_scope = 'selection'
     AND COALESCE(array_length(p_candidate_ids, 1), 0) = 0
  THEN
    RAISE EXCEPTION 'No candidate selected.';
  END IF;

  -- Plan sunucuda yeniden hesaplanır (istemci listesi güvenilmez).
  v_plan := private.bulk_gate_plan(
    p_batch_id,
    p_scope,
    p_candidate_ids,
    p_gates,
    p_group_filter
  );

  INSERT INTO public.admin_bulk_gate_runs (
    batch_id,
    scope,
    filter_spec,
    gates,
    model,
    status,
    planned_candidate_count,
    planned_task_count,
    planned_model_call_count,
    cost_estimate_status,
    cost_estimate_minor_units,
    cost_currency,
    created_by
  )
  VALUES (
    p_batch_id,
    p_scope,
    jsonb_build_object('group', p_group_filter),
    COALESCE(p_gates, ARRAY[]::text[]),
    p_model,
    'planned',
    (v_plan ->> 'selected_candidate_count')::integer,
    jsonb_array_length(v_plan -> 'tasks'),
    (v_plan ->> 'planned_model_calls')::integer,
    'unavailable',
    NULL,
    NULL,
    auth.uid()
  )
  RETURNING id INTO v_bulk_run_id;

  FOR v_task IN SELECT value FROM jsonb_array_elements(v_plan -> 'tasks') AS t(value)
  LOOP
    v_staging := (v_task ->> 'staging_question_id')::uuid;
    v_gate := v_task ->> 'gate_key';
    v_role := v_task ->> 'gate_role';
    v_need_start := COALESCE((v_task ->> 'need_start')::boolean, false);
    v_gate_run_id := (v_task ->> 'gate_run_id')::uuid;
    v_snapshot := v_task -> 'content_snapshot';
    v_position := (v_task ->> 'candidate_position')::integer;

    -- Kapı çalıştırma kaydı yoksa oluştur (mevcut start RPC üzerinden;
    --   guard ve kapı sözleşmesi aynen korunur).
    IF v_need_start THEN
      BEGIN
        IF v_gate = 'answer' THEN
          v_gate_run_id := private.start_answer_verification(v_staging, 0.90);
        ELSIF v_gate = 'curriculum' THEN
          v_gate_run_id := private.start_curriculum_fit_verification(v_staging, 0.90);
        ELSIF v_gate = 'quality' THEN
          v_gate_run_id := private.start_question_quality_review(v_staging, 0.90, 0.85);
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_start_error := SQLERRM;
        v_gate_run_id := NULL;
      END;
    END IF;

    IF v_start_error IS NOT NULL THEN
      v_errors := v_errors || jsonb_build_object(
        'staging_question_id', v_staging,
        'candidate_position', v_position,
        'gate_key', v_gate,
        'gate_role', v_role,
        'error_code', 'gate_start_failed',
        'error_message', v_start_error
      );
      v_start_error := NULL;
      CONTINUE;
    END IF;

    IF v_gate_run_id IS NULL THEN
      v_errors := v_errors || jsonb_build_object(
        'staging_question_id', v_staging,
        'candidate_position', v_position,
        'gate_key', v_gate,
        'gate_role', v_role,
        'error_code', 'gate_run_missing',
        'error_message', 'Gate run could not be opened.'
      );
      CONTINUE;
    END IF;

    INSERT INTO public.admin_bulk_gate_tasks (
      bulk_run_id,
      staging_question_id,
      candidate_position,
      gate_key,
      gate_role,
      status,
      gate_run_id,
      content_snapshot
    )
    VALUES (
      v_bulk_run_id,
      v_staging,
      v_position,
      v_gate,
      v_role,
      'pending',
      v_gate_run_id,
      v_snapshot
    )
    ON CONFLICT (bulk_run_id, staging_question_id, gate_key, gate_role)
    DO NOTHING;

    IF FOUND THEN
      v_created := v_created + 1;
    END IF;
  END LOOP;

  UPDATE public.admin_bulk_gate_runs
  SET
    planned_task_count = v_created,
    planned_model_call_count = v_created,
    status = CASE WHEN v_created = 0 THEN 'completed' ELSE 'planned' END
  WHERE id = v_bulk_run_id;

  RETURN jsonb_build_object(
    'bulk_run_id', v_bulk_run_id,
    'created_task_count', v_created,
    'selected_candidate_count', (v_plan ->> 'selected_candidate_count')::integer,
    'skipped', v_plan -> 'skipped',
    'human_queue', v_plan -> 'human_queue',
    'errors', v_errors,
    'planned_model_calls', v_created,
    'cost_estimate_status', 'unavailable',
    'cost_estimate_minor_units', NULL,
    'cost_currency', NULL,
    'model', p_model
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.start_bulk_gate_control(uuid, text, uuid[], text[], text, text)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.start_bulk_gate_control(uuid, text, uuid[], text[], text, text)
  TO authenticated, service_role;


-- ------------------------------------------------------------
-- 4.3) DURUM + SONUÇ LİSTESİ (salt-okunur)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_bulk_gate_control_status(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_runs jsonb;
  v_tasks jsonb;
  v_counts jsonb;
  v_rows jsonb;
  v_items jsonb := '[]'::jsonb;
  v_row jsonb;
  v_group text;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY x.created_at DESC), '[]'::jsonb)
  INTO v_runs
  FROM (
    SELECT
      r.id,
      r.scope,
      r.filter_spec,
      r.gates,
      r.model,
      r.status,
      r.stop_requested,
      r.planned_candidate_count,
      r.planned_task_count,
      r.planned_model_call_count,
      r.cost_estimate_status,
      r.cost_estimate_minor_units,
      r.cost_currency,
      r.created_by,
      r.created_at,
      r.started_at,
      r.stopped_at
    FROM public.admin_bulk_gate_runs r
    WHERE r.batch_id = p_batch_id
    ORDER BY r.created_at DESC
    LIMIT 5
  ) x;

  SELECT coalesce(jsonb_agg(x ORDER BY x.created_at DESC), '[]'::jsonb)
  INTO v_tasks
  FROM (
    SELECT
      t.id,
      t.bulk_run_id,
      t.staging_question_id,
      t.candidate_position,
      t.gate_key,
      t.gate_role,
      t.status,
      t.attempt_count,
      t.gate_run_id,
      t.error_code,
      t.error_message,
      t.created_at,
      t.started_at,
      t.completed_at
    FROM public.admin_bulk_gate_tasks t
    JOIN public.admin_bulk_gate_runs r
      ON r.id = t.bulk_run_id
    WHERE r.batch_id = p_batch_id
    ORDER BY t.created_at DESC
    LIMIT 500
  ) x;

  SELECT jsonb_build_object(
    'pending', count(*) FILTER (WHERE t.status = 'pending'),
    'running', count(*) FILTER (WHERE t.status = 'running'),
    'completed', count(*) FILTER (WHERE t.status = 'completed'),
    'failed', count(*) FILTER (WHERE t.status = 'failed'),
    'skipped', count(*) FILTER (WHERE t.status = 'skipped')
  )
  INTO v_counts
  FROM public.admin_bulk_gate_tasks t
  JOIN public.admin_bulk_gate_runs r
    ON r.id = t.bulk_run_id
  WHERE r.batch_id = p_batch_id;

  v_rows := private.bulk_gate_candidate_rows(p_batch_id);

  FOR v_row IN SELECT value FROM jsonb_array_elements(v_rows) AS t(value)
  LOOP
    v_group := private.bulk_gate_classify(v_row);
    v_items := v_items || jsonb_build_object(
      'staging_question_id', v_row -> 'staging_question_id',
      'candidate_position', v_row -> 'candidate_position',
      'client_question_id', v_row -> 'client_question_id',
      'staging_status', v_row -> 'staging_status',
      'grade_level', v_row -> 'grade_level',
      'subject_name', v_row -> 'subject_name',
      'topic_name', v_row -> 'topic_name',
      'subtopic_name', v_row -> 'subtopic_name',
      'outcome_code', v_row -> 'outcome_code',
      'question_text', v_row -> 'question_text',
      'options', v_row -> 'options',
      'gates', v_row -> 'gates',
      'readiness', v_row -> 'readiness',
      'bulk', v_row -> 'bulk',
      'group', v_group
    );
  END LOOP;

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'runs', v_runs,
    'tasks', v_tasks,
    'task_counts', v_counts,
    'candidates', v_items
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.get_bulk_gate_control_status(uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.get_bulk_gate_control_status(uuid)
  TO authenticated, service_role;


-- ------------------------------------------------------------
-- 4.4) DURDUR / DEVAM ET
--     Durdurma YENİ iş alımını keser; çalışan görevlerin yazımı
--     güvensiz biçimde kesilmez.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_bulk_gate_control_stop(
  p_bulk_run_id uuid,
  p_stop boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row record;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  UPDATE public.admin_bulk_gate_runs
  SET
    stop_requested = p_stop,
    status = CASE
      WHEN p_stop THEN 'stopped'
      WHEN status = 'stopped' THEN 'running'
      ELSE status
    END,
    stopped_at = CASE WHEN p_stop THEN now() ELSE NULL END
  WHERE id = p_bulk_run_id
  RETURNING
    id, scope, status, stop_requested, model,
    planned_candidate_count, planned_task_count, planned_model_call_count,
    cost_estimate_status, created_at, started_at, stopped_at
  INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bulk run not found.';
  END IF;

  RETURN jsonb_build_object(
    'bulk_run_id', v_row.id,
    'status', v_row.status,
    'stop_requested', v_row.stop_requested,
    'planned_task_count', v_row.planned_task_count,
    'planned_model_call_count', v_row.planned_model_call_count,
    'cost_estimate_status', v_row.cost_estimate_status,
    'model', v_row.model
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.set_bulk_gate_control_stop(uuid, boolean)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.set_bulk_gate_control_stop(uuid, boolean)
  TO authenticated, service_role;


-- ------------------------------------------------------------
-- 4.5) BAŞARISIZ TEKNİK İŞLERİ KONTROLLÜ YENİDEN DENE
--     Aynı hata için en fazla 3 deneme; sonrası "skipped" (engelli kayıt).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.retry_failed_bulk_gate_tasks(p_bulk_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_requeued integer := 0;
  v_exhausted integer := 0;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.admin_bulk_gate_runs WHERE id = p_bulk_run_id
  ) THEN
    RAISE EXCEPTION 'Bulk run not found.';
  END IF;

  UPDATE public.admin_bulk_gate_tasks
  SET
    status = 'skipped',
    error_code = 'max_attempts_exceeded',
    error_message = COALESCE(error_message,
      'Maximum 3 controlled attempts were used for this task.'),
    completed_at = now(),
    claimed_by = NULL,
    lease_expires_at = NULL
  WHERE bulk_run_id = p_bulk_run_id
    AND status = 'failed'
    AND attempt_count >= 3;

  GET DIAGNOSTICS v_exhausted = ROW_COUNT;

  UPDATE public.admin_bulk_gate_tasks
  SET
    status = 'pending',
    error_code = NULL,
    error_message = NULL,
    completed_at = NULL,
    claimed_by = NULL,
    lease_expires_at = NULL
  WHERE bulk_run_id = p_bulk_run_id
    AND status = 'failed'
    AND attempt_count < 3;

  GET DIAGNOSTICS v_requeued = ROW_COUNT;

  UPDATE public.admin_bulk_gate_runs
  SET
    status = CASE
      WHEN stop_requested THEN 'stopped'
      WHEN v_requeued > 0 THEN 'running'
      ELSE status
    END
  WHERE id = p_bulk_run_id;

  RETURN jsonb_build_object(
    'bulk_run_id', p_bulk_run_id,
    'requeued_task_count', v_requeued,
    'skipped_exhausted_count', v_exhausted
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.retry_failed_bulk_gate_tasks(uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE
  ON FUNCTION public.retry_failed_bulk_gate_tasks(uuid)
  TO authenticated, service_role;


-- ============================================================
-- 5) SERVICE_ROLE RPC'LER (worker yüzeyi)
-- ============================================================

-- ------------------------------------------------------------
-- 5.1) GÖREV AL (lease) — sınırlı eşzamanlılık ve durdurma
--     Dönen kör bağlam yalnız allowlist alanları içerir:
--     soru metni, seçenekler, ders adı, aday kimliği.
--     Üretici önerisi (proposed_correct_answer) veya çözüm metni YOKTUR.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_bulk_gate_tasks(
  p_worker_id text,
  p_limit integer DEFAULT 1,
  p_lease_seconds integer DEFAULT 300
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_task record;
  v_ctx record;
  v_model text;
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required.';
  END IF;

  FOR v_task IN
    WITH candidates AS (
      SELECT t.id
      FROM public.admin_bulk_gate_tasks t
      JOIN public.admin_bulk_gate_runs r
        ON r.id = t.bulk_run_id
      WHERE t.status = 'pending'
        AND r.stop_requested = false
      ORDER BY t.created_at ASC, t.id ASC
      FOR UPDATE OF t SKIP LOCKED
      LIMIT GREATEST(COALESCE(p_limit, 1), 1)
    )
    UPDATE public.admin_bulk_gate_tasks t
    SET
      status = 'running',
      claimed_by = p_worker_id,
      lease_expires_at = now()
        + make_interval(secs => GREATEST(COALESCE(p_lease_seconds, 300), 30)),
      started_at = COALESCE(t.started_at, now()),
      attempt_count = t.attempt_count + 1
    FROM candidates c
    WHERE t.id = c.id
    RETURNING
      t.id,
      t.bulk_run_id,
      t.staging_question_id,
      t.candidate_position,
      t.gate_key,
      t.gate_role,
      t.attempt_count,
      t.gate_run_id,
      t.content_snapshot
  LOOP
    SELECT r.model
    INTO v_model
    FROM public.admin_bulk_gate_runs r
    WHERE r.id = v_task.bulk_run_id;

    SELECT
      COALESCE(
        NULLIF(s.metadata ->> 'client_question_id', ''),
        s.metadata ->> 'client_question_id'
      ) AS client_question_id,
      sub.name AS subject_name,
      s.question_text,
      s.option_a, s.option_b, s.option_c, s.option_d, s.option_e,
      s.proposed_correct_answer,
      s.grade_level,
      s.subject_id,
      s.proposed_topic_id,
      s.proposed_subtopic_id,
      s.proposed_solve_time_seconds,
      s.proposed_curriculum_version_id,
      s.metadata ->> 'outcome_code' AS outcome_code
    INTO v_ctx
    FROM public.ai_question_staging s
    LEFT JOIN public.subjects sub
      ON sub.id = s.subject_id
    WHERE s.id = v_task.staging_question_id;

    v_items := v_items || jsonb_build_object(
      'task_id', v_task.id,
      'bulk_run_id', v_task.bulk_run_id,
      'staging_question_id', v_task.staging_question_id,
      'candidate_position', v_task.candidate_position,
      'gate_key', v_task.gate_key,
      'gate_role', v_task.gate_role,
      'attempt_count', v_task.attempt_count,
      'gate_run_id', v_task.gate_run_id,
      'content_snapshot', v_task.content_snapshot,
      'current_snapshot', jsonb_build_object(
        'question_text', v_ctx.question_text,
        'option_a', v_ctx.option_a,
        'option_b', v_ctx.option_b,
        'option_c', v_ctx.option_c,
        'option_d', v_ctx.option_d,
        'option_e', v_ctx.option_e,
        'proposed_correct_answer', v_ctx.proposed_correct_answer,
        'grade_level', v_ctx.grade_level,
        'subject_id', v_ctx.subject_id,
        'topic_id', v_ctx.proposed_topic_id,
        'subtopic_id', v_ctx.proposed_subtopic_id,
        'solve_time_seconds', v_ctx.proposed_solve_time_seconds,
        'curriculum_version_id', v_ctx.proposed_curriculum_version_id
      ),
      'model', v_model,
      'blind_context', jsonb_build_object(
        'clientQuestionId', v_ctx.client_question_id,
        'subjectName', COALESCE(v_ctx.subject_name, 'Matematik'),
        'questionText', v_ctx.question_text,
        'options', jsonb_build_object(
          'A', v_ctx.option_a,
          'B', v_ctx.option_b,
          'C', v_ctx.option_c,
          'D', v_ctx.option_d,
          'E', v_ctx.option_e
        ),
        'gradeLevel', v_ctx.grade_level,
        'subjectId', v_ctx.subject_id,
        'topicId', v_ctx.proposed_topic_id,
        'subtopicId', v_ctx.proposed_subtopic_id,
        'curriculumVersionId', v_ctx.proposed_curriculum_version_id,
        'outcomeCode', v_ctx.outcome_code
      )
    );
  END LOOP;

  RETURN jsonb_build_object(
    'claimed_count', jsonb_array_length(v_items),
    'tasks', v_items
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.claim_bulk_gate_tasks(text, integer, integer)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.claim_bulk_gate_tasks(text, integer, integer)
  TO service_role;


-- ------------------------------------------------------------
-- 5.2) GÖREV TAMAMLA — zincir adımı ve koşu durumu
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_bulk_gate_task(
  p_task_id uuid,
  p_status text,
  p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_task record;
  v_next_status text;
  v_next_created boolean := false;
  v_next_role text;
  v_remaining integer := 0;
  v_run_stopped boolean := false;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required.';
  END IF;

  IF p_status NOT IN ('completed', 'failed', 'skipped') THEN
    RAISE EXCEPTION 'Invalid task status.';
  END IF;

  SELECT *
  INTO v_task
  FROM public.admin_bulk_gate_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bulk task not found.';
  END IF;

  UPDATE public.admin_bulk_gate_tasks
  SET
    status = p_status,
    error_code = p_error_code,
    error_message = p_error_message,
    completed_at = CASE
      WHEN p_status = 'pending' THEN NULL
      ELSE now()
    END,
    claimed_by = NULL,
    lease_expires_at = NULL
  WHERE id = p_task_id;

  -- Zincir: kapı sıradaki adımı bekliyorsa yeni görev açılır.
  IF p_status = 'completed' THEN
    v_next_role := NULL;

    IF v_task.gate_key = 'answer' THEN
      SELECT consensus_status
      INTO v_next_status
      FROM public.ai_answer_verification_runs
      WHERE id = v_task.gate_run_id;

      IF v_next_status = 'waiting_solver_2' THEN
        v_next_role := 'solver_2';
      END IF;
    ELSE
      IF v_task.gate_key = 'curriculum' THEN
        SELECT status
        INTO v_next_status
        FROM public.ai_curriculum_fit_runs
        WHERE id = v_task.gate_run_id;
      ELSIF v_task.gate_key = 'quality' THEN
        SELECT status
        INTO v_next_status
        FROM public.ai_question_quality_runs
        WHERE id = v_task.gate_run_id;
      END IF;

      IF v_next_status = 'waiting_reviewer_2' THEN
        v_next_role := 'reviewer_2';
      END IF;
    END IF;

    IF v_next_role IS NOT NULL THEN
      INSERT INTO public.admin_bulk_gate_tasks (
        bulk_run_id,
        staging_question_id,
        candidate_position,
        gate_key,
        gate_role,
        status,
        gate_run_id,
        content_snapshot
      )
      VALUES (
        v_task.bulk_run_id,
        v_task.staging_question_id,
        v_task.candidate_position,
        v_task.gate_key,
        v_next_role,
        'pending',
        v_task.gate_run_id,
        v_task.content_snapshot
      )
      ON CONFLICT (bulk_run_id, staging_question_id, gate_key, gate_role)
      DO NOTHING;

      v_next_created := FOUND;
    END IF;
  END IF;

  SELECT
    count(*) FILTER (WHERE t.status IN ('pending', 'running')),
    COALESCE(bool_or(r.stop_requested), false)
  INTO v_remaining, v_run_stopped
  FROM public.admin_bulk_gate_tasks t
  JOIN public.admin_bulk_gate_runs r
    ON r.id = t.bulk_run_id
  WHERE t.bulk_run_id = v_task.bulk_run_id;

  UPDATE public.admin_bulk_gate_runs
  SET
    status = CASE
      WHEN v_run_stopped THEN 'stopped'
      WHEN v_remaining = 0 THEN 'completed'
      ELSE 'running'
    END,
    started_at = COALESCE(started_at, now())
  WHERE id = v_task.bulk_run_id;

  RETURN jsonb_build_object(
    'task_id', p_task_id,
    'status', p_status,
    'next_task_created', v_next_created,
    'remaining_task_count', v_remaining,
    'run_stopped', v_run_stopped
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.complete_bulk_gate_task(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.complete_bulk_gate_task(uuid, text, text, text)
  TO service_role;


-- ------------------------------------------------------------
-- 5.3) GÖREVİ YENİDEN KUYAĞA AL (hata geri çekilmesi)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.requeue_bulk_gate_task(
  p_task_id uuid,
  p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_attempt integer;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required.';
  END IF;

  UPDATE public.admin_bulk_gate_tasks
  SET
    status = 'pending',
    error_code = p_error_code,
    error_message = p_error_message,
    completed_at = NULL,
    claimed_by = NULL,
    lease_expires_at = NULL
  WHERE id = p_task_id
  RETURNING attempt_count INTO v_attempt;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bulk task not found.';
  END IF;

  RETURN jsonb_build_object(
    'task_id', p_task_id,
    'status', 'pending',
    'attempt_count', v_attempt
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.requeue_bulk_gate_task(uuid, text, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.requeue_bulk_gate_task(uuid, text, text)
  TO service_role;


-- ------------------------------------------------------------
-- 5.4) KANONİK KAZANIM KODLARI (müfredat kapısının kural kitabı)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_canonical_outcome_codes(
  p_curriculum_version_id uuid,
  p_subject_id uuid,
  p_min_grade integer DEFAULT 9,
  p_max_grade integer DEFAULT 12
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'code', o.outcome_code,
        'text', o.outcome_text
      )
      ORDER BY o.grade_level, o.outcome_code
    ),
    '[]'::jsonb
  )
  FROM public.curriculum_outcomes o
  WHERE o.is_active = true
    AND (p_curriculum_version_id IS NULL OR o.curriculum_version_id = p_curriculum_version_id)
    AND (p_subject_id IS NULL OR o.subject_id = p_subject_id)
    AND o.grade_level BETWEEN COALESCE(p_min_grade, 9) AND COALESCE(p_max_grade, 12);
$$;


REVOKE ALL
  ON FUNCTION public.get_canonical_outcome_codes(uuid, uuid, integer, integer)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.get_canonical_outcome_codes(uuid, uuid, integer, integer)
  TO service_role;

COMMIT;
