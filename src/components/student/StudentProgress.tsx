/**
 * Faz 11: Öğrencinin KENDİ kazanım ilerlemesi görünümü.
 *
 * Veri kaynağı: get_student_dimension_summary (085) üzerinden allowlist
 * DTO (DimensionSummaryRow). Sınıflandırma mevcut ürün eşiklerini
 * (performanceBandFrom: STRONG >= 70, WEAK < 40, kanıt < 5 deneme)
 * yeniden icat etmeden kullanır. Yüzde/seviye uydurma YOK.
 *
 * Bu bileşen yalnız sunucu tarafında render edilir; kendi verisi dışında
 * hiçbir öğrenci/sınıf verisi buraya ulaşamaz (kimlik auth.uid()'den).
 */

import Link from "next/link"

import { Badge } from "@/components/ui/Badge"
import { Card } from "@/components/ui/Card"
import { EmptyState } from "@/components/ui/EmptyState"
import { Progress } from "@/components/ui/Progress"
import type { DimensionSummaryRow, PerformanceBand } from "@/lib/analytics/types"
import { performanceBandFrom } from "@/lib/analytics/service"
import { computeOutcomeProgress } from "@/components/student/StudentHome"

export const BAND_LABELS: Record<PerformanceBand, string> = {
  STRONG: "Güçlü",
  DEVELOPING: "Gelişmekte",
  WEAK: "Zayıf",
  INSUFFICIENT_DATA: "Veri yok",
}

export interface SubjectProgressRow {
  subjectId: string | null
  subjectName: string
  total: number
  correct: number
  wrong: number
  blank: number
  passTimeout: number
  successRate: number
  lastAttemptedAt: string | null
}

export interface CategorizedProgressRow {
  name: string
  subjectName: string | null
  total: number
  correct: number
  wrong: number
  successRate: number
  band: PerformanceBand
}

export interface ProgressView {
  overview: ReturnType<typeof computeOutcomeProgress>
  subjects: SubjectProgressRow[]
  topics: CategorizedProgressRow[]
  outcomes: CategorizedProgressRow[]
  strongOutcomes: CategorizedProgressRow[]
  improvingOutcomes: CategorizedProgressRow[]
  insufficientOutcomeCount: number
  lastAttemptedAt: string | null
}

/**
 * Allowlist DTO satırlarından ilerleme görünümü modeli.
 * Sıralamalar deterministiktir (ad ASC, sonra subjectName/scopeKey).
 */
export function buildProgressView(
  rows: DimensionSummaryRow[]
): ProgressView {
  const subjectRows = rows
    .filter((row) => row.scopeType === "subject")
    .sort(compareByDisplayName)

  const subjects: SubjectProgressRow[] = subjectRows.map((row) => ({
    subjectId: row.subjectId,
    subjectName: row.displayName,
    total: row.total,
    correct: row.correct,
    wrong: row.wrong,
    blank: row.blank,
    passTimeout: row.passTimeout,
    successRate: row.successRate,
    lastAttemptedAt: row.lastAttemptedAt,
  }))

  const toCategorized = (
    row: DimensionSummaryRow
  ): CategorizedProgressRow => ({
    name: row.displayName,
    subjectName: row.subjectName,
    total: row.total,
    correct: row.correct,
    wrong: row.wrong,
    successRate: row.successRate,
    band: performanceBandFrom(row.total, row.successRate),
  })

  const topics = rows
    .filter((row) => row.scopeType === "topic")
    .map(toCategorized)
    .sort(
      (a, b) =>
        (a.subjectName ?? "").localeCompare(b.subjectName ?? "", "tr") ||
        a.name.localeCompare(b.name, "tr")
    )

  const outcomes = rows
    .filter((row) => row.scopeType === "outcome")
    .map(toCategorized)
    .sort(
      (a, b) =>
        (a.subjectName ?? "").localeCompare(b.subjectName ?? "", "tr") ||
        a.name.localeCompare(b.name, "tr")
    )

  const strongOutcomes = outcomes.filter((row) => row.band === "STRONG")
  const improvingOutcomes = outcomes.filter(
    (row) => row.band === "WEAK" || row.band === "DEVELOPING"
  )
  const insufficientOutcomeCount = outcomes.filter(
    (row) => row.band === "INSUFFICIENT_DATA"
  ).length

  let lastAttemptedAt: string | null = null
  for (const row of rows) {
    if (row.lastAttemptedAt === null) continue
    if (
      lastAttemptedAt === null ||
      row.lastAttemptedAt > lastAttemptedAt
    ) {
      lastAttemptedAt = row.lastAttemptedAt
    }
  }

  return {
    overview: computeOutcomeProgress(rows),
    subjects,
    topics,
    outcomes,
    strongOutcomes,
    improvingOutcomes,
    insufficientOutcomeCount,
    lastAttemptedAt,
  }
}

