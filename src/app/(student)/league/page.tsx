import { redirect } from "next/navigation"

import { Alert } from "@/components/ui/Alert"
import { Badge } from "@/components/ui/Badge"
import { Card } from "@/components/ui/Card"
import { EmptyState } from "@/components/ui/EmptyState"
import { Progress } from "@/components/ui/Progress"
import { leagueTierLabel } from "@/lib/league/mappers"
import { getMyLeagueRanking } from "@/lib/league/service"
import type { LeagueRankingDto } from "@/lib/league/types"
import { createClient } from "@/lib/supabase/server"

export const metadata = {
  title: "Lig | Altın Kalemler",
}

const DAY_MONTH_FORMAT = new Intl.DateTimeFormat("tr-TR", {
  day: "numeric",
  month: "long",
})

function formatSeasonEnd(endsAt: string | null): string | null {
  if (!endsAt) return null
  const date = new Date(endsAt)
  if (Number.isNaN(date.getTime())) return null
  return DAY_MONTH_FORMAT.format(date)
}

function RatingInfoNote() {
  return (
    <p className="mt-3 text-xs leading-relaxed text-ink-muted">
      Lig rating puanı yalnızca lig sıralaması, yükselme ve düşme için
      kullanılır. Harcanabilir yıldız bakiyesi ayrıdır ve lig sırasını
      belirlemez.
    </p>
  )
}

function OwnRankCard({ dto }: { dto: LeagueRankingDto }) {
  const my = dto.my
  const tierLabel = leagueTierLabel(my?.leagueCode)
  const next = dto.nextLeague

  return (
    <Card className="mt-6" aria-labelledby="own-rank-heading">
      <h2 id="own-rank-heading" className="text-lg font-semibold text-ink">
        Senin sıran
      </h2>

      <div className="mt-3 flex flex-wrap items-center gap-x-6 gap-y-3">
        <p className="text-4xl font-bold text-navy-800">
          <span className="sr-only">Sıralaman: </span>
          {my?.rank ?? "—"}
        </p>

        <div className="flex flex-col gap-1">
          <Badge variant="gold">{tierLabel} Lig</Badge>
          <p className="text-sm text-ink">
            <span className="font-semibold">Lig rating:</span>{" "}
            {my?.rating ?? 0} puan
          </p>
        </div>
      </div>

      {next && my?.rating !== null && my?.rating !== undefined && (
        <div className="mt-4">
          <Progress
            value={Math.min(my.rating, next.threshold)}
            max={next.threshold}
            label={`Sonraki lig (${next.leagueName}) ilerlemesi`}
          />
          <p className="mt-1 text-xs text-ink-muted">
            Sonraki lig: {next.leagueName} — {next.threshold} rating puanı
          </p>
        </div>
      )}

      <RatingInfoNote />
    </Card>
  )
}

function RankingList({ dto }: { dto: LeagueRankingDto }) {
  return (
    <section className="mt-6" aria-labelledby="ranking-heading">
      <h2 id="ranking-heading" className="text-lg font-semibold text-ink">
        Sıralama
      </h2>

      <p className="mt-1 text-sm text-ink-muted">
        Aynı sınıf düzeyindeki {dto.gradeLevel}. sınıf öğrencileriyle{" "}
        {dto.my?.leagueName ?? "ligin"} sıralaması. Toplam {dto.total}{" "}
        öğrenci.
      </p>

      <ol className="mt-3 divide-y divide-border rounded-2xl border border-border bg-surface">
        {dto.entries.map((entry) => (
          <li
            key={`${entry.rank}-${entry.nickname}`}
            className="flex min-h-11 items-center gap-3 px-4 py-3"
          >
            <span className="w-10 shrink-0 text-center text-sm font-bold text-ink">
              <span className="sr-only">{entry.rank}. sıra — </span>
              <span aria-hidden="true">{entry.rank}</span>
            </span>

            <span
              aria-hidden="true"
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-navy-100 text-sm font-bold text-navy-900"
            >
              {entry.nickname.slice(0, 1).toLocaleUpperCase("tr-TR")}
            </span>

            <span className="min-w-0 flex-1 truncate text-sm font-medium text-ink">
              {entry.nickname}
              {entry.isCurrentStudent && (
                <span className="ml-2 align-middle">
                  <Badge variant="teal">Sen</Badge>
                </span>
              )}
            </span>

            <span className="shrink-0 text-right">
              <span className="block text-sm font-semibold text-ink">
                {entry.rating}
                <span className="sr-only"> lig rating puanı</span>
              </span>
              <span
                aria-hidden="true"
                className="block text-xs text-ink-muted"
              >
                {leagueTierLabel(entry.leagueCode)}
              </span>
            </span>
          </li>
        ))}
      </ol>
    </section>
  )
}

export default async function LeaguePage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect("/login")
  }

  let dto: LeagueRankingDto | null = null
  let hasError = false

  try {
    dto = await getMyLeagueRanking(supabase)
  } catch {
    // Herhangi bir hata (bilinen/ham DB) guvenli durumda gosterilir;
    // hata ayrintisi UI'a sizmaz.
    hasError = true
  }

  if (hasError || !dto) {
    return (
      <main className="mx-auto w-full max-w-3xl p-6">
        <h1 className="text-3xl font-bold text-ink">Lig</h1>
        <div className="mt-6">
          <Alert variant="danger" title="Lig verisi yüklenemedi">
            Lig bilgisi şu anda gösterilemiyor. Lütfen sayfayı yenileyip
            tekrar dene.
          </Alert>
        </div>
      </main>
    )
  }

  const seasonEnd = formatSeasonEnd(dto.season?.endsAt ?? null)

  if (dto.status === "no_active_season") {
    return (
      <main className="mx-auto w-full max-w-3xl p-6">
        <h1 className="text-3xl font-bold text-ink">Lig</h1>
        <div className="mt-6">
          <EmptyState
            title="Şu anda aktif bir lig sezonu yok"
            description="Yeni sezon açıldığında bu sayfada aynı sınıf düzeyindeki öğrencilerle lig sıralamanı göreceksin."
          />
        </div>
      </main>
    )
  }

  if (dto.status === "no_membership") {
    return (
      <main className="mx-auto w-full max-w-3xl p-6">
        <h1 className="text-3xl font-bold text-ink">
          {dto.gradeLevel}. Sınıf Ligi
        </h1>

        {dto.season && (
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <Badge variant="navy">{dto.season.name}</Badge>
            {seasonEnd && (
              <span className="text-sm text-ink-muted">
                Sezon bitişi: {seasonEnd}
              </span>
            )}
          </div>
        )}

        <div className="mt-6">
          <EmptyState
            title="Henüz lig üyeliğin yok"
            description="Sezon içinde ilk yarışmanı tamamladığında Bronz Lig'e yerleştirilirsin ve sıralamada yerini görürsün."
          />
        </div>
      </main>
    )
  }

  return (
    <main className="mx-auto w-full max-w-3xl p-6">
      <h1 className="text-3xl font-bold text-ink">
        {dto.gradeLevel}. Sınıf Ligi
      </h1>

      {dto.season && (
        <div className="mt-2 flex flex-wrap items-center gap-2">
          <Badge variant="navy">{dto.season.name}</Badge>
          <Badge variant="success">Aktif sezon</Badge>
          {seasonEnd && (
            <span className="text-sm text-ink-muted">
              Sezon bitişi: {seasonEnd}
            </span>
          )}
        </div>
      )}

      <OwnRankCard dto={dto} />
      <RankingList dto={dto} />
    </main>
  )
}
