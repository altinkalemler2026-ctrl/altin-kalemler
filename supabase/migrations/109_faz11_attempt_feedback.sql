-- ============================================================
-- 109_faz11_attempt_feedback.sql
-- Altın Kalemler - Migration Faz 11: Onaylı Çözüm Geri Bildirimi
--
-- AMAÇ:
--   public.get_attempt_feedback(p_question_id uuid):
--   Öğrenci cevabını KABUL ETTİKTEN SONRA (training bağlamında en az
--   bir denemesi varken) sorunun doğru cevabını ve ONAYLI metin çözüm
--   açıklamasını döndürür. Cevap öncesi çağrı fail-closed {found:false}
--   döner; doğru cevap/açıklama ASLA sızmaz.
--
-- SÖZLEŞME KAYNAKLARI:
--   - Doğruluk: questions.correct_answer (070 tek kaynak; CHECK A..E).
--     Yalnız is_active + approval_status='approved' sorularda açılır.
--   - Açıklama: question_solution_assets (004) — asset_type=
--     'text_solution', is_active=true, validation_status='valid'
--     satırları. Yapay içerik üretilmez; yoksa solution_text NULL
--     döner (UI "Çözüm açıklaması hazırlanıyor." gösterir).
--
-- GÜVENLİK MODELİ (070/098 desenleriyle aynı):
--   - SECURITY DEFINER + set search_path='' + auth.uid() türetimi;
--     kullanıcı parametresi YOKTUR.
--   - Gösterim kapısı 1: exposure (user_id + question_id + 'training').
--   - Gösterim kapısı 2: en az bir training denemesi (cevap kabulü).
--   - Minimal sonuç allowlist'i: found, correct_answer, solution_text.
--     UUID/PII/ham hata/dahili anahtar DÖNMEZ.
--   - ACL: tam revoke → yalnız authenticated grant (070 deseni).
--   - random YOK; deterministik seçim (created_at ASC, id ASC).
-- ============================================================

begin;

create or replace function public.get_attempt_feedback(
  p_question_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user     uuid;
  v_correct  text;
  v_solution text;
  v_attempt  text;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  if p_question_id is null then
    raise exception 'Soru zorunludur.'
      using errcode = '22004';
  end if;

  -- ----------------------------------------------------------
  -- Kapı 1: soru bu kullanıcıya training bağlamında gösterilmiş mi?
  -- ----------------------------------------------------------
  if not exists (
    select 1
      from public.student_question_exposures e
     where e.user_id = v_user
       and e.question_id = p_question_id
       and e.attempt_context = 'training'
  ) then
    return jsonb_build_object('found', false);
  end if;

  -- ----------------------------------------------------------
  -- Kapı 2: kabul edilmiş en az bir deneme var mı?
  -- (Cevap öncesi doğru cevap/açıklama sızmaz — fail-closed.)
  -- ----------------------------------------------------------
  select a.result into v_attempt
    from public.student_question_attempts a
   where a.user_id = v_user
     and a.question_id = p_question_id
     and a.attempt_context = 'training'
   order by a.answered_at desc, a.id desc
   limit 1;

  if v_attempt is null then
    return jsonb_build_object('found', false);
  end if;

  -- ----------------------------------------------------------
  -- Doğru cevap: yalnız aktif + onaylı soruda açılır.
  -- ----------------------------------------------------------
  select q.correct_answer into v_correct
    from public.questions q
   where q.id = p_question_id
     and q.is_active
     and q.approval_status = 'approved';

  -- ----------------------------------------------------------
  -- Onaylı metin çözüm (004 sözleşmesi): yalnız text_solution +
  -- is_active + validation_status='valid'. Yoksa NULL (UI uydurmaz).
  -- ----------------------------------------------------------
  select sa.asset_text into v_solution
    from public.question_solution_assets sa
   where sa.question_id = p_question_id
     and sa.asset_type = 'text_solution'
     and sa.is_active = true
     and sa.validation_status = 'valid'
   order by sa.created_at asc, sa.id asc
   limit 1;

  return jsonb_build_object(
    'found',          true,
    'correct_answer', v_correct,
    'solution_text',  v_solution
  );
end;
$$;

comment on function public.get_attempt_feedback(uuid) is
  'Faz 11: cevap KABULunden sonra dogru cevap + onayli metin cozumu. Kapilar: auth.uid() + training exposure + mevcut deneme. Cevap oncesi {found:false}. Aclama yoksa solution_text NULL.';

-- ------------------------------------------------------------
-- ACL (070 deseni): tam revoke → yalnız authenticated.
-- PUBLIC/anon çalıştırma izni kapalıdır.
-- ------------------------------------------------------------
revoke execute
  on function public.get_attempt_feedback(uuid)
  from public, anon, authenticated;

grant execute
  on function public.get_attempt_feedback(uuid)
  to authenticated;

commit;