function compareByDisplayName(
  a: DimensionSummaryRow,
  b: DimensionSummaryRow
): number {
  return (
    a.displayName.localeCompare(b.displayName, "tr") ||
    a.scopeKey.localeCompare(b.scopeKey)
  )
}

/** Mevcut güvenilir alanlardan türetilen tr-TR zaman etiketi. */
export function formatLastUpdate(iso: string | null): string | null {
  if (iso === null) return null
  const parsed = new Date(iso)
  if (Number.isNaN(parsed.getTime())) return null
  return new Intl.DateTimeFormat("tr-TR", {
    dateStyle: "long",
    timeStyle: "short",
  }).format(parsed)
}

function BandBadge({ band }: { band: PerformanceBand }) {
  return (
    <Badge variant={band === "WEAK" ? "gold" : "navy"}>
      {BAND_LABELS[band]}
    </Badge>
  )
}

function StatLine({ row }: { row: CategorizedProgressRow }) {
  return (
    <li className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-border px-4 py-3">
      <div className="min-w-0 flex-1">
        <p className="break-words text-sm font-medium text-ink">{row.name}</p>
        <p className="mt-0.5 text-xs text-ink-muted">
          {row.total} deneme · {row.correct} doğru · {row.wrong} yanlış
        </p>
      </div>
      <div className="flex items-center gap-2">
        <span className="text-sm font-semibold tabular-nums text-ink">
          {row.band === "INSUFFICIENT_DATA"
            ? "—"
            : `${Math.round(row.successRate)}%`}
        </span>
        <BandBadge band={row.band} />
      </div>
    </li>
  )
}

