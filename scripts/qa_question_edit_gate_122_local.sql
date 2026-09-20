-- ============================================================
-- scripts/qa_question_edit_gate_122_local.sql
-- Altin Kalemler - Migration 122 yerel QA suite
-- (Işleyen soruda değişiklik kapısı + güvenli yeniden onay)
--
-- Kapsam:
--   T-01 : onayli+aktif soruda içerik degisikligi -> otomatik
--          pasif (is_active=false) + needs_review + deactivate
--          publication event + audit 'question.edit'
--   T-02 : yalnizca DIFficulty gibi tetikleyici OLMAYAN alanin
--          degisikligi kapıyı tetiklemez (approved+active kalir)
--   T-03 : has_visual degisikligi kapıyı tetikler (gorsel icerik)
--   T-04 : onayli ama PASIF soruda icerik degisikligi -> needs_review
--          (publication event YAZILMAZ: ogrenciye gorunur degildi)
--   T-05 : no-op edit (ayni degerler) kapıyı tetiklemez
--   T-06 : admin_question_requalify needs_review -> approved;
--          is_active FALSe KALIR; audit 'question.requalify'
--   T-07 : requalify zaten approved -> 'already_approved' (yeni audit yok)
--   T-08 : requalify needs_review olmayan (draft) -> hata
--   T-09 : questions.edit izni olmayan edit -> 42501
--   T-10 : questions.approve izni olmayan requalify -> 42501
--   T-11 : needs_review soru 040 readiness ile yayinlanamaz
--          (question_not_approved bloker)
--   T-12 : audit append-only: eski kayit bozulmaz, yeni satirlar eklenir
--
-- Calistirma (disposable DB, migration 001-122 uygulanmis):
--   docker cp scripts/qa_question_edit_gate_122_local.sql <db>:/tmp/
--   docker exec <db> psql -U postgres -d postgres \
--          -v ON_ERROR_STOP=1 -A -t -f /tmp/qa_question_edit_gate_122_local.sql
--
-- Guvence: tum suite TEK TRANSACTION icinde calisir ve sonunda
-- ROLLBACK yapilir; hicbir test artefakti/kayit kalici olmaz.
-- ============================================================

\set ON_ERROR_STOP on

begin;


-- ============================================================
-- SONUC TABLOSU + YARDIMCILAR
-- ============================================================

create table public._qa_q122_results (
  label  text not null,
  title  text not null,
  result text not null check (result in ('PASS', 'FAIL')),
  detail text
);

grant select, insert, update, delete
  on public._qa_q122_results
  to anon, authenticated, service_role;

create function public._qa_q122_expect(
  p_label text, p_title text, p_expect text, p_sql text
)
returns void
language plpgsql
security invoker
as $qa$
declare
  v_state text;
  v_msg   text;
begin
  begin
    execute p_sql;

    if p_expect = '' then
      insert into public._qa_q122_results
      values (p_label, p_title, 'PASS', 'beklendigi gibi uygulandi');
    else
      insert into public._qa_q122_results
      values (p_label, p_title, 'FAIL',
              'hata beklenmisti ama uygulandi; beklenen sqlstate=' || p_expect);
    end if;

  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;

    if p_expect <> '' and v_state = p_expect then
      insert into public._qa_q122_results
      values (p_label, p_title, 'PASS', 'beklenen sqlstate=' || v_state);
    else
      insert into public._qa_q122_results
      values (p_label, p_title, 'FAIL',
              'sqlstate=' || v_state || ' mesaj=' || left(v_msg, 200) ||
              ' beklenen=' || coalesce(p_expect, '<uygulanmali>'));
    end if;
  end;
end;
$qa$;

create function public._qa_q122_true(
  p_label text, p_title text, p_ok boolean, p_detail text
)
returns void
language plpgsql
security invoker
as $qa$
begin
  insert into public._qa_q122_results
  values (p_label, p_title, case when p_ok then 'PASS' else 'FAIL' end,
          coalesce(p_detail, ''));
end;
$qa$;

grant execute
  on function public._qa_q122_expect(text, text, text, text)
  to anon, authenticated, service_role;

grant execute
  on function public._qa_q122_true(text, text, boolean, text)
  to anon, authenticated, service_role;

-- Auth simulasyon yardimcisi: authenticated rolune gec + jwt claims kur.
create function public._qa_q122_as(p_claims text, p_sql text)
returns text
language plpgsql
security invoker
as $qa$
declare
  v_out text;
