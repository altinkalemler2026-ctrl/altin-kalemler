-- ============================================================
-- 057_vault_demand_planner.sql
-- Altın Kalemler
--
-- Vault Demand Planner
--
-- Amaç:
--
-- 1. Kasa başına güvenli soru stok ihtiyacını hesaplamak.
-- 2. Aktif öğrenci sayısını hesaba katmak.
-- 3. Mevcut uygun soru stoğunu ölçmek.
-- 4. Güncel / tarama soru üretim ihtiyacını ayırmak.
-- 5. Eksik soru varsa üretim önerisi oluşturmak.
-- 6. Üretim başlamadan önce admin onayı beklemek.
--
-- AI burada miktarı keyfi belirlemez.
-- Deterministic planner ihtiyacı hesaplar.
--
-- AI daha sonra:
--   - hangi alt konu
--   - hangi soru tipi
--   - hangi bilişsel seviye
--   - hangi referans sorular
-- kullanılmalı konusunda öneri verir.
-- ============================================================

begin;


-- ============================================================
-- 1. VAULT DEMAND POLICY
--
-- Her kasa için talep hesaplama ayarları.
-- ============================================================

create table if not exists public.question_vault_demand_policies (
  id uuid primary key
    default gen_random_uuid(),

  vault_id uuid not null
    references public.question_vaults(id)
    on delete cascade,

  inventory_scope text not null
    default 'practice',

  weekly_questions_per_student integer not null
    default 20,

  target_repeat_weeks integer not null
    default 8,

  safety_factor numeric(6,3) not null
    default 1.250,

  user_diversity_weight numeric(6,3) not null
    default 0.250,

  minimum_inventory_floor integer not null
    default 100,

  current_content_ratio numeric(6,3) not null
    default 0.700,

  review_content_ratio numeric(6,3) not null
    default 0.300,

  generation_batch_size integer not null
    default 20,

  low_shortage_threshold integer not null
    default 20,

  high_shortage_threshold integer not null
    default 100,

  auto_create_generation_recommendation boolean not null
    default true,

  is_active boolean not null
    default true,

  metadata jsonb not null
    default '{}'::jsonb,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  constraint question_vault_demand_policies_vault_unique
    unique (vault_id),

  constraint question_vault_demand_policies_scope_check
    check (
      inventory_scope in (
        'practice',
        'competition',
        'one_v_one',
        'exam'
      )
    ),

  constraint question_vault_demand_policies_weekly_questions_check
    check (
      weekly_questions_per_student >= 1
      and weekly_questions_per_student <= 500
    ),

  constraint question_vault_demand_policies_repeat_weeks_check
    check (
      target_repeat_weeks >= 1
      and target_repeat_weeks <= 52
    ),

  constraint question_vault_demand_policies_safety_factor_check
    check (
      safety_factor >= 1.000
      and safety_factor <= 5.000
    ),

  constraint question_vault_demand_policies_diversity_weight_check
    check (
      user_diversity_weight >= 0.000
      and user_diversity_weight <= 2.000
    ),

  constraint question_vault_demand_policies_min_floor_check
    check (
      minimum_inventory_floor >= 0
    ),

  constraint question_vault_demand_policies_ratio_check
    check (
      current_content_ratio >= 0
      and review_content_ratio >= 0
      and abs(
        (
          current_content_ratio
          +
          review_content_ratio
        )
        -
        1.000
      ) <= 0.001
    ),

  constraint question_vault_demand_policies_batch_size_check
    check (
      generation_batch_size >= 1
      and generation_batch_size <= 500
    ),

  constraint question_vault_demand_policies_threshold_check
    check (
      low_shortage_threshold >= 0
      and high_shortage_threshold >= low_shortage_threshold
    )
);


create index if not exists
  idx_question_vault_demand_policies_active
on public.question_vault_demand_policies (
  is_active,
  inventory_scope
);


-- ============================================================
-- 2. DEMAND SNAPSHOTS
--
-- Planner her hesap yaptığında tarihsel rapor tutulur.
--
-- Böylece:
-- "3 ay önce kaç kullanıcı vardı?"
-- "stok ne kadardı?"
-- "kaç soru önerilmişti?"
-- gibi raporlar alınabilir.
-- ============================================================

