-- ============================================================
-- 052_excel_question_import_pipeline.sql
-- Altın Kalemler
--
-- Legacy Excel soru verileri için:
--
-- RAW ROW
--   ↓
-- deterministic normalization
--   ↓
-- valid / quarantine
--   ↓
-- ai_question_staging
--
-- AI basit veri temizliği yapmaz.
-- AI yalnız anlam gerektiren belirsizliklerde devreye girer.
-- ============================================================

begin;


-- ============================================================
-- 1. EXCEL QUESTION IMPORT ROWS
-- ============================================================

create table if not exists public.excel_question_import_rows (
  id uuid primary key default gen_random_uuid(),

  import_batch_id uuid not null
    references public.import_batches(id)
    on delete cascade,

  source_row_number integer not null
    check (source_row_number > 0),

  -- ----------------------------------------------------------
  -- Excel ham değerleri
  -- ----------------------------------------------------------

  raw_data jsonb not null default '{}'::jsonb,

  raw_exam_track text,
  raw_grade_level text,

  raw_subject_name text,

  raw_topic_code text,
  raw_topic_name text,

  raw_test_code text,
  raw_question_number text,

  raw_answer text,
  raw_difficulty text,
  raw_quality_level text,
  raw_cognitive_type text,

  raw_primary_question_type text,
  raw_secondary_question_type text,

  raw_new_generation text,

  raw_link text,

  -- ----------------------------------------------------------
  -- Normalize edilmiş değerler
  -- ----------------------------------------------------------

  legacy_question_key text,

  normalized_exam_track text
    check (
      normalized_exam_track is null
      or normalized_exam_track in ('TYT', 'AYT')
    ),

  normalized_grade_level smallint
    check (
      normalized_grade_level is null
      or normalized_grade_level between 1 and 12
    ),

  normalized_subject_name text,

  normalized_topic_code text,
  normalized_topic_name text,

  normalized_test_code text,

  normalized_question_number integer
    check (
      normalized_question_number is null
      or normalized_question_number > 0
    ),

  normalized_answer text
    check (
      normalized_answer is null
      or normalized_answer in ('A', 'B', 'C', 'D', 'E')
    ),

  normalized_difficulty text
    check (
      normalized_difficulty is null
      or normalized_difficulty in (
        'easy',
        'medium',
        'hard'
      )
    ),

  normalized_quality_level text
    check (
      normalized_quality_level is null
      or normalized_quality_level in (
        'low',
        'medium',
        'high'
      )
    ),

  normalized_cognitive_type text
    check (
      normalized_cognitive_type is null
      or normalized_cognitive_type in (
        'learning',
        'comprehension',
        'application'
      )
    ),

  normalized_primary_question_type text,
  normalized_secondary_question_type text,

  normalized_is_new_generation boolean,

  -- ----------------------------------------------------------
  -- DB eşleştirmeleri
  -- ----------------------------------------------------------

  subject_id uuid
    references public.subjects(id)
    on delete set null,

  legacy_taxonomy_id uuid
    references public.legacy_taxonomy(id)
    on delete set null,

  -- ----------------------------------------------------------
  -- Validation / quarantine
  -- ----------------------------------------------------------

  normalization_status text not null default 'pending'
    check (
      normalization_status in (
        'pending',
        'normalized',
        'needs_review',
        'quarantined',
        'staged',
        'ignored'
      )
    ),

  normalization_issues jsonb not null default '[]'::jsonb,

  requires_ai_review boolean not null default false,
  requires_human_review boolean not null default false,

  -- ----------------------------------------------------------
  -- Staging bağlantısı
  -- ----------------------------------------------------------

  staging_question_id uuid
    references public.ai_question_staging(id)
    on delete set null,

  normalized_at timestamptz,
  staged_at timestamptz,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(import_batch_id, source_row_number)
);


create index if not exists idx_excel_import_rows_batch
  on public.excel_question_import_rows(import_batch_id);

create index if not exists idx_excel_import_rows_status
  on public.excel_question_import_rows(normalization_status);

create index if not exists idx_excel_import_rows_legacy_key
  on public.excel_question_import_rows(legacy_question_key);

