-- ============================================================
-- 049_seed_math_grade12_vaults.sql
-- Altın Kalemler
-- 12. Sınıf Matematik / Kolay soru kasaları örnek gerçek yapı
-- ============================================================

begin;

-- Matematik subject UUID:
-- 430903f3-527e-4e12-b7e8-ac0afdb784aa


-- ============================================================
-- 1. ANA KASA
-- 12. Sınıf Matematik
-- ============================================================

insert into public.question_vaults (
  vault_code,
  name,
  description,
  vault_type,
  parent_vault_id,
  grade_level,
  subject_id,
  difficulty_level,
  section_code,
  section_order,
  is_dynamic,
  is_active,
  allow_practice,
  allow_competition,
  allow_one_v_one,
  allow_exam,
  manual_question_assignment_allowed,
  metadata
)
values (
  'TR-G12-MATH',
  '12. Sınıf Matematik',
  '12. sınıf Matematik soru kasalarının ana kök kasası.',
  'academic',
  null,
  12,
  '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
  'mixed',
  null,
  null,
  false,
  true,
  false,
  false,
  false,
  false,
  true,
  jsonb_build_object(
    'country_code', 'TR',
    'seed_version', '049',
    'legacy_design_source', 'soru_paneli'
  )
)
on conflict (vault_code) do update
set
  name = excluded.name,
  description = excluded.description,
  is_active = true,
  updated_at = now();


-- ============================================================
-- 2. KOLAY SEVİYE ANA KASASI
-- ============================================================

insert into public.question_vaults (
  vault_code,
  name,
  description,
  vault_type,
  parent_vault_id,
  grade_level,
  subject_id,
  difficulty_level,
  section_code,
  section_order,
  is_dynamic,
  is_active,
  allow_practice,
  allow_competition,
  allow_one_v_one,
  allow_exam,
  manual_question_assignment_allowed,
  metadata
)
select
  'TR-G12-MATH-EASY',
  '12. Sınıf Matematik - Kolay',
  '12. sınıf Matematik kolay seviye soru kasalarının ana kasası.',
  'academic',
  parent.id,
  12,
  '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
  'easy',
  'EASY',
  1,
  false,
  true,
  true,
  false,
  false,
  false,
  true,
  jsonb_build_object(
    'country_code', 'TR',
    'seed_version', '049'
  )
from public.question_vaults parent
where parent.vault_code = 'TR-G12-MATH'
on conflict (vault_code) do update
set
  parent_vault_id = excluded.parent_vault_id,
  name = excluded.name,
  description = excluded.description,
  is_active = true,
  updated_at = now();


-- ============================================================
-- 3. KISIMLAR
-- Kısım 1 = konular 1-3
-- Kısım 2 = konular 4-6
-- Kısım 3 = konular 7-10
-- Kısım 4 = konular 11-13
--
-- Buradaki konu numaraları legacy tasarım mantığıdır.
-- Gerçek canonical MEB topic mapping daha sonra bağlanacaktır.
-- ============================================================

insert into public.question_vaults (
  vault_code,
  name,
  description,
  vault_type,
  parent_vault_id,
  grade_level,
  subject_id,
  difficulty_level,
  section_code,
  section_order,
  is_dynamic,
  is_active,
  allow_practice,
  allow_competition,
  allow_one_v_one,
  allow_exam,
  manual_question_assignment_allowed,
  metadata
)
select
  values_to_insert.vault_code,
  values_to_insert.name,
  values_to_insert.description,
  'academic',
  parent.id,
  12,
  '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
  'easy',
  values_to_insert.section_code,
  values_to_insert.section_order,
  false,
  true,
  true,
  false,
  false,
  false,
  true,
  values_to_insert.metadata