create table if not exists public.question_vault_demand_snapshots (
  id uuid primary key
    default gen_random_uuid(),

  vault_id uuid not null
    references public.question_vaults(id)
    on delete cascade,

  policy_id uuid
    references public.question_vault_demand_policies(id)
    on delete set null,

  requested_week integer not null,

  inventory_scope text not null,

  active_student_count integer not null,

  weekly_questions_per_student integer not null,

  estimated_weekly_attempts bigint not null,

  target_repeat_weeks integer not null,

  safety_factor numeric(6,3) not null,

  diversity_multiplier numeric(10,4) not null,

  activation_target_count integer not null
    default 0,

  calculated_dynamic_target integer not null,

  final_target_inventory integer not null,

  actual_eligible_inventory integer not null,

  shortage_count integer not null,

  excess_count integer not null,

  current_content_target integer not null,

  review_content_target integer not null,

  recommended_generation_count integer not null,

  recommended_current_generation integer not null,

  recommended_review_generation integer not null,

  generation_priority text not null,

  estimated_weeks_of_inventory numeric(12,4),

  generation_recommended boolean not null,

  calculation_details jsonb not null
    default '{}'::jsonb,

  created_at timestamptz not null
    default now(),

  constraint question_vault_demand_snapshots_scope_check
    check (
      inventory_scope in (
        'practice',
        'competition',
        'one_v_one',
        'exam'
      )
    ),

  constraint question_vault_demand_snapshots_week_check
    check (
      requested_week >= 0
    ),

  constraint question_vault_demand_snapshots_students_check
    check (
      active_student_count >= 0
    ),

  constraint question_vault_demand_snapshots_priority_check
    check (
      generation_priority in (
        'none',
        'low',
        'normal',
        'high',
        'critical'
      )
    )
);


create index if not exists
  idx_question_vault_demand_snapshots_vault_created
on public.question_vault_demand_snapshots (
  vault_id,
  created_at desc
);


create index if not exists
  idx_question_vault_demand_snapshots_generation
on public.question_vault_demand_snapshots (
  generation_recommended,
  generation_priority,
  created_at desc
);


-- ============================================================
-- 3. QUESTION GENERATION REQUESTS
--
-- Planner öneri oluşturur.
--
-- Üretim admin onayı olmadan başlamaz.
-- ============================================================

create table if not exists public.question_generation_requests (
  id uuid primary key
    default gen_random_uuid(),

  vault_id uuid not null
    references public.question_vaults(id)
    on delete cascade,

  demand_snapshot_id uuid
    references public.question_vault_demand_snapshots(id)
    on delete set null,

  request_status text not null
    default 'pending_approval',

  requested_question_count integer not null,

  current_question_count integer not null
    default 0,

  review_question_count integer not null
    default 0,

  generation_batch_size integer not null
    default 20,

  generation_priority text not null
    default 'normal',

  request_reason jsonb not null
    default '{}'::jsonb,

  ai_generation_spec jsonb not null
    default '{}'::jsonb,

  approved_by uuid,

  approved_at timestamptz,

  rejected_by uuid,

  rejected_at timestamptz,

  rejection_reason text,

  generation_started_at timestamptz,

  generation_completed_at timestamptz,

  generated_candidate_count integer not null
    default 0,

  approved_question_count integer not null
    default 0,

  rejected_question_count integer not null
    default 0,

  placed_question_count integer not null
    default 0,

  metadata jsonb not null
    default '{}'::jsonb,

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  constraint question_generation_requests_status_check
    check (
      request_status in (
        'pending_approval',
        'approved',
        'rejected',
        'generating',
        'reviewing',
        'awaiting_human_approval',
        'placing',
        'completed',
        'cancelled',
        'failed'
      )
    ),

  constraint question_generation_requests_count_check
    check (
      requested_question_count >= 0
      and current_question_count >= 0
      and review_question_count >= 0
      and (
        current_question_count
        +
        review_question_count
      ) = requested_question_count
    ),

  constraint question_generation_requests_batch_check
    check (
      generation_batch_size >= 1
      and generation_batch_size <= 500
    ),

  constraint question_generation_requests_priority_check
    check (
      generation_priority in (
        'low',
        'normal',
        'high',
        'critical'
      )
    )
);


create index if not exists
  idx_question_generation_requests_status
on public.question_generation_requests (
  request_status,
  generation_priority,
  created_at
);


create index if not exists
  idx_question_generation_requests_vault