create index if not exists idx_excel_import_rows_subject_grade
  on public.excel_question_import_rows(
    normalized_grade_level,
    subject_id
  );

create index if not exists idx_excel_import_rows_taxonomy
  on public.excel_question_import_rows(legacy_taxonomy_id);


-- ============================================================
-- 2. UPDATED_AT
-- ============================================================

drop trigger if exists trg_excel_question_import_rows_updated_at
  on public.excel_question_import_rows;

create trigger trg_excel_question_import_rows_updated_at
before update on public.excel_question_import_rows
for each row
execute function public.set_question_vault_updated_at();


-- ============================================================
-- 3. LEGACY QUESTION KEY
--
-- Örnek:
-- test_code = 2010023NFT1
-- question_number = 7
--
-- sonuç:
-- 2010023NFT1:7
-- ============================================================

create or replace function public.build_legacy_question_key(
  p_test_code text,
  p_question_number integer
)
returns text
language sql
immutable
security invoker
as $$
  select
    case
      when nullif(btrim(p_test_code), '') is null
        or p_question_number is null
        or p_question_number <= 0
      then null

      else
        upper(btrim(p_test_code))
        || ':'
        || p_question_number::text
    end;
$$;


-- ============================================================
-- 4. EXAM TRACK NORMALIZER
--
-- Excel'deki eski "SORU ID" alanında görülen
-- TYT / AYT değerleri için.
-- ============================================================

create or replace function public.normalize_excel_exam_track(
  p_value text
)
returns text
language sql
immutable
security invoker
as $$
  select
    case upper(btrim(coalesce(p_value, '')))
      when 'TYT' then 'TYT'
      when 'AYT' then 'AYT'
      else null
    end;
$$;


-- ============================================================
-- 5. ANSWER NORMALIZER
-- ============================================================

create or replace function public.normalize_excel_answer(
  p_value text
)
returns text
language sql
immutable
security invoker
as $$
  select
    case upper(btrim(coalesce(p_value, '')))
      when 'A' then 'A'
      when 'B' then 'B'
      when 'C' then 'C'
      when 'D' then 'D'
      when 'E' then 'E'
      else null
    end;
$$;


-- ============================================================
-- 6. DIFFICULTY NORMALIZER
--
-- Legacy:
-- 1 = Kolay
-- 2 = Orta
-- 3 = Zor
-- ============================================================

create or replace function public.normalize_excel_difficulty(
  p_value text
)
returns text
language sql
immutable
security invoker
as $$
  select
    case lower(btrim(coalesce(p_value, '')))

      when '1' then 'easy'
      when 'kolay' then 'easy'
      when 'easy' then 'easy'

      when '2' then 'medium'
      when 'orta' then 'medium'
      when 'medium' then 'medium'

      when '3' then 'hard'
      when 'zor' then 'hard'
      when 'hard' then 'hard'

      else null
    end;
$$;


-- ============================================================
-- 7. QUALITY NORMALIZER
--
-- Legacy:
-- 1 = Kalitesiz
-- 2 = Orta
-- 3 = Kaliteli
-- ============================================================

create or replace function public.normalize_excel_quality(
  p_value text
)
returns text
language sql
immutable
security invoker
as $$
  select
    case lower(btrim(coalesce(p_value, '')))

      when '1' then 'low'
      when 'kalitesiz' then 'low'
      when 'low' then 'low'

      when '2' then 'medium'
      when 'orta' then 'medium'
      when 'medium' then 'medium'

      when '3' then 'high'
      when 'kaliteli' then 'high'
      when 'high' then 'high'

      else null
    end;
$$;


-- ============================================================
-- 8. COGNITIVE TYPE NORMALIZER
--
-- Legacy:
-- 1 = Öğrenme
-- 2 = Kavrama
-- 3 = Uygulama
-- ============================================================

