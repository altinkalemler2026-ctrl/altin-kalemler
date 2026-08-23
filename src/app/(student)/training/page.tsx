import Link from "next/link"

import { createClient } from "@/lib/supabase/server"
import { mapTrainingError } from "@/lib/training/errors"
import { fetchWeeklyUsage, listTrainingSubjects } from "@/lib/training/service"
import type { WeeklyUsage } from "@/lib/training/types"

export const metadata = {
  title: "Konu Çalış | Altın Kalemler",
}

export default async function TrainingPage() {
  const supabase = await createClient()

  let subjects: Awaited<ReturnType<typeof listTrainingSubjects>> = []
  let subjectsError: string | null = null
  try {
    subjects = await listTrainingSubjects(supabase)
  } catch (error) {
    subjectsError = mapTrainingError(error)
  }

  let weeklyUsage: WeeklyUsage | null = null
  let errorMessage: string | null = null

  try {
    weeklyUsage = await fetchWeeklyUsage(supabase)
  } catch (error) {
    errorMessage = mapTrainingError(error)
  }

  const usageBySubject = new Map(
    (weeklyUsage?.subjects ?? []).map((item) => [item.subjectId, item])
  )

  return (
    <main className="mx-auto w-full max-w-3xl flex-1 p-6">
      <header>
        <p className="text-sm font-medium text-gray-500">Konu Çalış</p>
        <h1 className="mt-1 text-3xl font-bold text-gray-900">
          Ders Seç
        </h1>
        <p className="mt-2 text-gray-600">
          Çözmek istediğin dersi seç; bu haftaki soru hakkını burada
          görebilirsin.
        </p>
      </header>

      {errorMessage && (
        <div
          role="alert"
          aria-live="assertive"
          className="mt-6 rounded-2xl border border-amber-300 bg-amber-50 p-5 text-amber-900"
        >
          <p className="font-semibold">Soru akışı şu anda kapalı</p>
          <p className="mt-1 text-sm">{errorMessage}</p>
        </div>
      )}

      {!errorMessage && (
        <section aria-labelledby="weekly-usage-title" className="mt-6">
          <h2 id="weekly-usage-title" className="text-lg font-semibold text-gray-900">
            Bu haftanın kullanımı
            {weeklyUsage?.week !== null && weeklyUsage?.academicYear ? (
              <span className="ml-2 text-sm font-normal text-gray-500">
                ({weeklyUsage.academicYear}, {weeklyUsage.week}. hafta)
              </span>
            ) : null}
          </h2>

          {(weeklyUsage?.subjects.length ?? 0) === 0 ? (
            <p className="mt-2 text-sm text-gray-600">
              Bu hafta henüz yeni soru kullanmadın.
            </p>
          ) : (
            <ul className="mt-3 grid gap-2 sm:grid-cols-2">
              {weeklyUsage?.subjects.map((item) => (
                <li
                  key={item.subjectId}
                  className="rounded-xl border border-gray-200 px-4 py-2 text-sm text-gray-700"
                >
                  {item.newQuestionsUsed} / {item.limit} yeni soru kullanıldı
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      {subjectsError && (
        <div
          role="alert"
          aria-live="assertive"
          className="mt-6 rounded-2xl border border-red-200 bg-red-50 p-5 text-red-700"
        >
          <p className="font-semibold">Dersler yüklenemedi</p>
          <p className="mt-1 text-sm">{subjectsError}</p>
          <Link
            href="/dashboard"
            className="mt-3 inline-flex min-h-11 items-center font-semibold text-red-900 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-900"
          >
            Panele dön
          </Link>
        </div>
      )}

      <section aria-labelledby="subjects-title" className="mt-8">
        <h2 id="subjects-title" className="text-lg font-semibold text-gray-900">
          Dersler
        </h2>

        {subjectsError ? null : subjects.length === 0 ? (
          <p className="mt-3 rounded-2xl border border-gray-200 bg-white p-5 text-gray-600">
            Şu anda aktif ders bulunmuyor. Lütfen daha sonra tekrar deneyin.
          </p>
        ) : (
          <ul className="mt-3 grid gap-3 sm:grid-cols-2">
            {subjects.map((subject) => {
              const usage = usageBySubject.get(subject.id)
              return (
                <li key={subject.id}>
                  <Link
                    href={`/training/${subject.id}`}
                    className="flex min-h-11 flex-col justify-center rounded-2xl border border-gray-200 bg-white p-5 shadow-sm transition hover:border-gray-400 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
                  >
                    <span className="text-base font-semibold text-gray-900">
                      {subject.name}
                    </span>
                    <span className="mt-1 text-sm text-gray-600">
                      {usage
                        ? `${usage.newQuestionsUsed} / ${usage.limit} yeni soru`
                        : "Bu hafta hiç yeni soru kullanılmadı"}
                    </span>
                    <span className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-gray-900">
                      Çalışmaya başla
                      <span aria-hidden="true">→</span>
                    </span>
                  </Link>
                </li>
              )
            })}
          </ul>
        )}
      </section>

      <p className="mt-8 text-sm text-gray-500">
        Sorun mu var?{" "}
        <Link
          href="/dashboard"
          className="min-h-11 font-semibold text-gray-900 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
        >
          Panele dön
        </Link>
      </p>
    </main>
  )
}