from public.question_vaults parent
cross join (
  values
    (
      'TR-G12-MATH-EASY-P1',
      '12. Sınıf Matematik - Kolay - Kısım 1',
      'Legacy tasarımda ilk üç konuyu kapsayan kolay seviye bölüm.',
      'P1',
      1,
      jsonb_build_object(
        'legacy_topic_range', '1-3',
        'seed_version', '049'
      )
    ),
    (
      'TR-G12-MATH-EASY-P2',
      '12. Sınıf Matematik - Kolay - Kısım 2',
      'Legacy tasarımda 4-6. konuları kapsayan kolay seviye bölüm.',
      'P2',
      2,
      jsonb_build_object(
        'legacy_topic_range', '4-6',
        'seed_version', '049'
      )
    ),
    (
      'TR-G12-MATH-EASY-P3',
      '12. Sınıf Matematik - Kolay - Kısım 3',
      'Legacy tasarımda 7-10. konuları kapsayan kolay seviye bölüm.',
      'P3',
      3,
      jsonb_build_object(
        'legacy_topic_range', '7-10',
        'seed_version', '049'
      )
    ),
    (
      'TR-G12-MATH-EASY-P4',
      '12. Sınıf Matematik - Kolay - Kısım 4',
      'Legacy tasarımda 11-13. konuları kapsayan kolay seviye bölüm.',
      'P4',
      4,
      jsonb_build_object(
        'legacy_topic_range', '11-13',
        'seed_version', '049'
      )
    )
) as values_to_insert(
  vault_code,
  name,
  description,
  section_code,
  section_order,
  metadata
)
where parent.vault_code = 'TR-G12-MATH-EASY'
on conflict (vault_code) do update
set
  parent_vault_id = excluded.parent_vault_id,
  name = excluded.name,
  description = excluded.description,
  section_code = excluded.section_code,
  section_order = excluded.section_order,
  is_active = true,
  updated_at = now();


-- ============================================================
-- 4. KISIM 1 ALT KASALARI
--
-- 0-12 hafta:  A1, A2, A3
-- 12-24 hafta: A4, A5, A6
-- 24-36 hafta: A7, A8, A9
-- 36-48 hafta: A10, A11, A12
--
-- Soru sayıları tasarım hedefi olarak metadata'da tutulur.
-- ============================================================

insert into public.question_vaults (
  vault_code,
  name,
  description,
  vault_type,
  parent_vault_id,
  grade_level,
  subject_id,
  difficulty_level,
  section_code,
  section_order,
  is_dynamic,
  is_active,
  allow_practice,
  allow_competition,
  allow_one_v_one,
  allow_exam,
  manual_question_assignment_allowed,
  metadata
)
select
  'TR-G12-MATH-EASY-P1-' || x.code,
  '12. Matematik Kolay Kısım 1 - ' || x.code,
  '12. sınıf Matematik kolay Kısım 1 alt soru kasası ' || x.code || '.',
  'academic',
  parent.id,
  12,
  '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
  'easy',
  x.code,
  x.sort_order,
  false,
  true,
  true,
  false,
  false,
  false,
  true,
  jsonb_build_object(
    'legacy_vault_code', x.code,
    'target_question_count', x.target_count,
    'activation_start_week', x.start_week,
    'activation_end_week', x.end_week,
    'seed_version', '049'
  )
from public.question_vaults parent
cross join (
  values
    ('A1',  1, 300,  0, 12),
    ('A2',  2, 300,  0, 12),
    ('A3',  3, 300,  0, 12),

    ('A4',  4, 200, 12, 24),
    ('A5',  5, 200, 12, 24),
    ('A6',  6, 200, 12, 24),

    ('A7',  7, 100, 24, 36),
    ('A8',  8, 100, 24, 36),
    ('A9',  9, 100, 24, 36),

    ('A10', 10, 50, 36, 48),
    ('A11', 11, 50, 36, 48),
    ('A12', 12, 50, 36, 48)
) as x(
  code,
  sort_order,
  target_count,
  start_week,
  end_week
)
where parent.vault_code = 'TR-G12-MATH-EASY-P1'
on conflict (vault_code) do update
set
  parent_vault_id = excluded.parent_vault_id,
  metadata = excluded.metadata,
  is_active = true,
  updated_at = now();


-- ============================================================
-- 5. KISIM 2 ALT KASALARI
--
-- Tasarım:
-- B1 B2 B3 = yaklaşık 400
-- B4 B5 B6 = yaklaşık 300
-- B7 B8 B9 = yaklaşık 200
-- ============================================================

insert into public.question_vaults (
  vault_code,
  name,
  description,
  vault_type,
  parent_vault_id,
  grade_level,
  subject_id,
  difficulty_level,
  section_code,
  section_order,
  is_dynamic,
  is_active,
  allow_practice,
  allow_competition,
  allow_one_v_one,
  allow_exam,
  manual_question_assignment_allowed,
  metadata
)
select
  'TR-G12-MATH-EASY-P2-' || x.code,
  '12. Matematik Kolay Kısım 2 - ' || x.code,
  '12. sınıf Matematik kolay Kısım 2 alt soru kasası ' || x.code || '.',
  'academic',
  parent.id,
  12,
  '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
  'easy',
  x.code,
  x.sort_order,
  false,
  true,
  true,
  false,
  false,
  false,
  true,
  jsonb_build_object(
    'legacy_vault_code', x.code,
    'target_question_count', x.target_count,
    'activation_start_week', x.start_week,
    'activation_end_week', x.end_week,
    'seed_version', '049'
  )
