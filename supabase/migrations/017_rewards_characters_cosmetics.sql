-- 017_rewards_characters_cosmetics.sql
-- Altın Kalemler ödül, yıldız, karakter ve kozmetik altyapısı.

-- =========================================================
-- 1. KARAKTERLER
-- =========================================================

CREATE TABLE IF NOT EXISTS public.characters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  character_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  sort_order integer NOT NULL DEFAULT 0,

  rarity text NOT NULL DEFAULT 'common'
    CHECK (
      rarity IN (
        'common',
        'rare',
        'epic',
        'legendary',
        'special'
      )
    ),

  image_key text,

  unlock_type text NOT NULL DEFAULT 'default'
    CHECK (
      unlock_type IN (
        'default',
        'points',
        'stars',
        'achievement',
        'league',
        'season',
        'purchase',
        'special'
      )
    ),

  unlock_value integer
    CHECK (
      unlock_value IS NULL
      OR unlock_value >= 0
    ),

  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.characters
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read active characters"
ON public.characters
FOR SELECT
TO authenticated
USING (is_active = true);

DROP TRIGGER IF EXISTS trigger_characters_set_updated_at
ON public.characters;

CREATE TRIGGER trigger_characters_set_updated_at
BEFORE UPDATE ON public.characters
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 2. KOZMETİK ÜRÜNLER
-- =========================================================

CREATE TABLE IF NOT EXISTS public.cosmetic_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  item_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  item_type text NOT NULL
    CHECK (
      item_type IN (
        'shoes',
        'cape',
        'shirt',
        'shorts',
        'hat',
        'glasses',
        'accessory',
        'effect',
        'background',
        'frame',
        'title',
        'badge',
        'custom'
      )
    ),

  rarity text NOT NULL DEFAULT 'common'
    CHECK (
      rarity IN (
        'common',
        'rare',
        'epic',
        'legendary',
        'special'
      )
    ),

  asset_key text,

  compatible_character_code text,

  unlock_type text NOT NULL DEFAULT 'stars'
    CHECK (
      unlock_type IN (
        'free',
        'points',
        'stars',
        'achievement',
        'league',
        'season',
        'purchase',
        'special'
      )
    ),

  unlock_value integer
    CHECK (
      unlock_value IS NULL
      OR unlock_value >= 0
    ),

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cosmetic_items_type
ON public.cosmetic_items(item_type);

ALTER TABLE public.cosmetic_items
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read active cosmetic items"
ON public.cosmetic_items
FOR SELECT
TO authenticated
USING (is_active = true);

DROP TRIGGER IF EXISTS trigger_cosmetic_items_set_updated_at
ON public.cosmetic_items;