begin
  execute format('set local role %I', 'authenticated');
  perform set_config('request.jwt.claims', p_claims, true);
  perform set_config('request.jwt.claim.sub',
    (p_claims::jsonb ->> 'sub'), true);
  execute format('select (%s)::text', p_sql) into v_out;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  return coalesce(v_out, '');
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  execute 'reset role';
  raise;
end;
$qa$;

grant execute
  on function public._qa_q122_as(text, text)
  to anon, authenticated, service_role;


-- ============================================================
-- FIXTURE'LAR (sabit QA uuid'leri; rollback ile silinecek)
--   ADMIN  : super_admin (questions.edit + questions.approve)
--   ORDIN  : izinsiz kullanici
--   matematik: 430903f3-527e-4e12-b7e8-ac0afdb784aa (045 seed)
-- ============================================================

-- auth.users kolon adi disposable image'da confirmed_at (email_confirmed_at
-- degil) — bkz. docs/reports/faz20-nihai-rapor.md QA kurulum notlari.
insert into auth.users
  (id, aud, role, email, encrypted_password, confirmed_at,
   raw_user_meta_data, created_at, updated_at)
values
  ('99770000-0000-0000-0000-000000000991', 'authenticated', 'authenticated',
   'qa122-admin@e2e.test', '', now(),
   '{"nickname":"QA122_Admin"}'::jsonb, now(), now()),
  ('99770000-0000-0000-0000-000000000992', 'authenticated', 'authenticated',
   'qa122-ordin@e2e.test', '', now(),
   '{"nickname":"QA122_Ordin"}'::jsonb, now(), now())
on conflict (id) do nothing;

insert into public.admin_user_roles (user_id, role_id, assigned_by, assigned_at)
select '99770000-0000-0000-0000-000000000991', r.id,
       '99770000-0000-0000-0000-000000000991', now()
  from public.admin_roles r
 where r.role_code = 'super_admin'
on conflict do nothing;

-- Sorular: Q1 onayli+aktif, Q2 onayli+pasif, Q3 needs_review,
--          Q4 draft, Q5 onayli+aktif (metadata testi).
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   question_text, option_a, option_b, option_c, option_d, correct_answer,
   difficulty, cognitive_type, primary_question_type, has_visual,
   commercial_use_allowed, estimated_solve_time_seconds)
values
  ('99770000-0000-0000-0000-000000000a01', 'QA122-Q1', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'QA122 metin 1', 'A1', 'B1', 'C1', 'D1', 'A',
   'easy', 'learning', 'coktan_secmeli', false, true, 45),
  ('99770000-0000-0000-0000-000000000a02', 'QA122-Q2', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', false,
   'QA122 metin 2', 'A2', 'B2', 'C2', 'D2', 'B',
   'medium', 'comprehension', 'coktan_secmeli', false, true, 60),
  ('99770000-0000-0000-0000-000000000a03', 'QA122-Q3', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'needs_review', false,
   'QA122 metin 3', 'A3', 'B3', 'C3', 'D3', 'C',
   'easy', 'learning', 'coktan_secmeli', false, true, 45),
  ('99770000-0000-0000-0000-000000000a04', 'QA122-Q4', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'draft', false,
   'QA122 metin 4', 'A4', 'B4', 'C4', 'D4', 'D',
   'easy', 'learning', 'coktan_secmeli', false, true, 45),
  ('99770000-0000-0000-0000-000000000a05', 'QA122-Q5', 5,
   '430903f3-527e-4e12-b7e8-ac0afdb784aa', 'approved', true,
   'QA122 metin 5', 'A5', 'B5', 'C5', 'D5', 'A',
   'easy', 'learning', 'coktan_secmeli', false, true, 45)
on conflict (id) do nothing;

-- T-12 icin: kapıdan ONCE var olan bir audit kaydi (baslangic durumu).
insert into public.admin_audit_log
  (id, actor_user_id, action_code, entity_type, entity_id,
   before_data, after_data)
values
  ('99770000-0000-0000-0000-000000000f01',
   '99770000-0000-0000-0000-000000000991', 'question.edit', 'question',
   '99770000-0000-0000-0000-000000000a01',
   '{"approval_status":"approved","is_active":true}'::jsonb,
   '{"approval_status":"approved","is_active":true}'::jsonb);


-- ============================================================
-- T-01: onayli+AKTIF soruda içerik degisikligi -> pasif + needs_review
-- ============================================================

do $blk$
declare
  v_res jsonb;
