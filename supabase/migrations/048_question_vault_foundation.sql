-- ============================================================
-- 048_question_vault_foundation.sql
-- Altın Kalemler - Soru Kasaları temel mimarisi
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. QUESTION VAULTS
-- ------------------------------------------------------------

create table if not exists public.question_vaults (
  id uuid primary key default gen_random_uuid(),

  vault_code text not null unique,
  name text not null,
  description text,

  vault_type text not null default 'academic'
    check (
      vault_type in (
        'source',
        'academic',
        'practice',
        'competition',
        'one_v_one',
        'exam',
        'quarantine',
        'archive'
      )
    ),

  parent_vault_id uuid
    references public.question_vaults(id)
    on delete restrict,

  grade_level smallint
    check (
      grade_level is null
      or grade_level between 1 and 12
    ),

  subject_id uuid
    references public.subjects(id)
    on delete restrict,

  difficulty_level text
    check (
      difficulty_level is null
      or difficulty_level in (
        'easy',
        'medium',
        'hard',
        'mixed'
      )
    ),

  section_code text,
  section_order integer,

  is_dynamic boolean not null default false,

  is_active boolean not null default true,

  allow_practice boolean not null default false,
  allow_competition boolean not null default false,
  allow_one_v_one boolean not null default false,
  allow_exam boolean not null default false,

  manual_question_assignment_allowed boolean not null default true,

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint question_vault_parent_not_self
    check (
      parent_vault_id is null
      or parent_vault_id <> id
    )
);

create index if not exists idx_question_vaults_parent
  on public.question_vaults(parent_vault_id);

create index if not exists idx_question_vaults_grade_subject
  on public.question_vaults(grade_level, subject_id);

create index if not exists idx_question_vaults_type
  on public.question_vaults(vault_type);

create index if not exists idx_question_vaults_active
  on public.question_vaults(is_active);


-- ------------------------------------------------------------
-- 2. VAULT TOPICS
-- Bir kasa birden fazla konu içerebilir.
-- Örn:
-- 12. sınıf Matematik Kolay / Kısım 1
-- konu 1 + konu 2 + konu 3
-- ------------------------------------------------------------

create table if not exists public.question_vault_topics (
  id uuid primary key default gen_random_uuid(),

  vault_id uuid not null
    references public.question_vaults(id)
    on delete cascade,

  topic_id uuid,

  legacy_topic_code text,
  legacy_topic_name text,

  topic_order integer,

  is_required boolean not null default true,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  constraint question_vault_topic_source_required
    check (
      topic_id is not null
      or legacy_topic_code is not null
      or legacy_topic_name is not null
    )
);

create index if not exists idx_question_vault_topics_vault
  on public.question_vault_topics(vault_id);

create index if not exists idx_question_vault_topics_legacy_code
  on public.question_vault_topics(legacy_topic_code);


-- ------------------------------------------------------------
-- 3. VAULT ACTIVATION WINDOWS
--
-- PPT tasarımındaki:
-- 0-12 hafta
-- 12-24 hafta
-- 24-36 hafta
-- 36-48 hafta
--
-- mantığının karşılığı.
-- ------------------------------------------------------------

create table if not exists public.question_vault_activation_windows (
  id uuid primary key default gen_random_uuid(),

  vault_id uuid not null
    references public.question_vaults(id)
    on delete cascade,

  window_name text,

  start_week integer
    check (
      start_week is null
      or start_week >= 0
    ),

  end_week integer
    check (
      end_week is null
      or end_week >= 0
    ),

  starts_at timestamptz,
  ends_at timestamptz,

  is_enabled boolean not null default true,

  priority integer not null default 100,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint question_vault_activation_week_order
    check (
      start_week is null
      or end_week is null
      or end_week >= start_week
    ),

  constraint question_vault_activation_date_order
    check (
      starts_at is null
      or ends_at is null
      or ends_at >= starts_at
    )
);

create index if not exists idx_question_vault_activation_vault
  on public.question_vault_activation_windows(vault_id);

create index if not exists idx_question_vault_activation_weeks
  on public.question_vault_activation_windows(
    start_week,
    end_week
  );


-- ------------------------------------------------------------
-- 4. VAULT RULES
--
-- Dinamik veya kullanım kasalarının seçim kuralları.
--
-- Örnek:
-- quality >= 2
-- review_status = approved
-- commercial_use_allowed = true
-- solve_time <= 120
-- ------------------------------------------------------------

create table if not exists public.question_vault_rules (
  id uuid primary key default gen_random_uuid(),

  vault_id uuid not null
    references public.question_vaults(id)
    on delete cascade,

  rule_code text not null,

  rule_type text not null
    check (
      rule_type in (
        'eligibility',
        'exclusion',
        'selection',
        'distribution',
        'safety'
      )
    ),

  field_name text,

  operator text
    check (
      operator is null
      or operator in (
        'eq',
        'neq',
        'gt',
        'gte',
        'lt',
        'lte',
        'in',
        'not_in',
        'is_true',
        'is_false',
        'is_null',
        'is_not_null'
      )
    ),

  rule_value jsonb,

  rule_config jsonb not null default '{}'::jsonb,

  priority integer not null default 100,

  is_required boolean not null default true,
  is_active boolean not null default true,

  description text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(vault_id, rule_code)
);

create index if not exists idx_question_vault_rules_vault
  on public.question_vault_rules(vault_id);

create index if not exists idx_question_vault_rules_type
  on public.question_vault_rules(rule_type);


-- ------------------------------------------------------------
-- 5. UPDATED_AT TRIGGER
-- ------------------------------------------------------------

create or replace function public.set_question_vault_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_question_vaults_updated_at
  on public.question_vaults;

create trigger trg_question_vaults_updated_at
before update on public.question_vaults
for each row
execute function public.set_question_vault_updated_at();


drop trigger if exists trg_question_vault_activation_updated_at
  on public.question_vault_activation_windows;

create trigger trg_question_vault_activation_updated_at
before update on public.question_vault_activation_windows
for each row
execute function public.set_question_vault_updated_at();


drop trigger if exists trg_question_vault_rules_updated_at
  on public.question_vault_rules;

create trigger trg_question_vault_rules_updated_at
before update on public.question_vault_rules
for each row
execute function public.set_question_vault_updated_at();


-- ------------------------------------------------------------
-- 6. RLS
-- İlk aşamada tablolar RLS korumasına alınır.
-- İzin politikalarını admin permission sistemine
-- sonraki migration'da bağlayacağız.
-- ------------------------------------------------------------

alter table public.question_vaults
  enable row level security;

alter table public.question_vault_topics
  enable row level security;

alter table public.question_vault_activation_windows
  enable row level security;

alter table public.question_vault_rules
  enable row level security;


-- ------------------------------------------------------------
-- 7. SERVICE ROLE
-- ------------------------------------------------------------

grant select, insert, update, delete
on public.question_vaults
to service_role;

grant select, insert, update, delete
on public.question_vault_topics
to service_role;

grant select, insert, update, delete
on public.question_vault_activation_windows
to service_role;

grant select, insert, update, delete
on public.question_vault_rules
to service_role;


commit;