create or replace function public.normalize_excel_cognitive_type(
  p_value text
)
returns text
language sql
immutable
security invoker
as $$
  select
    case lower(btrim(coalesce(p_value, '')))

      when '1' then 'learning'
      when 'öğrenme' then 'learning'
      when 'ogrenme' then 'learning'
      when 'learning' then 'learning'

      when '2' then 'comprehension'
      when 'kavrama' then 'comprehension'
      when 'comprehension' then 'comprehension'

      when '3' then 'application'
      when 'uygulama' then 'application'
      when 'application' then 'application'

      else null
    end;
$$;


-- ============================================================
-- 9. NEW GENERATION NORMALIZER
--
-- Legacy:
-- E / e = true
-- H / h = false
-- boş / bilinmeyen = null
-- ============================================================

create or replace function public.normalize_excel_new_generation(
  p_value text
)
returns boolean
language sql
immutable
security invoker
as $$
  select
    case upper(btrim(coalesce(p_value, '')))

      when 'E' then true
      when 'EVET' then true
      when 'TRUE' then true
      when '1' then true

      when 'H' then false
      when 'HAYIR' then false
      when 'FALSE' then false
      when '0' then false

      else null
    end;
$$;


-- ============================================================
-- 10. SECONDARY QUESTION TYPE NORMALIZER
--
-- Legacy Excel'de:
-- 0 = ikinci tip yok
--
-- Bunu DB'de 0 olarak saklamıyoruz.
-- ============================================================

create or replace function public.normalize_excel_secondary_question_type(
  p_value text
)
returns text
language sql
immutable
security invoker
as $$
  select
    case
      when nullif(btrim(coalesce(p_value, '')), '') is null
        then null

      when btrim(p_value) = '0'
        then null

      else btrim(p_value)
    end;
$$;


-- ============================================================
-- 11. GRADE NORMALIZER
-- ============================================================

create or replace function public.normalize_excel_grade_level(
  p_value text
)
returns smallint
language plpgsql
immutable
security invoker
as $$
declare
  v_grade integer;
begin

  if nullif(btrim(coalesce(p_value, '')), '') is null then
    return null;
  end if;

  if btrim(p_value) !~ '^[0-9]+$' then
    return null;
  end if;

  v_grade := btrim(p_value)::integer;

  if v_grade < 1 or v_grade > 12 then
    return null;
  end if;

  return v_grade::smallint;
end;
$$;


-- ============================================================
-- 12. POSITIVE INTEGER NORMALIZER
--
-- Soru no vb.
-- ============================================================

create or replace function public.normalize_excel_positive_integer(
  p_value text
)
returns integer
language plpgsql
immutable
security invoker
as $$
declare
  v_number integer;
begin

  if nullif(btrim(coalesce(p_value, '')), '') is null then
    return null;
  end if;

  if btrim(p_value) !~ '^[0-9]+$' then
    return null;
  end if;

  v_number := btrim(p_value)::integer;

  if v_number <= 0 then
    return null;
  end if;

  return v_number;
end;
$$;


-- ============================================================
-- 13. TEK SATIRI NORMALIZE ET
--
-- Bu fonksiyon AI çağırmaz.
-- Yalnız deterministic dönüşüm yapar.
-- ============================================================

