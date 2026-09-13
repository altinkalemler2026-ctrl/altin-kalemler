import { redirect } from "next/navigation"

import AvatarPicker from "@/components/student/AvatarPicker"
import NicknameForm from "@/components/student/NicknameForm"
import StudentGamification from "@/components/student/StudentGamification"
import ThemePicker from "@/components/student/ThemePicker"
import { Alert } from "@/components/ui/Alert"
import { Card } from "@/components/ui/Card"
import { EmptyState } from "@/components/ui/EmptyState"
import { fetchGamificationProfile } from "@/lib/gamification/service"
import type { GamificationProfile } from "@/lib/gamification/types"
import {
  fetchAvatarCatalog,
  fetchOwnProfileSummary,
} from "@/lib/profile/service"
import type { OwnProfileSummary } from "@/lib/profile/types"
import { createClient } from "@/lib/supabase/server"
import { ThemeSurface } from "@/lib/ui/theme-context"

import { selectAvatarAction, updateNicknameAction } from "./actions"

export const metadata = {
  title: "Profil | Altın Kalemler",
}

/** Seçili avatarın ilk harfini güvenli biçimde döndürür. */
function avatarInitial(name: string): string {
  return name.slice(0, 1).toLocaleUpperCase("tr-TR")
}

function ProfileSummaryCard({ summary }: { summary: OwnProfileSummary }) {
  return (
    <Card
      padding="sm"
      aria-labelledby="profile-summary-heading"
    >
      <h2 id="profile-summary-heading" className="text-lg font-semibold text-ink">
        Bilgilerin
      </h2>

      <div className="mt-3 flex items-center gap-4">
        <span
          aria-hidden="true"
          className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-navy-100 text-xl font-bold text-navy-900"
        >
          {summary.avatar
            ? avatarInitial(summary.avatar.name)
            : summary.nickname.slice(0, 1).toLocaleUpperCase("tr-TR")}
        </span>

        <div className="min-w-0">
          <p className="truncate text-base font-semibold text-ink">
            <span className="sr-only">Takma ad: </span>
            {summary.nickname}
          </p>
          <p className="text-sm text-ink-muted">
            Sınıf:{" "}
            <span className="font-semibold">{summary.gradeLevel}. Sınıf</span>
            <span className="ml-1 text-xs">(sınıf değiştirilemez)</span>
          </p>
          <p className="truncate text-sm text-ink-muted">
            <span className="sr-only">Seçili karakter: </span>
            {summary.avatar
              ? summary.avatar.name
              : "Henüz bir karakter seçmedin."}
          </p>
        </div>
      </div>
    </Card>
  )
}

/** Tema secimi (Faz 12); tercih yalniz bu cihazda saklanir. */
function ThemeCard() {
  return (
    <Card padding="sm" aria-labelledby="theme-heading">
      <h3 id="theme-heading" className="text-lg font-semibold text-ink">
        Tema
      </h3>
      <p className="mt-1 text-sm text-ink-muted">
        Tema tercihin yalnız bu cihazda saklanır.
      </p>
      <ThemePicker />
    </Card>
  )
}

/** Takma ad ve avatar düzenleme alanı; kimlik bilgileriyle karışmaz. */
function EditingSection({
  summary,
  catalog,
}: {
  summary: OwnProfileSummary
  catalog: Awaited<ReturnType<typeof fetchAvatarCatalog>> | null
}) {
  return (
    <Card
      padding="sm"
      aria-labelledby="profile-editing-heading"
    >
      <h2
        id="profile-editing-heading"
        className="text-lg font-semibold text-ink"
      >
        Takma adın ve avatarın
      </h2>

      <div className="mt-4 max-w-sm">
        <NicknameForm
          currentNickname={summary.nickname}
          action={updateNicknameAction}
        />
      </div>

      <div className="mt-6 border-t border-border pt-4">
        <h3 className="text-sm font-medium text-ink">Avatarın</h3>

        {catalog && catalog.status === "empty" ? (
          <div className="mt-3">
            <EmptyState
              title="Avatarlar hazırlanıyor"
              description="Karakter kataloğu hazırlanıyor. Hazır olduğunda buradan avatarını seçebileceksin."
            />
          </div>
        ) : catalog ? (
          <div className="mt-3">
            <AvatarPicker
              options={catalog.options}
              currentCode={summary.avatar?.code ?? null}
              action={selectAvatarAction}
            />
          </div>
        ) : (
          <div className="mt-3">
            <Alert variant="warning" title="Avatar listesi yüklenemedi">
              Avatarlar şu anda gösterilemiyor. Lütfen tekrar dene.
            </Alert>
          </div>
        )}
      </div>
    </Card>
  )
}

export default async function ProfilePage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect("/login")
  }

  // Profil özeti: form ve kimlik bilgileri olmadan sayfa kurulamaz.
  let summary: OwnProfileSummary | null = null
  let summaryError = false

  try {
    summary = await fetchOwnProfileSummary(supabase, user.id)
  } catch {
    // Ham hata UI'a taşınmaz; güvenli durum gösterilir.
    summaryError = true
  }

  if (summaryError || !summary) {
    return (
      <ThemeSurface className="min-h-full bg-page">
        <main className="mx-auto w-full max-w-3xl p-6">
          <h1 className="text-2xl font-bold text-ink">Profilim</h1>
          <div className="mt-6">
            <Alert variant="danger" title="Profil bilgilerin yüklenemedi">
              Profil bilgilerin şu anda görüntülenemiyor. Lütfen sayfayı
              yenileyip tekrar dene.
            </Alert>
          </div>
        </main>
      </ThemeSurface>
    )
  }

  // Oyunlaştırma profili: yüklenemezse kart güvenli hata durumuyla
  // gösterilir; sahte değer üretilmez, ham hata sızmaz.
  let gamification: GamificationProfile | null = null
  let gamificationError = false

  try {
    gamification = await fetchGamificationProfile(supabase)
  } catch {
    gamificationError = true
  }

  // Katalog hatası yalnız avatar bölümünü etkiler; sayfa kurulur.
  let catalog: Awaited<ReturnType<typeof fetchAvatarCatalog>> | null = null

  try {
    catalog = await fetchAvatarCatalog(supabase)
  } catch {
    // Katalog null kalır; düzenleme bölümü güvenli uyarı gösterir.
  }

  return (
    <ThemeSurface className="min-h-full bg-page">
      <main className="mx-auto w-full max-w-3xl p-6">
        <h1 className="text-2xl font-bold text-ink">Profilim</h1>

        <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-12">
          <div className="flex min-w-0 flex-col gap-6 lg:col-span-5">
            <ProfileSummaryCard summary={summary} />
            <ThemeCard />
          </div>

          <div className="min-w-0 lg:col-span-7">
            {gamificationError ? (
              <Card
                padding="sm"
                aria-labelledby="progress-heading"
              >
                <h2 id="progress-heading" className="text-lg font-semibold text-ink">
                  Gelişimin
                </h2>
                <div className="mt-3">
                  <Alert variant="warning" title="Gelişim bilgilerin yüklenemedi">
                    XP, seri ve rozet bilgilerin şu anda gösterilemiyor. Lütfen
                    tekrar dene.
                  </Alert>
                </div>
              </Card>
            ) : (
              gamification && (
                <StudentGamification
                  profile={gamification}
                  hideProfileLink
                />
              )
            )}
          </div>

          <div className="min-w-0 lg:col-span-12">
            <EditingSection summary={summary} catalog={catalog} />
          </div>
        </div>
      </main>
    </ThemeSurface>
  )
}