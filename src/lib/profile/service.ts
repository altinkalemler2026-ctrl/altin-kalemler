/**
 * Faz 10 profil servis katmanı — YALNIZ server tarafı.
 *
 * Güvenlik kuralları:
 *  - Kullanıcı kimliği ASLA istemciden alınmaz; sunucu tarafında
 *    auth oturumundan (auth.getUser) okunup yalnız sunucuya verilir.
 *  - Nickname güncellemesi 093 kolon-ayricalığından geçer: öğrenci
 *    YALNIZ kendi satırının nickname kolonunu güncelleyebilir;
 *    grade_level/id/zaman damgaları veritabanında fail-closed'dur.
 *  - Avatar seçimi yalnız sunucu RPC'si (select_own_avatar) ile;
 *    katalog doğrulaması veritabanındadır. İstemci yalnız niyet
 *    (karakter kodu) gönderir.
 *  - Her okuma sıkı allowlist mapper'dan geçer; ham DB satırı ve
 *    ham hata dışarı sızmaz.
 *
 * Test edilebilirlik: fonksiyonlar istemciyi bağımlılık olarak alır.
 */

import type { SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "@/lib/supabase/types"

import type {
  AvatarCatalog,
  AvatarOption,
  AvatarSelectionResult,
  OwnAvatarInfo,
  OwnProfileSummary,
} from "./types"

export type ProfileClient = SupabaseClient<Database>

/** Kullanıcıya güvenle gösterilebilen hata. Ham DB mesajı taşımaz. */
export class ProfileServiceError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "ProfileServiceError"
  }
}

/** Nickname doğrulama hatası (kural: mevcut DB sözleşmesi). */
export class NicknameValidationError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "NicknameValidationError"
  }
}

/** Mevcut DB kuralı: nickname UNIQUE. 23505 → güvenli Türkçe mesaj. */
export const NICKNAME_DUPLICATE_MESSAGE =
  "Bu takma ad başka bir öğrenci tarafından kullanılıyor. Lütfen farklı bir takma ad dene."
export const NICKNAME_GENERIC_ERROR_MESSAGE =
  "Takma ad güncellenemedi. Lütfen tekrar dene."
export const AVATAR_GENERIC_ERROR_MESSAGE =
  "Avatar seçilemedi. Lütfen tekrar dene."
export const AVATAR_UNAVAILABLE_MESSAGE =
  "Bu avatar şu anda seçilemiyor. Lütfen listeden bir avatar seç."

// ------------------------------------------------------------
// Allowlist eşleyiciler
// ------------------------------------------------------------

function asRecord(raw: unknown): Record<string, unknown> {
  return typeof raw === "object" && raw !== null
    ? (raw as Record<string, unknown>)
    : {}
}

/**
 * student_profiles satırı → yalnız nickname + grade_level.
 * (Görsel allowlist: diğer herhangi bir sütun burada düşürülür.)
 */
export function mapOwnProfileSummary(
  profileRow: unknown,
  avatarRow: unknown
): OwnProfileSummary {
  const profile = asRecord(profileRow)
  const loadout = asRecord(avatarRow)
  const character = asRecord(loadout.character)

  const nickname = profile.nickname
  const gradeLevel = profile.grade_level

  let avatar: OwnAvatarInfo | null = null
  if (typeof character.character_code === "string") {
    const name =
      typeof character.name === "string" ? character.name : character.character_code
    avatar = { code: character.character_code, name }
  }

  return {
    nickname: typeof nickname === "string" ? nickname : "",
    gradeLevel:
      typeof gradeLevel === "number" && Number.isFinite(gradeLevel)
        ? gradeLevel
        : 0,
    avatar,
  }
}

/** characters satırı → katalog seçeneği allowlist. */
export function mapAvatarOption(row: unknown): AvatarOption | null {
  const record = asRecord(row)
  if (typeof record.character_code !== "string") return null

  return {
    code: record.character_code,
    name: typeof record.name === "string" ? record.name : record.character_code,
    description:
      typeof record.description === "string" ? record.description : null,
  }
}

/** select_own_avatar RPC jsonb → güvenli sonuç. */
export function mapAvatarSelection(raw: unknown): AvatarSelectionResult {
  const record = asRecord(raw)
  const code = record.character_code

  return {
    code: typeof code === "string" ? code : "",
    name:
      typeof record.character_name === "string"
        ? record.character_name
        : typeof code === "string"
          ? code
          : "",
  }
}

