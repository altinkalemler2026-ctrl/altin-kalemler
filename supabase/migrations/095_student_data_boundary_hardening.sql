-- ============================================================
-- 095_student_data_boundary_hardening.sql
-- Altın Kalemler - Öğrenci veri sınırı ve ödül güvenliği
--
-- KAPSAM (Faz 1):
--   1) student_public_profiles okuma politikası SINIF-İZOLE edilir.
--      015'teki politika yalnız is_visible şartı koyduğu için öğrenci
--      BAŞKA SINIFTAKI öğrencilerin public profilini okuyabiliyordu.
--      Yeni politika: kendi profili VEYA aynı sınıftan görünür profil.
--      088 admin policy'si ayrı permissive politika olduğundan admin
--      okuma yolu korunur.
--   2) student_loadouts doğrudan yazımı KAPATILIR (INSERT/UPDATE/
--      DELETE yetkileri geri alınır; SELECT kendi satırı kalır).
--      Sahip olunmayan karakter/kozmetiğin kuşanılması riski böylece
--      kapanır; kuşanma artık yalnız sunucu-otoriter RPC ile yapılır.
--   3) Sunucu-otoriter kuşanma RPC'leri eklenir:
--        equip_student_character(uuid)
--        unequip_student_character()
--        equip_student_cosmetic(uuid, boolean)
--      Envanter sahipliği (student_characters / student_cosmetics),
--      aktif ürün durumu ve kullanıcı kimliği (auth.uid()) RPC içinde
--      doğrulanır. öğrenci loadout'a asla doğrudan yazamaz.
--   4) Ödül/envanter/puanlama tablolarına savunma derinliği REVOKE:
--      öğrenci/anon cüzdan, defter, envanter, public profil, liderlik
--      ve lig tablolarına doğrudan yazamaz (SELECT meşru own/same-grade
--      politikalarıyla korunur). student_visibility_settings öğrencinin
--      kendi görünürlük tercihleri olduğundan own-write AYNEN kalır.
--   5) PII minimizasyonu: student_public_profiles yalnız güvenli takma
--      ad + oyun verisi taşır (gerçek ad/e-posta/telefon/okul kolonu
--      YOK); bilgi COMMENT ile sabitlenir.
--
-- BOZULMAYAN AKIŞLAR:
--   - Öğrenci dashboard'ı profili student_profiles'tan okur (etkilenmez).
--   - 088 admin okuma politikaları korunur.
--   - 015 leaderboard same-grade okuma politikası korunur.
--   - Öğrenci görünürlük tercihleri (own-write) korunur.
--   - Antrenman/yarışma akışları bu tablolara dokunmaz.
--
-- IDEMPOTENT: DROP/CREATE POLICY + REVOKE/GRANT tekrarlanabilir;
-- RPC create-or-replace.
-- Migration type: FORWARD ONLY. 001–094 değişmez.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. student_public_profiles: sınıf-izole görünürlük
-- ============================================================

DROP POLICY IF EXISTS "authenticated read visible public profiles"
ON public.student_public_profiles;

CREATE POLICY "same grade visible public profiles or self"
ON public.student_public_profiles
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR (
    is_visible = TRUE
    AND grade_level = (
      SELECT sp.grade_level
        FROM public.student_profiles sp
       WHERE sp.id = auth.uid()
    )
  )
);

-- Public profil yalnız sunucu tarafında yazılır (bugün yazan akış
-- yoktur); öğrenci/anon doğrudan yazamaz.
REVOKE INSERT, UPDATE, DELETE ON TABLE public.student_public_profiles FROM authenticated;
REVOKE ALL ON TABLE public.student_public_profiles FROM anon;

COMMENT ON TABLE public.student_public_profiles IS
  'V1 (095): ogrencinin halka acik oyun kimligi. PII minimizasyonu: yalniz guvenli takma ad + oyun verisi; gercek ad/e-posta/telefon/okul kolonu TASIMAZ. Okuma: kendi profili VEYA ayni siniftan is_visible profil (admin policy 088 ayridir). Yazim yalniz sunucu tarafindandir.';

-- ============================================================
-- 2. student_loadouts: doğrudan yazım kapanır
-- ============================================================

REVOKE INSERT, UPDATE, DELETE ON TABLE public.student_loadouts FROM authenticated;
REVOKE ALL ON TABLE public.student_loadouts FROM anon;

-- ============================================================
-- 3. Sunucu-otoriter kuşanma RPC'leri
-- ============================================================

