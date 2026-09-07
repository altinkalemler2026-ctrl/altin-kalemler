/**
 * Faz 8 Lig servisi — YALNIZ server tarafi.
 *
 * Guvenlik kurallari:
 *  - Kullanici kimligi/grade/season ASLA parametre olarak gonderilmez;
 *    RPC auth.uid() + student_profiles uzerinden kendisi turetir.
 *  - Ham Postgres/Supabase hata ayrintilari istemciye gonderilmez.
 *  - DTO allowlist mapper (mapLeagueRanking) olmadan veri UI'a gecmez.
 */

import type { SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "@/lib/supabase/types"

import { mapLeagueRanking } from "./mappers"
import type { LeagueRankingDto } from "./types"

export type LeagueClient = SupabaseClient<Database>

export class LeagueServiceError extends Error {}

/**
 * Ogrencinin kendi sinif + lig kapsamindaki guvenli siralamasini getirir.
 *
 * - p_user_id / p_grade_level / p_season ALMAZ (RPC imzasi yalniz
 *   p_limit/p_offset; varsayilanlar yeterlidir).
 * - Ham hata LeagueServiceError ile gizlenir.
 */
export async function getMyLeagueRanking(
  client: LeagueClient
): Promise<LeagueRankingDto> {
  const { data, error } = await client.rpc("get_my_league_ranking")

  if (error) {
    throw new LeagueServiceError("Lig verisi alinamadi.")
  }

  return mapLeagueRanking(data)
}
