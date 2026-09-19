-- ============================================================
-- 121_faz20_candidate_batch_operation_status.sql
-- Altın Kalemler — Faz 20: Üretim/denetim işlem durumu
-- (Yalnızca okuma, veri kıyısı).
--
-- Kapsam (Faz 16 §8 P1): paket aşaması, `waiting_*` gate'leri,
-- provider hatası ve güvenli yeniden deneme görünümü. API anahtarı
-- UI'da ASLA görünmez — zaten hiçbir provider kimliği (api_key,
-- secret vb.) bu RPC çıktısında yer alamaz.
--
--   public.get_candidate_question_batch_operation_status(p_batch_id)
--     → paket aşaması (status + aday durum dağılımı) + her gate için
--       son-run durum sayaçları (waiting_* başta) + provider hata
--       özeti (yalnız güvenli boolean/sayı; ham error_data OKUNMAZ)
--       + retry durumu.
--
-- Yetki: 118/119/120 ile BİREBİR aynı fail-closed kapı —
-- authenticated (ai.manage VEYA questions.approve) VEYA
-- service_role. auth.uid() yoksa kapatır. SECURITY DEFINER
-- (sahip) olarak RLS'siz staging/denetim tablolarını okuyabilen
-- tek dar yetkili okuma yoludur.
--
-- Güvenlik notları:
--   * Ham error_data / raw_payload / validation_errors içeriği
--     okunmaz ve dönmez; yalnızca "boş değil mi" boolean'ı ve
--     validation_errors'u dolu aday SAYISI döner. Orijinal hata
--     metni UI'a taşınmaz.
--   * `waiting_*` sayaçları: her adayın staging question'ı için o
--     gate'in EN SON run'ı esas alınır (DISTINCT ON + created_at
--     desc). Bekleyen gate "takılı" hissini hatalı üretmemek için
--     dolu/tespit durumları ayrı sayaçtadır.
--   * retry.supported = false: doğrulanmış backend gerçeği —
--     candidate-batch gate/in take akışı ai_job üretmez; 043'teki
--     worker-level retry yalnız `question_generation` job'ları
--     kapsar; gate run'larını yeniden başlatan public RPC yoktur.
--     Bu yüzden UI ASLA buradan "yeniden dene" düğmesi üretmez;
--     eksiklik sabit reason_key ile raporlanır.
--
-- İdempotent: CREATE OR REPLACE; append-only (117-120'e geri
-- dokunulmaz). ACL teyidi 119 deseni. Migration YALNIZ YEREL
-- disposable klonlarda uygulanabilir.
-- ============================================================

begin;

