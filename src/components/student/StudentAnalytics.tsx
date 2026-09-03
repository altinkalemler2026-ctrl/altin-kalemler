"use client"

import Link from "next/link"

import type {
  AttemptTrendDay,
  PerformanceBand,
  PriorityTopicDto,
  ReasonCode,
} from "@/lib/analytics/types"

const REASON_LABELS: Record<ReasonCode, string> = {
  LOW_SUCCESS: "Başarı oranı düşük",
  LOW_REPEAT_SUCCESS: "Tekrarlarda zorlanıyor",
  STALE_TOPIC: "Uzun süredir çalışılmadı",
  INSUFFICIENT_DATA: "Yeterli veri yok",
}

const BAND_LABELS: Record<PerformanceBand, string> = {
  STRONG: "Güçlü",
  DEVELOPING: "Gelişmekte",
  WEAK: "Öncelikli",
  INSUFFICIENT_DATA: "Yetersiz veri",
}

const BAND_DESCRIPTIONS: Record<PerformanceBand, string> = {
  STRONG: "Bu konuda güçlü bir başarı oranın var.",
  DEVELOPING: "Bu konuda ilerliyorsun; çalışmaya devam et.",
  WEAK: "Bu konulara öncelik vermeni öneriyoruz.",
  INSUFFICIENT_DATA: "Bu konuda yeterli çözüm verisi henüz yok.",
}

function groupByBand(
  priorities: PriorityTopicDto[]
): Record<"weak" | "developing" | "strong" | "insufficient", PriorityTopicDto[]> {
  const groups = {
    weak: [] as PriorityTopicDto[],
    developing: [] as PriorityTopicDto[],
    strong: [] as PriorityTopicDto[],
    insufficient: [] as PriorityTopicDto[],
  }
  for (const topic of priorities) {
    switch (topic.performanceBand) {
      case "WEAK":
        groups.weak.push(topic)
        break
      case "DEVELOPING":
        groups.developing.push(topic)
        break
      case "STRONG":
        groups.strong.push(topic)
        break
      case "INSUFFICIENT_DATA":
        groups.insufficient.push(topic)
        break
    }
  }
  return groups
}

/** Deterministik tarih gösterimi (GG.AA.YYYY); bozuk giriste null. */
function formatDate(iso: string | null): string | null {
  if (!iso) return null
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return null
  const day = String(d.getUTCDate()).padStart(2, "0")
  const month = String(d.getUTCMonth() + 1).padStart(2, "0")
  return `${day}.${month}.${d.getUTCFullYear()}`
}

/** Toplam deneme + başarı oranı içeren kısa metin satırı. */
function attemptsLine(topic: PriorityTopicDto): string {
  return `${topic.totalAttempts} deneme • başarı %${Math.round(topic.successRate)}`
}

interface TopicCardProps {
  topic: PriorityTopicDto
  showScore: boolean
}

function TopicCard({ topic, showScore }: TopicCardProps) {
  const lastDate = formatDate(topic.lastAttemptedAt)
  return (
    <li className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="font-semibold text-gray-900">{topic.topicName}</span>
        <span className="inline-flex rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-medium text-gray-700">
          {BAND_LABELS[topic.performanceBand]}
        </span>
      </div>

      {showScore ? (
        <p className="mt-2 text-sm text-gray-700">
          Öncelik puanı:{" "}
          <span className="font-semibold text-gray-900">
            {Math.round(topic.priorityScore)}
          </span>
        </p>
      ) : null}

      <p className="mt-1 text-sm text-gray-600">{attemptsLine(topic)}</p>

      {topic.repeatTotal > 0 && (
        <p className="mt-1 text-sm text-gray-600">
          Tekrar: %{Math.round(topic.repeatSuccessRate)} başarı (
          {topic.repeatTotal} tekrar)
        </p>
      )}

      {lastDate && (
        <p className="mt-1 text-sm text-gray-600">
          Son çalışma: {lastDate}
        </p>
      )}

      <p className="mt-2 text-xs text-gray-500">
        {BAND_DESCRIPTIONS[topic.performanceBand]}
      </p>

      {topic.reasonCodes.length > 0 ? (
        <ul className="mt-2 flex flex-wrap gap-1.5">
          {topic.reasonCodes.map((reason) => (
            <li
              key={reason}
              className="rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-medium text-amber-800"
            >
              {REASON_LABELS[reason] ?? reason}
            </li>
          ))}
        </ul>
      ) : null}
    </li>
  )
}