on public.question_generation_requests (
  vault_id,
  created_at desc
);


-- Aynı kasa için birden fazla açık otomatik talep oluşmasını engelle.
create unique index if not exists
  idx_question_generation_requests_one_open_per_vault
on public.question_generation_requests (
  vault_id
)
where request_status in (
  'pending_approval',
  'approved',
  'generating',
  'reviewing',
  'awaiting_human_approval',
  'placing'
);


-- ============================================================
-- 4. UPDATED_AT TRIGGERS
-- ============================================================

drop trigger if exists
  trg_question_vault_demand_policies_updated_at
on public.question_vault_demand_policies;

create trigger
  trg_question_vault_demand_policies_updated_at
before update
on public.question_vault_demand_policies
for each row
execute function public.set_question_vault_updated_at();


drop trigger if exists
  trg_question_generation_requests_updated_at
on public.question_generation_requests;

create trigger
  trg_question_generation_requests_updated_at
before update
on public.question_generation_requests
for each row
execute function public.set_question_vault_updated_at();


-- ============================================================
-- 5. DEFAULT POLICY CREATION
--
-- Policy yoksa otomatik varsayılan değerlerle oluşturulur.
-- ============================================================

create or replace function public.ensure_question_vault_demand_policy(
  p_vault_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_policy_id uuid;
begin

  if p_vault_id is null then
    raise exception
      'p_vault_id boş olamaz.';
  end if;


  if not exists (
    select 1
    from public.question_vaults v
    where v.id = p_vault_id
  ) then
    raise exception
      'Question vault bulunamadı: %',
      p_vault_id;
  end if;


  select p.id
  into v_policy_id
  from public.question_vault_demand_policies p
  where p.vault_id = p_vault_id;


  if v_policy_id is null then

    insert into public.question_vault_demand_policies (
      vault_id
    )
    values (
      p_vault_id
    )
    returning id
    into v_policy_id;

  end if;


  return v_policy_id;

end;
$function$;


-- ============================================================
-- 6. DEMAND CALCULATION
--
-- Kullanıcı sayısı doğrusal büyütülmez.
--
-- Aynı soru havuzu birçok öğrenci tarafından kullanılabilir.
--
-- Diversity multiplier:
--
--   1 + log10(active_student_count + 1) * weight
--
-- Örnek weight = 0.25:
--
-- 10 öğrenci   -> ~1.26
-- 100          -> ~1.50
-- 1.000        -> ~1.75
-- 10.000       -> ~2.00
--
-- Böylece kullanıcı sayısı büyüdükçe çeşitlilik ihtiyacı
-- artar fakat soru ihtiyacı kontrolden çıkmaz.
-- ============================================================

create or replace function public.calculate_question_vault_demand(
  p_vault_id uuid,
  p_current_week integer,
  p_active_student_count integer,
  p_weekly_questions_per_student integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_policy public.question_vault_demand_policies%rowtype;

  v_scope text;

  v_weekly_questions integer;

  v_estimated_weekly_attempts bigint;

  v_diversity_multiplier numeric(10,4);

  v_base_student_inventory numeric;

  v_dynamic_target integer;

  v_activation_target integer := 0;

  v_final_target integer;

  v_actual_inventory integer := 0;

  v_shortage integer;

  v_excess integer;

  v_current_target integer;

  v_review_target integer;

  v_generation_count integer;

  v_generation_current integer;

  v_generation_review integer;

  v_priority text;

  v_weeks_of_inventory numeric(12,4);

  v_snapshot_id uuid;

  v_generation_recommended boolean;
begin

  if p_vault_id is null then
    raise exception
      'p_vault_id boş olamaz.';
  end if;


  if p_current_week is null
     or p_current_week < 0
  then
    raise exception
      'p_current_week 0 veya daha büyük olmalıdır.';
  end if;


  if p_active_student_count is null
     or p_active_student_count < 0
  then
    raise exception
      'p_active_student_count 0 veya daha büyük olmalıdır.';
  end if;


  perform
    public.ensure_question_vault_demand_policy(
      p_vault_id
    );


  select *
  into v_policy
  from public.question_vault_demand_policies p
  where p.vault_id = p_vault_id
    and p.is_active = true;


  if not found then
    raise exception
      'Aktif demand policy bulunamadı: %',
      p_vault_id;
  end if;


  v_scope :=
    v_policy.inventory_scope;


  v_weekly_questions :=
    coalesce(
      p_weekly_questions_per_student,
      v_policy.weekly_questions_per_student
    );


  if v_weekly_questions < 1 then
    raise exception
      'Haftalık öğrenci başı soru sayısı en az 1 olmalıdır.';
  end if;


  -- ----------------------------------------------------------
  -- Toplam kullanım hacmi
  -- ----------------------------------------------------------

  v_estimated_weekly_attempts :=
    (
      p_active_student_count::bigint
      *
      v_weekly_questions::bigint
    );


  -- ----------------------------------------------------------
  -- Kullanıcı çeşitlilik katsayısı
  --
  -- PostgreSQL log(base, value)
  -- ----------------------------------------------------------

  v_diversity_multiplier :=
    round(
      (
        1
        +
        (
          log(
            10::numeric,
            greatest(
              p_active_student_count + 1,
              1
            )::numeric
          )
          *
          v_policy.user_diversity_weight
        )
      ),
      4
    );


  -- ----------------------------------------------------------
  -- Bir öğrencinin tekrar periyodu boyunca görmesi gereken
  -- benzersiz soru havuzu.
  --
  -- Öğrenci sayısı yalnız diversity_multiplier ile etkiler.
  -- ----------------------------------------------------------

  v_base_student_inventory :=
    (
      v_weekly_questions::numeric
      *
      v_policy.target_repeat_weeks::numeric
    );


  v_dynamic_target :=
    ceil(
      v_base_student_inventory
      *
      v_diversity_multiplier
      *
      v_policy.safety_factor
    )::integer;


  v_dynamic_target :=
    greatest(
      v_dynamic_target,
      v_policy.minimum_inventory_floor
    );


  -- ----------------------------------------------------------
  -- Eski A/B/C/D activation target varsa onu da koru.
  -- start inclusive / end exclusive.
  -- ----------------------------------------------------------

  select
    coalesce(
      max(w.target_question_count),
      0
    )
  into v_activation_target
  from public.question_vault_activation_windows w
  where w.vault_id = p_vault_id
    and p_current_week >= w.start_week
    and p_current_week < w.end_week;


  -- ----------------------------------------------------------
  -- Sistem eski tanımlanmış kasa hedefinin altına düşmez.
  -- ----------------------------------------------------------

  v_final_target :=
    greatest(
      v_dynamic_target,
      v_activation_target,
      v_policy.minimum_inventory_floor
    );


  -- ----------------------------------------------------------
  -- Gerçek uygun inventory
  -- ----------------------------------------------------------

  select
    count(*)::integer
  into v_actual_inventory
  from public.question_vault_memberships m
  where m.vault_id = p_vault_id
    and m.membership_status = 'active'
    and (
      (
        v_scope = 'practice'
        and m.practice_eligible = true
      )
      or
      (
        v_scope = 'competition'
        and m.competition_eligible = true
      )
      or
      (
        v_scope = 'one_v_one'
        and m.one_v_one_eligible = true
      )
      or
      (
        v_scope = 'exam'
        and m.exam_eligible = true
      )
    );


  -- ----------------------------------------------------------
  -- Shortage / excess
  -- ----------------------------------------------------------

  v_shortage :=
    greatest(
      v_final_target
      -
      v_actual_inventory,
      0
    );


  v_excess :=
    greatest(
      v_actual_inventory
      -
      v_final_target,
      0
    );


  -- ----------------------------------------------------------
  -- Güncel / tarama hedefleri
  -- ----------------------------------------------------------

  v_current_target :=
    ceil(
      v_final_target
      *
      v_policy.current_content_ratio
    )::integer;


  v_review_target :=
    greatest(
      v_final_target
      -
      v_current_target,
      0
    );


  -- ----------------------------------------------------------
  -- Generation count
  --
  -- Batch büyüklüğüne yukarı yuvarla.
  --
  -- Örnek:
  -- ihtiyaç 43
  -- batch 20
  -- öneri 60
  -- ----------------------------------------------------------

  if v_shortage > 0 then

    v_generation_count :=
      ceil(
        v_shortage::numeric
        /
        v_policy.generation_batch_size::numeric
      )::integer
      *
      v_policy.generation_batch_size;

  else

    v_generation_count := 0;

  end if;


  -- ----------------------------------------------------------
  -- Üretilecek yeni soruların dağılımı
  --
  -- Güncel içerik daha yüksek ağırlıklı.
  -- ----------------------------------------------------------

  v_generation_current :=
    ceil(
      v_generation_count
      *
      v_policy.current_content_ratio
    )::integer;


  v_generation_review :=
    greatest(
      v_generation_count
      -
      v_generation_current,
      0
    );


  -- ----------------------------------------------------------
  -- Priority
  -- ----------------------------------------------------------

  if v_shortage <= 0 then

    v_priority :=
      'none';

  elsif v_actual_inventory = 0 then

    v_priority :=
      'critical';

  elsif v_shortage >
    v_policy.high_shortage_threshold
  then

    v_priority :=
      'high';

  elsif v_shortage >
    v_policy.low_shortage_threshold
  then

    v_priority :=
      'normal';

  else

    v_priority :=
      'low';

  end if;


  v_generation_recommended :=
    v_shortage > 0;


  -- ----------------------------------------------------------
  -- Tahmini inventory haftası
  --
  -- Aynı havuzun paylaşılabilir olduğu varsayılır.
  -- Basit gösterge:
  --
  -- inventory /
  -- öğrenci başına haftalık soru
  -- ----------------------------------------------------------

  if v_weekly_questions > 0 then

    v_weeks_of_inventory :=
      round(
        (
          v_actual_inventory::numeric
          /
          v_weekly_questions::numeric
        ),
        4
      );

  else

    v_weeks_of_inventory :=
      null;

  end if;


  -- ----------------------------------------------------------
  -- Snapshot
  -- ----------------------------------------------------------

  insert into public.question_vault_demand_snapshots (
    vault_id,
    policy_id,
    requested_week,
    inventory_scope,
    active_student_count,
    weekly_questions_per_student,
    estimated_weekly_attempts,
    target_repeat_weeks,
    safety_factor,
    diversity_multiplier,
    activation_target_count,
    calculated_dynamic_target,
    final_target_inventory,
    actual_eligible_inventory,
    shortage_count,
    excess_count,
    current_content_target,
    review_content_target,
    recommended_generation_count,
    recommended_current_generation,
    recommended_review_generation,
    generation_priority,
    estimated_weeks_of_inventory,
    generation_recommended,
    calculation_details
  )
  values (
    p_vault_id,
    v_policy.id,
    p_current_week,
    v_scope,
    p_active_student_count,
    v_weekly_questions,
    v_estimated_weekly_attempts,
    v_policy.target_repeat_weeks,
    v_policy.safety_factor,
    v_diversity_multiplier,
    v_activation_target,
    v_dynamic_target,
    v_final_target,
    v_actual_inventory,
    v_shortage,
    v_excess,
    v_current_target,
    v_review_target,
    v_generation_count,
    v_generation_current,
    v_generation_review,
    v_priority,
    v_weeks_of_inventory,
    v_generation_recommended,

    jsonb_build_object(
      'formula_version',
      'vault-demand-v1',

      'current_content_ratio',
      v_policy.current_content_ratio,

      'review_content_ratio',
      v_policy.review_content_ratio,

      'generation_batch_size',
      v_policy.generation_batch_size,

      'minimum_inventory_floor',
      v_policy.minimum_inventory_floor
    )
  )
  returning id
  into v_snapshot_id;


  return jsonb_build_object(
    'snapshot_id',
    v_snapshot_id,

    'vault_id',
    p_vault_id,

    'week',
    p_current_week,

    'inventory_scope',
    v_scope,

    'active_student_count',
    p_active_student_count,

    'weekly_questions_per_student',
    v_weekly_questions,

    'estimated_weekly_attempts',
    v_estimated_weekly_attempts,

    'diversity_multiplier',
    v_diversity_multiplier,

    'activation_target_count',
    v_activation_target,

    'dynamic_target',
    v_dynamic_target,

    'final_target_inventory',
    v_final_target,

    'actual_eligible_inventory',
    v_actual_inventory,

    'shortage_count',
    v_shortage,

    'excess_count',
    v_excess,

    'current_content_target',
    v_current_target,

    'review_content_target',
    v_review_target,

    'recommended_generation_count',
    v_generation_count,

    'recommended_current_generation',
    v_generation_current,

    'recommended_review_generation',
    v_generation_review,

    'generation_priority',
    v_priority,

    'generation_recommended',
    v_generation_recommended
  );

end;
$function$;


-- ============================================================
-- 7. CREATE GENERATION REQUEST FROM SNAPSHOT
--
-- Planner sonucu admin ekranına taşınır.
--
-- Henüz üretim başlamaz.
-- ============================================================

create or replace function public.create_question_generation_request(
  p_snapshot_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_snapshot public.question_vault_demand_snapshots%rowtype;

  v_policy public.question_vault_demand_policies%rowtype;

  v_request_id uuid;
begin

  select *
  into v_snapshot
  from public.question_vault_demand_snapshots s
  where s.id = p_snapshot_id;


  if not found then
    raise exception
      'Demand snapshot bulunamadı: %',
      p_snapshot_id;
  end if;


  if v_snapshot.generation_recommended = false
     or v_snapshot.recommended_generation_count <= 0
  then
    raise exception
      'Bu snapshot için soru üretimi gerekli değil.';
  end if;


  select *
  into v_policy
  from public.question_vault_demand_policies p
  where p.id = v_snapshot.policy_id;


  -- Aynı kasa için açık talep varsa yenisini oluşturma.
  select r.id
  into v_request_id
  from public.question_generation_requests r
  where r.vault_id = v_snapshot.vault_id
    and r.request_status in (
      'pending_approval',
      'approved',
      'generating',
      'reviewing',
      'awaiting_human_approval',
      'placing'
    )
  order by r.created_at desc
  limit 1;


  if v_request_id is not null then
    return v_request_id;
  end if;


  insert into public.question_generation_requests (
    vault_id,
    demand_snapshot_id,
    request_status,
    requested_question_count,
    current_question_count,
    review_question_count,
    generation_batch_size,
    generation_priority,
    request_reason,
    ai_generation_spec
  )
  values (
    v_snapshot.vault_id,

    v_snapshot.id,

    'pending_approval',

    v_snapshot.recommended_generation_count,

    v_snapshot.recommended_current_generation,

    v_snapshot.recommended_review_generation,

    coalesce(
      v_policy.generation_batch_size,
      20
    ),

    case
      when v_snapshot.generation_priority = 'critical'
        then 'critical'

      when v_snapshot.generation_priority = 'high'
        then 'high'

      when v_snapshot.generation_priority = 'low'
        then 'low'

      else 'normal'
    end,

    jsonb_build_object(
      'shortage_count',
      v_snapshot.shortage_count,

      'actual_inventory',
      v_snapshot.actual_eligible_inventory,

      'target_inventory',
      v_snapshot.final_target_inventory,

      'active_student_count',
      v_snapshot.active_student_count,

      'estimated_weekly_attempts',
      v_snapshot.estimated_weekly_attempts
    ),

    jsonb_build_object(
      'generation_mode',
      'vault_shortage',

      'current_question_count',
      v_snapshot.recommended_current_generation,

      'review_question_count',
      v_snapshot.recommended_review_generation,

      'use_reference_questions',
      true,

      'human_final_approval_required',
      true,

      'auto_vault_placement_after_approval',
      true
    )
  )
  returning id
  into v_request_id;


  return v_request_id;

end;
$function$;


-- ============================================================
-- 8. APPROVE GENERATION REQUEST
--
-- Admin onayından sonra status = approved.
--
-- Burada henüz AI çağrısı yapılmaz.
-- AI worker sonraki migrationlarda approved talepleri işler.
-- ============================================================

create or replace function public.approve_question_generation_request(
  p_request_id uuid,
  p_approved_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_request public.question_generation_requests%rowtype;
begin

  select *
  into v_request
  from public.question_generation_requests r
  where r.id = p_request_id
  for update;


  if not found then
    raise exception
      'Generation request bulunamadı: %',
      p_request_id;
  end if;


  if v_request.request_status <> 'pending_approval' then
    raise exception
      'Yalnız pending_approval durumundaki talep onaylanabilir. Mevcut durum: %',
      v_request.request_status;
  end if;


  update public.question_generation_requests
  set
    request_status =
      'approved',

    approved_by =
      p_approved_by,

    approved_at =
      now(),

    updated_at =
      now()
  where id = p_request_id;


  return jsonb_build_object(
    'request_id',
    p_request_id,

    'status',
    'approved',

    'requested_question_count',
    v_request.requested_question_count,

    'current_question_count',
    v_request.current_question_count,

    'review_question_count',
    v_request.review_question_count
  );

end;
$function$;


-- ============================================================
-- 9. REJECT GENERATION REQUEST
-- ============================================================

create or replace function public.reject_question_generation_request(
  p_request_id uuid,
  p_rejected_by uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_status text;
begin

  select request_status
  into v_status
  from public.question_generation_requests
  where id = p_request_id
  for update;


  if not found then
    raise exception
      'Generation request bulunamadı: %',
      p_request_id;
  end if;


  if v_status <> 'pending_approval' then
    raise exception
      'Yalnız pending_approval durumundaki talep reddedilebilir.';
  end if;


  update public.question_generation_requests
  set
    request_status =
      'rejected',

    rejected_by =
      p_rejected_by,

    rejected_at =
      now(),

    rejection_reason =
      nullif(
        btrim(
          coalesce(
            p_reason,
            ''
          )
        ),
        ''
      ),

    updated_at =
      now()
  where id = p_request_id;


  return jsonb_build_object(
    'request_id',
    p_request_id,

    'status',
    'rejected'
  );

end;
$function$;


-- ============================================================
-- 10. REPORT VIEW
--
-- Admin ekranının kullanacağı özet.
-- SECURITY INVOKER.
-- ============================================================

create or replace view public.question_vault_demand_overview
with (
  security_invoker = true
)
as
select
  s.id as snapshot_id,

  s.vault_id,

  v.vault_code,

  v.name as vault_name,

  v.grade_level,

  v.subject_id,

  v.difficulty_level,

  s.requested_week,

  s.inventory_scope,

  s.active_student_count,

  s.estimated_weekly_attempts,

  s.activation_target_count,

  s.calculated_dynamic_target,

  s.final_target_inventory,

  s.actual_eligible_inventory,

  s.shortage_count,

  s.excess_count,

  s.current_content_target,

  s.review_content_target,

  s.recommended_generation_count,

  s.recommended_current_generation,

  s.recommended_review_generation,

  s.generation_priority,

  s.generation_recommended,

  s.created_at

from public.question_vault_demand_snapshots s

join public.question_vaults v
  on v.id = s.vault_id;


-- ============================================================
-- 11. RLS
-- ============================================================

alter table
  public.question_vault_demand_policies
enable row level security;


alter table
  public.question_vault_demand_snapshots
enable row level security;


alter table
  public.question_generation_requests
enable row level security;


-- ============================================================
-- 12. PRIVILEGES
--
-- Şimdilik bu planner server-side çalışır.
--
-- Admin UI erişimini ayrı güvenli server action üzerinden
-- bağlayacağız.
-- ============================================================

revoke all
on table public.question_vault_demand_policies
from anon, authenticated;

revoke all
on table public.question_vault_demand_snapshots
from anon, authenticated;

revoke all
on table public.question_generation_requests
from anon, authenticated;


grant select, insert, update, delete
on table public.question_vault_demand_policies
to service_role;

grant select, insert, update, delete
on table public.question_vault_demand_snapshots
to service_role;

grant select, insert, update, delete
on table public.question_generation_requests
to service_role;


revoke execute
on function public.ensure_question_vault_demand_policy(uuid)
from public, anon, authenticated;

grant execute
on function public.ensure_question_vault_demand_policy(uuid)
to service_role;


revoke execute
on function public.calculate_question_vault_demand(
  uuid,
  integer,
  integer,
  integer
)
from public, anon, authenticated;

grant execute
on function public.calculate_question_vault_demand(
  uuid,
  integer,
  integer,
  integer
)
to service_role;


revoke execute
on function public.create_question_generation_request(uuid)
from public, anon, authenticated;

grant execute
on function public.create_question_generation_request(uuid)
to service_role;


revoke execute
on function public.approve_question_generation_request(
  uuid,
  uuid
)
from public, anon, authenticated;

grant execute
on function public.approve_question_generation_request(
  uuid,
  uuid
)
to service_role;


revoke execute
on function public.reject_question_generation_request(
  uuid,
  uuid,
  text
)
from public, anon, authenticated;

grant execute
on function public.reject_question_generation_request(
  uuid,
  uuid,
  text
)
to service_role;


commit;