// ------------------------------------------------------------
// Okuma yolları
// ------------------------------------------------------------

/** Öğrencinin kendi profil özeti (nickname, sınıf, seçili avatar). */
export async function fetchOwnProfileSummary(
  client: ProfileClient,
  userId: string
): Promise<OwnProfileSummary> {
  const { data: profile, error } = await client
    .from("student_profiles")
    .select("nickname, grade_level")
    .eq("id", userId)
    .single()

  if (error) {
    throw new ProfileServiceError("Profil bilgileri alınamadı.")
  }

  const { data: loadout } = await client
    .from("student_loadouts")
    .select("character:characters(character_code, name)")
    .eq("user_id", userId)
    .maybeSingle()

  return mapOwnProfileSummary(profile, loadout)
}

/**
 * Onaylı avatar kataloğu: yalnız aktif + default-unlock karakterler.
 * (RLS zaten yalnız aktifleri döndürür; default filtresi yazma
 * RPC'sindeki sunucu kuralıyla aynıdır.)
 */
export async function fetchAvatarCatalog(
  client: ProfileClient
): Promise<AvatarCatalog> {
  const { data, error } = await client
    .from("characters")
    .select("character_code, name, description")
    .eq("unlock_type", "default")
    .order("character_code", { ascending: true })

  if (error) {
    throw new ProfileServiceError("Avatar listesi alınamadı.")
  }

  const options: AvatarOption[] = []
  for (const row of data ?? []) {
    const option = mapAvatarOption(row)
    if (option) options.push(option)
  }

  return {
    status: options.length > 0 ? "available" : "empty",
    options,
  }
}

// ------------------------------------------------------------
// Yazma yolları (sunucu-otoriter)
// ------------------------------------------------------------

/**
 * Kendi nickname'ini günceller.
 *
 * - Mevcut güvenli yol: 093 kolon-ayricalığı (nickname UPDATE)
 *   + 001 RLS satır kapsamı (yalnız kendi satırı).
 * - grade_level/id hiçbir koşulda gönderilmez; nickname + grade
 *   birlikte gönderilseydi veritabanı isteği BÜTÜNÜYLE reddederdi.
 * - Doğrulama: mevcut DB kuralı (boş olamaz + UNIQUE). Yeni
 *   uzunluk/karakter politikası uydurulmaz.
 */
export async function updateOwnNickname(
  client: ProfileClient,
  userId: string,
  rawNickname: unknown
): Promise<OwnProfileSummary> {
  if (typeof rawNickname !== "string") {
    throw new NicknameValidationError(
      "Takma ad boş olamaz. Lütfen bir takma ad yaz."
    )
  }

  const nickname = rawNickname.trim()
  if (nickname.length === 0) {
    throw new NicknameValidationError(
      "Takma ad boş olamaz. Lütfen bir takma ad yaz."
    )
  }

  const { data, error } = await client
    .from("student_profiles")
    .update({ nickname })
    .eq("id", userId)
    .select("nickname, grade_level")
    .single()

  if (error) {
    if (error.code === "23505") {
      throw new NicknameValidationError(NICKNAME_DUPLICATE_MESSAGE)
    }
    throw new ProfileServiceError(NICKNAME_GENERIC_ERROR_MESSAGE)
  }

  // Loadout okumasını tekrar kullanarak aynı DTO ile dön.
  const { data: loadout } = await client
    .from("student_loadouts")
    .select("character:characters(character_code, name)")
    .eq("user_id", userId)
    .maybeSingle()

  return mapOwnProfileSummary(data, loadout)
}

/**
 * Onaylı katalogdan avatar seçer. Kural doğrulaması sunucu RPC'sinde
 * (select_own_avatar): aktif + default-unlock zorunludur; pasif,
 * silinmiş veya kilitli karakter fail-closed reddedilir.
 */
export async function selectOwnAvatar(
  client: ProfileClient,
  rawCode: unknown
): Promise<AvatarSelectionResult> {
  if (typeof rawCode !== "string" || rawCode.trim().length === 0) {
    throw new ProfileServiceError(AVATAR_UNAVAILABLE_MESSAGE)
  }

  const { data, error } = await client.rpc("select_own_avatar", {
    p_character_code: rawCode.trim(),
  })

  if (error) {
    throw new ProfileServiceError(
      error.code === "P0001"
        ? AVATAR_UNAVAILABLE_MESSAGE
        : AVATAR_GENERIC_ERROR_MESSAGE
    )
  }

  return mapAvatarSelection(data)
}
