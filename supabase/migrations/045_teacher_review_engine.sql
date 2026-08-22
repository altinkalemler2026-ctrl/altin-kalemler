-- ============================================================
-- 045_teacher_review_engine.sql
--
-- Altin Kalemler
-- Subject-aware AI Teacher Review Engine
--
-- Goals:
-- - Subject specialist AI review
-- - Error hunting
-- - Correction proposals
-- - Final AI cross-check
-- - Human escalation for risky/uncertain questions
-- - NEVER allow AI review alone to publish to production
-- ============================================================


-- ============================================================
-- 0. CANONICAL SUBJECT SEED
--
-- ai_teacher_review_profiles.subject_id (ve sonrasinda 046/049) sabit
-- UUID'lerle public.subjects'e FK'li; repo zincirinde subjects seed'i
-- yoktu (satirlar production'a elle eklenmisti). Temiz db reset'te FK
-- ihlalini onlemek icin kanonik dersler burada idempotent seed
-- ediliyor (degerler production'dan dogrulandi).
-- ============================================================

insert into public.subjects (id, name, slug, sort_order, is_active)
values
  ('430903f3-527e-4e12-b7e8-ac0afdb784aa', 'Matematik', 'matematik', 1, true),
  ('25fb85d1-4810-4661-9053-6c746486556a', 'Türkçe', 'turkce', 2, true),
  ('33f52f3a-8032-449e-85db-0bffddec8d06', 'Edebiyat', 'edebiyat', 3, true),
  ('f4f39552-4d92-4d18-bfd5-c51abe00585d', 'Geometri', 'geometri', 4, true),
  ('4245101d-6269-40d0-a663-2016ab9d1ee4', 'Tarih', 'tarih', 5, true),
  ('57a959a8-43e7-4f0e-8b54-a7299386fdb3', 'Fizik', 'fizik', 6, true),
  ('6dbbbd2f-14d5-47aa-aef0-609a5e339b12', 'Kimya', 'kimya', 7, true),
  ('71191e01-220a-4682-9351-3d62631308d2', 'Biyoloji', 'biyoloji', 8, true),
  ('cae032d4-54c0-41d2-b420-17a88fd3770a', 'Coğrafya', 'cografya', 9, true),
  ('c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb', 'Felsefe', 'felsefe', 10, true)
on conflict do nothing;


-- ============================================================
-- 1. TEACHER REVIEW PROFILES
-- ============================================================

create table if not exists public.ai_teacher_review_profiles (
  id uuid primary key default gen_random_uuid(),

  profile_code text not null unique,

  name text not null,

  description text,

  subject_id uuid not null
    references public.subjects(id)
    on delete restrict,

  reviewer_role text not null,

  profile_version text not null default 'v1',

  prompt_version text not null default 'v1',

  minimum_confidence numeric not null default 0.90,

  automatic_low_risk_threshold numeric not null default 0.95,

  requires_answer_verification boolean not null default true,

  requires_solution_verification boolean not null default true,

  requires_curriculum_verification boolean not null default true,

  requires_language_verification boolean not null default true,

  requires_grade_verification boolean not null default true,

  requires_option_verification boolean not null default true,

  requires_solve_time_verification boolean not null default true,

  requires_originality_verification boolean not null default true,

  correction_allowed boolean not null default false,

  direct_publication_allowed boolean not null default false,

  rules jsonb not null default '{}'::jsonb,

  metadata jsonb not null default '{}'::jsonb,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint ai_teacher_review_profiles_reviewer_role_check
    check (
      reviewer_role in (
        'subject_teacher',
        'error_hunter',
        'correction',
        'final_checker'
      )
    ),

  constraint ai_teacher_review_profiles_minimum_confidence_check
    check (
      minimum_confidence >= 0
      and minimum_confidence <= 1
    ),

  constraint ai_teacher_review_profiles_low_risk_threshold_check
    check (
      automatic_low_risk_threshold >= 0
      and automatic_low_risk_threshold <= 1
    ),

  constraint ai_teacher_review_profiles_no_direct_publication_check
    check (
      direct_publication_allowed = false
    )
);


create index if not exists
  ai_teacher_review_profiles_subject_idx
on public.ai_teacher_review_profiles (
  subject_id,
  reviewer_role,
  is_active
);


-- ============================================================
-- 2. TEACHER REVIEW RUNS
--
-- One complete teacher-review workflow for one staging question.
-- ============================================================

create table if not exists public.ai_teacher_review_runs (
  id uuid primary key default gen_random_uuid(),

  staging_question_id uuid not null
    references public.ai_question_staging(id)
    on delete cascade,

  subject_id uuid not null
    references public.subjects(id)
    on delete restrict,

  status text not null default 'waiting_subject_teacher',

  current_stage text not null default 'subject_teacher',

  overall_confidence numeric,

  overall_risk_level text not null default 'unknown',

  subject_teacher_passed boolean,

  error_hunter_passed boolean,

  correction_required boolean not null default false,

  correction_completed boolean not null default false,

  final_checker_passed boolean,

  reviewer_disagreement_detected boolean not null default false,

  human_review_required boolean not null default true,

  human_review_reason text,

  human_decision text,

  human_reviewed_by uuid,

  human_reviewed_at timestamptz,

  ai_review_completed_at timestamptz,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint ai_teacher_review_runs_status_check
    check (
      status in (
        'waiting_subject_teacher',
        'waiting_error_hunter',
        'waiting_correction',
        'waiting_recheck',
        'waiting_final_checker',
        'ai_review_passed',
        'human_review_required',
        'human_approved',
        'human_rejected',
        'blocked',
        'failed'
      )
    ),

  constraint ai_teacher_review_runs_current_stage_check
    check (
      current_stage in (
        'subject_teacher',
        'error_hunter',
        'correction',
        'recheck',
        'final_checker',
        'human_review',
        'complete'
      )
    ),

  constraint ai_teacher_review_runs_confidence_check
    check (
      overall_confidence is null
      or (
        overall_confidence >= 0
        and overall_confidence <= 1
      )
    ),

  constraint ai_teacher_review_runs_risk_level_check
    check (
      overall_risk_level in (
        'unknown',
        'low',
        'medium',
        'high',
        'critical'
      )
    ),

  constraint ai_teacher_review_runs_human_decision_check
    check (
      human_decision is null
      or human_decision in (
        'approved',
        'rejected',
        'needs_revision'
      )
    ),

  constraint ai_teacher_review_runs_human_approval_fields_check
    check (
      human_decision is null
      or (
        human_reviewed_by is not null
        and human_reviewed_at is not null
      )
    )
);


create index if not exists
  ai_teacher_review_runs_staging_idx
on public.ai_teacher_review_runs (
  staging_question_id,
  created_at desc
);


create index if not exists
  ai_teacher_review_runs_queue_idx
on public.ai_teacher_review_runs (
  status,
  current_stage,
  overall_risk_level
);


-- ============================================================
-- 3. INDIVIDUAL AI TEACHER REVIEWS
-- ============================================================

create table if not exists public.ai_teacher_reviews (
  id uuid primary key default gen_random_uuid(),

  review_run_id uuid not null
    references public.ai_teacher_review_runs(id)
    on delete cascade,

  staging_question_id uuid not null
    references public.ai_question_staging(id)
    on delete cascade,

  profile_id uuid not null
    references public.ai_teacher_review_profiles(id)
    on delete restrict,

  reviewer_role text not null,

  reviewer_number smallint not null default 1,

  review_iteration smallint not null default 1,

  verdict text not null,

  risk_level text not null default 'unknown',

  confidence_score numeric not null,

  answer_is_correct boolean,

  solution_is_correct boolean,

  single_correct_answer boolean,

  question_is_complete boolean,

  question_is_unambiguous boolean,

  curriculum_fit boolean,

  grade_fit boolean,

  language_fit boolean,

  terminology_fit boolean,

  options_are_valid boolean,

  distractors_are_valid boolean,

  solve_time_is_reasonable boolean,

  factual_accuracy boolean,

  calculation_accuracy boolean,

  unit_consistency boolean,

  correction_required boolean not null default false,

  detected_errors jsonb not null default '[]'::jsonb,

  warnings jsonb not null default '[]'::jsonb,

  verification_details jsonb not null default '{}'::jsonb,

  provider_name text,

  model_name text,

  prompt_version text,

  review_summary text,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  constraint ai_teacher_reviews_reviewer_role_check
    check (
      reviewer_role in (
        'subject_teacher',
        'error_hunter',
        'correction',
        'final_checker'
      )
    ),

  constraint ai_teacher_reviews_reviewer_number_check
    check (
      reviewer_number >= 1
      and reviewer_number <= 10
    ),

  constraint ai_teacher_reviews_iteration_check
    check (
      review_iteration >= 1
      and review_iteration <= 20
    ),

  constraint ai_teacher_reviews_verdict_check
    check (
      verdict in (
        'pass',
        'pass_with_warning',
        'needs_correction',
        'human_review_required',
        'reject'
      )
    ),

  constraint ai_teacher_reviews_risk_level_check
    check (
      risk_level in (
        'unknown',
        'low',
        'medium',
        'high',
        'critical'
      )
    ),

  constraint ai_teacher_reviews_confidence_check
    check (
      confidence_score >= 0
      and confidence_score <= 1
    )
);


create index if not exists
  ai_teacher_reviews_run_idx
on public.ai_teacher_reviews (
  review_run_id,
  reviewer_role,
  review_iteration
);


create index if not exists
  ai_teacher_reviews_staging_idx
on public.ai_teacher_reviews (
  staging_question_id,
  created_at desc
);


-- ============================================================
-- 4. DETECTED ISSUE REGISTER
--
-- Structured issue storage for reporting/admin filtering.
-- ============================================================

create table if not exists public.ai_teacher_review_issues (
  id uuid primary key default gen_random_uuid(),

  review_id uuid not null
    references public.ai_teacher_reviews(id)
    on delete cascade,

  review_run_id uuid not null
    references public.ai_teacher_review_runs(id)
    on delete cascade,

  staging_question_id uuid not null
    references public.ai_question_staging(id)
    on delete cascade,

  issue_code text not null,

  issue_category text not null,

  severity text not null,

  field_name text,

  description text not null,

  evidence jsonb not null default '{}'::jsonb,

  correction_recommended boolean not null default false,

  blocks_publication boolean not null default false,

  created_at timestamptz not null default now(),

  constraint ai_teacher_review_issues_category_check
    check (
      issue_category in (
        'answer',
        'solution',
        'calculation',
        'factual',
        'curriculum',
        'grade_level',
        'language',
        'terminology',
        'ambiguity',
        'question_structure',
        'options',
        'distractors',
        'solve_time',
        'visual',
        'unit',
        'originality',
        'copyright',
        'other'
      )
    ),

  constraint ai_teacher_review_issues_severity_check
    check (
      severity in (
        'info',
        'low',
        'medium',
        'high',
        'critical'
      )
    )
);


create index if not exists
  ai_teacher_review_issues_run_idx
on public.ai_teacher_review_issues (
  review_run_id,
  severity
);


create index if not exists
  ai_teacher_review_issues_staging_idx
on public.ai_teacher_review_issues (
  staging_question_id,
  issue_category
);


-- ============================================================
-- 5. CORRECTION PROPOSALS
--
-- IMPORTANT:
-- This table NEVER overwrites ai_question_staging automatically.
-- Original question remains intact.
-- ============================================================

create table if not exists public.ai_teacher_correction_proposals (
  id uuid primary key default gen_random_uuid(),

  review_run_id uuid not null
    references public.ai_teacher_review_runs(id)
    on delete cascade,

  staging_question_id uuid not null
    references public.ai_question_staging(id)
    on delete cascade,

  source_review_id uuid
    references public.ai_teacher_reviews(id)
    on delete set null,

  status text not null default 'proposed',

  proposed_question_text text,

  proposed_option_a text,

  proposed_option_b text,

  proposed_option_c text,

  proposed_option_d text,

  proposed_option_e text,

  proposed_correct_answer text,

  proposed_solution jsonb not null default '{}'::jsonb,

  change_summary text,

  change_reasons jsonb not null default '[]'::jsonb,

  confidence_score numeric not null,

  requires_recheck boolean not null default true,

  human_review_required boolean not null default true,

  applied_to_staging boolean not null default false,

  applied_by uuid,

  applied_at timestamptz,

  provider_name text,

  model_name text,

  prompt_version text,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  constraint ai_teacher_correction_status_check
    check (
      status in (
        'proposed',
        'recheck_required',
        'recheck_passed',
        'recheck_failed',
        'human_approved',
        'human_rejected',
        'superseded'
      )
    ),

  constraint ai_teacher_correction_answer_check
    check (
      proposed_correct_answer is null
      or proposed_correct_answer in (
        'A',
        'B',
        'C',
        'D',
        'E'
      )
    ),

  constraint ai_teacher_correction_confidence_check
    check (
      confidence_score >= 0
      and confidence_score <= 1
    ),

  constraint ai_teacher_correction_apply_fields_check
    check (
      applied_to_staging = false
      or (
        applied_by is not null
        and applied_at is not null
      )
    )
);


create index if not exists
  ai_teacher_correction_proposals_run_idx
on public.ai_teacher_correction_proposals (
  review_run_id,
  status,
  created_at desc
);


-- ============================================================
-- 6. SAFETY TRIGGER
--
-- AI cannot mark a correction as applied by itself without
-- an authenticated human/admin identity being recorded.
--
-- Also prevents profiles from ever enabling direct publication.
-- ============================================================

create or replace function private.enforce_ai_teacher_review_safety()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin

  if tg_table_name = 'ai_teacher_review_profiles' then

    if new.direct_publication_allowed then
      raise exception
        'AI teacher profiles cannot directly publish questions.';
    end if;

    return new;

  end if;


  if tg_table_name = 'ai_teacher_correction_proposals' then

    if new.applied_to_staging then

      if new.applied_by is null
         or new.applied_at is null then

        raise exception
          'Applying an AI correction requires recorded human approval.';

      end if;

    end if;

    return new;

  end if;


  return new;

end;
$$;


drop trigger if exists
  trg_ai_teacher_review_profile_safety
on public.ai_teacher_review_profiles;

create trigger
  trg_ai_teacher_review_profile_safety
before insert or update
on public.ai_teacher_review_profiles
for each row
execute function private.enforce_ai_teacher_review_safety();


drop trigger if exists
  trg_ai_teacher_correction_safety
on public.ai_teacher_correction_proposals;

create trigger
  trg_ai_teacher_correction_safety
before insert or update
on public.ai_teacher_correction_proposals
for each row
execute function private.enforce_ai_teacher_review_safety();


-- ============================================================
-- 7. UPDATED_AT TRIGGERS
-- ============================================================

create or replace function private.set_ai_teacher_review_updated_at()
returns trigger
language plpgsql
set search_path = public, private
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


drop trigger if exists
  trg_ai_teacher_review_profiles_updated_at
on public.ai_teacher_review_profiles;

create trigger
  trg_ai_teacher_review_profiles_updated_at
before update
on public.ai_teacher_review_profiles
for each row
execute function private.set_ai_teacher_review_updated_at();


drop trigger if exists
  trg_ai_teacher_review_runs_updated_at
on public.ai_teacher_review_runs;

create trigger
  trg_ai_teacher_review_runs_updated_at
before update
on public.ai_teacher_review_runs
for each row
execute function private.set_ai_teacher_review_updated_at();


-- ============================================================
-- 8. ROW LEVEL SECURITY
-- ============================================================

alter table public.ai_teacher_review_profiles
  enable row level security;

alter table public.ai_teacher_review_runs
  enable row level security;

alter table public.ai_teacher_reviews
  enable row level security;

alter table public.ai_teacher_review_issues
  enable row level security;

alter table public.ai_teacher_correction_proposals
  enable row level security;


-- Profiles

drop policy if exists
  "question admins read teacher profiles"
on public.ai_teacher_review_profiles;

create policy
  "question admins read teacher profiles"
on public.ai_teacher_review_profiles
for select
to authenticated
using (
  private.current_user_has_admin_permission(
    'questions.view'
  )
);


drop policy if exists
  "question admins manage teacher profiles"
on public.ai_teacher_review_profiles;

create policy
  "question admins manage teacher profiles"
on public.ai_teacher_review_profiles
for all
to authenticated
using (
  private.current_user_has_admin_permission(
    'questions.edit'
  )
  or private.current_user_has_admin_permission(
    'questions.approve'
  )
)
with check (
  private.current_user_has_admin_permission(
    'questions.edit'
  )
  or private.current_user_has_admin_permission(
    'questions.approve'
  )
);


-- Review runs

drop policy if exists
  "question admins read teacher review runs"
on public.ai_teacher_review_runs;

create policy
  "question admins read teacher review runs"
on public.ai_teacher_review_runs
for select
to authenticated
using (
  private.current_user_has_admin_permission(
    'questions.view'
  )
);


drop policy if exists
  "question admins manage teacher review runs"
on public.ai_teacher_review_runs;

create policy
  "question admins manage teacher review runs"
on public.ai_teacher_review_runs
for all
to authenticated
using (
  private.current_user_has_admin_permission(
    'questions.edit'
  )
  or private.current_user_has_admin_permission(
    'questions.approve'
  )
  or private.current_user_has_admin_permission(
    'questions.reject'
  )
)
with check (
  private.current_user_has_admin_permission(
    'questions.edit'
  )
  or private.current_user_has_admin_permission(
    'questions.approve'
  )
  or private.current_user_has_admin_permission(
    'questions.reject'
  )
);


-- Individual reviews

drop policy if exists
  "question admins read teacher reviews"
on public.ai_teacher_reviews;

create policy
  "question admins read teacher reviews"
on public.ai_teacher_reviews
for select
to authenticated
using (
  private.current_user_has_admin_permission(
    'questions.view'
  )
);


drop policy if exists
  "question admins manage teacher reviews"
on public.ai_teacher_reviews;

create policy
  "question admins manage teacher reviews"
on public.ai_teacher_reviews
for all
to authenticated
using (
  private.current_user_has_admin_permission(
    'questions.edit'
  )
  or private.current_user_has_admin_permission(
    'questions.approve'
  )
  or private.current_user_has_admin_permission(
    'questions.reject'
  )
)
with check (
  private.current_user_has_admin_permission(
    'questions.edit'
  )
  or private.current_user_has_admin_permission(
    'questions.approve'
  )
  or private.current_user_has_admin_permission(
    'questions.reject'
  )
);


-- Issues

drop policy if exists
  "question admins read teacher issues"
on public.ai_teacher_review_issues;

create policy
  "question admins read teacher issues"
on public.ai_teacher_review_issues
for select
to authenticated
using (
  private.current_user_has_admin_permission(
    'questions.view'
  )
);


drop policy if exists
  "question admins manage teacher issues"
on public.ai_teacher_review_issues;

create policy
  "question admins manage teacher issues"
on public.ai_teacher_review_issues
for all
to authenticated
using (
  private.current_user_has_admin_permission(
    'questions.edit'
  )
  or private.current_user_has_admin_permission(
    'questions.approve'
  )
  or private.current_user_has_admin_permission(
    'questions.reject'
  )
)
with check (
  private.current_user_has_admin_permission(
    'questions.edit'
  )
  or private.current_user_has_admin_permission(
    'questions.approve'
  )
  or private.current_user_has_admin_permission(
    'questions.reject'
  )
);


-- Corrections

drop policy if exists
  "question admins read teacher corrections"
on public.ai_teacher_correction_proposals;

create policy
  "question admins read teacher corrections"
on public.ai_teacher_correction_proposals
for select
to authenticated
using (
  private.current_user_has_admin_permission(
    'questions.view'
  )
);


drop policy if exists
  "question admins manage teacher corrections"
on public.ai_teacher_correction_proposals;

create policy
  "question admins manage teacher corrections"
on public.ai_teacher_correction_proposals
for all
to authenticated
using (
  private.current_user_has_admin_permission(
    'questions.edit'
  )
  or private.current_user_has_admin_permission(
    'questions.approve'
  )
  or private.current_user_has_admin_permission(
    'questions.reject'
  )
)
with check (
  private.current_user_has_admin_permission(
    'questions.edit'
  )
  or private.current_user_has_admin_permission(
    'questions.approve'
  )
  or private.current_user_has_admin_permission(
    'questions.reject'
  )
);


-- ============================================================
-- 9. PRIVILEGES
-- ============================================================

revoke all
on public.ai_teacher_review_profiles
from anon;

revoke all
on public.ai_teacher_review_runs
from anon;

revoke all
on public.ai_teacher_reviews
from anon;

revoke all
on public.ai_teacher_review_issues
from anon;

revoke all
on public.ai_teacher_correction_proposals
from anon;


grant select, insert, update, delete
on public.ai_teacher_review_profiles
to authenticated;

grant select, insert, update, delete
on public.ai_teacher_review_runs
to authenticated;

grant select, insert, update, delete
on public.ai_teacher_reviews
to authenticated;

grant select, insert, update, delete
on public.ai_teacher_review_issues
to authenticated;

grant select, insert, update, delete
on public.ai_teacher_correction_proposals
to authenticated;


grant all
on public.ai_teacher_review_profiles
to service_role;

grant all
on public.ai_teacher_review_runs
to service_role;

grant all
on public.ai_teacher_reviews
to service_role;

grant all
on public.ai_teacher_review_issues
to service_role;

grant all
on public.ai_teacher_correction_proposals
to service_role;


-- ============================================================
-- 10. MATHEMATICS TEACHER AI PROFILES
--
-- Mathematics subject:
-- 430903f3-527e-4e12-b7e8-ac0afdb784aa
--
-- Four separate reviewer personalities.
-- ============================================================

insert into public.ai_teacher_review_profiles (
  profile_code,
  name,
  description,
  subject_id,
  reviewer_role,
  profile_version,
  prompt_version,
  minimum_confidence,
  automatic_low_risk_threshold,
  correction_allowed,
  direct_publication_allowed,
  rules,
  metadata
)
values

(
  'MATH-SUBJECT-TEACHER-V1',
  'Matematik Öğretmen AI',
  'Matematik sorularını doğruluk, çözüm, sınıf seviyesi, müfredat ve seçenek kalitesi açısından inceler.',
  '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
  'subject_teacher',
  'v1',
  'math-teacher-v1',
  0.92,
  0.97,
  false,
  false,
  jsonb_build_object(
    'verify_correct_answer', true,
    'solve_question_independently', true,
    'verify_solution_path', true,
    'verify_grade_level', true,
    'verify_curriculum_fit', true,
    'verify_single_correct_answer', true,
    'verify_distractors', true,
    'verify_mathematical_notation', true,
    'verify_age_appropriate_language', true,
    'do_not_trust_existing_answer_key', true
  ),
  jsonb_build_object(
    'subject', 'Matematik',
    'teacher_ai', true
  )
),

(
  'MATH-ERROR-HUNTER-V1',
  'Matematik Hata Avcısı AI',
  'Matematik sorularında gizli hata, çelişki, eksik bilgi, ikinci doğru seçenek ve hesaplama hatası arar.',
  '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
  'error_hunter',
  'v1',
  'math-error-hunter-v1',
  0.92,
  0.97,
  false,
  false,
  jsonb_build_object(
    'actively_search_for_counterexamples', true,
    'check_all_options', true,
    'detect_multiple_correct_answers', true,
    'detect_no_correct_answer', true,
    'detect_missing_information', true,
    'detect_ambiguous_wording', true,
    'recalculate_all_numeric_results', true,
    'verify_units', true,
    'verify_constraints', true,
    'assume_previous_ai_may_be_wrong', true
  ),
  jsonb_build_object(
    'subject', 'Matematik',
    'error_hunter_ai', true
  )
),

(
  'MATH-CORRECTION-V1',
  'Matematik Düzeltici AI',
  'Tespit edilen hatalar için orijinal soruyu bozmadan ayrı bir düzeltilmiş sürüm önerir.',
  '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
  'correction',
  'v1',
  'math-correction-v1',
  0.92,
  0.97,
  true,
  false,
  jsonb_build_object(
    'preserve_learning_objective', true,
    'fix_only_verified_errors', true,
    'produce_complete_corrected_question', true,
    'produce_complete_corrected_options', true,
    'produce_verified_answer', true,
    'produce_verified_solution', true,
    'avoid_unnecessary_rewrite', true,
    'require_recheck_after_correction', true
  ),
  jsonb_build_object(
    'subject', 'Matematik',
    'correction_ai', true
  )
),

(
  'MATH-FINAL-CHECKER-V1',
  'Matematik Son Denetçi AI',
  'Önceki AI kararlarını körü körüne kabul etmeden soruya son bağımsız matematik kontrolünü uygular.',
  '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
  'final_checker',
  'v1',
  'math-final-checker-v1',
  0.95,
  0.98,
  false,
  false,
  jsonb_build_object(
    'independent_full_solution_required', true,
    'compare_previous_reviews', true,
    'detect_reviewer_disagreement', true,
    'verify_correct_answer', true,
    'verify_solution', true,
    'verify_options', true,
    'verify_curriculum', true,
    'verify_grade_level', true,
    'escalate_on_uncertainty', true
  ),
  jsonb_build_object(
    'subject', 'Matematik',
    'final_checker_ai', true
  )
)

on conflict (profile_code)
do update set

  name = excluded.name,
  description = excluded.description,
  subject_id = excluded.subject_id,
  reviewer_role = excluded.reviewer_role,
  profile_version = excluded.profile_version,
  prompt_version = excluded.prompt_version,
  minimum_confidence = excluded.minimum_confidence,
  automatic_low_risk_threshold =
    excluded.automatic_low_risk_threshold,
  correction_allowed = excluded.correction_allowed,
  direct_publication_allowed =
    excluded.direct_publication_allowed,
  rules = excluded.rules,
  metadata = excluded.metadata,
  is_active = true,
  updated_at = now();


-- ============================================================
-- 11. ADMIN OVERVIEW VIEW
-- ============================================================

create or replace view public.ai_teacher_review_overview
with (security_invoker = true)
as

select
  r.id as review_run_id,

  r.staging_question_id,

  r.subject_id,

  r.status,

  r.current_stage,

  r.overall_confidence,

  r.overall_risk_level,

  r.subject_teacher_passed,

  r.error_hunter_passed,

  r.correction_required,

  r.correction_completed,

  r.final_checker_passed,

  r.reviewer_disagreement_detected,

  r.human_review_required,

  r.human_review_reason,

  r.human_decision,

  count(distinct rev.id) as review_count,

  count(distinct issue.id) as issue_count,

  count(
    distinct issue.id
  ) filter (
    where issue.severity in (
      'high',
      'critical'
    )
  ) as serious_issue_count,

  count(
    distinct correction.id
  ) as correction_proposal_count,

  r.created_at,

  r.updated_at

from public.ai_teacher_review_runs r

left join public.ai_teacher_reviews rev
  on rev.review_run_id = r.id

left join public.ai_teacher_review_issues issue
  on issue.review_run_id = r.id

left join public.ai_teacher_correction_proposals correction
  on correction.review_run_id = r.id

group by r.id;


revoke all
on public.ai_teacher_review_overview
from anon;

grant select
on public.ai_teacher_review_overview
to authenticated;

grant select
on public.ai_teacher_review_overview
to service_role;


-- ============================================================
-- END 045
-- ============================================================