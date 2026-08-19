begin;

with subject_profiles as (
  select *
  from (
    values
      (
        '25fb85d1-4810-4661-9053-6c746486556a'::uuid,
        'TURKISH',
        'Türkçe'
      ),
      (
        '33f52f3a-8032-449e-85db-0bffddec8d06'::uuid,
        'LITERATURE',
        'Edebiyat'
      ),
      (
        'f4f39552-4d92-4d18-bfd5-c51abe00585d'::uuid,
        'GEOMETRY',
        'Geometri'
      ),
      (
        '4245101d-6269-40d0-a663-2016ab9d1ee4'::uuid,
        'HISTORY',
        'Tarih'
      ),
      (
        '57a959a8-43e7-4f0e-8b54-a7299386fdb3'::uuid,
        'PHYSICS',
        'Fizik'
      ),
      (
        '6dbbbd2f-14d5-47aa-aef0-609a5e339b12'::uuid,
        'CHEMISTRY',
        'Kimya'
      ),
      (
        '71191e01-220a-4682-9351-3d62631308d2'::uuid,
        'BIOLOGY',
        'Biyoloji'
      ),
      (
        'cae032d4-54c0-41d2-b420-17a88fd3770a'::uuid,
        'GEOGRAPHY',
        'Coğrafya'
      ),
      (
        'c5750b82-86c9-4f84-b8f8-2a6f58a7a2bb'::uuid,
        'PHILOSOPHY',
        'Felsefe'
      )
  ) as s(
    subject_id,
    code_prefix,
    subject_name
  )
),

review_roles as (
  select *
  from (
    values
      (
        'SUBJECT-TEACHER',
        'subject_teacher',
        'Ders Öğretmeni AI',
        0.92::numeric,
        0.97::numeric,
        false
      ),
      (
        'ERROR-HUNTER',
        'error_hunter',
        'Hata Avcısı AI',
        0.92::numeric,
        0.97::numeric,
        false
      ),
      (
        'CORRECTION',
        'correction',
        'Düzeltici AI',
        0.92::numeric,
        0.97::numeric,
        true
      ),
      (
        'FINAL-CHECKER',
        'final_checker',
        'Son Denetçi AI',
        0.95::numeric,
        0.98::numeric,
        false
      )
  ) as r(
    role_code,
    reviewer_role,
    role_name,
    minimum_confidence,
    automatic_low_risk_threshold,
    correction_allowed
  )
)

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
  requires_answer_verification,
  requires_solution_verification,
  requires_curriculum_verification,
  requires_language_verification,
  requires_grade_verification,
  requires_option_verification,
  requires_solve_time_verification,
  requires_originality_verification,
  correction_allowed,
  direct_publication_allowed,
  rules,
  metadata,
  is_active
)
select
  sp.code_prefix
    || '-'
    || rr.role_code
    || '-V1',

  sp.subject_name
    || ' '
    || rr.role_name,

  case rr.reviewer_role
    when 'subject_teacher'
      then sp.subject_name
        || ' sorularında alan doğruluğu, eğitimsel uygunluk ve temel kalite denetimi yapar.'

    when 'error_hunter'
      then sp.subject_name
        || ' sorularında bağımsız hata, tutarsızlık ve yayın engelleyici sorun taraması yapar.'

    when 'correction'
      then sp.subject_name
        || ' sorularında tespit edilen hatalar için düzeltme önerisi üretir; staging kaydını otomatik değiştirmez.'

    when 'final_checker'
      then sp.subject_name
        || ' sorularında önceki AI değerlendirmelerinden bağımsız son doğrulama yapar.'
  end,

  sp.subject_id,

  rr.reviewer_role,

  'v1',

  'teacher-review-v1',

  rr.minimum_confidence,

  rr.automatic_low_risk_threshold,

  true,

  true,

  true,

  true,

  true,

  true,

  true,

  true,

  rr.correction_allowed,

  false,

  jsonb_build_object(
    'independent_review_required',
      true,

    'answer_key_must_not_be_trusted',
      true,

    'single_correct_answer_required',
      true,

    'question_must_be_complete',
      true,

    'ambiguity_check_required',
      true,

    'age_and_grade_fit_required',
      true,

    'language_and_terminology_check_required',
      true,

    'curriculum_alignment_check_required',
      true,

    'option_quality_check_required',
      true,

    'solve_time_check_required',
      true,

    'uncertainty_must_reduce_confidence',
      true,

    'critical_risk_requires_human_review',
      true,

    'ai_correction_must_not_auto_apply',
      true,

    'direct_publication_forbidden',
      true
  ),

  jsonb_build_object(
    'seed',
      '046_teacher_review_subject_profiles',

    'subject_name',
      sp.subject_name,

    'role',
      rr.reviewer_role,

    'production_publication',
      false
  ),

  true

from subject_profiles sp
cross join review_roles rr

on conflict (profile_code)
do update set
  name =
    excluded.name,

  description =
    excluded.description,

  subject_id =
    excluded.subject_id,

  reviewer_role =
    excluded.reviewer_role,

  profile_version =
    excluded.profile_version,

  prompt_version =
    excluded.prompt_version,

  minimum_confidence =
    excluded.minimum_confidence,

  automatic_low_risk_threshold =
    excluded.automatic_low_risk_threshold,

  requires_answer_verification =
    excluded.requires_answer_verification,

  requires_solution_verification =
    excluded.requires_solution_verification,

  requires_curriculum_verification =
    excluded.requires_curriculum_verification,

  requires_language_verification =
    excluded.requires_language_verification,

  requires_grade_verification =
    excluded.requires_grade_verification,

  requires_option_verification =
    excluded.requires_option_verification,

  requires_solve_time_verification =
    excluded.requires_solve_time_verification,

  requires_originality_verification =
    excluded.requires_originality_verification,

  correction_allowed =
    excluded.correction_allowed,

  direct_publication_allowed =
    false,

  rules =
    excluded.rules,

  metadata =
    excluded.metadata,

  is_active =
    true,

  updated_at =
    now();

commit;