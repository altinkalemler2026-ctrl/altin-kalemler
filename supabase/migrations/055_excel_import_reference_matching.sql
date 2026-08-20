-- ============================================================
-- 055_excel_import_reference_matching.sql
-- Altın Kalemler
--
-- Excel import reference matching
--
-- Amaç:
-- 1. Excel ders adını public.subjects.id ile eşleştirmek.
-- 2. Legacy taxonomy kaydını:
--      grade + subject + legacy_code + topic_name
--    üzerinden eşleştirmek.
-- 3. Referans bulunamazsa kaydı sessizce normalized
--    kabul etmemek.
-- 4. SECURITY DEFINER güvenliğini korumak.
-- ============================================================

begin;

create or replace function public.normalize_excel_question_import_row(
  p_row_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
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

  v_subject_name text;
  v_topic_code text;
  v_topic_name text;
  v_test_code text;

  v_subject_id uuid;
  v_legacy_taxonomy_id uuid;

  v_subject_match_count integer := 0;
  v_taxonomy_match_count integer := 0;

  v_legacy_key text;

  v_issues jsonb := '[]'::jsonb;

  v_requires_ai boolean := false;
  v_requires_human boolean := false;

  v_has_blocking_error boolean := false;

  v_status text := 'normalized';
begin

  -- ==========================================================
  -- ROW
  -- ==========================================================

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


  -- ==========================================================
  -- DETERMINISTIC NORMALIZATION
  -- ==========================================================

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


  v_subject_name :=
    nullif(
      btrim(
        coalesce(
          v_row.raw_subject_name,
          ''
        )
      ),
      ''
    );


  v_topic_code :=
    nullif(
      btrim(
        coalesce(
          v_row.raw_topic_code,
          ''
        )
      ),
      ''
    );


  v_topic_name :=
    nullif(
      btrim(
        coalesce(
          v_row.raw_topic_name,
          ''
        )
      ),
      ''
    );


  v_test_code :=
    nullif(
      upper(
        btrim(
          coalesce(
            v_row.raw_test_code,
            ''
          )
        )
      ),
      ''
    );


  v_legacy_key :=
    public.build_legacy_question_key(
      v_test_code,
      v_question_number
    );


  -- ==========================================================
  -- BASIC VALIDATION
  -- ==========================================================

  if v_grade is null then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code',
          'INVALID_GRADE_LEVEL',

          'severity',
          'error',

          'raw_value',
          v_row.raw_grade_level
        )
      );

    v_requires_human := true;
    v_has_blocking_error := true;

  end if;


  if v_subject_name is null then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code',
          'MISSING_SUBJECT',

          'severity',
          'error'
        )
      );

    v_requires_human := true;
    v_has_blocking_error := true;

  end if;


  if v_test_code is null then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code',
          'MISSING_TEST_CODE',

          'severity',
          'error'
        )
      );

    v_requires_human := true;
    v_has_blocking_error := true;

  end if;


  if v_question_number is null then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code',
          'INVALID_QUESTION_NUMBER',

          'severity',
          'error',

          'raw_value',
          v_row.raw_question_number
        )
      );

    v_requires_human := true;
    v_has_blocking_error := true;

  end if;


  if v_answer is null then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code',
          'UNRESOLVED_ANSWER',

          'severity',
          'error',

          'raw_value',
          v_row.raw_answer
        )
      );

    v_requires_human := true;
    v_has_blocking_error := true;

  end if;


  -- ==========================================================
  -- SUBJECT MATCHING
  -- ==========================================================

  if v_subject_name is not null then

    select count(*)
    into v_subject_match_count
    from public.subjects s
    where s.is_active = true
      and lower(
        btrim(s.name)
      ) = lower(
        btrim(v_subject_name)
      );

    if v_subject_match_count = 1 then

      select s.id
      into v_subject_id
      from public.subjects s
      where s.is_active = true
        and lower(
          btrim(s.name)
        ) = lower(
          btrim(v_subject_name)
        )
      limit 1;

    elsif v_subject_match_count = 0 then

      v_issues :=
        v_issues
        ||
        jsonb_build_array(
          jsonb_build_object(
            'code',
            'SUBJECT_NOT_FOUND',

            'severity',
            'error',

            'subject_name',
            v_subject_name
          )
        );

      v_requires_human := true;

    else

      v_issues :=
        v_issues
        ||
        jsonb_build_array(
          jsonb_build_object(
            'code',
            'AMBIGUOUS_SUBJECT',

            'severity',
            'error',

            'subject_name',
            v_subject_name,

            'match_count',
            v_subject_match_count
          )
        );

      v_requires_human := true;

    end if;

  end if;


  -- ==========================================================
  -- LEGACY TAXONOMY MATCHING
  --
  -- Global legacy_code unique kabul edilmez.
  --
  -- Eşleşme:
  -- source + grade + subject + code + topic name
  -- ==========================================================

  if
    v_grade is not null
    and v_subject_name is not null
    and v_topic_code is not null
    and v_topic_name is not null
  then

    select count(*)
    into v_taxonomy_match_count
    from public.legacy_taxonomy lt
    where lt.is_active = true
      and lt.source_name =
        'legacy_excel_konu_kodu'
      and lt.grade_level =
        v_grade
      and lower(
        btrim(lt.subject_name)
      ) = lower(
        btrim(v_subject_name)
      )
      and btrim(
        lt.legacy_code
      ) = btrim(
        v_topic_code
      )
      and lower(
        btrim(lt.topic_name)
      ) = lower(
        btrim(v_topic_name)
      );

    if v_taxonomy_match_count = 1 then

      select lt.id
      into v_legacy_taxonomy_id
      from public.legacy_taxonomy lt
      where lt.is_active = true
        and lt.source_name =
          'legacy_excel_konu_kodu'
        and lt.grade_level =
          v_grade
        and lower(
          btrim(lt.subject_name)
        ) = lower(
          btrim(v_subject_name)
        )
        and btrim(
          lt.legacy_code
        ) = btrim(
          v_topic_code
        )
        and lower(
          btrim(lt.topic_name)
        ) = lower(
          btrim(v_topic_name)
        )
      limit 1;

    elsif v_taxonomy_match_count = 0 then

      v_issues :=
        v_issues
        ||
        jsonb_build_array(
          jsonb_build_object(
            'code',
            'LEGACY_TAXONOMY_NOT_FOUND',

            'severity',
            'warning',

            'grade_level',
            v_grade,

            'subject_name',
            v_subject_name,

            'legacy_code',
            v_topic_code,

            'topic_name',
            v_topic_name
          )
        );

      v_requires_human := true;

    else

      v_issues :=
        v_issues
        ||
        jsonb_build_array(
          jsonb_build_object(
            'code',
            'AMBIGUOUS_LEGACY_TAXONOMY',

            'severity',
            'warning',

            'grade_level',
            v_grade,

            'subject_name',
            v_subject_name,

            'legacy_code',
            v_topic_code,

            'topic_name',
            v_topic_name,

            'match_count',
            v_taxonomy_match_count
          )
        );

      v_requires_human := true;

    end if;

  else

    if
      v_grade is not null
      and v_subject_name is not null
      and (
        v_topic_code is null
        or v_topic_name is null
      )
    then

      v_issues :=
        v_issues
        ||
        jsonb_build_array(
          jsonb_build_object(
            'code',
            'INCOMPLETE_LEGACY_TAXONOMY_DATA',

            'severity',
            'warning',

            'legacy_code',
            v_topic_code,

            'topic_name',
            v_topic_name
          )
        );

      v_requires_human := true;

    end if;

  end if;


  -- ==========================================================
  -- LEGACY FIELD VALIDATION
  -- ==========================================================

  if
    nullif(
      btrim(
        coalesce(
          v_row.raw_difficulty,
          ''
        )
      ),
      ''
    ) is not null
    and v_difficulty is null
  then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code',
          'UNKNOWN_DIFFICULTY',

          'severity',
          'warning',

          'raw_value',
          v_row.raw_difficulty
        )
      );

    v_requires_ai := true;

  end if;


  if
    nullif(
      btrim(
        coalesce(
          v_row.raw_quality_level,
          ''
        )
      ),
      ''
    ) is not null
    and v_quality is null
  then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code',
          'UNKNOWN_QUALITY_LEVEL',

          'severity',
          'warning',

          'raw_value',
          v_row.raw_quality_level
        )
      );

    v_requires_ai := true;

  end if;


  if
    nullif(
      btrim(
        coalesce(
          v_row.raw_cognitive_type,
          ''
        )
      ),
      ''
    ) is not null
    and v_cognitive is null
  then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code',
          'UNKNOWN_COGNITIVE_TYPE',

          'severity',
          'warning',

          'raw_value',
          v_row.raw_cognitive_type
        )
      );

    v_requires_ai := true;

  end if;


  if
    nullif(
      btrim(
        coalesce(
          v_row.raw_new_generation,
          ''
        )
      ),
      ''
    ) is not null
    and v_new_generation is null
  then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code',
          'UNKNOWN_NEW_GENERATION_FLAG',

          'severity',
          'warning',

          'raw_value',
          v_row.raw_new_generation
        )
      );

    v_requires_ai := true;

  end if;


  if
    nullif(
      btrim(
        coalesce(
          v_row.raw_exam_track,
          ''
        )
      ),
      ''
    ) is not null
    and v_exam_track is null
  then

    v_issues :=
      v_issues
      ||
      jsonb_build_array(
        jsonb_build_object(
          'code',
          'UNKNOWN_EXAM_TRACK',

          'severity',
          'warning',

          'raw_value',
          v_row.raw_exam_track
        )
      );

    v_requires_human := true;
    v_has_blocking_error := true;

  end if;


  -- ==========================================================
  -- FINAL STATUS
  --
  -- blocking error:
  --   quarantined
  --
  -- AI veya insan incelemesi gereken ama temel kimliği
  -- kullanılabilir kayıt:
  --   needs_review
  --
  -- hiçbir sorun yok:
  --   normalized
  -- ==========================================================

  if v_has_blocking_error = true then

    v_status :=
      'quarantined';

  elsif
    v_requires_ai = true
    or v_requires_human = true
  then

    v_status :=
      'needs_review';

  else

    v_status :=
      'normalized';

  end if;


  -- ==========================================================
  -- SAVE
  -- ==========================================================

  update public.excel_question_import_rows
  set
    normalized_exam_track =
      v_exam_track,

    normalized_grade_level =
      v_grade,

    normalized_subject_name =
      v_subject_name,

    subject_id =
      v_subject_id,

    normalized_topic_code =
      v_topic_code,

    normalized_topic_name =
      v_topic_name,

    legacy_taxonomy_id =
      v_legacy_taxonomy_id,

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
          coalesce(
            raw_primary_question_type,
            ''
          )
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


  -- ==========================================================
  -- RESULT
  -- ==========================================================

  return jsonb_build_object(
    'row_id',
    p_row_id,

    'status',
    v_status,

    'legacy_question_key',
    v_legacy_key,

    'subject_id',
    v_subject_id,

    'legacy_taxonomy_id',
    v_legacy_taxonomy_id,

    'requires_ai_review',
    v_requires_ai,

    'requires_human_review',
    v_requires_human,

    'issues',
    v_issues
  );

end;
$function$;


-- ============================================================
-- SECURITY
-- ============================================================

revoke execute
on function public.normalize_excel_question_import_row(uuid)
from public;

revoke execute
on function public.normalize_excel_question_import_row(uuid)
from anon;

revoke execute
on function public.normalize_excel_question_import_row(uuid)
from authenticated;

grant execute
on function public.normalize_excel_question_import_row(uuid)
to service_role;


commit;