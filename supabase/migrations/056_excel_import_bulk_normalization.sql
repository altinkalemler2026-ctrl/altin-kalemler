-- ============================================================
-- 056_excel_import_bulk_normalization.sql
-- Altın Kalemler
--
-- Excel import bulk normalization
--
-- Amaç:
-- 1. Her soru için ayrı HTTP/RPC çağrısını kaldırmak.
-- 2. Bir batch içindeki pending satırları DB içinde toplu işlemek.
-- 3. Güvenliği service_role ile sınırlı tutmak.
-- ============================================================

begin;


create or replace function public.normalize_excel_question_import_batch(
  p_batch_id uuid,
  p_limit integer default 1000
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_row record;

  v_requested integer := 0;
  v_processed integer := 0;

  v_normalized integer := 0;
  v_needs_review integer := 0;
  v_quarantined integer := 0;

  v_remaining integer := 0;

  v_result jsonb;
  v_status text;
begin

  if p_batch_id is null then
    raise exception
      'p_batch_id boş olamaz.';
  end if;


  if p_limit is null
     or p_limit < 1
     or p_limit > 5000
  then
    raise exception
      'p_limit 1 ile 5000 arasında olmalıdır.';
  end if;


  if not exists (
    select 1
    from public.import_batches b
    where b.id = p_batch_id
  ) then
    raise exception
      'Import batch bulunamadı: %',
      p_batch_id;
  end if;


  -- ==========================================================
  -- Yalnız henüz normalize edilmemiş kayıtları seç.
  -- ==========================================================

  select count(*)
  into v_requested
  from (
    select r.id
    from public.excel_question_import_rows r
    where r.import_batch_id = p_batch_id
      and r.normalization_status = 'pending'
    order by r.source_row_number
    limit p_limit
  ) q;


  -- ==========================================================
  -- Aynı DB bağlantısı içinde row normalizer'ı çalıştır.
  --
  -- Burada HTTP çağrısı yok.
  -- ==========================================================

  for v_row in
    select r.id
    from public.excel_question_import_rows r
    where r.import_batch_id = p_batch_id
      and r.normalization_status = 'pending'
    order by r.source_row_number
    limit p_limit
  loop

    v_result :=
      public.normalize_excel_question_import_row(
        v_row.id
      );

    v_status :=
      v_result ->> 'status';

    v_processed :=
      v_processed + 1;


    if v_status = 'normalized' then

      v_normalized :=
        v_normalized + 1;

    elsif v_status = 'needs_review' then

      v_needs_review :=
        v_needs_review + 1;

    elsif v_status = 'quarantined' then

      v_quarantined :=
        v_quarantined + 1;

    end if;

  end loop;


  -- ==========================================================
  -- Kalan pending kayıt
  -- ==========================================================

  select count(*)
  into v_remaining
  from public.excel_question_import_rows r
  where r.import_batch_id = p_batch_id
    and r.normalization_status = 'pending';


  return jsonb_build_object(
    'batch_id',
    p_batch_id,

    'requested',
    v_requested,

    'processed',
    v_processed,

    'normalized',
    v_normalized,

    'needs_review',
    v_needs_review,

    'quarantined',
    v_quarantined,

    'remaining',
    v_remaining
  );

end;
$function$;


-- ============================================================
-- SECURITY
-- ============================================================

revoke execute
on function public.normalize_excel_question_import_batch(
  uuid,
  integer
)
from public;

revoke execute
on function public.normalize_excel_question_import_batch(
  uuid,
  integer
)
from anon;

revoke execute
on function public.normalize_excel_question_import_batch(
  uuid,
  integer
)
from authenticated;

grant execute
on function public.normalize_excel_question_import_batch(
  uuid,
  integer
)
to service_role;


commit;