from public.question_vaults parent
cross join (
  values
    ('B1', 1, 400, 12, 24),
    ('B2', 2, 400, 12, 24),
    ('B3', 3, 400, 12, 24),

    ('B4', 4, 300, 24, 36),
    ('B5', 5, 300, 24, 36),
    ('B6', 6, 300, 24, 36),

    ('B7', 7, 200, 36, 48),
    ('B8', 8, 200, 36, 48),
    ('B9', 9, 200, 36, 48)
) as x(
  code,
  sort_order,
  target_count,
  start_week,
  end_week
)
where parent.vault_code = 'TR-G12-MATH-EASY-P2'
on conflict (vault_code) do update
set
  parent_vault_id = excluded.parent_vault_id,
  metadata = excluded.metadata,
  is_active = true,
  updated_at = now();


-- ============================================================
-- 6. KISIM 3 ALT KASALARI
--
-- C1 C2 C3 = yaklaşık 500
-- C4 C5 C6 = yaklaşık 350
-- ============================================================

insert into public.question_vaults (
  vault_code,
  name,
  description,
  vault_type,
  parent_vault_id,
  grade_level,
  subject_id,
  difficulty_level,
  section_code,
  section_order,
  is_dynamic,
  is_active,
  allow_practice,
  allow_competition,
  allow_one_v_one,
  allow_exam,
  manual_question_assignment_allowed,
  metadata
)
select
  'TR-G12-MATH-EASY-P3-' || x.code,
  '12. Matematik Kolay Kısım 3 - ' || x.code,
  '12. sınıf Matematik kolay Kısım 3 alt soru kasası ' || x.code || '.',
  'academic',
  parent.id,
  12,
  '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
  'easy',
  x.code,
  x.sort_order,
  false,
  true,
  true,
  false,
  false,
  false,
  true,
  jsonb_build_object(
    'legacy_vault_code', x.code,
    'target_question_count', x.target_count,
    'activation_start_week', x.start_week,
    'activation_end_week', x.end_week,
    'seed_version', '049'
  )
from public.question_vaults parent
cross join (
  values
    ('C1', 1, 500, 24, 36),
    ('C2', 2, 500, 24, 36),
    ('C3', 3, 500, 24, 36),

    ('C4', 4, 350, 36, 48),
    ('C5', 5, 350, 36, 48),
    ('C6', 6, 350, 36, 48)
) as x(
  code,
  sort_order,
  target_count,
  start_week,
  end_week
)
where parent.vault_code = 'TR-G12-MATH-EASY-P3'
on conflict (vault_code) do update
set
  parent_vault_id = excluded.parent_vault_id,
  metadata = excluded.metadata,
  is_active = true,
  updated_at = now();


-- ============================================================
-- 7. KISIM 4 ALT KASALARI
--
-- D1 D2 D3 = yaklaşık 800
-- ============================================================

insert into public.question_vaults (
  vault_code,
  name,
  description,
  vault_type,
  parent_vault_id,
  grade_level,
  subject_id,
  difficulty_level,
  section_code,
  section_order,
  is_dynamic,
  is_active,
  allow_practice,
  allow_competition,
  allow_one_v_one,
  allow_exam,
  manual_question_assignment_allowed,
  metadata
)
select
  'TR-G12-MATH-EASY-P4-' || x.code,
  '12. Matematik Kolay Kısım 4 - ' || x.code,
  '12. sınıf Matematik kolay Kısım 4 alt soru kasası ' || x.code || '.',
  'academic',
  parent.id,
  12,
  '430903f3-527e-4e12-b7e8-ac0afdb784aa'::uuid,
  'easy',
  x.code,
  x.sort_order,
  false,
  true,
  true,
  false,
  false,
  false,
  true,
  jsonb_build_object(
    'legacy_vault_code', x.code,
    'target_question_count', x.target_count,
    'activation_start_week', x.start_week,
    'activation_end_week', x.end_week,
    'seed_version', '049'
  )
