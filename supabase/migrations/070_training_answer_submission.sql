-- ============================================================
-- 070_training_answer_submission.sql
-- Altın Kalemler - Migration Faz 3 Temel: Güvenli Antrenman Cevabı
--
-- AMAÇ (Faz 3 hazırlık analizi → kritik güvenlik düzeltmesi):
--   ingest_student_attempt istemciden correct/wrong SONUCU alır.
--   Training için bu güvenilir değildir: doğruluk YALNIZ veritabanında,
--   questions.correct_answer üzerinden hesaplanmalıdır.
--
-- ÇÖZÜM:
--   public.submit_training_attempt(
--     p_question_id uuid,
--     p_choice      text,     -- 'A'..'E' (büyük/küçük harf esnek)
--     p_action      text,     -- 'pass' | 'timeout' | 'blank'
--     p_time_ms     integer,
--     p_client_key  uuid      -- ZORUNLU idempotency anahtarı
--   )
--
-- Garantiler:
--   1. İstemci yalnız soru + şık/eylem + süre + anahtar gönderir;
--      result parametresi YOKTUR. Doğruluk DB'de correct_answer ile
--      belirlenir ('correct' | 'wrong').
--   2. Yalnız kendisine TRAINING bağlamında gösterilmiş (exposure PK
--      user_id+question_id+'training') soruya cevap yazılabilir.
--   3. Yazım mevcut Faz 2 kurallarıyla olur: ingest_student_attempt
--      (advisory lock + attempt_number + 7 metrik kapsamı + dönem).
--   4. Idempotency: metadata.client_key üzerinde PARTIAL UNIQUE INDEX.
--      Aynı anahtar → aynı attempt, ikinci çağrı duplicate:true,
--      çift metrik İMKANSIZ (index ihlali yakalanır, mevcut kayıt döner).
--   5. Minimal sonuç: {attempt_id, attempt_number, result, duplicate}.
--      correct_answer / çözüm / gizli alan ASLA dönmez.
--   6. Sahte-sonuç kapanışı: authenticated artık ingest_student_attempt
--      çağıramaz (EXECUTE revoke). Training yazımı yalnız bu RPC'den.
--      Competition/one_v_one akışı (021/023) etkilenmez.
--
-- Güvenlik deseni: SECURITY DEFINER + set search_path='' + auth.uid()
-- + EXECUTE önce-tam-revoke-sonra-authenticated-grant.
-- ============================================================

begin;


-- ============================================================
-- 1. IDEMPOTENCY BENGERSİZLİĞİ (additive index)
--
-- student_question_attempts bir fact tablosudur (061); benzersizlik
-- yalnız training + client_key kombinasyonunda zorlanır.
-- ============================================================

create unique index if not exists uq_training_attempt_client_key
  on public.student_question_attempts (
    user_id,
    (metadata ->> 'client_key')
  )
  where attempt_context = 'training'
    and metadata ->> 'client_key' is not null;


-- ============================================================
-- 2. SUBMIT_TRAINING_ATTEMPT
-- ============================================================

