import Link from "next/link"
import { redirect } from "next/navigation"

import { createClient } from "@/lib/supabase/server"
import { getOwnResult } from "@/lib/competition/service"

interface PageProps {
  params: Promise<{ competitionId: string }>
}

/**
 * Yarisma sonuc sayfasi — Server Component.
 *
 * GUVENLIK:
 *  - Auth gate: auth.getUser() ile kullanici dogrulamasi.
 *  - Participant gate: is_competition_participant RPC ile katilim kontrolu.
 *  - Yalnizca OwnCompetitionResult render edilir.
 *  - Rakip ismi/skoru/ID'si gosterilmez.
 *  - winnerUserId, players dizisi veya full scoreboard client'a gecmez.
 *  - Tamamlanmamis yarismalarda redirect.
 */
export default async function CompetitionResultPage({ params }: PageProps) {
  const { competitionId } = await params

  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) {
    redirect("/login")
  }

  // Participant gate
  const { data: isParticipant } = await supabase.rpc(
    "is_competition_participant",
    { p_competition_id: competitionId }
  )

  if (!isParticipant) {
    redirect("/competition")
  }

  // Own result — rakip satirlari service tarafinda atilir
  let ownResult
  try {
    ownResult = await getOwnResult(supabase, competitionId)
  } catch {
    redirect(`/competition/${competitionId}`)
  }

  // Tamamlanmamis yarismalarda oturum sayfasina redirect
  if (!ownResult.completedAt) {
    redirect(`/competition/${competitionId}`)
  }

  return (
    <main className="mx-auto w-full max-w-2xl flex-1 p-4 sm:p-6">
      <section className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
        <h1 className="text-2xl font-bold text-gray-900">Yarisma Sonucu</h1>

        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <div className="rounded-xl border border-gray-200 px-4 py-3">
            <p className="text-sm text-gray-500">Yarisma Kodu</p>
            <p className="font-semibold text-gray-900">
              {ownResult.competitionCode}
            </p>
          </div>
          <div className="rounded-xl border border-gray-200 px-4 py-3">
            <p className="text-sm text-gray-500">Sonuc</p>
            <p className="font-semibold text-gray-900">
              {ownResult.resultType === "win_loss"
                ? "Galibiyet / Maglubiyet"
                : ownResult.resultType === "draw"
                  ? "Berabere"
                  : ownResult.resultType}
            </p>
          </div>
        </div>

        <h2 className="mt-6 text-lg font-semibold text-gray-900">
          Performansiniz
        </h2>
        <ul className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
          <li className="rounded-xl border border-gray-200 px-4 py-2 text-center">
            <p className="text-xs text-gray-500">Toplam Puan</p>
            <p className="text-lg font-bold text-gray-900">
              {ownResult.myTotalPoints}
            </p>
          </li>
          <li className="rounded-xl border border-gray-200 px-4 py-2 text-center">
            <p className="text-xs text-gray-500">Dogru</p>
            <p className="text-lg font-bold text-green-700">
              {ownResult.myCorrectCount}
            </p>
          </li>
          <li className="rounded-xl border border-gray-200 px-4 py-2 text-center">
            <p className="text-xs text-gray-500">Yanlis</p>
            <p className="text-lg font-bold text-red-600">
              {ownResult.myWrongCount}
            </p>
          </li>
          <li className="rounded-xl border border-gray-200 px-4 py-2 text-center">
            <p className="text-xs text-gray-500">Suresi Dolan</p>
            <p className="text-lg font-bold text-orange-600">
              {ownResult.myTimeoutCount}
            </p>
          </li>
        </ul>

        {ownResult.questionResults.length > 0 && (
          <>
            <h2 className="mt-6 text-lg font-semibold text-gray-900">
              Soru Detaylari
            </h2>
            <div className="mt-3 overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-gray-200 text-left text-gray-500">
                    <th className="px-3 py-2">Soru</th>
                    <th className="px-3 py-2">Zorluk</th>
                    <th className="px-3 py-2">Puan</th>
                    <th className="px-3 py-2">Sure (ms)</th>
                  </tr>
                </thead>
                <tbody>
                  {ownResult.questionResults.map((qr) => (
                    <tr
                      key={qr.questionOrder}
                      className="border-b border-gray-100"
                    >
                      <td className="px-3 py-2 font-medium text-gray-900">
                        {qr.questionOrder}
                      </td>
                      <td className="px-3 py-2 text-gray-700">
                        {qr.difficulty}
                      </td>
                      <td className="px-3 py-2 font-semibold text-gray-900">
                        {qr.pointsAwarded}
                      </td>
                      <td className="px-3 py-2 text-gray-700">{qr.timeMs}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}

        <div className="mt-6">
          <Link
            href="/competition"
            className="inline-flex min-h-11 items-center rounded-xl bg-gray-900 px-6 py-3 font-semibold text-white transition hover:bg-gray-800"
          >
            Yarismalara Don
          </Link>
        </div>
      </section>
    </main>
  )
}