export default function StudentProgress({
  rows,
  error,
}: {
  rows: DimensionSummaryRow[]
  error: string | null
}) {
  const view = buildProgressView(rows)
  const lastUpdate = formatLastUpdate(view.lastAttemptedAt)

  return (
    <section aria-labelledby="ilerleme-title" className="space-y-6">
      <header>
        <h1 id="ilerleme-title" className="text-3xl font-bold text-ink">
          İlerlemen
        </h1>
        <p className="mt-2 text-ink-muted">
          Kendi çalışma verine göre ders, konu ve kazanım ilerlemen.
          Bu sayfayı yalnız sen görebilirsin.
        </p>
      </header>

      {error && (
        <div
          role="alert"
          aria-live="assertive"
          className="rounded-xl border border-warning-900 bg-warning-100 px-4 py-3 text-sm text-warning-900"
        >
          İlerlemen şu anda yüklenemedi. {error}
        </div>
      )}

      {rows.length === 0 && !error && (
        <Card>
          <EmptyState
            title="Henüz çalışma verisi yok"
            description="Antrenman çözdükçe ders, konu ve kazanım ilerlemen burada görünür."
          />
          <div className="mt-4">
            <Link
              href="/training"
              className="inline-flex min-h-11 items-center rounded-xl bg-navy-800 px-4 py-2 text-sm font-semibold text-white transition hover:bg-navy-900 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
            >
              Antrenmana başla
            </Link>
          </div>
        </Card>
      )}

      {view.overview !== null && (
        <Card>
          <h2 className="font-semibold text-ink">Genel Kazanım Özeti</h2>
          <div className="mt-4">
            <Progress
              label="Ortalama kazanım başarısı"
              value={view.overview.averageSuccessRate}
              max={100}
            />
            <p className="mt-2 text-sm text-ink-muted">
              {view.overview.total} kazanım: {view.overview.mastered} güçlü,{" "}
              {view.overview.developing} gelişmekte, {view.overview.weak} zayıf
              {view.overview.insufficient > 0
                ? `, ${view.overview.insufficient} için veri yok`
                : ""}
              .
            </p>
          </div>
        </Card>
      )}

      {view.subjects.length > 0 && (
        <Card>
          <h2 className="font-semibold text-ink">Ders Bazında İlerleme</h2>
          <ul className="mt-4 space-y-3">
            {view.subjects.map((subject) => (
              <li
                key={subject.subjectName}
                className="rounded-2xl border border-border p-4"
              >
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div className="min-w-0">
                    <h3 className="break-words font-semibold text-ink">
                      {subject.subjectName}
                    </h3>
                    <p className="mt-0.5 text-sm text-ink-muted">
                      {subject.total} cevaplanan · {subject.correct} doğru ·{" "}
                      {subject.wrong} yanlış
                      {subject.blank > 0 ? ` · ${subject.blank} boş` : ""}
                      {subject.passTimeout > 0
                        ? ` · ${subject.passTimeout} pas/süre`
                        : ""}
                    </p>
                  </div>
                  <span className="text-sm font-semibold tabular-nums text-ink">
                    {subject.total > 0
                      ? `${Math.round(subject.successRate)}%`
                      : "—"}
                  </span>
                </div>

                {subject.total > 0 && (
                  <div className="mt-3">
                    <Progress
                      label={`${subject.subjectName} başarı oranı`}
                      value={Math.round(subject.successRate)}
                      max={100}
                    />
                  </div>
                )}

                {subject.subjectId && (
                  <Link
                    href={`/tekrar/${subject.subjectId}`}
                    className="mt-3 inline-flex min-h-11 items-center rounded-xl border border-border px-4 py-2 text-sm font-semibold text-ink transition hover:bg-surface-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
                  >
                    Kazanım analitiğini gör
                    <span aria-hidden="true">→</span>
                  </Link>
                )}
              </li>
            ))}
          </ul>
        </Card>
      )}

      {view.topics.length > 0 && (
        <Card>
          <h2 className="font-semibold text-ink">Konu Bazında İlerleme</h2>
          <ul className="mt-4 space-y-2">
            {view.topics.map((topic) => (
              <StatLine key={`${topic.subjectName ?? ""}-${topic.name}`} row={topic} />
            ))}
          </ul>
        </Card>
      )}

      {(view.strongOutcomes.length > 0 || view.improvingOutcomes.length > 0) && (
        <>
          <Card>
            <h2 className="font-semibold text-ink">Güçlü Kazanımların</h2>
            {view.strongOutcomes.length === 0 ? (
              <p className="mt-2 text-sm text-ink-muted">
                Henüz %70 ve üzeri başarıya ulaşmış kazanımın yok.
              </p>
            ) : (
              <ul className="mt-4 space-y-2">
                {view.strongOutcomes.map((row) => (
                  <StatLine
                    key={`strong-${row.subjectName ?? ""}-${row.name}`}
                    row={row}
                  />
                ))}
              </ul>
            )}
          </Card>

          <Card>
            <h2 className="font-semibold text-ink">Geliştirilecek Kazanımların</h2>
            {view.improvingOutcomes.length === 0 ? (
              <p className="mt-2 text-sm text-ink-muted">
                Şimdilik geliştirilecek kazanımın yok.
              </p>
            ) : (
              <ul className="mt-4 space-y-2">
                {view.improvingOutcomes.map((row) => (
                  <StatLine
                    key={`improve-${row.subjectName ?? ""}-${row.name}`}
                    row={row}
                  />
                ))}
              </ul>
            )}
            {view.improvingOutcomes.length > 0 && (
              <div className="mt-4">
                <Link
                  href="/tekrar"
                  className="inline-flex min-h-11 items-center rounded-xl bg-navy-800 px-4 py-2 text-sm font-semibold text-white transition hover:bg-navy-900 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
                >
                  Hedefli tekrara geç
                </Link>
              </div>
            )}
          </Card>

          {view.insufficientOutcomeCount > 0 && (
            <p className="text-sm text-ink-muted">
              {view.insufficientOutcomeCount} kazanım için henüz yeterli veri
              yok; antrenmana devam ettikçe burada görünür.
            </p>
          )}
        </>
      )}

      {view.topics.length === 0 &&
        view.subjects.length > 0 &&
        !error && (
          <p className="rounded-xl border border-border bg-surface-muted px-4 py-3 text-sm text-ink-muted">
            İçerikler hazırlanıyor. Bu dersler için konu ve kazanım bilgisi
            henüz yayımlanmadı.
          </p>
        )}

      {lastUpdate && (
        <p className="text-xs text-ink-muted">
          Son çalışma: {lastUpdate}
        </p>
      )}
    </section>
  )
}
