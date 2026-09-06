import Link from "next/link"

import OutcomeReviewPlan from "@/components/student/OutcomeReviewPlan"
import TrainingSession from "@/components/student/TrainingSession"
import { submitTrainingAttemptAction } from "@/app/(student)/training/actions"
import { createClient } from "@/lib/supabase/server"
import { mapTrainingError } from "@/lib/training/errors"
import {
  fetchOutcomeReviewPlan,
  startTargetedReview,
} from "@/lib/review/service"

export const metadata = {
  title: "Kazanım Tekrarı | Altın Kalemler",
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function ErrorCard({
  title,
  message,
}: {
  title: string
  message: string
}) {
  return (
    <main className="mx-auto w-full max-w-2xl flex-1 p-6">
      <div
        role="alert"
        aria-live="assertive"
        className="rounded-2xl border border-danger-700 bg-danger-100 p-5 text-danger-700"
      >
        <p className="font-semibold">{title}</p>
        <p className="mt-1 text-sm">{message}</p>
        <Link
          href="/tekrar"
          className="mt-3 inline-flex min-h-11 items-center font-semibold text-danger-700 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
        >
          Ders seçimine dön
        </Link>
      </div>
    </main>
  )
}

function StatusCard({
  title,
  message,
}: {
  title: string
  message: string
}) {
  return (
    <main className="mx-auto w-full max-w-2xl flex-1 p-6">
      <div className="rounded-2xl border border-gray-200 bg-white p-6">
        <h1 className="text-xl font-semibold text-gray-900">{title}</h1>
        <p className="mt-2 text-gray-600">{message}</p>
        <Link
          href={`/tekrar`}
          className="mt-4 inline-flex min-h-11 items-center font-medium text-gray-900 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
        >
          Ders seçimine dön
        </Link>
      </div>
    </main>
  )
}

export default async function ReviewSubjectPage({
  params,
  searchParams,
}: {
  params: Promise<{ subjectId: string }>
  searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
  const { subjectId } = await params
  const query = await searchParams

  if (!UUID_PATTERN.test(subjectId)) {
    return <ErrorCard title="Geçersiz ders adresi" message="Bu ders adresi geçersiz." />
  }

  const outcomeParam =
    typeof query.outcome === "string" && UUID_PATTERN.test(query.outcome)
      ? query.outcome
      : null

  const supabase = await createClient()

  // Ders adı (yalnız okuma; RLS subjects_read_active).
  const { data: subject } = await supabase
    .from("subjects")
    .select("name")
    .eq("id", subjectId)
    .maybeSingle()

  const subjectName = subject?.name ?? "Seçili ders"

  // ------------------------------------------------------------
  // Kazanım analitiği görünümü (outcome parametresi yok).
  // ------------------------------------------------------------
  if (outcomeParam === null) {
    let plan
    try {
      plan = await fetchOutcomeReviewPlan(supabase, subjectId)
    } catch (error) {
      return <ErrorCard title="Analitik yüklenemedi" message={mapTrainingError(error)} />
    }

    return (
      <main className="mx-auto w-full max-w-3xl flex-1 p-6">
        <header>
          <p className="text-sm font-medium text-gray-500">{subjectName}</p>
          <h1 className="mt-1 text-3xl font-bold text-gray-900">
            Kazanım Analitiği
          </h1>
          <p className="mt-2 text-gray-600">
            Kazanım bazında güçlü ve geliştirilecek alanların. Bekleyen
            hatası olan kazanımlar için hedefli tekrar başlatabilirsin.
          </p>
        </header>

        <OutcomeReviewPlan
          subjectId={subjectId}
          subjectName={subjectName}
          rows={plan}
        />
      </main>
    )
  }

  // ------------------------------------------------------------
  // Hedefli tekrar oturumu (outcome parametresi var).
  // Kimlik sunucudan; seçim deterministik RPC'den.
  // ------------------------------------------------------------
  let selection
  try {
    selection = await startTargetedReview(supabase, subjectId, outcomeParam)
  } catch (error) {
    return <ErrorCard title="Tekrar oturumu başlatılamadı" message={mapTrainingError(error)} />
  }

  if (selection.reason === "gecersiz_kapsam") {
    return (
      <ErrorCard
        title="Kazanım bu dönemde çalışılamaz"
        message="Seçili kazanım bu dönemin kapsamında bulunmuyor."
      />
    )
  }

  if (selection.questions.length === 0) {
    return (
      <StatusCard
        title="Şu anda tekrarlanacak hata yok"
        message="Bu kazanımda bekleyen yanlış bulunmuyor. Bugün yaptığın denemeler yarın yeni bir tekrar oturumuna aday olur."
      />
    )
  }

  // Oturum başlangıcı ölçüm bağlamı: kazanımın güncel etkisi.
  let startPending: number | null = null
  let startRedeemRate: number | null = null
  try {
    const plan = await fetchOutcomeReviewPlan(supabase, subjectId)
    const row = plan.find((item) => item.outcomeId === outcomeParam)
    if (row) {
      startPending = row.pendingErrors
      startRedeemRate = row.redeemRate
    }
  } catch {
    startPending = null
    startRedeemRate = null
  }

  return (
    <div className="flex w-full flex-col">
      <div className="mx-auto w-full max-w-2xl px-4 pt-4 sm:px-6">
        <div className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
          <p className="text-sm font-medium text-gray-500">
            Hedefli tekrar oturumu
          </p>
          <p className="mt-1 text-sm text-gray-600">
            {startPending !== null && startPending > 0
              ? `Başlangıç durumu: ${startPending} bekleyen hata${
                  startRedeemRate !== null
                    ? `, telafi oranı %${Math.round(startRedeemRate)}`
                    : ""
                }.`
              : "Bu oturumdaki cevapların sunucu tarafında değerlendirilir; tekrar etkisi kazanım analitiğinde güncellenir."}
          </p>
          <p
            role="status"
            aria-live="polite"
            className="mt-1 text-xs text-gray-500"
          >
            Oturumda {selection.wrongReviewCount} bekleyen yanlış ve{" "}
            {selection.newCount} yeni soru var.
          </p>
        </div>
      </div>

      <TrainingSession
        subjectName={`${subjectName} • Hedefli Tekrar`}
        questions={selection.questions}
        submitAction={submitTrainingAttemptAction}
        backHref={`/tekrar/${subjectId}`}
      />
    </div>
  )
}