begin
  v_res := public._qa_q122_as(
    '{"sub":"99770000-0000-0000-0000-000000000991","role":"authenticated"}',
    $sql$select public.admin_question_edit(
      p_question_id => '99770000-0000-0000-0000-000000000a01',
      p_question_text => 'QA122 metin 1 DEGISTI',
      p_option_a => 'A1', p_option_b => 'B1', p_option_c => 'C1',
      p_option_d => 'D1', p_correct_answer => 'A')$sql$
  )::jsonb;

  perform public._qa_q122_true('T-01a',
    'icindekim degisti: review_required=true cikisi',
    (v_res->>'review_required')::boolean = true,
    'review_required=' || coalesce(v_res->>'review_required', '<null>'));

  perform public._qa_q122_true('T-01b',
    'kapı sonrasi: is_active=false ve approval_status=needs_review',
    (select is_active = false and approval_status = 'needs_review'
       from public.questions where id = '99770000-0000-0000-0000-000000000a01'),
    'is_active/approval_status sorgu ile dogrulandi');

  perform public._qa_q122_true('T-01c',
    'deactivate publication event yazildi (otomatik kapı izi)',
    exists (
      select 1 from public.question_publication_events
       where question_id = '99770000-0000-0000-0000-000000000a01'
         and action = 'deactivate'
         and (metadata->>'automatic_content_change_gate')::boolean = true),
    'publication event arandi');

  perform public._qa_q122_true('T-01d',
    'audit question.edit yazildi',
    exists (
      select 1 from public.admin_audit_log
       where entity_id = '99770000-0000-0000-0000-000000000a01'
         and action_code = 'question.edit'
         and after_data->>'approval_status' = 'needs_review'),
    'after_data approval_status kontrol edildi');
end;
$blk$;


-- ============================================================
-- T-02: tetikleyici OLMAYAN alan (difficulty) -> kapı tetiklenmez
-- ============================================================

do $blk$
declare
  v_res jsonb;
  v_st  text;
  v_ia  boolean;
begin
  v_res := public._qa_q122_as(
    '{"sub":"99770000-0000-0000-0000-000000000991","role":"authenticated"}',
    $sql$select public.admin_question_edit(
      p_question_id => '99770000-0000-0000-0000-000000000a05',
      p_question_text => 'QA122 metin 5',
      p_option_a => 'A5', p_option_b => 'B5', p_option_c => 'C5',
      p_option_d => 'D5', p_correct_answer => 'A',
      p_difficulty => 'hard')$sql$
  )::jsonb;

  select approval_status, is_active into v_st, v_ia
    from public.questions where id = '99770000-0000-0000-0000-000000000a05';

  perform public._qa_q122_true('T-02',
    'difficulty degisikligi kapıyı tetiklemez; approved+active kalir',
    (v_res->>'review_required')::boolean = false
      and v_st = 'approved' and v_ia = true,
    'review_required=' || coalesce(v_res->>'review_required', '<null>')
      || ' st=' || v_st || ' ia=' || v_ia);
end;
$blk$;


-- ============================================================
-- T-03: has_visual degisikligi -> kapı tetiklenir (gorsel icerik)
-- ============================================================

do $blk$
declare
  v_res jsonb;
begin
  v_res := public._qa_q122_as(
    '{"sub":"99770000-0000-0000-0000-000000000991","role":"authenticated"}',
    $sql$select public.admin_question_edit(
      p_question_id => '99770000-0000-0000-0000-000000000a05',
      p_question_text => 'QA122 metin 5',
      p_option_a => 'A5', p_option_b => 'B5', p_option_c => 'C5',
      p_option_d => 'D5', p_correct_answer => 'A',
      p_difficulty => 'hard',
      p_has_visual => true)$sql$
  )::jsonb;

  perform public._qa_q122_true('T-03',
    'has_visual degisikligi kapıyı tetikler (needs_review+pasif)',
    (v_res->>'review_required')::boolean = true
      and (select approval_status = 'needs_review' and is_active = false
            from public.questions where id = '99770000-0000-0000-0000-000000000a05'),
    'review_required=' || coalesce(v_res->>'review_required', '<null>'));
end;
$blk$;


-- ============================================================
-- T-04: onayli ama PASIF soruda icerik degisikligi
--       -> needs_review; publication event YOK
-- ============================================================

do $blk$
declare
  v_res jsonb;
  v_events integer;
