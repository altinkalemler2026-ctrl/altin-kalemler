import { redirect } from "next/navigation"

import AvatarPicker from "@/components/student/AvatarPicker"
import NicknameForm from "@/components/student/NicknameForm"
import StudentGamification from "@/components/student/StudentGamification"
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
    <Card className="mt-6" aria-labelledby="profile-summary-heading">
      <h2 id="profile-summary-heading" className="text-lg font-semibold text-ink">
        Bilgilerin
      </h2>

      <div className="mt-4 flex items-center gap-4">
        <span
          aria-hidden="true"
          className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-navy-100 text-xl font-bold text-navy-900"
        >
          {summary.avatar
            ? avatarInitial(summary.avatar.name)
            : summary.nickname.slice(0, 1).toLocaleUpperCase("tr-TR")}
        </span>

        <div className="min-w-0">
          <p className="text-sm text-ink-muted">
            <span className="sr-only">Seçili karakter: </span>
            {summary.avatar
              ? summary.avatar.name
              : "Henüz bir karakter seçmedin."}
          </p>
          <p className="text-sm text-ink-muted">
            Sınıf: <span className="font-semibold">{summary.gradeLevel}. Sınıf</span>
            <span className="ml-1 text-xs">
              (sınıf değiştirilemez)
            </span>
          </p>
        </div>
      </div>

      <div className="mt-6 max-w-sm">
        <NicknameForm
          currentNickname={summary.nickname}
          action={updateNicknameAction}
        />
      </div>
    </Card>
  )
}

function AvatarSection({
  catalog,
  currentCode,
}: {
  catalog: Awaited<ReturnType<typeof fetchAvatarCatalog>>
  currentCode: string | null
}) {
  return (
    <Card className="mt-6" aria-labelledby="avatar-heading">
      <h2 id="avatar-heading" className="text-lg font-semibold text-ink">
        Avatarın
      </h2>

      {catalog.status === "empty" ? (
        <div className="mt-4">
          <EmptyState
            title="Avatarlar hazırlanıyor"
            description="Karakter kataloğu hazırlanıyor. Hazır olduğunda buradan avatarını seçebileceksin."
          />
        </div>
      ) : (
        <AvatarPicker
          options={catalog.options}
          currentCode={currentCode}
          action={selectAvatarAction}
        />
      )}
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
      <main className="mx-auto w-full max-w-3xl p-6">
        <h1 className="text-2xl font-bold text-ink">Profilim</h1>
        <div className="mt-6">
          <Alert variant="danger" title="Profil bilgilerin yüklenemedi">
            Profil bilgilerin şu anda görüntülenemiyor. Lütfen sayfayı
            yenileyip tekrar dene.
          </Alert>
        </div>
      </main>
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
  let catalogError = false

  try {
    catalog = await fetchAvatarCatalog(supabase)
  } catch {
    catalogError = true
  }

  return (
    <main className="mx-auto w-full max-w-3xl p-6">
      <h1 className="text-2xl font-bold text-ink">Profilim</h1>

      <ProfileSummaryCard summary={summary} />

      {catalogError ? (
        <Card className="mt-6" aria-labelledby="avatar-heading">
          <h2 id="avatar-heading" className="text-lg font-semibold text-ink">
            Avatarın
          </h2>
          <div className="mt-4">
            <Alert variant="warning" title="Avatar listesi yüklenemedi">
              Avatarlar şu anda gösterilemiyor. Lütfen tekrar dene.
            </Alert>
          </div>
        </Card>
      ) : (
        catalog && (
          <AvatarSection catalog={catalog} currentCode={summary.avatar?.code ?? null} />
        )
      )}

      {gamificationError ? (
        <Card className="mt-6" aria-labelledby="progress-heading">
          <h2 id="progress-heading" className="text-lg font-semibold text-ink">
            Gelişimin
          </h2>
          <div className="mt-4">
            <Alert variant="warning" title="Gelişim bilgilerin yüklenemedi">
              XP, seri ve rozet bilgilerin şu anda gösterilemiyor.
              Lütfen tekrar dene.
            </Alert>
          </div>
        </Card>
      ) : (
        gamification && <StudentGamification profile={gamification} />
      )}
    </main>
  )
}
