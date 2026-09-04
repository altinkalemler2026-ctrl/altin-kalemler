"use client"

/**
 * Antrenman kapsam filtreleri (Faz 5).
 *
 * - Seçenekler YALNIZ gerçek RPC listelerinden gelir (list_training_topics
 *   / list_training_outcomes); öğrenci başka sınıf kapsamını göremez.
 * - Konu seçilirse kazanım filtresi temizlenir (DB kuralı: ikisi birden
 *   kullanılamaz) ve tersi.
 * - Değişim URL (searchParams) üzerinden sunucuya taşınır; sayfa
 *   filtreli soru kümesini sunucu tarafında yeniden seçer.
 * - Erişilebilirlik: doğru label, ≥44px hedef, görünür focus.
 */

import { useRouter } from "next/navigation"
import { useId } from "react"

import type {
  TrainingOutcomeOption,
  TrainingTopicOption,
} from "@/lib/training/types"

const SELECT_CLASS =
  "min-h-11 w-full rounded-xl border border-border bg-surface px-4 py-2.5 text-ink outline-none transition focus:ring-2 focus:ring-teal-600 focus:ring-offset-1"

export default function TrainingFilters({
  subjectId,
  topics,
  outcomes,
  activeTopicId,
  activeOutcomeId,
}: {
  subjectId: string
  topics: TrainingTopicOption[]
  outcomes: TrainingOutcomeOption[]
  activeTopicId: string | null
  activeOutcomeId: string | null
}) {
  const router = useRouter()
  const topicId = useId()
  const outcomeId = useId()

  const navigate = (next: { topic?: string | null; outcome?: string | null }) => {
    const params = new URLSearchParams()

    const topic = next.topic !== undefined ? next.topic : activeTopicId
    const outcome = next.outcome !== undefined ? next.outcome : activeOutcomeId

    if (topic) params.set("topic", topic)
    if (outcome) params.set("outcome", outcome)

    const query = params.toString()

    router.push(query ? `/training/${subjectId}?${query}` : `/training/${subjectId}`)
  }

  return (
    <div className="grid gap-3 sm:grid-cols-2">
      <div>
        <label
          htmlFor={topicId}
          className="mb-1.5 block text-sm font-medium text-ink"
        >
          Konu filtresi
        </label>

        <select
          id={topicId}
          value={activeTopicId ?? ""}
          onChange={(event) =>
            navigate({ topic: event.target.value || null, outcome: null })
          }
          className={SELECT_CLASS}
        >
          <option value="">Tüm konular</option>

          {topics.map((topic) => (
            <option key={topic.topicId} value={topic.topicId}>
              {topic.topicName}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label
          htmlFor={outcomeId}
          className="mb-1.5 block text-sm font-medium text-ink"
        >
          Kazanım filtresi
        </label>

        <select
          id={outcomeId}
          value={activeOutcomeId ?? ""}
          onChange={(event) =>
            navigate({ outcome: event.target.value || null, topic: null })
          }
          className={SELECT_CLASS}
        >
          <option value="">Tüm kazanımlar</option>

          {outcomes.map((outcome) => (
            <option key={outcome.outcomeId} value={outcome.outcomeId}>
              {outcome.outcomeText}
            </option>
          ))}
        </select>
      </div>
    </div>
  )
}
