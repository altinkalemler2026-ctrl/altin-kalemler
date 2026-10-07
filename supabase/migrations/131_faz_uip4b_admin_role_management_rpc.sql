-- ============================================================
-- 131_faz_uip4b_admin_role_management_rpc.sql
-- Altın Kalemler — UI-P4B: Güvenli admin rol mutasyonu sözleşmesi.
--
-- UI-P4A denetiminde kanıtlanan açıkların (bkz.
-- docs/reports/ui-p4a-admin-rol-izin-sozlesme-denetimi.md) append-only
-- kapanışı:
--
--   G1/G2  users.manage sahibi, ham PostgREST yüzeyinden kendine /
--          başka kullanıcıya super_admin dahil rol ATAYABİLİYORDU.
--          → admin_user_roles VE admin_role_permissions üzerindeki
--            "users managers manage ..." (FOR ALL) yazım politikaları
--            DROP edilir; anon/authenticated için INSERT/UPDATE/DELETE
--            GRANT'ları REVOKE edilir. ROLLER ARTIK YALNIZ RPC İLE
--            DEĞİŞİR (fail-closed).
--   G3     Son super-admin koruması yoktu.
--          → RPC yüzeyinde super_admin hedef rolü KATEGORİK olarak
--            reddedilir (atama da, kaldırma da). Bu, sayaç-tabanlı
--            korumadan GÜÇLÜDÜR: son super-admin'in RPC yoluyla
--            kaldırılması TASARIM OLARAK imkânsızdır.
--   G4     Rol değişiklikleri audit üretmiyordu.
--          → her başarılı mutasyon TEK, atomik admin_audit_log
--            kaydı yazar (aktör + hedef + before/after + action
--            code + performed_at). Idempotent tekrar audit YAZMAZ.
--   G5     Mutasyon merkezi RPC sözleşmesine bağlanır:
--            public.assign_admin_role / public.revoke_admin_role
--            (SECURITY INVOKER sarmalayıcı)
--            private.assign_admin_role / private.revoke_admin_role
--            (SECURITY DEFINER gerçek uygulama)
--          — 089/090 kanonik deseni: sabit search_path, PUBLIC/anon
--            EXECUTE yok, explicit authenticated EXECUTE.
--
-- FAİL-CLOSED KOŞULLAR:
--   - RPC aktörü auth.uid() ile zorunlu; anon çağrı imkânsız.
--   - Çağrıyı yalnız GERÇEK EN YÜKSEK yönetici (aktif super_admin
--     ataması) yapabilir; users.manage yetkisi TEK BAŞINA YETERLİ
--     DEĞİLDİR (saldırı senaryosu 3).
--   - Hiçbir kullanıcı kendi admin rolünü değiştiremez (self-scope).
--   - Hedef super_admin ise reddedilir; hata durumunda atama VE
--     audit YARIM KALMAZ (tek SQL gövde, exception → tümü geri alınır).
--   - UYDUrMA/otomatik rol atama YOK: ana DB'de aktif bir super_admin
--     yoksa her RPC çağrısı 'requires super admin' ile reddedilir;
--     migration uygulama zamanında super_admin aramaz (yapısal
--     değişiklik precondition'sız güvenlidir) ve sessizce kimseye rol
--     vermez.
--
-- SEMANTİK GARANTİLER:
--   - "admin reads own roles" SELECT politikası KORUNUR.
--   - private.has_admin_permission / private.current_user_has_admin_
--     permission (UI-P2A karar izinleri) DEĞİŞMEZ.
--   - admin_roles / admin_permissions katalogları SELECT-only kalır.
--   - service_role davranışı DEĞİŞMEZ (RLS bypass; istemci erişimi
--     EKLENMEZ) — dokümante: §4 G.
-- ============================================================

BEGIN;


-- ============================================================
-- 1. DML YÜZEYİNİN KAPATILMASI
-- ============================================================

-- G1/G2: ham PostgREST yazım kapısı. FOR ALL politikaları DROP edilir;
-- SELECT politikaları korunur.
DROP POLICY IF EXISTS "users managers manage user roles"
ON public.admin_user_roles;

DROP POLICY IF EXISTS "users managers manage role permissions"
ON public.admin_role_permissions;

DROP POLICY IF EXISTS "users managers manage admin roles"
ON public.admin_roles;

DROP POLICY IF EXISTS "users managers manage admin permissions"
ON public.admin_permissions;

-- GRANT katmanı: anon/authenticated DML ayrıcalıkları REVOKE.
-- SELECT GRANT'ları korunur (RLS politikaları satır görünümünü
-- yönetmeye devam eder).
REVOKE INSERT, UPDATE, DELETE
ON public.admin_user_roles
FROM anon, authenticated;

