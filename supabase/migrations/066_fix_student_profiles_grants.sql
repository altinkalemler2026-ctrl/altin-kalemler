-- ============================================================
-- 066_fix_student_profiles_grants.sql
--
-- student_profiles ACL duzeltmesi (fix-forward).
--
-- Neden:
--   Yeni CLI davranisinda postgres tarafindan olusturulan
--   tablolar otomatik expose edilmediginden, 001'deki RLS
--   politikalari yetki VERMEDIGI icin authenticated hicbir
--   veri erisimine sahip olmuyordu (signup upsert akisi kirik).
--   001 production'da zaten uygulandigindan 001'e yapilan
--   duzeltme remote'a gitmez; her ortamda deterministik
--   yakinsama icin ayni guvenli izin modeli burada idempotent
--   olarak tekrar uygulanir.
--
-- Model (001 ile birebir):
--   - anon          : REVOKE ALL.
--   - authenticated : SELECT, INSERT, UPDATE (RLS: select_own/
--                     update_own/insert_own -> yalniz kendi satiri;
--                     DELETE/TRUNCATE/REFERENCES/TRIGGER kapali).
--   - service_role  : SELECT, INSERT, UPDATE, DELETE.
--   - PUBLIC'e tablo erisimi verilmez (legacy default ACL kalinti-
--                     larinin da temizlenmesi icin acik revoke).
--
-- RLS politikalari ve schedule_profile guard trigger'i korunur;
-- bu dosya yalniz ACL yuzeyini duzenler.
-- ============================================================

begin;

revoke all on table public.student_profiles
from public;

revoke all on table public.student_profiles
from anon, authenticated;

grant select, insert, update
on public.student_profiles
to authenticated;

grant select, insert, update, delete
on public.student_profiles
to service_role;

commit;
