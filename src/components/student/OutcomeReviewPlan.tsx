/**
 * Kazanım analitiği plan kartları (Faz 6).
 *
 * - Kazanımlar band'a göre gruplanır: Öncelikli (weak), Geliştirilecek
 *   (developing), Güçlü (strong), Yeterli veri beklenen
 *   (insufficient_data).
 * - Yetersiz veride yüzde GÖSTERİLMEZ; açıklayıcı metin vardır
 *   (docs/project/faz6-tasarim.md §2.1).
 * - Tekrar etkisi (redeem_rate) yalnız payda >= MIN_REDEEM_EVIDENCE
 *   iken gösterilir; aksi halde açıklayıcı metin.
 * - Tekrar başlat bağlantısı YALNIZ bekleyen hatası olan
 *   weak/developing kazanımlar için görünür (deterministik tekrar
 *   oturumu kapısı: hata havuzu boşsa sunucu oturum başlatmaz).
 * - Erişilebilirlik: semantik başlıklar, min 44px hedef, görünür focus.
 */

import Link from "next/link"

import type { OutcomeBand, OutcomeReviewRow } from "@/lib/review/types"

const BAND_TITLES: Record<OutcomeBand, string> = {
  weak: "Öncelikli kazanımlar",
  developing: "Geliştirilecek kazanımlar",
  strong: "Güçlü kazanımlar",
  insufficient_data: "Yeterli veri beklenen kazanımlar",
}

const BAND_DESCRIPTIONS: Record<OutcomeBand, string> = {
  weak: "Bu kazanımda başarı oranın düşük; hedefli tekrar öneriyoruz.",
  developing: "Bu kazanımda ilerliyorsun; tekrarla pekiştir.",
  strong: "Bu kazanımda güçlüsün; düzenli antrenman devam etsin.",
  insufficient_data:
    "Bu kazanımda henüz yeterli çözüm verisi yok; birkaç soru daha çözünce değerlendirme yapılabilir.",
}

function formatRate(rate: number | null): string | null {
  if (rate === null) return null
  const rounded = Math.round(rate)
  return `%${rounded}`
}

interface OutcomeCardProps {
  row: OutcomeReviewRow
  subjectId: string
  canStartReview: boolean
}

function OutcomeCard({ row, subjectId, canStartReview }: OutcomeCardProps) {
  const successText = formatRate(row.successRate)
  const redeemText = formatRate(row.redeemRate)
  const reviewHref = `/tekrar/${subjectId}?outcome=${row.outcomeId}`

  return (
    <li className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
      <p className="font-semibold text-gray-900">{row.outcomeText}</p>

      <p className="mt-1 text-sm text-gray-600">
        {row.totalAttempts} deneme
        {successText !== null ? (
          <>
            {" • başarı "}
            <span className="font-semibold text-gray-900">
              {successText}
            </span>
          </>
        ) : (
          " • yeterli veri yok"
        )}
      </p>

      {row.pendingErrors > 0 ? (
        <p className="mt-1 text-sm text-gray-600">
          Bekleyen hata: {row.pendingErrors}
          {redeemText !== null ? (
            <>
              {" • telafi "}
              {redeemText}
            </>
          ) : (
            <> • tekrar etkisi için yeterli veri yok</>
          )}
        </p>
      ) : row.redeemed > 0 ? (
        <p className="mt-1 text-sm text-gray-600">
          Telafi edilen: {row.redeemed}
        </p>
      ) : null}

      <p className="mt-2 text-xs text-gray-500">
        {BAND_DESCRIPTIONS[row.band]}
      </p>

      {canStartReview ? (
        <Link
          href={reviewHref}
          className="mt-3 inline-flex min-h-11 items-center rounded-xl bg-gray-900 px-4 py-2 text-sm font-semibold text-white transition hover:bg-gray-800 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
        >
          Tekrar başlat
          <span aria-hidden="true" className="ml-1">
            →
          </span>
        </Link>
      ) : null}
    </li>
  )
}

interface OutcomeReviewPlanProps {
  subjectId: string
  subjectName: string
  rows: OutcomeReviewRow[]
}

export default function OutcomeReviewPlan({
  subjectId,
  subjectName,
  rows,
}: OutcomeReviewPlanProps) {
  const groups: Record<OutcomeBand, OutcomeReviewRow[]> = {
    weak: [],
    developing: [],
    strong: [],
    insufficient_data: [],
  }
  for (const row of rows) {
    groups[row.band].push(row)
  }

  const hasAnyOutcome =
    rows.length > 0 &&
    rows.some(
      (row) =>
        row.totalAttempts > 0 ||
        row.pendingErrors > 0 ||
        row.redeemed > 0
    )

  if (!hasAnyOutcome) {
    return (
      <section
        aria-labelledby="review-empty-title"
        className="rounded-3xl border border-dashed border-gray-300 bg-white p-6 text-center shadow-sm"
      >
        <h2
          id="review-empty-title"
          className="text-lg font-semibold text-gray-900"
        >
          Henüz tekrar verisi yok
        </h2>
        <p className="mt-2 text-sm text-gray-600">
          {subjectName} dersinde henüz çözüm verin yok. Antrenman
          yaptıkça yanlışların burada hedefli tekrar olarak listelenecek.
        </p>
        <Link
          href="/training"
          className="mt-4 inline-flex min-h-11 items-center justify-center rounded-xl bg-gray-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-gray-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
        >
          Antrenmana başla
        </Link>
      </section>
    )
  }

  const orderedBands: OutcomeBand[] = [
    "weak",
    "developing",
    "strong",
    "insufficient_data",
  ]

  return (
    <div className="mt-6 grid gap-6">
      {orderedBands.map((band) => {
        const groupRows = groups[band]
        if (groupRows.length === 0) return null
        return (
          <section
            key={band}
            aria-labelledby={`review-${band}-title`}
          >
            <h2
              id={`review-${band}-title`}
              className="text-lg font-semibold text-gray-900"
            >
              {BAND_TITLES[band]}
            </h2>
            <p className="mt-1 text-sm text-gray-600">
              {BAND_DESCRIPTIONS[band]}
            </p>
            <ul className="mt-3 grid gap-3 sm:grid-cols-2">
              {groupRows.map((row) => (
                <OutcomeCard
                  key={row.outcomeId}
                  row={row}
                  subjectId={subjectId}
                  canStartReview={
                    (band === "weak" || band === "developing") &&
                    row.pendingErrors > 0
                  }
                />
              ))}
            </ul>
          </section>
        )
      })}
    </div>
  )
}