REVOKE INSERT, UPDATE, DELETE
ON public.admin_role_permissions
FROM anon, authenticated;

REVOKE INSERT, UPDATE, DELETE
ON public.admin_roles
FROM anon, authenticated;

REVOKE INSERT, UPDATE, DELETE
ON public.admin_permissions
FROM anon, authenticated;


-- ============================================================
-- 2. PRIVATE SECURITY DEFINER: ROL ATAMA
--
-- Sözleşme:
--   private.assign_admin_role(p_target_user_id uuid, p_role_code text)
--   → jsonb { status, target_user_id, role_code, audit_id? }
--
--   status = 'assigned'        (yeni atama + TEK audit)
--          | 'already_assigned' (idempotent tekrar; audit YOK)
--
-- Hatalar (P0001 / 22023):
--   'Human authentication required.'      → aktör yok
--   'Admin role management requires super admin.' → aktör super_admin değil
--   'Admins cannot change their own admin roles.' → self-scope
--   'Invalid admin role code.'            → kataloğa uygun değil /
--                                            inactive / super_admin
--   'Target user not found.'              → hedef auth.users'da yok
-- ============================================================

CREATE OR REPLACE FUNCTION private.assign_admin_role(
  p_target_user_id uuid,
  p_role_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor uuid;
  v_role  public.admin_roles%ROWTYPE;
  v_existing uuid;
  v_before text[] := '{}';
  v_audit_id uuid;
BEGIN
  v_actor := auth.uid();

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Human authentication required.';
  END IF;

  IF NOT private.is_current_user_super_admin() THEN
    RAISE EXCEPTION 'Admin role management requires super admin.';
  END IF;

  IF p_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Target user not found.';
  END IF;

  IF p_target_user_id = v_actor THEN
    RAISE EXCEPTION 'Admins cannot change their own admin roles.';
  END IF;

  -- Hedef gerçek bir auth kullanıcısı mı?
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'Target user not found.';
  END IF;

  -- Rol kataloğunda aktif mi? super_admin categorik reddedilir.
  SELECT * INTO v_role
    FROM public.admin_roles
   WHERE role_code = btrim(p_role_code)
     AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid admin role code.';
  END IF;

  IF v_role.role_code = 'super_admin' THEN
    RAISE EXCEPTION
      'The super admin role cannot be assigned or revoked through the admin role management interface.';
  END IF;

  -- Idempotent tekrar: aynı (user, role) ataması zaten varsa audit
  -- YAZILMADAN belirgin durum döner.
  SELECT aur.user_id INTO v_existing
    FROM public.admin_user_roles aur
   WHERE aur.user_id = p_target_user_id
     AND aur.role_id = v_role.id;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'status', 'already_assigned',
      'target_user_id', p_target_user_id,
      'role_code', v_role.role_code,
      'audit_id', NULL
    );
  END IF;

  -- Audit için önceki rol listesi
  SELECT array_agg(ar.role_code ORDER BY ar.role_code)
    INTO v_before
    FROM public.admin_user_roles aur
    JOIN public.admin_roles ar ON ar.id = aur.role_id
   WHERE aur.user_id = p_target_user_id;

  -- Atomik mutasyon + audit
  INSERT INTO public.admin_user_roles (user_id, role_id, assigned_by)
  VALUES (p_target_user_id, v_role.id, v_actor);

  INSERT INTO public.admin_audit_log (
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    before_data,
    after_data
  )
  VALUES (
    v_actor,
    'admin_user_role.assign',
    'admin_user_role',
    p_target_user_id,
    jsonb_build_object(
      'target_user_id', p_target_user_id,
      'role_codes', coalesce(to_jsonb(v_before), '[]'::jsonb)
    ),
    jsonb_build_object(
      'target_user_id', p_target_user_id,
      'role_codes',
        coalesce(to_jsonb(v_before), '[]'::jsonb) || to_jsonb(v_role.role_code),
      'added_role', v_role.role_code
    )
  )
  RETURNING id INTO v_audit_id;

  RETURN jsonb_build_object(
    'status', 'assigned',
    'target_user_id', p_target_user_id,
    'role_code', v_role.role_code,
    'audit_id', v_audit_id
  );
END;
$function$;


-- ============================================================
-- 3. PRIVATE SECURITY DEFINER: ROL KALDIRMA
--
--   status = 'revoked'         (kaldırma + TEK audit)
--          | 'already_revoked' (atama zaten yoktu; audit YOK)
--
--   G3: super_admin hedef rolü KATEGORİK reddedilir → son super-admin
--   RPC yoluyla asla kaldırılamaz (tasarım garantisi).
-- ============================================================