interface TodayCardProps {
  topic: PriorityTopicDto
}

function TodayCard({ topic }: TodayCardProps) {
  return (
    <li className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
      <p className="font-semibold text-gray-900">{topic.topicName}</p>
      <p className="mt-1 text-sm text-gray-600">
        {BAND_LABELS[topic.performanceBand]} • {attemptsLine(topic)}
      </p>
      {topic.reasonCodes.length > 0 ? (
        <p className="mt-2 text-xs text-gray-600">
          {topic.reasonCodes
            .map((reason) => REASON_LABELS[reason] ?? reason)
            .join(" • ")}
        </p>
      ) : null}
      {topic.subjectId ? (
        <Link
          href={`/training/${topic.subjectId}`}
          className="mt-3 inline-flex min-h-11 items-center text-sm font-medium text-gray-900 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
        >
          Bu dersle çalış
          <span aria-hidden="true" className="ml-1">
            →
          </span>
        </Link>
      ) : null}
    </li>
  )
}

function TrendSummary({
  title,
  rows,
}: {
  title: string
  rows: AttemptTrendDay[]
}) {
  if (rows.length === 0) return null
  const totalQuestions = rows.reduce((sum, row) => sum + row.total, 0)
  const activeDays = rows.filter((row) => row.total > 0).length
  const avgSuccess = totalQuestions
    ? rows.reduce((sum, row) => sum + row.successRate * row.total, 0) /
      totalQuestions
    : 0

  return (
    <div className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
      <h3 className="font-semibold text-gray-900">Son {title}</h3>
      <dl className="mt-2 grid gap-x-4 gap-y-1 text-sm sm:grid-cols-3">
        <div>
          <dt className="text-gray-500">Çözülen soru</dt>
          <dd className="font-semibold text-gray-900">{totalQuestions}</dd>
        </div>
        <div>
          <dt className="text-gray-500">Ortalama başarı</dt>
          <dd className="font-semibold text-gray-900">
            %{Math.round(avgSuccess)}
          </dd>
        </div>
        <div>
          <dt className="text-gray-500">Aktif gün</dt>
          <dd className="font-semibold text-gray-900">
            {activeDays} / {rows.length}
          </dd>
        </div>
      </dl>
    </div>
  )
}

interface StudentAnalyticsProps {
  priorities: PriorityTopicDto[]
  trend7: AttemptTrendDay[]
  trend30: AttemptTrendDay[]
}