create or replace function public.normalize_excel_question_import_row(
  p_row_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.excel_question_import_rows%rowtype;

  v_grade smallint;
  v_question_number integer;

  v_exam_track text;
  v_answer text;
  v_difficulty text;
  v_quality text;
  v_cognitive text;
  v_new_generation boolean;
  v_secondary_type text;

  v_test_code text;

  v_legacy_key text;

  v_issues jsonb := '[]'::jsonb;

  v_requires_ai boolean := false;
  v_requires_human boolean := false;

  v_status text := 'normalized';
begin

  select *
  into v_row
  from public.excel_question_import_rows
  where id = p_row_id
  for update;

  if not found then
    raise exception
      'Excel import row bulunamadı: %',
      p_row_id;
  end if;


  -- ----------------------------------------------------------
  -- Deterministic normalize
  -- ----------------------------------------------------------

  v_grade :=
    public.normalize_excel_grade_level(
      v_row.raw_grade_level
    );

  v_question_number :=
    public.normalize_excel_positive_integer(
      v_row.raw_question_number
    );

  v_exam_track :=
    public.normalize_excel_exam_track(
      v_row.raw_exam_track
    );

  v_answer :=
    public.normalize_excel_answer(
      v_row.raw_answer
    );

  v_difficulty :=
    public.normalize_excel_difficulty(
      v_row.raw_difficulty
    );

  v_quality :=
    public.normalize_excel_quality(
      v_row.raw_quality_level
    );

  v_cognitive :=
    public.normalize_excel_cognitive_type(
      v_row.raw_cognitive_type
    );

  v_new_generation :=
    public.normalize_excel_new_generation(
      v_row.raw_new_generation
    );

  v_secondary_type :=
    public.normalize_excel_secondary_question_type(
      v_row.raw_secondary_question_type
    );

  v_test_code :=
    nullif(
      upper(
        btrim(
          coalesce(v_row.raw_test_code, '')
        )
      ),
      ''
    );

  v_legacy_key :=
    public.build_legacy_question_key(
      v_test_code,
      v_question_number
    );


  -- ----------------------------------------------------------
  -- Validation issues
  -- ----------------------------------------------------------

  if v_grade is null then
    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code', 'INVALID_GRADE_LEVEL',
          'severity', 'error',
          'raw_value', v_row.raw_grade_level
        )
      );

    v_requires_human := true;
  end if;


  if nullif(btrim(coalesce(v_row.raw_subject_name, '')), '') is null then
    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code', 'MISSING_SUBJECT',
          'severity', 'error'
        )
      );

    v_requires_human := true;
  end if;


  if v_test_code is null then
    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code', 'MISSING_TEST_CODE',
          'severity', 'error'
        )
      );

    v_requires_human := true;
  end if;


  if v_question_number is null then
    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code', 'INVALID_QUESTION_NUMBER',
          'severity', 'error',
          'raw_value', v_row.raw_question_number
        )
      );

    v_requires_human := true;
  end if;


  if v_answer is null then
    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code', 'UNRESOLVED_ANSWER',
          'severity', 'error',
          'raw_value', v_row.raw_answer
        )
      );

    v_requires_human := true;
  end if;


  if
    nullif(btrim(coalesce(v_row.raw_difficulty, '')), '') is not null
    and v_difficulty is null
  then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code', 'UNKNOWN_DIFFICULTY',
          'severity', 'warning',
          'raw_value', v_row.raw_difficulty
        )
      );

    v_requires_ai := true;
  end if;


  if
    nullif(btrim(coalesce(v_row.raw_quality_level, '')), '') is not null
    and v_quality is null
  then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code', 'UNKNOWN_QUALITY_LEVEL',
          'severity', 'warning',
          'raw_value', v_row.raw_quality_level
        )
      );

    v_requires_ai := true;
  end if;


  if
    nullif(btrim(coalesce(v_row.raw_cognitive_type, '')), '') is not null
    and v_cognitive is null
  then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code', 'UNKNOWN_COGNITIVE_TYPE',
          'severity', 'warning',
          'raw_value', v_row.raw_cognitive_type
        )
      );

    v_requires_ai := true;
  end if;


  if
    nullif(btrim(coalesce(v_row.raw_new_generation, '')), '') is not null
    and v_new_generation is null
  then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code', 'UNKNOWN_NEW_GENERATION_FLAG',
          'severity', 'warning',
          'raw_value', v_row.raw_new_generation
        )
      );

    v_requires_ai := true;
  end if;


  if
    nullif(btrim(coalesce(v_row.raw_exam_track, '')), '') is not null
    and v_exam_track is null
  then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code', 'UNKNOWN_EXAM_TRACK',
          'severity', 'warning',
          'raw_value', v_row.raw_exam_track
        )
      );

    v_requires_human := true;
  end if;


  -- ----------------------------------------------------------
  -- Final status
  -- ----------------------------------------------------------

  if v_requires_human = true then
    v_status := 'quarantined';

  elsif v_requires_ai = true then
    v_status := 'needs_review';

  else
    v_status := 'normalized';
  end if;


  -- ----------------------------------------------------------
  -- Save
  -- ----------------------------------------------------------

  update public.excel_question_import_rows
  set
    normalized_exam_track =
      v_exam_track,

    normalized_grade_level =
      v_grade,

    normalized_subject_name =
      nullif(
        btrim(
          coalesce(raw_subject_name, '')
        ),
        ''
      ),

    normalized_topic_code =
      nullif(
        btrim(
          coalesce(raw_topic_code, '')
        ),
        ''
      ),

    normalized_topic_name =
      nullif(
        btrim(
          coalesce(raw_topic_name, '')
        ),
        ''
      ),

    normalized_test_code =
      v_test_code,

    normalized_question_number =
      v_question_number,

    normalized_answer =
      v_answer,

    normalized_difficulty =
      v_difficulty,

    normalized_quality_level =
      v_quality,

    normalized_cognitive_type =
      v_cognitive,

    normalized_primary_question_type =
      nullif(
        btrim(
          coalesce(raw_primary_question_type, '')
        ),
        ''
      ),

    normalized_secondary_question_type =
      v_secondary_type,

    normalized_is_new_generation =
      v_new_generation,

    legacy_question_key =
      v_legacy_key,

    normalization_status =
      v_status,

    normalization_issues =
      v_issues,

    requires_ai_review =
      v_requires_ai,

    requires_human_review =
      v_requires_human,

    normalized_at =
      now(),

    updated_at =
      now()

  where id = p_row_id;


  return jsonb_build_object(
    'row_id', p_row_id,

    'status', v_status,

    'legacy_question_key',
      v_legacy_key,

    'requires_ai_review',
      v_requires_ai,

    'requires_human_review',
      v_requires_human,

    'issues',
      v_issues
  );