begin
  v_res := public._qa_q122_as(
    '{"sub":"99770000-0000-0000-0000-000000000991","role":"authenticated"}',
    $sql$select public.admin_question_edit(
      p_question_id => '99770000-0000-0000-0000-000000000a02',
      p_question_text => 'QA122 metin 2 DEGISTI',
      p_option_a => 'A2', p_option_b => 'B2', p_option_c => 'C2',
      p_option_d => 'D2', p_correct_answer => 'B')$sql$
  )::jsonb;

  select count(*) into v_events
    from public.question_publication_events
   where question_id = '99770000-0000-0000-0000-000000000a02';

  perform public._qa_q122_true('T-04a',
    'pasif onayli soruda icerik degisikligi needs_review yapar',
    (v_res->>'review_required')::boolean = true
      and (select approval_status = 'needs_review' and is_active = false
            from public.questions where id = '99770000-0000-0000-0000-000000000a02'),
    'review_required=' || coalesce(v_res->>'review_required', '<null>'));

  perform public._qa_q122_true('T-04b',
    'pasif soruda publication event YAZILMAZ (gorunurluk degismedi)',
    v_events = 0,
    'event_sayisi=' || v_events);
end;
$blk$;


-- ============================================================
-- T-05: no-op edit (ayni degerler) -> kapı tetiklenmez
--       (needs_review'deki Q1'in içerigi ayerek tesdi edilir)
-- ============================================================

do $blk$
declare
  v_res jsonb;
begin
  -- Q1'i kapıyla ayni icerige tekrar yaz: degisiklik YOK -> tetiklenmez.
  v_res := public._qa_q122_as(
    '{"sub":"99770000-0000-0000-0000-000000000991","role":"authenticated"}',
    $sql$select public.admin_question_edit(
      p_question_id => '99770000-0000-0000-0000-000000000a01',
      p_question_text => 'QA122 metin 1 DEGISTI',
      p_option_a => 'A1', p_option_b => 'B1', p_option_c => 'C1',
      p_option_d => 'D1', p_correct_answer => 'A')$sql$
  )::jsonb;

  perform public._qa_q122_true('T-05',
    'ayni degerlerle kayit kapıyı tetiklemez',
    (v_res->>'review_required')::boolean = false
      and (v_res->>'content_changed')::boolean = false,
    'review_required=' || coalesce(v_res->>'review_required', '<null>')
      || ' content_changed=' || coalesce(v_res->>'content_changed', '<null>'));
end;
$blk$;


-- ============================================================
-- T-06: requalify needs_review -> approved; is_active false KALIR
-- ============================================================

do $blk$
declare
  v_res jsonb;
begin
  v_res := public._qa_q122_as(
    '{"sub":"99770000-0000-0000-0000-000000000991","role":"authenticated"}',
    $sql$select public.admin_question_requalify(
      p_question_id => '99770000-0000-0000-0000-000000000a03')$sql$
  )::jsonb;

  perform public._qa_q122_true('T-06a',
    'requalify needs_review -> approved yapar',
    v_res->>'status' = 'requalified'
      and (select approval_status = 'approved'
            from public.questions where id = '99770000-0000-0000-0000-000000000a03'),
    'status=' || coalesce(v_res->>'status', '<null>'));

  perform public._qa_q122_true('T-06b',
    'requalify sonrasi is_active FALSe KALIR (ogrenciye acilmaz)',
    (select is_active = false
       from public.questions where id = '99770000-0000-0000-0000-000000000a03'),
    'is_active sorgu ile kontrol edildi');

  perform public._qa_q122_true('T-06c',
    'requalify audit question.requalify yazar',
    exists (
      select 1 from public.admin_audit_log
       where entity_id = '99770000-0000-0000-0000-000000000a03'
         and action_code = 'question.requalify'
         and before_data->>'approval_status' = 'needs_review'
         and after_data->>'approval_status' = 'approved'),
    'audit before/after kontrol edildi');
end;
$blk$;


-- ============================================================
-- T-07: requalify zaten approved -> already_approved (yeni audit yok)
-- ============================================================

do $blk$
declare
  v_res   jsonb;
  v_audit integer;
begin
  select count(*) into v_audit
    from public.admin_audit_log
   where entity_id = '99770000-0000-0000-0000-000000000a03'
     and action_code = 'question.requalify';

  v_res := public._qa_q122_as(
    '{"sub":"99770000-0000-0000-0000-000000000991","role":"authenticated"}',
    $sql$select public.admin_question_requalify(
      p_question_id => '99770000-0000-0000-0000-000000000a03')$sql$
  )::jsonb;

  perform public._qa_q122_true('T-07a',
    'zaten approved soru already_approved no-op dondurur',
    v_res->>'status' = 'already_approved',
    'status=' || coalesce(v_res->>'status', '<null>'));

  perform public._qa_q122_true('T-07b',
    'already_approved icin yeni audit yazilmaz',
    (select count(*) from public.admin_audit_log
      where entity_id = '99770000-0000-0000-0000-000000000a03'
        and action_code = 'question.requalify') = v_audit,
    'onceki=' || v_audit);
