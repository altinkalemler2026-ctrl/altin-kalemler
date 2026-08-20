-- ============================================================
-- 051_question_vault_memberships.sql
-- Altın Kalemler
--
-- Canonical questions <-> question vault memberships
--
-- Bir soru birden fazla kasada olabilir.
-- Aynı soru aynı kasaya yalnız bir kez eklenebilir.
-- ============================================================

begin;


-- ============================================================
-- 1. QUESTION VAULT MEMBERSHIPS
-- ============================================================

create table if not exists public.question_vault_memberships (
  id uuid primary key default gen_random_uuid(),

  vault_id uuid not null
    references public.question_vaults(id)
    on delete cascade,

  question_id uuid not null
    references public.questions(id)
    on delete cascade,

  membership_source text not null default 'manual'
    check (
      membership_source in (
        'manual',
        'import',
        'rule_engine',
        'ai_recommendation',
        'migration'
      )
    ),

  membership_status text not null default 'active'
    check (
      membership_status in (
        'active',
        'inactive',
        'blocked',
        'pending_review'
      )
    ),

  practice_eligible boolean not null default false,
  competition_eligible boolean not null default false,
  one_v_one_eligible boolean not null default false,
  exam_eligible boolean not null default false,

  eligibility_reason jsonb not null default '{}'::jsonb,

  assigned_by uuid
    references auth.users(id)
    on delete set null,

  assigned_at timestamptz not null default now(),

  removed_by uuid
    references auth.users(id)
    on delete set null,

  removed_at timestamptz,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(vault_id, question_id),

  constraint question_vault_membership_removed_consistency
    check (
      (
        membership_status = 'inactive'
        and removed_at is not null
      )
      or
      membership_status <> 'inactive'
    )
);


create index if not exists idx_question_vault_memberships_vault
  on public.question_vault_memberships(vault_id);

create index if not exists idx_question_vault_memberships_question
  on public.question_vault_memberships(question_id);

create index if not exists idx_question_vault_memberships_status
  on public.question_vault_memberships(membership_status);

create index if not exists idx_question_vault_memberships_competition
  on public.question_vault_memberships(
    vault_id,
    competition_eligible
  )
  where membership_status = 'active';

create index if not exists idx_question_vault_memberships_practice
  on public.question_vault_memberships(
    vault_id,
    practice_eligible
  )
  where membership_status = 'active';


-- ============================================================
-- 2. UPDATED_AT TRIGGER
-- ============================================================

drop trigger if exists trg_question_vault_memberships_updated_at
  on public.question_vault_memberships;

create trigger trg_question_vault_memberships_updated_at
before update on public.question_vault_memberships
for each row
execute function public.set_question_vault_updated_at();


-- ============================================================
-- 3. QUESTION BASE ELIGIBILITY
--
-- Bu fonksiyon AI kararı değildir.
-- Mevcut production question alanlarından deterministik
-- güvenlik kontrolü yapar.
--
-- Teacher Review / readiness ek güvenlik kapıları
-- sonraki eligibility motoruna bağlanacaktır.
-- ============================================================

