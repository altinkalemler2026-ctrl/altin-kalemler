import Link from "next/link"

import TrainingFilters from "@/components/student/TrainingFilters"
import TrainingSession from "@/components/student/TrainingSession"
import { submitTrainingAttemptAction } from "@/app/(student)/training/actions"
import { createClient } from "@/lib/supabase/server"
import { mapTrainingError } from "@/lib/training/errors"
import {
  listTrainingOutcomes,
  listTrainingTopics,
  selectTrainingQuestions,
} from "@/lib/training/service"

export const metadata = {
  title: "Antrenman | Altın Kalemler",
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function ErrorCard({ message }: { message: string }) {
  return (
    <main className="mx-auto w-full max-w-2xl flex-1 p-6">
      <div
        role="alert"
        aria-live="assertive"
        className="rounded-2xl border border-danger-700 bg-danger-100 p-5 text-danger-700"
      >
        <p className="font-semibold">Antrenman başlatılamadı</p>
        <p className="mt-1 text-sm">{message}</p>
        <Link
          href="/training"
          className="mt-3 inline-flex min-h-11 items-center font-semibold text-danger-700 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
        >
          Ders seçimine dön
        </Link>
      </div>
    </main>
  )
}

function parseScopeParam(value: string | undefined): string | null {
  return value && UUID_PATTERN.test(value) ? value : null
}

export default async function TrainingSubjectPage({
  params,
  searchParams,
}: {
  params: Promise<{ subjectId: string }>
  searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
  const { subjectId } = await params
  const query = await searchParams

  if (!UUID_PATTERN.test(subjectId)) {
    return <ErrorCard message="Geçersiz ders adresi." />
  }

  const topicFilter = parseScopeParam(
    typeof query.topic === "string" ? query.topic : undefined
  )
  const outcomeFilter = parseScopeParam(
    typeof query.outcome === "string" ? query.outcome : undefined
  )

  const supabase = await createClient()

  // Ders adı (yalnız okuma; RLS subjects_read_active).
  const { data: subject } = await supabase
    .from("subjects")
    .select("name")
    .eq("id", subjectId)
    .maybeSingle()

  // Filtre seçenekleri: YALNIZ kendi sınıf/dönem kapsamı (096 RPC).
  // Liste yüklenemezse filtreler gizlenir; akış filtresiz devam eder.
  let topics: Awaited<ReturnType<typeof listTrainingTopics>> = []
  let outcomes: Awaited<ReturnType<typeof listTrainingOutcomes>> = []
  try {
    ;[topics, outcomes] = await Promise.all([
      listTrainingTopics(supabase, subjectId),
      listTrainingOutcomes(supabase, subjectId),
    ])
  } catch {
    topics = []
    outcomes = []
  }

  let questions
  let selectionReason: string | null = null
  try {
    const selection = await selectTrainingQuestions(
      supabase,
      subjectId,
      10,
      topicFilter
        ? { topicId: topicFilter }
        : outcomeFilter
          ? { outcomeId: outcomeFilter }
          : {}
    )
    questions = selection.questions
    selectionReason = selection.reason
  } catch (error) {
    return <ErrorCard message={mapTrainingError(error)} />
  }

  if (questions.length === 0 && selectionReason === "gecersiz_kapsam") {
    return <ErrorCard message="Seçili konu/kazanım bu dönemde çalışılamaz." />
  }

  return (
    <div className="flex w-full flex-col">
      {(topics.length > 0 || outcomes.length > 0) && (
        <div className="mx-auto w-full max-w-2xl px-4 pt-4 sm:px-6">
          <TrainingFilters
            subjectId={subjectId}
            topics={topics}
            outcomes={outcomes}
            activeTopicId={topicFilter}
            activeOutcomeId={outcomeFilter}
          />
        </div>
      )}

      <TrainingSession
        subjectName={subject?.name ?? "Seçili ders"}
        questions={questions}
        submitAction={submitTrainingAttemptAction}
      />
    </div>
  )
}