CREATE OR REPLACE FUNCTION public.equip_student_character(
  p_character_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user uuid;
  v_owned boolean;
  v_active boolean;
BEGIN
  v_user := auth.uid();

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Kimlik dogrulamasi gerekli.'
      USING errcode = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1
      FROM public.student_characters sc
     WHERE sc.user_id = v_user
       AND sc.character_id = p_character_id
  )
  INTO v_owned;

  IF NOT v_owned THEN
    RAISE EXCEPTION 'Karakter envanterinde bulunmuyor.'
      USING errcode = 'P0001';
  END IF;

  SELECT c.is_active INTO v_active
    FROM public.characters c
   WHERE c.id = p_character_id;

  IF v_active IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Karakter kullanimda degil.'
      USING errcode = 'P0001';
  END IF;

  INSERT INTO public.student_loadouts
    (user_id, character_id, equipped_items)
  VALUES
    (v_user, p_character_id, '{}'::jsonb)
  ON CONFLICT (user_id) DO UPDATE
    SET character_id = EXCLUDED.character_id,
        updated_at   = now();

  RETURN jsonb_build_object(
    'equipped', 'character',
    'character_id', p_character_id
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.unequip_student_character()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user uuid;
BEGIN
  v_user := auth.uid();

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Kimlik dogrulamasi gerekli.'
      USING errcode = '42501';
  END IF;

  UPDATE public.student_loadouts
     SET character_id = NULL,
         updated_at   = now()
   WHERE user_id = v_user;

  RETURN jsonb_build_object('equipped', 'none');
END;
$fn$;

CREATE OR REPLACE FUNCTION public.equip_student_cosmetic(
  p_cosmetic_item_id uuid,
  p_equip boolean DEFAULT TRUE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user uuid;
  v_owned boolean;
  v_item_type text;
  v_current jsonb;
BEGIN
  v_user := auth.uid();

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Kimlik dogrulamasi gerekli.'
      USING errcode = '42501';
  END IF;

  SELECT ci.item_type INTO v_item_type
    FROM public.cosmetic_items ci
   WHERE ci.id = p_cosmetic_item_id
     AND ci.is_active = TRUE;

  IF v_item_type IS NULL THEN
    RAISE EXCEPTION 'Kozmetik ogesi bulunamadi.'
      USING errcode = 'P0001';
  END IF;

  IF p_equip THEN
    SELECT EXISTS (
      SELECT 1
        FROM public.student_cosmetics scx
       WHERE scx.user_id = v_user
         AND scx.cosmetic_item_id = p_cosmetic_item_id
    )
    INTO v_owned;

    IF NOT v_owned THEN
      RAISE EXCEPTION 'Kozmetik envanterinde bulunmuyor.'
        USING errcode = 'P0001';
    END IF;
  END IF;

  -- Own loadout'u hazirla (yoksa olustur).
  INSERT INTO public.student_loadouts (user_id, equipped_items)
  VALUES (v_user, '{}'::jsonb)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT l.equipped_items INTO v_current
    FROM public.student_loadouts l
   WHERE l.user_id = v_user
     FOR UPDATE;

  IF p_equip THEN
    -- Ayni tip baska ogense overwrite; tek kusanim/tip.
    v_current := jsonb_build_object(v_item_type, p_cosmetic_item_id)
                 || (v_current - v_item_type);
  ELSE
    v_current := v_current - v_item_type;
  END IF;

  UPDATE public.student_loadouts
     SET equipped_items = v_current,
         updated_at     = now()
   WHERE user_id = v_user;

  RETURN jsonb_build_object(
    'item_type', v_item_type,
    'equipped', p_equip,
    'equipped_items', v_current
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.equip_student_character(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.equip_student_character(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.unequip_student_character() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unequip_student_character() TO authenticated;

REVOKE ALL ON FUNCTION public.equip_student_cosmetic(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.equip_student_cosmetic(uuid, boolean) TO authenticated;

-- ============================================================
-- 4. Ödül / envanter / sıralama tablolarına savunma derinliği
--    (SELECT meşru own/same-grade politikalarıyla korunur;
--     öğrenci/anon doğrudan YAZAMAZ.)
-- ============================================================

REVOKE INSERT, UPDATE, DELETE ON TABLE public.student_wallets          FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.reward_transactions      FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.student_characters       FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.student_cosmetics        FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.leaderboard_entries      FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.leaderboard_snapshots    FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.student_league_memberships FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.student_league_history   FROM authenticated;

REVOKE ALL ON TABLE public.student_wallets          FROM anon;
REVOKE ALL ON TABLE public.reward_transactions      FROM anon;
REVOKE ALL ON TABLE public.student_characters       FROM anon;
REVOKE ALL ON TABLE public.student_cosmetics        FROM anon;
REVOKE ALL ON TABLE public.leaderboard_entries      FROM anon;
REVOKE ALL ON TABLE public.leaderboard_snapshots    FROM anon;
REVOKE ALL ON TABLE public.student_league_memberships FROM anon;
REVOKE ALL ON TABLE public.student_league_history   FROM anon;

COMMENT ON TABLE public.student_loadouts IS
  'V1 (095): aktif karakter/kozmetik kusanma durumu. Ogrenci dogrudan yazamaz; yalniz equip_student_character / equip_student_cosmetic / unequip_student_character RPCleri ile, envanter sahipligi sunucuda dogrulanarak degisir.';

COMMIT;
