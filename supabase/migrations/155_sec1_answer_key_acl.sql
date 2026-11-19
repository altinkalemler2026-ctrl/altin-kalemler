-- ============================================================
-- 155_sec1_answer_key_acl.sql — AK-SEC-ANSWER-01 (9 Kasım 2026)
--
-- SEC-1: public.get_internal_correct_answer fonksiyonunun EXECUTE
-- izimi zincir DIŞINDA anon ve authenticated rollerine verilmiştir
-- (canlı proacl: postgres=X, anon=X, authenticated=X, service_role=X;
-- 021 REVOKE FROM PUBLIC ile kurmuş, 025 anon/auth'u da geri almış,
-- 080 yalnız search_path sertleştirmiş; zincirde bu grant'ı veren
-- hiçbir migration YOK — supabase_migrations.statements taraması
-- 2026-11-09'da doğrulandı). Fonksiyon gövdesinde kimlik kontrolü
-- bulunmadığından doğru cevap, soru UUID'sini bilen her istemciye
-- sızabilmektedir.
--
-- EN KÜÇÜK DÜZELTME (yalnız izin matrisi):
--   * PUBLIC, anon, authenticated → EXECUTE tam geri alınır (42501).
--   * service_role'ün MEVCUT izni korunur (zincir içi sunucu yolunda
--     doğrudan çağıran yok; yine de mevcut durumu bozmamak için
--     dokunulmaz). YENİ GRANT VERİLMEZ.
--   * Fonksiyon silinmez; gövde/imza/owner/SECURITY DEFINER/
--     search_path='' değiştirilmez; puan veya cevap kontrol
--     algoritmasına dokunulmaz.
--   * İç çağrı zinciri etkilenmez: tek gerçek çağıran
--     private.submit_competition_answer'dır (SECURITY DEFINER,
--     owner=postgres) ve owner haklarıyla çalışmaya devam eder.
--   * Antrenman değerlendirme private.submit_training_attempt yolu
--     correct_answer'ı TABLODAN (definer owner) okur; bu fonksiyonu
--     hiç kullanmaz — etkilenmez.
--
-- İÇERİK (fail-closed):
--   1) REVOKE (idempotent);
--   2) DO bloğu: fonksiyon yoksa PATLAR (kopya eksiği fark edilir);
--      REVOKE sonrası anon/authenticated EXECUTE hâlâ görünüyorsa
--      PATLAR; service_role izni bu migration öncesi X idi ise
--      sonrası da X olmak zorundadır, düştüyse PATLAR.
-- Tekrar uygulanabilir: REVOKE tekrarda no-op, assertion'lar geçer.
-- ============================================================

-- Ölçüm: migration öncesi service_role izni (koruma hedefi).
drop table if exists _sec1_pre;
create temp table _sec1_pre (pre_svc boolean);
insert into _sec1_pre
select has_function_privilege(
         'service_role',
         'public.get_internal_correct_answer(uuid)'::regprocedure,
         'EXECUTE');

REVOKE ALL ON FUNCTION public.get_internal_correct_answer(uuid)
  FROM PUBLIC, anon, authenticated;

DO $sec1$
declare
  v_oid  oid;
  v_pre  boolean;
begin
  select p.oid into v_oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'get_internal_correct_answer'
     and pg_get_function_identity_arguments(p.oid) = 'p_question_id uuid';

  if v_oid is null then
    raise exception 'SEC1: public.get_internal_correct_answer(uuid) bulunamadi — kopya/zincir tutarsizligi; fail-closed.'
      using errcode = 'P0001';
  end if;

  if has_function_privilege('anon', v_oid, 'EXECUTE')
     or has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'SEC1: REVOKE sonrasi anon/authenticated EXECUTE henuz gorunuyor — varsilmamis ACL mirasi; fail-closed.'
      using errcode = 'P0001';
  end if;

  select pre_svc into v_pre from _sec1_pre limit 1;

  if v_pre and not has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'SEC1: service_role EXECUTE izni beklenmedik sekilde dustu — sunucu yolu kirilir; fail-closed.'
      using errcode = 'P0001';
  end if;

  raise notice 'SEC1 OK: get_internal_correct_answer — anon/authenticated/PUBLIC EXECUTE yok; service_role korundu';
end;
$sec1$;