CREATE OR REPLACE FUNCTION private.revoke_admin_role(
  p_target_user_id uuid,
  p_role_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor uuid;
  v_role  public.admin_roles%ROWTYPE;
  v_removed integer;
  v_before text[] := '{}';
  v_other_super integer;
  v_audit_id uuid;
BEGIN
  v_actor := auth.uid();

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Human authentication required.';
  END IF;

  IF NOT private.is_current_user_super_admin() THEN
    RAISE EXCEPTION 'Admin role management requires super admin.';
  END IF;

  IF p_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Target user not found.';
  END IF;

  IF p_target_user_id = v_actor THEN
    RAISE EXCEPTION 'Admins cannot change their own admin roles.';
  END IF;

  SELECT * INTO v_role
    FROM public.admin_roles
   WHERE role_code = btrim(p_role_code)
     AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid admin role code.';
  END IF;

  -- G3 (savunma katmanı): hedef super_admin ise
  --   a) başka aktif super_admin YOKSA: son-admin koruması
  --   b) olsa bile: super_admin RPC yüzeyinden yönetilemez
  -- Her iki durumda da reddedilir; audit/atama YAZILMAZ.
  IF v_role.role_code = 'super_admin' THEN
    SELECT count(*) INTO v_other_super
      FROM public.admin_user_roles aur
      JOIN public.admin_roles ar ON ar.id = aur.role_id
     WHERE ar.role_code = 'super_admin'
       AND ar.is_active = true
       AND aur.user_id <> p_target_user_id;

    IF v_other_super = 0 THEN
      RAISE EXCEPTION 'Cannot remove the last super admin.';
    END IF;

    RAISE EXCEPTION
      'The super admin role cannot be assigned or revoked through the admin role management interface.';
  END IF;

  SELECT array_agg(ar.role_code ORDER BY ar.role_code)
    INTO v_before
    FROM public.admin_user_roles aur
    JOIN public.admin_roles ar ON ar.id = aur.role_id
   WHERE aur.user_id = p_target_user_id;

  DELETE FROM public.admin_user_roles
   WHERE user_id = p_target_user_id
     AND role_id = v_role.id;

  GET DIAGNOSTICS v_removed = ROW_COUNT;

  IF v_removed = 0 THEN
    RETURN jsonb_build_object(
      'status', 'already_revoked',
      'target_user_id', p_target_user_id,
      'role_code', v_role.role_code,
      'audit_id', NULL
    );
  END IF;

  INSERT INTO public.admin_audit_log (
    actor_user_id,
    action_code,
    entity_type,
    entity_id,
    before_data,
    after_data
  )
  VALUES (
    v_actor,
    'admin_user_role.revoke',
    'admin_user_role',
    p_target_user_id,
    jsonb_build_object(
      'target_user_id', p_target_user_id,
      'role_codes', coalesce(to_jsonb(v_before), '[]'::jsonb)
    ),
    jsonb_build_object(
      'target_user_id', p_target_user_id,
      'role_codes',
        (SELECT coalesce(jsonb_agg(DISTINCT r ORDER BY r), '[]'::jsonb)
           FROM unnest(v_before) r
          WHERE r <> v_role.role_code),
      'removed_role', v_role.role_code
    )
  )
  RETURNING id INTO v_audit_id;

  RETURN jsonb_build_object(
    'status', 'revoked',
    'target_user_id', p_target_user_id,
    'role_code', v_role.role_code,
    'audit_id', v_audit_id
  );
END;
$function$;


-- ============================================================
-- 4. PUBLIC SECURITY INVOKER SARMALEYİCİLER
-- ============================================================

