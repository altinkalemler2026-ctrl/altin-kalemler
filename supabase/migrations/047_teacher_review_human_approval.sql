begin;

-- ============================================================
-- 047 - TEACHER REVIEW HUMAN APPROVAL
--
-- Amaç:
-- - human_review_required kayıtlarını insan kararına bağlamak
-- - admin permission kontrolü yapmak
-- - AI correction proposal'ını yalnızca insan onayıyla staging'e uygulamak
-- - tüm insan kararlarını ayrı audit tablosunda tutmak
-- - AI'nın doğrudan yayın/düzeltme yetkisi olmamasını korumak
-- ============================================================


-- ============================================================
-- 1. HUMAN REVIEW AUDIT
-- ============================================================

create table if not exists public.ai_teacher_human_review_audit (
  id uuid primary key default gen_random_uuid(),

  review_run_id uuid not null
    references public.ai_teacher_review_runs(id)
    on delete cascade,

  staging_question_id uuid not null
    references public.ai_question_staging(id)
    on delete cascade,

  correction_proposal_id uuid
    references public.ai_teacher_correction_proposals(id)
    on delete set null,

  action text not null,

  performed_by uuid not null
    references auth.users(id)
    on delete restrict,

  notes text,

  details jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  constraint ai_teacher_human_review_audit_action_check
    check (
      action in (
        'approved',
        'rejected',
        'needs_revision',
        'correction_applied'
      )
    )
);


create index if not exists
  ai_teacher_human_review_audit_run_idx
on public.ai_teacher_human_review_audit (
  review_run_id,
  created_at
);


create index if not exists
  ai_teacher_human_review_audit_staging_idx
on public.ai_teacher_human_review_audit (
  staging_question_id,
  created_at
);


-- ============================================================
-- 2. ADMIN PERMISSION HELPER
--
-- auth.uid() kullanır.
-- AI worker/service-role bu fonksiyonu insan gibi kullanamaz.
-- ============================================================

create or replace function public.teacher_review_admin_has_permission(
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1

    from public.admin_user_roles aur

    join public.admin_roles ar
      on ar.id = aur.role_id
     and ar.is_active = true

    join public.admin_role_permissions arp
      on arp.role_id = ar.id

    join public.admin_permissions ap
      on ap.id = arp.permission_id

    where aur.user_id = auth.uid()
      and ap.permission_code = p_permission_code
  );
$$;


revoke all
on function public.teacher_review_admin_has_permission(text)
from public;

grant execute
on function public.teacher_review_admin_has_permission(text)
to authenticated;


-- ============================================================
-- 3. HUMAN DECISION FUNCTION
--
-- p_decision:
--   approved
--   rejected
--   needs_revision
--
-- approved:
--   questions.approve gerekir.
--
-- rejected / needs_revision:
--   questions.reject gerekir.
--
-- Eğer approved + correction_proposal_id verilirse:
-- - proposal run'a ait olmalı
-- - recheck_passed olmalı
-- - staging'e daha önce uygulanmamış olmalı
-- - düzeltme insan kimliğiyle staging'e uygulanır
--
-- Bu işlem soruyu questions tablosuna YAYINLAMAZ.
-- ============================================================

