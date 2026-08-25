import { redirect } from "next/navigation"

import { createClient } from "@/lib/supabase/server"
import CompetitionSession from "@/components/student/CompetitionSession"

interface PageProps {
  params: Promise<{ competitionId: string }>
}

/**
 * Yarisma oturum sayfasi — Server Component.
 *
 * GUVENLIK:
 *  - Auth gate: auth.getUser() ile kullanici dogrulamasi.
 *  - Participant gate: is_competition_participant RPC ile katilim kontrolu.
 *  - Hatali/girissiz kullanicilara redirect.
 *  - Client'a yalnizca competitionId gecer; rakip verisi gecmez.
 */
export default async function CompetitionSessionPage({ params }: PageProps) {
  const { competitionId } = await params

  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) {
    redirect("/login")
  }

  // Participant gate: kullanici bu yarismaya katilimci mi?
  const { data: isParticipant } = await supabase.rpc(
    "is_competition_participant",
    { p_competition_id: competitionId }
  )

  if (!isParticipant) {
    redirect("/competition")
  }

  return <CompetitionSession competitionId={competitionId} />
}
