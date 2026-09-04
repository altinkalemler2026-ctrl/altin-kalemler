import Link from "next/link"

import { Badge } from "@/components/ui/Badge"
import { Card } from "@/components/ui/Card"
import { EmptyState } from "@/components/ui/EmptyState"
import { Progress } from "@/components/ui/Progress"
import type {
  AttemptTrendDay,
  DimensionSummaryRow,
  PriorityTopicDto,
  ReasonCode,
} from "@/lib/analytics/types"
import {
  LOW_SUCCESS_THRESHOLD,
  STRONG_SUCCESS_THRESHOLD,
} from "@/lib/analytics/types"

/** Ürün kararı: günlük hedef, tek antrenman seansı (10 soru) ile eşdeğerdir. */
export const DAILY_GOAL_ATTEMPTS = 10

/** reason_codes -> doğal Türkçe etiket (UI'da yalnız bu etiketler görünür). */
export const REASON_LABELS: Record<ReasonCode, string> = {
  LOW_SUCCESS: "Başarı oranı düşük",
  LOW_REPEAT_SUCCESS: "Tekrar başarısı düşük",
  STALE_TOPIC: "Uzun süredir çalışılmadı",
  INSUFFICIENT_DATA: "Yeterli veri yok",
}

export interface DailyGoalState {
  attempted: number
  goal: number
  percent: number
}

/**
 * Trend verisinden bugünün satırını bulur (UTC takvim günü).
 * Trend satırları bugün dahil azalara sıralıdır; yine de gün eşleşmesi
 * deterministik olarak doğrulanır.
 */
export function todayTrendRow(
  trend: AttemptTrendDay[],
  referenceNow: number
): AttemptTrendDay | null {
  const today = new Date(referenceNow).toISOString().slice(0, 10)

  for (const row of trend) {
    if (row.day === today) return row
  }
  return null
}

/** Gerçek trend verisinden günlük hedef durumu; sahte değer üretmez. */
export function computeDailyGoal(
  trend: AttemptTrendDay[],
  referenceNow: number,
  goal: number = DAILY_GOAL_ATTEMPTS
): DailyGoalState {
  const row = todayTrendRow(trend, referenceNow)
  const attempted = row ? Math.max(0, row.total) : 0
  const safeGoal = goal > 0 ? goal : 1
  const percent = Math.min(100, Math.round((attempted / safeGoal) * 100))

  return { attempted, goal: safeGoal, percent }
}

export interface OutcomeProgress {
  total: number
  withEvidence: number
  mastered: number
  developing: number
  weak: number
  insufficient: number
  averageSuccessRate: number
}

/**
 * Kazanım (outcome) kapsamındaki gerçek satırlardan ilerleme özeti.
 * Sınıflandırma, topic priority ile AYNI ürün eşiklerini kullanır:
 * STRONG >= 70, LOW < 40 (analytics/types sabitleri).
 */
export function computeOutcomeProgress(
  rows: DimensionSummaryRow[]
): OutcomeProgress | null {
  const outcomes = rows.filter((row) => row.scopeType === "outcome")
  if (outcomes.length === 0) return null

  let mastered = 0
  let developing = 0
  let weak = 0
  let insufficient = 0
  let rateSum = 0

  for (const row of outcomes) {
    if (row.total < 1) {
      insufficient += 1
      continue
    }
    rateSum += row.successRate
    if (row.successRate >= STRONG_SUCCESS_THRESHOLD) mastered += 1
    else if (row.successRate < LOW_SUCCESS_THRESHOLD) weak += 1
    else developing += 1
  }

  const withEvidence = outcomes.length - insufficient

  return {
    total: outcomes.length,
    withEvidence,
    mastered,
    developing,
    weak,
    insufficient,
    averageSuccessRate:
      withEvidence > 0 ? Math.round(rateSum / withEvidence) : 0,
  }
}

/**
 * Hedefli tekrar önerisi: rank-1 topic ve yalnız gerçek pozitif öncelik
 * skoruna sahipse. Veri yoksa null (UI boş durum gösterir).
 */
export function topRepeatSuggestion(
  priorities: PriorityTopicDto[]
): PriorityTopicDto | null {
  const first = priorities.find((p) => p.priorityRank === 1) ?? priorities[0]

  if (!first || first.priorityScore <= 0) return null

  return first
}

export interface StudentHomeProps {
  nickname: string
  gradeLevel: number
  priorities: PriorityTopicDto[]
  trend7: AttemptTrendDay[]
  outcomeRows: DimensionSummaryRow[]
  referenceNow: number
  analyticsError: string | null
}

