import Link from "next/link"

import { createClient } from "@/lib/supabase/server"
import { mapTrainingError } from "@/lib/training/errors"
import { listTrainingSubjects } from "@/lib/training/service"

export const metadata = {
  title: "Hedefli Tekrar | Altın Kalemler",
}

export default async function ReviewPage() {
  const supabase = await createClient()

  let subjects: Awaited<ReturnType<typeof listTrainingSubjects>> = []
  let subjectsError: string | null = null
  try {
    subjects = await listTrainingSubjects(supabase)
  } catch (error) {
    subjectsError = mapTrainingError(error)
  }

  return (
    <main className="mx-auto w-full max-w-3xl flex-1 p-6">
      <header>
        <p className="text-sm font-medium text-gray-500">Hedefli Tekrar</p>
        <h1 className="mt-1 text-3xl font-bold text-gray-900">Ders Seç</h1>
        <p className="mt-2 text-gray-600">
          Yanlışların ve düşük başarı gösterdiğin kazanımlar sunucu
          tarafından belirlenir; sana özel deterministik bir tekrar
          oturumu oluşturulur.
        </p>
      </header>

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

      <section aria-labelledby="review-subjects-title" className="mt-8">
        <h2 id="review-subjects-title" className="text-lg font-semibold text-gray-900">
          Dersler
        </h2>

        {subjectsError ? null : subjects.length === 0 ? (
          <p className="mt-3 rounded-2xl border border-gray-200 bg-white p-5 text-gray-600">
            Şu anda aktif ders bulunmuyor. Lütfen daha sonra tekrar deneyin.
          </p>
        ) : (
          <ul className="mt-3 grid gap-3 sm:grid-cols-2">
            {subjects.map((subject) => (
              <li key={subject.id}>
                <Link
                  href={`/tekrar/${subject.id}`}
                  className="flex min-h-11 flex-col justify-center rounded-2xl border border-gray-200 bg-white p-5 shadow-sm transition hover:border-gray-400 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
                >
                  <span className="text-base font-semibold text-gray-900">
                    {subject.name}
                  </span>
                  <span className="mt-1 text-sm text-gray-600">
                    Kazanım analitiğini ve hedefli tekrarı gör
                  </span>
                  <span className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-gray-900">
                    Dersi aç
                    <span aria-hidden="true">→</span>
                  </span>
                </Link>
              </li>
            ))}
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