create or replace function public.get_candidate_question_batch_operation_status(
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
  v_batch record;
  v_candidate_counts jsonb;
  v_answer jsonb;
  v_curriculum jsonb;
  v_solve jsonb;
  v_originality jsonb;
  v_quality jsonb;
  v_readiness jsonb;
  v_final_review jsonb;
  v_has_batch_error boolean;
  v_candidate_error_count bigint;
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
    raise exception 'Iislem durumu icin ai.manage veya questions.approve yetkisi gerekli.'
      using errcode = '42501';
  end if;

  if p_batch_id is null then
    raise exception 'p_batch_id zorunludur.'
      using errcode = '22023';
  end if;

  select b.id, b.batch_key, b.status,
         b.total_items, b.valid_items, b.invalid_items,
         b.inserted_items, b.duplicate_items,
         b.error_data, b.created_at, b.updated_at
    into v_batch
  from public.candidate_question_batches b
  where b.id = p_batch_id;

  if not found then
    raise exception 'Aday paketi bulunamadi.'
      using errcode = 'P0002';
  end if;

  -- ------------------------------------------------------------
  -- PAKET AŞAMASI — aday bazlı durum dağılımı
  -- ------------------------------------------------------------

  select jsonb_build_object(
    'pending', count(*) filter (where cr.validation_status = 'pending'),
    'valid', count(*) filter (where cr.validation_status = 'valid'),
    'invalid', count(*) filter (where cr.validation_status = 'invalid'),
    'duplicate', count(*) filter (where cr.validation_status = 'duplicate'),
    'inserted', count(*) filter (where cr.validation_status = 'inserted'),
    'failed', count(*) filter (where cr.validation_status = 'failed')
  )
    into v_candidate_counts
  from public.candidate_batch_candidate_results cr
  where cr.batch_id = p_batch_id;

  -- ------------------------------------------------------------
  -- PROVIDER HATA ÖZETİ — ham içerik SADECE varlık olarak okunur.
  -- ------------------------------------------------------------

  v_has_batch_error := v_batch.error_data is not null
                        and v_batch.error_data <> '{}'::jsonb;

  select count(*)
    into v_candidate_error_count
  from public.candidate_batch_candidate_results cr
  where cr.batch_id = p_batch_id
    and cr.validation_errors is not null
    and jsonb_typeof(cr.validation_errors) = 'array'
    and jsonb_array_length(cr.validation_errors) > 0;

  -- ------------------------------------------------------------
  -- GATE'LER — aday sayısı üzerinden son-run durum sayaçları
  -- (her gate run'ı staging sorularıyla bağlantılıdır).
  -- ------------------------------------------------------------

  v_answer := (
    select jsonb_build_object(
      'total', count(*) filter (where a.staging_question_id is not null),
      'waiting_solver_1', count(*) filter (where a.consensus_status = 'waiting_solver_1'),
      'waiting_solver_2', count(*) filter (where a.consensus_status = 'waiting_solver_2'),
      'needs_human_review', count(*) filter (where a.consensus_status = 'needs_human_review'),
      'verified', count(*) filter (where a.consensus_status = 'verified'),
      'rejected', count(*) filter (where a.consensus_status = 'rejected'),
      'other', count(*) filter (where a.consensus_status not in (
        'waiting_solver_1', 'waiting_solver_2', 'needs_human_review',
        'verified', 'rejected'
      ))
    )
    from (
      select distinct on (a1.staging_question_id)
        a1.staging_question_id, a1.consensus_status
      from public.ai_answer_verification_runs a1
      where a1.staging_question_id in (
        select cr.staging_question_id
        from public.candidate_batch_candidate_results cr
        where cr.batch_id = p_batch_id
          and cr.staging_question_id is not null
      )
      order by a1.staging_question_id, a1.created_at desc
    ) a
  );

  v_curriculum := (
    select jsonb_build_object(
      'total', count(*) filter (where c.staging_question_id is not null),
      'waiting_reviewer_1', count(*) filter (where c.status = 'waiting_reviewer_1'),
      'waiting_reviewer_2', count(*) filter (where c.status = 'waiting_reviewer_2'),
      'verified', count(*) filter (where c.status = 'verified'),
      'rejected', count(*) filter (where c.status = 'rejected'),
      'other', count(*) filter (where c.status not in (
        'waiting_reviewer_1', 'waiting_reviewer_2', 'verified', 'rejected'
      ))
    )
    from (
      select distinct on (c1.staging_question_id)
        c1.staging_question_id, c1.status
      from public.ai_curriculum_fit_runs c1
      where c1.staging_question_id in (
        select cr.staging_question_id
        from public.candidate_batch_candidate_results cr
        where cr.batch_id = p_batch_id
          and cr.staging_question_id is not null
      )
      order by c1.staging_question_id, c1.created_at desc
    ) c
  );

  v_solve := (
    select jsonb_build_object(
      'total', count(*) filter (where s.staging_question_id is not null),
      'waiting_reviewer_1', count(*) filter (where s.status = 'waiting_reviewer_1'),
      'waiting_reviewer_2', count(*) filter (where s.status = 'waiting_reviewer_2'),
      'verified', count(*) filter (where s.status = 'verified'),
      'rejected', count(*) filter (where s.status = 'rejected'),
      'other', count(*) filter (where s.status not in (
        'waiting_reviewer_1', 'waiting_reviewer_2', 'verified', 'rejected'
      ))
    )
    from (
      select distinct on (s1.staging_question_id)
        s1.staging_question_id, s1.status
      from public.ai_solve_time_verification_runs s1
      where s1.staging_question_id in (
        select cr.staging_question_id
        from public.candidate_batch_candidate_results cr
        where cr.batch_id = p_batch_id
          and cr.staging_question_id is not null
      )
      order by s1.staging_question_id, s1.created_at desc
    ) s
  );

  v_originality := (
    select jsonb_build_object(
      'total', count(*) filter (where o.staging_question_id is not null),
      'waiting_reviewer_1', count(*) filter (where o.status = 'waiting_reviewer_1'),
      'waiting_reviewer_2', count(*) filter (where o.status = 'waiting_reviewer_2'),
      'verified', count(*) filter (where o.status = 'verified'),
      'blocked', count(*) filter (where o.status = 'blocked'),
      'rejected', count(*) filter (where o.status = 'rejected'),
      'other', count(*) filter (where o.status not in (
        'waiting_reviewer_1', 'waiting_reviewer_2', 'verified', 'blocked', 'rejected'
      ))
    )
    from (
      select distinct on (o1.staging_question_id)
        o1.staging_question_id, o1.status
      from public.ai_originality_verification_runs o1
      where o1.staging_question_id in (
        select cr.staging_question_id
        from public.candidate_batch_candidate_results cr
        where cr.batch_id = p_batch_id
          and cr.staging_question_id is not null
      )
      order by o1.staging_question_id, o1.created_at desc
    ) o
  );

  v_quality := (
    select jsonb_build_object(
      'total', count(*) filter (where q.staging_question_id is not null),
      'waiting_reviewer_1', count(*) filter (where q.status = 'waiting_reviewer_1'),
      'waiting_reviewer_2', count(*) filter (where q.status = 'waiting_reviewer_2'),
      'verified', count(*) filter (where q.status = 'verified'),
      'rejected', count(*) filter (where q.status = 'rejected'),
      'other', count(*) filter (where q.status not in (
        'waiting_reviewer_1', 'waiting_reviewer_2', 'verified', 'rejected'
      ))
    )
    from (
      select distinct on (q1.staging_question_id)
        q1.staging_question_id, q1.status
      from public.ai_question_quality_runs q1
      where q1.staging_question_id in (
        select cr.staging_question_id
        from public.candidate_batch_candidate_results cr
        where cr.batch_id = p_batch_id
          and cr.staging_question_id is not null
      )
      order by q1.staging_question_id, q1.created_at desc
    ) q
  );

  v_readiness := (
    select jsonb_build_object(
      'total', count(*) filter (where r.staging_question_id is not null),
      'not_ready', count(*) filter (where r.readiness_status = 'not_ready'),
      'ready_for_human_review', count(*) filter (where r.readiness_status = 'ready_for_human_review'),
      'human_review_required', count(*) filter (where r.readiness_status = 'human_review_required'),
      'blocked', count(*) filter (where r.readiness_status = 'blocked'),
      'rejected', count(*) filter (where r.readiness_status = 'rejected'),
      'already_promoted', count(*) filter (where r.readiness_status = 'already_promoted')
    )
    from public.ai_question_readiness_runs r
    where r.staging_question_id in (
      select cr.staging_question_id
      from public.candidate_batch_candidate_results cr
      where cr.batch_id = p_batch_id
        and cr.staging_question_id is not null
    )
  );

  v_final_review := (
    select jsonb_build_object(
      'total', count(*) filter (where f.staging_question_id is not null),
      'approve', count(*) filter (where f.decision = 'approve'),
      'request_changes', count(*) filter (where f.decision = 'request_changes'),
      'reject', count(*) filter (where f.decision = 'reject')
    )
    from public.ai_question_final_reviews f
    where f.staging_question_id in (
      select cr.staging_question_id
      from public.candidate_batch_candidate_results cr
      where cr.batch_id = p_batch_id
        and cr.staging_question_id is not null
    )
  );

  return jsonb_build_object(
    'batch', jsonb_build_object(
      'batch_id', v_batch.id,
      'batch_key', v_batch.batch_key,
      'status', v_batch.status,
      'counts', jsonb_build_object(
        'total_items', v_batch.total_items,
        'valid_items', v_batch.valid_items,
        'invalid_items', v_batch.invalid_items,
        'inserted_items', v_batch.inserted_items,
        'duplicate_items', v_batch.duplicate_items
      ),
      'created_at', v_batch.created_at,
      'updated_at', v_batch.updated_at
    ),
    'phase', jsonb_build_object(
      'candidate_counts', v_candidate_counts
    ),
    'gates', jsonb_build_object(
      'answer_verification', v_answer,
      'curriculum_fit', v_curriculum,
      'solve_time_verification', v_solve,
      'originality_verification', v_originality,
      'question_quality', v_quality,
      'readiness', v_readiness,
      'final_review', v_final_review
    ),
    'provider', jsonb_build_object(
      'has_batch_error_data', v_has_batch_error,
      'candidate_validation_error_count', v_candidate_error_count
    ),
    'retry', jsonb_build_object(
      'supported', false,
      'reason_key', 'gate_retry_not_supported'
    )
  );
end;
$$;


revoke all
on function public.get_candidate_question_batch_operation_status(uuid)
from public, anon;


grant execute
on function public.get_candidate_question_batch_operation_status(uuid)
to authenticated, service_role;


commit;