export default function StudentHome({
  nickname,
  gradeLevel,
  priorities,
  trend7,
  outcomeRows,
  referenceNow,
  analyticsError,
}: StudentHomeProps) {
  const dailyGoal = computeDailyGoal(trend7, referenceNow)
  const outcomeProgress = computeOutcomeProgress(outcomeRows)
  const suggestion = topRepeatSuggestion(priorities)

  return (
    <section aria-labelledby="home-title" className="space-y-6">
      <h1 id="home-title" className="sr-only">
        Öğrenci ana sayfası
      </h1>

      <Card padding="lg">
        <p className="text-sm font-medium text-ink-muted">Altın Kalemler</p>

        <p className="mt-2 text-3xl font-bold text-ink">
          Hoş geldin, {nickname}
        </p>

        <div className="mt-3">
          <Badge variant="navy">{gradeLevel}. Sınıf</Badge>
        </div>

        <div className="mt-6 grid gap-4 sm:grid-cols-2">
          <Link
            href="/training"
            className="flex min-h-11 flex-col rounded-2xl border border-border p-5 transition hover:border-border-strong focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
          >
            <h2 className="font-semibold text-ink">Antrenmana Başla</h2>

            <p className="mt-2 text-sm text-ink-muted">
              On soruluk matematik antrenmanı ile çalış.
            </p>

            <span className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-ink">
              Başla
              <span aria-hidden="true">→</span>
            </span>
          </Link>

          <Link
            href="/competition"
            className="flex min-h-11 flex-col rounded-2xl border border-border p-5 transition hover:border-border-strong focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
          >
            <h2 className="font-semibold text-ink">Yarışmaya Katıl</h2>

            <p className="mt-2 text-sm text-ink-muted">
              Beş soruluk bilgi yarışmasına katıl.
            </p>

            <span className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-ink">
              Katıl
              <span aria-hidden="true">→</span>
            </span>
          </Link>
        </div>
      </Card>

      {analyticsError && (
        <div
          role="alert"
          aria-live="assertive"
          className="rounded-xl border border-warning-900 bg-warning-100 px-4 py-3 text-sm text-warning-900"
        >
          Çalışma önerileri şu anda yüklenemedi. {analyticsError}
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <h2 className="font-semibold text-ink">Günlük Hedef</h2>

          {dailyGoal.attempted === 0 ? (
            <p className="mt-2 text-sm text-ink-muted">
              Bugün henüz soru çözmedin. Günlük hedefin {dailyGoal.goal} soru.
            </p>
          ) : (
            <div className="mt-4">
              <Progress
                label="Bugünkü denemeler"
                value={dailyGoal.attempted}
                max={dailyGoal.goal}
              />

              <p className="mt-2 text-sm text-ink-muted">
                Bugün {dailyGoal.attempted} soru çözdün; hedefin{" "}
                {dailyGoal.goal} soru.
              </p>
            </div>
          )}
        </Card>

        <Card>
          <h2 className="font-semibold text-ink">Kazanım İlerlemesi</h2>

          {outcomeProgress === null ? (
            <div className="mt-4">
              <EmptyState
                title="Kazanım verisi yok"
                description="Antrenman çözdükçe kazanım ilerlemen burada görünür."
              />
            </div>
          ) : (
            <div className="mt-4">
              <Progress
                label="Ortalama kazanım başarısı"
                value={outcomeProgress.averageSuccessRate}
                max={100}
              />

              <p className="mt-2 text-sm text-ink-muted">
                {outcomeProgress.total} kazanım: {outcomeProgress.mastered}{" "}
                güçlü, {outcomeProgress.developing} gelişmekte,{" "}
                {outcomeProgress.weak} zayıf
                {outcomeProgress.insufficient > 0
                  ? `, ${outcomeProgress.insufficient} için veri yok`
                  : ""}
                .
              </p>
            </div>
          )}
        </Card>
      </div>

      <Card>
        <h2 className="font-semibold text-ink">Hedefli Tekrar Önerisi</h2>

        {suggestion === null ? (
          <div className="mt-4">
            <EmptyState
              title="Şimdilik tekrar önerisi yok"
              description="İlk antrenmanını tamamladığında zayıf konuların için öneri burada görünür."
            />
          </div>
        ) : (
          <div className="mt-4">
            <p className="text-base font-semibold text-ink">
              {suggestion.topicName}
            </p>

            {suggestion.subjectName && (
              <p className="mt-1 text-sm text-ink-muted">
                {suggestion.subjectName} · Başarı oranı{" "}
                {Math.round(suggestion.successRate)}% · {suggestion.totalAttempts}{" "}
                deneme
              </p>
            )}

            <div className="mt-3 flex flex-wrap gap-2">
              {suggestion.reasonCodes.map((code) => (
                <Badge key={code} variant="gold">
                  {REASON_LABELS[code] ?? code}
                </Badge>
              ))}
            </div>

            <div className="mt-4">
              <Link
                href={
                  suggestion.subjectId
                    ? `/training/${suggestion.subjectId}`
                    : "/training"
                }
                className="inline-flex min-h-11 items-center rounded-xl bg-navy-800 px-4 py-2 text-sm font-semibold text-white transition hover:bg-navy-900 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
              >
                Bu konuda çalış
              </Link>
            </div>
          </div>
        )}
      </Card>
    </section>
  )
}
