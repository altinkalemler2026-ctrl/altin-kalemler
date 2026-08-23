"use server"

/**
 * Faz 3.5 akademik takvim sunucu aksiyonları.
 *
 * - Yetki RPC içinde (calendar.manage) tekrar doğrulanır; buradaki
 *   kontroller yalnız kullanıcı deneyimi içindir.
 * - Hatalar ham DB mesajı olarak döndürülmez; Türkçe flash mesajıyla
 *   sayfaya yönlendirilir.
 */

import { revalidatePath } from "next/cache"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  CALENDAR_INPUT_MESSAGES,
  CALENDAR_SUCCESS_MESSAGES,
  mapCalendarError,
} from "@/lib/admin/academic-calendar-errors"

type UpsertRpc = (
  functionName: "academic_calendar_upsert_week",
  args: {
    p_year: string
    p_week: number
    p_starts_at: string
    p_ends_at: string
  },
) => Promise<{ error: { message: string } | null }>

type DeleteRpc = (
  functionName: "academic_calendar_delete_week",
  args: {
    p_year: string
    p_week: number
  },
) => Promise<{ error: { message: string } | null }>

function flash(
  year: string,
  kind: "ok" | "error",
  message: string
): never {
  const params = new URLSearchParams()
  if (year) params.set("year", year)
  params.set(kind, message)
  redirect(`/admin/academic-calendar?${params.toString()}`)
}

function parseWeek(value: FormDataEntryValue | null): number | null {
  const text = String(value ?? "").trim()
  if (!/^\d+$/.test(text)) return null
  return Number(text)
}

function parseDate(value: FormDataEntryValue | null): string | null {
  const text = String(value ?? "").trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null
  if (Number.isNaN(new Date(`${text}T00:00:00Z`).getTime())) return null
  return text
}

/** Hafta ekleme/güncelleme (upsert). */
export async function upsertWeekAction(
  formData: FormData
): Promise<void> {
  const year = String(formData.get("year") ?? "").trim()
  const week = parseWeek(formData.get("week"))
  const startsAt = parseDate(formData.get("startsAt"))
  const endsAt = parseDate(formData.get("endsAt"))

  if (!year || year.length > 100) {
    flash(year, "error", CALENDAR_INPUT_MESSAGES.yearRequired)
  }
  if (week === null || week < 0 || week > 52) {
    flash(year, "error", CALENDAR_INPUT_MESSAGES.weekRange)
  }
  if (!startsAt || !endsAt) {
    flash(year, "error", CALENDAR_INPUT_MESSAGES.dateRequired)
  }
  if (endsAt <= startsAt!) {
    flash(year, "error", CALENDAR_INPUT_MESSAGES.dateOrder)
  }

  const supabase = await createClient()

  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    flash(year, "error", "Bu işlem için giriş yapmalısınız.")
  }

  const rpc = supabase.rpc.bind(supabase) as unknown as UpsertRpc
  const { error } = await rpc("academic_calendar_upsert_week", {
    p_year: year,
    p_week: week!,
    p_starts_at: startsAt!,
    p_ends_at: endsAt!,
  })

  if (error) {
    flash(year, "error", mapCalendarError(error))
  }

  revalidatePath("/admin/academic-calendar")
  flash(year, "ok", CALENDAR_SUCCESS_MESSAGES.upsert)
}

/** Hafta silme (yalnız gelecek + referanssız haftalar). */
export async function deleteWeekAction(
  formData: FormData
): Promise<void> {
  const year = String(formData.get("year") ?? "").trim()
  const week = parseWeek(formData.get("week"))

  if (!year || year.length > 100) {
    flash(year, "error", CALENDAR_INPUT_MESSAGES.yearRequired)
  }
  if (week === null || week < 0 || week > 52) {
    flash(year, "error", CALENDAR_INPUT_MESSAGES.weekRange)
  }

  const supabase = await createClient()

  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    flash(year, "error", "Bu işlem için giriş yapmalısınız.")
  }

  const rpc = supabase.rpc.bind(supabase) as unknown as DeleteRpc
  const { error } = await rpc("academic_calendar_delete_week", {
    p_year: year,
    p_week: week!,
  })

  if (error) {
    flash(year, "error", mapCalendarError(error))
  }

  revalidatePath("/admin/academic-calendar")
  flash(year, "ok", CALENDAR_SUCCESS_MESSAGES.delete)
}
