import Link from "next/link"
import { redirect } from "next/navigation"

import { createClient } from "@/lib/supabase/server"
import { getOwnResult } from "@/lib/competition/service"
import type {
  OwnCompetitionOutcome,
  OwnCompetitionResult,
} from "@/lib/competition/types"

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
 *  - Rakip ismi/skoru/ID'si/cevabi gosterilmez.
 *  - winnerUserId, players dizisi veya full scoreboard client'a gecmez.
 *  - Puan ve sonuc yalnizca sunucu sonucundan (V1) gelir; sabit
 *    "100 puan" veya "+20 XP" gibi istemci tarafı değerler YOKTUR.
 *  - Hata inceleme yalnizca KENDI answer_result/submitted_answer
 *    alanlarini gosterir; dogru cevap ASLA gosterilmez.
 *  - Tamamlanmamis yarismalarda oturum sayfasina redirect.
 */

const OUTCOME_LABELS: Record<OwnCompetitionOutcome, string> = {
  win: "Kazandın!",
  loss: "Kaybettin",
  draw: "Berabere",
  forfeit_win: "Rakibin çekildi; kazandın",
  forfeit_loss: "Yarışmadan çekildin",
  no_contest: "Sonuçlandırılamadı",
}

const ANSWER_RESULT_LABELS: Record<string, string> = {
  correct: "Doğru",
  wrong: "Yanlış",
  pass: "Pas",
  timeout: "Süre doldu",
}

function answerResultLabel(answerResult: string): string {
  return ANSWER_RESULT_LABELS[answerResult] ?? "Cevaplanmadı"
}

function answerResultTone(answerResult: string): string {
  switch (answerResult) {
    case "correct":
      return "bg-green-50 text-green-700 border-green-200"
    case "wrong":
      return "bg-red-50 text-red-700 border-red-200"
    case "pass":
      return "bg-gray-50 text-gray-600 border-gray-200"
    case "timeout":
      return "bg-orange-50 text-orange-700 border-orange-200"
    default:
      return "bg-gray-50 text-gray-600 border-gray-200"
  }
}

function formatSeconds(timeMs: number): string {
  if (timeMs <= 0) return "—"
  return `${Math.round(timeMs / 1000)} sn`
}

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
  let ownResult: OwnCompetitionResult
  try {
    ownResult = await getOwnResult(supabase, competitionId)
  } catch {
    redirect(`/competition/${competitionId}`)
  }

  // Tamamlanmamis yarismalarda oturum sayfasina redirect
  if (!ownResult.completedAt) {
    redirect(`/competition/${competitionId}`)
  }

  const outcomeLabel = OUTCOME_LABELS[ownResult.myResult] ?? "Sonuçlandırılamadı"

  return (
    <main className="mx-auto w-full max-w-2xl flex-1 p-4 sm:p-6">
      <section className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
        <h1 className="text-2xl font-bold text-gray-900">Yarışma sonucu</h1>

        <div className="mt-4 rounded-xl border border-gray-200 px-4 py-4 text-center">
          <p
            className="text-xl font-bold text-gray-900"
            aria-live="polite"
          >
            {outcomeLabel}
          </p>
          <p className="mt-1 text-sm text-gray-500">
            Yarışma kodu: {ownResult.competitionCode}
          </p>
        </div>

        <h2 className="mt-6 text-lg font-semibold text-gray-900">
          Performansın
        </h2>
        <ul className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-5">
          <li className="rounded-xl border border-gray-200 px-3 py-2 text-center">
            <p className="text-xs text-gray-500">Toplam puan</p>
            <p className="text-lg font-bold text-gray-900">
              {ownResult.myTotalPoints}
            </p>
          </li>
          <li className="rounded-xl border border-gray-200 px-3 py-2 text-center">
            <p className="text-xs text-gray-500">Doğru</p>
            <p className="text-lg font-bold text-green-700">
              {ownResult.myCorrectCount}
            </p>
          </li>
          <li className="rounded-xl border border-gray-200 px-3 py-2 text-center">
            <p className="text-xs text-gray-500">Yanlış</p>
            <p className="text-lg font-bold text-red-600">
              {ownResult.myWrongCount}
            </p>
          </li>
          <li className="rounded-xl border border-gray-200 px-3 py-2 text-center">
            <p className="text-xs text-gray-500">Pas</p>
            <p className="text-lg font-bold text-gray-700">
              {ownResult.myPassCount}
            </p>
          </li>
          <li className="rounded-xl border border-gray-200 px-3 py-2 text-center">
            <p className="text-xs text-gray-500">Süresi dolan</p>
            <p className="text-lg font-bold text-orange-600">
              {ownResult.myTimeoutCount}
            </p>
          </li>
        </ul>

        {ownResult.questionResults.length > 0 && (
          <>
            <h2 className="mt-6 text-lg font-semibold text-gray-900">
              Hata inceleme
            </h2>
            <p className="mt-1 text-sm text-gray-500">
              Kendi cevaplarını soru soru görebilirsin. Doğru seçenek
              güvenlik nedeniyle gösterilmez; yanlış yaptığın konuları
              tekrar bölümünde çalışabilirsin.
            </p>
            <ul className="mt-3 grid gap-2">
              {ownResult.questionResults.map((qr) => (
                <li
                  key={qr.questionOrder}
                  className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-gray-200 px-4 py-3"
                >
                  <div className="flex items-center gap-3">
                    <span className="text-sm font-semibold text-gray-900">
                      Soru {qr.questionOrder}
                    </span>
                    <span
                      className={`rounded-lg border px-2 py-0.5 text-xs font-medium ${answerResultTone(
                        qr.answerResult
                      )}`}
                    >
                      {answerResultLabel(qr.answerResult)}
                    </span>
                  </div>
                  <div className="flex items-center gap-4 text-xs text-gray-600">
                    <span>
                      {qr.submittedAnswer
                        ? `Seçtiğin: ${qr.submittedAnswer}`
                        : "Seçim yapılmadı"}
                    </span>
                    <span>{formatSeconds(qr.timeMs)}</span>
                    <span className="font-semibold text-gray-900">
                      {qr.pointsAwarded} puan
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          </>
        )}

        <div className="mt-6 flex flex-wrap gap-2">
          <Link
            href="/competition"
            className="inline-flex min-h-11 items-center rounded-xl bg-gray-900 px-6 py-3 font-semibold text-white transition hover:bg-gray-800"
          >
            Tekrar yarış
          </Link>
          <Link
            href="/dashboard"
            className="inline-flex min-h-11 items-center rounded-xl border border-gray-300 bg-white px-6 py-3 font-semibold text-gray-700 transition hover:bg-gray-50"
          >
            Panele dön
          </Link>
        </div>
      </section>
    </main>
  )
}