from public.question_vaults parent
cross join (
  values
    ('D1', 1, 800, 36, 48),
    ('D2', 2, 800, 36, 48),
    ('D3', 3, 800, 36, 48)
) as x(
  code,
  sort_order,
  target_count,
  start_week,
  end_week
)
where parent.vault_code = 'TR-G12-MATH-EASY-P4'
on conflict (vault_code) do update
set
  parent_vault_id = excluded.parent_vault_id,
  metadata = excluded.metadata,
  is_active = true,
  updated_at = now();


-- ============================================================
-- 8. HAFTALIK AKTİVASYON PENCERELERİ
--
-- Alt kasaların metadata içindeki hafta bilgileri gerçek
-- activation window kayıtlarına dönüştürülür.
-- ============================================================

insert into public.question_vault_activation_windows (
  vault_id,
  window_name,
  start_week,
  end_week,
  is_enabled,
  priority,
  metadata
)
select
  v.id,
  concat(
    coalesce(v.section_code, v.vault_code),
    ' / ',
    v.metadata->>'activation_start_week',
    '-',
    v.metadata->>'activation_end_week',
    ' hafta'
  ),
  (v.metadata->>'activation_start_week')::integer,
  (v.metadata->>'activation_end_week')::integer,
  true,
  100,
  jsonb_build_object(
    'seed_version', '049',
    'generated_from_vault_metadata', true
  )
from public.question_vaults v
where v.vault_code like 'TR-G12-MATH-EASY-P%'
  and v.metadata ? 'activation_start_week'
  and not exists (
    select 1
    from public.question_vault_activation_windows aw
    where aw.vault_id = v.id
      and aw.start_week =
        (v.metadata->>'activation_start_week')::integer
      and aw.end_week =
        (v.metadata->>'activation_end_week')::integer
  );


-- ============================================================
-- 9. KISIMLARA LEGACY KONU REFERANSLARI
-- Bunlar canonical topic değildir.
-- Eski tasarımdaki "1., 2., 3. konu" yapısını kaybetmemek
-- için placeholder legacy referanslarıdır.
-- ============================================================

insert into public.question_vault_topics (
  vault_id,
  legacy_topic_code,
  legacy_topic_name,
  topic_order,
  is_required,
  metadata
)
select
  v.id,
  t.topic_code,
  t.topic_name,
  t.topic_order,
  true,
  jsonb_build_object(
    'legacy_placeholder', true,
    'canonical_mapping_required', true,
    'seed_version', '049'
  )
from public.question_vaults v
join (
  values
    ('TR-G12-MATH-EASY-P1', 'LEGACY-1',  'Legacy Konu 1',  1),
    ('TR-G12-MATH-EASY-P1', 'LEGACY-2',  'Legacy Konu 2',  2),
    ('TR-G12-MATH-EASY-P1', 'LEGACY-3',  'Legacy Konu 3',  3),

    ('TR-G12-MATH-EASY-P2', 'LEGACY-4',  'Legacy Konu 4',  1),
    ('TR-G12-MATH-EASY-P2', 'LEGACY-5',  'Legacy Konu 5',  2),
    ('TR-G12-MATH-EASY-P2', 'LEGACY-6',  'Legacy Konu 6',  3),

    ('TR-G12-MATH-EASY-P3', 'LEGACY-7',  'Legacy Konu 7',  1),
    ('TR-G12-MATH-EASY-P3', 'LEGACY-8',  'Legacy Konu 8',  2),
    ('TR-G12-MATH-EASY-P3', 'LEGACY-9',  'Legacy Konu 9',  3),
    ('TR-G12-MATH-EASY-P3', 'LEGACY-10', 'Legacy Konu 10', 4),

    ('TR-G12-MATH-EASY-P4', 'LEGACY-11', 'Legacy Konu 11', 1),
    ('TR-G12-MATH-EASY-P4', 'LEGACY-12', 'Legacy Konu 12', 2),
    ('TR-G12-MATH-EASY-P4', 'LEGACY-13', 'Legacy Konu 13', 3)
) as t(
  vault_code,
  topic_code,
  topic_name,
  topic_order
)
  on t.vault_code = v.vault_code
where not exists (
  select 1
  from public.question_vault_topics existing
  where existing.vault_id = v.id
    and existing.legacy_topic_code = t.topic_code
);


commit;