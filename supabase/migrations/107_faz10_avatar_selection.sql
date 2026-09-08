-- ============================================================
-- 107_faz10_avatar_selection.sql
-- Altin Kalemler - Faz 10: Guvenli avatar secimi + public profil
-- takma ad esitlemesi.
--
-- AMAC:
--   1) select_own_avatar(p_character_code): ogrenci, onayli ve
--      aktif katalogdaki YALNIZ 'default' unlock'lu karakteri
--      kendi loadout'una secer; student_public_profiles.avatar_key
--      sunucuda senkronize edilir (lig satirinda ayni avatar).
--      - Kimlik YALNIZ auth.uid()'den; user_id parametre YOK.
--      - Katalog dogrulamasi sunucuda: is_active = true AND
--        unlock_type = 'default'. Pasif, silinmis veya kilitli
--        (points/stars/achievement/purchase...) karakter FAIL-CLOSED
--        reddedilir. Ekonomi kurulmadan kilitli secim yapilamaz.
--      - XP/lig rating/yildiz/grade/tablo baskasi DOKUNULMAZ.
--      - Idempotent: ayni secim tekrar edilebilir.
--      - Rate limit: select_own_avatar 10 istek / 60 sn (075 deseni).
--   2) student_public_profiles takma ad esitleme trigger'i:
--      student_profiles.nickname guncellenince guncel takma ad
--      student_public_profiles satirina yansitilir (lig gosterimi
--      taze kalir). Satir yoksa hicbir sey yapilmaz (fail-closed;
--      ogrencinin pp satiri select_own_avatar ile olusur).
--
-- GUVENLIK NOTLARI:
--   - 093 kolon-ayricaligi DEGISMEZ: ogrenci student_profiles'ta
--     yalniz nickname kolonunu guncelleyebilir; grade_level fail-closed.
--   - 095 kurali DEGISMEZ: student_public_profiles'a ogrenci
--     dogrudan YAZAMAZ; yazma yalniz SECURITY DEFINER RPC (bu dosya)
--     ve esitleme trigger'i uzerinden, yalniz kendi satiri icin.
--   - Iki fonksiyon da SECURITY DEFINER + SET search_path = ''.
--     EXECUTE yalniz authenticated'a aciktir (anon/PUBLIC revoked).
--
-- IDEMPOTENT: create-or-replace + drop-if-exists.
-- Migration type: FORWARD ONLY. Mevcut migration'lar degismez.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1) select_own_avatar(p_character_code text) -> jsonb
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.select_own_avatar(
  p_character_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_code text;
  r_character public.characters%rowtype;
  v_grade smallint;
  v_nickname text;
  v_result jsonb;
BEGIN
  -- Kimlik dogrulamasi fail-closed.
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Kimlik dogrulamasi gerekli.'
      USING errcode = '42501';
  END IF;

  -- Rate limit (075 cekirdegi; fail-closed).
  PERFORM public._faz4_consume_rate_limit('select_own_avatar', 10, 60);

  v_code := trim(coalesce(p_character_code, ''));
  IF v_code = '' OR length(v_code) > 100 THEN
    RAISE EXCEPTION 'Gecersiz avatar.'
      USING errcode = 'P0001';
  END IF;

  -- Katalog dogrulamasi: yalniz AKTIF ve DEFAULT-unlock karakter.
  -- Pasif / silinmis / kilitli karakterler burada elenir.
  SELECT c.*
    INTO r_character
    FROM public.characters c
   WHERE c.character_code = v_code
     AND c.is_active = true
     AND c.unlock_type = 'default'
   LIMIT 1;

  IF r_character.id IS NULL THEN
    RAISE EXCEPTION 'Gecersiz avatar.'
      USING errcode = 'P0001';
  END IF;

  -- Ogrenci profili zorunlu (nickname/grade turetimi).
  SELECT sp.grade_level, sp.nickname
    INTO v_grade, v_nickname
    FROM public.student_profiles sp
   WHERE sp.id = v_user
   LIMIT 1;

  IF v_grade IS NULL OR v_nickname IS NULL THEN
    RAISE EXCEPTION 'Ogrenci profili bulunamadi.'
      USING errcode = 'P0001';
  END IF;

  -- 1a) Kendi loadout'u: yalniz KENDI satiri (upsert, idempotent).
  INSERT INTO public.student_loadouts (user_id, character_id)
  VALUES (v_user, r_character.id)
  ON CONFLICT (user_id) DO UPDATE
     SET character_id = EXCLUDED.character_id,
         updated_at = now();

  -- 1b) Kendi public profili: lig gosterimi icin avatar_key.
  --     Satir yoksa olusturulur (nickname/grade profilden turetilir);
  --     varsa yalniz avatar_key guncellenir. Diger alanlara
  --     (puanlar, rozetler, metadata) DOKUNULMAZ.
  INSERT INTO public.student_public_profiles
    (user_id, nickname, grade_level, avatar_key, is_visible)
  VALUES (v_user, v_nickname, v_grade, r_character.character_code, true)
  ON CONFLICT (user_id) DO UPDATE
     SET avatar_key = EXCLUDED.avatar_key,
         updated_at = now();

  SELECT jsonb_build_object(
           'character_code', r_character.character_code,
           'character_name', r_character.name,
           'avatar_key', r_character.character_code
         )
    INTO v_result;

  RETURN v_result;
END;
$$;

