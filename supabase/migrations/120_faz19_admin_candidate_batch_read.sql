-- ============================================================
-- 120_faz19_admin_candidate_batch_read.sql
-- Altın Kalemler — Faz 19: Aday Yükleme Paketleri — yalnızca
-- okuma (veri kıyısı) görünümü.
--
-- Kapsam: /admin/candidate-batches (liste) ve
-- /admin/candidate-batches/[id] (detay) sayfalarını besleyen
-- iki SECURITY DEFINER okuma RPC'si. YAZMA YOK; gerçek AI/fabrika
-- yok; intake/gate/promotion tetiklenmez. 117/118'in ürettiği
-- veriyi düzenlenemez özet olarak sunar.
--
--   1. public.list_candidate_question_batches(p_limit, p_offset)
--        → paket künyesi + sayaç özeti (allowlist; raw_payload
--          ASLA dönmez).
--   2. public.get_candidate_question_batch_detail(p_batch_id)
--        → paket + aday sonuçları + staging önizleme + validation
--          sonuçları + review_queue + gate/durum özeti.
--
-- Yetki: 118 intake kapısıyla BİREBİR aynı fail-closed kapı —
-- authenticated (ai.manage VEYA questions.approve) VEYA
-- service_role. auth.uid() yoksa kapatır. Bu fonksiyonlar
-- SECURITY DEFINER (sahip) olarak RLS'siz staging/denetim
-- tablolarını okuyabildiği için tek dar yetkili okuma yoludur;
-- tarayıcı RLS engeliyle doğrudan staging satırlarına erişemez.
--
-- Güvenlik notu: önizleme alanı allowlist'tir; question_text,
-- seçenekler, önerilen cevap, çözüm (staging metadata'da saklanan)
-- dahil tüm alanlar tek tek seçilir. Ham JSON metastasında
-- arbitrary alan taşınmaz. RPC'ye erişen herkese bu alanlar
-- açıktır — bu nedenle kapı bu görünümün tamamını yönetir.
--
-- İdempotent: CREATE OR REPLACE; şema/RLS/policy dokunulmaz;
-- append-only (117/118'e geri dokunulmaz). ACL teyidi 119 deseni.
-- ============================================================

begin;

-- ============================================================
-- 1. LIST — aday paketleri (sayfalı künye listesi)
-- ============================================================

create or replace function public.list_candidate_question_batches(
  p_limit integer default 25,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_limit integer;
  v_offset integer;
  v_total bigint;
  v_items jsonb;
begin
  v_uid := auth.uid();

  if v_uid is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  if coalesce(auth.role(), '') <> 'service_role'
     and not (
       public.current_user_has_admin_permission('ai.manage')
       or public.current_user_has_admin_permission('questions.approve')
     )
  then
    raise exception 'Aday paket listesi icin ai.manage veya questions.approve yetkisi gerekli.'
      using errcode = '42501';
  end if;

  v_limit := greatest(1, least(coalesce(p_limit, 25), 100));
  v_offset := greatest(0, coalesce(p_offset, 0));

  select count(*)
    into v_total
  from public.candidate_question_batches b;

  select coalesce(jsonb_agg(j), '[]'::jsonb)
    into v_items
  from (
    select jsonb_build_object(
      'batch_id', b.id,
      'batch_key', b.batch_key,
      'schema_version', b.schema_version,
      'origin', b.origin,
      'producer_id', b.producer_id,
      'producer_model', b.producer_model,
      'status', b.status,
      'counts', jsonb_build_object(
        'total_items', b.total_items,
        'valid_items', b.valid_items,
        'invalid_items', b.invalid_items,
        'inserted_items', b.inserted_items,
        'duplicate_items', b.duplicate_items
      ),
      'validation_summary', b.validation_summary,
      'created_at', b.created_at,
      'updated_at', b.updated_at
    ) as j
    from public.candidate_question_batches b
    order by b.created_at desc
    limit v_limit offset v_offset
  ) t;

  return jsonb_build_object(
    'items', v_items,
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset
  );
end;
$$;


revoke all
on function public.list_candidate_question_batches(integer, integer)
from public, anon;


grant execute
on function public.list_candidate_question_batches(integer, integer)
to authenticated, service_role;


-- ============================================================
-- 2. DETAIL — tek paketin aday-adası özeti
-- ============================================================

create or replace function public.get_candidate_question_batch_detail(
  p_batch_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_batch public.candidate_question_batches%rowtype;
  v_candidates jsonb := '[]'::jsonb;
  v_candidate jsonb;
  v_preview jsonb;
  v_validation jsonb;
  v_review_entries jsonb;
  v_answer jsonb;
  v_curriculum jsonb;
  v_solve jsonb;
  v_originality jsonb;
  v_quality jsonb;
  v_readiness jsonb;
  v_final_review jsonb;
  r record;
begin
  v_uid := auth.uid();

  if v_uid is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  if coalesce(auth.role(), '') <> 'service_role'
     and not (
       public.current_user_has_admin_permission('ai.manage')
       or public.current_user_has_admin_permission('questions.approve')
     )
  then
    raise exception 'Aday paket detayi icin ai.manage veya questions.approve yetkisi gerekli.'
      using errcode = '42501';
  end if;

  if p_batch_id is null then
    raise exception 'p_batch_id zorunludur.'
      using errcode = '22023';
  end if;

  select *
    into v_batch
  from public.candidate_question_batches b
  where b.id = p_batch_id;

  if not found then
    raise exception 'Aday paketi bulunamadi.'
      using errcode = 'P0002';
  end if;

  for r in
    select
      cr.candidate_index,
      cr.client_question_id,
      cr.validation_status,
      cr.validation_errors,
      cr.validation_warnings,
      cr.staging_question_id,
      s.staging_status,
      s.ownership_status,
      s.license_status,
      s.commercial_use_allowed,
      s.copyright_risk_level,
      s.question_text,
      s.option_a,
      s.option_b,
      s.option_c,
      s.option_d,
      s.option_e,
      s.proposed_correct_answer,
      s.proposed_difficulty,
      s.proposed_cognitive_type,
      s.proposed_solve_time_seconds,
      s.grade_level,
      s.subject_id,
      s.proposed_curriculum_version_id,
      s.proposed_topic_id,
      s.proposed_subtopic_id,
      s.metadata
    from public.candidate_batch_candidate_results cr
    left join public.ai_question_staging s
      on s.id = cr.staging_question_id
    where cr.batch_id = p_batch_id
    order by cr.candidate_index asc
  loop

    if r.staging_question_id is null then
      v_preview := null;
      v_validation := '[]'::jsonb;
      v_review_entries := '[]'::jsonb;
      v_answer := null;
      v_curriculum := null;
      v_solve := null;
      v_originality := null;
      v_quality := null;
      v_readiness := null;
      v_final_review := null;
    else
      v_preview := jsonb_build_object(
        'staging_status', r.staging_status,
        'question_text', r.question_text,
        'options', jsonb_build_object(
          'A', r.option_a,
          'B', r.option_b,
          'C', r.option_c,
          'D', r.option_d,
          'E', r.option_e
        ),
        'proposed_correct_answer', r.proposed_correct_answer,
        'proposed_difficulty', r.proposed_difficulty,
        'proposed_cognitive_type', r.proposed_cognitive_type,
        'proposed_solve_time_seconds', r.proposed_solve_time_seconds,
        'grade_level', r.grade_level,
        'subject_id', r.subject_id,
        'proposed_curriculum_version_id', r.proposed_curriculum_version_id,
        'proposed_topic_id', r.proposed_topic_id,
        'proposed_subtopic_id', r.proposed_subtopic_id,
        'ownership_status', r.ownership_status,
        'license_status', r.license_status,
        'commercial_use_allowed', r.commercial_use_allowed,
        'copyright_risk_level', r.copyright_risk_level,
        'solution', r.metadata -> 'solution'
      );

      v_validation := (
        select coalesce(jsonb_agg(j order by vv.created_at asc), '[]'::jsonb)
        from (
          select jsonb_build_object(
            'validator_type', vr.validator_type,
            'validation_type', vr.validation_type,
            'result', vr.result,
            'score', vr.score,
            'summary', vr.summary,
            'provider_name', vr.provider_name,
            'model_name', vr.model_name,
            'prompt_version', vr.prompt_version,
            'created_at', vr.created_at
          ) as j,
          vr.created_at
          from public.ai_validation_results vr
          where vr.staging_question_id = r.staging_question_id
        ) vv
      );

      v_review_entries := (
        select coalesce(jsonb_agg(j order by rv.created_at asc), '[]'::jsonb)
        from (
          select jsonb_build_object(
            'reason_code', rq.reason_code,
            'reason_details', rq.reason_details,
            'priority', rq.priority,
            'status', rq.status,
            'created_at', rq.created_at
          ) as j,
          rq.created_at
          from public.review_queue rq
          where rq.entity_type = 'staging_question'
            and rq.entity_id = r.staging_question_id
        ) rv
      );

      v_answer := (
        select jsonb_build_object(
          'consensus_status', a.consensus_status,
          'consensus_answer', a.consensus_answer,
          'minimum_confidence', a.minimum_confidence,
          'solver_1_answer', a.solver_1_answer,
          'solver_1_confidence', a.solver_1_confidence,
          'solver_2_answer', a.solver_2_answer,
          'solver_2_confidence', a.solver_2_confidence,
          'human_decision', a.human_decision,
          'human_reviewed_by', a.human_reviewed_by,
          'human_reviewed_at', a.human_reviewed_at,
          'updated_at', a.updated_at
        )
        from public.ai_answer_verification_runs a
        where a.staging_question_id = r.staging_question_id
        order by a.created_at desc
        limit 1
      );

      v_curriculum := (
        select jsonb_build_object(
          'status', c.status,
          'expected_grade_level', c.expected_grade_level,
          'expected_subject_id', c.expected_subject_id,
          'expected_topic_id', c.expected_topic_id,
          'expected_subtopic_id', c.expected_subtopic_id,
          'expected_outcome_id', c.expected_outcome_id,
          'minimum_confidence', c.minimum_confidence,
          'human_decision', c.human_decision,
          'human_reviewed_by', c.human_reviewed_by,
          'human_reviewed_at', c.human_reviewed_at,
          'updated_at', c.updated_at
        )
        from public.ai_curriculum_fit_runs c
        where c.staging_question_id = r.staging_question_id
        order by c.created_at desc
        limit 1
      );

      v_solve := (
        select jsonb_build_object(
          'status', s.status,
          'producer_estimated_total_seconds', s.producer_estimated_total_seconds,
          'requested_min_seconds', s.requested_min_seconds,
          'requested_max_seconds', s.requested_max_seconds,
          'consensus_total_seconds', s.consensus_total_seconds,
          'recommended_race_limit_seconds', s.recommended_race_limit_seconds,
          'minimum_confidence', s.minimum_confidence,
          'human_decision', s.human_decision,
          'human_total_seconds', s.human_total_seconds,
          'human_reviewed_by', s.human_reviewed_by,
          'human_reviewed_at', s.human_reviewed_at,
          'updated_at', s.updated_at
        )
        from public.ai_solve_time_verification_runs s
        where s.staging_question_id = r.staging_question_id
        order by s.created_at desc
        limit 1
      );

      v_originality := (
        select jsonb_build_object(
          'status', o.status,
          'minimum_originality_score', o.minimum_originality_score,
          'maximum_similarity_score', o.maximum_similarity_score,
          'critical_similarity_score', o.critical_similarity_score,
          'consensus_originality_score', o.consensus_originality_score,
          'highest_detected_similarity_score', o.highest_detected_similarity_score,
          'highest_similarity_type', o.highest_similarity_type,
          'copyright_risk_level', o.copyright_risk_level,
          'human_decision', o.human_decision,
          'human_reviewed_by', o.human_reviewed_by,
          'human_reviewed_at', o.human_reviewed_at,
          'updated_at', o.updated_at
        )
        from public.ai_originality_verification_runs o
        where o.staging_question_id = r.staging_question_id
        order by o.created_at desc
        limit 1
      );

      v_quality := (
        select jsonb_build_object(
          'status', q.status,
          'minimum_confidence', q.minimum_confidence,
          'minimum_quality_score', q.minimum_quality_score,
          'consensus_quality_score', q.consensus_quality_score,
          'human_decision', q.human_decision,
          'human_reviewed_by', q.human_reviewed_by,
          'human_reviewed_at', q.human_reviewed_at,
          'updated_at', q.updated_at
        )
        from public.ai_question_quality_runs q
        where q.staging_question_id = r.staging_question_id
        order by q.created_at desc
        limit 1
      );

      v_readiness := (
        select jsonb_build_object(
          'readiness_status', rd.readiness_status,
          'readiness_score', rd.readiness_score,
          'blocking_reasons', rd.blocking_reasons,
          'warnings', rd.warnings,
          'answer_verification_passed', rd.answer_verification_passed,
          'curriculum_fit_passed', rd.curriculum_fit_passed,
          'solve_time_verification_passed', rd.solve_time_verification_passed,
          'originality_verification_passed', rd.originality_verification_passed,
          'question_quality_passed', rd.question_quality_passed,
          'commercial_clearance_status', rd.commercial_clearance_status,
          'commercial_ready', rd.commercial_ready,
          'evaluated_at', rd.evaluated_at,
          'updated_at', rd.updated_at
        )
        from public.ai_question_readiness_runs rd
        where rd.staging_question_id = r.staging_question_id
        order by rd.created_at desc
        limit 1
      );

      v_final_review := (
        select jsonb_build_object(
          'decision', fr.decision,
          'review_notes', fr.review_notes,
          'reviewed_by', fr.reviewed_by,
          'reviewed_at', fr.reviewed_at,
          'promoted_question_id', fr.promoted_question_id
        )
        from public.ai_question_final_reviews fr
        where fr.staging_question_id = r.staging_question_id
        order by fr.reviewed_at desc
        limit 1
      );
    end if;

    v_candidate := jsonb_build_object(
      'candidate_index', r.candidate_index,
      'client_question_id', r.client_question_id,
      'validation_status', r.validation_status,
      'validation_errors', r.validation_errors,
      'validation_warnings', r.validation_warnings,
      'staging_question_id', r.staging_question_id,
      'preview', v_preview,
      'validation_results', v_validation,
      'review_queue', v_review_entries,
      'gates', jsonb_build_object(
        'answer_verification', v_answer,
        'curriculum_fit', v_curriculum,
        'solve_time_verification', v_solve,
        'originality_verification', v_originality,
        'question_quality', v_quality,
        'readiness', v_readiness,
        'final_review', v_final_review
      )
    );

    v_candidates := v_candidates || v_candidate;
  end loop;

  return jsonb_build_object(
    'batch', jsonb_build_object(
      'batch_id', v_batch.id,
      'batch_key', v_batch.batch_key,
      'schema_version', v_batch.schema_version,
      'origin', v_batch.origin,
      'producer_id', v_batch.producer_id,
      'producer_model', v_batch.producer_model,
      'status', v_batch.status,
      'counts', jsonb_build_object(
        'total_items', v_batch.total_items,
        'valid_items', v_batch.valid_items,
        'invalid_items', v_batch.invalid_items,
        'inserted_items', v_batch.inserted_items,
        'duplicate_items', v_batch.duplicate_items
      ),
      'validation_summary', v_batch.validation_summary,
      'created_at', v_batch.created_at,
      'updated_at', v_batch.updated_at
    ),
    'candidates', v_candidates
  );
end;
$$;


revoke all
on function public.get_candidate_question_batch_detail(uuid)
from public, anon;


grant execute
on function public.get_candidate_question_batch_detail(uuid)
to authenticated, service_role;


commit;