end;
$blk$;


-- ============================================================
-- T-08: requalify needs_review olmayan (draft) soru -> hata
-- ============================================================

do $blk$
begin
  perform public._qa_q122_expect(
    'T-08',
    'draft soru requalify edilemez (yeniden inceleme durumu gerekir)',
    '22023',
    $qa$select public._qa_q122_as(
      '{"sub":"99770000-0000-0000-0000-000000000991","role":"authenticated"}',
      'select public.admin_question_requalify(
        p_question_id => ''99770000-0000-0000-0000-000000000a04'')')$qa$);
end;
$blk$;


-- ============================================================
-- T-09: questions.edit izni olmayan edit -> 42501
-- ============================================================

do $blk$
begin
  perform public._qa_q122_expect(
    'T-09',
    'yetkisiz kullanici edit yapamaz (42501)',
    '42501',
    $qa$select public._qa_q122_as(
      '{"sub":"99770000-0000-0000-0000-000000000992","role":"authenticated"}',
      'select public.admin_question_edit(
        p_question_id => ''99770000-0000-0000-0000-000000000a05'',
        p_question_text => ''QA122 HACKED'',
        p_option_a => ''A5'', p_option_b => ''B5'', p_option_c => ''C5'',
        p_option_d => ''D5'', p_correct_answer => ''A'')')$qa$);
end;
$blk$;


-- ============================================================
-- T-10: questions.approve izni olmayan requalify -> 42501
-- ============================================================

do $blk$
begin
  perform public._qa_q122_expect(
    'T-10',
    'yetkisiz kullanici requalify yapamaz (42501)',
    '42501',
    $qa$select public._qa_q122_as(
      '{"sub":"99770000-0000-0000-0000-000000000992","role":"authenticated"}',
      'select public.admin_question_requalify(
        p_question_id => ''99770000-0000-0000-0000-000000000a04'')')$qa$);
end;
$blk$;


-- ============================================================
-- T-11: needs_review soru 040 readiness ile yayinlanamaz
--       (question_not_approved bloker)
-- ============================================================

do $blk$
declare
  v_ready jsonb;
  v_block boolean := false;
  v_item  jsonb;
begin
  v_ready := public._qa_q122_as(
    '{"sub":"99770000-0000-0000-0000-000000000991","role":"authenticated"}',
    $sql$select private.check_question_activation_readiness(
      '99770000-0000-0000-0000-000000000a01')$sql$
  )::jsonb;

  -- blocking_reasons icerisinde question_not_approved aramasi.
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_ready->'blocking_reasons') LOOP
    IF v_item->>'code' = 'question_not_approved' THEN
      v_block := true;
    END IF;
  END LOOP;

  perform public._qa_q122_true('T-11',
    'needs_review soru yayina uygun degil (040 question_not_approved)',
    (v_ready->>'can_activate')::boolean = false and v_block,
    'can_activate=' || coalesce(v_ready->>'can_activate', '<null>')
      || ' block=' || v_block);
end;
$blk$;


-- ============================================================
-- T-12: audit append-only: eski kayit bozulmaz, yenileri eklenir
-- ============================================================

do $blk$
declare
  v_before jsonb;
  v_after  jsonb;
  v_cnt_before integer;
  v_cnt_after  integer;
begin
  select before_data, after_data into v_before, v_after
    from public.admin_audit_log
   where id = '99770000-0000-0000-0000-000000000f01';

  select count(*) into v_cnt_before from public.admin_audit_log;

  -- Q1'e bir degisiklik daha: yeni audit satiri olusur.
  perform public._qa_q122_as(
    '{"sub":"99770000-0000-0000-0000-000000000991","role":"authenticated"}',
    $sql$select public.admin_question_edit(
      p_question_id => '99770000-0000-0000-0000-000000000a01',
      p_question_text => 'QA122 metin 1 YENIDEN',
      p_option_a => 'A1', p_option_b => 'B1', p_option_c => 'C1',
      p_option_d => 'D1', p_correct_answer => 'A')$sql$
  );

  select count(*) into v_cnt_after from public.admin_audit_log;

  perform public._qa_q122_true('T-12',
    'eski audit kaydi bozulmadi ve yeni kayitlar eklendi (append-only)',
    v_before = '{"approval_status":"approved","is_active":true}'::jsonb
      and v_after = v_before
      and v_cnt_after > v_cnt_before,
    'onceki=' || v_cnt_before || ' sonra=' || v_cnt_after);
end;
$blk$;


-- ============================================================
-- SONUC
-- ============================================================

select label, title, result, detail
  from public._qa_q122_results
 order by label;

rollback;