-- ============================================================
-- 058_fix_vault_demand_target_source.sql
-- Altın Kalemler
--
-- Vault Demand Planner düzeltmesi
--
-- target_question_count gerçek kaynağı:
-- question_vaults.metadata ->> 'target_question_count'
-- ============================================================

begin;


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

  v_dynamic_target integer;

  v_defined_vault_target integer := 0;
  v_activation_target integer := 0;

  v_is_active_in_week boolean := false;

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
begin

  -- ==========================================================
  -- INPUT
  -- ==========================================================

  if p_vault_id is null then
    raise exception 'p_vault_id boş olamaz.';
  end if;

  if p_current_week is null
     or p_current_week < 0
  then
    raise exception 'p_current_week geçersiz.';
  end if;

  if p_active_student_count is null
     or p_active_student_count < 0
  then
    raise exception 'p_active_student_count geçersiz.';
  end if;


  -- ==========================================================
  -- POLICY
  -- ==========================================================

  perform public.ensure_question_vault_demand_policy(
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


  -- ==========================================================
  -- USER DEMAND
  -- ==========================================================

  v_estimated_weekly_attempts :=
    p_active_student_count::bigint
    *
    v_weekly_questions::bigint;


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


  v_dynamic_target :=
    ceil(
      v_weekly_questions::numeric
      *
      v_policy.target_repeat_weeks::numeric
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


  -- ==========================================================
  -- DEFINED VAULT TARGET
  --
  -- Örnek A1:
  -- metadata.target_question_count = 300
  -- ==========================================================

  select
    case
      when
        v.metadata ? 'target_question_count'
        and
        (
          v.metadata
          ->>
          'target_question_count'
        ) ~ '^[0-9]+$'
      then
        (
          v.metadata
          ->>
          'target_question_count'
        )::integer
      else
        0
    end
  into v_defined_vault_target
  from public.question_vaults v
  where v.id = p_vault_id;


  if not found then
    raise exception
      'Question vault bulunamadı: %',
      p_vault_id;
  end if;


  v_defined_vault_target :=
    coalesce(
      v_defined_vault_target,
      0
    );


  -- ==========================================================
  -- ACTIVE WINDOW
  -- ==========================================================

  select exists (
    select 1
    from public.question_vault_activation_windows w
    where w.vault_id = p_vault_id
      and w.is_enabled = true
      and p_current_week >= w.start_week
      and p_current_week < w.end_week
  )
  into v_is_active_in_week;


  if v_is_active_in_week then
    v_activation_target :=
      v_defined_vault_target;
  else
    v_activation_target :=
      0;
  end if;


  -- ==========================================================
  -- FINAL TARGET
  -- ==========================================================

  v_final_target :=
    greatest(
      v_dynamic_target,
      v_defined_vault_target,
      v_policy.minimum_inventory_floor
    );


  -- ==========================================================
  -- CURRENT INVENTORY
  -- ==========================================================

  select count(*)::integer
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


  -- ==========================================================
  -- SHORTAGE
  -- ==========================================================

  v_shortage :=
    greatest(
      v_final_target - v_actual_inventory,
      0
    );


  v_excess :=
    greatest(
      v_actual_inventory - v_final_target,
      0
    );


  -- ==========================================================
  -- CURRENT / REVIEW
  -- ==========================================================

  v_current_target :=
    ceil(
      v_final_target
      *
      v_policy.current_content_ratio
    )::integer;


  v_review_target :=
    greatest(
      v_final_target - v_current_target,
      0
    );


  -- ==========================================================
  -- GENERATION RECOMMENDATION
  -- ==========================================================

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


  -- ==========================================================
  -- PRIORITY
  -- ==========================================================

  if v_shortage = 0 then

    v_priority := 'none';

  elsif
    v_actual_inventory = 0
    and v_is_active_in_week = true
  then

    v_priority := 'critical';

  elsif v_actual_inventory = 0 then

    v_priority := 'high';

  elsif
    v_shortage >
    v_policy.high_shortage_threshold
  then

    v_priority := 'high';

  elsif
    v_shortage >
    v_policy.low_shortage_threshold
  then

    v_priority := 'normal';

  else

    v_priority := 'low';

  end if;


  -- ==========================================================
  -- ESTIMATED WEEKS
  -- ==========================================================

  if v_weekly_questions > 0 then

    v_weeks_of_inventory :=
      round(
        v_actual_inventory::numeric
        /
        v_weekly_questions::numeric,
        4
      );

  else

    v_weeks_of_inventory := null;

  end if;


  -- ==========================================================
  -- SNAPSHOT
  -- ==========================================================

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
    v_shortage > 0,

    jsonb_build_object(
      'formula_version',
      'vault-demand-v2',

      'defined_vault_target',
      v_defined_vault_target,

      'is_active_in_week',
      v_is_active_in_week
    )
  )
  returning id
  into v_snapshot_id;


  -- ==========================================================
  -- RESULT
  -- ==========================================================

  return jsonb_build_object(
    'snapshot_id',
    v_snapshot_id,

    'vault_id',
    p_vault_id,

    'week',
    p_current_week,

    'is_active_in_week',
    v_is_active_in_week,

    'inventory_scope',
    v_scope,

    'active_student_count',
    p_active_student_count,

    'estimated_weekly_attempts',
    v_estimated_weekly_attempts,

    'defined_vault_target',
    v_defined_vault_target,

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
    v_shortage > 0
  );

end;
$function$;


revoke execute
on function public.calculate_question_vault_demand(
  uuid,
  integer,
  integer,
  integer
)
from public;

revoke execute
on function public.calculate_question_vault_demand(
  uuid,
  integer,
  integer,
  integer
)
from anon;

revoke execute
on function public.calculate_question_vault_demand(
  uuid,
  integer,
  integer,
  integer
)
from authenticated;

grant execute
on function public.calculate_question_vault_demand(
  uuid,
  integer,
  integer,
  integer
)
to service_role;


commit;