CREATE TRIGGER trigger_cosmetic_items_set_updated_at
BEFORE UPDATE ON public.cosmetic_items
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 3. ÖĞRENCİ CÜZDANI
-- Puan, yıldız ve ileride başka para birimleri.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.student_wallets (
  user_id uuid PRIMARY KEY
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  points integer NOT NULL DEFAULT 0
    CHECK (points >= 0),

  stars integer NOT NULL DEFAULT 0
    CHECK (stars >= 0),

  balances jsonb NOT NULL DEFAULT '{}'::jsonb,

  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.student_wallets
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own wallet"
ON public.student_wallets
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

DROP TRIGGER IF EXISTS trigger_student_wallets_set_updated_at
ON public.student_wallets;

CREATE TRIGGER trigger_student_wallets_set_updated_at
BEFORE UPDATE ON public.student_wallets
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 4. ÖDÜL İŞLEM GEÇMİŞİ
-- Nereden kaç puan/yıldız geldi?
-- =========================================================

CREATE TABLE IF NOT EXISTS public.reward_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  reward_type text NOT NULL
    CHECK (
      reward_type IN (
        'points',
        'stars',
        'badge',
        'cosmetic',
        'character',
        'title',
        'custom'
      )
    ),

  amount integer,

  source_type text NOT NULL
    CHECK (
      source_type IN (
        'practice',
        'competition',
        'league',
        'achievement',
        'training_level',
        'season',
        'admin',
        'purchase',
        'special',
        'custom'
      )
    ),

  source_reference_id uuid,

  description text,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reward_transactions_user
ON public.reward_transactions(
  user_id,
  created_at DESC
);

ALTER TABLE public.reward_transactions
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own reward transactions"
ON public.reward_transactions
FOR SELECT
TO authenticated
USING (user_id = auth.uid());


-- =========================================================
-- 5. ÖĞRENCİ KARAKTER ENVANTERİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.student_characters (
  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  character_id uuid NOT NULL
    REFERENCES public.characters(id)
    ON DELETE CASCADE,

  unlocked_at timestamptz NOT NULL DEFAULT now(),

  unlock_source text,

  is_selected boolean NOT NULL DEFAULT false,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  PRIMARY KEY (user_id, character_id)
);

ALTER TABLE public.student_characters
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own characters"
ON public.student_characters
FOR SELECT
TO authenticated
USING (user_id = auth.uid());


-- =========================================================
-- 6. ÖĞRENCİ KOZMETİK ENVANTERİ
-- =========================================================

CREATE TABLE IF NOT EXISTS public.student_cosmetics (
  user_id uuid NOT NULL
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  cosmetic_item_id uuid NOT NULL
    REFERENCES public.cosmetic_items(id)
    ON DELETE CASCADE,

  unlocked_at timestamptz NOT NULL DEFAULT now(),

  unlock_source text,

  is_equipped boolean NOT NULL DEFAULT false,

  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  PRIMARY KEY (user_id, cosmetic_item_id)
);

CREATE INDEX IF NOT EXISTS idx_student_cosmetics_user
ON public.student_cosmetics(user_id);

ALTER TABLE public.student_cosmetics
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own cosmetics"
ON public.student_cosmetics
FOR SELECT
TO authenticated
USING (user_id = auth.uid());


-- =========================================================
-- 7. AKTİF KARAKTER / KOZMETİK LOADOUT
-- =========================================================

CREATE TABLE IF NOT EXISTS public.student_loadouts (
  user_id uuid PRIMARY KEY
    REFERENCES auth.users(id)
    ON DELETE CASCADE,

  character_id uuid
    REFERENCES public.characters(id)
    ON DELETE SET NULL,

  equipped_items jsonb NOT NULL DEFAULT '{}'::jsonb,

  appearance_settings jsonb NOT NULL DEFAULT '{}'::jsonb,

  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.student_loadouts
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student reads own loadout"
ON public.student_loadouts
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "student updates own loadout"
ON public.student_loadouts
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY "student inserts own loadout"
ON public.student_loadouts
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

DROP TRIGGER IF EXISTS trigger_student_loadouts_set_updated_at
ON public.student_loadouts;

CREATE TRIGGER trigger_student_loadouts_set_updated_at
BEFORE UPDATE ON public.student_loadouts
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 8. ÖDÜL TANIMLARI
-- İleride admin panelinden yeni ödül kuralları eklenebilir.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.reward_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  reward_code text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,

  trigger_type text NOT NULL
    CHECK (
      trigger_type IN (
        'practice_complete',
        'correct_answer',
        'competition_win',
        'competition_participation',
        'streak',
        'training_level_complete',
        'training_stars',
        'league_promotion',
        'season_finish',
        'achievement',
        'custom'
      )
    ),

  reward_type text NOT NULL
    CHECK (
      reward_type IN (
        'points',
        'stars',
        'badge',
        'cosmetic',
        'character',
        'title',
        'custom'
      )
    ),

  reward_value integer
    CHECK (
      reward_value IS NULL
      OR reward_value >= 0
    ),

  reward_data jsonb NOT NULL DEFAULT '{}'::jsonb,

  conditions jsonb NOT NULL DEFAULT '{}'::jsonb,

  is_repeatable boolean NOT NULL DEFAULT true,

  cooldown_seconds integer
    CHECK (
      cooldown_seconds IS NULL
      OR cooldown_seconds >= 0
    ),

  is_active boolean NOT NULL DEFAULT true,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.reward_definitions
ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated read active reward definitions"
ON public.reward_definitions
FOR SELECT
TO authenticated
USING (is_active = true);

DROP TRIGGER IF EXISTS trigger_reward_definitions_set_updated_at
ON public.reward_definitions;

CREATE TRIGGER trigger_reward_definitions_set_updated_at
BEFORE UPDATE ON public.reward_definitions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


-- =========================================================
-- 9. BAŞLANGIÇ 3 KARAKTER
-- İsim ve görseller daha sonra değiştirilebilir.
-- =========================================================

INSERT INTO public.characters (
  character_code,
  name,
  description,
  sort_order,
  rarity,
  unlock_type,
  unlock_value
)
VALUES
(
  'character_1',
  'Karakter 1',
  'Başlangıç karakteri.',
  10,
  'common',
  'default',
  0
),
(
  'character_2',
  'Karakter 2',
  'İlerleme ile açılabilen karakter.',
  20,
  'rare',
  'stars',
  500
),
(
  'character_3',
  'Karakter 3',
  'İleri seviye ödül karakteri.',
  30,
  'epic',
  'stars',
  1500
)
ON CONFLICT (character_code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  sort_order = EXCLUDED.sort_order,
  rarity = EXCLUDED.rarity,
  unlock_type = EXCLUDED.unlock_type,
  unlock_value = EXCLUDED.unlock_value,
  is_active = true;