-- Yalniz authenticated; anon/PUBLIC fail-closed.
REVOKE ALL ON FUNCTION public.select_own_avatar(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.select_own_avatar(text)
  TO authenticated;

-- ------------------------------------------------------------
-- 2) Takma ad esitleme trigger'i (student_profiles -> pp)
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sync_public_profile_nickname()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Yalniz nickname (ve grade, meşru service-role değişimi ihtimali
  -- icin) degistiginde; pp satiri VARSA guncelle. Satir yoksa
  -- olusturmaz (avatar secimi olusturur) — fail-closed.
  IF NEW.nickname IS DISTINCT FROM OLD.nickname
     OR NEW.grade_level IS DISTINCT FROM OLD.grade_level THEN
    UPDATE public.student_public_profiles pp
       SET nickname = NEW.nickname,
           grade_level = NEW.grade_level,
           updated_at = now()
     WHERE pp.user_id = NEW.id;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trigger_sync_public_profile_nickname
  ON public.student_profiles;

CREATE TRIGGER trigger_sync_public_profile_nickname
AFTER UPDATE ON public.student_profiles
FOR EACH ROW
EXECUTE FUNCTION public.sync_public_profile_nickname();

REVOKE ALL ON FUNCTION public.sync_public_profile_nickname()
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.select_own_avatar(text) IS
  'Faz 10: ogrenci yalniz aktif + default-unlock katalog karakterini secer (auth.uid, fail-closed, rate limited); loadout + student_public_profiles.avatar_key sunucuda senkronize edilir.';

-- ------------------------------------------------------------
-- 3) Faz 9 profil RPC duzeltmesi (enkaz kaldirma, append-only):
--    get_own_gamification_profile security INVOKER'di ve govdesinde
--    internal yardimcilari (faz9_level_from_total_xp, _faz9_local_day,
--    ...) cagiriyordu; 103 bu yardimcilarin EXECUTE'unu
--    authenticated'dan aldiginden RPC gercek oturumda
--    'permission denied' ile dusuyordu (yalniz superuser baglamindaki
--    SQL QA bunu goremedi; ogrenci UI'inda kart hicbir zaman
--    gorunmuyordu).
--    Cozum (EN KUCUK guvenli duzeltme): RPC'yi SECURITY DEFINER ile
--    yeniden tanimla. Guvenlik sozlesi aynen korunur: kimlik yalniz
--    auth.uid()'den; yalniz KENDI satirlari okunur; DTO allowlist
--    (xp/streak/daily_quota/badges) aynidir; degistirme-pas-hata
--    yolu yoktur (salt-okunur). Internal yardimcilar istemcilere
--    ACILMAZ (revoke yerinde kalir).
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_own_gamification_profile()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user     uuid;
  v_total    bigint;
  v_level    integer;
  v_next_req bigint;
  v_day      date;
  v_used     integer;
  r_streak   public.student_streaks%rowtype;
  v_badges   jsonb;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Kimlik dogrulamasi gerekli.'
      USING errcode = '42501';
  END IF;

  SELECT coalesce(t.total_xp, 0)
    INTO v_total
    FROM public.student_xp_totals t
   WHERE t.user_id = v_user;

  v_level := public.faz9_level_from_total_xp(coalesce(v_total, 0));

  IF v_level < 50 THEN
    v_next_req := public.faz9_required_total_xp(v_level + 1);
  ELSE
    v_next_req := NULL;
  END IF;

  SELECT * INTO r_streak
    FROM public.student_streaks s
   WHERE s.user_id = v_user;

  v_day := public._faz9_local_day(now());

  SELECT c.questions_used
    INTO v_used
    FROM public.student_daily_question_counters c
   WHERE c.user_id = v_user
     AND c.quota_day = v_day;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'badge_code', b.badge_code,
        'name', d.name,
        'granted_at', b.granted_at
      )
      ORDER BY b.granted_at, b.badge_code
    ),
    '[]'::jsonb
  )
    INTO v_badges
    FROM public.student_badges b
    JOIN public.badge_definitions d
      ON d.badge_code = b.badge_code
   WHERE b.user_id = v_user
     AND d.is_active;

  RETURN jsonb_build_object(
    'xp', jsonb_build_object(
      'total', coalesce(v_total, 0),
      'level', v_level,
      'max_level', 50,
      'next_level_required_total_xp', v_next_req,
      'xp_to_next_level',
        CASE WHEN v_next_req IS NULL
             THEN NULL
             ELSE v_next_req - coalesce(v_total, 0)
        END
    ),
    'streak', jsonb_build_object(
      'current', coalesce(r_streak.current_streak, 0),
      'longest', coalesce(r_streak.longest_streak, 0),
      'last_activity_day', r_streak.last_activity_day
    ),
    'daily_quota', jsonb_build_object(
      'day', v_day,
      'questions_used', coalesce(v_used, 0),
      'limit', 500,
      'remaining', 500 - coalesce(v_used, 0)
    ),
    'badges', v_badges
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_own_gamification_profile()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.get_own_gamification_profile()
  TO authenticated;

COMMENT ON FUNCTION public.get_own_gamification_profile() IS
  'Faz 10: SECURITY DEFINER ile yeniden tanimlandi; invoker baglaminda internal yardimci EXECUTE izni olmadigi icin ogrenci oturumunda permission denied veriyordu. Kimlik yalniz auth.uid(); DTO allowlist ayni.';

COMMENT ON TABLE public.student_loadouts IS
  'Faz 10: ogrencinin aktif karakteri yalniz select_own_avatar RPC uzerinden (katalog dogrulamali) guncellenir.';

COMMIT;