CREATE OR REPLACE FUNCTION public.assign_admin_role(
  p_target_user_id uuid,
  p_role_code text
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT private.assign_admin_role(p_target_user_id, p_role_code);
$function$;

CREATE OR REPLACE FUNCTION public.revoke_admin_role(
  p_target_user_id uuid,
  p_role_code text
)
RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT private.revoke_admin_role(p_target_user_id, p_role_code);
$function$;


-- ============================================================
-- 5. GRANT YÜZEYİ (089/090 kanonik modeli)
-- ============================================================

REVOKE ALL
ON FUNCTION private.assign_admin_role(uuid, text)
FROM PUBLIC, anon, service_role;

GRANT EXECUTE
ON FUNCTION private.assign_admin_role(uuid, text)
TO authenticated;

REVOKE ALL
ON FUNCTION private.revoke_admin_role(uuid, text)
FROM PUBLIC, anon, service_role;

GRANT EXECUTE
ON FUNCTION private.revoke_admin_role(uuid, text)
TO authenticated;

REVOKE ALL
ON FUNCTION public.assign_admin_role(uuid, text)
FROM PUBLIC, anon, service_role;

GRANT EXECUTE
ON FUNCTION public.assign_admin_role(uuid, text)
TO authenticated;

REVOKE ALL
ON FUNCTION public.revoke_admin_role(uuid, text)
FROM PUBLIC, anon, service_role;

GRANT EXECUTE
ON FUNCTION public.revoke_admin_role(uuid, text)
TO authenticated;


-- ============================================================
-- 6. KORUMA İNVARİYANTLARI
--
--    Yeni PUBLIC yüzey anon/PUBLIC'e açılmadı; DML yüzeyi kapandı;
--    SELECT sözleşmesi korundu. Bu migration'ın güvenlik iddiası
--    bu invaryantların bozulmamasına dayanır.
-- ============================================================

DO $$
DECLARE
  v_leak text;
  v_policy_count integer;
  v_rls boolean;
  v_priv text;
BEGIN

  -- 6a: anon EXECUTE / PUBLIC EXECUTE sızıntısı YOK
  SELECT string_agg(
           format('%I.%I', n.nspname, p.proname),
           ', '
         )
    INTO v_leak
    FROM pg_proc p
    JOIN pg_namespace n
      ON n.oid = p.pronamespace
   WHERE p.proname IN (
           'assign_admin_role',
           'revoke_admin_role'
         )
     AND (
       has_function_privilege('anon', p.oid, 'EXECUTE')
       OR EXISTS (
         SELECT 1
         FROM pg_catalog.aclexplode(p.proacl) a
         WHERE a.grantee = 0
           AND a.privilege_type = 'EXECUTE'
       )
     );

  IF v_leak IS NOT NULL THEN
    RAISE EXCEPTION
      '131: private/public rol mutasyon yuzeyi sizdi, rollback gerekir: %', v_leak;
  END IF;

  -- 6b: admin_user_roles üzerinde TEK politik kalmalı (own-roles SELECT)
  SELECT count(*) INTO v_policy_count
    FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename = 'admin_user_roles';

  IF v_policy_count <> 1 THEN
    RAISE EXCEPTION
      '131: admin_user_roles politika sayisi %; 1 (own-roles SELECT) beklenir, rollback gerekir',
      v_policy_count;
  END IF;

  -- 6c: RLS dört tabloda da etkin kalmalı
  SELECT relrowsecurity INTO v_rls FROM pg_class
   WHERE oid = 'public.admin_user_roles'::regclass;
  IF v_rls IS NOT TRUE THEN
    RAISE EXCEPTION '131: admin_user_roles RLS kapandi, rollback gerekir';
  END IF;

  SELECT relrowsecurity INTO v_rls FROM pg_class
   WHERE oid = 'public.admin_role_permissions'::regclass;
  IF v_rls IS NOT TRUE THEN
    RAISE EXCEPTION '131: admin_role_permissions RLS kapandi, rollback gerekir';
  END IF;

  -- 6d: authenticated/anon DML ayrıcalıkları gerçekten kapanmış olmalı
  IF has_table_privilege('authenticated', 'public.admin_user_roles', 'INSERT')
     OR has_table_privilege('authenticated', 'public.admin_user_roles', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.admin_user_roles', 'DELETE') THEN
    RAISE EXCEPTION '131: authenticated DML yuzeyi hala acik, rollback gerekir';
  END IF;

  IF has_table_privilege('anon', 'public.admin_user_roles', 'INSERT') THEN
    RAISE EXCEPTION '131: anon DML yuzeyi hala acik, rollback gerekir';
  END IF;

  IF has_table_privilege('authenticated', 'public.admin_role_permissions', 'INSERT')
     OR has_table_privilege('authenticated', 'public.admin_role_permissions', 'DELETE') THEN
    RAISE EXCEPTION '131: admin_role_permissions DML yuzeyi hala acik, rollback gerekir';
  END IF;

  -- 6e: SELECT ayrıcalığı korunmalı (own-roles sözleşmesi)
  IF NOT has_table_privilege('authenticated', 'public.admin_user_roles', 'SELECT') THEN
    RAISE EXCEPTION '131: authenticated SELECT kayboldu, rollback gerekir';
  END IF;

  -- 6f: private yardımcılar (UI-P2A izin zinciri) sağlam kalmalı
  SELECT string_agg(format('%I.%I', n.nspname, p.proname), ', ')
    INTO v_priv
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'private'
     AND p.proname IN ('has_admin_permission',
                       'current_user_has_admin_permission',
                       'is_current_user_super_admin');

  IF v_priv IS NULL THEN
    RAISE EXCEPTION '131: private izin yardimcilari kayip, rollback gerekir';
  END IF;

END;
$$;


COMMIT;
