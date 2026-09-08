"use server"

/**
 * Profil sunucu aksiyonları (Faz 10).
 *
 * - Kullanıcı kimliği ASLA istemciden alınmaz; oturumdan okunur.
 * - İstemci yalnız niyet gönderir: yeni takma ad / seçilen avatar kodu.
 * - Grade, XP, lig rating, yıldız veya kota aksiyona giremez.
 * - Hatalar ham DB metni olarak döndürülmez; Türkçe güvenli mesaj.
 */

import { revalidatePath } from "next/cache"

import {
  NicknameValidationError,
  ProfileServiceError,
  updateOwnNickname,
  selectOwnAvatar,
} from "@/lib/profile/service"
import type {
  AvatarSelectionResult,
  OwnProfileSummary,
} from "@/lib/profile/types"
import { createClient } from "@/lib/supabase/server"

export type ProfileActionResponse<T> =
  | { ok: true; data: T }
  | { ok: false; message: string }

const SESSION_EXPIRED_MESSAGE =
  "Oturumunuz doğrulanamadı. Lütfen giriş yapıp tekrar deneyin."

/** Takma ad güncelleme: kimlik sunucudan; yalnız nickname yazılır. */
export async function updateNicknameAction(
  rawNickname: unknown
): Promise<ProfileActionResponse<OwnProfileSummary>> {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) return { ok: false, message: SESSION_EXPIRED_MESSAGE }

  try {
    const data = await updateOwnNickname(supabase, user.id, rawNickname)
    revalidatePath("/profile")
    revalidatePath("/dashboard")
    return { ok: true, data }
  } catch (error) {
    if (error instanceof NicknameValidationError) {
      return { ok: false, message: error.message }
    }
    if (error instanceof ProfileServiceError) {
      return { ok: false, message: error.message }
    }
    return { ok: false, message: "Takma ad güncellenemedi. Lütfen tekrar dene." }
  }
}

/** Avatar seçimi: katalog doğrulaması sunucu RPC'sindedir. */
export async function selectAvatarAction(
  rawCode: unknown
): Promise<ProfileActionResponse<AvatarSelectionResult>> {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) return { ok: false, message: SESSION_EXPIRED_MESSAGE }

  try {
    const data = await selectOwnAvatar(supabase, rawCode)
    revalidatePath("/profile")
    revalidatePath("/dashboard")
    return { ok: true, data }
  } catch (error) {
    if (error instanceof ProfileServiceError) {
      return { ok: false, message: error.message }
    }
    return { ok: false, message: "Avatar seçilemedi. Lütfen tekrar dene." }
  }
}
