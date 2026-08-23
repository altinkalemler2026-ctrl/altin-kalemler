import Link from "next/link"

import { submitTrainingAttemptAction } from "@/app/(student)/training/actions"
import TrainingSession from "@/components/student/TrainingSession"
import { createClient } from "@/lib/supabase/server"
import { mapTrainingError } from "@/lib/training/errors"
import { selectTrainingQuestions } from "@/lib/training/service"

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
        className="rounded-2xl border border-red-200 bg-red-50 p-5 text-red-700"
      >
        <p className="font-semibold">Antrenman başlatılamadı</p>
        <p className="mt-1 text-sm">{message}</p>
        <Link
          href="/training"
          className="mt-3 inline-flex min-h-11 items-center font-semibold text-red-900 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-900"
        >
          Ders seçimine dön
        </Link>
      </div>
    </main>
  )
}

export default async function TrainingSubjectPage({
  params,
}: {
  params: Promise<{ subjectId: string }>
}) {
  const { subjectId } = await params

  if (!UUID_PATTERN.test(subjectId)) {
    return <ErrorCard message="Geçersiz ders adresi." />
  }

  const supabase = await createClient()

  // Ders adı (yalnız okuma; RLS subjects_read_active).
  const { data: subject } = await supabase
    .from("subjects")
    .select("name")
    .eq("id", subjectId)
    .maybeSingle()

  let questions
  try {
    ({ questions } = await selectTrainingQuestions(supabase, subjectId, 10))
  } catch (error) {
    return <ErrorCard message={mapTrainingError(error)} />
  }

  return (
    <TrainingSession
      subjectName={subject?.name ?? "Seçili ders"}
      questions={questions}
      submitAction={submitTrainingAttemptAction}
    />
  )
}