create or replace function public.get_question_base_eligibility(
  p_question_id uuid
)
returns table (
  question_id uuid,

  approval_status text,
  is_active boolean,

  ownership_status text,
  license_status text,
  commercial_use_allowed boolean,

  has_answer boolean,

  practice_base_eligible boolean,
  competition_base_eligible boolean,
  one_v_one_base_eligible boolean,

  blocking_reasons jsonb
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    q.id as question_id,

    q.approval_status,
    q.is_active,

    q.ownership_status,
    q.license_status,
    q.commercial_use_allowed,

    (
      q.correct_answer is not null
      and btrim(q.correct_answer) <> ''
    ) as has_answer,

    (
      q.is_active = true
      and q.approval_status = 'approved'
      and q.correct_answer is not null
      and btrim(q.correct_answer) <> ''
    ) as practice_base_eligible,

    (
      q.is_active = true
      and q.approval_status = 'approved'
      and q.correct_answer is not null
      and btrim(q.correct_answer) <> ''
      and q.commercial_use_allowed = true
    ) as competition_base_eligible,

    (
      q.is_active = true
      and q.approval_status = 'approved'
      and q.correct_answer is not null
      and btrim(q.correct_answer) <> ''
      and q.commercial_use_allowed = true
      and q.estimated_solve_time_seconds is not null
      and q.estimated_solve_time_seconds > 0
    ) as one_v_one_base_eligible,

    jsonb_strip_nulls(
      jsonb_build_object(

        'inactive',
        case
          when q.is_active = false
          then true
          else null
        end,

        'approval_not_approved',
        case
          when q.approval_status <> 'approved'
          then q.approval_status
          else null
        end,

        'missing_correct_answer',
        case
          when q.correct_answer is null
            or btrim(q.correct_answer) = ''
          then true
          else null
        end,

        'commercial_use_not_allowed',
        case
          when q.commercial_use_allowed = false
          then true
          else null
        end,

        'missing_solve_time',
        case
          when q.estimated_solve_time_seconds is null
            or q.estimated_solve_time_seconds <= 0
          then true
          else null
        end

      )
    ) as blocking_reasons

  from public.questions q
  where q.id = p_question_id;
$$;


-- ============================================================
-- 4. KASA ÖZETİ
--
-- Hedef soru
-- Gerçek aktif üyelik
-- Eksik
-- Fazla
-- ============================================================

create or replace function public.get_question_vault_inventory_summary(
  p_vault_id uuid
)
returns table (
  vault_id uuid,
  vault_code text,
  vault_name text,

  target_question_count integer,

  actual_question_count bigint,

  practice_eligible_count bigint,
  competition_eligible_count bigint,
  one_v_one_eligible_count bigint,
  exam_eligible_count bigint,

  missing_question_count bigint,
  excess_question_count bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    v.id as vault_id,
    v.vault_code,
    v.name as vault_name,

    case
      when v.metadata ? 'target_question_count'
        and (v.metadata->>'target_question_count') ~ '^[0-9]+$'
      then (v.metadata->>'target_question_count')::integer
      else null
    end as target_question_count,

    count(m.id)
      filter (
        where m.membership_status = 'active'
      ) as actual_question_count,

    count(m.id)
      filter (
        where m.membership_status = 'active'
          and m.practice_eligible = true
      ) as practice_eligible_count,

    count(m.id)
      filter (
        where m.membership_status = 'active'
          and m.competition_eligible = true
      ) as competition_eligible_count,

    count(m.id)
      filter (
        where m.membership_status = 'active'
          and m.one_v_one_eligible = true
      ) as one_v_one_eligible_count,

    count(m.id)
      filter (
        where m.membership_status = 'active'
          and m.exam_eligible = true
      ) as exam_eligible_count,

    greatest(
      coalesce(
        case
          when v.metadata ? 'target_question_count'
            and (v.metadata->>'target_question_count') ~ '^[0-9]+$'
          then (v.metadata->>'target_question_count')::integer
          else 0
        end,
        0
      )
      -
      count(m.id)
        filter (
          where m.membership_status = 'active'
        ),
      0
    )::bigint as missing_question_count,

    greatest(
      count(m.id)
        filter (
          where m.membership_status = 'active'
        )
      -
      coalesce(
        case
          when v.metadata ? 'target_question_count'
            and (v.metadata->>'target_question_count') ~ '^[0-9]+$'
          then (v.metadata->>'target_question_count')::integer
          else 0
        end,
        0
      ),
      0
    )::bigint as excess_question_count

  from public.question_vaults v

  left join public.question_vault_memberships m
    on m.vault_id = v.id

  where v.id = p_vault_id

  group by
    v.id,
    v.vault_code,
    v.name,
    v.metadata;
$$;


-- ============================================================
-- 5. TÜM KASALAR İÇİN ENVANTER ÖZETİ
--
-- ÖNEMLİ:
-- security_invoker = true
--
-- View sahibinin yetkilerini kullanmaz.
-- Sorguyu yapan kullanıcının permissions / RLS kuralları
-- uygulanır.
-- ============================================================

create or replace view public.question_vault_inventory_overview
with (security_invoker = true)
as
select
  v.id as vault_id,
  v.vault_code,
  v.name as vault_name,

  v.grade_level,
  v.subject_id,
  v.difficulty_level,
  v.section_code,

  case
    when v.metadata ? 'target_question_count'
      and (v.metadata->>'target_question_count') ~ '^[0-9]+$'
    then (v.metadata->>'target_question_count')::integer
    else null
  end as target_question_count,

  count(m.id)
    filter (
      where m.membership_status = 'active'
    ) as actual_question_count,

  count(m.id)
    filter (
      where m.membership_status = 'active'
        and m.practice_eligible = true
    ) as practice_eligible_count,

  count(m.id)
    filter (
      where m.membership_status = 'active'
        and m.competition_eligible = true
    ) as competition_eligible_count,

  count(m.id)
    filter (
      where m.membership_status = 'active'
        and m.one_v_one_eligible = true
    ) as one_v_one_eligible_count

from public.question_vaults v

left join public.question_vault_memberships m
  on m.vault_id = v.id

group by
  v.id,
  v.vault_code,
  v.name,
  v.grade_level,
  v.subject_id,
  v.difficulty_level,
  v.section_code,
  v.metadata;


-- ============================================================
-- 6. RLS
-- ============================================================

alter table public.question_vault_memberships
  enable row level security;


-- ============================================================
-- 7. SERVICE ROLE
-- ============================================================

grant select, insert, update, delete
on public.question_vault_memberships
to service_role;

grant execute
on function public.get_question_base_eligibility(uuid)
to service_role;

grant execute
on function public.get_question_vault_inventory_summary(uuid)
to service_role;

grant select
on public.question_vault_inventory_overview
to service_role;


commit;