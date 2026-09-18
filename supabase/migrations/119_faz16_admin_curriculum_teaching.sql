-- ============================================================
-- 119_faz16_admin_curriculum_teaching.sql
-- Altın Kalemler — Faz 16 P0.1: Admin Öğretmen Konu-Açma Ekranı (veri kıyısı)
--
-- 110'daki "konu işlendi" onayı RPC'lerinin append-only genişletmesi.
--   1. set_curriculum_teaching_approval    → ATOMIK ADMIN_AUDIT_LOG YAZIMI eklenir
--      (089 deseni: mutation + audit aynı fonksiyon = aynı transaction).
--      Davranış/imza değişmez; yalnız güvenlik boşluğu kapanır (Faz 16 şartı:
--      "tüm yazma işlemlerinde atomik audit kaydı").
--   2. list_curriculum_teaching_approvals  → schedule_profile_id / profile_code /
--      profile_name ALANLARI eklenir (additive; satır şekli başka değişmez).
--      İmza değişmez: (uuid, text) → Returns jsonb. Mevcut tüketici yoktur
--      (110 §6b notu), types.ts imzaları değişmediği için type-drift yaratmaz.
-- SCOP: yalnız bu iki RPC'nin CREATE OR REPLACE'i. Şema/RLS/izin değişmez;
-- append-only (110'a dokunulmaz). ACL teyidi 110 §7 deseniyle birebir.
-- İdempotent: CREATE OR REPLACE; yeniden çalıştırılabilir.
-- ============================================================

begin;

-- ============================================================
-- 1. SET_CURRICULUM_TEACHING_APPROVAL + ATOMIC AUDIT
--    İmza: (uuid, text, text, text) — tipik p_schedule_item_id, p_academic_year,
--          p_status ('approved'|'rejected'), p_notes. 110 davranışı korunur:
--          fail-closed yazma (giriş + curriculum.manage + schedule item varlığı),
--          UNIQUE(academic_year, schedule_item_id) üzerinde upsert.
--    before_data: mevcut onayın (status, notes) anlık görüntüsü (yoksa null).
--    after_data: mutation sonrası (status, notes, approved_by).
--    admin_audit_log yazımı SECURITY DEFINER (sahip) olarak burada yapılır;
--    RLS INSERT policy olmadığı için browser doğrudan yazamaz (089).
-- ============================================================

create or replace function public.set_curriculum_teaching_approval(
  p_schedule_item_id uuid,
  p_academic_year text,
  p_status text default 'approved',
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid;
  v_row  public.curriculum_teaching_approvals%rowtype;
  v_before_status text;
  v_before_notes  text;
  v_audit_id      uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  if not public.current_user_has_admin_permission('curriculum.manage') then
    raise exception 'curriculum.manage yetkisi gerekli.'
      using errcode = '42501';
  end if;

  if p_schedule_item_id is null
     or p_academic_year is null
     or p_academic_year = '' then
    raise exception 'Schedule item ve akademik yil zorunludur.'
      using errcode = '22004';
  end if;

  if p_status not in ('approved', 'rejected') then
    raise exception 'p_status approved veya rejected olmalidir.'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
      from public.curriculum_schedule_items si
     where si.id = p_schedule_item_id
  ) then
    raise exception 'Schedule item bulunamadi.'
      using errcode = 'P0002';
  end if;

  -- before_data: mevcut onayın allowlist görüntüsü (hiç yoksa null).
  select a.status, a.notes
    into v_before_status, v_before_notes
    from public.curriculum_teaching_approvals a
   where a.academic_year = p_academic_year
     and a.schedule_item_id = p_schedule_item_id;

  insert into public.curriculum_teaching_approvals
    (academic_year, schedule_item_id, status, approved_by, notes)
  values
    (p_academic_year, p_schedule_item_id, p_status, v_uid, p_notes)
  on conflict (academic_year, schedule_item_id)
  do update set
    status = excluded.status,
    approved_by = excluded.approved_by,
    notes = excluded.notes,
    updated_at = now()
  returning * into v_row;

  -- ATOMIC AUDIT — aynı transaction. Audit INSERT başarısız olursa
  -- mutation da geri alınır.
  insert into public.admin_audit_log (
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    before_data,
    after_data
  )
  values (
    v_uid,
    'curriculum.teaching_approval',
    'curriculum_schedule_item',
    p_schedule_item_id,
    case when v_before_status is null then null
         else jsonb_build_object(
           'status', v_before_status,
           'notes', v_before_notes
         )
    end,
    jsonb_build_object(
      'academic_year', p_academic_year,
      'status', v_row.status,
      'notes', v_row.notes,
      'approved_by', v_row.approved_by
    )
  )
  returning id
  into v_audit_id;

  return jsonb_build_object(
    'id', v_row.id,
    'academic_year', v_row.academic_year,
    'schedule_item_id', v_row.schedule_item_id,
    'status', v_row.status,
    'notes', v_row.notes,
    'updated_at', v_row.updated_at,
    'audit_id', v_audit_id
  );
end;
$$;

-- ============================================================
-- 2. LIST_CURRICULUM_TEACHING_APPROVALS + PROFİL ALANLARI
--    Additive: satır objesine schedule_profile_id, profile_code,
--    profile_name eklenir. İmza ve diğer tüm alanlar 110 ile aynı.
--    (Faz 16 P0.1 UI, onayın hangi sıralama profiline ait olduğunu
--    gösterebilmeli — kullanıcı kararı: şube yok; profil + sınıf +
--    ders + konu + yıl + takvim öğesi kapsamı.)
-- ============================================================

create or replace function public.list_curriculum_teaching_approvals(
  p_subject_id uuid,
  p_academic_year text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid;
  v_rows jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  if not public.current_user_has_admin_permission('curriculum.manage') then
    raise exception 'curriculum.manage yetkisi gerekli.'
      using errcode = '42501';
  end if;

  if p_academic_year is null or p_academic_year = '' then
    raise exception 'Akademik yil zorunludur.'
      using errcode = '22004';
  end if;

  select coalesce(jsonb_agg(row_to_j order by row_to_j->>'grade_level'),
                  '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
        'schedule_item_id', si.id,
        'schedule_profile_id', sp.id,
        'profile_code', sp.code,
        'profile_name', sp.name,
        'grade_level', si.grade_level,
        'topic_id', si.topic_id,
        'topic_name', tp.name,
        'outcome_id', si.outcome_id,
        'outcome_text', co.outcome_text,
        'start_week', si.start_week,
        'status', coalesce(a.status, null),
        'updated_at', a.updated_at
      ) as row_to_j
        from public.curriculum_schedule_items si
        left join public.curriculum_schedule_profiles sp
          on sp.id = si.schedule_profile_id
        left join public.curriculum_teaching_approvals a
          on a.schedule_item_id = si.id
         and a.academic_year = p_academic_year
        left join public.topics tp on tp.id = si.topic_id
        left join public.curriculum_outcomes co on co.id = si.outcome_id
       where si.subject_id = p_subject_id
         and si.is_active = true
    ) t;

  return jsonb_build_object(
    'subject_id', p_subject_id,
    'academic_year', p_academic_year,
    'items', v_rows
  );
end;
$$;

-- ============================================================
-- 3. ACL TEYİTLERİ (impersonation-safe envroles ACL'i; 110 §7 deseni)
--    CREATE OR REPLACE imzaları korur; yine de 110'daki revoke/grant
--    teyidi aynen yeniden uygulanır (idempotent).
-- ============================================================

revoke execute
  on function public.set_curriculum_teaching_approval(uuid, text, text, text)
  from public, anon, authenticated;
grant execute
  on function public.set_curriculum_teaching_approval(uuid, text, text, text)
  to authenticated;

revoke execute
  on function public.list_curriculum_teaching_approvals(uuid, text)
  from public, anon, authenticated;
grant execute
  on function public.list_curriculum_teaching_approvals(uuid, text)
  to authenticated;

comment on function public.set_curriculum_teaching_approval(uuid, text, text, text) is
  'FAZ 16 P0.1: "konu islendi" onayini yazar (yil + schedule item). Yalniz curriculum.manage yetkilisi. Atomik admin_audit_log kaydi ustur (089 deseni). Onay kapsami: schedule profile + sinif + ders + konu + yil + takvim ogesi; sube okul paneli yok (kullanci karari).';
comment on function public.list_curriculum_teaching_approvals(uuid, text) is
  'FAZ 16 P0.1: ders + akademik yil bazli aktif schedule item listesi ve mevcut onay durumlari (LEFT JOIN). schedule_profile_id / profile_code / profile_name alanlarini da dondurur. Yalniz curriculum.manage yetkilisi.';

commit;