export default function StudentAnalytics({
  priorities,
  trend7,
  trend30,
}: StudentAnalyticsProps) {
  const { weak, developing, strong, insufficient } = groupByBand(priorities)

  const actionable = priorities.filter(
    (topic) => topic.performanceBand !== "INSUFFICIENT_DATA"
  )
  const todayTopics = actionable.slice(0, 3)

  const hasAnyTopics =
    weak.length > 0 ||
    developing.length > 0 ||
    strong.length > 0 ||
    insufficient.length > 0

  return (
    <div className="mt-8 grid gap-6">
      {!hasAnyTopics && trend7.length === 0 && trend30.length === 0 ? (
        <section
          aria-labelledby="analytics-empty-title"
          className="rounded-3xl border border-dashed border-gray-300 bg-white p-6 text-center shadow-sm"
        >
          <h2
            id="analytics-empty-title"
            className="text-lg font-semibold text-gray-900"
          >
            Henüz yeterli veri yok
          </h2>
          <p className="mt-2 text-sm text-gray-600">
            Henüz yeterli çözüm verin yok. Birkaç çalışma yaptıktan sonra
            önerilerin burada görünecek.
          </p>
          <Link
            href="/training"
            className="mt-4 inline-flex min-h-11 items-center justify-center rounded-xl bg-gray-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-gray-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
          >
            Çalışmaya başla
          </Link>
        </section>
      ) : (
        <>
          {todayTopics.length > 0 && (
            <section aria-labelledby="today-title">
              <h2
                id="today-title"
                className="text-lg font-semibold text-gray-900"
              >
                Bugün ne çalışmalıyım?
              </h2>
              <p className="mt-1 text-sm text-gray-600">
                Öncelik puanına göre en çok dikkat etmen gereken konular.
              </p>
              <ul className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {todayTopics.map((topic) => (
                  <TodayCard key={topic.topicId} topic={topic} />
                ))}
              </ul>
            </section>
          )}

          {weak.length > 0 && (
            <section aria-labelledby="priority-title">
              <h2
                id="priority-title"
                className="text-lg font-semibold text-gray-900"
              >
                Öncelikli konular
              </h2>
              <p className="mt-1 text-sm text-gray-600">
                Düşük başarı oranı olan ve öncelikli çalışman gereken konular.
              </p>
              <ul className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {weak.map((topic) => (
                  <TopicCard
                    key={topic.topicId}
                    topic={topic}
                    showScore={true}
                  />
                ))}
              </ul>
            </section>
          )}

          {developing.length > 0 && (
            <section aria-labelledby="developing-title">
              <h2
                id="developing-title"
                className="text-lg font-semibold text-gray-900"
              >
                Gelişen konular
              </h2>
              <p className="mt-1 text-sm text-gray-600">
                İlerlediğin ama üzerinde çalışmaya devam etmen gereken konular.
              </p>
              <ul className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {developing.map((topic) => (
                  <TopicCard
                    key={topic.topicId}
                    topic={topic}
                    showScore={false}
                  />
                ))}
              </ul>
            </section>
          )}

          {strong.length > 0 && (
            <section aria-labelledby="strong-title">
              <h2
                id="strong-title"
                className="text-lg font-semibold text-gray-900"
              >
                Güçlü konular
              </h2>
              <p className="mt-1 text-sm text-gray-600">
                Bu konularda yüksek başarı oranına sahipsin.
              </p>
              <ul className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {strong.map((topic) => (
                  <TopicCard
                    key={topic.topicId}
                    topic={topic}
                    showScore={false}
                  />
                ))}
              </ul>
            </section>
          )}

          {insufficient.length > 0 && (
            <section aria-labelledby="insufficient-title">
              <h2
                id="insufficient-title"
                className="text-lg font-semibold text-gray-900"
              >
                Daha fazla veri beklenen konular
              </h2>
              <p className="mt-1 text-sm text-gray-600">
                Bu konularda henüz yeterli çözüm verisi yok. Birkaç soru daha
                çözdükten sonra öneri üretilebilir.
              </p>
              <ul className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {insufficient.map((topic) => (
                  <TopicCard
                    key={topic.topicId}
                    topic={topic}
                    showScore={false}
                  />
                ))}
              </ul>
            </section>
          )}

          {(trend7.length > 0 || trend30.length > 0) && (
            <section aria-labelledby="trend-title">
              <h2
                id="trend-title"
                className="text-lg font-semibold text-gray-900"
              >
                Çözüm özeti
              </h2>
              <div className="mt-3 grid gap-3 sm:grid-cols-2">
                <TrendSummary title="7 gün" rows={trend7} />
                <TrendSummary title="30 gün" rows={trend30} />
              </div>
            </section>
          )}
        </>
      )}
    </div>
  )
}