create or replace function public.decide_teacher_review(
  p_review_run_id uuid,
  p_decision text,
  p_correction_proposal_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;

  v_run public.ai_teacher_review_runs%rowtype;

  v_proposal public.ai_teacher_correction_proposals%rowtype;

  v_required_permission text;

  v_correction_applied boolean := false;

  v_now timestamptz := now();
begin

  -- ----------------------------------------------------------
  -- Authenticated human identity required
  -- ----------------------------------------------------------

  v_actor := auth.uid();

  if v_actor is null then
    raise exception
      'Human teacher review decision requires an authenticated user.';
  end if;


  -- ----------------------------------------------------------
  -- Validate decision
  -- ----------------------------------------------------------

  if p_decision not in (
    'approved',
    'rejected',
    'needs_revision'
  ) then
    raise exception
      'Invalid human decision: %',
      p_decision;
  end if;


  -- ----------------------------------------------------------
  -- Permission mapping
  -- ----------------------------------------------------------

  if p_decision = 'approved' then
    v_required_permission :=
      'questions.approve';
  else
    v_required_permission :=
      'questions.reject';
  end if;


  if not public.teacher_review_admin_has_permission(
    v_required_permission
  ) then
    raise exception
      'Permission denied. Required permission: %',
      v_required_permission;
  end if;


  -- ----------------------------------------------------------
  -- Lock review run
  -- ----------------------------------------------------------

  select *
  into v_run
  from public.ai_teacher_review_runs
  where id = p_review_run_id
  for update;


  if not found then
    raise exception
      'Teacher review run not found: %',
      p_review_run_id;
  end if;


  -- Human decision is only accepted when the workflow
  -- is explicitly waiting for human review.
  if v_run.status <> 'human_review_required'
     or v_run.current_stage <> 'human_review'
  then
    raise exception
      'Teacher review run is not waiting for human review. status=%, stage=%',
      v_run.status,
      v_run.current_stage;
  end if;


  -- ----------------------------------------------------------
  -- Optional correction proposal
  -- ----------------------------------------------------------

  if p_correction_proposal_id is not null then

    select *
    into v_proposal
    from public.ai_teacher_correction_proposals
    where id = p_correction_proposal_id
    for update;


    if not found then
      raise exception
        'Correction proposal not found: %',
        p_correction_proposal_id;
    end if;


    if v_proposal.review_run_id <> p_review_run_id then
      raise exception
        'Correction proposal does not belong to this review run.';
    end if;


    if v_proposal.staging_question_id
       <> v_run.staging_question_id
    then
      raise exception
        'Correction proposal staging question does not match review run.';
    end if;

  end if;


  -- ==========================================================
  -- APPROVED
  -- ==========================================================

  if p_decision = 'approved' then

    -- --------------------------------------------------------
    -- If a correction exists, human approval applies exactly
    -- that verified proposal to staging.
    -- --------------------------------------------------------

    if p_correction_proposal_id is not null then

      if v_proposal.status <> 'recheck_passed' then
        raise exception
          'Correction proposal must be recheck_passed before human approval. Current status: %',
          v_proposal.status;
      end if;


      if v_proposal.applied_to_staging = true then
        raise exception
          'Correction proposal has already been applied to staging.';
      end if;


      update public.ai_question_staging
      set
        question_text =
          coalesce(
            v_proposal.proposed_question_text,
            question_text
          ),

        option_a =
          coalesce(
            v_proposal.proposed_option_a,
            option_a
          ),

        option_b =
          coalesce(
            v_proposal.proposed_option_b,
            option_b
          ),

        option_c =
          coalesce(
            v_proposal.proposed_option_c,
            option_c
          ),

        option_d =
          coalesce(
            v_proposal.proposed_option_d,
            option_d
          ),

        option_e =
          coalesce(
            v_proposal.proposed_option_e,
            option_e
          ),

        proposed_correct_answer =
          coalesce(
            v_proposal.proposed_correct_answer,
            proposed_correct_answer
          )

      where id =
        v_run.staging_question_id;


      if not found then
        raise exception
          'Staging question not found while applying correction.';
      end if;


      update public.ai_teacher_correction_proposals
      set
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

      where id =
        v_proposal.id;


      v_correction_applied :=
        true;


      insert into public.ai_teacher_human_review_audit (
        review_run_id,
        staging_question_id,
        correction_proposal_id,
        action,
        performed_by,
        notes,
        details
      )
      values (
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

    end if;


    update public.ai_teacher_review_runs
    set
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

    where id =
      v_run.id;


    insert into public.ai_teacher_human_review_audit (
      review_run_id,
      staging_question_id,
      correction_proposal_id,
      action,
      performed_by,
      notes,
      details
    )
    values (
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

  elsif p_decision = 'rejected' then

    if p_correction_proposal_id is not null then

      update public.ai_teacher_correction_proposals
      set
        status =
          'human_rejected',

        human_review_required =
          false

      where id =
        v_proposal.id;

    end if;


    update public.ai_teacher_review_runs
    set
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

    where id =
      v_run.id;


    insert into public.ai_teacher_human_review_audit (
      review_run_id,
      staging_question_id,
      correction_proposal_id,
      action,
      performed_by,
      notes,
      details
    )
    values (
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

  elsif p_decision = 'needs_revision' then

    if p_correction_proposal_id is not null then

      update public.ai_teacher_correction_proposals
      set
        status =
          'superseded',

        human_review_required =
          false

      where id =
        v_proposal.id;

    end if;


    update public.ai_teacher_review_runs
    set
      status =
        'waiting_correction',

      current_stage =
        'correction',

      correction_required =
        true,

      correction_completed =
        false,

      final_checker_passed =
        null,

      human_review_required =
        false,

      human_decision =
        'needs_revision',

      human_reviewed_by =
        v_actor,

      human_reviewed_at =
        v_now,

      ai_review_completed_at =
        null

    where id =
      v_run.id;


    insert into public.ai_teacher_human_review_audit (
      review_run_id,
      staging_question_id,
      correction_proposal_id,
      action,
      performed_by,
      notes,
      details
    )
    values (
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

  end if;


  -- ----------------------------------------------------------
  -- Return compact result
  -- ----------------------------------------------------------

  return jsonb_build_object(
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

end;
$$;


revoke all
on function public.decide_teacher_review(
  uuid,
  text,
  uuid,
  text
)
from public;


grant execute
on function public.decide_teacher_review(
  uuid,
  text,
  uuid,
  text
)
to authenticated;


-- ============================================================
-- 4. AUDIT RLS
-- ============================================================

alter table public.ai_teacher_human_review_audit
enable row level security;


drop policy if exists
  "Admins can view teacher review audit"
on public.ai_teacher_human_review_audit;


create policy
  "Admins can view teacher review audit"
on public.ai_teacher_human_review_audit
for select
to authenticated
using (
  public.teacher_review_admin_has_permission(
    'questions.view'
  )
);


-- Direct client inserts/updates/deletes are intentionally absent.
-- Audit writes happen through the SECURITY DEFINER decision function.


-- ============================================================
-- 5. SERVICE ROLE READ ACCESS
-- ============================================================

grant select
on public.ai_teacher_human_review_audit
to service_role;


-- ============================================================
-- IMPORTANT SAFETY RULE
--
-- This migration:
-- - does NOT promote a staging question to public.questions
-- - does NOT publish content
-- - does NOT allow AI to approve its own correction
-- - requires auth.uid() + admin permission
-- ============================================================

commit;