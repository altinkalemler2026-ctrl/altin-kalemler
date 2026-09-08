-- ============================================================
-- 106_faz9_ledger_cascade_guard.sql
-- Altın Kalemler - Migration Faz 9D (106): XP ledger cascade guard.
--
-- CI #48 BULGUSU (kanıtlanmış kök neden):
--   qa_faz2_local_validation.sql:1389 `delete from auth.users ...`
--   temizliği, student_xp_ledger.user_id FK'sinin ON DELETE
--   CASCADE'i (103) üzerinden ledger satırlarını silmeye çalışır;
--   Faz 9'un append-only guard'ı (103 guard_student_xp_ledger_
--   append_only) HER DELETE'i engellediği için cascade tamamlanamaz
--   (P0001 → ON_ERROR_STOP → CI Step 17 failure).
--   Aynı kısıt üretimde yetkili hesap silme yolunu da bloke eder.
--
-- DÜZELTME (en küçük kapsam — CREATE OR REPLACE; trigger, owner,
-- SECURITY INVOKER, search_path ve ACL'ler AYNEN korunur):
--   - UPDATE: her rol ve her durumda YASAK (değişmedi).
--   - DELETE: OLD.user_id sahibi auth.users satırı HÂLÂ MEVCUTSA
--     yasak (doğrudan silme; postgres/service_role dahil).
--     Sahip satırı zaten silinmişse (gerçek FK cascade temizliği /
--     hesap silme) izinli.
--   - auth.users okunamayan roller fail-closed kalır (istisna ile
--     engellenir) — güvenlik zayıflatılmaz.
--
-- YASAK YAKLAŞIMLAR (uyulmadı): trigger kaldırma, FK/CASCADE
-- kaldırma, session_replication_role, pg_trigger_depth bypass,
-- istemci bayrağı/GUC ile silme izni.
--
-- IDEMPOTENCY: create or replace idempotent; ikinci uygulama aynı
-- davranışı üretir.
-- ============================================================

begin;


create or replace function public.guard_student_xp_ledger_append_only()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    -- Gerçek FK cascade temizliği: üst auth.users satırı bu noktada
    -- zaten silinmiştir; cascade'in tamamlanmasına izin verilir.
    -- Sahip hâlâ yaşıyorsa doğrudan silme girişimidir → yasak.
    if not exists (
      select 1
        from auth.users u
       where u.id = old.user_id
    ) then
      return old;
    end if;
  end if;

  raise exception
    'XP ledger append-only dir; guncelleme ve silme yasaktir.'
    using errcode = 'P0001';
end;
$$;


-- ACL savunmacı teyit (103 ile aynı; create or replace ACL'leri
-- korur, teyit idempotenttir):
revoke execute
on function public.guard_student_xp_ledger_append_only()
from public, anon, authenticated;

comment on function public.guard_student_xp_ledger_append_only() is
  'Faz 9D: UPDATE her zaman yasak. DELETE yalniz ust auth.users satiri silinmisken (FK cascade / hesap silme) izinli; canli sahibi olan dogrudan silmeler ve auth.users okunamayan roller fail-closed engellenir.';


commit;
