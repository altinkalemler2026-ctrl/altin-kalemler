-- ============================================================
-- 059_07_competition_vault_member_limit.sql
-- Altın Kalemler - Migration 059 Faz 1
--
-- Competition / 1v1 paket kasalarında üye sayısı sınırı.
--
-- 059 kuralı:
--   - "Her competition/1v1 kasası maksimum 5 soru taşımalı."
--   - "5 soruluk yarışma kasaları question_vaults yapısının yerine
--     geçmemeli" -> paketler question_vaults üzerinde,
--     vault_type IN ('competition','one_v_one') ile modellenir
--     (048); büyük akademik havuzlar 'academic' tip olarak kalır.
--
-- Kapsanan yazım yolları:
--   1. question_vault_memberships INSERT
--   2. question_vault_memberships vault_id değiştiren UPDATE
--      (eski kasadan çıkış ihlal üretemez; hedef kasa kontrol edilir)
--   3. question_vault_memberships membership_status aktife dönen UPDATE
--   4. question_vaults UPDATE ile academic -> competition/one_v_one
--      tip geçişi (mevcut üye sayısı 5'i aşıyorsa geçiş reddedilir)
--
-- SAYIM SEMANTİĞİ:
--   Limit yalnız membership_status = 'active' üyelere uygulanır;
--   inactive/blocked/pending_review satırlar kasanın taşıdığı soru
--   sayısını temsil etmez (051 partial index semantiğiyle uyumlu).
--   Aktif olmayan satır yazımları limitsizdir (F-2).
--
-- EŞZAMANLILIK:
--   Paket tipli hedef kasada sayımdan önce parent satır kilidi
--   (SELECT ... FOR UPDATE) alınır; eşzamanlı üye yazımları kasa
--   bazında serileşir ve ikinci işlem güncel sayıyı görür.
--   Detay: fonksiyon gövdesindeki F-1 yorumu.
--
-- DOKUNULMAYANLAR:
--   Yarışma başındaki snapshot kilidi mevcut yapıda zaten vardır ve
--   bozulmaz: competitions.question_count CHECK (022) +
--   validate_competition_question_limit trigger (022) +
--   competition_questions satırlarının yarışma başında yazılması
--   (019). Bu migration yalnız kasa (vault) tarafını sınırlar;
--   yarışma nesnesine dokunmaz.
--
-- Güvenlik:
--   - Fonksiyonlar SECURITY INVOKER'dır; bu tablolara yazabilen roller
--     (service_role / postgres / admin yolları) üye satırlarını zaten
--     okuyabilir. İstemcilerin bu tablolarda yazma yetkisi yoktur.
--   - search_path sabittir ('').
--   - RPC yüzeyi açılmaz: EXECUTE PUBLIC/anon/authenticated'dan alınır
--     (trigger çağrımı EXECUTE yetkisi gerektirmez; CREATE TRIGGER
--     sahibi postgres'tir).
--
-- Idempotency: create or replace function + drop trigger if exists.
-- ============================================================

begin;


-- ============================================================
-- 1. LİMİT DOĞRULAMA FONKSİYONU
-- ============================================================

create or replace function public.validate_competition_vault_member_limit()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_vault_type         text;
  v_active_member_count integer;
begin

  -- ------------------------------------------------------------
  -- A) question_vault_memberships yazımları
  --    BEFORE tetiminde satır henüz tabloda NEW değerleriyle yer
  --    almadığı için sayım NEW satırını içermez; +1 ile kontrol edilir.
  -- ------------------------------------------------------------
  if tg_table_name = 'question_vault_memberships' then

    -- vault_id ve status değişmediyse limit etkilenmez.
    if tg_op = 'UPDATE'
       and new.vault_id is not distinct from old.vault_id
       and new.membership_status is not distinct from old.membership_status
    then
      return new;
    end if;

    -- F-2 düzeltmesi: Limit yalnız AKTIF üyelere uygulanır.
    -- Inactive/blocked/pending_review satırlar kasanın taşıdığı soru
    -- sayısını temsil etmez; bu satırların INSERT'i (veya aktif olmayan
    -- durumda kalırken kasalar arası taşınması) aktif üye sayımını
    -- değiştirmediğinden limitsiz geçer. Bu guard olmadan dolu bir
    -- competition/one_v_one kasasına inactive üye eklemek hatalı
    -- biçimde reddediliyordu (sayım +1 varsayımı yalnız aktifler
    -- için geçerlidir).
    if new.membership_status is distinct from 'active' then
      return new;
    end if;

    select qv.vault_type
      into v_vault_type
      from public.question_vaults qv
     where qv.id = new.vault_id;

    if v_vault_type is null then
      raise exception 'Vault not found for member limit validation.';
    end if;

    if v_vault_type in ('competition', 'one_v_one') then

      -- F-1 düzeltmesi (eşzamanlılık / TOCTOU):
      --
      -- COUNT(*) kilit almadığı için, READ COMMITTED altında iki
      -- eşzamanlı INSERT/UPDATE birbirinin commit edilmemiş satırını
      -- görmez ve ikisi de limiti geçebilir.
      --
      -- Çözüm: sayımdan HEMEN ÖNCE hedef kasa satırını kilitle.
      --   - İkinci işlem bu kilitte birincinin commit'ini bekler;
      --     READ COMMITTED'te bekleyen ifade yeni snapshot alır ve
      --     güncel aktif üye sayısını görür -> doğru reddedilir.
      --   - Kilit yalnız paket tipli hedef kasada alınır; akademik /
      --     kaynak gibi büyük havuzlara yazımlar serileştirilmez.
      --   - Kilitsiz okunan ilk vault_type eski olabilir; bu yüzden
      --     tür, kilit altında yeniden okunup çift kontrol edilir
      --     (akademik->paket geçişi penceresini kapatır). Ters yönlü
      --     yarış (paket iken üye ekleme x tür geçişi) Branch B'nin
      --     kendi satır kilidiyle zaten serileşir.
      perform 1
        from public.question_vaults qv
       where qv.id = new.vault_id
         for update;

      -- Kilit altında güncel türü tekrar oku (EvalPlanQual: dönen
      -- satır, kilidin alındığı andaki en güncel committed satırdır).
      select qv.vault_type
        into v_vault_type
        from public.question_vaults qv
       where qv.id = new.vault_id
         for update;

      if v_vault_type in ('competition', 'one_v_one') then

        select count(*)
          into v_active_member_count
          from public.question_vault_memberships m
         where m.vault_id = new.vault_id
           and m.membership_status = 'active';

        if v_active_member_count + 1 > 5 then
          raise exception
            'Competition/one_v_one vault member limit exceeded. Max: 5, active members: %',
            v_active_member_count;
        end if;

      end if;

    end if;

    return new;
  end if;

  -- ------------------------------------------------------------
  -- B) question_vaults UPDATE
  --    Paket türlü (veya paket türüne geçen) kasanın mevcut aktif
  --    üye sayısı 5'i aşamaz. Bu dal, academic -> competition /
  --    one_v_one geçişlerini de kapatır.
  -- ------------------------------------------------------------
  if tg_table_name = 'question_vaults'
     and tg_op = 'UPDATE'
     and new.vault_type in ('competition', 'one_v_one')
  then

    select count(*)
      into v_active_member_count
      from public.question_vault_memberships m
     where m.vault_id = new.id
       and m.membership_status = 'active';

    if v_active_member_count > 5 then
      raise exception
        'Vault cannot be typed as competition/one_v_one: active member count (%) exceeds max 5.',
        v_active_member_count;
    end if;

  end if;

  return new;
end;
$$;


-- ============================================================
-- 2. TRIGGERLAR
-- ============================================================

drop trigger if exists trg_vault_memberships_pack_limit
  on public.question_vault_memberships;

create trigger trg_vault_memberships_pack_limit
before insert or update on public.question_vault_memberships
for each row
execute function public.validate_competition_vault_member_limit();


drop trigger if exists trg_question_vaults_pack_limit
  on public.question_vaults;

create trigger trg_question_vaults_pack_limit
before update on public.question_vaults
for each row
execute function public.validate_competition_vault_member_limit();


-- ============================================================
-- 3. EXECUTE İZİNLERİ
--
-- Trigger fonksiyonlarının tetiklenmesi EXECUTE gerektirmez;
-- revoke yalnız RPC/Data API yüzeyinden doğrudan çağrıyı kapatır.
-- ============================================================

revoke execute
on function public.validate_competition_vault_member_limit()
from public, anon, authenticated;


commit;


-- ============================================================
-- 4. DOĞRULAMA
-- ============================================================

select
  c.relname as table_name,
  t.tgname as trigger_name
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and t.tgname in (
    'trg_vault_memberships_pack_limit',
    'trg_question_vaults_pack_limit'
  )
order by c.relname;