create or replace function public.submit_training_attempt(
  p_question_id uuid,
  p_choice      text    default null,
  p_action      text    default null,
  p_time_ms     integer default null,
  p_client_key  uuid    default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user     uuid;
  v_choice   text;
  v_correct  text;
  v_result   text;
  v_time_ms  integer;
  v_prior    record;
begin
  -- ----------------------------------------------------------
  -- 2a. Kimlik ve zorunlu alanlar
  -- ----------------------------------------------------------
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  if p_question_id is null then
    raise exception 'Soru zorunludur.'
      using errcode = '22004';
  end if;

  if p_client_key is null then
    raise exception 'Idempotency anahtari (p_client_key) zorunludur.'
      using errcode = '22004';
  end if;

  -- Süre: negatif → 0, üst sınır 1 saat (metrik sağlığı).
  v_time_ms := least(greatest(coalesce(p_time_ms, 0), 0), 3600000);

  -- ----------------------------------------------------------
  -- 2b. Şık/eylem çözümlemesi → result YALNIZ burada üretilir
  -- ----------------------------------------------------------
  if p_choice is not null and p_action is not null then
    raise exception 'Secim ve eylem birlikte gonderilemez.'
      using errcode = 'P0001';
  end if;

  if p_choice is not null then
    v_choice := upper(btrim(p_choice));
    if v_choice not in ('A', 'B', 'C', 'D', 'E') then
      raise exception 'Gecersiz sik secimi.'
        using errcode = 'P0001';
    end if;

    -- Doğruluk kaynağı TEK: questions.correct_answer (CHECK: A..E).
    -- Aktif olmayan veya cevapsız soru puanlanamaz (fail-closed).
    select q.correct_answer
      into v_correct
      from public.questions q
     where q.id = p_question_id
       and q.is_active;

    if v_correct is null then
      raise exception 'Soru puanlanamaz; cevap anahtari yok ya da soru aktif degil.'
        using errcode = 'P0001';
    end if;

    v_result := case when v_choice = v_correct
                     then 'correct'
                     else 'wrong'
                end;

  elsif p_action is not null then
    if btrim(p_action) not in ('pass', 'timeout', 'blank') then
      raise exception 'Gecersiz eylem; pass|timeout|blank bekleniyor.'
        using errcode = 'P0001';
    end if;
    v_result := btrim(p_action);

  else
    raise exception 'Secim (p_choice) veya eylem (p_action) zorunludur.'
      using errcode = 'P0001';
  end if;

  -- ----------------------------------------------------------
  -- 2c. Gösterim kapısı: exposure olmadan cevap YOK
  --     (PK: user_id + question_id + attempt_context)
  -- ----------------------------------------------------------
  if not exists (
    select 1
      from public.student_question_exposures e
     where e.user_id = v_user
       and e.question_id = p_question_id
       and e.attempt_context = 'training'
  ) then
    raise exception 'Bu soru size antrenman baglaminda gosterilmedi.'
      using errcode = 'P0001';
  end if;

  -- ----------------------------------------------------------
  -- 2d. Idempotency ön-okuması (hızlı yol)
  -- ----------------------------------------------------------
  select a.id, a.attempt_number, a.result
    into v_prior
    from public.student_question_attempts a
   where a.user_id = v_user
     and a.attempt_context = 'training'
     and a.metadata ->> 'client_key' = p_client_key::text
   limit 1;

  if found then
    return jsonb_build_object(
      'attempt_id',     v_prior.id,
      'attempt_number', v_prior.attempt_number,
      'result',         v_prior.result,
      'duplicate',      true
    );
  end if;

  -- ----------------------------------------------------------
  -- 2e. Yazım: mevcut Faz 2 ingestion kurallarıyla
  --     (kullanıcı+soru advisory lock, attempt_number, 7 metrik)
  -- ----------------------------------------------------------
  begin
    perform public.ingest_student_attempt(
      p_question_id,
      'training',
      v_result,
      v_time_ms,
      null,
      jsonb_build_object(
        'client_key', p_client_key::text,
        'graded_by',  'db_correct_answer'
      )
    );
  exception
    -- Eşzamanlı aynı-anahtar yarışı: partial unique index ihlali.
    -- İkinci çağrının tüm kısmi etkileri geri alınır; ilk attempt döner.
    when unique_violation then
      select a.id, a.attempt_number, a.result
        into v_prior
        from public.student_question_attempts a
       where a.user_id = v_user
         and a.attempt_context = 'training'
         and a.metadata ->> 'client_key' = p_client_key::text
       limit 1;

      if not found then
        raise;
      end if;

      return jsonb_build_object(
        'attempt_id',     v_prior.id,
        'attempt_number', v_prior.attempt_number,
        'result',         v_prior.result,
        'duplicate',      true
      );
  end;

  -- ----------------------------------------------------------
  -- 2f. Minimal sonuç (allowlist; cevap anahtarı içermez)
  -- ----------------------------------------------------------
  select a.id, a.attempt_number, a.result
    into v_prior
    from public.student_question_attempts a
   where a.user_id = v_user
     and a.attempt_context = 'training'
     and a.metadata ->> 'client_key' = p_client_key::text
   limit 1;

  return jsonb_build_object(
    'attempt_id',     v_prior.id,
    'attempt_number', v_prior.attempt_number,
    'result',         v_prior.result,
    'duplicate',      false
  );
end;
$$;


-- ============================================================
-- 3. EXECUTE İZİNLERİ
-- ============================================================

revoke execute
on function public.submit_training_attempt(uuid, text, text, integer, uuid)
from public, anon, authenticated;

grant execute
on function public.submit_training_attempt(uuid, text, text, integer, uuid)
to authenticated;


-- ============================================================
-- 4. SAHTE-SONUÇ KAPANIŞI
--
-- 069'da bu fonksiyon icin PUBLIC EXECUTE geri alinmamisti (PostgreSQL
-- varsayilani); istemciler PUBLIC uzerinden cagirabiliyordu. Burada
-- tam revoke yapilir: public/anon/authenticated dahil HICBIR istemci
-- rolu EXECUTE kalmaz. service_role'a bilerek explicit grant
-- VERILMEDI; sunucu ici yol semadan dogrulandi: her iki fonksiyon da
-- SECURITY DEFINER + search_path='' + owner=postgres oldugundan,
-- submit_training_attempt govdesindeki cagri, cagiran rolun EXECUTE
-- iznine bakilmaksizin postgres kimligiyle cozulur. Competition
-- akisi bu RPC'yi hic kullanmadigi icin 021/023 etkilenmez.
-- ============================================================

revoke execute
on function public.ingest_student_attempt(uuid, text, text, integer, uuid, jsonb)
from public, anon, authenticated;

comment on function public.ingest_student_attempt(uuid, text, text, integer, uuid, jsonb) is
  'Sunucu-ici kullanim: istemciye KAPALI (070). Dogruluk istemciden alinamaz; training icin submit_training_attempt kullanilir.';


commit;