end;
$$;


-- ============================================================
-- 14. IMPORT BATCH SUMMARY
-- ============================================================

create or replace function public.get_excel_import_batch_summary(
  p_import_batch_id uuid
)
returns table (
  import_batch_id uuid,

  total_rows bigint,

  pending_rows bigint,
  normalized_rows bigint,
  needs_review_rows bigint,
  quarantined_rows bigint,
  staged_rows bigint,
  ignored_rows bigint,

  requires_ai_review_rows bigint,
  requires_human_review_rows bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    p_import_batch_id,

    count(*),

    count(*)
      filter (
        where normalization_status = 'pending'
      ),

    count(*)
      filter (
        where normalization_status = 'normalized'
      ),

    count(*)
      filter (
        where normalization_status = 'needs_review'
      ),

    count(*)
      filter (
        where normalization_status = 'quarantined'
      ),

    count(*)
      filter (
        where normalization_status = 'staged'
      ),

    count(*)
      filter (
        where normalization_status = 'ignored'
      ),

    count(*)
      filter (
        where requires_ai_review = true
      ),

    count(*)
      filter (
        where requires_human_review = true
      )

  from public.excel_question_import_rows
  where import_batch_id = p_import_batch_id;
$$;


-- ============================================================
-- 15. RLS
-- ============================================================

alter table public.excel_question_import_rows
  enable row level security;


-- ============================================================
-- 16. SERVICE ROLE
-- ============================================================

grant select, insert, update, delete
on public.excel_question_import_rows
to service_role;


grant execute
on function public.build_legacy_question_key(
  text,
  integer
)
to service_role;


grant execute
on function public.normalize_excel_exam_track(text)
to service_role;


grant execute
on function public.normalize_excel_answer(text)
to service_role;


grant execute
on function public.normalize_excel_difficulty(text)
to service_role;


grant execute
on function public.normalize_excel_quality(text)
to service_role;


grant execute
on function public.normalize_excel_cognitive_type(text)
to service_role;


grant execute
on function public.normalize_excel_new_generation(text)
to service_role;


grant execute
on function public.normalize_excel_secondary_question_type(text)
to service_role;


grant execute
on function public.normalize_excel_grade_level(text)
to service_role;


grant execute
on function public.normalize_excel_positive_integer(text)
to service_role;


grant execute
on function public.normalize_excel_question_import_row(uuid)
to service_role;


grant execute
on function public.get_excel_import_batch_summary(uuid)
to service_role;


commit;